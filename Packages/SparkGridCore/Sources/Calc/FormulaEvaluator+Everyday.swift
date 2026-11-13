import Formula
import Foundation
import Functions
import GridCore
import Model
import NumberFormat

extension FormulaEvaluator {
  fileprivate struct ValueMatrix {
    public var rows: Int
    public var cols: Int
    public var values: [CellValue]
  }

  fileprivate struct RangeAnchor {
    public var sheet: String?
    public var row: Int
    public var col: Int
    public var rows: Int
    public var cols: Int
  }

  fileprivate struct LookupMemoKey: Hashable {
    public var sheet: String?
    public var row: Int
    public var col: Int
  }

  /// Excel-style aggregates skip #VALUE! / #REF! rows instead of failing the whole formula.
  fileprivate func lookupForAggregate(_ ref: FormulaRef, memo: inout [LookupMemoKey: CellValue])
    -> CellValue
  {
    let key = LookupMemoKey(sheet: ref.sheet, row: ref.row, col: ref.col)
    if let cached = memo[key] { return cached }
    let value = lookup(ref)
    memo[key] = value
    return value
  }

  fileprivate func aggregateRowError(_ value: CellValue) -> Bool {
    if case .error = value { return true }
    return false
  }

  fileprivate enum CriteriaOp {
    case eq, ne, lt, le, gt, ge
  }

  fileprivate struct CriteriaTest {
    public var op: CriteriaOp
    public var number: Double?
    public var text: String
    public var wildcard: Bool
    public var blank: Bool
  }

  public func evalSUMIF(_ args: [FormulaExpr]) -> CellValue {
    conditionalAggregate(args, kind: .sum)
  }

  public func evalAVERAGEIF(_ args: [FormulaExpr]) -> CellValue {
    conditionalAggregate(args, kind: .average)
  }

  public func evalCOUNTIF(_ args: [FormulaExpr]) -> CellValue {
    guard args.count == 2 else { return .error(.value) }
    guard let anchor = rangeAnchor(args[0]) else { return .error(.value) }
    let criterion = evaluate(args[1])
    if case .error = criterion { return criterion }
    let test = criteriaTest(from: criterion)
    var memo: [LookupMemoKey: CellValue] = [:]
    let values = snapshotValues(anchor: anchor, memo: &memo)
    if let cache = aggregateRangeCache,
      criteriaSupportsIndexLookup(test),
      let lookupKey = lookupKeyForCriterion(criterion, test: test)
    {
      let rangeKey = aggregateRangeKey(for: anchor)
      let count = cache.countForCriteria(
        rangeKeys: [rangeKey],
        criteriaKeys: [lookupKey],
        supplyColumns: { [values] }
      )
      return .number(Double(count))
    }
    var count = 0
    for value in values {
      if aggregateRowError(value) { continue }
      if criteriaMatch(value, test) { count += 1 }
    }
    return .number(Double(count))
  }

  public func evalSUMIFS(_ args: [FormulaExpr]) -> CellValue {
    multiCriteriaAggregate(args, kind: .sum)
  }

  public func evalAVERAGEIFS(_ args: [FormulaExpr]) -> CellValue {
    multiCriteriaAggregate(args, kind: .average)
  }

  public func evalCOUNTIFS(_ args: [FormulaExpr]) -> CellValue {
    guard args.count >= 2, args.count.isMultiple(of: 2) else { return .error(.value) }
    guard let first = rangeAnchor(args[0]) else { return .error(.value) }
    var tests: [(RangeAnchor, CriteriaTest, CellValue)] = []
    var index = 0
    while index < args.count {
      guard let anchor = rangeAnchor(args[index]) else { return .error(.value) }
      if anchor.rows != first.rows || anchor.cols != first.cols { return .error(.value) }
      let criterion = evaluate(args[index + 1])
      if case .error = criterion { return criterion }
      tests.append((anchor, criteriaTest(from: criterion), criterion))
      index += 2
    }
    var memo: [LookupMemoKey: CellValue] = [:]
    if let cache = aggregateRangeCache,
      let lookupKeys = aggregateLookupKeys(
        criteria: tests.map(\.2),
        tests: tests.map(\.1)
      )
    {
      let rangeKeys = tests.map { aggregateRangeKey(for: $0.0) }
      let matches = cache.countForCriteria(
        rangeKeys: rangeKeys,
        criteriaKeys: lookupKeys,
        supplyColumns: {
          var snapMemo: [LookupMemoKey: CellValue] = [:]
          return tests.map { snapshotValues(anchor: $0.0, memo: &snapMemo) }
        }
      )
      recalcProfile?.countifsHistogramLookups += 1
      return .number(Double(matches))
    }
    let rangeSnapshots = tests.map { snapshotValues(anchor: $0.0, memo: &memo) }
    let count = rangeSnapshots[0].count
    var matches = 0
    recalcProfile?.countifsRowScanCells += count
    for offset in 0..<count {
      var matched = true
      for (rangeIndex, test) in tests.map(\.1).enumerated() {
        let value = rangeSnapshots[rangeIndex][offset]
        if aggregateRowError(value) {
          matched = false
          break
        }
        if !criteriaMatch(value, test) {
          matched = false
          break
        }
      }
      if matched { matches += 1 }
    }
    return .number(Double(matches))
  }

  public func evalCOUNTBLANK(_ args: [FormulaExpr]) -> CellValue {
    guard args.count == 1, let anchor = rangeAnchor(args[0]) else { return .error(.value) }
    var count = 0
    for row in 0..<anchor.rows {
      for col in 0..<anchor.cols {
        let value = lookup(cellRef(anchor, row: row, col: col))
        if isBlankForCount(value) { count += 1 }
      }
    }
    return .number(Double(count))
  }

  public func evalSUMPRODUCT(_ args: [FormulaExpr]) -> CellValue {
    guard !args.isEmpty else { return .error(.value) }
    let booleanShaped = looksLikeBooleanSumProduct(args)
    if let fast = tryEvalBooleanSumProduct(args) {
      recalcProfile?.sumproductBooleanHits += 1
      return fast
    }
    if booleanShaped {
      recalcProfile?.sumproductBooleanFallbacks += 1
    }
    if args.count == 1 {
      let cacheBox = FormulaEvaluator.ArrayEvalCacheBox()
      let values = arrayEvaluate(args[0], cache: cacheBox)
      var total = 0.0
      for value in values {
        if case .error(let error) = value { return .error(error) }
        total += sumProductCoefficient(value)
      }
      return .number(total)
    }
    var matrices: [ValueMatrix] = []
    for arg in args {
      guard let matrix = valueMatrix(arg) else { return .error(.value) }
      matrices.append(matrix)
    }
    let rows = matrices[0].rows
    let cols = matrices[0].cols
    guard matrices.allSatisfy({ $0.rows == rows && $0.cols == cols }) else { return .error(.value) }
    var total = 0.0
    let count = rows * cols
    for index in 0..<count {
      var product = 1.0
      for matrix in matrices {
        let value = matrix.values[index]
        if case .error(let error) = value { return .error(error) }
        product *= sumProductCoefficient(value)
      }
      total += product
    }
    return .number(total)
  }

  public func evalIFNA(_ args: [FormulaExpr]) -> CellValue {
    guard args.count == 2 else { return .error(.value) }
    let value = evaluate(args[0])
    if case .error(.na) = value {
      return evaluate(args[1])
    }
    return value
  }

  public func evalIFS(_ args: [FormulaExpr]) -> CellValue {
    guard args.count >= 2, args.count.isMultiple(of: 2) else { return .error(.value) }
    var index = 0
    while index < args.count {
      let condition = evaluate(args[index])
      if case .error = condition { return condition }
      guard let flag = condition.asBool else { return .error(.value) }
      if flag { return evaluate(args[index + 1]) }
      index += 2
    }
    return .error(.na)
  }

  public func evalNOT(_ args: [FormulaExpr]) -> CellValue {
    guard args.count == 1 else { return .error(.value) }
    let value = evaluate(args[0])
    if case .error = value { return value }
    guard let flag = value.asBool else { return .error(.value) }
    return .bool(!flag)
  }

  public func evalTextCase(_ args: [FormulaExpr], uppercased: Bool) -> CellValue {
    guard args.count == 1 else { return .error(.value) }
    let value = evaluate(args[0])
    if case .error = value { return value }
    let text = value.asString
    return .string(uppercased ? text.uppercased() : text.lowercased())
  }

  public func evalMID(_ args: [FormulaExpr]) -> CellValue {
    guard args.count == 3 else { return .error(.value) }
    let text = evaluate(args[0])
    let start = evaluate(args[1])
    let count = evaluate(args[2])
    if case .error = text { return text }
    if case .error = start { return start }
    if case .error = count { return count }
    guard let startNumber = start.asNumber, let countNumber = count.asNumber else {
      return .error(.value)
    }
    if startNumber < 1 || countNumber < 0 { return .error(.value) }
    let startIndex = Int(startNumber.rounded(.towardZero))
    let length = Int(countNumber.rounded(.towardZero))
    let chars = Array(text.asString)
    let offset = startIndex - 1
    if offset >= chars.count || length == 0 { return .string("") }
    let end = min(chars.count, offset + length)
    return .string(String(chars[offset..<end]))
  }

  public func evalSUBSTITUTE(_ args: [FormulaExpr]) -> CellValue {
    guard args.count == 3 || args.count == 4 else { return .error(.value) }
    let text = evaluate(args[0])
    let old = evaluate(args[1])
    let new = evaluate(args[2])
    if case .error = text { return text }
    if case .error = old { return old }
    if case .error = new { return new }
    let source = text.asString
    let needle = old.asString
    let replacement = new.asString
    if needle.isEmpty { return .string(source) }

    if args.count == 4 {
      let instance = evaluate(args[3])
      if case .error = instance { return instance }
      guard let instanceNumber = instance.asNumber else { return .error(.value) }
      let occurrence = Int(instanceNumber.rounded(.towardZero))
      if occurrence < 1 { return .error(.value) }
      return .string(
        replaceOccurrence(in: source, needle: needle, with: replacement, occurrence: occurrence))
    }
    return .string(source.replacingOccurrences(of: needle, with: replacement))
  }

  public func evalTEXTJOIN(_ args: [FormulaExpr]) -> CellValue {
    guard args.count >= 3 else { return .error(.value) }
    let delimiter = evaluate(args[0])
    if case .error = delimiter { return delimiter }
    let ignore = evaluate(args[1])
    if case .error = ignore { return ignore }
    guard let ignoreEmpty = ignore.asBool else { return .error(.value) }
    var parts: [String] = []
    for value in expandedValues(Array(args.dropFirst(2))) {
      if case .error(let error) = value { return .error(error) }
      if ignoreEmpty && isBlankForCount(value) { continue }
      parts.append(value.asString)
    }
    return .string(parts.joined(separator: delimiter.asString))
  }

  public func evalDirectionalRound(_ args: [FormulaExpr], mode: NSDecimalNumber.RoundingMode)
    -> CellValue
  {
    guard args.count == 1 || args.count == 2 else { return .error(.value) }
    let value = evaluate(args[0])
    if case .error = value { return value }
    guard let number = value.asNumber else { return .error(.value) }
    var places = 0
    if args.count == 2 {
      let digits = evaluate(args[1])
      if case .error = digits { return digits }
      guard let digitNumber = digits.asNumber else { return .error(.value) }
      places = Int(digitNumber.rounded())
    }
    return .number(excelRound(number, places: places, mode: mode))
  }

  // MARK: - Conditional aggregates

  fileprivate enum AggregateKind {
    case sum
    case average
  }

  private func conditionalAggregate(_ args: [FormulaExpr], kind: AggregateKind) -> CellValue {
    guard args.count == 2 || args.count == 3 else { return .error(.value) }
    guard let criteria = rangeAnchor(args[0]) else { return .error(.value) }
    let criterion = evaluate(args[1])
    if case .error = criterion { return criterion }
    let test = criteriaTest(from: criterion)
    let sumAnchor: RangeAnchor
    if args.count == 3 {
      guard let sum = rangeAnchor(args[2]) else { return .error(.value) }
      sumAnchor = RangeAnchor(
        sheet: sum.sheet, row: sum.row, col: sum.col, rows: criteria.rows, cols: criteria.cols)
    } else {
      sumAnchor = criteria
    }
    return reduceMatches(
      criteria: criteria, test: test, criterion: criterion, values: sumAnchor, kind: kind)
  }

  /// MAXIFS and MINIFS: the largest or smallest number whose rows meet every criterion. 0 when none do.
  public func evalExtremeIFS(_ args: [FormulaExpr], pickMin: Bool) -> CellValue {
    guard args.count >= 3, (args.count - 1).isMultiple(of: 2) else { return .error(.value) }
    guard let target = rangeAnchor(args[0]) else { return .error(.value) }
    var tests: [(RangeAnchor, CriteriaTest)] = []
    var index = 1
    while index < args.count {
      guard let anchor = rangeAnchor(args[index]) else { return .error(.value) }
      if anchor.rows != target.rows || anchor.cols != target.cols { return .error(.value) }
      let criterion = evaluate(args[index + 1])
      if case .error = criterion { return criterion }
      tests.append((anchor, criteriaTest(from: criterion)))
      index += 2
    }
    var memo: [LookupMemoKey: CellValue] = [:]
    let values = snapshotValues(anchor: target, memo: &memo)
    let columns = tests.map { snapshotValues(anchor: $0.0, memo: &memo) }
    var best: Double?
    for offset in 0..<values.count {
      var matched = true
      for (testIndex, test) in tests.enumerated() {
        let value = columns[testIndex][offset]
        if aggregateRowError(value) || !criteriaMatch(value, test.1) {
          matched = false
          break
        }
      }
      guard matched, case .number(let n) = values[offset] else { continue }
      if let current = best {
        best = pickMin ? min(current, n) : max(current, n)
      } else {
        best = n
      }
    }
    return .number(best ?? 0)
  }

  private func multiCriteriaAggregate(_ args: [FormulaExpr], kind: AggregateKind) -> CellValue {
    guard args.count >= 3, (args.count - 1).isMultiple(of: 2) else { return .error(.value) }
    guard let sum = rangeAnchor(args[0]) else { return .error(.value) }
    var tests: [(RangeAnchor, CriteriaTest, CellValue)] = []
    var index = 1
    while index < args.count {
      guard let anchor = rangeAnchor(args[index]) else { return .error(.value) }
      if anchor.rows != sum.rows || anchor.cols != sum.cols { return .error(.value) }
      let criterion = evaluate(args[index + 1])
      if case .error = criterion { return criterion }
      tests.append((anchor, criteriaTest(from: criterion), criterion))
      index += 2
    }
    var memo: [LookupMemoKey: CellValue] = [:]
    if kind == .average {
      return averageOfMatchingRows(sum: sum, tests: tests, memo: &memo)
    }
    if let cache = aggregateRangeCache {
      if let lookupKeys = aggregateLookupKeys(criteria: tests.map(\.2), tests: tests.map(\.1)) {
        let criteriaKeys = tests.map { aggregateRangeKey(for: $0.0) }
        let sumKey = aggregateRangeKey(for: sum)
        let bucket = cache.sumForCriteria(
          criteriaRangeKeys: criteriaKeys,
          sumRangeKey: sumKey,
          criteriaKeys: lookupKeys,
          supplyColumns: {
            var snapMemo: [LookupMemoKey: CellValue] = [:]
            let sumValues = snapshotValues(anchor: sum, memo: &snapMemo)
            let criteriaColumns = tests.map { snapshotValues(anchor: $0.0, memo: &snapMemo) }
            return (criteriaColumns, sumValues)
          }
        )
        switch kind {
        case .sum:
          return .number(bucket.sum)
        case .average:
          guard bucket.count > 0 else { return .error(.divZero) }
          return .number(bucket.sum / Double(bucket.count))
        }
      }
      if tests.allSatisfy({ !$0.1.wildcard }) {
        let sumValues = snapshotValues(anchor: sum, memo: &memo)
        let rangeSnapshots = tests.map { snapshotValues(anchor: $0.0, memo: &memo) }
        let bucket = cache.sumByRowFilter(sumColumn: sumValues) { row in
          for (rangeIndex, test) in tests.map(\.1).enumerated() {
            let value = rangeSnapshots[rangeIndex][row]
            if aggregateRowError(value) { return false }
            if !criteriaMatch(value, test) { return false }
          }
          return true
        }
        switch kind {
        case .sum:
          return .number(bucket.sum)
        case .average:
          guard bucket.count > 0 else { return .error(.divZero) }
          return .number(bucket.sum / Double(bucket.count))
        }
      }
    }
    let sumValues = snapshotValues(anchor: sum, memo: &memo)
    let rangeSnapshots = tests.map { snapshotValues(anchor: $0.0, memo: &memo) }
    let cellCount = sumValues.count
    var total = 0.0
    var matchCount = 0
    for offset in 0..<cellCount {
      var matched = true
      for (rangeIndex, test) in tests.map(\.1).enumerated() {
        let value = rangeSnapshots[rangeIndex][offset]
        if aggregateRowError(value) {
          matched = false
          break
        }
        if !criteriaMatch(value, test) {
          matched = false
          break
        }
      }
      guard matched else { continue }
      let value = sumValues[offset]
      if aggregateRowError(value) { continue }
      guard let number = numericAddend(value) else { continue }
      total += number
      matchCount += 1
    }
    switch kind {
    case .sum:
      return .number(total)
    case .average:
      guard matchCount > 0 else { return .error(.divZero) }
      return .number(total / Double(matchCount))
    }
  }

  /// A criteria match whose averaged cell is an error is that error. `SUMIFS` still skips it.
  private func averageOfMatchingRows(
    sum: RangeAnchor,
    tests: [(RangeAnchor, CriteriaTest, CellValue)],
    memo: inout [LookupMemoKey: CellValue]
  ) -> CellValue {
    let sumValues = snapshotValues(anchor: sum, memo: &memo)
    let rangeSnapshots = tests.map { snapshotValues(anchor: $0.0, memo: &memo) }
    var total = 0.0
    var matchCount = 0
    for offset in 0..<sumValues.count {
      var matched = true
      for (rangeIndex, test) in tests.map(\.1).enumerated() {
        guard rangeSnapshots.indices.contains(rangeIndex),
          rangeSnapshots[rangeIndex].indices.contains(offset)
        else {
          matched = false
          break
        }
        let value = rangeSnapshots[rangeIndex][offset]
        if aggregateRowError(value) || !criteriaMatch(value, test) {
          matched = false
          break
        }
      }
      guard matched else { continue }
      let value = sumValues[offset]
      if case .error(let error) = value { return .error(error) }
      guard let number = numericAddend(value) else { continue }
      total += number
      matchCount += 1
    }
    guard matchCount > 0 else { return .error(.divZero) }
    return .number(total / Double(matchCount))
  }

  private func reduceMatches(
    criteria: RangeAnchor,
    test: CriteriaTest,
    criterion: CellValue,
    values: RangeAnchor,
    kind: AggregateKind
  ) -> CellValue {
    var memo: [LookupMemoKey: CellValue] = [:]
    let criteriaValues = snapshotValues(anchor: criteria, memo: &memo)
    let sumValues = snapshotValues(anchor: values, memo: &memo)
    if let cache = aggregateRangeCache,
      criteriaSupportsIndexLookup(test),
      let lookupKey = lookupKeyForCriterion(criterion, test: test)
    {
      let criteriaKey = aggregateRangeKey(for: criteria)
      let sumKey = aggregateRangeKey(for: values)
      let bucket = cache.sumForCriteria(
        criteriaRangeKeys: [criteriaKey],
        sumRangeKey: sumKey,
        criteriaKeys: [lookupKey],
        supplyColumns: { ([criteriaValues], sumValues) }
      )
      switch kind {
      case .sum:
        return .number(bucket.sum)
      case .average:
        guard bucket.count > 0 else { return .error(.divZero) }
        return .number(bucket.sum / Double(bucket.count))
      }
    }
    var total = 0.0
    var count = 0
    for offset in 0..<criteriaValues.count {
      let candidate = criteriaValues[offset]
      if aggregateRowError(candidate) { continue }
      guard criteriaMatch(candidate, test) else { continue }
      let value = sumValues[offset]
      if aggregateRowError(value) { continue }
      guard let number = numericAddend(value) else { continue }
      total += number
      count += 1
    }
    switch kind {
    case .sum:
      return .number(total)
    case .average:
      guard count > 0 else { return .error(.divZero) }
      return .number(total / Double(count))
    }
  }

  private func aggregateRangeKey(for anchor: RangeAnchor) -> AggregateRangeKey {
    AggregateRangeKey(
      sheet: anchor.sheet,
      row: anchor.row,
      col: anchor.col,
      rows: anchor.rows,
      cols: anchor.cols
    )
  }

  private func criteriaSupportsIndexLookup(_ test: CriteriaTest) -> Bool {
    test.op == .eq && !test.wildcard
  }

  private func lookupKeyForCriterion(_ criterion: CellValue, test: CriteriaTest)
    -> AggregateValueKey?
  {
    guard criteriaSupportsIndexLookup(test) else { return nil }
    if case .error = criterion { return nil }
    if test.blank {
      return AggregateValueKey(kind: .blank, numberBits: 0, text: "")
    }
    if let number = test.number {
      return AggregateValueKey(kind: .number, numberBits: number.bitPattern, text: "")
    }
    return AggregateValueKey.from(cellValue: criterion)
  }

  private func aggregateLookupKeys(criteria: [CellValue], tests: [CriteriaTest])
    -> [AggregateValueKey]?
  {
    guard criteria.count == tests.count else { return nil }
    var keys: [AggregateValueKey] = []
    keys.reserveCapacity(criteria.count)
    for (value, test) in zip(criteria, tests) {
      guard let key = lookupKeyForCriterion(value, test: test) else { return nil }
      keys.append(key)
    }
    return keys
  }

  private func snapshotValues(
    anchor: RangeAnchor,
    memo: inout [LookupMemoKey: CellValue]
  ) -> [CellValue] {
    let count = anchor.rows * anchor.cols
    let key = AggregateRangeKey(
      sheet: anchor.sheet,
      row: anchor.row,
      col: anchor.col,
      rows: anchor.rows,
      cols: anchor.cols
    )
    if let cache = aggregateRangeCache {
      return cache.rowMajorValues(key: key, count: count) { index in
        let row = index / anchor.cols
        let col = index % anchor.cols
        return lookupForAggregate(cellRef(anchor, row: row, col: col), memo: &memo)
      }
    }
    var values: [CellValue] = []
    values.reserveCapacity(count)
    for row in 0..<anchor.rows {
      for col in 0..<anchor.cols {
        values.append(lookupForAggregate(cellRef(anchor, row: row, col: col), memo: &memo))
      }
    }
    return values
  }

  // MARK: - Criteria

  private func criteriaTest(from value: CellValue) -> CriteriaTest {
    switch value {
    case .number(let number):
      return CriteriaTest(op: .eq, number: number, text: "", wildcard: false, blank: false)
    case .bool(let flag):
      return CriteriaTest(
        op: .eq, number: nil, text: flag ? "TRUE" : "FALSE", wildcard: false, blank: false)
    case .blank:
      return CriteriaTest(op: .eq, number: nil, text: "", wildcard: false, blank: true)
    case .string(let text):
      return criteriaTest(from: text)
    case .error:
      return CriteriaTest(op: .eq, number: nil, text: "", wildcard: false, blank: false)
    }
  }

  private func criteriaTest(from raw: String) -> CriteriaTest {
    var op: CriteriaOp = .eq
    var rest = raw
    if rest.hasPrefix(">=") {
      op = .ge
      rest = String(rest.dropFirst(2))
    } else if rest.hasPrefix("<=") {
      op = .le
      rest = String(rest.dropFirst(2))
    } else if rest.hasPrefix("<>") {
      op = .ne
      rest = String(rest.dropFirst(2))
    } else if rest.hasPrefix(">") {
      op = .gt
      rest = String(rest.dropFirst(1))
    } else if rest.hasPrefix("<") {
      op = .lt
      rest = String(rest.dropFirst(1))
    } else if rest.hasPrefix("=") {
      op = .eq
      rest = String(rest.dropFirst(1))
    }
    if rest.isEmpty {
      return CriteriaTest(op: op, number: nil, text: "", wildcard: false, blank: true)
    }
    let wildcard = excelHasWildcard(rest)
    if !wildcard, let number = Double(rest.trimmingCharacters(in: .whitespacesAndNewlines)) {
      return CriteriaTest(op: op, number: number, text: rest, wildcard: false, blank: false)
    }
    return CriteriaTest(op: op, number: nil, text: rest, wildcard: wildcard, blank: false)
  }

  private func criteriaMatch(_ value: CellValue, _ test: CriteriaTest) -> Bool {
    let blank = isBlankForCount(value)
    if test.wildcard && (test.op == .eq || test.op == .ne) {
      if blank { return test.op == .ne }
      let matched = excelWildcardMatch(criteriaText(value), pattern: test.text)
      return test.op == .eq ? matched : !matched
    }
    if let criterion = test.number {
      if let number = criteriaNumber(value) {
        return compareCriteria(test.op, number, criterion)
      }
      return test.op == .ne
    }
    if test.blank {
      switch test.op {
      case .eq: return blank
      case .ne: return !blank
      default: return false
      }
    }
    if blank { return test.op == .ne }
    if case .number = value {
      return test.op == .ne
    }
    let comparison = criteriaText(value).caseInsensitiveCompare(test.text)
    switch test.op {
    case .eq: return comparison == .orderedSame
    case .ne: return comparison != .orderedSame
    case .lt: return comparison == .orderedAscending
    case .gt: return comparison == .orderedDescending
    case .le: return comparison != .orderedDescending
    case .ge: return comparison != .orderedAscending
    }
  }

  private func compareCriteria(_ op: CriteriaOp, _ lhs: Double, _ rhs: Double) -> Bool {
    switch op {
    case .eq: return lhs == rhs
    case .ne: return lhs != rhs
    case .lt: return lhs < rhs
    case .le: return lhs <= rhs
    case .gt: return lhs > rhs
    case .ge: return lhs >= rhs
    }
  }

  private func criteriaNumber(_ value: CellValue) -> Double? {
    switch value {
    case .number(let number):
      return number
    case .string(let text):
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.isEmpty { return nil }
      return Double(trimmed)
    default:
      return nil
    }
  }

  public func criteriaText(_ value: CellValue) -> String {
    switch value {
    case .number:
      return value.displayString
    case .bool(let flag):
      return flag ? "TRUE" : "FALSE"
    case .string(let text):
      return text
    case .blank, .error:
      return ""
    }
  }

  public func isBlankForCount(_ value: CellValue) -> Bool {
    switch value {
    case .blank:
      return true
    case .string(let text):
      return text.isEmpty
    default:
      return false
    }
  }

  private func numericAddend(_ value: CellValue) -> Double? {
    if case .number(let number) = value { return number }
    return nil
  }

  private func excelHasWildcard(_ text: String) -> Bool {
    let chars = Array(text)
    var index = 0
    while index < chars.count {
      if chars[index] == "~", index + 1 < chars.count {
        let next = chars[index + 1]
        if next == "*" || next == "?" || next == "~" { return true }
        index += 2
        continue
      }
      if chars[index] == "*" || chars[index] == "?" { return true }
      index += 1
    }
    return false
  }

  public func excelWildcardMatch(_ text: String, pattern: String) -> Bool {
    let haystack = Array(text.lowercased())
    let needle = Array(pattern.lowercased())
    func match(from textIndex: Int, patternIndex: Int) -> Bool {
      var ti = textIndex
      var pi = patternIndex
      while pi < needle.count {
        if needle[pi] == "~", pi + 1 < needle.count {
          guard ti < haystack.count, haystack[ti] == needle[pi + 1] else { return false }
          ti += 1
          pi += 2
          continue
        }
        if needle[pi] == "*" {
          var next = pi + 1
          while next < needle.count, needle[next] == "*" { next += 1 }
          if next == needle.count { return true }
          for start in ti...haystack.count where match(from: start, patternIndex: next) {
            return true
          }
          return false
        }
        guard ti < haystack.count, needle[pi] == "?" || haystack[ti] == needle[pi] else {
          return false
        }
        ti += 1
        pi += 1
      }
      return ti == haystack.count
    }
    return match(from: 0, patternIndex: 0)
  }

  // MARK: - Ranges and arrays

  public func resolvedExpr(_ expr: FormulaExpr) -> FormulaExpr {
    if case .namedRange(let name) = expr, let resolved = namedRangeLookup(name) {
      return resolved
    }
    if case .call(let name, let args) = expr, Self.isSpillReference(name) {
      return spillReferenceRange(args) ?? .error(.ref)
    }
    return expr
  }

  private func rangeAnchor(_ expr: FormulaExpr) -> RangeAnchor? {
    switch resolvedExpr(expr) {
    case .range(let start, let end):
      let bounds = normalizedBounds(start: start, end: end)
      return RangeAnchor(
        sheet: start.sheet ?? end.sheet ?? formulaSheetName,
        row: bounds.minRow,
        col: bounds.minCol,
        rows: bounds.maxRow - bounds.minRow + 1,
        cols: bounds.maxCol - bounds.minCol + 1
      )
    case .cellRef(let ref):
      guard !ref.isRowOpen, !ref.isColOpen else { return nil }
      return RangeAnchor(
        sheet: ref.sheet ?? formulaSheetName, row: ref.row, col: ref.col, rows: 1, cols: 1)
    default:
      return nil
    }
  }

  private func cellRef(_ anchor: RangeAnchor, row: Int, col: Int) -> FormulaRef {
    FormulaRef(
      sheet: anchor.sheet,
      row: anchor.row + row,
      col: anchor.col + col,
      absRow: false,
      absCol: false
    )
  }

  private func valueMatrix(_ expr: FormulaExpr) -> ValueMatrix? {
    let resolved = resolvedExpr(expr)
    switch resolved {
    case .range(let start, let end):
      let bounds = normalizedBounds(start: start, end: end)
      let rows = bounds.maxRow - bounds.minRow + 1
      let cols = bounds.maxCol - bounds.minCol + 1
      guard rows > 0, cols > 0 else { return nil }
      return ValueMatrix(rows: rows, cols: cols, values: rangeCellValues(start: start, end: end))
    case .unary(let op, let inner):
      guard let matrix = valueMatrix(inner) else { return nil }
      return ValueMatrix(
        rows: matrix.rows, cols: matrix.cols, values: matrix.values.map { applyUnary(op, to: $0) })
    case .binary(let op, let lhs, let rhs):
      guard let left = valueMatrix(lhs), let right = valueMatrix(rhs) else { return nil }
      return combine(op, left, right)
    case .cellRef:
      return ValueMatrix(rows: 1, cols: 1, values: [evaluate(resolved)])
    default:
      return ValueMatrix(rows: 1, cols: 1, values: [evaluate(resolved)])
    }
  }

  private func combine(_ op: BinaryOp, _ lhs: ValueMatrix, _ rhs: ValueMatrix) -> ValueMatrix? {
    if lhs.rows == rhs.rows, lhs.cols == rhs.cols {
      let values = zip(lhs.values, rhs.values).map { applyBinary(op, lhs: $0, rhs: $1) }
      return ValueMatrix(rows: lhs.rows, cols: lhs.cols, values: values)
    }
    if lhs.rows == 1, lhs.cols == 1 {
      let values = rhs.values.map { applyBinary(op, lhs: lhs.values[0], rhs: $0) }
      return ValueMatrix(rows: rhs.rows, cols: rhs.cols, values: values)
    }
    if rhs.rows == 1, rhs.cols == 1 {
      let values = lhs.values.map { applyBinary(op, lhs: $0, rhs: rhs.values[0]) }
      return ValueMatrix(rows: lhs.rows, cols: lhs.cols, values: values)
    }
    return nil
  }

  private func expandedValues(_ args: [FormulaExpr]) -> [CellValue] {
    var values: [CellValue] = []
    for arg in args {
      if let matrix = valueMatrix(arg) {
        values.append(contentsOf: matrix.values)
      } else {
        values.append(evaluate(arg))
      }
    }
    return values
  }

  private func sumProductCoefficient(_ value: CellValue) -> Double {
    switch value {
    case .number(let number):
      return number
    case .bool(let flag):
      return flag ? 1 : 0
    case .blank, .string, .error:
      return 0
    }
  }

  private func replaceOccurrence(
    in source: String, needle: String, with replacement: String, occurrence: Int
  ) -> String {
    var found = 0
    var search = source.startIndex
    while search < source.endIndex,
      let range = source.range(of: needle, range: search..<source.endIndex)
    {
      found += 1
      if found == occurrence {
        var result = source
        result.replaceSubrange(range, with: replacement)
        return result
      }
      search = range.upperBound
    }
    return source
  }

  private func statsNumericValue(_ value: CellValue) -> Double? {
    switch value {
    case .number(let number):
      return number
    case .bool(let flag):
      return flag ? 1 : 0
    case .blank, .string, .error:
      return nil
    }
  }

  public func fastAverageIfPossible(_ args: [FormulaExpr]) -> CellValue? {
    guard args.count == 1 else { return nil }
    guard let anchor = rangeAnchor(args[0]) else { return nil }
    var memo: [LookupMemoKey: CellValue] = [:]
    let values = snapshotValues(anchor: anchor, memo: &memo)
    var sum = 0.0
    var count = 0
    for value in values {
      if case .error(let error) = value { return .error(error) }
      guard let number = statsNumericValue(value) else { continue }
      sum += number
      count += 1
    }
    guard count > 0 else { return .error(.divZero) }
    return .number(sum / Double(count))
  }

  // MARK: - SUMPRODUCT boolean products

  private func tryEvalBooleanSumProduct(_ args: [FormulaExpr]) -> CellValue? {
    guard let plan = parseSumProductBooleanPlan(args) else { return nil }
    return evalBooleanSumProductPlan(plan)
  }

  private func evalBooleanSumProductPlan(_ plan: SumProductBooleanPlan) -> CellValue? {
    guard let cache = aggregateRangeCache else { return nil }
    var memo: [LookupMemoKey: CellValue] = [:]
    let columns = plan.anchors.map { snapshotValues(anchor: $0, memo: &memo) }
    let rowCount = columns.first?.count ?? 0
    guard rowCount > 0, columns.allSatisfy({ $0.count == rowCount }) else { return nil }

    let staticMask = cache.booleanStaticMask(key: plan.staticMaskKey, rowCount: rowCount) { row in
      for test in plan.staticTests {
        let value = columns[test.columnIndex][row]
        if aggregateRowError(value) { return false }
        if !criteriaMatch(value, test.test) { return false }
      }
      for diff in plan.diffBoundTests {
        let lhs = columns[diff.lhsColumnIndex][row]
        let rhs = columns[diff.rhsColumnIndex][row]
        guard let left = lhs.asNumber, let right = rhs.asNumber else { return false }
        let delta = left - right
        switch diff.op {
        case .ge:
          if delta < diff.threshold { return false }
        case .le:
          if delta > diff.threshold { return false }
        default:
          return false
        }
      }
      return true
    }

    if plan.dynamicTests.count == 1, plan.dynamicTests[0].op == .eq {
      let dynamic = plan.dynamicTests[0]
      let criterion = evaluate(dynamic.criterionExpr)
      if case .error = criterion { return criterion }
      if let test = criteriaTestFromComparison(criterion: criterion, op: dynamic.op),
        criteriaSupportsIndexLookup(test),
        let lookupKey = lookupKeyForCriterion(criterion, test: test)
      {
        let rangeKey = aggregateRangeKey(for: plan.anchors[dynamic.columnIndex])
        let count = cache.countForMaskedCriteria(
          rangeKey: rangeKey,
          column: columns[dynamic.columnIndex],
          staticMaskKey: plan.staticMaskKey,
          mask: staticMask,
          criteriaKey: lookupKey
        )
        return .number(Double(count))
      }
    }

    var dynamicTests: [(columnIndex: Int, test: CriteriaTest)] = []
    for dynamic in plan.dynamicTests {
      let criterion = evaluate(dynamic.criterionExpr)
      if case .error = criterion { return criterion }
      guard let test = criteriaTestFromComparison(criterion: criterion, op: dynamic.op) else {
        return nil
      }
      dynamicTests.append((dynamic.columnIndex, test))
    }

    var count = 0
    for row in 0..<rowCount {
      guard staticMask[row] else { continue }
      var matched = true
      for dynamic in dynamicTests {
        let value = columns[dynamic.columnIndex][row]
        if aggregateRowError(value) {
          matched = false
          break
        }
        if !criteriaMatch(value, dynamic.test) {
          matched = false
          break
        }
      }
      if matched { count += 1 }
    }
    return .number(Double(count))
  }

  private struct SumProductBooleanPlan {
    public var anchors: [RangeAnchor]
    public var staticTests: [StaticColumnTest]
    public var dynamicTests: [DynamicColumnTest]
    public var diffBoundTests: [DiffBoundTest]
    public var staticMaskKey: UInt64

    public struct StaticColumnTest {
      public var columnIndex: Int
      public var test: CriteriaTest
    }

    public struct DynamicColumnTest {
      public var columnIndex: Int
      public var op: BinaryOp
      public var criterionExpr: FormulaExpr
    }

    public struct DiffBoundTest {
      public var lhsColumnIndex: Int
      public var rhsColumnIndex: Int
      public var op: CriteriaOp
      public var threshold: Double
    }
  }

  private enum ParsedBooleanFactor {
    case staticTest(RangeAnchor, CriteriaTest)
    case dynamicTest(RangeAnchor, BinaryOp, FormulaExpr)
    case diffBound(RangeAnchor, RangeAnchor, CriteriaOp, Double)
  }

  private func looksLikeBooleanSumProduct(_ args: [FormulaExpr]) -> Bool {
    guard let factors = booleanProductFactors(from: args), !factors.isEmpty else { return false }
    let meaningful = factors.filter { !isIgnorableBooleanProductFactor($0) }
    guard !meaningful.isEmpty else { return false }
    return meaningful.allSatisfy { parseBooleanFactor($0) != nil }
  }

  private func booleanProductFactors(from args: [FormulaExpr]) -> [FormulaExpr]? {
    guard !args.isEmpty else { return nil }
    if args.count == 1 {
      var factors: [FormulaExpr] = []
      guard collectMultiplyFactors(unwrapSumProductParen(args[0]), into: &factors) else {
        return nil
      }
      return factors.map { unwrapBooleanCoercion($0) }
    }
    return args.map { unwrapBooleanCoercion($0) }
  }

  private func isIgnorableBooleanProductFactor(_ expr: FormulaExpr) -> Bool {
    switch unwrapBooleanCoercion(expr) {
    case .number(let value):
      return value == 1
    case .boolean(let flag):
      return flag
    default:
      return false
    }
  }

  private func unwrapBooleanCoercion(_ expr: FormulaExpr) -> FormulaExpr {
    var node = unwrapSumProductParen(expr)
    while case .unary(.plus, let inner) = node {
      node = unwrapSumProductParen(inner)
    }
    while case .unary(.negate, let inner) = node {
      node = unwrapSumProductParen(inner)
    }
    return node
  }

  private func parseSumProductBooleanPlan(_ args: [FormulaExpr]) -> SumProductBooleanPlan? {
    guard let factors = booleanProductFactors(from: args), !factors.isEmpty else { return nil }
    var anchors: [RangeAnchor] = []
    var staticTests: [SumProductBooleanPlan.StaticColumnTest] = []
    var dynamicTests: [SumProductBooleanPlan.DynamicColumnTest] = []
    var diffBoundTests: [SumProductBooleanPlan.DiffBoundTest] = []
    var staticHasher = Hasher()

    for factor in factors {
      if isIgnorableBooleanProductFactor(factor) { continue }
      guard let parsed = parseBooleanFactor(factor) else { return nil }
      switch parsed {
      case .staticTest(let anchor, let test):
        let index = sumProductAnchorIndex(anchor, anchors: &anchors)
        staticTests.append(.init(columnIndex: index, test: test))
        mixStaticCriteriaTest(test, into: &staticHasher)
      case .dynamicTest(let anchor, let op, let criterionExpr):
        let index = sumProductAnchorIndex(anchor, anchors: &anchors)
        dynamicTests.append(.init(columnIndex: index, op: op, criterionExpr: criterionExpr))
      case .diffBound(let lhs, let rhs, let op, let threshold):
        let li = sumProductAnchorIndex(lhs, anchors: &anchors)
        let ri = sumProductAnchorIndex(rhs, anchors: &anchors)
        diffBoundTests.append(
          .init(lhsColumnIndex: li, rhsColumnIndex: ri, op: op, threshold: threshold))
        staticHasher.combine(op.hashValue)
        staticHasher.combine(threshold)
      }
    }

    guard !(staticTests.isEmpty && dynamicTests.isEmpty && diffBoundTests.isEmpty) else {
      return nil
    }
    for anchor in anchors {
      mixSumProductAnchor(anchor, into: &staticHasher)
    }
    return SumProductBooleanPlan(
      anchors: anchors,
      staticTests: staticTests,
      dynamicTests: dynamicTests,
      diffBoundTests: diffBoundTests,
      staticMaskKey: UInt64(bitPattern: Int64(staticHasher.finalize()))
    )
  }

  private func unwrapSumProductParen(_ expr: FormulaExpr) -> FormulaExpr {
    if case .unary(.plus, let inner) = expr { return unwrapSumProductParen(inner) }
    return expr
  }

  private func collectMultiplyFactors(_ expr: FormulaExpr, into factors: inout [FormulaExpr])
    -> Bool
  {
    switch expr {
    case .binary(.multiply, let lhs, let rhs):
      guard collectMultiplyFactors(lhs, into: &factors), collectMultiplyFactors(rhs, into: &factors)
      else {
        return false
      }
      return true
    case .unary(.plus, let inner):
      return collectMultiplyFactors(inner, into: &factors)
    default:
      factors.append(unwrapBooleanCoercion(expr))
      return true
    }
  }

  private func parseBooleanFactor(_ expr: FormulaExpr) -> ParsedBooleanFactor? {
    let node = unwrapSumProductParen(expr)
    guard case .binary(let op, let lhs, let rhs) = node else { return nil }
    if let diff = parseRangeSubtractBound(lhs: lhs, op: op, rhs: rhs) {
      return diff
    }
    switch op {
    case .eq, .ne, .lt, .le, .gt, .ge:
      break
    default:
      return nil
    }
    if let anchor = rangeAnchor(lhs) {
      guard !isRangeExpr(rhs) else { return nil }
      if isDynamicCriterion(rhs) {
        return .dynamicTest(anchor, op, rhs)
      }
      let criterion = evaluate(rhs)
      if case .error = criterion { return nil }
      guard let test = criteriaTestFromComparison(criterion: criterion, op: op) else { return nil }
      return .staticTest(anchor, test)
    }
    if let anchor = rangeAnchor(rhs) {
      guard !isRangeExpr(lhs) else { return nil }
      let flipped = flipComparisonOp(op)
      if isDynamicCriterion(lhs) {
        return .dynamicTest(anchor, flipped, lhs)
      }
      let criterion = evaluate(lhs)
      if case .error = criterion { return nil }
      guard let test = criteriaTestFromComparison(criterion: criterion, op: flipped) else {
        return nil
      }
      return .staticTest(anchor, test)
    }
    return nil
  }

  private func parseRangeSubtractBound(
    lhs: FormulaExpr,
    op: BinaryOp,
    rhs: FormulaExpr
  ) -> ParsedBooleanFactor? {
    guard op == .ge || op == .le else { return nil }
    guard case .number(let threshold) = evaluate(rhs) else { return nil }
    guard case .binary(.subtract, let left, let right) = unwrapSumProductParen(lhs),
      let lhsAnchor = rangeAnchor(left),
      let rhsAnchor = rangeAnchor(right),
      lhsAnchor.rows == rhsAnchor.rows,
      lhsAnchor.cols == rhsAnchor.cols
    else {
      return nil
    }
    let boundOp: CriteriaOp = op == .ge ? .ge : .le
    return .diffBound(lhsAnchor, rhsAnchor, boundOp, threshold)
  }

  private func isRangeExpr(_ expr: FormulaExpr) -> Bool {
    if case .range = expr { return true }
    return false
  }

  private func isDynamicCriterion(_ expr: FormulaExpr) -> Bool {
    switch expr {
    case .cellRef, .namedRange:
      return true
    case .unary(.plus, let inner), .unary(.negate, let inner):
      return isDynamicCriterion(inner)
    default:
      return false
    }
  }

  private func flipComparisonOp(_ op: BinaryOp) -> BinaryOp {
    switch op {
    case .eq: return .eq
    case .ne: return .ne
    case .lt: return .gt
    case .le: return .ge
    case .gt: return .lt
    case .ge: return .le
    default: return op
    }
  }

  private func criteriaTestFromComparison(criterion: CellValue, op: BinaryOp) -> CriteriaTest? {
    guard let criteriaOp = binaryOpToCriteriaOp(op) else { return nil }
    if criteriaOp == .ne {
      if case .string(let text) = criterion, text.isEmpty {
        return CriteriaTest(op: .ne, number: nil, text: "", wildcard: false, blank: true)
      }
      if case .blank = criterion {
        return CriteriaTest(op: .ne, number: nil, text: "", wildcard: false, blank: true)
      }
    }
    var test = criteriaTest(from: criterion)
    if test.wildcard { return nil }
    test.op = criteriaOp
    return test
  }

  private func binaryOpToCriteriaOp(_ op: BinaryOp) -> CriteriaOp? {
    switch op {
    case .eq: return .eq
    case .ne: return .ne
    case .lt: return .lt
    case .le: return .le
    case .gt: return .gt
    case .ge: return .ge
    default: return nil
    }
  }

  private func sumProductAnchorIndex(_ anchor: RangeAnchor, anchors: inout [RangeAnchor]) -> Int {
    if let index = anchors.firstIndex(where: { sameSumProductAnchorShape($0, anchor) }) {
      return index
    }
    anchors.append(anchor)
    return anchors.count - 1
  }

  private func sameSumProductAnchorShape(_ lhs: RangeAnchor, _ rhs: RangeAnchor) -> Bool {
    (lhs.sheet ?? "").caseInsensitiveCompare(rhs.sheet ?? "") == .orderedSame
      && lhs.row == rhs.row && lhs.col == rhs.col && lhs.rows == rhs.rows && lhs.cols == rhs.cols
  }

  private func mixSumProductAnchor(_ anchor: RangeAnchor, into hasher: inout Hasher) {
    hasher.combine((anchor.sheet ?? "").lowercased())
    hasher.combine(anchor.row)
    hasher.combine(anchor.col)
    hasher.combine(anchor.rows)
    hasher.combine(anchor.cols)
  }

  private func mixStaticCriteriaTest(_ test: CriteriaTest, into hasher: inout Hasher) {
    hasher.combine(test.op.hashValue)
    hasher.combine(test.number ?? 0)
    hasher.combine(test.text)
    hasher.combine(test.wildcard)
    hasher.combine(test.blank)
  }

  private func excelRound(_ value: Double, places: Int, mode: NSDecimalNumber.RoundingMode)
    -> Double
  {
    // Foundation rounds toward ±infinity. Excel ROUNDUP is away from zero and ROUNDDOWN is toward zero,
    // so the sign is applied after rounding the magnitude.
    let negative = value < 0
    let magnitude = abs(value)
    let source = Decimal(string: String(magnitude)) ?? Decimal(magnitude)
    var input = source
    var output = Decimal()
    NSDecimalRound(&output, &input, places, mode)
    // Read the digits as text: NSDecimalNumber.doubleValue can miss the nearest double.
    let digits = NSDecimalNumber(decimal: output).description(
      withLocale: Locale(identifier: "en_US_POSIX"))
    let rounded = Double(digits) ?? NSDecimalNumber(decimal: output).doubleValue
    // ROUNDDOWN(-0.004, 2) is 0, not negative zero.
    return negative && rounded != 0 ? -rounded : rounded
  }

  // MARK: - Column shape strip (tight eval loop)

  /// Vertical shared-shape column. Returns false when no column plan matches.
  public func evaluateColumnShapeStrip(
    master: CellAddress,
    members: [CellAddress],
    masterExpr: FormulaExpr,
    sink: (CellAddress, CellValue) -> Void
  ) -> Bool {
    guard members.count >= 2 else { return false }
    guard members.allSatisfy({ $0.col == master.col }) else { return false }
    let rows = members.map(\.row)
    guard let firstRow = rows.first, let lastRow = rows.last else { return false }
    guard lastRow - firstRow + 1 == members.count, rows == rows.sorted() else { return false }

    if let ifBlank = unpackIFBlankBranch(stripUnwrap(masterExpr)) {
      return evaluateColumnIFBlankStrip(
        master: master,
        members: members,
        ifGuard: ifBlank.ifGuard,
        branch: ifBlank.branch,
        sink: sink
      )
    }
    if let countifsKernel = stripCountifsKernelExpr(stripUnwrap(masterExpr)),
      evaluateColumnCOUNTIFSStrip(
        master: master, members: members, expr: countifsKernel, sink: sink)
    {
      return true
    }
    if evaluateColumnIFERRORVlookupStrip(
      master: master,
      members: members,
      expr: stripUnwrap(masterExpr),
      sink: sink
    ) {
      return true
    }
    return false
  }

  private enum IFBlankGuard {
    case single(FormulaRef)
    case andBothBlank(FormulaRef, FormulaRef)
  }

  private struct IFBlankBranch {
    public var ifGuard: IFBlankGuard
    public var branch: FormulaExpr
  }

  private func stripUnwrap(_ expr: FormulaExpr) -> FormulaExpr {
    if case .unary(.plus, let inner) = expr { return stripUnwrap(inner) }
    return expr
  }

  private func unpackIFBlankBranch(_ expr: FormulaExpr) -> IFBlankBranch? {
    guard case .call(let name, let args) = expr, name.uppercased() == "IF", args.count == 3 else {
      return nil
    }
    guard stripIsStaticEmptyLiteral(args[1]) else { return nil }
    if let guardRef = stripBlankEqualityGuardRef(args[0]) {
      return IFBlankBranch(ifGuard: .single(guardRef), branch: args[2])
    }
    if let pair = stripAndBothBlankGuardRefs(args[0]) {
      return IFBlankBranch(ifGuard: .andBothBlank(pair.0, pair.1), branch: args[2])
    }
    return nil
  }

  private func stripAndBothBlankGuardRefs(_ condition: FormulaExpr) -> (FormulaRef, FormulaRef)? {
    guard case .call(let name, let args) = stripUnwrap(condition), name.uppercased() == "AND",
      args.count == 2
    else {
      return nil
    }
    guard let left = stripBlankEqualityGuardRef(args[0]),
      let right = stripBlankEqualityGuardRef(args[1])
    else { return nil }
    return (left, right)
  }

  private func ifBlankGuardIsActive(
    _ ifGuard: IFBlankGuard,
    master: CellAddress,
    origin: CellAddress
  ) -> Bool {
    switch ifGuard {
    case .single(let ref):
      let cell = shiftedRef(ref, master: master, origin: origin)
      return stripValueIsBlankForIfGuard(lookup(cell))
    case .andBothBlank(let left, let right):
      let leftCell = shiftedRef(left, master: master, origin: origin)
      let rightCell = shiftedRef(right, master: master, origin: origin)
      return stripValueIsBlankForIfGuard(lookup(leftCell))
        && stripValueIsBlankForIfGuard(lookup(rightCell))
    }
  }

  private func singleGuardRef(_ ifGuard: IFBlankGuard) -> FormulaRef? {
    switch ifGuard {
    case .single(let ref):
      return ref
    case .andBothBlank:
      return nil
    }
  }

  private func stripIsStaticEmptyLiteral(_ expr: FormulaExpr) -> Bool {
    switch stripUnwrap(expr) {
    case .string(let text):
      return text.isEmpty
    default:
      return false
    }
  }

  /// Excel `TRUE` / `TRUE()` / `FALSE` / `FALSE()` in formula text (e.g. TEXTJOIN ignore flag).
  private func stripExcelBoolLiteral(_ expr: FormulaExpr) -> Bool? {
    switch stripUnwrap(expr) {
    case .boolean(let flag):
      return flag
    case .call(let name, let args) where name.uppercased() == "TRUE" && args.isEmpty:
      return true
    case .call(let name, let args) where name.uppercased() == "FALSE" && args.isEmpty:
      return false
    default:
      return nil
    }
  }

  private func stripBlankEqualityGuardRef(_ condition: FormulaExpr) -> FormulaRef? {
    guard case .binary(.eq, let lhs, let rhs) = stripUnwrap(condition) else { return nil }
    if stripIsStaticEmptyLiteral(rhs), let ref = stripFormulaCellRef(lhs) { return ref }
    if stripIsStaticEmptyLiteral(lhs), let ref = stripFormulaCellRef(rhs) { return ref }
    return nil
  }

  private func stripValueIsBlankForIfGuard(_ value: CellValue) -> Bool {
    switch value {
    case .blank:
      return true
    case .string(let text):
      return text.isEmpty
    default:
      return false
    }
  }

  private func stripFormulaCellRef(_ expr: FormulaExpr) -> FormulaRef? {
    switch stripUnwrap(expr) {
    case .cellRef(let ref):
      return ref
    default:
      return nil
    }
  }

  private func shiftedRef(_ ref: FormulaRef, master: CellAddress, origin: CellAddress) -> FormulaRef
  {
    let rowDelta = origin.row - master.row
    let colDelta = origin.col - master.col
    return ref.adjusted(rowDelta: rowDelta, colDelta: colDelta) ?? ref
  }

  /// Peel `IFERROR(COUNTIFS…)` / unary wrappers to the COUNTIFS call.
  private func stripCountifsKernelExpr(_ branch: FormulaExpr) -> FormulaExpr? {
    var current = stripUnwrap(branch)
    for _ in 0..<8 {
      if case .call(let name, _) = current, name.uppercased() == "COUNTIFS" {
        return current
      }
      if case .call(let name, let args) = current, name.uppercased() == "IFERROR", args.count == 2 {
        current = stripUnwrap(args[0])
        continue
      }
      if case .unary(.plus, let inner) = current {
        current = stripUnwrap(inner)
        continue
      }
      break
    }
    return nil
  }

  private func diagnoseIfStripBranchKernelMiss(
    _ branch: FormulaExpr,
    ifGuard: IFBlankGuard,
    master: CellAddress
  ) -> String {
    switch ifGuard {
    case .andBothBlank(let left, let right):
      if makeColumnTextJoinPlan(branch, guardA: left, guardB: right) != nil {
        return "textJoinUnexpected"
      }
      if makeColumnDuplicateStatusPlan(branch, pickRef: left, altRef: right, master: master) != nil
      {
        return "dupStatusUnexpected"
      }
    case .single(let ref):
      if makeColumnCountifPickPlan(branch, guardRef: ref, master: master) != nil {
        return "countifPickUnexpected"
      }
    }
    if let kernel = stripCountifsKernelExpr(branch) {
      return makeColumnCOUNTIFSPlan(kernel, master: master) == nil
        ? "countifsPlan" : "countifsUnexpected"
    }
    if case .call(let name, _) = stripUnwrap(branch), name.uppercased() == "IFERROR" {
      return "iferrorNotVlk"
    }
    return "otherBranch"
  }

  /// `IF(pick<>"",COUNTIF(fixedA,pick),COUNTIF(fixedG,guard))`.
  private struct ColumnCountifPickPlan {
    public var pickRef: FormulaRef
    public var rangeA: RangeAnchor
    public var rangeG: RangeAnchor
    public var valuesA: [CellValue]
    public var valuesG: [CellValue]
    public var rangeKeyA: AggregateRangeKey
    public var rangeKeyG: AggregateRangeKey
  }

  private func stripNotEmptyPickRef(_ condition: FormulaExpr) -> FormulaRef? {
    guard case .binary(.ne, let lhs, let rhs) = stripUnwrap(condition) else { return nil }
    guard stripIsStaticEmptyLiteral(rhs), let ref = stripFormulaCellRef(lhs) else { return nil }
    return ref
  }

  private func stripCountifRangeCriterion(_ expr: FormulaExpr) -> (RangeAnchor, FormulaRef)? {
    guard case .call(let name, let args) = stripUnwrap(expr), name.uppercased() == "COUNTIF",
      args.count == 2
    else {
      return nil
    }
    guard let anchor = rangeAnchor(args[0]), anchor.cols == 1 else { return nil }
    guard let criterionRef = stripFormulaCellRef(args[1]) else { return nil }
    return (anchor, criterionRef)
  }

  private func stripRefSameShapeAs(_ ref: FormulaRef, other: FormulaRef) -> Bool {
    (ref.sheet ?? "").caseInsensitiveCompare(other.sheet ?? "") == .orderedSame
      && ref.col == other.col
      && ref.absCol == other.absCol
      && ref.absRow == other.absRow
  }

  /// Same sheet cell as `keyRef`. Absolute flags may differ.
  private func stripRefSameCellAs(_ ref: FormulaRef, keyRef: FormulaRef) -> Bool {
    (ref.sheet ?? "").caseInsensitiveCompare(keyRef.sheet ?? "") == .orderedSame
      && ref.row == keyRef.row
      && ref.col == keyRef.col
  }

  private func makeColumnCountifPickPlan(
    _ branch: FormulaExpr,
    guardRef: FormulaRef,
    master: CellAddress
  ) -> ColumnCountifPickPlan? {
    guard case .call(let name, let args) = stripUnwrap(branch), name.uppercased() == "IF",
      args.count == 3
    else {
      return nil
    }
    guard let pickRef = stripNotEmptyPickRef(args[0]) else { return nil }
    guard let (rangeA, critA) = stripCountifRangeCriterion(args[1]),
      let (rangeG, critG) = stripCountifRangeCriterion(args[2])
    else { return nil }
    guard stripRefSameShapeAs(critA, other: pickRef), stripRefSameShapeAs(critG, other: guardRef)
    else { return nil }

    prepareForCellEvaluation(origin: master)
    var memo: [LookupMemoKey: CellValue] = [:]
    let valuesA = snapshotValues(anchor: rangeA, memo: &memo)
    let valuesG = snapshotValues(anchor: rangeG, memo: &memo)
    return ColumnCountifPickPlan(
      pickRef: pickRef,
      rangeA: rangeA,
      rangeG: rangeG,
      valuesA: valuesA,
      valuesG: valuesG,
      rangeKeyA: aggregateRangeKey(for: rangeA),
      rangeKeyG: aggregateRangeKey(for: rangeG)
    )
  }

  private func emitColumnCountifPickRow(
    plan: ColumnCountifPickPlan,
    guardRef: FormulaRef,
    master: CellAddress,
    origin: CellAddress,
    sink: (CellAddress, CellValue) -> Void
  ) {
    prepareForCellEvaluation(origin: origin)
    let guardCell = shiftedRef(guardRef, master: master, origin: origin)
    if stripValueIsBlankForIfGuard(lookup(guardCell)) {
      sink(origin, .string(""))
      recalcProfile?.ifStripCountifsRows += 1
      return
    }
    let pickCell = shiftedRef(plan.pickRef, master: master, origin: origin)
    let pickValue = lookup(pickCell)
    let usePickBranch = !stripValueIsBlankForIfGuard(pickValue)
    let values = usePickBranch ? plan.valuesA : plan.valuesG
    let rangeKey = usePickBranch ? plan.rangeKeyA : plan.rangeKeyG
    let criterion = usePickBranch ? pickValue : lookup(guardCell)
    if case .error = criterion {
      sink(origin, criterion)
      recalcProfile?.ifStripCountifsRows += 1
      return
    }
    let test = criteriaTest(from: criterion)
    if let cache = aggregateRangeCache,
      criteriaSupportsIndexLookup(test),
      let lookupKey = lookupKeyForCriterion(criterion, test: test)
    {
      let count = cache.countForCriteria(
        rangeKeys: [rangeKey],
        criteriaKeys: [lookupKey],
        supplyColumns: { [values] }
      )
      sink(origin, .number(Double(count)))
      recalcProfile?.ifStripCountifsRows += 1
      return
    }
    var matches = 0
    recalcProfile?.countifsRowScanCells += values.count
    for value in values {
      if aggregateRowError(value) { continue }
      if criteriaMatch(value, test) { matches += 1 }
    }
    sink(origin, .number(Double(matches)))
    recalcProfile?.ifStripCountifsRows += 1
  }

  /// `TEXTJOIN` of two cells after `IF(AND(left="",right=""),"",…)`.
  private struct ColumnTextJoinPlan {
    public var joinRefA: FormulaRef
    public var joinRefB: FormulaRef
    public var delimiter: String
    public var ignoreEmpty: Bool
  }

  private func makeColumnTextJoinPlan(
    _ branch: FormulaExpr,
    guardA: FormulaRef,
    guardB: FormulaRef
  ) -> ColumnTextJoinPlan? {
    guard case .call(let name, let args) = stripUnwrap(branch), name.uppercased() == "TEXTJOIN",
      args.count == 4
    else {
      return nil
    }
    guard case .string(let delimiter) = stripUnwrap(args[0]) else { return nil }
    guard let ignoreEmpty = stripExcelBoolLiteral(args[1]) else { return nil }
    guard let joinA = stripFormulaCellRef(args[2]), let joinB = stripFormulaCellRef(args[3]) else {
      return nil
    }
    guard stripRefSameShapeAs(joinA, other: guardA), stripRefSameShapeAs(joinB, other: guardB)
    else { return nil }
    return ColumnTextJoinPlan(
      joinRefA: joinA, joinRefB: joinB, delimiter: delimiter, ignoreEmpty: ignoreEmpty)
  }

  private func emitColumnTextJoinRow(
    plan: ColumnTextJoinPlan,
    master: CellAddress,
    origin: CellAddress,
    sink: (CellAddress, CellValue) -> Void
  ) {
    prepareForCellEvaluation(origin: origin)
    let left = lookup(shiftedRef(plan.joinRefA, master: master, origin: origin))
    let right = lookup(shiftedRef(plan.joinRefB, master: master, origin: origin))
    if case .error(let error) = left {
      sink(origin, .error(error))
      recalcProfile?.ifStripTextJoinRows += 1
      return
    }
    if case .error(let error) = right {
      sink(origin, .error(error))
      recalcProfile?.ifStripTextJoinRows += 1
      return
    }
    var parts: [String] = []
    for value in [left, right] {
      if plan.ignoreEmpty && isBlankForCount(value) { continue }
      parts.append(value.asString)
    }
    sink(origin, .string(parts.joined(separator: plan.delimiter)))
    recalcProfile?.ifStripTextJoinRows += 1
  }

  /// One arm of a duplicate-status formula (`DUPLICATE` / `ORIGINAL` / `UNIQUE`).
  private struct DuplicateStatusArmPlan {
    public var keyCol: Int
    public var prefixStartRow: Int
    public var fixedValues: [CellValue]
    public var fixedRangeKey: AggregateRangeKey
  }

  private struct ColumnDuplicateStatusPlan {
    public var pickRef: FormulaRef
    public var altRef: FormulaRef
    public var pickArm: DuplicateStatusArmPlan
    public var altArm: DuplicateStatusArmPlan
  }

  private func stripStaticLabel(_ expr: FormulaExpr, _ label: String) -> Bool {
    guard case .string(let text) = stripUnwrap(expr) else { return false }
    return text.caseInsensitiveCompare(label) == .orderedSame
  }

  private func stripCountGreaterThanOneExpr(_ expr: FormulaExpr) -> FormulaExpr? {
    guard case .binary(.gt, let lhs, let rhs) = stripUnwrap(expr) else { return nil }
    guard case .number(let number) = stripUnwrap(rhs), number == 1 else { return nil }
    return stripUnwrap(lhs)
  }

  private func stripGrowingCountifsPrefix(
    _ rangeExpr: FormulaExpr,
    criterion: FormulaExpr,
    keyRef: FormulaRef
  ) -> (prefixStartRow: Int, keyCol: Int)? {
    guard case .range(let start, let end) = resolvedExpr(stripUnwrap(rangeExpr)) else { return nil }
    guard start.absRow, !end.absRow, start.col == end.col else { return nil }
    guard end.row == keyRef.row, end.col == keyRef.col else { return nil }
    guard let critRef = stripFormulaCellRef(criterion), stripRefSameCellAs(critRef, keyRef: keyRef)
    else {
      return nil
    }
    guard critRef.row == end.row, critRef.col == end.col else { return nil }
    return (start.row, start.col)
  }

  private func parseDuplicateStatusArm(
    _ expr: FormulaExpr,
    keyRef: FormulaRef,
    master: CellAddress
  ) -> DuplicateStatusArmPlan? {
    guard case .call(let name, let args) = stripUnwrap(expr), name.uppercased() == "IF",
      args.count == 3
    else {
      return nil
    }
    guard let countifsExpr = stripCountGreaterThanOneExpr(args[0]),
      case .call(let countifsName, let countifsArgs) = stripUnwrap(countifsExpr),
      countifsName.uppercased() == "COUNTIFS",
      countifsArgs.count == 2
    else { return nil }
    guard stripStaticLabel(args[1], "DUPLICATE") else { return nil }
    guard case .call(let innerName, let innerArgs) = stripUnwrap(args[2]),
      innerName.uppercased() == "IF",
      innerArgs.count == 3
    else { return nil }
    guard let countifExpr = stripCountGreaterThanOneExpr(innerArgs[0]),
      case .call(let countifName, let countifArgs) = stripUnwrap(countifExpr),
      countifName.uppercased() == "COUNTIF",
      countifArgs.count == 2
    else { return nil }
    guard stripStaticLabel(innerArgs[1], "ORIGINAL"), stripStaticLabel(innerArgs[2], "UNIQUE")
    else { return nil }
    guard
      let prefix = stripGrowingCountifsPrefix(
        countifsArgs[0], criterion: countifsArgs[1], keyRef: keyRef),
      let (fixedAnchor, fixedCrit) = stripCountifRangeCriterion(countifExpr),
      stripRefSameCellAs(fixedCrit, keyRef: keyRef)
    else { return nil }
    guard fixedAnchor.col == prefix.keyCol else { return nil }

    prepareForCellEvaluation(origin: master)
    var memo: [LookupMemoKey: CellValue] = [:]
    let fixedValues = snapshotValues(anchor: fixedAnchor, memo: &memo)
    return DuplicateStatusArmPlan(
      keyCol: prefix.keyCol,
      prefixStartRow: prefix.prefixStartRow,
      fixedValues: fixedValues,
      fixedRangeKey: aggregateRangeKey(for: fixedAnchor)
    )
  }

  private func makeColumnDuplicateStatusPlan(
    _ branch: FormulaExpr,
    pickRef: FormulaRef,
    altRef: FormulaRef,
    master: CellAddress
  ) -> ColumnDuplicateStatusPlan? {
    guard case .call(let name, let args) = stripUnwrap(branch), name.uppercased() == "IF",
      args.count == 3
    else {
      return nil
    }
    guard let branchPick = stripNotEmptyPickRef(args[0]),
      stripRefSameCellAs(branchPick, keyRef: pickRef)
    else {
      return nil
    }
    guard let pickArm = parseDuplicateStatusArm(args[1], keyRef: pickRef, master: master),
      let altArm = parseDuplicateStatusArm(args[2], keyRef: altRef, master: master)
    else { return nil }
    return ColumnDuplicateStatusPlan(
      pickRef: pickRef,
      altRef: altRef,
      pickArm: pickArm,
      altArm: altArm
    )
  }

  // MARK: - L duplicate-status plan reject diagnostics (match guards; no behavior change)

  private func diagnoseStripGrowingCountifsPrefixReject(
    _ rangeExpr: FormulaExpr,
    criterion: FormulaExpr,
    keyRef: FormulaRef
  ) -> String {
    guard case .range(let start, let end) = resolvedExpr(stripUnwrap(rangeExpr)) else {
      return "dup.prefix.notRange"
    }
    guard start.absRow, !end.absRow, start.col == end.col else {
      return "dup.prefix.startEndShape"
    }
    guard end.row == keyRef.row, end.col == keyRef.col else {
      return "dup.prefix.endKeyRowCol"
    }
    guard let critRef = stripFormulaCellRef(criterion) else {
      return "dup.prefix.criterionRef"
    }
    guard stripRefSameCellAs(critRef, keyRef: keyRef) else {
      return "dup.prefix.critKeyCell"
    }
    guard critRef.row == end.row, critRef.col == end.col else {
      return "dup.prefix.critEndRowCol"
    }
    return "dup.prefix.ok"
  }

  private func diagnoseStripCountifRangeCriterionReject(_ expr: FormulaExpr) -> String {
    guard case .call(let name, let args) = stripUnwrap(expr), name.uppercased() == "COUNTIF",
      args.count == 2
    else {
      return "dup.countif.notCall2"
    }
    guard let anchor = rangeAnchor(args[0]), anchor.cols == 1 else {
      return "dup.countif.rangeCols"
    }
    guard stripFormulaCellRef(args[1]) != nil else {
      return "dup.countif.criterionRef"
    }
    return "dup.countif.ok"
  }

  private func diagnoseDuplicateStatusArmReject(
    _ expr: FormulaExpr,
    keyRef: FormulaRef,
    arm: String
  ) -> String? {
    let prefix = "dup.\(arm)."
    guard case .call(let name, let args) = stripUnwrap(expr), name.uppercased() == "IF",
      args.count == 3
    else {
      return prefix + "ifTop"
    }
    guard let countifsExpr = stripCountGreaterThanOneExpr(args[0]),
      case .call(let countifsName, let countifsArgs) = stripUnwrap(countifsExpr),
      countifsName.uppercased() == "COUNTIFS",
      countifsArgs.count == 2
    else {
      return prefix + "countifsGt1"
    }
    guard stripStaticLabel(args[1], "DUPLICATE") else {
      return prefix + "duplicateLabel"
    }
    guard case .call(let innerName, let innerArgs) = stripUnwrap(args[2]),
      innerName.uppercased() == "IF",
      innerArgs.count == 3
    else {
      return prefix + "innerIf"
    }
    guard let countifExpr = stripCountGreaterThanOneExpr(innerArgs[0]),
      case .call(let countifName, let countifArgs) = stripUnwrap(countifExpr),
      countifName.uppercased() == "COUNTIF",
      countifArgs.count == 2
    else {
      return prefix + "countifGt1"
    }
    guard stripStaticLabel(innerArgs[1], "ORIGINAL"), stripStaticLabel(innerArgs[2], "UNIQUE")
    else {
      return prefix + "originalUniqueLabel"
    }
    let prefixReject = diagnoseStripGrowingCountifsPrefixReject(
      countifsArgs[0],
      criterion: countifsArgs[1],
      keyRef: keyRef
    )
    if prefixReject != "dup.prefix.ok" {
      return prefix + String(prefixReject.dropFirst(4))
    }
    let countifReject = diagnoseStripCountifRangeCriterionReject(countifExpr)
    if countifReject != "dup.countif.ok" {
      return prefix + String(countifReject.dropFirst(4))
    }
    guard let (_, fixedCrit) = stripCountifRangeCriterion(countifExpr) else {
      return prefix + "countifRange"
    }
    guard stripRefSameCellAs(fixedCrit, keyRef: keyRef) else {
      return prefix + "fixedCritKeyCell"
    }
    guard
      let growing = stripGrowingCountifsPrefix(
        countifsArgs[0], criterion: countifsArgs[1], keyRef: keyRef),
      let (fixedAnchor, _) = stripCountifRangeCriterion(countifExpr)
    else {
      return prefix + "prefixOrCountif"
    }
    guard fixedAnchor.col == growing.keyCol else {
      return prefix + "fixedColPrefixCol"
    }
    return nil
  }

  private func diagnoseColumnDuplicateStatusPlanReject(
    branch: FormulaExpr,
    pickRef: FormulaRef,
    altRef: FormulaRef
  ) -> String {
    guard case .call(let name, let args) = stripUnwrap(branch), name.uppercased() == "IF",
      args.count == 3
    else {
      return "dup.branch.ifTop"
    }
    guard let branchPick = stripNotEmptyPickRef(args[0]) else {
      return "dup.branch.pickNotEmpty"
    }
    guard stripRefSameCellAs(branchPick, keyRef: pickRef) else {
      return "dup.branch.pickKeyCell"
    }
    if let pickReject = diagnoseDuplicateStatusArmReject(args[1], keyRef: pickRef, arm: "pick") {
      return pickReject
    }
    if let altReject = diagnoseDuplicateStatusArmReject(args[2], keyRef: altRef, arm: "alt") {
      return altReject
    }
    return "dup.branch.ok"
  }

  private func diagnoseIfStripOtherBranchReject(
    branch: FormulaExpr,
    ifGuard: IFBlankGuard,
    master: CellAddress
  ) -> String {
    switch ifGuard {
    case .andBothBlank(let left, let right):
      if makeColumnTextJoinPlan(branch, guardA: left, guardB: right) != nil {
        return "ifBlank.textJoinUnexpected"
      }
      let dupReject = diagnoseColumnDuplicateStatusPlanReject(
        branch: branch,
        pickRef: left,
        altRef: right
      )
      if dupReject != "dup.branch.ok" {
        return dupReject
      }
      if makeColumnDuplicateStatusPlan(branch, pickRef: left, altRef: right, master: master) != nil
      {
        return "ifBlank.dupUnexpected"
      }
      return "ifBlank.dupSnapshot"
    case .single(let guardRef):
      if makeColumnCountifPickPlan(branch, guardRef: guardRef, master: master) != nil {
        return "ifBlank.countifPickUnexpected"
      }
      if let kernel = stripCountifsKernelExpr(branch) {
        return makeColumnCOUNTIFSPlan(kernel, master: master) == nil
          ? "ifBlank.countifsPlan" : "ifBlank.countifsUnexpected"
      }
      if case .call(let name, _) = stripUnwrap(branch), name.uppercased() == "IFERROR" {
        return "ifBlank.iferrorNotVlk"
      }
      return "ifBlank.singleOther"
    }
  }

  private func stripAggregateValueKey(_ value: CellValue) -> AggregateValueKey? {
    if case .error = value { return nil }
    return lookupKeyForCriterion(value, test: criteriaTest(from: value))
  }

  private func seedDuplicatePrefixCounts(
    arm: DuplicateStatusArmPlan,
    throughRow: Int,
    master: CellAddress
  ) -> [AggregateValueKey: Int] {
    var counts: [AggregateValueKey: Int] = [:]
    guard throughRow >= arm.prefixStartRow else { return counts }
    for row in arm.prefixStartRow...throughRow {
      let origin = CellAddress(row: row, col: master.col)
      prepareForCellEvaluation(origin: origin)
      let ref = FormulaRef(sheet: nil, row: row, col: arm.keyCol, absRow: false, absCol: false)
      let value = lookup(ref)
      if let key = stripAggregateValueKey(value) {
        counts[key, default: 0] += 1
      }
    }
    return counts
  }

  private func emitDuplicateStatusArmRow(
    arm: DuplicateStatusArmPlan,
    keyRef: FormulaRef,
    master: CellAddress,
    origin: CellAddress,
    prefixCounts: inout [AggregateValueKey: Int],
    sink: (CellAddress, CellValue) -> Void
  ) {
    let value = lookup(shiftedRef(keyRef, master: master, origin: origin))
    if case .error = value {
      sink(origin, value)
      return
    }
    guard let key = stripAggregateValueKey(value) else {
      sink(origin, .string("UNIQUE"))
      return
    }
    prefixCounts[key, default: 0] += 1
    if let seen = prefixCounts[key], seen > 1 {
      sink(origin, .string("DUPLICATE"))
      return
    }
    let test = criteriaTest(from: value)
    if let cache = aggregateRangeCache,
      criteriaSupportsIndexLookup(test),
      let lookupKey = lookupKeyForCriterion(value, test: test)
    {
      let full = cache.countForCriteria(
        rangeKeys: [arm.fixedRangeKey],
        criteriaKeys: [lookupKey],
        supplyColumns: { [arm.fixedValues] }
      )
      sink(origin, .string(full > 1 ? "ORIGINAL" : "UNIQUE"))
      return
    }
    var matches = 0
    for cell in arm.fixedValues {
      if aggregateRowError(cell) { continue }
      if criteriaMatch(cell, test) { matches += 1 }
    }
    sink(origin, .string(matches > 1 ? "ORIGINAL" : "UNIQUE"))
  }

  private func evaluateColumnDuplicateStatusStrip(
    master: CellAddress,
    members: [CellAddress],
    ifGuard: IFBlankGuard,
    branch: FormulaExpr,
    pickRef: FormulaRef,
    altRef: FormulaRef,
    sink: (CellAddress, CellValue) -> Void
  ) -> Bool {
    guard
      let plan = makeColumnDuplicateStatusPlan(
        branch, pickRef: pickRef, altRef: altRef, master: master)
    else {
      return false
    }
    var pickCounts = seedDuplicatePrefixCounts(
      arm: plan.pickArm, throughRow: master.row - 1, master: master)
    var altCounts = seedDuplicatePrefixCounts(
      arm: plan.altArm, throughRow: master.row - 1, master: master)
    for origin in members {
      prepareForCellEvaluation(origin: origin)
      if ifBlankGuardIsActive(ifGuard, master: master, origin: origin) {
        recalcProfile?.ifBlankEqualityFastHits += 1
        sink(origin, .string(""))
        recalcProfile?.ifStripDupStatusRows += 1
        continue
      }
      recalcProfile?.ifBlankEqualityFastHits += 1
      let pickValue = lookup(shiftedRef(plan.pickRef, master: master, origin: origin))
      if !stripValueIsBlankForIfGuard(pickValue) {
        emitDuplicateStatusArmRow(
          arm: plan.pickArm,
          keyRef: plan.pickRef,
          master: master,
          origin: origin,
          prefixCounts: &pickCounts,
          sink: sink
        )
      } else {
        emitDuplicateStatusArmRow(
          arm: plan.altArm,
          keyRef: plan.altRef,
          master: master,
          origin: origin,
          prefixCounts: &altCounts,
          sink: sink
        )
      }
      recalcProfile?.ifStripDupStatusRows += 1
    }
    return true
  }

  private struct ColumnCOUNTIFSPlan {
    public var staticCriteria: [CellValue]
    public var staticTests: [CriteriaTest]
    public var dynamicCriterionRefs: [FormulaRef]
    public var columns: [[CellValue]]
    public var rangeKeys: [AggregateRangeKey]
  }

  private struct ColumnIFERRORVlookupPlan {
    public var needleRef: FormulaRef
    public var tableStart: FormulaRef
    public var tableEnd: FormulaRef
    public var tableKey: LookupTableKey
    public var bounds: (minRow: Int, maxRow: Int, minCol: Int, maxCol: Int)
    public var resultOffset: Int
    public var fallbackAtMaster: FormulaExpr
  }

  private func stripResolveTableRange(_ expr: FormulaExpr) -> (FormulaRef, FormulaRef)? {
    switch resolvedExpr(expr) {
    case .range(let start, let end):
      return (start, end)
    case .namedRange(let name):
      guard let resolved = namedRangeLookup(name),
        case .range(let start, let end) = resolved
      else { return nil }
      return (start, end)
    default:
      return nil
    }
  }

  private func makeColumnIFERRORVlookupPlan(_ expr: FormulaExpr, master: CellAddress)
    -> ColumnIFERRORVlookupPlan?
  {
    guard case .call(let outer, let outerArgs) = stripUnwrap(expr), outer.uppercased() == "IFERROR",
      outerArgs.count == 2
    else { return nil }
    guard case .call(let inner, let vargs) = stripUnwrap(outerArgs[0]),
      inner.uppercased() == "VLOOKUP",
      vargs.count >= 3, vargs.count <= 4
    else { return nil }
    guard let needleRef = stripFormulaCellRef(vargs[0]) else { return nil }

    prepareForCellEvaluation(origin: master)
    let indexValue = evaluate(vargs[2])
    if case .error = indexValue { return nil }
    guard let indexNumber = indexValue.asNumber else { return nil }
    let index = Int(indexNumber.rounded(.down))

    var exact = false
    if vargs.count == 4 {
      let flag = evaluate(vargs[3])
      if case .error = flag { return nil }
      exact = !(flag.asBool ?? true)
    }
    guard exact, lookupTableCache != nil else { return nil }

    guard let (start, end) = stripResolveTableRange(vargs[1]) else { return nil }
    let n = normalizedBounds(start: start, end: end)
    let span = n.maxCol - n.minCol + 1
    guard index >= 1, index <= span else { return nil }
    let resultOffset = n.minCol + index - 1

    let tableKey = LookupTableKey(
      sheet: (start.sheet ?? end.sheet ?? formulaSheetName ?? "").lowercased(),
      minRow: n.minRow,
      minCol: n.minCol,
      maxRow: n.maxRow,
      maxCol: n.maxCol,
      resultIndex: index,
      horizontal: false
    )
    return ColumnIFERRORVlookupPlan(
      needleRef: needleRef,
      tableStart: start,
      tableEnd: end,
      tableKey: tableKey,
      bounds: n,
      resultOffset: resultOffset,
      fallbackAtMaster: outerArgs[1]
    )
  }

  private func emitColumnIFERRORVlookupRow(
    plan: ColumnIFERRORVlookupPlan,
    master: CellAddress,
    origin: CellAddress,
    sink: (CellAddress, CellValue) -> Void
  ) {
    prepareForCellEvaluation(origin: origin)
    let needle = lookup(shiftedRef(plan.needleRef, master: master, origin: origin))
    recalcProfile?.iferrorVlookupFastHits += 1
    let rowDelta = origin.row - master.row
    let colDelta = origin.col - master.col
    let fallbackExpr = FormulaRewriter.adjustExpression(
      plan.fallbackAtMaster,
      rowDelta: rowDelta,
      colDelta: colDelta
    )
    if case .error = needle {
      recalcProfile?.ifStripVlkNA += 1
      sink(origin, evaluate(fallbackExpr))
      return
    }
    guard let cache = lookupTableCache else {
      recalcProfile?.ifStripVlkNA += 1
      sink(origin, evaluate(fallbackExpr))
      return
    }
    if let hit = cache.exactLookup(
      key: plan.tableKey, needle: needle,
      build: {
        buildExactLookupMap(
          horizontal: false,
          bounds: plan.bounds,
          start: plan.tableStart,
          resultOffset: plan.resultOffset
        )
      })
    {
      recalcProfile?.ifStripHits += 1
      sink(origin, hit)
    } else {
      recalcProfile?.ifStripVlkNA += 1
      sink(origin, evaluate(fallbackExpr))
    }
  }

  private func makeColumnCOUNTIFSPlan(_ countifsExpr: FormulaExpr, master: CellAddress)
    -> ColumnCOUNTIFSPlan?
  {
    guard case .call(let name, let args) = stripUnwrap(countifsExpr),
      name.uppercased() == "COUNTIFS"
    else {
      return nil
    }
    guard args.count >= 2, args.count.isMultiple(of: 2) else { return nil }
    guard let firstAnchor = rangeAnchor(args[0]) else { return nil }

    var criterionExprs: [FormulaExpr] = []
    var index = 0
    while index < args.count {
      guard let anchor = rangeAnchor(args[index]) else { return nil }
      if anchor.rows != firstAnchor.rows || anchor.cols != firstAnchor.cols { return nil }
      criterionExprs.append(args[index + 1])
      index += 2
    }

    prepareForCellEvaluation(origin: master)
    var staticCriteria: [CellValue] = []
    var staticTests: [CriteriaTest] = []
    var dynamicCriterionRefs: [FormulaRef] = []
    for criterionExpr in criterionExprs {
      if let ref = stripFormulaCellRef(criterionExpr) {
        dynamicCriterionRefs.append(ref)
        staticCriteria.append(.blank)
        staticTests.append(
          CriteriaTest(op: .eq, number: nil, text: "", wildcard: false, blank: false))
      } else {
        let value = evaluate(criterionExpr)
        if case .error = value { return nil }
        staticCriteria.append(value)
        staticTests.append(criteriaTest(from: value))
        dynamicCriterionRefs.append(
          FormulaRef(sheet: nil, row: -1, col: -1, absRow: true, absCol: true)
        )
      }
    }

    var rangeAnchors: [RangeAnchor] = []
    index = 0
    while index < args.count {
      guard let anchor = rangeAnchor(args[index]) else { return nil }
      rangeAnchors.append(anchor)
      index += 2
    }

    var snapMemo: [LookupMemoKey: CellValue] = [:]
    let columns = rangeAnchors.map { snapshotValues(anchor: $0, memo: &snapMemo) }
    let rangeKeys = rangeAnchors.map { aggregateRangeKey(for: $0) }
    return ColumnCOUNTIFSPlan(
      staticCriteria: staticCriteria,
      staticTests: staticTests,
      dynamicCriterionRefs: dynamicCriterionRefs,
      columns: columns,
      rangeKeys: rangeKeys
    )
  }

  private func emitColumnCOUNTIFSRow(
    plan: ColumnCOUNTIFSPlan,
    master: CellAddress,
    origin: CellAddress,
    sink: (CellAddress, CellValue) -> Void
  ) {
    prepareForCellEvaluation(origin: origin)
    var criteriaValues = plan.staticCriteria
    var tests = plan.staticTests
    var criterionError: CellValue?
    for (pairIndex, ref) in plan.dynamicCriterionRefs.enumerated() where ref.row >= 0 {
      let shifted = shiftedRef(ref, master: master, origin: origin)
      let value = lookup(shifted)
      if case .error = value {
        criterionError = value
        break
      }
      criteriaValues[pairIndex] = value
      tests[pairIndex] = criteriaTest(from: value)
    }
    if let criterionError {
      sink(origin, criterionError)
      return
    }
    if let cache = aggregateRangeCache,
      let lookupKeys = aggregateLookupKeys(criteria: criteriaValues, tests: tests)
    {
      let matches = cache.countForCriteria(
        rangeKeys: plan.rangeKeys,
        criteriaKeys: lookupKeys,
        supplyColumns: { plan.columns }
      )
      recalcProfile?.countifsHistogramLookups += 1
      sink(origin, .number(Double(matches)))
      return
    }
    let count = plan.columns[0].count
    var matches = 0
    recalcProfile?.countifsRowScanCells += count
    for offset in 0..<count {
      var matched = true
      for rangeIndex in 0..<tests.count {
        let value = plan.columns[rangeIndex][offset]
        if aggregateRowError(value) {
          matched = false
          break
        }
        if !criteriaMatch(value, tests[rangeIndex]) {
          matched = false
          break
        }
      }
      if matched { matches += 1 }
    }
    sink(origin, .number(Double(matches)))
  }

  private func evaluateColumnIFBlankStrip(
    master: CellAddress,
    members: [CellAddress],
    ifGuard: IFBlankGuard,
    branch: FormulaExpr,
    sink: (CellAddress, CellValue) -> Void
  ) -> Bool {
    let branchExpr = stripUnwrap(branch)
    switch ifGuard {
    case .andBothBlank(let left, let right):
      if let textJoinPlan = makeColumnTextJoinPlan(branchExpr, guardA: left, guardB: right) {
        for origin in members {
          prepareForCellEvaluation(origin: origin)
          if ifBlankGuardIsActive(ifGuard, master: master, origin: origin) {
            recalcProfile?.ifBlankEqualityFastHits += 1
            sink(origin, .string(""))
            recalcProfile?.ifStripTextJoinRows += 1
            continue
          }
          recalcProfile?.ifBlankEqualityFastHits += 1
          emitColumnTextJoinRow(plan: textJoinPlan, master: master, origin: origin, sink: sink)
        }
        return true
      }
      if evaluateColumnDuplicateStatusStrip(
        master: master,
        members: members,
        ifGuard: ifGuard,
        branch: branchExpr,
        pickRef: left,
        altRef: right,
        sink: sink
      ) {
        return true
      }
    case .single(let guardRef):
      if let vlookupPlan = makeColumnIFERRORVlookupPlan(branchExpr, master: master) {
        for origin in members {
          prepareForCellEvaluation(origin: origin)
          if ifBlankGuardIsActive(ifGuard, master: master, origin: origin) {
            recalcProfile?.ifBlankEqualityFastHits += 1
            sink(origin, .string(""))
            continue
          }
          recalcProfile?.ifBlankEqualityFastHits += 1
          emitColumnIFERRORVlookupRow(plan: vlookupPlan, master: master, origin: origin, sink: sink)
        }
        return true
      }
      if let countifPickPlan = makeColumnCountifPickPlan(
        branchExpr, guardRef: guardRef, master: master)
      {
        for origin in members {
          prepareForCellEvaluation(origin: origin)
          if ifBlankGuardIsActive(ifGuard, master: master, origin: origin) {
            recalcProfile?.ifBlankEqualityFastHits += 1
            sink(origin, .string(""))
            recalcProfile?.ifStripCountifsRows += 1
            continue
          }
          recalcProfile?.ifBlankEqualityFastHits += 1
          emitColumnCountifPickRow(
            plan: countifPickPlan,
            guardRef: guardRef,
            master: master,
            origin: origin,
            sink: sink
          )
        }
        return true
      }
      if let countifsExpr = stripCountifsKernelExpr(branchExpr),
        let countifsPlan = makeColumnCOUNTIFSPlan(countifsExpr, master: master)
      {
        for origin in members {
          prepareForCellEvaluation(origin: origin)
          if ifBlankGuardIsActive(ifGuard, master: master, origin: origin) {
            recalcProfile?.ifBlankEqualityFastHits += 1
            sink(origin, .string(""))
            continue
          }
          recalcProfile?.ifBlankEqualityFastHits += 1
          emitColumnCOUNTIFSRow(plan: countifsPlan, master: master, origin: origin, sink: sink)
          recalcProfile?.ifStripCountifsRows += 1
        }
        return true
      }
    }
    #if DEBUG
      if let profile = recalcProfile {
        let missReason = diagnoseIfStripBranchKernelMiss(
          branchExpr, ifGuard: ifGuard, master: master)
        profile.recordIfStripPlanMiss(missReason)
        if missReason == "otherBranch", let diag = stripPlanDiagnosticContext {
          let rejectCode = diagnoseIfStripOtherBranchReject(
            branch: branchExpr,
            ifGuard: ifGuard,
            master: master
          )
          profile.recordIfStripOtherBranch(
            sheet: diag.sheetName,
            masterA1: master.a1,
            formula: diag.masterFormulaText,
            rejectCode: rejectCode
          )
        }
      }
    #endif
    return false
  }

  private func evaluateColumnCOUNTIFSStrip(
    master: CellAddress,
    members: [CellAddress],
    expr: FormulaExpr,
    sink: (CellAddress, CellValue) -> Void
  ) -> Bool {
    guard let plan = makeColumnCOUNTIFSPlan(expr, master: master) else { return false }
    for origin in members {
      emitColumnCOUNTIFSRow(plan: plan, master: master, origin: origin, sink: sink)
    }
    return true
  }

  private func evaluateColumnIFERRORVlookupStrip(
    master: CellAddress,
    members: [CellAddress],
    expr: FormulaExpr,
    sink: (CellAddress, CellValue) -> Void
  ) -> Bool {
    guard let plan = makeColumnIFERRORVlookupPlan(expr, master: master) else { return false }
    for origin in members {
      emitColumnIFERRORVlookupRow(plan: plan, master: master, origin: origin, sink: sink)
    }
    return true
  }
}
