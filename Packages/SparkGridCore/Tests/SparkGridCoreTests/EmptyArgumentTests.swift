import Calc
import Formula
import GridCore
import Model
import XCTest

/// An argument left out between commas reads as other apps read it: a blank, so 0 to arithmetic,
/// "" to text and FALSE to a yes-or-no argument; an IF or CHOOSE that picks it gives 0. These
/// formulas did not parse at all, so they showed nothing.
final class EmptyArgumentTests: XCTestCase {
  private func results(_ formulas: [String]) -> [CellValue] {
    var sheet = Sheet(name: "S")
    let data: [(Int, Int, String)] = [
      (0, 0, "1"), (0, 1, "one"), (1, 0, "5"), (1, 1, "five"), (2, 0, "9"), (2, 1, "nine"),
    ]
    for (row, col, raw) in data {
      sheet.setCell(Cell(raw: raw), at: CellAddress(row: row, col: col))
    }
    for (i, formula) in formulas.enumerated() {
      sheet.setCell(Cell(raw: formula), at: CellAddress(row: 10 + i, col: 4))
    }
    let engine = FormulaEngine()
    engine.recalculateEntireWorkbook(Workbook(sheets: [sheet]), profile: false)
    let values = engine.formulaResults(on: sheet)
    return formulas.indices.map { values[CellAddress(row: 10 + $0, col: 4)] ?? .blank }
  }

  func testEmptyArgumentsReadAsBlanks() {
    let values = results([
      "=IF(A2>1,,2)", "=IF(A2>9,2,)", "=SUM(1,,2)", #"=CONCATENATE("a",,"b")"#,
      "=ROUND(2.567,)", "=VLOOKUP(4,A1:B3,2,)", "=VLOOKUP(4,A1:B3,2)", "=CHOOSE(2,7,,9)",
    ])
    XCTAssertEqual(values[0], .number(0))
    XCTAssertEqual(values[1], .number(0))
    XCTAssertEqual(values[2], .number(3))
    XCTAssertEqual(values[3], .string("ab"))
    XCTAssertEqual(values[4], .number(3))
    // A trailing comma asks for an exact match: 4 is not in the list.
    XCTAssertEqual(values[5], .error(.na))
    // Without it, the nearest match below.
    XCTAssertEqual(values[6], .string("one"))
    XCTAssertEqual(values[7], .number(0))
  }

  func testWrittenBackAsTyped() throws {
    for formula in ["=IF(A2>1,,2)", "=VLOOKUP(4,A1:B3,2,)", "=SUM(,1)", "=NOW()"] {
      let parsed = try FormulaParser.parse(formula)
      XCTAssertEqual("=" + FormulaRewriter.serialize(parsed), formula)
    }
    // No arguments at all is not one empty argument.
    XCTAssertEqual(try FormulaParser.parse("=NOW()"), .call("NOW", []))
  }
}
