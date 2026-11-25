import XCTest

@testable import Formula

/// Formula Help drops sheet names the formula doesn't need: its own sheet, and sheets the
/// workbook doesn't have. Names of other sheets stay.
final class SheetPrefixesTests: XCTestCase {
  func testDropsMadeUpAndOwnSheetNames() {
    XCTAssertEqual(
      SheetPrefixes.keepingOnly(["Data"], in: "=SUMIF(Sheet1!B2:B5,1200)"), "=SUMIF(B2:B5,1200)")
    XCTAssertEqual(
      SheetPrefixes.keepingOnly(["Data"], in: "=SUM(Report!$B$2:$B$9)+'Report'!C1"),
      "=SUM($B$2:$B$9)+C1")
    XCTAssertEqual(
      SheetPrefixes.keepingOnly([], in: "Sums the values in Sheet1!B2:B5 that equal 1200."),
      "Sums the values in B2:B5 that equal 1200.")
  }

  func testKeepsOtherSheetsStringsAndPlainText() {
    XCTAssertEqual(
      SheetPrefixes.keepingOnly(["Q1 Sales", "Data"], in: "='Q1 Sales'!B2+data!A:A+Report!C3"),
      "='Q1 Sales'!B2+data!A:A+C3")
    XCTAssertEqual(
      SheetPrefixes.keepingOnly([], in: "=COUNTIF(A2:A9,\"Sheet1!B2\")"),
      "=COUNTIF(A2:A9,\"Sheet1!B2\")")
    XCTAssertEqual(SheetPrefixes.keepingOnly([], in: "Wow! It adds B2."), "Wow! It adds B2.")
    XCTAssertEqual(
      SheetPrefixes.keepingOnly(["It's"], in: "='It''s'!A1+'Gone'!A1"), "='It''s'!A1+A1")
  }
}
