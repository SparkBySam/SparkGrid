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

  private func matches(_ text: String, rule: Rule, cutoffs: Cutoffs) -> Bool {
    let cell = text.trimmingCharacters(in: .whitespaces)
    let wanted = rule.value.trimmingCharacters(in: .whitespaces)
    let lowerCell = cell.lowercased()
    let lowerWanted = wanted.lowercased()
    switch rule.kind {
    case .equals:
      if let a = Self.number(cell), let b = Self.number(wanted) { return a == b }
      return lowerCell == lowerWanted
    case .notEquals:
      if let a = Self.number(cell), let b = Self.number(wanted) { return a != b }
      return lowerCell != lowerWanted
    case .contains: return lowerCell.contains(lowerWanted)
    case .notContains: return !lowerCell.contains(lowerWanted)
    case .beginsWith: return lowerCell.hasPrefix(lowerWanted)
    case .endsWith: return lowerCell.hasSuffix(lowerWanted)
    case .greaterThan, .greaterOrEqual, .lessThan, .lessOrEqual:
      guard let a = Self.number(cell), let b = Self.number(wanted) else { return false }
      switch rule.kind {
      case .greaterThan: return a > b
      case .greaterOrEqual: return a >= b
      case .lessThan: return a < b
      default: return a <= b
      }
    case .between:
      guard let a = Self.number(cell), let low = Self.number(wanted),
        let high = Self.number(rule.value2)
      else { return false }
      return a >= min(low, high) && a <= max(low, high)
    case .top:
      guard let a = Self.number(cell), let cutoff = cutoffs.top else { return false }
      return a >= cutoff
    case .bottom:
      guard let a = Self.number(cell), let cutoff = cutoffs.bottom else { return false }
      return a <= cutoff
    }
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
    t = t.replacingOccurrences(of: ",", with: "")
    t = t.replacingOccurrences(of: "$", with: "")
    guard let value = Double(t) else { return nil }
    return negative ? -value : value
  }
}
