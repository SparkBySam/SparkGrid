import Calc
import Engine
import Formula
import GridCore
import Model
import XCTest

/// `C1#` is every cell the formula in C1 spills into. Files save it as `_xlfn.ANCHORARRAY(C1)`.
final class SpillReferenceTests: XCTestCase {
  private func address(_ a1: String) -> CellAddress {
    let letters = a1.prefix { $0.isLetter }
    let col = letters.unicodeScalars.reduce(0) { $0 * 26 + Int($1.value) - 64 } - 1
    return CellAddress(row: Int(a1.dropFirst(letters.count))! - 1, col: col)
  }

  // MARK: - Reading and writing the formula

  func testParsesAndWritesBackSpillReferences() throws {
    for text in ["ROWS(G1#)", "SUM($G$1#)*2", "COUNTA(Data!B2#)", "INDEX('My Data'!A10#,2)"] {
      let expr = try FormulaParser.parse("=" + text)
      XCTAssertEqual(FormulaRewriter.serialize(expr), text)
    }
    let expr = try FormulaParser.parse("=ROWS(G1#)")
    guard case .call("ROWS", let args) = expr, case .call(let name, let inner) = args[0] else {
      return XCTFail("\(expr)")
    }
    XCTAssertEqual(name, "ANCHORARRAY")
    XCTAssertEqual(inner, [.cellRef(FormulaRef(row: 0, col: 6, absRow: false, absCol: false))])
    // The form saved files use reads the same.
    XCTAssertEqual(
      try FormulaParser.parse("=ROWS(_xlfn.ANCHORARRAY(G1))"),
      .call(
        "ROWS",
        [
          .call(
            "_XLFN.ANCHORARRAY",
            [.cellRef(FormulaRef(row: 0, col: 6, absRow: false, absCol: false))])
        ]))
    // `#` still starts an error value where no cell comes before it.
    XCTAssertEqual(
      try FormulaParser.parse("=IF(A1,#DIV/0!,1/2)"),
      .call(
        "IF",
        [
          .cellRef(FormulaRef(row: 0, col: 0, absRow: false, absCol: false)), .error(.divZero),
          .binary(.divide, .number(1), .number(2)),
        ]))
    let a1 = FormulaExpr.cellRef(FormulaRef(row: 0, col: 0, absRow: false, absCol: false))
    XCTAssertEqual(
      try FormulaParser.parse("=IFERROR(A1,#N/A)"), .call("IFERROR", [a1, .error(.na)]))
  }

  func testInsertedRowMovesTheSpillReference() throws {
    let moved = FormulaRewriter.shiftForStructure(
      "=ROWS(C1#)+SUM(Data!C1#)", formulaSheetName: "Main", mutatedSheetName: "Main",
      axis: .row, change: .insert(at: 0, count: 2))
    XCTAssertEqual(moved, "=ROWS(C3#)+SUM(Data!C1#)")
  }

  // MARK: - Results

  /// A1:A5 holds numbers, C1 sorts them, and other formulas read `C1#`.
  private func calculated(
    _ formulas: [String: String], extra: [Sheet] = []
  ) -> (FormulaEngine, Sheet) {
    var sheet = Sheet(name: "Main")
    for (row, value) in ["30", "10", "50", "20", "40"].enumerated() {
      sheet.setCell(Cell(raw: value), at: CellAddress(row: row, col: 0))
    }
    sheet.setCell(Cell(raw: "=SORT(A1:A5)"), at: address("C1"))
    for (a1, raw) in formulas { sheet.setCell(Cell(raw: raw), at: address(a1)) }
    let engine = FormulaEngine()
    for _ in 0..<4 {
      engine.rebuild(workbook: Workbook(sheets: [sheet] + extra), recalculate: true)
      var arrays: [CellAddress: ArrayResult] = [:]
      for anchor in SpillLayout.anchors(in: sheet) {
        arrays[anchor] = engine.spillArray(at: anchor, sheet: sheet, activeSheet: sheet)
      }
      let outcome = SpillLayout.apply(arrays, to: &sheet)
      if outcome.changedCells.isEmpty && outcome.changedAnchors.isEmpty { break }
    }
    engine.rebuild(workbook: Workbook(sheets: [sheet] + extra), recalculate: true)
    return (engine, sheet)
  }

  func testFunctionsReadTheWholeSpill() {
    let (engine, sheet) = calculated([
      "E1": "=ROWS(C1#)", "E2": "=SUM(C1#)", "E3": "=INDEX(C1#,2)", "E4": "=COUNTIF(C1#,\">25\")",
      "E5": "=MAX(C1#)-MIN(C1#)",
    ])
    XCTAssertEqual(engine.displayValue(at: address("E1"), sheet: sheet), .number(5))
    XCTAssertEqual(engine.displayValue(at: address("E2"), sheet: sheet), .number(150))
    XCTAssertEqual(engine.displayValue(at: address("E3"), sheet: sheet), .number(20))
    XCTAssertEqual(engine.displayValue(at: address("E5"), sheet: sheet), .number(40))
    XCTAssertEqual(engine.displayValue(at: address("E4"), sheet: sheet), .number(3))
  }

  /// `=C1#*10` spills itself, as large as C1's spill.
  func testSpillReferenceSpills() {
    let (engine, sheet) = calculated(["G1": "=C1#*10"])
    XCTAssertEqual(sheet.fileExtras.spills[address("G1")]?.a1Label, "G1:G5")
    let shown = (1...5).map { engine.sheetDisplayValue(at: address("G\($0)"), sheet: sheet) }
    XCTAssertEqual(shown, [100, 200, 300, 400, 500].map { CellValue.number($0) })
  }

  func testSpillReferenceOnAnotherSheet() {
    var summary = Sheet(name: "Summary")
    summary.setCell(Cell(raw: "=ROWS(Main!C1#)"), at: address("A1"))
    summary.setCell(Cell(raw: "=SUM(Main!C1#)"), at: address("A2"))
    let (engine, main) = calculated([:], extra: [summary])
    // The whole-workbook pass, as on open and in the answer checks.
    engine.recalculateEntireWorkbook(Workbook(sheets: [main, summary]))
    let results = engine.formulaResults(on: summary)
    XCTAssertEqual(results[address("A1")], .number(5))
    XCTAssertEqual(results[address("A2")], .number(150))
    // Shown on the summary sheet.
    let book = Workbook(sheets: [main, summary], activeSheetIndex: 1)
    engine.rebuild(workbook: book, recalculate: true)
    XCTAssertEqual(engine.displayValue(at: address("A1"), sheet: summary), .number(5))
  }

  func testSpillReferenceErrors() {
    let (engine, sheet) = calculated([
      "E1": "=ROWS(A1#)",  // A1 is a typed number, not a formula
      "E2": "=ROWS(H1#)",  // H1 is a formula that does not spill
      "H1": "=1+1",
      "J1": "=SORT(J1#)",  // reads itself
    ])
    XCTAssertEqual(engine.displayValue(at: address("E1"), sheet: sheet), .error(.ref))
    XCTAssertEqual(engine.displayValue(at: address("E2"), sheet: sheet), .error(.ref))
    if case .error = engine.displayValue(at: address("J1"), sheet: sheet) {
    } else {
      XCTFail("a spill reference to itself should be an error")
    }
  }

  /// A blocked spill has no cells to read.
  func testBlockedSpillReferenceIsRefError() {
    let (engine, sheet) = calculated(["C3": "in the way", "E1": "=ROWS(C1#)"])
    XCTAssertTrue(sheet.fileExtras.blockedSpills.contains(address("C1")))
    XCTAssertEqual(engine.displayValue(at: address("E1"), sheet: sheet), .error(.ref))
  }

  // MARK: - Editing, as the app does it

  /// The app's steps: the edit, then laying out spills (which reports changed cells again), then
  /// the background update. Formulas reading `C1#` follow new data and a spill that grows.
  func testEditsUpdateSpillReferences() {
    var sheet = Sheet(name: "Data")
    for (row, value) in ["30", "10", "20"].enumerated() {
      sheet.setCell(Cell(raw: value), at: CellAddress(row: row, col: 0))
    }
    let engine = FormulaEngine()
    engine.rebuild(workbook: Workbook(sheets: [sheet]), recalculate: true)
    func set(_ a1: String, _ raw: String) {
      sheet.setCell(Cell(raw: raw), at: address(a1))
      _ = engine.cellsDidChange([address(a1)], sheet: sheet)
      for _ in 0..<4 {
        var arrays: [CellAddress: ArrayResult] = [:]
        for anchor in SpillLayout.anchors(in: sheet) {
          arrays[anchor] = engine.spillArray(at: anchor, sheet: sheet, activeSheet: sheet)
        }
        let outcome = SpillLayout.apply(arrays, to: &sheet)
        let changed = outcome.changedCells.union(outcome.changedAnchors)
          .union(SpillLayout.anchors(of: outcome.changedCells, in: sheet))
        if changed.isEmpty { break }
        _ = engine.cellsDidChange(Array(changed), sheet: sheet)
      }
      engine.finishPendingCrossSheet()
    }
    func shown(_ labels: [String]) -> [CellValue] {
      labels.map { engine.displayValue(at: address($0), sheet: sheet) }
    }
    set("C1", "=SORT(A1:A3)")
    set("E1", "=SUM(C1#)")
    set("E2", "=ROWS(C1#)")
    set("E3", "=INDEX(C1#,1)")
    set("G1", "=C1#*2")
    XCTAssertEqual(shown(["E1", "E2", "E3", "G1"]), [60, 3, 10, 20].map { CellValue.number($0) })
    set("A2", "5")
    XCTAssertEqual(shown(["E1", "E2", "E3", "G1"]), [55, 3, 5, 10].map { CellValue.number($0) })
    set("A4", "1")
    set("C1", "=SORT(A1:A4)")
    XCTAssertEqual(
      shown(["E1", "E2", "E3", "G1", "G4"]), [56, 4, 1, 2, 60].map { CellValue.number($0) })
  }
}
