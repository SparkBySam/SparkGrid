import Foundation
import GridCore

/// What a chart from another app shows, read from its kept chart part. Spark Grid draws it from
/// the cells it names; the part itself is saved back unchanged.
public nonisolated struct ImportedChart: Equatable, Sendable {
  public enum Kind: String, Equatable, Sendable {
    /// Vertical bars.
    case column
    /// Horizontal bars.
    case bar
    case line
    case area
    case pie
    case doughnut
    case scatter
  }

  /// A block of cells on a named sheet, such as `'Monthly Summary'!$C$4:$N$4`.
  public struct Reference: Equatable, Sendable {
    /// Nil when the reference names no sheet; it then reads the chart's own sheet.
    public var sheetName: String?
    public var range: CellRange

    public init(sheetName: String?, range: CellRange) {
      self.sheetName = sheetName
      self.range = range
    }

    /// Cells in reading order: across a row, or down a column, as the file lays them out.
    public var addresses: [CellAddress] {
      let n = range.normalized
      var cells: [CellAddress] = []
      cells.reserveCapacity((n.maxRow - n.minRow + 1) * (n.maxCol - n.minCol + 1))
      for row in n.minRow...n.maxRow {
        for col in n.minCol...n.maxCol {
          cells.append(CellAddress(row: row, col: col))
        }
      }
      return cells
    }
  }

  public struct Series: Equatable, Sendable {
    /// Legend name: the cell it reads, or the text the file stores.
    public var nameReference: Reference?
    public var name: String
    /// Category labels, or X values for a scatter chart.
    public var categories: Reference?
    public var values: Reference?
    /// What the file saved for each point. Shown when a cell cannot be read.
    public var cachedCategories: [String]
    public var cachedValues: [Double?]
    /// `RRGGBB` from the series' own fill or line, when the file sets one.
    public var colorHex: String?

    public init(
      nameReference: Reference? = nil,
      name: String = "",
      categories: Reference? = nil,
      values: Reference? = nil,
      cachedCategories: [String] = [],
      cachedValues: [Double?] = [],
      colorHex: String? = nil
    ) {
      self.nameReference = nameReference
      self.name = name
      self.categories = categories
      self.values = values
      self.cachedCategories = cachedCategories
      self.cachedValues = cachedValues
      self.colorHex = colorHex
    }
  }

  public var kind: Kind
  public var title: String
  /// Bars or areas in one series stacked on the series before.
  public var isStacked: Bool
  public var series: [Series]
  public var showsLegend: Bool
  public var categoryAxisTitle: String
  public var valueAxisTitle: String

  public init(
    kind: Kind,
    title: String = "",
    isStacked: Bool = false,
    series: [Series],
    showsLegend: Bool = false,
    categoryAxisTitle: String = "",
    valueAxisTitle: String = ""
  ) {
    self.kind = kind
    self.title = title
    self.isStacked = isStacked
    self.series = series
    self.showsLegend = showsLegend
    self.categoryAxisTitle = categoryAxisTitle
    self.valueAxisTitle = valueAxisTitle
  }
}
