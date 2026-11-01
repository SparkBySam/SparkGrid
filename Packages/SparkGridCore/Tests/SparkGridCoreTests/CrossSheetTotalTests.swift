import GridCore
import Model
import XCTest

@testable import Calc

/// A summary sheet can be calculated before the sheet it reads. The total is still the count.
@MainActor
final class CrossSheetTotalTests: XCTestCase {
  func testSummarySumsACountIfOnALaterSheet() {
    let january = Sheet(
      name: "January",
      cells: [
        CellAddress(row: 0, col: 0): Cell(raw: "cat"),
        CellAddress(row: 0, col: 2): Cell(raw: "cat"),
        CellAddress(row: 1, col: 2): Cell(raw: "cat"),
        CellAddress(row: 0, col: 3): Cell(raw: "=COUNTIF(C1:C2,A1)"),
      ]
    )
    let summary = Sheet(
      name: "Summary",
      cells: [
        CellAddress(row: 0, col: 0): Cell(raw: "=January!D1")
      ]
    )
    let workbook = Workbook(sheets: [summary, january])
    let engine = FormulaEngine()
    engine.rebuild(workbook: workbook, recalculate: false)
    let value = engine.sheetDisplayValue(
      at: CellAddress(row: 0, col: 0), sheet: workbook.sheets[0])
    XCTAssertEqual(value, .number(2))
  }

  /// Summary reads the end of a 500-row chain on another sheet. The chain is deeper than the
  /// recursion limit; it used to come back #VALUE! instead of 500.
  func testSummaryReadsTheEndOfALongChainOnAnotherSheet() {
    var chainCells: [CellAddress: Cell] = [CellAddress(row: 0, col: 0): Cell(raw: "1")]
    for row in 1..<500 {
      chainCells[CellAddress(row: row, col: 0)] = Cell(raw: "=A\(row)+1")
    }
    let chain = Sheet(name: "Chain", cells: chainCells)
    let summary = Sheet(
      name: "Summary",
      cells: [CellAddress(row: 0, col: 0): Cell(raw: "=Chain!A500")]
    )
    let workbook = Workbook(sheets: [summary, chain])
    let engine = FormulaEngine()
    engine.rebuild(workbook: workbook, recalculate: false)
    let value = engine.sheetDisplayValue(
      at: CellAddress(row: 0, col: 0), sheet: workbook.sheets[0])
    XCTAssertEqual(value, .number(500))
  }

  /// April's `=B1*2` is read from Summary after a sheet switch. B1 still has its
  /// calculated value but is no longer parsed. The read gets 5, not a blank.
  func testCrossSheetReadAfterASheetSwitchUsesTheCalculatedPrecedent() {
    let a1 = CellAddress(row: 0, col: 0)
    let b1 = CellAddress(row: 0, col: 1)
    let c1 = CellAddress(row: 0, col: 2)
    let d1 = CellAddress(row: 0, col: 3)
    let april = Sheet(
      name: "April",
      cells: [
        a1: Cell(raw: "5"),
        b1: Cell(raw: "=A1"),
        c1: Cell(raw: "=B1*2"),
        d1: Cell(raw: "=Summary!A1"),
      ]
    )
    let summary = Sheet(name: "Summary", cells: [a1: Cell(raw: "=April!C1")])
    var workbook = Workbook(sheets: [april, summary])
    let engine = FormulaEngine()
    engine.rebuild(workbook: workbook, recalculate: false)
    XCTAssertEqual(engine.sheetDisplayValue(at: b1, sheet: workbook.sheets[0]), .number(5))
    workbook.activeSheetIndex = 1
    engine.activateSheet(workbook)
    workbook.activeSheetIndex = 0
    engine.activateSheet(workbook)

    XCTAssertEqual(engine.sheetDisplayValue(at: d1, sheet: workbook.sheets[0]), .number(10))
  }

  /// Two sheets use the same unqualified COUNTIF coordinates. Each range stays on its sheet.
  func testCrossSheetCountIfRangesStayOnTheirOwnSheet() {
    func month(_ name: String, label: String) -> Sheet {
      Sheet(
        name: name,
        cells: [
          CellAddress(row: 0, col: 0): Cell(raw: label),
          CellAddress(row: 0, col: 2): Cell(raw: label),
          CellAddress(row: 1, col: 2): Cell(raw: label),
          CellAddress(row: 0, col: 3): Cell(raw: "=COUNTIF($C$1:$C$2,$A1)"),
        ]
      )
    }
    let summary = Sheet(
      name: "Summary",
      cells: [
        CellAddress(row: 0, col: 0): Cell(raw: "=January!D1+June!D1")
      ]
    )
    let workbook = Workbook(sheets: [
      summary,
      month("January", label: "no"),
      month("June", label: "yes"),
    ])
    let engine = FormulaEngine()
    engine.rebuild(workbook: workbook, recalculate: false)
    let address = CellAddress(row: 0, col: 0)
    let value = engine.sheetDisplayValue(at: address, sheet: workbook.sheets[0])
    XCTAssertEqual(value, .number(4))

    let full = FormulaEngine()
    full.recalculateEntireWorkbook(workbook)
    XCTAssertEqual(full.formulaResults(on: summary)[address], .number(4))
  }

  /// A sheet whose name used to sort last still runs after the sheet it reads.
  func testSheetWavesFollowPrecedentsRatherThanNames() {
    let summary = Sheet(
      name: "Summary",
      cells: [
        CellAddress(row: 0, col: 0): Cell(raw: "=Data!A1")
      ]
    )
    let data = Sheet(
      name: "Data",
      cells: [
        CellAddress(row: 0, col: 0): Cell(raw: "=1+1")
      ]
    )
    let workbook = Workbook(sheets: [summary, data])
    let graph = WorkbookDependencyGraph.build(CrossSheetBackground.graphInput(for: workbook))
    XCTAssertEqual(graph.sheetEvaluationWaves(), [[1], [0]])

    let engine = FormulaEngine()
    engine.recalculateEntireWorkbook(workbook, profile: false)
    let address = CellAddress(row: 0, col: 0)
    XCTAssertEqual(engine.formulaResults(on: data)[address], .number(2))
    XCTAssertEqual(engine.formulaResults(on: summary)[address], .number(2))
  }

  /// Sheets that do not read each other stay in one wave, in workbook order.
  func testIndependentSheetsShareOneEvaluationWave() {
    let left = Sheet(
      name: "Left",
      cells: [
        CellAddress(row: 0, col: 0): Cell(raw: "=1+2")
      ]
    )
    let right = Sheet(
      name: "Right",
      cells: [
        CellAddress(row: 0, col: 0): Cell(raw: "=3+4")
      ]
    )
    let workbook = Workbook(sheets: [left, right])
    let graph = WorkbookDependencyGraph.build(CrossSheetBackground.graphInput(for: workbook))
    XCTAssertEqual(graph.sheetEvaluationWaves(), [[0, 1]])
  }
}
