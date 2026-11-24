import Calc
import Engine
import Foundation
import GridCore
import Model
import XCTest

/// Long chains of formulas, each reading the one before: every value right, a range over them
/// right, an edit at the top reaching the bottom, all in time that grows with the length. The
/// order of calculation searched a list for each cell, and filling a column copied it per cell:
/// a 10,000-cell chain took 11.6 s to calculate and 3 s per edit in a debug build.
final class LongChainTests: XCTestCase {
  private func chain(_ length: Int) -> Sheet {
    var sheet = Sheet(name: "Chain")
    sheet.setCell(Cell(raw: "1"), at: CellAddress(row: 0, col: 0))
    for row in 1..<length {
      sheet.setCell(Cell(raw: "=A\(row)+1"), at: CellAddress(row: row, col: 0))
    }
    // One running upward too, so the order the cells were typed in does not help.
    sheet.setCell(Cell(raw: "1"), at: CellAddress(row: length - 1, col: 1))
    for row in 0..<(length - 1) {
      sheet.setCell(Cell(raw: "=B\(row + 2)+1"), at: CellAddress(row: row, col: 1))
    }
    sheet.setCell(Cell(raw: "=SUM(A1:A\(length))"), at: CellAddress(row: 0, col: 3))
    return sheet
  }

  func testLongChainsCalculate() {
    let length = 20_000
    let started = Date()
    var sheet = chain(length)
    let engine = FormulaEngine()
    engine.rebuild(sheet: sheet, recalculate: true)
    XCTAssertEqual(
      engine.sheetDisplayValue(at: CellAddress(row: length - 1, col: 0), sheet: sheet),
      .number(Double(length)))
    XCTAssertEqual(
      engine.sheetDisplayValue(at: CellAddress(row: 0, col: 1), sheet: sheet),
      .number(Double(length)))
    XCTAssertEqual(
      engine.sheetDisplayValue(at: CellAddress(row: 0, col: 3), sheet: sheet),
      .number(Double(length) * Double(length + 1) / 2))
    sheet.setCell(Cell(raw: "101"), at: CellAddress(row: 0, col: 0))
    _ = engine.cellsDidChange([CellAddress(row: 0, col: 0)], sheet: sheet)
    engine.finishPendingCrossSheet()
    XCTAssertEqual(
      engine.sheetDisplayValue(at: CellAddress(row: length - 1, col: 0), sheet: sheet),
      .number(Double(length + 100)))
    // About 1 s in a debug build now; the old code took over 45 s.
    XCTAssertLessThan(Date().timeIntervalSince(started), 15)
  }

  /// Filling and clearing a column of formulas keeps the sheet's formula index in row order.
  func testFormulaIndexStaysInOrder() {
    var sheet = Sheet(name: "Index")
    for row in stride(from: 0, to: 200, by: 2) {
      sheet.setCell(Cell(raw: "=\(row)"), at: CellAddress(row: row, col: 0))
    }
    for row in stride(from: 1, to: 200, by: 2) {
      sheet.setCell(Cell(raw: "=\(row)"), at: CellAddress(row: row, col: 0))
    }
    for row in stride(from: 0, to: 200, by: 3) {
      sheet.setCell(Cell(raw: "plain"), at: CellAddress(row: row, col: 0))
    }
    let rows = (sheet.formulaIngestByColumn[0] ?? []).map(\.0.row)
    XCTAssertEqual(rows, (0..<200).filter { $0 % 3 != 0 })
  }
}
