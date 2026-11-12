import Engine
import Formula
import GridCore
import Model
import XCTest

/// Deleting rows or columns at the edge of a range shrinks it. A range becomes #REF! only when
/// every row (or column) of it is deleted, as other spreadsheet apps do.
final class StructureShiftRangeTests: XCTestCase {
  private func shift(
    _ raw: String, on formulaSheet: String = "Data", mutated: String = "Data",
    _ axis: FormulaRewriter.Axis, _ change: FormulaRewriter.StructureChange
  ) -> String {
    FormulaRewriter.shiftForStructure(
      raw, formulaSheetName: formulaSheet, mutatedSheetName: mutated, axis: axis, change: change)
  }

  func testDeletingTheFirstRowOfARangeShrinksIt() {
    XCTAssertEqual(shift("=COUNTA(D1:D20)", .row, .delete(at: 0, count: 1)), "=COUNTA(D1:D19)")
    XCTAssertEqual(shift("=SUM(A2:A10)", .row, .delete(at: 1, count: 1)), "=SUM(A2:A9)")
  }

  func testDeletingTheLastRowOfARangeShrinksIt() {
    XCTAssertEqual(shift("=SUM(A2:A10)", .row, .delete(at: 9, count: 1)), "=SUM(A2:A9)")
  }

  func testDeletingAMiddleRowShrinksTheRange() {
    XCTAssertEqual(shift("=SUM(A2:A10)", .row, .delete(at: 4, count: 1)), "=SUM(A2:A9)")
  }

  func testDeletingRowsThatOverlapAnEdge() {
    // Rows 1-3 go; rows 4-10 of the range are left and move up to rows 1-7.
    XCTAssertEqual(shift("=SUM(A2:A10)", .row, .delete(at: 0, count: 3)), "=SUM(A1:A7)")
    // Rows 9-12 go; rows 2-8 are left.
    XCTAssertEqual(shift("=SUM(A2:A10)", .row, .delete(at: 8, count: 4)), "=SUM(A2:A8)")
  }

  func testDeletingRowsOutsideTheRange() {
    XCTAssertEqual(shift("=SUM(A2:A10)", .row, .delete(at: 0, count: 1)), "=SUM(A1:A9)")
    XCTAssertEqual(shift("=SUM(A2:A10)", .row, .delete(at: 10, count: 5)), "=SUM(A2:A10)")
  }

  func testDeletingEveryRowOfARangeIsARefError() {
    XCTAssertEqual(shift("=SUM(A2:A10)", .row, .delete(at: 1, count: 9)), "=SUM(#REF!)")
    XCTAssertEqual(shift("=SUM(A2:A10)", .row, .delete(at: 0, count: 20)), "=SUM(#REF!)")
  }

  func testDeletingASingleCellsRowIsStillARefError() {
    XCTAssertEqual(shift("=A1", .row, .delete(at: 0, count: 1)), "=#REF!")
    XCTAssertEqual(shift("=SUM(A1:A1)", .row, .delete(at: 0, count: 1)), "=SUM(#REF!)")
  }

  func testAbsoluteRangesShrinkToo() {
    XCTAssertEqual(shift("=SUM($A$2:$A$10)", .row, .delete(at: 1, count: 1)), "=SUM($A$2:$A$9)")
  }

  func testTwoDimensionalRangeKeepsItsOtherAxis() {
    XCTAssertEqual(shift("=SUM(B2:D10)", .row, .delete(at: 9, count: 1)), "=SUM(B2:D9)")
    XCTAssertEqual(shift("=SUM(B2:D10)", .column, .delete(at: 1, count: 1)), "=SUM(B2:C10)")
  }

  func testColumnAxis() {
    XCTAssertEqual(shift("=SUM(A1:J1)", .column, .delete(at: 0, count: 1)), "=SUM(A1:I1)")
    XCTAssertEqual(shift("=SUM(B1:J1)", .column, .delete(at: 1, count: 1)), "=SUM(B1:I1)")
    XCTAssertEqual(shift("=SUM(B1:J1)", .column, .delete(at: 9, count: 1)), "=SUM(B1:I1)")
    XCTAssertEqual(shift("=SUM(B1:J1)", .column, .delete(at: 4, count: 1)), "=SUM(B1:I1)")
    XCTAssertEqual(shift("=SUM(B1:J1)", .column, .delete(at: 1, count: 9)), "=SUM(#REF!)")
    XCTAssertEqual(shift("=B1", .column, .delete(at: 1, count: 1)), "=#REF!")
  }

  func testRangesOnOtherSheets() {
    // A formula on Summary reading Data shrinks when Data loses the range's first row.
    XCTAssertEqual(
      shift("=SUM(Data!A2:A10)", on: "Summary", .row, .delete(at: 1, count: 1)),
      "=SUM(Data!A2:A9)")
    XCTAssertEqual(
      shift("=SUM(Data!A2:A10)", on: "Summary", .row, .delete(at: 1, count: 9)),
      "=SUM(#REF!)")
    // A delete on another sheet leaves the range alone.
    XCTAssertEqual(
      shift("=SUM(Other!A2:A10)", on: "Summary", .row, .delete(at: 1, count: 9)),
      "=SUM(Other!A2:A10)")
    // An unqualified range on Summary does not read Data.
    XCTAssertEqual(
      shift("=SUM(A2:A10)", on: "Summary", .row, .delete(at: 1, count: 1)), "=SUM(A2:A10)")
  }

  func testWholeColumnAndWholeRowReferences() {
    // Rows deleted under a whole-column reference leave it as it was.
    XCTAssertEqual(shift("=SUM(A:A)", .row, .delete(at: 0, count: 5)), "=SUM(A:A)")
    // Columns deleted at its edge shrink it; all of them deleted is #REF!.
    XCTAssertEqual(shift("=SUM(B:D)", .column, .delete(at: 1, count: 1)), "=SUM(B:C)")
    XCTAssertEqual(shift("=SUM(B:D)", .column, .delete(at: 3, count: 1)), "=SUM(B:C)")
    XCTAssertEqual(shift("=SUM(B:D)", .column, .delete(at: 1, count: 3)), "=SUM(#REF!)")
    // Whole rows, the same along the other axis.
    XCTAssertEqual(shift("=SUM(1:1)", .column, .delete(at: 0, count: 5)), "=SUM(1:1)")
    XCTAssertEqual(shift("=SUM(2:5)", .row, .delete(at: 1, count: 1)), "=SUM(2:4)")
    XCTAssertEqual(shift("=SUM(2:5)", .row, .delete(at: 4, count: 1)), "=SUM(2:4)")
    XCTAssertEqual(shift("=SUM(2:5)", .row, .delete(at: 1, count: 4)), "=SUM(#REF!)")
  }

  func testInsertsStillMoveEachEnd() {
    XCTAssertEqual(shift("=SUM(A2:A10)", .row, .insert(at: 1, count: 1)), "=SUM(A3:A11)")
    XCTAssertEqual(shift("=SUM(A2:A10)", .row, .insert(at: 4, count: 2)), "=SUM(A2:A12)")
    XCTAssertEqual(shift("=SUM(B1:J1)", .column, .insert(at: 9, count: 1)), "=SUM(B1:K1)")
  }

  // MARK: - Through the commands

  private func run(
    _ id: String, _ arguments: [String: String], on workbook: inout Workbook,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    let outcome = WorkbookSession().apply(id: id, arguments: arguments, to: &workbook)
    XCTAssertTrue(outcome.ok, outcome.message, file: file, line: line)
  }

  private func cell(_ label: String, in sheet: Sheet) -> String {
    guard let parsed = A1Reference.parseAddress(label) else { return "?" }
    return sheet.cell(at: CellAddress(row: parsed.row, col: parsed.col)).raw
  }

  private func book() -> Workbook {
    var data = Sheet(name: "Data")
    data.setCell(Cell(raw: "=SUM(A2:A10)"), at: CellAddress(row: 0, col: 5))
    var summary = Sheet(name: "Summary")
    summary.setCell(Cell(raw: "=SUM(Data!A2:A10)"), at: CellAddress(row: 0, col: 0))
    summary.setCell(Cell(raw: "=SUM(Data!B1:J1)"), at: CellAddress(row: 1, col: 0))
    var workbook = Workbook(sheets: [data, summary])
    workbook.namedRanges["rows"] = NamedRange(
      name: "Rows", sheetName: "Data",
      range: CellRange(start: CellAddress(row: 1, col: 0), end: CellAddress(row: 9, col: 0)))
    workbook.namedRanges["cols"] = NamedRange(
      name: "Cols", sheetName: "Data",
      range: CellRange(start: CellAddress(row: 0, col: 1), end: CellAddress(row: 0, col: 9)))
    return workbook
  }

  func testDeletingTheFirstRowOfARangeThroughTheCommand() {
    var workbook = book()
    run("sheet.deleteRows", ["index": "1", "count": "1", "sheet": "Data"], on: &workbook)
    XCTAssertEqual(cell("F1", in: workbook.sheets[0]), "=SUM(A2:A9)")
    XCTAssertEqual(cell("A1", in: workbook.sheets[1]), "=SUM(Data!A2:A9)")
    let rows = workbook.namedRanges["rows"]
    XCTAssertEqual(rows?.startRow, 1)
    XCTAssertEqual(rows?.endRow, 8)
  }

  func testDeletingTheLastColumnOfARangeThroughTheCommand() {
    var workbook = book()
    run("sheet.deleteColumns", ["index": "9", "count": "1", "sheet": "Data"], on: &workbook)
    XCTAssertEqual(cell("A2", in: workbook.sheets[1]), "=SUM(Data!B1:I1)")
    let cols = workbook.namedRanges["cols"]
    XCTAssertEqual(cols?.startCol, 1)
    XCTAssertEqual(cols?.endCol, 8)
  }

  func testDeletingTheFirstColumnOfANamedRange() {
    var workbook = book()
    run("sheet.deleteColumns", ["index": "1", "count": "1", "sheet": "Data"], on: &workbook)
    let cols = workbook.namedRanges["cols"]
    XCTAssertEqual(cols?.startCol, 1)
    XCTAssertEqual(cols?.endCol, 8)
  }

  func testDeletingEveryRowOfANamedRangeDropsIt() {
    var workbook = book()
    run("sheet.deleteRows", ["index": "1", "count": "9", "sheet": "Data"], on: &workbook)
    XCTAssertNil(workbook.namedRanges["rows"])
    XCTAssertEqual(cell("A1", in: workbook.sheets[1]), "=SUM(#REF!)")
  }
}
