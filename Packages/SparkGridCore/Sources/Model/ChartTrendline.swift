import Foundation

/// A line fitted through a chart series, as other spreadsheet apps draw one: straight, curved,
/// or a moving average, with its equation and R² shown if asked for.
public nonisolated struct ChartTrendline: Codable, Equatable, Sendable {
  public enum Kind: String, Codable, Sendable, CaseIterable, Identifiable {
    case linear
    case exponential
    case logarithmic
    case power
    case movingAverage

    public var id: String { rawValue }

    public var title: String {
      switch self {
      case .linear: return "Linear"
      case .exponential: return "Exponential"
      case .logarithmic: return "Logarithmic"
      case .power: return "Power"
      case .movingAverage: return "Moving Average"
      }
    }

    /// The name the chart file format uses.
    public var fileName: String {
      switch self {
      case .linear: return "linear"
      case .exponential: return "exp"
      case .logarithmic: return "log"
      case .power: return "power"
      case .movingAverage: return "movingAvg"
      }
    }

    public init?(fileName: String) {
      guard let kind = Self.allCases.first(where: { $0.fileName == fileName }) else { return nil }
      self = kind
    }
  }

  public var kind: Kind
  /// Points averaged by a moving average; at least 2.
  public var period: Int
  public var showsEquation: Bool
  public var showsRSquared: Bool

  public init(
    kind: Kind = .linear, period: Int = 2, showsEquation: Bool = false,
    showsRSquared: Bool = false
  ) {
    self.kind = kind
    self.period = max(2, period)
    self.showsEquation = showsEquation
    self.showsRSquared = showsRSquared
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .linear
    period = max(2, try c.decodeIfPresent(Int.self, forKey: .period) ?? 2)
    showsEquation = try c.decodeIfPresent(Bool.self, forKey: .showsEquation) ?? false
    showsRSquared = try c.decodeIfPresent(Bool.self, forKey: .showsRSquared) ?? false
  }

  /// A fitted curve: `y = value(x)` for the regressions, or the averaged points.
  public struct Fit: Equatable, Sendable {
    public var kind: Kind
    /// For linear `a + b·x`, exponential `a·e^(b·x)`, logarithmic `a + b·ln(x)`, power `a·x^b`.
    public var a: Double
    public var b: Double
    public var rSquared: Double?
    /// Moving average points as (x, y).
    public var averages: [(x: Double, y: Double)]

    public static func == (lhs: Fit, rhs: Fit) -> Bool {
      lhs.kind == rhs.kind && lhs.a == rhs.a && lhs.b == rhs.b && lhs.rSquared == rhs.rSquared
        && lhs.averages.map(\.x) == rhs.averages.map(\.x)
        && lhs.averages.map(\.y) == rhs.averages.map(\.y)
    }

    public func value(at x: Double) -> Double? {
      let y: Double
      switch kind {
      case .linear: y = a + b * x
      case .exponential: y = a * exp(b * x)
      case .logarithmic:
        guard x > 0 else { return nil }
        y = a + b * log(x)
      case .power:
        guard x > 0 else { return nil }
        y = a * pow(x, b)
      case .movingAverage:
        return nil
      }
      return y.isFinite ? y : nil
    }

    /// `y = 2.5x + 1.2`, `y = 3e^(0.2x)`, `y = 1.5ln(x) + 4`, `y = 2x^0.5`, as the other apps
    /// write them. Nil for a moving average, which has no equation.
    public var equation: String? {
      func n(_ v: Double) -> String { Fit.number(v) }
      func signed(_ v: Double) -> String { v < 0 ? " - \(n(-v))" : " + \(n(v))" }
      switch kind {
      case .linear: return "y = \(n(b))x\(signed(a))"
      case .exponential: return "y = \(n(a))e^(\(n(b))x)"
      case .logarithmic: return "y = \(n(b))ln(x)\(signed(a))"
      case .power: return "y = \(n(a))x^\(n(b))"
      case .movingAverage: return nil
      }
    }

    static func number(_ v: Double) -> String {
      if v == 0 { return "0" }
      let magnitude = abs(v)
      if magnitude >= 1e6 || magnitude < 1e-4 {
        return String(format: "%.4g", v)
      }
      let digits = magnitude >= 100 ? 2 : 4
      var text = String(format: "%.\(digits)f", v)
      while text.contains("."), text.hasSuffix("0") { text.removeLast() }
      if text.hasSuffix(".") { text.removeLast() }
      return text
    }
  }

  /// Fits this trendline through the points. Category charts pass x = 1, 2, 3…, as the other
  /// apps do. Points a curve cannot take (x ≤ 0 for logarithmic and power, y ≤ 0 for
  /// exponential and power) leave the fit out, as those apps refuse such a trendline.
  public func fit(x xs: [Double], y ys: [Double]) -> Fit? {
    let pairs = zip(xs, ys).filter { $0.0.isFinite && $0.1.isFinite }
    if kind == .movingAverage {
      guard pairs.count >= period else { return nil }
      var averages: [(x: Double, y: Double)] = []
      for end in (period - 1)..<pairs.count {
        let window = pairs[(end - period + 1)...end]
        averages.append((pairs[end].0, window.reduce(0) { $0 + $1.1 } / Double(period)))
      }
      return Fit(kind: kind, a: 0, b: 0, rSquared: nil, averages: averages)
    }
    guard pairs.count >= 2 else { return nil }
    // Each curve is a straight line through transformed points.
    var tx: [Double] = []
    var ty: [Double] = []
    for (x, y) in pairs {
      switch kind {
      case .linear:
        tx.append(x)
        ty.append(y)
      case .exponential:
        guard y > 0 else { return nil }
        tx.append(x)
        ty.append(log(y))
      case .logarithmic:
        guard x > 0 else { return nil }
        tx.append(log(x))
        ty.append(y)
      case .power:
        guard x > 0, y > 0 else { return nil }
        tx.append(log(x))
        ty.append(log(y))
      case .movingAverage:
        return nil
      }
    }
    let count = Double(tx.count)
    let meanX = tx.reduce(0, +) / count
    let meanY = ty.reduce(0, +) / count
    var sxx = 0.0
    var sxy = 0.0
    var syy = 0.0
    for (x, y) in zip(tx, ty) {
      sxx += (x - meanX) * (x - meanX)
      sxy += (x - meanX) * (y - meanY)
      syy += (y - meanY) * (y - meanY)
    }
    guard sxx > 0 else { return nil }
    let slope = sxy / sxx
    let intercept = meanY - slope * meanX
    // R² of the straight-line fit on the transformed values, as the other apps report it.
    let rSquared = syy > 0 ? (sxy * sxy) / (sxx * syy) : 1
    let a: Double
    switch kind {
    case .exponential, .power: a = exp(intercept)
    default: a = intercept
    }
    guard a.isFinite, slope.isFinite else { return nil }
    return Fit(kind: kind, a: a, b: slope, rSquared: rSquared, averages: [])
  }
}
