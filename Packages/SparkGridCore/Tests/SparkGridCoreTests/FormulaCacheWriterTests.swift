import FileFormats
import GridCore
import Model
import XCTest

@testable import Calc

private final class ChainBox: @unchecked Sendable {
  var value: CellValue?
}

final class FormulaCacheWriterTests: XCTestCase {
  func testMissingCachesAreCalculatedAndAnExistingCacheIsKept() {
    let a1 = CellAddress(row: 0, col: 0)
    let b1 = CellAddress(row: 0, col: 1)
    let c1 = CellAddress(row: 0, col: 2)
    let sheet = Sheet(
      name: "Data",
      cells: [
        a1: Cell(raw: "=1+1"),
        b1: Cell(raw: "=A1"),
        c1: Cell(raw: "=3", importedFormulaResult: "3", importedFormulaValueType: .number),
      ]
    )
    let saved = FormulaCacheWriter.prepare(Workbook(sheets: [sheet]))
    guard let data = saved.sheets.first else {
      XCTFail("sheet missing")
      return
    }
    XCTAssertEqual(data.cell(at: a1).cachedFormulaValue, .number(2))
    XCTAssertEqual(data.cell(at: b1).cachedFormulaValue, .number(2))
    XCTAssertEqual(data.cell(at: c1).importedFormulaResult, "3")
  }

  func testCachedResultIsShownWithoutCalculating() {
    let b1 = CellAddress(row: 0, col: 1)
    let sheet = Sheet(
      name: "Data",
      cells: [
        CellAddress(row: 0, col: 0): Cell(raw: "1"),
        b1: Cell(
          raw: "=1/0",
          importedFormulaResult: "7",
          importedFormulaValueType: .number
        ),
      ]
    )
    let saved = FormulaCacheWriter.prepare(Workbook(sheets: [sheet]))
    guard let data = saved.sheets.first else {
      XCTFail("sheet missing")
      return
    }
    XCTAssertEqual(data.cell(at: b1).importedFormulaResult, "7")
    let engine = FormulaEngine()
    engine.rebuild(workbook: saved, recalculate: false)
    XCTAssertEqual(engine.sheetDisplayValue(at: b1, sheet: data), .number(7))
  }

  func testEditWritesDependentsAndKeepsAnUntouchedCache() throws {
    let a1 = CellAddress(row: 0, col: 0)
    let b1 = CellAddress(row: 0, col: 1)
    let c1 = CellAddress(row: 0, col: 2)
    var data = Sheet(
      name: "Data",
      cells: [
        a1: Cell(raw: "1"),
        b1: Cell(
          raw: "=A1+10",
          importedFormulaResult: "11",
          importedFormulaValueType: .number
        ),
        c1: Cell(raw: "=3", importedFormulaResult: "3", importedFormulaValueType: .number),
      ]
    )
    let total = Sheet(
      name: "Total",
      cells: [
        a1: Cell(
          raw: "=Data!B1",
          importedFormulaResult: "11",
          importedFormulaValueType: .number
        )
      ]
    )
    var workbook = Workbook(sheets: [data, total])
    let engine = FormulaEngine()
    engine.rebuild(workbook: workbook, recalculate: false)
    engine.prepareDependencyGraph()
    _ = engine.sheetDisplayValue(at: b1, sheet: data)

    data.setCell(Cell(raw: "4"), at: a1)
    workbook.sheets[0] = data
    engine.adoptWorkbook(workbook)
    _ = engine.cellsDidChange([a1], sheet: data)
    let stamp = engine.formulaSaveStamp()
    XCTAssertFalse(stamp.recalculateAllFormulas)

    let saved = FormulaCacheWriter.prepare(workbook, stamp: stamp)
    guard let savedData = saved.sheets.first(where: { $0.name == "Data" }),
      let savedTotal = saved.sheets.first(where: { $0.name == "Total" })
    else {
      XCTFail("sheets missing")
      return
    }
    XCTAssertEqual(savedData.cell(at: b1).cachedFormulaValue, .number(14))
    XCTAssertEqual(savedData.cell(at: c1).importedFormulaResult, "3")
    XCTAssertEqual(savedTotal.cell(at: a1).cachedFormulaValue, .number(14))

    let exported = try XLSXCodec.exportWorkbook(saved, includeFormulaCaches: true)
    let reopened = try XLSXCodec.importWorkbook(from: exported)
    guard let reopenedData = reopened.sheets.first(where: { $0.name == "Data" }) else {
      XCTFail("reopened sheet missing")
      return
    }
    XCTAssertEqual(reopenedData.cell(at: b1).cachedFormulaValue, .number(14))
    let display = FormulaEngine()
    display.rebuild(workbook: reopened, recalculate: false)
    XCTAssertEqual(display.sheetDisplayValue(at: b1, sheet: reopenedData), .number(14))
  }

  func testLongChainGetsACacheWithoutRecursingPerLink() {
    let links = 2_000
    var sheet = Sheet(name: "Chain")
    sheet.setCell(Cell(raw: "1"), at: CellAddress(row: 0, col: 0))
    for row in 1..<links {
      let previous = CellAddress(row: row - 1, col: 0).a1
      sheet.setCell(Cell(raw: "=\(previous)+1"), at: CellAddress(row: row, col: 0))
    }
    let workbook = Workbook(sheets: [sheet])
    let finished = expectation(description: "chain")
    let box = ChainBox()
    DispatchQueue.global(qos: .utility).async {
      let saved = FormulaCacheWriter.prepare(workbook)
      box.value =
        saved.sheets.first?.cell(at: CellAddress(row: links - 1, col: 0))
        .cachedFormulaValue
      finished.fulfill()
    }
    wait(for: [finished], timeout: 30)
    XCTAssertEqual(box.value, .number(Double(links)))
  }

  /// After a structural edit every stored result is stale. The save leaves them out rather
  /// than recalculating the whole workbook, and never writes the stale 999.
  func testStructuralRebuildDropsAStaleCache() {
    let a1 = CellAddress(row: 0, col: 0)
    let b1 = CellAddress(row: 0, col: 1)
    let sheet = Sheet(
      name: "Data",
      cells: [
        a1: Cell(raw: "3"),
        b1: Cell(
          raw: "=SUM(A1:A1)",
          importedFormulaResult: "999",
          importedFormulaValueType: .number
        ),
      ]
    )
    let workbook = Workbook(sheets: [sheet])
    let engine = FormulaEngine()
    engine.rebuild(workbook: workbook, trustImportedCaches: false)
    let saved = FormulaCacheWriter.prepare(workbook, stamp: engine.formulaSaveStamp())
    guard let data = saved.sheets.first else {
      XCTFail("sheet missing")
      return
    }
    XCTAssertNil(data.cell(at: b1).importedFormulaResult)
    XCTAssertEqual(data.cell(at: b1).raw, "=SUM(A1:A1)")
    XCTAssertTrue(engine.formulaSaveStamp().recalculateAllFormulas)
  }
}
