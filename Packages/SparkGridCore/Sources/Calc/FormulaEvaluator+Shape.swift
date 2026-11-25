import Formula
import Foundation
import GridCore
import Model

/// LET, and the functions that build, cut and reshape arrays: VSTACK, HSTACK, TAKE, DROP,
/// CHOOSECOLS, CHOOSEROWS, WRAPROWS, WRAPCOLS, TOCOL, TOROW, TEXTSPLIT and RANDARRAY.
extension FormulaEvaluator {
  /// The array functions in this file, all of which can spill.
  static let shapeFunctionNames: Set<String> = [
    "VSTACK", "HSTACK", "TAKE", "DROP", "CHOOSECOLS", "CHOOSEROWS", "WRAPROWS", "WRAPCOLS",
    "TOCOL", "TOROW", "TEXTSPLIT", "RANDARRAY", "TRANSPOSE",
  ]

  func shapeArray(_ name: String, _ args: [FormulaExpr]) -> ArrayResult? {
    switch name {
    case "VSTACK": return stack(args, vertically: true)
    case "HSTACK": return stack(args, vertically: false)
    case "TAKE": return takeOrDrop(args, take: true)
    case "DROP": return takeOrDrop(args, take: false)
    case "CHOOSECOLS": return choose(args, columns: true)
    case "CHOOSEROWS": return choose(args, columns: false)
    case "WRAPROWS": return wrap(args, intoRows: true)
    case "WRAPCOLS": return wrap(args, intoRows: false)
    case "TOCOL": return flatten(args, column: true)
    case "TOROW": return flatten(args, column: false)
    case "TEXTSPLIT": return textSplit(args)
    case "RANDARRAY": return randomArray(args)
    case "TRANSPOSE":
      guard args.count == 1 else { return Self.fail(.value) }
      switch source(args[0]) {
      case .failed(let e): return Self.fail(e)
      case .value(let array): return array.transposed
      }
    default: return nil
    }
  }

  // MARK: - LET(name1, value1, [name2, value2, ...], calculation)

  /// A LET name as it is compared: without the `_xlpm.` files save it with, any case.
  static func letName(_ raw: String) -> String? {
    var name = raw.lowercased()
    if name.hasPrefix("_xlpm.") { name.removeFirst("_xlpm.".count) }
    return name.isEmpty ? nil : name
  }

  static func isLet(_ name: String) -> Bool { plainFunctionName(name) == "LET" }

  /// The calculation with each name replaced by its value. A value that is one plain value,
  /// not a reference, is worked out once here rather than at every use.
  func letCalculation(_ args: [FormulaExpr]) -> FormulaExpr {
    guard args.count >= 3, args.count % 2 == 1 else { return .error(.value) }
    var bindings: [(name: String, value: FormulaExpr)] = []
    for i in stride(from: 0, to: args.count - 1, by: 2) {
      guard case .namedRange(let raw) = args[i], let name = Self.letName(raw),
        !bindings.contains(where: { $0.name == name })
      else { return .error(.value) }
      var value = Self.substitute(args[i + 1], bindings)
      if Self.canWorkOutOnce(value) {
        let values = arrayEvaluate(value, cache: nil)
        if values.count == 1, let literal = Self.literal(values[0]) { value = literal }
      }
      bindings.append((name, value))
    }
    return Self.substitute(args[args.count - 1], bindings)
  }

  /// False for references, which other functions read as places (ROW, OFFSET, a range in
  /// SUMIF), and for arrays, which have no literal form.
  private static func canWorkOutOnce(_ expr: FormulaExpr) -> Bool {
    switch expr {
    case .cellRef, .range, .namedRange, .missing: return false
    case .call(let name, _):
      // A LAMBDA is kept to be called, not worked out (alone it is #CALC!).
      if FormulaParser.isLambda(expr) { return false }
      let plain = plainFunctionName(name)
      return !["INDEX", "OFFSET", "INDIRECT", "CHOOSE", "IF", "IFS", "SWITCH", "XLOOKUP"]
        .contains(plain) && !spills(expr)
    case .unary, .binary: return !spills(expr)
    default: return true
    }
  }

  static func literal(_ value: CellValue) -> FormulaExpr? {
    switch value {
    case .number(let n): return .number(n)
    case .string(let s): return .string(s)
    case .bool(let b): return .boolean(b)
    case .error(let e): return .error(e)
    case .blank: return nil
    }
  }

  /// `expr` with each bound name replaced. A LET inside binds its own names from where it
  /// names them, hiding an outer name of the same spelling.
  static func substitute(_ expr: FormulaExpr, _ bindings: [(name: String, value: FormulaExpr)])
    -> FormulaExpr
  {
    guard !bindings.isEmpty else { return expr }
    switch expr {
    case .namedRange(let raw):
      guard let name = letName(raw), let hit = bindings.last(where: { $0.name == name }) else {
        return expr
      }
      return hit.value
    case .unary(let op, let inner):
      return .unary(op, substitute(inner, bindings))
    case .binary(let op, let lhs, let rhs):
      return .binary(op, substitute(lhs, bindings), substitute(rhs, bindings))
    case .call(let name, let args) where plainFunctionName(name) == "LAMBDA":
      // A LAMBDA's own parameters hide outer names of the same spelling inside its body.
      var inner = bindings
      for arg in args.dropLast() {
        if case .namedRange(let raw) = arg, let name = letName(raw) {
          inner.removeAll { $0.name == name }
        }
      }
      guard let body = args.last else { return expr }
      return .call(name, args.dropLast() + [substitute(body, inner)])
    case .call(let name, let args):
      // `LET(f,LAMBDA(x,x+1),f(9))`: a name given a LAMBDA, called like a function.
      if let key = letName(name), let bound = bindings.last(where: { $0.name == key }),
        FormulaParser.isLambda(bound.value)
      {
        return .call(
          FormulaExpr.lambdaCallFunction, [bound.value] + args.map { substitute($0, bindings) })
      }
      guard isLet(name) else { return .call(name, args.map { substitute($0, bindings) }) }
      var inner = bindings
      var out: [FormulaExpr] = []
      for (i, arg) in args.enumerated() {
        if i % 2 == 0, i < args.count - 1, case .namedRange(let raw) = arg,
          let name = letName(raw)
        {
          out.append(arg)
          inner.removeAll { $0.name == name }
        } else {
          out.append(substitute(arg, inner))
        }
      }
      return .call(name, out)
    default:
      return expr
    }
  }

  // MARK: - Helpers

  /// An argument's value, or the error it gives.
  enum Outcome<Value> {
    case value(Value)
    case failed(FormulaError)
  }

  private func given(_ args: [FormulaExpr], _ index: Int) -> FormulaExpr? {
    guard index < args.count else { return nil }
    if case .missing = args[index] { return nil }
    return args[index]
  }

  /// A whole number argument, truncated toward zero; nil when left out, an error when not a
  /// number.
  private func count(_ args: [FormulaExpr], _ index: Int) -> Outcome<Int?> {
    guard let expr = given(args, index) else { return .value(nil) }
    let value = evaluate(expr)
    if case .error(let e) = value { return .failed(e) }
    if case .blank = value { return .value(nil) }
    guard let n = value.asNumber, n.isFinite, abs(n) < 1e9 else { return .failed(.value) }
    return .value(Int(n.rounded(.towardZero)))
  }

  private func flagArgument(_ args: [FormulaExpr], _ index: Int, default fallback: Bool)
    -> Outcome<Bool>
  {
    guard let expr = given(args, index) else { return .value(fallback) }
    switch evaluate(expr) {
    case .error(let e): return .failed(e)
    case .blank: return .value(fallback)
    case .bool(let b): return .value(b)
    case .number(let n): return .value(n != 0)
    case .string(let s):
      if s.caseInsensitiveCompare("TRUE") == .orderedSame { return .value(true) }
      if s.caseInsensitiveCompare("FALSE") == .orderedSame { return .value(false) }
      return .failed(.value)
    }
  }

  private func source(_ expr: FormulaExpr) -> Outcome<ArrayResult> {
    let array = evaluateArray(expr)
    if array.isSingle, case .error(let e) = array.first { return .failed(e) }
    return .value(array)
  }

  static func fail(_ error: FormulaError) -> ArrayResult { ArrayResult(.error(error)) }

  /// The rows `rows` and columns `cols` of `array`, in that order.
  private static func pick(_ array: ArrayResult, rows: [Int], cols: [Int]) -> ArrayResult {
    var values: [CellValue] = []
    values.reserveCapacity(rows.count * cols.count)
    for r in rows {
      for c in cols { values.append(array.value(row: r, col: c)) }
    }
    return ArrayResult(rows: rows.count, cols: cols.count, values: values)
  }

  // MARK: - VSTACK and HSTACK

  /// One array after another, down or across. Shorter ones are filled out with #N/A.
  private func stack(_ args: [FormulaExpr], vertically: Bool) -> ArrayResult {
    guard !args.isEmpty else { return Self.fail(.value) }
    var arrays: [ArrayResult] = []
    for arg in args {
      // A left-out argument is an error, not an empty array.
      guard given(args, arrays.count) != nil else { return Self.fail(.value) }
      let array = evaluateArray(arg)
      arrays.append(vertically ? array : array.transposed)
    }
    let width = arrays.map(\.cols).max() ?? 0
    let height = arrays.reduce(0) { $0 + $1.rows }
    guard InputBounds.materializedCount(rows: height, cols: width) != nil else {
      return Self.fail(.value)
    }
    var values: [CellValue] = []
    values.reserveCapacity(height * width)
    for array in arrays {
      for r in 0..<array.rows {
        for c in 0..<width {
          values.append(c < array.cols ? array.value(row: r, col: c) : .error(.na))
        }
      }
    }
    let result = ArrayResult(rows: height, cols: width, values: values)
    return vertically ? result : result.transposed
  }

  // MARK: - TAKE and DROP

  /// TAKE(array, rows, [columns]) and DROP(array, rows, [columns]). A negative count counts
  /// from the end.
  private func takeOrDrop(_ args: [FormulaExpr], take: Bool) -> ArrayResult {
    guard (2...3).contains(args.count) else { return Self.fail(.value) }
    let array: ArrayResult
    switch source(args[0]) {
    case .failed(let e): return Self.fail(e)
    case .value(let a): array = a
    }
    let rowCount: Int?
    let colCount: Int?
    switch (count(args, 1), count(args, 2)) {
    case (.failed(let e), _), (_, .failed(let e)): return Self.fail(e)
    case (.value(let r), .value(let c)):
      rowCount = r
      colCount = c
    }
    func indices(_ total: Int, _ n: Int?) -> [Int] {
      guard let n else { return Array(0..<total) }
      let k = min(abs(n), total)
      if take { return n >= 0 ? Array(0..<k) : Array((total - k)..<total) }
      return n >= 0 ? Array(k..<total) : Array(0..<(total - k))
    }
    // Taking none is #VALUE!, as Excel 16.115 gives it; dropping everything is #CALC!.
    if take, rowCount == 0 || colCount == 0 { return Self.fail(.value) }
    let rows = indices(array.rows, rowCount)
    let cols = indices(array.cols, colCount)
    guard !rows.isEmpty, !cols.isEmpty else { return Self.fail(.calc) }
    return Self.pick(array, rows: rows, cols: cols)
  }

  // MARK: - CHOOSECOLS and CHOOSEROWS

  /// CHOOSECOLS(array, col_num1, ...): the columns by number, in the order given. A negative
  /// number counts from the end; 0 or past the end is #VALUE!.
  private func choose(_ args: [FormulaExpr], columns: Bool) -> ArrayResult {
    guard args.count >= 2 else { return Self.fail(.value) }
    let array: ArrayResult
    switch source(args[0]) {
    case .failed(let e): return Self.fail(e)
    case .value(let a): array = a
    }
    let total = columns ? array.cols : array.rows
    var chosen: [Int] = []
    for arg in args.dropFirst() {
      if case .missing = arg { return Self.fail(.value) }
      for value in evaluateArray(arg).values {
        if case .error(let e) = value { return Self.fail(e) }
        guard let n = value.asNumber, n.isFinite else { return Self.fail(.value) }
        let k = Int(n.rounded(.towardZero))
        guard k != 0, abs(k) <= total else { return Self.fail(.value) }
        chosen.append(k > 0 ? k - 1 : total + k)
      }
    }
    return columns
      ? Self.pick(array, rows: Array(0..<array.rows), cols: chosen)
      : Self.pick(array, rows: chosen, cols: Array(0..<array.cols))
  }

  // MARK: - WRAPROWS and WRAPCOLS

  /// WRAPROWS(vector, wrap_count, [pad_with]): a row or column cut into rows of `wrap_count`
  /// values; the last is filled out with `pad_with`, #N/A when left out.
  private func wrap(_ args: [FormulaExpr], intoRows: Bool) -> ArrayResult {
    guard (2...3).contains(args.count) else { return Self.fail(.value) }
    let vector: ArrayResult
    switch source(args[0]) {
    case .failed(let e): return Self.fail(e)
    case .value(let a): vector = a
    }
    guard vector.rows == 1 || vector.cols == 1 else { return Self.fail(.value) }
    let size: Int
    switch count(args, 1) {
    case .failed(let e): return Self.fail(e)
    case .value(nil): return Self.fail(.value)
    case .value(let n?): size = n
    }
    guard size >= 1 else { return Self.fail(.num) }
    let pad = given(args, 2).map { evaluate($0) } ?? .error(.na)
    let items = vector.values
    let lines = (items.count + size - 1) / size
    guard InputBounds.materializedCount(rows: lines, cols: size) != nil else {
      return Self.fail(.value)
    }
    var values: [CellValue] = []
    values.reserveCapacity(lines * size)
    for i in 0..<(lines * size) { values.append(i < items.count ? items[i] : pad) }
    let rows = ArrayResult(rows: lines, cols: size, values: values)
    return intoRows ? rows : rows.transposed
  }

  // MARK: - TOCOL and TOROW

  /// TOCOL(array, [ignore], [scan_by_column]): every value in one column, row by row unless
  /// `scan_by_column`. `ignore` 1 leaves out blanks, 2 errors, 3 both.
  private func flatten(_ args: [FormulaExpr], column: Bool) -> ArrayResult {
    guard (1...3).contains(args.count) else { return Self.fail(.value) }
    let array: ArrayResult
    switch source(args[0]) {
    case .failed(let e): return Self.fail(e)
    case .value(let a): array = a
    }
    let ignore: Int
    switch count(args, 1) {
    case .failed(let e): return Self.fail(e)
    case .value(let n): ignore = n ?? 0
    }
    guard (0...3).contains(ignore) else { return Self.fail(.value) }
    let byColumn: Bool
    switch flagArgument(args, 2, default: false) {
    case .failed(let e): return Self.fail(e)
    case .value(let b): byColumn = b
    }
    let ordered = byColumn ? array.transposed.values : array.values
    let kept = ordered.filter { value in
      switch value {
      case .blank: return ignore & 1 == 0
      case .error: return ignore & 2 == 0
      default: return true
      }
    }
    guard !kept.isEmpty else { return Self.fail(.calc) }
    return column
      ? ArrayResult(rows: kept.count, cols: 1, values: kept)
      : ArrayResult(rows: 1, cols: kept.count, values: kept)
  }

  // MARK: - TEXTSPLIT

  /// TEXTSPLIT(text, col_delimiter, [row_delimiter], [ignore_empty], [match_mode], [pad_with]).
  /// A delimiter may be a range of several. Short rows are filled out with `pad_with`,
  /// #N/A when left out. Given a range, each cell gives the first piece of its own text.
  private func textSplit(_ args: [FormulaExpr]) -> ArrayResult {
    guard (2...6).contains(args.count) else { return Self.fail(.value) }
    let text: ArrayResult
    switch source(args[0]) {
    case .failed(let e): return Self.fail(e)
    case .value(let a): text = a
    }
    func delimiters(_ index: Int) -> Outcome<[String]> {
      guard let expr = given(args, index) else { return .value([]) }
      var out: [String] = []
      for value in evaluateArray(expr).values {
        if case .error(let e) = value { return .failed(e) }
        out.append(value.asString)
      }
      return .value(out)
    }
    let columnDelimiters: [String]
    let rowDelimiters: [String]
    switch (delimiters(1), delimiters(2)) {
    case (.failed(let e), _), (_, .failed(let e)): return Self.fail(e)
    case (.value(let c), .value(let r)):
      columnDelimiters = c
      rowDelimiters = r
    }
    guard !(columnDelimiters + rowDelimiters).isEmpty,
      !(columnDelimiters + rowDelimiters).contains(where: \.isEmpty)
    else { return Self.fail(.value) }
    let ignoreEmpty: Bool
    switch flagArgument(args, 3, default: false) {
    case .failed(let e): return Self.fail(e)
    case .value(let b): ignoreEmpty = b
    }
    let mode: Int
    switch count(args, 4) {
    case .failed(let e): return Self.fail(e)
    case .value(let n): mode = n ?? 0
    }
    guard mode == 0 || mode == 1 else { return Self.fail(.value) }
    let options: String.CompareOptions = mode == 1 ? [.caseInsensitive] : []
    let pad = given(args, 5).map { evaluate($0) } ?? .error(.na)

    func split(_ string: String, by separators: [String]) -> [String] {
      guard !separators.isEmpty else { return [string] }
      var pieces: [String] = []
      var rest = string[...]
      while true {
        // The delimiter found first; at the same place, the longest.
        var best: Range<Substring.Index>?
        for separator in separators {
          guard let found = rest.range(of: separator, options: options) else { continue }
          if let current = best {
            if found.lowerBound < current.lowerBound
              || (found.lowerBound == current.lowerBound && found.upperBound > current.upperBound)
            {
              best = found
            }
          } else {
            best = found
          }
        }
        guard let cut = best else {
          pieces.append(String(rest))
          break
        }
        pieces.append(String(rest[..<cut.lowerBound]))
        rest = rest[cut.upperBound...]
      }
      return ignoreEmpty ? pieces.filter { !$0.isEmpty } : pieces
    }

    func grid(_ string: String) -> [[String]] {
      split(string, by: rowDelimiters).map { split($0, by: columnDelimiters) }
        .filter { !ignoreEmpty || !$0.isEmpty }
    }

    if !text.isSingle {
      // Each cell keeps only its first piece, as other apps give it.
      let values = text.values.map { value -> CellValue in
        if case .error = value { return value }
        return grid(value.asString).first?.first.map(CellValue.string) ?? pad
      }
      return ArrayResult(rows: text.rows, cols: text.cols, values: values)
    }
    let rows = grid(text.first.asString)
    guard !rows.isEmpty else { return Self.fail(.calc) }
    let width = rows.map(\.count).max() ?? 0
    guard width > 0 else { return Self.fail(.calc) }
    guard InputBounds.materializedCount(rows: rows.count, cols: width) != nil else {
      return Self.fail(.value)
    }
    var values: [CellValue] = []
    values.reserveCapacity(rows.count * width)
    for row in rows {
      for c in 0..<width { values.append(c < row.count ? .string(row[c]) : pad) }
    }
    return ArrayResult(rows: rows.count, cols: width, values: values)
  }

  // MARK: - RANDARRAY([rows], [columns], [min], [max], [whole_number])

  private func randomArray(_ args: [FormulaExpr]) -> ArrayResult {
    guard args.count <= 5 else { return Self.fail(.value) }
    func number(_ index: Int, _ fallback: Double) -> Outcome<Double> {
      guard let expr = given(args, index) else { return .value(fallback) }
      let value = evaluate(expr)
      if case .error(let e) = value { return .failed(e) }
      if case .blank = value { return .value(fallback) }
      guard let n = value.asNumber, n.isFinite else { return .failed(.value) }
      return .value(n)
    }
    var numbers: [Double] = []
    for (index, fallback) in [(0, 1.0), (1, 1.0), (2, 0.0), (3, 1.0)] {
      switch number(index, fallback) {
      case .failed(let e): return Self.fail(e)
      case .value(let n): numbers.append(n)
      }
    }
    let whole: Bool
    switch flagArgument(args, 4, default: false) {
    case .failed(let e): return Self.fail(e)
    case .value(let b): whole = b
    }
    let rows = Int(numbers[0].rounded(.towardZero))
    let cols = Int(numbers[1].rounded(.towardZero))
    let low = numbers[2]
    let high = numbers[3]
    guard rows >= 0, cols >= 0 else { return Self.fail(.value) }
    guard rows > 0, cols > 0 else { return Self.fail(.calc) }
    guard low <= high else { return Self.fail(.value) }
    guard InputBounds.materializedCount(rows: rows, cols: cols) != nil else {
      return Self.fail(.value)
    }
    if whole {
      guard low == low.rounded(), high == high.rounded(), abs(low) < 1e15, abs(high) < 1e15
      else { return Self.fail(.value) }
      let range = Int(low)...Int(high)
      let values = (0..<(rows * cols)).map { _ in CellValue.number(Double(Int.random(in: range))) }
      return ArrayResult(rows: rows, cols: cols, values: values)
    }
    let values = (0..<(rows * cols)).map { _ -> CellValue in
      .number(low == high ? low : Double.random(in: low..<high))
    }
    return ArrayResult(rows: rows, cols: cols, values: values)
  }
}
