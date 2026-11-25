import Formula
import Foundation
import GridCore
import Model

/// Functions batch 7 for 1.7: bonds and other securities, depreciation (VDB, AMORLINC,
/// AMORDEGRC), small money helpers, CONVERT, complex numbers (COMPLEX and the IM functions) and
/// the Bessel functions.
extension FormulaEvaluator {
  /// Handles a batch 7 function, or returns nil when `name` is not one.
  func evalBatch7(_ name: String, _ args: [FormulaExpr]) -> CellValue? {
    switch name {
    // MARK: Coupons and bonds
    case "COUPDAYBS", "COUPDAYS", "COUPDAYSNC", "COUPNCD", "COUPNUM", "COUPPCD":
      return security(args, dates: 2, numbers: 1, basisAt: 3) { s, m, n, basis in
        let frequency = n[0]
        guard let coupon = Self.coupons(s, m, frequency) else { return .error(.num) }
        switch name {
        case "COUPPCD": return .number(Double(coupon.previous))
        case "COUPNCD": return .number(Double(coupon.next))
        case "COUPNUM": return .number(Double(coupon.count))
        case "COUPDAYBS":
          return .number(Self.dayCount(coupon.previous, s, basis))
        case "COUPDAYS":
          return .number(Self.couponDays(coupon, frequency, basis))
        default:
          return .number(Self.daysToNextCoupon(s, coupon, frequency, basis))
        }
      }
    case "PRICE":
      return security(args, dates: 2, numbers: 4, basisAt: 6) { s, m, n, basis in
        let (rate, yld, redemption, frequency) = (n[0], n[1], n[2], n[3])
        guard rate >= 0, yld >= 0, redemption > 0 else { return .error(.num) }
        return Self.bondPrice(s, m, rate, yld, redemption, frequency, basis)
      }
    case "YIELD":
      return security(args, dates: 2, numbers: 4, basisAt: 6) { s, m, n, basis in
        let (rate, price, redemption, frequency) = (n[0], n[1], n[2], n[3])
        guard rate >= 0, price > 0, redemption > 0 else { return .error(.num) }
        return Self.bondYield(s, m, rate, price, redemption, frequency, basis)
      }
    case "DURATION", "MDURATION":
      return security(args, dates: 2, numbers: 3, basisAt: 5) { s, m, n, basis in
        let (coupon, yld, frequency) = (n[0], n[1], n[2])
        guard coupon >= 0, yld >= 0 else { return .error(.num) }
        let duration = Self.duration(s, m, coupon, yld, frequency, basis)
        guard case .number(let d) = duration, name == "MDURATION" else { return duration }
        return .number(d / (1 + yld / frequency))
      }
    case "ACCRINT":
      guard (6...8).contains(args.count) else { return .error(.value) }
      // ACCRINT(issue, first_interest, settlement, rate, par, frequency, [basis], [calc_method]).
      return numbers7(Array(args.prefix(7))) { a in
        let issue = Int(a[0].rounded(.down))
        let settlement = Int(a[2].rounded(.down))
        let (rate, par, frequency) = (a[3], a[4], a[5])
        let basis = a.count > 6 ? Int(a[6].rounded(.towardZero)) : 0
        let firstInterest = Int(a[1].rounded(.down))
        guard rate > 0, par > 0, [1.0, 2, 4].contains(frequency), (0...4).contains(basis),
          issue < settlement
        else { return .error(.num) }
        // Interest accrues period by period, each counted against its own length, on the coupon
        // dates that lead up to the first interest date.
        let step = 12 / Int(frequency)
        guard let fd = Self.ymd(firstInterest) else { return .error(.num) }
        let endOfMonth = fd.day == Self.monthLength(fd.year, fd.month)
        var k = 0
        var start = firstInterest
        while start > issue {
          k += 1
          start = Self.addingMonths(firstInterest, -step * k, endOfMonth: endOfMonth)
        }
        var total = 0.0
        while start < settlement {
          k -= 1
          let end = Self.addingMonths(firstInterest, -step * k, endOfMonth: endOfMonth)
          let from = max(start, issue)
          let to = min(end, settlement)
          if to > from {
            let length = Self.couponDays(
              Coupon(previous: start, next: end, count: 1), frequency, basis)
            total += Self.dayCount(from, to, basis) / length
          }
          start = end
        }
        return .number(par * rate / frequency * total)
      }
    case "ACCRINTM":
      guard args.count == 4 || args.count == 5 else { return .error(.value) }
      return numbers7(args) { a in
        let issue = Int(a[0].rounded(.down))
        let settlement = Int(a[1].rounded(.down))
        let basis = a.count > 4 ? Int(a[4].rounded(.towardZero)) : 0
        guard a[2] > 0, a[3] > 0, (0...4).contains(basis), issue < settlement else {
          return .error(.num)
        }
        return .number(a[3] * a[2] * Self.yearFraction(issue, settlement, basis))
      }
    case "DISC", "INTRATE", "RECEIVED", "PRICEDISC", "YIELDDISC":
      return security(args, dates: 2, numbers: 2, basisAt: 4, frequencyLast: false) {
        s, m, n, basis in
        let (x, y) = (n[0], n[1])
        guard x > 0, y > 0 else { return .error(.num) }
        let t = Self.yearFraction(s, m, basis)
        switch name {
        case "DISC": return .number((y - x) / y / t)
        case "INTRATE": return .number((y - x) / x / t)
        case "RECEIVED":
          let d = 1 - y * t
          return d > 0 ? .number(x / d) : .error(.num)
        case "PRICEDISC": return .number(y * (1 - x * t))
        default: return .number((y / x - 1) / t)
        }
      }
    case "PRICEMAT", "YIELDMAT":
      // (settlement, maturity, issue, rate, yld or pr, [basis])
      guard args.count == 5 || args.count == 6 else { return .error(.value) }
      return numbers7(args) { a in
        let s = Int(a[0].rounded(.down))
        let m = Int(a[1].rounded(.down))
        let issue = Int(a[2].rounded(.down))
        let basis = a.count > 5 ? Int(a[5].rounded(.towardZero)) : 0
        guard s < m, (0...4).contains(basis), a[3] >= 0, a[4] >= 0 else { return .error(.num) }
        // Days over a year of 360 days (bases 0, 2, 4) or 365 (1, 3), as other apps count.
        let year: Double = basis == 1 || basis == 3 ? 365 : 360
        let issueToMaturity = Self.dayCount(issue, m, basis) / year
        let issueToSettlement = Self.dayCount(issue, s, basis) / year
        let settlementToMaturity = Self.dayCount(s, m, basis) / year
        if name == "PRICEMAT" {
          let price =
            (1 + issueToMaturity * a[3]) / (1 + settlementToMaturity * a[4])
            - issueToSettlement * a[3]
          return .number(price * 100)
        }
        guard a[4] > 0 else { return .error(.num) }
        let y =
          ((1 + issueToMaturity * a[3]) / (a[4] / 100 + issueToSettlement * a[3]) - 1)
          / settlementToMaturity
        return .number(y)
      }
    case "TBILLPRICE", "TBILLYIELD", "TBILLEQ":
      guard args.count == 3 else { return .error(.value) }
      return numbers7(args) { a in
        let s = Int(a[0].rounded(.down))
        let m = Int(a[1].rounded(.down))
        let days = Double(m - s)
        guard m > s, a[2] > 0, Self.addingMonths(s, 12) >= m else { return .error(.num) }
        switch name {
        case "TBILLPRICE":
          let price = 100 * (1 - a[2] * days / 360)
          return price > 0 ? .number(price) : .error(.num)
        case "TBILLYIELD":
          return .number((100 - a[2]) / a[2] * 360 / days)
        default:
          if days <= 182 { return .number(365 * a[2] / (360 - a[2] * days)) }
          let price = 1 - a[2] * days / 360
          let t = days / 365
          let discriminant = t * t - (2 * t - 1) * (1 - 1 / price)
          guard discriminant >= 0 else { return .error(.num) }
          return .number(2 * (discriminant.squareRoot() - t) / (2 * t - 1))
        }
      }

    // MARK: Depreciation and money helpers
    case "VDB": return evalVDB(args)
    case "AMORLINC", "AMORDEGRC":
      guard args.count == 6 || args.count == 7 else { return .error(.value) }
      return numbers7(args) { a in
        let (cost, purchased, firstPeriod, salvage, period, rate) = (
          a[0], Int(a[1].rounded(.down)), Int(a[2].rounded(.down)), a[3], a[4], a[5]
        )
        let basis = a.count > 6 ? Int(a[6].rounded(.towardZero)) : 0
        guard cost >= 0, salvage >= 0, salvage <= cost, period >= 0, rate > 0,
          [0, 1, 3, 4].contains(basis), purchased <= firstPeriod
        else { return .error(.num) }
        let firstFraction = Self.yearFraction(purchased, firstPeriod, basis)
        let periodIndex = Int(period.rounded(.towardZero))
        if name == "AMORLINC" {
          let full = cost * rate
          let first = firstFraction * rate * cost
          let fullPeriods = Int(((cost - salvage - first) / full).rounded(.towardZero))
          if periodIndex == 0 { return .number(first) }
          if periodIndex <= fullPeriods { return .number(full) }
          if periodIndex == fullPeriods + 1 {
            return .number(max(0, cost - salvage - full * Double(fullPeriods) - first))
          }
          return .number(0)
        }
        let life = 1 / rate
        let coefficient = life < 3 ? 1.0 : life < 5 ? 1.5 : life <= 6 ? 2.0 : 2.5
        let r = rate * coefficient
        var amount = (firstFraction * r * cost).rounded()
        var value = cost - amount
        var rest = value - salvage
        if periodIndex == 0 { return .number(amount) }
        for n in 0..<periodIndex {
          amount = (r * value).rounded()
          rest -= amount
          if rest < 0 {
            return .number(periodIndex - n <= 1 ? (value * 0.5).rounded() : 0)
          }
          value -= amount
        }
        return .number(amount)
      }
    case "FVSCHEDULE":
      guard args.count == 2 else { return .error(.value) }
      let principal = evaluate(args[0])
      if case .error = principal { return principal }
      guard var total = principal.asNumber else { return .error(.value) }
      for value in flatten([args[1]]) {
        switch value {
        case .error: return value
        case .number(let r): total *= 1 + r
        case .blank: continue
        default: return .error(.value)
        }
      }
      return .number(total)
    case "DOLLARDE", "DOLLARFR":
      guard args.count == 2 else { return .error(.value) }
      return numbers7(args) { a in
        let fraction = a[1].rounded(.towardZero)
        guard fraction >= 0 else { return .error(.num) }
        guard fraction > 0 else { return .error(.divZero) }
        let whole = a[0].rounded(.towardZero)
        let part = a[0] - whole
        let scale = pow(10, (log10(fraction)).rounded(.up))
        return .number(
          name == "DOLLARDE" ? whole + part * scale / fraction : whole + part * fraction / scale)
      }
    case "PDURATION":
      guard args.count == 3 else { return .error(.value) }
      return numbers7(args) { a in
        guard a[0] > 0, a[1] > 0, a[2] > 0 else { return .error(.num) }
        return .number((log(a[2]) - log(a[1])) / log1p(a[0]))
      }
    case "RRI":
      guard args.count == 3 else { return .error(.value) }
      return numbers7(args) { a in
        guard a[0] > 0, a[1] != 0 else { return .error(.num) }
        return .number(pow(a[2] / a[1], 1 / a[0]) - 1)
      }

    // MARK: Units, complex numbers, Bessel
    case "CONVERT": return evalCONVERT(args)
    case "COMPLEX": return evalCOMPLEX(args)
    case "BESSELJ", "BESSELY", "BESSELI", "BESSELK":
      guard args.count == 2 else { return .error(.value) }
      return numbers7(args) { a in
        let x = a[0]
        let n = a[1].rounded(.towardZero)
        guard n >= 0 else { return .error(.num) }
        let order = Int(n)
        switch name {
        case "BESSELJ": return .number(jn(Int32(order), x))
        case "BESSELY":
          guard x > 0 else { return .error(.num) }
          return .number(yn(Int32(order), x))
        case "BESSELI": return .number(Self.besselI(order, x))
        default:
          guard x > 0 else { return .error(.num) }
          return .number(Self.besselK(Double(order), x))
        }
      }
    default:
      if name.hasPrefix("IM") { return evalComplexFunction(name, args) }
      return nil
    }
  }

  // MARK: - Arguments

  /// Every argument as a number; a missing one as 0. Text that reads as a date or number counts.
  private func numbers7(_ args: [FormulaExpr], _ body: ([Double]) -> CellValue) -> CellValue {
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
        guard let n = Double(text.trimmingCharacters(in: .whitespaces)) ?? Self.dateSerial(text)
        else { return .error(.value) }
        out.append(n)
      }
    }
    let result = body(out)
    if case .number(let n) = result, !n.isFinite { return .error(.num) }
    return result
  }

  /// Settlement and maturity dates (truncated to days), then numbers, then an optional basis.
  /// When the last number is a frequency it must be 1, 2 or 4.
  private func security(
    _ args: [FormulaExpr], dates: Int, numbers count: Int, basisAt: Int,
    frequencyLast: Bool = true, _ body: (Int, Int, [Double], Int) -> CellValue
  ) -> CellValue {
    guard args.count == basisAt || args.count == basisAt + 1 else { return .error(.value) }
    return numbers7(args) { a in
      let s = Int(a[0].rounded(.down))
      let m = Int(a[1].rounded(.down))
      var rest = Array(a[dates..<(dates + count)])
      let basis = a.count > basisAt ? Int(a[basisAt].rounded(.towardZero)) : 0
      guard (0...4).contains(basis), s < m, s >= 0 else { return .error(.num) }
      if frequencyLast, let last = rest.last {
        let frequency = last.rounded(.towardZero)
        guard [1.0, 2, 4].contains(frequency) else { return .error(.num) }
        rest[rest.count - 1] = frequency
      }
      return body(s, m, rest, basis)
    }
  }

  // MARK: - Day counts

  static func yearFraction(_ start: Int, _ end: Int, _ basis: Int) -> Double {
    var evaluator = FormulaEvaluator { _ in .blank }
    evaluator.formulaSheetName = nil
    let value = evaluator.evalYEARFRAC([
      .number(Double(start)), .number(Double(end)), .number(Double(basis)),
    ])
    return value.asNumber ?? 0
  }

  /// Days from `start` to `end` as the basis counts them: 30/360 for 0 and 4, actual otherwise.
  static func dayCount(_ start: Int, _ end: Int, _ basis: Int) -> Double {
    guard basis == 0 || basis == 4, let a = ymd(start), let b = ymd(end) else {
      return Double(end - start)
    }
    var d1 = a.day
    var d2 = b.day
    if basis == 4 {
      d1 = min(d1, 30)
      d2 = min(d2, 30)
    } else {
      let aLastFeb = a.month == 2 && d1 == monthLength(a.year, 2)
      let bLastFeb = b.month == 2 && d2 == monthLength(b.year, 2)
      if aLastFeb && bLastFeb { d2 = 30 }
      if aLastFeb { d1 = 30 }
      if d2 == 31 && d1 >= 30 { d2 = 30 }
      if d1 == 31 { d1 = 30 }
    }
    return Double((b.year - a.year) * 360 + (b.month - a.month) * 30 + (d2 - d1))
  }

  /// The serial `months` months after `serial`; the end of a month stays the end of a month.
  static func addingMonths(_ date: Int, _ months: Int, endOfMonth: Bool = false) -> Int {
    guard let d = ymd(date) else { return date }
    let total = d.year * 12 + (d.month - 1) + months
    let year = total / 12
    let month = total % 12 + 1
    let last = monthLength(year, month)
    let day = endOfMonth ? last : min(d.day, last)
    return serial(year: year, month: month, day: day) ?? date
  }

  struct Coupon {
    var previous: Int
    var next: Int
    var count: Int
  }

  /// The coupon dates around settlement, counted back from maturity.
  static func coupons(_ settlement: Int, _ maturity: Int, _ frequency: Double) -> Coupon? {
    guard [1.0, 2, 4].contains(frequency), settlement < maturity,
      let m = ymd(maturity)
    else { return nil }
    let step = 12 / Int(frequency)
    let endOfMonth = m.day == monthLength(m.year, m.month)
    var count = 0
    var date = maturity
    var later = maturity
    while date > settlement {
      later = date
      count += 1
      date = addingMonths(maturity, -step * count, endOfMonth: endOfMonth)
    }
    return Coupon(previous: date, next: later, count: count)
  }

  static func couponDays(_ coupon: Coupon, _ frequency: Double, _ basis: Int) -> Double {
    switch basis {
    case 1: return Double(coupon.next - coupon.previous)
    case 3: return 365 / frequency
    default: return 360 / frequency
    }
  }

  static func daysToNextCoupon(
    _ settlement: Int, _ coupon: Coupon, _ frequency: Double, _ basis: Int
  )
    -> Double
  {
    switch basis {
    case 0: return couponDays(coupon, frequency, basis) - dayCount(coupon.previous, settlement, 0)
    case 4: return dayCount(settlement, coupon.next, 4)
    default: return Double(coupon.next - settlement)
    }
  }

  static func bondPrice(
    _ s: Int, _ m: Int, _ rate: Double, _ yld: Double, _ redemption: Double, _ frequency: Double,
    _ basis: Int
  ) -> CellValue {
    guard let coupon = coupons(s, m, frequency) else { return .error(.num) }
    let e = couponDays(coupon, frequency, basis)
    let a = dayCount(coupon.previous, s, basis)
    // Other apps take the days to the next coupon as the period less the days gone.
    let dsc = e - a
    let n = Double(coupon.count)
    let payment = 100 * rate / frequency
    let base = 1 + yld / frequency
    if coupon.count == 1 {
      let price = (redemption + payment) / (1 + dsc / e * yld / frequency) - payment * a / e
      return .number(price)
    }
    var price = redemption / pow(base, n - 1 + dsc / e)
    for k in 1...coupon.count {
      price += payment / pow(base, Double(k) - 1 + dsc / e)
    }
    return .number(price - payment * a / e)
  }

  static func bondYield(
    _ s: Int, _ m: Int, _ rate: Double, _ price: Double, _ redemption: Double, _ frequency: Double,
    _ basis: Int
  ) -> CellValue {
    guard let coupon = coupons(s, m, frequency) else { return .error(.num) }
    if coupon.count == 1 {
      // Excel 16.115 takes the period's actual length here for actual/360, not 360 / frequency.
      let e =
        basis == 2 ? Double(coupon.next - coupon.previous) : couponDays(coupon, frequency, basis)
      let a = dayCount(coupon.previous, s, basis)
      let dsr = daysToNextCoupon(s, coupon, frequency, basis)
      let paid = price / 100 + a / e * rate / frequency
      let y = (redemption / 100 + rate / frequency - paid) / paid * frequency * e / dsr
      return .number(y)
    }
    // Price falls as yield rises: search between a yield giving too high a price and one too low.
    func priceAt(_ y: Double) -> Double {
      bondPrice(s, m, rate, y, redemption, frequency, basis).asNumber ?? .nan
    }
    var low = 0.0
    var high = 1.0
    while priceAt(high) > price, high < 1e6 { high *= 2 }
    guard priceAt(low) >= price, priceAt(high) <= price else { return .error(.num) }
    for _ in 0..<200 {
      let mid = (low + high) / 2
      if mid == low || mid == high { break }
      if priceAt(mid) > price { low = mid } else { high = mid }
    }
    return .number((low + high) / 2)
  }

  static func duration(
    _ s: Int, _ m: Int, _ couponRate: Double, _ yld: Double, _ frequency: Double, _ basis: Int
  ) -> CellValue {
    guard let coupon = coupons(s, m, frequency) else { return .error(.num) }
    let n = Double(coupon.count)
    let e = couponDays(coupon, frequency, basis)
    let offset = (e - dayCount(coupon.previous, s, basis)) / e - 1
    let payment = couponRate * 100 / frequency
    let base = yld / frequency + 1
    var weighted = 0.0
    var present = 0.0
    var t = 1.0
    while t < n {
      let discount = pow(base, t + offset)
      weighted += (t + offset) * payment / discount
      present += payment / discount
      t += 1
    }
    let last = pow(base, n + offset)
    weighted += (n + offset) * (payment + 100) / last
    present += (payment + 100) / last
    return .number(weighted / present / frequency)
  }

  // MARK: - VDB

  private static func doubleDeclining(
    _ cost: Double, _ salvage: Double, _ life: Double, _ period: Double, _ factor: Double
  ) -> Double {
    var rate = factor / life
    let old: Double
    if rate >= 1 {
      rate = 1
      old = period == 1 ? cost : 0
    } else {
      old = cost * pow(1 - rate, period - 1)
    }
    let new = cost * pow(1 - rate, period)
    let amount = new < salvage ? old - salvage : old - new
    return max(amount, 0)
  }

  private static func interVDB(
    _ cost: Double, _ salvage: Double, _ life: Double, _ life1: Double, _ period: Double,
    _ factor: Double
  ) -> Double {
    var total = 0.0
    let end = period.rounded(.up)
    var straight = 0.0
    var remaining = cost - salvage
    var switched = false
    var i = 1.0
    while i <= end {
      var term: Double
      if !switched {
        let ddb = doubleDeclining(cost, salvage, life, i, factor)
        straight = remaining / (life1 - (i - 1))
        if straight > ddb {
          term = straight
          switched = true
        } else {
          term = ddb
          remaining -= ddb
        }
      } else {
        term = straight
      }
      if i == end { term *= period + 1 - end }
      total += term
      i += 1
    }
    return total
  }

  private func evalVDB(_ args: [FormulaExpr]) -> CellValue {
    guard (5...7).contains(args.count) else { return .error(.value) }
    return numbers7(args) { a in
      var cost = a[0]
      let (salvage, life, start, end) = (a[1], a[2], a[3], a[4])
      let factor = a.count > 5 && args[5] != .missing ? a[5] : 2
      let noSwitch = a.count > 6 ? a[6] != 0 : false
      guard start >= 0, end >= start, end <= life, cost >= 0, salvage <= cost, factor > 0,
        life > 0
      else { return .error(.num) }
      let intStart = start.rounded(.down)
      let intEnd = end.rounded(.up)
      if noSwitch {
        var total = 0.0
        var i = intStart + 1
        while i <= intEnd {
          var term = Self.doubleDeclining(cost, salvage, life, i, factor)
          if i == intStart + 1 {
            term *= min(end, intStart + 1) - start
          } else if i == intEnd {
            term *= end + 1 - intEnd
          }
          total += term
          i += 1
        }
        return .number(total)
      }
      cost -= Self.interVDB(cost, salvage, life, life, start, factor)
      return .number(Self.interVDB(cost, salvage, life, life - start, end - start, factor))
    }
  }

  // MARK: - CONVERT

  enum UnitGroup {
    case mass, distance, time, pressure, force, energy, power, magnetism, volume, area
    case information, speed, temperature
  }

  /// Each unit's size in its group's base unit (g, m, sec, Pa, N, J, W, T, m3, m2, bit, m/s),
  /// as Excel 16.115 gives them, and whether a metric prefix may go in front.
  static let units: [String: (group: UnitGroup, factor: Double, prefixes: Bool)] = [
    "g": (.mass, 1.0, true),
    "sg": (.mass, 14593.9029372064, false),
    "lbm": (.mass, 453.59237, false),
    "u": (.mass, 1.660538782e-24, true),
    "ozm": (.mass, 28.349523125, false),
    "grain": (.mass, 0.06479891, false),
    "cwt": (.mass, 45359.237, false),
    "shweight": (.mass, 45359.237, false),
    "uk_cwt": (.mass, 50802.34544, false),
    "lcwt": (.mass, 50802.34544, false),
    "hweight": (.mass, 50802.34544, false),
    "stone": (.mass, 6350.29318, false),
    "ton": (.mass, 907184.74, false),
    "uk_ton": (.mass, 1016046.9088, false),
    "LTON": (.mass, 1016046.9088, false),
    "brton": (.mass, 1016046.9088, false),
    "m": (.distance, 1.0, true),
    "mi": (.distance, 1609.344, false),
    "Nmi": (.distance, 1852.0, false),
    "in": (.distance, 0.0254, false),
    "ft": (.distance, 0.3048, false),
    "yd": (.distance, 0.9144, false),
    "ang": (.distance, 1e-10, true),
    "ell": (.distance, 1.143, false),
    "ly": (.distance, 9460730472580800.0, true),
    "parsec": (.distance, 3.08567758128155e+16, true),
    "pc": (.distance, 3.08567758128155e+16, true),
    "Pica": (.distance, 0.000352777777777778, false),
    "Picapt": (.distance, 0.000352777777777778, false),
    "pica": (.distance, 0.00423333333333333, false),
    "survey_mi": (.distance, 1609.34721869444, false),
    "yr": (.time, 31557600.0, false),
    "day": (.time, 86400.0, false),
    "d": (.time, 86400.0, false),
    "hr": (.time, 3600.0, false),
    "mn": (.time, 60.0, false),
    "min": (.time, 60.0, false),
    "sec": (.time, 1.0, true),
    "s": (.time, 1.0, true),
    "Pa": (.pressure, 1.0, true),
    "p": (.pressure, 1.0, true),
    "atm": (.pressure, 101325.0, true),
    "at": (.pressure, 101325.0, true),
    "mmHg": (.pressure, 133.322, true),
    "psi": (.pressure, 6894.75729316836, false),
    "Torr": (.pressure, 133.322368421053, false),
    "N": (.force, 1.0, true),
    "dyn": (.force, 1e-05, true),
    "dy": (.force, 1e-05, true),
    "lbf": (.force, 4.4482216152605, false),
    "pond": (.force, 0.00980665, true),
    "J": (.energy, 1.0, true),
    "e": (.energy, 1e-07, true),
    "c": (.energy, 4.184, true),
    "cal": (.energy, 4.1868, true),
    "eV": (.energy, 1.602176487e-19, true),
    "ev": (.energy, 1.602176487e-19, true),
    "HPh": (.energy, 2684519.53769617, false),
    "hh": (.energy, 2684519.53769617, false),
    "Wh": (.energy, 3600.0, true),
    "wh": (.energy, 3600.0, true),
    "flb": (.energy, 1.3558179483314, false),
    "BTU": (.energy, 1055.05585262, false),
    "btu": (.energy, 1055.05585262, false),
    "HP": (.power, 745.69987158227, false),
    "h": (.power, 745.69987158227, false),
    "PS": (.power, 735.49875, false),
    "W": (.power, 1.0, true),
    "w": (.power, 1.0, true),
    "T": (.magnetism, 1.0, true),
    "ga": (.magnetism, 0.0001, true),
    "tsp": (.volume, 4.92892159375e-06, false),
    "tspm": (.volume, 5e-06, false),
    "tbs": (.volume, 1.478676478125e-05, false),
    "oz": (.volume, 2.95735295625e-05, false),
    "cup": (.volume, 0.0002365882365, false),
    "pt": (.volume, 0.000473176473, false),
    "us_pt": (.volume, 0.000473176473, false),
    "uk_pt": (.volume, 0.00056826125, true),
    "qt": (.volume, 0.000946352946, false),
    "uk_qt": (.volume, 0.0011365225, false),
    "gal": (.volume, 0.003785411784, false),
    "uk_gal": (.volume, 0.00454609, false),
    "l": (.volume, 0.001, true),
    "L": (.volume, 0.001, true),
    "lt": (.volume, 0.001, true),
    "ang3": (.volume, 1e-30, true),
    "ang^3": (.volume, 1e-30, true),
    "barrel": (.volume, 0.158987294928, false),
    "bushel": (.volume, 0.03523907016688, false),
    "ft3": (.volume, 0.028316846592, false),
    "ft^3": (.volume, 0.028316846592, false),
    "in3": (.volume, 1.6387064e-05, false),
    "in^3": (.volume, 1.6387064e-05, false),
    "ly3": (.volume, 8.46786664623715e+47, false),
    "ly^3": (.volume, 8.46786664623715e+47, false),
    "m3": (.volume, 1.0, true),
    "m^3": (.volume, 1.0, true),
    "mi3": (.volume, 4168181825.44058, false),
    "mi^3": (.volume, 4168181825.44058, false),
    "yd3": (.volume, 0.764554857984, false),
    "yd^3": (.volume, 0.764554857984, false),
    "Nmi3": (.volume, 6352182208.0, false),
    "Nmi^3": (.volume, 6352182208.0, false),
    "Pica3": (.volume, 4.39039566186557e-11, false),
    "Pica^3": (.volume, 4.39039566186557e-11, false),
    "Picapt3": (.volume, 4.39039566186557e-11, false),
    "Picapt^3": (.volume, 4.39039566186557e-11, false),
    "GRT": (.volume, 2.8316846592, false),
    "regton": (.volume, 2.8316846592, false),
    "MTON": (.volume, 1.13267386368, false),
    "m2": (.area, 1.0, true),
    "m^2": (.area, 1.0, true),
    "mi2": (.area, 2589988.110336, false),
    "mi^2": (.area, 2589988.110336, false),
    "Nmi2": (.area, 3429904.0, false),
    "Nmi^2": (.area, 3429904.0, false),
    "in2": (.area, 0.00064516, false),
    "in^2": (.area, 0.00064516, false),
    "ft2": (.area, 0.09290304, false),
    "ft^2": (.area, 0.09290304, false),
    "yd2": (.area, 0.83612736, false),
    "yd^2": (.area, 0.83612736, false),
    "ang2": (.area, 1e-20, true),
    "ang^2": (.area, 1e-20, true),
    "Pica2": (.area, 1.24452160493827e-07, false),
    "Pica^2": (.area, 1.24452160493827e-07, false),
    "Picapt2": (.area, 1.24452160493827e-07, false),
    "Picapt^2": (.area, 1.24452160493827e-07, false),
    "Morgen": (.area, 2500.0, false),
    "ar": (.area, 100.0, true),
    "uk_acre": (.area, 4046.8564224, false),
    "us_acre": (.area, 4046.87260987425, false),
    "ly2": (.area, 8.95054210748189e+31, false),
    "ly^2": (.area, 8.95054210748189e+31, false),
    "ha": (.area, 10000.0, false),
    "bit": (.information, 1.0, true),
    "byte": (.information, 8.0, true),
    "m/s": (.speed, 1.0, true),
    "m/sec": (.speed, 1.0, true),
    "m/h": (.speed, 0.000277777777777778, true),
    "m/hr": (.speed, 0.000277777777777778, true),
    "mph": (.speed, 0.44704, true),
    "kn": (.speed, 0.514444444444444, false),
    "admkn": (.speed, 0.514773333333333, false),
    "mm2": (.area, 1e-06, false),
    "km^2": (.area, 1000000.0, false),
    "kmph": (.speed, 447.04, false),
  ]

  private static let prefixes: [(String, Double)] = [
    ("da", 1e1), ("Y", 1e24), ("Z", 1e21), ("E", 1e18), ("P", 1e15), ("T", 1e12), ("G", 1e9),
    ("M", 1e6), ("k", 1e3), ("h", 1e2), ("e", 1e1), ("d", 1e-1), ("c", 1e-2), ("m", 1e-3),
    ("u", 1e-6), ("n", 1e-9), ("p", 1e-12), ("f", 1e-15), ("a", 1e-18), ("z", 1e-21),
    ("y", 1e-24),
  ]
  private static let binaryPrefixes: [(String, Double)] = [
    ("ki", 0x1p10), ("Mi", 0x1p20), ("Gi", 0x1p30), ("Ti", 0x1p40), ("Pi", 0x1p50),
    ("Ei", 0x1p60), ("Zi", 0x1p70), ("Yi", 0x1p80),
  ]
  private static let temperatures: [String: String] = [
    "C": "C", "cel": "C", "F": "F", "fah": "F", "K": "K", "kel": "K", "Rank": "Rank",
    "Reau": "Reau",
  ]

  /// A unit's group and size, the prefix applied; nil when Excel would not know it.
  static func unit(_ text: String) -> (group: UnitGroup, factor: Double, temperature: String?)? {
    if let t = temperatures[text] { return (.temperature, 1, t) }
    if let u = units[text] { return (u.group, u.factor, nil) }
    for (prefix, scale) in binaryPrefixes where text.hasPrefix(prefix) {
      let rest = String(text.dropFirst(prefix.count))
      if rest == "bit" || rest == "byte", let u = units[rest] {
        return (u.group, u.factor * scale, nil)
      }
    }
    for (prefix, scale) in prefixes where text.hasPrefix(prefix) {
      let rest = String(text.dropFirst(prefix.count))
      if rest == "K" || rest == "kel" { return (.temperature, scale, "K") }
      guard let u = units[rest], u.prefixes else { continue }
      let power: Double = rest.hasSuffix("3") ? 3 : rest.hasSuffix("2") ? 2 : 1
      return (u.group, u.factor * pow(scale, power), nil)
    }
    return nil
  }

  private func evalCONVERT(_ args: [FormulaExpr]) -> CellValue {
    guard args.count == 3 else { return .error(.value) }
    let value = evaluate(args[0])
    if case .error = value { return value }
    guard let number = value.asNumber else { return .error(.value) }
    let fromValue = evaluate(args[1])
    let toValue = evaluate(args[2])
    if case .error = fromValue { return fromValue }
    if case .error = toValue { return toValue }
    guard let from = Self.unit(fromValue.asString), let to = Self.unit(toValue.asString),
      from.group == to.group
    else { return .error(.na) }
    if from.group == .temperature, let f = from.temperature, let t = to.temperature {
      let kelvin = Self.toKelvin(number * (f == "K" ? from.factor : 1), f)
      let out = Self.fromKelvin(kelvin, t)
      return .number(t == "K" ? out / to.factor : out)
    }
    return .number(number * from.factor / to.factor)
  }

  private static func toKelvin(_ x: Double, _ unit: String) -> Double {
    switch unit {
    case "C": return x + 273.15
    case "F": return (x - 32) * 5 / 9 + 273.15
    case "Rank": return x * 5 / 9
    case "Reau": return x * 1.25 + 273.15
    default: return x
    }
  }

  private static func fromKelvin(_ k: Double, _ unit: String) -> Double {
    switch unit {
    case "C": return k - 273.15
    case "F": return (k - 273.15) * 9 / 5 + 32
    case "Rank": return k * 9 / 5
    case "Reau": return (k - 273.15) * 0.8
    default: return k
    }
  }

  // MARK: - Complex numbers

  struct Complex {
    var re: Double
    var im: Double
    var suffix: Character = "i"

    var magnitude: Double { hypot(re, im) }
    var argument: Double { atan2(im, re) }
    static func + (a: Complex, b: Complex) -> Complex { Complex(re: a.re + b.re, im: a.im + b.im) }
    static func - (a: Complex, b: Complex) -> Complex { Complex(re: a.re - b.re, im: a.im - b.im) }
    static func * (a: Complex, b: Complex) -> Complex {
      Complex(re: a.re * b.re - a.im * b.im, im: a.re * b.im + a.im * b.re)
    }
    static func / (a: Complex, b: Complex) -> Complex? {
      let d = b.re * b.re + b.im * b.im
      guard d != 0 else { return nil }
      return Complex(re: (a.re * b.re + a.im * b.im) / d, im: (a.im * b.re - a.re * b.im) / d)
    }
    var exp: Complex {
      let e = Foundation.exp(re)
      return Complex(re: e * Foundation.cos(im), im: e * Foundation.sin(im))
    }
    var log: Complex? {
      guard re != 0 || im != 0 else { return nil }
      return Complex(re: Foundation.log(magnitude), im: argument)
    }
    var sin: Complex {
      Complex(
        re: Foundation.sin(re) * Foundation.cosh(im), im: Foundation.cos(re) * Foundation.sinh(im))
    }
    var cos: Complex {
      Complex(
        re: Foundation.cos(re) * Foundation.cosh(im), im: -Foundation.sin(re) * Foundation.sinh(im))
    }
    var sinh: Complex {
      Complex(
        re: Foundation.sinh(re) * Foundation.cos(im), im: Foundation.cosh(re) * Foundation.sin(im))
    }
    var cosh: Complex {
      Complex(
        re: Foundation.cosh(re) * Foundation.cos(im), im: Foundation.sinh(re) * Foundation.sin(im))
    }
  }

  /// "3+4i", "-2.5j", "i", "7": a complex number as text, or nil.
  static func parseComplex(_ text: String) -> Complex? {
    let s = text.trimmingCharacters(in: .whitespaces)
    if s.isEmpty { return Complex(re: 0, im: 0) }
    guard !s.contains(" ") else { return nil }
    if let n = Double(s) { return Complex(re: n, im: 0) }
    guard let last = s.last, last == "i" || last == "j" else { return nil }
    let body = String(s.dropLast())
    // Split before the last sign that is not part of an exponent.
    let chars = Array(body)
    var split: Int?
    var k = chars.count - 1
    while k > 0 {
      if chars[k] == "+" || chars[k] == "-", chars[k - 1] != "e", chars[k - 1] != "E" {
        split = k
        break
      }
      k -= 1
    }
    func coefficient(_ t: String) -> Double? {
      switch t {
      case "", "+": return 1
      case "-": return -1
      default: return Double(t)
      }
    }
    if let split {
      guard let re = Double(String(chars[0..<split])),
        let im = coefficient(String(chars[split...]))
      else { return nil }
      return Complex(re: re, im: im, suffix: last)
    }
    guard let im = coefficient(body) else { return nil }
    return Complex(re: 0, im: im, suffix: last)
  }

  /// Fifteen significant digits, as Excel writes the parts of a complex number.
  private static func complexPart(_ x: Double) -> String {
    let rounded = Double(String(format: "%.15g", x)) ?? x
    if rounded == rounded.rounded(), abs(rounded) < 1e15 {
      return String(format: "%.0f", rounded)
    }
    var text = String(format: "%.15g", rounded)
    if text.contains("e") {
      // 1e-05 as 1E-05, as Excel writes it.
      text = text.replacingOccurrences(of: "e", with: "E")
    }
    return text
  }

  static func formatComplex(_ z: Complex) -> String {
    let re = Double(String(format: "%.15g", z.re)) ?? z.re
    let im = Double(String(format: "%.15g", z.im)) ?? z.im
    if im == 0 { return complexPart(re) }
    let suffix = String(z.suffix)
    let imText: String
    switch im {
    case 1: imText = suffix
    case -1: imText = "-" + suffix
    default: imText = complexPart(im) + suffix
    }
    if re == 0 { return imText }
    return complexPart(re) + (im > 0 ? "+" : "") + imText
  }

  private func complexArgument(_ expr: FormulaExpr) -> Result<Complex, ErrorBox> {
    let value = evaluate(expr)
    switch value {
    case .error: return .failure(ErrorBox(value: value))
    case .number(let n): return .success(Complex(re: n, im: 0))
    case .blank: return .success(Complex(re: 0, im: 0))
    case .bool: return .failure(ErrorBox(value: .error(.value)))
    case .string(let text):
      guard let z = Self.parseComplex(text) else {
        return .failure(ErrorBox(value: .error(.num)))
      }
      return .success(z)
    }
  }

  private func evalCOMPLEX(_ args: [FormulaExpr]) -> CellValue {
    guard args.count == 2 || args.count == 3 else { return .error(.value) }
    let re = evaluate(args[0])
    let im = evaluate(args[1])
    if case .error = re { return re }
    if case .error = im { return im }
    guard let r = re.asNumber, let i = im.asNumber else { return .error(.value) }
    var suffix: Character = "i"
    if args.count == 3, args[2] != .missing {
      let s = evaluate(args[2]).asString
      guard s == "i" || s == "j" || s.isEmpty else { return .error(.value) }
      if s == "j" { suffix = "j" }
    }
    return .string(Self.formatComplex(Complex(re: r, im: i, suffix: suffix)))
  }

  private func evalComplexFunction(_ name: String, _ args: [FormulaExpr]) -> CellValue? {
    let known: Set<String> = [
      "IMABS", "IMAGINARY", "IMARGUMENT", "IMCONJUGATE", "IMCOS", "IMCOSH", "IMCOT", "IMCSC",
      "IMCSCH", "IMDIV", "IMEXP", "IMLN", "IMLOG10", "IMLOG2", "IMPOWER", "IMPRODUCT", "IMREAL",
      "IMSEC", "IMSECH", "IMSIN", "IMSINH", "IMSQRT", "IMSUB", "IMSUM", "IMTAN",
    ]
    guard known.contains(name) else { return nil }
    if name == "IMSUM" || name == "IMPRODUCT" {
      guard !args.isEmpty else { return .error(.value) }
      var total = name == "IMSUM" ? Complex(re: 0, im: 0) : Complex(re: 1, im: 0)
      var suffix: Character?
      for value in flatten(args) {
        let z: Complex
        switch value {
        case .error: return value
        case .number(let n): z = Complex(re: n, im: 0)
        case .blank: continue
        case .bool: return .error(.value)
        case .string(let text):
          guard let parsed = Self.parseComplex(text) else { return .error(.num) }
          z = parsed
          if parsed.im != 0 {
            if let suffix, suffix != parsed.suffix { return .error(.value) }
            suffix = parsed.suffix
          }
        }
        total = name == "IMSUM" ? total + z : total * z
      }
      total.suffix = suffix ?? "i"
      return .string(Self.formatComplex(total))
    }
    let two = name == "IMDIV" || name == "IMSUB" || name == "IMPOWER"
    guard args.count == (two ? 2 : 1) else { return .error(.value) }
    let z: Complex
    switch complexArgument(args[0]) {
    case .failure(let box): return box.value
    case .success(let found): z = found
    }
    func out(_ w: Complex?) -> CellValue {
      guard var w, w.re.isFinite, w.im.isFinite else { return .error(.num) }
      w.suffix = z.suffix
      return .string(Self.formatComplex(w))
    }
    switch name {
    case "IMABS": return .number(z.magnitude)
    case "IMAGINARY": return .number(z.im)
    case "IMREAL": return .number(z.re)
    case "IMARGUMENT":
      guard z.re != 0 || z.im != 0 else { return .error(.divZero) }
      return .number(z.argument)
    case "IMCONJUGATE": return out(Complex(re: z.re, im: -z.im))
    case "IMCOS": return out(z.cos)
    case "IMCOSH": return out(z.cosh)
    case "IMSIN": return out(z.sin)
    case "IMSINH": return out(z.sinh)
    case "IMTAN", "IMCOT":
      // tan z = (sin 2x + i sinh 2y) / (cos 2x + cosh 2y), which keeps more digits than sin/cos.
      let (x2, y2) = (2 * z.re, 2 * z.im)
      if name == "IMTAN" {
        let d = Foundation.cos(x2) + Foundation.cosh(y2)
        guard d != 0 else { return .error(.num) }
        return out(Complex(re: Foundation.sin(x2) / d, im: Foundation.sinh(y2) / d))
      }
      let d = Foundation.cosh(y2) - Foundation.cos(x2)
      guard d != 0 else { return .error(.num) }
      return out(Complex(re: Foundation.sin(x2) / d, im: -Foundation.sinh(y2) / d))
    case "IMSEC", "IMCSC":
      let (x, y) = (z.re, z.im)
      if name == "IMSEC" {
        let d = Foundation.cos(2 * x) + Foundation.cosh(2 * y)
        guard d != 0 else { return .error(.num) }
        return out(
          Complex(
            re: 2 * Foundation.cos(x) * Foundation.cosh(y) / d,
            im: 2 * Foundation.sin(x) * Foundation.sinh(y) / d))
      }
      let d = Foundation.cosh(2 * y) - Foundation.cos(2 * x)
      guard d != 0 else { return .error(.num) }
      return out(
        Complex(
          re: 2 * Foundation.sin(x) * Foundation.cosh(y) / d,
          im: -2 * Foundation.cos(x) * Foundation.sinh(y) / d))
    case "IMSECH": return out(Complex(re: 1, im: 0) / z.cosh)
    case "IMCSCH": return out(Complex(re: 1, im: 0) / z.sinh)
    case "IMEXP": return out(z.exp)
    case "IMLN": return out(z.log)
    case "IMLOG10", "IMLOG2":
      guard let ln = z.log else { return .error(.num) }
      let base = name == "IMLOG10" ? log(10.0) : log(2.0)
      return out(Complex(re: ln.re / base, im: ln.im / base))
    case "IMSQRT":
      let r = z.magnitude.squareRoot()
      let t = z.argument / 2
      return out(Complex(re: r * Foundation.cos(t), im: r * Foundation.sin(t)))
    case "IMDIV", "IMSUB":
      let w: Complex
      switch complexArgument(args[1]) {
      case .failure(let box): return box.value
      case .success(let found): w = found
      }
      if z.im != 0, w.im != 0, z.suffix != w.suffix { return .error(.value) }
      if name == "IMSUB" { return out(z - w) }
      return out(z / w)
    default:
      let p = evaluate(args[1])
      if case .error = p { return p }
      guard let power = p.asNumber else { return .error(.value) }
      if z.re == 0 && z.im == 0 { return power > 0 ? .string("0") : .error(.num) }
      let r = pow(z.magnitude, power)
      let t = z.argument * power
      return out(Complex(re: r * Foundation.cos(t), im: r * Foundation.sin(t)))
    }
  }

  // MARK: - Bessel

  /// I_n(x) by its power series, which has no cancellation.
  static func besselI(_ n: Int, _ x: Double) -> Double {
    let half = x / 2
    var term = pow(half, Double(n)) / tgamma(Double(n) + 1)
    var sum = term
    var k = 1.0
    while k < 500 {
      term *= half * half / (k * (k + Double(n)))
      sum += term
      if abs(term) < abs(sum) * 1e-17 { break }
      k += 1
    }
    return sum
  }

  /// K_v(x) = ∫₀^∞ exp(-x cosh t) cosh(v t) dt, by the trapezoid rule, which converges very fast
  /// for a smooth integrand that falls off this quickly.
  static func besselK(_ v: Double, _ x: Double) -> Double {
    let h = 0.02
    var sum = 0.5 * exp(-x)
    var t = h
    while t < 50 {
      let term = exp(-x * cosh(t) + v * t) * 0.5 * (1 + exp(-2 * v * t))
      sum += term
      if term < sum * 1e-18 { break }
      t += h
    }
    return sum * h
  }
}
