import FileFormats
import Formula
import Foundation
import Functions
import GridCore
import Model
import NumberFormat
import Rendering
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
    // A rounding difference never shows as "-0".
    if case .number(let zero) = FormulaProbe.eval("ROUNDDOWN(-0.004,2)") {
      XCTAssertEqual(zero.sign, .plus)
    } else {
      XCTFail("ROUNDDOWN(-0.004,2) is a number")
    }
    var currency = CellFormat()
    currency.numberFormat = .currency
    XCTAssertFalse(
      CellFormatRenderer.displayText(for: .number(-0.0), format: currency, fallbackRaw: "")
        .contains("-"))
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
    "INDIRECT": Sample(
      formula: "INDIRECT(\"B\"&2)", expect: .value(.number(9)),
      numbers: ["B1": 7, "B2": 9, "B3": 3]),
    "ADDRESS": Sample(formula: "ADDRESS(2, 3, 4)", expect: .value(.string("C2"))),
    "ISREF": Sample(formula: "ISREF(A1)", expect: .value(.bool(true))),
    "ISFORMULA": Sample(formula: "ISFORMULA(A1)", expect: .value(.bool(false))),
    "CELL": Sample(formula: "CELL(\"row\", B5)", expect: .value(.number(5))),
    "PERCENTILE.EXC": Sample(formula: "PERCENTILE.EXC({1,2,3,4}, 0.2)", expect: .value(.number(1))),
    "QUARTILE.EXC": Sample(formula: "QUARTILE.EXC({1,2,3,4,5,6,7}, 1)", expect: .value(.number(2))),
    "OFFSET": Sample(
      formula: "SUM(OFFSET(B1, 1, 0, 2))", expect: .value(.number(12)),
      numbers: ["B1": 7, "B2": 9, "B3": 3]),
    "LOOKUP": Sample(
      formula: "LOOKUP(5, A1:A3, B1:B3)", expect: .value(.number(9)),
      numbers: ["A1": 1, "A2": 4, "A3": 8, "B1": 7, "B2": 9, "B3": 3]),
    "YEARFRAC": Sample(formula: "YEARFRAC(45292, 45658, 3)", expect: .value(.number(366.0 / 365))),
    "XMATCH": Sample(
      formula: "XMATCH(2, A1:A3, 0)",
      expect: .value(.number(2)),
      numbers: ["A1": 1, "A2": 2, "A3": 3]
    ),
    "YEAR": Sample(formula: "YEAR(DATE(2020, 6, 15))", expect: .value(.number(2020))),
    // 1.4 batch 2
    "PMT": Sample(
      formula: "PMT(0.05/12, 360, 200000)", expect: .numberBetween(-1073.65, -1073.64)),
    "IPMT": Sample(
      formula: "IPMT(0.1/12, 1, 36, 8000)", expect: .numberBetween(-66.67, -66.66)),
    "PPMT": Sample(
      formula: "PPMT(0.1/12, 1, 24, 2000)", expect: .numberBetween(-75.63, -75.61)),
    "FV": Sample(
      formula: "FV(0.06/12, 10, -200, -500, 1)", expect: .numberBetween(2581.4, 2581.41)),
    "PV": Sample(
      formula: "PV(0.08/12, 240, 500)", expect: .numberBetween(-59777.16, -59777.14)),
    "NPER": Sample(
      formula: "NPER(0.12/12, -100, -1000, 10000, 1)", expect: .numberBetween(59.673, 59.674)),
    "RATE": Sample(
      formula: "RATE(48, -200, 8000)", expect: .numberBetween(0.0077014, 0.0077015)),
    "NPV": Sample(
      formula: "NPV(0.1, -10000, 3000, 4200, 6800)", expect: .numberBetween(1188.43, 1188.45)),
    "IRR": Sample(
      formula: "IRR(A1:A6)", expect: .numberBetween(0.08663, 0.08664),
      numbers: ["A1": -70000, "A2": 12000, "A3": 15000, "A4": 18000, "A5": 21000, "A6": 26000]),
    "XNPV": Sample(
      formula: "XNPV(0.09, A1:A5, B1:B5)", expect: .numberBetween(2086.64, 2086.66),
      numbers: [
        "A1": -10000, "A2": 2750, "A3": 4250, "A4": 3250, "A5": 2750, "B1": 39448, "B2": 39508,
        "B3": 39751, "B4": 39859, "B5": 39904,
      ]),
    "XIRR": Sample(
      formula: "XIRR(A1:A5, B1:B5)", expect: .numberBetween(0.37336, 0.37337),
      numbers: [
        "A1": -10000, "A2": 2750, "A3": 4250, "A4": 3250, "A5": 2750, "B1": 39448, "B2": 39508,
        "B3": 39751, "B4": 39859, "B5": 39904,
      ]),
    "DAYS": Sample(
      formula: "DAYS(45000, 44900)", expect: .value(.number(100))),
    "DATEDIF": Sample(
      formula: "DATEDIF(DATE(2001,6,1), DATE(2002,8,15), \"YD\")", expect: .value(.number(75))),
    "NETWORKDAYS": Sample(
      formula: "NETWORKDAYS(DATE(2012,10,1), DATE(2013,3,1), A1)", expect: .value(.number(109)),
      numbers: ["A1": 41235]),
    "WORKDAY": Sample(
      formula: "WORKDAY(DATE(2008,10,1), 151)", expect: .value(.number(39933))),
    "WEEKNUM": Sample(
      formula: "WEEKNUM(DATE(2012,3,9), 2)", expect: .value(.number(11))),
    "ISOWEEKNUM": Sample(
      formula: "ISOWEEKNUM(DATE(2012,3,9))", expect: .value(.number(10))),
    "STDEV": Sample(
      formula: "STDEV(A1:A8)", expect: .numberBetween(2.13808, 2.13809),
      numbers: ["A1": 2, "A2": 4, "A3": 4, "A4": 4, "A5": 5, "A6": 5, "A7": 7, "A8": 9]),
    "STDEV.S": Sample(
      formula: "STDEV.S(A1:A8)", expect: .numberBetween(2.13808, 2.13809),
      numbers: ["A1": 2, "A2": 4, "A3": 4, "A4": 4, "A5": 5, "A6": 5, "A7": 7, "A8": 9]),
    "STDEVP": Sample(
      formula: "STDEVP(A1:A8)", expect: .value(.number(2)),
      numbers: ["A1": 2, "A2": 4, "A3": 4, "A4": 4, "A5": 5, "A6": 5, "A7": 7, "A8": 9]),
    "STDEV.P": Sample(
      formula: "STDEV.P(A1:A8)", expect: .value(.number(2)),
      numbers: ["A1": 2, "A2": 4, "A3": 4, "A4": 4, "A5": 5, "A6": 5, "A7": 7, "A8": 9]),
    "VAR": Sample(
      formula: "VAR(A1:A8)", expect: .numberBetween(4.5714, 4.5715),
      numbers: ["A1": 2, "A2": 4, "A3": 4, "A4": 4, "A5": 5, "A6": 5, "A7": 7, "A8": 9]),
    "VAR.S": Sample(
      formula: "VAR.S(A1:A8)", expect: .numberBetween(4.5714, 4.5715),
      numbers: ["A1": 2, "A2": 4, "A3": 4, "A4": 4, "A5": 5, "A6": 5, "A7": 7, "A8": 9]),
    "VARP": Sample(
      formula: "VARP(A1:A8)", expect: .value(.number(4)),
      numbers: ["A1": 2, "A2": 4, "A3": 4, "A4": 4, "A5": 5, "A6": 5, "A7": 7, "A8": 9]),
    "VAR.P": Sample(
      formula: "VAR.P(A1:A8)", expect: .value(.number(4)),
      numbers: ["A1": 2, "A2": 4, "A3": 4, "A4": 4, "A5": 5, "A6": 5, "A7": 7, "A8": 9]),
    "PERCENTILE": Sample(
      formula: "PERCENTILE(A1:A4, 0.3)", expect: .numberBetween(1.8999999, 1.9000001),
      numbers: ["A1": 1, "A2": 2, "A3": 3, "A4": 4]),
    "PERCENTILE.INC": Sample(
      formula: "PERCENTILE.INC(A1:A4, 0.3)", expect: .numberBetween(1.8999999, 1.9000001),
      numbers: ["A1": 1, "A2": 2, "A3": 3, "A4": 4]),
    "QUARTILE": Sample(
      formula: "QUARTILE(A1:A8, 1)", expect: .value(.number(3.5)),
      numbers: ["A1": 1, "A2": 2, "A3": 4, "A4": 7, "A5": 8, "A6": 9, "A7": 10, "A8": 12]),
    "QUARTILE.INC": Sample(
      formula: "QUARTILE.INC(A1:A8, 3)", expect: .value(.number(9.25)),
      numbers: ["A1": 1, "A2": 2, "A3": 4, "A4": 7, "A5": 8, "A6": 9, "A7": 10, "A8": 12]),
    "MODE": Sample(
      formula: "MODE(5.6, 4, 4, 3, 2, 4)", expect: .value(.number(4))),
    "MODE.SNGL": Sample(
      formula: "MODE.SNGL(1, 2, 2, 3, 3)", expect: .value(.number(2))),
    "CORREL": Sample(
      formula: "CORREL(A1:A5, B1:B5)", expect: .numberBetween(0.997054, 0.997055),
      numbers: [
        "A1": 3, "A2": 2, "A3": 4, "A4": 5, "A5": 6, "B1": 9, "B2": 7, "B3": 12, "B4": 15, "B5": 17,
      ]),
    "SLOPE": Sample(
      formula: "SLOPE(A1:A7, B1:B7)", expect: .numberBetween(0.305555, 0.305556),
      numbers: [
        "A1": 2, "A2": 3, "A3": 9, "A4": 1, "A5": 8, "A6": 7, "A7": 5, "B1": 6, "B2": 5, "B3": 11,
        "B4": 7, "B5": 5, "B6": 4, "B7": 4,
      ]),
    "INTERCEPT": Sample(
      formula: "INTERCEPT(A1:A5, B1:B5)", expect: .numberBetween(0.048387, 0.048388),
      numbers: [
        "A1": 2, "A2": 3, "A3": 9, "A4": 1, "A5": 8, "B1": 6, "B2": 5, "B3": 11, "B4": 7, "B5": 5,
      ]),
    "FORECAST": Sample(
      formula: "FORECAST(30, A1:A5, B1:B5)", expect: .numberBetween(10.60725, 10.60726),
      numbers: [
        "A1": 6, "A2": 7, "A3": 9, "A4": 15, "A5": 21,
        "B1": 20, "B2": 28, "B3": 31, "B4": 38, "B5": 40,
      ]),
    "FORECAST.LINEAR": Sample(
      formula: "FORECAST.LINEAR(30, A1:A5, B1:B5)", expect: .numberBetween(10.60725, 10.60726),
      numbers: [
        "A1": 6, "A2": 7, "A3": 9, "A4": 15, "A5": 21,
        "B1": 20, "B2": 28, "B3": 31, "B4": 38, "B5": 40,
      ]),
    "COUNTUNIQUE": Sample(
      formula: "COUNTUNIQUE(1, 1, 2, \"a\", \"A\")", expect: .value(.number(3))),
    "SUMSQ": Sample(
      formula: "SUMSQ(3, 4)", expect: .value(.number(25))),
    "MROUND": Sample(
      formula: "MROUND(1.3, 0.2)", expect: .value(.number(1.4))),
    "TRUNC": Sample(
      formula: "TRUNC(-8.9)", expect: .value(.number(-8))),
    "EXP": Sample(
      formula: "EXP(1)", expect: .numberBetween(2.718281, 2.718282)),
    "LN": Sample(
      formula: "LN(86)", expect: .numberBetween(4.454347, 4.454348)),
    "LOG": Sample(
      formula: "LOG(8, 2)", expect: .value(.number(3))),
    "LOG10": Sample(
      formula: "LOG10(100)", expect: .value(.number(2))),
    "FACT": Sample(
      formula: "FACT(5)", expect: .value(.number(120))),
    "GCD": Sample(
      formula: "GCD(24, 36)", expect: .value(.number(12))),
    "LCM": Sample(
      formula: "LCM(5, 2)", expect: .value(.number(10))),
    "EVEN": Sample(
      formula: "EVEN(-1)", expect: .value(.number(-2))),
    "ODD": Sample(
      formula: "ODD(2)", expect: .value(.number(3))),
    "SWITCH": Sample(
      formula: "SWITCH(2, 1, \"a\", 2, \"b\")", expect: .value(.string("b"))),
    "CHOOSE": Sample(
      formula: "CHOOSE(2, \"a\", \"b\")", expect: .value(.string("b"))),
    "XOR": Sample(
      formula: "XOR(TRUE, FALSE, TRUE, TRUE)", expect: .value(.bool(true))),
    "ISEVEN": Sample(
      formula: "ISEVEN(2.5)", expect: .value(.bool(true))),
    "ISODD": Sample(
      formula: "ISODD(-5)", expect: .value(.bool(true))),
    "ISLOGICAL": Sample(
      formula: "ISLOGICAL(FALSE)", expect: .value(.bool(true))),
    "ISNA": Sample(
      formula: "ISNA(NA())", expect: .value(.bool(true))),
    "ISERR": Sample(
      formula: "ISERR(NA())", expect: .value(.bool(false))),
    "NA": Sample(
      formula: "NA()", expect: .value(.error(.na))),
    "TEXTBEFORE": Sample(
      formula: "TEXTBEFORE(\"Little Red Riding Hood's red hood\", \"hood\")",
      expect: .value(.string("Little Red Riding Hood's red "))),
    "REGEXTEST": Sample(
      formula: "REGEXTEST(\"Hello World\", \"world\", 1)", expect: .value(.bool(true))),
    "REGEXEXTRACT": Sample(
      formula: "REGEXEXTRACT(\"Order 12-B\", \"\\d+\")", expect: .value(.string("12"))),
    "REGEXREPLACE": Sample(
      formula: "REGEXREPLACE(\"Hello World\", \"(\\w+) (\\w+)\", \"$2 $1\")",
      expect: .value(.string("World Hello"))),
    "TEXTAFTER": Sample(
      formula: "TEXTAFTER(\"Little Red Riding Hood's red hood\", \"HOOD\", -1, 1)",
      expect: .value(.string(""))),
    "CLEAN": Sample(
      formula: "CLEAN(CHAR(9) & \"Monthly\" & CHAR(10))", expect: .value(.string("Monthly"))),
    "CODE": Sample(
      formula: "CODE(\"A\")", expect: .value(.number(65))),
    "UNICODE": Sample(
      formula: "UNICODE(\"B\")", expect: .value(.number(66))),
    "UNICHAR": Sample(
      formula: "UNICHAR(66)", expect: .value(.string("B"))),
    // No pivot table in this sheet: GETPIVOTDATA reports #REF!, as other apps do.
    "GETPIVOTDATA": Sample(
      formula: "GETPIVOTDATA(\"Sum of Amount\", A1)", expect: .value(.error(.ref))),
    "HYPERLINK": Sample(
      formula: "HYPERLINK(\"https://example.com\", \"Site\")", expect: .value(.string("Site"))),
    // A spilling result shows its first value in the formula's cell.
    "FILTER": Sample(
      formula: "FILTER(SEQUENCE(3), SEQUENCE(3) > 1)", expect: .value(.number(2))),
    "SORT": Sample(formula: "SORT(SEQUENCE(3, 1, 3, -1))", expect: .value(.number(1))),
    "SORTBY": Sample(
      formula: "SORTBY(SEQUENCE(3), SEQUENCE(3, 1, 3, -1))", expect: .value(.number(3))),
    "UNIQUE": Sample(formula: "UNIQUE(SEQUENCE(2))", expect: .value(.number(1))),
    "LET": Sample(formula: "LET(x, 2, y, x * 3, x + y)", expect: .value(.number(8))),
    "VSTACK": Sample(formula: "VSTACK(5, SEQUENCE(2))", expect: .value(.number(5))),
    "HSTACK": Sample(formula: "HSTACK(SEQUENCE(2), 7)", expect: .value(.number(1))),
    "TAKE": Sample(formula: "TAKE(SEQUENCE(5), -2)", expect: .value(.number(4))),
    "DROP": Sample(formula: "DROP(SEQUENCE(5), 3)", expect: .value(.number(4))),
    "CHOOSECOLS": Sample(
      formula: "CHOOSECOLS(SEQUENCE(2, 3), -1)", expect: .value(.number(3))),
    "CHOOSEROWS": Sample(
      formula: "CHOOSEROWS(SEQUENCE(3, 2), 2)", expect: .value(.number(3))),
    "WRAPROWS": Sample(formula: "WRAPROWS(SEQUENCE(5), 2)", expect: .value(.number(1))),
    "WRAPCOLS": Sample(formula: "WRAPCOLS(SEQUENCE(5, 1, 9), 2)", expect: .value(.number(9))),
    "TOCOL": Sample(formula: "TOCOL(SEQUENCE(2, 2, 6))", expect: .value(.number(6))),
    "TOROW": Sample(formula: "TOROW(SEQUENCE(2, 2, 6), 0, TRUE)", expect: .value(.number(6))),
    "TEXTSPLIT": Sample(
      formula: "TEXTSPLIT(\"North, South\", \", \")", expect: .value(.string("North"))),
    "RANDARRAY": Sample(formula: "RANDARRAY(2, 2, 5, 9)", expect: .numberBetween(5, 9)),
    // 1.5 batch 3
    "SIN": Sample(formula: "SIN(0)", expect: .value(.number(0))),
    "COS": Sample(formula: "COS(0)", expect: .value(.number(1))),
    "TAN": Sample(formula: "TAN(0)", expect: .value(.number(0))),
    "ASIN": Sample(formula: "ASIN(2)", expect: .value(.error(.num))),
    "ACOS": Sample(formula: "ACOS(1)", expect: .value(.number(0))),
    "ATAN": Sample(formula: "ATAN(0)", expect: .value(.number(0))),
    "ATAN2": Sample(formula: "ATAN2(0, 0)", expect: .value(.error(.divZero))),
    "SINH": Sample(formula: "SINH(0)", expect: .value(.number(0))),
    "COSH": Sample(formula: "COSH(0)", expect: .value(.number(1))),
    "TANH": Sample(formula: "TANH(0)", expect: .value(.number(0))),
    "ASINH": Sample(formula: "ASINH(0)", expect: .value(.number(0))),
    "ACOSH": Sample(formula: "ACOSH(1)", expect: .value(.number(0))),
    "ATANH": Sample(formula: "ATANH(1)", expect: .value(.error(.num))),
    "DEGREES": Sample(formula: "DEGREES(PI())", expect: .value(.number(180))),
    "RADIANS": Sample(formula: "RADIANS(180)", expect: .numberBetween(3.14159, 3.1416)),
    "SQRTPI": Sample(formula: "SQRTPI(-1)", expect: .value(.error(.num))),
    "COMBIN": Sample(formula: "COMBIN(8, 2)", expect: .value(.number(28))),
    "PERMUT": Sample(formula: "PERMUT(5, 2)", expect: .value(.number(20))),
    "QUOTIENT": Sample(formula: "QUOTIENT(-7, 2)", expect: .value(.number(-3))),
    "RAND": Sample(formula: "RAND()", expect: .numberBetween(0, 1)),
    "RANDBETWEEN": Sample(formula: "RANDBETWEEN(3, 3)", expect: .value(.number(3))),
    "AVERAGEA": Sample(
      formula: "AVERAGEA(A1:A3)", expect: .value(.number(1)),
      numbers: ["A1": 2], text: ["A2": "x"]),
    "MAXA": Sample(formula: "MAXA(-1, -2)", expect: .value(.number(-1))),
    "MINA": Sample(
      formula: "MINA(A1:A2)", expect: .value(.number(0)),
      numbers: ["A1": 5], text: ["A2": "x"]),
    "STDEVA": Sample(formula: "STDEVA(1, 3)", expect: .numberBetween(1.4142, 1.4143)),
    "STDEVPA": Sample(formula: "STDEVPA(1, 3)", expect: .value(.number(1))),
    "VARA": Sample(formula: "VARA(1, 3)", expect: .value(.number(2))),
    "VARPA": Sample(formula: "VARPA(1, 3)", expect: .value(.number(1))),
    "GEOMEAN": Sample(formula: "GEOMEAN(2, 8)", expect: .value(.number(4))),
    "HARMEAN": Sample(formula: "HARMEAN(1, 1)", expect: .value(.number(1))),
    "DEVSQ": Sample(formula: "DEVSQ(1, 2, 3)", expect: .value(.number(2))),
    "AVEDEV": Sample(formula: "AVEDEV(1, 3)", expect: .value(.number(1))),
    "SKEW": Sample(formula: "SKEW(1, 2, 3)", expect: .value(.number(0))),
    "SKEW.P": Sample(formula: "SKEW.P(1, 2, 3)", expect: .value(.number(0))),
    "KURT": Sample(formula: "KURT(1, 2)", expect: .value(.error(.divZero))),
    "TRIMMEAN": Sample(formula: "TRIMMEAN({1,2,3,100}, 0.5)", expect: .value(.number(2.5))),
    "STANDARDIZE": Sample(formula: "STANDARDIZE(12, 10, 2)", expect: .value(.number(1))),
    "FISHER": Sample(formula: "FISHER(0)", expect: .value(.number(0))),
    "FISHERINV": Sample(formula: "FISHERINV(0)", expect: .value(.number(0))),
    "COVARIANCE.S": Sample(formula: "COVARIANCE.S({1,2,3},{2,4,6})", expect: .value(.number(2))),
    "COVARIANCE.P": Sample(
      formula: "COVARIANCE.P({1,2,3},{2,4,6})", expect: .numberBetween(1.3333, 1.3334)),
    "COVAR": Sample(formula: "COVAR({1,2,3},{2,4,6})", expect: .numberBetween(1.3333, 1.3334)),
    "PEARSON": Sample(
      formula: "PEARSON({1,2,3},{2,4,6})", expect: .numberBetween(0.99999, 1.00001)),
    "RSQ": Sample(formula: "RSQ({2,4,6},{1,2,3})", expect: .numberBetween(0.99999, 1.00001)),
    "RANK.AVG": Sample(formula: "RANK.AVG(5, {5,5,9})", expect: .value(.number(2.5))),
    "PERCENTRANK": Sample(formula: "PERCENTRANK({1,2,3,4,5}, 2)", expect: .value(.number(0.25))),
    "PERCENTRANK.INC": Sample(
      formula: "PERCENTRANK.INC({1,2,3,4,5}, 2.5)", expect: .value(.number(0.375))),
    "PERCENTRANK.EXC": Sample(
      formula: "PERCENTRANK.EXC({1,2,3,4,5}, 2)", expect: .value(.number(0.333))),
    "NORM.DIST": Sample(formula: "NORM.DIST(0, 0, 1, TRUE)", expect: .value(.number(0.5))),
    "NORMDIST": Sample(formula: "NORMDIST(0, 0, 1, TRUE)", expect: .value(.number(0.5))),
    "NORM.S.DIST": Sample(formula: "NORM.S.DIST(0, TRUE)", expect: .value(.number(0.5))),
    "NORMSDIST": Sample(formula: "NORMSDIST(0)", expect: .value(.number(0.5))),
    "NORM.INV": Sample(formula: "NORM.INV(0.5, 10, 2)", expect: .numberBetween(9.99999, 10.00001)),
    "NORMINV": Sample(formula: "NORMINV(0.5, 10, 2)", expect: .numberBetween(9.99999, 10.00001)),
    "NORM.S.INV": Sample(formula: "NORM.S.INV(0.975)", expect: .numberBetween(1.95996, 1.95997)),
    "NORMSINV": Sample(formula: "NORMSINV(0.975)", expect: .numberBetween(1.95996, 1.95997)),
    "REPLACE": Sample(
      formula: "REPLACE(\"abcdef\", 3, 2, \"XY\")", expect: .value(.string("abXYef"))),
    "FIXED": Sample(formula: "FIXED(1234.567, 1)", expect: .value(.string("1,234.6"))),
    "DOLLAR": Sample(formula: "DOLLAR(-1234.567)", expect: .value(.string("($1,234.57)"))),
    "T": Sample(formula: "T(12)", expect: .value(.string(""))),
    "NUMBERVALUE": Sample(
      formula: "NUMBERVALUE(\"1.234,5\", \",\", \".\")", expect: .value(.number(1234.5))),
    "TIME": Sample(formula: "TIME(18, 0, 0)", expect: .value(.number(0.75))),
    "TIMEVALUE": Sample(formula: "TIMEVALUE(\"6:00 PM\")", expect: .value(.number(0.75))),
    "DATEVALUE": Sample(formula: "DATEVALUE(\"1/1/2026\")", expect: .value(.number(46023))),
    "DAYS360": Sample(formula: "DAYS360(46023, 46053)", expect: .value(.number(30))),
    "N": Sample(formula: "N(TRUE)", expect: .value(.number(1))),
    "ISNONTEXT": Sample(formula: "ISNONTEXT(5)", expect: .value(.bool(true))),
    "TYPE": Sample(formula: "TYPE(\"a\")", expect: .value(.number(2))),
    "ERROR.TYPE": Sample(formula: "ERROR.TYPE(1/0)", expect: .value(.number(2))),
    "SLN": Sample(formula: "SLN(1000, 100, 9)", expect: .value(.number(100))),
    "SYD": Sample(formula: "SYD(1000, 100, 3, 1)", expect: .value(.number(450))),
    "DDB": Sample(formula: "DDB(1000, 100, 4, 1)", expect: .value(.number(500))),
    "DB": Sample(formula: "DB(1000, 100, 4, 1)", expect: .value(.number(438))),
    "EFFECT": Sample(formula: "EFFECT(0.1, 1)", expect: .numberBetween(0.09999, 0.10001)),
    "NOMINAL": Sample(formula: "NOMINAL(0.1, 1)", expect: .numberBetween(0.09999, 0.10001)),
    "ISPMT": Sample(formula: "ISPMT(0.1, 0, 2, 100)", expect: .value(.number(-10))),
    "CUMIPMT": Sample(formula: "CUMIPMT(0.1, 2, 100, 1, 1, 0)", expect: .value(.number(-10))),
    "CUMPRINC": Sample(
      formula: "CUMPRINC(0.1, 2, 100, 1, 2, 0)", expect: .numberBetween(-100.0001, -99.9999)),
    // 1.7 batch 7: answers from Excel 16.115.
    "COUPDAYBS": Sample(
      formula: "COUPDAYBS(DATE(2008,2,15),DATE(2017,11,15),2,0)",
      expect: .numberBetween(89.999999909999, 90.000000090001)),
    "COUPDAYS": Sample(
      formula: "COUPDAYS(DATE(2008,2,15),DATE(2017,11,15),2,0)",
      expect: .numberBetween(179.999999819999, 180.000000180001)),
    "COUPDAYSNC": Sample(
      formula: "COUPDAYSNC(DATE(2008,2,15),DATE(2017,11,15),2,0)",
      expect: .numberBetween(89.999999909999, 90.000000090001)),
    "COUPNCD": Sample(
      formula: "COUPNCD(DATE(2008,2,15),DATE(2017,11,15),2,1)",
      expect: .numberBetween(39582.999960417, 39583.000039583)),
    "COUPNUM": Sample(
      formula: "COUPNUM(DATE(2008,2,15),DATE(2017,11,15),2,1)",
      expect: .numberBetween(19.999999979999, 20.000000020001)),
    "COUPPCD": Sample(
      formula: "COUPPCD(DATE(2008,2,15),DATE(2017,11,15),2,1)",
      expect: .numberBetween(39400.999960599, 39401.000039401)),
    "PRICE": Sample(
      formula: "PRICE(DATE(2008,2,15),DATE(2017,11,15),0.0575,0.065,100,2,0)",
      expect: .numberBetween(94.63436152668675, 94.63436171595745)),
    "YIELD": Sample(
      formula: "YIELD(DATE(2008,2,15),DATE(2017,11,15),0.0575,95.04287,100,2,0)",
      expect: .numberBetween(0.06440961166613587, 0.06440961179695512)),
    "DURATION": Sample(
      formula: "DURATION(DATE(2008,2,15),DATE(2017,11,15),0.08,0.09,2,0)",
      expect: .numberBetween(6.704496332562293, 6.704496345973286)),
    "MDURATION": Sample(
      formula: "MDURATION(DATE(2024,1,31),DATE(2030,8,31),0.08,0.09,4,0)",
      expect: .numberBetween(4.956466315621324, 4.956466325536256)),
    "ACCRINT": Sample(
      formula: "ACCRINT(DATE(2008,3,1),DATE(2008,8,31),DATE(2008,5,1),0.1,1000,2,0)",
      expect: .numberBetween(16.666666649999033, 16.666666683334366)),
    "ACCRINTM": Sample(
      formula: "ACCRINTM(DATE(2008,4,1),DATE(2008,6,15),0.1,1000,3)",
      expect: .numberBetween(20.54794518493056, 20.547945226028443)),
    "DISC": Sample(
      formula: "DISC(DATE(2018,1,25),DATE(2018,6,15),97.975,100,1)",
      expect: .numberBetween(0.05242021271253749, 0.052420212819377913)),
    "INTRATE": Sample(
      formula: "INTRATE(DATE(2008,2,15),DATE(2008,5,15),1000000,1014420,2)",
      expect: .numberBetween(0.057679999941320004, 0.05768000005868)),
    "RECEIVED": Sample(
      formula: "RECEIVED(DATE(2008,2,15),DATE(2008,5,15),1000000,0.0575,2)",
      expect: .numberBetween(1014584.6533925154, 1014584.6554216847)),
    "PRICEDISC": Sample(
      formula: "PRICEDISC(DATE(2008,2,16),DATE(2008,3,1),0.0525,100,2)",
      expect: .numberBetween(99.79583323353648, 99.79583343313013)),
    "YIELDDISC": Sample(
      formula: "YIELDDISC(DATE(2008,2,16),DATE(2008,3,1),99.795,100,2)",
      expect: .numberBetween(0.05282257193303573, 0.052822572040680874)),
    "PRICEMAT": Sample(
      formula: "PRICEMAT(DATE(2008,2,15),DATE(2008,4,13),DATE(2007,11,11),0.061,0.061,0)",
      expect: .numberBetween(99.9844987755714, 99.9844989755424)),
    "YIELDMAT": Sample(
      formula: "YIELDMAT(DATE(2008,3,15),DATE(2008,11,3),DATE(2007,11,8),0.0625,100.0123,0)",
      expect: .numberBetween(0.06095433362958437, 0.06095433375349303)),
    "TBILLPRICE": Sample(
      formula: "TBILLPRICE(DATE(2008,3,31),DATE(2008,6,1),0.09)",
      expect: .numberBetween(98.449999901549, 98.450000098451)),
    "TBILLYIELD": Sample(
      formula: "TBILLYIELD(DATE(2008,3,31),DATE(2008,6,1),98.45)",
      expect: .numberBetween(0.09141696283292564, 0.09141696301775956)),
    "TBILLEQ": Sample(
      formula: "TBILLEQ(DATE(2008,3,31),DATE(2008,6,1),0.0914)",
      expect: .numberBetween(0.0941514934707915, 0.0941514936610945)),
    "VDB": Sample(
      formula: "VDB(2400,300,10,0,1)", expect: .numberBetween(479.999999519999, 480.000000480001)),
    "AMORLINC": Sample(
      formula: "AMORLINC(2400,DATE(2008,8,19),DATE(2008,12,31),300,1,0.15,1)",
      expect: .numberBetween(359.999999639999, 360.000000360001)),
    "AMORDEGRC": Sample(
      formula: "AMORDEGRC(2400,DATE(2008,8,19),DATE(2008,12,31),300,1,0.15,1)",
      expect: .numberBetween(775.999999223999, 776.000000776001)),
    "FVSCHEDULE": Sample(
      formula: "FVSCHEDULE(1,{0.09,0.11,0.1})",
      expect: .numberBetween(1.3308899986681098, 1.33089000133189)),
    "DOLLARDE": Sample(
      formula: "DOLLARDE(1.02,16)", expect: .numberBetween(1.1249999988739998, 1.1250000011260002)),
    "DOLLARFR": Sample(
      formula: "DOLLARFR(1.125,16)", expect: .numberBetween(1.0199999989789998, 1.0200000010210002)),
    "PDURATION": Sample(
      formula: "PDURATION(0.025,2000,2200)",
      expect: .numberBetween(3.8598661587617937, 3.8598661664835263)),
    "RRI": Sample(
      formula: "RRI(96,10000,11000)",
      expect: .numberBetween(0.0009933073742980226, 0.0009933073782846375)),
    "CONVERT": Sample(
      formula: "CONVERT(68,\"F\",\"C\")", expect: .numberBetween(19.999999979999, 20.000000020001)),
    "COMPLEX": Sample(formula: "COMPLEX(3,4)", expect: .value(.string("3+4i"))),
    "BESSELJ": Sample(
      formula: "BESSELJ(1.9,2)", expect: .numberBetween(0.3299192301522116, 0.3299324271873584)),
    "BESSELY": Sample(
      formula: "BESSELY(2.5,1)", expect: .numberBetween(0.14591521914456285, 0.14592105587206317)),
    "BESSELI": Sample(
      formula: "BESSELI(1.5,1)", expect: .numberBetween(0.9816467951455966, 0.9816860618047355)),
    "BESSELK": Sample(
      formula: "BESSELK(1.5,1)", expect: .numberBetween(0.2773822558751864, 0.27739335138933163)),
    "IMABS": Sample(
      formula: "IMABS(\"5+12i\")", expect: .numberBetween(12.999999986999, 13.000000013001)),
    "IMAGINARY": Sample(
      formula: "IMAGINARY(\"3+4i\")", expect: .numberBetween(3.999999995999, 4.000000004001)),
    "IMARGUMENT": Sample(
      formula: "IMARGUMENT(\"3+4i\")",
      expect: .numberBetween(0.9272952170733167, 0.9272952189299072)),
    "IMCONJUGATE": Sample(formula: "IMCONJUGATE(\"3+4i\")", expect: .value(.string("3-4i"))),
    "IMCOS": Sample(
      formula: "IMCOS(\"1+i\")", expect: .value(.string("0.833730025131149-0.988897705762865i"))),
    "IMCOSH": Sample(
      formula: "IMCOSH(\"4+3i\")", expect: .value(.string("-27.0349456030742+3.85115333481178i"))),
    "IMCOT": Sample(
      formula: "IMCOT(\"4+3i\")", expect: .value(.string("0.00490118239430447-0.999266927805902i"))),
    "IMCSC": Sample(
      formula: "IMCSC(\"4+3i\")", expect: .value(.string("-0.0754898329158637+0.0648774713706355i"))
    ),
    "IMCSCH": Sample(
      formula: "IMCSCH(\"4+3i\")", expect: .value(.string("-0.036275889628626-0.0051744731840194i"))
    ),
    "IMEXP": Sample(
      formula: "IMEXP(\"1+i\")", expect: .value(.string("1.46869393991589+2.28735528717884i"))),
    "IMLN": Sample(
      formula: "IMLN(\"3+4i\")", expect: .value(.string("1.6094379124341+0.927295218001612i"))),
    "IMLOG10": Sample(
      formula: "IMLOG10(\"3+4i\")", expect: .value(.string("0.698970004336019+0.402719196273373i"))),
    "IMLOG2": Sample(
      formula: "IMLOG2(\"3+4i\")", expect: .value(.string("2.32192809488736+1.33780421245098i"))),
    "IMREAL": Sample(
      formula: "IMREAL(\"6-9i\")", expect: .numberBetween(5.999999993999, 6.000000006001)),
    "IMSEC": Sample(
      formula: "IMSEC(\"4+3i\")", expect: .value(.string("-0.0652940278579471-0.0752249603027732i"))
    ),
    "IMSECH": Sample(
      formula: "IMSECH(\"4+3i\")",
      expect: .value(.string("-0.0362534969158689-0.00516434460775318i"))),
    "IMSIN": Sample(
      formula: "IMSIN(\"4+3i\")", expect: .value(.string("-7.61923172032141-6.548120040911i"))),
    "IMSINH": Sample(
      formula: "IMSINH(\"4+3i\")", expect: .value(.string("-27.0168132580039+3.85373803791938i"))),
    "IMSQRT": Sample(
      formula: "IMSQRT(\"1+i\")", expect: .value(.string("1.09868411346781+0.455089860562227i"))),
    "IMTAN": Sample(
      formula: "IMTAN(\"4+3i\")", expect: .value(.string("0.00490825806749606+1.00070953606723i"))),
    "IMDIV": Sample(formula: "IMDIV(\"-238+240i\",\"10+24i\")", expect: .value(.string("5+12i"))),
    "IMSUB": Sample(formula: "IMSUB(\"13+4i\",\"5+3i\")", expect: .value(.string("8+i"))),
    "IMPOWER": Sample(
      formula: "IMPOWER(\"2+3i\",3)", expect: .value(.string("-46+9.00000000000001i"))),
    "IMPRODUCT": Sample(formula: "IMPRODUCT(\"3+4i\",\"5-3i\")", expect: .value(.string("27+11i"))),
    "IMSUM": Sample(formula: "IMSUM(\"3+4i\",\"5-3i\")", expect: .value(.string("8+i"))),
    // 1.7 batch 6
    "LAMBDA": Sample(formula: "LAMBDA(x, x + 1)", expect: .value(.error(.calc))),
    "MAP": Sample(formula: "SUM(MAP({1,2,3}, LAMBDA(x, x * x)))", expect: .value(.number(14))),
    "REDUCE": Sample(
      formula: "REDUCE(0, {1,2,3}, LAMBDA(a, b, a + b))", expect: .value(.number(6))),
    "SCAN": Sample(
      formula: "SUM(SCAN(0, {1,2,3}, LAMBDA(a, b, a + b)))", expect: .value(.number(10))),
    "BYROW": Sample(
      formula: "SUM(BYROW({1,2;3,4}, LAMBDA(r, MAX(r))))", expect: .value(.number(6))),
    "BYCOL": Sample(formula: "SUM(BYCOL({1,2;3,4}, SUM))", expect: .value(.number(10))),
    "MAKEARRAY": Sample(
      formula: "SUM(MAKEARRAY(2, 2, LAMBDA(r, c, r * c)))", expect: .value(.number(9))),
    "ISOMITTED": Sample(formula: "ISOMITTED(1)", expect: .value(.bool(false))),
    "EXPAND": Sample(formula: "ROWS(EXPAND({1;2}, 4))", expect: .value(.number(4))),
    "GROUPBY": Sample(
      formula: "ROWS(GROUPBY({\"a\";\"b\";\"a\"}, {1;2;3}, SUM))", expect: .value(.number(3))),
    "PIVOTBY": Sample(
      formula: "ROWS(PIVOTBY({\"a\";\"b\"}, {\"x\";\"y\"}, {1;2}, SUM))", expect: .value(.number(4))
    ),
    // 1.7 batch 5: answers from Excel 16.115 where the formula needs no cells.
    "BETA.DIST": Sample(
      formula: "BETA.DIST(2,8,10,TRUE,1,3)",
      expect: .numberBetween(0.6854705803682164, 0.6854705817411575)),
    "BETA.INV": Sample(
      formula: "BETA.INV(0.685470581,8,10,1,3)",
      expect: .numberBetween(1.99999999796214, 2.00000000196414)),
    "BETADIST": Sample(
      formula: "BETADIST(2,8,10,1,3)",
      expect: .numberBetween(0.6854705803682164, 0.6854705817411575)),
    "BETAINV": Sample(
      formula: "BETAINV(0.2,4,5)", expect: .numberBetween(0.30322584435985617, 0.3032258449683078)),
    "BINOM.DIST": Sample(
      formula: "BINOM.DIST(6,10,0.5,FALSE)",
      expect: .numberBetween(0.20507812479392187, 0.20507812520607813)),
    "BINOMDIST": Sample(
      formula: "BINOMDIST(3,8,0.3,TRUE)",
      expect: .numberBetween(0.8058956491931043, 0.8058956508068956)),
    "BINOM.DIST.RANGE": Sample(
      formula: "BINOM.DIST.RANGE(60,0.75,48)",
      expect: .numberBetween(0.08397496734407253, 0.08397496751402247)),
    "BINOM.INV": Sample(
      formula: "BINOM.INV(6,0.5,0.75)", expect: .numberBetween(3.999999995999, 4.000000004001)),
    "CRITBINOM": Sample(
      formula: "CRITBINOM(100,0.2,0.9)",
      expect: .numberBetween(24.999999974999003, 25.000000025000997)),
    "NEGBINOM.DIST": Sample(
      formula: "NEGBINOM.DIST(10,5,0.25,TRUE)",
      expect: .numberBetween(0.31351405816366296, 0.313514058792691)),
    "NEGBINOMDIST": Sample(
      formula: "NEGBINOMDIST(10,5,0.25)",
      expect: .numberBetween(0.05504866031912924, 0.05504866043122656)),
    "HYPGEOM.DIST": Sample(
      formula: "HYPGEOM.DIST(1,4,8,20,TRUE)",
      expect: .numberBetween(0.46542827610735876, 0.4654282770402152)),
    "HYPGEOMDIST": Sample(
      formula: "HYPGEOMDIST(1,4,8,20)",
      expect: .numberBetween(0.36326109354698793, 0.36326109427551007)),
    "POISSON.DIST": Sample(
      formula: "POISSON.DIST(2,5,TRUE)",
      expect: .numberBetween(0.12465201935742896, 0.12465201960873303)),
    "POISSON": Sample(
      formula: "POISSON(0,0,FALSE)", expect: .numberBetween(0.999999998999, 1.0000000010010002)),
    "EXPON.DIST": Sample(
      formula: "EXPON.DIST(0.2,10,TRUE)",
      expect: .numberBetween(0.8646647158977223, 0.8646647176290516)),
    "EXPONDIST": Sample(
      formula: "EXPONDIST(1,0.5,TRUE)",
      expect: .numberBetween(0.39346933989289773, 0.3934693406818363)),
    "WEIBULL.DIST": Sample(
      formula: "WEIBULL.DIST(105,20,100,TRUE)",
      expect: .numberBetween(0.9295813891386956, 0.9295813909998584)),
    "WEIBULL": Sample(
      formula: "WEIBULL(1,2,3,TRUE)",
      expect: .numberBetween(0.10516068307946931, 0.1051606832917907)),
    "GAMMA.DIST": Sample(
      formula: "GAMMA.DIST(10.00001131,9,2,FALSE)",
      expect: .numberBetween(0.03263913038465487, 0.032639130451933125)),
    "GAMMADIST": Sample(
      formula: "GAMMADIST(3,0.5,1,TRUE)",
      expect: .numberBetween(0.985694120577876, 0.9856941225512641)),
    "GAMMA.INV": Sample(
      formula: "GAMMA.INV(0.068094,9,2)",
      expect: .numberBetween(10.000011181436188, 10.00001120143821)),
    "GAMMAINV": Sample(
      formula: "GAMMAINV(0.5,0.5,1)",
      expect: .numberBetween(0.22746821133131778, 0.22746821178825422)),
    "CHISQ.DIST": Sample(
      formula: "CHISQ.DIST(0.5,1,TRUE)",
      expect: .numberBetween(0.5204998772915471, 0.5204998783345468)),
    "CHISQ.DIST.RT": Sample(
      formula: "CHISQ.DIST.RT(18.307,10)",
      expect: .numberBetween(0.05000058904039752, 0.05000058914239869)),
    "CHIDIST": Sample(
      formula: "CHIDIST(3.84,1)", expect: .numberBetween(0.05004352119766158, 0.050043521299748615)),
    "CHISQ.INV": Sample(
      formula: "CHISQ.INV(0.93,1)", expect: .numberBetween(3.28302028347551, 3.28302029004355)),
    "CHISQ.INV.RT": Sample(
      formula: "CHISQ.INV.RT(0.050001,10)",
      expect: .numberBetween(18.306973438653127, 18.30697347526907)),
    "CHIINV": Sample(
      formula: "CHIINV(0.05,1)", expect: .numberBetween(3.8414588168516612, 3.841458824536579)),
    "F.DIST": Sample(
      formula: "F.DIST(15.2069,6,4,TRUE)",
      expect: .numberBetween(0.990000042011763, 0.9900000439937631)),
    "F.DIST.RT": Sample(
      formula: "F.DIST.RT(15.2069,6,4)",
      expect: .numberBetween(0.009999956986237351, 0.009999957008237267)),
    "FDIST": Sample(
      formula: "FDIST(2,3,10)", expect: .numberBetween(0.1780074071961686, 0.17800740755418343)),
    "F.INV": Sample(
      formula: "F.INV(0.01,6,4)", expect: .numberBetween(0.10930991401426908, 0.10930991423488891)),
    "F.INV.RT": Sample(
      formula: "F.INV.RT(0.01,6,4)", expect: .numberBetween(15.206864845949635, 15.206864876365366)),
    "FINV": Sample(
      formula: "FINV(0.05,2,20)", expect: .numberBetween(3.492828473241801, 3.4928284802294587)),
    "LOGNORM.DIST": Sample(
      formula: "LOGNORM.DIST(4,3.5,1.2,TRUE)",
      expect: .numberBetween(0.039083555666716945, 0.039083555746884054)),
    "LOGNORMDIST": Sample(
      formula: "LOGNORMDIST(4,3.5,1.2)",
      expect: .numberBetween(0.039083555666716945, 0.039083555746884054)),
    "LOGNORM.INV": Sample(
      formula: "LOGNORM.INV(0.039084,3.5,1.2)",
      expect: .numberBetween(4.0000252146796145, 4.000025222681665)),
    "LOGINV": Sample(
      formula: "LOGINV(0.5,0,1)", expect: .numberBetween(0.999999998999, 1.0000000010010002)),
    "T.DIST": Sample(
      formula: "T.DIST(60,1,TRUE)", expect: .numberBetween(0.9946953253716817, 0.9946953273630723)),
    "T.DIST.2T": Sample(
      formula: "T.DIST.2T(1.959999998,60)",
      expect: .numberBetween(0.05464492992027607, 0.054644930031565925)),
    "T.DIST.RT": Sample(
      formula: "T.DIST.RT(1.959999998,60)",
      expect: .numberBetween(0.027322464959638037, 0.02732246501628296)),
    "TDIST": Sample(
      formula: "TDIST(1.96,60,2)", expect: .numberBetween(0.05464492968088437, 0.054644929792174224)
    ),
    "T.INV": Sample(
      formula: "T.INV(0.75,2)", expect: .numberBetween(0.8164965801102295, 0.8164965817452225)),
    "T.INV.2T": Sample(
      formula: "T.INV.2T(0.546449,60)", expect: .numberBetween(0.606533075218226, 0.606533076433292)
    ),
    "TINV": Sample(
      formula: "TINV(0.05,3)", expect: .numberBetween(3.1824463021002636, 3.1824463084671564)),
    "CONFIDENCE.NORM": Sample(
      formula: "CONFIDENCE.NORM(0.05,2.5,50)",
      expect: .numberBetween(0.6929519114808871, 0.6929519128687909)),
    "CONFIDENCE": Sample(
      formula: "CONFIDENCE(0.05,2.5,50)",
      expect: .numberBetween(0.6929519114808871, 0.6929519128687909)),
    "CONFIDENCE.T": Sample(
      formula: "CONFIDENCE.T(0.05,1,50)",
      expect: .numberBetween(0.2841968552105332, 0.2841968557809268)),
    "MDETERM": Sample(
      formula: "MDETERM({3,6,1;1,1,0;3,10,2})",
      expect: .numberBetween(0.999999998999, 1.0000000010010002)),
    "CHISQ.TEST": Sample(
      formula: "CHISQ.TEST({10,20}, {15,15})", expect: .numberBetween(0.0678, 0.0680)),
    "CHITEST": Sample(formula: "CHITEST({10,20}, {15,15})", expect: .numberBetween(0.0678, 0.0680)),
    "F.TEST": Sample(formula: "F.TEST({1,2,3,4}, {2,4,6,9})", expect: .numberBetween(0.0, 1.0)),
    "FTEST": Sample(formula: "FTEST({1,2,3,4}, {2,4,6,9})", expect: .numberBetween(0.0, 1.0)),
    "T.TEST": Sample(
      formula: "T.TEST({1,2,3,4}, {2,4,6,9}, 2, 2)", expect: .numberBetween(0.0, 1.0)),
    "TTEST": Sample(formula: "TTEST({1,2,3,4}, {2,4,6,9}, 2, 2)", expect: .numberBetween(0.0, 1.0)),
    "Z.TEST": Sample(formula: "Z.TEST({1,2,3,4}, 2.5)", expect: .numberBetween(0.4999, 0.5001)),
    "ZTEST": Sample(formula: "ZTEST({1,2,3,4}, 2.5)", expect: .numberBetween(0.4999, 0.5001)),
    "PROB": Sample(
      formula: "PROB({0,1,2,3}, {0.2,0.3,0.1,0.4}, 2)", expect: .numberBetween(0.0999, 0.1001)),
    "STEYX": Sample(formula: "STEYX({2,4,5,9}, {1,2,3,4})", expect: .numberBetween(0.0, 10.0)),
    "FREQUENCY": Sample(formula: "FREQUENCY({1,5,9}, {4})", expect: .value(.number(1))),
    "MODE.MULT": Sample(formula: "MODE.MULT({1,2,2,3})", expect: .value(.number(2))),
    "LINEST": Sample(
      formula: "LINEST({2,4,6}, {1,2,3})", expect: .numberBetween(1.9999999, 2.0000001)),
    "LOGEST": Sample(
      formula: "LOGEST({2,4,8}, {1,2,3})", expect: .numberBetween(1.9999999, 2.0000001)),
    "TREND": Sample(
      formula: "TREND({2,4,6}, {1,2,3}, 4)", expect: .numberBetween(7.9999999, 8.0000001)),
    "GROWTH": Sample(
      formula: "GROWTH({2,4,8}, {1,2,3}, 4)", expect: .numberBetween(15.999999, 16.000001)),
    "MMULT": Sample(formula: "MMULT({1,2}, {3;4})", expect: .value(.number(11))),
    "MINVERSE": Sample(formula: "MINVERSE({2,0;0,4})", expect: .value(.number(0.5))),
    "MUNIT": Sample(formula: "MUNIT(2)", expect: .value(.number(1))),
    // 1.7 batch 4: answers from Excel 16.115 where the formula needs no cells.
    "NETWORKDAYS.INTL": Sample(
      formula: "NETWORKDAYS.INTL(45658,45688)",
      expect: .numberBetween(22.999999976999003, 23.000000023000997)),
    "WORKDAY.INTL": Sample(
      formula: "WORKDAY.INTL(45658,10)", expect: .numberBetween(45671.999954328, 45672.000045672)),
    "SHEET": Sample(formula: "SHEET()", expect: .numberBetween(0.999999998999, 1.0000000010010002)),
    "SHEETS": Sample(
      formula: "SHEETS()", expect: .value(.number(1))),
    "COT": Sample(
      formula: "COT(1)", expect: .numberBetween(0.6420926152912384, 0.6420926165774236)),
    "CSC": Sample(
      formula: "CSC(1)", expect: .numberBetween(1.1883951045887247, 1.1883951069675152)),
    "SEC": Sample(formula: "SEC(1)", expect: .numberBetween(1.850815715829114, 1.8508157195327457)),
    "COTH": Sample(
      formula: "COTH(1)", expect: .numberBetween(1.3130352841852946, 1.3130352868133652)),
    "CSCH": Sample(
      formula: "CSCH(1)", expect: .numberBetween(0.8509181273874039, 0.8509181290912401)),
    "SECH": Sample(
      formula: "SECH(1)", expect: .numberBetween(0.6480542730148308, 0.6480542743129393)),
    "ACOT": Sample(
      formula: "ACOT(2)", expect: .numberBetween(0.4636476085361584, 0.4636476094654536)),
    "ACOTH": Sample(
      formula: "ACOTH(3)", expect: .numberBetween(0.3465735899323994, 0.34657359062754656)),
    "CEILING.PRECISE": Sample(
      formula: "CEILING.PRECISE(4.3)",
      expect: .numberBetween(4.9999999949989995, 5.0000000050010005)),
    "ISO.CEILING": Sample(
      formula: "ISO.CEILING(-4.3,2)", expect: .numberBetween(-4.000000004001, -3.999999995999)),
    "FLOOR.PRECISE": Sample(
      formula: "FLOOR.PRECISE(4.3)", expect: .numberBetween(3.999999995999, 4.000000004001)),
    "COMBINA": Sample(
      formula: "COMBINA(4,3)", expect: .numberBetween(19.999999979999, 20.000000020001)),
    "PERMUTATIONA": Sample(
      formula: "PERMUTATIONA(3,2)", expect: .numberBetween(8.999999990999, 9.000000009001)),
    "FACTDOUBLE": Sample(
      formula: "FACTDOUBLE(6)", expect: .numberBetween(47.999999951999, 48.000000048001)),
    "MULTINOMIAL": Sample(
      formula: "MULTINOMIAL(2,3,4)", expect: .numberBetween(1259.999998739999, 1260.000001260001)),
    "SERIESSUM": Sample(
      formula: "SERIESSUM(2,1,2,{1,2,3})",
      expect: .numberBetween(113.999999885999, 114.000000114001)),
    "GAMMA": Sample(
      formula: "GAMMA(5)", expect: .numberBetween(23.999999975999003, 24.000000024000997)),
    "GAMMALN": Sample(
      formula: "GAMMALN(10)", expect: .numberBetween(12.801827467278672, 12.801827492884327)),
    "GAMMALN.PRECISE": Sample(
      formula: "GAMMALN.PRECISE(0.5)",
      expect: .numberBetween(0.5723649423513351, 0.5723649434980649)),
    "GAUSS": Sample(
      formula: "GAUSS(1)", expect: .numberBetween(0.3413447457261983, 0.3413447464108877)),
    "PHI": Sample(
      formula: "PHI(0.75)", expect: .numberBetween(0.30113743185266656, 0.3011374324569414)),
    "ROMAN": Sample(formula: "ROMAN(499)", expect: .value(.string("CDXCIX"))),
    "ARABIC": Sample(
      formula: "ARABIC(\"MCMXCIV\")", expect: .numberBetween(1993.999998005999, 1994.000001994001)),
    "BASE": Sample(formula: "BASE(255,16)", expect: .value(.string("FF"))),
    "DECIMAL": Sample(
      formula: "DECIMAL(\"FF\",16)", expect: .numberBetween(254.999999744999, 255.000000255001)),
    "BIN2DEC": Sample(
      formula: "BIN2DEC(1100100)", expect: .numberBetween(99.99999989999901, 100.00000010000099)),
    "BIN2HEX": Sample(formula: "BIN2HEX(11111011,4)", expect: .value(.string("00FB"))),
    "BIN2OCT": Sample(formula: "BIN2OCT(1001,3)", expect: .value(.string("011"))),
    "OCT2BIN": Sample(formula: "OCT2BIN(3,3)", expect: .value(.string("011"))),
    "OCT2DEC": Sample(
      formula: "OCT2DEC(\"7777777533\")",
      expect: .numberBetween(-165.00000016500098, -164.99999983499902)),
    "OCT2HEX": Sample(formula: "OCT2HEX(100,4)", expect: .value(.string("0040"))),
    "HEX2BIN": Sample(formula: "HEX2BIN(\"F\",8)", expect: .value(.string("00001111"))),
    "HEX2DEC": Sample(
      formula: "HEX2DEC(\"A5\")", expect: .numberBetween(164.99999983499902, 165.00000016500098)),
    "HEX2OCT": Sample(formula: "HEX2OCT(\"3B4E\")", expect: .value(.string("35516"))),
    "DEC2BIN": Sample(formula: "DEC2BIN(9,4)", expect: .value(.string("1001"))),
    "DEC2HEX": Sample(formula: "DEC2HEX(100,4)", expect: .value(.string("0064"))),
    "DEC2OCT": Sample(formula: "DEC2OCT(58,3)", expect: .value(.string("072"))),
    "BITAND": Sample(
      formula: "BITAND(13,25)", expect: .numberBetween(8.999999990999, 9.000000009001)),
    "BITOR": Sample(
      formula: "BITOR(23,10)", expect: .numberBetween(30.999999968999003, 31.000000031000997)),
    "BITXOR": Sample(
      formula: "BITXOR(5,3)", expect: .numberBetween(5.999999993999, 6.000000006001)),
    "BITLSHIFT": Sample(
      formula: "BITLSHIFT(4,2)", expect: .numberBetween(15.999999983999, 16.000000016001)),
    "BITRSHIFT": Sample(
      formula: "BITRSHIFT(13,2)", expect: .numberBetween(2.999999996999, 3.000000003001)),
    "DELTA": Sample(formula: "DELTA(5,4)", expect: .numberBetween(-1e-12, 1e-12)),
    "GESTEP": Sample(
      formula: "GESTEP(5,4)", expect: .numberBetween(0.999999998999, 1.0000000010010002)),
    "ERF": Sample(
      formula: "ERF(0.745)", expect: .numberBetween(0.7079289193868091, 0.707928920804667)),
    "ERF.PRECISE": Sample(
      formula: "ERF.PRECISE(0.5)", expect: .numberBetween(0.5204998772915471, 0.5204998783345468)),
    "ERFC": Sample(
      formula: "ERFC(1)", expect: .numberBetween(0.1572992068919858, 0.1572992072085842)),
    "ERFC.PRECISE": Sample(
      formula: "ERFC.PRECISE(-1)", expect: .numberBetween(1.842700791106009, 1.8427007947934109)),
    "LENB": Sample(
      formula: "LENB(\"abc\")", expect: .numberBetween(2.999999996999, 3.000000003001)),
    "LEFTB": Sample(formula: "LEFTB(\"abcdef\",2)", expect: .value(.string("ab"))),
    "RIGHTB": Sample(formula: "RIGHTB(\"abcdef\",2)", expect: .value(.string("ef"))),
    "MIDB": Sample(formula: "MIDB(\"abcdef\",2,3)", expect: .value(.string("bcd"))),
    "FINDB": Sample(
      formula: "FINDB(\"c\",\"abcdef\")", expect: .numberBetween(2.999999996999, 3.000000003001)),
    "SEARCHB": Sample(
      formula: "SEARCHB(\"C\",\"abcdef\")", expect: .numberBetween(2.999999996999, 3.000000003001)),
    "REPLACEB": Sample(formula: "REPLACEB(\"abcdef\",2,3,\"X\")", expect: .value(.string("aXef"))),
    "ASC": Sample(formula: "ASC(\"ＡＢＣ１２３\")", expect: .value(.string("ＡＢＣ１２３"))),
    "DBCS": Sample(formula: "DBCS(\"ABC\")", expect: .value(.string("ABC"))),
    "VALUETOTEXT": Sample(formula: "VALUETOTEXT(\"abc\")", expect: .value(.string("abc"))),
    "ARRAYTOTEXT": Sample(
      formula: "ARRAYTOTEXT({1,2;3,\"x\"},1)", expect: .value(.string("{1,2;3,\"x\"}"))),
    "BAHTTEXT": Sample(
      formula: "BAHTTEXT(1234.5)", expect: .value(.string("หนึ่งพันสองร้อยสามสิบสี่บาทห้าสิบสตางค์"))),
    "SUBTOTAL": Sample(
      formula: "SUBTOTAL(9, A1:A3)", expect: .value(.number(6)),
      numbers: ["A1": 1, "A2": 2, "A3": 3]),
    "DAVERAGE": Sample(
      formula: "DAVERAGE({\"N\",\"V\";\"a\",2;\"b\",4;\"a\",6}, \"V\", {\"N\";\"a\"})",
      expect: .value(.number(4))),
    "DCOUNT": Sample(
      formula: "DCOUNT({\"N\",\"V\";\"a\",2;\"b\",4;\"a\",6}, \"V\", {\"N\";\"a\"})",
      expect: .value(.number(2))),
    "DCOUNTA": Sample(
      formula: "DCOUNTA({\"N\",\"V\";\"a\",2;\"b\",4;\"a\",6}, , {\"N\";\"b\"})",
      expect: .value(.number(1))),
    "DGET": Sample(
      formula: "DGET({\"N\",\"V\";\"a\",2;\"b\",4;\"a\",6}, \"V\", {\"N\";\"b\"})",
      expect: .value(.number(4))),
    "DMAX": Sample(
      formula: "DMAX({\"N\",\"V\";\"a\",2;\"b\",4;\"a\",6}, \"V\", {\"N\";\"a\"})",
      expect: .value(.number(6))),
    "DMIN": Sample(
      formula: "DMIN({\"N\",\"V\";\"a\",2;\"b\",4;\"a\",6}, \"V\", {\"N\";\"a\"})",
      expect: .value(.number(2))),
    "DPRODUCT": Sample(
      formula: "DPRODUCT({\"N\",\"V\";\"a\",2;\"b\",4;\"a\",6}, \"V\", {\"N\";\"a\"})",
      expect: .value(.number(12))),
    "DSTDEV": Sample(
      formula: "DSTDEV({\"N\",\"V\";\"a\",2;\"b\",4;\"a\",6}, 2, {\"N\";\"a\"})",
      expect: .numberBetween(2.8284, 2.8285)),
    "DSTDEVP": Sample(
      formula: "DSTDEVP({\"N\",\"V\";\"a\",2;\"b\",4;\"a\",6}, 2, {\"N\";\"a\"})",
      expect: .value(.number(2))),
    "DSUM": Sample(
      formula: "DSUM({\"N\",\"V\";\"a\",2;\"b\",4;\"a\",6}, \"V\", {\"N\";\"a\"})",
      expect: .value(.number(8))),
    "DVAR": Sample(
      formula: "DVAR({\"N\",\"V\";\"a\",2;\"b\",4;\"a\",6}, 2, {\"N\";\"a\"})",
      expect: .value(.number(8))),
    "DVARP": Sample(
      formula: "DVARP({\"N\",\"V\";\"a\",2;\"b\",4;\"a\",6}, 2, {\"N\";\"a\"})",
      expect: .value(.number(4))),
    "FORMULATEXT": Sample(formula: "FORMULATEXT(A1)", expect: .value(.error(.na))),
    "AREAS": Sample(formula: "AREAS(A1:B2)", expect: .value(.number(1))),
    "ENCODEURL": Sample(formula: "ENCODEURL(\"a b\")", expect: .value(.string("a%20b"))),
    "AGGREGATE": Sample(formula: "AGGREGATE(14, 6, {1,5,3}, 1)", expect: .value(.number(5))),
    "SUMX2MY2": Sample(formula: "SUMX2MY2({1,2}, {3,4})", expect: .value(.number(-20))),
    "SUMX2PY2": Sample(formula: "SUMX2PY2({1,2}, {3,4})", expect: .value(.number(30))),
    "SUMXMY2": Sample(formula: "SUMXMY2({1,2}, {3,4})", expect: .value(.number(8))),
    "MIRR": Sample(formula: "MIRR({-100,110}, 0.1, 0.1)", expect: .numberBetween(0.09999, 0.10001)),
    "TRANSPOSE": Sample(formula: "TRANSPOSE({7,8})", expect: .value(.number(7))),
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

/// Batch 2 details beyond the one sample per function, and the `_xlfn.` mark on save.
@MainActor
final class FunctionBatch2Tests: XCTestCase {
  private func number(_ formula: String, _ numbers: [String: Double] = [:]) -> Double? {
    FormulaProbe.eval(formula, numbers: numbers).asNumber
  }

  func testDatedifUnits() {
    let span = "DATE(2001,6,1), DATE(2002,8,15)"
    XCTAssertEqual(number("DATEDIF(\(span), \"Y\")"), 1)
    XCTAssertEqual(number("DATEDIF(\(span), \"M\")"), 14)
    XCTAssertEqual(number("DATEDIF(\(span), \"D\")"), 440)
    XCTAssertEqual(number("DATEDIF(\(span), \"YM\")"), 2)
    XCTAssertEqual(number("DATEDIF(\(span), \"MD\")"), 14)
    XCTAssertEqual(
      FormulaProbe.eval("DATEDIF(DATE(2002,1,1), DATE(2001,1,1), \"D\")"), .error(.num))
  }

  func testWorkingDays() {
    XCTAssertEqual(number("NETWORKDAYS(DATE(2012,10,1), DATE(2013,3,1))"), 110)
    XCTAssertEqual(number("NETWORKDAYS(DATE(2013,3,1), DATE(2012,10,1))"), -110)
    // Friday plus one working day is Monday.
    XCTAssertEqual(number("WORKDAY(DATE(2026,11,6), 1)"), number("DATE(2026,11,9)"))
    XCTAssertEqual(number("WORKDAY(DATE(2026,11,9), -1)"), number("DATE(2026,11,6)"))
  }

  func testWeekNumbers() {
    XCTAssertEqual(number("WEEKNUM(DATE(2012,3,9))"), 10)
    XCTAssertEqual(number("ISOWEEKNUM(DATE(2021,1,1))"), 53)
    XCTAssertEqual(number("WEEKNUM(DATE(2021,1,1), 21)"), 53)
  }

  func testLoanPartsAddUpToThePayment() {
    let pmt = number("PMT(0.1/12, 24, 2000)") ?? 0
    let ipmt = number("IPMT(0.1/12, 5, 24, 2000)") ?? 0
    let ppmt = number("PPMT(0.1/12, 5, 24, 2000)") ?? 0
    XCTAssertEqual(ipmt + ppmt, pmt, accuracy: 1e-9)
    XCTAssertEqual(number("PMT(0, 10, 1000)"), -100)
  }

  func testNameThatLooksLikeACell() {
    XCTAssertEqual(number("LOG10(1000)"), 3)
  }

  func testTextAroundOptions() {
    XCTAssertEqual(
      FormulaProbe.eval("TEXTAFTER(\"a-b-c\", \"-\", 2)"), .string("c"))
    XCTAssertEqual(
      FormulaProbe.eval("TEXTBEFORE(\"a-b-c\", \"-\", -1)"), .string("a-b"))
    XCTAssertEqual(FormulaProbe.eval("TEXTBEFORE(\"abc\", \"x\")"), .error(.na))
    XCTAssertEqual(
      FormulaProbe.eval("TEXTBEFORE(\"abc\", \"x\", 1, 0, 0, \"none\")"), .string("none"))
  }

  func testSwitchDefaultAndNoMatch() {
    XCTAssertEqual(FormulaProbe.eval("SWITCH(9, 1, \"a\", \"other\")"), .string("other"))
    XCTAssertEqual(FormulaProbe.eval("SWITCH(9, 1, \"a\")"), .error(.na))
  }

  func testNewerFunctionsGetTheExcelPrefixOnSave() {
    XCTAssertEqual(
      ExcelFutureFunctions.prefixed("XLOOKUP(A1,B:B,C:C)+SUM(A1:A3)"),
      "_xlfn.XLOOKUP(A1,B:B,C:C)+SUM(A1:A3)")
    XCTAssertEqual(
      ExcelFutureFunctions.prefixed("IFS(A1>1,\"DAYS(\",TRUE,stdev.s(B1:B3))"),
      "_xlfn.IFS(A1>1,\"DAYS(\",TRUE,_xlfn.stdev.s(B1:B3))")
    XCTAssertEqual(
      ExcelFutureFunctions.prefixed("_xlfn.XLOOKUP(A1,'IFS(x'!A:A,B:B)"),
      "_xlfn.XLOOKUP(A1,'IFS(x'!A:A,B:B)")
  }
}
