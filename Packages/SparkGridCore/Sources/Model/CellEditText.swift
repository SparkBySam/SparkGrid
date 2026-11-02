import Foundation
import NumberFormat

extension Cell {
  /// The text the formula bar shows and editing starts from. A percent reads as `29.8%` and a
  /// date as `2/28/2026`, as other spreadsheet apps show them, rather than the stored `0.298`
  /// or `46081`. Typing either form back stores the same value.
  public var editableText: String {
    guard let format, !raw.isEmpty, !raw.hasPrefix("="), let value = Double(raw), value.isFinite
    else { return raw }
    switch format.numberFormat {
    case .percent:
      return String(format: "%.10g", locale: Self.posix, value * 100) + "%"
    case .date:
      // Whole days only; a date with a time keeps its stored number.
      guard value >= 1, value == value.rounded(), value < 2_958_466 else { return raw }
      return Self.dateFormatter.string(from: Date(timeIntervalSince1970: (value - 25_569) * 86_400))
    default:
      return raw
    }
  }

  private static let posix = Locale(identifier: "en_US_POSIX")

  private static let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = posix
    formatter.timeZone = .gmt
    formatter.dateFormat = "M/d/yyyy"
    return formatter
  }()
}
