import GridCore
import Model
import XCTest

@testable import Calc

/// After a step that makes every stored result stale (a sort, an Undo of a paste), a save of a
/// workbook of ordinary size still writes every formula's result.
final class StaleResultsOnSaveTests: XCTestCase {
  func testSmallWorkbookGetsEveryResult() {
    var data = Sheet(name: "Data")
    data.setCell(Cell(raw: "4"), at: CellAddress(row: 0, col: 0))
    data.setCell(
      Cell(raw: "=A1*2", importedFormulaResult: "999", importedFormulaValueType: .number),
      at: CellAddress(row: 0, col: 1))
    var summary = Sheet(name: "Summary")
    summary.setCell(Cell(raw: "=Data!B1+1"), at: .origin)
    let prepared = FormulaCacheWriter.prepare(
      Workbook(sheets: [data, summary]), stamp: FormulaSaveStamp(recalculateAllFormulas: true))
    XCTAssertEqual(
      prepared.sheets[0].cell(at: CellAddress(row: 0, col: 1)).cachedFormulaValue, .number(8))
    XCTAssertEqual(prepared.sheets[1].cell(at: .origin).cachedFormulaValue, .number(9))
  }

  /// A function Spark Grid does not have keeps the result its file saved, even when every other
  /// result is calculated again (a Reddit question, Nov 19).
  func testUnknownFunctionKeepsItsSavedResult() {
    var sheet = Sheet(name: "Data")
    sheet.setCell(
      Cell(
        raw: "=ZZTESTUNKNOWN(5)", importedFormulaResult: "Five Baht",
        importedFormulaValueType: .string),
      at: .origin)
    // Nothing has calculated the cell first: a file opened with its results only shows them.
    let prepared = FormulaCacheWriter.prepare(
      Workbook(sheets: [sheet]), stamp: FormulaSaveStamp(recalculateAllFormulas: true))
    XCTAssertEqual(prepared.sheets[0].cell(at: .origin).cachedFormulaValue, .string("Five Baht"))
    XCTAssertEqual(prepared.sheets[0].cell(at: .origin).raw, "=ZZTESTUNKNOWN(5)")
  }
}
