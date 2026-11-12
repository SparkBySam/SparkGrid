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
  /// `printOptions`, `pageMargins`, `pageSetup`, `headerFooter`, in file order. Page breaks are
  /// kept in `rowBreaks` and `columnBreaks`.
  public var pageLayoutXML: String?
  /// The range File ▸ Print prints from this sheet, saved as its `_xlnm.Print_Area` name.
  public var printArea: CellRange?
  /// Manual page breaks: each is the first row or column of a new page.
  public var rowBreaks: Set<Int> = []
  public var columnBreaks: Set<Int> = []
  /// Other names a file scopes to this sheet with the `_xlnm.` prefix (print titles, a filter's
  /// range), keyed by full name, with the formula text as written.
  public var builtInNames: [String: String] = [:]
  public var dataValidations: [DataValidationRule] = []
  public var hyperlinks: [CellHyperlink] = []
  public var comments: [CellComment] = []
  public var tables: [SheetTable] = []
  public var foreignCharts: [ForeignChart] = []
  public var pivotTables: [PivotTablePart] = []
  /// Pivot tables made in Spark Grid, drawn on this sheet.
  public var sparkPivots: [SheetPivot] = []
  /// Cells each array formula spills into, keyed by the formula's cell (its own cell included).
  public var spills: [CellAddress: CellRange] = [:]
  /// Array formulas whose results are blocked by cells that are not empty; they show #SPILL!.
  public var blockedSpills: Set<CellAddress> = []

  public init() {}

  public var isEmpty: Bool { self == SheetFileExtras() }

  public enum CodingKeys: String, CodingKey {
    case visibility, hiddenRows, hiddenColumns, rowOutlineLevels, columnOutlineLevels
    case collapsedRows, collapsedColumns, sheetPropertiesXML, protectionXML, pageLayoutXML
    case printArea, rowBreaks, columnBreaks, builtInNames
    case dataValidations, hyperlinks, comments, tables, foreignCharts, pivotTables, sparkPivots
    case spills, blockedSpills
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
    printArea = try c.decodeIfPresent(CellRange.self, forKey: .printArea)
    rowBreaks = try c.decodeIfPresent(Set<Int>.self, forKey: .rowBreaks) ?? []
    columnBreaks = try c.decodeIfPresent(Set<Int>.self, forKey: .columnBreaks) ?? []
    builtInNames = try c.decodeIfPresent([String: String].self, forKey: .builtInNames) ?? [:]
    // Earlier builds kept page breaks inside the page layout text.
    if let layout = pageLayoutXML, layout.contains("Breaks") {
      let split = Self.splittingPageBreaks(from: layout)
      pageLayoutXML = split.layout
      rowBreaks.formUnion(split.rows)
      columnBreaks.formUnion(split.columns)
    }
    dataValidations =
      try c.decodeIfPresent([DataValidationRule].self, forKey: .dataValidations) ?? []
    hyperlinks = try c.decodeIfPresent([CellHyperlink].self, forKey: .hyperlinks) ?? []
    comments = try c.decodeIfPresent([CellComment].self, forKey: .comments) ?? []
    tables = try c.decodeIfPresent([SheetTable].self, forKey: .tables) ?? []
    foreignCharts = try c.decodeIfPresent([ForeignChart].self, forKey: .foreignCharts) ?? []
    pivotTables = try c.decodeIfPresent([PivotTablePart].self, forKey: .pivotTables) ?? []
    sparkPivots = try c.decodeIfPresent([SheetPivot].self, forKey: .sparkPivots) ?? []
    spills = try c.decodeIfPresent([CellAddress: CellRange].self, forKey: .spills) ?? [:]
    blockedSpills =
      try c.decodeIfPresent(Set<CellAddress>.self, forKey: .blockedSpills) ?? []
  }
}

extension SheetFileExtras {
  /// Takes `<rowBreaks>` and `<colBreaks>` out of page layout XML and returns their manual breaks.
  /// A `<brk id="n">` starts a new page at zero-based row or column `n`.
  public static func splittingPageBreaks(from xml: String) -> (
    layout: String?, rows: Set<Int>, columns: Set<Int>
  ) {
    var layout = xml
    var found: [String: Set<Int>] = ["rowBreaks": [], "colBreaks": []]
    for element in ["rowBreaks", "colBreaks"] {
      let pattern = "<\(element)\\b[^>]*/>|<\(element)\\b[^>]*>[\\s\\S]*?</\(element)>"
      while let range = layout.range(of: pattern, options: .regularExpression) {
        let block = String(layout[range])
        var ids = Set<Int>()
        var rest = block[...]
        while let brk = rest.range(of: #"<brk\b[^>]*>"#, options: .regularExpression) {
          let tag = String(rest[brk])
          rest = rest[brk.upperBound...]
          // Breaks a printer driver placed are written without man="1"; only manual ones stay.
          guard tag.contains(#"man="1""#) || tag.contains(#"man="true""#),
            let idRange = tag.range(of: #"\bid="(\d+)""#, options: .regularExpression)
          else { continue }
          let digits = tag[idRange].filter(\.isNumber)
          if let id = Int(digits), id > 0 { ids.insert(id) }
        }
        found[element, default: []].formUnion(ids)
        layout.removeSubrange(range)
      }
    }
    return (layout.isEmpty ? nil : layout, found["rowBreaks"] ?? [], found["colBreaks"] ?? [])
  }

  /// `<rowBreaks>` and `<colBreaks>` for the manual breaks, in the order a worksheet lists them.
  public var pageBreaksXML: String {
    func block(_ name: String, _ ids: Set<Int>, max: Int) -> String {
      guard !ids.isEmpty else { return "" }
      let items = ids.sorted().map { #"<brk id="\#($0)" max="\#(max)" man="1"/>"# }.joined()
      return
        #"<\#(name) count="\#(ids.count)" manualBreakCount="\#(ids.count)">\#(items)</\#(name)>"#
    }
    return block("rowBreaks", rowBreaks, max: 16383)
      + block("colBreaks", columnBreaks, max: 1_048_575)
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
