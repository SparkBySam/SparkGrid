import Foundation
import GridCore

/// Small charts drawn inside cells, one per cell, each from a row or column of numbers. A group
/// shares a type and colors, as in other spreadsheet apps (Sam, Nov 20: "Goal Seek, chart
/// trendlines, sparklines, and saving as .ods").
public nonisolated struct SparklineGroup: Codable, Equatable, Sendable, Identifiable {
  public enum Kind: String, Codable, Sendable, CaseIterable, Identifiable {
    case line
    case column
    /// Up or down blocks: positive numbers up, negative down, zero blank.
    case winLoss

    public var id: String { rawValue }

    public var title: String {
      switch self {
      case .line: return "Line"
      case .column: return "Column"
      case .winLoss: return "Win/Loss"
      }
    }

    /// The `type` attribute the file format writes; a line writes none.
    public var fileType: String? {
      switch self {
      case .line: return nil
      case .column: return "column"
      case .winLoss: return "stacked"
      }
    }

    public init(fileType: String?) {
      switch fileType {
      case "column": self = .column
      case "stacked": self = .winLoss
      default: self = .line
      }
    }
  }

  /// One sparkline: the cell it draws in and the cells it reads.
  public struct Sparkline: Codable, Equatable, Sendable {
    public var location: CellAddress
    /// The sheet the data is on, when it is another sheet.
    public var dataSheet: String?
    public var data: CellRange

    public init(location: CellAddress, dataSheet: String? = nil, data: CellRange) {
      self.location = location
      self.dataSheet = dataSheet
      self.data = data
    }
  }

  public var id: UUID
  public var kind: Kind
  /// `RRGGBB`.
  public var colorHex: String
  /// `RRGGBB` for negative points, and for markers on high and low points.
  public var negativeColorHex: String
  /// Dots on every point of a line.
  public var showsMarkers: Bool
  /// The highest and lowest points marked.
  public var showsHighLow: Bool
  /// Negative columns in the negative color.
  public var showsNegative: Bool
  public var sparklines: [Sparkline]

  public static let defaultColor = "376092"
  public static let defaultNegativeColor = "D00000"

  public init(
    id: UUID = UUID(),
    kind: Kind = .line,
    colorHex: String = SparklineGroup.defaultColor,
    negativeColorHex: String = SparklineGroup.defaultNegativeColor,
    showsMarkers: Bool = false,
    showsHighLow: Bool = false,
    showsNegative: Bool = true,
    sparklines: [Sparkline]
  ) {
    self.id = id
    self.kind = kind
    self.colorHex = colorHex
    self.negativeColorHex = negativeColorHex
    self.showsMarkers = showsMarkers
    self.showsHighLow = showsHighLow
    self.showsNegative = showsNegative
    self.sparklines = sparklines
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
    kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .line
    colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex) ?? Self.defaultColor
    negativeColorHex =
      try c.decodeIfPresent(String.self, forKey: .negativeColorHex) ?? Self.defaultNegativeColor
    showsMarkers = try c.decodeIfPresent(Bool.self, forKey: .showsMarkers) ?? false
    showsHighLow = try c.decodeIfPresent(Bool.self, forKey: .showsHighLow) ?? false
    showsNegative = try c.decodeIfPresent(Bool.self, forKey: .showsNegative) ?? true
    sparklines = try c.decodeIfPresent([Sparkline].self, forKey: .sparklines) ?? []
  }

  /// Sparklines for each row of `data` into a column of cells starting at `location`, or each
  /// column into a row, whichever lines up with the location range. A single row or column of
  /// data makes one sparkline.
  public static func layout(data: CellRange, locations: CellRange) -> [Sparkline]? {
    let d = data.normalized
    let l = locations.normalized
    let locationCells =
      (l.minRow...l.maxRow).flatMap { row in
        (l.minCol...l.maxCol).map { CellAddress(row: row, col: $0) }
      }
    let rows = d.maxRow - d.minRow + 1
    let cols = d.maxCol - d.minCol + 1
    if locationCells.count == 1 {
      guard rows == 1 || cols == 1 else { return nil }
      return [Sparkline(location: locationCells[0], data: data)]
    }
    let locationIsColumn = l.minCol == l.maxCol
    let locationIsRow = l.minRow == l.maxRow
    if locationIsColumn, locationCells.count == rows {
      return (0..<rows).map { offset in
        Sparkline(
          location: locationCells[offset],
          data: CellRange(
            start: CellAddress(row: d.minRow + offset, col: d.minCol),
            end: CellAddress(row: d.minRow + offset, col: d.maxCol)))
      }
    }
    if locationIsRow, locationCells.count == cols {
      return (0..<cols).map { offset in
        Sparkline(
          location: locationCells[offset],
          data: CellRange(
            start: CellAddress(row: d.minRow, col: d.minCol + offset),
            end: CellAddress(row: d.maxRow, col: d.minCol + offset)))
      }
    }
    return nil
  }
}
