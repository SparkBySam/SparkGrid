import Calc
import Engine
import Foundation
import GridCore
import Model
import XCTest

@testable import FileFormats

/// Text that reads like a number stays text: ZIP codes, codes with leading zeros, long IDs, a
/// file's text cells, and anything typed after an apostrophe. 02134 read back as 2134 and was
/// saved as a number, losing the zero for good (found Nov 18).
final class TextCellTests: XCTestCase {
  private func textCell(_ raw: String) -> Cell {
    var cell = Cell(raw: raw)
    cell.markTextIfNeeded()
    return cell
  }

  private func sheet() -> Sheet {
    var sheet = Sheet(name: "Codes")
    for (row, raw) in ["02134", "007", "1", "12345678901234567890", "TRUE"].enumerated() {
      sheet.setCell(textCell(raw), at: CellAddress(row: row, col: 1))
    }
    sheet.setCell(Cell(raw: "42"), at: CellAddress(row: 5, col: 1))
    return sheet
  }

  func testTextCellsReadAsText() {
    let cells = sheet()
    XCTAssertEqual(cells.cell(at: CellAddress(row: 0, col: 1)).literalValue, .string("02134"))
    XCTAssertEqual(cells.cell(at: CellAddress(row: 4, col: 1)).literalValue, .string("TRUE"))
    XCTAssertEqual(cells.cell(at: CellAddress(row: 5, col: 1)).literalValue, .number(42))
    XCTAssertEqual(cells.cell(at: CellAddress(row: 1, col: 1)).editableText, "'007")
    // Plain text needs no mark.
    XCTAssertNil(textCell("apple").isText)
  }

  func testFormulasSeeText() {
    var sheet = sheet()
    let formulas = [
      "=LEN(B2)", "=ISTEXT(B3)", "=SUM(B1:B6)", "=COUNTIF(B1:B6,\"*\")", "=B1&\"-x\"", "=B3+1",
    ]
    for (row, formula) in formulas.enumerated() {
      sheet.setCell(Cell(raw: formula), at: CellAddress(row: row, col: 3))
    }
    let engine = FormulaEngine()
    engine.rebuild(sheet: sheet, recalculate: true)
    let shown = (0..<formulas.count).map {
      engine.sheetDisplayValue(at: CellAddress(row: $0, col: 3), sheet: sheet)
    }
    XCTAssertEqual(shown[0], .number(3))
    XCTAssertEqual(shown[1], .bool(true))
    XCTAssertEqual(shown[2], .number(42))  // text is not added
    XCTAssertEqual(shown[3], .number(5))
    XCTAssertEqual(shown[4], .string("02134-x"))
    XCTAssertEqual(shown[5], .number(2))  // arithmetic still reads "1" as 1, as other apps do
  }

  /// Saved as text, and opened again as text; another app's file reads the same way.
  func testTextSurvivesSaving() throws {
    let saved = try XLSXCodec.exportWorkbook(Workbook(sheets: [sheet()]))
    let opened = try XLSXCodec.importWorkbook(from: saved).sheets[0]
    for (row, raw) in ["02134", "007", "1", "12345678901234567890", "TRUE"].enumerated() {
      let cell = opened.cell(at: CellAddress(row: row, col: 1))
      XCTAssertEqual(cell.raw, raw)
      XCTAssertEqual(cell.isText, true, raw)
      XCTAssertEqual(cell.literalValue, .string(raw))
    }
    XCTAssertNil(opened.cell(at: CellAddress(row: 5, col: 1)).isText)
  }

  @MainActor
  func testTypingAnApostropheKeepsText() {
    let session = WorkbookSession()
    _ = session.run(id: "cell.set", arguments: ["address": "A1", "raw": "'007"])
    _ = session.run(id: "cell.set", arguments: ["address": "A2", "raw": "007"])
    _ = session.run(id: "cell.set", arguments: ["address": "A3", "raw": "'hello"])
    let sheet = session.workbook.activeSheet
    XCTAssertEqual(sheet.cell(at: .origin).raw, "007")
    XCTAssertEqual(sheet.cell(at: .origin).literalValue, .string("007"))
    XCTAssertEqual(sheet.cell(at: .origin).editableText, "'007")
    XCTAssertEqual(sheet.cell(at: CellAddress(row: 1, col: 0)).literalValue, .number(7))
    XCTAssertEqual(sheet.cell(at: CellAddress(row: 2, col: 0)).literalValue, .string("hello"))
    // Typing a number over text makes it a number again.
    _ = session.run(id: "cell.set", arguments: ["address": "A1", "raw": "8"])
    XCTAssertNil(session.workbook.activeSheet.cell(at: .origin).isText)
  }
}
