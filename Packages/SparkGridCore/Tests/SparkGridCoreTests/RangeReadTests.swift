import GridCore
import Model
import XCTest

@testable import Calc

/// A range must calculate formula cells inside it. Their source text is not a value.
@MainActor
final class RangeReadTests: XCTestCase {
  func testSumReadsAFormulaOnTheSameSheet() {
    let sheet = Sheet(
      name: "Data",
      cells: [
        CellAddress(row: 0, col: 0): Cell(raw: "10"),
        CellAddress(row: 1, col: 0): Cell(raw: "=A1"),
        CellAddress(row: 0, col: 1): Cell(raw: "=SUM(A1:A2)"),
      ]
    )
    let workbook = Workbook(sheets: [sheet])
    let engine = FormulaEngine()
    engine.rebuild(workbook: workbook, recalculate: false)
    let value = engine.sheetDisplayValue(
      at: CellAddress(row: 0, col: 1), sheet: workbook.sheets[0])
    XCTAssertEqual(value, .number(20))
  }

  func testSumReadsAFormulaOnAnotherSheet() {
    let january = Sheet(
      name: "January",
      cells: [
        CellAddress(row: 0, col: 0): Cell(raw: "10"),
        CellAddress(row: 1, col: 0): Cell(raw: "=A1"),
      ]
    )
    let june = Sheet(
      name: "June",
      cells: [
        CellAddress(row: 0, col: 0): Cell(raw: "=SUM(January!A1:A2)")
      ]
    )
    let workbook = Workbook(sheets: [june, january])
    let engine = FormulaEngine()
    engine.rebuild(workbook: workbook, recalculate: false)
    let value = engine.sheetDisplayValue(
      at: CellAddress(row: 0, col: 0), sheet: workbook.sheets[0])
    XCTAssertEqual(value, .number(20))
  }
}
