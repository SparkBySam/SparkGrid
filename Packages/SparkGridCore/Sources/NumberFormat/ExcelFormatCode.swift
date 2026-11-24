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
    switch render(value, code: code, fractionDigits: fractionDigits) {
    case .text(let text): return text
    case .general, .invalid: return nil
    }
  }

  /// Fourth section of a format code (text). Nil when the code has no text section.
  public static func formattedText(_ text: String, code: String) -> String? {
    let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty || trimmed.caseInsensitiveCompare("General") == .orderedSame {
      return nil
    }
    let sections = splitSections(trimmed)
    if sections.count >= 4 { return renderTextSection(sections[3], text: text) }
    // With fewer sections, one with @ in it is for text: TEXT("abc","@@") is abcabc.
    guard let textSection = sections.first(where: isTextPlaceholder) else { return nil }
    return renderTextSection(textSection, text: text)
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

  static func splitSections(_ code: String) -> [String] {
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

  /// A section with `@` in it, outside quotes. A quoted `"@"` is a literal, not this placeholder.
  static func isTextPlaceholder(_ section: String) -> Bool {
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
    // Any section with an unquoted @ shows text: `@@` repeats it, `"Name: "@` labels it.
    return body.contains("@")
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

  static func isDateSection(_ section: String) -> Bool {
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
      // Fractions of a second, as in ss.00, are part of a time.
      .replacingOccurrences(of: #"s\.0+"#, with: "s", options: .regularExpression)
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
}
