import Foundation
import SparkGridCore

/// Hide and Unhide for rows, columns and sheets. Files hide them; these let people see them again.
extension SpreadsheetViewModel {
  enum HideAxis {
    case rows, columns
  }

  /// Rows or columns the selection covers.
  func selectedIndexes(_ axis: HideAxis) -> Set<Int> {
    let ranges = selectionRanges.isEmpty ? [selectionRange] : selectionRanges
    var indexes = Set<Int>()
    for range in ranges {
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

  var canUnhideInSelection: (rows: Bool, columns: Bool) {
    let extras = activeSheet.fileExtras
    guard !extras.hiddenRows.isEmpty || !extras.hiddenColumns.isEmpty else { return (false, false) }
    // Rows hidden next to the selection count, so a hidden row between two selected rows,
    // or just past one, can come back.
    let rows = selectedIndexes(.rows)
    let columns = selectedIndexes(.columns)
    func near(_ hidden: Set<Int>, _ selected: Set<Int>) -> Bool {
      guard let low = selected.min(), let high = selected.max() else { return false }
      return hidden.contains { $0 >= low - 1 && $0 <= high + 1 }
    }
    return (near(extras.hiddenRows, rows), near(extras.hiddenColumns, columns))
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
    let selected = selectedIndexes(axis)
    guard let low = selected.min(), let high = selected.max() else { return }
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
    let after = sheet.fileExtras
    applyFileExtras(after)
    undoManager?.registerUndo(withTarget: self) { target in
      target.applyFileExtras(before)
      target.undoManager?.registerUndo(withTarget: target) { inner in
        inner.applyFileExtras(after)
      }
    }
    undoManager?.setActionName(actionName)
  }

  /// Changes the active sheet's kept file parts as one undoable step.
  func updateFileExtras(actionName: String, _ change: (inout SheetFileExtras) -> Void) {
    commitEditIfNeeded()
    let before = activeSheet.fileExtras
    var after = before
    change(&after)
    guard after != before else { return }
    applyFileExtras(after)
    undoManager?.registerUndo(withTarget: self) { target in
      target.applyFileExtras(before)
      target.undoManager?.registerUndo(withTarget: target) { inner in
        inner.applyFileExtras(after)
      }
    }
    undoManager?.setActionName(actionName)
  }

  private func applyFileExtras(_ extras: SheetFileExtras) {
    var sheet = activeSheet
    sheet.fileExtras = extras
    setActiveSheetPreservingFormulas(sheet)
    clampSelectionToSheet()
    notifyGridRefresh()
    onGridInvalidation?(.full)
  }
}
