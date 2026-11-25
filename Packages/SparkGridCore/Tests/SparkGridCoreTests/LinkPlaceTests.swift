import XCTest

@testable import GridCore
@testable import Model

/// A jump within the workbook saved as an outside address starting with `#` (openpyxl does
/// this) is a place, as other apps treat it (Nov 23).
final class LinkPlaceTests: XCTestCase {
  private let cell = CellRange(start: .origin, end: .origin)

  func testHashTargetIsAPlace() {
    let link = CellHyperlink(range: cell, target: "#'Orders'!A1")
    XCTAssertEqual(link.place, "'Orders'!A1")
    XCTAssertNil(link.outsideTarget)
  }

  func testLocationWins() {
    let link = CellHyperlink(range: cell, target: "#Other!B2", location: "Sheet2!A1")
    XCTAssertEqual(link.place, "Sheet2!A1")
  }

  func testWebAddressIsOutside() {
    let link = CellHyperlink(range: cell, target: "https://example.com")
    XCTAssertNil(link.place)
    XCTAssertEqual(link.outsideTarget, "https://example.com")
  }

  func testBareHashIsNothing() {
    XCTAssertNil(CellHyperlink(range: cell, target: "#").place)
  }
}
