import Engine
import Formula
import GridCore
import Model
import NumberFormat
import XCTest

@testable import Calc

final class CrashSafetyTests: XCTestCase {
  func testColumnLabelDoesNotTrap() {
    XCTAssertEqual(A1Notation.columnLabel(for: 0), "A")
    XCTAssertEqual(A1Notation.columnLabel(for: 25), "Z")
    XCTAssertEqual(A1Notation.columnLabel(for: 26), "AA")
  }

  func testElapsedFormatCodeDoesNotTrap() {
    _ = ExcelFormatCode.formatted(1.5, code: "[h]:mm", fractionDigits: nil)
  }

  func testCheckedSpanDoesNotOverflow() {
    XCTAssertNil(InputBounds.materializedCount(rows: Int.max, cols: Int.max))
    XCTAssertEqual(InputBounds.span(from: 0, through: 3), 4)
    XCTAssertEqual(InputBounds.cappedCount(-4), 0)
    XCTAssertEqual(InputBounds.cappedCount(Int.max), InputBounds.maxStructureCount)
  }

  func testFormulaNestingStops() {
    var expr = FormulaExpr.number(1)
    for _ in 0..<(InputBounds.maxFormulaNesting + 8) {
      expr = .call("ABS", [expr])
    }
    let evaluator = FormulaEvaluator { _ in .blank }
    XCTAssertEqual(evaluator.evaluate(expr), .error(.value))
  }

  func testNamedRangeCycleStops() {
    var evaluator = FormulaEvaluator { _ in .blank }
    evaluator.namedRangeLookup = { name in .namedRange(name) }
    XCTAssertEqual(evaluator.evaluate(.namedRange("Loop")), .error(.cycle))
  }

  func testReptRejectsHostileLength() {
    let evaluator = FormulaEvaluator { _ in .blank }
    let hostile = evaluator.evaluate(.call("REPT", [.string("a"), .number(100_000)]))
    XCTAssertEqual(hostile, .error(.value))
    let small = evaluator.evaluate(.call("REPT", [.string("ab"), .number(3)]))
    XCTAssertEqual(small, .string("ababab"))
  }

  func testSequenceRejectsHostileSize() {
    let evaluator = FormulaEvaluator { _ in .blank }
    let hostile = evaluator.evaluate(.call("SEQUENCE", [.number(1_000_000), .number(1_000_000)]))
    XCTAssertEqual(hostile, .error(.value))
    let one = evaluator.evaluate(.call("SEQUENCE", [.number(1)]))
    XCTAssertEqual(one, .number(1))
  }

  func testApproximateMatchDoesNotTrap() {
    let evaluator = FormulaEvaluator { ref in
      switch ref.row {
      case 0: return .number(1)
      case 1: return .number(3)
      case 2: return .number(5)
      default: return .blank
      }
    }
    let match = evaluator.evaluate(
      .call(
        "MATCH",
        [
          .number(4),
          .range(
            FormulaRef(sheet: nil, row: 0, col: 0, absRow: false, absCol: false),
            FormulaRef(sheet: nil, row: 2, col: 0, absRow: false, absCol: false)
          ),
          .number(1),
        ]))
    XCTAssertEqual(match, .number(2))
  }

  func testDependencyGraphBuildDoesNotTrap() throws {
    let cell = WorkbookGraphInput.Cell(row: 1, col: 0, raw: "=A1+1")
    let sheet = WorkbookGraphInput.Sheet(
      name: "Sheet1",
      sheetID: 0,
      maxRow: 10,
      maxCol: 5,
      columns: [[cell]]
    )
    let input = WorkbookGraphInput(
      sheets: [sheet],
      names: [],
      sheetIDsByName: ["sheet1": 0],
      fallbackMaxRow: 10,
      fallbackMaxCol: 5
    )
    let graph = WorkbookDependencyGraph.build(input)
    XCTAssertEqual(graph.formulaCoords.count, 1)
  }

  @MainActor
  func testShortChainStillCalculates() {
    var sheet = Sheet(name: "Chain")
    sheet.setCell(Cell(raw: "1"), at: CellAddress(row: 0, col: 0))
    for row in 1...40 {
      let previous = CellAddress(row: row - 1, col: 0).a1
      sheet.setCell(Cell(raw: "=\(previous)+1"), at: CellAddress(row: row, col: 0))
    }
    let engine = FormulaEngine()
    engine.rebuild(sheet: sheet, recalculate: true)
    let value = engine.sheetDisplayValue(at: CellAddress(row: 40, col: 0), sheet: sheet)
    XCTAssertEqual(value, .number(41))
  }

  @MainActor
  func testDependencyDepthStops() {
    let depth = InputBounds.maxDependencyDepth + 5
    var sheets: [Sheet] = []
    var first = Sheet(name: "S0")
    first.setCell(Cell(raw: "1"), at: CellAddress(row: 0, col: 0))
    sheets.append(first)
    for index in 1...depth {
      var sheet = Sheet(name: "S\(index)")
      sheet.setCell(Cell(raw: "=S\(index - 1)!A1+1"), at: CellAddress(row: 0, col: 0))
      sheets.append(sheet)
    }
    let workbook = Workbook(sheets: sheets, activeSheetIndex: sheets.count - 1)
    let engine = FormulaEngine()
    engine.rebuild(workbook: workbook, recalculate: false)
    let value = engine.sheetDisplayValue(
      at: CellAddress(row: 0, col: 0),
      sheet: workbook.activeSheet
    )
    XCTAssertEqual(value, .error(.value))
  }

  func testBackgroundWriteRefusesMainThread() {
    XCTAssertThrowsError(try BackgroundWriteGuard.requireBackgroundThread()) { error in
      XCTAssertEqual(error as? BackgroundWriteError, .refusingMainThread)
    }
  }

  @MainActor
  func testRecoveryCopyRoundTrip() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("spark-grid-recovery-\(UUID().uuidString)", isDirectory: true)
    defer { CrashRecoveryStore.clear(in: directory) }
    var sheet = Sheet(name: "Saved")
    sheet.setCell(Cell(raw: "42"), at: CellAddress(row: 0, col: 0))
    let workbook = Workbook(sheets: [sheet])
    try CrashRecoveryStore.beginSession(in: directory)
    XCTAssertFalse(CrashRecoveryStore.needsRestore(in: directory))
    try CrashRecoveryStore.write(
      workbook: workbook, documentPath: "/tmp/example.xlsx", in: directory)
    XCTAssertTrue(CrashRecoveryStore.needsRestore(in: directory))
    let loaded = try CrashRecoveryStore.load(in: directory)
    XCTAssertEqual(loaded.workbook.sheets.first?.cell(at: CellAddress(row: 0, col: 0)).raw, "42")
    XCTAssertEqual(loaded.documentPath, "/tmp/example.xlsx")
    CrashRecoveryStore.noteCleanExit(in: directory)
    XCTAssertFalse(CrashRecoveryStore.needsRestore(in: directory))
  }
}
