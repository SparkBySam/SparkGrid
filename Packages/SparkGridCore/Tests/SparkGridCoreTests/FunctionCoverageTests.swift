import Formula
import Foundation
import Functions
import GridCore
import XCTest

@testable import Calc

@MainActor
final class FunctionCoverageTests: XCTestCase {
  func testEveryPresentFunctionHasACase() throws {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let markdown = try String(
      contentsOf: root.appendingPathComponent("docs/function-parity.md"),
      encoding: .utf8
    )
    let present = presentFunctionNames(in: markdown)
    XCTAssertFalse(present.isEmpty)
    let covered = Set(Self.cases.keys)
    let missing = Set(present).subtracting(covered)
    XCTAssertEqual(missing, [], "present functions without a unit test: \(missing.sorted())")
    for name in FormulaFunctions.all {
      XCTAssertNotNil(FormulaFunctionCatalog.entry(named: name), name)
    }
  }

  func testRoundHalfCentsMatchExcel() {
    let halfCent = FormulaProbe.eval("ROUND(5*308.02*0.95,2)")
    XCTAssertTrue(
      AnswerProbe.same(halfCent, .number(1463.10)),
      "half cent -> \(halfCent.displayString)"
    )
    XCTAssertTrue(AnswerProbe.same(FormulaProbe.eval("ROUND(2.5,0)"), .number(3)))
    XCTAssertTrue(AnswerProbe.same(FormulaProbe.eval("ROUND(-2.5,0)"), .number(-3)))
    XCTAssertTrue(AnswerProbe.same(FormulaProbe.eval("ROUND(1.005,2)"), .number(1.01)))
    // The rounded result is the nearest double, so it equals the typed number exactly.
    XCTAssertEqual(FormulaProbe.eval("ROUND(PI(),4)"), .number(3.1416))
    XCTAssertEqual(FormulaProbe.eval("ROUNDUP(PI(),4)"), .number(3.1416))
    XCTAssertEqual(FormulaProbe.eval("ROUNDDOWN(PI(),3)"), .number(3.141))
    XCTAssertTrue(AnswerProbe.same(FormulaProbe.eval("ROUND(1250,-2)"), .number(1300)))
    XCTAssertTrue(AnswerProbe.same(FormulaProbe.eval("ROUND(-1250,-2)"), .number(-1300)))
  }

  func testExcelFutureFunctionPrefix() {
    XCTAssertEqual(
      FormulaProbe.eval("_xlfn.CONCAT(\"North\", \" / \", \"Sage\")"),
      .string("North / Sage")
    )
    XCTAssertEqual(
      FormulaProbe.eval("_xlfn.TEXTJOIN(\", \",TRUE,\"a\",\"b\")"),
      .string("a, b")
    )
    XCTAssertEqual(
      FormulaProbe.eval("_xlfn.IFS(FALSE,\"Low\",TRUE,\"High\")"),
      .string("High")
    )
    XCTAssertEqual(
      FormulaProbe.eval(
        "_xlfn.XLOOKUP(2,A1:A2,B1:B2)",
        numbers: ["A1": 1, "A2": 2, "B1": 10, "B2": 20]
      ),
      .number(20)
    )
    XCTAssertEqual(
      FormulaProbe.eval(
        "_xlfn.XMATCH(2,A1:A2,0)",
        numbers: ["A1": 1, "A2": 2]
      ),
      .number(2)
    )
  }

  func testIndexOnASingleRowUsesTheColumn() {
    XCTAssertEqual(
      FormulaProbe.eval(
        "INDEX(A1:C1,2)",
        numbers: ["A1": 10, "B1": 20, "C1": 30]
      ),
      .number(20)
    )
    XCTAssertEqual(
      FormulaProbe.eval(
        "INDEX(A1:A3,2)",
        numbers: ["A1": 10, "A2": 20, "A3": 30]
      ),
      .number(20)
    )
    XCTAssertEqual(
      FormulaProbe.eval(
        "INDEX(A1:C2,1,3)",
        numbers: ["A1": 1, "B1": 2, "C1": 3, "A2": 4, "B2": 5, "C2": 6]
      ),
      .number(3)
    )
  }

  func testPresentFunctionsEvaluate() {
    for (name, sample) in Self.cases.sorted(by: { $0.key < $1.key }) {
      let value = FormulaProbe.eval(
        sample.formula,
        numbers: sample.numbers,
        text: sample.text
      )
      switch sample.expect {
      case .value(let expected):
        XCTAssertTrue(
          AnswerProbe.same(value, expected),
          "\(name) \(sample.formula) -> \(value.displayString), expected \(expected.displayString)"
        )
      case .numberBetween(let lower, let upper):
        guard case .number(let number) = value else {
          XCTFail("\(name) \(sample.formula) -> \(value.displayString)")
          continue
        }
        XCTAssertGreaterThanOrEqual(number, lower, name)
        XCTAssertLessThan(number, upper, name)
      }
    }
  }

  private func presentFunctionNames(in markdown: String) -> [String] {
    var names: [String] = []
    for raw in markdown.split(separator: "\n") {
      let parts = raw.split(separator: "|").map {
        $0.trimmingCharacters(in: .whitespaces)
      }.filter { !$0.isEmpty }
      guard parts.count >= 3, parts[2] == "yes" else { continue }
      let name = parts[0].trimmingCharacters(in: CharacterSet(charactersIn: "`"))
      guard !name.isEmpty else { continue }
      names.append(name)
    }
    return names
  }

  private struct Sample {
    var formula: String
    var expect: Expectation
    var numbers: [String: Double] = [:]
    var text: [String: String] = [:]
  }

  private enum Expectation {
    case value(CellValue)
    case numberBetween(Double, Double)
  }

  /// Simple inputs. These are not ground truth from a saved Excel, Sheets, or Numbers file.
  private static let cases: [String: Sample] = [
    "INT": Sample(formula: "INT(-2.5)", expect: .value(.number(-3))),
    "SIGN": Sample(formula: "SIGN(-4)", expect: .value(.number(-1))),
    "SQRT": Sample(formula: "SQRT(16)", expect: .value(.number(4))),
    "PI": Sample(formula: "PI()", expect: .numberBetween(3.14159, 3.1416)),
    "MOD": Sample(formula: "MOD(-3, 2)", expect: .value(.number(1))),
    "POWER": Sample(formula: "POWER(2, 10)", expect: .value(.number(1024))),
    "CEILING": Sample(formula: "CEILING(4.2, 0.5)", expect: .value(.number(4.5))),
    "CEILING.MATH": Sample(formula: "CEILING.MATH(4.2)", expect: .value(.number(5))),
    "FLOOR": Sample(formula: "FLOOR(4.7, 0.5)", expect: .value(.number(4.5))),
    "FLOOR.MATH": Sample(formula: "FLOOR.MATH(4.7)", expect: .value(.number(4))),
    "PRODUCT": Sample(
      formula: "PRODUCT(A1:A3)", expect: .value(.number(24)),
      numbers: ["A1": 2, "A2": 3, "A3": 4]),
    "MEDIAN": Sample(
      formula: "MEDIAN(A1:A4)", expect: .value(.number(2.5)),
      numbers: ["A1": 1, "A2": 2, "A3": 3, "A4": 4]),
    "LARGE": Sample(
      formula: "LARGE(A1:A3, 2)", expect: .value(.number(5)),
      numbers: ["A1": 1, "A2": 9, "A3": 5]),
    "SMALL": Sample(
      formula: "SMALL(A1:A3, 2)", expect: .value(.number(5)),
      numbers: ["A1": 1, "A2": 9, "A3": 5]),
    "RANK": Sample(
      formula: "RANK(5, A1:A3)", expect: .value(.number(2)),
      numbers: ["A1": 1, "A2": 9, "A3": 5]),
    "RANK.EQ": Sample(
      formula: "RANK.EQ(5, A1:A3, 1)", expect: .value(.number(2)),
      numbers: ["A1": 1, "A2": 9, "A3": 5]),
    "MAXIFS": Sample(
      formula: "MAXIFS(B1:B3, A1:A3, 1)", expect: .value(.number(7)),
      numbers: ["A1": 1, "A2": 2, "A3": 1, "B1": 7, "B2": 9, "B3": 3]),
    "MINIFS": Sample(
      formula: "MINIFS(B1:B3, A1:A3, 1)", expect: .value(.number(3)),
      numbers: ["A1": 1, "A2": 2, "A3": 1, "B1": 7, "B2": 9, "B3": 3]),
    "PROPER": Sample(formula: "PROPER(\"north WEST\")", expect: .value(.string("North West"))),
    "FIND": Sample(formula: "FIND(\"b\", \"abcb\", 3)", expect: .value(.number(4))),
    "SEARCH": Sample(formula: "SEARCH(\"B?\", \"abcb\")", expect: .value(.number(2))),
    "VALUE": Sample(formula: "VALUE(\"1,250.5\")", expect: .value(.number(1250.5))),
    "EXACT": Sample(formula: "EXACT(\"a\", \"A\")", expect: .value(.bool(false))),
    "ISBLANK": Sample(formula: "ISBLANK(A1)", expect: .value(.bool(true))),
    "ISNUMBER": Sample(formula: "ISNUMBER(4)", expect: .value(.bool(true))),
    "ISTEXT": Sample(formula: "ISTEXT(\"x\")", expect: .value(.bool(true))),
    "ISERROR": Sample(formula: "ISERROR(1/0)", expect: .value(.bool(true))),
    "FALSE": Sample(formula: "FALSE()", expect: .value(.bool(false))),
    "WEEKDAY": Sample(formula: "WEEKDAY(DATE(2026, 10, 29))", expect: .value(.number(5))),
    "HOUR": Sample(formula: "HOUR(0.75)", expect: .value(.number(18))),
    "MINUTE": Sample(formula: "MINUTE(0.5104166667)", expect: .value(.number(15))),
    "SECOND": Sample(formula: "SECOND(0.0000231482)", expect: .value(.number(2))),
    "EDATE": Sample(
      formula: "EDATE(DATE(2026, 1, 31), 1)-DATE(2026, 2, 28)", expect: .value(.number(0))),
    "EOMONTH": Sample(
      formula: "EOMONTH(DATE(2026, 1, 15), 1)-DATE(2026, 2, 28)", expect: .value(.number(0))),
    "ROW": Sample(formula: "ROW(C7)", expect: .value(.number(7))),
    "ROWS": Sample(formula: "ROWS(A2:B9)", expect: .value(.number(8))),
    "COLUMNS": Sample(formula: "COLUMNS(A2:D9)", expect: .value(.number(4))),
    "ABS": Sample(formula: "ABS(-1.5)", expect: .value(.number(1.5))),
    "AND": Sample(formula: "AND(TRUE(), TRUE())", expect: .value(.bool(true))),
    "AVERAGE": Sample(formula: "AVERAGE(2, 4)", expect: .value(.number(3))),
    "AVERAGEIF": Sample(
      formula: "AVERAGEIF(A1:A3, 2, B1:B3)",
      expect: .value(.number(20)),
      numbers: ["A1": 1, "A2": 2, "A3": 2, "B1": 5, "B2": 20, "B3": 20]
    ),
    "AVERAGEIFS": Sample(
      formula: "AVERAGEIFS(C1:C2, A1:A2, 1, B1:B2, 2)",
      expect: .value(.number(8)),
      numbers: ["A1": 1, "A2": 1, "B1": 2, "B2": 3, "C1": 8, "C2": 9]
    ),
    "CHAR": Sample(formula: "CHAR(65)", expect: .value(.string("A"))),
    "COLUMN": Sample(formula: "COLUMN(B1)", expect: .value(.number(2))),
    "CONCAT": Sample(formula: "CONCAT(\"ab\", \"c\")", expect: .value(.string("abc"))),
    "CONCATENATE": Sample(formula: "CONCATENATE(\"a\", \"b\")", expect: .value(.string("ab"))),
    "COUNT": Sample(formula: "COUNT(1, \"a\", 2)", expect: .value(.number(2))),
    "COUNTA": Sample(formula: "COUNTA(1, \"a\")", expect: .value(.number(2))),
    "COUNTBLANK": Sample(
      formula: "COUNTBLANK(A1:A2)",
      expect: .value(.number(1)),
      numbers: ["A1": 1]
    ),
    "COUNTIF": Sample(
      formula: "COUNTIF(A1:A3, 2)",
      expect: .value(.number(2)),
      numbers: ["A1": 2, "A2": 2, "A3": 3]
    ),
    "COUNTIFS": Sample(
      formula: "COUNTIFS(A1:A2, 1, B1:B2, 2)",
      expect: .value(.number(1)),
      numbers: ["A1": 1, "A2": 1, "B1": 2, "B2": 3]
    ),
    "DATE": Sample(formula: "DATE(2020, 6, 15)", expect: .numberBetween(40_000, 50_000)),
    "DAY": Sample(formula: "DAY(DATE(2020, 6, 15))", expect: .value(.number(15))),
    "HLOOKUP": Sample(
      formula: "HLOOKUP(2, A1:C2, 2, FALSE)",
      expect: .value(.number(20)),
      numbers: ["A1": 1, "B1": 2, "C1": 3, "A2": 10, "B2": 20, "C2": 30]
    ),
    "IF": Sample(formula: "IF(TRUE(), 1, 2)", expect: .value(.number(1))),
    "IFERROR": Sample(formula: "IFERROR(1/0, 5)", expect: .value(.number(5))),
    "IFNA": Sample(formula: "IFNA(1, 9)", expect: .value(.number(1))),
    "IFS": Sample(formula: "IFS(FALSE, 1, TRUE(), 2)", expect: .value(.number(2))),
    "INDEX": Sample(
      formula: "INDEX(A1:A3, 2)",
      expect: .value(.number(20)),
      numbers: ["A1": 10, "A2": 20, "A3": 30]
    ),
    "LEFT": Sample(formula: "LEFT(\"abcd\", 2)", expect: .value(.string("ab"))),
    "LEN": Sample(formula: "LEN(\"ab\")", expect: .value(.number(2))),
    "LOWER": Sample(formula: "LOWER(\"Ab\")", expect: .value(.string("ab"))),
    "MATCH": Sample(
      formula: "MATCH(3, A1:A3, 0)",
      expect: .value(.number(2)),
      numbers: ["A1": 1, "A2": 3, "A3": 5]
    ),
    "MAX": Sample(formula: "MAX(3, 1)", expect: .value(.number(3))),
    "MID": Sample(formula: "MID(\"abcd\", 2, 2)", expect: .value(.string("bc"))),
    "MIN": Sample(formula: "MIN(3, 1)", expect: .value(.number(1))),
    "MONTH": Sample(formula: "MONTH(DATE(2020, 6, 15))", expect: .value(.number(6))),
    "NOT": Sample(formula: "NOT(FALSE)", expect: .value(.bool(true))),
    "NOW": Sample(formula: "NOW()", expect: .numberBetween(40_000, 80_000)),
    "OR": Sample(formula: "OR(FALSE, TRUE())", expect: .value(.bool(true))),
    "REPT": Sample(formula: "REPT(\"ab\", 2)", expect: .value(.string("abab"))),
    "RIGHT": Sample(formula: "RIGHT(\"abcd\", 2)", expect: .value(.string("cd"))),
    "ROUND": Sample(formula: "ROUND(1.4)", expect: .value(.number(1))),
    "ROUNDDOWN": Sample(formula: "ROUNDDOWN(1.9, 0)", expect: .value(.number(1))),
    "ROUNDUP": Sample(formula: "ROUNDUP(1.1, 0)", expect: .value(.number(2))),
    "SEQUENCE": Sample(formula: "SEQUENCE(1, 1, 4, 1)", expect: .value(.number(4))),
    "SUBSTITUTE": Sample(
      formula: "SUBSTITUTE(\"a-b-a\", \"a\", \"c\")",
      expect: .value(.string("c-b-c"))
    ),
    "SUM": Sample(formula: "SUM(1, 2, 3)", expect: .value(.number(6))),
    "SUMIF": Sample(
      formula: "SUMIF(A1:A3, 2, B1:B3)",
      expect: .value(.number(40)),
      numbers: ["A1": 1, "A2": 2, "A3": 2, "B1": 5, "B2": 20, "B3": 20]
    ),
    "SUMIFS": Sample(
      formula: "SUMIFS(C1:C2, A1:A2, 1, B1:B2, 2)",
      expect: .value(.number(8)),
      numbers: ["A1": 1, "A2": 1, "B1": 2, "B2": 3, "C1": 8, "C2": 9]
    ),
    "SUMPRODUCT": Sample(
      formula: "SUMPRODUCT(A1:A2, B1:B2)",
      expect: .value(.number(23)),
      numbers: ["A1": 2, "A2": 3, "B1": 4, "B2": 5]
    ),
    "TEXT": Sample(formula: "TEXT(12.5, \"0.00\")", expect: .value(.string("12.50"))),
    "TEXTJOIN": Sample(
      formula: "TEXTJOIN(\",\", TRUE(), \"a\", \"b\")",
      expect: .value(.string("a,b"))
    ),
    "TODAY": Sample(formula: "TODAY()", expect: .numberBetween(40_000, 80_000)),
    "TRIM": Sample(formula: "TRIM(\" a  b \")", expect: .value(.string("a b"))),
    "TRUE": Sample(formula: "TRUE()", expect: .value(.bool(true))),
    "UPPER": Sample(formula: "UPPER(\"Ab\")", expect: .value(.string("AB"))),
    "VLOOKUP": Sample(
      formula: "VLOOKUP(2, A1:B3, 2, FALSE)",
      expect: .value(.number(20)),
      numbers: ["A1": 1, "B1": 10, "A2": 2, "B2": 20, "A3": 3, "B3": 30]
    ),
    "XLOOKUP": Sample(
      formula: "XLOOKUP(2, A1:A3, B1:B3)",
      expect: .value(.number(20)),
      numbers: ["A1": 1, "A2": 2, "A3": 3, "B1": 10, "B2": 20, "B3": 30]
    ),
    "XMATCH": Sample(
      formula: "XMATCH(2, A1:A3, 0)",
      expect: .value(.number(2)),
      numbers: ["A1": 1, "A2": 2, "A3": 3]
    ),
    "YEAR": Sample(formula: "YEAR(DATE(2020, 6, 15))", expect: .value(.number(2020))),
  ]
}

@MainActor
private enum FormulaProbe {
  static func eval(
    _ source: String,
    numbers: [String: Double] = [:],
    text: [String: String] = [:]
  ) -> CellValue {
    let expr: FormulaExpr
    do {
      expr = try FormulaParser.parse(source)
    } catch {
      return .error(.error)
    }
    var grid: [CellAddress: CellValue] = [:]
    for (key, value) in numbers {
      guard let parsed = A1Reference.parseAddress(key) else { continue }
      grid[CellAddress(row: parsed.row, col: parsed.col)] = .number(value)
    }
    for (key, value) in text {
      guard let parsed = A1Reference.parseAddress(key) else { continue }
      grid[CellAddress(row: parsed.row, col: parsed.col)] = .string(value)
    }
    var evaluator = FormulaEvaluator { ref in
      grid[CellAddress(row: ref.row, col: ref.col)] ?? .blank
    }
    evaluator.evaluationOrigin = CellAddress(row: 0, col: 0)
    evaluator.sheetExtent = { _ in (maxRow: 20, maxCol: 10) }
    return evaluator.evaluate(expr)
  }
}

private enum AnswerProbe {
  static func same(_ lhs: CellValue, _ rhs: CellValue) -> Bool {
    if lhs == rhs { return true }
    if case .number(let left) = lhs, case .number(let right) = rhs {
      return abs(left - right) < 1e-9
    }
    return false
  }
}
