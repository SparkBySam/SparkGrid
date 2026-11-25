import AppKit
import SparkGridCore

/// Dragging a selection by its border moves the cells: values, formulas and formats go to the
/// new place, the old place is left empty, and formulas that pointed at the moved cells follow
/// them, as in other spreadsheet apps. One undo step (asked for by Sam, Nov 19).
extension SpreadsheetViewModel {
  func moveCells(_ source: CellRange, to target: CellAddress) {
    commitEditIfNeeded()
    let n = source.normalized
    let rowDelta = target.row - n.minRow
    let colDelta = target.col - n.minCol
    guard rowDelta != 0 || colDelta != 0, target.row >= 0, target.col >= 0 else { return }
    let destination = CellRange(
      start: target,
      end: CellAddress(row: n.maxRow + rowDelta, col: n.maxCol + colDelta))
    guard protectionAllows([source, destination]) else { return }

    let sheet = activeSheet
    let sourceRows = n.minRow...n.maxRow
    let sourceColumns = n.minCol...n.maxCol
    // Cells already at the destination, outside the block itself, are written over.
    let d = destination.normalized
    let covered = sheet.cells.contains { address, cell in
      (d.minRow...d.maxRow).contains(address.row) && (d.minCol...d.maxCol).contains(address.col)
        && !(sourceRows.contains(address.row) && sourceColumns.contains(address.col))
        && !(cell.raw.isEmpty && cell.format == nil)
    }
    if covered {
      // A sheet on the workbook's window, as the app's other questions are; a free alert in
      // the middle of the screen was easy to miss (found in testing, Nov 19).
      confirmReplacingCells { [weak self] replace in
        if replace { self?.performMove(source, rowDelta: rowDelta, colDelta: colDelta) }
      }
      return
    }
    performMove(source, rowDelta: rowDelta, colDelta: colDelta)
  }

  private func performMove(_ source: CellRange, rowDelta: Int, colDelta: Int) {
    let n = source.normalized
    let destination = CellRange(
      start: CellAddress(row: n.minRow + rowDelta, col: n.minCol + colDelta),
      end: CellAddress(row: n.maxRow + rowDelta, col: n.maxCol + colDelta))
    var sheet = activeSheet
    let sourceRows = n.minRow...n.maxRow
    let sourceColumns = n.minCol...n.maxCol
    let moving = sheet.cells.filter {
      sourceRows.contains($0.key.row) && sourceColumns.contains($0.key.col)
    }
    let before = workbook
    for address in moving.keys {
      sheet.setCell(Cell(), at: address)
    }
    for (address, cell) in moving {
      sheet.setCell(cell, at: CellAddress(row: address.row + rowDelta, col: address.col + colDelta))
    }
    // Merged cells wholly inside the block move with it.
    sheet.mergedRanges = sheet.mergedRanges.map { merge in
      let m = merge.normalized
      guard sourceRows.contains(m.minRow), sourceRows.contains(m.maxRow),
        sourceColumns.contains(m.minCol), sourceColumns.contains(m.maxCol)
      else { return merge }
      return CellRange(
        start: CellAddress(row: m.minRow + rowDelta, col: m.minCol + colDelta),
        end: CellAddress(row: m.maxRow + rowDelta, col: m.maxCol + colDelta))
    }

    var book = workbook
    book.activeSheet = sheet
    let movedSheetName = sheet.name
    // Only formulas whose text names one of the block's columns (and, on another sheet, this
    // sheet) can point into it; the rest are not parsed. Parsing all 115k on the stress
    // workbook made a move hang (found in testing, Nov 19).
    let labels = sourceColumns.map {
      NSRegularExpression.escapedPattern(for: A1Notation.columnLabel(for: $0))
    }
    let mentionsBlock = try? NSRegularExpression(
      pattern: "(?<![A-Za-z0-9_.])\\$?(?:" + labels.joined(separator: "|") + ")\\$?[0-9]",
      options: [.caseInsensitive])
    func mightPointIntoBlock(_ raw: String, onMovedSheet: Bool) -> Bool {
      if !onMovedSheet, raw.range(of: movedSheetName, options: .caseInsensitive) == nil {
        return false
      }
      guard let mentionsBlock else { return true }
      return mentionsBlock.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)) != nil
    }
    // Formulas anywhere in the workbook that pointed into the block now point at its new place.
    for index in book.sheets.indices {
      var each = book.sheets[index]
      var changed = false
      let onMovedSheet = each.name == movedSheetName
      for (address, cell) in each.cells
      where FormulaSyntax.isFormula(cell.raw)
        && mightPointIntoBlock(cell.raw, onMovedSheet: onMovedSheet)
      {
        let next = FormulaRewriter.movingReferences(
          cell.raw, formulaSheetName: each.name, movedSheetName: movedSheetName,
          rows: sourceRows, columns: sourceColumns, rowDelta: rowDelta, colDelta: colDelta)
        guard next != cell.raw else { continue }
        var updated = cell
        updated.raw = next
        updated.importedFormulaResult = nil
        updated.importedFormulaValueType = nil
        each.setCell(updated, at: address)
        changed = true
      }
      if changed { book.sheets[index] = each }
    }
    workbook = book
    registerWorkbookStructureUndo(before: before, action: "Move Cells")
    selectRange(from: destination.start, to: destination.end)
    requestScrollSelectionIntoView()
    notifyGridRefresh()
  }

  private func confirmReplacingCells(then answer: @escaping (Bool) -> Void) {
    let alert = NSAlert()
    alert.messageText = "Replace the cells already there?"
    alert.informativeText = "The cells you are moving onto have contents. Moving replaces them."
    alert.addButton(withTitle: "Replace")
    alert.addButton(withTitle: "Cancel")
    // The workbook's window, also when another app is in front.
    if let window = NSApp.keyWindow ?? NSApp.mainWindow {
      alert.beginSheetModal(for: window) { answer($0 == .alertFirstButtonReturn) }
    } else {
      answer(alert.runModal() == .alertFirstButtonReturn)
    }
  }
}
