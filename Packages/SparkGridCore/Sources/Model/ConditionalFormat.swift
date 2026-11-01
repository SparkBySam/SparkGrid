import Formula
import Foundation
import GridCore
import NumberFormat

/// Overlay style applied when a conditional formatting rule matches.
/// Only non-nil fields are applied (Excel dxf semantics).
public nonisolated struct ConditionalFormatStyle: Codable, Equatable, Hashable, Sendable {
  public var bold: Bool?
  public var italic: Bool?
  public var textColor: CodableColor?
  public var fillColor: CodableColor?

  public init(
    bold: Bool? = nil,
    italic: Bool? = nil,
    textColor: CodableColor? = nil,
    fillColor: CodableColor? = nil
  ) {
    self.bold = bold
    self.italic = italic
    self.textColor = textColor
    self.fillColor = fillColor
  }

  public static let redFill = ConditionalFormatStyle(
    fillColor: CodableColor(red: 0.96, green: 0.78, blue: 0.78, alpha: 1)
  )

  public static let yellowFill = ConditionalFormatStyle(
    fillColor: CodableColor(red: 1.0, green: 0.95, blue: 0.7, alpha: 1)
  )

  public static let greenFill = ConditionalFormatStyle(
    fillColor: CodableColor(red: 0.78, green: 0.94, blue: 0.78, alpha: 1)
  )

  public static let blueFill = ConditionalFormatStyle(
    fillColor: CodableColor(red: 0.78, green: 0.88, blue: 0.98, alpha: 1)
  )

  public static let orangeFill = ConditionalFormatStyle(
    fillColor: CodableColor(red: 1.0, green: 0.88, blue: 0.72, alpha: 1)
  )

  public static let purpleFill = ConditionalFormatStyle(
    fillColor: CodableColor(red: 0.9, green: 0.82, blue: 0.96, alpha: 1)
  )

  public static let grayFill = ConditionalFormatStyle(
    fillColor: CodableColor(red: 0.88, green: 0.88, blue: 0.9, alpha: 1)
  )

  public func applying(to base: CellFormat) -> CellFormat {
    var result = base
    if let bold { result.bold = bold }
    if let italic { result.italic = italic }
    if let textColor { result.textColor = textColor }
    if let fillColor { result.fillColor = fillColor }
    return result
  }

  public var hasAny: Bool {
    bold != nil || italic != nil || textColor != nil || fillColor != nil
  }

  /// Stores the Bold checkbox on this style.
  /// On records true. Turning a stored true off records false, not nil, so the
  /// uncheck is still off when the rule is reselected or the workbook is reopened.
  /// A style that never set bold stays nil when the checkbox was not touched, so
  /// an unrelated edit does not start forcing bold cells off. Fill, italic, and
  /// text color on `self` are left in place.
  /// Italic (and any similar checkbox) stores on as true and off as nil.
  /// An explicit false from the file stays false, so saving Bold does not drop it.
  public static func preservedCheckbox(isOn: Bool, previous: Bool?) -> Bool? {
    if isOn { return true }
    if previous == false { return false }
    return nil
  }

  public func withBoldCheckbox(isOn: Bool, previous: Bool?, touched: Bool) -> ConditionalFormatStyle
  {
    var copy = self
    if isOn {
      copy.bold = true
    } else if previous == true || touched {
      copy.bold = false
    } else {
      copy.bold = previous
    }
    return copy
  }
}

public nonisolated struct ColorScaleStop: Codable, Equatable, Sendable {
  public enum StopType: String, Codable, Sendable {
    case min
    case max
    case number
    case percent
    case percentile
  }

  public var type: StopType
  public var value: Double?
  public var color: CodableColor

  public init(type: StopType, value: Double?, color: CodableColor) {
    self.type = type
    self.value = value
    self.color = color
  }
}

public nonisolated struct DataBarStyle: Codable, Equatable, Sendable {
  public var color: CodableColor
  public var showValue: Bool

  public init(color: CodableColor, showValue: Bool) {
    self.color = color
    self.showValue = showValue
  }

  public static let blue = DataBarStyle(
    color: CodableColor(red: 0.39, green: 0.58, blue: 0.93, alpha: 1),
    showValue: true
  )

  public static let green = DataBarStyle(
    color: CodableColor(red: 0.39, green: 0.78, blue: 0.47, alpha: 1),
    showValue: true
  )
}

public nonisolated enum IconSetStyle: String, Codable, Sendable, CaseIterable {
  case threeTrafficLights
  case threeArrows
  case threeSymbols

  public var title: String {
    switch self {
    case .threeTrafficLights: return "3 Traffic Lights"
    case .threeArrows: return "3 Arrows"
    case .threeSymbols: return "3 Symbols"
    }
  }

  /// Excel `iconSet` attribute.
  public var excelName: String {
    switch self {
    case .threeTrafficLights: return "3TrafficLights1"
    case .threeArrows: return "3Arrows"
    case .threeSymbols: return "3Symbols"
    }
  }

  public static func fromExcelName(_ name: String) -> IconSetStyle? {
    switch name {
    case "3TrafficLights1", "3TrafficLights2": return .threeTrafficLights
    case "3Arrows", "3ArrowsGray": return .threeArrows
    case "3Symbols", "3Symbols2": return .threeSymbols
    default: return nil
    }
  }
}

public nonisolated enum IconSetGlyph: String, Codable, Sendable {
  case greenCircle, yellowCircle, redCircle
  case greenArrow, yellowArrow, redArrow
  case greenCheck, yellowDash, redX
}

/// Resolved conditional paint for a cell (format overlays + decorations).
public nonisolated struct ConditionalPaint: Equatable, Sendable {
  public var format: CellFormat?
  public var dataBarFraction: Double?
  public var dataBarColor: CodableColor?
  public var dataBarShowValue: Bool = true
  public var icon: IconSetGlyph?

  public init(
    format: CellFormat? = nil,
    dataBarFraction: Double? = nil,
    dataBarColor: CodableColor? = nil,
    dataBarShowValue: Bool = true,
    icon: IconSetGlyph? = nil
  ) {
    self.format = format
    self.dataBarFraction = dataBarFraction
    self.dataBarColor = dataBarColor
    self.dataBarShowValue = dataBarShowValue
    self.icon = icon
  }

  public var hasDecoration: Bool {
    dataBarFraction != nil || icon != nil
  }
}

public nonisolated enum ConditionalFormatPredicate: Codable, Equatable, Sendable {
  case greaterThan(Double)
  case lessThan(Double)
  case greaterOrEqual(Double)
  case lessOrEqual(Double)
  case equal(Double)
  case notEqual(Double)
  case between(Double, Double)
  case notBetween(Double, Double)
  case textContains(String)
  case blanks
  case nonBlanks
  /// Formula relative to the top-left of the rule range (Excel-style).
  case formula(String)
  /// 2- or 3-color scale; style fills come from interpolation, not `rule.style`.
  case colorScale([ColorScaleStop])
  case dataBar(DataBarStyle)
  case iconSet(IconSetStyle)

  public var title: String {
    switch self {
    case .greaterThan(let v): return "Cell value > \(formatNumber(v))"
    case .lessThan(let v): return "Cell value < \(formatNumber(v))"
    case .greaterOrEqual(let v): return "Cell value ≥ \(formatNumber(v))"
    case .lessOrEqual(let v): return "Cell value ≤ \(formatNumber(v))"
    case .equal(let v): return "Cell value = \(formatNumber(v))"
    case .notEqual(let v): return "Cell value ≠ \(formatNumber(v))"
    case .between(let a, let b):
      return "Cell value between \(formatNumber(a)) and \(formatNumber(b))"
    case .notBetween(let a, let b):
      return "Cell value not between \(formatNumber(a)) and \(formatNumber(b))"
    case .textContains(let s): return "Text contains “\(s)”"
    case .blanks: return "Blanks"
    case .nonBlanks: return "Non-blanks"
    case .formula(let f): return "Formula: \(f)"
    case .colorScale(let stops): return "Color scale (\(stops.count) stops)"
    case .dataBar: return "Data bars"
    case .iconSet(let style): return "Icon set: \(style.title)"
    }
  }

  private func formatNumber(_ value: Double) -> String {
    if value.rounded() == value, abs(value) < 1e12 {
      return String(Int(value))
    }
    return String(value)
  }

  public var primaryEditText: String? {
    switch self {
    case .greaterThan(let v), .lessThan(let v), .greaterOrEqual(let v), .lessOrEqual(let v),
      .equal(let v), .notEqual(let v):
      return Self.editNumber(v)
    case .between(let a, _), .notBetween(let a, _):
      return Self.editNumber(a)
    case .textContains(let s):
      return s
    case .formula(let f):
      return f
    case .blanks, .nonBlanks, .colorScale, .dataBar, .iconSet:
      return nil
    }
  }

  public var secondaryEditText: String? {
    switch self {
    case .between(_, let b), .notBetween(_, let b):
      return Self.editNumber(b)
    default:
      return nil
    }
  }

  public var editsValues: Bool {
    switch self {
    case .blanks, .nonBlanks, .colorScale, .dataBar, .iconSet:
      return false
    default:
      return true
    }
  }

  /// Highlight and formula rules paint bold, italic, fill, and text color.
  /// Color scales, data bars, and icon sets do not.
  public var usesFontStyle: Bool {
    switch self {
    case .colorScale, .dataBar, .iconSet:
      return false
    default:
      return true
    }
  }

  public func replacingEditValues(primary: String, secondary: String) -> ConditionalFormatPredicate?
  {
    switch self {
    case .greaterThan:
      guard let v = Self.parseEditNumber(primary) else { return nil }
      return .greaterThan(v)
    case .lessThan:
      guard let v = Self.parseEditNumber(primary) else { return nil }
      return .lessThan(v)
    case .greaterOrEqual:
      guard let v = Self.parseEditNumber(primary) else { return nil }
      return .greaterOrEqual(v)
    case .lessOrEqual:
      guard let v = Self.parseEditNumber(primary) else { return nil }
      return .lessOrEqual(v)
    case .equal:
      guard let v = Self.parseEditNumber(primary) else { return nil }
      return .equal(v)
    case .notEqual:
      guard let v = Self.parseEditNumber(primary) else { return nil }
      return .notEqual(v)
    case .between:
      guard let a = Self.parseEditNumber(primary), let b = Self.parseEditNumber(secondary) else {
        return nil
      }
      return .between(a, b)
    case .notBetween:
      guard let a = Self.parseEditNumber(primary), let b = Self.parseEditNumber(secondary) else {
        return nil
      }
      return .notBetween(a, b)
    case .textContains:
      guard !primary.isEmpty else { return nil }
      return .textContains(primary)
    case .formula:
      var formula = primary.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !formula.isEmpty else { return nil }
      if !formula.hasPrefix("=") { formula = "=\(formula)" }
      return .formula(formula)
    case .blanks, .nonBlanks, .colorScale, .dataBar, .iconSet:
      return self
    }
  }

  private static func editNumber(_ value: Double) -> String {
    if value.rounded() == value, abs(value) < 1e12 {
      return String(Int(value))
    }
    return String(value)
  }

  private static func parseEditNumber(_ raw: String) -> Double? {
    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: ",", with: "")
      .replacingOccurrences(of: "$", with: "")
    return Double(text)
  }
}

public nonisolated struct ConditionalFormatRule: Identifiable, Codable, Equatable, Sendable {
  public var id: UUID
  public var range: CellRange
  public var stopIfTrue: Bool
  public var predicate: ConditionalFormatPredicate
  public var style: ConditionalFormatStyle

  public init(
    id: UUID = UUID(),
    range: CellRange,
    stopIfTrue: Bool = true,
    predicate: ConditionalFormatPredicate,
    style: ConditionalFormatStyle = ConditionalFormatStyle()
  ) {
    self.id = id
    self.range = range
    self.stopIfTrue = stopIfTrue
    self.predicate = predicate
    self.style = style
  }

  public func edited(rangeText: String, primary: String, secondary: String)
    -> ConditionalFormatRule?
  {
    guard let range = CellRange.fromA1(rangeText) else { return nil }
    guard let predicate = predicate.replacingEditValues(primary: primary, secondary: secondary)
    else { return nil }
    var copy = self
    copy.range = range
    copy.predicate = predicate
    return copy
  }
}

public nonisolated enum ConditionalFormatEvaluator {
  /// Resolves base format plus matching conditional overlays for a cell.
  public static func resolvedPaint(
    at address: CellAddress,
    base: CellFormat?,
    rules: [ConditionalFormatRule],
    value: CellValue,
    displayString: String,
    numberFormat: CellFormat.NumberFormat?,
    numericValuesInRange: (CellRange) -> [Double],
    evaluateFormula: (String, CellAddress, CellAddress) -> CellValue
  ) -> ConditionalPaint {
    guard !rules.isEmpty else {
      return ConditionalPaint(format: base)
    }
    var result = base ?? CellFormat()
    var applied = false
    var paint = ConditionalPaint(format: base)

    // `break` inside the switch only ends that case. stopIfTrue has to leave the rule list,
    // or a later match (for example a formula that treats a blank neighbor as 0) repaints the cell.
    ruleList: for rule in rules {
      guard rule.range.contains(address) else { continue }
      let origin = CellAddress(
        row: rule.range.normalized.minRow,
        col: rule.range.normalized.minCol
      )

      switch rule.predicate {
      case .colorScale(let stops):
        guard
          let fill = colorScaleFill(
            stops: stops,
            value: value,
            range: rule.range,
            numericValuesInRange: numericValuesInRange
          )
        else { continue }
        result.fillColor = fill
        applyContrastingText(to: &result, fill: fill, ruleTextColor: rule.style.textColor)
        paint.format = result.isDefault ? nil : result
        applied = true
        if rule.stopIfTrue { break ruleList }

      case .dataBar(let style):
        guard
          let fraction = dataBarFraction(
            value: value,
            range: rule.range,
            numericValuesInRange: numericValuesInRange
          )
        else { continue }
        paint.dataBarFraction = fraction
        paint.dataBarColor = style.color
        paint.dataBarShowValue = style.showValue
        applied = true
        if rule.stopIfTrue { break ruleList }

      case .iconSet(let style):
        guard
          let glyph = iconGlyph(
            style: style,
            value: value,
            range: rule.range,
            numericValuesInRange: numericValuesInRange
          )
        else { continue }
        paint.icon = glyph
        applied = true
        if rule.stopIfTrue { break ruleList }

      default:
        guard
          matches(
            rule.predicate,
            value: value,
            displayString: displayString,
            numberFormat: numberFormat,
            address: address,
            origin: origin,
            evaluateFormula: evaluateFormula
          )
        else { continue }

        let ruleTextColor = rule.style.textColor
        result = rule.style.applying(to: result)
        if let fill = rule.style.fillColor {
          applyContrastingText(to: &result, fill: fill, ruleTextColor: ruleTextColor)
        }
        paint.format = result.isDefault ? nil : result
        applied = true
        if rule.stopIfTrue { break ruleList }
      }
    }

    if !applied {
      return ConditionalPaint(format: base)
    }
    if paint.format == nil, !result.isDefault {
      paint.format = result
    }
    return paint
  }

  /// A conditional fill replaces the cell background, so unreadably light or dark
  /// text (including the dark-mode label color) switches to the opposite.
  /// A text color chosen on the rule itself is left alone.
  private static func applyContrastingText(
    to result: inout CellFormat,
    fill: CodableColor,
    ruleTextColor: CodableColor?
  ) {
    guard ruleTextColor == nil else { return }
    result.textColor = CodableColor.contrastingText(on: fill)
  }

  /// Convenience for callers that only need the format overlay.
  public static func resolvedFormat(
    at address: CellAddress,
    base: CellFormat?,
    rules: [ConditionalFormatRule],
    value: CellValue,
    displayString: String,
    numberFormat: CellFormat.NumberFormat?,
    numericValuesInRange: (CellRange) -> [Double],
    evaluateFormula: (String, CellAddress, CellAddress) -> CellValue
  ) -> CellFormat? {
    resolvedPaint(
      at: address,
      base: base,
      rules: rules,
      value: value,
      displayString: displayString,
      numberFormat: numberFormat,
      numericValuesInRange: numericValuesInRange,
      evaluateFormula: evaluateFormula
    ).format
  }

  public static func matches(
    _ predicate: ConditionalFormatPredicate,
    value: CellValue,
    displayString: String,
    numberFormat: CellFormat.NumberFormat?,
    address: CellAddress,
    origin: CellAddress,
    evaluateFormula: (String, CellAddress, CellAddress) -> CellValue
  ) -> Bool {
    switch predicate {
    case .blanks:
      return value == .blank || displayString.isEmpty
    case .nonBlanks:
      return value != .blank && !displayString.isEmpty
    case .textContains(let needle):
      guard !needle.isEmpty else { return false }
      return displayString.localizedCaseInsensitiveContains(needle)
    case .greaterThan(let n):
      guard let v = compareNumber(value, threshold: n, numberFormat: numberFormat) else {
        return false
      }
      return v.cell > v.threshold
    case .lessThan(let n):
      guard let v = compareNumber(value, threshold: n, numberFormat: numberFormat) else {
        return false
      }
      return v.cell < v.threshold
    case .greaterOrEqual(let n):
      guard let v = compareNumber(value, threshold: n, numberFormat: numberFormat) else {
        return false
      }
      return v.cell >= v.threshold
    case .lessOrEqual(let n):
      guard let v = compareNumber(value, threshold: n, numberFormat: numberFormat) else {
        return false
      }
      return v.cell <= v.threshold
    case .equal(let n):
      guard let v = compareNumber(value, threshold: n, numberFormat: numberFormat) else {
        return false
      }
      return abs(v.cell - v.threshold) < 1e-9
    case .notEqual(let n):
      guard let v = compareNumber(value, threshold: n, numberFormat: numberFormat) else {
        return false
      }
      return abs(v.cell - v.threshold) >= 1e-9
    case .between(let a, let b):
      guard let loPair = compareNumber(value, threshold: a, numberFormat: numberFormat),
        let hiPair = compareNumber(value, threshold: b, numberFormat: numberFormat)
      else { return false }
      let lo = min(loPair.threshold, hiPair.threshold)
      let hi = max(loPair.threshold, hiPair.threshold)
      return loPair.cell >= lo && loPair.cell <= hi
    case .notBetween(let a, let b):
      guard let loPair = compareNumber(value, threshold: a, numberFormat: numberFormat),
        let hiPair = compareNumber(value, threshold: b, numberFormat: numberFormat)
      else { return false }
      let lo = min(loPair.threshold, hiPair.threshold)
      let hi = max(loPair.threshold, hiPair.threshold)
      return loPair.cell < lo || loPair.cell > hi
    case .formula(let raw):
      let result = evaluateFormula(raw, address, origin)
      if case .error = result { return false }
      return result.asBool == true || (result.asNumber ?? 0) != 0
    case .colorScale, .dataBar, .iconSet:
      return false
    }
  }

  /// When the cell is percent-formatted, compare using display percentage (×100)
  /// so a rule “> 50” matches `100%` stored as `1.0`.
  private static func compareNumber(
    _ value: CellValue,
    threshold: Double,
    numberFormat: CellFormat.NumberFormat?
  ) -> (cell: Double, threshold: Double)? {
    guard let raw = value.asNumber else { return nil }
    if numberFormat == .percent {
      return (raw * 100, threshold)
    }
    return (raw, threshold)
  }

  private static func dataBarFraction(
    value: CellValue,
    range: CellRange,
    numericValuesInRange: (CellRange) -> [Double]
  ) -> Double? {
    guard let cellValue = value.asNumber else { return nil }
    let values = numericValuesInRange(range)
    guard !values.isEmpty else { return nil }
    let dataMin = min(0, values.min() ?? 0)
    let dataMax = values.max() ?? cellValue
    let span = dataMax - dataMin
    if span <= 0 { return cellValue > 0 ? 1 : 0 }
    return min(1, max(0, (cellValue - dataMin) / span))
  }

  private static func iconGlyph(
    style: IconSetStyle,
    value: CellValue,
    range: CellRange,
    numericValuesInRange: (CellRange) -> [Double]
  ) -> IconSetGlyph? {
    guard let cellValue = value.asNumber else { return nil }
    let values = numericValuesInRange(range).sorted()
    guard !values.isEmpty else { return nil }
    let p67 = percentile(values, p: 67)
    let p33 = percentile(values, p: 33)
    let tier: Int
    if cellValue >= p67 {
      tier = 0
    } else if cellValue >= p33 {
      tier = 1
    } else {
      tier = 2
    }
    switch style {
    case .threeTrafficLights:
      return [.greenCircle, .yellowCircle, .redCircle][tier]
    case .threeArrows:
      return [.greenArrow, .yellowArrow, .redArrow][tier]
    case .threeSymbols:
      return [.greenCheck, .yellowDash, .redX][tier]
    }
  }

  private static func colorScaleFill(
    stops: [ColorScaleStop],
    value: CellValue,
    range: CellRange,
    numericValuesInRange: (CellRange) -> [Double]
  ) -> CodableColor? {
    guard let cellValue = value.asNumber, stops.count >= 2 else { return nil }
    let values = numericValuesInRange(range)
    guard !values.isEmpty else { return nil }
    let dataMin = values.min() ?? cellValue
    let dataMax = values.max() ?? cellValue
    let resolved = stops.map { stop -> (position: Double, color: CodableColor) in
      let position: Double
      switch stop.type {
      case .min:
        position = dataMin
      case .max:
        position = dataMax
      case .number:
        position = stop.value ?? dataMin
      case .percent:
        let pct = (stop.value ?? 0) / 100
        position = dataMin + (dataMax - dataMin) * pct
      case .percentile:
        position = percentile(values.sorted(), p: stop.value ?? 50)
      }
      return (position, stop.color)
    }.sorted { $0.position < $1.position }

    guard let first = resolved.first, let last = resolved.last else { return nil }
    if cellValue <= first.position { return first.color }
    if cellValue >= last.position { return last.color }
    for index in 0..<(resolved.count - 1) {
      let a = resolved[index]
      let b = resolved[index + 1]
      if cellValue >= a.position && cellValue <= b.position {
        let span = b.position - a.position
        let t = span == 0 ? 0 : (cellValue - a.position) / span
        return interpolate(a.color, b.color, t: t)
      }
    }
    return last.color
  }

  private static func percentile(_ sorted: [Double], p: Double) -> Double {
    guard !sorted.isEmpty else { return 0 }
    let clamped = min(100, max(0, p))
    if sorted.count == 1 { return sorted[0] }
    let rank = (clamped / 100) * Double(sorted.count - 1)
    let lo = Int(rank.rounded(.down))
    let hi = min(sorted.count - 1, lo + 1)
    let frac = rank - Double(lo)
    return sorted[lo] * (1 - frac) + sorted[hi] * frac
  }

  private static func interpolate(_ a: CodableColor, _ b: CodableColor, t: Double) -> CodableColor {
    let u = min(1, max(0, t))
    return CodableColor(
      red: a.red + (b.red - a.red) * u,
      green: a.green + (b.green - a.green) * u,
      blue: a.blue + (b.blue - a.blue) * u,
      alpha: a.alpha + (b.alpha - a.alpha) * u
    )
  }
}
