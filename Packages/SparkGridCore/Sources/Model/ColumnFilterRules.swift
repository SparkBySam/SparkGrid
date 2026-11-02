import Foundation
import GridCore

/// A rule filter on one column: up to two conditions, joined by "all" or "any", or a top or
/// bottom count. Two conditions is what the file format holds, so a rule filter saves and reopens
/// in other spreadsheet apps.
public nonisolated struct ColumnFilterRules: Codable, Equatable, Sendable {
  public enum Kind: String, Codable, CaseIterable, Sendable {
    case equals, notEquals
    case contains, notContains, beginsWith, endsWith
    case greaterThan, greaterOrEqual, lessThan, lessOrEqual
    case between
    case top, bottom

    /// Compares numbers (or dates), not text.
    public var isNumeric: Bool {
      switch self {
      case .greaterThan, .greaterOrEqual, .lessThan, .lessOrEqual, .between, .top, .bottom:
        return true
      default:
        return false
      }
    }

    public var takesSecondValue: Bool { self == .between }
  }

  public struct Rule: Codable, Equatable, Sendable {
    public var kind: Kind
    public var value: String
    public var value2: String

    public init(kind: Kind, value: String, value2: String = "") {
      self.kind = kind
      self.value = value
      self.value2 = value2
    }
  }

  public var rules: [Rule]
  /// True: a row must meet every rule. False: any one is enough.
  public var matchAll: Bool

  public init(rules: [Rule], matchAll: Bool = true) {
    self.rules = Array(rules.prefix(2))
    // With one rule "all" and "any" mean the same; keep one form so a save reads back equal.
    self.matchAll = self.rules.count < 2 ? true : matchAll
  }

  /// The largest and smallest values a top or bottom rule keeps, worked out once per pass.
  public struct Cutoffs: Sendable {
    public var top: Double?
    public var bottom: Double?

    public init(top: Double? = nil, bottom: Double? = nil) {
      self.top = top
      self.bottom = bottom
    }
  }

  /// Cutoffs for this column's top and bottom rules over `numbers` (the column's values).
  public func cutoffs(numbers: [Double]) -> Cutoffs {
    var result = Cutoffs()
    let sorted = numbers.sorted()
    for rule in rules {
      guard let count = Int(rule.value.trimmingCharacters(in: .whitespaces)), count > 0,
        !sorted.isEmpty
      else { continue }
      let n = min(count, sorted.count)
      switch rule.kind {
      case .top: result.top = sorted[sorted.count - n]
      case .bottom: result.bottom = sorted[n - 1]
      default: break
      }
    }
    return result
  }

  /// True when a cell showing `text` passes the rules.
  public func matches(_ text: String, cutoffs: Cutoffs) -> Bool {
    let checks = rules.map { matches(text, rule: $0, cutoffs: cutoffs) }
    guard !checks.isEmpty else { return true }
    return matchAll ? checks.allSatisfy { $0 } : checks.contains(true)
  }

  /// Runs once per row and rule, so each kind does only the work it needs: text rules never
  /// parse numbers, and number rules never lowercase.
  private func matches(_ text: String, rule: Rule, cutoffs: Cutoffs) -> Bool {
    switch rule.kind {
    case .equals, .notEquals:
      let same: Bool
      if let a = Self.number(text), let b = Self.number(rule.value) {
        same = a == b
      } else {
        same = Self.folded(text) == Self.folded(rule.value)
      }
      return rule.kind == .equals ? same : !same
    case .contains, .notContains, .beginsWith, .endsWith:
      let cell = Self.folded(text)
      let wanted = Self.folded(rule.value)
      switch rule.kind {
      case .contains: return cell.contains(wanted)
      case .notContains: return !cell.contains(wanted)
      case .beginsWith: return cell.hasPrefix(wanted)
      default: return cell.hasSuffix(wanted)
      }
    case .greaterThan, .greaterOrEqual, .lessThan, .lessOrEqual:
      guard let a = Self.number(text), let b = Self.number(rule.value) else { return false }
      switch rule.kind {
      case .greaterThan: return a > b
      case .greaterOrEqual: return a >= b
      case .lessThan: return a < b
      default: return a <= b
      }
    case .between:
      guard let a = Self.number(text), let low = Self.number(rule.value),
        let high = Self.number(rule.value2)
      else { return false }
      return a >= min(low, high) && a <= max(low, high)
    case .top:
      guard let cutoff = cutoffs.top, let a = Self.number(text) else { return false }
      return a >= cutoff
    case .bottom:
      guard let cutoff = cutoffs.bottom, let a = Self.number(text) else { return false }
      return a <= cutoff
    }
  }

  /// Text compared without case or surrounding spaces.
  private static func folded(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespaces).lowercased()
  }

  /// A number from shown text: `$1,250.50`, `(300)`, `12%` (as 12) and `-4` all read as numbers.
  public static func number(_ text: String) -> Double? {
    var t = text.trimmingCharacters(in: .whitespaces)
    guard !t.isEmpty else { return nil }
    var negative = false
    if t.hasPrefix("("), t.hasSuffix(")") {
      negative = true
      t = String(t.dropFirst().dropLast())
    }
    // A percent compares as shown: 12% reads as 12, so a rule of 10 means 10%.
    if t.hasSuffix("%") { t.removeLast() }
    // Plain numbers, most cells, skip the copies below.
    if let plain = Double(t), plain.isFinite { return negative ? -plain : plain }
    t.removeAll { $0 == "," || $0 == "$" }
    // "nan" and "inf" are words in a cell, not numbers.
    guard let value = Double(t), value.isFinite else { return negative ? nil : dateSerial(text) }
    return negative ? -value : value
  }

  /// A shown date such as `2/28/2026`, `2026-02-28` or `28-Feb-2026` as a spreadsheet date
  /// serial (days since 30 Dec 1899), so "greater than 1/1/2026" compares dates, not text.
  public static func dateSerial(_ text: String) -> Double? {
    let t = text.trimmingCharacters(in: .whitespaces)
    // Every form read here has a digit and a / or - or space between parts.
    guard t.count >= 6, t.count <= 20, t.contains(where: \.isNumber),
      t.contains(where: { $0 == "/" || $0 == "-" || $0 == " " })
    else { return nil }
    for formatter in dateFormatters {
      if let date = formatter.date(from: t) {
        return (date.timeIntervalSince(serialEpoch) / 86_400).rounded()
      }
    }
    return nil
  }

  /// 30 Dec 1899, day zero of spreadsheet date serials (25,569 days before 1970).
  private static let serialEpoch = Date(timeIntervalSince1970: -2_209_161_600)

  private static let dateFormatters: [DateFormatter] = [
    "M/d/yyyy", "M/d/yy", "yyyy-MM-dd", "d-MMM-yyyy", "d-MMM-yy", "MMM d, yyyy", "MMMM d, yyyy",
  ].map { pattern in
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .gmt
    formatter.dateFormat = pattern
    formatter.isLenient = false
    return formatter
  }
}
