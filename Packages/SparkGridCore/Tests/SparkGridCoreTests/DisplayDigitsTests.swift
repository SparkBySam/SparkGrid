import GridCore
import XCTest

/// Numbers show and turn into text with at most 15 significant digits, as Excel's General.
final class DisplayDigitsTests: XCTestCase {
  func testFloatingPointNoiseIsHidden() {
    XCTAssertEqual(CellValue.number(186_000 * 0.7).displayString, "130200")
    XCTAssertEqual(CellValue.number(0.1 + 0.2).displayString, "0.3")
    XCTAssertEqual(CellValue.number(1.0 / 3.0).displayString, "0.333333333333333")
  }

  func testOrdinaryNumbersAreUnchanged() {
    XCTAssertEqual(CellValue.number(42).displayString, "42")
    XCTAssertEqual(CellValue.number(-2.5).displayString, "-2.5")
    XCTAssertEqual(CellValue.number(1_463.095).displayString, "1463.095")
    XCTAssertEqual(CellValue.number(0.000125).displayString, "0.000125")
  }
}
