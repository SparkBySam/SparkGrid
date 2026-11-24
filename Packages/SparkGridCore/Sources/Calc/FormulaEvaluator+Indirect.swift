import Formula
import Foundation
import GridCore

/// INDIRECT and ADDRESS, checked against Excel 16.115 (Nov 18).
extension FormulaEvaluator {
  static func isIndirect(_ name: String) -> Bool {
    plainFunctionName(name) == "INDIRECT"
  }

  /// The reference INDIRECT's text names: `"B2"`, `"B1:B3"`, `"Sheet2!A1"`, `"'My Sheet'!A:A"`, a
  /// defined name, or with FALSE as the second argument `"R2C2"` and `"R[1]C[-1]"`, counted
  /// from the formula's cell. Nil when the text names nothing, which INDIRECT shows as #REF!.
  func indirectTarget(_ args: [FormulaExpr]) -> FormulaExpr? {
    guard (1...2).contains(args.count) else { return nil }
    let textValue = evaluate(args[0])
    if case .error = textValue { return nil }
    let text = textValue.asString.trimmingCharacters(in: .whitespaces)
    guard !text.isEmpty else { return nil }
    var a1 = true
    if args.count == 2, !Self.isMissing(args[1]) {
      let flag = evaluate(args[1])
      if case .error = flag { return nil }
      a1 = flag.asBool ?? true
    }
    if !a1 { return Self.r1c1Reference(text, origin: evaluationOrigin) }
    guard let parsed = try? FormulaParser.parse(text) else { return nil }
    switch parsed {
    case .cellRef, .range:
      return parsed
    case .namedRange(let name):
      guard let resolved = namedRangeLookup(name) else { return nil }
      switch resolved {
      case .cellRef, .range: return resolved
      default: return nil
      }
    default:
      return nil
    }
  }

  /// INDIRECT where one value is wanted: the cell's value; a range of several cells is #VALUE!,
  /// as a plain range typed in a cell is.
  func evalINDIRECT(_ args: [FormulaExpr]) -> CellValue {
    guard (1...2).contains(args.count) else { return .error(.value) }
    if case .error(let error) = evaluate(args[0]) { return .error(error) }
    guard let target = indirectTarget(args) else { return .error(.ref) }
    if case .range(let start, let end) = target {
      let n = normalizedBounds(start: start, end: end)
      guard n.minRow == n.maxRow, n.minCol == n.maxCol else { return .error(.value) }
      return evaluate(.cellRef(start))
    }
    return evaluate(target)
  }

  /// `R2C3`, `R[1]C[-1]`, `RC[2]`, a range of two such, with an optional sheet in front.
  static func r1c1Reference(_ text: String, origin: CellAddress?) -> FormulaExpr? {
    var sheet: String?
    var body = Substring(text)
    if let bang = text.lastIndex(of: "!") {
      var name = String(text[..<bang])
      if name.hasPrefix("'"), name.hasSuffix("'"), name.count >= 2 {
        name = String(name.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
      }
      guard !name.isEmpty else { return nil }
      sheet = name
      body = text[text.index(after: bang)...]
    }
    let parts = body.split(separator: ":", omittingEmptySubsequences: false)
    guard (1...2).contains(parts.count) else { return nil }
    var refs: [FormulaRef] = []
    for part in parts {
      guard let ref = r1c1Cell(String(part), origin: origin) else { return nil }
      var withSheet = ref
      withSheet.sheet = sheet
      refs.append(withSheet)
    }
    return refs.count == 1 ? .cellRef(refs[0]) : .range(refs[0], refs[1])
  }

  private static func r1c1Cell(_ text: String, origin: CellAddress?) -> FormulaRef? {
    let upper = Array(text.uppercased())
    guard upper.first == "R", let cIndex = upper.firstIndex(of: "C") else { return nil }
    func axis(_ chars: ArraySlice<Character>, from base: Int?) -> (Int, Bool)? {
      if chars.isEmpty {
        guard let base else { return nil }
        return (base, false)
      }
      if chars.first == "[", chars.last == "]" {
        guard let base, let delta = Int(String(chars.dropFirst().dropLast())) else { return nil }
        return (base + delta, false)
      }
      guard let number = Int(String(chars)), number >= 1 else { return nil }
      return (number - 1, true)
    }
    guard let row = axis(upper[1..<cIndex], from: origin?.row),
      let col = axis(upper[(cIndex + 1)...], from: origin?.col),
      row.0 >= 0, col.0 >= 0, row.0 < 1_048_576, col.0 < 16_384
    else { return nil }
    return FormulaRef(row: row.0, col: col.0, absRow: row.1, absCol: col.1)
  }

  /// ADDRESS(row, column, [abs_num], [a1], [sheet_text]) as text: `$C$2`, `C$2`, `$C2`, `C2`,
  /// `R2C3`…`R[2]C[3]`, with the sheet in front, quoted where it needs to be.
  func evalADDRESS(_ args: [FormulaExpr]) -> CellValue {
    guard (2...5).contains(args.count) else { return .error(.value) }
    func number(_ index: Int, default fallback: Double) -> Outcome<Double> {
      guard index < args.count, !Self.isMissing(args[index]) else { return .value(fallback) }
      let value = evaluate(args[index])
      if case .error(let error) = value { return .failed(error) }
      guard let n = value.asNumber else { return .failed(.value) }
      return .value(n)
    }
    let rowNumber: Double
    let colNumber: Double
    let absNumber: Double
    switch (number(0, default: 0), number(1, default: 0), number(2, default: 1)) {
    case (.value(let r), .value(let c), .value(let a)):
      rowNumber = r
      colNumber = c
      absNumber = a
    case (.failed(let e), _, _), (_, .failed(let e), _), (_, _, .failed(let e)):
      return .error(e)
    }
    let row = Int(rowNumber.rounded(.down))
    let col = Int(colNumber.rounded(.down))
    let mode = Int(absNumber.rounded(.down))
    guard (1...1_048_576).contains(row), (1...16_384).contains(col), (1...4).contains(mode) else {
      return .error(.value)
    }
    var a1 = true
    if args.count >= 4, !Self.isMissing(args[3]) {
      let flag = evaluate(args[3])
      if case .error = flag { return flag }
      guard let value = flag.asBool else { return .error(.value) }
      a1 = value
    }
    let absRow = mode == 1 || mode == 2
    let absCol = mode == 1 || mode == 3
    let cell: String
    if a1 {
      cell =
        (absCol ? "$" : "") + A1Notation.columnLabel(for: col - 1) + (absRow ? "$" : "")
        + String(row)
    } else {
      cell = "R" + (absRow ? String(row) : "[\(row)]") + "C" + (absCol ? String(col) : "[\(col)]")
    }
    guard args.count == 5, !Self.isMissing(args[4]) else { return .string(cell) }
    let sheetValue = evaluate(args[4])
    if case .error = sheetValue { return sheetValue }
    return .string(Self.quotedSheetName(sheetValue.asString) + "!" + cell)
  }

  /// A sheet name as a reference writes it: quoted, with inner quotes doubled, when it has
  /// anything but letters, digits and underscores, starts with a digit, or reads as a cell.
  static func quotedSheetName(_ name: String) -> String {
    guard !name.isEmpty else { return "" }
    let plain = name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }
    let startsWithDigit = name.first?.isNumber == true
    let upper = name.uppercased()
    let readsAsCell =
      A1Reference.parseAddress(upper).map { $0.col < 16_384 && $0.row < 1_048_576 } ?? false
    let readsAsR1C1 =
      r1c1Reference(upper, origin: CellAddress(row: 0, col: 0)) != nil
      || upper == "R" || upper == "C"
    guard !plain || startsWithDigit || readsAsCell || readsAsR1C1 else { return name }
    return "'" + name.replacingOccurrences(of: "'", with: "''") + "'"
  }
}
