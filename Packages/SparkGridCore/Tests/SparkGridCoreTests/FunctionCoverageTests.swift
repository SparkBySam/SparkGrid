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
