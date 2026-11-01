import GridCore
import Model
import XCTest

@testable import Calc

/// `TEXT` date and time codes go through `ExcelFormatCode`, not a single date pattern.
@MainActor
final class TextFormatTests: XCTestCase {
  /// 2026-06-01, a Monday. Excel serial days since 1899-12-30.
  private let daySerial = 46_174.0
  /// 15:04:05 on that date.
  private var timeSerial: Double {
    let seconds = Double(15 * 3_600 + 4 * 60 + 5)
    return daySerial + seconds / 86_400
  }

  func testDayCodes() {
    XCTAssertEqual(text("d", serial: daySerial), .string("1"))
    XCTAssertEqual(text("dd", serial: daySerial), .string("01"))
    XCTAssertEqual(text("ddd", serial: daySerial), .string("Mon"))
    XCTAssertEqual(text("dddd", serial: daySerial), .string("Monday"))
  }

  func testMonthAndYearCodes() {
    XCTAssertEqual(text("m", serial: daySerial), .string("6"))
    XCTAssertEqual(text("mm", serial: daySerial), .string("06"))
    XCTAssertEqual(text("mmm", serial: daySerial), .string("Jun"))
    XCTAssertEqual(text("mmmm", serial: daySerial), .string("June"))
    XCTAssertEqual(text("yy", serial: daySerial), .string("26"))
    XCTAssertEqual(text("yyyy", serial: daySerial), .string("2026"))
    XCTAssertEqual(text("yyyy-mm-dd", serial: daySerial), .string("2026-06-01"))
  }

  func testTimeCodes() {
    XCTAssertEqual(text("h", serial: timeSerial), .string("15"))
    XCTAssertEqual(text("hh", serial: timeSerial), .string("15"))
    XCTAssertEqual(text("h:mm", serial: timeSerial), .string("15:04"))
    XCTAssertEqual(text("hh:mm:ss", serial: timeSerial), .string("15:04:05"))
    XCTAssertEqual(text("h:mm AM/PM", serial: timeSerial), .string("3:04 PM"))
    XCTAssertEqual(text("ss", serial: timeSerial), .string("05"))
  }

  func testNumberCodesStayNumeric() {
    XCTAssertEqual(text("0.00", serial: 12.5), .string("12.50"))
    XCTAssertEqual(text("0%", serial: 0.125), .string("13%"))
    XCTAssertEqual(text("0.00%", serial: 0.125), .string("12.50%"))
  }

  private func text(_ code: String, serial: Double) -> CellValue {
    let sheet = Sheet(
      name: "Data",
      cells: [
        CellAddress(row: 0, col: 0): Cell(raw: "\(serial)"),
        CellAddress(row: 0, col: 1): Cell(raw: "=TEXT(A1,\"\(code)\")"),
      ]
    )
    let workbook = Workbook(sheets: [sheet])
    let engine = FormulaEngine()
    engine.rebuild(workbook: workbook, recalculate: false)
    return engine.sheetDisplayValue(at: CellAddress(row: 0, col: 1), sheet: workbook.sheets[0])
  }
}
