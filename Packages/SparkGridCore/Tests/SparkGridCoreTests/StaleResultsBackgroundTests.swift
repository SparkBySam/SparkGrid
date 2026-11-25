import Calc
import GridCore
import Model
import XCTest

/// Above the size a save calculates itself, a structural step's stale results are calculated in
/// the background, so the next save writes results again (gaps 8).
final class StaleResultsBackgroundTests: XCTestCase {
  private func bigWorkbook() -> Workbook {
    var sheet = Sheet(name: "Data")
    let rows = FormulaCacheWriter.recalculateOnSaveLimit / 2 + 10
    for row in 0..<rows {
      sheet.setCell(Cell(raw: String(row)), at: CellAddress(row: row, col: 0))
      sheet.setCell(Cell(raw: "=A\(row + 1)*2"), at: CellAddress(row: row, col: 1))
      sheet.setCell(Cell(raw: "=B\(row + 1)+1"), at: CellAddress(row: row, col: 2))
    }
    return Workbook(sheets: [sheet])
  }

  func testResultsReadyAfterAStructuralStep() {
    let engine = FormulaEngine()
    let workbook = bigWorkbook()
    engine.rebuild(workbook: workbook, recalculate: false, trustImportedCaches: false)
    XCTAssertTrue(engine.formulaSaveStamp().recalculateAllFormulas)
    XCTAssertTrue(engine.isCalculatingStaleResults)
    let done = expectation(description: "results")
    func poll() {
      if !engine.formulaSaveStamp().recalculateAllFormulas {
        done.fulfill()
      } else {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: poll)
      }
    }
    poll()
    wait(for: [done], timeout: 60)
    let stamp = engine.formulaSaveStamp()
    XCTAssertEqual(stamp.freshValues["data"]?[CellAddress(row: 9, col: 2)], .number(19))
    XCTAssertFalse(engine.isCalculatingStaleResults)
    let saved = FormulaCacheWriter.prepare(workbook, stamp: stamp)
    XCTAssertEqual(
      saved.sheets[0].cell(at: CellAddress(row: 9, col: 2)).importedFormulaResult, "19")
  }

  func testSmallWorkbookLeftToTheSave() {
    var sheet = Sheet(name: "Data")
    sheet.setCell(Cell(raw: "=1+1"), at: .origin)
    let engine = FormulaEngine()
    engine.rebuild(
      workbook: Workbook(sheets: [sheet]), recalculate: false, trustImportedCaches: false)
    XCTAssertFalse(engine.isCalculatingStaleResults)
    XCTAssertTrue(engine.formulaSaveStamp().recalculateAllFormulas)
  }
}
