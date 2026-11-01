import GridCore
import XCTest

final class GridCoreTests: XCTestCase {
  @MainActor
  func testColumnLabel() {
    XCTAssertEqual(A1Notation.columnLabel(for: 0), "A")
    XCTAssertEqual(A1Notation.columnLabel(for: 25), "Z")
    XCTAssertEqual(A1Notation.columnLabel(for: 26), "AA")
    XCTAssertEqual(A1Notation.columnIndex(from: "AA"), 26)
  }
}
