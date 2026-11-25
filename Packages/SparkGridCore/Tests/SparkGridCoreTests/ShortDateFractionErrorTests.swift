import Engine
import FileFormats
import Foundation
import GridCore
import Model
import XCTest

/// Short dates, fractions and error codes typed into a cell, against what Excel 16.115 stored
/// for the same typing (value and number format, asked by AppleScript on Nov 20, 2026).
@MainActor
final class ShortDateFractionErrorTests: XCTestCase {
  func testShortDatesAsExcelReadsThemIn2026() {
    let excel: [(String, Int?, String?)] = [
      ("3/4", 46085, "d-mmm"), ("15-Mar", 46096, "d-mmm"), ("Mar 15", 46096, "d-mmm"),
      ("Mar-15", 46096, "d-mmm"), ("15 Mar", 46096, "d-mmm"), ("March 15", 46096, "d-mmm"),
      ("1/2", 46024, "d-mmm"), ("1 /2", 46024, "d-mmm"), ("12/31", 46387, "d-mmm"),
      ("4-Jul", 46207, "d-mmm"), ("2/30", 10990, "mmm-yy"), ("1-2", 46024, "d-mmm"),
      ("31/12", nil, nil), ("13/1", nil, nil), ("abc", nil, nil),
    ]
    for (text, serial, code) in excel {
      let found = TypedEntry.shortDate(text, year: 2026)
      XCTAssertEqual(found?.serial, serial, text)
      XCTAssertEqual(found?.formatCode, code, text)
    }
  }

  func testFractions() {
    let excel: [(String, Double?, String?)] = [
      ("1 1/2", 1.5, "# ?/?"), ("0 1/2", 0.5, "# ?/?"), ("2 3/4", 2.75, "# ?/?"),
      ("-1 1/2", -1.5, "# ?/?"), ("1 1/3", 4.0 / 3, "# ?/?"), ("3 10/16", 3.625, "# ??/??"),
      ("1 1/0", nil, nil), ("1/2", nil, nil),
    ]
    for (text, value, code) in excel {
      let found = TypedEntry.fraction(text)
      if let value {
        XCTAssertEqual(found?.value ?? .nan, value, accuracy: 1e-12, text)
      } else {
        XCTAssertNil(found, text)
      }
      XCTAssertEqual(found?.formatCode, code, text)
    }
  }

  private func typed(_ text: String) -> Cell {
    let session = WorkbookSession()
    _ = session.run(id: "cell.set", arguments: ["address": "A1", "raw": text])
    return session.workbook.activeSheet.cell(at: .origin)
  }

  func testTypedIntoACell() {
    let year = Calendar.current.component(.year, from: Date())
    let march4 = TypedEntry.shortDate("3/4", year: year)?.serial
    XCTAssertEqual(typed("3/4").literalValue, .number(Double(march4 ?? 0)))
    XCTAssertEqual(typed("3/4").format?.formatCode, "d-mmm")
    XCTAssertEqual(typed("1 1/2").literalValue, .number(1.5))
    XCTAssertEqual(typed("1 1/2").format?.formatCode, "# ?/?")
    XCTAssertEqual(typed("#n/a").literalValue, .error(.na))
    XCTAssertEqual(typed("#DIV/0!").literalValue, .error(.divZero))
    XCTAssertEqual(typed("'#N/A").literalValue, .string("#N/A"))
  }

  /// A typed error saves as an error cell and opens as one; text "#N/A" stays text.
  func testErrorCellsSaveAsErrors() throws {
    var sheet = Sheet(name: "S")
    sheet.setCell(Cell(raw: "#N/A"), at: .origin)
    var text = Cell(raw: "#N/A")
    text.isText = true
    sheet.setCell(text, at: CellAddress(row: 1, col: 0))
    let data = try XLSXCodec.exportWorkbook(Workbook(sheets: [sheet]))
    let opened = try XLSXCodec.importWorkbook(from: data).activeSheet
    XCTAssertEqual(opened.cell(at: .origin).literalValue, .error(.na))
    XCTAssertEqual(opened.cell(at: CellAddress(row: 1, col: 0)).literalValue, .string("#N/A"))
  }
}

/// Text pasted from another app, or put by a script or an AI assistant, reads as typing reads
/// it; Spark Grid's own pasted cells and pivot tables do not (found in the 1.7 bug test).
@MainActor
final class PastedTextReadsAsTypedTests: XCTestCase {
  private func pasted(_ text: String, typed: Bool) -> Cell {
    let session = WorkbookSession()
    _ = session.run(
      id: "edit.paste",
      arguments: ["anchor": "A1", "text": text, "typed": typed ? "1" : "0"])
    return session.workbook.activeSheet.cell(at: .origin)
  }

  func testTypedPaste() {
    XCTAssertEqual(pasted("1 1/2", typed: true).literalValue, .number(1.5))
    XCTAssertEqual(pasted("$1,234.50", typed: true).literalValue, .number(1234.5))
    XCTAssertEqual(pasted("#n/a", typed: true).literalValue, .error(.na))
    XCTAssertEqual(pasted("1/5/2026", typed: true).literalValue, .number(46027))
  }

  func testOwnPasteKeepsText() {
    XCTAssertEqual(pasted("1 1/2", typed: false).literalValue, .string("1 1/2"))
  }
}
