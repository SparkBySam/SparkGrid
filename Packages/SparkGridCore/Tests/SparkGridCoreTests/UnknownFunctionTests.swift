import Formula
import GridCore
import Model
import XCTest

@testable import Calc

/// A formula that calls a function Spark Grid does not have shows the result its file saved, on
/// the sheet and in the whole-workbook pass; one with nothing saved still shows #NAME?.
final class UnknownFunctionTests: XCTestCase {
  private func sheet() -> Sheet {
    Sheet(
      name: "Data",
      cells: [
        CellAddress(row: 0, col: 0): Cell(
          raw: "=BAHTTEXT(5)", importedFormulaResult: "Five Baht",
          importedFormulaValueType: .string),
        CellAddress(row: 0, col: 1): Cell(raw: "=LEN(A1)"),
        CellAddress(row: 1, col: 0): Cell(raw: "=NOTAFUNCTION(1)"),
        CellAddress(row: 2, col: 0): Cell(
          raw: "=SUM(1,2)+NOTAFUNCTION(1)", importedFormulaResult: "#NAME?",
          importedFormulaValueType: .error),
      ])
  }

  func testOnTheSheet() {
    let sheet = sheet()
    let engine = FormulaEngine()
    engine.rebuild(workbook: Workbook(sheets: [sheet]), recalculate: false)
    XCTAssertEqual(
      engine.sheetDisplayValue(at: CellAddress(row: 0, col: 0), sheet: sheet), .string("Five Baht"))
    XCTAssertEqual(
      engine.sheetDisplayValue(at: CellAddress(row: 0, col: 1), sheet: sheet), .number(9))
    XCTAssertEqual(
      engine.sheetDisplayValue(at: CellAddress(row: 1, col: 0), sheet: sheet), .error(.name))
    XCTAssertEqual(
      engine.sheetDisplayValue(at: CellAddress(row: 2, col: 0), sheet: sheet), .error(.name))
  }

  func testWholeWorkbookPass() {
    let outcome = CrossSheetBackground.calculateAllFormulas(in: Workbook(sheets: [sheet()]))
    let values = outcome.valuesBySheet.values.first ?? [:]
    XCTAssertEqual(values[CellAddress(row: 0, col: 0)], .string("Five Baht"))
    XCTAssertEqual(values[CellAddress(row: 0, col: 1)], .number(9))
    XCTAssertEqual(values[CellAddress(row: 1, col: 0)], .error(.name))
  }

  func testKnownFunctionsAreNotUnknown() {
    let expr = try? FormulaParser.parse("=SUM(1,2)")
    XCTAssertFalse(expr.map(UnknownFunctions.called) ?? true)
  }
}
