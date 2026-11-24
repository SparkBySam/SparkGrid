import Foundation

/// OOXML type of a formula cell's cached `<v>`. Numbers have no `t` attribute.
public nonisolated enum ImportedFormulaValueType: String, Codable, Equatable, Sendable {
  case number
  case string
  case boolean
  case error
}

public nonisolated enum FormulaError: Equatable, Hashable, Sendable, CaseIterable {
  case divZero
  /// Two ranges with a space between them that do not overlap.
  case null
  case ref
  case value
  /// Multi-cell / array result forced into a single cell (Sheets-style `#VALUE!`).
  case arrayResult
  case name
  case cycle
  case na
  /// A number that cannot be computed, such as the square root of a negative.
  case num
  /// A formula whose results would spill over cells that already hold something.
  case spill
  /// A calculation with no result, such as FILTER matching nothing.
  case calc
  case error

  /// What appears in the cell (e.g. `#VALUE!`).
  public var displayCode: String {
    switch self {
    case .divZero: return "#DIV/0!"
    case .null: return "#NULL!"
    case .ref: return "#REF!"
    case .value, .arrayResult: return "#VALUE!"
    case .name: return "#NAME?"
    case .cycle: return "#CYCLE!"
    case .na: return "#N/A"
    case .num: return "#NUM!"
    case .spill: return "#SPILL!"
    case .calc: return "#CALC!"
    case .error: return "#ERROR!"
    }
  }

  /// Short Sheets-style explanation of what went wrong.
  public var explanation: String {
    switch self {
    case .divZero:
      return "Division by zero."
    case .ref:
      return
        "Invalid cell reference. The formula points at a cell that doesn’t exist (often after deleting rows or columns)."
    case .value:
      return
        "Wrong type of argument or operand. Check that values and ranges are the kinds this formula expects."
    case .null:
      return "The two ranges have no cell in common, so there is nothing to read."
    case .arrayResult:
      return
        "This formula produces more than one value, but it sits in a single cell. Wrap it in SUM(…) to combine the results, or use ARRAYFORMULA to fill a range."
    case .name:
      return
        "Unknown function or named range. Check the spelling, or define the name under Sheet → Name Manager…"
    case .cycle:
      return "Circular reference. This formula depends on itself (directly or through other cells)."
    case .na:
      return "Value not available. A lookup didn’t find a match."
    case .num:
      return
        "The number can’t be calculated, such as the square root of a negative number or a position past the end of a list."
    case .spill:
      return
        "The results would spill into cells that aren’t empty. Clear the cells below or beside the formula."
    case .calc:
      return "There is nothing to show, such as a FILTER that matches no rows."
    case .error:
      return
        "Couldn’t parse or evaluate this formula. Check for typos, missing parentheses, or unsupported syntax."
    }
  }

  public init?(displayCode code: String) {
    switch code.uppercased() {
    case "#DIV/0!": self = .divZero
    case "#NULL!": self = .null
    case "#REF!": self = .ref
    case "#VALUE!": self = .value
    case "#NAME?": self = .name
    case "#CYCLE!": self = .cycle
    case "#N/A": self = .na
    case "#NUM!": self = .num
    case "#SPILL!": self = .spill
    case "#CALC!": self = .calc
    case "#ERROR!": self = .error
    default: return nil
    }
  }
}

public nonisolated enum CellValue: Equatable, Sendable {
  case number(Double)
  case string(String)
  case bool(Bool)
  case blank
  case error(FormulaError)

  public var isError: Bool {
    if case .error = self { return true }
    return false
  }

  public var formulaError: FormulaError? {
    if case .error(let e) = self { return e }
    return nil
  }

  public var displayString: String {
    switch self {
    case .number(let n):
      if n.rounded() == n, abs(n) < 1e15 {
        return String(Int(n))
      }
      // Excel shows and converts numbers with at most 15 significant digits, so
      // 186000 * 0.7 is 130200, not 130199.99999999999, and 0.1 + 0.2 is 0.3.
      let fifteen = String(format: "%.15g", n)
      if !fifteen.contains("e"), let rounded = Double(fifteen) {
        if rounded.rounded() == rounded, abs(rounded) < 1e15 { return String(Int(rounded)) }
        return fifteen
      }
      var text = String(n)
      if text.hasSuffix(".0") {
        text = String(text.dropLast(2))
      }
      return text
    case .string(let s):
      return s
    case .bool(let b):
      return b ? "TRUE" : "FALSE"
    case .blank:
      return ""
    case .error(let e):
      return e.displayCode
    }
  }

  public var asNumber: Double? {
    switch self {
    case .number(let n): return n
    case .bool(let b): return b ? 1 : 0
    case .blank: return 0
    case .string(let s):
      let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.isEmpty { return 0 }
      return CellValue.numberReadingGroupCommas(trimmed)
    case .error:
      return nil
    }
  }

  /// Numeric value for chart previews — blanks and empty text are omitted, not treated as zero.
  public var asChartNumber: Double? {
    switch self {
    case .number(let n): return n
    case .bool(let b): return b ? 1 : 0
    case .blank: return nil
    case .string(let s):
      let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.isEmpty { return nil }
      return CellValue.numberReadingGroupCommas(trimmed)
    case .error:
      return nil
    }
  }

  public var asBool: Bool? {
    switch self {
    case .bool(let b): return b
    case .number(let n): return n != 0
    case .string(let s):
      let upper = s.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
      if upper == "TRUE" { return true }
      if upper == "FALSE" { return false }
      return nil
    case .blank: return false
    case .error: return nil
    }
  }

  public var asString: String {
    switch self {
    case .string(let s): return s
    case .number, .bool, .blank, .error: return displayString
    }
  }

  /// Text and OOXML type for a formula cell's cached `<v>`.
  /// Whole numbers stay decimal. Non-finite numbers are `#NUM!`.
  public var importedCacheStorage: (text: String, type: ImportedFormulaValueType) {
    switch self {
    case .number(let number):
      guard number.isFinite else { return ("#NUM!", .error) }
      return (Self.cacheNumber(number), .number)
    case .string(let text):
      return (text, .string)
    case .bool(let value):
      return (value ? "1" : "0", .boolean)
    case .blank:
      return ("", .string)
    case .error(let error):
      return (error.displayCode, .error)
    }
  }

  private static func cacheNumber(_ number: Double) -> String {
    if let exact = Int64(exactly: number) {
      return String(exact)
    }
    return String(number)
  }

  /// Value from an imported workbook's cached formula result (`<v>`).
  public static func fromImportedExcel(_ raw: String) -> CellValue {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return .blank }
    if let error = FormulaError(displayCode: trimmed) { return .error(error) }
    return fromLiteralRaw(trimmed)
  }

  /// Cached `<v>` using the cell's OOXML type. Untyped text keeps the old classification.
  public static func fromImportedCache(_ raw: String, type: ImportedFormulaValueType?) -> CellValue
  {
    switch type {
    case .boolean:
      switch raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
      case "1", "TRUE": return .bool(true)
      case "0", "FALSE": return .bool(false)
      default: return .bool(false)
      }
    case .error:
      let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      if let error = FormulaError(displayCode: trimmed) { return .error(error) }
      return .error(.error)
    case .string:
      let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? .blank : .string(trimmed)
    case .number:
      let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      if let number = CellValue.numberReadingGroupCommas(trimmed) {
        return .number(number)
      }
      return fromImportedExcel(trimmed)
    case nil:
      return fromImportedExcel(raw)
    }
  }

  public static func fromLiteralRaw(_ raw: String) -> CellValue {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return .blank }
    let upper = trimmed.uppercased()
    if upper == "TRUE" { return .bool(true) }
    if upper == "FALSE" { return .bool(false) }
    if let number = CellValue.numberReadingGroupCommas(trimmed) {
      return .number(number)
    }
    if trimmed.hasPrefix("$"),
      let number = CellValue.numberReadingGroupCommas(String(trimmed.dropFirst()))
    {
      return .number(number)
    }
    if trimmed.hasSuffix("%"),
      let number = CellValue.numberReadingGroupCommas(
        String(trimmed.dropLast()).trimmingCharacters(in: .whitespaces))
    {
      return .number(number / 100)
    }
    return .string(trimmed)
  }
}

extension CellValue {
  /// A number that may have commas between groups of three digits: `1,234.5`, `-12,000`.
  /// Commas anywhere else (`1,23`, `12,34,567`) make it text, as in other spreadsheet apps;
  /// they read as 123 and 1234567 before (found by script, Nov 18).
  public static func numberReadingGroupCommas(_ text: String) -> Double? {
    guard text.contains(",") else { return Double(text) }
    var body = Substring(text)
    var sign = ""
    if let first = body.first, first == "-" || first == "+" {
      sign = first == "-" ? "-" : ""
      body = body.dropFirst()
    }
    let parts = body.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count <= 2, let whole = parts.first else { return nil }
    let groups = whole.split(separator: ",", omittingEmptySubsequences: false)
    guard let first = groups.first, (1...3).contains(first.count) else { return nil }
    for group in groups.dropFirst() where group.count != 3 { return nil }
    guard groups.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }) else { return nil }
    let plain = sign + groups.joined() + (parts.count == 2 ? "." + parts[1] : "")
    return Double(plain)
  }
}
