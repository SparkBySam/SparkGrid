import Formula
import Foundation
import GridCore
import Model

/// REGEXTEST, REGEXEXTRACT and REGEXREPLACE (1.7, Nov 23), checked against Excel 16.115
/// (`ExcelRegexTests`). Patterns run on Foundation's regular expressions, which read the same
/// syntax as Excel's for everything tested, `\w` and `\p{Lu}` matching any letter included. One
/// difference: after an empty match Excel also tries a longer one at the same place, so a lazy
/// pattern that can match nothing (`a*?`) finds more matches in Excel.
extension FormulaEvaluator {
  /// REGEXEXTRACT returns all matches (mode 1) or the groups (mode 2) across a row.
  static let regexArrayFunctionNames: Set<String> = ["REGEXEXTRACT"]

  func evalRegex(_ name: String, _ args: [FormulaExpr]) -> CellValue? {
    switch name {
    case "REGEXTEST": return regexTest(args)
    case "REGEXREPLACE": return regexReplace(args)
    default: return nil
    }
  }

  func regexArray(_ name: String, _ args: [FormulaExpr]) -> ArrayResult? {
    name == "REGEXEXTRACT" ? regexExtract(args) : nil
  }

  // MARK: - REGEXTEST(text, pattern, [case_sensitivity])

  private func regexTest(_ args: [FormulaExpr]) -> CellValue {
    guard (2...3).contains(args.count) else { return .error(.value) }
    let text: String
    let regex: NSRegularExpression
    switch (regexText(args[0]), regexPattern(args, patternAt: 1, caseAt: 2)) {
    case (.failed(let e), _), (_, .failed(let e)): return .error(e)
    case (.value(let t), .value(let r)):
      text = t
      regex = r
    }
    let ns = text as NSString
    return .bool(regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) != nil)
  }

  // MARK: - REGEXEXTRACT(text, pattern, [return_mode], [case_sensitivity])

  /// Mode 0: the first match. 1: every match, across a row. 2: the first match's groups, across
  /// a row, #N/A for a group that took no part. No match is #N/A (#VALUE! in mode 2, as Excel).
  private func regexExtract(_ args: [FormulaExpr]) -> ArrayResult {
    guard (2...4).contains(args.count) else { return Self.fail(.value) }
    // A range of texts is #VALUE! in Excel; REGEXTEST and REGEXREPLACE go through each one.
    let source = evaluateArray(args[0])
    guard source.isSingle else { return Self.fail(.value) }
    let text: String
    switch regexText(args[0]) {
    case .failed(let e): return Self.fail(e)
    case .value(let t): text = t
    }
    let mode: Int
    switch regexWhole(args, 2, default: 0) {
    case .failed(let e): return Self.fail(e)
    case .value(let n): mode = n
    }
    guard (0...2).contains(mode) else { return Self.fail(.value) }
    let regex: NSRegularExpression
    switch regexPattern(args, patternAt: 1, caseAt: 3) {
    case .failed(let e): return Self.fail(e)
    case .value(let r): regex = r
    }
    let ns = text as NSString
    let whole = NSRange(location: 0, length: ns.length)
    switch mode {
    case 1:
      let matches = regex.matches(in: text, range: whole)
      guard !matches.isEmpty else { return Self.fail(.na) }
      let values = matches.map { CellValue.string(ns.substring(with: $0.range)) }
      return ArrayResult(rows: 1, cols: values.count, values: values)
    case 2:
      guard regex.numberOfCaptureGroups > 0, let match = regex.firstMatch(in: text, range: whole)
      else { return Self.fail(.value) }
      let values = (1...regex.numberOfCaptureGroups).map { index -> CellValue in
        let range = match.range(at: index)
        return range.location == NSNotFound ? .error(.na) : .string(ns.substring(with: range))
      }
      return ArrayResult(rows: 1, cols: values.count, values: values)
    default:
      guard let match = regex.firstMatch(in: text, range: whole) else { return Self.fail(.na) }
      return ArrayResult(.string(ns.substring(with: match.range)))
    }
  }

  // MARK: - REGEXREPLACE(text, pattern, replacement, [occurrence], [case_sensitivity])

  /// Occurrence 0 replaces every match; n the nth; -n the nth from the end; one past the matches
  /// leaves the text as it is. `$1`, `${1}`, `${name}` and `$0` put in groups; `$$` and `\$`
  /// a dollar sign; `\n` and `\t` a line break and a tab.
  private func regexReplace(_ args: [FormulaExpr]) -> CellValue {
    guard (3...5).contains(args.count) else { return .error(.value) }
    let text: String
    switch regexText(args[0]) {
    case .failed(let e): return .error(e)
    case .value(let t): text = t
    }
    let regex: NSRegularExpression
    switch regexPattern(args, patternAt: 1, caseAt: 4) {
    case .failed(let e): return .error(e)
    case .value(let r): regex = r
    }
    let replacement: String
    switch regexText(args[2]) {
    case .failed(let e): return .error(e)
    case .value(let t): replacement = t
    }
    let occurrence: Int
    switch regexWhole(args, 3, default: 0) {
    case .failed(let e): return .error(e)
    case .value(let n): occurrence = n
    }
    let ns = text as NSString
    let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
    let chosen: Set<Int>
    if occurrence == 0 {
      chosen = Set(matches.indices)
    } else {
      let index = occurrence > 0 ? occurrence - 1 : matches.count + occurrence
      chosen = matches.indices.contains(index) ? [index] : []
    }
    var out = ""
    var position = 0
    for (index, match) in matches.enumerated() where chosen.contains(index) {
      out += ns.substring(
        with: NSRange(location: position, length: match.range.location - position))
      guard
        let piece = Self.regexSubstitution(
          replacement, match: match, in: ns, regex: regex)
      else { return .error(.value) }
      out += piece
      position = match.range.location + match.range.length
    }
    out += ns.substring(from: position)
    return .string(out)
  }

  /// The replacement with its groups and escapes filled in; nil where Excel gives #VALUE!: a
  /// group the pattern doesn't have, a `$` before anything else, an unknown letter escape.
  static func regexSubstitution(
    _ template: String, match: NSTextCheckingResult, in ns: NSString,
    regex: NSRegularExpression
  ) -> String? {
    let chars = Array(template)
    var out = ""
    var i = 0
    func group(_ index: Int) -> String? {
      guard index <= regex.numberOfCaptureGroups else { return nil }
      let range = match.range(at: index)
      return range.location == NSNotFound ? "" : ns.substring(with: range)
    }
    func named(_ name: String) -> String? {
      // Asking for a name the pattern doesn't define raises, so look for it first.
      let pattern = regex.pattern
      guard pattern.contains("(?<\(name)>") || pattern.contains("(?P<\(name)>") else { return nil }
      let range = match.range(withName: name)
      return range.location == NSNotFound ? "" : ns.substring(with: range)
    }
    while i < chars.count {
      let c = chars[i]
      if c == "$" {
        guard i + 1 < chars.count else { return nil }
        let next = chars[i + 1]
        if next == "$" {
          out.append("$")
          i += 2
        } else if next.isASCII, next.isNumber {
          var j = i + 1
          var digits = ""
          while j < chars.count, chars[j].isASCII, chars[j].isNumber {
            digits.append(chars[j])
            j += 1
          }
          guard let index = Int(digits), let text = group(index) else { return nil }
          out += text
          i = j
        } else if next == "{", let close = chars[(i + 2)...].firstIndex(of: "}") {
          let inner = String(chars[(i + 2)..<close])
          let text = Int(inner).flatMap(group) ?? (Int(inner) == nil ? named(inner) : nil)
          guard let text else { return nil }
          out += text
          i = close + 1
        } else {
          return nil
        }
      } else if c == "\\", i + 1 < chars.count {
        let next = chars[i + 1]
        switch next {
        case "n": out.append("\n")
        case "t": out.append("\t")
        case "r": out.append("\r")
        case "f": out.append("\u{0C}")
        case "a": out.append("\u{07}")
        case "e": out.append("\u{1B}")
        default:
          // A letter or digit with no meaning is an error; anything else stands for itself.
          if next.isLetter || next.isNumber { return nil }
          out.append(next)
        }
        i += 2
      } else {
        out.append(c)
        i += 1
      }
    }
    return out
  }

  // MARK: - Arguments

  /// An argument as text: a number as it shows in General, TRUE as TRUE; an error stays one.
  private func regexText(_ expr: FormulaExpr) -> Outcome<String> {
    let value = evaluate(expr)
    if case .error(let e) = value { return .failed(e) }
    return .value(value.asString)
  }

  /// A whole-number option, cut toward zero as Excel does (1.7 is 1, -0.5 is 0).
  private func regexWhole(_ args: [FormulaExpr], _ index: Int, default fallback: Int)
    -> Outcome<Int>
  {
    guard index < args.count else { return .value(fallback) }
    if case .missing = args[index] { return .value(fallback) }
    let value = evaluate(args[index])
    switch value {
    case .error(let e): return .failed(e)
    case .blank: return .value(fallback)
    case .bool(let flag): return .value(flag ? 1 : 0)
    default:
      guard
        let number = value.asNumber ?? Double(value.asString.trimmingCharacters(in: .whitespaces)),
        number.isFinite, abs(number) < 1e9
      else { return .failed(.value) }
      return .value(Int(number.rounded(.towardZero)))
    }
  }

  /// The pattern, compiled; case_sensitivity 0 (the default) tells capitals apart, 1 doesn't.
  private func regexPattern(_ args: [FormulaExpr], patternAt index: Int, caseAt caseIndex: Int)
    -> Outcome<NSRegularExpression>
  {
    let pattern: String
    switch regexText(args[index]) {
    case .failed(let e): return .failed(e)
    case .value(let p): pattern = p
    }
    let caseValue: Int
    switch regexWhole(args, caseIndex, default: 0) {
    case .failed(let e): return .failed(e)
    case .value(let n): caseValue = n
    }
    guard caseValue == 0 || caseValue == 1 else { return .failed(.value) }
    // An empty pattern matches everywhere in Excel; Foundation refuses it, so ask for an empty
    // group, which means the same.
    guard
      let regex = try? NSRegularExpression(
        pattern: pattern.isEmpty ? "(?:)" : pattern,
        options: caseValue == 1 ? [.caseInsensitive] : [])
    else { return .failed(.value) }
    return .value(regex)
  }
}
