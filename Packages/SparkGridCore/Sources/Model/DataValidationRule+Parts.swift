import Foundation
import GridCore

/// A validation rule's parts, read from and written to the attributes and formulas a file
/// stores (`type="whole" operator="between" showErrorMessage="1" ...`, `<formula1>1</formula1>`).
extension DataValidationRule {
  public enum Kind: String, CaseIterable, Sendable {
    case any = "none"
    case whole, decimal, list, date, time, textLength, custom
  }

  public enum Comparison: String, CaseIterable, Sendable {
    case between, notBetween, equal, notEqual, greaterThan, lessThan, greaterThanOrEqual,
      lessThanOrEqual

    /// Whether the rule takes a second value (a maximum).
    public var takesTwo: Bool { self == .between || self == .notBetween }
  }

  public enum AlertStyle: String, CaseIterable, Sendable {
    case stop, warning, information
  }

  /// Everything a rule says, apart from where it applies.
  public struct Parts: Equatable, Sendable {
    public var kind: Kind = .whole
    public var comparison: Comparison = .between
    public var formula1 = ""
    public var formula2 = ""
    public var allowBlank = true
    public var showInput = true
    public var promptTitle = ""
    public var prompt = ""
    public var showError = true
    public var alertStyle: AlertStyle = .stop
    public var errorTitle = ""
    public var error = ""

    public init() {}
  }

  public var parts: Parts {
    var p = Parts()
    let attrs = Self.attributeValues(attributes)
    p.kind = attrs["type"].flatMap(Kind.init(rawValue:)) ?? .any
    p.comparison = attrs["operator"].flatMap(Comparison.init(rawValue:)) ?? .between
    p.allowBlank = Self.flag(attrs["allowBlank"])
    p.showInput = Self.flag(attrs["showInputMessage"])
    p.showError = Self.flag(attrs["showErrorMessage"])
    p.alertStyle = attrs["errorStyle"].flatMap(AlertStyle.init(rawValue:)) ?? .stop
    p.promptTitle = attrs["promptTitle"] ?? ""
    p.prompt = attrs["prompt"] ?? ""
    p.errorTitle = attrs["errorTitle"] ?? ""
    p.error = attrs["error"] ?? ""
    p.formula1 = Self.element("formula1", in: body) ?? ""
    p.formula2 = Self.element("formula2", in: body) ?? ""
    return p
  }

  public init(ranges: [CellRange], parts p: Parts) {
    var attrs: [String] = []
    if p.kind != .any { attrs.append(#"type="\#(p.kind.rawValue)""#) }
    if p.kind != .any, p.kind != .list, p.kind != .custom, p.comparison != .between {
      attrs.append(#"operator="\#(p.comparison.rawValue)""#)
    }
    if p.alertStyle != .stop { attrs.append(#"errorStyle="\#(p.alertStyle.rawValue)""#) }
    if p.allowBlank { attrs.append(#"allowBlank="1""#) }
    if p.showInput { attrs.append(#"showInputMessage="1""#) }
    if p.showError { attrs.append(#"showErrorMessage="1""#) }
    for (name, value) in [
      ("errorTitle", p.errorTitle), ("error", p.error), ("promptTitle", p.promptTitle),
      ("prompt", p.prompt),
    ] where !value.isEmpty {
      attrs.append(#"\#(name)="\#(Self.escape(value))""#)
    }
    var body = ""
    let first = p.formula1.trimmingCharacters(in: .whitespaces)
    let second = p.formula2.trimmingCharacters(in: .whitespaces)
    if p.kind != .any, !first.isEmpty {
      body += "<formula1>\(Self.escape(Self.withoutEquals(first)))</formula1>"
    }
    if p.kind != .any, p.comparison.takesTwo, p.kind != .list, p.kind != .custom,
      !second.isEmpty
    {
      body += "<formula2>\(Self.escape(Self.withoutEquals(second)))</formula2>"
    }
    self.init(ranges: ranges, attributes: attrs.joined(separator: " "), body: body)
  }

  // MARK: - Text

  private static func withoutEquals(_ text: String) -> String {
    text.hasPrefix("=") ? String(text.dropFirst()) : text
  }

  private static func flag(_ value: String?) -> Bool { value == "1" || value == "true" }

  static func attributeValues(_ text: String) -> [String: String] {
    var out: [String: String] = [:]
    let pattern = #"([A-Za-z_:]+)\s*=\s*"([^"]*)""#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return out }
    let ns = text as NSString
    for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
      out[ns.substring(with: match.range(at: 1))] = unescape(ns.substring(with: match.range(at: 2)))
    }
    return out
  }

  static func element(_ name: String, in body: String) -> String? {
    guard let open = body.range(of: "<\(name)>"),
      let close = body.range(of: "</\(name)>", range: open.upperBound..<body.endIndex)
    else { return nil }
    return unescape(String(body[open.upperBound..<close.lowerBound]))
  }

  static func unescape(_ text: String) -> String {
    text.replacingOccurrences(of: "&quot;", with: "\"")
      .replacingOccurrences(of: "&apos;", with: "'")
      .replacingOccurrences(of: "&lt;", with: "<")
      .replacingOccurrences(of: "&gt;", with: ">")
      .replacingOccurrences(of: "&#10;", with: "\n")
      .replacingOccurrences(of: "&amp;", with: "&")
  }

  static func escape(_ text: String) -> String {
    text.replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "\"", with: "&quot;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\n", with: "&#10;")
  }
}
