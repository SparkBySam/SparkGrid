import Foundation
import SparkGridCore

/// FILTER, SORT, UNIQUE and other array formulas fill the cells below and beside them. After a
/// calculation this writes each formula's results into those cells, or marks the formula #SPILL!
/// when something typed is in the way. The spilled cells are worked out again, never undone.
extension SpreadsheetViewModel {
  /// Places the active sheet's array formula results. Spilled values can feed other array
  /// formulas, so it runs again while anything changes, a few times at most.
  func syncSpills() {
    guard !isSyncingSpills, !suspendFormulaRebuild else { return }
    isSyncingSpills = true
    defer { isSyncingSpills = false }
    for _ in 0..<4 {
      var sheet = activeSheet
      let anchors = SpillLayout.anchors(in: sheet)
      guard
        !anchors.isEmpty || !sheet.fileExtras.spills.isEmpty
          || !sheet.fileExtras.blockedSpills.isEmpty
      else { return }
      var arrays: [CellAddress: ArrayResult] = [:]
      for anchor in anchors {
        arrays[anchor] = formulaEngine.spillArray(at: anchor, sheet: sheet, activeSheet: sheet)
      }
      let extrasBefore = sheet.fileExtras
      let outcome = SpillLayout.apply(arrays, to: &sheet)
      let changed = outcome.changedCells.union(outcome.changedAnchors)
        .union(SpillLayout.anchors(of: outcome.changedCells, in: sheet))
      guard !changed.isEmpty || sheet.fileExtras != extrasBefore else { return }
      // Worked out from the formulas each time, so not a step Undo goes through.
      undoManager?.disableUndoRegistration()
      replaceActiveSheetForSpill(sheet, changed: Array(changed))
      undoManager?.enableUndoRegistration()
    }
  }

  /// The array formula whose results cover `address`, if one does.
  func spillAnchor(covering address: CellAddress) -> CellAddress? {
    activeSheet.fileExtras.spills.first { anchor, range in
      anchor != address && range.contains(address)
    }?.key
  }
}
