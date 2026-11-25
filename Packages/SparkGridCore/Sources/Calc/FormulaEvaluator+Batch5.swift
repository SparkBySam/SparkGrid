import Formula
import Foundation
import GridCore
import Model

/// Functions batch 5 for 1.7: the probability distributions and their inverses (beta, binomial,
/// chi-squared, exponential, F, gamma, hypergeometric, lognormal, negative binomial, Poisson,
/// Student's t, Weibull), the tests (chi-squared, F, t, z), confidence intervals, PROB and
/// STEYX, and the array functions FREQUENCY, MODE.MULT, LINEST, LOGEST, TREND, GROWTH, MMULT,
/// MINVERSE and MUNIT, with MDETERM. Old names (BINOMDIST, TDIST, ...) are the same functions.
extension FormulaEvaluator {
  /// The array functions in this file. They spill.
  static let statArrayFunctionNames: Set<String> = [
    "FREQUENCY", "MODE.MULT", "LINEST", "LOGEST", "TREND", "GROWTH", "MMULT", "MINVERSE", "MUNIT",
  ]

  func statArray(_ name: String, _ args: [FormulaExpr]) -> ArrayResult? {
    switch name {
    case "FREQUENCY": return frequency(args)
    case "MODE.MULT": return modeMulti(args)
    case "LINEST", "LOGEST": return linest(args, logarithmic: name == "LOGEST")
    case "TREND", "GROWTH": return trend(args, logarithmic: name == "GROWTH")
    case "MMULT": return matrixMultiply(args)
    case "MINVERSE": return matrixInverse(args)
    case "MUNIT":
      guard args.count == 1 else { return Self.fail(.value) }
      let value = evaluate(args[0])
      if case .error(let e) = value { return Self.fail(e) }
      guard let n = value.asNumber else { return Self.fail(.value) }
      let size = Int(n.rounded(.towardZero))
      guard size >= 1, size <= 1000 else { return Self.fail(.value) }
      var values: [CellValue] = []
      values.reserveCapacity(size * size)
      for r in 0..<size {
        for c in 0..<size { values.append(.number(r == c ? 1 : 0)) }
      }
      return ArrayResult(rows: size, cols: size, values: values)
    default: return nil
    }
  }

  /// Handles a batch 5 function, or returns nil when `name` is not one.
  func evalBatch5(_ name: String, _ args: [FormulaExpr]) -> CellValue? {
    switch name {
    // MARK: Binomial family
    case "BINOM.DIST", "BINOMDIST":
      return distribution(args, count: 4, flagAt: 3) { a, cumulative in
        let n = a[1].rounded(.towardZero)
        let k = a[0].rounded(.towardZero)
        guard n >= 0, k >= 0, k <= n, a[2] >= 0, a[2] <= 1 else { return .error(.num) }
        return .number(cumulative ? Self.binomialCDF(k, n, a[2]) : Self.binomialPMF(k, n, a[2]))
      }
    case "BINOM.DIST.RANGE":
      guard args.count == 3 || args.count == 4 else { return .error(.value) }
      return numbers(args) { a in
        let n = a[0].rounded(.towardZero)
        let s = a[2].rounded(.towardZero)
        let s2 = a.count == 4 ? a[3].rounded(.towardZero) : s
        guard n >= 0, a[1] >= 0, a[1] <= 1, s >= 0, s <= n, s2 >= s, s2 <= n else {
          return .error(.num)
        }
        var sum = 0.0
        var k = s
        while k <= s2 {
          sum += Self.binomialPMF(k, n, a[1])
          k += 1
        }
        return .number(sum)
      }
    case "BINOM.INV", "CRITBINOM":
      guard args.count == 3 else { return .error(.value) }
      return numbers(args) { a in
        let n = a[0].rounded(.towardZero)
        guard n >= 0, a[1] >= 0, a[1] <= 1, a[2] > 0, a[2] <= 1 else { return .error(.num) }
        var cdf = 0.0
        var k = 0.0
        while k <= n {
          cdf += Self.binomialPMF(k, n, a[1])
          if cdf >= a[2] * (1 - 1e-15) { return .number(k) }
          k += 1
        }
        return .number(n)
      }
    case "NEGBINOM.DIST", "NEGBINOMDIST":
      let isNew = name == "NEGBINOM.DIST"
      return distribution(args, count: isNew ? 4 : 3, flagAt: isNew ? 3 : nil) { a, cumulative in
        let f = a[0].rounded(.towardZero)
        let s = a[1].rounded(.towardZero)
        let p = a[2]
        guard f >= 0, s >= 1, p >= 0, p <= 1 else { return .error(.num) }
        if cumulative { return .number(Self.betaRegularized(p, s, f + 1)) }
        let log =
          lgamma(f + s) - lgamma(f + 1) - lgamma(s) + s * Foundation.log(p) + f * log1p(-p)
        return .number(p == 1 ? (f == 0 ? 1 : 0) : exp(log))
      }
    case "HYPGEOM.DIST", "HYPGEOMDIST":
      let isNew = name == "HYPGEOM.DIST"
      return distribution(args, count: isNew ? 5 : 4, flagAt: isNew ? 4 : nil) { a, cumulative in
        let k = a[0].rounded(.towardZero)
        let n = a[1].rounded(.towardZero)
        let successes = a[2].rounded(.towardZero)
        let population = a[3].rounded(.towardZero)
        guard k >= 0, n >= 0, successes >= 0, population >= 0, n <= population,
          successes <= population, k <= n, k <= successes,
          n - k <= population - successes
        else { return .error(.num) }
        func pmf(_ i: Double) -> Double {
          guard i >= max(0, n - (population - successes)), i <= min(n, successes) else { return 0 }
          return exp(
            Self.logChoose(successes, i) + Self.logChoose(population - successes, n - i)
              - Self.logChoose(population, n))
        }
        guard cumulative else { return .number(pmf(k)) }
        var sum = 0.0
        var i = 0.0
        while i <= k {
          sum += pmf(i)
          i += 1
        }
        return .number(min(sum, 1))
      }
    case "POISSON.DIST", "POISSON":
      return distribution(args, count: 3, flagAt: 2) { a, cumulative in
        let k = a[0].rounded(.towardZero)
        let mean = a[1]
        guard k >= 0, mean >= 0 else { return .error(.num) }
        if cumulative { return .number(mean == 0 ? 1 : Self.gammaUpperRegularized(k + 1, mean)) }
        if mean == 0 { return .number(k == 0 ? 1 : 0) }
        return .number(exp(k * log(mean) - mean - lgamma(k + 1)))
      }

    // MARK: Continuous distributions
    case "EXPON.DIST", "EXPONDIST":
      return distribution(args, count: 3, flagAt: 2) { a, cumulative in
        guard a[0] >= 0, a[1] > 0 else { return .error(.num) }
        return .number(cumulative ? -expm1(-a[1] * a[0]) : a[1] * exp(-a[1] * a[0]))
      }
    case "WEIBULL.DIST", "WEIBULL":
      return distribution(args, count: 4, flagAt: 3) { a, cumulative in
        let (x, alpha, beta) = (a[0], a[1], a[2])
        guard x >= 0, alpha > 0, beta > 0 else { return .error(.num) }
        let z = pow(x / beta, alpha)
        if cumulative { return .number(-expm1(-z)) }
        return .number(alpha / pow(beta, alpha) * pow(x, alpha - 1) * exp(-z))
      }
    case "GAMMA.DIST", "GAMMADIST":
      return distribution(args, count: 4, flagAt: 3) { a, cumulative in
        let (x, alpha, beta) = (a[0], a[1], a[2])
        guard x >= 0, alpha > 0, beta > 0 else { return .error(.num) }
        if cumulative { return .number(Self.gammaLowerRegularized(alpha, x / beta)) }
        return .number(Self.gammaPDF(x, alpha, beta))
      }
    case "GAMMA.INV", "GAMMAINV":
      guard args.count == 3 else { return .error(.value) }
      return numbers(args) { a in
        let (p, alpha, beta) = (a[0], a[1], a[2])
        guard p >= 0, p < 1, alpha > 0, beta > 0 else { return .error(.num) }
        if p == 0 { return .number(0) }
        return Self.invert(p, low: 0, high: max(1, alpha * beta) * 10, increasing: true) {
          Self.gammaLowerRegularized(alpha, $0 / beta)
        }
      }
    case "CHISQ.DIST":
      return distribution(args, count: 3, flagAt: 2) { a, cumulative in
        let df = a[1].rounded(.towardZero)
        guard a[0] >= 0, df >= 1, df <= 1e10 else { return .error(.num) }
        if cumulative { return .number(Self.gammaLowerRegularized(df / 2, a[0] / 2)) }
        return .number(Self.gammaPDF(a[0], df / 2, 2))
      }
    case "CHISQ.DIST.RT", "CHIDIST":
      guard args.count == 2 else { return .error(.value) }
      return numbers(args) { a in
        let df = a[1].rounded(.towardZero)
        guard a[0] >= 0, df >= 1, df <= 1e10 else { return .error(.num) }
        return .number(Self.gammaUpperRegularized(df / 2, a[0] / 2))
      }
    case "CHISQ.INV", "CHISQ.INV.RT", "CHIINV":
      guard args.count == 2 else { return .error(.value) }
      let right = name != "CHISQ.INV"
      return numbers(args) { a in
        let df = a[1].rounded(.towardZero)
        guard a[0] >= 0, a[0] <= 1, df >= 1, df <= 1e10 else { return .error(.num) }
        let p = right ? 1 - a[0] : a[0]
        if p == 0 { return .number(0) }
        guard p < 1 else { return .error(.num) }
        return Self.invert(a[0], low: 0, high: max(10, df * 10), increasing: !right) {
          right
            ? Self.gammaUpperRegularized(df / 2, $0 / 2)
            : Self.gammaLowerRegularized(df / 2, $0 / 2)
        }
      }
    case "BETA.DIST":
      guard (4...6).contains(args.count) else { return .error(.value) }
      return distribution(Array(args.prefix(3)) + Array(args.dropFirst(4)), flag: args[3]) {
        a, cumulative in
        let low = a.count > 3 ? a[3] : 0
        let high = a.count > 4 ? a[4] : 1
        let (x, alpha, beta) = (a[0], a[1], a[2])
        guard alpha > 0, beta > 0, low < high, x >= low, x <= high else { return .error(.num) }
        let z = (x - low) / (high - low)
        if cumulative { return .number(Self.betaRegularized(z, alpha, beta)) }
        let log =
          (alpha - 1) * Foundation.log(z) + (beta - 1) * log1p(-z) - Self.logBeta(alpha, beta)
        return .number(exp(log) / (high - low))
      }
    case "BETADIST":
      guard (3...5).contains(args.count) else { return .error(.value) }
      return numbers(args) { a in
        let low = a.count > 3 ? a[3] : 0
        let high = a.count > 4 ? a[4] : 1
        guard a[1] > 0, a[2] > 0, low < high, a[0] >= low, a[0] <= high else {
          return .error(.num)
        }
        return .number(Self.betaRegularized((a[0] - low) / (high - low), a[1], a[2]))
      }
    case "BETA.INV", "BETAINV":
      guard (3...5).contains(args.count) else { return .error(.value) }
      return numbers(args) { a in
        let low = a.count > 3 ? a[3] : 0
        let high = a.count > 4 ? a[4] : 1
        let (p, alpha, beta) = (a[0], a[1], a[2])
        guard p >= 0, p <= 1, alpha > 0, beta > 0, low < high else { return .error(.num) }
        let z = Self.invert(p, low: 0, high: 1, increasing: true) {
          Self.betaRegularized($0, alpha, beta)
        }
        guard case .number(let unit) = z else { return z }
        return .number(low + unit * (high - low))
      }
    case "F.DIST":
      return distribution(args, count: 4, flagAt: 3) { a, cumulative in
        let d1 = a[1].rounded(.towardZero)
        let d2 = a[2].rounded(.towardZero)
        guard a[0] >= 0, d1 >= 1, d2 >= 1 else { return .error(.num) }
        if cumulative { return .number(Self.fCDF(a[0], d1, d2)) }
        let x = a[0]
        let log =
          0.5
          * (d1 * Foundation.log(d1 * x) + d2 * Foundation.log(d2)
            - (d1 + d2) * Foundation.log(d1 * x + d2)) - Foundation.log(x)
          - Self.logBeta(d1 / 2, d2 / 2)
        return .number(x == 0 ? (d1 == 2 ? 1 : 0) : exp(log))
      }
    case "F.DIST.RT", "FDIST":
      guard args.count == 3 else { return .error(.value) }
      return numbers(args) { a in
        let d1 = a[1].rounded(.towardZero)
        let d2 = a[2].rounded(.towardZero)
        guard a[0] >= 0, d1 >= 1, d2 >= 1 else { return .error(.num) }
        return .number(Self.fUpper(a[0], d1, d2))
      }
    case "F.INV", "F.INV.RT", "FINV":
      guard args.count == 3 else { return .error(.value) }
      let right = name != "F.INV"
      return numbers(args) { a in
        let d1 = a[1].rounded(.towardZero)
        let d2 = a[2].rounded(.towardZero)
        guard a[0] >= 0, a[0] <= 1, d1 >= 1, d2 >= 1 else { return .error(.num) }
        if (right && a[0] == 1) || (!right && a[0] == 0) { return .number(0) }
        guard (right && a[0] > 0) || (!right && a[0] < 1) else { return .error(.num) }
        // In beta terms, then back: x = d2 z / (d1 (1 - z)).
        let target = right ? 1 - a[0] : a[0]
        let z = Self.invert(target, low: 0, high: 1, increasing: true) {
          Self.betaRegularized($0, d1 / 2, d2 / 2)
        }
        guard case .number(let u) = z, u < 1 else { return .error(.num) }
        return .number(d2 * u / (d1 * (1 - u)))
      }
    case "LOGNORM.DIST":
      return distribution(args, count: 4, flagAt: 3) { a, cumulative in
        let (x, mean, sd) = (a[0], a[1], a[2])
        guard x > 0, sd > 0 else { return .error(.num) }
        let z = (log(x) - mean) / sd
        return .number(cumulative ? Self.normalCDF(z) : Self.normalPDF(z) / (x * sd))
      }
    case "LOGNORMDIST":
      guard args.count == 3 else { return .error(.value) }
      return numbers(args) { a in
        guard a[0] > 0, a[2] > 0 else { return .error(.num) }
        return .number(Self.normalCDF((log(a[0]) - a[1]) / a[2]))
      }
    case "LOGNORM.INV", "LOGINV":
      guard args.count == 3 else { return .error(.value) }
      return numbers(args) { a in
        guard a[0] > 0, a[0] < 1, a[2] > 0 else { return .error(.num) }
        return .number(exp(a[1] + a[2] * Self.normalInverse(a[0])))
      }

    // MARK: Student's t
    case "T.DIST":
      return distribution(args, count: 3, flagAt: 2) { a, cumulative in
        let df = a[1].rounded(.towardZero)
        guard df >= 1 else { return .error(.num) }
        if cumulative { return .number(Self.tCDF(a[0], df)) }
        let log =
          lgamma((df + 1) / 2) - lgamma(df / 2) - 0.5 * Foundation.log(df * .pi)
          - (df + 1) / 2 * log1p(a[0] * a[0] / df)
        return .number(exp(log))
      }
    case "T.DIST.2T", "T.DIST.RT":
      guard args.count == 2 else { return .error(.value) }
      return numbers(args) { a in
        let df = a[1].rounded(.towardZero)
        guard df >= 1 else { return .error(.num) }
        if name == "T.DIST.2T" {
          guard a[0] >= 0 else { return .error(.num) }
          return .number(2 * (1 - Self.tCDF(a[0], df)))
        }
        return .number(1 - Self.tCDF(a[0], df))
      }
    case "TDIST":
      guard args.count == 3 else { return .error(.value) }
      return numbers(args) { a in
        let df = a[1].rounded(.towardZero)
        let tails = a[2].rounded(.towardZero)
        guard a[0] >= 0, df >= 1, tails == 1 || tails == 2 else { return .error(.num) }
        return .number(tails * (1 - Self.tCDF(a[0], df)))
      }
    case "T.INV":
      guard args.count == 2 else { return .error(.value) }
      return numbers(args) { a in
        let df = a[1].rounded(.towardZero)
        guard a[0] > 0, a[0] < 1, df >= 1 else { return .error(.num) }
        return Self.tInverse(a[0], df)
      }
    case "T.INV.2T", "TINV":
      guard args.count == 2 else { return .error(.value) }
      return numbers(args) { a in
        let df = a[1].rounded(.towardZero)
        guard a[0] > 0, a[0] <= 1, df >= 1 else { return .error(.num) }
        guard case .number(let t) = Self.tInverse(1 - a[0] / 2, df) else { return .error(.num) }
        return .number(abs(t))
      }

    // MARK: Tests and intervals
    case "CHISQ.TEST", "CHITEST": return chiSquaredTest(args)
    case "F.TEST", "FTEST":
      guard args.count == 2 else { return .error(.value) }
      let a = numbersIn([args[0]])
      if let error = a.error { return error }
      let b = numbersIn([args[1]])
      if let error = b.error { return error }
      guard let va = Self.variance(a.values, sample: true),
        let vb = Self.variance(b.values, sample: true), va > 0, vb > 0
      else { return .error(.divZero) }
      let f = va / vb
      let cdf = Self.fCDF(f, Double(a.values.count - 1), Double(b.values.count - 1))
      return .number(2 * min(cdf, 1 - cdf))
    case "T.TEST", "TTEST": return tTest(args)
    case "Z.TEST", "ZTEST":
      guard args.count == 2 || args.count == 3 else { return .error(.value) }
      let data = numbersIn([args[0]])
      if let error = data.error { return error }
      let v = data.values
      guard !v.isEmpty else { return .error(.na) }
      return numbers(Array(args.dropFirst())) { a in
        let n = Double(v.count)
        let mean = v.reduce(0, +) / n
        let sd: Double
        if a.count > 1 {
          sd = a[1]
        } else {
          guard let variance = Self.variance(v, sample: true) else { return .error(.divZero) }
          sd = variance.squareRoot()
        }
        guard sd > 0 else { return .error(.divZero) }
        return .number(1 - Self.normalCDF((mean - a[0]) / (sd / n.squareRoot())))
      }
    case "CONFIDENCE.NORM", "CONFIDENCE", "CONFIDENCE.T":
      guard args.count == 3 else { return .error(.value) }
      return numbers(args) { a in
        let alpha = a[0]
        let sd = a[1]
        let n = a[2].rounded(.towardZero)
        guard alpha > 0, alpha < 1, sd > 0, n >= 1 else { return .error(.num) }
        if name == "CONFIDENCE.T" {
          guard n > 1 else { return .error(.divZero) }
          guard case .number(let t) = Self.tInverse(1 - alpha / 2, n - 1) else {
            return .error(.num)
          }
          return .number(t * sd / n.squareRoot())
        }
        return .number(Self.normalInverse(1 - alpha / 2) * sd / n.squareRoot())
      }
    case "PROB": return probability(args)
    case "STEYX":
      guard args.count == 2 else { return .error(.value) }
      let pairs: [(x: Double, y: Double)]
      switch numberPairs(args[1], args[0]) {
      case .failure(let error): return error.value
      case .success(let found): pairs = found
      }
      let n = Double(pairs.count)
      guard n >= 3 else { return .error(.divZero) }
      let mx = pairs.map(\.x).reduce(0, +) / n
      let my = pairs.map(\.y).reduce(0, +) / n
      let sxx = pairs.map { ($0.x - mx) * ($0.x - mx) }.reduce(0, +)
      let syy = pairs.map { ($0.y - my) * ($0.y - my) }.reduce(0, +)
      let sxy = pairs.map { ($0.x - mx) * ($0.y - my) }.reduce(0, +)
      guard sxx > 0 else { return .error(.divZero) }
      return .number(((syy - sxy * sxy / sxx) / (n - 2)).squareRoot())
    case "MDETERM":
      guard args.count == 1 else { return .error(.value) }
      switch numericMatrix(args[0]) {
      case .failure(let box): return box.value
      case .success(let m):
        guard m.rows == m.cols, m.rows > 0 else { return .error(.value) }
        return .number(Self.determinant(m.values, m.rows))
      }
    default:
      return nil
    }
  }

  // MARK: - Argument helpers

  /// Every argument as a number; a blank reads as 0, text that is not a number is #VALUE!.
  private func numbers(_ args: [FormulaExpr], _ body: ([Double]) -> CellValue) -> CellValue {
    var out: [Double] = []
    for arg in args {
      if arg == .missing {
        out.append(0)
        continue
      }
      let value = evaluate(arg)
      switch value {
      case .error: return value
      case .number(let n): out.append(n)
      case .blank: out.append(0)
      case .bool(let b): out.append(b ? 1 : 0)
      case .string(let text):
        guard let n = Double(text.trimmingCharacters(in: .whitespaces)) else {
          return .error(.value)
        }
        out.append(n)
      }
    }
    let result = body(out)
    if case .number(let n) = result, !n.isFinite { return .error(.num) }
    return result
  }

  /// Numbers, with the TRUE/FALSE "cumulative" argument at `flagAt` (nil: always the density
  /// or mass, as in the old names that have no such argument).
  private func distribution(
    _ args: [FormulaExpr], count: Int, flagAt: Int?, _ body: ([Double], Bool) -> CellValue
  ) -> CellValue {
    guard args.count == count else { return .error(.value) }
    guard let flagAt else { return numbers(args) { body($0, false) } }
    var rest = args
    let flag = rest.remove(at: flagAt)
    return distribution(rest, flag: flag, body)
  }

  private func distribution(
    _ args: [FormulaExpr], flag: FormulaExpr, _ body: ([Double], Bool) -> CellValue
  ) -> CellValue {
    let flagValue = evaluate(flag)
    let cumulative: Bool
    switch flagValue {
    case .error: return flagValue
    case .bool(let b): cumulative = b
    case .number(let n): cumulative = n != 0
    case .blank: cumulative = false
    case .string(let s):
      if s.caseInsensitiveCompare("TRUE") == .orderedSame {
        cumulative = true
      } else if s.caseInsensitiveCompare("FALSE") == .orderedSame {
        cumulative = false
      } else {
        return .error(.value)
      }
    }
    return numbers(args) { body($0, cumulative) }
  }

  // MARK: - Special functions

  static func logBeta(_ a: Double, _ b: Double) -> Double {
    lgamma(a) + lgamma(b) - lgamma(a + b)
  }

  static func logChoose(_ n: Double, _ k: Double) -> Double {
    lgamma(n + 1) - lgamma(k + 1) - lgamma(n - k + 1)
  }

  static func binomialPMF(_ k: Double, _ n: Double, _ p: Double) -> Double {
    if p == 0 { return k == 0 ? 1 : 0 }
    if p == 1 { return k == n ? 1 : 0 }
    return exp(logChoose(n, k) + k * log(p) + (n - k) * log1p(-p))
  }

  static func binomialCDF(_ k: Double, _ n: Double, _ p: Double) -> Double {
    if k >= n { return 1 }
    if p == 0 { return 1 }
    if p == 1 { return 0 }
    // I_{1-p}(n-k, k+1).
    return betaRegularized(1 - p, n - k, k + 1)
  }

  /// The regularized incomplete beta function I_x(a, b), by its continued fraction.
  static func betaRegularized(_ x: Double, _ a: Double, _ b: Double) -> Double {
    if x <= 0 { return 0 }
    if x >= 1 { return 1 }
    let front = exp(a * log(x) + b * log1p(-x) - logBeta(a, b))
    if x < (a + 1) / (a + b + 2) {
      return front * betaFraction(x, a, b) / a
    }
    return 1 - front * betaFraction(1 - x, b, a) / b
  }

  private static func betaFraction(_ x: Double, _ a: Double, _ b: Double) -> Double {
    let tiny = 1e-300
    let qab = a + b
    let qap = a + 1
    let qam = a - 1
    var c = 1.0
    var d = 1 - qab * x / qap
    if abs(d) < tiny { d = tiny }
    d = 1 / d
    var h = d
    for m in 1...10_000 {
      let m = Double(m)
      let m2 = 2 * m
      var aa = m * (b - m) * x / ((qam + m2) * (a + m2))
      d = 1 + aa * d
      if abs(d) < tiny { d = tiny }
      c = 1 + aa / c
      if abs(c) < tiny { c = tiny }
      d = 1 / d
      h *= d * c
      aa = -(a + m) * (qab + m) * x / ((a + m2) * (qap + m2))
      d = 1 + aa * d
      if abs(d) < tiny { d = tiny }
      c = 1 + aa / c
      if abs(c) < tiny { c = tiny }
      d = 1 / d
      let delta = d * c
      h *= delta
      if abs(delta - 1) < 1e-16 { break }
    }
    return h
  }

  /// The regularized lower incomplete gamma function P(a, x).
  static func gammaLowerRegularized(_ a: Double, _ x: Double) -> Double {
    if x <= 0 { return 0 }
    if x < a + 1 { return gammaSeries(a, x) }
    return 1 - gammaFraction(a, x)
  }

  /// Q(a, x) = 1 - P(a, x), worked out directly so a small tail keeps its digits.
  static func gammaUpperRegularized(_ a: Double, _ x: Double) -> Double {
    if x <= 0 { return 1 }
    if x < a + 1 { return 1 - gammaSeries(a, x) }
    return gammaFraction(a, x)
  }

  private static func gammaSeries(_ a: Double, _ x: Double) -> Double {
    var sum = 1 / a
    var term = sum
    var ap = a
    for _ in 0..<100_000 {
      ap += 1
      term *= x / ap
      sum += term
      if abs(term) < abs(sum) * 1e-17 { break }
    }
    return sum * exp(-x + a * log(x) - lgamma(a))
  }

  private static func gammaFraction(_ a: Double, _ x: Double) -> Double {
    let tiny = 1e-300
    var b = x + 1 - a
    var c = 1 / tiny
    var d = 1 / b
    var h = d
    for i in 1...100_000 {
      let an = -Double(i) * (Double(i) - a)
      b += 2
      d = an * d + b
      if abs(d) < tiny { d = tiny }
      c = b + an / c
      if abs(c) < tiny { c = tiny }
      d = 1 / d
      let delta = d * c
      h *= delta
      if abs(delta - 1) < 1e-16 { break }
    }
    return exp(-x + a * log(x) - lgamma(a)) * h
  }

  static func gammaPDF(_ x: Double, _ alpha: Double, _ beta: Double) -> Double {
    if x == 0 { return alpha == 1 ? 1 / beta : (alpha < 1 ? .infinity : 0) }
    return exp((alpha - 1) * log(x) - x / beta - lgamma(alpha) - alpha * log(beta))
  }

  static func fCDF(_ x: Double, _ d1: Double, _ d2: Double) -> Double {
    guard x > 0 else { return 0 }
    return betaRegularized(d1 * x / (d1 * x + d2), d1 / 2, d2 / 2)
  }

  static func fUpper(_ x: Double, _ d1: Double, _ d2: Double) -> Double {
    guard x > 0 else { return 1 }
    return betaRegularized(d2 / (d2 + d1 * x), d2 / 2, d1 / 2)
  }

  static func tCDF(_ t: Double, _ df: Double) -> Double {
    let tail = 0.5 * betaRegularized(df / (df + t * t), df / 2, 0.5)
    return t > 0 ? 1 - tail : tail
  }

  static func tInverse(_ p: Double, _ df: Double) -> CellValue {
    if p == 0.5 { return .number(0) }
    // Search on the side the answer is on; the tail is found where it keeps its digits.
    let upper = p > 0.5
    let target = upper ? 1 - p : p
    let found = invert(target, low: 0, high: 1e10, increasing: false) {
      0.5 * betaRegularized(df / (df + $0 * $0), df / 2, 0.5)
    }
    guard case .number(let t) = found else { return found }
    return .number(upper ? t : -t)
  }

  /// The x in [low, high] where `f(x) == target`, for an `f` that only rises (or only falls) on
  /// that span. The span widens when the answer lies beyond it.
  static func invert(
    _ target: Double, low: Double, high: Double, increasing: Bool, _ f: (Double) -> Double
  ) -> CellValue {
    var lo = low
    var hi = high
    func below(_ x: Double) -> Bool { increasing ? f(x) < target : f(x) > target }
    var widen = 0
    while below(hi), widen < 60 {
      lo = hi
      hi *= 2
      widen += 1
    }
    guard !below(hi) else { return .error(.num) }
    for _ in 0..<200 {
      let mid = (lo + hi) / 2
      if mid == lo || mid == hi { break }
      if below(mid) { lo = mid } else { hi = mid }
    }
    return .number((lo + hi) / 2)
  }

  // MARK: - Tests

  private func chiSquaredTest(_ args: [FormulaExpr]) -> CellValue {
    guard args.count == 2 else { return .error(.value) }
    let actual = evaluateArray(args[0])
    let expected = evaluateArray(args[1])
    guard actual.rows == expected.rows, actual.cols == expected.cols else { return .error(.na) }
    var chi = 0.0
    for (a, e) in zip(actual.values, expected.values) {
      if case .error = a { return a }
      if case .error = e { return e }
      guard case .number(let x) = a, case .number(let m) = e else { continue }
      guard m != 0 else { return .error(.divZero) }
      chi += (x - m) * (x - m) / m
    }
    let df: Double =
      actual.rows > 1 && actual.cols > 1
      ? Double((actual.rows - 1) * (actual.cols - 1))
      : Double(actual.rows * actual.cols - 1)
    guard df >= 1 else { return .error(.na) }
    return .number(Self.gammaUpperRegularized(df / 2, chi / 2))
  }

  private func tTest(_ args: [FormulaExpr]) -> CellValue {
    guard args.count == 4 else { return .error(.value) }
    var parts: [Double] = []
    let read = numbers(Array(args.suffix(2))) { a in
      parts = a
      return .number(0)
    }
    if case .error = read { return read }
    let tails = parts[0].rounded(.towardZero)
    let type = parts[1].rounded(.towardZero)
    guard tails == 1 || tails == 2, (1...3).contains(type) else { return .error(.num) }
    let xs: [Double]
    let ys: [Double]
    if type == 1 {
      // Paired: the two ranges must be the same size, and pairs with a non-number drop out.
      switch numberPairs(args[0], args[1]) {
      case .failure(let box): return box.value
      case .success(let pairs):
        xs = pairs.map(\.x)
        ys = pairs.map(\.y)
      }
    } else {
      let a = numbersIn([args[0]])
      if let error = a.error { return error }
      let b = numbersIn([args[1]])
      if let error = b.error { return error }
      xs = a.values
      ys = b.values
    }
    let t: Double
    let df: Double
    switch type {
    case 1:
      let d = zip(xs, ys).map { $0 - $1 }
      guard d.count >= 2, let v = Self.variance(d, sample: true), v > 0 else {
        return .error(.divZero)
      }
      let n = Double(d.count)
      t = d.reduce(0, +) / n / (v / n).squareRoot()
      df = n - 1
    default:
      guard xs.count >= 2, ys.count >= 2, let va = Self.variance(xs, sample: true),
        let vb = Self.variance(ys, sample: true)
      else { return .error(.divZero) }
      let na = Double(xs.count)
      let nb = Double(ys.count)
      let diff = xs.reduce(0, +) / na - ys.reduce(0, +) / nb
      if type == 2 {
        let pooled = ((na - 1) * va + (nb - 1) * vb) / (na + nb - 2)
        guard pooled > 0 else { return .error(.divZero) }
        t = diff / (pooled * (1 / na + 1 / nb)).squareRoot()
        df = na + nb - 2
      } else {
        let sa = va / na
        let sb = vb / nb
        guard sa + sb > 0 else { return .error(.divZero) }
        t = diff / (sa + sb).squareRoot()
        df = (sa + sb) * (sa + sb) / (sa * sa / (na - 1) + sb * sb / (nb - 1))
      }
    }
    let oneTail = 1 - Self.tCDF(abs(t), df)
    return .number(tails * oneTail)
  }

  private func probability(_ args: [FormulaExpr]) -> CellValue {
    guard args.count == 3 || args.count == 4 else { return .error(.value) }
    let xs = evaluateArray(args[0]).values
    let ps = evaluateArray(args[1]).values
    guard xs.count == ps.count else { return .error(.na) }
    return numbers(Array(args.dropFirst(2))) { bounds in
      let lower = bounds[0]
      let upper = bounds.count > 1 ? bounds[1] : lower
      var total = 0.0
      var picked = 0.0
      for (x, p) in zip(xs, ps) {
        guard case .number(let probability) = p else { continue }
        guard probability >= 0, probability <= 1 else { return .error(.num) }
        total += probability
        if case .number(let value) = x, value >= lower, value <= upper { picked += probability }
      }
      guard abs(total - 1) < 1e-7 else { return .error(.num) }
      return .number(picked)
    }
  }

  // MARK: - Array functions

  private func frequency(_ args: [FormulaExpr]) -> ArrayResult {
    guard args.count == 2 else { return Self.fail(.value) }
    let data = numbersIn([args[0]])
    if case .error(let e) = data.error { return Self.fail(e) }
    let bins = numbersIn([args[1]])
    if case .error(let e) = bins.error { return Self.fail(e) }
    let order = bins.values.indices.sorted { bins.values[$0] < bins.values[$1] }
    var counts = [Double](repeating: 0, count: bins.values.count + 1)
    for value in data.values {
      if let slot = order.first(where: { value <= bins.values[$0] }) {
        counts[slot] += 1
      } else {
        counts[bins.values.count] += 1
      }
    }
    return ArrayResult(rows: counts.count, cols: 1, values: counts.map { .number($0) })
  }

  private func modeMulti(_ args: [FormulaExpr]) -> ArrayResult {
    let read = numbersIn(args)
    if case .error(let e) = read.error { return Self.fail(e) }
    var counts: [Double: Int] = [:]
    var order: [Double] = []
    for x in read.values {
      if counts[x] == nil { order.append(x) }
      counts[x, default: 0] += 1
    }
    let best = counts.values.max() ?? 0
    guard best > 1 else { return Self.fail(.na) }
    let modes = order.filter { counts[$0] == best }
    return ArrayResult(rows: modes.count, cols: 1, values: modes.map { .number($0) })
  }

  /// A range or list of numbers with its shape. Text, TRUE and blanks are #VALUE!.
  private func numericMatrix(_ expr: FormulaExpr) -> Result<
    (rows: Int, cols: Int, values: [Double]), ErrorBox
  > {
    let array = evaluateArray(expr)
    var values: [Double] = []
    values.reserveCapacity(array.values.count)
    for value in array.values {
      switch value {
      case .error: return .failure(ErrorBox(value: value))
      case .number(let n): values.append(n)
      default: return .failure(ErrorBox(value: .error(.value)))
      }
    }
    return .success((array.rows, array.cols, values))
  }

  private func matrixMultiply(_ args: [FormulaExpr]) -> ArrayResult {
    guard args.count == 2 else { return Self.fail(.value) }
    let a: (rows: Int, cols: Int, values: [Double])
    let b: (rows: Int, cols: Int, values: [Double])
    switch numericMatrix(args[0]) {
    case .failure(let box): return ArrayResult(box.value)
    case .success(let m): a = m
    }
    switch numericMatrix(args[1]) {
    case .failure(let box): return ArrayResult(box.value)
    case .success(let m): b = m
    }
    guard a.cols == b.rows else { return Self.fail(.value) }
    var out: [CellValue] = []
    out.reserveCapacity(a.rows * b.cols)
    for r in 0..<a.rows {
      for c in 0..<b.cols {
        var sum = 0.0
        for k in 0..<a.cols { sum += a.values[r * a.cols + k] * b.values[k * b.cols + c] }
        out.append(.number(sum))
      }
    }
    return ArrayResult(rows: a.rows, cols: b.cols, values: out)
  }

  private func matrixInverse(_ args: [FormulaExpr]) -> ArrayResult {
    guard args.count == 1 else { return Self.fail(.value) }
    switch numericMatrix(args[0]) {
    case .failure(let box): return ArrayResult(box.value)
    case .success(let m):
      guard m.rows == m.cols, m.rows > 0 else { return Self.fail(.value) }
      guard let inverse = Self.inverse(m.values, m.rows) else { return Self.fail(.num) }
      return ArrayResult(rows: m.rows, cols: m.rows, values: inverse.map { .number($0) })
    }
  }

  /// Gauss-Jordan with partial pivoting; nil for a singular matrix.
  static func inverse(_ values: [Double], _ n: Int) -> [Double]? {
    var a = values
    var inv = [Double](repeating: 0, count: n * n)
    for i in 0..<n { inv[i * n + i] = 1 }
    let scale = values.map(abs).max() ?? 1
    for col in 0..<n {
      var pivot = col
      for r in col..<n where abs(a[r * n + col]) > abs(a[pivot * n + col]) { pivot = r }
      guard abs(a[pivot * n + col]) > scale * 1e-15 else { return nil }
      if pivot != col {
        for c in 0..<n {
          a.swapAt(pivot * n + c, col * n + c)
          inv.swapAt(pivot * n + c, col * n + c)
        }
      }
      let p = a[col * n + col]
      for c in 0..<n {
        a[col * n + c] /= p
        inv[col * n + c] /= p
      }
      for r in 0..<n where r != col {
        let factor = a[r * n + col]
        guard factor != 0 else { continue }
        for c in 0..<n {
          a[r * n + c] -= factor * a[col * n + c]
          inv[r * n + c] -= factor * inv[col * n + c]
        }
      }
    }
    return inv
  }

  static func determinant(_ values: [Double], _ n: Int) -> Double {
    var a = values
    var det = 1.0
    for col in 0..<n {
      var pivot = col
      for r in col..<n where abs(a[r * n + col]) > abs(a[pivot * n + col]) { pivot = r }
      if a[pivot * n + col] == 0 { return 0 }
      if pivot != col {
        for c in 0..<n { a.swapAt(pivot * n + c, col * n + c) }
        det = -det
      }
      let p = a[col * n + col]
      det *= p
      for r in (col + 1)..<max(n, col + 1) {
        let factor = a[r * n + col] / p
        for c in col..<n { a[r * n + c] -= factor * a[col * n + c] }
      }
    }
    return det
  }

  // MARK: - Regression

  /// Known y and x for LINEST, TREND and their log forms: y as one column or row, each x
  /// variable a column (or a row, when y is a row). x left out is 1, 2, 3...
  private struct Regression {
    var ys: [Double]
    /// One row per observation, one column per variable.
    var xs: [[Double]]
    var yIsRow: Bool
  }

  private func regressionInput(_ args: [FormulaExpr], logarithmic: Bool) -> Result<
    Regression, ErrorBox
  > {
    let yMatrix: (rows: Int, cols: Int, values: [Double])
    switch numericMatrix(args[0]) {
    case .failure(let box): return .failure(box)
    case .success(let m): yMatrix = m
    }
    var ys = yMatrix.values
    if logarithmic {
      guard ys.allSatisfy({ $0 > 0 }) else { return .failure(ErrorBox(value: .error(.num))) }
      ys = ys.map(log)
    }
    let n = ys.count
    let yIsRow = yMatrix.rows == 1 && yMatrix.cols > 1
    guard args.count > 1, args[1] != .missing else {
      return .success(Regression(ys: ys, xs: (1...max(n, 1)).map { [Double($0)] }, yIsRow: yIsRow))
    }
    let x: (rows: Int, cols: Int, values: [Double])
    switch numericMatrix(args[1]) {
    case .failure(let box): return .failure(box)
    case .success(let m): x = m
    }
    var rows: [[Double]] = []
    if yMatrix.rows == 1 || yMatrix.cols == 1 {
      if x.rows * x.cols == n {
        rows = x.values.map { [$0] }
      } else if !yIsRow, x.rows == n {
        rows = (0..<n).map { r in (0..<x.cols).map { x.values[r * x.cols + $0] } }
      } else if yIsRow, x.cols == n {
        rows = (0..<n).map { c in (0..<x.rows).map { x.values[$0 * x.cols + c] } }
      } else {
        return .failure(ErrorBox(value: .error(.ref)))
      }
    } else {
      guard x.rows == yMatrix.rows, x.cols == yMatrix.cols else {
        return .failure(ErrorBox(value: .error(.ref)))
      }
      rows = x.values.map { [$0] }
    }
    return .success(Regression(ys: ys, xs: rows, yIsRow: yIsRow))
  }

  /// Least squares: the coefficients for each variable, then the intercept (0 without one),
  /// and the inverse of XᵀX for the standard errors. Nil when the fit cannot be made.
  private static func leastSquares(_ input: Regression, constant: Bool) -> (
    coefficients: [Double], intercept: Double, inverse: [Double], columns: Int
  )? {
    let k = input.xs.first?.count ?? 0
    let p = k + (constant ? 1 : 0)
    let n = input.ys.count
    guard n > 0, p > 0 else { return nil }
    var xtx = [Double](repeating: 0, count: p * p)
    var xty = [Double](repeating: 0, count: p)
    for (row, y) in zip(input.xs, input.ys) {
      let full = constant ? row + [1] : row
      for i in 0..<p {
        xty[i] += full[i] * y
        for j in 0..<p { xtx[i * p + j] += full[i] * full[j] }
      }
    }
    guard let inv = inverse(xtx, p) else { return nil }
    var beta = [Double](repeating: 0, count: p)
    for i in 0..<p {
      for j in 0..<p { beta[i] += inv[i * p + j] * xty[j] }
    }
    return (Array(beta.prefix(k)), constant ? beta[k] : 0, inv, p)
  }

  private func flagArgument(_ args: [FormulaExpr], at index: Int, default value: Bool)
    -> Result<Bool, ErrorBox>
  {
    guard index < args.count, args[index] != .missing else { return .success(value) }
    switch evaluate(args[index]) {
    case .error(let e): return .failure(ErrorBox(value: .error(e)))
    case .bool(let b): return .success(b)
    case .number(let n): return .success(n != 0)
    case .blank: return .success(value)
    case .string: return .failure(ErrorBox(value: .error(.value)))
    }
  }

  private func linest(_ args: [FormulaExpr], logarithmic: Bool) -> ArrayResult {
    guard (1...4).contains(args.count) else { return Self.fail(.value) }
    let input: Regression
    switch regressionInput(args, logarithmic: logarithmic) {
    case .failure(let box): return ArrayResult(box.value)
    case .success(let r): input = r
    }
    let constant: Bool
    let stats: Bool
    switch flagArgument(args, at: 2, default: true) {
    case .failure(let box): return ArrayResult(box.value)
    case .success(let b): constant = b
    }
    switch flagArgument(args, at: 3, default: false) {
    case .failure(let box): return ArrayResult(box.value)
    case .success(let b): stats = b
    }
    guard let fit = Self.leastSquares(input, constant: constant) else { return Self.fail(.num) }
    let k = fit.coefficients.count
    let cols = k + 1
    func shown(_ x: Double) -> CellValue { .number(logarithmic ? exp(x) : x) }
    var first: [CellValue] = fit.coefficients.reversed().map(shown)
    first.append(constant ? shown(fit.intercept) : .number(logarithmic ? 1 : 0))
    guard stats else { return ArrayResult(rows: 1, cols: cols, values: first) }
    let n = Double(input.ys.count)
    let df = n - Double(fit.columns)
    var ssResid = 0.0
    var ssReg = 0.0
    let mean = input.ys.reduce(0, +) / n
    for (row, y) in zip(input.xs, input.ys) {
      let fitted = zip(row, fit.coefficients).map(*).reduce(0, +) + fit.intercept
      ssResid += (y - fitted) * (y - fitted)
      ssReg += constant ? (fitted - mean) * (fitted - mean) : fitted * fitted
    }
    let na = CellValue.error(.na)
    let sey2 = df > 0 ? ssResid / df : .nan
    var errors: [CellValue] = (0..<k).reversed().map { i in
      df > 0 ? .number((fit.inverse[i * fit.columns + i] * sey2).squareRoot()) : na
    }
    errors.append(
      constant && df > 0 ? .number((fit.inverse[k * fit.columns + k] * sey2).squareRoot()) : na)
    let r2 = ssReg + ssResid > 0 ? ssReg / (ssReg + ssResid) : 1
    func padded(_ a: CellValue, _ b: CellValue) -> [CellValue] {
      [a, b] + [CellValue](repeating: na, count: max(0, cols - 2))
    }
    let fStat: CellValue =
      df > 0 && ssResid > 0 ? .number((ssReg / Double(k)) / (ssResid / df)) : .error(.num)
    let rows: [[CellValue]] = [
      first, errors,
      padded(.number(r2), df > 0 ? .number(sey2.squareRoot()) : na),
      padded(fStat, .number(df)),
      padded(.number(ssReg), .number(ssResid)),
    ]
    // With one column there is no room for the second value of rows 3 to 5.
    let values = rows.flatMap { Array($0.prefix(cols)) }
    return ArrayResult(rows: 5, cols: cols, values: values)
  }

  private func trend(_ args: [FormulaExpr], logarithmic: Bool) -> ArrayResult {
    guard (1...4).contains(args.count) else { return Self.fail(.value) }
    let input: Regression
    switch regressionInput(args, logarithmic: logarithmic) {
    case .failure(let box): return ArrayResult(box.value)
    case .success(let r): input = r
    }
    let constant: Bool
    switch flagArgument(args, at: 3, default: true) {
    case .failure(let box): return ArrayResult(box.value)
    case .success(let b): constant = b
    }
    guard let fit = Self.leastSquares(input, constant: constant) else { return Self.fail(.num) }
    let k = fit.coefficients.count
    // New x: given, or the known x again, in the shape it came in.
    var points: [[Double]]
    var shape: (rows: Int, cols: Int)
    if args.count > 2, args[2] != .missing {
      let m: (rows: Int, cols: Int, values: [Double])
      switch numericMatrix(args[2]) {
      case .failure(let box): return ArrayResult(box.value)
      case .success(let found): m = found
      }
      if k == 1 {
        points = m.values.map { [$0] }
        shape = (m.rows, m.cols)
      } else if !input.yIsRow, m.cols == k {
        points = (0..<m.rows).map { r in (0..<k).map { m.values[r * m.cols + $0] } }
        shape = (m.rows, 1)
      } else if input.yIsRow, m.rows == k {
        points = (0..<m.cols).map { c in (0..<k).map { m.values[$0 * m.cols + c] } }
        shape = (1, m.cols)
      } else {
        return Self.fail(.ref)
      }
    } else {
      points = input.xs
      shape = input.yIsRow ? (1, points.count) : (points.count, 1)
    }
    let values: [CellValue] = points.map { row in
      let y = zip(row, fit.coefficients).map(*).reduce(0, +) + fit.intercept
      return .number(logarithmic ? exp(y) : y)
    }
    return ArrayResult(rows: shape.rows, cols: shape.cols, values: values)
  }
}
