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

  public func evaluate(_ expr: FormulaExpr) -> CellValue {
    if budget.depth >= budget.maxDepth {
      return .error(.value)
    }
    budget.depth += 1
    defer { budget.depth -= 1 }
    switch expr {
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
    }
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
    }
  }

  public func applyBinary(_ op: BinaryOp, lhs: CellValue, rhs: CellValue) -> CellValue {
    if case .error = lhs { return lhs }
    if case .error = rhs { return rhs }

    switch op {
    case .concat:
      return .string(lhs.asString + rhs.asString)
    case .add, .subtract, .multiply, .divide, .power:
      guard let a = lhs.asNumber, let b = rhs.asNumber else { return .error(.value) }
      switch op {
      case .add: return .number(a + b)
      case .subtract: return .number(a - b)
      case .multiply: return .number(a * b)
      case .divide:
        guard b != 0 else { return .error(.divZero) }
        return .number(a / b)
      case .power: return .number(pow(a, b))
      default: return .error(.value)
      }
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
    case .number, .string, .boolean, .error, .cellRef:
      return [evaluate(expr)]
    case .namedRange(let name):
      guard let resolved = namedRangeLookup(name) else { return [.error(.name)] }
      return arrayEvaluate(resolved, cache: cache)
    case .range(let start, let end):
      return rangeCellValues(start: start, end: end)
    case .unary(let op, let inner):
      return arrayEvaluate(inner, cache: cache).map { applyUnary(op, to: $0) }
    case .binary(let op, let lhs, let rhs):
      return arrayBinary(op, lhs, rhs, cache: cache)
    case .call(let name, _):
      // SUM(FILTER(...)) adds every value the array function gives.
      if Self.arrayFunctionNames.contains(Self.plainFunctionName(name)) {
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
    if let a = lhs.asNumber, let b = rhs.asNumber {
      switch op {
      case .eq: return .bool(a == b)
      case .ne: return .bool(a != b)
      case .lt: return .bool(a < b)
      case .gt: return .bool(a > b)
      case .le: return .bool(a <= b)
      case .ge: return .bool(a >= b)
      default: return .error(.value)
      }
    }
    // Text compares without regard to case, as other spreadsheet apps compare it:
    // "east" = "East" is TRUE.
    let order = lhs.asString.compare(rhs.asString, options: [.caseInsensitive])
    switch op {
    case .eq: return .bool(order == .orderedSame)
    case .ne: return .bool(order != .orderedSame)
    case .lt: return .bool(order == .orderedAscending)
    case .gt: return .bool(order == .orderedDescending)
    case .le: return .bool(order != .orderedDescending)
    case .ge: return .bool(order != .orderedAscending)
    default: return .error(.value)
    }
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
    case "SUM": return aggregate(args, skipNonNumeric: true) { $0 + $1 }
    case "AVERAGE":
      if let fast = fastAverageIfPossible(args) { return fast }
      var sum = 0.0
      var count = 0
      for value in flatten(args) {
        if case .error = value { return value }
        if let n = numericForStats(value) {
          sum += n
          count += 1
        }
      }
      guard count > 0 else { return .error(.divZero) }
      return .number(sum / Double(count))
    case "COUNT":
      var count = 0
      for value in flatten(args) {
        if case .error = value { return value }
        if numericForStats(value) != nil { count += 1 }
      }
      return .number(Double(count))
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
        return evaluate(args[1])
      }
      if args.count == 3 {
        return evaluate(args[2])
      }
      return .bool(false)
    case "IFERROR":
      guard args.count == 2 else { return .error(.value) }
      if let fast = fastIFERRORVLOOKUP(args) {
        return fast
      }
      let value = evaluate(args[0])
      if case .error = value {
        return evaluate(args[1])
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
      let collapsed = value.asString
        .split(whereSeparator: { $0.isWhitespace })
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
      return evalDatePart(args) { ExcelDate.utcComponent(.year, from: $0) }
    case "MONTH":
      return evalDatePart(args) { ExcelDate.utcComponent(.month, from: $0) }
    case "DAY":
      return evalDatePart(args) { ExcelDate.utcComponent(.day, from: $0) }
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
    case "SEQUENCE", "FILTER", "SORT", "SORTBY", "UNIQUE":
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
      return evalBatch1(name, args) ?? evalBatch2(name, args) ?? .error(.name)
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
      if let rendered = ExcelFormatCode.formatted(number, code: pattern, fractionDigits: nil) {
        return .string(rendered)
      }
      return .string(value.displayString)
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
      for (index, value) in values.enumerated() {
        if case .error = value { return value }
        if valuesEqual(needle, value) {
          return .number(Double(index + 1))
        }
      }
      return .error(.na)
    }

    // Approximate: largest value ≤ needle (match_type 1) or smallest ≥ needle (-1)
    guard let needleNum = needle.asNumber else { return .error(.na) }
    var best: (index: Int, key: Double)?
    for (index, value) in values.enumerated() {
      if case .error = value { return value }
      guard let key = value.asNumber else { continue }
      if matchType > 0 {
        if key <= needleNum, best == nil || key >= (best?.key ?? key) {
          best = (index, key)
        }
      } else if key >= needleNum, best == nil || key <= (best?.key ?? key) {
        best = (index, key)
      }
    }
    guard let best else { return .error(.na) }
    return .number(Double(best.index + 1))
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

  private func evalDatePart(_ args: [FormulaExpr], _ part: (Date) -> Int) -> CellValue {
    guard args.count == 1 else { return .error(.value) }
    let value = evaluate(args[0])
    if case .error = value { return value }
    guard let serial = value.asNumber, let date = ExcelDate.date(from: serial) else {
      return .error(.value)
    }
    return .number(Double(part(date)))
  }

  private func resolveToRange(_ expr: FormulaExpr) -> FormulaExpr? {
    switch expr {
    case .range:
      return expr
    case .namedRange(let name):
      return namedRangeLookup(name)
    default:
      return nil
    }
  }

  private func resolveToRangeExpr(_ expr: FormulaExpr) -> FormulaExpr? {
    resolveToRange(expr)
  }

  private func evalXLOOKUP(_ args: [FormulaExpr]) -> CellValue {
    // 4-argument calls stay exact: the fourth value is if_not_found, not a match mode.
    guard args.count >= 3, args.count <= 5 else { return .error(.value) }
    let needle = evaluate(args[0])
    if case .error = needle { return needle }

    let lookupValues = rangeValues(args[1])
    let returnValues = rangeValues(args[2])
    guard let lookupValues, let returnValues else { return .error(.value) }
    guard lookupValues.count == returnValues.count, !lookupValues.isEmpty else {
      return .error(.value)
    }

    let mode: XLookupMatchMode
    if args.count == 5 {
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
      if args.count >= 4 {
        return evaluate(args[3])
      }
      return .error(.na)
    }
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

    var approximate: (key: Double, value: CellValue)?
    let outerStart = horizontal ? n.minCol : n.minRow
    let outerEnd = horizontal ? n.maxCol : n.maxRow

    for position in outerStart...outerEnd {
      let keyRef = FormulaRef(
        sheet: start.sheet,
        row: horizontal ? n.minRow : position,
        col: horizontal ? position : n.minCol,
        absRow: false,
        absCol: false
      )
      let key = lookup(keyRef)
      if case .error = key { return key }

      let result = lookup(
        FormulaRef(
          sheet: start.sheet,
          row: horizontal ? resultOffset : position,
          col: horizontal ? position : resultOffset,
          absRow: false,
          absCol: false
        ))

      if exact {
        if valuesEqual(needle, key) { return result }
      } else {
        guard let needleNum = needle.asNumber, let keyNum = key.asNumber else { continue }
        if keyNum <= needleNum {
          if approximate == nil || keyNum >= (approximate?.key ?? keyNum) {
            approximate = (keyNum, result)
          }
        }
      }
    }

    if exact { return .error(.na) }
    return approximate?.value ?? .error(.na)
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

  private func valuesEqual(_ lhs: CellValue, _ rhs: CellValue) -> Bool {
    if let a = lhs.asNumber, let b = rhs.asNumber {
      return a == b
    }
    return lhs.asString.caseInsensitiveCompare(rhs.asString) == .orderedSame
  }

  private func rangeValues(_ expr: FormulaExpr) -> [CellValue]? {
    let resolved: FormulaExpr
    if case .namedRange(let name) = expr, let rangeExpr = namedRangeLookup(name) {
      resolved = rangeExpr
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
    default:
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
    let n = max(0, Int(count.rounded(.down)))
    let chars = Array(value.asString)
    if fromStart {
      return .string(String(chars.prefix(n)))
    }
    return .string(String(chars.suffix(n)))
  }

  private func extreme(_ args: [FormulaExpr], pickMin: Bool) -> CellValue {
    var current: Double?
    for value in flatten(args) {
      if case .error = value { return value }
      guard let n = numericForStats(value) else { continue }
      if let c = current {
        current = pickMin ? min(c, n) : max(c, n)
      } else {
        current = n
      }
    }
    guard let current else { return .error(.value) }
    return .number(current)
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
    case .number, .string, .boolean, .error:
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
    case .call(_, let args):
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
    case .number, .string, .boolean, .error:
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
    case .number, .string, .boolean, .error:
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
