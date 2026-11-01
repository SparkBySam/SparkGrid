import Foundation
import Model
import NumberFormat

/// How the fill handle continues a run of cells, as other spreadsheet apps do: numbers and dates
/// keep their step, text keeps counting its trailing number, and month and day names go on.
/// Formulas, blanks and plain text are copied instead; that case returns nil.
public enum FillSeries: Equatable, Sendable {
  /// `intercept + slope × k`, where k is the position counted from the first source cell.
  case linear(intercept: Double, slope: Double)
  /// `prefix` then a counter, padded to `width` digits.
  case numberedText(prefix: String, intercept: Double, slope: Double, width: Int)
  /// A name from `names`, stepping `step` names each cell, written in the source's letter case.
  case names(names: [String], start: Int, step: Int, style: LetterCase)

  public enum LetterCase: Equatable, Sendable {
    case capitalized, upper, lower
  }

  /// The series a line of source cells (one column for a fill down, one row for a fill across)
  /// starts, or nil when the cells are copied.
  public static func plan(_ cells: [Cell]) -> FillSeries? {
    guard !cells.isEmpty else { return nil }
    let raws = cells.map { $0.raw.trimmingCharacters(in: .whitespaces) }
    guard raws.allSatisfy({ !$0.isEmpty && !$0.hasPrefix("=") }) else { return nil }

    let numbers = raws.compactMap { Double($0.replacingOccurrences(of: ",", with: "")) }
    if numbers.count == raws.count, numbers.allSatisfy(\.isFinite) {
      if numbers.count >= 2 {
        let (intercept, slope) = fit(numbers)
        return .linear(intercept: intercept, slope: slope)
      }
      // One date or time steps a day. One plain number is copied.
      let kind = cells[0].format?.numberFormat
      if kind == .date, let first = numbers.first {
        return .linear(intercept: first, slope: 1)
      }
      return nil
    }

    if let found = nameSeries(raws) { return found }

    var prefix: String?
    var counters: [Double] = []
    var width = 1
    for raw in raws {
      guard let split = trailingNumber(raw) else { return nil }
      if let prefix, prefix != split.prefix { return nil }
      prefix = split.prefix
      counters.append(split.value)
      width = max(width, split.digits.hasPrefix("0") ? split.digits.count : 1)
    }
    guard let prefix, !prefix.isEmpty, let first = counters.first else { return nil }
    if counters.count == 1 {
      return .numberedText(prefix: prefix, intercept: first, slope: 1, width: width)
    }
    let (intercept, slope) = fit(counters)
    return .numberedText(prefix: prefix, intercept: intercept, slope: slope, width: width)
  }

  /// The raw text of the cell `k` places after the first source cell. Negative `k` fills
  /// up or left.
  public func value(at k: Int) -> String {
    switch self {
    case .linear(let intercept, let slope):
      return Self.numberText(intercept + slope * Double(k))
    case .numberedText(let prefix, let intercept, let slope, let width):
      let counter = abs((intercept + slope * Double(k)).rounded())
      let digits = counter < 1e15 ? String(Int64(counter)) : Self.numberText(counter)
      let padded = String(repeating: "0", count: max(0, width - digits.count)) + digits
      return prefix + padded
    case .names(let names, let start, let step, let style):
      guard !names.isEmpty else { return "" }
      let index = ((start + step * k) % names.count + names.count) % names.count
      let name = names[index]
      switch style {
      case .capitalized: return name
      case .upper: return name.uppercased()
      case .lower: return name.lowercased()
      }
    }
  }

  // MARK: - Helpers

  private static let nameLists: [[String]] = [
    [
      "January", "February", "March", "April", "May", "June", "July", "August", "September",
      "October", "November", "December",
    ],
    ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"],
    ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"],
    ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"],
  ]

  private static func nameSeries(_ raws: [String]) -> FillSeries? {
    for list in nameLists {
      let lowered = list.map { $0.lowercased() }
      let indexes = raws.compactMap { lowered.firstIndex(of: $0.lowercased()) }
      guard indexes.count == raws.count, let start = indexes.first else { continue }
      var step = 1
      if indexes.count >= 2 {
        step = ((indexes[1] - indexes[0]) % list.count + list.count) % list.count
        // Every pair must keep that step, or the names are copied.
        for i in 1..<indexes.count
        where ((indexes[i] - indexes[i - 1]) % list.count + list.count) % list.count != step {
          return nil
        }
        if step == 0 { return nil }
      }
      let sample = raws[0]
      let style: LetterCase =
        sample == sample.uppercased() && sample.count > 1
        ? .upper : sample == sample.lowercased() ? .lower : .capitalized
      return .names(names: list, start: start, step: step, style: style)
    }
    return nil
  }

  private static func trailingNumber(_ raw: String) -> (
    prefix: String, digits: String, value: Double
  )? {
    let digits = String(raw.reversed().prefix { $0.isASCII && $0.isNumber }.reversed())
    guard !digits.isEmpty, digits.count <= 15, let value = Double(digits) else { return nil }
    return (String(raw.dropLast(digits.count)), digits, value)
  }

  /// Least-squares line through (0, y0), (1, y1), …: the same line two cells define exactly.
  private static func fit(_ values: [Double]) -> (intercept: Double, slope: Double) {
    let n = Double(values.count)
    let meanX = (n - 1) / 2
    let meanY = values.reduce(0, +) / n
    var numerator = 0.0
    var denominator = 0.0
    for (i, y) in values.enumerated() {
      let dx = Double(i) - meanX
      numerator += dx * (y - meanY)
      denominator += dx * dx
    }
    let slope = denominator == 0 ? 0 : numerator / denominator
    return (meanY - slope * meanX, slope)
  }

  /// Short text for a number, without binary noise such as 0.30000000000000004.
  static func numberText(_ value: Double) -> String {
    guard value.isFinite else { return "0" }
    let rounded = (value * 1e10).rounded() / 1e10
    if rounded == rounded.rounded(), abs(rounded) < 1e15 {
      return String(Int64(rounded))
    }
    var text = String(format: "%.10f", rounded)
    while text.hasSuffix("0") { text.removeLast() }
    if text.hasSuffix(".") { text.removeLast() }
    return text
  }
}
