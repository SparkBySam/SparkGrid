import Engine
import Foundation
import GridCore
import Model
import XCTest

/// Entries typed the way people write them, against what Excel 16.115 stored for the same
/// typing (value and number format, asked by AppleScript on Nov 18).
@MainActor
final class TypedEntryTests: XCTestCase {
  private func typed(_ text: String) -> Cell {
    let session = WorkbookSession()
    _ = session.run(id: "cell.set", arguments: ["address": "A1", "raw": text])
    return session.workbook.activeSheet.cell(at: .origin)
  }

  func testTypedEntriesMatchExcel() {
    let excel: [(String, Double?, String?)] = [
      ("1,234", 1234, "#,##0"),
      ("1,234.5", 1234.5, "#,##0.00"),
      ("-1,234", -1234, "#,##0"),
      ("$1,234.50", 1234.5, "$#,##0.00_);[Red]($#,##0.00)"),
      ("$1234", 1234, "$#,##0_);[Red]($#,##0)"),
      ("$5.5", 5.5, "$#,##0.00_);[Red]($#,##0.00)"),
      ("(5)", -5, nil),
      ("($1,234.50)", -1234.5, "$#,##0.00_);[Red]($#,##0.00)"),
      ("10:30", 0.4375, "h:mm"),
      ("10:30 PM", 0.9375, "h:mm AM/PM"),
      ("10:30:15", 37815.0 / 86400, "h:mm:ss"),
      ("9:05 am", 32700.0 / 86400, "h:mm AM/PM"),
      ("25:00", 90000.0 / 86400, "[h]:mm:ss"),
      ("10:30:15 PM", 81015.0 / 86400, "h:mm:ss AM/PM"),
      ("12:00 AM", 0, "h:mm AM/PM"),
      ("10:30PM", nil, nil),
      ("1,23", nil, nil),
      ("12,34,567", nil, nil),
    ]
    for (text, value, code) in excel {
      let cell = typed(text)
      switch (value, cell.literalValue) {
      case (let expected?, .number(let stored)):
        XCTAssertEqual(stored, expected, accuracy: 1e-12, text)
      case (nil, .string(let stored)):
        XCTAssertEqual(stored, text, text)
      default:
        XCTFail("\(text): stored \(cell.raw) as \(cell.literalValue)")
      }
      XCTAssertEqual(cell.format?.formatCode, code, text)
    }
  }

  /// A typed time shows as typed in the formula bar, and typing that back stores the same.
  func testTypedTimesEditAsTyped() {
    for text in ["10:30", "10:30:15", "9:05 AM", "10:30 PM", "25:00:00", "12:00 AM"] {
      let cell = typed(text)
      XCTAssertEqual(cell.editableText, text, text)
      XCTAssertEqual(typed(cell.editableText).raw, cell.raw, text)
    }
  }

  func testCommasMustGroupThousands() {
    XCTAssertEqual(CellValue.fromLiteralRaw("1,234,567.25"), .number(1_234_567.25))
    XCTAssertEqual(CellValue.fromLiteralRaw("1,23"), .string("1,23"))
    XCTAssertEqual(CellValue.fromLiteralRaw("12,34,567"), .string("12,34,567"))
    XCTAssertEqual(CellValue.fromLiteralRaw("-12,000"), .number(-12_000))
  }
}
