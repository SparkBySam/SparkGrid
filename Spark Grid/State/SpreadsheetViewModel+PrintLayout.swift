import Foundation
import SparkGridCore

/// File ▸ Print Area and Sheet ▸ page breaks. Both are saved with the sheet, so other apps print
/// the same pages.
extension SpreadsheetViewModel {
  var printArea: CellRange? { activeSheet.fileExtras.printArea }

  func setPrintArea() {
    let n = selectionRange.normalized
    let area = CellRange(
      start: CellAddress(row: n.minRow, col: n.minCol),
      end: CellAddress(row: n.maxRow, col: n.maxCol))
    updateFileExtras(actionName: "Set Print Area") { $0.printArea = area }
  }

  func clearPrintArea() {
    updateFileExtras(actionName: "Clear Print Area") { $0.printArea = nil }
  }

  /// The row and column a new page would start at: above and left of the active cell, or only
  /// above a selected row and only left of a selected column. Row 1 and column A start the first
  /// page already, so they take no break.
  private var pageBreakTargets: (row: Int?, column: Int?) {
    let n = selectionRange.normalized
    let row = n.minRow > 0 ? n.minRow : nil
    let column = n.minCol > 0 ? n.minCol : nil
    switch selectionAxis {
    case .row: return (row, nil)
    case .column: return (nil, column)
    case .sheet: return (nil, nil)
    case .cells: return (row, column)
    }
  }

  var canInsertPageBreak: Bool {
    let t = pageBreakTargets
    let extras = activeSheet.fileExtras
    return (t.row.map { !extras.rowBreaks.contains($0) } ?? false)
      || (t.column.map { !extras.columnBreaks.contains($0) } ?? false)
  }

  /// A break on the active cell's row or column, above or left of it.
  var canRemovePageBreak: Bool {
    let extras = activeSheet.fileExtras
    return extras.rowBreaks.contains(selectionAnchor.row)
      || extras.columnBreaks.contains(selectionAnchor.col)
  }

  var hasPageBreaks: Bool {
    !activeSheet.fileExtras.rowBreaks.isEmpty || !activeSheet.fileExtras.columnBreaks.isEmpty
  }

  func insertPageBreak() {
    let t = pageBreakTargets
    updateFileExtras(actionName: "Insert Page Break") { extras in
      if let row = t.row { extras.rowBreaks.insert(row) }
      if let column = t.column { extras.columnBreaks.insert(column) }
    }
  }

  func removePageBreak() {
    let anchor = selectionAnchor
    updateFileExtras(actionName: "Remove Page Break") { extras in
      extras.rowBreaks.remove(anchor.row)
      extras.columnBreaks.remove(anchor.col)
    }
  }

  func resetAllPageBreaks() {
    updateFileExtras(actionName: "Reset All Page Breaks") { extras in
      extras.rowBreaks = []
      extras.columnBreaks = []
    }
  }
}
