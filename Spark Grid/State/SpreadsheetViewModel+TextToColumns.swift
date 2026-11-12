import Foundation
import SparkGridCore

/// Data ▸ Text to Columns: splits the text in one column into the columns to its right.
extension SpreadsheetViewModel {
  /// The selected column's rows, or the filled block under the active cell when one cell is
  /// selected. Nil when the selection spans more than one column.
  func textToColumnsSource() -> CellRange? {
    var range = selectionRange
    if range.isSingleCell, let region = contiguousRegion(around: selectionAnchor) {
      let r = region.normalized
      let col = selectionAnchor.col
      range = CellRange(
        start: CellAddress(row: r.minRow, col: col), end: CellAddress(row: r.maxRow, col: col))
    }
    let n = range.normalized
    guard n.minCol == n.maxCol else { return nil }
    return range
  }

  /// Each source row split into fields. A formula row keeps its formula and the cells beside it.
  func textToColumnsGrid(_ source: CellRange, options: TextSplitter.Options, rowLimit: Int? = nil)
    -> [[String]]
  {
    let n = source.normalized
    let lastRow = rowLimit.map { min(n.maxRow, n.minRow + $0 - 1) } ?? n.maxRow
    var rows: [[String]] = []
    for row in n.minRow...lastRow {
      let raw = activeSheet.cell(at: CellAddress(row: row, col: n.minCol)).raw
      if FormulaSyntax.isFormula(raw) {
        rows.append([raw])
        continue
      }
      // A tab or line break inside a field would split the paste that writes it.
      rows.append(
        TextSplitter.split(raw, options: options).map {
          $0.replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        })
    }
    return rows
  }

  /// How many filled cells the split would write over, to the right of the source column.
  func textToColumnsOverwriteCount(_ source: CellRange, width: Int) -> Int {
    let n = source.normalized
    guard width > 1 else { return 0 }
    var count = 0
    for row in n.minRow...n.maxRow {
      for col in (n.minCol + 1)..<(n.minCol + width) where col < activeSheet.effectiveColumnCount {
        if !activeSheet.cell(at: CellAddress(row: row, col: col)).raw.isEmpty { count += 1 }
      }
    }
    return count
  }

  /// Splits the column, as one undo step.
  func applyTextToColumns(_ source: CellRange, options: TextSplitter.Options) {
    commitEditIfNeeded()
    let n = source.normalized
    var grid = textToColumnsGrid(source, options: options)
    let width = grid.map(\.count).max() ?? 1
    for (offset, fields) in grid.enumerated() {
      let row = n.minRow + offset
      if fields.count == 1, FormulaSyntax.isFormula(fields[0]) {
        // Leave the formula's row as it is.
        grid[offset] = (0..<width).map {
          activeSheet.cell(at: CellAddress(row: row, col: n.minCol + $0)).raw
        }
      } else {
        grid[offset] = fields + Array(repeating: "", count: width - fields.count)
      }
    }
    pasteGrid(
      grid, at: CellAddress(row: n.minRow, col: n.minCol), adjustFormulas: false,
      actionName: "Text to Columns")
    selectRange(
      from: CellAddress(row: n.minRow, col: n.minCol),
      to: CellAddress(row: n.maxRow, col: n.minCol + width - 1))
  }
}
