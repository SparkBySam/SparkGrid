import Formula
import Foundation
import GridCore
import Model

/// Functions batch 4 for 1.7 (Sam, Nov 20: "add more functions"): SUBTOTAL and AGGREGATE, the
/// database functions, NETWORKDAYS.INTL and WORKDAY.INTL, SHEET, SHEETS, FORMULATEXT and AREAS,
/// number bases and bits, the rest of the trigonometry, rounding and counting functions, and
/// text functions for values, arrays, Thai baht and web addresses.
extension FormulaEvaluator {
  /// Handles a batch 4 function, or returns nil when `name` is not one.
  func evalBatch4(_ name: String, _ args: [FormulaExpr]) -> CellValue? {
    switch name {
    // MARK: Subtotals
    case "SUBTOTAL": return evalSUBTOTAL(args)
    case "AGGREGATE": return evalAGGREGATE(args)

    // MARK: Database
    case "DAVERAGE", "DCOUNT", "DCOUNTA", "DGET", "DMAX", "DMIN", "DPRODUCT", "DSTDEV",
      "DSTDEVP", "DSUM", "DVAR", "DVARP":
      return evalDatabase(name, args)

    // MARK: Dates
    case "NETWORKDAYS.INTL": return evalNetworkdaysIntl(args)
    case "WORKDAY.INTL": return evalWorkdayIntl(args)

    // MARK: Information
    case "SHEET": return evalSHEET(args)
    case "SHEETS":
      guard args.count <= 1 else { return .error(.value) }
      if args.isEmpty { return .number(Double(max(sheetNames().count, 1))) }
      return Self.isReference(args[0]) ? .number(1) : .error(.value)
    case "FORMULATEXT": return evalFORMULATEXT(args)
    case "AREAS":
      guard args.count == 1 else { return .error(.value) }
      return Self.isReference(args[0]) ? .number(1) : .error(.value)

    // MARK: Trigonometry
    case "COT": return oneNumber(args) { x in Self.reciprocal(x, big: true) { tan($0) } }
    case "CSC": return oneNumber(args) { x in Self.reciprocal(x, big: true) { sin($0) } }
    case "SEC": return oneNumber(args) { x in Self.reciprocal(x, big: true) { cos($0) } }
    case "COTH": return oneNumber(args) { x in Self.reciprocal(x, big: true) { tanh($0) } }
    case "CSCH": return oneNumber(args) { x in Self.reciprocal(x, big: true) { sinh($0) } }
    case "SECH": return oneNumber(args) { x in Self.reciprocal(x, big: true) { cosh($0) } }
    case "ACOT": return oneNumber(args) { .number(.pi / 2 - atan($0)) }
    case "ACOTH":
      return oneNumber(args) { x in
        abs(x) > 1 ? .number(0.5 * log((x + 1) / (x - 1))) : .error(.num)
      }

    // MARK: Rounding and counting
    case "CEILING.PRECISE", "ISO.CEILING", "FLOOR.PRECISE":
      return evalPreciseRounding(args, up: name != "FLOOR.PRECISE")
    case "COMBINA":
      return twoNumbers(args) { n, k in
        let n = n.rounded(.towardZero)
        let k = k.rounded(.towardZero)
        guard n >= 0, k >= 0 else { return .error(.num) }
        if k == 0 { return .number(1) }
        return Self.combinations(n + k - 1, k)
      }
    case "PERMUTATIONA":
      return twoNumbers(args) { n, k in
        let n = n.rounded(.towardZero)
        let k = k.rounded(.towardZero)
        guard n >= 0, k >= 0 else { return .error(.num) }
        let result = pow(n, k)
        return result.isFinite ? .number(result) : .error(.num)
      }
    case "FACTDOUBLE":
      return oneNumber(args) { x in
        let n = x.rounded(.towardZero)
        guard n >= -1 else { return .error(.num) }
        var result = 1.0
        var i = n
        while i > 1 {
          result *= i
          i -= 2
        }
        return result.isFinite ? .number(result) : .error(.num)
      }
    case "MULTINOMIAL":
      let numbers = numbersIn(args)
      if let error = numbers.error { return error }
      var sum = 0.0
      var logDenominator = 0.0
      for value in numbers.values {
        let n = value.rounded(.towardZero)
        guard n >= 0 else { return .error(.num) }
        sum += n
        logDenominator += lgamma(n + 1)
      }
      let result = exp(lgamma(sum + 1) - logDenominator)
      return result.isFinite ? .number(result.rounded()) : .error(.num)
    case "SERIESSUM": return evalSERIESSUM(args)
    case "SUMX2MY2", "SUMX2PY2", "SUMXMY2":
      guard args.count == 2 else { return .error(.value) }
      let pairs: [(x: Double, y: Double)]
      switch numberPairs(args[0], args[1]) {
      case .failure(let error): return error.value
      case .success(let found): pairs = found
      }
      switch name {
      case "SUMX2MY2": return .number(pairs.map { $0.x * $0.x - $0.y * $0.y }.reduce(0, +))
      case "SUMX2PY2": return .number(pairs.map { $0.x * $0.x + $0.y * $0.y }.reduce(0, +))
      default: return .number(pairs.map { ($0.x - $0.y) * ($0.x - $0.y) }.reduce(0, +))
      }
    case "GAMMA":
      return oneNumber(args) { x in
        if x <= 0, x == x.rounded() { return .error(.num) }
        let result = tgamma(x)
        return result.isFinite ? .number(result) : .error(.num)
      }
    case "GAMMALN", "GAMMALN.PRECISE":
      return oneNumber(args) { $0 > 0 ? .number(lgamma($0)) : .error(.num) }
    case "GAUSS": return oneNumber(args) { .number(Self.normalCDF($0) - 0.5) }
    case "PHI": return oneNumber(args) { .number(Self.normalPDF($0)) }

    // MARK: Roman numerals and bases
    case "ROMAN": return evalROMAN(args)
    case "ARABIC": return evalARABIC(args)
    case "BASE": return evalBASE(args)
    case "DECIMAL": return evalDECIMAL(args)

    // MARK: Engineering
    case "BIN2DEC", "BIN2HEX", "BIN2OCT", "OCT2BIN", "OCT2DEC", "OCT2HEX", "HEX2BIN", "HEX2DEC",
      "HEX2OCT":
      return evalFromBase(name, args)
    case "DEC2BIN", "DEC2HEX", "DEC2OCT":
      return evalFromDecimal(name, args)
    case "BITAND", "BITOR", "BITXOR":
      return twoNumbers(args) { a, b in
        guard let x = Self.bitOperand(a), let y = Self.bitOperand(b) else { return .error(.num) }
        switch name {
        case "BITAND": return .number(Double(x & y))
        case "BITOR": return .number(Double(x | y))
        default: return .number(Double(x ^ y))
        }
      }
    case "BITLSHIFT", "BITRSHIFT":
      return twoNumbers(args) { a, b in
        guard let x = Self.bitOperand(a), b == b.rounded(.towardZero), abs(b) <= 53 else {
          return .error(.num)
        }
        let shift = Int(b) * (name == "BITLSHIFT" ? 1 : -1)
        let result = shift >= 0 ? Double(x) * pow(2, Double(shift)) : Double(x >> -shift)
        return result < Self.bitLimit ? .number(result) : .error(.num)
      }
    case "DELTA":
      guard args.count == 1 || args.count == 2 else { return .error(.value) }
      return numbersWithDefaults(args, defaults: [nil, 0]) { .number($0[0] == $0[1] ? 1 : 0) }
    case "GESTEP":
      guard args.count == 1 || args.count == 2 else { return .error(.value) }
      return numbersWithDefaults(args, defaults: [nil, 0]) { .number($0[0] >= $0[1] ? 1 : 0) }
    case "ERF":
      guard args.count == 1 || args.count == 2 else { return .error(.value) }
      return numbersWithDefaults(args, defaults: [nil, nil]) { a in
        a.count == 1 ? .number(erf(a[0])) : .number(erf(a[1]) - erf(a[0]))
      }
    case "ERF.PRECISE": return oneNumber(args) { .number(erf($0)) }
    case "ERFC", "ERFC.PRECISE": return oneNumber(args) { .number(erfc($0)) }

    // MARK: Text
    case "LENB": return evaluate(.call("LEN", args))
    case "LEFTB": return evaluate(.call("LEFT", args))
    case "RIGHTB": return evaluate(.call("RIGHT", args))
    case "MIDB": return evaluate(.call("MID", args))
    case "FINDB": return evaluate(.call("FIND", args))
    case "SEARCHB": return evaluate(.call("SEARCH", args))
    case "REPLACEB": return evaluate(.call("REPLACE", args))
    case "ASC", "DBCS":
      // Other apps change the width of letters only with an East Asian language turned on;
      // otherwise the text comes back as it was (Excel 16.115).
      guard args.count == 1 else { return .error(.value) }
      let value = evaluate(args[0])
      if case .error = value { return value }
      return .string(value.asString)
    case "VALUETOTEXT": return evalVALUETOTEXT(args)
    case "ARRAYTOTEXT": return evalARRAYTOTEXT(args)
    case "BAHTTEXT":
      return oneNumber(args) { .string(Self.bahtText($0)) }
    case "ENCODEURL":
      guard args.count == 1 else { return .error(.value) }
      let value = evaluate(args[0])
      if case .error = value { return value }
      return .string(Self.encodeURL(value.asString))
    default:
      return nil
    }
  }

  // MARK: - Shared

  static func isReference(_ expr: FormulaExpr) -> Bool {
    switch expr {
    case .cellRef, .range, .namedRange: return true
    case .call(let name, _):
      return ["INDEX", "OFFSET", "INDIRECT", FormulaExpr.rangeOperatorFunction]
        .contains(plainFunctionName(name))
    default: return false
    }
  }

  /// 1 over a trigonometric function. Excel answers #NUM! from 2^27 on for the circular ones.
  private static func reciprocal(_ x: Double, big: Bool, _ f: (Double) -> Double) -> CellValue {
    if big, abs(x) >= 134_217_728 { return .error(.num) }
    let d = f(x)
    guard d != 0 else { return .error(.divZero) }
    let result = 1 / d
    return result.isFinite ? .number(result) : .error(.num)
  }

  static func combinations(_ n: Double, _ k: Double) -> CellValue {
    var result = 1.0
    let steps = min(k, n - k)
    var i = 0.0
    while i < steps {
      result = result * (n - i) / (i + 1)
      i += 1
    }
    return result.isFinite ? .number(result.rounded()) : .error(.num)
  }

  /// Numbers for each argument. One left out takes its default; with no default it is required,
  /// unless it is past the end (an optional argument with no default, as ERF's second).
  private func numbersWithDefaults(
    _ args: [FormulaExpr], defaults: [Double?], _ body: ([Double]) -> CellValue
  ) -> CellValue {
    var numbers: [Double] = []
    for (index, fallback) in defaults.enumerated() {
      if index >= args.count || args[index] == .missing {
        if let fallback {
          numbers.append(fallback)
          continue
        }
        if index >= args.count { break }
        return .error(.value)
      }
      let value = evaluate(args[index])
      switch value {
      case .error: return value
      case .number(let n): numbers.append(n)
      case .blank: numbers.append(0)
      case .bool: return .error(.value)
      case .string(let text):
        guard let n = Double(text.trimmingCharacters(in: .whitespaces)) else {
          return .error(.value)
        }
        numbers.append(n)
      }
    }
    let result = body(numbers)
    if case .number(let n) = result, !n.isFinite { return .error(.num) }
    return result
  }

  // MARK: - SUBTOTAL and AGGREGATE

  /// One value read from a SUBTOTAL or AGGREGATE argument.
  private enum Pick {
    case value(CellValue)
    case skip
  }

  /// The values of a reference argument cell by cell, leaving out nested SUBTOTAL and AGGREGATE
  /// cells and, when asked, hidden rows. A value that is not a reference is read whole.
  private func subtotalValues(
    _ expr: FormulaExpr, skipNested: Bool, skipHidden: Bool, skipFiltered: Bool
  ) -> [CellValue] {
    let bounds: (sheet: String, rows: ClosedRange<Int>, cols: ClosedRange<Int>)?
    switch expr {
    case .cellRef(let ref):
      bounds = (ref.sheet ?? formulaSheetName ?? "", ref.row...ref.row, ref.col...ref.col)
    case .range(let start, let end):
      let n = normalizedBounds(start: start, end: end)
      guard n.maxRow >= n.minRow, n.maxCol >= n.minCol else { return [.error(.ref)] }
      bounds = (start.sheet ?? formulaSheetName ?? "", n.minRow...n.maxRow, n.minCol...n.maxCol)
    default:
      bounds = nil
    }
    guard let bounds else {
      if Self.isReference(expr), let target = referenceTarget(expr) {
        return subtotalValues(
          target, skipNested: skipNested, skipHidden: skipHidden, skipFiltered: skipFiltered)
      }
      return evaluateArray(expr).values
    }
    let values = evaluateArray(expr).values
    let cols = bounds.cols.count
    var out: [CellValue] = []
    out.reserveCapacity(values.count)
    for (index, value) in values.enumerated() {
      let row = bounds.rows.lowerBound + index / cols
      let col = bounds.cols.lowerBound + index % cols
      if skipHidden, rowHidden(bounds.sheet, row) { continue }
      if skipFiltered || skipHidden, rowFiltered(bounds.sheet, row) { continue }
      if skipNested, let formula = formulaText(bounds.sheet, CellAddress(row: row, col: col)),
        Self.callsSubtotal(formula)
      {
        continue
      }
      out.append(value)
    }
    return out
  }

  private func referenceTarget(_ expr: FormulaExpr) -> FormulaExpr? {
    switch expr {
    case .namedRange(let name): return namedRangeLookup(name)
    case .call(let name, let args): return referenceFunctionTarget(name, args)
    default: return nil
    }
  }

  private static func callsSubtotal(_ formula: String) -> Bool {
    let upper = formula.uppercased()
    return upper.contains("SUBTOTAL(") || upper.contains("AGGREGATE(")
  }

  private func evalSUBTOTAL(_ args: [FormulaExpr]) -> CellValue {
    guard args.count >= 2 else { return .error(.value) }
    let kind = evaluate(args[0])
    if case .error = kind { return kind }
    guard let number = kind.asNumber else { return .error(.value) }
    let code = Int(number.rounded(.towardZero))
    let base = code > 100 ? code - 100 : code
    guard (1...11).contains(base) else { return .error(.value) }
    var values: [CellValue] = []
    for arg in args.dropFirst() {
      guard Self.isReference(arg) else { return .error(.value) }
      values += subtotalValues(
        arg, skipNested: true, skipHidden: code > 100, skipFiltered: true)
    }
    return aggregate(base, values, k: nil, skipErrors: false)
  }

  private func evalAGGREGATE(_ args: [FormulaExpr]) -> CellValue {
    guard args.count >= 3 else { return .error(.value) }
    let kind = evaluate(args[0])
    if case .error = kind { return kind }
    let optionValue = args[1] == .missing ? .number(0) : evaluate(args[1])
    if case .error = optionValue { return optionValue }
    guard let f = kind.asNumber, let o = optionValue.asNumber else { return .error(.value) }
    let function = Int(f.rounded(.towardZero))
    let option = Int(o.rounded(.towardZero))
    guard (1...19).contains(function), (0...7).contains(option) else { return .error(.value) }
    let skipNested = option <= 3
    let skipHidden = [1, 3, 5, 7].contains(option)
    let skipErrors = [2, 3, 6, 7].contains(option)
    if function >= 14 {
      guard args.count == 4 else { return .error(.value) }
      let kValue = evaluate(args[3])
      if case .error = kValue { return kValue }
      guard let k = kValue.asNumber else { return .error(.value) }
      let values =
        Self.isReference(args[2])
        ? subtotalValues(
          args[2], skipNested: skipNested, skipHidden: skipHidden, skipFiltered: skipHidden)
        : evaluateArray(args[2]).values
      return aggregate(function, values, k: k, skipErrors: skipErrors)
    }
    var values: [CellValue] = []
    for arg in args.dropFirst(2) {
      guard Self.isReference(arg) else { return .error(.value) }
      values += subtotalValues(
        arg, skipNested: skipNested, skipHidden: skipHidden, skipFiltered: skipHidden)
    }
    return aggregate(function, values, k: nil, skipErrors: skipErrors)
  }

  /// AGGREGATE's 19 functions over values read from cells: numbers count, text and TRUE do not.
  private func aggregate(_ function: Int, _ values: [CellValue], k: Double?, skipErrors: Bool)
    -> CellValue
  {
    var numbers: [Double] = []
    var nonBlank = 0
    for value in values {
      switch value {
      case .error:
        if skipErrors { continue }
        // COUNT leaves errors out and COUNTA counts them, as SUBTOTAL 2 and 3 do.
        if function == 2 { continue }
        if function == 3 {
          nonBlank += 1
          continue
        }
        return value
      case .number(let n):
        numbers.append(n)
        nonBlank += 1
      case .blank: continue
      default: nonBlank += 1
      }
    }
    let n = Double(numbers.count)
    switch function {
    case 1: return numbers.isEmpty ? .error(.divZero) : .number(numbers.reduce(0, +) / n)
    case 2: return .number(n)
    case 3: return .number(Double(nonBlank))
    case 4: return .number(numbers.max() ?? 0)
    case 5: return .number(numbers.min() ?? 0)
    case 6: return .number(numbers.isEmpty ? 0 : numbers.reduce(1, *))
    case 7, 8, 10, 11:
      guard let variance = Self.variance(numbers, sample: function == 7 || function == 10) else {
        return .error(.divZero)
      }
      return .number(function <= 8 ? variance.squareRoot() : variance)
    case 9: return .number(numbers.reduce(0, +))
    case 12:
      guard !numbers.isEmpty else { return .error(.num) }
      let sorted = numbers.sorted()
      let mid = sorted.count / 2
      return .number(sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2)
    case 13:
      var counts: [Double: Int] = [:]
      var best: (value: Double, count: Int)?
      for x in numbers {
        counts[x, default: 0] += 1
        let c = counts[x] ?? 0
        if c > 1, c > (best?.count ?? 1) { best = (x, c) }
      }
      return best.map { .number($0.value) } ?? .error(.na)
    case 14, 15:
      guard let k, k >= 1, Int(k.rounded(.up)) <= numbers.count else { return .error(.num) }
      let sorted = function == 14 ? numbers.sorted(by: >) : numbers.sorted()
      return .number(sorted[Int(k.rounded(.up)) - 1])
    default:
      guard let k, !numbers.isEmpty else { return .error(.num) }
      let sorted = numbers.sorted()
      switch function {
      case 16: return Self.percentileInclusive(sorted, k)
      case 17:
        let q = k.rounded(.towardZero)
        guard q >= 0, q <= 4 else { return .error(.num) }
        return Self.percentileInclusive(sorted, q / 4)
      case 18: return Self.percentileExclusive(sorted, k)
      default:
        let q = k.rounded(.towardZero)
        guard q >= 1, q <= 3 else { return .error(.num) }
        return Self.percentileExclusive(sorted, q / 4)
      }
    }
  }

  static func percentileInclusive(_ sorted: [Double], _ k: Double) -> CellValue {
    guard k >= 0, k <= 1, !sorted.isEmpty else { return .error(.num) }
    let h = Double(sorted.count - 1) * k
    let low = Int(h.rounded(.down))
    let high = min(low + 1, sorted.count - 1)
    return .number(sorted[low] + (h - Double(low)) * (sorted[high] - sorted[low]))
  }

  static func percentileExclusive(_ sorted: [Double], _ k: Double) -> CellValue {
    let n = Double(sorted.count)
    guard k > 0, k < 1, k >= 1 / (n + 1), k <= n / (n + 1) else { return .error(.num) }
    let h = (n + 1) * k - 1
    let low = Int(h.rounded(.down))
    let high = min(low + 1, sorted.count - 1)
    return .number(sorted[low] + (h - Double(low)) * (sorted[high] - sorted[low]))
  }

  // MARK: - Database functions

  private func evalDatabase(_ name: String, _ args: [FormulaExpr]) -> CellValue {
    let fieldOptional = name == "DCOUNT" || name == "DCOUNTA"
    guard args.count == 3 || (fieldOptional && args.count == 2) else { return .error(.value) }
    let database = evaluateArray(args[0])
    let criteria = evaluateArray(args[args.count - 1])
    guard database.rows >= 1, criteria.rows >= 2 else { return .error(.value) }
    let headers = database.row(0).map { $0.asString.trimmingCharacters(in: .whitespaces) }
    func column(named label: String) -> Int? {
      headers.firstIndex { $0.caseInsensitiveCompare(label) == .orderedSame }
    }
    // The field, by header text or by number counting from 1; left out, the whole record.
    var field: Int?
    if args.count == 3, args[1] != .missing {
      let value = evaluate(args[1])
      switch value {
      case .error: return value
      case .number(let n):
        let index = Int(n.rounded(.towardZero)) - 1
        guard index >= 0, index < database.cols else { return .error(.value) }
        field = index
      case .string(let text):
        guard let index = column(named: text.trimmingCharacters(in: .whitespaces)) else {
          return .error(.value)
        }
        field = index
      default: return .error(.value)
      }
    } else if !fieldOptional {
      return .error(.value)
    }
    // Criteria: a row of headers, then rows of conditions. Conditions in one row must all hold;
    // any one row holding is enough. Text such as "Dav" matches text that starts with it.
    let criteriaHeaders = criteria.row(0).map { $0.asString.trimmingCharacters(in: .whitespaces) }
    var rules: [[(column: Int, test: CriteriaTest)]] = []
    for r in 1..<criteria.rows {
      var rule: [(column: Int, test: CriteriaTest)] = []
      for c in 0..<criteria.cols {
        let condition = criteria.value(row: r, col: c)
        if case .blank = condition { continue }
        if case .string(let s) = condition, s.isEmpty { continue }
        guard let target = column(named: criteriaHeaders[c]) else { continue }
        rule.append((target, criteriaTest(from: Self.databaseCondition(condition))))
      }
      rules.append(rule)
    }
    var picked: [CellValue] = []
    var records = 0
    for r in 1..<max(database.rows, 1) {
      let matches = rules.contains { rule in
        rule.allSatisfy { criteriaMatch(database.value(row: r, col: $0.column), $0.test) }
      }
      guard matches else { continue }
      records += 1
      if let field { picked.append(database.value(row: r, col: field)) }
    }
    switch name {
    case "DCOUNT":
      guard field != nil else { return .number(Double(records)) }
      return .number(Double(picked.filter { if case .number = $0 { true } else { false } }.count))
    case "DCOUNTA":
      guard field != nil else { return .number(Double(records)) }
      return .number(Double(picked.filter { if case .blank = $0 { false } else { true } }.count))
    case "DGET":
      guard !picked.isEmpty else { return .error(.value) }
      guard picked.count == 1 else { return .error(.num) }
      if case .blank = picked[0] { return .number(0) }
      return picked[0]
    default:
      let code = [
        "DAVERAGE": 1, "DMAX": 4, "DMIN": 5, "DPRODUCT": 6, "DSTDEV": 7, "DSTDEVP": 8,
        "DSUM": 9, "DVAR": 10, "DVARP": 11,
      ][name, default: 9]
      return aggregate(code, picked, k: nil, skipErrors: false)
    }
  }

  /// A criteria cell as a COUNTIF-style condition: plain text matches text starting with it.
  private static func databaseCondition(_ value: CellValue) -> CellValue {
    guard case .string(let text) = value else { return value }
    if let first = text.first, "<>=".contains(first) { return value }
    if Double(text.trimmingCharacters(in: .whitespaces)) != nil { return value }
    return .string(text + "*")
  }

  // MARK: - NETWORKDAYS.INTL and WORKDAY.INTL

  /// The days of the week that are weekend, Sunday 0 to Saturday 6, from a weekend number or
  /// a seven-letter string of 0 and 1 starting on Monday. Nil for an error.
  private func weekendDays(_ args: [FormulaExpr], at index: Int, allowAll: Bool)
    -> Result<Set<Int>, ErrorBox>
  {
    guard index < args.count, args[index] != .missing else { return .success([0, 6]) }
    let value = evaluate(args[index])
    switch value {
    case .error: return .failure(ErrorBox(value: value))
    case .blank: return .success([0, 6])
    case .string(let text):
      guard text.count == 7, text.allSatisfy({ $0 == "0" || $0 == "1" }),
        allowAll || text != "1111111"
      else { return .failure(ErrorBox(value: .error(.value))) }
      var days = Set<Int>()
      for (offset, flag) in text.enumerated() where flag == "1" { days.insert((offset + 1) % 7) }
      return .success(days)
    default:
      guard let n = value.asNumber else { return .failure(ErrorBox(value: .error(.value))) }
      let code = Int(n.rounded(.towardZero))
      switch code {
      case 1...7:
        // 1 is Saturday and Sunday, 2 Sunday and Monday, ... 7 Friday and Saturday.
        let first = (code + 5) % 7
        return .success([first, (first + 1) % 7])
      case 11...17: return .success([(code - 11) % 7])
      default: return .failure(ErrorBox(value: .error(.num)))
      }
    }
  }

  private func evalNetworkdaysIntl(_ args: [FormulaExpr]) -> CellValue {
    guard (2...4).contains(args.count) else { return .error(.value) }
    let startValue = evaluate(args[0])
    if case .error = startValue { return startValue }
    let endValue = evaluate(args[1])
    if case .error = endValue { return endValue }
    guard let s = startValue.asNumber, let e = endValue.asNumber else { return .error(.value) }
    let weekend: Set<Int>
    switch weekendDays(args, at: 2, allowAll: true) {
    case .failure(let box): return box.value
    case .success(let days): weekend = days
    }
    let off: Set<Int>
    switch holidays(args, at: 3) {
    case .failure(let box): return box.value
    case .success(let days): off = days
    }
    var a = Int(s.rounded(.down))
    var b = Int(e.rounded(.down))
    let sign = a <= b ? 1.0 : -1.0
    if a > b { swap(&a, &b) }
    guard b - a < 1_000_000 else { return .error(.num) }
    let span = b - a + 1
    var count = span / 7 * (7 - weekend.count)
    var day = a + span / 7 * 7
    while day <= b {
      if !weekend.contains(Self.weekday(day)) { count += 1 }
      day += 1
    }
    for holiday in off where holiday >= a && holiday <= b {
      if !weekend.contains(Self.weekday(holiday)) { count -= 1 }
    }
    return .number(sign * Double(count))
  }

  private func evalWorkdayIntl(_ args: [FormulaExpr]) -> CellValue {
    guard (2...4).contains(args.count) else { return .error(.value) }
    let startValue = evaluate(args[0])
    if case .error = startValue { return startValue }
    let daysValue = evaluate(args[1])
    if case .error = daysValue { return daysValue }
    guard let s = startValue.asNumber, let d = daysValue.asNumber else { return .error(.value) }
    let weekend: Set<Int>
    switch weekendDays(args, at: 2, allowAll: false) {
    case .failure(let box): return box.value
    case .success(let days): weekend = days
    }
    let off: Set<Int>
    switch holidays(args, at: 3) {
    case .failure(let box): return box.value
    case .success(let days): off = days
    }
    var remaining = Int(d.rounded(.towardZero))
    guard abs(remaining) < 1_000_000 else { return .error(.num) }
    var day = Int(s.rounded(.down))
    let step = remaining >= 0 ? 1 : -1
    while remaining != 0 {
      day += step
      if !weekend.contains(Self.weekday(day)), !off.contains(day) { remaining -= step }
    }
    return .number(Double(day))
  }

  // MARK: - SHEET and FORMULATEXT

  private func evalSHEET(_ args: [FormulaExpr]) -> CellValue {
    guard args.count <= 1 else { return .error(.value) }
    let names = sheetNames()
    func index(of name: String) -> CellValue {
      guard let i = names.firstIndex(where: { $0.caseInsensitiveCompare(name) == .orderedSame })
      else { return names.isEmpty ? .number(1) : .error(.na) }
      return .number(Double(i + 1))
    }
    guard let arg = args.first else { return index(of: formulaSheetName ?? "") }
    switch arg {
    case .cellRef(let ref): return index(of: ref.sheet ?? formulaSheetName ?? "")
    case .range(let start, _): return index(of: start.sheet ?? formulaSheetName ?? "")
    default:
      if Self.isReference(arg), let target = referenceTarget(arg) {
        return evalSHEET([target])
      }
      let value = evaluate(arg)
      if case .error = value { return value }
      guard case .string(let text) = value else { return .error(.na) }
      return index(of: text)
    }
  }

  private func evalFORMULATEXT(_ args: [FormulaExpr]) -> CellValue {
    guard args.count == 1 else { return .error(.value) }
    var ref: FormulaRef?
    switch args[0] {
    case .cellRef(let r): ref = r
    case .range(let start, let end):
      let n = normalizedBounds(start: start, end: end)
      ref = FormulaRef(
        sheet: start.sheet, row: n.minRow, col: n.minCol, absRow: false, absCol: false)
    default:
      if Self.isReference(args[0]), let target = referenceTarget(args[0]) {
        return evalFORMULATEXT([target])
      }
      return .error(.value)
    }
    guard let ref else { return .error(.na) }
    let sheet = ref.sheet ?? formulaSheetName ?? ""
    guard let formula = formulaText(sheet, CellAddress(row: ref.row, col: ref.col)) else {
      return .error(.na)
    }
    return .string(formula)
  }

  // MARK: - Precise rounding and series

  private func evalPreciseRounding(_ args: [FormulaExpr], up: Bool) -> CellValue {
    guard args.count == 1 || args.count == 2 else { return .error(.value) }
    return numbersWithDefaults(args, defaults: [nil, 1]) { a in
      let step = abs(a.count > 1 ? a[1] : 1)
      guard step != 0 else { return .number(0) }
      let units = a[0] / step
      let rounded = up ? units.rounded(.up) : units.rounded(.down)
      // Snap a quotient like 2.9999999999999996 to 3 first, as Excel does.
      let snapped = abs(units - units.rounded()) < 1e-12 ? units.rounded() : rounded
      return .number(snapped * step + 0)
    }
  }

  private func evalSERIESSUM(_ args: [FormulaExpr]) -> CellValue {
    guard args.count == 4 else { return .error(.value) }
    var head: [Double] = []
    for arg in args.prefix(3) {
      let value = evaluate(arg)
      if case .error = value { return value }
      guard let n = value.asNumber else { return .error(.value) }
      head.append(n)
    }
    var sum = 0.0
    var index = 0.0
    for value in flatten([args[3]]) {
      switch value {
      case .error: return value
      case .number(let a):
        sum += a * pow(head[0], head[1] + index * head[2])
        index += 1
      case .blank: index += 1
      default: return .error(.value)
      }
    }
    return sum.isFinite ? .number(sum) : .error(.num)
  }

  // MARK: - ROMAN, ARABIC, BASE and DECIMAL

  private func evalROMAN(_ args: [FormulaExpr]) -> CellValue {
    guard args.count == 1 || args.count == 2 else { return .error(.value) }
    let numberValue = evaluate(args[0])
    if case .error = numberValue { return numberValue }
    guard let number = numberValue.asNumber else { return .error(.value) }
    var form = 0
    if args.count == 2, args[1] != .missing {
      let formValue = evaluate(args[1])
      switch formValue {
      case .error: return formValue
      case .bool(let b): form = b ? 0 : 4
      case .blank: form = 0
      default:
        guard let f = formValue.asNumber else { return .error(.value) }
        form = Int(f.rounded(.towardZero))
      }
    }
    let n = Int(number.rounded(.towardZero))
    guard n >= 0, n < 4000, (0...4).contains(form) else { return .error(.value) }
    return .string(Self.roman(n, form: form))
  }

  /// Roman numerals, with forms 1 to 4 taking the shorter subtractive spellings other apps use
  /// (499 is CDXCIX, LDVLIV, XDIX, VDIV, ID).
  static func roman(_ number: Int, form: Int) -> String {
    let chars: [Character] = ["M", "D", "C", "L", "X", "V", "I"]
    let values = [1000, 500, 100, 50, 10, 5, 1]
    let maxIndex = values.count - 1
    var out = ""
    var value = number
    for i in 0...(maxIndex / 2) {
      var index = 2 * i
      let digit = value / values[index]
      if digit % 5 == 4 {
        let index2 = digit == 4 ? index - 1 : index - 2
        var steps = 0
        while steps < form, index < maxIndex {
          steps += 1
          if values[index2] - values[index + 1] <= value {
            index += 1
          } else {
            steps = form
          }
        }
        out.append(chars[index])
        out.append(chars[index2])
        value += values[index]
        value -= values[index2]
      } else {
        if digit > 4 { out.append(chars[index - 1]) }
        out += String(repeating: chars[index], count: digit % 5)
        value %= values[index]
      }
    }
    return out
  }

  private func evalARABIC(_ args: [FormulaExpr]) -> CellValue {
    guard args.count == 1 else { return .error(.value) }
    let value = evaluate(args[0])
    if case .error = value { return value }
    if case .blank = value { return .number(0) }
    guard case .string(let raw) = value else { return .error(.value) }
    var text = raw.trimmingCharacters(in: .whitespaces).uppercased()
    guard text.count <= 255 else { return .error(.value) }
    var sign = 1.0
    if text.hasPrefix("-") {
      sign = -1
      text.removeFirst()
    }
    let worth: [Character: Int] = ["I": 1, "V": 5, "X": 10, "L": 50, "C": 100, "D": 500, "M": 1000]
    var digits: [Int] = []
    for c in text {
      guard let v = worth[c] else { return .error(.value) }
      digits.append(v)
    }
    var total = 0
    for (i, v) in digits.enumerated() {
      if i + 1 < digits.count, v < digits[i + 1] { total -= v } else { total += v }
    }
    return .number(sign * Double(total))
  }

  private func evalBASE(_ args: [FormulaExpr]) -> CellValue {
    guard args.count == 2 || args.count == 3 else { return .error(.value) }
    return numbersWithDefaults(args, defaults: [nil, nil, 0]) { a in
      let number = a[0].rounded(.towardZero)
      let radix = a[1].rounded(.towardZero)
      let length = a.count > 2 ? a[2].rounded(.towardZero) : 0
      guard number >= 0, number < 9_007_199_254_740_992, radix >= 2, radix <= 36,
        length >= 0, length <= 255
      else { return .error(.num) }
      var text = String(UInt64(number), radix: Int(radix), uppercase: true)
      if text.count < Int(length) {
        text = String(repeating: "0", count: Int(length) - text.count) + text
      }
      return .string(text)
    }
  }

  private func evalDECIMAL(_ args: [FormulaExpr]) -> CellValue {
    guard args.count == 2 else { return .error(.value) }
    let textValue = evaluate(args[0])
    if case .error = textValue { return textValue }
    let radixValue = evaluate(args[1])
    if case .error = radixValue { return radixValue }
    guard let r = radixValue.asNumber else { return .error(.value) }
    let radix = Int(r.rounded(.towardZero))
    guard radix >= 2, radix <= 36 else { return .error(.num) }
    let text = textValue.asString.trimmingCharacters(in: .whitespaces)
    guard text.count <= 255 else { return .error(.value) }
    var total = 0.0
    for c in text.uppercased() {
      guard let digit = c.hexDigitValue ?? Self.letterDigit(c), digit < radix else {
        return .error(.num)
      }
      total = total * Double(radix) + Double(digit)
    }
    return total < 9_007_199_254_740_992 ? .number(total) : .error(.num)
  }

  private static func letterDigit(_ c: Character) -> Int? {
    guard let ascii = c.asciiValue, ascii >= 65, ascii <= 90 else { return nil }
    return Int(ascii) - 55
  }

  // MARK: - Number bases (engineering)

  /// The number of bits each base holds, as other apps define the functions: ten digits.
  private static func bits(for base: Int) -> Int {
    switch base {
    case 2: return 10
    case 8: return 30
    default: return 40
    }
  }

  private static func base(of letter: Character) -> Int {
    switch letter {
    case "B": return 2
    case "O": return 8
    case "D": return 10
    default: return 16
    }
  }

  /// Text in base 2, 8 or 16, ten digits at most, the tenth-digit-high ones negative.
  private func parseBase(_ value: CellValue, base: Int) -> Result<Int64, ErrorBox> {
    var text: String
    switch value {
    case .error: return .failure(ErrorBox(value: value))
    case .bool: return .failure(ErrorBox(value: .error(.value)))
    case .blank: text = "0"
    case .number(let n):
      guard n >= 0, n == n.rounded() else { return .failure(ErrorBox(value: .error(.num))) }
      text = String(format: "%.0f", n)
    case .string(let s): text = s.trimmingCharacters(in: .whitespaces)
    }
    if text.isEmpty { text = "0" }
    guard text.count <= 10, let parsed = Int64(text, radix: base), parsed >= 0 else {
      return .failure(ErrorBox(value: .error(.num)))
    }
    let bits = Self.bits(for: base)
    let limit = Int64(1) << Int64(bits)
    let half = limit >> 1
    guard parsed < limit else { return .failure(ErrorBox(value: .error(.num))) }
    return .success(parsed >= half ? parsed - limit : parsed)
  }

  /// `number` in base 2, 8 or 16, padded to `places`; a negative number as ten digits.
  private static func formatBase(_ number: Int64, base: Int, places: Int?) -> CellValue {
    let bits = Self.bits(for: base)
    let limit = Int64(1) << Int64(bits)
    guard number >= -(limit >> 1), number < (limit >> 1) else { return .error(.num) }
    if number < 0 {
      return .string(String(number + limit, radix: base, uppercase: true))
    }
    var text = String(number, radix: base, uppercase: true)
    if let places {
      guard places >= 1, places <= 10, places >= text.count else { return .error(.num) }
      text = String(repeating: "0", count: places - text.count) + text
    }
    return .string(text)
  }

  private func placesArgument(_ args: [FormulaExpr]) -> Result<Int?, ErrorBox> {
    guard args.count == 2, args[1] != .missing else { return .success(nil) }
    let value = evaluate(args[1])
    switch value {
    case .error: return .failure(ErrorBox(value: value))
    case .bool: return .failure(ErrorBox(value: .error(.value)))
    default:
      guard let n = value.asNumber else { return .failure(ErrorBox(value: .error(.value))) }
      guard n >= 0 else { return .failure(ErrorBox(value: .error(.num))) }
      return .success(Int(n.rounded(.towardZero)))
    }
  }

  private func evalFromBase(_ name: String, _ args: [FormulaExpr]) -> CellValue {
    guard args.count == 1 || (args.count == 2 && !name.hasSuffix("DEC")) else {
      return .error(.value)
    }
    let letters = Array(name)
    let from = Self.base(of: letters[0])
    let to = Self.base(of: letters[letters.count - 3])
    let number: Int64
    switch parseBase(evaluate(args[0]), base: from) {
    case .failure(let box): return box.value
    case .success(let n): number = n
    }
    if to == 10 { return .number(Double(number)) }
    switch placesArgument(args) {
    case .failure(let box): return box.value
    case .success(let places): return Self.formatBase(number, base: to, places: places)
    }
  }

  private func evalFromDecimal(_ name: String, _ args: [FormulaExpr]) -> CellValue {
    guard args.count == 1 || args.count == 2 else { return .error(.value) }
    let value = evaluate(args[0])
    if case .error = value { return value }
    if case .bool = value { return .error(.value) }
    guard let n = value.asNumber else { return .error(.value) }
    let to = Self.base(of: Array(name)[name.count - 3])
    let whole = n.rounded(.towardZero)
    guard abs(whole) < 1e15 else { return .error(.num) }
    switch placesArgument(args) {
    case .failure(let box): return box.value
    case .success(let places): return Self.formatBase(Int64(whole), base: to, places: places)
    }
  }

  private static let bitLimit = 281_474_976_710_656.0  // 2^48

  private static func bitOperand(_ x: Double) -> Int64? {
    guard x >= 0, x < bitLimit, x == x.rounded() else { return nil }
    return Int64(x)
  }

  // MARK: - VALUETOTEXT and ARRAYTOTEXT

  private func textFormatArgument(_ args: [FormulaExpr]) -> Result<Bool, ErrorBox> {
    guard args.count == 2, args[1] != .missing else { return .success(false) }
    let value = evaluate(args[1])
    if case .error = value { return .failure(ErrorBox(value: value)) }
    guard let n = value.asNumber else { return .failure(ErrorBox(value: .error(.value))) }
    switch Int(n.rounded(.towardZero)) {
    case 0: return .success(false)
    case 1: return .success(true)
    default: return .failure(ErrorBox(value: .error(.value)))
    }
  }

  private static func valueText(_ value: CellValue, strict: Bool) -> String {
    switch value {
    case .string(let text):
      return strict ? "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : text
    case .blank: return ""
    default: return value.asString
    }
  }

  private func evalVALUETOTEXT(_ args: [FormulaExpr]) -> CellValue {
    guard args.count == 1 || args.count == 2 else { return .error(.value) }
    switch textFormatArgument(args) {
    case .failure(let box): return box.value
    case .success(let strict):
      return .string(Self.valueText(evaluate(args[0]), strict: strict))
    }
  }

  private func evalARRAYTOTEXT(_ args: [FormulaExpr]) -> CellValue {
    guard args.count == 1 || args.count == 2 else { return .error(.value) }
    let strict: Bool
    switch textFormatArgument(args) {
    case .failure(let box): return box.value
    case .success(let s): strict = s
    }
    let array = evaluateArray(args[0])
    if !strict {
      return .string(array.values.map { Self.valueText($0, strict: false) }.joined(separator: ", "))
    }
    let rows = (0..<array.rows).map { r in
      array.row(r).map { Self.valueText($0, strict: true) }.joined(separator: ",")
    }
    return .string("{" + rows.joined(separator: ";") + "}")
  }

  // MARK: - BAHTTEXT

  /// A number as Thai words for baht and satang, as other apps write it.
  static func bahtText(_ value: Double) -> String {
    let digits = ["", "หนึ่ง", "สอง", "สาม", "สี่", "ห้า", "หก", "เจ็ด", "แปด", "เก้า"]
    let places = ["", "สิบ", "ร้อย", "พัน", "หมื่น", "แสน"]
    /// Below a million.
    func words(_ n: Int) -> String {
      guard n > 0 else { return "" }
      var out = ""
      let text = Array(String(n))
      for (i, c) in text.enumerated() {
        let digit = Int(String(c)) ?? 0
        let place = text.count - 1 - i
        guard digit > 0 else { continue }
        if place == 1 {
          out += digit == 1 ? "" : (digit == 2 ? "ยี่" : digits[digit])
          out += places[1]
        } else if place == 0, digit == 1, text.count > 1 {
          out += "เอ็ด"
        } else {
          out += digits[digit] + places[place]
        }
      }
      return out
    }
    func spell(_ n: Int) -> String {
      if n >= 1_000_000 {
        return spell(n / 1_000_000) + "ล้าน" + words(n % 1_000_000)
      }
      return words(n)
    }
    let negative = value < 0
    let cents = (abs(value) * 100).rounded()
    let baht = Int((cents / 100).rounded(.down))
    let satang = Int(cents - Double(baht) * 100)
    var out = negative ? "ลบ" : ""
    if baht == 0 && satang == 0 { return out + "ศูนย์บาทถ้วน" }
    if baht > 0 { out += spell(baht) + "บาท" }
    out += satang == 0 ? "ถ้วน" : spell(satang) + "สตางค์"
    return out
  }

  // MARK: - ENCODEURL

  static func encodeURL(_ text: String) -> String {
    var out = ""
    for byte in text.utf8 {
      let c = Character(Unicode.Scalar(byte))
      if c.isASCII, c.isLetter || c.isNumber || "-_.~".contains(c) {
        out.append(c)
      } else {
        out += String(format: "%%%02X", byte)
      }
    }
    return out
  }
}
