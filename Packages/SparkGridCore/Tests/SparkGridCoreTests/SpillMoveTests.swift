import Calc
import Engine
import Formula
import GridCore
import Model
import XCTest

/// Rows and columns inserted or deleted, and sorts, move cells. A spilled value must never move
/// with them: it would belong to no formula afterwards, and stay on the sheet as if typed.
final class SpillMoveTests: XCTestCase {
  private let a1 = CellAddress(row: 0, col: 0)

  /// What the app does after every change: works out each spilling formula on the sheet and
  /// places its results, again while anything changes.
  private func respill(_ workbook: inout Workbook) {
    for _ in 0..<4 {
      var sheet = workbook.activeSheet
      let engine = FormulaEngine()
      engine.rebuild(workbook: workbook, recalculate: true)
      var arrays: [CellAddress: ArrayResult] = [:]
      for anchor in SpillLayout.anchors(in: sheet) {
        arrays[anchor] = engine.spillArray(at: anchor, sheet: sheet, activeSheet: sheet)
      }
      let before = sheet.fileExtras
      let outcome = SpillLayout.apply(arrays, to: &sheet)
      workbook.activeSheet = sheet
      if outcome.changedCells.isEmpty, outcome.changedAnchors.isEmpty, sheet.fileExtras == before {
        return
      }
    }
  }

  /// A one-sheet workbook with `cells` typed in, spilled.
  private func workbook(_ cells: [String: String]) -> Workbook {
    var sheet = Sheet(name: "Data")
    for (label, raw) in cells {
      guard let address = A1Reference.parseAddress(label) else { continue }
      sheet.setCell(Cell(raw: raw), at: CellAddress(row: address.row, col: address.col))
    }
    var workbook = Workbook(sheets: [sheet])
    respill(&workbook)
    return workbook
  }

  private func run(
    _ id: String, _ arguments: [String: String], on workbook: inout Workbook,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    let outcome = WorkbookSession().apply(id: id, arguments: arguments, to: &workbook)
    XCTAssertTrue(outcome.ok, outcome.message, file: file, line: line)
  }

  /// Spilled values no formula's results cover, as `A4=3`. There must never be any.
  private func strandedValues(in sheet: Sheet) -> [String] {
    var covered = Set<CellAddress>()
    for (anchor, range) in sheet.fileExtras.spills {
      for address in range.allAddresses() where address != anchor { covered.insert(address) }
    }
    return sheet.cells
      .filter { $0.value.isSpilled && !covered.contains($0.key) }
      .map { "\($0.key.a1)=\($0.value.importedFormulaResult ?? "")" }
      .sorted()
  }

  /// What each cell holds: a formula or typed text as written, a spilled value in brackets.
  private func shown(_ labels: [String], in sheet: Sheet) -> [String] {
    labels.map { label in
      guard let parsed = A1Reference.parseAddress(label) else { return "?" }
      let cell = sheet.cell(at: CellAddress(row: parsed.row, col: parsed.col))
      return cell.isSpilled ? "[\(cell.literalValue.displayString)]" : cell.raw
    }
  }

  private func spills(in sheet: Sheet) -> [String] {
    sheet.fileExtras.spills.map { "\($0.key.a1) fills \($0.value.a1Label)" }.sorted()
  }

  func testSpilledToStartWith() {
    let book = workbook(["A1": "=SEQUENCE(3)"])
    XCTAssertEqual(
      shown(["A1", "A2", "A3", "A4"], in: book.activeSheet), ["=SEQUENCE(3)", "[2]", "[3]", ""])
    XCTAssertEqual(spills(in: book.activeSheet), ["A1 fills A1:A3"])
    XCTAssertEqual(strandedValues(in: book.activeSheet), [])
  }

  func testInsertingARowThroughASpill() {
    var book = workbook(["A1": "=SEQUENCE(3)"])
    run("sheet.insertRows", ["index": "1", "count": "1"], on: &book)
    // Straight after the move, before the results are placed again.
    XCTAssertEqual(strandedValues(in: book.activeSheet), [])
    XCTAssertEqual(
      shown(["A1", "A2", "A3", "A4"], in: book.activeSheet), ["=SEQUENCE(3)", "", "", ""])
    respill(&book)
    XCTAssertEqual(
      shown(["A1", "A2", "A3", "A4", "A5"], in: book.activeSheet),
      ["=SEQUENCE(3)", "[2]", "[3]", "", ""])
    XCTAssertNil(book.activeSheet.cells[CellAddress(row: 3, col: 0)], "A4 held a stray 3")
    XCTAssertEqual(spills(in: book.activeSheet), ["A1 fills A1:A3"])
    XCTAssertEqual(strandedValues(in: book.activeSheet), [])
  }

  func testInsertingRowsAboveASpillMovesItWhole() {
    var book = workbook(["A1": "=SEQUENCE(3)", "B1": "typed"])
    run("sheet.insertRows", ["index": "0", "count": "2"], on: &book)
    XCTAssertEqual(strandedValues(in: book.activeSheet), [])
    respill(&book)
    XCTAssertEqual(
      shown(["A1", "A2", "A3", "A4", "A5", "A6", "B3"], in: book.activeSheet),
      ["", "", "=SEQUENCE(3)", "[2]", "[3]", "", "typed"])
    XCTAssertEqual(spills(in: book.activeSheet), ["A3 fills A3:A5"])
    XCTAssertEqual(strandedValues(in: book.activeSheet), [])
  }

  func testDeletingTheFormulasRowLeavesNothing() {
    var book = workbook(["A1": "=SEQUENCE(3)", "C2": "kept"])
    run("sheet.deleteRows", ["index": "0", "count": "1"], on: &book)
    XCTAssertEqual(strandedValues(in: book.activeSheet), [])
    respill(&book)
    XCTAssertEqual(shown(["A1", "A2", "A3", "C1"], in: book.activeSheet), ["", "", "", "kept"])
    XCTAssertNil(book.activeSheet.cells[a1], "A1 held a stray 2")
    XCTAssertEqual(spills(in: book.activeSheet), [])
    XCTAssertEqual(book.activeSheet.cells.count, 1, "only the typed cell is left")
  }

  func testDeletingARowInsideASpillFillsItAgain() {
    var book = workbook(["A1": "=SEQUENCE(4)"])
    run("sheet.deleteRows", ["index": "1", "count": "2"], on: &book)
    XCTAssertEqual(strandedValues(in: book.activeSheet), [])
    respill(&book)
    XCTAssertEqual(
      shown(["A1", "A2", "A3", "A4", "A5"], in: book.activeSheet),
      ["=SEQUENCE(4)", "[2]", "[3]", "[4]", ""])
    XCTAssertEqual(strandedValues(in: book.activeSheet), [])
  }

  func testInsertingAColumnThroughASpill() {
    var book = workbook(["A1": "=SEQUENCE(1,3)"])
    XCTAssertEqual(
      shown(["A1", "B1", "C1"], in: book.activeSheet), ["=SEQUENCE(1,3)", "[2]", "[3]"])
    run("sheet.insertColumns", ["index": "1", "count": "1"], on: &book)
    XCTAssertEqual(strandedValues(in: book.activeSheet), [])
    respill(&book)
    XCTAssertEqual(
      shown(["A1", "B1", "C1", "D1"], in: book.activeSheet), ["=SEQUENCE(1,3)", "[2]", "[3]", ""])
    XCTAssertNil(book.activeSheet.cells[CellAddress(row: 0, col: 3)], "D1 held a stray 3")
    XCTAssertEqual(strandedValues(in: book.activeSheet), [])
  }

  func testDeletingTheFormulasColumnLeavesNothing() {
    var book = workbook(["A1": "=SEQUENCE(1,3)"])
    run("sheet.deleteColumns", ["index": "0", "count": "1"], on: &book)
    XCTAssertEqual(strandedValues(in: book.activeSheet), [])
    respill(&book)
    XCTAssertTrue(book.activeSheet.cells.isEmpty, "\(book.activeSheet.cells.keys.map(\.a1))")
    XCTAssertEqual(spills(in: book.activeSheet), [])
  }

  func testDeletingAColumnInsideASpillFillsItAgain() {
    var book = workbook(["B2": "=SEQUENCE(2,3)"])
    run("sheet.deleteColumns", ["index": "2", "count": "1"], on: &book)
    XCTAssertEqual(strandedValues(in: book.activeSheet), [])
    respill(&book)
    XCTAssertEqual(
      shown(["B2", "C2", "D2", "E2", "B3", "C3", "D3", "E3"], in: book.activeSheet),
      ["=SEQUENCE(2,3)", "[2]", "[3]", "", "[4]", "[5]", "[6]", ""])
    XCTAssertEqual(strandedValues(in: book.activeSheet), [])
  }

  /// The header row holds the formula; its results lie in the rows being sorted.
  func testSortingRowsASpillLiesIn() {
    var book = workbook([
      "A1": "Name", "B1": "=SEQUENCE(4)",
      "A2": "Cy", "A3": "Ann", "A4": "Bo",
    ])
    XCTAssertEqual(shown(["B2", "B3", "B4"], in: book.activeSheet), ["[2]", "[3]", "[4]"])
    run(
      "data.sort",
      ["sheet": "Data", "range": "A1:B4", "column": "0", "ascending": "true", "header": "true"],
      on: &book)
    XCTAssertEqual(strandedValues(in: book.activeSheet), [])
    respill(&book)
    XCTAssertEqual(shown(["A2", "A3", "A4"], in: book.activeSheet), ["Ann", "Bo", "Cy"])
    // The results are the formula's, in its order, whatever order the rows went into.
    XCTAssertEqual(
      shown(["B1", "B2", "B3", "B4"], in: book.activeSheet), ["=SEQUENCE(4)", "[2]", "[3]", "[4]"])
    XCTAssertEqual(spills(in: book.activeSheet), ["B1 fills B1:B4"])
    XCTAssertEqual(strandedValues(in: book.activeSheet), [])
  }

  /// The formula is in a sorted row, so it moves; its results follow it and none stay behind.
  func testSortingTheRowAFormulaIsIn() {
    var book = workbook([
      "A1": "Name", "A2": "Cy", "A3": "Ann", "A4": "Bo",
      "C2": "=SEQUENCE(3)",
    ])
    XCTAssertEqual(
      shown(["C2", "C3", "C4"], in: book.activeSheet), ["=SEQUENCE(3)", "[2]", "[3]"])
    run(
      "data.sort",
      ["sheet": "Data", "range": "A1:C4", "column": "0", "ascending": "true", "header": "true"],
      on: &book)
    XCTAssertEqual(strandedValues(in: book.activeSheet), [])
    respill(&book)
    XCTAssertEqual(shown(["A2", "A3", "A4"], in: book.activeSheet), ["Ann", "Bo", "Cy"])
    // Cy's row is last now, and the formula went with it.
    XCTAssertEqual(
      shown(["C2", "C3", "C4", "C5", "C6", "C7"], in: book.activeSheet),
      ["", "", "=SEQUENCE(3)", "[2]", "[3]", ""])
    XCTAssertEqual(spills(in: book.activeSheet), ["C4 fills C4:C6"])
    XCTAssertEqual(strandedValues(in: book.activeSheet), [])
  }

  func testAResultOfRealDataFollowsItsFormulaThroughAnInsert() {
    var book = workbook([
      "A1": "West", "A2": "East", "A3": "West", "A4": "North",
      "C1": "=UNIQUE(A1:A4)", "D1": "=COUNTA(C1:C9)",
    ])
    XCTAssertEqual(
      shown(["C1", "C2", "C3", "C4"], in: book.activeSheet),
      ["=UNIQUE(A1:A4)", "[East]", "[North]", ""])
    run("sheet.insertRows", ["index": "2", "count": "1"], on: &book)
    XCTAssertEqual(strandedValues(in: book.activeSheet), [])
    respill(&book)
    // The data now has a blank row in it, which UNIQUE lists as 0, as other apps do.
    XCTAssertEqual(book.activeSheet.cell(at: CellAddress(row: 0, col: 2)).raw, "=UNIQUE(A1:A5)")
    XCTAssertEqual(
      shown(["C2", "C3", "C4", "C5"], in: book.activeSheet), ["[East]", "[0]", "[North]", ""])
    XCTAssertEqual(strandedValues(in: book.activeSheet), [])
  }

  func testClearingKeepsFormatsTypedCellsAndFormulas() {
    var sheet = Sheet(name: "S")
    sheet.setCell(Cell(raw: "=SEQUENCE(3)"), at: a1)
    sheet.setCell(Cell(raw: "typed"), at: CellAddress(row: 0, col: 1))
    SpillLayout.apply(
      [a1: ArrayResult(rows: 3, cols: 1, values: [.number(1), .number(2), .number(3)])],
      to: &sheet)
    var bold = CellFormat()
    bold.bold = true
    let a2 = CellAddress(row: 1, col: 0)
    let a3 = CellAddress(row: 2, col: 0)
    var formatted = sheet.cell(at: a2)
    formatted.format = bold
    sheet.setCell(formatted, at: a2)
    // A value left behind by an earlier move, which no record covers.
    let stray = CellAddress(row: 8, col: 5)
    sheet.setCell(
      Cell(raw: "", importedFormulaResult: "9", importedFormulaValueType: .number), at: stray)
    XCTAssertEqual(sheet.maxPopulatedRow, 8)

    let cleared = SpillLayout.clearSpills(in: &sheet)
    XCTAssertEqual(cleared, [a2, a3, stray])
    XCTAssertEqual(sheet.cell(at: a1).raw, "=SEQUENCE(3)")
    XCTAssertEqual(sheet.cell(at: CellAddress(row: 0, col: 1)).raw, "typed")
    XCTAssertEqual(sheet.cells[a2]?.format, bold, "the format stays")
    XCTAssertFalse(sheet.cell(at: a2).hasContent, "the value goes")
    XCTAssertNil(sheet.cells[a3])
    XCTAssertNil(sheet.cells[stray])
    XCTAssertTrue(sheet.fileExtras.spills.isEmpty)
    XCTAssertTrue(sheet.fileExtras.blockedSpills.isEmpty)
    XCTAssertEqual(sheet.maxPopulatedRow, 1, "the sheet no longer reaches the stray cell's row")
    XCTAssertEqual(SpillLayout.clearSpills(in: &sheet), [], "nothing left to clear")
  }

  func testABlockedFormulaIsWorkedOutAgainAfterAMove() {
    var book = workbook(["A1": "=SEQUENCE(3)", "A3": "in the way"])
    XCTAssertEqual(book.activeSheet.fileExtras.blockedSpills, [a1])
    // Deleting the row of the cell in the way frees the formula.
    run("sheet.deleteRows", ["index": "2", "count": "1"], on: &book)
    XCTAssertTrue(book.activeSheet.fileExtras.blockedSpills.isEmpty)
    respill(&book)
    XCTAssertEqual(
      shown(["A1", "A2", "A3"], in: book.activeSheet), ["=SEQUENCE(3)", "[2]", "[3]"])
    XCTAssertTrue(book.activeSheet.fileExtras.blockedSpills.isEmpty)
    XCTAssertEqual(strandedValues(in: book.activeSheet), [])
  }
}
