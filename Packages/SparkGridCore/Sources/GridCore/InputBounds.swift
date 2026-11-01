import Foundation

/// Caps and checked arithmetic for numbers that come from files, formulas, pastes, or commands.
public nonisolated enum InputBounds {
  /// One range materialization. Larger than a full Excel column, smaller than a hostile grid.
  public static let maxMaterializedCells = 4_194_304
  /// Excel rejects a REPT result longer than this.
  public static let maxRepeatCharacters = 32_767
  /// Nested calls inside one formula.
  public static let maxFormulaNesting = 64
  /// Cell-to-cell evaluation depth. Each hop costs many stack frames, so this stays
  /// well below the depth that overflows the thread. A longer chain returns an error.
  public static let maxDependencyDepth = 64
  /// Rows or columns inserted, deleted, filled, or pasted in one command.
  public static let maxStructureCount = 1_048_576

  public static func span(from lower: Int, through upper: Int) -> Int {
    guard upper >= lower else { return 0 }
    let (delta, overflow) = upper.subtractingReportingOverflow(lower)
    if overflow { return maxMaterializedCells &+ 1 }
    let (count, countOverflow) = delta.addingReportingOverflow(1)
    if countOverflow { return maxMaterializedCells &+ 1 }
    return count
  }

  /// Nil when the product overflows or is above `maxMaterializedCells`. Zero when a side is empty.
  public static func materializedCount(rows: Int, cols: Int) -> Int? {
    if rows <= 0 || cols <= 0 { return 0 }
    let (product, overflow) = rows.multipliedReportingOverflow(by: cols)
    if overflow || product > maxMaterializedCells { return nil }
    return product
  }

  public static func cappedCount(_ count: Int, limit: Int = maxStructureCount) -> Int {
    if count < 0 { return 0 }
    return min(count, limit)
  }
}
