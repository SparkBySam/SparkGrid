import Formula
import Foundation
import GridCore

/// A formula result with a shape: rows of values, row-major. A formula whose result has more
/// than one value spills it into the cells below and to the right.
public nonisolated struct ArrayResult: Equatable, Sendable {
  public var rows: Int
  public var cols: Int
  public var values: [CellValue]

  public init(rows: Int, cols: Int, values: [CellValue]) {
    self.rows = rows
    self.cols = cols
    self.values = values
  }

  public init(_ value: CellValue) {
    self.init(rows: 1, cols: 1, values: [value])
  }

  public var isSingle: Bool { rows == 1 && cols == 1 }
  public var first: CellValue { values.first ?? .blank }

  public func value(row: Int, col: Int) -> CellValue {
    guard row >= 0, row < rows, col >= 0, col < cols else { return .error(.na) }
    let index = row * cols + col
    return index < values.count ? values[index] : .blank
  }

  func row(_ r: Int) -> [CellValue] {
    (0..<cols).map { value(row: r, col: $0) }
  }

  func column(_ c: Int) -> [CellValue] {
    (0..<rows).map { value(row: $0, col: c) }
  }

  var transposed: ArrayResult {
    var out: [CellValue] = []
    out.reserveCapacity(values.count)
    for c in 0..<cols {
      for r in 0..<rows { out.append(value(row: r, col: c)) }
    }
    return ArrayResult(rows: cols, cols: rows, values: out)
  }
}

extension FormulaEvaluator {
  /// The formula being evaluated is an array formula whose spill is blocked.
  var spillIsBlocked: Bool {
    guard let origin = evaluationOrigin, let sheet = formulaSheetName else { return false }
    return spillBlocked(sheet, origin)
  }

  /// Functions whose result can be many cells.
  public static let arrayFunctionNames: Set<String> = [
    "FILTER", "SORT", "SORTBY", "UNIQUE", "SEQUENCE",
  ]

  /// The name without the `_xlfn.` and `_xlws.` prefixes Excel saves newer functions with.
  public static func plainFunctionName(_ name: String) -> String {
    var upper = name.uppercased()
    for prefix in ["_XLFN.", "_XLWS."] where upper.hasPrefix(prefix) {
      upper.removeFirst(prefix.count)
    }
    if upper.hasPrefix("_XLWS.") { upper.removeFirst("_XLWS.".count) }
    return upper
  }

  /// True when the formula's outermost result can spill: it calls an array function outside any
  /// other function, as in `=FILTER(...)` or `=SORT(UNIQUE(...))*2`.
  public static func spills(_ expr: FormulaExpr) -> Bool {
    switch expr {
    case .call(let name, _):
      return arrayFunctionNames.contains(plainFunctionName(name))
    case .unary(_, let inner):
      return spills(inner)
    case .binary(_, let lhs, let rhs):
      return spills(lhs) || spills(rhs)
    default:
      return false
    }
  }

  /// The whole result of `expr`, with its shape.
  public func evaluateArray(_ expr: FormulaExpr) -> ArrayResult {
    switch expr {
    case .range(let start, let end):
      let n = normalizedBounds(start: start, end: end)
      let rows = n.maxRow - n.minRow + 1
      let cols = n.maxCol - n.minCol + 1
      guard rows > 0, cols > 0 else { return ArrayResult(.error(.ref)) }
      let values = rangeCellValues(start: start, end: end)
      guard values.count == rows * cols else { return ArrayResult(values.first ?? .error(.value)) }
      return ArrayResult(rows: rows, cols: cols, values: values)
    case .namedRange(let name):
      guard let resolved = namedRangeLookup(name) else { return ArrayResult(.error(.name)) }
      return evaluateArray(resolved)
    case .unary(let op, let inner):
      var array = evaluateArray(inner)
      array.values = array.values.map { applyUnary(op, to: $0) }
      return array
    case .binary(let op, let lhs, let rhs):
      return broadcast(evaluateArray(lhs), evaluateArray(rhs)) { applyBinary(op, lhs: $0, rhs: $1) }
    case .call(let rawName, let args):
      switch Self.plainFunctionName(rawName) {
      case "FILTER": return arrayFILTER(args)
      case "SORT": return arraySORT(args)
      case "SORTBY": return arraySORTBY(args)
      case "UNIQUE": return arrayUNIQUE(args)
      case "SEQUENCE": return arraySEQUENCE(args)
      default: return ArrayResult(evaluate(expr))
      }
    default:
      return ArrayResult(evaluate(expr))
    }
  }

  /// Element by element. A single value or a single row or column stretches to the other.
  private func broadcast(
    _ a: ArrayResult, _ b: ArrayResult, _ combine: (CellValue, CellValue) -> CellValue
  ) -> ArrayResult {
    let rows = max(a.rows, b.rows)
    let cols = max(a.cols, b.cols)
    func pick(_ x: ArrayResult, _ r: Int, _ c: Int) -> CellValue? {
      let rr = x.rows == 1 ? 0 : r
      let cc = x.cols == 1 ? 0 : c
      guard rr < x.rows, cc < x.cols else { return nil }
      return x.value(row: rr, col: cc)
    }
    var values: [CellValue] = []
    values.reserveCapacity(rows * cols)
    for r in 0..<rows {
      for c in 0..<cols {
        guard let l = pick(a, r, c), let rv = pick(b, r, c) else {
          values.append(.error(.na))
          continue
        }
        values.append(combine(l, rv))
      }
    }
    return ArrayResult(rows: rows, cols: cols, values: values)
  }

  private func truthy(_ value: CellValue) -> Bool? {
    switch value {
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

  // MARK: - FILTER(array, include, [if_empty])

  private func arrayFILTER(_ args: [FormulaExpr]) -> ArrayResult {
    guard args.count == 2 || args.count == 3 else { return ArrayResult(.error(.value)) }
    let array = evaluateArray(args[0])
    let include = evaluateArray(args[1])
    if array.isSingle, case .error = array.first { return array }
    if let error = include.values.first(where: \.isError) { return ArrayResult(error) }
    var keep: [Bool] = []
    let byRows: Bool
    if include.cols == 1, include.rows == array.rows {
      byRows = true
    } else if include.rows == 1, include.cols == array.cols {
      byRows = false
    } else if include.isSingle, array.rows == 1 || array.cols == 1 {
      byRows = array.cols == 1
    } else {
      return ArrayResult(.error(.value))
    }
    for value in include.values {
      guard let flag = truthy(value) else { return ArrayResult(.error(.value)) }
      keep.append(flag)
    }
    var values: [CellValue] = []
    var count = 0
    if byRows {
      for r in 0..<array.rows where r < keep.count && keep[r] {
        values.append(contentsOf: array.row(r))
        count += 1
      }
      if count > 0 { return ArrayResult(rows: count, cols: array.cols, values: values) }
    } else {
      let kept = (0..<array.cols).filter { $0 < keep.count && keep[$0] }
      for r in 0..<array.rows {
        for c in kept { values.append(array.value(row: r, col: c)) }
      }
      if !kept.isEmpty { return ArrayResult(rows: array.rows, cols: kept.count, values: values) }
    }
    if args.count == 3 { return evaluateArray(args[2]) }
    return ArrayResult(.error(.calc))
  }

  // MARK: - SORT and SORTBY

  /// Excel's sort order: numbers, then text without regard to case, then TRUE/FALSE, then
  /// errors. Blanks go last whichever way the sort runs.
  static func sortRank(_ value: CellValue) -> Int {
    switch value {
    case .number: return 0
    case .string(let s): return s.isEmpty ? 4 : 1
    case .bool: return 2
    case .error: return 3
    case .blank: return 4
    }
  }

  /// -1, 0 or 1, ascending, blanks not handled (callers keep them last).
  static func compareForSort(_ a: CellValue, _ b: CellValue) -> Int {
    let ra = sortRank(a)
    let rb = sortRank(b)
    if ra != rb { return ra < rb ? -1 : 1 }
    switch (a, b) {
    case (.number(let x), .number(let y)): return x == y ? 0 : (x < y ? -1 : 1)
    case (.string(let x), .string(let y)):
      switch x.compare(y, options: [.caseInsensitive, .diacriticInsensitive]) {
      case .orderedAscending: return -1
      case .orderedDescending: return 1
      case .orderedSame: return 0
      }
    case (.bool(let x), .bool(let y)): return x == y ? 0 : (!x ? -1 : 1)
    default: return 0
    }
  }

  /// Rows (or columns) of `array` in the order the keys give, stable.
  private func sorted(
    _ array: ArrayResult, byColumns: Bool, keys: [(values: [CellValue], ascending: Bool)]
  ) -> ArrayResult {
    let source = byColumns ? array.transposed : array
    let order = (0..<source.rows).sorted { i, j in
      for key in keys {
        let a = i < key.values.count ? key.values[i] : .blank
        let b = j < key.values.count ? key.values[j] : .blank
        let blankA = Self.sortRank(a) == 4
        let blankB = Self.sortRank(b) == 4
        if blankA != blankB { return blankB }
        let c = Self.compareForSort(a, b)
        if c != 0 { return key.ascending ? c < 0 : c > 0 }
      }
      return i < j
    }
    var values: [CellValue] = []
    values.reserveCapacity(source.values.count)
    for r in order { values.append(contentsOf: source.row(r)) }
    let result = ArrayResult(rows: source.rows, cols: source.cols, values: values)
    return byColumns ? result.transposed : result
  }

  private func number(_ expr: FormulaExpr, default fallback: Double) -> Double? {
    let value = evaluate(expr)
    if case .blank = value { return fallback }
    return value.asNumber
  }

  private func flag(_ expr: FormulaExpr) -> Bool? {
    let value = evaluate(expr)
    if case .blank = value { return false }
    return truthy(value)
  }

  /// SORT(array, [sort_index], [sort_order], [by_col])
  private func arraySORT(_ args: [FormulaExpr]) -> ArrayResult {
    guard (1...4).contains(args.count) else { return ArrayResult(.error(.value)) }
    let array = evaluateArray(args[0])
    if array.isSingle, case .error = array.first { return array }
    guard let index = args.count > 1 ? number(args[1], default: 1) : 1,
      let order = args.count > 2 ? number(args[2], default: 1) : 1,
      let byColumns = args.count > 3 ? flag(args[3]) : false,
      order == 1 || order == -1
    else { return ArrayResult(.error(.value)) }
    let keyIndex = Int(index) - 1
    let keyCount = byColumns ? array.rows : array.cols
    guard keyIndex >= 0, keyIndex < keyCount else { return ArrayResult(.error(.value)) }
    let key = byColumns ? array.row(keyIndex) : array.column(keyIndex)
    return sorted(array, byColumns: byColumns, keys: [(key, order == 1)])
  }

  /// SORTBY(array, by_array1, [sort_order1], ...)
  private func arraySORTBY(_ args: [FormulaExpr]) -> ArrayResult {
    guard args.count >= 2 else { return ArrayResult(.error(.value)) }
    let array = evaluateArray(args[0])
    if array.isSingle, case .error = array.first { return array }
    var keys: [(values: [CellValue], ascending: Bool)] = []
    var byColumns: Bool?
    var i = 1
    while i < args.count {
      let by = evaluateArray(args[i])
      let order = i + 1 < args.count ? number(args[i + 1], default: 1) : 1
      guard let order, order == 1 || order == -1 else { return ArrayResult(.error(.value)) }
      let columnKey = by.cols == 1 && by.rows == array.rows
      let rowKey = by.rows == 1 && by.cols == array.cols && !columnKey
      guard columnKey || rowKey else { return ArrayResult(.error(.value)) }
      if let byColumns, byColumns != rowKey { return ArrayResult(.error(.value)) }
      byColumns = rowKey
      keys.append((by.values, order == 1))
      i += 2
    }
    return sorted(array, byColumns: byColumns ?? false, keys: keys)
  }

  // MARK: - UNIQUE(array, [by_col], [exactly_once])

  private func arrayUNIQUE(_ args: [FormulaExpr]) -> ArrayResult {
    guard (1...3).contains(args.count) else { return ArrayResult(.error(.value)) }
    let array = evaluateArray(args[0])
    if array.isSingle, case .error = array.first { return array }
    guard let byColumns = args.count > 1 ? flag(args[1]) : false,
      let exactlyOnce = args.count > 2 ? flag(args[2]) : false
    else { return ArrayResult(.error(.value)) }
    let source = byColumns ? array.transposed : array
    // Text matches without regard to case, as other apps match it.
    func key(_ row: [CellValue]) -> [String] {
      row.map { value -> String in
        switch value {
        case .number(let n): return "n:\(n)"
        case .string(let s): return "s:" + s.lowercased()
        case .bool(let b): return "b:\(b)"
        case .blank: return "_"
        case .error(let e): return "e:\(e.displayCode)"
        }
      }
    }
    var counts: [[String]: Int] = [:]
    var firstRows: [Int] = []
    for r in 0..<source.rows {
      let k = key(source.row(r))
      if counts[k] == nil { firstRows.append(r) }
      counts[k, default: 0] += 1
    }
    let kept = firstRows.filter { !exactlyOnce || counts[key(source.row($0))] == 1 }
    guard !kept.isEmpty else { return ArrayResult(.error(.calc)) }
    var values: [CellValue] = []
    for r in kept { values.append(contentsOf: source.row(r)) }
    let result = ArrayResult(rows: kept.count, cols: source.cols, values: values)
    return byColumns ? result.transposed : result
  }

  // MARK: - SEQUENCE(rows, [columns], [start], [step])

  private func arraySEQUENCE(_ args: [FormulaExpr]) -> ArrayResult {
    guard (1...4).contains(args.count) else { return ArrayResult(.error(.value)) }
    guard let rowsNumber = number(args[0], default: 1),
      let colsNumber = args.count > 1 ? number(args[1], default: 1) : 1,
      let start = args.count > 2 ? number(args[2], default: 1) : 1,
      let step = args.count > 3 ? number(args[3], default: 1) : 1
    else { return ArrayResult(.error(.value)) }
    let rows = Int(rowsNumber)
    let cols = Int(colsNumber)
    guard rows >= 1, cols >= 1 else { return ArrayResult(.error(.value)) }
    guard InputBounds.materializedCount(rows: rows, cols: cols) != nil else {
      return ArrayResult(.error(.value))
    }
    let values = (0..<(rows * cols)).map { CellValue.number(start + Double($0) * step) }
    return ArrayResult(rows: rows, cols: cols, values: values)
  }
}
