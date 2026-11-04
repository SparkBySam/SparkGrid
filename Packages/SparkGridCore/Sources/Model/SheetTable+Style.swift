import Foundation
import GridCore

/// How a table's built-in style (`TableStyleMedium2` and the like) paints its cells: a colored
/// header and banded rows. A cell's own fill, text color and bold always win.
public nonisolated struct TableStylePaint: Equatable, Sendable {
  public var headerFill: CodableColor?
  public var headerText: CodableColor?
  public var headerBold: Bool
  public var bandFill: CodableColor?
  public var headerRowCount: Int
  public var totalsRowCount: Int
  public var showsRowStripes: Bool

  /// Reads `<tableStyleInfo name="TableStyleMedium2" showRowStripes="1"/>` and the header and
  /// totals row counts. Nil when the table has no style.
  public init?(tableXML xml: String) {
    func attribute(_ name: String, in text: Substring) -> String? {
      guard let range = text.range(of: #"\b\#(name)="[^"]*""#, options: .regularExpression)
      else { return nil }
      return text[range].split(separator: "\"").dropFirst().first.map(String.init)
    }
    let tableTag =
      xml.range(of: #"<(\w+:)?table\b[^>]*>"#, options: .regularExpression).map { xml[$0] } ?? ""
    headerRowCount = attribute("headerRowCount", in: tableTag).flatMap(Int.init) ?? 1
    totalsRowCount = attribute("totalsRowCount", in: tableTag).flatMap(Int.init) ?? 0
    guard
      let infoRange = xml.range(of: #"<(\w+:)?tableStyleInfo\b[^>]*>"#, options: .regularExpression)
    else { return nil }
    let info = xml[infoRange]
    showsRowStripes = attribute("showRowStripes", in: info) == "1"
    guard let name = attribute("name", in: info), let style = Self.builtIn(name) else { return nil }
    headerFill = style.headerFill
    headerText = style.headerText
    headerBold = true
    bandFill = style.bandFill
  }

  /// Light, Medium and Dark styles 1–28: the number picks an Office accent, in rows of seven
  /// starting with a gray one.
  private static func builtIn(_ name: String)
    -> (headerFill: CodableColor?, headerText: CodableColor?, bandFill: CodableColor?)?
  {
    let families = ["TableStyleLight", "TableStyleMedium", "TableStyleDark"]
    guard let family = families.first(where: { name.hasPrefix($0) }),
      let number = Int(name.dropFirst(family.count)), number >= 1
    else { return nil }
    let accents: [(Double, Double, Double)] = [
      (0.25, 0.25, 0.25), (0.27, 0.45, 0.77), (0.93, 0.49, 0.19), (0.65, 0.65, 0.65),
      (1.0, 0.75, 0.0), (0.36, 0.61, 0.84), (0.44, 0.68, 0.28),
    ]
    let (r, g, b) = accents[(number - 1) % accents.count]
    let accent = CodableColor(red: r, green: g, blue: b, alpha: 1)
    func tint(_ amount: Double) -> CodableColor {
      CodableColor(
        red: r + (1 - r) * amount, green: g + (1 - g) * amount, blue: b + (1 - b) * amount,
        alpha: 1)
    }
    let white = CodableColor(red: 1, green: 1, blue: 1, alpha: 1)
    switch family {
    case "TableStyleLight":
      return (nil, nil, tint(0.8))
    case "TableStyleDark":
      let black = CodableColor(red: 0, green: 0, blue: 0, alpha: 1)
      return (black, white, tint(0.4))
    default:
      return (accent, white, tint(0.8))
    }
  }

  /// The cell's format with the table's paint underneath, or the cell's own format when the
  /// table paints nothing there.
  public func format(_ own: CellFormat?, at address: CellAddress, in range: CellRange)
    -> CellFormat?
  {
    let n = range.normalized
    let isHeader = address.row < n.minRow + headerRowCount
    let isTotals = totalsRowCount > 0 && address.row > n.maxRow - totalsRowCount
    var format = own ?? CellFormat()
    if isHeader || isTotals {
      if format.fillColor == nil, let headerFill, isHeader { format.fillColor = headerFill }
      if format.textColor == nil, isHeader, let headerText { format.textColor = headerText }
      if headerBold { format.bold = true }
    } else if showsRowStripes, format.fillColor == nil, let bandFill {
      // The first data row is banded, then every other one.
      let dataRow = address.row - (n.minRow + headerRowCount)
      guard dataRow % 2 == 0 else { return own }
      format.fillColor = bandFill
    } else {
      return own
    }
    return format
  }
}

extension Sheet {
  /// True when a styled table covers `address`, so an empty cell there still gets painted.
  public func tableContains(_ address: CellAddress) -> Bool {
    fileExtras.tables.contains { $0.range.contains(address) }
  }

  /// The cell's own format with any table style under it.
  public func formatWithTableStyle(at address: CellAddress) -> CellFormat? {
    let own = cell(at: address).format
    guard !fileExtras.tables.isEmpty else { return own }
    for table in fileExtras.tables where table.range.contains(address) {
      guard let paint = TableStylePaint.cached(table.xml) else { return own }
      return paint.format(own, at: address, in: table.range)
    }
    return own
  }
}

extension TableStylePaint {
  private static let cache = TableStyleCache()

  /// Parsed once per table definition; painting asks for every visible cell.
  static func cached(_ xml: String) -> TableStylePaint? {
    cache.paint(for: xml)
  }
}

private final class TableStyleCache: @unchecked Sendable {
  private let lock = NSLock()
  private var entries: [String: TableStylePaint?] = [:]

  func paint(for xml: String) -> TableStylePaint? {
    lock.lock()
    defer { lock.unlock() }
    if let hit = entries[xml] { return hit }
    let paint = TableStylePaint(tableXML: xml)
    if entries.count > 256 { entries.removeAll() }
    entries[xml] = .some(paint)
    return paint
  }
}
