import GridCore
import Model
import NumberFormat
import XCTest

@testable import FileFormats
@testable import Rendering

/// Save As › Tab-Separated Text and Web Page (1.7).
@MainActor
final class WebPageAndTSVExportTests: XCTestCase {
  func testTabSeparatedTextQuotesOnlyWhenNeeded() {
    let sheet = Sheet(
      name: "S",
      cells: [
        CellAddress(row: 0, col: 0): Cell(raw: "Name"),
        CellAddress(row: 0, col: 1): Cell(raw: "=SUM(B2:B3)"),
        CellAddress(row: 1, col: 0): Cell(raw: "a\tb"),
        CellAddress(row: 1, col: 1): Cell(raw: "say \"hi\""),
        CellAddress(row: 2, col: 1): Cell(raw: "3"),
      ])
    XCTAssertEqual(
      CSVCodec.exportTSV(from: sheet),
      "Name\t=SUM(B2:B3)\n\"a\tb\"\t\"say \"\"hi\"\"\"\n\t3")
  }

  func testWebPageShowsWhatCellsShow() {
    var bold = CellFormat()
    bold.bold = true
    var money = CellFormat()
    money.numberFormat = .currency
    let total = Cell(
      raw: "=B2*2", format: money, importedFormulaResult: "2468", importedFormulaValueType: .number)
    let sheet = Sheet(
      name: "Sales & More",
      cells: [
        CellAddress(row: 0, col: 0): Cell(raw: "<Title>", format: bold),
        CellAddress(row: 1, col: 1): Cell(raw: "1234"),
        CellAddress(row: 1, col: 2): total,
      ],
      mergedRanges: [
        CellRange(start: CellAddress(row: 0, col: 0), end: CellAddress(row: 0, col: 2))
      ])
    var hidden = Sheet(name: "Secret", cells: [CellAddress(row: 0, col: 0): Cell(raw: "x")])
    hidden.fileExtras.visibility = .hidden
    let html = HTMLExporter.export(Workbook(sheets: [sheet, hidden]), title: "Book")
    XCTAssertTrue(html.contains("<title>Book</title>"))
    XCTAssertTrue(html.contains("&lt;Title&gt;"))
    XCTAssertTrue(html.contains("colspan=\"3\""))
    XCTAssertTrue(html.contains("font-weight:bold"))
    XCTAssertTrue(html.contains("$2468.00"), html)
    XCTAssertFalse(html.contains("=B2*2"))
    XCTAssertFalse(html.contains("Secret"))
  }
}
