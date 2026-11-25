import Formula
import Foundation
import GridCore
import Model

/// Functions batch 6 for 1.7: LAMBDA and the functions that take one (MAP, REDUCE, SCAN, BYROW,
/// BYCOL, MAKEARRAY, ISOMITTED), names that hold a LAMBDA called like a function, and EXPAND,
/// GROUPBY and PIVOTBY.
extension FormulaEvaluator {
  /// The array functions in this file. They spill.
  static let lambdaArrayFunctionNames: Set<String> = [
    "MAP", "SCAN", "BYROW", "BYCOL", "MAKEARRAY", "EXPAND", "GROUPBY", "PIVOTBY",
  ]

  /// A function of named parameters, or a built-in function given by name (`BYROW(A1:C3,SUM)`).
  struct Lambda {
    var params: [String]
    var body: FormulaExpr
    var builtIn: String?
  }

  func lambda(from expr: FormulaExpr) -> Lambda? {
    switch expr {
    case .call(let name, let args) where Self.plainFunctionName(name) == "LAMBDA":
      guard let body = args.last else { return nil }
      var params: [String] = []
      for arg in args.dropLast() {
        guard case .namedRange(let raw) = arg, let name = Self.letName(raw),
          !params.contains(name)
        else { return nil }
        params.append(name)
      }
      return Lambda(params: params, body: body, builtIn: nil)
    case .namedRange(let raw):
      if let resolved = namedRangeLookup(raw) { return lambda(from: resolved) }
      var plain = Self.plainFunctionName(raw)
      if plain.hasPrefix("_XLETA.") { plain.removeFirst("_XLETA.".count) }
      guard FormulaFunctions.all.contains(plain) else { return nil }
      return Lambda(params: [], body: .missing, builtIn: plain)
    default:
      return nil
    }
  }

  /// The body with each parameter replaced by the value given for it. Parameters with nothing
  /// given are left out, which ISOMITTED reports. Nil when too many values are given.
  func applied(_ lambda: Lambda, _ values: [FormulaExpr]) -> FormulaExpr? {
    if let name = lambda.builtIn { return .call(name, values) }
    guard values.count <= lambda.params.count else { return nil }
    var bindings: [(name: String, value: FormulaExpr)] = []
    for (index, param) in lambda.params.enumerated() {
      bindings.append((param, index < values.count ? values[index] : .missing))
    }
    return Self.substitute(lambda.body, bindings)
  }

  /// `LAMBDA(x,x*3)(7)`: the LAMBDA's body with the values given after it. A LAMBDA that gives
  /// a LAMBDA (`LAMBDA(x,LAMBDA(y,x+y))(1)(2)`) is worked out first.
  private func calledInPlace(_ args: [FormulaExpr]) -> FormulaExpr? {
    guard var target = args.first else { return nil }
    if case .call(let name, let inner) = target, name == FormulaExpr.lambdaCallFunction {
      guard let made = calledInPlace(inner) else { return nil }
      target = made
    }
    guard let found = lambda(from: target) else { return nil }
    return applied(found, Array(args.dropFirst()))
  }

  /// One value as a formula piece; an empty cell stays empty.
  static func piece(_ value: CellValue) -> FormulaExpr { literal(value) ?? .missing }

  /// An array as a typed list, so a lambda can read a whole row or column.
  static func piece(_ array: ArrayResult) -> FormulaExpr {
    if array.isSingle { return piece(array.first) }
    return .array((0..<array.rows).map { r in array.row(r).map { literal($0) ?? .number(0) } })
  }

  /// A lambda's result for one place in a MAP, BYROW and the rest: one value, or #CALC! when it
  /// gives several.
  private func single(_ lambda: Lambda, _ values: [FormulaExpr]) -> CellValue {
    guard let body = applied(lambda, values) else { return .error(.value) }
    let result = evaluateArray(body)
    return result.isSingle ? result.first : .error(.calc)
  }

  /// Handles a batch 6 function that gives one value, or returns nil when `name` is not one.
  func evalBatch6(_ name: String, _ args: [FormulaExpr]) -> CellValue? {
    switch name {
    case "LAMBDA":
      // A LAMBDA that is not called has no value to show, as in other apps.
      return .error(.calc)
    case FormulaExpr.lambdaCallFunction:
      guard let body = calledInPlace(args) else { return .error(.value) }
      return evaluate(body)
    case "ISOMITTED":
      guard args.count == 1 else { return .error(.value) }
      return .bool(args[0] == .missing)
    case "REDUCE":
      return reduce(args).map { $0.isSingle ? $0.first : .error(.calc) } ?? .error(.value)
    default:
      // A name that holds a LAMBDA, called like a function.
      guard let resolved = namedRangeLookup(name), let found = lambda(from: resolved),
        found.builtIn == nil
      else { return nil }
      guard let body = applied(found, args) else { return .error(.value) }
      return evaluate(body)
    }
  }

  func lambdaArray(_ name: String, _ args: [FormulaExpr]) -> ArrayResult? {
    switch name {
    case "MAP": return map(args)
    case "SCAN": return scan(args)
    case "REDUCE": return reduce(args) ?? Self.fail(.value)
    case "BYROW", "BYCOL": return byLine(args, rows: name == "BYROW")
    case "MAKEARRAY": return makeArray(args)
    case "EXPAND": return expand(args)
    case "GROUPBY": return groupBy(args)
    case "PIVOTBY": return pivotBy(args)
    case FormulaExpr.lambdaCallFunction:
      guard let body = calledInPlace(args) else { return Self.fail(.value) }
      return evaluateArray(body)
    default:
      guard let resolved = namedRangeLookup(name), let found = lambda(from: resolved),
        found.builtIn == nil
      else { return nil }
      guard let body = applied(found, args) else { return Self.fail(.value) }
      return evaluateArray(body)
    }
  }

  // MARK: - MAP, REDUCE, SCAN, BYROW, BYCOL, MAKEARRAY

  private func map(_ args: [FormulaExpr]) -> ArrayResult {
    guard args.count >= 2, let fn = lambda(from: args[args.count - 1]) else {
      return Self.fail(.value)
    }
    let arrays = args.dropLast().map { evaluateArray($0) }
    guard fn.builtIn != nil || fn.params.count == arrays.count else { return Self.fail(.value) }
    let rows = arrays.map(\.rows).max() ?? 1
    let cols = arrays.map(\.cols).max() ?? 1
    guard arrays.allSatisfy({ $0.isSingle || ($0.rows == rows && $0.cols == cols) }) else {
      return Self.fail(.value)
    }
    var out: [CellValue] = []
    out.reserveCapacity(rows * cols)
    for r in 0..<rows {
      for c in 0..<cols {
        let values = arrays.map { Self.piece($0.isSingle ? $0.first : $0.value(row: r, col: c)) }
        out.append(single(fn, values))
      }
    }
    return ArrayResult(rows: rows, cols: cols, values: out)
  }

  /// REDUCE([initial], array, lambda): the running value after every item, row by row.
  private func reduce(_ args: [FormulaExpr]) -> ArrayResult? {
    guard args.count == 3 || args.count == 2, let fn = lambda(from: args[args.count - 1]),
      fn.builtIn != nil || fn.params.count == 2
    else { return nil }
    var accumulator: FormulaExpr =
      args.count == 3 && args[0] != .missing ? Self.piece(evaluateArray(args[0])) : .missing
    var last = ArrayResult(evaluate(accumulator))
    for value in evaluateArray(args[args.count - 2]).values {
      guard let body = applied(fn, [accumulator, Self.piece(value)]) else { return nil }
      last = evaluateArray(body)
      if case .error = last.first, last.isSingle { return last }
      accumulator = Self.piece(last)
    }
    return last
  }

  private func scan(_ args: [FormulaExpr]) -> ArrayResult {
    guard args.count == 3 || args.count == 2, let fn = lambda(from: args[args.count - 1]),
      fn.builtIn != nil || fn.params.count == 2
    else { return Self.fail(.value) }
    var accumulator: FormulaExpr =
      args.count == 3 && args[0] != .missing ? Self.piece(evaluate(args[0])) : .missing
    let source = evaluateArray(args[args.count - 2])
    var out: [CellValue] = []
    out.reserveCapacity(source.values.count)
    for value in source.values {
      let next = single(fn, [accumulator, Self.piece(value)])
      out.append(next)
      accumulator = Self.piece(next)
    }
    return ArrayResult(rows: source.rows, cols: source.cols, values: out)
  }

  private func byLine(_ args: [FormulaExpr], rows byRow: Bool) -> ArrayResult {
    guard args.count == 2, let fn = lambda(from: args[1]),
      fn.builtIn != nil || fn.params.count == 1
    else { return Self.fail(.value) }
    let source = evaluateArray(args[0])
    let count = byRow ? source.rows : source.cols
    let values: [CellValue] = (0..<count).map { i in
      let line =
        byRow
        ? ArrayResult(rows: 1, cols: source.cols, values: source.row(i))
        : ArrayResult(rows: source.rows, cols: 1, values: source.column(i))
      return single(fn, [Self.piece(line)])
    }
    return byRow
      ? ArrayResult(rows: count, cols: 1, values: values)
      : ArrayResult(rows: 1, cols: count, values: values)
  }

  private func makeArray(_ args: [FormulaExpr]) -> ArrayResult {
    guard args.count == 3, let fn = lambda(from: args[2]), fn.params.count == 2 else {
      return Self.fail(.value)
    }
    let r = evaluate(args[0])
    let c = evaluate(args[1])
    if case .error(let e) = r { return Self.fail(e) }
    if case .error(let e) = c { return Self.fail(e) }
    guard let rn = r.asNumber, let cn = c.asNumber else { return Self.fail(.value) }
    let rows = Int(rn.rounded(.towardZero))
    let cols = Int(cn.rounded(.towardZero))
    guard rows >= 1, cols >= 1, rows * cols <= 1_048_576 else { return Self.fail(.value) }
    var out: [CellValue] = []
    out.reserveCapacity(rows * cols)
    for i in 1...rows {
      for j in 1...cols { out.append(single(fn, [.number(Double(i)), .number(Double(j))])) }
    }
    return ArrayResult(rows: rows, cols: cols, values: out)
  }

  // MARK: - EXPAND

  private func expand(_ args: [FormulaExpr]) -> ArrayResult {
    guard (2...4).contains(args.count) else { return Self.fail(.value) }
    let source = evaluateArray(args[0])
    func size(_ index: Int, _ fallback: Int) -> Int? {
      guard index < args.count, args[index] != .missing else { return fallback }
      guard let n = evaluate(args[index]).asNumber else { return nil }
      return Int(n.rounded(.towardZero))
    }
    guard let rows = size(1, source.rows), let cols = size(2, source.cols) else {
      return Self.fail(.value)
    }
    guard rows >= source.rows, cols >= source.cols else { return Self.fail(.value) }
    let pad: CellValue = args.count == 4 && args[3] != .missing ? evaluate(args[3]) : .error(.na)
    var out: [CellValue] = []
    out.reserveCapacity(rows * cols)
    for r in 0..<rows {
      for c in 0..<cols {
        out.append(r < source.rows && c < source.cols ? source.value(row: r, col: c) : pad)
      }
    }
    return ArrayResult(rows: rows, cols: cols, values: out)
  }

  // MARK: - GROUPBY and PIVOTBY

  /// A group key: each key column's value, text without regard to case, as other apps group.
  private struct GroupKey: Hashable {
    var values: [CellValue]
    private var text: String {
      values.map { value -> String in
        switch value {
        case .number(let n): return "n\(n)"
        case .string(let s): return "s" + s.lowercased()
        case .bool(let b): return "b\(b)"
        case .error(let e): return "e" + e.displayCode
        case .blank: return "_"
        }
      }.joined(separator: "\u{1F}")
    }
    static func == (a: GroupKey, b: GroupKey) -> Bool { a.text == b.text }
    func hash(into hasher: inout Hasher) { hasher.combine(text) }
  }

  /// The aggregate of `values` with `fn` (SUM, AVERAGE, a LAMBDA...), given as one column.
  private func aggregateGroup(_ fn: Lambda, _ values: [CellValue]) -> CellValue {
    let column = ArrayResult(
      rows: max(values.count, 1), cols: 1, values: values.isEmpty ? [.blank] : values)
    return single(fn, [Self.piece(column)])
  }

  /// Whether field_headers says the first row is headers, and whether to show them.
  private func headerSetting(_ args: [FormulaExpr], at index: Int, firstValues: [CellValue])
    -> (hasHeaders: Bool, show: Bool)?
  {
    if index < args.count, args[index] != .missing {
      guard let n = evaluate(args[index]).asNumber else { return nil }
      switch Int(n.rounded(.towardZero)) {
      case 0: return (false, false)
      case 1: return (true, false)
      case 2: return (false, true)
      case 3: return (true, true)
      default: return nil
      }
    }
    // Left out: headers when the first value is text and the one under it is not.
    if firstValues.count >= 2, case .string = firstValues[0] {
      if case .string = firstValues[1] { return (false, false) }
      return (true, false)
    }
    return (false, false)
  }

  private func intArgument(_ args: [FormulaExpr], _ index: Int, _ fallback: Int) -> Int? {
    guard index < args.count, args[index] != .missing else { return fallback }
    guard let n = evaluate(args[index]).asNumber else { return nil }
    return Int(n.rounded(.towardZero))
  }

  private func groupBy(_ args: [FormulaExpr]) -> ArrayResult {
    guard (3...8).contains(args.count), let fn = lambda(from: args[2]) else {
      return Self.fail(.value)
    }
    let keys = evaluateArray(args[0])
    let values = evaluateArray(args[1])
    guard keys.rows == values.rows else { return Self.fail(.value) }
    guard
      let headers = headerSetting(args, at: 3, firstValues: values.column(0)),
      let totalDepth = intArgument(args, 4, 1),
      let sortOrder = intArgument(args, 5, 1)
    else { return Self.fail(.value) }
    var include = [Bool](repeating: true, count: keys.rows)
    if args.count > 6, args[6] != .missing {
      let filter = evaluateArray(args[6])
      guard filter.values.count == keys.rows else { return Self.fail(.value) }
      include = filter.values.map { ($0.asBool ?? false) }
    }
    let start = headers.hasHeaders ? 1 : 0
    var order: [GroupKey] = []
    var members: [GroupKey: [Int]] = [:]
    for r in start..<keys.rows where include[r] {
      let key = GroupKey(values: keys.row(r))
      if members[key] == nil { order.append(key) }
      members[key, default: []].append(r)
    }
    var rows: [[CellValue]] = order.map { key in
      key.values
        + (0..<values.cols).map { c in
          aggregateGroup(fn, members[key, default: []].map { values.value(row: $0, col: c) })
        }
    }
    rows = sortRows(rows, by: sortOrder, keyCount: keys.cols)
    var out: [[CellValue]] = []
    if headers.show {
      let keyHeads: [CellValue] = (0..<keys.cols).map { c in
        headers.hasHeaders ? keys.value(row: 0, col: c) : .string("Row Field \(c + 1)")
      }
      let valueHeads: [CellValue] = (0..<values.cols).map { c in
        headers.hasHeaders ? values.value(row: 0, col: c) : .string("Value \(c + 1)")
      }
      out.append(keyHeads + valueHeads)
    }
    var total: [CellValue] = []
    if totalDepth != 0 {
      let all = (start..<keys.rows).filter { include[$0] }
      total =
        [.string("Total")] + [CellValue](repeating: .blank, count: keys.cols - 1)
        + (0..<values.cols).map { c in aggregateGroup(fn, all.map { values.value(row: $0, col: c) })
        }
    }
    if totalDepth < 0 { out.append(total) }
    out += rows
    if totalDepth > 0 { out.append(total) }
    return Self.table(out)
  }

  /// Rows sorted by a 1-based column, descending when negative.
  private func sortRows(_ rows: [[CellValue]], by column: Int, keyCount: Int) -> [[CellValue]] {
    let index = abs(column) - 1
    guard column != 0, index < (rows.first?.count ?? 0) else { return rows }
    return rows.sorted { a, b in
      let order = Self.sortOrder(a[index], b[index])
      return column > 0 ? order < 0 : order > 0
    }
  }

  /// Numbers before text before TRUE/FALSE, text without regard to case, as other apps sort.
  static func sortOrder(_ a: CellValue, _ b: CellValue) -> Int {
    func rank(_ v: CellValue) -> Int {
      switch v {
      case .number: return 0
      case .string: return 1
      case .bool: return 2
      case .error: return 3
      case .blank: return 4
      }
    }
    if rank(a) != rank(b) { return rank(a) < rank(b) ? -1 : 1 }
    switch (a, b) {
    case (.number(let x), .number(let y)): return x < y ? -1 : (x > y ? 1 : 0)
    case (.string(let x), .string(let y)):
      switch x.compare(y, options: [.caseInsensitive], locale: Locale(identifier: "en_US")) {
      case .orderedAscending: return -1
      case .orderedDescending: return 1
      case .orderedSame: return 0
      }
    case (.bool(let x), .bool(let y)): return x == y ? 0 : (x ? 1 : -1)
    default: return 0
    }
  }

  private static func table(_ rows: [[CellValue]]) -> ArrayResult {
    let cols = rows.map(\.count).max() ?? 0
    guard !rows.isEmpty, cols > 0 else { return fail(.calc) }
    let values = rows.flatMap { $0 + [CellValue](repeating: .blank, count: cols - $0.count) }
    return ArrayResult(rows: rows.count, cols: cols, values: values)
  }

  private func pivotBy(_ args: [FormulaExpr]) -> ArrayResult {
    guard (4...10).contains(args.count), let fn = lambda(from: args[3]) else {
      return Self.fail(.value)
    }
    let rowKeys = evaluateArray(args[0])
    let colKeys = evaluateArray(args[1])
    let values = evaluateArray(args[2])
    guard rowKeys.rows == values.rows, colKeys.rows == values.rows, rowKeys.cols == 1,
      colKeys.cols == 1, values.cols == 1
    else { return Self.fail(.value) }
    guard
      let headers = headerSetting(args, at: 4, firstValues: values.column(0)),
      let rowTotals = intArgument(args, 5, 1),
      let rowSort = intArgument(args, 6, 1),
      let colTotals = intArgument(args, 7, 1),
      let colSort = intArgument(args, 8, 1)
    else { return Self.fail(.value) }
    var include = [Bool](repeating: true, count: values.rows)
    if args.count > 9, args[9] != .missing {
      let filter = evaluateArray(args[9])
      guard filter.values.count == values.rows else { return Self.fail(.value) }
      include = filter.values.map { ($0.asBool ?? false) }
    }
    let start = headers.hasHeaders ? 1 : 0
    let used = (start..<values.rows).filter { include[$0] }
    func same(_ a: CellValue, _ b: CellValue) -> Bool {
      GroupKey(values: [a]) == GroupKey(values: [b])
    }
    func distinct(_ array: ArrayResult, descending: Bool) -> [CellValue] {
      var seen: [CellValue] = []
      for r in used where !seen.contains(where: { same($0, array.value(row: r, col: 0)) }) {
        seen.append(array.value(row: r, col: 0))
      }
      return seen.sorted {
        let order = Self.sortOrder($0, $1)
        return descending ? order > 0 : order < 0
      }
    }
    let rowList = distinct(rowKeys, descending: rowSort < 0)
    let colList = distinct(colKeys, descending: colSort < 0)
    func cell(_ row: CellValue?, _ col: CellValue?) -> CellValue {
      let picked = used.filter { r in
        (row.map { same(rowKeys.value(row: r, col: 0), $0) } ?? true)
          && (col.map { same(colKeys.value(row: r, col: 0), $0) } ?? true)
      }
      if picked.isEmpty { return .string("") }
      return aggregateGroup(fn, picked.map { values.value(row: $0, col: 0) })
    }
    var columns: [CellValue?] = colList.map { $0 }
    if colTotals > 0 { columns.append(nil) }
    if colTotals < 0 { columns.insert(nil, at: 0) }
    var out: [[CellValue]] = []
    out.append([.string("")] + columns.map { $0 ?? .string("Total") })
    var rowsOut: [[CellValue]] = rowList.map { key in [key] + columns.map { cell(key, $0) } }
    let totalRow: [CellValue] = [.string("Total")] + columns.map { cell(nil, $0) }
    if rowTotals < 0 { rowsOut.insert(totalRow, at: 0) }
    if rowTotals > 0 { rowsOut.append(totalRow) }
    out += rowsOut
    return Self.table(out)
  }
}
