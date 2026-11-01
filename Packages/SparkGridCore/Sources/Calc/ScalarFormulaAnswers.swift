import Formula
import Foundation
import Functions
import GridCore
import Model
import NumberFormat

/// Answer oracle: every formula cell through a fresh scalar `FormulaEvaluator`.
///
/// No shape strips, no aggregate-range cache, and no lookup-table cache. Each
/// formula is parsed and passed to `evaluate` once. Dependencies resolve through
/// the same evaluator, including cross-sheet references. Imported cached results
/// are ignored.
public enum ScalarFormulaAnswers {
  public struct CellAnswer {
    public var sheetIndex: Int
    public var sheetName: String
    public var address: CellAddress
    public var value: CellValue
  }

  public static func evaluate(
    workbook: Workbook,
    progress: ((Int) -> Void)? = nil
  ) -> [CellAnswer] {
    let oracle = Oracle(workbook: workbook)
    var answers: [CellAnswer] = []
    var seen = 0
    for sheetIndex in workbook.sheets.indices {
      let sheet = workbook.sheets[sheetIndex]
      let addresses = sheet.cells.keys.filter { address in
        FormulaSyntax.isFormula(sheet.cell(at: address).raw)
      }.sorted()
      for address in addresses {
        let value = oracle.value(sheetIndex: sheetIndex, address: address)
        answers.append(
          CellAnswer(
            sheetIndex: sheetIndex,
            sheetName: sheet.name,
            address: address,
            value: value
          ))
        seen += 1
        if seen % 5000 == 0 {
          progress?(seen)
        }
      }
    }
    progress?(seen)
    return answers
  }

  public static func encode(_ value: CellValue) -> String {
    switch value {
    case .number(let number):
      return "n:" + String(format: "%.12g", number)
    case .string(let text):
      let escaped =
        text
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\n", with: "\\n")
        .replacingOccurrences(of: "\t", with: "\\t")
      return "s:" + escaped
    case .bool(let flag):
      return flag ? "b:1" : "b:0"
    case .blank:
      return "z"
    case .error(let error):
      return "e:" + error.displayCode
    }
  }

  public static func same(_ lhs: CellValue, _ rhs: CellValue) -> Bool {
    if lhs == rhs { return true }
    if case .number(let left) = lhs, case .number(let right) = rhs {
      let scale = max(1.0, abs(left), abs(right))
      return abs(left - right) <= 1e-9 * scale
    }
    return false
  }

  public static func write(
    _ answers: [CellAnswer],
    label: String,
    mismatches: Int,
    to url: URL
  ) throws {
    var lines = [
      "# scalar FormulaEvaluator answers",
      "# no shape strips, no aggregate-range cache, no lookup-table cache",
      "# label \(label)",
      "# formulas \(answers.count)",
      "# path-mismatches \(mismatches)",
      "sheet\ta1\tvalue",
    ]
    lines.reserveCapacity(answers.count + 6)
    for answer in answers {
      lines.append("\(answer.sheetName)\t\(answer.address.a1)\t\(encode(answer.value))")
    }
    let text = lines.joined(separator: "\n") + "\n"
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data(text.utf8).write(to: url, options: .atomic)
  }

  private final class Oracle {
    public let workbook: Workbook
    private var memo: [[CellAddress: CellValue]]
    private var visiting: Set<Visit> = []

    public struct Visit: Hashable {
      public var sheet: Int
      public var address: CellAddress
    }

    public init(workbook: Workbook) {
      self.workbook = workbook
      memo = Array(repeating: [:], count: workbook.sheets.count)
    }

    public func value(sheetIndex: Int, address: CellAddress) -> CellValue {
      if let cached = memo[sheetIndex][address] { return cached }
      let visit = Visit(sheet: sheetIndex, address: address)
      if visiting.contains(visit) {
        return .error(.cycle)
      }
      let raw = workbook.sheets[sheetIndex].cell(at: address).raw
      guard FormulaSyntax.isFormula(raw) else {
        let literal = CellValue.fromLiteralRaw(raw)
        memo[sheetIndex][address] = literal
        return literal
      }
      visiting.insert(visit)
      defer { visiting.remove(visit) }
      let value: CellValue
      do {
        let expr = try FormulaParser.parse(raw)
        var evaluator = FormulaEvaluator { [weak self] ref in
          guard let self else { return .blank }
          return self.resolve(ref, activeSheet: sheetIndex)
        }
        evaluator.evaluationOrigin = address
        evaluator.namedRangeLookup = { [weak self] name in
          self?.namedRangeExpression(name)
        }
        evaluator.sheetExtent = { [weak self] name in
          self?.extent(named: name, activeSheet: sheetIndex) ?? (maxRow: 999, maxCol: 25)
        }
        value = evaluator.evaluate(expr)
      } catch {
        value = .error(.error)
      }
      memo[sheetIndex][address] = value
      return value
    }

    private func resolve(_ ref: FormulaRef, activeSheet: Int) -> CellValue {
      let sheetIndex: Int
      if let name = ref.sheet {
        guard let found = indexOfSheet(named: name) else { return .error(.ref) }
        sheetIndex = found
      } else {
        sheetIndex = activeSheet
      }
      if ref.isRowOpen || ref.isColOpen {
        return .error(.ref)
      }
      return value(sheetIndex: sheetIndex, address: ref.address)
    }

    private func indexOfSheet(named name: String) -> Int? {
      workbook.sheets.firstIndex { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    private func extent(named name: String?, activeSheet: Int) -> (maxRow: Int, maxCol: Int) {
      let index = name.flatMap { indexOfSheet(named: $0) } ?? activeSheet
      guard workbook.sheets.indices.contains(index) else { return (999, 25) }
      let sheet = workbook.sheets[index]
      return (
        maxRow: max(0, sheet.effectiveRowCount - 1),
        maxCol: max(0, sheet.effectiveColumnCount - 1)
      )
    }

    private func namedRangeExpression(_ name: String) -> FormulaExpr? {
      guard let named = workbook.namedRange(named: name), named.resolvesToRange else { return nil }
      let start = FormulaRef(
        sheet: named.sheetName,
        row: named.startRow,
        col: named.startCol,
        absRow: false,
        absCol: false
      )
      let end = FormulaRef(
        sheet: named.sheetName,
        row: named.endRow,
        col: named.endCol,
        absRow: false,
        absCol: false
      )
      if start.row == end.row, start.col == end.col {
        return .cellRef(start)
      }
      return .range(start, end)
    }
  }
}
