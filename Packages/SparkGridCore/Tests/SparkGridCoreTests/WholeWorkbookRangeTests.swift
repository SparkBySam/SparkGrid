import Calc
import GridCore
import Model
import XCTest

/// Unqualified ranges in a whole-workbook recalculation: each sheet's SUM reads its own cells,
/// after they are calculated.
final class WholeWorkbookRangeTests: XCTestCase {
  private func sheet(_ name: String, base: Int, rows: Int = 3) -> Sheet {
    var sheet = Sheet(name: name)
    for row in 0..<rows {
      for col in 0..<3 {
        sheet.setCell(Cell(raw: "=\(base)+\(row)"), at: CellAddress(row: row, col: col))
      }
      sheet.setCell(Cell(raw: "=SUM(A\(row + 1):C\(row + 1))"), at: CellAddress(row: row, col: 3))
    }
    sheet.setCell(Cell(raw: "=SUM(D1:D\(rows))"), at: CellAddress(row: rows, col: 3))
    return sheet
  }

  func testSameRangeOnTwoSheetsKeepsEachSheetsAnswer() {
    let first = sheet("Monthly", base: 100)
    let second = sheet("Daily", base: 1)
    let workbook = Workbook(sheets: [first, second])
    let engine = FormulaEngine()
    engine.recalculateEntireWorkbook(workbook, profile: false)
    // Monthly: rows 100,101,102 × 3 = 909. Daily: 1,2,3 × 3 = 18.
    XCTAssertEqual(engine.formulaResults(on: first)[CellAddress(row: 0, col: 3)], .number(300))
    XCTAssertEqual(engine.formulaResults(on: first)[CellAddress(row: 3, col: 3)], .number(909))
    XCTAssertEqual(engine.formulaResults(on: second)[CellAddress(row: 0, col: 3)], .number(3))
    XCTAssertEqual(engine.formulaResults(on: second)[CellAddress(row: 3, col: 3)], .number(18))
  }

  func testSheetsThatReadEachOther() {
    var reps = sheet("Reps", base: 10)
    var summary = sheet("Summary", base: 5)
    // Reps reads Summary's total; Summary reads a Reps total.
    reps.setCell(Cell(raw: "=Summary!D4"), at: CellAddress(row: 5, col: 0))
    summary.setCell(Cell(raw: "=Reps!D4*2"), at: CellAddress(row: 5, col: 0))
    let workbook = Workbook(sheets: [summary, reps])
    let engine = FormulaEngine()
    engine.recalculateEntireWorkbook(workbook, profile: false)
    // Summary D4 = (5+6+7)*3 = 54; Reps D4 = (10+11+12)*3 = 99.
    XCTAssertEqual(engine.formulaResults(on: summary)[CellAddress(row: 3, col: 3)], .number(54))
    XCTAssertEqual(engine.formulaResults(on: reps)[CellAddress(row: 3, col: 3)], .number(99))
    XCTAssertEqual(engine.formulaResults(on: reps)[CellAddress(row: 5, col: 0)], .number(54))
    XCTAssertEqual(engine.formulaResults(on: summary)[CellAddress(row: 5, col: 0)], .number(198))
  }
}
