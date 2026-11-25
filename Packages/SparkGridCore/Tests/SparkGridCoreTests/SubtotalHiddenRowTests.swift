import Calc
import GridCore
import Model
import XCTest

/// SUBTOTAL and AGGREGATE through the engine: rows hidden by hand or by a filter are left out
/// by SUBTOTAL 101 to 111 and AGGREGATE's options, and a filter's rows by every SUBTOTAL.
final class SubtotalHiddenRowTests: XCTestCase {
  private func sheet() -> Sheet {
    var sheet = Sheet(name: "Data")
    for row in 0..<5 {
      sheet.setCell(Cell(raw: String(row + 1)), at: CellAddress(row: row, col: 0))
    }
    sheet.setCell(Cell(raw: "=SUBTOTAL(109,A1:A5)"), at: CellAddress(row: 0, col: 2))
    sheet.setCell(Cell(raw: "=SUBTOTAL(9,A1:A5)"), at: CellAddress(row: 1, col: 2))
    sheet.setCell(Cell(raw: "=AGGREGATE(9,5,A1:A5)"), at: CellAddress(row: 2, col: 2))
    sheet.setCell(Cell(raw: "=SUBTOTAL(9,A1:A5,C1)"), at: CellAddress(row: 3, col: 2))
    return sheet
  }

  private func values(_ sheet: Sheet) -> [CellValue] {
    let engine = FormulaEngine()
    engine.rebuild(sheet: sheet, recalculate: true)
    return (0..<4).map { engine.displayValue(at: CellAddress(row: $0, col: 2), sheet: sheet) }
  }

  func testNothingHidden() {
    XCTAssertEqual(values(sheet()), [.number(15), .number(15), .number(15), .number(15)])
  }

  func testHiddenRowsLeftOutBy109AndAggregate() {
    var s = sheet()
    s.fileExtras.hiddenRows = [1]
    XCTAssertEqual(values(s), [.number(13), .number(15), .number(13), .number(15)])
  }

  func testFilteredRowsLeftOutByEverySubtotal() {
    var s = sheet()
    s.fileExtras.filteredRows = [1, 3]
    // A nested SUBTOTAL (C1) is not counted again.
    XCTAssertEqual(values(s), [.number(9), .number(9), .number(9), .number(9)])
  }
}
