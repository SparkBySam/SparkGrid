import Formula
import Foundation
import Functions
import GridCore
import Model

/// Functions batch 1 for 1.2: everyday math, statistics, text, information and date functions
/// that showed #NAME? before.
extension FormulaEvaluator {
  /// Handles a batch 1 function, or returns nil when `name` is not one.
  func evalBatch1(_ name: String, _ args: [FormulaExpr]) -> CellValue? {
    switch name {
    case "INT":
      return unaryNumber(args) { .number($0.rounded(.down)) }
    case "SIGN":
      return unaryNumber(args) { .number($0 > 0 ? 1 : ($0 < 0 ? -1 : 0)) }
    case "SQRT":
      return unaryNumber(args) { $0 < 0 ? .error(.num) : .number($0.squareRoot()) }
    case "PI":
      guard args.isEmpty else { return .error(.value) }
      return .number(Double.pi)
    case "MOD":
      return binaryNumber(args) { number, divisor in
        guard divisor != 0 else { return .error(.divZero) }
        // The result takes the divisor's sign, as other spreadsheet apps do.
        return .number(number - divisor * (number / divisor).rounded(.down))
      }
    case "POWER":
      return binaryNumber(args) { base, exponent in
        let result = pow(base, exponent)
        return result.isFinite ? .number(result) : .error(.num)
      }
    case "CEILING", "CEILING.MATH":
      return roundToMultiple(args, rule: .up)
    case "FLOOR", "FLOOR.MATH":
      return roundToMultiple(args, rule: .down)
    case "PRODUCT":
      var product = 1.0
      var any = false
      for value in flatten(args) {
        if case .error = value { return value }
        if case .number(let n) = value {
          product *= n
          any = true
        }
      }
      return .number(any ? product : 0)
    case "MEDIAN":
      var numbers = statNumbers(args)
      if let error = numbers.error { return error }
      guard !numbers.values.isEmpty else { return .error(.num) }
      numbers.values.sort()
      let count = numbers.values.count
      let middle = count / 2
      if count.isMultiple(of: 2) {
        return .number((numbers.values[middle - 1] + numbers.values[middle]) / 2)
      }
      return .number(numbers.values[middle])
    case "LARGE", "SMALL":
      guard args.count == 2 else { return .error(.value) }
      var numbers = statNumbers([args[0]])
      if let error = numbers.error { return error }
      let k = evaluate(args[1])
      if case .error = k { return k }
      guard let kNumber = k.asNumber else { return .error(.value) }
      let index = Int(kNumber.rounded(.up))
      guard index >= 1, index <= numbers.values.count else { return .error(.num) }
      numbers.values.sort(by: name == "LARGE" ? (>) : (<))
      return .number(numbers.values[index - 1])
    case "RANK", "RANK.EQ":
      guard args.count == 2 || args.count == 3 else { return .error(.value) }
      let target = evaluate(args[0])
      if case .error = target { return target }
      guard let value = target.asNumber else { return .error(.value) }
      let numbers = statNumbers([args[1]])
      if let error = numbers.error { return error }
      var ascending = false
      if args.count == 3 {
        let order = evaluate(args[2])
        if case .error = order { return order }
        ascending = (order.asNumber ?? 0) != 0
      }
      guard numbers.values.contains(value) else { return .error(.na) }
      let ahead = numbers.values.filter { ascending ? $0 < value : $0 > value }.count
      return .number(Double(ahead + 1))
    case "PROPER":
      return unaryText(args) { .string(properCase($0)) }
    case "FIND", "SEARCH":
      return evalFind(args, caseSensitive: name == "FIND")
    case "VALUE":
      guard args.count == 1 else { return .error(.value) }
      let value = evaluate(args[0])
      switch value {
      case .error: return value
      case .number: return value
      case .blank: return .number(0)
      case .bool: return .error(.value)
      case .string(let text):
        let cleaned = text.trimmingCharacters(in: .whitespaces)
          .replacingOccurrences(of: ",", with: "")
          .replacingOccurrences(of: "$", with: "")
        if cleaned.hasSuffix("%"), let n = Double(cleaned.dropLast()) { return .number(n / 100) }
        if let n = Double(cleaned) { return .number(n) }
        return .error(.value)
      }
    case "EXACT":
      guard args.count == 2 else { return .error(.value) }
      let left = evaluate(args[0])
      let right = evaluate(args[1])
      if case .error = left { return left }
      if case .error = right { return right }
      return .bool(left.asString == right.asString)
    case "ISBLANK":
      return isTest(args) { if case .blank = $0 { return true } else { return false } }
    case "ISNUMBER":
      return isTest(args) { if case .number = $0 { return true } else { return false } }
    case "ISTEXT":
      return isTest(args) { if case .string = $0 { return true } else { return false } }
    case "ISERROR":
      return isTest(args) { if case .error = $0 { return true } else { return false } }
    case "FALSE":
      guard args.isEmpty else { return .error(.value) }
      return .bool(false)
    case "WEEKDAY":
      return evalWeekday(args)
    case "HOUR", "MINUTE", "SECOND":
      return unaryNumber(args) { serial in
        guard serial >= 0 else { return .error(.num) }
        let seconds = Int(((serial - serial.rounded(.down)) * 86_400).rounded())
        switch name {
        case "HOUR": return .number(Double(seconds / 3600 % 24))
        case "MINUTE": return .number(Double(seconds / 60 % 60))
        default: return .number(Double(seconds % 60))
        }
      }
    case "EDATE", "EOMONTH":
      return evalMonthShift(args, endOfMonth: name == "EOMONTH")
    case "ROW":
      return evalRow(args)
    case "ROWS", "COLUMNS":
      guard args.count == 1 else { return .error(.value) }
      switch resolvedExpr(args[0]) {
      case .cellRef:
        return .number(1)
      case .range(let start, let end):
        if name == "ROWS" {
          guard !start.isRowOpen, !end.isRowOpen else { return .error(.value) }
          return .number(Double(abs(end.row - start.row) + 1))
        }
        guard !start.isColOpen, !end.isColOpen else { return .error(.value) }
        return .number(Double(abs(end.col - start.col) + 1))
      default:
        return .error(.value)
      }
    case "MAXIFS":
      return evalExtremeIFS(args, pickMin: false)
    case "MINIFS":
      return evalExtremeIFS(args, pickMin: true)
    default:
      return nil
    }
  }

  // MARK: - Helpers

  private func unaryNumber(_ args: [FormulaExpr], _ body: (Double) -> CellValue) -> CellValue {
    guard args.count == 1 else { return .error(.value) }
    let value = evaluate(args[0])
    if case .error = value { return value }
    guard let number = value.asNumber else { return .error(.value) }
    return body(number)
  }

  private func binaryNumber(_ args: [FormulaExpr], _ body: (Double, Double) -> CellValue)
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

  private func unaryText(_ args: [FormulaExpr], _ body: (String) -> CellValue) -> CellValue {
    guard args.count == 1 else { return .error(.value) }
    let value = evaluate(args[0])
    if case .error = value { return value }
    return body(value.asString)
  }

  private func isTest(_ args: [FormulaExpr], _ test: (CellValue) -> Bool) -> CellValue {
    guard args.count == 1 else { return .error(.value) }
    return .bool(test(evaluate(args[0])))
  }

  /// Numbers in the arguments, skipping text and blanks in ranges. The first error stops it.
  private func statNumbers(_ args: [FormulaExpr]) -> (values: [Double], error: CellValue?) {
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

  private enum MultipleRounding { case up, down }

  /// CEILING and FLOOR: to the next multiple of `significance` (1 when it is left out).
  private func roundToMultiple(_ args: [FormulaExpr], rule: MultipleRounding) -> CellValue {
    guard args.count == 1 || args.count == 2 else { return .error(.value) }
    let value = evaluate(args[0])
    if case .error = value { return value }
    guard let number = value.asNumber else { return .error(.value) }
    var step = 1.0
    if args.count == 2 {
      let significance = evaluate(args[1])
      if case .error = significance { return significance }
      guard let s = significance.asNumber else { return .error(.value) }
      step = abs(s)
    }
    guard step != 0 else { return .number(0) }
    let quotient = number / step
    // Absorb binary noise so 0.3/0.1 counts as exactly 3.
    let nearest = quotient.rounded()
    let whole =
      abs(quotient - nearest) < 1e-9
      ? nearest : (rule == .up ? quotient.rounded(.up) : quotient.rounded(.down))
    return .number(whole * step)
  }

  private func properCase(_ text: String) -> String {
    var result = ""
    var startOfWord = true
    for character in text {
      if character.isLetter {
        result += startOfWord ? character.uppercased() : character.lowercased()
        startOfWord = false
      } else {
        result.append(character)
        startOfWord = !character.isNumber && character != "'"
      }
    }
    return result
  }

  /// FIND (case-sensitive) and SEARCH (ignores case, allows `?` and `*`). 1-based position.
  private func evalFind(_ args: [FormulaExpr], caseSensitive: Bool) -> CellValue {
    guard args.count == 2 || args.count == 3 else { return .error(.value) }
    let needleValue = evaluate(args[0])
    if case .error = needleValue { return needleValue }
    let haystackValue = evaluate(args[1])
    if case .error = haystackValue { return haystackValue }
    var start = 1
    if args.count == 3 {
      let startValue = evaluate(args[2])
      if case .error = startValue { return startValue }
      guard let s = startValue.asNumber else { return .error(.value) }
      start = Int(s.rounded(.down))
    }
    let needle = Array(needleValue.asString)
    let haystack = Array(haystackValue.asString)
    guard start >= 1, start <= haystack.count + 1 else { return .error(.value) }
    if needle.isEmpty { return .number(Double(start)) }
    if caseSensitive {
      guard needle.count <= haystack.count else { return .error(.value) }
      var index = start - 1
      while index + needle.count <= haystack.count {
        if Array(haystack[index..<(index + needle.count)]) == needle {
          return .number(Double(index + 1))
        }
        index += 1
      }
      return .error(.value)
    }
    let pattern = String(needle)
    let suffix = String(haystack[(start - 1)...])
    let escaped = NSRegularExpression.escapedPattern(for: pattern)
      .replacingOccurrences(of: "\\?", with: ".")
      .replacingOccurrences(of: "\\*", with: ".*?")
    guard
      let regex = try? NSRegularExpression(
        pattern: escaped, options: [.caseInsensitive, .dotMatchesLineSeparators]),
      let match = regex.firstMatch(
        in: suffix, range: NSRange(suffix.startIndex..., in: suffix)),
      let range = Range(match.range, in: suffix)
    else { return .error(.value) }
    return .number(Double(start + suffix.distance(from: suffix.startIndex, to: range.lowerBound)))
  }

  /// WEEKDAY with return types 1 (Sunday = 1), 2 (Monday = 1) and 3 (Monday = 0).
  private func evalWeekday(_ args: [FormulaExpr]) -> CellValue {
    guard args.count == 1 || args.count == 2 else { return .error(.value) }
    let value = evaluate(args[0])
    if case .error = value { return value }
    guard let serial = value.asNumber, serial >= 0 else { return .error(.value) }
    var type = 1
    if args.count == 2 {
      let typeValue = evaluate(args[1])
      if case .error = typeValue { return typeValue }
      guard let t = typeValue.asNumber else { return .error(.value) }
      type = Int(t)
    }
    // Serial 1 (1900-01-01 in this calendar's count from 1899-12-30) is a Sunday.
    let sundayBased = (Int(serial.rounded(.down)) % 7 + 6) % 7  // 0 = Sunday
    switch type {
    case 1: return .number(Double(sundayBased + 1))
    case 2: return .number(Double((sundayBased + 6) % 7 + 1))
    case 3: return .number(Double((sundayBased + 6) % 7))
    default: return .error(.num)
    }
  }

  /// EDATE and EOMONTH: the date `months` months on, or the last day of that month.
  private func evalMonthShift(_ args: [FormulaExpr], endOfMonth: Bool) -> CellValue {
    guard args.count == 2 else { return .error(.value) }
    let start = evaluate(args[0])
    if case .error = start { return start }
    let monthsValue = evaluate(args[1])
    if case .error = monthsValue { return monthsValue }
    guard let serial = start.asNumber, serial >= 0, let shift = monthsValue.asNumber,
      abs(shift) < 120_000, let date = ExcelDate.date(from: serial.rounded(.down))
    else { return .error(.num) }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
    let months = Int(shift.rounded(.towardZero))
    if endOfMonth {
      var components = calendar.dateComponents([.year, .month], from: date)
      components.month = (components.month ?? 1) + months + 1
      components.day = 0
      guard let end = calendar.date(from: components) else { return .error(.num) }
      return .number(ExcelDate.serial(from: end))
    }
    // Past the end of a shorter month, the date stops at that month's last day.
    guard let moved = calendar.date(byAdding: .month, value: months, to: date) else {
      return .error(.num)
    }
    return .number(ExcelDate.serial(from: moved))
  }

  private func evalRow(_ args: [FormulaExpr]) -> CellValue {
    if args.isEmpty {
      guard let origin = evaluationOrigin else { return .error(.value) }
      return .number(Double(origin.row + 1))
    }
    guard args.count == 1 else { return .error(.value) }
    switch resolvedExpr(args[0]) {
    case .cellRef(let ref):
      guard !ref.isRowOpen else { return .error(.value) }
      return .number(Double(ref.row + 1))
    case .range(let start, let end):
      guard !start.isRowOpen, !end.isRowOpen, start.row == end.row else { return .error(.value) }
      return .number(Double(start.row + 1))
    default:
      return .error(.value)
    }
  }
}
