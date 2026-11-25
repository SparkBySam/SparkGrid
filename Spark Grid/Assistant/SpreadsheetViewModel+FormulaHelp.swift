import Foundation
import SparkGridCore

extension SpreadsheetViewModel {
  /// What formula help tells the model about the sheet: its name, the others, and each column's
  /// header with a couple of its values. Short, as the model on the Mac reads a few thousand
  /// words at most.
  func formulaHelpContext() -> String {
    let sheet = activeSheet
    var lines: [String] = []
    let others = workbook.sheets.map(\.name).filter { $0 != sheet.name }
    lines.append(
      "The sheet is named '\(sheet.name)'."
        + (others.isEmpty
          ? "" : " Other sheets: " + others.map { "'\($0)'" }.joined(separator: ", ") + "."))
    guard sheet.maxPopulatedRow >= 0, sheet.maxPopulatedColumn >= 0 else {
      lines.append("The sheet is empty.")
      return lines.joined(separator: "\n")
    }
    // The block of data the selected cell is in or just under, else the whole sheet: on a
    // sheet of several tables the model was told about the top one only (Sam, Nov 20).
    let block = formulaHelpBlock()
    let firstRow = block.minRow
    let lastRow = block.maxRow
    let firstCol = block.minCol
    let lastCol = min(block.maxCol, firstCol + 25)
    // The header row: the first row, within the top ten, whose filled cells are mostly text.
    var headerRow = firstRow
    for row in firstRow...min(lastRow, firstRow + 9) {
      let values = (firstCol...lastCol).map { displayValue(at: CellAddress(row: row, col: $0)) }
      let filled = values.filter { if case .blank = $0 { false } else { true } }
      let text = filled.filter { if case .string = $0 { true } else { false } }
      if filled.count >= 2, text.count >= filled.count - 1 {
        headerRow = row
        break
      }
    }
    // A last row that says Total is not data.
    var lastData = lastRow
    let lastRowText = (firstCol...lastCol).map {
      displayString(at: CellAddress(row: lastRow, col: $0)).lowercased()
    }
    if lastRow > headerRow + 1, lastRowText.contains(where: { $0.hasPrefix("total") }) {
      lastData = lastRow - 1
      lines.append(
        "Headers are in row \(headerRow + 1); data rows are \(headerRow + 2) to \(lastData + 1); "
          + "row \(lastRow + 1) is a total row.")
    } else {
      lines.append(
        "Headers are in row \(headerRow + 1); data rows are \(headerRow + 2) to \(lastData + 1).")
    }
    lines.append("Columns:")
    for col in firstCol...lastCol {
      let header = displayString(at: CellAddress(row: headerRow, col: col))
      let rows = (headerRow + 1)...max(headerRow + 1, min(lastData, headerRow + 3))
      let samples = rows.map { displayString(at: CellAddress(row: $0, col: col)) }
        .filter { !$0.isEmpty }
      guard !header.isEmpty || !samples.isEmpty else { continue }
      let numeric = rows.allSatisfy {
        switch displayValue(at: CellAddress(row: $0, col: col)) {
        case .number, .blank: return true
        default: return false
        }
      }
      let letter = A1Notation.columnLabel(for: col)
      var line = "- \(letter): " + (header.isEmpty ? "(no header)" : "\"\(header.prefix(40))\"")
      line += numeric ? " (numbers)" : " (text)"
      if !samples.isEmpty {
        line += ", for example " + samples.map { String($0.prefix(30)) }.joined(separator: ", ")
      }
      lines.append(line)
    }
    if block.maxCol > lastCol {
      lines.append("(and more columns to \(A1Notation.columnLabel(for: block.maxCol)))")
    }
    return lines.joined(separator: "\n")
  }

  /// The data the request is most likely about: the filled block holding the selected cell, or
  /// the one just above or to its left (where a total goes), else the whole sheet.
  private func formulaHelpBlock() -> (minRow: Int, maxRow: Int, minCol: Int, maxCol: Int) {
    let anchor = selectionAnchor
    let seeds = [
      anchor, CellAddress(row: max(0, anchor.row - 1), col: anchor.col),
      CellAddress(row: anchor.row, col: max(0, anchor.col - 1)),
    ]
    for seed in seeds where !displayString(at: seed).isEmpty {
      if let region = contiguousRegion(around: seed) {
        let n = region.normalized
        if n.maxRow > n.minRow { return (n.minRow, n.maxRow, n.minCol, n.maxCol) }
      }
    }
    return (0, activeSheet.maxPopulatedRow, 0, activeSheet.maxPopulatedColumn)
  }

  /// The selected cell's formula, for Explain.
  var selectedFormula: String? {
    let raw = activeSheet.cell(at: selectionAnchor).raw
    return FormulaSyntax.isFormula(raw) ? raw : nil
  }

  /// What `formula` would show in the selected cell, so formula help can show it before Insert.
  func previewResult(of formula: String) -> String {
    let value = formulaEngine.evaluateConditionalFormula(
      formula, at: selectionAnchor, relativeTo: selectionAnchor, sheet: activeSheet)
    return FormulaEvaluator.cellResult(value).displayString
  }

  /// Puts a formula from formula help in the selected cell, as typing it would.
  func insertSuggestedFormula(_ formula: String) {
    commitEditIfNeeded()
    setCellValue(formula, at: selectionAnchor)
    notifyGridRefresh()
  }
}
