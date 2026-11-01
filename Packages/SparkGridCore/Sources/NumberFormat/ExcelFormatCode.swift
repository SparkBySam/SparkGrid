import Foundation
import GridCore

/// Renders an Excel number-format code: decimals, thousands separators, percent,
/// a currency symbol in the code, four sections, quoted literals, and date or time patterns.
public enum ExcelFormatCode {
  /// Maps a stored format code onto the categories the grid already displays.
  public static func numberFormatKind(for code: String) -> NumberFormatKind {
    let custom = withoutQuotedLiterals(code).trimmingCharacters(in: .whitespacesAndNewlines)
    if custom.isEmpty || custom == "general" || custom == "@" { return .general }
    if custom.contains("%") { return .percent }
    if custom.contains("$") || custom.contains("¥") || custom.contains("€") || custom.contains("£")
      || custom.contains("₩") || custom.contains("₹") || custom.contains("₽")
      || custom.contains("[$")
    {
      return .currency
    }
    if custom.contains("e+") || custom.contains("e-") { return .scientific }
    let looksLikeDate = (custom.contains("y") || custom.contains("d")) && custom.contains("m")
    if looksLikeDate { return .date }
    if custom.contains("h")
      && (custom.contains(":") || custom.contains("m") || custom.contains("s"))
    {
      return .time
    }
    if custom.contains("0") || custom.contains("#") { return .number }
    return .general
  }

  public static func formatted(_ value: Double, code: String, fractionDigits: Int?) -> String? {
    let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty || trimmed.caseInsensitiveCompare("General") == .orderedSame {
      return nil
    }
    let sections = splitSections(trimmed)
    guard let first = sections.first else { return nil }
    let negative = value < 0
    let section: String
    let signedBySection: Bool
    if value == 0, sections.count >= 3 {
      section = sections[2]
      signedBySection = true
    } else if negative, sections.count >= 2 {
      section = sections[1]
      signedBySection = true
    } else {
      section = first
      signedBySection = false
    }
    if section.isEmpty { return "" }
    if isTextPlaceholder(section) {
      return CellValue.number(value).displayString
    }
    if isDateSection(section) {
      return formatDate(value, section: section)
    }
    let parsed = parseNumber(section)
    if parsed.body.isEmpty {
      return parsed.prefix + parsed.suffix
    }
    let digits = formatDigits(abs(value), parsed: parsed, fractionDigits: fractionDigits)
    let rendered = parsed.prefix + digits + parsed.suffix
    let numeric = digits.filter(\.isNumber)
    if negative, !signedBySection, numeric.contains(where: { $0 != "0" }) {
      return "-" + rendered
    }
    return rendered
  }

  /// Fourth section of a format code (text). Nil when the code has no text section.
  public static func formattedText(_ text: String, code: String) -> String? {
    let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty || trimmed.caseInsensitiveCompare("General") == .orderedSame {
      return nil
    }
    let sections = splitSections(trimmed)
    guard sections.count >= 4 else { return nil }
    return renderTextSection(sections[3], text: text)
  }

  /// Fraction digits in the positive section, when the code is a number format.
  public static func fractionDigits(in code: String) -> Int? {
    let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed.caseInsensitiveCompare("General") != .orderedSame else {
      return nil
    }
    guard let section = splitSections(trimmed).first, !isDateSection(section),
      !isTextPlaceholder(section)
    else {
      return nil
    }
    let parsed = parseNumber(section)
    guard !parsed.body.isEmpty else { return nil }
    return parsed.minFraction
  }

  // MARK: - Sections

  private static func splitSections(_ code: String) -> [String] {
    var sections: [String] = []
    var current = ""
    var quoted = false
    var brackets = 0
    let chars = Array(code)
    var index = 0
    while index < chars.count {
      let character = chars[index]
      if character == "\"" {
        current.append(character)
        if quoted, index + 1 < chars.count, chars[index + 1] == "\"" {
          current.append(chars[index + 1])
          index += 2
          continue
        }
        quoted.toggle()
        index += 1
        continue
      }
      if !quoted, character == "\\" {
        current.append(character)
        index += 1
        if index < chars.count {
          current.append(chars[index])
          index += 1
        }
        continue
      }
      if !quoted, character == "[" {
        brackets += 1
      } else if !quoted, character == "]", brackets > 0 {
        brackets -= 1
      }
      if character == ";", !quoted, brackets == 0 {
        sections.append(current)
        current = ""
        index += 1
        continue
      }
      current.append(character)
      index += 1
    }
    sections.append(current)
    return sections
  }

  /// `@` with optional color brackets. A quoted `"@"` is a literal, not this placeholder.
  private static func isTextPlaceholder(_ section: String) -> Bool {
    var body = ""
    var quoted = false
    let chars = Array(section)
    var index = 0
    while index < chars.count {
      if chars[index] == "\"" {
        if quoted, index + 1 < chars.count, chars[index + 1] == "\"" {
          index += 2
          continue
        }
        quoted.toggle()
        index += 1
        continue
      }
      if quoted {
        index += 1
        continue
      }
      if chars[index] == "\\" {
        index += 2
        continue
      }
      if chars[index] == "[" {
        while index < chars.count, chars[index] != "]" { index += 1 }
        if index < chars.count { index += 1 }
        continue
      }
      body.append(chars[index])
      index += 1
    }
    return body.trimmingCharacters(in: .whitespaces) == "@"
  }

  private static func renderTextSection(_ section: String, text: String) -> String {
    var result = ""
    let chars = Array(section)
    var index = 0
    while index < chars.count {
      let character = chars[index]
      if character == "\"" {
        let quoted = readQuotedLiteral(in: chars, opening: index)
        result += quoted.text
        index = quoted.next
        continue
      }
      if character == "\\" {
        index += 1
        if index < chars.count {
          result.append(chars[index])
          index += 1
        }
        continue
      }
      if character == "_" || character == "*" {
        index += min(2, chars.count - index)
        continue
      }
      if character == "[" {
        while index < chars.count, chars[index] != "]" { index += 1 }
        if index < chars.count { index += 1 }
        continue
      }
      if character == "@" {
        result += text
        index += 1
        continue
      }
      result.append(character)
      index += 1
    }
    return result
  }

  /// Lowercased code with quoted literals and escaped characters removed.
  private static func withoutQuotedLiterals(_ section: String) -> String {
    var result = ""
    var quoted = false
    let chars = Array(section)
    var index = 0
    while index < chars.count {
      if chars[index] == "\"" {
        if quoted, index + 1 < chars.count, chars[index + 1] == "\"" {
          index += 2
          continue
        }
        quoted.toggle()
        index += 1
        continue
      }
      if quoted {
        index += 1
        continue
      }
      if chars[index] == "\\" {
        index += 2
        continue
      }
      result.append(chars[index])
      index += 1
    }
    return result.lowercased()
  }

  private static func readQuotedLiteral(in chars: [Character], opening index: Int) -> (
    text: String, next: Int
  ) {
    var text = ""
    var cursor = index + 1
    while cursor < chars.count {
      if chars[cursor] == "\"" {
        if cursor + 1 < chars.count, chars[cursor + 1] == "\"" {
          text.append("\"")
          cursor += 2
          continue
        }
        return (text, cursor + 1)
      }
      text.append(chars[cursor])
      cursor += 1
    }
    return (text, cursor)
  }

  private static func isDateSection(_ section: String) -> Bool {
    var significant = ""
    var quoted = false
    let chars = Array(section)
    var index = 0
    while index < chars.count {
      if chars[index] == "\"" {
        if quoted, index + 1 < chars.count, chars[index + 1] == "\"" {
          index += 2
          continue
        }
        quoted.toggle()
        index += 1
        continue
      }
      if quoted {
        index += 1
        continue
      }
      if chars[index] == "\\" {
        index += 2
        continue
      }
      if chars[index] == "[" {
        var inner = ""
        index += 1
        while index < chars.count, chars[index] != "]" {
          inner.append(chars[index])
          index += 1
        }
        if index < chars.count { index += 1 }
        let lower = inner.lowercased()
        if !lower.isEmpty, lower.allSatisfy({ $0 == "h" || $0 == "m" || $0 == "s" }) {
          significant += lower
        }
        continue
      }
      significant.append(chars[index])
      index += 1
    }
    let lower = significant.lowercased()
      .replacingOccurrences(of: "am/pm", with: "")
      .replacingOccurrences(of: "a/p", with: "")
    if lower.contains("0") || lower.contains("#") || lower.contains("?") { return false }
    if lower.contains("y") || lower.contains("d") || lower.contains("h") || lower.contains("s") {
      return true
    }
    return lower.contains("m")
  }

  // MARK: - Numbers

  private struct ParsedNumber {
    public var prefix = ""
    public var suffix = ""
    public var body = ""
    public var percent = 0
    public var grouping = false
    public var scale = 0
    public var minInteger = 0
    public var minFraction = 0
    public var maxFraction = 0
    public var scientificPlus: Bool?
    public var scientificDigits = 2
  }

  private static func parseNumber(_ section: String) -> ParsedNumber {
    var parsed = ParsedNumber()
    var stage = 0
    let chars = Array(section)
    var index = 0

    func appendLiteral(_ text: String) {
      if stage == 0 {
        parsed.prefix += text
      } else {
        stage = 2
        parsed.suffix += text
      }
    }

    while index < chars.count {
      let character = chars[index]
      if character == "\"" {
        let quoted = readQuotedLiteral(in: chars, opening: index)
        appendLiteral(quoted.text)
        index = quoted.next
        continue
      }
      if character == "\\" {
        index += 1
        if index < chars.count {
          appendLiteral(String(chars[index]))
          index += 1
        }
        continue
      }
      if character == "_" || character == "*" {
        index += min(2, chars.count - index)
        continue
      }
      if character == "[" {
        var inner = ""
        index += 1
        while index < chars.count, chars[index] != "]" {
          inner.append(chars[index])
          index += 1
        }
        if index < chars.count { index += 1 }
        if inner.hasPrefix("$") {
          let symbolSource = inner.dropFirst()
          let symbol =
            symbolSource.split(separator: "-", maxSplits: 1).first.map(String.init)
            ?? String(symbolSource)
          appendLiteral(symbol)
        }
        continue
      }
      if character == "%" {
        parsed.percent += 1
        appendLiteral("%")
        index += 1
        continue
      }
      if character == "0" || character == "#" || character == "?" || character == "."
        || character == ","
      {
        if stage == 0 { stage = 1 }
        if stage == 1 {
          parsed.body.append(character)
        } else {
          appendLiteral(String(character))
        }
        index += 1
        continue
      }
      if character == "E" || character == "e",
        stage == 1,
        index + 1 < chars.count,
        chars[index + 1] == "+" || chars[index + 1] == "-"
      {
        parsed.body.append(character)
        parsed.body.append(chars[index + 1])
        index += 2
        while index < chars.count, chars[index] == "0" {
          parsed.body.append(chars[index])
          index += 1
        }
        stage = 2
        continue
      }
      if stage == 1 { stage = 2 }
      appendLiteral(String(character))
      index += 1
    }

    analyze(&parsed)
    return parsed
  }

  private static func analyze(_ parsed: inout ParsedNumber) {
    var body = parsed.body
    if let range = body.range(of: "E+", options: .caseInsensitive)
      ?? body.range(of: "E-", options: .caseInsensitive)
    {
      let marker = body[range].uppercased()
      parsed.scientificPlus = marker.hasSuffix("+")
      let exponent = body[range.upperBound...].filter { $0 == "0" }
      parsed.scientificDigits = max(2, exponent.count)
      body = String(body[..<range.lowerBound])
    }
    var integer = body
    var fraction = ""
    if let dot = integer.firstIndex(of: ".") {
      fraction = String(integer[integer.index(after: dot)...])
      integer = String(integer[..<dot])
    }
    if let lastDigit = integer.lastIndex(where: { $0 == "0" || $0 == "#" || $0 == "?" }) {
      let after = integer[integer.index(after: lastDigit)...]
      parsed.scale = after.filter { $0 == "," }.count
      parsed.grouping = integer[..<lastDigit].contains(",")
      parsed.minInteger = integer.filter { $0 == "0" }.count
    } else {
      parsed.scale = integer.filter { $0 == "," }.count
    }
    parsed.minFraction = fraction.filter { $0 == "0" }.count
    parsed.maxFraction = fraction.filter { $0 == "0" || $0 == "#" || $0 == "?" }.count
  }

  private static func formatDigits(_ value: Double, parsed: ParsedNumber, fractionDigits: Int?)
    -> String
  {
    var number = value
    if parsed.percent > 0 {
      number *= pow(100, Double(parsed.percent))
    }
    if parsed.scale > 0 {
      number /= pow(1000, Double(parsed.scale))
    }
    if parsed.scientificPlus != nil {
      return formatScientific(
        number, fraction: fractionDigits ?? parsed.maxFraction, digits: parsed.scientificDigits,
        showPlus: parsed.scientificPlus == true)
    }
    let minFraction = fractionDigits ?? parsed.minFraction
    let maxFraction = fractionDigits ?? max(parsed.maxFraction, parsed.minFraction)
    return formatFixed(
      number, minInteger: max(parsed.minInteger, 1), minFraction: minFraction,
      maxFraction: maxFraction, grouping: parsed.grouping)
  }

  private static func formatFixed(
    _ value: Double,
    minInteger: Int,
    minFraction: Int,
    maxFraction: Int,
    grouping: Bool
  ) -> String {
    let places = max(0, maxFraction)
    let scale = pow(10, Double(places))
    let rounded = (abs(value) * scale).rounded() / scale
    let text = String(format: "%.\(places)f", rounded)
    let pieces = text.split(separator: ".", omittingEmptySubsequences: false)
    var integer = String(pieces.first ?? "0")
    var fraction = pieces.count > 1 ? String(pieces[1]) : ""
    while integer.count < max(minInteger, 1) {
      integer = "0" + integer
    }
    let minimum = max(0, minFraction)
    while fraction.count > minimum, fraction.last == "0" {
      fraction.removeLast()
    }
    if grouping {
      integer = grouped(integer)
    }
    if fraction.isEmpty { return integer }
    return integer + "." + fraction
  }

  private static func grouped(_ integer: String) -> String {
    guard integer.count > 3 else { return integer }
    var digits = Array(integer)
    var groupedDigits: [Character] = []
    var count = 0
    while let digit = digits.popLast() {
      if count == 3 {
        groupedDigits.append(",")
        count = 0
      }
      groupedDigits.append(digit)
      count += 1
    }
    return String(groupedDigits.reversed())
  }

  private static func formatScientific(_ value: Double, fraction: Int, digits: Int, showPlus: Bool)
    -> String
  {
    let places = max(0, fraction)
    if value == 0 {
      let zeros = String(repeating: "0", count: places)
      let exponent = String(repeating: "0", count: max(2, digits))
      let mantissa = places == 0 ? "0" : "0." + zeros
      return mantissa + "E+" + exponent
    }
    let exponent = Int(floor(log10(abs(value))))
    let mantissa = abs(value) / pow(10, Double(exponent))
    let body = formatFixed(
      mantissa, minInteger: 1, minFraction: places, maxFraction: places, grouping: false)
    let sign = exponent < 0 ? "-" : (showPlus ? "+" : "+")
    let width = max(2, digits)
    return body + "E" + sign + String(format: "%0\(width)d", abs(exponent))
  }

  // MARK: - Dates

  private static func formatDate(_ serial: Double, section: String) -> String {
    if let elapsed = elapsedString(serial: serial, pattern: section) {
      return elapsed
    }
    guard let date = ExcelDate.date(from: serial) else {
      return CellValue.number(serial).displayString
    }
    var pattern = dateFormatterPattern(from: section)
    if patternContainsUnquotedAMPM(pattern) {
      // DateFormatter follows the Mac 24-hour clock and drops AM/PM (`h:mm AM/PM` → 17:52).
      // The hour and marker are literals so the code stays 12-hour.
      let hour = ExcelDate.utcComponent(.hour, from: date)
      pattern = patternLocking12HourClock(pattern, hour: hour)
    }
    if let rendered = formatNumericDate(date, pattern: pattern) {
      return rendered
    }
    return dateFormatter(pattern: pattern).string(from: date)
  }

  /// Year, month, day, and time tokens with no month or weekday names.
  /// `DateFormatter` loads an ICU calendar for those patterns; the digits do not need it.
  private static func formatNumericDate(_ date: Date, pattern: String) -> String? {
    let instant = Int(date.timeIntervalSince1970.rounded())
    var days = instant / 86_400
    var time = instant % 86_400
    if time < 0 {
      time += 86_400
      days -= 1
    }
    let civil = civilDate(unixDays: days)
    let hour = time / 3_600
    let minute = (time % 3_600) / 60
    let second = time % 60
    var output = ""
    let chars = Array(pattern)
    var index = 0
    while index < chars.count {
      let character = chars[index]
      if character == "'" {
        index += 1
        while index < chars.count {
          if chars[index] == "'" {
            if index + 1 < chars.count, chars[index + 1] == "'" {
              output.append("'")
              index += 2
              continue
            }
            index += 1
            break
          }
          output.append(chars[index])
          index += 1
        }
        continue
      }
      if character == "y" || character == "M" || character == "d" || character == "H"
        || character == "h" || character == "m" || character == "s"
      {
        var end = index + 1
        while end < chars.count, chars[end] == character { end += 1 }
        let count = end - index
        switch character {
        case "y":
          output += yearDigits(civil.year, count: count)
        case "M":
          if count >= 3 { return nil }
          output += fixedDigits(civil.month, count: count)
        case "d":
          if count >= 3 { return nil }
          output += fixedDigits(civil.day, count: count)
        case "H":
          output += fixedDigits(hour, count: min(count, 2))
        case "h":
          let twelve = hour % 12
          output += fixedDigits(twelve == 0 ? 12 : twelve, count: min(count, 2))
        case "m":
          output += fixedDigits(minute, count: min(count, 2))
        case "s":
          output += fixedDigits(second, count: min(count, 2))
        default:
          return nil
        }
        index = end
        continue
      }
      if character.isLetter { return nil }
      output.append(character)
      index += 1
    }
    return output
  }

  /// Gregorian year, month, and day for a count of days since 1970-01-01.
  private static func civilDate(unixDays: Int) -> (year: Int, month: Int, day: Int) {
    var z = unixDays + 719_468
    let era = (z >= 0 ? z : z - 146_096) / 146_097
    let dayOfEra = z - era * 146_097
    let yearOfEra = (dayOfEra - dayOfEra / 1_460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
    let year = yearOfEra + era * 400
    let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
    let monthPart = (5 * dayOfYear + 2) / 153
    let day = dayOfYear - (153 * monthPart + 2) / 5 + 1
    let month = monthPart + (monthPart < 10 ? 3 : -9)
    return (year + (month <= 2 ? 1 : 0), month, day)
  }

  private static func yearDigits(_ year: Int, count: Int) -> String {
    if count == 2 {
      return fixedDigits(year % 100, count: 2)
    }
    if count >= 4 {
      return fixedDigits(year, count: 4)
    }
    return fixedDigits(year, count: count)
  }

  private static func fixedDigits(_ value: Int, count: Int) -> String {
    let digits = String(value)
    if count <= 1 || digits.count >= count { return digits }
    return String(repeating: "0", count: count - digits.count) + digits
  }

  /// `DateFormatter` rebuilds its ICU calendar on the first string of a new
  /// instance. Tiles format thousands of dates, so each thread keeps one
  /// formatter per pattern. Formatters are not safe to share across threads.
  private static func dateFormatter(pattern: String) -> DateFormatter {
    let key = "com.sparkbysam.SparkGrid.dateFormatter." + pattern
    if let existing = Thread.current.threadDictionary[key] as? DateFormatter {
      return existing
    }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = pattern
    Thread.current.threadDictionary[key] = formatter
    return formatter
  }

  /// `h:mm AM/PM` becomes a pattern with an unquoted `a`. Quoted text such as `"AM"` does not.
  private static func patternContainsUnquotedAMPM(_ pattern: String) -> Bool {
    var quoted = false
    let chars = Array(pattern)
    var index = 0
    while index < chars.count {
      if chars[index] == "'" {
        if quoted, index + 1 < chars.count, chars[index + 1] == "'" {
          index += 2
          continue
        }
        quoted.toggle()
        index += 1
        continue
      }
      if !quoted, chars[index] == "a" || chars[index] == "A" { return true }
      index += 1
    }
    return false
  }

  /// Replaces hour and AM/PM tokens with the 12-hour clock (`5` and `PM`). Other tokens stay.
  private static func patternLocking12HourClock(_ pattern: String, hour: Int) -> String {
    let remainder = hour % 12
    let clock = remainder == 0 ? 12 : remainder
    let marker = hour >= 12 ? "PM" : "AM"
    var output = ""
    let chars = Array(pattern)
    var index = 0
    var quoted = false
    while index < chars.count {
      let character = chars[index]
      if character == "'" {
        if quoted, index + 1 < chars.count, chars[index + 1] == "'" {
          output += "''"
          index += 2
          continue
        }
        quoted.toggle()
        output.append(character)
        index += 1
        continue
      }
      if !quoted, character == "h" || character == "H" {
        var end = index + 1
        while end < chars.count, chars[end] == character { end += 1 }
        let text = (end - index) >= 2 ? String(format: "%02d", clock) : String(clock)
        output += quotedLiteral(text)
        index = end
        continue
      }
      if !quoted, character == "a" || character == "A" {
        var end = index + 1
        while end < chars.count, chars[end] == character { end += 1 }
        output += quotedLiteral(marker)
        index = end
        continue
      }
      output.append(character)
      index += 1
    }
    return output
  }

  private static func elapsedString(serial: Double, pattern: String) -> String? {
    guard pattern.range(of: #"\[h+\]"#, options: [.regularExpression, .caseInsensitive]) != nil
    else { return nil }
    let total = Int((abs(serial) * 86_400).rounded())
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let seconds = total % 60
    let lower = withoutQuotedLiterals(pattern)
    if lower.contains("s") {
      return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }
    if lower.contains("m") {
      return String(format: "%d:%02d", hours, minutes)
    }
    return String(hours)
  }

  private static func dateFormatterPattern(from excel: String) -> String {
    let chars = Array(excel)
    let plain = withoutQuotedLiterals(excel)
    let hasPeriod = plain.contains("am/pm") || plain.contains("a/p")
    var output = ""
    var index = 0

    func starts(with token: String) -> Bool {
      guard index + token.count <= chars.count else { return false }
      return String(chars[index..<(index + token.count)]).caseInsensitiveCompare(token)
        == .orderedSame
    }

    while index < chars.count {
      if starts(with: "AM/PM") {
        output += "a"
        index += 5
        continue
      }
      if starts(with: "A/P") {
        output += "a"
        index += 3
        continue
      }
      let character = chars[index]
      if character == "\"" {
        let quoted = readQuotedLiteral(in: chars, opening: index)
        output += "'"
        for scalar in quoted.text {
          if scalar == "'" { output += "''" } else { output.append(scalar) }
        }
        output += "'"
        index = quoted.next
        continue
      }
      if character == "\\" {
        index += 1
        if index < chars.count {
          output += quotedLiteral(String(chars[index]))
          index += 1
        }
        continue
      }
      if character == "[" {
        var inner = ""
        index += 1
        while index < chars.count, chars[index] != "]" {
          inner.append(chars[index])
          index += 1
        }
        if index < chars.count { index += 1 }
        let lower = inner.lowercased()
        if !lower.isEmpty, lower.allSatisfy({ $0 == "h" || $0 == "m" || $0 == "s" }),
          let first = lower.first
        {
          let token = first == "h" ? (hasPeriod ? "h" : "H") : String(first)
          output += String(repeating: token, count: min(lower.count, 2))
        }
        continue
      }
      if "yYdDhHsSmM".contains(character) {
        let kind = String(character).lowercased()
        var end = index
        while end < chars.count, String(chars[end]).lowercased() == kind { end += 1 }
        let count = end - index
        switch kind {
        case "y":
          output += String(repeating: "y", count: min(count, 4))
        case "d":
          switch count {
          case 1: output += "d"
          case 2: output += "dd"
          case 3: output += "EEE"
          default: output += "EEEE"
          }
        case "h":
          output += String(repeating: hasPeriod ? "h" : "H", count: min(count, 2))
        case "s":
          output += String(repeating: "s", count: min(count, 2))
        case "m":
          if isMinute(chars, start: index, end: end) {
            output += String(repeating: "m", count: min(count, 2))
          } else {
            switch count {
            case 1: output += "M"
            case 2: output += "MM"
            case 3: output += "MMM"
            default: output += "MMMM"
            }
          }
        default:
          break
        }
        index = end
        continue
      }
      if character.isLetter {
        output += quotedLiteral(String(character))
      } else {
        output.append(character)
      }
      index += 1
    }
    return output
  }

  private struct TimeLetter {
    public var index: Int
    public var letter: Character
  }

  /// Date and time letters outside quotes, plus elapsed `[h]` / `[m]` / `[s]`.
  private static func significantTimeLetters(_ chars: [Character]) -> [TimeLetter] {
    var letters: [TimeLetter] = []
    var index = 0
    var quoted = false
    while index < chars.count {
      let character = chars[index]
      if character == "\"" {
        if quoted, index + 1 < chars.count, chars[index + 1] == "\"" {
          index += 2
          continue
        }
        quoted.toggle()
        index += 1
        continue
      }
      if quoted {
        index += 1
        continue
      }
      if character == "\\" {
        index += 2
        continue
      }
      if character == "[" {
        let start = index
        index += 1
        var inner = ""
        while index < chars.count, chars[index] != "]" {
          inner.append(chars[index])
          index += 1
        }
        if index < chars.count { index += 1 }
        let lower = inner.lowercased()
        if let first = lower.first, !lower.isEmpty,
          lower.allSatisfy({ $0 == "h" || $0 == "m" || $0 == "s" })
        {
          letters.append(TimeLetter(index: start, letter: first))
        }
        continue
      }
      let lower = String(character).lowercased()
      if lower == "h" || lower == "m" || lower == "s" || lower == "y" || lower == "d" {
        letters.append(TimeLetter(index: index, letter: Character(lower)))
      }
      index += 1
    }
    return letters
  }

  private static func isMinute(_ chars: [Character], start: Int, end: Int) -> Bool {
    let letters = significantTimeLetters(chars)
    if letters.last(where: { $0.index < start })?.letter == "h" {
      return true
    }
    if letters.first(where: { $0.index >= end })?.letter == "s" {
      return true
    }
    return false
  }

  private static func quotedLiteral(_ text: String) -> String {
    "'" + text.replacingOccurrences(of: "'", with: "''") + "'"
  }
}
