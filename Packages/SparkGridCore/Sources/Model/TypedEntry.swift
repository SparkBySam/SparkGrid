import Foundation

/// Numbers and times typed into a cell the way people write them, read as other spreadsheet
/// apps read them: `1,234`, `$1,234.50`, `(5)`, `10:30`, `9:05 am`, `25:00`. Each gives the
/// stored number and the format code the cell shows it with. Checked against Excel 16.115.
public enum TypedEntry {
  public struct Reading: Equatable, Sendable {
    public var value: Double
    /// Nil when the cell keeps General.
    public var formatCode: String?
    public var isTime: Bool
  }

  public static func read(_ text: String) -> Reading? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !trimmed.hasPrefix("=") else { return nil }
    return time(trimmed) ?? number(trimmed)
  }

  // MARK: Numbers

  /// `1,234`, `-1,234`, `1,234.5`, `$1,234.50`, `($5)`, `(5)`. A plain number with no comma,
  /// dollar sign or parentheses is left to the usual reading.
  private static func number(_ text: String) -> Reading? {
    var body = Substring(text)
    var negative = false
    if body.hasPrefix("("), body.hasSuffix(")") {
      negative = true
      body = body.dropFirst().dropLast()
    } else if body.hasPrefix("-") {
      negative = true
      body = body.dropFirst()
    }
    var currency = false
    if body.hasPrefix("$") {
      currency = true
      body = body.dropFirst()
    }
    if !negative, !currency, body.hasPrefix("-") { return nil }
    if currency, !negative, body.hasPrefix("-") {
      negative = true
      body = body.dropFirst()
    }
    let parentheses = text.hasPrefix("(")
    let grouped = body.contains(",")
    guard currency || grouped || parentheses else { return nil }
    guard let digits = groupedDigits(String(body)), let magnitude = Double(digits.plain) else {
      return nil
    }
    let value = negative ? -magnitude : magnitude
    if currency {
      let code =
        digits.hasFraction
        ? "$#,##0.00_);[Red]($#,##0.00)" : "$#,##0_);[Red]($#,##0)"
      return Reading(value: value, formatCode: code, isTime: false)
    }
    if grouped {
      return Reading(
        value: value, formatCode: digits.hasFraction ? "#,##0.00" : "#,##0", isTime: false)
    }
    return Reading(value: value, formatCode: nil, isTime: false)
  }

  /// Digits with commas only between groups of three in the whole part: `1,234.5` but not
  /// `1,23` or `12,34,567`, which stay text in other apps.
  public static func groupedDigits(_ text: String) -> (plain: String, hasFraction: Bool)? {
    let parts = text.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count <= 2, let whole = parts.first, !whole.isEmpty else { return nil }
    let fraction = parts.count == 2 ? parts[1] : ""
    guard fraction.allSatisfy(\.isASCIIDigit) else { return nil }
    let groups = whole.split(separator: ",", omittingEmptySubsequences: false)
    guard let first = groups.first, (1...3).contains(first.count) || groups.count == 1 else {
      return nil
    }
    for (index, group) in groups.enumerated() {
      guard !group.isEmpty, group.allSatisfy(\.isASCIIDigit) else { return nil }
      if index > 0, group.count != 3 { return nil }
    }
    let plain = groups.joined() + (parts.count == 2 ? "." + fraction : "")
    return (plain, parts.count == 2 && !fraction.isEmpty)
  }

  // MARK: Times

  /// `10:30`, `10:30:15`, `9:05 am`, `10:30:15 PM`, `25:00`. A day is 1, so 10:30 is 0.4375.
  /// AM or PM needs the space before it, as in other apps; `10:30PM` stays text.
  private static func time(_ text: String) -> Reading? {
    var clock = Substring(text)
    var meridiem: String?
    let words = text.split(separator: " ")
    if words.count == 2 {
      let mark = words[1].uppercased()
      guard mark == "AM" || mark == "PM" else { return nil }
      meridiem = mark
      clock = words[0]
    } else if words.count != 1 {
      return nil
    }
    let fields = clock.split(separator: ":", omittingEmptySubsequences: false)
    guard (2...3).contains(fields.count),
      fields.allSatisfy({ !$0.isEmpty && $0.count <= 2 && $0.allSatisfy(\.isASCIIDigit) }),
      let hours = Int(fields[0]), let minutes = Int(fields[1])
    else { return nil }
    let seconds = fields.count == 3 ? Int(fields[2]) ?? 0 : 0
    guard fields[1].count == 2, fields.count < 3 || fields[2].count == 2, minutes < 60,
      seconds < 60
    else { return nil }
    var hour = hours
    if let meridiem {
      guard (1...12).contains(hours) else { return nil }
      hour = hours % 12 + (meridiem == "PM" ? 12 : 0)
    }
    let value = Double(hour * 3600 + minutes * 60 + seconds) / 86_400
    let code: String
    if meridiem != nil {
      code = fields.count == 3 ? "h:mm:ss AM/PM" : "h:mm AM/PM"
    } else if hour >= 24 {
      code = "[h]:mm:ss"
    } else {
      code = fields.count == 3 ? "h:mm:ss" : "h:mm"
    }
    return Reading(value: value, formatCode: code, isTime: true)
  }

  /// A stored time as it was typed, for editing: `10:30`, `10:30:15`, `9:05 AM`, `25:00:00`.
  public static func timeText(_ value: Double, formatCode: String) -> String? {
    guard value >= 0, value < 10_000 else { return nil }
    let total = Int((value * 86_400).rounded())
    var hours = total / 3600
    let minutes = total / 60 % 60
    let seconds = total % 60
    let showsSeconds = formatCode.contains("ss")
    var suffix = ""
    if formatCode.uppercased().contains("AM/PM") {
      guard hours < 24 else { return nil }
      suffix = hours >= 12 ? " PM" : " AM"
      hours = hours % 12 == 0 ? 12 : hours % 12
    } else if !formatCode.hasPrefix("[h]"), hours >= 24 {
      return nil
    }
    var text = "\(hours):" + String(format: "%02d", minutes)
    if showsSeconds { text += ":" + String(format: "%02d", seconds) }
    return text + suffix
  }
}

extension Character {
  fileprivate var isASCIIDigit: Bool { isASCII && isNumber }
}
