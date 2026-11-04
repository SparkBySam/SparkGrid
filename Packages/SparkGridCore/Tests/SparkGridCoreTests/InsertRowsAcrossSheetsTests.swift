import GridCore
import Model
import XCTest

@testable import Engine

/// Inserting rows shifts formulas on every sheet that names the changed one, and only those.
@MainActor
final class InsertRowsAcrossSheetsTests: XCTestCase {
  private func book() -> Workbook {
    var data = Sheet(name: "O'Brien Data")
    data.setCell(Cell(raw: "=SUM(A1:A3)"), at: CellAddress(row: 4, col: 1))
    var summary = Sheet(name: "Summary")
    summary.setCell(Cell(raw: "='o''brien data'!B5*2"), at: .origin)
    summary.setCell(Cell(raw: "=SUM(A5:A9)"), at: CellAddress(row: 1, col: 0))
    var other = Sheet(name: "Other")
    other.setCell(Cell(raw: "=Summary!A1"), at: .origin)
    return Workbook(sheets: [data, summary, other])
  }

  private func raw(_ book: Workbook, _ sheet: Int, _ row: Int, _ col: Int) -> String? {
    book.sheets[sheet].cells[CellAddress(row: row, col: col)]?.raw
  }

  func testInsertShiftsQuotedReferencesInAnyCaseAndLeavesOtherSheetsAlone() {
    var workbook = book()
    let outcome = WorkbookSession().apply(
      id: "sheet.insertRows",
      arguments: ["sheet": "O'Brien Data", "index": "0", "count": "2"], to: &workbook)
    XCTAssertTrue(outcome.ok)
    XCTAssertEqual(raw(workbook, 0, 6, 1), "=SUM(A3:A5)")
    XCTAssertEqual(raw(workbook, 1, 0, 0), "='o''brien data'!B7*2")
    XCTAssertEqual(raw(workbook, 1, 1, 0), "=SUM(A5:A9)")
    XCTAssertEqual(raw(workbook, 2, 0, 0), "=Summary!A1")
  }

  func testByteScanIgnoresASCIICase() {
    let needle = Array("Orders".utf8)
    XCTAssertTrue(WorkbookSession.containsIgnoringASCIICase("=SUM(oRDERS!A:A)", needle))
    XCTAssertFalse(WorkbookSession.containsIgnoringASCIICase("=SUM(Order!A:A)", needle))
    XCTAssertFalse(WorkbookSession.containsIgnoringASCIICase("=Ord", needle))
    XCTAssertTrue(WorkbookSession.containsIgnoringASCIICase("=ÉTÉ!A1", Array("été".utf8)))
  }
}
