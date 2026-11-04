import GridCore
import Model
import XCTest

/// A table's built-in style paints its header and banded rows under the cells' own formats.
final class TableStyleTests: XCTestCase {
  private let xml =
    #"<table id="1" name="Deals" displayName="Deals" ref="A57:E62" headerRowCount="1" xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><autoFilter ref="A57:E62" /><tableColumns count="5"/><tableStyleInfo name="TableStyleMedium2" showRowStripes="1" /></table>"#

  private func sheet() -> Sheet {
    var sheet = Sheet(name: "New in 1.2")
    let range = CellRange(start: CellAddress(row: 56, col: 0), end: CellAddress(row: 61, col: 4))
    sheet.fileExtras.tables = [SheetTable(range: range, xml: xml)]
    var own = CellFormat()
    own.fillColor = CodableColor(red: 1, green: 0, blue: 0, alpha: 1)
    sheet.setCell(Cell(raw: "Mine", format: own), at: CellAddress(row: 59, col: 2))
    return sheet
  }

  func testHeaderIsTheAccentWithWhiteBoldText() throws {
    let header = try XCTUnwrap(sheet().formatWithTableStyle(at: CellAddress(row: 56, col: 1)))
    XCTAssertEqual(header.fillColor?.blue ?? 0, 0.77, accuracy: 0.01)
    XCTAssertEqual(header.textColor, CodableColor(red: 1, green: 1, blue: 1, alpha: 1))
    XCTAssertTrue(header.bold)
  }

  func testEveryOtherDataRowIsBanded() {
    let s = sheet()
    XCTAssertNotNil(s.formatWithTableStyle(at: CellAddress(row: 57, col: 0))?.fillColor)
    XCTAssertNil(s.formatWithTableStyle(at: CellAddress(row: 58, col: 0))?.fillColor)
    XCTAssertNotNil(s.formatWithTableStyle(at: CellAddress(row: 59, col: 0))?.fillColor)
  }

  func testACellsOwnFillWinsAndOutsideIsUntouched() {
    let s = sheet()
    XCTAssertEqual(
      s.formatWithTableStyle(at: CellAddress(row: 59, col: 2))?.fillColor,
      CodableColor(red: 1, green: 0, blue: 0, alpha: 1))
    XCTAssertNil(s.formatWithTableStyle(at: CellAddress(row: 70, col: 0)))
  }
}
