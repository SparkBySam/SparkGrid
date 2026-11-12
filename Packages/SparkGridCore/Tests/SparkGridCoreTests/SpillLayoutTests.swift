import Calc
import Engine
import GridCore
import Model
import XCTest

final class SpillLayoutTests: XCTestCase {
  private func column(_ values: [Double]) -> ArrayResult {
    ArrayResult(rows: values.count, cols: 1, values: values.map { .number($0) })
  }

  func testSpillsBelowTheFormula() {
    var sheet = Sheet(name: "S")
    let anchor = CellAddress(row: 1, col: 3)
    sheet.setCell(Cell(raw: "=SORT(A1:A3)"), at: anchor)
    let outcome = SpillLayout.apply([anchor: column([1, 2, 3])], to: &sheet)
    XCTAssertEqual(sheet.cell(at: CellAddress(row: 2, col: 3)).literalValue, .number(2))
    XCTAssertEqual(sheet.cell(at: CellAddress(row: 3, col: 3)).literalValue, .number(3))
    XCTAssertTrue(sheet.cell(at: CellAddress(row: 3, col: 3)).isSpilled)
    XCTAssertEqual(outcome.changedCells.count, 2)
    XCTAssertEqual(sheet.fileExtras.spills[anchor]?.a1Label, "D2:D4")
    // Shrinking clears the cell that is no longer covered.
    let shrink = SpillLayout.apply([anchor: column([5, 6])], to: &sheet)
    XCTAssertEqual(shrink.changedCells, [CellAddress(row: 2, col: 3), CellAddress(row: 3, col: 3)])
    XCTAssertFalse(sheet.cell(at: CellAddress(row: 3, col: 3)).isSpilled)
    XCTAssertNil(sheet.cells[CellAddress(row: 3, col: 3)])
  }

  func testTypedCellBlocksTheSpill() {
    var sheet = Sheet(name: "S")
    let anchor = CellAddress(row: 0, col: 0)
    sheet.setCell(Cell(raw: "=SEQUENCE(3)"), at: anchor)
    SpillLayout.apply([anchor: column([1, 2, 3])], to: &sheet)
    sheet.setCell(Cell(raw: "typed"), at: CellAddress(row: 2, col: 0))
    let outcome = SpillLayout.apply([anchor: column([1, 2, 3])], to: &sheet)
    XCTAssertEqual(sheet.fileExtras.blockedSpills, [anchor])
    XCTAssertEqual(outcome.changedAnchors, [anchor])
    XCTAssertFalse(sheet.cell(at: CellAddress(row: 1, col: 0)).isSpilled, "blocked spills clear")
    XCTAssertEqual(sheet.cell(at: CellAddress(row: 2, col: 0)).raw, "typed")
  }

  func testTwoFormulasCannotShareCells() {
    var sheet = Sheet(name: "S")
    let first = CellAddress(row: 0, col: 0)
    let second = CellAddress(row: 2, col: 0)
    sheet.setCell(Cell(raw: "=SEQUENCE(4)"), at: first)
    sheet.setCell(Cell(raw: "=SEQUENCE(2)"), at: second)
    SpillLayout.apply([first: column([1, 2, 3, 4]), second: column([7, 8])], to: &sheet)
    XCTAssertEqual(sheet.fileExtras.blockedSpills, [first])
    XCTAssertEqual(sheet.cell(at: CellAddress(row: 3, col: 0)).literalValue, .number(8))
  }

  func testBlanksShowAsZeroAndAnchorsAreFound() {
    var sheet = Sheet(name: "S")
    sheet.setCell(Cell(raw: "=FILTER(A1:A3,B1:B3)"), at: CellAddress(row: 0, col: 4))
    sheet.setCell(Cell(raw: "=SUM(FILTER(A1:A3,B1:B3))"), at: CellAddress(row: 0, col: 5))
    sheet.setCell(Cell(raw: "=_xlfn._xlws.SORT(A1:A3)"), at: CellAddress(row: 0, col: 6))
    XCTAssertEqual(
      SpillLayout.anchors(in: sheet), [CellAddress(row: 0, col: 4), CellAddress(row: 0, col: 6)])
    let anchor = CellAddress(row: 0, col: 4)
    SpillLayout.apply(
      [anchor: ArrayResult(rows: 2, cols: 1, values: [.string("a"), .blank])], to: &sheet)
    XCTAssertEqual(sheet.cell(at: CellAddress(row: 1, col: 4)).literalValue, .number(0))
  }
}
