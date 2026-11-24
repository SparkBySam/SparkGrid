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
      // Formulas reading a spill, as in SUM(C1#), read it again now it is laid out. They are
      // recorded as reading only C1, so a new value further down the spill, or a longer spill,
      // left them with the old answer (found by script, Nov 18). Array formulas such as C1#*2
      // are worked out again above with the rest.
      let readers = Self.spillReferenceReaders(in: sheet).subtracting(changed)
        .subtracting(anchors)
      // Worked out from the formulas each time, so not a step Undo goes through.
      undoManager?.disableUndoRegistration()
      replaceActiveSheetForSpill(sheet, changed: Array(changed))
      // After the spill has its new values: read together, SUM(C1#) kept #SPILL! from a block
      // that Undo had just taken away.
      if !readers.isEmpty {
        replaceActiveSheetForSpill(activeSheet, changed: Array(readers))
      }
      undoManager?.enableUndoRegistration()
    }
  }

  /// Formulas on `sheet` with a spill reference: `C1#`, or `ANCHORARRAY(C1)` as files save it.
  static func spillReferenceReaders(in sheet: Sheet) -> Set<CellAddress> {
    var readers: Set<CellAddress> = []
    for entries in sheet.formulaIngestByColumn.values {
      for (address, raw) in entries
      where raw.contains("#") || raw.uppercased().contains("ANCHORARRAY(") {
        if raw.range(of: #"[A-Za-z]+\$?[0-9]+#"#, options: .regularExpression) != nil
          || raw.uppercased().contains("ANCHORARRAY(")
        {
          readers.insert(address)
        }
      }
    }
    return readers
  }

  /// The array formula whose results cover `address`, if one does.
  func spillAnchor(covering address: CellAddress) -> CellAddress? {
    activeSheet.fileExtras.spills.first { anchor, range in
      anchor != address && range.contains(address)
    }?.key
  }
}
