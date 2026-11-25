import Formula
import Foundation
import GridCore
import Model

/// Functions batch 3 for 1.5: trigonometry and more math, the A statistics, means and spread,
/// the normal distribution, percent rank, text formatting, time and date text, type tests,
/// depreciation and interest.
extension FormulaEvaluator {
  /// Handles a batch 3 function, or returns nil when `name` is not one.
  func evalBatch3(_ name: String, _ args: [FormulaExpr]) -> CellValue? {
    switch name {
    // MARK: Trigonometry
    case "SIN": return oneNumber(args) { .number(sin($0)) }
    case "COS": return oneNumber(args) { .number(cos($0)) }
    case "TAN": return oneNumber(args) { .number(tan($0)) }
    case "ASIN": return oneNumber(args) { abs($0) <= 1 ? .number(asin($0)) : .error(.num) }
    case "ACOS": return oneNumber(args) { abs($0) <= 1 ? .number(acos($0)) : .error(.num) }
    case "ATAN": return oneNumber(args) { .number(atan($0)) }
    case "SINH": return oneNumber(args) { Self.finite(sinh($0)) }
    case "COSH": return oneNumber(args) { Self.finite(cosh($0)) }
    case "TANH": return oneNumber(args) { .number(tanh($0)) }
    case "ASINH": return oneNumber(args) { .number(asinh($0)) }
    case "ACOSH": return oneNumber(args) { $0 >= 1 ? .number(acosh($0)) : .error(.num) }
    case "ATANH": return oneNumber(args) { abs($0) < 1 ? .number(atanh($0)) : .error(.num) }
    case "ATAN2":
      // ATAN2(x, y): the angle of the point (x, y).
      return twoNumbers(args) { x, y in
        x == 0 && y == 0 ? .error(.divZero) : .number(atan2(y, x))
      }
    case "DEGREES": return oneNumber(args) { .number($0 * 180 / .pi) }
    case "RADIANS": return oneNumber(args) { .number($0 * .pi / 180) }
    case "SQRTPI":
      return oneNumber(args) { $0 >= 0 ? .number(($0 * .pi).squareRoot()) : .error(.num) }

    // MARK: Math
    case "COMBIN", "PERMUT":
      return twoNumbers(args) { n, k in
        let n = n.rounded(.towardZero)
        let k = k.rounded(.towardZero)
        guard n >= 0, k >= 0, n >= k else { return .error(.num) }
        var result = 1.0
        let steps = name == "COMBIN" ? min(k, n - k) : k
        var i = 0.0
        while i < steps {
          result *= (n - i)
          if name == "COMBIN" { result /= (i + 1) }
          i += 1
        }
        return Self.finite(name == "COMBIN" ? result.rounded() : result)
      }
    case "QUOTIENT":
      return twoNumbers(args) { n, d in
        d == 0 ? .error(.divZero) : .number((n / d).rounded(.towardZero))
      }
    case "RAND":
      guard args.isEmpty else { return .error(.value) }
      return .number(Double.random(in: 0..<1))
    case "RANDBETWEEN":
      return twoNumbers(args) { low, high in
        let lo = low.rounded(.up)
        let hi = high.rounded(.down)
        guard lo <= hi, abs(lo) < 1e15, abs(hi) < 1e15 else { return .error(.num) }
        return .number(Double(Int.random(in: Int(lo)...Int(hi))))
      }

    // MARK: Statistics
    case "AVERAGEA", "MAXA", "MINA", "STDEVA", "STDEVPA", "VARA", "VARPA":
      let values = aValues(args)
      if let error = values.error { return error }
      let v = values.values
      switch name {
      case "AVERAGEA":
        return v.isEmpty ? .error(.divZero) : .number(v.reduce(0, +) / Double(v.count))
      case "MAXA": return .number(v.max() ?? 0)
      case "MINA": return .number(v.min() ?? 0)
      default:
        let sample = !name.contains("P")
        guard let variance = Self.variance(v, sample: sample) else { return .error(.divZero) }
        return .number(name.hasPrefix("STDEV") ? variance.squareRoot() : variance)
      }
    // Spark Grid's own names (SparkOnlyFunctions): calculated exactly as the formula a file
    // stores for them, so the result is the same in every app.
    case "SEM":
      return evaluate(
        .binary(
          .divide, .call("STDEV.S", args), .call("SQRT", [.call("COUNT", args)])))
    case "MEAN", "MEAN.ARITH":
      return evaluate(.call("AVERAGE", args))
    case "MEAN.GEOM":
      return evaluate(.call("GEOMEAN", args))
    case "MEAN.HARM":
      return evaluate(.call("HARMEAN", args))
    case "GEOMEAN", "HARMEAN":
      let numbers = numbersIn(args)
      if let error = numbers.error { return error }
      let v = numbers.values
      guard !v.isEmpty, v.allSatisfy({ $0 > 0 }) else { return .error(.num) }
      if name == "GEOMEAN" {
        return .number(exp(v.map(log).reduce(0, +) / Double(v.count)))
      }
      return .number(Double(v.count) / v.map { 1 / $0 }.reduce(0, +))
    case "DEVSQ", "AVEDEV":
      let numbers = numbersIn(args)
      if let error = numbers.error { return error }
      let v = numbers.values
      guard !v.isEmpty else { return name == "DEVSQ" ? .error(.num) : .error(.num) }
      let mean = v.reduce(0, +) / Double(v.count)
      if name == "DEVSQ" { return .number(v.map { ($0 - mean) * ($0 - mean) }.reduce(0, +)) }
      return .number(v.map { abs($0 - mean) }.reduce(0, +) / Double(v.count))
    case "SKEW", "SKEW.P", "KURT":
      let numbers = numbersIn(args)
      if let error = numbers.error { return error }
      return Self.shape(name, numbers.values)
    case "TRIMMEAN":
      guard args.count == 2 else { return .error(.value) }
      let numbers = numbersIn([args[0]])
      if let error = numbers.error { return error }
      let percent = evaluate(args[1])
      if case .error = percent { return percent }
      guard let p = percent.asNumber, p >= 0, p < 1, !numbers.values.isEmpty else {
        return .error(.num)
      }
      let sorted = numbers.values.sorted()
      // Leave out an even number of values, half from each end, rounded down.
      let cut = Int((Double(sorted.count) * p / 2).rounded(.down))
      let kept = sorted[cut..<(sorted.count - cut)]
      return .number(kept.reduce(0, +) / Double(kept.count))
    case "STANDARDIZE":
      return numbersExactly(args, 3) { a in
        a[2] > 0 ? .number((a[0] - a[1]) / a[2]) : .error(.num)
      }
    case "FISHER":
      return oneNumber(args) {
        abs($0) < 1 ? .number(0.5 * log((1 + $0) / (1 - $0))) : .error(.num)
      }
    case "FISHERINV": return oneNumber(args) { .number(tanh($0)) }
    case "COVARIANCE.S", "COVARIANCE.P", "COVAR", "PEARSON", "RSQ":
      guard args.count == 2 else { return .error(.value) }
      let pairs: [(x: Double, y: Double)]
      switch numberPairs(args[0], args[1]) {
      case .failure(let error): return error.value
      case .success(let found): pairs = found
      }
      let n = Double(pairs.count)
      guard n > 0 else { return .error(.divZero) }
      let mx = pairs.map(\.x).reduce(0, +) / n
      let my = pairs.map(\.y).reduce(0, +) / n
      let sxy = pairs.map { ($0.x - mx) * ($0.y - my) }.reduce(0, +)
      switch name {
      case "COVARIANCE.S":
        return n > 1 ? .number(sxy / (n - 1)) : .error(.divZero)
      case "COVARIANCE.P", "COVAR":
        return .number(sxy / n)
      default:
        let sxx = pairs.map { ($0.x - mx) * ($0.x - mx) }.reduce(0, +)
        let syy = pairs.map { ($0.y - my) * ($0.y - my) }.reduce(0, +)
        guard sxx > 0, syy > 0 else { return .error(.divZero) }
        let r = sxy / (sxx * syy).squareRoot()
        return .number(name == "RSQ" ? r * r : r)
      }
    case "RANK.AVG":
      return rankAverage(args)
    case "PERCENTRANK", "PERCENTRANK.INC", "PERCENTRANK.EXC":
      return percentRank(args, exclusive: name == "PERCENTRANK.EXC")

    // MARK: Normal distribution
    case "NORM.DIST", "NORMDIST":
      guard args.count == 4 else { return .error(.value) }
      return numbersExactly(Array(args.prefix(3)), 3) { a in
        guard a[2] > 0 else { return .error(.num) }
        let cumulative = self.flagValue(args[3])
        guard let cumulative else { return .error(.value) }
        let z = (a[0] - a[1]) / a[2]
        return .number(cumulative ? Self.normalCDF(z) : Self.normalPDF(z) / a[2])
      }
    case "NORM.S.DIST":
      guard args.count == 2 else { return .error(.value) }
      return numbersExactly([args[0]], 1) { a in
        guard let cumulative = self.flagValue(args[1]) else { return .error(.value) }
        return .number(cumulative ? Self.normalCDF(a[0]) : Self.normalPDF(a[0]))
      }
    case "NORMSDIST": return oneNumber(args) { .number(Self.normalCDF($0)) }
    case "NORM.INV", "NORMINV":
      return numbersExactly(args, 3) { a in
        guard a[0] > 0, a[0] < 1, a[2] > 0 else { return .error(.num) }
        return .number(a[1] + a[2] * Self.normalInverse(a[0]))
      }
    case "NORM.S.INV", "NORMSINV":
      return oneNumber(args) { p in
        p > 0 && p < 1 ? .number(Self.normalInverse(p)) : .error(.num)
      }

    // MARK: Text
    case "REPLACE": return evalReplace(args)
    case "FIXED": return evalFixed(args)
    case "DOLLAR": return evalDollar(args)
    case "T":
      guard args.count == 1 else { return .error(.value) }
      let value = firstValue(args[0])
      if case .error = value { return value }
      if case .string = value { return value }
      return .string("")
    case "NUMBERVALUE": return evalNumberValue(args)

    // MARK: Time and date text
    case "TIME":
      return numbersExactly(args, 3) { a in
        let parts = a.map { $0.rounded(.towardZero) }
        guard parts.allSatisfy({ $0 <= 32767 }) else { return .error(.num) }
        let seconds = parts[0] * 3600 + parts[1] * 60 + parts[2]
        guard seconds >= 0 else { return .error(.num) }
        return .number(seconds.truncatingRemainder(dividingBy: 86_400) / 86_400)
      }
    case "TIMEVALUE":
      return textArgument(args) { text in
        guard let fraction = Self.timeFraction(text) else { return .error(.value) }
        return .number(fraction)
      }
    case "DATEVALUE":
      return textArgument(args) { text in
        guard let serial = Self.dateSerial(text) else { return .error(.value) }
        return .number(serial)
      }
    case "DAYS360": return evalDays360(args)

    // MARK: Type tests
    case "N":
      guard args.count == 1 else { return .error(.value) }
      switch firstValue(args[0]) {
      case .number(let n): return .number(n)
      case .bool(let b): return .number(b ? 1 : 0)
      case .error(let e): return .error(e)
      case .string, .blank: return .number(0)
      }
    case "ISNONTEXT":
      guard args.count == 1 else { return .error(.value) }
      if case .string = evaluate(args[0]) { return .bool(false) }
      return .bool(true)
    case "TYPE":
      guard args.count == 1 else { return .error(.value) }
      // A range of several cells is 16, as other apps give it; only a typed list is 64.
      if case .range = args[0] {
        let values = arrayEvaluate(args[0], cache: nil)
        if values.count != 1 { return .number(16) }
      }
      if case .array(let rows) = args[0], rows.count * (rows.first?.count ?? 0) > 1 {
        return .number(64)
      }
      switch evaluate(args[0]) {
      case .number, .blank: return .number(1)
      case .string: return .number(2)
      case .bool: return .number(4)
      case .error: return .number(16)
      }
    case "ERROR.TYPE":
      guard args.count == 1 else { return .error(.value) }
      guard case .error(let error) = evaluate(args[0]) else { return .error(.na) }
      switch error {
      case .null: return .number(1)
      case .divZero: return .number(2)
      case .value, .arrayResult: return .number(3)
      case .ref: return .number(4)
      case .name: return .number(5)
      case .num: return .number(6)
      case .na: return .number(7)
      case .spill: return .number(9)
      case .calc: return .number(14)
      case .cycle, .error: return .error(.na)
      }

    // MARK: Depreciation and interest
    case "SLN":
      return numbersExactly(args, 3) { a in
        a[2] == 0 ? .error(.divZero) : .number((a[0] - a[1]) / a[2])
      }
    case "SYD":
      return numbersExactly(args, 4) { a in
        let (cost, salvage, life, period) = (a[0], a[1], a[2], a[3])
        guard life > 0, period > 0, period <= life, salvage >= 0 else { return .error(.num) }
        return .number((cost - salvage) * (life - period + 1) * 2 / (life * (life + 1)))
      }
    case "DDB": return evalDDB(args)
    case "DB": return evalDB(args)
    case "EFFECT", "NOMINAL":
      return numbersExactly(args, 2) { a in
        let periods = a[1].rounded(.towardZero)
        guard a[0] > 0, periods >= 1 else { return .error(.num) }
        if name == "EFFECT" { return .number(pow(1 + a[0] / periods, periods) - 1) }
        return .number(periods * (pow(1 + a[0], 1 / periods) - 1))
      }
    case "ISPMT":
      return numbersExactly(args, 4) { a in
        a[2] == 0 ? .error(.divZero) : .number(a[3] * a[0] * (a[1] / a[2] - 1))
      }
    case "CUMIPMT", "CUMPRINC":
      return numbersExactly(args, 6) { a in
        let (rate, periods, present) = (a[0], a[1].rounded(.towardZero), a[2])
        let first = a[3].rounded(.up)
        let last = a[4].rounded(.down)
        let type = a[5]
        guard rate > 0, periods > 0, present > 0, first >= 1, last >= first, last <= periods,
          type == 0 || type == 1
        else { return .error(.num) }
        let payment = Self.payment(
          rate: rate, periods: periods, present: present, future: 0, type: type)
        var total = 0.0
        var period = first
        while period <= last {
          let interest = Self.interestPart(
            rate: rate, period: period, periods: periods, present: present, future: 0, type: type)
          total += name == "CUMIPMT" ? interest : payment - interest
          period += 1
        }
        return .number(total)
      }
    case "MIRR": return evalMIRR(args)

    default:
      return nil
    }
  }

  // MARK: - Helpers

  private static func finite(_ value: Double) -> CellValue {
    value.isFinite ? .number(value) : .error(.num)
  }

  /// Exactly `count` number arguments; a blank reads as 0.
  private func numbersExactly(
    _ args: [FormulaExpr], _ count: Int, _ body: ([Double]) -> CellValue
  ) -> CellValue {
    guard args.count == count else { return .error(.value) }
    var numbers: [Double] = []
    for arg in args {
      let value = evaluate(arg)
      if case .error = value { return value }
      if case .blank = value {
        numbers.append(0)
        continue
      }
      guard let n = value.asNumber else { return .error(.value) }
      numbers.append(n)
    }
    let result = body(numbers)
    if case .number(let n) = result, !n.isFinite { return .error(.num) }
    return result
  }

  /// TRUE or FALSE, as a number or TRUE/FALSE; nil when it is neither.
  private func flagValue(_ expr: FormulaExpr) -> Bool? {
    switch evaluate(expr) {
    case .bool(let b): return b
    case .number(let n): return n != 0
    case .blank: return false
    case .string(let s):
      if s.caseInsensitiveCompare("TRUE") == .orderedSame { return true }
      if s.caseInsensitiveCompare("FALSE") == .orderedSame { return false }
      return nil
    case .error: return nil
    }
  }

  /// The value of a cell, or a range's first cell, as N and T read one.
  private func firstValue(_ expr: FormulaExpr) -> CellValue {
    if case .range = expr { return arrayEvaluate(expr, cache: nil).first ?? .blank }
    return evaluate(expr)
  }

  private func textArgument(_ args: [FormulaExpr], _ body: (String) -> CellValue) -> CellValue {
    guard args.count == 1 else { return .error(.value) }
    let value = evaluate(args[0])
    switch value {
    case .error: return value
    case .string(let text): return body(text)
    default: return .error(.value)
    }
  }

  /// The A statistics: in a range, text counts as 0 and TRUE as 1; blanks are left out. Typed
  /// as an argument, text must read as a number.
  private func aValues(_ args: [FormulaExpr]) -> (values: [Double], error: CellValue?) {
    var values: [Double] = []
    for arg in args {
      if case .string(let text) = arg {
        guard let n = Double(text.trimmingCharacters(in: .whitespaces)) else {
          return ([], .error(.value))
        }
        values.append(n)
        continue
      }
      for value in arrayEvaluate(arg, cache: nil) {
        switch value {
        case .error: return ([], value)
        case .number(let n): values.append(n)
        case .bool(let b): values.append(b ? 1 : 0)
        case .string: values.append(0)
        case .blank: continue
        }
      }
    }
    return (values, nil)
  }

  /// SKEW (sample), SKEW.P and KURT (sample excess), as other apps define them.
  private static func shape(_ name: String, _ v: [Double]) -> CellValue {
    let n = Double(v.count)
    let mean = v.reduce(0, +) / max(n, 1)
    let m2 = v.map { pow($0 - mean, 2) }.reduce(0, +)
    switch name {
    case "SKEW":
      guard n >= 3, m2 > 0 else { return .error(.divZero) }
      let s = (m2 / (n - 1)).squareRoot()
      let sum = v.map { pow(($0 - mean) / s, 3) }.reduce(0, +)
      return .number(n / ((n - 1) * (n - 2)) * sum)
    case "SKEW.P":
      guard n >= 1, m2 > 0 else { return .error(.divZero) }
      let s = (m2 / n).squareRoot()
      return .number(v.map { pow(($0 - mean) / s, 3) }.reduce(0, +) / n)
    default:
      guard n >= 4, m2 > 0 else { return .error(.divZero) }
      let s = (m2 / (n - 1)).squareRoot()
      let sum = v.map { pow(($0 - mean) / s, 4) }.reduce(0, +)
      let a = n * (n + 1) / ((n - 1) * (n - 2) * (n - 3))
      let b = 3 * pow(n - 1, 2) / ((n - 2) * (n - 3))
      return .number(a * sum - b)
    }
  }

  private func rankAverage(_ args: [FormulaExpr]) -> CellValue {
    guard args.count == 2 || args.count == 3 else { return .error(.value) }
    let target = evaluate(args[0])
    if case .error = target { return target }
    guard let x = target.asNumber else { return .error(.value) }
    let numbers = numbersIn([args[1]])
    if let error = numbers.error { return error }
    let ascending = args.count == 3 ? (flagValue(args[2]) ?? false) : false
    let ties = numbers.values.filter { $0 == x }.count
    guard ties > 0 else { return .error(.na) }
    let ahead = numbers.values.filter { ascending ? $0 < x : $0 > x }.count
    return .number(Double(ahead) + Double(ties + 1) / 2)
  }

  /// PERCENTRANK.INC (and PERCENTRANK): where x falls among the values, 0 to 1, between
  /// neighbours by straight line. .EXC counts from 1/(n+1) to n/(n+1). Cut, not rounded, to
  /// `significance` digits (3 when left out).
  private func percentRank(_ args: [FormulaExpr], exclusive: Bool) -> CellValue {
    guard args.count == 2 || args.count == 3 else { return .error(.value) }
    let numbers = numbersIn([args[0]])
    if let error = numbers.error { return error }
    let target = evaluate(args[1])
    if case .error = target { return target }
    guard let x = target.asNumber else { return .error(.value) }
    var digits = 3.0
    if args.count == 3 {
      let given = evaluate(args[2])
      if case .error = given { return given }
      guard let d = given.asNumber else { return .error(.value) }
      digits = d.rounded(.towardZero)
    }
    guard digits >= 1 else { return .error(.num) }
    let sorted = numbers.values.sorted()
    guard let first = sorted.first, let last = sorted.last, x >= first, x <= last else {
      return .error(.na)
    }
    let n = Double(sorted.count)
    // The position of x among the sorted values, counting from 0, between two of them.
    var position = 0.0
    if let exact = sorted.firstIndex(of: x) {
      position = Double(exact)
    } else {
      let below = sorted.lastIndex(where: { $0 < x }) ?? 0
      position =
        Double(below) + (x - sorted[below]) / (sorted[below + 1] - sorted[below])
    }
    let rank: Double
    if exclusive {
      rank = (position + 1) / (n + 1)
    } else {
      guard n > 1 else { return .number(1) }
      rank = position / (n - 1)
    }
    let scale = pow(10, digits)
    return .number((rank * scale + 1e-9).rounded(.down) / scale)
  }

  // MARK: Normal distribution

  static func normalPDF(_ z: Double) -> Double { exp(-z * z / 2) / (2 * Double.pi).squareRoot() }

  static func normalCDF(_ z: Double) -> Double { 0.5 * erfc(-z / 2.0.squareRoot()) }

  /// The z for which normalCDF(z) = p: Acklam's approximation, then one Halley step.
  static func normalInverse(_ p: Double) -> Double {
    let a = [
      -3.969683028665376e+01, 2.209460984245205e+02, -2.759285104469687e+02,
      1.383577518672690e+02, -3.066479806614716e+01, 2.506628277459239e+00,
    ]
    let b = [
      -5.447609879822406e+01, 1.615858368580409e+02, -1.556989798598866e+02,
      6.680131188771972e+01, -1.328068155288572e+01,
    ]
    let c = [
      -7.784894002430293e-03, -3.223964580411365e-01, -2.400758277161838e+00,
      -2.549732539343734e+00, 4.374664141464968e+00, 2.938163982698783e+00,
    ]
    let d = [
      7.784695709041462e-03, 3.224671290700398e-01, 2.445134137142996e+00,
      3.754408661907416e+00,
    ]
    let low = 0.02425
    var x: Double
    if p < low {
      let q = (-2 * log(p)).squareRoot()
      x =
        (((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5])
        / ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1)
    } else if p <= 1 - low {
      let q = p - 0.5
      let r = q * q
      x =
        (((((a[0] * r + a[1]) * r + a[2]) * r + a[3]) * r + a[4]) * r + a[5]) * q
        / (((((b[0] * r + b[1]) * r + b[2]) * r + b[3]) * r + b[4]) * r + 1)
    } else {
      let q = (-2 * log(1 - p)).squareRoot()
      x =
        -(((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5])
        / ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1)
    }
    for _ in 0..<2 {
      let e = normalCDF(x) - p
      let u = e * (2 * Double.pi).squareRoot() * exp(x * x / 2)
      x -= u / (1 + x * u / 2)
    }
    return x
  }

  // MARK: Text

  private func evalReplace(_ args: [FormulaExpr]) -> CellValue {
    guard args.count == 4 else { return .error(.value) }
    let values = args.map { evaluate($0) }
    if let error = values.first(where: \.isError) { return error }
    guard let start = values[1].asNumber, let count = values[2].asNumber else {
      return .error(.value)
    }
    let from = Int(start.rounded(.towardZero))
    let length = Int(count.rounded(.towardZero))
    guard from >= 1, length >= 0 else { return .error(.value) }
    let old = Array(values[0].asString)
    let begin = min(from - 1, old.count)
    let end = min(begin + length, old.count)
    return .string(String(old[..<begin]) + values[3].asString + String(old[end...]))
  }

  /// A number rounded to `decimals` places, half away from zero, with commas, as text.
  static func groupedText(_ value: Double, decimals: Int, commas: Bool) -> String {
    let rounded = roundHalfAway(value, decimals)
    let places = max(0, decimals)
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.numberStyle = .decimal
    formatter.usesGroupingSeparator = commas
    formatter.groupingSeparator = ","
    formatter.groupingSize = 3
    formatter.decimalSeparator = "."
    formatter.minimumFractionDigits = places
    formatter.maximumFractionDigits = places
    formatter.roundingMode = .halfUp
    return formatter.string(from: NSNumber(value: abs(rounded))) ?? String(abs(rounded))
  }

  private static func roundHalfAway(_ value: Double, _ decimals: Int) -> Double {
    let scale = pow(10, Double(decimals))
    let shifted = Double(String(format: "%.15g", value * scale)) ?? value * scale
    let rounded = shifted >= 0 ? (shifted + 0.5).rounded(.down) : -((-shifted + 0.5).rounded(.down))
    return rounded / scale
  }

  private func evalFixed(_ args: [FormulaExpr]) -> CellValue {
    guard (1...3).contains(args.count) else { return .error(.value) }
    let value = evaluate(args[0])
    if case .error = value { return value }
    guard let number = value.asNumber else { return .error(.value) }
    var decimals = 2
    if args.count > 1, case .missing = args[1] {
    } else if args.count > 1 {
      let d = evaluate(args[1])
      if case .error = d { return d }
      guard let n = d.asNumber, abs(n) <= 127 else { return .error(.value) }
      decimals = Int(n.rounded(.towardZero))
    }
    let noCommas = args.count > 2 ? (flagValue(args[2]) ?? false) : false
    let rounded = Self.roundHalfAway(number, decimals)
    let text = Self.groupedText(rounded, decimals: decimals, commas: !noCommas)
    return .string(rounded < 0 ? "-" + text : text)
  }

  private func evalDollar(_ args: [FormulaExpr]) -> CellValue {
    guard (1...2).contains(args.count) else { return .error(.value) }
    let value = evaluate(args[0])
    if case .error = value { return value }
    guard let number = value.asNumber else { return .error(.value) }
    var decimals = 2
    if args.count == 2 {
      let d = evaluate(args[1])
      if case .error = d { return d }
      guard let n = d.asNumber, abs(n) <= 127 else { return .error(.value) }
      decimals = Int(n.rounded(.towardZero))
    }
    let rounded = Self.roundHalfAway(number, decimals)
    let text = "$" + Self.groupedText(rounded, decimals: decimals, commas: true)
    return .string(rounded < 0 ? "(" + text + ")" : text)
  }

  private func evalNumberValue(_ args: [FormulaExpr]) -> CellValue {
    guard (1...3).contains(args.count) else { return .error(.value) }
    let values = args.map { evaluate($0) }
    if let error = values.first(where: \.isError) { return error }
    if case .number = values[0] { return values[0] }
    let decimal = args.count > 1 ? values[1].asString.first.map(String.init) ?? "." : "."
    let group = args.count > 2 ? values[2].asString.first.map(String.init) ?? "," : ","
    var text = values[0].asString.filter { !$0.isWhitespace }
    if text.isEmpty { return .number(0) }
    var divide = 1.0
    while text.hasSuffix("%") {
      text.removeLast()
      divide *= 100
    }
    guard decimal != group || args.count < 3 else { return .error(.value) }
    let parts = text.components(separatedBy: decimal)
    guard parts.count <= 2, !(parts.count == 2 && parts[1].contains(group)) else {
      return .error(.value)
    }
    let whole = parts[0].replacingOccurrences(of: group, with: "")
    let joined = parts.count == 2 ? whole + "." + parts[1] : whole
    guard let n = Double(joined.isEmpty ? "0" : joined) else { return .error(.value) }
    return .number(n / divide)
  }

  // MARK: Time and date text

  /// A time such as `6:30 PM`, `18:30:15` or `1/5/2026 9:00 AM` as a fraction of a day.
  static func timeFraction(_ text: String) -> Double? {
    var t = text.trimmingCharacters(in: .whitespaces).uppercased()
    var pm: Bool?
    if t.hasSuffix("PM") || t.hasSuffix("AM") {
      pm = t.hasSuffix("PM")
      t = String(t.dropLast(2)).trimmingCharacters(in: .whitespaces)
    }
    // A date before the time is left out.
    if let space = t.lastIndex(of: " ") { t = String(t[t.index(after: space)...]) }
    let parts = t.split(separator: ":", omittingEmptySubsequences: false)
    guard (2...3).contains(parts.count),
      let h = Double(parts[0]), let m = Double(parts[1]),
      h >= 0, m >= 0, m < 60
    else { return nil }
    let s = parts.count == 3 ? Double(parts[2]) : 0
    guard let s, s >= 0, s < 60 else { return nil }
    var hours = h
    if let pm {
      guard h >= 1, h <= 12 else { return nil }
      hours = h.truncatingRemainder(dividingBy: 12) + (pm ? 12 : 0)
    }
    let seconds = hours * 3600 + m * 60 + s
    return seconds.truncatingRemainder(dividingBy: 86_400) / 86_400
  }

  /// A date such as `1/5/2026`, `2026-01-05` or `5-Jan-2026`, a time after it left out.
  public static func dateSerial(_ text: String) -> Double? {
    let t = text.trimmingCharacters(in: .whitespaces)
    if let serial = ColumnFilterRules.dateSerial(t) { return serial }
    // Drop a time after the date: the last space-separated part with a colon, and AM/PM.
    var words = t.split(separator: " ").map(String.init)
    if let last = words.last, last.uppercased() == "AM" || last.uppercased() == "PM" {
      words.removeLast()
    }
    if let last = words.last, last.contains(":") {
      words.removeLast()
      return ColumnFilterRules.dateSerial(words.joined(separator: " "))
    }
    return nil
  }

  private func evalDays360(_ args: [FormulaExpr]) -> CellValue {
    guard args.count == 2 || args.count == 3 else { return .error(.value) }
    let values = args.map { evaluate($0) }
    if let error = values.first(where: \.isError) { return error }
    guard let startSerial = values[0].asNumber, let endSerial = values[1].asNumber,
      startSerial >= 0, endSerial >= 0
    else { return .error(.value) }
    let european = args.count == 3 ? (flagValue(args[2]) ?? false) : false
    guard let start = Self.ymd(Int(startSerial.rounded(.down))),
      let end = Self.ymd(Int(endSerial.rounded(.down)))
    else { return .error(.num) }
    var (d1, d2) = (start.day, end.day)
    if european {
      d1 = min(d1, 30)
      d2 = min(d2, 30)
    } else {
      let startIsLastOfFebruary = start.month == 2 && Self.isLastDayOfMonth(start)
      if startIsLastOfFebruary || d1 == 31 { d1 = 30 }
      if d2 == 31 && d1 >= 30 { d2 = 30 }
    }
    let days =
      (end.year - start.year) * 360 + (end.month - start.month) * 30 + (d2 - d1)
    return .number(Double(days))
  }

  private static func isLastDayOfMonth(_ date: (year: Int, month: Int, day: Int)) -> Bool {
    let leap = (date.year % 4 == 0 && date.year % 100 != 0) || date.year % 400 == 0
    let lengths = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    return date.day == lengths[date.month - 1]
  }

  // MARK: Depreciation

  /// Declining balance at `factor` (2 when left out), never below salvage.
  private func evalDDB(_ args: [FormulaExpr]) -> CellValue {
    guard args.count == 4 || args.count == 5 else { return .error(.value) }
    let padded = args.count == 5 ? args : args + [.number(2)]
    return numbersExactly(padded, 5) { a in
      let (cost, salvage, life, period, factor) = (a[0], a[1], a[2], a[3], a[4])
      guard cost >= 0, salvage >= 0, life > 0, period > 0, period <= life, factor > 0 else {
        return .error(.num)
      }
      let rate = min(factor / life, 1)
      var book = cost
      var depreciation = 0.0
      var p = 1.0
      while p <= period.rounded(.up) {
        depreciation = min(book * rate, max(0, book - salvage))
        book -= depreciation
        p += 1
      }
      return .number(depreciation)
    }
  }

  /// Fixed declining balance with the rate rounded to three places; `month` is how many
  /// months the first year has (12 when left out).
  private func evalDB(_ args: [FormulaExpr]) -> CellValue {
    guard args.count == 4 || args.count == 5 else { return .error(.value) }
    let padded = args.count == 5 ? args : args + [.number(12)]
    return numbersExactly(padded, 5) { a in
      let (cost, salvage, life) = (a[0], a[1], a[2])
      let period = a[3].rounded(.towardZero)
      let month = a[4].rounded(.towardZero)
      guard cost >= 0, salvage >= 0, life > 0, period >= 1, month >= 1, month <= 12,
        period <= life + (month < 12 ? 1 : 0)
      else { return .error(.num) }
      guard cost > 0 else { return .number(0) }
      let rate = ((1 - pow(salvage / cost, 1 / life)) * 1000).rounded() / 1000
      var total = 0.0
      var depreciation = 0.0
      var p = 1.0
      while p <= period {
        if p == 1 {
          depreciation = cost * rate * month / 12
        } else if p == life + 1 {
          depreciation = (cost - total) * rate * (12 - month) / 12
        } else {
          depreciation = (cost - total) * rate
        }
        total += depreciation
        p += 1
      }
      return .number(depreciation)
    }
  }

  /// Modified internal rate of return: payments out grow at `finance_rate`, money in at
  /// `reinvest_rate`.
  private func evalMIRR(_ args: [FormulaExpr]) -> CellValue {
    guard args.count == 3 else { return .error(.value) }
    let flows = numbersIn([args[0]])
    if let error = flows.error { return error }
    let rates = [args[1], args[2]].map { evaluate($0) }
    if let error = rates.first(where: \.isError) { return error }
    guard let finance = rates[0].asNumber, let reinvest = rates[1].asNumber else {
      return .error(.value)
    }
    let v = flows.values
    let n = Double(v.count)
    guard v.count >= 2 else { return .error(.divZero) }
    var outflows = 0.0
    var inflows = 0.0
    for (i, value) in v.enumerated() {
      if value < 0 {
        outflows += value / pow(1 + finance, Double(i))
      } else {
        inflows += value * pow(1 + reinvest, n - 1 - Double(i))
      }
    }
    guard outflows != 0, inflows != 0 else { return .error(.divZero) }
    return Self.finite(pow(-inflows / outflows, 1 / (n - 1)) - 1)
  }
}
