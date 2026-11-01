import Foundation
import GridCore

public nonisolated enum A1Reference {
  public struct ParsedAddress: Equatable {
    public var row: Int
    public var col: Int
    public var absRow: Bool
    public var absCol: Bool

    public var asRef: FormulaRef {
      FormulaRef(sheet: nil, row: row, col: col, absRow: absRow, absCol: absCol)
    }
  }

  /// Full cell, column-only (`A`), or row-only (`2`) — used for open ranges like `A2:A`.
  public enum RangeEndpoint: Equatable {
    case cell(ParsedAddress)
    case column(col: Int, absCol: Bool)
    case row(row: Int, absRow: Bool)

    public var asRef: FormulaRef {
      switch self {
      case .cell(let parsed):
        return parsed.asRef
      case .column(let col, let absCol):
        return FormulaRef(sheet: nil, row: FormulaRef.open, col: col, absRow: false, absCol: absCol)
      case .row(let row, let absRow):
        return FormulaRef(sheet: nil, row: row, col: FormulaRef.open, absRow: absRow, absCol: false)
      }
    }
  }

  public static func parseAddress(_ text: String) -> ParsedAddress? {
    let upper = text.uppercased()
    guard !upper.isEmpty else { return nil }

    var index = upper.startIndex
    var absCol = false
    var absRow = false

    if upper[index] == "$" {
      absCol = true
      index = upper.index(after: index)
      guard index < upper.endIndex else { return nil }
    }

    var colLetters = ""
    while index < upper.endIndex, upper[index].isLetter {
      colLetters.append(upper[index])
      index = upper.index(after: index)
    }
    guard !colLetters.isEmpty, let col = A1Notation.columnIndex(from: colLetters) else {
      return nil
    }

    if index < upper.endIndex, upper[index] == "$" {
      absRow = true
      index = upper.index(after: index)
      guard index < upper.endIndex else { return nil }
    }

    var rowDigits = ""
    while index < upper.endIndex, upper[index].isNumber {
      rowDigits.append(upper[index])
      index = upper.index(after: index)
    }
    guard index == upper.endIndex, let rowNumber = Int(rowDigits), rowNumber >= 1 else {
      return nil
    }

    return ParsedAddress(row: rowNumber - 1, col: col, absRow: absRow, absCol: absCol)
  }

  public static func parseRangeEndpoint(_ text: String) -> RangeEndpoint? {
    if let cell = parseAddress(text) { return .cell(cell) }

    let upper = text.uppercased()
    guard !upper.isEmpty else { return nil }
    var index = upper.startIndex
    var abs = false
    if upper[index] == "$" {
      abs = true
      index = upper.index(after: index)
      guard index < upper.endIndex else { return nil }
    }

    // Column only: A / $A
    if upper[index].isLetter {
      var letters = ""
      while index < upper.endIndex, upper[index].isLetter {
        letters.append(upper[index])
        index = upper.index(after: index)
      }
      guard index == upper.endIndex, let col = A1Notation.columnIndex(from: letters) else {
        return nil
      }
      return .column(col: col, absCol: abs)
    }

    // Row only: 2 / $2
    if upper[index].isNumber {
      var digits = ""
      while index < upper.endIndex, upper[index].isNumber {
        digits.append(upper[index])
        index = upper.index(after: index)
      }
      guard index == upper.endIndex, let rowNumber = Int(digits), rowNumber >= 1 else { return nil }
      return .row(row: rowNumber - 1, absRow: abs)
    }

    return nil
  }

  /// Parses `A1`, `$A$1`, `Sheet1!A1`, `'My Sheet'!$B$2`.
  public static func parseFormulaRef(_ text: String) -> FormulaRef? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    if let bang = trimmed.firstIndex(of: "!") {
      let sheetPart = String(trimmed[..<bang])
      let addressPart = String(trimmed[trimmed.index(after: bang)...])
      guard let sheet = decodeSheetName(sheetPart),
        let parsed = parseAddress(addressPart)
      else { return nil }
      var ref = parsed.asRef
      ref.sheet = sheet
      return ref
    }

    guard let parsed = parseAddress(trimmed) else { return nil }
    return parsed.asRef
  }

  /// Parses `A1:B2`, `A2:A`, `A:A`, `2:2`, or `Sheet1!A2:A`.
  public static func parseFormulaRange(_ text: String) -> (FormulaRef, FormulaRef)? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let bang = trimmed.firstIndex(of: "!") else {
      return parseLocalRange(trimmed)
    }

    let sheetPart = String(trimmed[..<bang])
    let rangePart = String(trimmed[trimmed.index(after: bang)...])
    guard let sheet = decodeSheetName(sheetPart),
      let (start, end) = parseLocalRange(rangePart)
    else { return nil }
    var s = start
    var e = end
    s.sheet = sheet
    e.sheet = sheet
    return (s, e)
  }

  public static func parseRange(_ text: String) -> (CellAddress, CellAddress)? {
    guard let (start, end) = parseFormulaRange(text) else { return nil }
    return (start.address, end.address)
  }

  public static func isValidAddressToken(_ text: String) -> Bool {
    parseAddress(text) != nil
  }

  public static func isValidRangeEndpointToken(_ text: String) -> Bool {
    parseRangeEndpoint(text) != nil
  }

  public static func format(_ ref: FormulaRef) -> String {
    let body: String
    if ref.isRowOpen && !ref.isColOpen {
      let absPrefix = ref.absCol ? "$" : ""
      body = "\(absPrefix)\(A1Notation.columnLabel(for: ref.col))"
    } else if ref.isColOpen && !ref.isRowOpen {
      let absRowPrefix = ref.absRow ? "$" : ""
      body = "\(absRowPrefix)\(ref.row + 1)"
    } else if ref.isRowOpen && ref.isColOpen {
      body = "A1"
    } else {
      let absPrefix = ref.absCol ? "$" : ""
      let absRowPrefix = ref.absRow ? "$" : ""
      body = "\(absPrefix)\(A1Notation.columnLabel(for: ref.col))\(absRowPrefix)\(ref.row + 1)"
    }
    guard let sheet = ref.sheet else { return body }
    return "\(encodeSheetName(sheet))!\(body)"
  }

  public static func formatRange(start: FormulaRef, end: FormulaRef) -> String {
    let sheet = start.sheet ?? end.sheet
    var s = start
    var e = end
    s.sheet = nil
    e.sheet = nil
    let body = "\(format(s)):\(format(e))"
    guard let sheet else { return body }
    return "\(encodeSheetName(sheet))!\(body)"
  }

  /// Resolve open-ended bounds using the sheet's used extent.
  public static func resolvedBounds(
    start: FormulaRef,
    end: FormulaRef,
    maxRow: Int,
    maxCol: Int
  ) -> (minRow: Int, maxRow: Int, minCol: Int, maxCol: Int) {
    let lastRow = max(0, maxRow)
    let lastCol = max(0, maxCol)

    let startRow = start.isRowOpen ? 0 : start.row
    let startCol = start.isColOpen ? 0 : start.col
    let endRow = end.isRowOpen ? lastRow : end.row
    let endCol = end.isColOpen ? lastCol : end.col

    return (
      min(startRow, endRow),
      max(startRow, endRow),
      min(startCol, endCol),
      max(startCol, endCol)
    )
  }

  // MARK: - Private

  private static func parseLocalRange(_ text: String) -> (FormulaRef, FormulaRef)? {
    let parts = text.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count == 2,
      let start = parseRangeEndpoint(String(parts[0])),
      let end = parseRangeEndpoint(String(parts[1]))
    else { return nil }
    return (start.asRef, end.asRef)
  }

  private static func decodeSheetName(_ raw: String) -> String? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if trimmed.hasPrefix("'"), trimmed.hasSuffix("'"), trimmed.count >= 2 {
      let inner = trimmed.dropFirst().dropLast()
      return inner.replacingOccurrences(of: "''", with: "'")
    }
    if trimmed.contains("!") { return nil }
    return trimmed
  }

  private static func encodeSheetName(_ name: String) -> String {
    let needsQuotes =
      name.contains(" ")
      || name.contains("'")
      || name.contains("!")
      || name.first?.isNumber == true
      || name.contains(where: { !$0.isLetter && !$0.isNumber && $0 != "_" && $0 != "." })
    if needsQuotes {
      return "'\(name.replacingOccurrences(of: "'", with: "''"))'"
    }
    return name
  }
}
