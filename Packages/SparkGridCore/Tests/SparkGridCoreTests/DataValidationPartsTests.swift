import GridCore
import Model
import XCTest

/// A validation rule's parts read back as written, and a file's rule read as Excel wrote it.
final class DataValidationPartsTests: XCTestCase {
  func testWrittenRuleReadsBack() {
    var parts = DataValidationRule.Parts()
    parts.kind = .decimal
    parts.comparison = .greaterThan
    parts.formula1 = "=$B$1*2"
    parts.alertStyle = .warning
    parts.errorTitle = "Too small"
    parts.error = "Use more than \"twice B1\" & check <it>."
    parts.prompt = "A number"
    parts.showInput = true
    let rule = DataValidationRule(
      ranges: [CellRange(start: CellAddress(row: 0, col: 0), end: CellAddress(row: 4, col: 0))],
      parts: parts)
    XCTAssertEqual(rule.parts.kind, .decimal)
    XCTAssertEqual(rule.parts.comparison, .greaterThan)
    XCTAssertEqual(rule.parts.formula1, "$B$1*2")
    XCTAssertEqual(rule.parts.alertStyle, .warning)
    XCTAssertEqual(rule.parts.error, parts.error)
    XCTAssertEqual(rule.parts.prompt, "A number")
    XCTAssertTrue(rule.parts.showError)
    XCTAssertFalse(rule.body.contains("formula2"))
  }

  func testExcelRule() {
    let rule = DataValidationRule(
      ranges: [],
      attributes:
        #"type="date" operator="greaterThanOrEqual" allowBlank="1" showInputMessage="1" showErrorMessage="1" errorTitle="Date" error="On or after today" promptTitle="When?""#,
      body: "<formula1>TODAY()</formula1>")
    let parts = rule.parts
    XCTAssertEqual(parts.kind, .date)
    XCTAssertEqual(parts.comparison, .greaterThanOrEqual)
    XCTAssertEqual(parts.formula1, "TODAY()")
    XCTAssertEqual(parts.alertStyle, .stop)
    XCTAssertEqual(parts.promptTitle, "When?")
    XCTAssertTrue(parts.allowBlank)
  }
}
