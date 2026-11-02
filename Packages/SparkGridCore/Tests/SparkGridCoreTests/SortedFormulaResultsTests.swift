import GridCore
import Model
import XCTest

@testable import Calc

/// A sort by a formula column moved the typed columns, but every formula column kept showing the
/// answer of the row that used to sit at its address. Those answers came from the background
/// calculation that fills in a file opened without results.
@MainActor
final class SortedFormulaResultsTests: XCTestCase {
  private func sheet(quantities: [Int]) -> Sheet {
    var cells: [CellAddress: Cell] = [:]
    for (row, quantity) in quantities.enumerated() {
      cells[CellAddress(row: row, col: 0)] = Cell(raw: String(quantity))
      cells[CellAddress(row: row, col: 1)] = Cell(raw: "=A\(row + 1)*10")
    }
    return Sheet(name: "Orders", cells: cells)
  }

  func testFormulaResultsFollowTheirRowsAfterASort() {
    let opened = Workbook(sheets: [sheet(quantities: [3, 1, 2])])
    let engine = FormulaEngine()
    engine.rebuild(workbook: opened, recalculate: false)
    // The open calculation's answers, keyed by address.
    engine.installCalculatedResults([
      "orders": [
        CellAddress(row: 0, col: 1): .number(30),
        CellAddress(row: 1, col: 1): .number(10),
        CellAddress(row: 2, col: 1): .number(20),
      ]
    ])

    // Sorted A to Z: each row's formula moved with it and now reads its new row.
    let sorted = Workbook(sheets: [sheet(quantities: [1, 2, 3])])
    engine.rebuild(workbook: sorted, trustImportedCaches: false)
    let values = (0..<3).map {
      engine.displayValue(at: CellAddress(row: $0, col: 1), sheet: sorted.sheets[0])
    }
    XCTAssertEqual(values, [.number(10), .number(20), .number(30)])
  }

  /// A file opened without results paints its formulas from the background calculation. A
  /// highlight rule reading those cells got blanks: Flag showed "Large" but N2="Large" was false.
  func testHighlightRuleReadsBackgroundResults() {
    let book = Workbook(sheets: [
      Sheet(
        name: "Orders",
        cells: [
          CellAddress(row: 0, col: 0): Cell(raw: "40"),
          CellAddress(row: 0, col: 1): Cell(raw: #"=IF(A1>10,"Large","OK")"#),
        ])
    ])
    let engine = FormulaEngine()
    engine.rebuild(workbook: book)
    engine.setPaintsStoredResultsOnly(true)
    engine.installCalculatedResults(["orders": [CellAddress(row: 0, col: 1): .string("Large")]])
    let flag = CellAddress(row: 0, col: 1)
    XCTAssertEqual(engine.displayValue(at: flag, sheet: book.sheets[0]), .string("Large"))
    XCTAssertEqual(
      engine.evaluateConditionalFormula(
        #"B1="Large""#, at: flag, relativeTo: flag, sheet: book.sheets[0]),
      .bool(true))
  }
}
