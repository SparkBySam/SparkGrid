import GridCore
import Model
import XCTest

@testable import Calc
@testable import Formula

/// A range or list in a criteria argument gives one answer per criterion, as in other apps:
/// =SUMIFS(C1:C4,A1:A4,B1:B4) spills four totals. It was #VALUE! (Sam's test, Nov 20).
@MainActor
final class CriteriaArrayTests: XCTestCase {
  func testCriteriaRangesGiveOneAnswerEach() throws {
    // A: region, B: the region asked about, C: amount.
    let rows: [(String, String, Double)] = [
      ("East", "West", 10), ("West", "East", 20), ("East", "North", 30), ("North", "East", 40),
    ]
    var cells: [CellAddress: Cell] = [:]
    for (r, row) in rows.enumerated() {
      cells[CellAddress(row: r, col: 0)] = Cell(raw: row.0)
      cells[CellAddress(row: r, col: 1)] = Cell(raw: row.1)
      cells[CellAddress(row: r, col: 2)] = Cell(raw: String(row.2))
    }
    let formulas: [(String, CellValue)] = [
      // West 20, East 40, North 40, East 40.
      ("=SUM(SUMIFS(C1:C4,A1:A4,B1:B4))", .number(140)),
      ("=INDEX(SUMIFS(C1:C4,A1:A4,B1:B4),3)", .number(40)),
      ("=INDEX(SUMIF(A1:A4,B1:B4,C1:C4),1)", .number(20)),
      ("=SUM(COUNTIF(A1:A4,{\"East\",\"West\"}))", .number(3)),
      ("=INDEX(COUNTIFS(A1:A4,B1:B4,C1:C4,\">15\"),2)", .number(1)),
      ("=INDEX(AVERAGEIFS(C1:C4,A1:A4,{\"East\";\"North\"}),1)", .number(20)),
      ("=SUMIFS(C1:C4,A1:A4,\"East\")", .number(40)),
    ]
    for (i, item) in formulas.enumerated() {
      cells[CellAddress(row: 10 + i, col: 0)] = Cell(raw: item.0)
    }
    let sheet = Sheet(name: "Sheet1", cells: cells)
    let engine = FormulaEngine()
    engine.rebuild(workbook: Workbook(sheets: [sheet]), recalculate: true)
    for (i, item) in formulas.enumerated() {
      XCTAssertEqual(
        engine.sheetDisplayValue(at: CellAddress(row: 10 + i, col: 0), sheet: sheet), item.1,
        item.0)
    }
    XCTAssertTrue(FormulaEvaluator.spills(try FormulaParser.parse("=SUMIFS(C1:C4,A1:A4,B1:B4)")))
    XCTAssertFalse(
      FormulaEvaluator.spills(try FormulaParser.parse("=SUMIFS(C1:C4,A1:A4,\"East\")")))
    XCTAssertFalse(FormulaEvaluator.spills(try FormulaParser.parse("=SUMIF(A1:A4,\"East\",C1:C4)")))
  }
}
