import Foundation

/// Builtin number-format category. Custom format codes live beside this value.
public enum NumberFormatKind: String, Codable, Hashable, Sendable {
  case general, number, currency, percent, scientific, date, time
}
