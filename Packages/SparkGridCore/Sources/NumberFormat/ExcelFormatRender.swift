import Foundation
import GridCore

/// Excel's number-format language, as TEXT and the grid read it: sections and conditions, digit
/// placeholders spread across literals, thousands grouping and scaling, percent, scientific and
/// engineering notation, fractions, `_` padding, and dates and times in Excel's 1900 calendar.
/// Checked against Excel 16.115 in `ExcelSavedTextTests`.
extension ExcelFormatCode {
  /// What a code makes of a number: text, General (the caller's own display), or nothing it
  /// can show (a date before 1900 or after 9999), which TEXT gives as #VALUE!.
  public enum Outcome: Equatable, Sendable {
    case text(String)
    case general
    case invalid
  }

  public static func render(_ value: Double, code: String, fractionDigits: Int?) -> Outcome {
    let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty || trimmed.caseInsensitiveCompare("General") == .orderedSame {
      return .general
    }
    let sections = splitSections(trimmed).prefix(3).map(parseSection)
    guard !sections.isEmpty, value.isFinite else { return .general }
    let (section, signed) = choose(sections, for: value)
    if section.body.isEmpty { return .text("") }
    if isTextPlaceholder(section.body) {
      return .text(CellValue.number(value).displayString)
    }
    let shown = signed ? value : abs(value)
    if isDateSection(section.body) {
      return renderDate(shown, body: section.body)
    }
    return renderNumber(shown, body: section.body, fractionDigits: fractionDigits)
  }

  // MARK: - Sections and conditions

  struct Section {
    var body: String
    var condition: (op: String, operand: Double)?
  }

  /// Takes out colors, locales and conditions; a currency like `[$€-407]` becomes its symbol.
  static func parseSection(_ raw: String) -> Section {
    var body = ""
    var condition: (op: String, operand: Double)?
    let chars = Array(raw)
    var i = 0
    while i < chars.count {
      let c = chars[i]
      if c == "\"" {
        let (_, end) = quoted(chars, from: i)
        body += String(chars[i..<end])
        i = end
        continue
      }
      if c == "\\", i + 1 < chars.count {
        body += String(chars[i...i + 1])
        i += 2
        continue
      }
      if c == "[" {
        var j = i + 1
        while j < chars.count, chars[j] != "]" { j += 1 }
        let inside = String(chars[(i + 1)..<min(j, chars.count)])
        let lower = inside.lowercased()
        if ["h", "hh", "m", "mm", "s", "ss"].contains(lower) {
          body += "[" + lower + "]"
        } else if inside.hasPrefix("$") {
          let symbol = inside.dropFirst().split(separator: "-", maxSplits: 1).first ?? ""
          if !symbol.isEmpty { body += "\"" + symbol + "\"" }
        } else if let parsed = parseCondition(inside) {
          condition = parsed
        }
        i = j + 1
        continue
      }
      body.append(c)
      i += 1
    }
    return Section(body: body, condition: condition)
  }

  private static func parseCondition(_ text: String) -> (op: String, operand: Double)? {
    for op in ["<=", ">=", "<>", "<", ">", "="] where text.hasPrefix(op) {
      guard let operand = Double(text.dropFirst(op.count)) else { return nil }
      return (op, operand)
    }
    return nil
  }

  private static func holds(_ condition: (op: String, operand: Double), _ v: Double) -> Bool {
    switch condition.op {
    case "<=": return v <= condition.operand
    case ">=": return v >= condition.operand
    case "<>": return v != condition.operand
    case "<": return v < condition.operand
    case ">": return v > condition.operand
    default: return v == condition.operand
    }
  }

  /// The section for `value`, and whether it shows the value's own sign. Whether a value is
  /// negative is decided before rounding, so -0.004 takes the negative section.
  private static func choose(_ sections: [Section], for value: Double) -> (Section, Bool) {
    if sections.contains(where: { $0.condition != nil }) {
      if let c = sections[0].condition, holds(c, value) {
        return (sections[0], !impliesNegative(c))
      }
      if sections[0].condition == nil, value >= 0 { return (sections[0], true) }
      if sections.count >= 2 {
        if let c = sections[1].condition {
          if holds(c, value) { return (sections[1], !impliesNegative(c)) }
          return (sections.count >= 3 ? sections[2] : sections[1], true)
        }
        return (sections[1], true)
      }
      return (sections[0], true)
    }
    switch sections.count {
    case 1: return (sections[0], true)
    case 2: return value < 0 ? (sections[1], false) : (sections[0], true)
    default:
      if value > 0 { return (sections[0], true) }
      if value < 0 { return (sections[1], false) }
      return (sections[2], true)
    }
  }

  private static func impliesNegative(_ c: (op: String, operand: Double)) -> Bool {
    (c.op == "<" || c.op == "<=") && c.operand <= 0
  }

  // MARK: - Numbers

  enum Token: Equatable {
    case literal(String)
    case digit(Character)
    case point
    case comma
    case percent
    case exponent(plus: Bool, upper: Bool)
    case slash
    case general
  }

  /// The text of a quoted literal starting at `start`, where `""` inside is one quote mark,
  /// and the index just past its closing quote.
  static func quoted(_ chars: [Character], from start: Int) -> (text: String, end: Int) {
    var text = ""
    var j = start + 1
    while j < chars.count {
      if chars[j] == "\"" {
        if j + 1 < chars.count, chars[j + 1] == "\"" {
          text.append("\"")
          j += 2
          continue
        }
        return (text, j + 1)
      }
      text.append(chars[j])
      j += 1
    }
    return (text, j)
  }

  static func tokenize(_ body: String) -> [Token] {
    var tokens: [Token] = []
    let chars = Array(body)
    var i = 0
    var sawPoint = false
    while i < chars.count {
      let c = chars[i]
      switch c {
      case "\"":
        let (text, end) = quoted(chars, from: i)
        tokens.append(.literal(text))
        i = end
        continue
      case "\\":
        if i + 1 < chars.count { tokens.append(.literal(String(chars[i + 1]))) }
        i += 2
        continue
      case "_":
        // Room for the next character: a space.
        tokens.append(.literal(" "))
        i += 2
        continue
      case "*":
        // Repeat to fill the cell: nothing in text.
        i += 2
        continue
      case "0", "#", "?":
        tokens.append(.digit(c))
      case ".":
        if sawPoint {
          tokens.append(.literal("."))
        } else {
          sawPoint = true
          tokens.append(.point)
        }
      case ",": tokens.append(.comma)
      case "%": tokens.append(.percent)
      case "/": tokens.append(.slash)
      case "E", "e":
        if i + 1 < chars.count, chars[i + 1] == "+" || chars[i + 1] == "-" {
          tokens.append(.exponent(plus: chars[i + 1] == "+", upper: c == "E"))
          i += 2
          continue
        }
        tokens.append(.literal(String(c)))
      case "G", "g":
        if String(chars[i..<min(i + 7, chars.count)]).lowercased() == "general" {
          tokens.append(.general)
          i += 7
          continue
        }
        tokens.append(.literal(String(c)))
      default:
        tokens.append(.literal(String(c)))
      }
      i += 1
    }
    return tokens
  }

  static func renderNumber(_ value: Double, body: String, fractionDigits: Int?) -> Outcome {
    let tokens = tokenize(body)
    let negative = value < 0
    let magnitude = abs(value)
    if tokens.contains(.general) {
      let general = CellValue.number(magnitude).displayString
      let text = tokens.map { token -> String in
        switch token {
        case .literal(let s): return s
        case .general: return general
        default: return ""
        }
      }.joined()
      return .text(negative ? "-" + text : text)
    }
    if !tokens.contains(where: { if case .digit = $0 { return true } else { return false } }) {
      // Only literals: the section's own text.
      return .text(
        tokens.map { if case .literal(let s) = $0 { return s } else { return "" } }.joined())
    }
    if tokens.contains(where: { if case .exponent = $0 { return true } else { return false } }) {
      return .text(renderScientific(magnitude, negative: negative, tokens: tokens))
    }
    if let fraction = renderFraction(magnitude, negative: negative, tokens: tokens) {
      return fraction
    }
    return .text(
      renderFixed(magnitude, negative: negative, tokens: tokens, fractionDigits: fractionDigits))
  }

  /// `value` rounded half away from zero on its 15-digit decimal, as whole and decimal digits.
  static func roundedDigits(_ value: Double, decimals: Int) -> (whole: String, fraction: String) {
    let text = String(format: "%.15g", locale: Locale(identifier: "en_US_POSIX"), value)
    guard var decimal = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else {
      return ("0", String(repeating: "0", count: max(0, decimals)))
    }
    var rounded = Decimal()
    NSDecimalRound(&rounded, &decimal, max(0, decimals), .plain)
    let plain = NSDecimalNumber(decimal: rounded).description(
      withLocale: Locale(identifier: "en_US_POSIX"))
    let parts = plain.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
    var fraction = parts.count > 1 ? parts[1] : ""
    if fraction.count < decimals {
      fraction += String(repeating: "0", count: decimals - fraction.count)
    }
    return (parts[0].hasPrefix("-") ? String(parts[0].dropFirst()) : parts[0], fraction)
  }

  /// Places `digits` into integer placeholders right to left; digits left over go before the
  /// first. An unfilled `0` shows 0, `?` a space, `#` nothing.
  private static func fillWhole(_ digits: String, tokens: [Token], group: Bool) -> String {
    var pending = Array(digits == "0" ? "" : digits)
    let placeholders = tokens.filter { if case .digit = $0 { return true } else { return false } }
    var out: [String] = []
    var seen = 0
    for token in tokens.reversed() {
      switch token {
      case .digit(let kind):
        seen += 1
        var piece: String
        if let last = pending.popLast() {
          piece = String(last)
        } else {
          piece = kind == "0" ? "0" : kind == "?" ? " " : ""
        }
        if seen == placeholders.count, !pending.isEmpty {
          piece = String(pending) + piece
          pending.removeAll()
        }
        out.append(piece)
      case .literal(let s):
        out.append(s)
      case .percent:
        out.append("%")
      default:
        break
      }
    }
    let joined = out.reversed().joined()
    guard group else { return joined }
    // Commas between the digits, counted from the right.
    let leading = joined.prefix { !$0.isNumber }
    let rest = joined.dropFirst(leading.count)
    let run = rest.prefix { $0.isNumber }
    let tail = rest.dropFirst(run.count)
    var groupedRun = ""
    for (i, ch) in run.reversed().enumerated() {
      if i > 0, i % 3 == 0 { groupedRun.append(",") }
      groupedRun.append(ch)
    }
    return String(leading) + String(groupedRun.reversed()) + String(tail)
  }

  private static func renderFixed(
    _ magnitude: Double, negative: Bool, tokens: [Token], fractionDigits: Int?
  ) -> String {
    let pointIndex = tokens.firstIndex(of: .point)
    var wholeTokens = Array(tokens[..<(pointIndex ?? tokens.endIndex)])
    var fractionTokens = pointIndex.map { Array(tokens[($0 + 1)...]) } ?? []
    // Commas right after the last whole placeholder scale by 1,000 each; between them, group.
    var scale = 0
    var group = false
    if let lastDigit = wholeTokens.lastIndex(where: {
      if case .digit = $0 { return true } else { return false }
    }) {
      var k = lastDigit + 1
      while k < wholeTokens.count, wholeTokens[k] == .comma {
        scale += 1
        k += 1
      }
      let firstDigit =
        wholeTokens.firstIndex(where: {
          if case .digit = $0 { return true } else { return false }
        }) ?? 0
      group = wholeTokens[firstDigit..<lastDigit].contains(.comma)
    }
    if pointIndex == nil, scale == 0 {
      // Commas at the very end of a code with no decimal point also scale.
      scale = tokens.reversed().prefix { $0 == .comma }.count
    }
    if scale == 0,
      let lastDigit = fractionTokens.lastIndex(where: {
        if case .digit = $0 { return true } else { return false }
      })
    {
      // Commas right after the last decimal place scale too: `0.0,,"M"` shows millions.
      scale = fractionTokens[(lastDigit + 1)...].prefix { $0 == .comma }.count
    }
    wholeTokens.removeAll { $0 == .comma }
    if let fd = fractionDigits {
      // The toolbar's decimal places replace the code's.
      fractionTokens = fractionTokens.filter {
        if case .digit = $0 { return false } else { return true }
      }
      fractionTokens.insert(contentsOf: Array(repeating: Token.digit("0"), count: fd), at: 0)
    }
    fractionTokens.removeAll { $0 == .comma }
    let percents = tokens.filter { $0 == .percent }.count
    var scaled = magnitude * pow(100, Double(percents)) / pow(1000, Double(scale))
    if !scaled.isFinite { scaled = magnitude }
    let decimalPlaces = fractionTokens.filter {
      if case .digit = $0 { return true } else { return false }
    }.count
    let digits = roundedDigits(scaled, decimals: decimalPlaces)
    var text = fillWhole(digits.whole, tokens: wholeTokens, group: group)
    // The toolbar's decimal places decide whether there is a point at all.
    let showPoint = fractionDigits.map { $0 > 0 } ?? (pointIndex != nil)
    if showPoint {
      text += "."
      let fraction = Array(digits.fraction)
      // Zeros at the end show for `0`, as a space for `?`, and not at all for `#`.
      let lastNonZero = fraction.lastIndex(where: { $0 != "0" }) ?? -1
      var position = 0
      for token in fractionTokens {
        switch token {
        case .digit(let kind):
          let ch = position < fraction.count ? fraction[position] : "0"
          if position <= lastNonZero || kind == "0" {
            text.append(ch)
          } else if kind == "?" {
            text.append(" ")
          }
          position += 1
        case .literal(let s): text += s
        case .percent: text += "%"
        default: break
        }
      }
    }
    let shownDigits = text.filter(\.isNumber)
    if negative, shownDigits.contains(where: { $0 != "0" }) { return "-" + text }
    return text
  }

  private static func renderScientific(_ magnitude: Double, negative: Bool, tokens: [Token])
    -> String
  {
    guard
      let e = tokens.firstIndex(where: {
        if case .exponent = $0 { return true } else { return false }
      }), case .exponent(let plus, let upper) = tokens[e]
    else { return "" }
    let mantissaTokens = Array(tokens[..<e]).filter { $0 != .comma }
    let exponentTokens = Array(tokens[(e + 1)...])
    let pointIndex = mantissaTokens.firstIndex(of: .point)
    let wholeTokens = Array(mantissaTokens[..<(pointIndex ?? mantissaTokens.endIndex)])
    let fractionTokens = pointIndex.map { Array(mantissaTokens[($0 + 1)...]) } ?? []
    let wholePlaces = wholeTokens.filter {
      if case .digit = $0 { return true } else { return false }
    }.count
    let decimals = fractionTokens.filter {
      if case .digit = $0 { return true } else { return false }
    }.count
    let exponentPlaces = max(
      1, exponentTokens.filter { if case .digit = $0 { return true } else { return false } }.count)
    // A # in the whole part steps the exponent by the number of whole places: ##0.0E+0 is
    // engineering notation.
    let engineering = wholePlaces > 1 && wholeTokens.contains(.digit("#"))
    let step = engineering ? wholePlaces : 1
    var exponent = 0
    var mantissa = 0.0
    if magnitude > 0 {
      let order = Int(floor(log10(magnitude)))
      if engineering {
        exponent = Int(floor(Double(order) / Double(step))) * step
      } else {
        exponent = order - max(0, wholePlaces - 1)
      }
      mantissa = magnitude / pow(10, Double(exponent))
      let limit = pow(10, Double(engineering ? step : max(1, wholePlaces)))
      let rounded =
        Double(
          roundedDigits(mantissa, decimals: decimals).whole + "."
            + roundedDigits(mantissa, decimals: decimals).fraction) ?? mantissa
      if rounded >= limit {
        exponent += step
        mantissa = magnitude / pow(10, Double(exponent))
      }
    }
    let digits = roundedDigits(mantissa, decimals: decimals)
    var wholeText: String
    if magnitude == 0 {
      // Zero shows every whole place, as other apps do: 000.0E+0.
      wholeText = String(repeating: "0", count: wholePlaces)
    } else {
      wholeText = fillWhole(digits.whole, tokens: wholeTokens, group: false)
    }
    if wholeText.isEmpty, wholePlaces > 0 { wholeText = "0" }
    var text = wholeText
    if pointIndex != nil {
      text += "."
      var position = 0
      let fraction = Array(digits.fraction)
      for token in fractionTokens {
        if case .digit = token {
          text.append(position < fraction.count ? fraction[position] : "0")
          position += 1
        } else if case .literal(let s) = token {
          text += s
        }
      }
    }
    let sign = exponent < 0 ? "-" : (plus ? "+" : "")
    let power = String(abs(exponent))
    let padded = String(repeating: "0", count: max(0, exponentPlaces - power.count)) + power
    text += (upper ? "E" : "e") + sign + padded
    for token in exponentTokens {
      if case .literal(let s) = token { text += s }
    }
    return negative && magnitude != 0 ? "-" + text : text
  }

  /// `# ?/?`, `# ??/??`, `?/8` and the like. Nil when the code is not a fraction.
  private static func renderFraction(_ magnitude: Double, negative: Bool, tokens: [Token])
    -> Outcome?
  {
    guard let slash = tokens.firstIndex(of: .slash) else { return nil }
    let before = Array(tokens[..<slash])
    let after = Array(tokens[(slash + 1)...])
    guard
      let numeratorEnd = before.lastIndex(where: {
        if case .digit = $0 { return true } else { return false }
      })
    else { return nil }
    var numeratorStart = numeratorEnd
    while numeratorStart > 0, case .digit = before[numeratorStart - 1] { numeratorStart -= 1 }
    let numeratorTokens = Array(before[numeratorStart...numeratorEnd])
    let wholeTokens = Array(before[..<numeratorStart])
    let hasWhole = wholeTokens.contains {
      if case .digit = $0 { return true } else { return false }
    }
    // The denominator: placeholders, or a number written in the code.
    var denominatorTokens: [Token] = []
    var fixedDenominator = ""
    var rest = after[...]
    while let first = rest.first {
      if case .digit = first {
        denominatorTokens.append(first)
      } else if case .literal(let s) = first, s.count == 1, let ch = s.first, ch.isNumber {
        fixedDenominator.append(ch)
      } else {
        break
      }
      rest = rest.dropFirst()
    }
    guard !denominatorTokens.isEmpty || !fixedDenominator.isEmpty else { return nil }
    var whole = hasWhole ? floor(magnitude) : 0
    let part = hasWhole ? magnitude - whole : magnitude
    var numerator = 0
    var denominator = 1
    if let fixed = Int(fixedDenominator), fixed > 0 {
      denominator = fixed
      let scaled = (part * Double(fixed)).rounded(.toNearestOrAwayFromZero)
      // Other apps keep this numerator in 16 bits: past 32,767 there is nothing to show.
      guard hasWhole || scaled <= 32_767 else { return .invalid }
      numerator = Int(scaled)
    } else {
      let maxDenominator = Int(pow(10, Double(denominatorTokens.count))) - 1
      var bestError = Double.infinity
      for q in 1...max(1, maxDenominator) {
        let p = (part * Double(q)).rounded(.toNearestOrAwayFromZero)
        let error = abs(part - p / Double(q))
        if error < bestError - 1e-12 {
          bestError = error
          numerator = Int(p)
          denominator = q
        }
      }
    }
    if hasWhole, numerator == denominator, numerator > 0 {
      whole += 1
      numerator = 0
    }
    func placed(_ digits: String, _ placeholders: [Token], leftPad: Bool) -> String {
      let width = placeholders.count
      guard digits.count < width else { return digits }
      let fill = String(repeating: " ", count: width - digits.count)
      return leftPad ? fill + digits : digits + fill
    }
    var text = ""
    let showFraction = numerator != 0 || !hasWhole
    if hasWhole {
      let wholeDigits = whole == 0 && showFraction ? "" : String(Int(whole))
      text += fillWhole(wholeDigits.isEmpty ? "0" : wholeDigits, tokens: wholeTokens, group: false)
      if whole == 0, !showFraction, !text.contains("0") { text = "0" + text }
    }
    let between = before[(numeratorEnd + 1)...].map {
      if case .literal(let s) = $0 { return s } else { return "" }
    }.joined()
    let denominatorText =
      fixedDenominator.isEmpty
      ? placed(String(denominator), denominatorTokens, leftPad: false) : fixedDenominator
    let fractionText =
      placed(String(numerator), numeratorTokens, leftPad: true) + between + "/" + denominatorText
    if showFraction {
      text += fractionText
    } else {
      text += String(repeating: " ", count: fractionText.count)
    }
    for token in rest {
      if case .literal(let s) = token { text += s }
    }
    let minus = negative && (hasWhole || numerator != 0)
    return .text(minus ? "-" + text : text)
  }

  // MARK: - Dates and times

  /// Days 1-59 are Jan 1 to Feb 28 1900; 60 is the Feb 29 1900 other apps keep; 0 is Jan 0.
  public static func excelDate(_ days: Int) -> (year: Int, month: Int, day: Int) {
    if days == 0 { return (1900, 1, 0) }
    if days == 60 { return (1900, 2, 29) }
    if days < 60 {
      let jan = days <= 31
      return jan ? (1900, 1, days) : (1900, 2, days - 31)
    }
    // Later days count from 30 Dec 1899, by the civil calendar.
    let z = days - 25_569 + 719_468
    let era = (z >= 0 ? z : z - 146_096) / 146_097
    let doe = z - era * 146_097
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
    let y = yoe + era * 400
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
    let mp = (5 * doy + 2) / 153
    let d = doy - (153 * mp + 2) / 5 + 1
    let m = mp < 10 ? mp + 3 : mp - 9
    return (m <= 2 ? y + 1 : y, m, d)
  }

  private enum DatePart: Equatable {
    case literal(String)
    case year(Int)
    case month(Int)
    case minute(Int)
    case day(Int)
    case hour(Int)
    case second(Int, fraction: Int)
    case elapsed(Character, Int)
    case ampm(String)
  }

  private static func dateParts(_ body: String) -> [DatePart] {
    var parts: [DatePart] = []
    let chars = Array(body)
    var i = 0
    func run(_ letter: Character) -> Int {
      var j = i
      while j < chars.count, chars[j].lowercased() == String(letter) { j += 1 }
      return j - i
    }
    while i < chars.count {
      let c = chars[i]
      let lower = Character(c.lowercased())
      if c == "\"" {
        let (text, end) = quoted(chars, from: i)
        parts.append(.literal(text))
        i = end
        continue
      }
      if c == "\\", i + 1 < chars.count {
        parts.append(.literal(String(chars[i + 1])))
        i += 2
        continue
      }
      if c == "_" {
        parts.append(.literal(" "))
        i += 2
        continue
      }
      if c == "*" {
        i += 2
        continue
      }
      if c == "[" {
        var j = i + 1
        while j < chars.count, chars[j] != "]" { j += 1 }
        let inside = String(chars[(i + 1)..<min(j, chars.count)])
        if let first = inside.first {
          parts.append(.elapsed(first, inside.count))
        }
        i = j + 1
        continue
      }
      let rest = String(chars[i...]).uppercased()
      if rest.hasPrefix("AM/PM") {
        parts.append(.ampm(String(chars[i..<i + 5])))
        i += 5
        continue
      }
      if rest.hasPrefix("A/P") {
        parts.append(.ampm(String(chars[i..<i + 3])))
        i += 3
        continue
      }
      switch lower {
      case "y", "e":
        let n = run(lower)
        parts.append(.year(lower == "e" ? 4 : n))
        i += n
      case "m":
        let n = run("m")
        parts.append(.month(n))
        i += n
      case "d":
        let n = run("d")
        parts.append(.day(n))
        i += n
      case "h":
        let n = run("h")
        parts.append(.hour(n))
        i += n
      case "s":
        let n = run("s")
        i += n
        var fraction = 0
        if i < chars.count, chars[i] == "." {
          var j = i + 1
          while j < chars.count, chars[j] == "0" { j += 1 }
          fraction = j - i - 1
          if fraction > 0 { i = j }
        }
        parts.append(.second(n, fraction: fraction))
      default:
        parts.append(.literal(String(c)))
        i += 1
      }
    }
    // An m right after an hour or right before a second is minutes.
    for index in parts.indices {
      guard case .month(let n) = parts[index], n <= 2 else { continue }
      let previous = parts[..<index].last {
        if case .literal = $0 { return false } else { return true }
      }
      let next = parts[(index + 1)...].first {
        if case .literal = $0 { return false } else { return true }
      }
      var afterHour = false
      if case .hour = previous { afterHour = true }
      if case .elapsed(let unit, _) = previous, unit == "h" { afterHour = true }
      var beforeSecond = false
      if case .second = next { beforeSecond = true }
      if case .elapsed(let unit, _) = next, unit == "s" { beforeSecond = true }
      if afterHour || beforeSecond { parts[index] = .minute(n) }
    }
    return parts
  }

  static func renderDate(_ serial: Double, body: String) -> Outcome {
    guard serial >= 0, serial < 2_958_466 else { return .invalid }
    let parts = dateParts(body)
    var fractionPlaces = 0
    var twelveHour = false
    for part in parts {
      if case .second(_, let f) = part { fractionPlaces = max(fractionPlaces, f) }
      if case .ampm = part { twelveHour = true }
    }
    // Rounded once, to the smallest unit shown, so 23:59:59.6 shows as the next day.
    let unitsPerSecond = pow(10, Double(fractionPlaces))
    let unitsPerDay = 86_400 * unitsPerSecond
    let units = (serial * unitsPerDay).rounded(.toNearestOrAwayFromZero)
    let days = Int((units / unitsPerDay).rounded(.down))
    let dayUnits = units - Double(days) * unitsPerDay
    let totalSeconds = units / unitsPerSecond
    let secondsInDay = Int((dayUnits / unitsPerSecond).rounded(.down))
    let hour = secondsInDay / 3600
    let minute = (secondsInDay % 3600) / 60
    let second = secondsInDay % 60
    let subsecond = dayUnits - Double(secondsInDay) * unitsPerSecond
    let date = excelDate(days)
    let weekday = (days + 6) % 7
    let months = [
      "January", "February", "March", "April", "May", "June", "July", "August", "September",
      "October", "November", "December",
    ]
    let weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    func two(_ n: Int) -> String { n < 10 ? "0\(n)" : String(n) }
    var text = ""
    for part in parts {
      switch part {
      case .literal(let s): text += s
      case .year(let n): text += n <= 2 ? two(date.year % 100) : String(date.year)
      case .month(let n):
        let name = months[date.month - 1]
        switch n {
        case 1: text += String(date.month)
        case 2: text += two(date.month)
        case 3: text += String(name.prefix(3))
        case 5: text += String(name.prefix(1))
        default: text += name
        }
      case .minute(let n): text += n == 1 ? String(minute) : two(minute)
      case .day(let n):
        switch n {
        case 1: text += String(date.day)
        case 2: text += two(date.day)
        case 3: text += String(weekdays[weekday].prefix(3))
        default: text += weekdays[weekday]
        }
      case .hour(let n):
        var h = hour
        if twelveHour {
          h = hour % 12
          if h == 0 { h = 12 }
        }
        text += n == 1 ? String(h) : two(h)
      case .second(let n, let fraction):
        text += n == 1 ? String(second) : two(second)
        if fraction > 0 {
          let digits = String(Int(subsecond))
          let padded = String(repeating: "0", count: max(0, fractionPlaces - digits.count)) + digits
          text += "." + String(padded.prefix(fraction))
        }
      case .elapsed(let unit, let n):
        let whole: Int
        switch unit {
        case "h", "H": whole = Int((totalSeconds / 3600).rounded(.down))
        case "m", "M": whole = Int((totalSeconds / 60).rounded(.down))
        default: whole = Int(totalSeconds.rounded(.down))
        }
        let digits = String(whole)
        text += String(repeating: "0", count: max(0, n - digits.count)) + digits
      case .ampm(let written):
        let pm = hour >= 12
        if written.count == 3 {
          let letter = pm ? "P" : "A"
          text += written.first?.isLowercase == true ? letter.lowercased() : letter
        } else {
          let word = pm ? "PM" : "AM"
          text += written.first?.isLowercase == true ? word.lowercased() : word
        }
      }
    }
    return .text(text)
  }
}
