import Foundation
import GridCore
import Model
import XCTest

@testable import FileFormats

/// A Numbers table's look comes in: each cell's fill, text color, bold, italic, font, size and
/// alignment; the table's bold, gray header row and column; and its column widths and row
/// heights. Colors match Numbers' own Excel export of the same file.
final class NumbersStyleTests: XCTestCase {
  private var sheet: Sheet!

  override func setUpWithError() throws {
    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("Fixtures/numbers-styles.numbers")
    sheet = try NumbersImporter.importWorkbook(from: url).sheets[0]
  }

  private func format(_ a1: String) -> CellFormat {
    sheet.cell(at: XLSXCodec.parseCellRange(a1)!.start).format ?? CellFormat()
  }

  private func hex(_ color: CodableColor?) -> String? {
    color.map {
      String(format: "%02X%02X%02X", Int($0.red * 255), Int($0.green * 255), Int($0.blue * 255))
    }
  }

  func testCellStyles() {
    XCTAssertEqual(hex(format("A2").fillColor), "FF2600")
    XCTAssertEqual(hex(format("B2").textColor), "0432FF")
    XCTAssertTrue(format("C2").bold)
    XCTAssertEqual(format("C2").fontFamily, "Helvetica")
    XCTAssertEqual(format("C2").fontSize, 20)
    XCTAssertTrue(format("C3").italic)
    XCTAssertEqual(format("B3").horizontalAlign, .center)
    XCTAssertEqual(format("A3").horizontalAlign, .right)
    XCTAssertEqual(hex(format("A4").fillColor), "00A700")
    XCTAssertEqual(hex(format("A4").textColor), "FFFEFF")
    XCTAssertTrue(format("A4").bold)
    // Plain cells stay plain, in Spark Grid's own font.
    XCTAssertNil(format("D2").fontFamily)
    XCTAssertNil(format("D2").fillColor)
  }

  func testHeaderRowAndColumn() {
    // The header row is bold on gray across the table, empty cells too.
    XCTAssertTrue(format("E1").bold)
    XCTAssertEqual(hex(format("E1").fillColor), "BDC0BF")
    // The header column is bold on a lighter gray; a cell's own fill wins.
    XCTAssertEqual(hex(format("A3").fillColor), "DBDBDB")
    XCTAssertTrue(format("A3").bold)
    XCTAssertEqual(hex(format("A2").fillColor), "FF2600")
    XCTAssertFalse(format("B3").bold)
  }

  func testColumnWidthsAndRowHeights() {
    XCTAssertEqual(sheet.columnWidths[1], 150)
    XCTAssertEqual(sheet.columnWidths[0], 98)
    XCTAssertEqual(sheet.rowHeights[3], 40)
    // Row 2 holds 20 point text; Numbers fits the row to it without saving a height.
    XCTAssertEqual(sheet.rowHeights[1], 28)
    XCTAssertNil(sheet.rowHeights[2])
  }
}
