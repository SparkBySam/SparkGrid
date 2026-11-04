import Calc
import FileFormats
import GridCore
import Model
import XCTest

/// Highlight Duplicates and Highlight Unique mark repeated and one-off values in a range.
@MainActor
final class DuplicateHighlightTests: XCTestCase {
  /// A1:A6 is apple, Pear, APPLE, blank, kiwi, pear.
  private func sheet(_ predicate: ConditionalFormatPredicate) -> Sheet {
    var sheet = Sheet(name: "Fruit")
    for (row, value) in ["apple", "Pear", "APPLE", "", "kiwi", "pear"].enumerated()
    where !value.isEmpty {
      sheet.setCell(Cell(raw: value), at: CellAddress(row: row, col: 0))
    }
    sheet.conditionalFormats = [
      ConditionalFormatRule(
        range: CellRange(start: .origin, end: CellAddress(row: 5, col: 0)),
        predicate: predicate, style: .redFill)
    ]
    return sheet
  }

  private func marked(_ sheet: Sheet) -> [Bool] {
    let engine = FormulaEngine()
    engine.rebuild(workbook: Workbook(sheets: [sheet]))
    return (0..<6).map { row in
      let address = CellAddress(row: row, col: 0)
      let value = engine.displayValue(at: address, sheet: sheet)
      let paint = ConditionalFormatEvaluator.resolvedPaint(
        at: address, base: nil, rules: sheet.conditionalFormats, value: value,
        displayString: value.displayString, numberFormat: nil,
        numericValuesInRange: { _ in [] },
        evaluateFormula: { raw, at, origin in
          engine.evaluateConditionalFormula(raw, at: at, relativeTo: origin, sheet: sheet)
        })
      return paint.format?.fillColor != nil
    }
  }

  func testDuplicatesIgnoreCaseAndSkipBlanks() {
    XCTAssertEqual(marked(sheet(.duplicateValues)), [true, true, true, false, false, true])
  }

  func testUniqueMarksValuesThatAppearOnce() {
    XCTAssertEqual(marked(sheet(.uniqueValues)), [false, false, false, false, true, false])
  }

  func testDuplicateRuleSavesAsADuplicateValuesRule() throws {
    let data = try XLSXCodec.exportWorkbook(Workbook(sheets: [sheet(.duplicateValues)]))
    let xml = XLSXCodec.zipEntryString(archiveData: data, entryPath: "xl/worksheets/sheet1.xml")
    XCTAssertTrue(xml?.contains(#"type="duplicateValues""#) == true)
    let reopened = try XLSXCodec.importWorkbook(from: data).sheets[0]
    XCTAssertEqual(reopened.conditionalFormats.first?.predicate, .duplicateValues)
  }
}
