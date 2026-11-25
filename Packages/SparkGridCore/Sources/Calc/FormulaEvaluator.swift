import Formula
import Foundation
import Functions
import GridCore
import Model
import NumberFormat

private enum ExcelRoundFormat {
  nonisolated static let locale = Locale(identifier: "en_US_POSIX")
}

private nonisolated enum XLookupMatchMode {
  case exact
  case nextSmaller
  case nextLarger
  case wildcard
}

private nonisolated enum XLookupHit {
  case found(Int)
  case notFound
  case failed(CellValue)
}

private nonisolated enum LookupKind {
  case number(Double)
  case text(String)
  case bool(Bool)
}

public nonisolated struct FormulaEvaluator {
  /// Resolves a cell reference (local or cross-sheet).
  public typealias ValueLookup = (FormulaRef) -> CellValue
  /// Resolves a named range to a sheet-qualified range expression, if defined.
  public typealias NamedRangeLookup = (String) -> FormulaExpr?
  /// Last usable row/col index for open-ended ranges (`A2:A`, `A:A`, `2:2`).
  public typealias SheetExtentLookup = (_ sheetName: String?) -> (maxRow: Int, maxCol: Int)

  public let lookup: ValueLookup
  public var namedRangeLookup: NamedRangeLookup = { _ in nil }
  /// The Spark Grid pivot table drawn over a cell, by sheet name, for GETPIVOTDATA.
  public var pivotLookup: (String, CellAddress) -> SheetPivot? = { _, _ in nil }
  /// True when the array formula in this cell cannot spill because cells in the way are not
  /// empty. It then shows #SPILL!.
  public var spillBlocked: (String, CellAddress) -> Bool = { _, _ in false }
  /// The cells a formula's results spill into, by sheet name and the formula's cell, for `G1#`.
  /// Nil when nothing spills from that cell, or its spill is blocked.
  public var spillRange: (String, CellAddress) -> CellRange? = { _, _ in nil }
  /// Whether a cell holds a formula, by sheet name and address, for ISFORMULA.
  public var holdsFormula: (String, CellAddress) -> Bool = { _, _ in false }
  /// A cell's formula as typed, by sheet name and address, or nil when it holds none
  /// (FORMULATEXT, and SUBTOTAL and AGGREGATE leaving out the subtotals in their ranges).
  public var formulaText: (String, CellAddress) -> String? = { _, _ in nil }
  /// Whether a row is hidden by hand or from the file, by sheet name and row index
  /// (SUBTOTAL 101 to 111, AGGREGATE's options that leave out hidden rows).
  public var rowHidden: (String, Int) -> Bool = { _, _ in false }
  /// Whether the sheet's filter hides a row (every SUBTOTAL leaves those out).
  public var rowFiltered: (String, Int) -> Bool = { _, _ in false }
  /// The workbook's sheet names in tab order (SHEET, SHEETS).
  public var sheetNames: () -> [String] = { [] }
  /// Defaults to a modest grid so open ranges don't explode when extent isn't wired.
  public var sheetExtent: SheetExtentLookup = { _ in (maxRow: 999, maxCol: 25) }
  /// Cell being evaluated (`COLUMN()` / `ROW()` with no argument). Held in a class cell so batch strip eval can set origin without mutating the evaluator struct.
  public nonisolated final class EvaluationOriginCell {
    public var address: CellAddress?
  }

  public var evaluationOriginCell = EvaluationOriginCell()

  /// Shared across copies of this struct so nested `evaluate` calls see one depth.
  public nonisolated final class EvaluationBudget: @unchecked Sendable {
    public var depth = 0
    public var names: Set<String> = []
    public var maxDepth = InputBounds.maxFormulaNesting
  }

  public var budget = EvaluationBudget()

  public var evaluationOrigin: CellAddress? {
    get { evaluationOriginCell.address }
    set { evaluationOriginCell.address = newValue }
  }

  /// Sheet that owns the formula being evaluated. Unqualified ranges belong to that
  /// sheet. Without this, two sheets' `COUNTIF($C$1:$C$2,$A1)` share one cache key.
  public var formulaSheetName: String?

  /// Shared range snapshots for COUNTIFS / SUMIFS-style functions (one scan per range per batch).
  public var aggregateRangeCache: FormulaAggregateRangeCache?
  /// Exact VLOOKUP / HLOOKUP tables.
  public var lookupTableCache: FormulaLookupTableCache?
  public weak var recalcProfile: FormulaRecalcProfile?

  /// Sheet + stored master formula for IF-blank strip plan-miss diagnostics.
  public nonisolated struct StripPlanDiagnosticContext {
    public var sheetName: String
    public var masterFormulaText: String
  }

  public var stripPlanDiagnosticContext: StripPlanDiagnosticContext?

  public func prepareForCellEvaluation(origin: CellAddress?) {
    evaluationOriginCell.address = origin
  }

  public nonisolated final class ArrayEvalCacheBox {
    public var values: [FormulaExpr: [CellValue]] = [:]
  }

  /// A branch IF, CHOOSE, SWITCH or IFERROR picks. One left out gives 0, as in other apps:
  /// `=IF(A2>1,,2)` is 0 when A2 is over 1.
  func evaluateChosen(_ expr: FormulaExpr) -> CellValue {
    if case .missing = expr { return .number(0) }
    return evaluate(expr)
  }

  public func evaluate(_ expr: FormulaExpr) -> CellValue {
    if budget.depth >= budget.maxDepth {
      return .error(.value)
    }
    budget.depth += 1
    defer { budget.depth -= 1 }
    if budget.depth == 1, let first = firstValueOfLaidOutSpill(expr) { return first }
    switch expr {
    case .missing:
      // An argument left out reads as a blank: 0 to arithmetic, FALSE to a test.
      return .blank
    case .number(let n):
      return .number(n)
    case .string(let s):
      return .string(s)
    case .boolean(let b):
      return .bool(b)
    case .error(let e):
      return .error(e)
    case .namedRange(let name):
      let key = name.lowercased()
      if budget.names.contains(key) { return .error(.cycle) }
      guard let resolved = namedRangeLookup(name) else { return .error(.name) }
      budget.names.insert(key)
      let resolvedValue = evaluate(resolved)
      budget.names.remove(key)
      return resolvedValue
    case .cellRef(let ref):
      return lookup(ref)
    case .range:
      // Bare ranges are multi-valued; scalar context matches Sheets `#VALUE!`.
      return .error(.arrayResult)
    case .unary(let op, let expr):
      return evalUnary(op, expr)
    case .binary(let op, let lhs, let rhs):
      return evalBinary(op, lhs, rhs)
    case .call(let name, let args):
      return evalCall(name, args)
    case .array(let rows):
      // A list in a cell shows its first item; the rest spill, as other apps show it.
      guard let first = rows.first?.first else { return .error(.value) }
      if rows.count * (rows.first?.count ?? 0) > 1, spillIsBlocked { return .error(.spill) }
      return evaluate(first)
    }
  }

  /// The value a range or a one-value function given a range shows in its own cell when it
  /// spills (`=A1:A3`, `=LEN(D1:D8)`, `=ROW(B1:B8)`): the first of its values, or #SPILL! when
  /// something is in the way. Nil otherwise, including for a file's pre-spill formula, which
  /// is not laid out as a spill.
  private func firstValueOfLaidOutSpill(_ expr: FormulaExpr) -> CellValue? {
    switch expr {
    case .range: break
    case .call(let name, _):
      let plain = Self.plainFunctionName(name)
      guard Self.liftedFunctionNames.contains(plain) || plain == "ROW" || plain == "COLUMN",
        Self.spills(expr)
      else { return nil }
    default: return nil
    }
    guard let origin = evaluationOrigin, let sheet = formulaSheetName else { return nil }
    if spillBlocked(sheet, origin) { return .error(.spill) }
    guard spillRange(sheet, origin) != nil else { return nil }
    return evaluateArray(expr).values.first.map(Self.cellResult)
  }

  private func evalUnary(_ op: UnaryOp, _ expr: FormulaExpr) -> CellValue {
    let values = arrayEvaluate(expr, cache: nil)
    if values.count == 1 {
      return applyUnary(op, to: values[0])
    }
    if values.isEmpty { return .blank }
    if Self.spills(expr) {
      return spillIsBlocked ? .error(.spill) : applyUnary(op, to: values[0])
    }
    return .error(.arrayResult)
  }

  private func evalBinary(_ op: BinaryOp, _ lhsExpr: FormulaExpr, _ rhsExpr: FormulaExpr)
    -> CellValue
  {
    let values = arrayBinary(op, lhsExpr, rhsExpr, cache: nil)
    if values.count == 1 { return values[0] }
    if values.isEmpty { return .blank }
    // FILTER(...)*2 spills; the cell shows the first value.
    if Self.spills(lhsExpr) || Self.spills(rhsExpr) {
      return spillIsBlocked ? .error(.spill) : values[0]
    }
    // Sheets/Excel: multi-value result in one cell is not silently collapsed.
    return .error(.arrayResult)
  }

  public func applyUnary(_ op: UnaryOp, to value: CellValue) -> CellValue {
    if case .error = value { return value }
    guard let number = value.asNumber else { return .error(.value) }
    switch op {
    case .negate: return .number(-number)
    case .plus: return .number(number)
    case .percent: return .number(number / 100)
    }
  }

  /// `^` and POWER as other apps work them out: an odd root of a negative number is negative
  /// (`(-8)^(1/3)` is -2), other fractional powers of one are #NUM!, as is 0^0 and anything
  /// past the largest number. They showed as "nan" and "inf" (found by script, Nov 18).
  static func power(_ base: Double, _ exponent: Double) -> CellValue {
    if base == 0, exponent == 0 { return .error(.num) }
    if base == 0, exponent < 0 { return .error(.divZero) }
    var result = pow(base, exponent)
    if base < 0, exponent != exponent.rounded() {
      let root = 1 / exponent
      let whole = root.rounded()
      guard abs(root - whole) < 1e-9, Int(whole) % 2 != 0 else { return .error(.num) }
      result = -pow(-base, exponent)
    }
    return result.isFinite ? .number(result) : .error(.num)
  }

  public func applyBinary(_ op: BinaryOp, lhs: CellValue, rhs: CellValue) -> CellValue {
    if case .error = lhs { return lhs }
    if case .error = rhs { return rhs }

    switch op {
    case .concat:
      return .string(lhs.asString + rhs.asString)
    case .add, .subtract, .multiply, .divide, .power:
      guard let a = lhs.asNumber, let b = rhs.asNumber else { return .error(.value) }
      let result: Double
      switch op {
      case .add: result = a + b
      case .subtract: result = a - b
      case .multiply: result = a * b
      case .divide:
        guard b != 0 else { return .error(.divZero) }
        result = a / b
      case .power: return Self.power(a, b)
      default: return .error(.value)
      }
      // Past the largest number, #NUM! as in other apps; it showed as "inf".
      return result.isFinite ? .number(result) : .error(.num)
    case .eq, .ne, .lt, .gt, .le, .ge:
      return compare(op, lhs, rhs)
    }
  }

  /// Evaluates an expression to one or more values (ranges / broadcast arithmetic).
  public func arrayEvaluate(_ expr: FormulaExpr, cache: ArrayEvalCacheBox?) -> [CellValue] {
    if let cache, let hit = cache.values[expr] {
      return hit
    }
    let result = arrayEvaluateImpl(expr, cache: cache)
    cache?.values[expr] = result
    return result
  }

  private func arrayEvaluateImpl(_ expr: FormulaExpr, cache: ArrayEvalCacheBox?) -> [CellValue] {
    switch expr {
    case .number, .string, .boolean, .error, .cellRef, .missing:
      return [evaluate(expr)]
    case .array(let rows):
      // SUM({1,2,3}) adds every item.
      return rows.flatMap { $0.map { evaluate($0) } }
    case .namedRange(let name):
      guard let resolved = namedRangeLookup(name) else { return [.error(.name)] }
      return arrayEvaluate(resolved, cache: cache)
    case .range(let start, let end):
      return rangeCellValues(start: start, end: end)
    case .unary(let op, let inner):
      return arrayEvaluate(inner, cache: cache).map { applyUnary(op, to: $0) }
    case .binary(let op, let lhs, let rhs):
      return arrayBinary(op, lhs, rhs, cache: cache)
    case .call(let name, let args):
      if Self.isLet(name) { return arrayEvaluate(letCalculation(args), cache: cache) }
      // SUM(FILTER(...)) adds every value the array function gives.
      if Self.arrayFunctionNames.contains(Self.plainFunctionName(name)) {
        return evaluateArray(expr).values
      }
      // LEN(A1:A8) inside SUM: one length for each cell.
      if Self.givesArray(expr) {
        return evaluateArray(expr).values
      }
      return [evaluate(expr)]
    }
  }

  private func arrayBinary(
    _ op: BinaryOp,
    _ lhsExpr: FormulaExpr,
    _ rhsExpr: FormulaExpr,
    cache: ArrayEvalCacheBox?
  ) -> [CellValue] {
    let lhs = arrayEvaluate(lhsExpr, cache: cache)
    let rhs = arrayEvaluate(rhsExpr, cache: cache)
    if let err = lhs.first(where: \.isError) { return [err] }
    if let err = rhs.first(where: \.isError) { return [err] }

    if lhs.count == 1, rhs.count == 1 {
      return [applyBinary(op, lhs: lhs[0], rhs: rhs[0])]
    }
    // Broadcast scalar × range (and vice versa), e.g. `(A2+A6+A7)*(B3:B5)`.
    if lhs.count == 1 {
      return rhs.map { applyBinary(op, lhs: lhs[0], rhs: $0) }
    }
    if rhs.count == 1 {
      return lhs.map { applyBinary(op, lhs: $0, rhs: rhs[0]) }
    }
    guard lhs.count == rhs.count else { return [.error(.value)] }
    return zip(lhs, rhs).map { applyBinary(op, lhs: $0, rhs: $1) }
  }

  public func rangeCellValues(start: FormulaRef, end: FormulaRef) -> [CellValue] {
    let n = normalizedBounds(start: start, end: end)
    let rows = InputBounds.span(from: n.minRow, through: n.maxRow)
    let cols = InputBounds.span(from: n.minCol, through: n.maxCol)
    guard let count = InputBounds.materializedCount(rows: rows, cols: cols) else {
      return [.error(.value)]
    }
    guard count > 0 else { return [] }
    if let cache = aggregateRangeCache {
      let sheetName = start.sheet ?? end.sheet ?? formulaSheetName
      let key = AggregateRangeKey(
        sheet: sheetName,
        row: n.minRow,
        col: n.minCol,
        rows: rows,
        cols: cols
      )
      return cache.rowMajorValues(key: key, count: count) { index in
        let row = n.minRow + index / cols
        let col = n.minCol + index % cols
        var ref = FormulaRef(
          sheet: sheetName, row: row, col: col, absRow: false, absCol: false)
        return lookup(ref)
      }
    }
    var values: [CellValue] = []
    values.reserveCapacity(count)
    for row in n.minRow...n.maxRow {
      for col in n.minCol...n.maxCol {
        var ref = FormulaRef(sheet: start.sheet, row: row, col: col, absRow: false, absCol: false)
        if ref.sheet == nil { ref.sheet = end.sheet }
        values.append(lookup(ref))
      }
    }
    return values
  }

  private func compare(_ op: BinaryOp, _ lhs: CellValue, _ rhs: CellValue) -> CellValue {
    if lhs.isError { return lhs }
    if rhs.isError { return rhs }
    let order = Self.comparisonOrder(lhs, rhs)
    switch op {
    case .eq: return .bool(order == 0)
    case .ne: return .bool(order != 0)
    case .lt: return .bool(order < 0)
    case .gt: return .bool(order > 0)
    case .le: return .bool(order <= 0)
    case .ge: return .bool(order >= 0)
    default: return .error(.value)
    }
  }

  /// How `=`, `<` and the rest order two values, as other spreadsheet apps do (checked against
  /// Excel 16.115, Nov 18). Numbers come before text and text before TRUE and FALSE, so
  /// `1=TRUE` is FALSE and `TRUE>1` is TRUE. Text compares as text without regard to case,
  /// even when it looks like a number: `"10"<"9"` is TRUE. An empty cell takes the other
  /// side's kind (0, "" or FALSE). Numbers equal to 15 significant digits are equal, so
  /// `0.1+0.2=0.3` is TRUE.
  static func comparisonOrder(_ lhs: CellValue, _ rhs: CellValue) -> Int {
    func asOther(_ other: CellValue) -> CellValue {
      switch other {
      case .string: return .string("")
      case .bool: return .bool(false)
      default: return .number(0)
      }
    }
    var a = lhs
    var b = rhs
    if case .blank = a { a = asOther(b) }
    if case .blank = b { b = asOther(a) }

    func rank(_ value: CellValue) -> Int {
      switch value {
      case .string: return 1
      case .bool: return 2
      default: return 0
      }
    }
    let ra = rank(a)
    let rb = rank(b)
    if ra != rb { return ra < rb ? -1 : 1 }
    switch (a, b) {
    case (.string(let x), .string(let y)):
      // In the order other apps use: punctuation, then digits, then letters, accents beside
      // their letters ("~"<"a", "co-op"<"coop", "é"<"f"; 16 cases checked with Excel 16.115).
      switch x.compare(y, options: [.caseInsensitive], range: nil, locale: Self.textOrderLocale) {
      case .orderedAscending: return -1
      case .orderedDescending: return 1
      case .orderedSame: return 0
      }
    case (.bool(let x), .bool(let y)):
      return x == y ? 0 : (x ? 1 : -1)
    default:
      guard let x = a.asNumber, let y = b.asNumber else { return 0 }
      if x == y || Self.equalTo15Digits(x, y) { return 0 }
      return x < y ? -1 : 1
    }
  }

  static let textOrderLocale = Locale(identifier: "en_US")

  static func equalTo15Digits(_ x: Double, _ y: Double) -> Bool {
    guard x.isFinite, y.isFinite else { return false }
    let posix = Locale(identifier: "en_US_POSIX")
    return String(format: "%.15g", locale: posix, x) == String(format: "%.15g", locale: posix, y)
  }

  /// `IF(Cn="","",…)` — skip heavy false-branch work on blank rows.
  private func fastIFBlankEquality(_ args: [FormulaExpr]) -> CellValue? {
    guard args.count == 3 else { return nil }
    guard isStaticEmptyLiteral(args[1]) else { return nil }
    guard let ref = blankEqualityGuardRef(args[0]) else { return nil }
    let value = lookup(ref)
    if valueIsBlankForIfGuard(value) {
      recalcProfile?.ifBlankEqualityFastHits += 1
      return .string("")
    }
    recalcProfile?.ifBlankEqualityFastHits += 1
    return evaluate(args[2])
  }

  /// `Cn=""` or `""=Cn` with a single cell reference.
  private func blankEqualityGuardRef(_ condition: FormulaExpr) -> FormulaRef? {
    guard case .binary(.eq, let lhs, let rhs) = unwrapFormulaExpr(condition) else { return nil }
    if isStaticEmptyLiteral(rhs), let ref = formulaCellRef(lhs) { return ref }
    if isStaticEmptyLiteral(lhs), let ref = formulaCellRef(rhs) { return ref }
    return nil
  }

  /// `IFERROR(VLOOKUP(needle, range, col, FALSE), fallback)`.
  private func fastIFERRORVLOOKUP(_ args: [FormulaExpr]) -> CellValue? {
    guard case .call(let name, let vargs) = unwrapFormulaExpr(args[0]),
      name.uppercased() == "VLOOKUP",
      vargs.count >= 3, vargs.count <= 4
    else { return nil }
    let value = tableLookup(vargs, horizontal: false)
    recalcProfile?.iferrorVlookupFastHits += 1
    if case .error = value {
      return evaluate(args[1])
    }
    return value
  }

  private func isStaticEmptyLiteral(_ expr: FormulaExpr) -> Bool {
    switch unwrapFormulaExpr(expr) {
    case .string(let text):
      return text.isEmpty
    default:
      return false
    }
  }

  private func unwrapFormulaExpr(_ expr: FormulaExpr) -> FormulaExpr {
    if case .unary(.plus, let inner) = expr { return unwrapFormulaExpr(inner) }
    return expr
  }

  private func formulaCellRef(_ expr: FormulaExpr) -> FormulaRef? {
    switch unwrapFormulaExpr(expr) {
    case .cellRef(let ref):
      return ref
    default:
      return nil
    }
  }

  private func valueIsBlankForIfGuard(_ value: CellValue) -> Bool {
    switch value {
    case .blank:
      return true
    case .string(let text):
      return text.isEmpty
    default:
      return false
    }
  }

  private func evalCall(_ name: String, _ args: [FormulaExpr]) -> CellValue {
    let name = canonicalFunctionName(name)
    let profileStart = recalcProfile != nil ? CFAbsoluteTimeGetCurrent() : 0
    let result = evalCallBody(name, args)
    if let profile = recalcProfile {
      profile.recordEval(
        function: name.uppercased(), seconds: CFAbsoluteTimeGetCurrent() - profileStart)
    }
    return result
  }

  /// Excel writes newer functions as `_xlfn.XLOOKUP`. The prefix is not part of the name.
  private func canonicalFunctionName(_ name: String) -> String {
    guard name.hasPrefix("_") else { return name }
    // `_xlfn.XLOOKUP`, and `_xlfn._xlws.FILTER` for FILTER and SORT.
    return Self.plainFunctionName(name)
  }

  private func evalCallBody(_ name: String, _ args: [FormulaExpr]) -> CellValue {
    switch name {
    case "SUM":
      let read = statNumbers(args, textIsError: true)
      if let error = read.error { return error }
      return .number(read.numbers.reduce(0, +))
    case "AVERAGE":
      if let fast = fastAverageIfPossible(args) { return fast }
      let read = statNumbers(args, textIsError: true)
      if let error = read.error { return error }
      guard !read.numbers.isEmpty else { return .error(.divZero) }
      return .number(read.numbers.reduce(0, +) / Double(read.numbers.count))
    case "COUNT":
      // Errors and text are not counted, and stop nothing.
      return .number(Double(statNumbers(args, textIsError: false, countOnly: true).numbers.count))
    case "COUNTA":
      var count = 0
      for value in flatten(args) {
        if case .error = value { return value }
        if case .blank = value { continue }
        count += 1
      }
      return .number(Double(count))
    case "MIN": return extreme(args, pickMin: true)
    case "MAX": return extreme(args, pickMin: false)
    case "IF":
      guard args.count >= 2, args.count <= 3 else { return .error(.value) }
      if args.count == 3, let fast = fastIFBlankEquality(args) {
        return fast
      }
      let condition = evaluate(args[0])
      if case .error = condition { return condition }
      guard let flag = condition.asBool else { return .error(.value) }
      if flag {
        return evaluateChosen(args[1])
      }
      if args.count == 3 {
        return evaluateChosen(args[2])
      }
      return .bool(false)
    case "IFERROR":
      guard args.count == 2 else { return .error(.value) }
      if let fast = fastIFERRORVLOOKUP(args) {
        return fast
      }
      let value = evaluate(args[0])
      if case .error = value {
        return evaluateChosen(args[1])
      }
      return value
    case "AND":
      return logicalJoin(args, requireAll: true)
    case "OR":
      return logicalJoin(args, requireAll: false)
    case "ABS":
      guard args.count == 1 else { return .error(.value) }
      let value = evaluate(args[0])
      if case .error = value { return value }
      guard let n = value.asNumber else { return .error(.value) }
      return .number(abs(n))
    case "ROUND":
      guard args.count == 1 || args.count == 2 else { return .error(.value) }
      let value = evaluate(args[0])
      if case .error = value { return value }
      guard let n = value.asNumber else { return .error(.value) }
      var digits = 0.0
      if args.count == 2 {
        let d = evaluate(args[1])
        if case .error = d { return d }
        guard let dn = d.asNumber else { return .error(.value) }
        digits = dn
      }
      let places = digits.rounded()
      guard let placeCount = Int(exactly: places) else {
        let factor = pow(10.0, places)
        return .number((n * factor).rounded() / factor)
      }
      return .number(excelRoundHalfAwayFromZero(n, places: placeCount))
    case "LEN":
      guard args.count == 1 else { return .error(.value) }
      let value = evaluate(args[0])
      if case .error = value { return value }
      return .number(Double(value.asString.count))
    case "LEFT":
      return substring(args, fromStart: true)
    case "RIGHT":
      return substring(args, fromStart: false)
    case "TRIM":
      guard args.count == 1 else { return .error(.value) }
      let value = evaluate(args[0])
      if case .error = value { return value }
      // Only the ordinary space, as in other apps: a non-breaking space or tab stays.
      let collapsed = value.asString
        .split(separator: " ")
        .joined(separator: " ")
      return .string(collapsed)
    case "CONCAT", "CONCATENATE":
      var result = ""
      for value in flatten(args) {
        if case .error = value { return value }
        result += value.asString
      }
      return .string(result)
    case "TEXT":
      return evalTEXT(args)
    case "XLOOKUP":
      return evalXLOOKUP(args)
    case "INDIRECT":
      return evalINDIRECT(args)
    case "OFFSET":
      return evalOFFSET(args)
    case FormulaExpr.rangeOperatorFunction, FormulaExpr.intersectionFunction:
      return evalReferenceOperator(name, args)
    case "ISREF":
      return evalISREF(args)
    case "ISFORMULA":
      return evalISFORMULA(args)
    case "CELL":
      return evalCELL(args)
    case "PERCENTILE.EXC":
      return evalPercentileExc(args, quartile: false)
    case "QUARTILE.EXC":
      return evalPercentileExc(args, quartile: true)
    case "LOOKUP":
      return evalLOOKUP(args)
    case "YEARFRAC":
      return evalYEARFRAC(args)
    case "ADDRESS":
      return evalADDRESS(args)
    case "VLOOKUP":
      return evalVLOOKUP(args)
    case "HLOOKUP":
      return evalHLOOKUP(args)
    case "INDEX":
      return evalINDEX(args)
    case "MATCH":
      return evalMATCH(args)
    case "XMATCH":
      return evalXMATCH(args)
    case "TODAY":
      guard args.isEmpty else { return .error(.value) }
      let clock = ExcelDate.wallClock()
      return .number(ExcelDate.localSerial(from: clock.date, timeZone: clock.timeZone))
    case "DATE":
      return evalDATE(args)
    case "YEAR":
      return evalDatePart(args) { $0.year }
    case "MONTH":
      return evalDatePart(args) { $0.month }
    case "DAY":
      return evalDatePart(args) { $0.day }
    case "SUMIF":
      return evalSUMIF(args)
    case "AVERAGEIF":
      return evalAVERAGEIF(args)
    case "COUNTIF":
      return evalCOUNTIF(args)
    case "SUMIFS":
      return evalSUMIFS(args)
    case "COUNTIFS":
      return evalCOUNTIFS(args)
    case "AVERAGEIFS":
      return evalAVERAGEIFS(args)
    case "COUNTBLANK":
      return evalCOUNTBLANK(args)
    case "SUMPRODUCT":
      return evalSUMPRODUCT(args)
    case "IFNA":
      return evalIFNA(args)
    case "IFS":
      return evalIFS(args)
    case "NOT":
      return evalNOT(args)
    case "UPPER":
      return evalTextCase(args, uppercased: true)
    case "LOWER":
      return evalTextCase(args, uppercased: false)
    case "MID":
      return evalMID(args)
    case "SUBSTITUTE":
      return evalSUBSTITUTE(args)
    case "TEXTJOIN":
      return evalTEXTJOIN(args)
    case "ROUNDUP":
      return evalDirectionalRound(args, mode: .up)
    case "ROUNDDOWN":
      return evalDirectionalRound(args, mode: .down)
    case "NOW":
      guard args.isEmpty else { return .error(.value) }
      let clock = ExcelDate.wallClock()
      return .number(ExcelDate.localSerialWithTime(from: clock.date, timeZone: clock.timeZone))
    case "COLUMN":
      return evalCOLUMN(args)
    case "CHAR":
      return evalCHAR(args)
    case "REPT":
      return evalREPT(args)
    case "LET":
      return evaluate(letCalculation(args))
    case _ where Self.shapeFunctionNames.contains(name),
      _ where Self.statArrayFunctionNames.contains(name),
      _ where Self.regexArrayFunctionNames.contains(name),
      _ where Self.lambdaArrayFunctionNames.contains(name),
      "SEQUENCE", "FILTER", "SORT", "SORTBY", "UNIQUE", FormulaExpr.anchorArrayFunction:
      // The cell shows the first value; the rest spill into the cells below and beside it.
      if spillIsBlocked { return .error(.spill) }
      // A blank in an array result shows as 0, as other apps show it.
      let first = evaluateArray(.call(name, args)).first
      if case .blank = first { return .number(0) }
      return first
    case "TRUE":
      guard args.isEmpty else { return .error(.value) }
      return .bool(true)
    default:
      if let value = evalRegex(name, args) ?? evalBatch1(name, args) ?? evalBatch2(name, args)
        ?? evalBatch3(name, args)
        ?? evalBatch4(name, args) ?? evalBatch5(name, args)
        ?? evalBatch7(name, args) ?? evalBatch6(name, args)
      {
        return value
      }
      UnknownFunctions.note(name)
      return .error(.name)
    }
  }

  private func evalREPT(_ args: [FormulaExpr]) -> CellValue {
    guard args.count == 2 else { return .error(.value) }
    let text = evaluate(args[0])
    let times = evaluate(args[1])
    if case .error = text { return text }
    if case .error = times { return times }
    guard let count = times.asNumber, count >= 0, count < Double(Int.max) else {
      return .error(.value)
    }
    let repeats = Int(count)
    let piece = text.asString
    if repeats == 0 || piece.isEmpty { return .string("") }
    let (total, overflow) = piece.count.multipliedReportingOverflow(by: repeats)
    if overflow || total > InputBounds.maxRepeatCharacters { return .error(.value) }
    return .string(String(repeating: piece, count: repeats))
  }

  private func evalCOLUMN(_ args: [FormulaExpr]) -> CellValue {
    if args.isEmpty {
      guard let origin = evaluationOrigin else { return .error(.value) }
      return .number(Double(origin.col + 1))
    }
    guard args.count == 1 else { return .error(.value) }
    switch resolvedExpr(args[0]) {
    case .cellRef(let ref):
      guard !ref.isColOpen else { return .error(.value) }
      return .number(Double(ref.col + 1))
    case .range(let start, let end):
      guard !start.isColOpen, !end.isColOpen, start.col == end.col else { return .error(.value) }
      return .number(Double(start.col + 1))
    default:
      return .error(.value)
    }
  }

  private func evalCHAR(_ args: [FormulaExpr]) -> CellValue {
    guard args.count == 1 else { return .error(.value) }
    let value = evaluate(args[0])
    if case .error = value { return value }
    guard let number = value.asNumber else { return .error(.value) }
    let code = Int(number.rounded(.towardZero))
    guard code >= 0, let scalar = Unicode.Scalar(code) else { return .error(.value) }
    return .string(String(Character(scalar)))
  }

  private func logicalJoin(_ args: [FormulaExpr], requireAll: Bool) -> CellValue {
    guard !args.isEmpty else { return .error(.value) }
    var sawValue = false
    for value in flatten(args) {
      if case .error = value { return value }
      if case .blank = value { continue }
      guard let flag = value.asBool else { return .error(.value) }
      sawValue = true
      if requireAll {
        if !flag { return .bool(false) }
      } else if flag {
        return .bool(true)
      }
    }
    guard sawValue else { return .error(.value) }
    return .bool(requireAll)
  }

  private func evalTEXT(_ args: [FormulaExpr]) -> CellValue {
    guard args.count == 2 else { return .error(.value) }
    let value = evaluate(args[0])
    if case .error = value { return value }
    let formatValue = evaluate(args[1])
    if case .error = formatValue { return formatValue }
    let pattern = formatValue.asString
    if let number = value.asNumber {
      switch ExcelFormatCode.render(number, code: pattern, fractionDigits: nil) {
      case .text(let rendered): return .string(rendered)
      case .general: return .string(value.displayString)
      // A date before 1900 or after 9999, as other apps give it.
      case .invalid: return .error(.value)
      }
    }
    if let rendered = ExcelFormatCode.formattedText(value.asString, code: pattern) {
      return .string(rendered)
    }
    return .string(value.asString)
  }

  /// Excel rounds the 15-significant-digit decimal value, half away from zero.
  private func excelRoundHalfAwayFromZero(_ value: Double, places: Int) -> Double {
    if !value.isFinite || value == 0 { return value }
    let text = String(format: "%.15g", locale: ExcelRoundFormat.locale, value)
    guard var decimal = Decimal(string: text, locale: ExcelRoundFormat.locale) else {
      return value
    }
    var rounded = Decimal()
    NSDecimalRound(&rounded, &decimal, places, .plain)
    // NSDecimalNumber.doubleValue is not exact (3.1416 came back as 3.1415999999999995).
    // Reading the rounded digits as text gives the nearest double.
    let digits = NSDecimalNumber(decimal: rounded).description(withLocale: ExcelRoundFormat.locale)
    return Double(digits) ?? NSDecimalNumber(decimal: rounded).doubleValue
  }

  private func evalINDEX(_ args: [FormulaExpr]) -> CellValue {
    guard args.count == 2 || args.count == 3 else { return .error(.value) }
    if Self.spills(args[0]) { return indexIntoArray(args) }
    guard case .range(let start, let end) = resolveToRange(args[0]) else {
      return .error(.value)
    }
    let position = evaluate(args[1])
    if case .error = position { return position }
    guard let positionNumber = position.asNumber else { return .error(.value) }
    let positionIndex = Int(positionNumber.rounded(.down))

    let n = normalizedBounds(start: start, end: end)
    let height = n.maxRow - n.minRow + 1
    let width = n.maxCol - n.minCol + 1

    var rowIndex = positionIndex
    var colIndex = 1
    if args.count == 3 {
      let colValue = evaluate(args[2])
      if case .error = colValue { return colValue }
      guard let colNumber = colValue.asNumber else { return .error(.value) }
      colIndex = Int(colNumber.rounded(.down))
    } else if height == 1, width > 1 {
      // One row: the only index is the column. Excel does the same.
      rowIndex = 1
      colIndex = positionIndex
    }

    guard rowIndex >= 1, rowIndex <= height, colIndex >= 1, colIndex <= width else {
      return .error(.ref)
    }
    let ref = FormulaRef(
      sheet: start.sheet ?? end.sheet,
      row: n.minRow + rowIndex - 1,
      col: n.minCol + colIndex - 1,
      absRow: false,
      absCol: false
    )
    return lookup(ref)
  }

  /// INDEX(SORT(…), 1): one value from a result that would spill.
  private func indexIntoArray(_ args: [FormulaExpr]) -> CellValue {
    let array = evaluateArray(args[0])
    if array.isSingle, case .error = array.first { return array.first }
    var indexes: [Int] = []
    for arg in args.dropFirst() {
      let value = evaluate(arg)
      if case .error = value { return value }
      guard let number = value.asNumber else { return .error(.value) }
      indexes.append(Int(number.rounded(.down)))
    }
    var row = indexes[0]
    var col = indexes.count > 1 ? indexes[1] : 1
    if indexes.count == 1, array.rows == 1, array.cols > 1 {
      row = 1
      col = indexes[0]
    }
    guard row >= 1, row <= array.rows, col >= 1, col <= array.cols else { return .error(.ref) }
    let value = array.value(row: row - 1, col: col - 1)
    if case .blank = value { return .number(0) }
    return value
  }

  private func evalMATCH(_ args: [FormulaExpr]) -> CellValue {
    guard args.count == 2 || args.count == 3 else { return .error(.value) }
    let needle = evaluate(args[0])
    if case .error = needle { return needle }
    guard let values = rangeValues(resolveToRangeExpr(args[1]) ?? args[1]) else {
      return .error(.value)
    }

    var matchType = 1
    if args.count == 3 {
      let typeValue = evaluate(args[2])
      if case .error = typeValue { return typeValue }
      guard let typeNumber = typeValue.asNumber else { return .error(.value) }
      matchType = Int(typeNumber.rounded(.down))
    }

    if matchType == 0 {
      // `"b?"` and `"app*"` match text as wildcards, as in other apps (found by script).
      if case .string(let pattern) = needle, excelHasWildcard(pattern) {
        for (index, value) in values.enumerated() {
          if case .string(let text) = value, excelWildcardMatch(text, pattern: pattern) {
            return .number(Double(index + 1))
          }
        }
        return .error(.na)
      }
      for (index, value) in values.enumerated() {
        if case .error = value { return value }
        if valuesEqual(needle, value) {
          return .number(Double(index + 1))
        }
      }
      return .error(.na)
    }

    // Approximate: Excel's sorted search for 1. For -1 Excel reads from the top: the first
    // value equal to the needle, or the last one before a value below it (Excel 16.115).
    if matchType < 0 {
      var last: Int?
      for (index, value) in values.enumerated() {
        guard case .some = Self.lookupKind(value), Self.lookupKind(value) == Self.lookupKind(needle)
        else { continue }
        let order = Self.comparisonOrder(value, needle)
        if order == 0 { return .number(Double(index + 1)) }
        if order < 0 { break }
        last = index
      }
      return last.map { .number(Double($0 + 1)) } ?? .error(.na)
    }
    guard let index = Self.sortedSearch(needle, in: values, descending: false) else {
      return .error(.na)
    }
    return .number(Double(index + 1))
  }

  private func evalDATE(_ args: [FormulaExpr]) -> CellValue {
    guard args.count == 3 else { return .error(.value) }
    let y = evaluate(args[0])
    let m = evaluate(args[1])
    let d = evaluate(args[2])
    if case .error = y { return y }
    if case .error = m { return m }
    if case .error = d { return d }
    guard let year = y.asNumber, let month = m.asNumber, let day = d.asNumber else {
      return .error(.value)
    }
    var components = DateComponents()
    components.year = Int(year.rounded(.down))
    components.month = Int(month.rounded(.down))
    components.day = Int(day.rounded(.down))
    guard let date = Calendar.current.date(from: components) else { return .error(.value) }
    return .number(ExcelDate.serial(from: date))
  }

  /// YEAR, MONTH and DAY in Excel's 1900 calendar: 0 is 0 Jan 1900, 1 is 1 Jan 1900 and 60 the
  /// 29 Feb 1900 other apps keep. Days up to 60 read one day early before (found by script).
  private func evalDatePart(
    _ args: [FormulaExpr], _ part: ((year: Int, month: Int, day: Int)) -> Int
  ) -> CellValue {
    guard args.count == 1 else { return .error(.value) }
    let value = evaluate(args[0])
    if case .error = value { return value }
    guard let serial = value.asNumber else { return .error(.value) }
    guard serial >= 0, serial < 2_958_466 else { return .error(.num) }
    return .number(Double(part(ExcelFormatCode.excelDate(Int(serial.rounded(.down))))))
  }

  private func resolveToRange(_ expr: FormulaExpr) -> FormulaExpr? {
    switch expr {
    case .range:
      return expr
    case .namedRange(let name):
      return namedRangeLookup(name)
    case .call(let name, let args) where Self.isSpillReference(name):
      return spillReferenceRange(args)
    case .call(let name, let args) where Self.isReferenceFunction(name):
      switch referenceFunctionTarget(name, args) {
      case .range(let start, let end): return .range(start, end)
      case .cellRef(let ref): return .range(ref, ref)
      default: return nil
      }
    default:
      return nil
    }
  }

  private func resolveToRangeExpr(_ expr: FormulaExpr) -> FormulaExpr? {
    resolveToRange(expr)
  }

  private func evalXLOOKUP(_ args: [FormulaExpr]) -> CellValue {
    // 4-argument calls stay exact: the fourth value is if_not_found, not a match mode.
    guard args.count >= 3, args.count <= 6 else { return .error(.value) }
    let needle = evaluate(args[0])
    if case .error = needle { return needle }

    let lookupValues = rangeValues(args[1])
    let returnValues = rangeValues(args[2])
    guard var lookupValues, var returnValues else { return .error(.value) }
    guard lookupValues.count == returnValues.count, !lookupValues.isEmpty else {
      return .error(.value)
    }
    // Search mode: 1 first to last, -1 last to first; 2 and -2 (a sorted search) give the
    // same answers on sorted data. It was not read, so a sixth argument was #VALUE!.
    if args.count == 6, !Self.isMissing(args[5]) {
      let searchValue = evaluate(args[5])
      if case .error = searchValue { return searchValue }
      guard let search = searchValue.asNumber, [1, -1, 2, -2].contains(Int(search)) else {
        return .error(.value)
      }
      if search < 0 {
        lookupValues.reverse()
        returnValues.reverse()
      }
    }

    let mode: XLookupMatchMode
    if args.count >= 5, !Self.isMissing(args[4]) {
      let modeValue = evaluate(args[4])
      if case .error = modeValue { return modeValue }
      guard let parsed = xLookupMatchMode(from: modeValue) else { return .error(.value) }
      mode = parsed
    } else {
      mode = .exact
    }

    switch xLookupIndex(needle: needle, in: lookupValues, mode: mode) {
    case .found(let index):
      let result = returnValues[index]
      if case .error = result { return result }
      return result
    case .failed(let error):
      return error
    case .notFound:
      // Left out (`XLOOKUP(x,A:A,B:B,,0)`), not found is #N/A.
      if args.count >= 4, !Self.isMissing(args[3]) {
        return evaluate(args[3])
      }
      return .error(.na)
    }
  }

  /// A formula's answer as its cell holds it: an empty cell picked as the answer is 0.
  public static func cellResult(_ value: CellValue) -> CellValue {
    if case .blank = value { return .number(0) }
    return value
  }

  static func isMissing(_ expr: FormulaExpr) -> Bool {
    if case .missing = expr { return true }
    return false
  }

  private func evalXMATCH(_ args: [FormulaExpr]) -> CellValue {
    guard args.count == 2 || args.count == 3 else { return .error(.value) }
    let needle = evaluate(args[0])
    if case .error = needle { return needle }
    guard let values = rangeValues(args[1]), !values.isEmpty else { return .error(.value) }

    let mode: XLookupMatchMode
    if args.count == 3 {
      let modeValue = evaluate(args[2])
      if case .error = modeValue { return modeValue }
      guard let parsed = xLookupMatchMode(from: modeValue) else { return .error(.value) }
      mode = parsed
    } else {
      mode = .exact
    }

    switch xLookupIndex(needle: needle, in: values, mode: mode) {
    case .found(let index):
      return .number(Double(index + 1))
    case .failed(let error):
      return error
    case .notFound:
      return .error(.na)
    }
  }

  /// 0 exact, -1 next smaller, 1 next larger, 2 wildcard. Anything else is invalid.
  private func xLookupMatchMode(from value: CellValue) -> XLookupMatchMode? {
    guard let number = value.asNumber else { return nil }
    let rounded = number.rounded(.down)
    guard rounded.isFinite, let code = Int(exactly: rounded) else { return nil }
    switch code {
    case 0: return .exact
    case -1: return .nextSmaller
    case 1: return .nextLarger
    case 2: return .wildcard
    default: return nil
    }
  }

  private func xLookupIndex(needle: CellValue, in values: [CellValue], mode: XLookupMatchMode)
    -> XLookupHit
  {
    switch mode {
    case .exact:
      for (index, value) in values.enumerated() {
        if case .error = value { return .failed(value) }
        if valuesEqual(needle, value) { return .found(index) }
      }
      return .notFound
    case .wildcard:
      let pattern = needle.asString
      for (index, value) in values.enumerated() {
        if case .error = value { return .failed(value) }
        if isBlankForCount(value) { continue }
        if excelWildcardMatch(criteriaText(value), pattern: pattern) { return .found(index) }
      }
      return .notFound
    case .nextSmaller, .nextLarger:
      var best: (index: Int, key: CellValue)?
      for (index, value) in values.enumerated() {
        if case .error = value { return .failed(value) }
        if valuesEqual(needle, value) { return .found(index) }
        guard let order = lookupCompare(value, needle) else { continue }
        let isCandidate =
          mode == .nextSmaller
          ? order == .orderedAscending
          : order == .orderedDescending
        guard isCandidate else { continue }
        if let current = best {
          guard let against = lookupCompare(value, current.key) else { continue }
          let closer =
            mode == .nextSmaller
            ? against == .orderedDescending
            : against == .orderedAscending
          if closer { best = (index, value) }
        } else {
          best = (index, value)
        }
      }
      if let best { return .found(best.index) }
      return .notFound
    }
  }

  /// Numbers, then text, then booleans. Text compares without case.
  private func lookupCompare(_ lhs: CellValue, _ rhs: CellValue) -> ComparisonResult? {
    guard let left = lookupKind(lhs), let right = lookupKind(rhs) else { return nil }
    switch (left, right) {
    case (.number(let left), .number(let right)):
      if left < right { return .orderedAscending }
      if left > right { return .orderedDescending }
      return .orderedSame
    case (.text(let left), .text(let right)):
      return left.caseInsensitiveCompare(right)
    case (.bool(let left), .bool(let right)):
      if left == right { return .orderedSame }
      return left ? .orderedDescending : .orderedAscending
    case (.number, .text), (.number, .bool), (.text, .bool):
      return .orderedAscending
    case (.text, .number), (.bool, .number), (.bool, .text):
      return .orderedDescending
    }
  }

  private func lookupKind(_ value: CellValue) -> LookupKind? {
    switch value {
    case .number(let number): return .number(number)
    case .string(let text): return .text(text)
    case .bool(let flag): return .bool(flag)
    case .blank, .error: return nil
    }
  }

  private func evalVLOOKUP(_ args: [FormulaExpr]) -> CellValue {
    tableLookup(args, horizontal: false)
  }

  private func evalHLOOKUP(_ args: [FormulaExpr]) -> CellValue {
    tableLookup(args, horizontal: true)
  }

  /// VLOOKUP walks the first column. HLOOKUP walks the first row. Same exact and approximate rules.
  private func tableLookup(_ args: [FormulaExpr], horizontal: Bool) -> CellValue {
    guard args.count >= 3, args.count <= 4 else { return .error(.value) }
    let needle = evaluate(args[0])
    if case .error = needle { return needle }

    guard case .range(let start, let end) = resolveToRange(args[1]) else { return .error(.value) }
    let indexValue = evaluate(args[2])
    if case .error = indexValue { return indexValue }
    guard let indexNumber = indexValue.asNumber else { return .error(.value) }
    let index = Int(indexNumber.rounded(.down))

    var exact = false  // Excel default: approximate match
    if args.count == 4 {
      let flag = evaluate(args[3])
      if case .error = flag { return flag }
      // FALSE → exact; TRUE/omitted → approximate
      exact = !(flag.asBool ?? true)
    }

    let n = normalizedBounds(start: start, end: end)
    let span = horizontal ? (n.maxRow - n.minRow + 1) : (n.maxCol - n.minCol + 1)
    guard index >= 1, index <= span else { return .error(.ref) }

    let resultOffset = (horizontal ? n.minRow : n.minCol) + index - 1
    // An exact lookup of `"app*"` or `"b?"` matches text as a wildcard, as in other apps; it
    // looked for those characters (found by script, Nov 18).
    if exact, case .string(let pattern) = needle, excelHasWildcard(pattern) {
      return wildcardTableLookup(
        pattern: pattern, horizontal: horizontal, bounds: n, start: start,
        resultOffset: resultOffset)
    }
    if exact, let cache = lookupTableCache {
      let tableKey = LookupTableKey(
        sheet: (start.sheet ?? end.sheet ?? formulaSheetName ?? "").lowercased(),
        minRow: n.minRow,
        minCol: n.minCol,
        maxRow: n.maxRow,
        maxCol: n.maxCol,
        resultIndex: index,
        horizontal: horizontal
      )
      if let hit = cache.exactLookup(
        key: tableKey, needle: needle,
        build: {
          buildExactLookupMap(
            horizontal: horizontal,
            bounds: n,
            start: start,
            resultOffset: resultOffset
          )
        })
      {
        return hit
      }
      return .error(.na)
    }

    let outerStart = horizontal ? n.minCol : n.minRow
    let outerEnd = horizontal ? n.maxCol : n.maxRow
    func resultRef(_ position: Int) -> FormulaRef {
      FormulaRef(
        sheet: start.sheet, row: horizontal ? resultOffset : position,
        col: horizontal ? position : resultOffset, absRow: false, absCol: false)
    }
    var keys: [CellValue] = []
    keys.reserveCapacity(outerEnd - outerStart + 1)
    for position in outerStart...outerEnd {
      let key = lookup(
        FormulaRef(
          sheet: start.sheet, row: horizontal ? n.minRow : position,
          col: horizontal ? position : n.minCol, absRow: false, absCol: false))
      if exact {
        if case .error = key { return key }
        if valuesEqual(needle, key) { return lookup(resultRef(position)) }
      } else {
        keys.append(key)
      }
    }
    if exact { return .error(.na) }
    guard let index = Self.sortedSearch(needle, in: keys, descending: false) else {
      return .error(.na)
    }
    return lookup(resultRef(outerStart + index))
  }

  /// Excel's approximate match: a binary search over the values of the needle's kind (numbers,
  /// text or TRUE/FALSE; blanks and errors are passed over) for the last one not past it, in
  /// ascending order, or not below it in descending order. On sorted data that is the largest
  /// value up to the needle. On anything else it gives what other apps give, which some
  /// workbooks rely on: MATCH(9.99E+307,B:B) finds the last number, MATCH("zzz",D:D) the last
  /// text. Spark Grid took the largest value up to the needle, and text needles found nothing
  /// (found by script against Excel 16.115, Nov 18).
  /// Numbers, text and TRUE/FALSE are searched apart; blanks and errors are passed over.
  static func lookupKind(_ value: CellValue) -> Int? {
    switch value {
    case .number: return 0
    case .string: return 1
    case .bool: return 2
    case .blank, .error: return nil
    }
  }

  static func sortedSearch(_ needle: CellValue, in values: [CellValue], descending: Bool) -> Int? {
    guard let needleKind = lookupKind(needle) else { return nil }
    var candidates: [Int] = []
    candidates.reserveCapacity(values.count)
    for (index, value) in values.enumerated() where lookupKind(value) == needleKind {
      candidates.append(index)
    }
    var lo = 0
    var hi = candidates.count - 1
    var found: Int?
    while lo <= hi {
      let mid = (lo + hi) / 2
      let order = comparisonOrder(values[candidates[mid]], needle)
      if descending ? order >= 0 : order <= 0 {
        found = mid
        lo = mid + 1
      } else {
        hi = mid - 1
      }
    }
    return found.map { candidates[$0] }
  }

  /// The first text key in the table's first column (or row) that `pattern` matches.
  func wildcardTableLookup(
    pattern: String,
    horizontal: Bool,
    bounds n: (minRow: Int, minCol: Int, maxRow: Int, maxCol: Int),
    start: FormulaRef,
    resultOffset: Int
  ) -> CellValue {
    let first = horizontal ? n.minCol : n.minRow
    let last = horizontal ? n.maxCol : n.maxRow
    for position in first...last {
      let key = lookup(
        FormulaRef(
          sheet: start.sheet, row: horizontal ? n.minRow : position,
          col: horizontal ? position : n.minCol, absRow: false, absCol: false))
      guard case .string(let text) = key, excelWildcardMatch(text, pattern: pattern) else {
        continue
      }
      return lookup(
        FormulaRef(
          sheet: start.sheet, row: horizontal ? resultOffset : position,
          col: horizontal ? position : resultOffset, absRow: false, absCol: false))
    }
    return .error(.na)
  }

  public func buildExactLookupMap(
    horizontal: Bool,
    bounds: (minRow: Int, minCol: Int, maxRow: Int, maxCol: Int),
    start: FormulaRef,
    resultOffset: Int
  ) -> [AggregateValueKey: CellValue] {
    var map: [AggregateValueKey: CellValue] = [:]
    let outerStart = horizontal ? bounds.minCol : bounds.minRow
    let outerEnd = horizontal ? bounds.maxCol : bounds.maxRow
    for position in outerStart...outerEnd {
      let keyRef = FormulaRef(
        sheet: start.sheet,
        row: horizontal ? bounds.minRow : position,
        col: horizontal ? position : bounds.minCol,
        absRow: false,
        absCol: false
      )
      let key = lookup(keyRef)
      if case .error = key { continue }
      guard let keyIndex = AggregateValueKey.from(cellValue: key) else { continue }
      if map[keyIndex] != nil { continue }
      let result = lookup(
        FormulaRef(
          sheet: start.sheet,
          row: horizontal ? resultOffset : position,
          col: horizontal ? position : resultOffset,
          absRow: false,
          absCol: false
        ))
      map[keyIndex] = result
    }
    return map
  }

  /// Exact lookup equality. An empty cell matches nothing, as in other apps: MATCH(0,…,0) and
  /// XLOOKUP(0,…) found the first blank as if it were 0 (found by script, Nov 18).
  private func valuesEqual(_ lhs: CellValue, _ rhs: CellValue) -> Bool {
    if case .blank = rhs { return false }
    if case .blank = lhs { return false }
    if let a = lhs.asNumber, let b = rhs.asNumber {
      return a == b
    }
    return lhs.asString.caseInsensitiveCompare(rhs.asString) == .orderedSame
  }

  private func rangeValues(_ expr: FormulaExpr) -> [CellValue]? {
    let resolved: FormulaExpr
    if case .namedRange(let name) = expr, let rangeExpr = namedRangeLookup(name) {
      resolved = rangeExpr
    } else if case .call(let name, let args) = expr, Self.isReferenceFunction(name) {
      guard let target = referenceFunctionTarget(name, args) else { return nil }
      resolved = target
    } else {
      resolved = expr
    }
    switch resolved {
    case .range(let start, let end):
      let n = normalizedBounds(start: start, end: end)
      if aggregateRangeCache != nil,
        InputBounds.materializedCount(
          rows: n.maxRow - n.minRow + 1, cols: n.maxCol - n.minCol + 1) != nil
      {
        return rangeCellValues(start: start, end: end)
      }
      var values: [CellValue] = []
      for row in n.minRow...n.maxRow {
        for col in n.minCol...n.maxCol {
          var ref = FormulaRef(sheet: start.sheet, row: row, col: col, absRow: false, absCol: false)
          if ref.sheet == nil { ref.sheet = end.sheet }
          values.append(lookup(ref))
        }
      }
      return values
    case .array:
      // MATCH("c", {"a","b","c"}, 0) looks through a typed list.
      return arrayEvaluate(resolved, cache: nil)
    default:
      // And through what a spilling formula gives, as in MATCH(x, UNIQUE(...), 0), or worked
      // out from a range, as in MATCH(2, 1/(B1:B8>40)), which finds the last row that holds.
      if Self.spills(resolved) || Self.givesArray(resolved) {
        return evaluateArray(resolved).values
      }
      return [evaluate(resolved)]
    }
  }

  public func normalizedBounds(start: FormulaRef, end: FormulaRef) -> (
    minRow: Int, maxRow: Int, minCol: Int, maxCol: Int
  ) {
    let sheet = start.sheet ?? end.sheet
    let extent = sheetExtent(sheet)
    return A1Reference.resolvedBounds(
      start: start,
      end: end,
      maxRow: extent.maxRow,
      maxCol: extent.maxCol
    )
  }

  private func substring(_ args: [FormulaExpr], fromStart: Bool) -> CellValue {
    guard args.count == 1 || args.count == 2 else { return .error(.value) }
    let value = evaluate(args[0])
    if case .error = value { return value }
    var count = 1.0
    if args.count == 2 {
      let c = evaluate(args[1])
      if case .error = c { return c }
      guard let cn = c.asNumber else { return .error(.value) }
      count = cn
    }
    guard count >= 0 else { return .error(.value) }
    let n = Int(count.rounded(.down))
    let chars = Array(value.asString)
    if fromStart {
      return .string(String(chars.prefix(n)))
    }
    return .string(String(chars.suffix(n)))
  }

  private func extreme(_ args: [FormulaExpr], pickMin: Bool) -> CellValue {
    let read = statNumbers(args, textIsError: true)
    if let error = read.error { return error }
    // No numbers at all gives 0, as in other apps.
    return .number((pickMin ? read.numbers.min() : read.numbers.max()) ?? 0)
  }

  /// The numbers SUM, AVERAGE, COUNT, MIN and MAX read, as other spreadsheet apps read them
  /// (checked against Excel 16.115, Nov 18). From a cell, a range or a list, only numbers
  /// count: TRUE, FALSE and text there are skipped, so a TRUE in A1:A8 is not 1. Typed
  /// straight into the call, or worked out there (`SUM(--A4)`), TRUE is 1, FALSE 0 and text
  /// that reads as a number counts; other text is #VALUE! (COUNT skips it).
  func statNumbers(_ args: [FormulaExpr], textIsError: Bool, countOnly: Bool = false)
    -> (numbers: [Double], error: CellValue?)
  {
    var numbers: [Double] = []
    for arg in args {
      let resolved: FormulaExpr
      if case .namedRange(let name) = arg, let rangeExpr = namedRangeLookup(name) {
        resolved = rangeExpr
      } else {
        resolved = arg
      }
      if case .missing = resolved { continue }
      let values = arrayEvaluate(resolved, cache: nil)
      if values.count == 1, Self.readsAsTypedValue(resolved) {
        switch values[0] {
        case .number(let n): numbers.append(n)
        case .bool(let b): numbers.append(b ? 1 : 0)
        case .string(let text):
          if let n = CellValue.numberReadingGroupCommas(
            text.trimmingCharacters(in: .whitespaces))
          {
            numbers.append(n)
          } else if textIsError {
            return (numbers, .error(.value))
          }
        case .error:
          if !countOnly { return (numbers, values[0]) }
        case .blank:
          continue
        }
        continue
      }
      for value in values {
        switch value {
        case .number(let n): numbers.append(n)
        case .error: if !countOnly { return (numbers, value) }
        default: continue
        }
      }
    }
    return (numbers, nil)
  }

  /// An argument whose value counts as typed into the call: not a cell, range, name, list or
  /// spill reference.
  static func readsAsTypedValue(_ expr: FormulaExpr) -> Bool {
    switch expr {
    case .cellRef, .range, .namedRange, .array: return false
    case .call(let name, _):
      let plain = plainFunctionName(name)
      return !arrayFunctionNames.contains(plain) && plain != "INDEX" && plain != "OFFSET"
        && plain != "INDIRECT"
    default: return true
    }
  }

  private func aggregate(
    _ args: [FormulaExpr],
    skipNonNumeric: Bool,
    combine: (Double, Double) -> Double
  ) -> CellValue {
    var total = 0.0
    var saw = false
    for value in flatten(args) {
      if case .error = value { return value }
      if let n = value.asNumber {
        total = saw ? combine(total, n) : n
        saw = true
      } else if !skipNonNumeric {
        return .error(.value)
      }
    }
    return .number(total)
  }

  private func numericForStats(_ value: CellValue) -> Double? {
    switch value {
    case .number(let n): return n
    case .bool(let b): return b ? 1 : 0
    case .blank, .string, .error: return nil
    }
  }

  func flatten(_ args: [FormulaExpr]) -> [CellValue] {
    var values: [CellValue] = []
    for arg in args {
      let resolved: FormulaExpr
      if case .namedRange(let name) = arg, let rangeExpr = namedRangeLookup(name) {
        resolved = rangeExpr
      } else {
        resolved = arg
      }
      // Expands ranges and broadcast arithmetic like `(A2+A6+A7)*(B3:B5)`.
      values.append(contentsOf: arrayEvaluate(resolved, cache: nil))
    }
    return values
  }
}

public enum FormulaDependencies {
  /// One AST walk for workbook ingest (deps; optional range list for incremental invalidation).
  public static func collectForIngest(
    from expr: FormulaExpr,
    activeSheetName: String,
    maxRow: Int,
    maxCol: Int,
    collectWatchedRanges: Bool,
    namedRangeLookup: (String) -> FormulaExpr? = { _ in nil }
  ) -> (deps: Set<CellAddress>, ranges: [CellRange]) {
    var deps: Set<CellAddress> = []
    var ranges: [CellRange] = []
    collectForIngest(
      expr,
      activeSheetName: activeSheetName,
      maxRow: maxRow,
      maxCol: maxCol,
      collectWatchedRanges: collectWatchedRanges,
      namedRangeLookup: namedRangeLookup,
      intoDeps: &deps,
      intoRanges: &ranges
    )
    return (deps, ranges)
  }

  private static func collectForIngest(
    _ expr: FormulaExpr,
    activeSheetName: String,
    maxRow: Int,
    maxCol: Int,
    collectWatchedRanges: Bool,
    namedRangeLookup: (String) -> FormulaExpr?,
    intoDeps: inout Set<CellAddress>,
    intoRanges: inout [CellRange]
  ) {
    switch expr {
    case .number, .string, .boolean, .error, .missing, .array:
      break
    case .namedRange(let name):
      if let resolved = namedRangeLookup(name) {
        collectForIngest(
          resolved,
          activeSheetName: activeSheetName,
          maxRow: maxRow,
          maxCol: maxCol,
          collectWatchedRanges: collectWatchedRanges,
          namedRangeLookup: namedRangeLookup,
          intoDeps: &intoDeps,
          intoRanges: &intoRanges
        )
      }
    case .cellRef(let ref):
      if ref.isOnSheet(activeSheetName), !ref.isRowOpen, !ref.isColOpen {
        intoDeps.insert(ref.address)
      }
    case .range(let start, let end):
      if start.isOnSheet(activeSheetName) {
        let n = A1Reference.resolvedBounds(
          start: start,
          end: end,
          maxRow: maxRow,
          maxCol: maxCol
        )
        let rows = InputBounds.span(from: n.minRow, through: n.maxRow)
        let cols = InputBounds.span(from: n.minCol, through: n.maxCol)
        if InputBounds.materializedCount(rows: rows, cols: cols) == 1 {
          intoDeps.insert(CellAddress(row: n.minRow, col: n.minCol))
        } else if collectWatchedRanges {
          intoRanges.append(
            CellRange(
              start: CellAddress(row: n.minRow, col: n.minCol),
              end: CellAddress(row: n.maxRow, col: n.maxCol)
            )
          )
        }
      }
    case .unary(_, let inner):
      collectForIngest(
        inner,
        activeSheetName: activeSheetName,
        maxRow: maxRow,
        maxCol: maxCol,
        collectWatchedRanges: collectWatchedRanges,
        namedRangeLookup: namedRangeLookup,
        intoDeps: &intoDeps,
        intoRanges: &intoRanges
      )
    case .binary(_, let lhs, let rhs):
      collectForIngest(
        lhs,
        activeSheetName: activeSheetName,
        maxRow: maxRow,
        maxCol: maxCol,
        collectWatchedRanges: collectWatchedRanges,
        namedRangeLookup: namedRangeLookup,
        intoDeps: &intoDeps,
        intoRanges: &intoRanges
      )
      collectForIngest(
        rhs,
        activeSheetName: activeSheetName,
        maxRow: maxRow,
        maxCol: maxCol,
        collectWatchedRanges: collectWatchedRanges,
        namedRangeLookup: namedRangeLookup,
        intoDeps: &intoDeps,
        intoRanges: &intoRanges
      )
    case .call(let name, let args):
      // `C1#` reads C1's spilled cells, which are laid out after C1 recalculates. The background
      // update recalculates it from the workbook graph, where it reads C1; recalculated here, it
      // read C1's old results and the background update kept that.
      guard !FormulaEvaluator.isSpillReference(name) else { break }
      // INDIRECT's and OFFSET's targets are known only when they run: they watch the whole sheet, as other
      // apps recalculate it on every change. The workbook graph watches the other sheets.
      if FormulaEvaluator.isVolatileReference(name), collectWatchedRanges {
        intoRanges.append(
          CellRange(
            start: CellAddress(row: 0, col: 0),
            end: CellAddress(
              row: InputBounds.maxStructureCount - 1, col: 16_383)))
      }
      for arg in args {
        collectForIngest(
          arg,
          activeSheetName: activeSheetName,
          maxRow: maxRow,
          maxCol: maxCol,
          collectWatchedRanges: collectWatchedRanges,
          namedRangeLookup: namedRangeLookup,
          intoDeps: &intoDeps,
          intoRanges: &intoRanges
        )
      }
    }
  }

  /// Sheet-local ranges referenced by a formula (for invalidation when cells inside change).
  public static func collectWatchedRanges(
    from expr: FormulaExpr,
    activeSheetName: String,
    maxRow: Int,
    maxCol: Int,
    namedRangeLookup: (String) -> FormulaExpr? = { _ in nil }
  ) -> [CellRange] {
    var ranges: [CellRange] = []
    collectWatchedRanges(
      expr,
      activeSheetName: activeSheetName,
      maxRow: maxRow,
      maxCol: maxCol,
      namedRangeLookup: namedRangeLookup,
      into: &ranges
    )
    return ranges
  }

  private static func collectWatchedRanges(
    _ expr: FormulaExpr,
    activeSheetName: String,
    maxRow: Int,
    maxCol: Int,
    namedRangeLookup: (String) -> FormulaExpr?,
    into ranges: inout [CellRange]
  ) {
    switch expr {
    case .number, .string, .boolean, .error, .missing, .array:
      break
    case .namedRange(let name):
      if let resolved = namedRangeLookup(name) {
        collectWatchedRanges(
          resolved,
          activeSheetName: activeSheetName,
          maxRow: maxRow,
          maxCol: maxCol,
          namedRangeLookup: namedRangeLookup,
          into: &ranges
        )
      }
    case .cellRef:
      break
    case .range(let start, let end):
      if start.isOnSheet(activeSheetName) {
        let n = A1Reference.resolvedBounds(
          start: start,
          end: end,
          maxRow: maxRow,
          maxCol: maxCol
        )
        let rows = n.maxRow - n.minRow + 1
        let cols = n.maxCol - n.minCol + 1
        if rows * cols > 1 {
          ranges.append(
            CellRange(
              start: CellAddress(row: n.minRow, col: n.minCol),
              end: CellAddress(row: n.maxRow, col: n.maxCol)
            )
          )
        }
      }
    case .unary(_, let inner):
      collectWatchedRanges(
        inner,
        activeSheetName: activeSheetName,
        maxRow: maxRow,
        maxCol: maxCol,
        namedRangeLookup: namedRangeLookup,
        into: &ranges
      )
    case .binary(_, let lhs, let rhs):
      collectWatchedRanges(
        lhs,
        activeSheetName: activeSheetName,
        maxRow: maxRow,
        maxCol: maxCol,
        namedRangeLookup: namedRangeLookup,
        into: &ranges
      )
      collectWatchedRanges(
        rhs,
        activeSheetName: activeSheetName,
        maxRow: maxRow,
        maxCol: maxCol,
        namedRangeLookup: namedRangeLookup,
        into: &ranges
      )
    case .call(_, let args):
      for arg in args {
        collectWatchedRanges(
          arg,
          activeSheetName: activeSheetName,
          maxRow: maxRow,
          maxCol: maxCol,
          namedRangeLookup: namedRangeLookup,
          into: &ranges
        )
      }
    }
  }

  /// Local (same-sheet) dependencies for the active sheet's dependency graph.
  public static func collect(
    from expr: FormulaExpr,
    activeSheetName: String,
    maxRow: Int,
    maxCol: Int,
    namedRangeLookup: (String) -> FormulaExpr? = { _ in nil }
  ) -> Set<CellAddress> {
    var deps: Set<CellAddress> = []
    collect(
      expr,
      activeSheetName: activeSheetName,
      maxRow: maxRow,
      maxCol: maxCol,
      namedRangeLookup: namedRangeLookup,
      into: &deps
    )
    return deps
  }

  private static func collect(
    _ expr: FormulaExpr,
    activeSheetName: String,
    maxRow: Int,
    maxCol: Int,
    namedRangeLookup: (String) -> FormulaExpr?,
    into deps: inout Set<CellAddress>
  ) {
    switch expr {
    case .number, .string, .boolean, .error, .missing, .array:
      break
    case .namedRange(let name):
      if let resolved = namedRangeLookup(name) {
        collect(
          resolved,
          activeSheetName: activeSheetName,
          maxRow: maxRow,
          maxCol: maxCol,
          namedRangeLookup: namedRangeLookup,
          into: &deps
        )
      }
    case .cellRef(let ref):
      if ref.isOnSheet(activeSheetName), !ref.isRowOpen, !ref.isColOpen {
        deps.insert(ref.address)
      }
    case .range(let start, let end):
      if start.isOnSheet(activeSheetName) {
        let n = A1Reference.resolvedBounds(
          start: start,
          end: end,
          maxRow: maxRow,
          maxCol: maxCol
        )
        let rows = n.maxRow - n.minRow + 1
        let cols = n.maxCol - n.minCol + 1
        // Multi-cell ranges (COUNTIFS criteria ranges, etc.) are read via lookup at
        // evaluate time. Listing every cell as a dependency forces recalc of the
        // entire range before each summary formula.
        if rows * cols == 1 {
          deps.insert(CellAddress(row: n.minRow, col: n.minCol))
        }
      }
    case .unary(_, let expr):
      collect(
        expr,
        activeSheetName: activeSheetName,
        maxRow: maxRow,
        maxCol: maxCol,
        namedRangeLookup: namedRangeLookup,
        into: &deps
      )
    case .binary(_, let lhs, let rhs):
      collect(
        lhs,
        activeSheetName: activeSheetName,
        maxRow: maxRow,
        maxCol: maxCol,
        namedRangeLookup: namedRangeLookup,
        into: &deps
      )
      collect(
        rhs,
        activeSheetName: activeSheetName,
        maxRow: maxRow,
        maxCol: maxCol,
        namedRangeLookup: namedRangeLookup,
        into: &deps
      )
    case .call(_, let args):
      for arg in args {
        collect(
          arg,
          activeSheetName: activeSheetName,
          maxRow: maxRow,
          maxCol: maxCol,
          namedRangeLookup: namedRangeLookup,
          into: &deps
        )
      }
    }
  }
}
