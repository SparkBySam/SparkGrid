import XCTest

@testable import Formula

/// References into a block of moved cells follow it; others stay.
final class MoveReferencesTests: XCTestCase {
  private func move(_ raw: String, on sheet: String = "Data") -> String {
    FormulaRewriter.movingReferences(
      raw, formulaSheetName: sheet, movedSheetName: "Data", rows: 1...3, columns: 1...1,
      rowDelta: 0, colDelta: 3)  // B2:B4
  }

  func testCellsAndWholeRangesFollow() {
    XCTAssertEqual(move("=B2*2"), "=E2*2")
    XCTAssertEqual(move("=SUM(B2:B4)+$B$3"), "=SUM(E2:E4)+$E$3")
    XCTAssertEqual(move("=SUM(B1:B4)"), "=SUM(B1:B4)")  // reaches outside the block
    XCTAssertEqual(move("=A2+C2"), "=A2+C2")
  }

  func testOtherSheets() {
    XCTAssertEqual(move("=Data!B2", on: "Summary"), "=Data!E2")
    XCTAssertEqual(move("=B2", on: "Summary"), "=B2")  // Summary's own B2
    XCTAssertEqual(move("=Other!B2"), "=Other!B2")
  }
}
