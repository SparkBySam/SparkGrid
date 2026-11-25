import Calc
import GridCore
import Model
import XCTest

final class GoalSeekTests: XCTestCase {
  /// A loan's payment: what amount gives a payment of 500 a month over 5 years at 6%?
  func testLoanAmountForAPayment() throws {
    var sheet = Sheet(name: "Loan")
    sheet.setCell(Cell(raw: "20000"), at: CellAddress(row: 0, col: 1))
    sheet.setCell(Cell(raw: "=PMT(0.06/12,60,-B1)"), at: CellAddress(row: 1, col: 1))
    let result = GoalSeek.run(
      workbook: Workbook(sheets: [sheet]), setSheet: "Loan", setCell: CellAddress(row: 1, col: 1),
      goal: 500, changingSheet: "Loan", changingCell: CellAddress(row: 0, col: 1))
    let outcome = try result.get()
    XCTAssertTrue(outcome.found)
    XCTAssertEqual(outcome.input, 25862.78, accuracy: 0.01)
  }

  /// A non-linear formula on another sheet.
  func testSquareAcrossSheets() throws {
    var inputs = Sheet(name: "In")
    inputs.setCell(Cell(raw: "1"), at: .origin)
    var out = Sheet(name: "Out")
    out.setCell(Cell(raw: "=In!A1^2+3"), at: .origin)
    let outcome = try GoalSeek.run(
      workbook: Workbook(sheets: [inputs, out]), setSheet: "Out", setCell: .origin, goal: 19,
      changingSheet: "In", changingCell: .origin
    ).get()
    XCTAssertTrue(outcome.found)
    XCTAssertEqual(outcome.input, 4, accuracy: 1e-5)
  }

  func testRefusals() {
    var sheet = Sheet(name: "S")
    sheet.setCell(Cell(raw: "5"), at: .origin)
    sheet.setCell(Cell(raw: "=A1*2"), at: CellAddress(row: 1, col: 0))
    let book = Workbook(sheets: [sheet])
    XCTAssertEqual(
      GoalSeek.run(
        workbook: book, setSheet: "S", setCell: .origin, goal: 1, changingSheet: "S",
        changingCell: CellAddress(row: 1, col: 0)),
      .failure(.setCellHasNoFormula))
    XCTAssertEqual(
      GoalSeek.run(
        workbook: book, setSheet: "S", setCell: CellAddress(row: 1, col: 0), goal: 1,
        changingSheet: "S", changingCell: CellAddress(row: 1, col: 0)),
      .failure(.changingCellHasFormula))
  }

  /// No input gives a negative square: the closest is reported, not found.
  func testNoSolution() throws {
    var sheet = Sheet(name: "S")
    sheet.setCell(Cell(raw: "3"), at: .origin)
    sheet.setCell(Cell(raw: "=A1^2"), at: CellAddress(row: 1, col: 0))
    let outcome = try GoalSeek.run(
      workbook: Workbook(sheets: [sheet]), setSheet: "S", setCell: CellAddress(row: 1, col: 0),
      goal: -4, changingSheet: "S", changingCell: .origin
    ).get()
    XCTAssertFalse(outcome.found)
  }
}
