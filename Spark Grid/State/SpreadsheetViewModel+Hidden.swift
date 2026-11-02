import Foundation
import SparkGridCore

/// Hide and Unhide for rows, columns and sheets. Files hide them; these let people see them again.
extension SpreadsheetViewModel {
  enum HideAxis {
    case rows, columns
  }

  /// The selection's ranges.
  private var hideTargetRanges: [CellRange] {
    selectionRanges.isEmpty ? [selectionRange] : selectionRanges
  }

  /// First and last row or column the selection covers, or nil when it covers none.
  private func selectedBounds(_ axis: HideAxis) -> (low: Int, high: Int)? {
    var bounds: (low: Int, high: Int)?
    for range in hideTargetRanges {
      let n = range.normalized
      let lower = axis == .rows ? n.minRow : n.minCol
      let upper = axis == .rows ? n.maxRow : n.maxCol
      guard upper >= lower else { continue }
      bounds = (min(bounds?.low ?? lower, lower), max(bounds?.high ?? upper, upper))
    }
    return bounds
  }

  /// Rows or columns the selection covers.
  private func selectedIndexes(_ axis: HideAxis) -> Set<Int> {
    var indexes = Set<Int>()
    for range in hideTargetRanges {
      let n = range.normalized
      let lower = axis == .rows ? n.minRow : n.minCol
      let upper = axis == .rows ? n.maxRow : n.maxCol
      guard upper >= lower else { continue }
      // A whole-sheet selection would list a million rows. Hidden ones are all that matter.
      if upper - lower > 100_000 {
        let hidden =
          axis == .rows ? activeSheet.fileExtras.hiddenRows : activeSheet.fileExtras.hiddenColumns
        indexes.formUnion(hidden.filter { $0 >= lower && $0 <= upper })
        continue
      }
      indexes.formUnion(lower...upper)
    }
    return indexes
  }

  /// Whether Unhide Rows and Unhide Columns apply. The menus ask on every selection change, so
  /// this reads only the selection's bounds, never a set of every selected row.
  var canUnhideInSelection: (rows: Bool, columns: Bool) {
    let extras = activeSheet.fileExtras
    guard !extras.hiddenRows.isEmpty || !extras.hiddenColumns.isEmpty else { return (false, false) }
    // Rows hidden next to the selection count, so a hidden row between two selected rows,
    // or just past one, can come back.
    func near(_ hidden: Set<Int>, _ axis: HideAxis) -> Bool {
      guard !hidden.isEmpty, let bounds = selectedBounds(axis) else { return false }
      return hidden.contains { $0 >= bounds.low - 1 && $0 <= bounds.high + 1 }
    }
    return (near(extras.hiddenRows, .rows), near(extras.hiddenColumns, .columns))
  }

  func hideSelected(_ axis: HideAxis) {
    commitEditIfNeeded()
    let indexes = selectedIndexes(axis)
    guard !indexes.isEmpty else { return }
    let sheet = activeSheet
    // Keep at least one row or column showing.
    let total = axis == .rows ? sheet.effectiveRowCount : sheet.effectiveColumnCount
    let alreadyHidden =
      axis == .rows ? sheet.fileExtras.hiddenRows.count : sheet.fileExtras.hiddenColumns.count
    guard indexes.count + alreadyHidden < max(total, 2) else { return }
    updateHidden(axis, actionName: axis == .rows ? "Hide Rows" : "Hide Columns") {
      $0.formUnion(indexes)
    }
  }

  /// Shows hidden rows or columns inside the selection and right next to it.
  func unhideSelected(_ axis: HideAxis) {
    commitEditIfNeeded()
    guard let (low, high) = selectedBounds(axis) else { return }
    updateHidden(axis, actionName: axis == .rows ? "Unhide Rows" : "Unhide Columns") { hidden in
      // Grow past runs of hidden rows touching the selection, so Unhide on the row below a
      // hidden block shows the whole block.
      var lower = low - 1
      while hidden.contains(lower) { lower -= 1 }
      var upper = high + 1
      while hidden.contains(upper) { upper += 1 }
      hidden = hidden.filter { $0 <= lower || $0 >= upper }
    }
  }

  private func updateHidden(
    _ axis: HideAxis, actionName: String, _ change: (inout Set<Int>) -> Void
  ) {
    var sheet = activeSheet
    let before = sheet.fileExtras
    switch axis {
    case .rows: change(&sheet.fileExtras.hiddenRows)
    case .columns: change(&sheet.fileExtras.hiddenColumns)
    }
    guard sheet.fileExtras != before else { return }
    recordFileExtrasChange(before: before, after: sheet.fileExtras, actionName: actionName)
  }

  /// Changes the active sheet's kept file parts as one undoable step.
  func updateFileExtras(actionName: String, _ change: (inout SheetFileExtras) -> Void) {
    commitEditIfNeeded()
    let before = activeSheet.fileExtras
    var after = before
    change(&after)
    guard after != before else { return }
    recordFileExtrasChange(before: before, after: after, actionName: actionName)
  }

  /// Applies `after` to the active sheet with an undo step that puts `before` back on that same
  /// sheet, even when another sheet is showing by the time Undo is chosen.
  private func recordFileExtrasChange(
    before: SheetFileExtras, after: SheetFileExtras, actionName: String
  ) {
    let sheetID = activeSheet.id
    applyFileExtras(after, sheetID: sheetID)
    registerFileExtrasUndo(before: before, after: after, sheetID: sheetID)
    undoManager?.setActionName(actionName)
  }

  private func registerFileExtrasUndo(
    before: SheetFileExtras, after: SheetFileExtras, sheetID: UUID
  ) {
    undoManager?.registerUndo(withTarget: self) { target in
      target.applyFileExtras(before, sheetID: sheetID)
      target.registerFileExtrasUndo(before: after, after: before, sheetID: sheetID)
    }
  }

  private func applyFileExtras(_ extras: SheetFileExtras, sheetID: UUID) {
    guard let index = workbook.sheets.firstIndex(where: { $0.id == sheetID }) else { return }
    if index != workbook.activeSheetIndex { selectSheet(at: index) }
    var sheet = activeSheet
    sheet.fileExtras = extras
    setActiveSheetPreservingFormulas(sheet)
    clampSelectionToSheet()
    notifyGridRefresh()
    onGridInvalidation?(.full)
  }
}
