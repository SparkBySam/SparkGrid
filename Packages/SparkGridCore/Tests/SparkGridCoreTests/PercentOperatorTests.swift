import Calc
import Formula
import GridCore
import Model
import XCTest

/// `%` after a value divides it by 100, as other spreadsheet apps read it: `=A2%`, `=B2*10%`.
/// Spark Grid could not read it at all; a Numbers or other file with one showed a blank.
final class PercentOperatorTests: XCTestCase {
  private func results(_ formulas: [String]) -> [CellValue] {
    var sheet = Sheet(name: "S")
    sheet.setCell(Cell(raw: "5"), at: CellAddress(row: 1, col: 0))
    sheet.setCell(Cell(raw: "200"), at: CellAddress(row: 1, col: 1))
    for (i, formula) in formulas.enumerated() {
      sheet.setCell(Cell(raw: formula), at: CellAddress(row: 10 + i, col: 3))
    }
    let engine = FormulaEngine()
    engine.recalculateEntireWorkbook(Workbook(sheets: [sheet]), profile: false)
    let values = engine.formulaResults(on: sheet)
    return formulas.indices.map { values[CellAddress(row: 10 + $0, col: 3)] ?? .blank }
  }

  func testPercentDividesByAHundred() {
    let values = results(["=50%", "=A2%", "=B2*10%", "=-A2%", "=2^50%", "=A2%%", "=(A2+B2)%"])
    XCTAssertEqual(values[0], .number(0.5))
    XCTAssertEqual(values[1], .number(0.05))
    XCTAssertEqual(values[2], .number(20))
    XCTAssertEqual(values[3], .number(-0.05))
    guard case .number(let root) = values[4] else { return XCTFail("\(values[4])") }
    XCTAssertEqual(root, 2.0.squareRoot(), accuracy: 1e-12)
    XCTAssertEqual(values[5], .number(0.0005))
    XCTAssertEqual(values[6], .number(2.05))
  }

  func testPercentIsWrittenBack() throws {
    for formula in ["=50%", "=A2%", "=B2*10%", "=(A2+B2)%"] {
      let parsed = try FormulaParser.parse(formula)
      XCTAssertEqual("=" + FormulaRewriter.serialize(parsed), formula)
    }
  }

  func testTextAndErrorsStayAsTheyAre() {
    let values = results([#"="50%""#, "=1/0%"])
    XCTAssertEqual(values[0], .string("50%"))
    XCTAssertEqual(values[1], .error(.divZero))
  }
}
