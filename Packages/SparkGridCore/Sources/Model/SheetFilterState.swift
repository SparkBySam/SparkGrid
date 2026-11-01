import Formula
import Foundation
import GridCore
import NumberFormat

/// AutoFilter on a sheet. Persisted with the workbook; xlsx round-trip keeps range and selected values.
public nonisolated struct SheetFilterState: Codable, Equatable, Sendable {
  /// Inclusive data range including the header row.
  public var range: CellRange
  /// Per-column selected display values. Missing key = all values visible for that column.
  public var selectedValuesByColumn: [Int: Set<String>]
  /// Columns that still sit in `range` but no longer participate (chevron removed / criteria cleared).
  public var excludedColumns: Set<Int> = []
  /// Rule filters by column (contains, greater than, between, top 10). A column has values or
  /// rules, not both.
  public var rulesByColumn: [Int: ColumnFilterRules] = [:]

  public init(
    range: CellRange,
    selectedValuesByColumn: [Int: Set<String>] = [:],
    excludedColumns: Set<Int> = []
  ) {
    self.range = range
    self.selectedValuesByColumn = selectedValuesByColumn
    self.excludedColumns = excludedColumns
  }

  public enum CodingKeys: String, CodingKey {
    case range, selectedValuesByColumn, excludedColumns, rulesByColumn
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    range = try c.decode(CellRange.self, forKey: .range)
    selectedValuesByColumn =
      try c.decodeIfPresent([Int: Set<String>].self, forKey: .selectedValuesByColumn) ?? [:]
    excludedColumns = try c.decodeIfPresent(Set<Int>.self, forKey: .excludedColumns) ?? []
    rulesByColumn =
      try c.decodeIfPresent([Int: ColumnFilterRules].self, forKey: .rulesByColumn) ?? [:]
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(range, forKey: .range)
    try c.encode(selectedValuesByColumn, forKey: .selectedValuesByColumn)
    try c.encode(excludedColumns, forKey: .excludedColumns)
    if !rulesByColumn.isEmpty {
      try c.encode(rulesByColumn, forKey: .rulesByColumn)
    }
  }

  /// True when any column has values unchecked or a rule.
  public var hasCriteria: Bool { !selectedValuesByColumn.isEmpty || !rulesByColumn.isEmpty }

  /// True when this column's values or rules hide rows.
  public func isFiltering(column: Int) -> Bool {
    selectedValuesByColumn[column] != nil || rulesByColumn[column] != nil
  }

  /// Top and bottom cutoffs for every column with such a rule, worked out once per pass.
  public func cutoffs(sheet: Sheet, displayString: (CellAddress) -> String)
    -> [Int: ColumnFilterRules.Cutoffs]
  {
    var result: [Int: ColumnFilterRules.Cutoffs] = [:]
    for (col, rules) in rulesByColumn
    where rules.rules.contains(where: { $0.kind == .top || $0.kind == .bottom }) {
      let numbers = dataRows.compactMap {
        ColumnFilterRules.number(displayString(CellAddress(row: $0, col: col)))
      }
      result[col] = rules.cutoffs(numbers: numbers)
    }
    return result
  }

  public var headerRow: Int { range.normalized.minRow }

  public var dataRows: ClosedRange<Int> {
    let n = range.normalized
    return (n.minRow + 1)...n.maxRow
  }

  public func isColumnActive(_ col: Int) -> Bool {
    let n = range.normalized
    return col >= n.minCol && col <= n.maxCol && !excludedColumns.contains(col)
  }

  public func isRowHidden(
    _ row: Int, sheet: Sheet, displayString: (CellAddress) -> String,
    cutoffs: [Int: ColumnFilterRules.Cutoffs] = [:]
  ) -> Bool {
    isRowHidden(
      row, sheet: sheet, displayString: displayString, excludingColumn: nil, cutoffs: cutoffs)
  }

  public func uniqueValues(forColumn col: Int, sheet: Sheet, displayString: (CellAddress) -> String)
    -> [String]
  {
    let n = range.normalized
    guard isColumnActive(col), n.maxRow > n.minRow else { return [] }
    var seen = Set<String>()
    var ordered: [String] = []
    let cutoffs = cutoffs(sheet: sheet, displayString: displayString)
    for row in (n.minRow + 1)...n.maxRow {
      // Cascade: only list values from rows still visible under *other* columns' filters.
      if isRowHidden(
        row, sheet: sheet, displayString: displayString, excludingColumn: col, cutoffs: cutoffs)
      {
        continue
      }
      let value = displayString(CellAddress(row: row, col: col))
      if seen.insert(value).inserted {
        ordered.append(value)
      }
    }
    return ordered.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
  }

  /// Like `isRowHidden`, but ignores the filter on `excludingColumn` so that column's menu can widen.
  public func isRowHidden(
    _ row: Int,
    sheet: Sheet,
    displayString: (CellAddress) -> String,
    excludingColumn: Int?,
    cutoffs: [Int: ColumnFilterRules.Cutoffs] = [:]
  ) -> Bool {
    let n = range.normalized
    guard row > n.minRow, row <= n.maxRow else { return false }
    for col in n.minCol...n.maxCol {
      if let excludingColumn, col == excludingColumn { continue }
      guard isColumnActive(col) else { continue }
      if let rules = rulesByColumn[col] {
        let value = displayString(CellAddress(row: row, col: col))
        let columnCutoffs = cutoffs[col] ?? ColumnFilterRules.Cutoffs()
        if !rules.matches(value, cutoffs: columnCutoffs) { return true }
        continue
      }
      guard let allowed = selectedValuesByColumn[col] else { continue }
      let value = displayString(CellAddress(row: row, col: col))
      if !allowed.contains(value) { return true }
    }
    return false
  }
}

public nonisolated enum FindScope: String, CaseIterable, Sendable {
  case sheet
  case selection
}

public nonisolated enum SortDirection: String, CaseIterable, Sendable {
  case ascending
  case descending
}
