import FileFormats
import GridCore
import Model
import Rendering
import XCTest

@testable import Calc

final class MissingSheetCacheTests: XCTestCase {
  func testManyMissingSheetsKeepTheStoredResultOnFirstCalculation() {
    let address = CellAddress(row: 0, col: 0)
    var total = Cell(
      raw: "=M1!A1+M2!A1+M3!A1+M4!A1+M5!A1+M6!A1+M7!A1+M8!A1+M9!A1+M10!A1+M11!A1+M12!A1"
    )
    total.importedFormulaResult = "42"
    total.importedFormulaValueType = .number
    let summary = Sheet(name: "Summary", cells: [address: total])
    let engine = FormulaEngine()
    engine.setAwaitingRemainder(false)
    engine.rebuild(workbook: Workbook(sheets: [summary]), recalculate: false)
    XCTAssertEqual(engine.sheetDisplayValue(at: address, sheet: summary), .number(42))
    engine.rebuild(workbook: Workbook(sheets: [summary]), recalculate: true)
    XCTAssertEqual(engine.displayValue(at: address, sheet: summary), .number(42))
    XCTAssertEqual(engine.sheetDisplayValue(at: address, sheet: summary), .number(42))
  }

  func testStoredResultStandsInWhileTheOtherSheetIsNotLoaded() {
    let address = CellAddress(row: 0, col: 0)
    var total = Cell(raw: "=Other!A1")
    total.importedFormulaResult = "42"
    total.importedFormulaValueType = .number
    let sheet = Sheet(name: "Summary", cells: [address: total])
    let engine = FormulaEngine()
    engine.setAwaitingRemainder(true)
    engine.rebuild(workbook: Workbook(sheets: [sheet]), recalculate: true)

    XCTAssertEqual(engine.sheetDisplayValue(at: address, sheet: sheet), .number(42))
  }

  /// Calculation can run before the window marks the workbook as still loading.
  func testStoredResultStandsInWhenTheWaitingFlagIsOff() {
    let address = CellAddress(row: 0, col: 0)
    var total = Cell(raw: "=Other!A1")
    total.importedFormulaResult = "42"
    total.importedFormulaValueType = .number
    let summary = Sheet(name: "Summary", cells: [address: total])
    let engine = FormulaEngine()
    engine.setAwaitingRemainder(false)
    engine.rebuild(workbook: Workbook(sheets: [summary]), recalculate: true)

    XCTAssertEqual(engine.sheetDisplayValue(at: address, sheet: summary), .number(42))

    let other = Sheet(name: "Other", cells: [address: Cell(raw: "7")])
    let full = Workbook(sheets: [summary, other])
    engine.replaceWorkbookKeepingValues(full)
    XCTAssertEqual(engine.sheetDisplayValue(at: address, sheet: summary), .number(42))

    engine.rebuild(workbook: full, recalculate: true)
    XCTAssertEqual(engine.sheetDisplayValue(at: address, sheet: summary), .number(7))
  }

  func testOpenPaintLeavesAnUncachedFormulaBlank() {
    let address = CellAddress(row: 0, col: 0)
    let sheet = Sheet(name: "Summary", cells: [address: Cell(raw: "=1+1")])
    let engine = FormulaEngine()
    engine.rebuild(workbook: Workbook(sheets: [sheet]), recalculate: false)
    engine.setPaintsStoredResultsOnly(true)
    XCTAssertEqual(engine.sheetDisplayValue(at: address, sheet: sheet), .blank)
    engine.setPaintsStoredResultsOnly(false)
    XCTAssertEqual(engine.sheetDisplayValue(at: address, sheet: sheet), .number(2))
  }

  func testMissingSheetWithoutAStoredResultIsStillRef() {
    let address = CellAddress(row: 0, col: 0)
    let sheet = Sheet(name: "Summary", cells: [address: Cell(raw: "=Other!A1")])
    let engine = FormulaEngine()
    engine.setAwaitingRemainder(true)
    engine.rebuild(workbook: Workbook(sheets: [sheet]), recalculate: true)

    XCTAssertEqual(engine.sheetDisplayValue(at: address, sheet: sheet), .error(.ref))
  }

  func testCompleteWorkbookReplacesTheStoredResult() {
    let address = CellAddress(row: 0, col: 0)
    var total = Cell(raw: "=Other!A1")
    total.importedFormulaResult = "99"
    total.importedFormulaValueType = .number
    let summary = Sheet(name: "Summary", cells: [address: total])
    let other = Sheet(name: "Other", cells: [address: Cell(raw: "7")])
    let engine = FormulaEngine()
    engine.setAwaitingRemainder(false)
    engine.rebuild(workbook: Workbook(sheets: [summary, other]), recalculate: true)

    XCTAssertEqual(engine.sheetDisplayValue(at: address, sheet: summary), .number(7))
  }

  func testFullWorkbookImportWallClock() throws {
    let path = NSHomeDirectory() + "/Downloads/BDC Digital KPI 2026.xlsx"
    guard FileManager.default.fileExists(atPath: path) else {
      throw XCTSkip("corpus file is not on this machine")
    }
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let started = CFAbsoluteTimeGetCurrent()
    let workbook = try XLSXCodec.importWorkbook(from: data)
    let elapsed = CFAbsoluteTimeGetCurrent() - started
    var formulas = 0
    var cached = 0
    var refShown = 0
    let engine = FormulaEngine()
    engine.rebuild(workbook: workbook, recalculate: false)
    let sheet = workbook.activeSheet
    for (address, cell) in sheet.cells where cell.raw.hasPrefix("=") {
      formulas += 1
      if cell.cachedFormulaValue != nil { cached += 1 }
      let shown = engine.sheetDisplayValue(at: address, sheet: sheet, cell: cell)
      if case .error(.ref) = shown, cell.cachedFormulaValue != .error(.ref) {
        refShown += 1
      }
    }
    XCTAssertGreaterThan(workbook.sheets.count, 1)
    XCTAssertEqual(cached, formulas)
    XCTAssertEqual(refShown, 0)
    XCTAssertLessThan(elapsed, 3)
  }

  func testPartialKPIOpenDoesNotShowRefForStoredCrossSheetFormulas() throws {
    let path = NSHomeDirectory() + "/Downloads/BDC Digital KPI 2026.xlsx"
    guard FileManager.default.fileExists(atPath: path) else {
      throw XCTSkip("corpus file is not on this machine")
    }
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let importer = try XLSXCodec.Importer(data: data)
    let partial = try importer.importActiveSheet()
    let sheet = partial.activeSheet
    XCTAssertEqual(partial.sheets.count, 1)

    let painted = FormulaEngine()
    painted.setAwaitingRemainder(false)
    painted.rebuild(workbook: partial, recalculate: false)
    let paintCounts = Self.refCounts(sheet: sheet, engine: painted)
    XCTAssertEqual(paintCounts.cacheNotRef, 0)
    XCTAssertEqual(Self.screenTextRefCount(sheet: sheet, engine: painted), 0)

    let recalc = FormulaEngine()
    recalc.setAwaitingRemainder(false)
    recalc.rebuild(workbook: partial, recalculate: true)
    let forced = Self.refCounts(sheet: sheet, engine: recalc)
    XCTAssertEqual(
      forced.cacheNotRef, 0,
      "partial recalc showed #REF! for \(forced.cacheNotRef) stored results")
    XCTAssertEqual(Self.screenTextRefCount(sheet: sheet, engine: recalc), 0)

    let full = try importer.importRemaining(after: partial)
    XCTAssertGreaterThan(full.sheets.count, 1)
    recalc.replaceWorkbookKeepingValues(full)
    let arrived = Self.refCounts(sheet: full.sheets[0], engine: recalc)
    XCTAssertEqual(
      arrived.cacheNotRef, 0,
      "stored results still showed #REF! after the remaining sheets arrived")
    XCTAssertEqual(Self.screenTextRefCount(sheet: full.sheets[0], engine: recalc), 0)
  }

  private struct RefCounts {
    var cross = 0
    var rawRef = 0
    var cached = 0
    var displayRef = 0
    var cacheNotRef = 0
  }

  /// First screen of formula cells whose drawn text contains a missing-sheet error.
  private static func screenTextRefCount(sheet: Sheet, engine: FormulaEngine) -> Int {
    var textRef = 0
    for (address, cell) in sheet.cells
    where address.row < 80 && address.col < 30 && cell.raw.hasPrefix("=") {
      let shown = engine.sheetDisplayValue(at: address, sheet: sheet, cell: cell)
      let text = CellFormatRenderer.displayText(
        for: shown, format: cell.format, fallbackRaw: cell.raw)
      if text.contains("#REF!") { textRef += 1 }
    }
    return textRef
  }

  private static func refCounts(sheet: Sheet, engine: FormulaEngine) -> RefCounts {
    var counts = RefCounts()
    for (address, cell) in sheet.cells {
      let raw = cell.raw
      guard raw.hasPrefix("=") else { continue }
      counts.cross += 1
      if raw.contains("#REF!") { counts.rawRef += 1 }
      let stored = cell.cachedFormulaValue
      if stored != nil { counts.cached += 1 }
      let shown = engine.sheetDisplayValue(at: address, sheet: sheet, cell: cell)
      if case .error(.ref) = shown {
        counts.displayRef += 1
        if let stored, stored != .error(.ref) {
          counts.cacheNotRef += 1
        }
      }
    }
    return counts
  }
}
