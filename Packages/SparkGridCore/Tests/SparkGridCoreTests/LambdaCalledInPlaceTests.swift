import GridCore
import Model
import XCTest

@testable import Calc
@testable import Formula

/// A LAMBDA given its values where it is written, `=LAMBDA(x,x*3)(7)`, as other apps allow.
/// Spark Grid read the second brackets as a mistake and showed #ERROR! (Sam's test, Nov 20).
@MainActor
final class LambdaCalledInPlaceTests: XCTestCase {
  func testLambdaCalledWhereItIsWritten() {
    let cases: [(String, CellValue)] = [
      ("=LAMBDA(x,x*3)(7)", .number(21)),
      ("=_xlfn.LAMBDA(_xlpm.x,_xlpm.x*3)(7)", .number(21)),
      ("=LAMBDA(a,b,a+b)(2,5)", .number(7)),
      ("=LAMBDA(x,LAMBDA(y,x*y))(3)(4)", .number(12)),
      ("=LAMBDA(r,SUM(r))(A1:A3)", .number(6)),
      ("=LET(f,LAMBDA(x,x+1),f(9))", .number(10)),
      ("=LET(sum,5,SUM(1,2)+sum)", .number(8)),
      ("=LAMBDA(x,x)(1,2)", .error(.value)),
      ("=LAMBDA(x,x*2)", .error(.calc)),
    ]
    var cells: [CellAddress: Cell] = [
      CellAddress(row: 0, col: 0): Cell(raw: "1"),
      CellAddress(row: 1, col: 0): Cell(raw: "2"),
      CellAddress(row: 2, col: 0): Cell(raw: "3"),
    ]
    for (row, item) in cases.enumerated() {
      cells[CellAddress(row: row, col: 1)] = Cell(raw: item.0)
    }
    let sheet = Sheet(name: "Sheet1", cells: cells)
    let engine = FormulaEngine()
    engine.rebuild(workbook: Workbook(sheets: [sheet]), recalculate: true)
    for (row, item) in cases.enumerated() {
      XCTAssertEqual(
        engine.sheetDisplayValue(at: CellAddress(row: row, col: 1), sheet: sheet), item.1, item.0)
    }
  }

  func testCalledLambdaThatGivesAnArraySpills() throws {
    let expr = try FormulaParser.parse("=LAMBDA(n,SEQUENCE(n))(3)")
    XCTAssertTrue(FormulaEvaluator.spills(expr))
    XCTAssertFalse(FormulaEvaluator.spills(try FormulaParser.parse("=LAMBDA(x,x*3)(7)")))
  }
}
