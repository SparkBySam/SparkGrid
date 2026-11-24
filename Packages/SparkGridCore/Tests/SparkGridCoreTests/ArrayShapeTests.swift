import FileFormats
import Formula
import GridCore
import XCTest

@testable import Calc

/// LET, VSTACK, HSTACK, TAKE, DROP, CHOOSECOLS, CHOOSEROWS, WRAPROWS, WRAPCOLS, TOCOL, TOROW,
/// TEXTSPLIT and RANDARRAY, on values worked out by hand from how other apps document them.
final class ArrayShapeTests: XCTestCase {
  /// A1:C3 holds 1 to 9 row by row; E1:E2 two short lists; G1 a sentence; H1:H2 delimiters.
  private let cells: [String: CellValue] = {
    var out: [String: CellValue] = [:]
    for r in 0..<3 {
      for c in 0..<3 {
        out[CellAddress(row: r, col: c).a1] = .number(Double(r * 3 + c + 1))
      }
    }
    out["E1"] = .string("a")
    out["E2"] = .string("b")
    out["G1"] = .string("Ann,West;Bo,East;Cy")
    out["H1"] = .string(",")
    out["H2"] = .string(";")
    out["I1"] = .string("x--y")
    out["I2"] = .error(.divZero)
    return out
  }()

  private func evaluator() -> FormulaEvaluator {
    let cells = self.cells
    return FormulaEvaluator { ref in cells[ref.address.a1] ?? .blank }
  }

  private func array(_ formula: String) throws -> ArrayResult {
    evaluator().evaluateArray(try FormulaParser.parse(formula))
  }

  private func scalar(_ formula: String) throws -> CellValue {
    evaluator().evaluate(try FormulaParser.parse(formula))
  }

  private func texts(_ formula: String) throws -> [[String]] {
    let a = try array(formula)
    return (0..<a.rows).map { r in (0..<a.cols).map { a.value(row: r, col: $0).displayString } }
  }

  // MARK: LET

  func testLetNamesValuesInOrder() throws {
    XCTAssertEqual(try scalar("=LET(x, 2, y, x * 3, x + y)"), .number(8))
    XCTAssertEqual(try scalar("=LET(Total, SUM(A1:C1), Total * 2)"), .number(12))
    // A name for a range reads as the range.
    XCTAssertEqual(try scalar("=LET(r, A1:A3, SUM(r) + ROWS(r))"), .number(15))
    // Names are compared without regard to case, and with the prefix files save them with.
    XCTAssertEqual(try scalar("=LET(Rate, 0.5, rate * 10)"), .number(5))
    XCTAssertEqual(try scalar("=_xlfn.LET(_xlpm.x, 4, _xlpm.x * _xlpm.x)"), .number(16))
    // An inner LET's name hides the outer one inside it only.
    XCTAssertEqual(try scalar("=LET(x, 1, LET(x, 10, x) + x)"), .number(11))
  }

  func testLetErrors() throws {
    // A name without a calculation, an even count, and a name given twice.
    XCTAssertEqual(try scalar("=LET(x, 1)"), .error(.value))
    XCTAssertEqual(try scalar("=LET(x, 1, y, 2)"), .error(.value))
    XCTAssertEqual(try scalar("=LET(x, 1, x, 2, x)"), .error(.value))
    // A name LET does not give is still a defined name, and there is none here.
    XCTAssertEqual(try scalar("=LET(x, 1, x + nothing)"), .error(.name))
    // A value's error comes through where it is used.
    XCTAssertEqual(try scalar("=LET(x, 1/0, x + 1)"), .error(.divZero))
  }

  func testLetSpills() throws {
    let expr = try FormulaParser.parse("=LET(n, 3, SEQUENCE(n) * 10)")
    XCTAssertTrue(FormulaEvaluator.spills(expr))
    XCTAssertEqual(try texts("=LET(n, 3, SEQUENCE(n) * 10)"), [["10"], ["20"], ["30"]])
    XCTAssertEqual(try texts("=LET(rows, TAKE(A1:C3, 2), CHOOSECOLS(rows, 3))"), [["3"], ["6"]])
    XCTAssertFalse(FormulaEvaluator.spills(try FormulaParser.parse("=LET(x, 1, x + 1)")))
    // SUM over a LET that gives an array adds all of it.
    XCTAssertEqual(try scalar("=SUM(LET(s, SEQUENCE(4), s))"), .number(10))
  }

  // MARK: Stacking

  func testVStackAndHStack() throws {
    XCTAssertEqual(
      try texts("=VSTACK(A1:C1, E1:E2)"),
      [["1", "2", "3"], ["a", "#N/A", "#N/A"], ["b", "#N/A", "#N/A"]])
    XCTAssertEqual(try texts("=HSTACK(A1:A2, E1:E2, 7)"), [["1", "a", "7"], ["4", "b", "#N/A"]])
    XCTAssertEqual(try texts("=VSTACK(1, 2)"), [["1"], ["2"]])
  }

  // MARK: Taking and dropping

  func testTakeAndDrop() throws {
    XCTAssertEqual(try texts("=TAKE(A1:C3, 2)"), [["1", "2", "3"], ["4", "5", "6"]])
    XCTAssertEqual(try texts("=TAKE(A1:C3, -1, -2)"), [["8", "9"]])
    XCTAssertEqual(try texts("=TAKE(A1:C3, , 1)"), [["1"], ["4"], ["7"]])
    XCTAssertEqual(try texts("=TAKE(A1:C3, 10)").count, 3)
    XCTAssertEqual(try array("=TAKE(A1:C3, 0)").first, .error(.value))
    XCTAssertEqual(try texts("=DROP(A1:C3, 2)"), [["7", "8", "9"]])
    XCTAssertEqual(try texts("=DROP(A1:C3, -2, 1)"), [["2", "3"]])
    XCTAssertEqual(try array("=DROP(A1:C3, 3)").first, .error(.calc))
    XCTAssertEqual(try array("=TAKE(A1:C3)").first, .error(.value))
  }

  func testChooseColumnsAndRows() throws {
    XCTAssertEqual(try texts("=CHOOSECOLS(A1:C3, 3, 1)"), [["3", "1"], ["6", "4"], ["9", "7"]])
    XCTAssertEqual(try texts("=CHOOSEROWS(A1:C3, -1)"), [["7", "8", "9"]])
    XCTAssertEqual(try texts("=CHOOSEROWS(A1:C3, 2, 2)"), [["4", "5", "6"], ["4", "5", "6"]])
    XCTAssertEqual(try array("=CHOOSECOLS(A1:C3, 4)").first, .error(.value))
    XCTAssertEqual(try array("=CHOOSECOLS(A1:C3, 0)").first, .error(.value))
  }

  // MARK: Reshaping

  func testWrapRowsAndColumns() throws {
    XCTAssertEqual(
      try texts("=WRAPROWS(SEQUENCE(5), 2)"), [["1", "2"], ["3", "4"], ["5", "#N/A"]])
    XCTAssertEqual(
      try texts("=WRAPROWS(SEQUENCE(5), 2, \"\")"), [["1", "2"], ["3", "4"], ["5", ""]])
    XCTAssertEqual(
      try texts("=WRAPCOLS(SEQUENCE(1, 5), 3, 0)"), [["1", "4"], ["2", "5"], ["3", "0"]])
    XCTAssertEqual(try array("=WRAPROWS(A1:C3, 2)").first, .error(.value))
    XCTAssertEqual(try array("=WRAPROWS(SEQUENCE(5), 0)").first, .error(.num))
  }

  func testToColumnAndRow() throws {
    XCTAssertEqual(try texts("=TOCOL(A1:B2)"), [["1"], ["2"], ["4"], ["5"]])
    XCTAssertEqual(try texts("=TOCOL(A1:B2, 0, TRUE)"), [["1"], ["4"], ["2"], ["5"]])
    XCTAssertEqual(try texts("=TOROW(A1:B2)"), [["1", "2", "4", "5"]])
    // E1:F2 has blanks in F; I1:I2 has an error.
    XCTAssertEqual(try texts("=TOCOL(E1:F2, 1)"), [["a"], ["b"]])
    XCTAssertEqual(try texts("=TOCOL(I1:I2, 2)"), [["x--y"]])
    XCTAssertEqual(try texts("=TOCOL(E1:F2)").count, 4)
    XCTAssertEqual(try array("=TOCOL(F1:F2, 1)").first, .error(.calc))
    XCTAssertEqual(try array("=TOCOL(A1:B2, 4)").first, .error(.value))
  }

  // MARK: TEXTSPLIT

  func testTextSplit() throws {
    XCTAssertEqual(try texts("=TEXTSPLIT(\"a,b,c\", \",\")"), [["a", "b", "c"]])
    XCTAssertEqual(
      try texts("=TEXTSPLIT(G1, \",\", \";\")"),
      [["Ann", "West"], ["Bo", "East"], ["Cy", "#N/A"]])
    XCTAssertEqual(
      try texts("=TEXTSPLIT(G1, \",\", \";\", FALSE, 0, \"-\")"),
      [["Ann", "West"], ["Bo", "East"], ["Cy", "-"]])
    // Only a row delimiter: one column.
    XCTAssertEqual(try texts("=TEXTSPLIT(\"a;b\", , \";\")"), [["a"], ["b"]])
    // Several delimiters from a range.
    XCTAssertEqual(try texts("=TEXTSPLIT(\"a,b;c\", H1:H2)"), [["a", "b", "c"]])
    // Empty pieces stay unless told to go.
    XCTAssertEqual(try texts("=TEXTSPLIT(I1, \"-\")"), [["x", "", "y"]])
    XCTAssertEqual(try texts("=TEXTSPLIT(I1, \"-\", , TRUE)"), [["x", "y"]])
    // Case matters unless match_mode is 1.
    XCTAssertEqual(try texts("=TEXTSPLIT(\"1x2X3\", \"x\")"), [["1", "2X3"]])
    XCTAssertEqual(try texts("=TEXTSPLIT(\"1x2X3\", \"x\", , , 1)"), [["1", "2", "3"]])
    // The longest delimiter wins where two start at the same place.
    XCTAssertEqual(try texts("=TEXTSPLIT(\"a--b-c\", H1:H1, )").count, 1)
    XCTAssertEqual(try array("=TEXTSPLIT(\"abc\", \"\")").first, .error(.value))
    XCTAssertEqual(try array("=TEXTSPLIT(I2, \",\")").first, .error(.divZero))
  }

  // MARK: RANDARRAY

  func testRandomArray() throws {
    let a = try array("=RANDARRAY(4, 3, 10, 20, TRUE)")
    XCTAssertEqual(a.rows, 4)
    XCTAssertEqual(a.cols, 3)
    for value in a.values {
      guard case .number(let n) = value else { return XCTFail("\(value)") }
      XCTAssertTrue((10...20).contains(n) && n == n.rounded(), "\(n)")
    }
    for value in try array("=RANDARRAY(50)").values {
      guard case .number(let n) = value else { return XCTFail("\(value)") }
      XCTAssertTrue(n >= 0 && n < 1)
    }
    XCTAssertEqual(try array("=RANDARRAY()").rows, 1)
    XCTAssertEqual(try array("=RANDARRAY(2, 2, 5, 1)").first, .error(.value))
    XCTAssertEqual(try array("=RANDARRAY(2, 2, 0.5, 3, TRUE)").first, .error(.value))
    XCTAssertEqual(try array("=RANDARRAY(0)").first, .error(.calc))
  }

  // MARK: Saving

  func testSavedWithExcelPrefixes() {
    XCTAssertEqual(
      ExcelFutureFunctions.prefixed("LET(x,A1*2,total,SUM(B1:B3),x+total)"),
      "_xlfn.LET(_xlpm.x,A1*2,_xlpm.total,SUM(B1:B3),_xlpm.x+_xlpm.total)")
    // Not before a cell, a function, a defined name outside the LET, or quoted text.
    XCTAssertEqual(
      ExcelFutureFunctions.prefixed("LET(a,$A$1,a&\"a\")+a"),
      "_xlfn.LET(_xlpm.a,$A$1,_xlpm.a&\"a\")+a")
    XCTAssertEqual(
      ExcelFutureFunctions.prefixed("VSTACK(TAKE(A1:C3,1),TEXTSPLIT(G1,\",\"))"),
      "_xlfn.VSTACK(_xlfn.TAKE(A1:C3,1),_xlfn.TEXTSPLIT(G1,\",\"))")
    // Already saved with prefixes: left alone.
    XCTAssertEqual(
      ExcelFutureFunctions.prefixed("_xlfn.LET(_xlpm.x,1,_xlpm.x)"),
      "_xlfn.LET(_xlpm.x,1,_xlpm.x)")
  }

  // MARK: Typed lists

  func testTypedLists() throws {
    XCTAssertEqual(try texts("={1,2,3}"), [["1", "2", "3"]])
    XCTAssertEqual(try texts("={1;2;3}"), [["1"], ["2"], ["3"]])
    XCTAssertEqual(try texts("={1,\"a\";TRUE,#N/A}"), [["1", "a"], ["TRUE", "#N/A"]])
    XCTAssertEqual(try texts("={-1.5,+2}"), [["-1.5", "2"]])
    XCTAssertTrue(FormulaEvaluator.spills(try FormulaParser.parse("={1,2}")))
    XCTAssertFalse(FormulaEvaluator.spills(try FormulaParser.parse("={7}")))
    XCTAssertEqual(try scalar("={7}"), .number(7))
    // Read as arrays by functions.
    XCTAssertEqual(try scalar("=SUM({1,2,3})"), .number(6))
    XCTAssertEqual(try scalar("=INDEX({10,20,30},2)"), .number(20))
    XCTAssertEqual(try texts("={1,2,3}*10"), [["10", "20", "30"]])
    XCTAssertEqual(try texts("=CHOOSECOLS(A1:C3,{1,3})"), [["1", "3"], ["4", "6"], ["7", "9"]])
    XCTAssertEqual(try texts("=TEXTSPLIT(\"a,b;c\",{\",\",\";\"})"), [["a", "b", "c"]])
    XCTAssertEqual(try texts("=VSTACK({1,2},{3,4})"), [["1", "2"], ["3", "4"]])
  }

  func testTypedListsThatAreNotLists() {
    // Rows of different lengths, a reference or a formula inside, and an unclosed brace.
    for bad in ["={1,2;3}", "={A1,2}", "={1+1}", "={1,2", "={}"] {
      XCTAssertThrowsError(try FormulaParser.parse(bad), bad)
    }
  }

  func testTypedListsWrittenBack() throws {
    let expr = try FormulaParser.parse("=SUM({1,2;3,4})+{\"x\"}")
    XCTAssertEqual(FormulaRewriter.serialize(expr), "SUM({1,2;3,4})+{\"x\"}")
    // Copied down a row, a list stays as it is and the reference moves.
    XCTAssertEqual(
      FormulaRewriter.adjust("=SUM({1,2})+A1", rowDelta: 1, colDelta: 0), "=SUM({1,2})+A2")
  }

  /// Functions that take a range read a typed list or a spilling result value by value. They
  /// took only the first value (found by script, Nov 18).
  func testRangeFunctionsReadEveryValueOfAnArray() throws {
    XCTAssertEqual(try scalar("=TEXTJOIN(\"-\",TRUE,{3,1,2})"), .string("3-1-2"))
    XCTAssertEqual(try scalar("=TEXTJOIN(\"-\",TRUE,SORT({3;1;2}))"), .string("1-2-3"))
    XCTAssertEqual(try scalar("=TEXTJOIN(\",\",TRUE,TOROW(A1:B2))"), .string("1,2,4,5"))
    XCTAssertEqual(try scalar("=SUMPRODUCT({1,2,3},{4,5,6})"), .number(32))
    XCTAssertEqual(try scalar("=SUMPRODUCT(SEQUENCE(3),SEQUENCE(3))"), .number(14))
  }
}
