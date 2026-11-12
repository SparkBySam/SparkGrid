import Foundation
import SparkGridCore

/// Fill Down, Fill Right, and Edit > Clear.
extension SpreadsheetViewModel {
  /// Command-D. Several rows: the top row is copied down the selection. One row: the cells
  /// above are copied into it. Formulas adjust, as with the fill handle.
  func fillDown() {
    let n = selectionRange.normalized
    if n.maxRow > n.minRow {
      fillSelection(
        from: CellRange(
          start: CellAddress(row: n.minRow, col: n.minCol),
          end: CellAddress(row: n.minRow, col: n.maxCol)),
        to: CellAddress(row: n.maxRow, col: n.maxCol), copyOnly: true)
    } else if n.minRow > 0 {
      let anchor = selectionAnchor
      fillSelection(
        from: CellRange(
          start: CellAddress(row: n.minRow - 1, col: n.minCol),
          end: CellAddress(row: n.minRow - 1, col: n.maxCol)),
        to: CellAddress(row: n.maxRow, col: n.maxCol), copyOnly: true)
      selectRange(from: anchor, to: CellAddress(row: n.maxRow, col: n.maxCol))
    }
    undoManager?.setActionName("Fill Down")
  }

  /// Command-R. Several columns: the left column is copied across. One column: the cells to the
  /// left are copied into it.
  func fillRight() {
    let n = selectionRange.normalized
    if n.maxCol > n.minCol {
      fillSelection(
        from: CellRange(
          start: CellAddress(row: n.minRow, col: n.minCol),
          end: CellAddress(row: n.maxRow, col: n.minCol)),
        to: CellAddress(row: n.maxRow, col: n.maxCol), copyOnly: true)
    } else if n.minCol > 0 {
      let anchor = selectionAnchor
      fillSelection(
        from: CellRange(
          start: CellAddress(row: n.minRow, col: n.minCol - 1),
          end: CellAddress(row: n.maxRow, col: n.minCol - 1)),
        to: CellAddress(row: n.maxRow, col: n.maxCol), copyOnly: true)
      selectRange(from: anchor, to: CellAddress(row: n.maxRow, col: n.maxCol))
    }
    undoManager?.setActionName("Fill Right")
  }

  /// Values and formulas go; formats stay. The Delete key does the same.
  func clearContents() {
    commitEditIfNeeded()
    undoManager?.beginUndoGrouping()
    for range in selectionRanges { clearRange(range, actionName: "Clear Contents") }
    undoManager?.endUndoGrouping()
    undoManager?.setActionName("Clear Contents")
    syncEditTextFromSelection()
  }

  /// Formats go back to plain; values stay.
  func clearFormats() {
    commitEditIfNeeded()
    applyFormat(toRanges: selectionRanges, actionName: "Clear Formats") { _, format in
      format = CellFormat()
    }
  }

  /// Contents and formats, in one undo step.
  func clearAll() {
    commitEditIfNeeded()
    undoManager?.beginUndoGrouping()
    for range in selectionRanges { clearRange(range, actionName: "Clear All") }
    applyFormat(toRanges: selectionRanges, actionName: nil) { _, format in format = CellFormat() }
    undoManager?.endUndoGrouping()
    undoManager?.setActionName("Clear All")
    syncEditTextFromSelection()
  }
}
