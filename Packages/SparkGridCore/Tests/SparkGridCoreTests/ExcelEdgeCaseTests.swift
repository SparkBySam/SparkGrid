import Formula
import GridCore
import XCTest

@testable import Calc

/// Edge cases typed into Excel 16.115 and Spark Grid by script on Nov 18, with Excel's answers.
/// A1:A8 mixes types; B1:B8 numbers with a blank; C1:C8 date serials; D1:D8 short words with wildcard characters.
final class ExcelEdgeCaseTests: XCTestCase {
  private let cells: [String: CellValue] = [
    "A1": .number(5), "A2": .string("apple"), "A4": .bool(true), "A5": .number(-2.5),
    "A6": .string("Apple pie"), "A7": .number(0), "A8": .string("banana"),
    "B1": .number(10), "B2": .number(20), "B3": .number(30), "B5": .number(50),
    "B6": .number(-60), "B7": .number(70.25), "B8": .number(0),
    "C1": .number(45000), "C2": .number(45031), "C3": .number(45291), "C4": .number(45351),
    "C5": .number(1), "C6": .number(60), "C7": .number(61), "C8": .number(2_958_465),
    "H1": .number(1.0), "H2": .number(3.0), "H3": .number(3.0), "H4": .number(7.0),
    "H5": .number(10.0), "H6": .number(15.0), "H7": .number(15.0), "H8": .number(20.0),
    "I1": .string("ant"), "I2": .string("bee"), "I3": .string("cat"), "I4": .string("dog"),
    "I5": .string("eel"), "I6": .string("fox"), "I7": .string("gnu"), "I8": .string("hen"),
    "J1": .number(90.0), "J2": .number(70.0), "J3": .number(50.0), "J4": .number(50.0),
    "J5": .number(30.0), "J6": .number(10.0), "J7": .number(5.0), "J8": .number(1.0),
    "K1": .number(4.0), "K2": .string("x"), "K4": .number(2.0), "K5": .bool(true),
    "K6": .number(9.0), "K7": .string("y"), "K8": .number(6.0),
    "F2": .number(2), "D1": .string("a"), "D2": .string("b*"), "D3": .string("c?d"),
    "D4": .string("~"),
    "D5": .string("ab"), "D6": .string("abc"), "D7": .string("A"), "D8": .string("x"),
  ]

  private func value(_ formula: String) throws -> CellValue {
    let cells = self.cells
    var evaluator = FormulaEvaluator { ref in cells[ref.address.a1] ?? .blank }
    evaluator.holdsFormula = { _, address in address.a1 == "F2" }
    return evaluator.evaluate(try FormulaParser.parse(formula))
  }

  private func check(
    _ cases: [(String, CellValue)], file: StaticString = #filePath, line: UInt = #line
  )
    throws
  {
    for (formula, expected) in cases {
      let got = try value(formula)
      if case .number(let e) = expected, case .number(let g) = got {
        XCTAssertEqual(g, e, accuracy: 1e-9, formula, file: file, line: line)
      } else {
        XCTAssertEqual(got, expected, formula, file: file, line: line)
      }
    }
  }

  /// TRUE in a range is not a number; typed into the call it is 1.
  func testStatisticsSkipTrueAndTextInRanges() throws {
    try check([
      ("=COUNT(A1:A8)", .number(3)), ("=SUM(A1:A8)", .number(2.5)),
      ("=AVERAGE(A1:A8)", .number(2.5 / 3)), ("=SUM(A4,1)", .number(1)),
      ("=SUM(TRUE,1)", .number(2)), ("=SUM(\"5\",1)", .number(6)), ("=SUM(--A4)", .number(1)),
      ("=COUNT(\"5\",\"a\",TRUE)", .number(2)), ("=SUM(\"abc\",1)", .error(.value)),
      ("=MAX(D1:D8)", .number(0)), ("=MIN(B1:B8)", .number(-60)),
    ])
  }

  func testComparisonsOrderNumbersTextThenTrueFalse() throws {
    try check([
      ("=1=TRUE", .bool(false)), ("=TRUE>1", .bool(true)), ("=\"10\"<\"9\"", .bool(true)),
      ("=\"a\"<\"B\"", .bool(true)), ("=\"a\"=\"A\"", .bool(true)), ("=1<\"a\"", .bool(true)),
      ("=0.1+0.2=0.3", .bool(true)),
      // Text is never equal to a number, as in Excel; a cell holding text "1" is marked as text
      // (`Cell.isText`), so it meets a formula's "1" as text.
      ("=TEXTAFTER(\"north-west-1\",\"-\",-1)=1", .bool(false)), ("=\"5\"<10", .bool(false)),
      ("=A3=0", .bool(true)), ("=A3=\"\"", .bool(true)),
      ("=A3=FALSE", .bool(true)), ("=1/0=1", .error(.divZero)),
    ])
  }

  func testPowersAndOverflowAreErrorsNotNaN() throws {
    try check([
      ("=(-8)^(1/3)", .number(-2)), ("=POWER(-8,1/3)", .number(-2)),
      ("=(-8)^(1/2)", .error(.num)), ("=0^0", .error(.num)), ("=-2^2", .number(4)),
      ("=1E+308*10", .error(.num)), ("=2^-1", .number(0.5)),
    ])
  }

  /// Excel's 1900 calendar keeps 29 Feb 1900 (serial 60) and a day 0.
  func testDatePartsFollowThe1900Calendar() throws {
    try check([
      ("=DAY(60)", .number(29)), ("=MONTH(60)", .number(2)), ("=YEAR(1)", .number(1900)),
      ("=DAY(0)", .number(0)), ("=DAY(61)", .number(1)), ("=MONTH(61)", .number(3)),
      ("=YEAR(45291)", .number(2023)), ("=DAY(-1)", .error(.num)),
    ])
  }

  func testExactLookupsMatchWildcards() throws {
    try check([
      ("=VLOOKUP(\"app*\",A1:B8,2,FALSE)", .number(20)),
      ("=VLOOKUP(\"*pie\",A1:B8,2,FALSE)", .number(-60)),
      ("=MATCH(\"b?\",D1:D8,0)", .number(2)), ("=MATCH(\"c~?d\",D1:D8,0)", .number(3)),
      ("=HLOOKUP(\"z*\",D1:D2,2,FALSE)", .error(.na)),
      ("=VLOOKUP(\"APPLE\",A1:B8,2,FALSE)", .number(20)),
    ])
  }

  func testXLOOKUPSearchModeAndEmptyArguments() throws {
    try check([
      ("=XLOOKUP(70,B1:B8,D1:D8,,0,-1)", .error(.na)),
      ("=XLOOKUP(0,B1:B8,D1:D8,\"n\",0,-1)", .string("x")),
      ("=XLOOKUP(0,B1:B8,D1:D8,\"n\",0,1)", .string("x")),
      ("=XLOOKUP(\"a\",D1:D8,B1:B8,,0,-1)", .number(70.25)),
      ("=XLOOKUP(\"a\",D1:D8,B1:B8,,0,1)", .number(10)),
      ("=XLOOKUP(99,B1:B8,D1:D8,,)", .error(.na)),
    ])
  }

  func testCaseChangesOneCharacterAtATime() throws {
    try check([
      ("=UPPER(\"straße\")", .string("STRAßE")), ("=LOWER(\"ÄÖ\")", .string("äö")),
      ("=PROPER(\"o'neil mc-donald\")", .string("O'Neil Mc-Donald")),
      ("=PROPER(\"2nd floor 3d\")", .string("2Nd Floor 3D")),
    ])
  }

  /// Second batch, Nov 18.
  func testCriteriaWildcardsAndTextComparisonsSeeTextOnly() throws {
    try check([
      ("=COUNTIF(A1:A8,\"*\")", .number(3)), ("=COUNTIF(A1:A8,\">a\")", .number(3)),
      ("=COUNTIF(A1:A8,\"<>*\")", .number(5)), ("=COUNTIF(A1:A8,\"APPLE*\")", .number(2)),
    ])
  }

  func testTextFunctionEdges() throws {
    try check([
      ("=VALUE(\"3/15/2026\")", .number(46096)), ("=VALUE(\"10:30\")", .number(0.4375)),
      ("=VALUE(\"x\")", .error(.value)), ("=LEFT(\"abc\",-1)", .error(.value)),
      ("=RIGHT(\"abc\",0)", .string("")),
      ("=TRIM(\"  a   b  \")", .string("a b")),
      ("=TRIM(CHAR(160)&\"a\")", .string("\u{00A0}a")),
      ("=TEXT(1234567,\"0.0,,\\M\")", .string("1.2M")),
      ("=TEXT(\"abc\",\"@@\")", .string("abcabc")),
    ])
  }

  /// One-value functions working through a range inside an array formula, with Excel 16.115's
  /// answers for each (typed by script, Nov 18). They were #VALUE!.
  func testFunctionsWorkThroughRangesInArrayFormulas() throws {
    try check([
      ("=SUM(LEN(D1:D8))", .number(14.0)),
      ("=SUMPRODUCT(LEN(D1:D8))", .number(14.0)),
      ("=MAX(IF(B1:B8<50,B1:B8))", .number(30.0)),
      ("=MIN(IF(B1:B8>0,B1:B8))", .number(10.0)),
      ("=SUM(IF(B1:B8>15,1,0))", .number(4.0)),
      ("=SUM(--ISNUMBER(A1:A8))", .number(3.0)),
      ("=SUM(--ISTEXT(A1:A8))", .number(3.0)),
      ("=SUMPRODUCT(--ISBLANK(B1:B8))", .number(1.0)),
      ("=COUNT(IF(B1:B8>0,B1:B8))", .number(5.0)),
      ("=AVERAGE(IF(B1:B8>0,B1:B8))", .number(36.05)),
      ("=SUM(ROUND(B1:B8/3,0))", .number(40.0)),
      ("=SUM(ABS(B1:B8))", .number(240.25)),
      ("=MAX(LEN(A1:A8))", .number(9.0)),
      ("=SUM(--(LEFT(D1:D8,1)=\"a\"))", .number(4.0)),
      ("=SUMPRODUCT((LEFT(D1:D8,1)=\"a\")*B1:B8)", .number(70.25)),
      ("=SUM(IFERROR(1/B1:B8,0))", .number(0.200901542112)),
      ("=SUM(MOD(B1:B3,7))", .number(11.0)),
      ("=SUM(YEAR(C1:C4))", .number(8093.0)),
      ("=SUM(MONTH(C1:C3))", .number(19.0)),
      ("=SUMPRODUCT(--(YEAR(C1:C4)=2023))", .number(3.0)),
      ("=TEXTJOIN(\",\",TRUE,UPPER(D1:D3))", .string("A,B*,C?D")),
      ("=TEXTJOIN(\"|\",TRUE,IF(B1:B8>25,D1:D8,\"\"))", .string("c?d|ab|A")),
      ("=CONCAT(LEFT(D1:D8,1))", .string("abc~aaAx")),
      ("=SUM(LEN(D1:D8)-LEN(SUBSTITUTE(D1:D8,\"a\",\"\")))", .number(3.0)),
      ("=SUM(--ISERROR(SEARCH(\"b\",D1:D8)))", .number(5.0)),
      ("=SUM(IF(ISNUMBER(SEARCH(\"a\",D1:D8)),1,0))", .number(4.0)),
      ("=ROWS(FILTER(D1:D8,ISNUMBER(SEARCH(\"a\",D1:D8))))", .number(4.0)),
      ("=INDEX(FILTER(D1:D8,LEN(D1:D8)=2),1)", .string("b*")),
      ("=SUM(FILTER(B1:B8,ISNUMBER(B1:B8)))", .number(120.25)),
      ("=SUM(LEN({\"ab\",\"cde\"}))", .number(5.0)),
      ("=SUM(IF({1,0,1},{5,6,7}))", .number(12.0)),
      ("=MAX(IF(D1:D8=\"a\",B1:B8))", .number(70.25)),
      ("=SUM(IF(D1:D8=\"a\",B1:B8,0))", .number(80.25)),
      ("=SUM(IF(B1:B8>10,IF(B1:B8<60,B1:B8)))", .number(100.0)),
      ("=SUM(N(B1:B3))", .number(10.0)),
      ("=SUM(VALUE({\"1\",\"2\"}))", .number(3.0)),
      ("=SUM(POWER(B1:B3,2))", .number(1400.0)),
      ("=SUMPRODUCT(SQRT(ABS(B1:B3)))", .number(13.11163919022)),
      ("=SUM(INT(B1:B8))", .number(120.0)),
      ("=COUNT(SEARCH(\"a\",D1:D8))", .number(4.0)),
      ("=SUM(IF(MOD(ROW(B1:B8),2)=0,B1:B8))", .number(-40.0)),
      ("=SUM(--NOT(ISBLANK(B1:B8)))", .number(7.0)),
      ("=SUM(LEN(TRIM(D1:D8)))", .number(14.0)),
      ("=SUM(--EXACT(D1:D8,\"a\"))", .number(1.0)),
    ])
  }

  /// INDIRECT and ADDRESS, with Excel 16.115's answers (typed by script, Nov 18).
  func testIndirectAndAddressMatchExcel() throws {
    try check([
      ("=INDIRECT(\"B2\")", .number(20.0)),
      ("=INDIRECT(\"b\"&3)", .number(30.0)),
      ("=SUM(INDIRECT(\"B1:B3\"))", .number(60.0)),
      ("=INDIRECT(\"R2C2\",FALSE)", .number(20.0)),
      ("=INDIRECT(\"nonsense\")", .error(.ref)),
      ("=INDIRECT(\"\")", .error(.ref)),
      ("=COUNTIF(INDIRECT(\"A1:A8\"),\"*\")", .number(3.0)),
      ("=VLOOKUP(\"apple\",INDIRECT(\"A1:B8\"),2,FALSE)", .number(20.0)),
      ("=INDEX(INDIRECT(\"B1:B8\"),5)", .number(50.0)),
      ("=ROWS(INDIRECT(\"B2:B5\"))", .number(4.0)),
      ("=MATCH(30,INDIRECT(\"B:B\"),0)", .number(3.0)),
      ("=SUM(INDIRECT(\"B\"&1&\":B\"&3))", .number(60.0)),
      ("=INDIRECT(ADDRESS(2,2))", .number(20.0)),
      ("=SUMPRODUCT(LEN(INDIRECT(\"D1:D8\")))", .number(14.0)),
      ("=ADDRESS(2,3)", .string("$C$2")),
      ("=ADDRESS(2,3,2)", .string("C$2")),
      ("=ADDRESS(2,3,3)", .string("$C2")),
      ("=ADDRESS(2,3,4)", .string("C2")),
      ("=ADDRESS(2,3,1,FALSE)", .string("R2C3")),
      ("=ADDRESS(2,3,2,FALSE)", .string("R2C[3]")),
      ("=ADDRESS(2,3,3,FALSE)", .string("R[2]C3")),
      ("=ADDRESS(2,3,4,FALSE)", .string("R[2]C[3]")),
      ("=ADDRESS(2,3,1,TRUE,\"Sheet2\")", .string("Sheet2!$C$2")),
      ("=ADDRESS(2,3,1,TRUE,\"My Sheet\")", .string("'My Sheet'!$C$2")),
      ("=ADDRESS(2,3,4,TRUE,\"a-b\")", .string("'a-b'!C2")),
      ("=ADDRESS(1048576,16384)", .string("$XFD$1048576")),
      ("=ADDRESS(0,1)", .error(.value)),
      ("=ADDRESS(1,16385)", .error(.value)),
      ("=ADDRESS(2,3,5)", .error(.value)),
      ("=ADDRESS(2.9,3.9)", .string("$C$2")),
      ("=ADDRESS(2,3,,,\"x\")", .string("x!$C$2")),
      ("=ADDRESS(2,28)", .string("$AB$2")),
      ("=ADDRESS(2,3,1,TRUE,\"\")", .string("!$C$2")),
      ("=ADDRESS(2,3,1,TRUE,\"Q1\")", .string("'Q1'!$C$2")),
      ("=ADDRESS(2,3,1,TRUE,\"1x\")", .string("'1x'!$C$2")),
      ("=ADDRESS(2,3,1,TRUE,\"it's\")", .string("'it''s'!$C$2")),
    ])
  }

  /// R1C1 counts from the formula's cell: R[1]C[-4] from F6 is B7.
  func testIndirectR1C1CountsFromTheFormulasCell() throws {
    let cells = self.cells
    var evaluator = FormulaEvaluator { ref in cells[ref.address.a1] ?? .blank }
    evaluator.evaluationOrigin = CellAddress(row: 5, col: 5)
    XCTAssertEqual(
      evaluator.evaluate(try FormulaParser.parse("=INDIRECT(\"R[1]C[-4]\",FALSE)")),
      .number(70.25))
    XCTAssertEqual(
      evaluator.evaluate(try FormulaParser.parse("=INDIRECT(\"RC[-4]\",FALSE)")), .number(-60))
  }

  /// Approximate MATCH, VLOOKUP and HLOOKUP as Excel's sorted search, with Excel 16.115's
  /// answers (typed by script, Nov 18): sorted lists, duplicates, text, descending, mixed kinds
  /// and the last-value idioms MATCH(9.99E+307,…), MATCH("zzz",…) and MATCH(2,1/(…)).
  func testApproximateLookupsSearchAsExcelDoes() throws {
    try check([
      ("=MATCH(9.99E+307,B1:B8)", .number(8.0)),
      ("=MATCH(1E+99,B1:B8)", .number(8.0)),
      ("=MATCH(\"zzz\",D1:D8)", .number(8.0)),
      ("=MATCH(\"zzz\",A1:A8)", .number(8.0)),
      ("=MATCH(9.99E+307,A1:A8)", .number(7.0)),
      ("=MATCH(3,H1:H8)", .number(3.0)),
      ("=MATCH(15,H1:H8)", .number(7.0)),
      ("=MATCH(16,H1:H8)", .number(7.0)),
      ("=MATCH(0,H1:H8)", .error(.na)),
      ("=MATCH(100,H1:H8)", .number(8.0)),
      ("=MATCH(\"c\",I1:I8)", .number(2.0)),
      ("=MATCH(\"cat\",I1:I8)", .number(3.0)),
      ("=MATCH(\"zebra\",I1:I8)", .number(8.0)),
      ("=MATCH(\"a\",I1:I8)", .error(.na)),
      ("=MATCH(\"CAT\",I1:I8)", .number(3.0)),
      ("=MATCH(50,J1:J8,-1)", .number(3.0)),
      ("=MATCH(40,J1:J8,-1)", .number(4.0)),
      ("=MATCH(95,J1:J8,-1)", .error(.na)),
      ("=MATCH(0,J1:J8,-1)", .number(8.0)),
      ("=VLOOKUP(16,H1:I8,2)", .string("gnu")),
      ("=VLOOKUP(16,H1:I8,2,TRUE)", .string("gnu")),
      ("=VLOOKUP(\"d\",I1:J8,2)", .number(50.0)),
      ("=VLOOKUP(\"zz\",I1:J8,2)", .number(1.0)),
      ("=VLOOKUP(0,H1:I8,2)", .error(.na)),
      ("=HLOOKUP(5,B1:D2,2)", .error(.na)),
      ("=MATCH(5,K1:K8)", .number(4.0)),
      ("=MATCH(9.99E+307,K1:K8)", .number(8.0)),
      ("=MATCH(\"zzz\",K1:K8)", .number(7.0)),
      ("=MATCH(TRUE,K1:K8)", .number(5.0)),
      ("=MATCH(25,B1:B8)", .number(2.0)),
      ("=MATCH(15,B1:B8)", .number(1.0)),
      ("=MATCH(55,B1:B8)", .number(6.0)),
      ("=MATCH(-100,B1:B8)", .error(.na)),
      ("=VLOOKUP(55,B1:D8,3)", .string("abc")),
      ("=MATCH(2,1/(B1:B8>40))", .number(7.0)),
      ("=MATCH(2,1/(D1:D8=\"ab\"))", .number(5.0)),
      ("=INDEX(D1:D8,MATCH(2,1/(B1:B8>0)))", .string("A")),
    ])
  }

  /// OFFSET, LOOKUP and YEARFRAC (every basis, leap years, month ends, either order), with
  /// Excel 16.115's answers (typed by script, Nov 18).
  func testOffsetLookupAndYearfracMatchExcel() throws {
    try check([
      ("=OFFSET(B1,1,0)", .number(20.0)),
      ("=OFFSET(B1,0,1)", .number(45000.0)),
      ("=SUM(OFFSET(B1,0,0,3,1))", .number(60.0)),
      ("=SUM(OFFSET(B1,1,0,3))", .number(50.0)),
      ("=OFFSET(A1,2,3)", .string("c?d")),
      ("=SUM(OFFSET(B1:B3,1,0))", .number(50.0)),
      ("=ROWS(OFFSET(A1,0,0,5,2))", .number(5.0)),
      ("=COLUMNS(OFFSET(A1,0,0,5,2))", .number(2.0)),
      ("=OFFSET(B1,-1,0)", .error(.ref)),
      ("=OFFSET(B1,0,0,0,1)", .error(.ref)),
      ("=SUM(OFFSET(B8,-2,0,3,1))", .number(10.25)),
      ("=COUNTIF(OFFSET(A1,0,0,8,1),\"*\")", .number(3.0)),
      ("=INDEX(OFFSET(A1,0,0,8,4),2,4)", .string("b*")),
      ("=SUM(OFFSET(B1,0,0,-3,1))", .error(.ref)),
      ("=AVERAGE(OFFSET(H1,2,0,3))", .number(6.666666666667)),
      ("=MATCH(30,OFFSET(B1,0,0,8),0)", .number(3.0)),
      ("=VLOOKUP(\"dog\",OFFSET(I1,0,0,8,2),2,FALSE)", .number(50.0)),
      ("=OFFSET(B2,,)", .number(20.0)),
      ("=SUM(OFFSET(B1,0,0,COUNTA(B1:B8)))", .number(120.25)),
      ("=LOOKUP(25,B1:B3)", .number(20.0)),
      ("=LOOKUP(16,H1:H8,I1:I8)", .string("gnu")),
      ("=LOOKUP(\"dog\",I1:I8,H1:H8)", .number(7.0)),
      ("=LOOKUP(0,H1:H8,I1:I8)", .error(.na)),
      ("=LOOKUP(100,H1:H8,I1:I8)", .string("hen")),
      ("=LOOKUP(2,1/(B1:B8>40),D1:D8)", .string("A")),
      ("=LOOKUP(9.99E+307,B1:B8)", .number(0.0)),
      ("=LOOKUP(\"zzz\",D1:D8)", .string("x")),
      ("=LOOKUP(16,H1:I8)", .string("gnu")),
      ("=LOOKUP(\"c\",{\"a\",\"b\",\"d\"},{1,2,3})", .number(2.0)),
      ("=LOOKUP(3,{1,2,3;\"x\",\"y\",\"z\"})", .string("z")),
      ("=LOOKUP(2.5,{1,2,3},{\"a\",\"b\",\"c\"})", .string("b")),
      ("=LOOKUP(\"eel\",I1:I8,H2:H8)", .number(15.0)),
      ("=LOOKUP(5,K1:K8)", .number(2.0)),
      ("=YEARFRAC(DATEVALUE(\"2024-01-01\"),DATEVALUE(\"2024-12-31\"),0)", .number(1.0)),
      ("=YEARFRAC(DATEVALUE(\"2024-01-01\"),DATEVALUE(\"2024-12-31\"),1)", .number(0.997267759563)),
      ("=YEARFRAC(DATEVALUE(\"2024-01-01\"),DATEVALUE(\"2024-12-31\"),2)", .number(1.013888888889)),
      ("=YEARFRAC(DATEVALUE(\"2024-01-01\"),DATEVALUE(\"2024-12-31\"),3)", .number(1.0)),
      ("=YEARFRAC(DATEVALUE(\"2024-01-01\"),DATEVALUE(\"2024-12-31\"),4)", .number(0.997222222222)),
      ("=YEARFRAC(DATEVALUE(\"2023-02-28\"),DATEVALUE(\"2024-02-29\"),0)", .number(1.0)),
      ("=YEARFRAC(DATEVALUE(\"2023-02-28\"),DATEVALUE(\"2024-02-29\"),1)", .number(1.001367989056)),
      ("=YEARFRAC(DATEVALUE(\"2023-02-28\"),DATEVALUE(\"2024-02-29\"),2)", .number(1.016666666667)),
      ("=YEARFRAC(DATEVALUE(\"2023-02-28\"),DATEVALUE(\"2024-02-29\"),3)", .number(1.002739726027)),
      ("=YEARFRAC(DATEVALUE(\"2023-02-28\"),DATEVALUE(\"2024-02-29\"),4)", .number(1.002777777778)),
      ("=YEARFRAC(DATEVALUE(\"2024-02-29\"),DATEVALUE(\"2025-02-28\"),0)", .number(1.0)),
      ("=YEARFRAC(DATEVALUE(\"2024-02-29\"),DATEVALUE(\"2025-02-28\"),1)", .number(0.997267759563)),
      ("=YEARFRAC(DATEVALUE(\"2024-02-29\"),DATEVALUE(\"2025-02-28\"),2)", .number(1.013888888889)),
      ("=YEARFRAC(DATEVALUE(\"2024-02-29\"),DATEVALUE(\"2025-02-28\"),3)", .number(1.0)),
      ("=YEARFRAC(DATEVALUE(\"2024-02-29\"),DATEVALUE(\"2025-02-28\"),4)", .number(0.997222222222)),
      ("=YEARFRAC(DATEVALUE(\"2023-01-31\"),DATEVALUE(\"2023-03-31\"),0)", .number(0.166666666667)),
      ("=YEARFRAC(DATEVALUE(\"2023-01-31\"),DATEVALUE(\"2023-03-31\"),1)", .number(0.161643835616)),
      ("=YEARFRAC(DATEVALUE(\"2023-01-31\"),DATEVALUE(\"2023-03-31\"),2)", .number(0.163888888889)),
      ("=YEARFRAC(DATEVALUE(\"2023-01-31\"),DATEVALUE(\"2023-03-31\"),3)", .number(0.161643835616)),
      ("=YEARFRAC(DATEVALUE(\"2023-01-31\"),DATEVALUE(\"2023-03-31\"),4)", .number(0.166666666667)),
      ("=YEARFRAC(DATEVALUE(\"2020-03-15\"),DATEVALUE(\"2026-11-18\"),0)", .number(6.675)),
      ("=YEARFRAC(DATEVALUE(\"2020-03-15\"),DATEVALUE(\"2026-11-18\"),1)", .number(6.676965193586)),
      ("=YEARFRAC(DATEVALUE(\"2020-03-15\"),DATEVALUE(\"2026-11-18\"),2)", .number(6.775)),
      ("=YEARFRAC(DATEVALUE(\"2020-03-15\"),DATEVALUE(\"2026-11-18\"),3)", .number(6.682191780822)),
      ("=YEARFRAC(DATEVALUE(\"2020-03-15\"),DATEVALUE(\"2026-11-18\"),4)", .number(6.675)),
      ("=YEARFRAC(DATEVALUE(\"2024-01-31\"),DATEVALUE(\"2024-02-29\"),0)", .number(0.080555555556)),
      ("=YEARFRAC(DATEVALUE(\"2024-01-31\"),DATEVALUE(\"2024-02-29\"),1)", .number(0.079234972678)),
      ("=YEARFRAC(DATEVALUE(\"2024-01-31\"),DATEVALUE(\"2024-02-29\"),2)", .number(0.080555555556)),
      ("=YEARFRAC(DATEVALUE(\"2024-01-31\"),DATEVALUE(\"2024-02-29\"),3)", .number(0.079452054795)),
      ("=YEARFRAC(DATEVALUE(\"2024-01-31\"),DATEVALUE(\"2024-02-29\"),4)", .number(0.080555555556)),
      ("=YEARFRAC(DATEVALUE(\"2023-12-31\"),DATEVALUE(\"2024-01-31\"),0)", .number(0.083333333333)),
      ("=YEARFRAC(DATEVALUE(\"2023-12-31\"),DATEVALUE(\"2024-01-31\"),1)", .number(0.084931506849)),
      ("=YEARFRAC(DATEVALUE(\"2023-12-31\"),DATEVALUE(\"2024-01-31\"),2)", .number(0.086111111111)),
      ("=YEARFRAC(DATEVALUE(\"2023-12-31\"),DATEVALUE(\"2024-01-31\"),3)", .number(0.084931506849)),
      ("=YEARFRAC(DATEVALUE(\"2023-12-31\"),DATEVALUE(\"2024-01-31\"),4)", .number(0.083333333333)),
      ("=YEARFRAC(DATEVALUE(\"2024-03-01\"),DATEVALUE(\"2023-03-01\"),0)", .number(1.0)),
      ("=YEARFRAC(DATEVALUE(\"2024-03-01\"),DATEVALUE(\"2023-03-01\"),1)", .number(1.0)),
      ("=YEARFRAC(DATEVALUE(\"2024-03-01\"),DATEVALUE(\"2023-03-01\"),2)", .number(1.016666666667)),
      ("=YEARFRAC(DATEVALUE(\"2024-03-01\"),DATEVALUE(\"2023-03-01\"),3)", .number(1.002739726027)),
      ("=YEARFRAC(DATEVALUE(\"2024-03-01\"),DATEVALUE(\"2023-03-01\"),4)", .number(1.0)),
      ("=YEARFRAC(DATEVALUE(\"2023-02-28\"),DATEVALUE(\"2023-03-31\"),0)", .number(0.086111111111)),
      ("=YEARFRAC(DATEVALUE(\"2023-02-28\"),DATEVALUE(\"2023-03-31\"),1)", .number(0.084931506849)),
      ("=YEARFRAC(DATEVALUE(\"2023-02-28\"),DATEVALUE(\"2023-03-31\"),2)", .number(0.086111111111)),
      ("=YEARFRAC(DATEVALUE(\"2023-02-28\"),DATEVALUE(\"2023-03-31\"),3)", .number(0.084931506849)),
      ("=YEARFRAC(DATEVALUE(\"2023-02-28\"),DATEVALUE(\"2023-03-31\"),4)", .number(0.088888888889)),
      ("=YEARFRAC(DATEVALUE(\"2024-02-29\"),DATEVALUE(\"2024-03-31\"),0)", .number(0.086111111111)),
      ("=YEARFRAC(DATEVALUE(\"2024-02-29\"),DATEVALUE(\"2024-03-31\"),1)", .number(0.084699453552)),
      ("=YEARFRAC(DATEVALUE(\"2024-02-29\"),DATEVALUE(\"2024-03-31\"),2)", .number(0.086111111111)),
      ("=YEARFRAC(DATEVALUE(\"2024-02-29\"),DATEVALUE(\"2024-03-31\"),3)", .number(0.084931506849)),
      ("=YEARFRAC(DATEVALUE(\"2024-02-29\"),DATEVALUE(\"2024-03-31\"),4)", .number(0.086111111111)),
      ("=YEARFRAC(DATEVALUE(\"2022-07-15\"),DATEVALUE(\"2024-07-14\"),0)", .number(1.997222222222)),
      ("=YEARFRAC(DATEVALUE(\"2022-07-15\"),DATEVALUE(\"2024-07-14\"),1)", .number(1.998175182482)),
      ("=YEARFRAC(DATEVALUE(\"2022-07-15\"),DATEVALUE(\"2024-07-14\"),2)", .number(2.027777777778)),
      ("=YEARFRAC(DATEVALUE(\"2022-07-15\"),DATEVALUE(\"2024-07-14\"),3)", .number(2.0)),
      ("=YEARFRAC(DATEVALUE(\"2022-07-15\"),DATEVALUE(\"2024-07-14\"),4)", .number(1.997222222222)),
      ("=YEARFRAC(DATEVALUE(\"2023-05-31\"),DATEVALUE(\"2023-06-30\"),0)", .number(0.083333333333)),
      ("=YEARFRAC(DATEVALUE(\"2023-05-31\"),DATEVALUE(\"2023-06-30\"),1)", .number(0.082191780822)),
      ("=YEARFRAC(DATEVALUE(\"2023-05-31\"),DATEVALUE(\"2023-06-30\"),2)", .number(0.083333333333)),
      ("=YEARFRAC(DATEVALUE(\"2023-05-31\"),DATEVALUE(\"2023-06-30\"),3)", .number(0.082191780822)),
      ("=YEARFRAC(DATEVALUE(\"2023-05-31\"),DATEVALUE(\"2023-06-30\"),4)", .number(0.083333333333)),
      ("=YEARFRAC(45000,45000)", .number(0.0)),
      ("=YEARFRAC(45000,45100,5)", .error(.num)),
      ("=YEARFRAC(\"x\",45000)", .error(.value)),
      ("=YEARFRAC(45000.7,45100.2)", .number(0.272222222222)),
    ])
  }

  /// ISREF, ISFORMULA, CELL, PERCENTILE.EXC, QUARTILE.EXC, the space (intersection) operator
  /// and ranges ending at INDIRECT or INDEX, with Excel 16.115's answers (Nov 18). F2 holds
  /// =1+1.
  func testReferencesAndExcPercentilesMatchExcel() throws {
    try check([
      ("=ISREF(A1)", .bool(true)),
      ("=ISREF(A1:B2)", .bool(true)),
      ("=ISREF(\"A1\")", .bool(false)),
      ("=ISREF(5)", .bool(false)),
      ("=ISREF(INDIRECT(\"A1\"))", .bool(true)),
      ("=ISREF(OFFSET(A1,1,1))", .bool(true)),
      ("=ISREF(Z99)", .bool(true)),
      ("=ISREF(1/0)", .bool(false)),
      ("=ISFORMULA(A1)", .bool(false)),
      ("=ISFORMULA(F2)", .bool(true)),
      ("=ISFORMULA(Z99)", .bool(false)),
      ("=CELL(\"address\",B2)", .string("$B$2")),
      ("=CELL(\"row\",B5)", .number(5.0)),
      ("=CELL(\"col\",D2)", .number(4.0)),
      ("=CELL(\"contents\",B2)", .number(20.0)),
      ("=CELL(\"type\",A2)", .string("l")),
      ("=CELL(\"type\",B2)", .string("v")),
      ("=CELL(\"type\",Z99)", .string("b")),
      ("=CELL(\"address\",B2:C5)", .string("$B$2")),
      ("=CELL(\"prefix\",A2)", .string("'")),
      ("=CELL(\"filename\",A1)", .string("")),
      ("=PERCENTILE.EXC(B1:B8,0.5)", .number(20.0)),
      ("=PERCENTILE.EXC(B1:B8,0.25)", .number(0.0)),
      ("=PERCENTILE.EXC(B1:B8,0.9)", .error(.num)),
      ("=PERCENTILE.EXC(B1:B8,0.05)", .error(.num)),
      ("=PERCENTILE.EXC({1,2,3,4},0.2)", .number(1.0)),
      ("=PERCENTILE.EXC({1,2,3,4},0.8)", .number(4.0)),
      ("=PERCENTILE.EXC({1,2,3,4},0.1)", .error(.num)),
      ("=QUARTILE.EXC(B1:B8,1)", .number(0.0)),
      ("=QUARTILE.EXC(B1:B8,3)", .number(50.0)),
      ("=SUM(B1:B3 B2:B5)", .number(50.0)),
      ("=B1:B5 B3", .number(30.0)),
      ("=SUM(B1:B8 A3:D3)", .number(30.0)),
      ("=SUM(B1:B2 B4:B5)", .error(.null)),
      ("=SUM(INDIRECT(\"B1\"):INDIRECT(\"B3\"))", .number(60.0)),
      ("=SUM(B1:INDEX(B1:B8,3))", .number(60.0)),
      ("=SUM(INDEX(B1:B8,2):B4)", .number(50.0)),
      ("=ROWS(B2:INDEX(B1:B8,5))", .number(4.0)),
    ])
  }
}
