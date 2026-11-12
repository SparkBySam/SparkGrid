import Foundation
import GridCore

/// What a pivot table shows: fields of a source range grouped into rows and columns, with values
/// summed, counted, averaged or reduced to their smallest or largest.
public nonisolated struct PivotDefinition: Codable, Equatable, Sendable {
  public enum Aggregate: String, Codable, CaseIterable, Sendable {
    case sum, count, average, min, max

    /// The word other spreadsheet apps put before a value field's name.
    public var label: String {
      switch self {
      case .sum: "Sum"
      case .count: "Count"
      case .average: "Average"
      case .min: "Min"
      case .max: "Max"
      }
    }
  }

  public struct ValueField: Codable, Equatable, Sendable {
    /// Column offset in the source range.
    public var field: Int
    public var aggregate: Aggregate

    public init(field: Int, aggregate: Aggregate) {
      self.field = field
      self.aggregate = aggregate
    }
  }

  public struct Filter: Codable, Equatable, Sendable {
    public var field: Int
    /// Item labels left out, as `PivotTable.label(for:)` writes them.
    public var hidden: Set<String>

    public init(field: Int, hidden: Set<String> = []) {
      self.field = field
      self.hidden = hidden
    }
  }

  /// How a date field's days are put together.
  public enum DateGroup: String, Codable, CaseIterable, Sendable {
    case year, quarter, month, day

    public var label: String {
      switch self {
      case .year: "Year"
      case .quarter: "Quarter"
      case .month: "Month"
      case .day: "Day"
      }
    }
  }

  public var rows: [Int]
  public var columns: [Int]
  public var values: [ValueField]
  public var filters: [Filter]
  /// Date fields grouped by year, quarter, month or day, by field.
  public var dateGroups: [Int: DateGroup]

  public init(
    rows: [Int] = [], columns: [Int] = [], values: [ValueField] = [], filters: [Filter] = [],
    dateGroups: [Int: DateGroup] = [:]
  ) {
    self.rows = rows
    self.columns = columns
    self.values = values
    self.filters = filters
    self.dateGroups = dateGroups
  }

  private enum CodingKeys: String, CodingKey {
    case rows, columns, values, filters, dateGroups
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    rows = try c.decodeIfPresent([Int].self, forKey: .rows) ?? []
    columns = try c.decodeIfPresent([Int].self, forKey: .columns) ?? []
    values = try c.decodeIfPresent([ValueField].self, forKey: .values) ?? []
    filters = try c.decodeIfPresent([Filter].self, forKey: .filters) ?? []
    dateGroups = try c.decodeIfPresent([Int: DateGroup].self, forKey: .dateGroups) ?? [:]
  }
}

/// A pivot table Spark Grid made: where its data comes from, where it is drawn, and what it shows.
public nonisolated struct SheetPivot: Codable, Equatable, Sendable, Identifiable {
  public var id: UUID
  public var name: String
  /// The source, header row first.
  public var sourceSheet: String
  public var sourceRange: CellRange
  /// The top-left cell of the drawn table on the sheet that holds this pivot.
  public var anchor: CellAddress
  public var definition: PivotDefinition
  /// The rows and columns the last drawing took, cleared before the next one.
  public var drawnRows: Int
  public var drawnColumns: Int
  /// The source's column names when the table was last drawn, for GETPIVOTDATA.
  public var fieldNames: [String]
  /// The name of the pivot table another app saved here that this one redraws. That table stays
  /// in the file and is told to rebuild itself when the file next opens in that app.
  public var linkedFilePivot: String?

  public init(
    id: UUID = UUID(), name: String, sourceSheet: String, sourceRange: CellRange,
    anchor: CellAddress, definition: PivotDefinition, drawnRows: Int = 0, drawnColumns: Int = 0,
    fieldNames: [String] = [], linkedFilePivot: String? = nil
  ) {
    self.id = id
    self.name = name
    self.sourceSheet = sourceSheet
    self.sourceRange = sourceRange
    self.anchor = anchor
    self.definition = definition
    self.drawnRows = drawnRows
    self.drawnColumns = drawnColumns
    self.fieldNames = fieldNames
    self.linkedFilePivot = linkedFilePivot
  }

  private enum CodingKeys: String, CodingKey {
    case id, name, sourceSheet, sourceRange, anchor, definition, drawnRows, drawnColumns
    case fieldNames, linkedFilePivot
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
    name = try c.decodeIfPresent(String.self, forKey: .name) ?? "PivotTable"
    sourceSheet = try c.decode(String.self, forKey: .sourceSheet)
    sourceRange = try c.decode(CellRange.self, forKey: .sourceRange)
    anchor = try c.decode(CellAddress.self, forKey: .anchor)
    definition =
      try c.decodeIfPresent(PivotDefinition.self, forKey: .definition) ?? PivotDefinition()
    drawnRows = try c.decodeIfPresent(Int.self, forKey: .drawnRows) ?? 0
    drawnColumns = try c.decodeIfPresent(Int.self, forKey: .drawnColumns) ?? 0
    fieldNames = try c.decodeIfPresent([String].self, forKey: .fieldNames) ?? []
    linkedFilePivot = try c.decodeIfPresent(String.self, forKey: .linkedFilePivot)
  }

  /// "Sum of Amount", one per value field, as the header row shows them.
  public var valueNames: [String] {
    definition.values.map { value in
      let field =
        value.field < fieldNames.count ? fieldNames[value.field] : "Column \(value.field + 1)"
      return "\(value.aggregate.label) of \(field)"
    }
  }

  /// The cells the last drawing covered.
  public var drawnRange: CellRange? {
    guard drawnRows > 0, drawnColumns > 0 else { return nil }
    return CellRange(
      start: anchor,
      end: CellAddress(row: anchor.row + drawnRows - 1, col: anchor.col + drawnColumns - 1))
  }
}

extension Workbook {
  /// The Spark Grid pivot table drawn over `address` on the sheet named `sheet`.
  public func sparkPivot(on sheet: String, containing address: CellAddress) -> SheetPivot? {
    guard
      let target = sheets.first(where: { $0.name.caseInsensitiveCompare(sheet) == .orderedSame })
    else { return nil }
    return target.fileExtras.sparkPivots.first { pivot in
      pivot.anchor == address || pivot.drawnRange?.contains(address) == true
    }
  }
}
