import CoreGraphics
import Formula
import Foundation
import GridCore
import NumberFormat

/// A workbook-scoped defined name. Static ranges resolve to cells. Formulas such as
/// `OFFSET(...)` stay as `refersTo` and are not treated as a cell range.
public nonisolated struct NamedRange: Codable, Equatable, Sendable {
  public var name: String
  public var sheetName: String
  public var startRow: Int
  public var startCol: Int
  public var endRow: Int
  public var endCol: Int
  /// Original refers-to text from the workbook or the name manager.
  public var refersTo: String?
  /// False for formulas (OFFSET and anything else that is not a static reference).
  public var resolvesToRange: Bool

  public var range: CellRange {
    CellRange(
      start: CellAddress(row: startRow, col: startCol),
      end: CellAddress(row: endRow, col: endCol)
    )
  }

  /// What the name manager shows. Formula names keep their text; they are not rewritten as A1.
  public var referenceText: String {
    if let refersTo {
      let trimmed = refersTo.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty { return trimmed }
    }
    return Self.coordinateReference(sheetName: sheetName, range: range)
  }

  public init(name: String, sheetName: String, range: CellRange) {
    let n = range.normalized
    self.name = name
    self.sheetName = sheetName
    self.startRow = n.minRow
    self.startCol = n.minCol
    self.endRow = n.maxRow
    self.endCol = n.maxCol
    self.refersTo = nil
    self.resolvesToRange = true
  }

  /// A defined name whose refers-to is not a static range.
  public init(formulaName name: String, refersTo: String, sheetName: String) {
    self.name = name
    self.sheetName = sheetName
    self.startRow = 0
    self.startCol = 0
    self.endRow = 0
    self.endCol = 0
    self.refersTo = refersTo
    self.resolvesToRange = false
  }

  public static func coordinateReference(sheetName: String, range: CellRange) -> String {
    let n = range.normalized
    let sheetRef = sheetName.replacingOccurrences(of: "'", with: "''")
    let start = CellAddress(row: n.minRow, col: n.minCol).a1
    let end = CellAddress(row: n.maxRow, col: n.maxCol).a1
    if start == end { return "'\(sheetRef)'!\(start)" }
    return "'\(sheetRef)'!\(start):\(end)"
  }

  public enum CodingKeys: String, CodingKey {
    case name, sheetName, startRow, startCol, endRow, endCol, refersTo, resolvesToRange
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    name = try c.decode(String.self, forKey: .name)
    sheetName = try c.decode(String.self, forKey: .sheetName)
    startRow = try c.decode(Int.self, forKey: .startRow)
    startCol = try c.decode(Int.self, forKey: .startCol)
    endRow = try c.decode(Int.self, forKey: .endRow)
    endCol = try c.decode(Int.self, forKey: .endCol)
    refersTo = try c.decodeIfPresent(String.self, forKey: .refersTo)
    resolvesToRange = try c.decodeIfPresent(Bool.self, forKey: .resolvesToRange) ?? true
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(name, forKey: .name)
    try c.encode(sheetName, forKey: .sheetName)
    try c.encode(startRow, forKey: .startRow)
    try c.encode(startCol, forKey: .startCol)
    try c.encode(endRow, forKey: .endRow)
    try c.encode(endCol, forKey: .endCol)
    try c.encodeIfPresent(refersTo, forKey: .refersTo)
    try c.encode(resolvesToRange, forKey: .resolvesToRange)
  }
}

/// Parses a defined-name formula into a static range, or keeps the text when it is not one.
public nonisolated enum DefinedNameFormula {
  public static func make(name: String, formula: String, sheets: [Sheet], localSheet: String?)
    -> NamedRange
  {
    var text = formula.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.hasPrefix("=") {
      text = String(text.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if text.hasPrefix("["), let close = text.firstIndex(of: "]") {
      text = String(text[text.index(after: close)...]).trimmingCharacters(
        in: .whitespacesAndNewlines)
    }
    let fallback = localSheet ?? sheets.first?.name ?? "Sheet1"
    guard isStaticReference(text) else {
      return NamedRange(formulaName: name, refersTo: text, sheetName: fallback)
    }

    let start: FormulaRef
    let end: FormulaRef
    if let range = A1Reference.parseFormulaRange(text) {
      start = range.0
      end = range.1
    } else if let cell = A1Reference.parseFormulaRef(text) {
      start = cell
      end = cell
    } else {
      return NamedRange(formulaName: name, refersTo: text, sheetName: fallback)
    }

    var resolvedStart = start
    var resolvedEnd = end
    if resolvedStart.sheet == nil {
      resolvedStart.sheet = localSheet ?? end.sheet ?? sheets.first?.name
    }
    if resolvedEnd.sheet == nil {
      resolvedEnd.sheet = resolvedStart.sheet
    }
    guard let sheetName = resolvedStart.sheet ?? resolvedEnd.sheet,
      let sheet = sheets.first(where: { $0.name.caseInsensitiveCompare(sheetName) == .orderedSame })
    else {
      return NamedRange(formulaName: name, refersTo: text, sheetName: fallback)
    }

    let bounds = A1Reference.resolvedBounds(
      start: resolvedStart,
      end: resolvedEnd,
      maxRow: max(0, sheet.effectiveRowCount - 1),
      maxCol: max(0, sheet.effectiveColumnCount - 1)
    )
    var named = NamedRange(
      name: name,
      sheetName: sheet.name,
      range: CellRange(
        start: CellAddress(row: bounds.minRow, col: bounds.minCol),
        end: CellAddress(row: bounds.maxRow, col: bounds.maxCol)
      )
    )
    named.refersTo = text
    return named
  }

  /// Functions, unions, and arithmetic are not a single range.
  private static func isStaticReference(_ text: String) -> Bool {
    guard !text.isEmpty else { return false }
    var quoted = false
    for character in text {
      if character == "'" {
        quoted.toggle()
        continue
      }
      if quoted { continue }
      switch character {
      case "(", ")", ",", "+", "-", "*", "/", "&", "^", "=", "<", ">":
        return false
      default:
        break
      }
    }
    return true
  }
}

public nonisolated struct Workbook: Codable, Equatable, Sendable {
  public static let defaultRowCount = 1_000
  public static let defaultColumnCount = 26
  public static let defaultColumnWidth: CGFloat = 80
  public static let defaultRowHeight: CGFloat = 22

  public var sheets: [Sheet]
  public var activeSheetIndex: Int
  /// Global named ranges, keyed by uppercase name.
  public var namedRanges: [String: NamedRange]
  /// Raw `xl/theme/theme1.xml` from import — round-tripped on export when present.
  public var xlsxThemeData: Data?
  /// Pivot caches kept from the file for the pivot tables on its sheets.
  public var pivotCaches: [PivotCachePart] = []

  public init(
    sheets: [Sheet] = [Sheet(name: "Sheet1")],
    activeSheetIndex: Int = 0,
    namedRanges: [String: NamedRange] = [:],
    xlsxThemeData: Data? = nil
  ) {
    self.sheets = sheets.isEmpty ? [Sheet(name: "Sheet1")] : sheets
    self.activeSheetIndex = min(max(0, activeSheetIndex), self.sheets.count - 1)
    self.namedRanges = namedRanges
    self.xlsxThemeData = xlsxThemeData
  }

  public enum CodingKeys: String, CodingKey {
    case sheets, activeSheetIndex, namedRanges, xlsxThemeData, pivotCaches
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    sheets = try c.decode([Sheet].self, forKey: .sheets)
    activeSheetIndex = try c.decode(Int.self, forKey: .activeSheetIndex)
    namedRanges = try c.decodeIfPresent([String: NamedRange].self, forKey: .namedRanges) ?? [:]
    xlsxThemeData = try c.decodeIfPresent(Data.self, forKey: .xlsxThemeData)
    pivotCaches = try c.decodeIfPresent([PivotCachePart].self, forKey: .pivotCaches) ?? []
    if sheets.isEmpty { sheets = [Sheet(name: "Sheet1")] }
    activeSheetIndex = min(max(0, activeSheetIndex), sheets.count - 1)
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(sheets, forKey: .sheets)
    try c.encode(activeSheetIndex, forKey: .activeSheetIndex)
    try c.encode(namedRanges, forKey: .namedRanges)
    try c.encodeIfPresent(xlsxThemeData, forKey: .xlsxThemeData)
    if !pivotCaches.isEmpty {
      try c.encode(pivotCaches, forKey: .pivotCaches)
    }
  }

  public var activeSheet: Sheet {
    get { sheets[activeSheetIndex] }
    set { sheets[activeSheetIndex] = newValue }
  }

  public var isEffectivelyEmpty: Bool {
    sheets.allSatisfy(\.cells.isEmpty) && namedRanges.isEmpty
  }

  public static var empty: Workbook { Workbook() }

  public mutating func setNamedRange(_ range: NamedRange) {
    namedRanges[range.name.uppercased()] = range
  }

  public mutating func removeNamedRange(named name: String) {
    namedRanges.removeValue(forKey: name.uppercased())
  }

  public func namedRange(named name: String) -> NamedRange? {
    namedRanges[name.uppercased()]
  }
}
