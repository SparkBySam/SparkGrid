import Formula
import Foundation
import GridCore

/// OFFSET, LOOKUP and YEARFRAC, checked against Excel 16.115 (Nov 18).
extension FormulaEvaluator {
  /// INDIRECT and OFFSET give a reference, worked out only when they run.
  static func isReferenceFunction(_ name: String) -> Bool {
    let plain = plainFunctionName(name)
    return plain == "INDIRECT" || plain == "OFFSET" || plain == FormulaExpr.rangeOperatorFunction
      || plain == FormulaExpr.intersectionFunction
  }

  /// INDIRECT and OFFSET read cells found only when they run, so they watch every cell.
  static func isVolatileReference(_ name: String) -> Bool {
    let plain = plainFunctionName(name)
    return plain == "INDIRECT" || plain == "OFFSET"
  }

  /// The reference INDIRECT, OFFSET or a `:` or space operator gives, or nil (#REF!).
  func referenceFunctionTarget(_ name: String, _ args: [FormulaExpr]) -> FormulaExpr? {
    switch Self.plainFunctionName(name) {
    case "OFFSET": return offsetTarget(args)
    case FormulaExpr.rangeOperatorFunction: return rangeOperatorTarget(args)
    case FormulaExpr.intersectionFunction: return intersectionTarget(args)
    default: return indirectTarget(args)
    }
  }

  private static func reference(
    sheet: String?, _ n: (minRow: Int, minCol: Int, maxRow: Int, maxCol: Int)
  ) -> FormulaExpr {
    let start = FormulaRef(sheet: sheet, row: n.minRow, col: n.minCol, absRow: false, absCol: false)
    if n.minRow == n.maxRow, n.minCol == n.maxCol { return .cellRef(start) }
    return .range(
      start, FormulaRef(sheet: sheet, row: n.maxRow, col: n.maxCol, absRow: false, absCol: false))
  }

  /// `X:Y`: the smallest range holding both, on one sheet.
  func rangeOperatorTarget(_ args: [FormulaExpr]) -> FormulaExpr? {
    guard args.count == 2, let a = referenceBounds(args[0]), let b = referenceBounds(args[1]),
      (a.sheet ?? "").caseInsensitiveCompare(b.sheet ?? a.sheet ?? "") == .orderedSame
    else { return nil }
    return Self.reference(
      sheet: a.sheet ?? b.sheet,
      (
        min(a.n.minRow, b.n.minRow), min(a.n.minCol, b.n.minCol),
        max(a.n.maxRow, b.n.maxRow), max(a.n.maxCol, b.n.maxCol)
      ))
  }

  /// `X Y`: the cells both share, or nil when they share none (#NULL!).
  func intersectionTarget(_ args: [FormulaExpr]) -> FormulaExpr? {
    guard args.count == 2, let a = referenceBounds(args[0]), let b = referenceBounds(args[1])
    else { return nil }
    let n = (
      max(a.n.minRow, b.n.minRow), max(a.n.minCol, b.n.minCol),
      min(a.n.maxRow, b.n.maxRow), min(a.n.maxCol, b.n.maxCol)
    )
    guard n.0 <= n.2, n.1 <= n.3 else { return nil }
    return Self.reference(sheet: a.sheet ?? b.sheet, n)
  }

  /// A `:` or space operator where one value is wanted: the cell's value; several cells are
  /// #VALUE!; ranges sharing no cell are #NULL!.
  func evalReferenceOperator(_ name: String, _ args: [FormulaExpr]) -> CellValue {
    for arg in args {
      if case .error(let error) = evaluateReferenceError(arg) { return .error(error) }
    }
    guard let target = referenceFunctionTarget(name, args) else {
      return Self.plainFunctionName(name) == FormulaExpr.intersectionFunction
        ? .error(.null) : .error(.ref)
    }
    if case .range(let start, let end) = target {
      let n = normalizedBounds(start: start, end: end)
      guard n.minRow == n.maxRow, n.minCol == n.maxCol else { return .error(.value) }
      return evaluate(.cellRef(start))
    }
    return evaluate(target)
  }

  private func evaluateReferenceError(_ expr: FormulaExpr) -> CellValue {
    if case .call(let name, let args) = expr, Self.plainFunctionName(name) == "INDEX" {
      for arg in args.dropFirst() {
        if case .error = evaluate(arg) { return evaluate(arg) }
      }
    }
    return .blank
  }

  /// ISREF: whether the argument is a reference, as other apps say: A1, A1:B2, INDIRECT("A1")
  /// and OFFSET give TRUE; text, numbers and errors FALSE.
  func evalISREF(_ args: [FormulaExpr]) -> CellValue {
    guard args.count == 1 else { return .error(.value) }
    switch args[0] {
    case .cellRef, .range: return .bool(true)
    default: return .bool(referenceBounds(args[0]) != nil)
    }
  }

  /// ISFORMULA: whether the referenced cell holds a formula.
  func evalISFORMULA(_ args: [FormulaExpr]) -> CellValue {
    guard args.count == 1 else { return .error(.value) }
    guard let target = referenceBounds(args[0]) else { return .error(.value) }
    let sheet = target.sheet ?? formulaSheetName ?? ""
    return .bool(holdsFormula(sheet, CellAddress(row: target.n.minRow, col: target.n.minCol)))
  }

  /// CELL(info, reference) for the parts that depend on the cell itself: "address", "row",
  /// "col", "contents", "type" (b blank, l text, v value), "prefix" (' for text) and
  /// "filename" (empty until saved). Width, format and the rest are #VALUE! for now.
  func evalCELL(_ args: [FormulaExpr]) -> CellValue {
    guard args.count == 2 else { return .error(.value) }
    let info = evaluate(args[0])
    if case .error = info { return info }
    guard let target = referenceBounds(args[1]) else { return .error(.value) }
    let address = CellAddress(row: target.n.minRow, col: target.n.minCol)
    let ref = FormulaRef(
      sheet: target.sheet, row: address.row, col: address.col, absRow: true, absCol: true)
    let value = lookup(ref)
    switch info.asString.lowercased() {
    case "address":
      return .string("$" + A1Notation.columnLabel(for: address.col) + "$" + String(address.row + 1))
    case "row": return .number(Double(address.row + 1))
    case "col": return .number(Double(address.col + 1))
    case "contents": return value
    case "type":
      switch value {
      case .blank: return .string("b")
      case .string: return .string("l")
      default: return .string("v")
      }
    case "prefix":
      if case .string = value { return .string("'") }
      return .string("")
    case "filename": return .string("")
    default: return .error(.value)
    }
  }

  /// PERCENTILE.EXC and QUARTILE.EXC: the rank is p × (n + 1), which must fall between 1 and n.
  func evalPercentileExc(_ args: [FormulaExpr], quartile: Bool) -> CellValue {
    guard args.count == 2 else { return .error(.value) }
    var numbers: [Double] = []
    for value in arrayEvaluate(args[0], cache: nil) {
      if case .error = value { return value }
      if case .number(let n) = value { numbers.append(n) }
    }
    let kValue = evaluate(args[1])
    if case .error = kValue { return kValue }
    guard var k = kValue.asNumber else { return .error(.value) }
    if quartile {
      let q = k.rounded(.down)
      guard q >= 1, q <= 3 else { return .error(.num) }
      k = q / 4
    }
    guard !numbers.isEmpty, k > 0, k < 1 else { return .error(.num) }
    numbers.sort()
    let rank = k * Double(numbers.count + 1)
    guard rank >= 1, rank <= Double(numbers.count) else { return .error(.num) }
    let low = Int(rank.rounded(.down))
    let fraction = rank - Double(low)
    if low >= numbers.count { return .number(numbers[numbers.count - 1]) }
    return .number(numbers[low - 1] + fraction * (numbers[low] - numbers[low - 1]))
  }

  /// A reference as a place: a cell, a range, a name for one, or what INDIRECT or OFFSET give.
  func referenceBounds(_ expr: FormulaExpr) -> (
    sheet: String?, n: (minRow: Int, minCol: Int, maxRow: Int, maxCol: Int)
  )? {
    switch expr {
    case .cellRef(let ref):
      guard !ref.isRowOpen, !ref.isColOpen else { return nil }
      return (ref.sheet, (ref.row, ref.col, ref.row, ref.col))
    case .range(let start, let end):
      return (start.sheet ?? end.sheet, normalizedBounds(start: start, end: end))
    case .namedRange(let name):
      guard let resolved = namedRangeLookup(name) else { return nil }
      return referenceBounds(resolved)
    case .call(let name, let args) where Self.isReferenceFunction(name):
      return referenceFunctionTarget(name, args).flatMap(referenceBounds)
    case .call(let name, let args) where Self.plainFunctionName(name) == "INDEX":
      return indexBounds(args)
    default:
      return nil
    }
  }

  /// INDEX(range, row, [col]) as a reference, for `B1:INDEX(B:B,5)`: the one cell, or the
  /// whole row or column when the row or column is 0.
  func indexBounds(_ args: [FormulaExpr]) -> (
    sheet: String?, n: (minRow: Int, minCol: Int, maxRow: Int, maxCol: Int)
  )? {
    guard (2...3).contains(args.count), let base = referenceBounds(args[0]) else { return nil }
    func whole(_ expr: FormulaExpr?) -> Int? {
      guard let expr, !Self.isMissing(expr) else { return 0 }
      guard let n = evaluate(expr).asNumber else { return nil }
      return Int(n.rounded(.down))
    }
    let b = base.n
    let height = b.maxRow - b.minRow + 1
    let width = b.maxCol - b.minCol + 1
    guard var row = whole(args[1]), var col = whole(args.count == 3 ? args[2] : nil) else {
      return nil
    }
    if args.count == 2, height == 1, width > 1 {
      col = row
      row = 1
    } else if args.count == 2, width == 1 {
      col = 1
    }
    guard row >= 0, col >= 0, row <= height, col <= width else { return nil }
    let rows = row == 0 ? (b.minRow, b.maxRow) : (b.minRow + row - 1, b.minRow + row - 1)
    let cols = col == 0 ? (b.minCol, b.maxCol) : (b.minCol + col - 1, b.minCol + col - 1)
    return (base.sheet, (rows.0, cols.0, rows.1, cols.1))
  }

  /// OFFSET(reference, rows, cols, [height], [width]): the range moved by rows and columns, as
  /// tall and wide as the reference unless given. Off the sheet, or a height or width under 1,
  /// is #REF!.
  func offsetTarget(_ args: [FormulaExpr]) -> FormulaExpr? {
    guard (3...5).contains(args.count), let base = referenceBounds(args[0]) else { return nil }
    func whole(_ index: Int, _ fallback: Int) -> Int? {
      guard index < args.count, !Self.isMissing(args[index]) else { return fallback }
      let value = evaluate(args[index])
      guard let n = value.asNumber, n.isFinite, abs(n) < 2e9 else { return nil }
      return Int(n.rounded(.down))
    }
    let b = base.n
    guard let rows = whole(1, 0), let cols = whole(2, 0),
      let height = whole(3, b.maxRow - b.minRow + 1), let width = whole(4, b.maxCol - b.minCol + 1),
      height >= 1, width >= 1
    else { return nil }
    let top = b.minRow + rows
    let left = b.minCol + cols
    let bottom = top + height - 1
    let right = left + width - 1
    guard top >= 0, left >= 0, bottom < InputBounds.maxStructureCount, right < 16_384 else {
      return nil
    }
    let start = FormulaRef(sheet: base.sheet, row: top, col: left, absRow: false, absCol: false)
    if height == 1, width == 1 { return .cellRef(start) }
    let end = FormulaRef(sheet: base.sheet, row: bottom, col: right, absRow: false, absCol: false)
    return .range(start, end)
  }

  /// OFFSET where one value is wanted: the cell's value; a range of several cells is #VALUE!.
  func evalOFFSET(_ args: [FormulaExpr]) -> CellValue {
    guard (3...5).contains(args.count) else { return .error(.value) }
    for arg in args.dropFirst() where !Self.isMissing(arg) {
      if case .error(let error) = evaluate(arg) { return .error(error) }
    }
    guard let target = offsetTarget(args) else { return .error(.ref) }
    if case .range(let start, let end) = target {
      let n = normalizedBounds(start: start, end: end)
      guard n.minRow == n.maxRow, n.minCol == n.maxCol else { return .error(.value) }
      return evaluate(.cellRef(start))
    }
    return evaluate(target)
  }

  /// LOOKUP(value, lookup_vector, [result_vector]) and LOOKUP(value, array): Excel's sorted
  /// search, so LOOKUP(2,1/(B1:B8>40),D1:D8) finds the last row that holds. The result is taken
  /// by position. With no result vector, a table wider than tall is searched along its first
  /// row and answers from its last row; otherwise down its first column, from its last column.
  func evalLOOKUP(_ args: [FormulaExpr]) -> CellValue {
    guard args.count == 2 || args.count == 3 else { return .error(.value) }
    let needle = evaluate(args[0])
    if case .error = needle { return needle }
    let table = evaluateArray(resolvedExpr(args[1]))
    if table.isSingle, case .error = table.values[0] { return table.values[0] }
    let keys: [CellValue]
    let answers: [CellValue]
    if args.count == 3 {
      keys = table.values
      let result = evaluateArray(resolvedExpr(args[2]))
      if result.isSingle, case .error = result.values[0] { return result.values[0] }
      answers = result.values
    } else if table.cols > table.rows {
      keys = Array(table.values[0..<table.cols])
      let last = (table.rows - 1) * table.cols
      answers = Array(table.values[last..<(last + table.cols)])
    } else {
      keys = (0..<table.rows).map { table.values[$0 * table.cols] }
      answers = (0..<table.rows).map { table.values[$0 * table.cols + table.cols - 1] }
    }
    guard let index = Self.sortedSearch(needle, in: keys, descending: false) else {
      return .error(.na)
    }
    guard index < answers.count else { return .error(.na) }
    return answers[index]
  }

  /// YEARFRAC(start, end, [basis]): the part of a year between two dates. Basis 0 (or left
  /// out) is US 30/360, 1 actual days over the actual year, 2 actual/360, 3 actual/365, 4
  /// European 30/360. The dates may come in either order.
  func evalYEARFRAC(_ args: [FormulaExpr]) -> CellValue {
    guard args.count == 2 || args.count == 3 else { return .error(.value) }
    var numbers: [Double] = []
    for (index, arg) in args.enumerated() {
      if index == 2, Self.isMissing(arg) {
        numbers.append(0)
        continue
      }
      let value = evaluate(arg)
      if case .error = value { return value }
      if case .string(let text) = value {
        guard let n = Double(text) ?? Self.dateSerial(text) else { return .error(.value) }
        numbers.append(n)
        continue
      }
      guard let n = value.asNumber else { return .error(.value) }
      numbers.append(n)
    }
    let basis = numbers.count == 3 ? Int(numbers[2].rounded(.down)) : 0
    guard (0...4).contains(basis) else { return .error(.num) }
    var first = Int(numbers[0].rounded(.down))
    var second = Int(numbers[1].rounded(.down))
    guard first >= 0, second >= 0 else { return .error(.num) }
    if first > second { swap(&first, &second) }
    if first == second { return .number(0) }
    guard let a = Self.ymd(first), let b = Self.ymd(second) else { return .error(.num) }
    let days = Double(second - first)
    switch basis {
    case 0:
      var d1 = a.day
      var d2 = b.day
      let aLastFeb = a.month == 2 && d1 == Self.monthLength(a.year, 2)
      let bLastFeb = b.month == 2 && d2 == Self.monthLength(b.year, 2)
      // In this order, as Excel applies them: from the end of February a 31st stays.
      if d1 == 31 && d2 == 31 {
        d1 = 30
        d2 = 30
      } else if d1 == 31 {
        d1 = 30
      } else if d1 == 30 && d2 == 31 {
        d2 = 30
      } else if aLastFeb && bLastFeb {
        d1 = 30
        d2 = 30
      } else if aLastFeb {
        d1 = 30
      }
      let total = (b.year - a.year) * 360 + (b.month - a.month) * 30 + (d2 - d1)
      return .number(Double(total) / 360)
    case 1:
      let oneYearLater =
        (b.year == a.year)
        || (b.year == a.year + 1 && (b.month < a.month || (b.month == a.month && b.day <= a.day)))
      if oneYearLater {
        let leapDay: Bool
        if a.year == b.year {
          leapDay = Self.isLeap(a.year)
        } else {
          leapDay =
            (Self.isLeap(a.year) && (a.month < 3))
            || (Self.isLeap(b.year) && (b.month > 2 || (b.month == 2 && b.day == 29)))
        }
        return .number(days / (leapDay ? 366 : 365))
      }
      var yearDays = 0
      for year in a.year...b.year { yearDays += Self.isLeap(year) ? 366 : 365 }
      let average = Double(yearDays) / Double(b.year - a.year + 1)
      return .number(days / average)
    case 2:
      return .number(days / 360)
    case 3:
      return .number(days / 365)
    default:
      let d1 = min(a.day, 30)
      let d2 = min(b.day, 30)
      let total = (b.year - a.year) * 360 + (b.month - a.month) * 30 + (d2 - d1)
      return .number(Double(total) / 360)
    }
  }

  static func isLeap(_ year: Int) -> Bool {
    (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
  }

  static func monthLength(_ year: Int, _ month: Int) -> Int {
    [31, isLeap(year) ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1]
  }
}
