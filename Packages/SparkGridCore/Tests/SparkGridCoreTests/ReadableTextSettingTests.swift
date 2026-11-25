import XCTest

@testable import SparkGridCore

/// Settings › Readable text on filled cells (Nov 23): on, a conditional fill changes text to a
/// color that reads on it; off, text keeps its own color, as other apps show it.
final class ReadableTextSettingTests: XCTestCase {
  private let dark = CodableColor(red: 0.1, green: 0.1, blue: 0.2, alpha: 1)

  private func paint(base: CellFormat?, readableText: Bool) -> ConditionalPaint {
    let rule = ConditionalFormatRule(
      range: CellRange(start: .origin, end: .origin),
      predicate: .greaterThan(0),
      style: ConditionalFormatStyle(fillColor: dark))
    return ConditionalFormatEvaluator.resolvedPaint(
      at: .origin, base: base, rules: [rule], value: .number(5), displayString: "5",
      numberFormat: nil, numericValuesInRange: { _ in [] },
      evaluateFormula: { _, _, _ in .blank }, readableText: readableText)
  }

  func testOnTurnsTextLightOnADarkConditionalFill() {
    let text = paint(base: nil, readableText: true).format?.textColor
    XCTAssertGreaterThan(text?.relativeLuminance ?? 0, 0.8)
  }

  func testOffKeepsTheCellsOwnTextColor() {
    var base = CellFormat()
    base.textColor = CodableColor(red: 0, green: 0, blue: 0, alpha: 1)
    let format = paint(base: base, readableText: false).format
    XCTAssertEqual(format?.textColor, base.textColor)
    XCTAssertEqual(format?.fillColor, dark)
  }

  func testOffLeavesTextWithNoColorAlone() {
    XCTAssertNil(paint(base: nil, readableText: false).format?.textColor)
  }

  func testTheDefaultIsOn() {
    let text = ConditionalFormatEvaluator.resolvedPaint(
      at: .origin, base: nil,
      rules: [
        ConditionalFormatRule(
          range: CellRange(start: .origin, end: .origin), predicate: .greaterThan(0),
          style: ConditionalFormatStyle(fillColor: dark))
      ], value: .number(5), displayString: "5", numberFormat: nil,
      numericValuesInRange: { _ in [] }, evaluateFormula: { _, _, _ in .blank }
    ).format?.textColor
    XCTAssertNotNil(text)
  }
}
