import GridCore
import Model
import XCTest

@testable import Calc

final class CellsDidChangeTests: XCTestCase {
  func testCellsDidChangeReportsDependentsWhoseValueChanged() {
    let a1 = CellAddress(row: 0, col: 0)
    let b1 = CellAddress(row: 0, col: 1)
    let c1 = CellAddress(row: 0, col: 2)
    let sheet = Sheet(
      name: "Data",
      cells: [
        a1: Cell(raw: "5"),
        b1: Cell(raw: "=A1"),
        c1: Cell(raw: "=10"),
      ]
    )
    let workbook = Workbook(sheets: [sheet])
    let engine = FormulaEngine()
    engine.rebuild(workbook: workbook, recalculate: false)
    _ = engine.sheetDisplayValue(at: b1, sheet: sheet)
    _ = engine.sheetDisplayValue(at: c1, sheet: sheet)
    let builds = engine.dependencyGraphBuildCount

    var edited = sheet
    edited.setCell(Cell(raw: "6"), at: a1)
    var next = workbook
    next.sheets[0] = edited
    engine.adoptWorkbook(next)
    let changed = engine.cellsDidChange([a1], sheet: edited)

    XCTAssertEqual(engine.dependencyGraphBuildCount, builds)
    let addresses = changed["Data"] ?? []
    XCTAssertTrue(addresses.contains(a1))
    XCTAssertTrue(addresses.contains(b1))
    XCTAssertFalse(addresses.contains(c1))
    XCTAssertEqual(engine.sheetDisplayValue(at: b1, sheet: edited), .number(6))
    XCTAssertEqual(engine.sheetDisplayValue(at: c1, sheet: edited), .number(10))
  }

  func testCrossSheetPassReturnsTheCellWhoseValueChanged() {
    let a1 = CellAddress(row: 0, col: 0)
    let data = Sheet(name: "Data", cells: [a1: Cell(raw: "1")])
    let total = Sheet(name: "Total", cells: [a1: Cell(raw: "=Data!A1")])
    var workbook = Workbook(sheets: [data, total])
    let engine = FormulaEngine()
    engine.rebuild(workbook: workbook, recalculate: false)
    engine.prepareDependencyGraph()
    let builds = engine.dependencyGraphBuildCount

    var edited = data
    edited.setCell(Cell(raw: "2"), at: a1)
    workbook.sheets[0] = edited
    engine.adoptWorkbook(workbook)
    let local = engine.cellsDidChange([a1], sheet: edited)
    let external = engine.finishPendingCrossSheet()

    XCTAssertEqual(engine.dependencyGraphBuildCount, builds)
    XCTAssertTrue(local["Data"]?.contains(a1) == true)
    XCTAssertTrue(external["Total"]?.contains(a1) == true, "\(external)")
  }
}
