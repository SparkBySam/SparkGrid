import GridCore
import Model
import XCTest

@testable import Calc

/// Range and lookup caches are shared across sheets. Two sheets with the same unqualified
/// ranges but different data must not read each other's snapshot.
@MainActor
final class SharedRangeCacheTests: XCTestCase {
  private func region(_ name: String, first: (String, Int), second: (String, Int)) -> Sheet {
    Sheet(
      name: name,
      cells: [
        CellAddress(row: 0, col: 0): Cell(raw: first.0),
        CellAddress(row: 0, col: 1): Cell(raw: String(first.1)),
        CellAddress(row: 1, col: 0): Cell(raw: second.0),
        CellAddress(row: 1, col: 1): Cell(raw: String(second.1)),
        CellAddress(row: 0, col: 3): Cell(raw: #"=VLOOKUP("x",A1:B2,2,FALSE)"#),
        CellAddress(row: 1, col: 3): Cell(raw: #"=SUMIFS(B1:B2,A1:A2,"x")"#),
        CellAddress(row: 2, col: 3): Cell(raw: #"=MATCH("y",A1:A2,0)"#),
      ]
    )
  }

  private var workbook: Workbook {
    Workbook(sheets: [
      Sheet(
        name: "Summary",
        cells: [
          CellAddress(row: 0, col: 0): Cell(raw: "=East!D1"),
          CellAddress(row: 0, col: 1): Cell(raw: "=West!D1"),
        ]),
      region("East", first: ("x", 10), second: ("y", 20)),
      region("West", first: ("y", 30), second: ("x", 40)),
    ])
  }

  func testOpeningCalculatesEachSheetFromItsOwnRanges() {
    let values = CrossSheetBackground.calculateFormulasWithoutCaches(in: workbook).valuesBySheet
    let east = values.first { $0.key.caseInsensitiveCompare("East") == .orderedSame }?.value
    let west = values.first { $0.key.caseInsensitiveCompare("West") == .orderedSame }?.value
    XCTAssertEqual(east?[CellAddress(row: 0, col: 3)], .number(10))
    XCTAssertEqual(west?[CellAddress(row: 0, col: 3)], .number(40))
    XCTAssertEqual(east?[CellAddress(row: 1, col: 3)], .number(10))
    XCTAssertEqual(west?[CellAddress(row: 1, col: 3)], .number(40))
    XCTAssertEqual(east?[CellAddress(row: 2, col: 3)], .number(2))
    XCTAssertEqual(west?[CellAddress(row: 2, col: 3)], .number(1))
  }

  func testSummaryReadsEachSheetsOwnLookup() {
    let book = workbook
    let engine = FormulaEngine()
    engine.rebuild(workbook: book, recalculate: false)
    XCTAssertEqual(
      engine.sheetDisplayValue(at: CellAddress(row: 0, col: 0), sheet: book.sheets[0]),
      .number(10))
    XCTAssertEqual(
      engine.sheetDisplayValue(at: CellAddress(row: 0, col: 1), sheet: book.sheets[0]),
      .number(40))
  }
}
