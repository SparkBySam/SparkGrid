import GridCore
import Model
import XCTest

@testable import Calc

/// `AVERAGE` and `AVERAGEIFS` return an error that sits in the averaged cells.
/// `IFERROR` around that result is the fallback, not the average of the other numbers.
@MainActor
final class AverageErrorTests: XCTestCase {
  func testAverageReturnsTheErrorInItsRange() {
    let sheet = Sheet(
      name: "Summary",
      cells: [
        CellAddress(row: 0, col: 0): Cell(raw: "1"),
        CellAddress(row: 1, col: 0): Cell(raw: "=1/0"),
        CellAddress(row: 2, col: 0): Cell(raw: "=IFERROR(AVERAGE(A1:A2),\"x\")"),
        CellAddress(row: 0, col: 1): Cell(raw: "1"),
        CellAddress(row: 1, col: 1): Cell(raw: "=1/0"),
        CellAddress(row: 0, col: 2): Cell(raw: "a"),
        CellAddress(row: 1, col: 2): Cell(raw: "a"),
        CellAddress(row: 2, col: 1): Cell(
          raw: "=IFERROR(AVERAGEIFS(B1:B2,C1:C2,\"a\"),\"x\")"),
      ]
    )
    let workbook = Workbook(sheets: [sheet])
    let engine = FormulaEngine()
    engine.rebuild(workbook: workbook, recalculate: false)
    XCTAssertEqual(
      engine.sheetDisplayValue(at: CellAddress(row: 2, col: 0), sheet: sheet),
      .string("x")
    )
    XCTAssertEqual(
      engine.sheetDisplayValue(at: CellAddress(row: 2, col: 1), sheet: sheet),
      .string("x")
    )
  }
}
