import Calc
import Engine
import Foundation
import GridCore
import Model
import NumberFormat
import XCTest

@testable import FileFormats

/// `Fixtures/excel-text-formats.xlsx`: TEXT of 8 values (row 1) and a word under 48 format codes
/// (column A), opened, fully recalculated and saved by Excel 16.115 for Mac (Nov 18 2026). Only
/// the last-author name and saved path were replaced afterwards. The codes cover decimals,
/// grouping and scaling, percent, scientific and engineering notation, fractions, digits spread
/// across literals, sections and conditions, padding, and dates and times before 1900, in it,
/// and past 9999.
final class ExcelSavedTextTests: XCTestCase {
  func testTextMatchesExcel() throws {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let data = try Data(contentsOf: root.appendingPathComponent("Fixtures/excel-text-formats.xlsx"))
    let sheet = try XLSXCodec.importWorkbook(from: data).activeSheet
    var excel: [CellAddress: String] = [:]
    for (address, cell) in sheet.cells where cell.importedFormulaResult != nil {
      excel[address] = cell.importedFormulaResult
    }
    let engine = FormulaEngine()
    engine.rebuild(sheet: sheet, recalculate: true)
    XCTAssertEqual(excel.count, 480)
    for (address, value) in excel {
      let code = sheet.cell(at: CellAddress(row: address.row, col: 0)).raw
      let input = sheet.cell(at: CellAddress(row: 0, col: address.col)).raw
      XCTAssertEqual(
        engine.sheetDisplayValue(at: address, sheet: sheet).displayString, value,
        "TEXT(\(input), \(code))")
    }
  }

  /// Asked of Excel 16.115 directly: with a set denominator and no whole part, the numerator
  /// stops at 32,767; past it there is nothing to show. A denominator Excel picks has no limit.
  func testFractionNumeratorLimit() {
    func text(_ value: Double, _ code: String) -> ExcelFormatCode.Outcome {
      ExcelFormatCode.render(value, code: code, fractionDigits: nil)
    }
    XCTAssertEqual(text(4095, "?/8"), .text("32760/8"))
    XCTAssertEqual(text(4096, "?/8"), .invalid)
    XCTAssertEqual(text(-5000, "?/8"), .invalid)
    XCTAssertEqual(text(4096, "?/1"), .text("4096/1"))
    XCTAssertEqual(text(9999, "?/1"), .text("9999/1"))
    XCTAssertEqual(text(99999, "?/1"), .invalid)
    XCTAssertEqual(text(4096, "?/?"), .text("4096/1"))
    XCTAssertEqual(text(5000.5, "??/??"), .text("10001/2 "))
    XCTAssertEqual(text(1234.5678, "??/???"), .text("145679/118"))
    XCTAssertEqual(text(4096, "# ?/8"), .text("4096    "))
    XCTAssertEqual(text(46023.75, "# ?/8"), .text("46023 6/8"))
  }
}
