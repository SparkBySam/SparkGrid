import Calc
import Foundation
import GridCore
import Model
import XCTest

@testable import FileFormats

/// Two edits on different sheets, the second before the first has reached the other sheets.
/// The second update replaced the first and dropped its cells: on the stress workbook, a new
/// Config threshold followed at once by an edit on another sheet never reached Orders or the
/// Dashboard (found by script, Nov 18).
final class CrossSheetSequenceTests: XCTestCase {
  func testAnEditOnAnotherSheetKeepsTheFirstEditsReach() throws {
    var dash = Sheet(name: "Dash")
    var config = Sheet(name: "Config")
    var orders = Sheet(name: "Orders")
    config.setCell(Cell(raw: "5000"), at: CellAddress(row: 4, col: 1))
    for row in 0..<200 {
      orders.setCell(Cell(raw: String(Double(row % 100) * 100)), at: CellAddress(row: row, col: 0))
      orders.setCell(
        Cell(raw: "=IF(A\(row + 1)>=Config!$B$5,\"Large\",\"OK\")"),
        at: CellAddress(row: row, col: 1))
    }
    dash.setCell(Cell(raw: "=COUNTIF(Orders!B1:B200,\"Large\")"), at: .origin)
    dash.setCell(Cell(raw: "1"), at: CellAddress(row: 0, col: 3))
    dash.setCell(Cell(raw: "=D1*2"), at: CellAddress(row: 0, col: 4))
    // Saved with its results and opened again, as a file is: the app trusts saved results.
    let first = FormulaEngine()
    let built = Workbook(sheets: [dash, config, orders])
    first.rebuild(workbook: built, recalculate: true)
    first.recalculateEntireWorkbook(built)
    let saved = try XLSXCodec.exportWorkbook(
      FormulaCacheWriter.prepare(built, stamp: first.formulaSaveStamp()), includeFormulaCaches: true
    )
    var workbook = try XLSXCodec.importWorkbook(from: saved)
    XCTAssertEqual(
      workbook.sheets[2].cell(at: CellAddress(row: 30, col: 1)).importedFormulaResult, "OK")
    let engine = FormulaEngine()
    engine.rebuild(workbook: workbook, recalculate: false, trustImportedCaches: true)
    engine.prepareDependencyGraph()
    XCTAssertEqual(engine.value(onSheet: "Dash", at: .origin), .number(100))

    // Config: the threshold drops to 3000. Its update is still on its way.
    workbook.activeSheetIndex = 1
    engine.activateSheet(workbook)
    workbook.sheets[1].setCell(Cell(raw: "3000"), at: CellAddress(row: 4, col: 1))
    engine.adoptWorkbook(workbook)
    _ = engine.cellsDidChange([CellAddress(row: 4, col: 1)], sheet: workbook.sheets[1])

    // At once, an edit on Dash.
    workbook.activeSheetIndex = 0
    engine.activateSheet(workbook)
    workbook.sheets[0].setCell(Cell(raw: "5"), at: CellAddress(row: 0, col: 3))
    engine.adoptWorkbook(workbook)
    _ = engine.cellsDidChange([CellAddress(row: 0, col: 3)], sheet: workbook.sheets[0])
    engine.finishPendingCrossSheet()

    XCTAssertEqual(engine.value(onSheet: "Dash", at: .origin), .number(140))
    // Orders shown, as a person would go and look.
    workbook.activeSheetIndex = 2
    engine.activateSheet(workbook)
    XCTAssertEqual(
      engine.sheetDisplayValue(at: CellAddress(row: 30, col: 1), sheet: workbook.sheets[2]),
      .string("Large"))
    workbook.activeSheetIndex = 0
    engine.activateSheet(workbook)
    XCTAssertEqual(engine.value(onSheet: "Dash", at: .origin), .number(140))
    XCTAssertEqual(engine.value(onSheet: "Dash", at: CellAddress(row: 0, col: 4)), .number(10))
  }

  /// A formula typed after the file opened, reading another sheet that reads this one back:
  /// Data!G1 = 'Second Sheet'!B1*2 with B1 = SUM(Data!E1:E6). The workbook graph built at open
  /// did not have the typed formulas, so an edit on Data updated B1 but never G1 (found by
  /// script, Nov 18).
  func testFormulasTypedAfterOpeningJoinTheWorkbookGraph() throws {
    var data = Sheet(name: "Data")
    for (row, amount) in [10, 20, 30, 40, 50, 60].enumerated() {
      data.setCell(Cell(raw: String(amount)), at: CellAddress(row: row, col: 4))
    }
    let saved = try XLSXCodec.exportWorkbook(Workbook(sheets: [data, Sheet(name: "Second Sheet")]))
    var workbook = try XLSXCodec.importWorkbook(from: saved)
    let engine = FormulaEngine()
    engine.rebuild(workbook: workbook, recalculate: false, trustImportedCaches: true)
    engine.prepareDependencyGraph()
    func put(_ sheet: Int, _ row: Int, _ col: Int, _ raw: String) {
      let before = workbook.activeSheetIndex
      if sheet != before {
        workbook.activeSheetIndex = sheet
        engine.activateSheet(workbook)
      }
      workbook.sheets[sheet].setCell(Cell(raw: raw), at: CellAddress(row: row, col: col))
      engine.adoptWorkbook(workbook)
      _ = engine.cellsDidChange([CellAddress(row: row, col: col)], sheet: workbook.sheets[sheet])
      engine.finishPendingCrossSheet()
      if sheet != before {
        workbook.activeSheetIndex = before
        engine.activateSheet(workbook)
      }
    }
    let g1 = CellAddress(row: 0, col: 6)
    put(1, 0, 1, "=SUM(Data!E1:E6)")
    put(0, 0, 6, "='Second Sheet'!B1*2")
    XCTAssertEqual(engine.value(onSheet: "Data", at: g1), .number(420))
    put(0, 2, 4, "100")
    XCTAssertEqual(engine.value(onSheet: "Data", at: g1), .number(560))
    put(0, 4, 4, "1")
    XCTAssertEqual(engine.value(onSheet: "Data", at: g1), .number(462))
  }

  /// INDIRECT's target is known only when it runs, so an edit to the cell it points at, on its
  /// own sheet or another, updates it, as other apps recalculate it on every change.
  func testIndirectFollowsTheCellItNames() throws {
    var data = Sheet(name: "Data")
    data.setCell(Cell(raw: "B"), at: CellAddress(row: 0, col: 0))
    data.setCell(Cell(raw: "10"), at: CellAddress(row: 1, col: 1))
    data.setCell(Cell(raw: "=INDIRECT(A1&\"2\")"), at: CellAddress(row: 0, col: 3))
    data.setCell(Cell(raw: "=SUM(INDIRECT(\"Other!A1:A3\"))"), at: CellAddress(row: 1, col: 3))
    var other = Sheet(name: "Other")
    other.setCell(Cell(raw: "1"), at: .origin)
    let saved = try XLSXCodec.exportWorkbook(Workbook(sheets: [data, other]))
    var workbook = try XLSXCodec.importWorkbook(from: saved)
    let engine = FormulaEngine()
    engine.rebuild(workbook: workbook, recalculate: true)
    engine.prepareDependencyGraph()
    let d1 = CellAddress(row: 0, col: 3)
    let d2 = CellAddress(row: 1, col: 3)
    XCTAssertEqual(engine.value(onSheet: "Data", at: d1), .number(10))
    XCTAssertEqual(engine.value(onSheet: "Data", at: d2), .number(1))
    func put(_ sheet: Int, _ row: Int, _ col: Int, _ raw: String) {
      if workbook.activeSheetIndex != sheet {
        workbook.activeSheetIndex = sheet
        engine.activateSheet(workbook)
      }
      workbook.sheets[sheet].setCell(Cell(raw: raw), at: CellAddress(row: row, col: col))
      engine.adoptWorkbook(workbook)
      _ = engine.cellsDidChange([CellAddress(row: row, col: col)], sheet: workbook.sheets[sheet])
      engine.finishPendingCrossSheet()
      if workbook.activeSheetIndex != 0 {
        workbook.activeSheetIndex = 0
        engine.activateSheet(workbook)
      }
    }
    put(0, 1, 1, "25")  // B2, which D1 reaches through INDIRECT("B2")
    XCTAssertEqual(engine.value(onSheet: "Data", at: d1), .number(25))
    put(0, 1, 2, "7")  // C2
    put(0, 0, 0, "C")  // D1 now reads C2
    XCTAssertEqual(engine.value(onSheet: "Data", at: d1), .number(7))
    put(1, 2, 0, "5")  // Other!A3
    XCTAssertEqual(engine.value(onSheet: "Data", at: d2), .number(6))
  }

  /// A formula whose answer is an empty cell gives 0, as in other apps, on its own sheet and
  /// read from another; formulas reading it see 0, not an empty cell (found by script, Nov 18).
  func testAFormulaPickingAnEmptyCellGivesZero() throws {
    var data = Sheet(name: "Data")
    data.setCell(Cell(raw: "=A3"), at: CellAddress(row: 0, col: 1))
    data.setCell(Cell(raw: "=ISBLANK(B1)"), at: CellAddress(row: 1, col: 1))
    data.setCell(Cell(raw: "=IF(TRUE,A3)"), at: CellAddress(row: 2, col: 1))
    data.setCell(Cell(raw: "=IF(A3=\"\",\"\",1)"), at: CellAddress(row: 3, col: 1))
    var other = Sheet(name: "Other")
    other.setCell(Cell(raw: "=Data!A3"), at: .origin)
    other.setCell(Cell(raw: "=Data!B1&\"x\""), at: CellAddress(row: 1, col: 0))
    let engine = FormulaEngine()
    let workbook = Workbook(sheets: [data, other])
    engine.rebuild(workbook: workbook, recalculate: true)
    engine.prepareDependencyGraph()
    XCTAssertEqual(engine.value(onSheet: "Data", at: CellAddress(row: 0, col: 1)), .number(0))
    XCTAssertEqual(engine.value(onSheet: "Data", at: CellAddress(row: 1, col: 1)), .bool(false))
    XCTAssertEqual(engine.value(onSheet: "Data", at: CellAddress(row: 2, col: 1)), .number(0))
    // An empty string chosen on purpose stays empty.
    XCTAssertEqual(engine.value(onSheet: "Data", at: CellAddress(row: 3, col: 1)), .string(""))
    XCTAssertEqual(engine.value(onSheet: "Other", at: .origin), .number(0))
    XCTAssertEqual(engine.value(onSheet: "Other", at: CellAddress(row: 1, col: 0)), .string("0x"))
    // Spilled, too: SORT over a range with a gap shows 0 there (Excel 16.115).
    var sorted = Sheet(name: "Sorted")
    sorted.setCell(Cell(raw: "1"), at: .origin)
    sorted.setCell(Cell(raw: "3"), at: CellAddress(row: 2, col: 0))
    sorted.setCell(Cell(raw: "=FILTER(A1:A3,TRUE)"), at: CellAddress(row: 0, col: 2))
    let spillEngine = FormulaEngine()
    spillEngine.rebuild(sheet: sorted, recalculate: true)
    let spilled = spillEngine.spillArray(
      at: CellAddress(row: 0, col: 2), sheet: sorted, activeSheet: sorted)
    XCTAssertEqual(spilled?.values, [.number(1), .number(0), .number(3)])
  }

  /// OFFSET reads a range found when it runs, so it updates after any edit, like INDIRECT.
  func testOffsetFollowsTheRangeItFinds() throws {
    var data = Sheet(name: "Data")
    for row in 0..<4 { data.setCell(Cell(raw: String(row + 1)), at: CellAddress(row: row, col: 0)) }
    data.setCell(Cell(raw: "2"), at: CellAddress(row: 0, col: 2))
    data.setCell(Cell(raw: "=SUM(OFFSET(A1,1,0,C1))"), at: CellAddress(row: 0, col: 3))
    var workbook = Workbook(sheets: [data])
    let engine = FormulaEngine()
    engine.rebuild(workbook: workbook, recalculate: true)
    engine.prepareDependencyGraph()
    let d1 = CellAddress(row: 0, col: 3)
    XCTAssertEqual(engine.value(onSheet: "Data", at: d1), .number(5))  // A2:A3
    func put(_ row: Int, _ col: Int, _ raw: String) {
      workbook.sheets[0].setCell(Cell(raw: raw), at: CellAddress(row: row, col: col))
      engine.adoptWorkbook(workbook)
      _ = engine.cellsDidChange([CellAddress(row: row, col: col)], sheet: workbook.sheets[0])
      engine.finishPendingCrossSheet()
    }
    put(0, 2, "3")  // now A2:A4
    XCTAssertEqual(engine.value(onSheet: "Data", at: d1), .number(9))
    put(3, 0, "40")  // A4
    XCTAssertEqual(engine.value(onSheet: "Data", at: d1), .number(45))
  }
}
