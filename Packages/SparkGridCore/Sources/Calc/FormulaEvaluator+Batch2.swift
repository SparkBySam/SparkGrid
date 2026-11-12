import Formula
import Foundation
import Functions
import GridCore
import Model

/// Functions batch 2 for 1.4: loans and cash flows, working days and date differences,
/// spread and trend statistics, more math, text and logic.
extension FormulaEvaluator {
  /// Handles a batch 2 function, or returns nil when `name` is not one.
  func evalBatch2(_ name: String, _ args: [FormulaExpr]) -> CellValue? {
    switch name {
    // MARK: Financial
    case "PMT":
      return financial(args, required: 3) { a in
        .number(Self.payment(rate: a[0], periods: a[1], present: a[2], future: a[3], type: a[4]))
      }
    case "FV":
      return financial(args, required: 3) { a in
        .number(
          Self.futureValue(rate: a[0], periods: a[1], payment: a[2], present: a[3], type: a[4]))
      }
    case "PV":
      return financial(args, required: 3) { a in
        let (r, n, pmt, fv, type) = (a[0], a[1], a[2], a[3], a[4])
        if r == 0 { return .number(-(fv + pmt * n)) }
        let growth = pow(1 + r, n)
        return .number(-(fv + pmt * (1 + r * type) * (growth - 1) / r) / growth)
      }
    case "NPER":
      return financial(args, required: 3) { a in
        let (r, pmt, pv, fv, type) = (a[0], a[1], a[2], a[3], a[4])
        if r == 0 {
          guard pmt != 0 else { return .error(.num) }
          return .number(-(pv + fv) / pmt)
        }
        let top = pmt * (1 + r * type) - fv * r
        let bottom = pmt * (1 + r * type) + pv * r
        guard bottom != 0, top / bottom > 0 else { return .error(.num) }
        return .number(log(top / bottom) / log(1 + r))
      }
    case "IPMT", "PPMT":
      return financial(args, required: 4, total: 6) { a in
        let (r, per, n, pv, fv, type) = (a[0], a[1], a[2], a[3], a[4], a[5])
        guard per >= 1, per <= n else { return .error(.num) }
        let interest = Self.interestPart(
          rate: r, period: per, periods: n, present: pv, future: fv, type: type)
        if name == "IPMT" { return .number(interest) }
        return .number(
          Self.payment(rate: r, periods: n, present: pv, future: fv, type: type) - interest)
      }
    case "RATE": return evalRate(args)
    case "NPV": return evalNPV(args)
    case "IRR": return evalIRR(args)
    case "XNPV": return evalXNPV(args)
    case "XIRR": return evalXIRR(args)

    // MARK: Date
    case "DAYS":
      return twoNumbers(args) { end, start in .number(end.rounded(.down) - start.rounded(.down)) }
    case "DATEDIF": return evalDatedif(args)
    case "NETWORKDAYS": return evalNetworkdays(args)
    case "WORKDAY": return evalWorkday(args)
    case "WEEKNUM": return evalWeeknum(args)
    case "ISOWEEKNUM":
      return oneNumber(args) { serial in
        guard serial >= 0 else { return .error(.num) }
        return .number(Double(Self.isoWeek(Int(serial.rounded(.down)))))
      }

    // MARK: Statistics
    case "STDEV", "STDEV.S", "STDEVP", "STDEV.P", "VAR", "VAR.S", "VARP", "VAR.P":
      let numbers = numbersIn(args)
      if let error = numbers.error { return error }
      let sample = !(name.hasSuffix("P") || name.hasSuffix(".P"))
      guard let variance = Self.variance(numbers.values, sample: sample) else {
        return .error(.divZero)
      }
      return .number(name.hasPrefix("STDEV") ? variance.squareRoot() : variance)
    case "PERCENTILE", "PERCENTILE.INC", "QUARTILE", "QUARTILE.INC":
      guard args.count == 2 else { return .error(.value) }
      let numbers = numbersIn([args[0]])
      if let error = numbers.error { return error }
      let kValue = evaluate(args[1])
      if case .error = kValue { return kValue }
      guard var k = kValue.asNumber, !numbers.values.isEmpty else { return .error(.num) }
      if name.hasPrefix("QUARTILE") {
        let quart = k.rounded(.down)
        guard quart >= 0, quart <= 4 else { return .error(.num) }
        k = quart / 4
      }
      guard k >= 0, k <= 1 else { return .error(.num) }
      let sorted = numbers.values.sorted()
      let position = k * Double(sorted.count - 1)
      let lower = Int(position.rounded(.down))
      let upper = min(lower + 1, sorted.count - 1)
      return .number(sorted[lower] + (position - Double(lower)) * (sorted[upper] - sorted[lower]))
    case "MODE", "MODE.SNGL":
      let numbers = numbersIn(args)
      if let error = numbers.error { return error }
      var counts: [Double: Int] = [:]
      for n in numbers.values { counts[n, default: 0] += 1 }
      // The first number to reach the top count, in the order given.
      let top = counts.values.max() ?? 0
      guard top > 1, let mode = numbers.values.first(where: { counts[$0] == top }) else {
        return .error(.na)
      }
      return .number(mode)
    case "CORREL", "SLOPE", "INTERCEPT":
      guard args.count == 2 else { return .error(.value) }
      // SLOPE and INTERCEPT take known y's first, then known x's.
      guard case .success(let pairs) = numberPairs(args[1], args[0]) else {
        if case .failure(let error) = numberPairs(args[1], args[0]) { return error.value }
        return .error(.value)
      }
      guard let fit = Self.linearFit(pairs) else { return .error(.divZero) }
      switch name {
      case "SLOPE": return .number(fit.slope)
      case "INTERCEPT": return .number(fit.intercept)
      default:
        guard let r = fit.correlation else { return .error(.divZero) }
        return .number(r)
      }
    case "FORECAST", "FORECAST.LINEAR":
      guard args.count == 3 else { return .error(.value) }
      let xValue = evaluate(args[0])
      if case .error = xValue { return xValue }
      guard let x = xValue.asNumber else { return .error(.value) }
      switch numberPairs(args[2], args[1]) {
      case .failure(let error): return error.value
      case .success(let pairs):
        guard let fit = Self.linearFit(pairs) else { return .error(.divZero) }
        return .number(fit.intercept + fit.slope * x)
      }
    case "COUNTUNIQUE":
      guard !args.isEmpty else { return .error(.value) }
      var seen = Set<String>()
      for value in flatten(args) {
        switch value {
        case .blank: continue
        case .string(let s) where s.isEmpty: continue
        case .number(let n): seen.insert("n\(n)")
        case .bool(let b): seen.insert("b\(b)")
        case .error(let e): seen.insert("e\(e)")
        case .string(let s): seen.insert("s" + s.lowercased())
        }
      }
      return .number(Double(seen.count))
    case "SUMSQ":
      let numbers = numbersIn(args)
      if let error = numbers.error { return error }
      return .number(numbers.values.reduce(0) { $0 + $1 * $1 })

    // MARK: Math
    case "MROUND":
      return twoNumbers(args) { number, multiple in
        if multiple == 0 { return .number(0) }
        guard number == 0 || (number > 0) == (multiple > 0) else { return .error(.num) }
        let quotient = number / multiple
        // Half away from zero, after trimming float noise such as 2.4999999999.
        let steadied = (quotient * 1e9).rounded() / 1e9
        return .number(steadied.rounded(.toNearestOrAwayFromZero) * multiple)
      }
    case "TRUNC":
      guard args.count == 1 || args.count == 2 else { return .error(.value) }
      let value = evaluate(args[0])
      if case .error = value { return value }
      guard let number = value.asNumber else { return .error(.value) }
      var digits = 0.0
      if args.count == 2 {
        let d = evaluate(args[1])
        if case .error = d { return d }
        guard let n = d.asNumber else { return .error(.value) }
        digits = n.rounded(.towardZero)
      }
      let scale = pow(10, digits)
      return .number((number * scale).rounded(.towardZero) / scale)
    case "EXP":
      return oneNumber(args) { n in
        let result = exp(n)
        return result.isFinite ? .number(result) : .error(.num)
      }
    case "LN":
      return oneNumber(args) { $0 > 0 ? .number(log($0)) : .error(.num) }
    case "LOG10":
      return oneNumber(args) { $0 > 0 ? .number(log10($0)) : .error(.num) }
    case "LOG":
      guard args.count == 1 || args.count == 2 else { return .error(.value) }
      let value = evaluate(args[0])
      if case .error = value { return value }
      var base = 10.0
      if args.count == 2 {
        let b = evaluate(args[1])
        if case .error = b { return b }
        guard let n = b.asNumber else { return .error(.value) }
        base = n
      }
      guard let number = value.asNumber else { return .error(.value) }
      guard number > 0, base > 0 else { return .error(.num) }
      guard base != 1 else { return .error(.divZero) }
      return .number(log(number) / log(base))
    case "FACT":
      return oneNumber(args) { n in
        let whole = n.rounded(.down)
        guard whole >= 0, whole <= 170 else { return .error(.num) }
        var result = 1.0
        var k = 2.0
        while k <= whole {
          result *= k
          k += 1
        }
        return .number(result)
      }
    case "GCD", "LCM":
      let numbers = numbersIn(args)
      if let error = numbers.error { return error }
      guard !numbers.values.isEmpty else { return .error(.value) }
      var result = name == "GCD" ? 0 : 1
      for n in numbers.values {
        guard n >= 0, n < 9.007e15 else { return .error(.num) }
        let whole = Int(n.rounded(.down))
        if name == "GCD" {
          result = Self.gcd(result, whole)
        } else {
          if whole == 0 { return .number(0) }
          let (product, overflow) = (result / Self.gcd(result, whole)).multipliedReportingOverflow(
            by: whole)
          guard !overflow else { return .error(.num) }
          result = product
        }
      }
      return .number(Double(result))
    case "EVEN", "ODD":
      return oneNumber(args) { n in
        let away = abs(n).rounded(.up)
        var whole = away
        if name == "EVEN" {
          if whole.truncatingRemainder(dividingBy: 2) != 0 { whole += 1 }
        } else if whole.truncatingRemainder(dividingBy: 2) == 0 {
          whole += 1
        }
        return .number(n < 0 ? -whole : whole)
      }

    // MARK: Logic and information
    case "SWITCH":
      guard args.count >= 3 else { return .error(.value) }
      let subject = evaluate(args[0])
      if case .error = subject { return subject }
      var index = 1
      while index + 1 < args.count {
        let candidate = evaluate(args[index])
        if case .error = candidate { return candidate }
        if Self.sameValue(subject, candidate) { return evaluate(args[index + 1]) }
        index += 2
      }
      return index < args.count ? evaluate(args[index]) : .error(.na)
    case "CHOOSE":
      guard args.count >= 2 else { return .error(.value) }
      let pick = evaluate(args[0])
      if case .error = pick { return pick }
      guard let n = pick.asNumber else { return .error(.value) }
      let index = Int(n.rounded(.down))
      guard index >= 1, index < args.count else { return .error(.value) }
      return evaluate(args[index])
    case "XOR":
      guard !args.isEmpty else { return .error(.value) }
      var trueCount = 0
      var any = false
      for value in flatten(args) {
        switch value {
        case .error: return value
        case .bool(let b):
          any = true
          if b { trueCount += 1 }
        case .number(let n):
          any = true
          if n != 0 { trueCount += 1 }
        default: continue
        }
      }
      guard any else { return .error(.value) }
      return .bool(trueCount % 2 == 1)
    case "ISEVEN", "ISODD":
      return oneNumber(args) { n in
        let even = n.rounded(.towardZero).truncatingRemainder(dividingBy: 2) == 0
        return .bool(name == "ISEVEN" ? even : !even)
      }
    case "ISLOGICAL":
      guard args.count == 1 else { return .error(.value) }
      if case .bool = evaluate(args[0]) { return .bool(true) }
      return .bool(false)
    case "ISNA":
      guard args.count == 1 else { return .error(.value) }
      if case .error(.na) = evaluate(args[0]) { return .bool(true) }
      return .bool(false)
    case "ISERR":
      guard args.count == 1 else { return .error(.value) }
      let value = evaluate(args[0])
      if case .error(let e) = value, e != .na { return .bool(true) }
      return .bool(false)
    case "NA":
      guard args.isEmpty else { return .error(.value) }
      return .error(.na)

    // MARK: Text
    case "TEXTBEFORE", "TEXTAFTER": return evalTextAround(args, before: name == "TEXTBEFORE")
    case "CLEAN":
      guard args.count == 1 else { return .error(.value) }
      let value = evaluate(args[0])
      if case .error = value { return value }
      return .string(
        String(String.UnicodeScalarView(value.asString.unicodeScalars.filter { $0.value >= 32 })))
    case "CODE", "UNICODE":
      guard args.count == 1 else { return .error(.value) }
      let value = evaluate(args[0])
      if case .error = value { return value }
      guard let scalar = value.asString.unicodeScalars.first else { return .error(.value) }
      return .number(Double(scalar.value))
    case "UNICHAR":
      return oneNumber(args) { n in
        guard n >= 1, let scalar = Unicode.Scalar(UInt32(min(n, 0x10FFFF).rounded(.down))) else {
          return .error(.value)
        }
        return .string(String(Character(scalar)))
      }
    case "GETPIVOTDATA":
      return evalGetPivotData(args)
    case "HYPERLINK":
      // The cell shows the friendly name, or the address when there is none.
      guard args.count == 1 || args.count == 2 else { return .error(.value) }
      let address = evaluate(args[0])
      if case .error = address { return address }
      if args.count == 2 {
        let label = evaluate(args[1])
        if case .blank = label { return .number(0) }
        return label
      }
      return .string(address.asString)
    default:
      return nil
    }
  }

  // MARK: - Argument helpers

  private func oneNumber(_ args: [FormulaExpr], _ body: (Double) -> CellValue) -> CellValue {
    guard args.count == 1 else { return .error(.value) }
    let value = evaluate(args[0])
    if case .error = value { return value }
    guard let number = value.asNumber else { return .error(.value) }
    return body(number)
  }

  private func twoNumbers(_ args: [FormulaExpr], _ body: (Double, Double) -> CellValue)
    -> CellValue
  {
    guard args.count == 2 else { return .error(.value) }
    let left = evaluate(args[0])
    if case .error = left { return left }
    let right = evaluate(args[1])
    if case .error = right { return right }
    guard let a = left.asNumber, let b = right.asNumber else { return .error(.value) }
    return body(a, b)
  }

  /// Numbers in the arguments, skipping text and blanks in ranges. The first error stops it.
  private func numbersIn(_ args: [FormulaExpr]) -> (values: [Double], error: CellValue?) {
    var values: [Double] = []
    for value in flatten(args) {
      switch value {
      case .error: return ([], value)
      case .number(let n): values.append(n)
      default: continue
      }
    }
    return (values, nil)
  }

  private struct ErrorBox: Error { var value: CellValue }

  /// (x, y) pairs from two ranges of the same size, keeping pairs where both are numbers.
  private func numberPairs(_ xs: FormulaExpr, _ ys: FormulaExpr) -> Result<
    [(x: Double, y: Double)], ErrorBox
  > {
    let xValues = flatten([xs])
    let yValues = flatten([ys])
    guard xValues.count == yValues.count else { return .failure(ErrorBox(value: .error(.na))) }
    var pairs: [(x: Double, y: Double)] = []
    for (x, y) in zip(xValues, yValues) {
      if case .error = x { return .failure(ErrorBox(value: x)) }
      if case .error = y { return .failure(ErrorBox(value: y)) }
      if case .number(let a) = x, case .number(let b) = y { pairs.append((a, b)) }
    }
    return .success(pairs)
  }

  /// Loan arguments: `required` numbers, then optional ones that default to 0, up to `total`.
  private func financial(
    _ args: [FormulaExpr], required: Int, total: Int = 5, _ body: ([Double]) -> CellValue
  ) -> CellValue {
    guard args.count >= required, args.count <= total else { return .error(.value) }
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
    while numbers.count < total { numbers.append(0) }
    // The payment-timing argument counts only as 0 (end of period) or not 0 (start).
    numbers[total - 1] = numbers[total - 1] == 0 ? 0 : 1
    let result = body(numbers)
    if case .number(let n) = result, !n.isFinite { return .error(.num) }
    return result
  }

  // MARK: - Loans and cash flows

  static func payment(
    rate r: Double, periods n: Double, present pv: Double, future fv: Double,
    type: Double
  ) -> Double {
    if r == 0 { return -(pv + fv) / n }
    let growth = pow(1 + r, n)
    return -(r * (fv + pv * growth)) / ((1 + r * type) * (growth - 1))
  }

  static func futureValue(
    rate r: Double, periods n: Double, payment pmt: Double,
    present pv: Double, type: Double
  ) -> Double {
    if r == 0 { return -(pv + pmt * n) }
    let growth = pow(1 + r, n)
    return -(pv * growth + pmt * (1 + r * type) * (growth - 1) / r)
  }

  /// The interest in payment `period`, as IPMT gives it.
  static func interestPart(
    rate r: Double, period: Double, periods n: Double, present pv: Double,
    future fv: Double, type: Double
  ) -> Double {
    let pmt = payment(rate: r, periods: n, present: pv, future: fv, type: type)
    let interest: Double
    if period == 1 {
      interest = type == 1 ? 0 : -pv
    } else if type == 1 {
      interest = futureValue(rate: r, periods: period - 2, payment: pmt, present: pv, type: 1) - pmt
    } else {
      interest = futureValue(rate: r, periods: period - 1, payment: pmt, present: pv, type: 0)
    }
    return interest * r
  }

  private func evalRate(_ args: [FormulaExpr]) -> CellValue {
    guard args.count >= 3, args.count <= 6 else { return .error(.value) }
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
    let n = numbers[0]
    let pmt = numbers[1]
    let pv = numbers[2]
    let fv = numbers.count > 3 ? numbers[3] : 0
    let type = numbers.count > 4 && numbers[4] != 0 ? 1.0 : 0
    let guess = numbers.count > 5 ? numbers[5] : 0.1
    guard n > 0 else { return .error(.num) }
    func f(_ r: Double) -> Double {
      if abs(r) < 1e-12 { return pv + pmt * n + fv }
      let growth = pow(1 + r, n)
      return pv * growth + pmt * (1 + r * type) * (growth - 1) / r + fv
    }
    guard let rate = Self.solve(f, guess: guess) else { return .error(.num) }
    return .number(rate)
  }

  private func evalNPV(_ args: [FormulaExpr]) -> CellValue {
    guard args.count >= 2 else { return .error(.value) }
    let rateValue = evaluate(args[0])
    if case .error = rateValue { return rateValue }
    guard let rate = rateValue.asNumber else { return .error(.value) }
    guard rate != -1 else { return .error(.divZero) }
    let flows = numbersIn(Array(args.dropFirst()))
    if let error = flows.error { return error }
    var total = 0.0
    for (i, flow) in flows.values.enumerated() {
      total += flow / pow(1 + rate, Double(i + 1))
    }
    return .number(total)
  }

  private func evalIRR(_ args: [FormulaExpr]) -> CellValue {
    guard args.count == 1 || args.count == 2 else { return .error(.value) }
    let flows = numbersIn([args[0]])
    if let error = flows.error { return error }
    var guess = 0.1
    if args.count == 2 {
      let g = evaluate(args[1])
      if case .error = g { return g }
      guard let n = g.asNumber else { return .error(.value) }
      guess = n
    }
    let values = flows.values
    guard values.contains(where: { $0 > 0 }), values.contains(where: { $0 < 0 }) else {
      return .error(.num)
    }
    func npv(_ r: Double) -> Double {
      var total = 0.0
      for (i, v) in values.enumerated() { total += v / pow(1 + r, Double(i)) }
      return total
    }
    guard let rate = Self.solve(npv, guess: guess) else { return .error(.num) }
    return .number(rate)
  }

  /// Cash flows and their dates for XNPV and XIRR. The first date is the start.
  private func datedFlows(_ valuesArg: FormulaExpr, _ datesArg: FormulaExpr) -> Result<
    [(value: Double, years: Double)], ErrorBox
  > {
    let values = flatten([valuesArg])
    let dates = flatten([datesArg])
    guard values.count == dates.count, !values.isEmpty else {
      return .failure(ErrorBox(value: .error(.num)))
    }
    var flows: [(value: Double, years: Double)] = []
    var start: Double?
    for (v, d) in zip(values, dates) {
      if case .error = v { return .failure(ErrorBox(value: v)) }
      if case .error = d { return .failure(ErrorBox(value: d)) }
      guard let amount = v.asNumber, let day = d.asNumber else {
        return .failure(ErrorBox(value: .error(.value)))
      }
      let whole = day.rounded(.down)
      let first = start ?? whole
      start = first
      guard whole >= first else { return .failure(ErrorBox(value: .error(.num))) }
      flows.append((amount, (whole - first) / 365))
    }
    return .success(flows)
  }

  private func evalXNPV(_ args: [FormulaExpr]) -> CellValue {
    guard args.count == 3 else { return .error(.value) }
    let rateValue = evaluate(args[0])
    if case .error = rateValue { return rateValue }
    guard let rate = rateValue.asNumber else { return .error(.value) }
    guard rate > -1 else { return .error(.num) }
    switch datedFlows(args[1], args[2]) {
    case .failure(let box): return box.value
    case .success(let flows):
      return .number(flows.reduce(0) { $0 + $1.value / pow(1 + rate, $1.years) })
    }
  }

  private func evalXIRR(_ args: [FormulaExpr]) -> CellValue {
    guard args.count == 2 || args.count == 3 else { return .error(.value) }
    var guess = 0.1
    if args.count == 3 {
      let g = evaluate(args[2])
      if case .error = g { return g }
      guard let n = g.asNumber else { return .error(.value) }
      guess = n
    }
    switch datedFlows(args[0], args[1]) {
    case .failure(let box): return box.value
    case .success(let flows):
      guard flows.contains(where: { $0.value > 0 }), flows.contains(where: { $0.value < 0 }) else {
        return .error(.num)
      }
      let f: (Double) -> Double = { r in
        flows.reduce(0) { $0 + $1.value / pow(1 + r, $1.years) }
      }
      guard let rate = Self.solve(f, guess: guess) else { return .error(.num) }
      return .number(rate)
    }
  }

  /// A root of `f` near `guess`: Newton's method, then a wider bracket search.
  static func solve(_ f: (Double) -> Double, guess: Double) -> Double? {
    var r = guess
    for _ in 0..<100 {
      let value = f(r)
      guard value.isFinite else { break }
      if abs(value) < 1e-10 { return r }
      let h = max(abs(r) * 1e-6, 1e-8)
      let slope = (f(r + h) - f(r - h)) / (2 * h)
      guard slope != 0, slope.isFinite else { break }
      let next = r - value / slope
      guard next > -1, next.isFinite else { break }
      if abs(next - r) < 1e-12 { return abs(f(next)) < 1e-6 ? next : nil }
      r = next
    }
    // Bisection between rates where the sign changes.
    let points = stride(from: -0.99, through: 10, by: 0.01).map { $0 }
    var previous = points[0]
    var previousValue = f(previous)
    for point in points.dropFirst() {
      let value = f(point)
      if previousValue.isFinite, value.isFinite, (previousValue < 0) != (value < 0) {
        var low = previous
        var high = point
        var lowValue = previousValue
        for _ in 0..<200 {
          let mid = (low + high) / 2
          let midValue = f(mid)
          if abs(midValue) < 1e-10 || high - low < 1e-14 { return mid }
          if (midValue < 0) == (lowValue < 0) {
            low = mid
            lowValue = midValue
          } else {
            high = mid
          }
        }
        return (low + high) / 2
      }
      previous = point
      previousValue = value
    }
    return nil
  }

  // MARK: - Dates

  /// 0 = Sunday ... 6 = Saturday, for a whole-day serial.
  static func weekday(_ serial: Int) -> Int { ((serial % 7) + 6) % 7 }

  private static var utcCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
    return calendar
  }

  private static func ymd(_ serial: Int) -> (year: Int, month: Int, day: Int)? {
    guard let date = ExcelDate.date(from: Double(serial)) else { return nil }
    let parts = utcCalendar.dateComponents([.year, .month, .day], from: date)
    guard let y = parts.year, let m = parts.month, let d = parts.day else { return nil }
    return (y, m, d)
  }

  private static func serial(year: Int, month: Int, day: Int) -> Int? {
    guard
      let date = utcCalendar.date(from: DateComponents(year: year, month: month, day: day))
    else { return nil }
    return Int(ExcelDate.serial(from: date))
  }

  static func isoWeek(_ serial: Int) -> Int {
    // The Thursday of the same Monday-start week decides the year.
    let mondayBased = (weekday(serial) + 6) % 7  // 0 = Monday
    let thursday = serial - mondayBased + 3
    guard let parts = ymd(thursday), let janFirst = Self.serial(year: parts.year, month: 1, day: 1)
    else { return 0 }
    return (thursday - janFirst) / 7 + 1
  }

  private func evalWeeknum(_ args: [FormulaExpr]) -> CellValue {
    guard args.count == 1 || args.count == 2 else { return .error(.value) }
    let value = evaluate(args[0])
    if case .error = value { return value }
    guard let serialNumber = value.asNumber, serialNumber >= 0 else { return .error(.num) }
    var type = 1
    if args.count == 2 {
      let t = evaluate(args[1])
      if case .error = t { return t }
      guard let n = t.asNumber else { return .error(.value) }
      type = Int(n)
    }
    let serial = Int(serialNumber.rounded(.down))
    let startDay: Int  // 0 = Sunday
    switch type {
    case 1, 17: startDay = 0
    case 2, 11: startDay = 1
    case 12...16: startDay = type - 10
    case 21: return .number(Double(Self.isoWeek(serial)))
    default: return .error(.num)
    }
    guard let parts = Self.ymd(serial),
      let janFirst = Self.serial(year: parts.year, month: 1, day: 1)
    else { return .error(.num) }
    let offset = (Self.weekday(janFirst) - startDay + 7) % 7
    return .number(Double((serial - janFirst + offset) / 7 + 1))
  }

  private func evalDatedif(_ args: [FormulaExpr]) -> CellValue {
    guard args.count == 3 else { return .error(.value) }
    let startValue = evaluate(args[0])
    if case .error = startValue { return startValue }
    let endValue = evaluate(args[1])
    if case .error = endValue { return endValue }
    let unitValue = evaluate(args[2])
    if case .error = unitValue { return unitValue }
    guard let s = startValue.asNumber, let e = endValue.asNumber else { return .error(.value) }
    let start = Int(s.rounded(.down))
    let end = Int(e.rounded(.down))
    guard start <= end, start >= 0 else { return .error(.num) }
    guard let a = Self.ymd(start), let b = Self.ymd(end) else { return .error(.num) }
    var months = (b.year - a.year) * 12 + (b.month - a.month)
    if b.day < a.day { months -= 1 }
    switch unitValue.asString.uppercased() {
    case "Y": return .number(Double(months / 12))
    case "M": return .number(Double(months))
    case "D": return .number(Double(end - start))
    case "YM": return .number(Double(months % 12))
    case "MD":
      if b.day >= a.day { return .number(Double(b.day - a.day)) }
      // Days from the start's day in the month before the end's month.
      let previousMonth = b.month == 1 ? 12 : b.month - 1
      let previousYear = b.month == 1 ? b.year - 1 : b.year
      guard let anchor = Self.serial(year: previousYear, month: previousMonth, day: a.day) else {
        return .error(.num)
      }
      return .number(Double(end - anchor))
    case "YD":
      var year = b.year
      if b.month < a.month || (b.month == a.month && b.day < a.day) { year -= 1 }
      guard let anchor = Self.serial(year: year, month: a.month, day: a.day) else {
        return .error(.num)
      }
      return .number(Double(end - anchor))
    default:
      return .error(.num)
    }
  }

  /// Holiday serials from an optional argument.
  private func holidays(_ args: [FormulaExpr], at index: Int) -> Result<Set<Int>, ErrorBox> {
    guard args.count > index else { return .success([]) }
    var days = Set<Int>()
    for value in flatten([args[index]]) {
      switch value {
      case .error: return .failure(ErrorBox(value: value))
      case .number(let n): days.insert(Int(n.rounded(.down)))
      case .blank: continue
      default: return .failure(ErrorBox(value: .error(.value)))
      }
    }
    return .success(days)
  }

  private func evalNetworkdays(_ args: [FormulaExpr]) -> CellValue {
    guard args.count == 2 || args.count == 3 else { return .error(.value) }
    let startValue = evaluate(args[0])
    if case .error = startValue { return startValue }
    let endValue = evaluate(args[1])
    if case .error = endValue { return endValue }
    guard let s = startValue.asNumber, let e = endValue.asNumber else { return .error(.value) }
    let off: Set<Int>
    switch holidays(args, at: 2) {
    case .failure(let box): return box.value
    case .success(let days): off = days
    }
    var a = Int(s.rounded(.down))
    var b = Int(e.rounded(.down))
    let sign = a <= b ? 1.0 : -1.0
    if a > b { swap(&a, &b) }
    guard b - a < 1_000_000 else { return .error(.num) }
    // Whole weeks hold five working days each; count the rest one by one.
    let span = b - a + 1
    var count = span / 7 * 5
    var day = a + span / 7 * 7
    while day <= b {
      let wd = Self.weekday(day)
      if wd != 0, wd != 6 { count += 1 }
      day += 1
    }
    for holiday in off where holiday >= a && holiday <= b {
      let wd = Self.weekday(holiday)
      if wd != 0, wd != 6 { count -= 1 }
    }
    return .number(sign * Double(count))
  }

  private func evalWorkday(_ args: [FormulaExpr]) -> CellValue {
    guard args.count == 2 || args.count == 3 else { return .error(.value) }
    let startValue = evaluate(args[0])
    if case .error = startValue { return startValue }
    let daysValue = evaluate(args[1])
    if case .error = daysValue { return daysValue }
    guard let s = startValue.asNumber, let d = daysValue.asNumber else { return .error(.value) }
    let off: Set<Int>
    switch holidays(args, at: 2) {
    case .failure(let box): return box.value
    case .success(let days): off = days
    }
    var remaining = Int(d.rounded(.towardZero))
    guard abs(remaining) < 1_000_000 else { return .error(.num) }
    var day = Int(s.rounded(.down))
    let step = remaining >= 0 ? 1 : -1
    while remaining != 0 {
      day += step
      let wd = Self.weekday(day)
      if wd != 0, wd != 6, !off.contains(day) { remaining -= step }
    }
    return .number(Double(day))
  }

  // MARK: - Statistics helpers

  static func variance(_ values: [Double], sample: Bool) -> Double? {
    let count = Double(values.count)
    guard count > (sample ? 1 : 0) else { return nil }
    let mean = values.reduce(0, +) / count
    let squares = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
    return squares / (sample ? count - 1 : count)
  }

  static func linearFit(_ pairs: [(x: Double, y: Double)]) -> (
    slope: Double, intercept: Double, correlation: Double?
  )? {
    let n = Double(pairs.count)
    guard n > 0 else { return nil }
    let meanX = pairs.reduce(0) { $0 + $1.x } / n
    let meanY = pairs.reduce(0) { $0 + $1.y } / n
    var sxy = 0.0
    var sxx = 0.0
    var syy = 0.0
    for p in pairs {
      sxy += (p.x - meanX) * (p.y - meanY)
      sxx += (p.x - meanX) * (p.x - meanX)
      syy += (p.y - meanY) * (p.y - meanY)
    }
    guard sxx != 0 else { return nil }
    let slope = sxy / sxx
    let correlation = syy == 0 ? nil : sxy / (sxx * syy).squareRoot()
    return (slope, meanY - slope * meanX, correlation)
  }

  static func gcd(_ a: Int, _ b: Int) -> Int {
    var (x, y) = (a, b)
    while y != 0 { (x, y) = (y, x % y) }
    return x
  }

  /// SWITCH matching: numbers by value, text ignoring case, as other spreadsheet apps do.
  static func sameValue(_ a: CellValue, _ b: CellValue) -> Bool {
    switch (a, b) {
    case (.number(let x), .number(let y)): return x == y
    case (.bool(let x), .bool(let y)): return x == y
    case (.string(let x), .string(let y)): return x.caseInsensitiveCompare(y) == .orderedSame
    case (.blank, .blank): return true
    case (.blank, .string(let s)), (.string(let s), .blank): return s.isEmpty
    case (.blank, .number(let n)), (.number(let n), .blank): return n == 0
    default: return false
    }
  }

  // MARK: - Text

  /// TEXTBEFORE and TEXTAFTER: text, delimiter, [instance], [match_mode], [match_end],
  /// [if_not_found]. A negative instance counts from the end.
  private func evalTextAround(_ args: [FormulaExpr], before: Bool) -> CellValue {
    guard (2...6).contains(args.count) else { return .error(.value) }
    let textValue = evaluate(args[0])
    if case .error = textValue { return textValue }
    let delimiterValue = evaluate(args[1])
    if case .error = delimiterValue { return delimiterValue }
    var numbers: [Double] = [1, 0, 0]
    for (slot, index) in (2..<min(args.count, 5)).enumerated() {
      let value = evaluate(args[index])
      if case .error = value { return value }
      if case .blank = value { continue }
      guard let n = value.asNumber else { return .error(.value) }
      numbers[slot] = n
    }
    let instance = Int(numbers[0].rounded(.towardZero))
    let ignoreCase = numbers[1] != 0
    let matchEnd = numbers[2] != 0
    let text = textValue.asString
    let delimiter = delimiterValue.asString
    guard instance != 0, abs(instance) <= max(text.count, 1) else { return .error(.value) }
    func notFound() -> CellValue {
      args.count == 6 ? evaluate(args[5]) : .error(.na)
    }
    if delimiter.isEmpty {
      return .string(before ? (instance > 0 ? "" : text) : (instance > 0 ? text : ""))
    }
    let options: String.CompareOptions = ignoreCase ? [.caseInsensitive] : []
    var matches: [Range<String.Index>] = []
    var searchStart = text.startIndex
    while searchStart < text.endIndex,
      let found = text.range(of: delimiter, options: options, range: searchStart..<text.endIndex)
    {
      matches.append(found)
      searchStart = found.upperBound
    }
    // Match end treats the end of the text as one more delimiter.
    if matchEnd {
      if instance > 0 {
        matches.append(text.endIndex..<text.endIndex)
      } else {
        matches.insert(text.startIndex..<text.startIndex, at: 0)
      }
    }
    let position = instance > 0 ? instance - 1 : matches.count + instance
    guard position >= 0, position < matches.count else { return notFound() }
    let match = matches[position]
    if before { return .string(String(text[text.startIndex..<match.lowerBound])) }
    return .string(String(text[match.upperBound..<text.endIndex]))
  }
}
