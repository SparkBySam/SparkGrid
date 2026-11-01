import CoreGraphics
import Formula
import Foundation
import GridCore
import NumberFormat

/// Chart embedded on a sheet (Spark-native; also stored in xlsx as a custom part).
public nonisolated struct SheetChart: Identifiable, Codable, Equatable, Sendable {
  public enum Kind: String, Codable, Sendable, CaseIterable, Identifiable {
    case bar
    case line
    case area

    public var id: String { rawValue }

    public var title: String {
      switch self {
      case .bar: return "Bar"
      case .line: return "Line"
      case .area: return "Area"
      }
    }
  }

  /// How Y values are produced from the data range.
  public enum ValueMode: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Plot numbers from `valueColumn`.
    case values
    /// Count rows for each distinct category label (good for CRM / lead dumps).
    case count

    public var id: String { rawValue }

    public var title: String {
      switch self {
      case .values: return "Values"
      case .count: return "Count of rows"
      }
    }
  }

  public var id: UUID
  public var kind: Kind
  public var title: String
  /// Inclusive data range (may include a header row).
  public var dataRange: CellRange
  /// Absolute column index used for category / X labels. `nil` = infer at render time (legacy).
  public var categoryColumn: Int?
  /// Absolute column index used for Y values when `valueMode == .values`.
  public var valueColumn: Int?
  public var hasHeaderRow: Bool
  public var valueMode: ValueMode
  /// Top-left of the on-sheet chart frame, in cell coordinates.
  public var anchorRow: Int
  public var anchorCol: Int
  public var rowSpan: Int
  public var colSpan: Int
  /// Points from the left edge of `anchorCol`. Zero keeps that edge on the cell border.
  public var originXOffset: CGFloat
  /// Points from the top edge of `anchorRow`. Zero keeps that edge on the cell border.
  public var originYOffset: CGFloat
  /// Points past the right edge of the spanned columns. Zero keeps that edge on a cell border.
  public var endXOffset: CGFloat
  /// Points past the bottom edge of the spanned rows. Zero keeps that edge on a cell border.
  public var endYOffset: CGFloat
  /// Whole-series color. Nil uses `defaultSeriesColor(for:)`.
  public var seriesColor: CodableColor?
  /// Plotted-point index → color. A missing index uses the series color.
  public var pointColors: [Int: CodableColor]
  public var showsLegend: Bool
  public var showsGridlines: Bool
  public var categoryAxisTitle: String
  public var valueAxisTitle: String
  /// Set once the user moves or resizes the chart. Import then keeps that
  /// frame, including when the frame covers the data range.
  public var frameIsCustom: Bool

  /// Smallest on-sheet span, in rows or columns.
  public static let minimumSpan = 4

  /// A placement offset is a distance from a cell border. Missing, negative,
  /// and non-finite values sit on the border.
  public static func clampedPlacementOffset(_ value: CGFloat) -> CGFloat {
    guard value.isFinite, value > 0 else { return 0 }
    return value
  }

  public init(
    id: UUID = UUID(),
    kind: Kind = .bar,
    title: String = "Chart",
    dataRange: CellRange,
    categoryColumn: Int? = nil,
    valueColumn: Int? = nil,
    hasHeaderRow: Bool = true,
    valueMode: ValueMode = .values,
    anchorRow: Int,
    anchorCol: Int,
    rowSpan: Int = 12,
    colSpan: Int = 8,
    originXOffset: CGFloat = 0,
    originYOffset: CGFloat = 0,
    endXOffset: CGFloat = 0,
    endYOffset: CGFloat = 0,
    seriesColor: CodableColor? = nil,
    pointColors: [Int: CodableColor] = [:],
    showsLegend: Bool = false,
    showsGridlines: Bool = true,
    categoryAxisTitle: String = "",
    valueAxisTitle: String = "",
    frameIsCustom: Bool = false
  ) {
    self.id = id
    self.kind = kind
    self.title = title
    self.dataRange = dataRange
    self.categoryColumn = categoryColumn
    self.valueColumn = valueColumn
    self.hasHeaderRow = hasHeaderRow
    self.valueMode = valueMode
    self.anchorRow = anchorRow
    self.anchorCol = anchorCol
    self.rowSpan = max(Self.minimumSpan, rowSpan)
    self.colSpan = max(Self.minimumSpan, colSpan)
    self.originXOffset = Self.clampedPlacementOffset(originXOffset)
    self.originYOffset = Self.clampedPlacementOffset(originYOffset)
    self.endXOffset = Self.clampedPlacementOffset(endXOffset)
    self.endYOffset = Self.clampedPlacementOffset(endYOffset)
    self.seriesColor = seriesColor
    self.pointColors = pointColors
    self.showsLegend = showsLegend
    self.showsGridlines = showsGridlines
    self.categoryAxisTitle = categoryAxisTitle
    self.valueAxisTitle = valueAxisTitle
    self.frameIsCustom = frameIsCustom
  }

  public enum CodingKeys: String, CodingKey {
    case id, kind, title, dataRange
    case categoryColumn, valueColumn, hasHeaderRow, valueMode
    case anchorRow, anchorCol, rowSpan, colSpan
    case originXOffset, originYOffset, endXOffset, endYOffset
    case seriesColor, pointColors, showsLegend, showsGridlines
    case categoryAxisTitle, valueAxisTitle, frameIsCustom
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
    kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .bar
    title = try c.decodeIfPresent(String.self, forKey: .title) ?? "Chart"
    dataRange = try c.decode(CellRange.self, forKey: .dataRange)
    categoryColumn = try c.decodeIfPresent(Int.self, forKey: .categoryColumn)
    valueColumn = try c.decodeIfPresent(Int.self, forKey: .valueColumn)
    hasHeaderRow = try c.decodeIfPresent(Bool.self, forKey: .hasHeaderRow) ?? true
    valueMode = try c.decodeIfPresent(ValueMode.self, forKey: .valueMode) ?? .values
    anchorRow = try c.decodeIfPresent(Int.self, forKey: .anchorRow) ?? 0
    anchorCol = try c.decodeIfPresent(Int.self, forKey: .anchorCol) ?? 0
    rowSpan = try c.decodeIfPresent(Int.self, forKey: .rowSpan) ?? 12
    colSpan = try c.decodeIfPresent(Int.self, forKey: .colSpan) ?? 8
    originXOffset = Self.clampedPlacementOffset(
      try c.decodeIfPresent(CGFloat.self, forKey: .originXOffset) ?? 0)
    originYOffset = Self.clampedPlacementOffset(
      try c.decodeIfPresent(CGFloat.self, forKey: .originYOffset) ?? 0)
    endXOffset = Self.clampedPlacementOffset(
      try c.decodeIfPresent(CGFloat.self, forKey: .endXOffset) ?? 0)
    endYOffset = Self.clampedPlacementOffset(
      try c.decodeIfPresent(CGFloat.self, forKey: .endYOffset) ?? 0)
    seriesColor = try c.decodeIfPresent(CodableColor.self, forKey: .seriesColor)
    pointColors = try c.decodeIfPresent([Int: CodableColor].self, forKey: .pointColors) ?? [:]
    showsLegend = try c.decodeIfPresent(Bool.self, forKey: .showsLegend) ?? false
    showsGridlines = try c.decodeIfPresent(Bool.self, forKey: .showsGridlines) ?? true
    categoryAxisTitle = try c.decodeIfPresent(String.self, forKey: .categoryAxisTitle) ?? ""
    valueAxisTitle = try c.decodeIfPresent(String.self, forKey: .valueAxisTitle) ?? ""
    frameIsCustom = try c.decodeIfPresent(Bool.self, forKey: .frameIsCustom) ?? false
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(id, forKey: .id)
    try c.encode(kind, forKey: .kind)
    try c.encode(title, forKey: .title)
    try c.encode(dataRange, forKey: .dataRange)
    try c.encodeIfPresent(categoryColumn, forKey: .categoryColumn)
    try c.encodeIfPresent(valueColumn, forKey: .valueColumn)
    try c.encode(hasHeaderRow, forKey: .hasHeaderRow)
    try c.encode(valueMode, forKey: .valueMode)
    try c.encode(anchorRow, forKey: .anchorRow)
    try c.encode(anchorCol, forKey: .anchorCol)
    try c.encode(rowSpan, forKey: .rowSpan)
    try c.encode(colSpan, forKey: .colSpan)
    try c.encode(originXOffset, forKey: .originXOffset)
    try c.encode(originYOffset, forKey: .originYOffset)
    try c.encode(endXOffset, forKey: .endXOffset)
    try c.encode(endYOffset, forKey: .endYOffset)
    try c.encodeIfPresent(seriesColor, forKey: .seriesColor)
    try c.encode(pointColors, forKey: .pointColors)
    try c.encode(showsLegend, forKey: .showsLegend)
    try c.encode(showsGridlines, forKey: .showsGridlines)
    try c.encode(categoryAxisTitle, forKey: .categoryAxisTitle)
    try c.encode(valueAxisTitle, forKey: .valueAxisTitle)
    try c.encode(frameIsCustom, forKey: .frameIsCustom)
  }

  /// Color used when the chart has no series color of its own.
  /// Bar and line use the first palette swatch. Area uses a steady blue.
  public static func defaultSeriesColor(for kind: Kind) -> CodableColor {
    switch kind {
    case .bar, .line:
      return CodableColor(red: 0.18, green: 0.45, blue: 0.86, alpha: 1)
    case .area:
      return CodableColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1)
    }
  }

  /// Series color, or the kind's default when the series color is unset.
  public var resolvedSeriesColor: CodableColor {
    seriesColor ?? Self.defaultSeriesColor(for: kind)
  }

  /// Point color, or the series color when this point has no override.
  public func resolvedColor(forPoint index: Int) -> CodableColor {
    pointColors[index] ?? resolvedSeriesColor
  }

  public mutating func setPointColor(_ color: CodableColor?, at index: Int) {
    if let color {
      pointColors[index] = color
    } else {
      pointColors.removeValue(forKey: index)
    }
  }

  /// Where the chart sits, for the side panel and Edit Chart.
  public var placementDescription: String {
    let cell = CellAddress(row: anchorRow, col: anchorCol).a1
    return "At \(cell) · \(colSpan)×\(rowSpan)"
  }

  /// Charts saved before they were drawn on the sheet sit on top of their data
  /// (anchor 0,0, or any frame that covers the plotted cells). Those move just
  /// under the data range. A frame the user placed stays put, even over the data.
  public func positionedUnderData() -> SheetChart {
    if frameIsCustom { return self }
    let n = dataRange.normalized
    let frameRows = max(1, rowSpan)
    let frameCols = max(1, colSpan)
    let overlapsRows = anchorRow <= n.maxRow && anchorRow + frameRows - 1 >= n.minRow
    let overlapsCols = anchorCol <= n.maxCol && anchorCol + frameCols - 1 >= n.minCol
    guard overlapsRows && overlapsCols else { return self }
    var next = self
    next.anchorRow = n.maxRow + 2
    next.anchorCol = n.minCol
    next.rowSpan = max(12, rowSpan)
    next.colSpan = max(8, colSpan)
    next.originXOffset = 0
    next.originYOffset = 0
    next.endXOffset = 0
    next.endYOffset = 0
    return next
  }
}
