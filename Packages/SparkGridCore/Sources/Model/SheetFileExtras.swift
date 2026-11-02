import Foundation
import GridCore

/// Parts of a sheet that a file carries and the app keeps, so a save writes them back.
/// Hidden rows, columns and sheets also hide in the grid. The rest is kept as the file wrote it.
public nonisolated struct SheetFileExtras: Codable, Equatable, Sendable {
  public enum Visibility: String, Codable, Sendable {
    case visible, hidden, veryHidden
  }

  public var visibility: Visibility = .visible
  public var hiddenRows: Set<Int> = []
  public var hiddenColumns: Set<Int> = []
  /// Group (outline) level by row or column, 1 through 7. Level 0 is not stored.
  public var rowOutlineLevels: [Int: Int] = [:]
  public var columnOutlineLevels: [Int: Int] = [:]
  public var collapsedRows: Set<Int> = []
  public var collapsedColumns: Set<Int> = []
  /// `<sheetPr>` as read: tab color and outline settings.
  public var sheetPropertiesXML: String?
  /// `<sheetProtection>` as read, password hash included.
  public var protectionXML: String?
  /// `printOptions`, `pageMargins`, `pageSetup`, `headerFooter`, `rowBreaks`, `colBreaks`, in file order.
  public var pageLayoutXML: String?
  public var dataValidations: [DataValidationRule] = []
  public var hyperlinks: [CellHyperlink] = []
  public var comments: [CellComment] = []
  public var tables: [SheetTable] = []
  public var foreignCharts: [ForeignChart] = []
  public var pivotTables: [PivotTablePart] = []

  public init() {}

  public var isEmpty: Bool { self == SheetFileExtras() }

  public enum CodingKeys: String, CodingKey {
    case visibility, hiddenRows, hiddenColumns, rowOutlineLevels, columnOutlineLevels
    case collapsedRows, collapsedColumns, sheetPropertiesXML, protectionXML, pageLayoutXML
    case dataValidations, hyperlinks, comments, tables, foreignCharts, pivotTables
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    visibility = try c.decodeIfPresent(Visibility.self, forKey: .visibility) ?? .visible
    hiddenRows = try c.decodeIfPresent(Set<Int>.self, forKey: .hiddenRows) ?? []
    hiddenColumns = try c.decodeIfPresent(Set<Int>.self, forKey: .hiddenColumns) ?? []
    rowOutlineLevels = try c.decodeIfPresent([Int: Int].self, forKey: .rowOutlineLevels) ?? [:]
    columnOutlineLevels =
      try c.decodeIfPresent([Int: Int].self, forKey: .columnOutlineLevels) ?? [:]
    collapsedRows = try c.decodeIfPresent(Set<Int>.self, forKey: .collapsedRows) ?? []
    collapsedColumns = try c.decodeIfPresent(Set<Int>.self, forKey: .collapsedColumns) ?? []
    sheetPropertiesXML = try c.decodeIfPresent(String.self, forKey: .sheetPropertiesXML)
    protectionXML = try c.decodeIfPresent(String.self, forKey: .protectionXML)
    pageLayoutXML = try c.decodeIfPresent(String.self, forKey: .pageLayoutXML)
    dataValidations =
      try c.decodeIfPresent([DataValidationRule].self, forKey: .dataValidations) ?? []
    hyperlinks = try c.decodeIfPresent([CellHyperlink].self, forKey: .hyperlinks) ?? []
    comments = try c.decodeIfPresent([CellComment].self, forKey: .comments) ?? []
    tables = try c.decodeIfPresent([SheetTable].self, forKey: .tables) ?? []
    foreignCharts = try c.decodeIfPresent([ForeignChart].self, forKey: .foreignCharts) ?? []
    pivotTables = try c.decodeIfPresent([PivotTablePart].self, forKey: .pivotTables) ?? []
  }
}

/// One `<dataValidation>`: its ranges, its other attributes, and its formulas as written.
public nonisolated struct DataValidationRule: Codable, Equatable, Sendable {
  public var ranges: [CellRange]
  /// Attributes other than `sqref`, as written.
  public var attributes: String
  /// Child elements (`formula1`, `formula2`), as written.
  public var body: String

  public init(ranges: [CellRange], attributes: String, body: String) {
    self.ranges = ranges
    self.attributes = attributes
    self.body = body
  }

  /// True for a dropdown list rule.
  public var isList: Bool { attributes.contains(#"type="list""#) }

  /// The choices of a list rule whose source is written inline, such as `"Open,Closed"`.
  public var inlineListItems: [String]? {
    guard isList, let formula = formula1, Self.isInlineList(formula) else { return nil }
    return formula.dropFirst().dropLast().split(separator: ",", omittingEmptySubsequences: false)
      .map { String($0) }
  }

  /// The source formula of a list rule that points at cells, such as `$F$2:$F$9`.
  public var listSourceFormula: String? {
    guard isList, let formula = formula1, !formula.isEmpty, !Self.isInlineList(formula) else {
      return nil
    }
    return formula
  }

  private static func isInlineList(_ formula: String) -> Bool {
    formula.count >= 2 && formula.hasPrefix("\"") && formula.hasSuffix("\"")
  }

  /// The text of `<formula1>`, unescaped, so `'R&amp;D'!$A$1` reads as `'R&D'!$A$1`.
  private var formula1: String? {
    guard let open = body.range(of: "<formula1>"),
      let close = body.range(of: "</formula1>", range: open.upperBound..<body.endIndex)
    else { return nil }
    return String(body[open.upperBound..<close.lowerBound])
      .replacingOccurrences(of: "&quot;", with: "\"")
      .replacingOccurrences(of: "&apos;", with: "'")
      .replacingOccurrences(of: "&lt;", with: "<")
      .replacingOccurrences(of: "&gt;", with: ">")
      .replacingOccurrences(of: "&amp;", with: "&")
  }
}

public nonisolated struct CellHyperlink: Codable, Equatable, Sendable {
  public var range: CellRange
  /// A web or file address.
  public var target: String?
  /// A place in the workbook, such as `Sheet2!A1`.
  public var location: String?
  public var display: String?
  public var tooltip: String?

  public init(
    range: CellRange, target: String? = nil, location: String? = nil, display: String? = nil,
    tooltip: String? = nil
  ) {
    self.range = range
    self.target = target
    self.location = location
    self.display = display
    self.tooltip = tooltip
  }
}

public nonisolated struct CellComment: Codable, Equatable, Sendable {
  public var address: CellAddress
  public var author: String
  public var text: String

  public init(address: CellAddress, author: String, text: String) {
    self.address = address
    self.author = author
    self.text = text
  }
}

/// A table (`xl/tables/tableN.xml`) kept as written. `ref` is rewritten when rows move.
public nonisolated struct SheetTable: Codable, Equatable, Sendable {
  public var range: CellRange
  public var xml: String

  public init(range: CellRange, xml: String) {
    self.range = range
    self.xml = xml
  }
}

/// Cell position of a drawing corner, with its offset into that cell in EMU.
public nonisolated struct DrawingMarker: Codable, Equatable, Sendable {
  public var col: Int
  public var colOffset: Int
  public var row: Int
  public var rowOffset: Int

  public init(col: Int, colOffset: Int, row: Int, rowOffset: Int) {
    self.col = col
    self.colOffset = colOffset
    self.row = row
    self.rowOffset = rowOffset
  }
}

/// A chart the app does not draw yet, kept as written so a save does not drop it.
public nonisolated struct ForeignChart: Codable, Equatable, Sendable {
  /// The whole drawing anchor (two-cell, one-cell or absolute). Its chart reference is written as
  /// `r:id="SPARK_CHART_ID"`. `from` and `to` replace the anchor's own markers on save.
  public var anchorXML: String
  public var from: DrawingMarker?
  public var to: DrawingMarker?
  public var chartXML: Data

  public static let chartIDPlaceholder = "SPARK_CHART_ID"

  public init(anchorXML: String, from: DrawingMarker?, to: DrawingMarker?, chartXML: Data) {
    self.anchorXML = anchorXML
    self.from = from
    self.to = to
    self.chartXML = chartXML
  }
}

/// A pivot table definition kept as written, and the cache it reads.
public nonisolated struct PivotTablePart: Codable, Equatable, Sendable {
  public var xml: Data
  public var cacheID: Int

  public init(xml: Data, cacheID: Int) {
    self.xml = xml
    self.cacheID = cacheID
  }
}

/// A workbook pivot cache kept as written.
public nonisolated struct PivotCachePart: Codable, Equatable, Sendable {
  public var cacheID: Int
  public var definitionXML: Data
  public var recordsXML: Data?

  public init(cacheID: Int, definitionXML: Data, recordsXML: Data?) {
    self.cacheID = cacheID
    self.definitionXML = definitionXML
    self.recordsXML = recordsXML
  }
}
