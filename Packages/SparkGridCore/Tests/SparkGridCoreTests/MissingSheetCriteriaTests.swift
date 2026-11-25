import GridCore
import Model
import XCTest

@testable import Calc

/// SUMIF, COUNTIF and the other criteria functions over a sheet the workbook doesn't have give
/// #REF!, as `=Nope!A1` and `=SUM(Nope!A1:A3)` do, not 0. Formula Help's model wrote
/// `=SUMIF(Sheet1!B2:B5,1200)` for a sheet named Report and the cell showed 0 (Nov 20).
@MainActor
final class MissingSheetCriteriaTests: XCTestCase {
  func testCriteriaFunctionsOnAMissingSheetAreRefErrors() {
    let data = Sheet(
      name: "Data",
      cells: [
        CellAddress(row: 0, col: 0): Cell(raw: "1"),
        CellAddress(row: 1, col: 0): Cell(raw: "2"),
        CellAddress(row: 2, col: 0): Cell(raw: "1"),
      ]
    )
    let formulas = [
      "=SUMIF(Nope!A1:A3,1)",
      "=COUNTIF(Nope!A1:A3,1)",
      "=AVERAGEIF(Nope!A1:A3,1)",
      "=SUMIFS(Nope!A1:A3,Data!A1:A3,1)",
      "=COUNTIFS(Data!A1:A3,1,Nope!A1:A3,1)",
      "=MAXIFS(Nope!A1:A3,Data!A1:A3,1)",
      "=COUNTBLANK(Nope!A1:A3)",
      "=SUMIF(Data!A1:A3,1,Nope!A1:A3)",
    ]
    // Still numbers: another sheet that exists, this sheet by name, and this sheet's own cells.
    let working = [
      ("=SUMIF(Data!A1:A3,1)", 2.0),
      ("=COUNTIF(Data!A1:A3,1)", 2.0),
      ("=COUNTIF('Report'!A1:A3,1)", 0.0),
      ("=SUMIFS(Data!A1:A3,Data!A1:A3,\">0\")", 4.0),
      ("=COUNTBLANK(Z1:Z3)", 3.0),
    ]
    var cells: [CellAddress: Cell] = [:]
    for (row, formula) in formulas.enumerated() {
      cells[CellAddress(row: row, col: 1)] = Cell(raw: formula)
    }
    for (row, item) in working.enumerated() {
      cells[CellAddress(row: row, col: 2)] = Cell(raw: item.0)
    }
    let report = Sheet(name: "Report", cells: cells)
    let workbook = Workbook(sheets: [report, data])
    let engine = FormulaEngine()
    engine.rebuild(workbook: workbook, recalculate: true)
    for (row, formula) in formulas.enumerated() {
      XCTAssertEqual(
        engine.sheetDisplayValue(at: CellAddress(row: row, col: 1), sheet: report),
        .error(.ref), formula)
    }
    for (row, item) in working.enumerated() {
      XCTAssertEqual(
        engine.sheetDisplayValue(at: CellAddress(row: row, col: 2), sheet: report),
        .number(item.1), item.0)
    }
  }
}
