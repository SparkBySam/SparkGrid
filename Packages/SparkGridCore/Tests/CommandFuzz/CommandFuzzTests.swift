import Calc
import FileFormats
import Formula
import Foundation
import GridCore
import Model
import NumberFormat
import XCTest

@testable import Engine

@MainActor
final class CommandFuzzTests: XCTestCase {
  func testMissingParametersDoNotChangeTheWorkbook() {
    let session = WorkbookSession()
    let outcome = session.run(id: "cell.set", arguments: [:])
    XCTAssertFalse(outcome.ok)
    XCTAssertTrue(session.workbook.sheets[0].cells.isEmpty)
    XCTAssertFalse(session.isEnabled("edit.undo"))
    XCTAssertTrue(session.isEnabled("cell.set"))
    XCTAssertFalse(session.isEnabled("sheet.delete"))
  }

  func testUndoThenRedoRestoresTheEdit() {
    let session = WorkbookSession()
    let outcome = session.run(
      id: "cell.set",
      arguments: ["address": "A1", "raw": "42"]
    )
    XCTAssertTrue(outcome.ok)
    XCTAssertEqual(session.workbook.activeSheet.cell(at: .origin).raw, "42")
    XCTAssertTrue(session.undo())
    XCTAssertEqual(session.workbook.activeSheet.cell(at: .origin).raw, "")
    XCTAssertTrue(session.redo())
    XCTAssertEqual(session.workbook.activeSheet.cell(at: .origin).raw, "42")
  }

  func testApplyDoesNotSnapshotUndo() {
    let session = WorkbookSession()
    var workbook = session.workbook
    let outcome = session.apply(
      id: "cell.set",
      arguments: ["address": "A1", "raw": "50%"],
      to: &workbook
    )
    XCTAssertTrue(outcome.ok)
    XCTAssertEqual(workbook.activeSheet.cell(at: .origin).raw, "50%")
    XCTAssertEqual(workbook.activeSheet.cell(at: .origin).format?.numberFormat, .percent)
    XCTAssertFalse(session.canUndo)
  }

  func testSortMovesAMergeWithItsRow() {
    var sheet = Sheet(name: "Sheet1")
    sheet.setCell(Cell(raw: "b"), at: CellAddress(row: 0, col: 0))
    sheet.setCell(Cell(raw: "a"), at: CellAddress(row: 1, col: 0))
    sheet.mergedRanges = [
      CellRange(
        start: CellAddress(row: 0, col: 0),
        end: CellAddress(row: 0, col: 1)
      )
    ]
    var workbook = Workbook(sheets: [sheet])
    let session = WorkbookSession(workbook: workbook)
    let outcome = session.apply(
      id: "data.sort",
      arguments: ["range": "A1:B2", "column": "0", "ascending": "true"],
      to: &workbook
    )
    XCTAssertTrue(outcome.ok, outcome.message)
    XCTAssertEqual(workbook.activeSheet.cell(at: CellAddress(row: 0, col: 0)).raw, "a")
    XCTAssertEqual(workbook.activeSheet.cell(at: CellAddress(row: 1, col: 0)).raw, "b")
    let merge = workbook.activeSheet.mergedRanges[0].normalized
    XCTAssertEqual(merge.minRow, 1)
    XCTAssertEqual(merge.maxCol, 1)
  }

  func testSortOrderPutsRowsBack() {
    var sheet = Sheet(name: "Sheet1")
    for (row, text) in ["Name", "c", "a", "b"].enumerated() {
      sheet.setCell(Cell(raw: text), at: CellAddress(row: row, col: 0))
    }
    var workbook = Workbook(sheets: [sheet])
    let session = WorkbookSession(workbook: workbook)
    let sorted = session.apply(
      id: "data.sort",
      arguments: ["range": "A1:A4", "column": "0", "ascending": "true", "header": "true"],
      to: &workbook
    )
    XCTAssertTrue(sorted.ok, sorted.message)
    // a came from row 2, b from row 3, c from row 1.
    XCTAssertEqual(session.lastSortOrder, [2, 3, 1])

    // Row 1 now holds what came from row 2, and so on. Put each back.
    let current = session.lastSortOrder
    let restore = (1...3).map { original in 1 + current.firstIndex(of: original)! }
    let restored = session.apply(
      id: "data.sort",
      arguments: [
        "range": "A1:A4", "column": "0", "header": "true",
        "order": restore.map(String.init).joined(separator: ","),
      ],
      to: &workbook
    )
    XCTAssertTrue(restored.ok, restored.message)
    let column = (1...3).map { workbook.activeSheet.cell(at: CellAddress(row: $0, col: 0)).raw }
    XCTAssertEqual(column, ["c", "a", "b"])

    let bad = session.apply(
      id: "data.sort",
      arguments: ["range": "A1:A4", "column": "0", "header": "true", "order": "1,1,2"],
      to: &workbook
    )
    XCTAssertFalse(bad.ok)
  }

  func testPasteAdjustsARelativeFormula() {
    var workbook = Workbook()
    let session = WorkbookSession()
    let outcome = session.apply(
      id: "edit.paste",
      arguments: ["anchor": "B2", "text": "=A1", "rowDelta": "1", "colDelta": "1"],
      to: &workbook
    )
    XCTAssertTrue(outcome.ok, outcome.message)
    XCTAssertEqual(workbook.activeSheet.cell(at: CellAddress(row: 1, col: 1)).raw, "=B2")
  }

  func testFuzzSmoke() throws {
    let env = ProcessInfo.processInfo.environment
    let seed = UInt64(env["SPARK_GRID_FUZZ_SEED"] ?? "") ?? 1
    let steps = Int(env["SPARK_GRID_FUZZ_STEPS"] ?? "") ?? 20
    var rng = SplitMix64(state: seed == 0 ? 1 : seed)
    let session = WorkbookSession(workbook: seedWorkbook())
    let incremental = FormulaEngine()
    incremental.rebuild(workbook: session.workbook, recalculate: true)
    for step in 0..<steps {
      let invocation = nextCommand(&rng, session: session)
      let outcome = session.run(id: invocation.id, arguments: invocation.arguments)
      if outcome.ok == false && invocation.id != "edit.undo" && invocation.id != "edit.redo"
        && invocation.id != "sheet.delete"
      {
        // A refused hostile or incomplete command leaves the workbook unchanged.
      }
      if session.lastChange.structural || !outcome.ok {
        incremental.rebuild(workbook: session.workbook, recalculate: true)
      } else if !session.lastChange.addresses.isEmpty {
        let sheet =
          sheetNamed(session.lastChange.sheetName, in: session.workbook)
          ?? session.workbook.activeSheet
        incremental.cellsDidChange(session.lastChange.addresses, sheet: sheet)
      }
      let snapshot = session.workbook
      var undone = 0
      while session.canUndo {
        if session.undo() == false { break }
        undone += 1
      }
      for _ in 0..<undone {
        if session.redo() == false {
          failReplay(
            seed: seed,
            steps: step + 1,
            reason: "redo stopped early after \(undone) undos at step \(step) (\(invocation.id))"
          )
          return
        }
      }
      if session.workbook != snapshot {
        failReplay(
          seed: seed,
          steps: step + 1,
          reason: "undo all then redo all changed the workbook at step \(step) (\(invocation.id))"
        )
        return
      }
      do {
        let exported = try XLSXCodec.exportWorkbook(session.workbook, includeFormulaCaches: true)
        let imported = try XLSXCodec.importWorkbook(from: exported)
        if let reason = contentDifference(session.workbook, imported) {
          failReplay(seed: seed, steps: step + 1, reason: "export/import \(reason) at step \(step)")
          return
        }
      } catch {
        failReplay(seed: seed, steps: step + 1, reason: "export/import threw at step \(step)")
        return
      }
      if let reason = recalcDifference(incremental: incremental, workbook: session.workbook) {
        failReplay(
          seed: seed,
          steps: step + 1,
          reason: "incremental recalc \(reason) at step \(step) after \(invocation.id)"
        )
        return
      }
    }
    print("fuzz smoke: seed \(seed) steps \(steps) pass")
  }

  private struct Invocation {
    var id: String
    var arguments: [String: String]
  }

  private func nextCommand(_ rng: inout SplitMix64, session: WorkbookSession) -> Invocation {
    let ids = [
      "cell.set", "edit.paste", "edit.fill",
      "sheet.insertRows", "sheet.deleteRows", "sheet.insertColumns", "sheet.deleteColumns",
      "data.sort", "edit.undo", "edit.redo", "sheet.add", "sheet.rename", "sheet.delete",
    ]
    let id = ids[rng.int(ids.count)]
    let sheet = session.workbook.activeSheet.name
    switch id {
    case "cell.set":
      let raws = ["1", "2", "9", "=A1+1", "=SUM(A1:B1)", "hello"]
      return Invocation(
        id: id,
        arguments: [
          "sheet": sheet,
          "address": address(row: rng.int(6), col: rng.int(4)),
          "raw": raws[rng.int(raws.count)],
        ]
      )
    case "edit.paste":
      return Invocation(
        id: id,
        arguments: [
          "sheet": sheet,
          "anchor": address(row: rng.int(4), col: rng.int(3)),
          "text": "\(rng.int(9))\t\(rng.int(9))\n=A1+B1",
        ]
      )
    case "edit.fill":
      return Invocation(
        id: id,
        arguments: [
          "sheet": sheet,
          "source": "A1:A2",
          "end": address(row: 2 + rng.int(3), col: rng.int(2)),
        ]
      )
    case "sheet.insertRows", "sheet.deleteRows":
      return Invocation(
        id: id,
        arguments: ["sheet": sheet, "index": String(rng.int(4)), "count": "1"]
      )
    case "sheet.insertColumns", "sheet.deleteColumns":
      return Invocation(
        id: id,
        arguments: ["sheet": sheet, "index": String(rng.int(3)), "count": "1"]
      )
    case "data.sort":
      return Invocation(
        id: id,
        arguments: [
          "sheet": sheet,
          "range": "A1:C4",
          "column": String(rng.int(3)),
          "ascending": rng.int(2) == 0 ? "true" : "false",
          "header": "false",
        ]
      )
    case "sheet.add":
      return Invocation(id: id, arguments: ["name": "Extra"])
    case "sheet.rename":
      return Invocation(id: id, arguments: ["sheet": sheet, "name": "Renamed\(rng.int(5))"])
    case "sheet.delete":
      return Invocation(id: id, arguments: ["sheet": sheet])
    default:
      return Invocation(id: id, arguments: [:])
    }
  }

  private func seedWorkbook() -> Workbook {
    var sheet = Sheet(name: "Sheet1")
    var first = Cell(raw: "1")
    first.format = CellFormat(bold: true, numberFormat: .number, formatCode: "0.00")
    sheet.setCell(first, at: CellAddress(row: 0, col: 0))
    sheet.setCell(Cell(raw: "2"), at: CellAddress(row: 0, col: 1))
    var formula = Cell(raw: "=A1+B1")
    formula.importedFormulaResult = "3"
    formula.importedFormulaValueType = .number
    sheet.setCell(formula, at: CellAddress(row: 0, col: 2))
    sheet.setCell(Cell(raw: "4"), at: CellAddress(row: 1, col: 0))
    return Workbook(sheets: [sheet])
  }

  private func address(row: Int, col: Int) -> String {
    CellAddress(row: row, col: col).a1
  }

  private func sheetNamed(_ name: String, in workbook: Workbook) -> Sheet? {
    workbook.sheets.first { $0.name == name }
  }

  private func failReplay(seed: UInt64, steps: Int, reason: String) {
    XCTFail(
      """
      \(reason)
      replay: SPARK_GRID_FUZZ_SEED=\(seed) SPARK_GRID_FUZZ_STEPS=\(steps)
      """
    )
  }

  private func contentDifference(_ left: Workbook, _ right: Workbook) -> String? {
    guard left.sheets.count == right.sheets.count else {
      return "sheet count \(left.sheets.count) vs \(right.sheets.count)"
    }
    for (lhs, rhs) in zip(left.sheets, right.sheets) {
      if lhs.name != rhs.name { return "sheet name \(lhs.name) vs \(rhs.name)" }
      let addresses = Set(lhs.cells.keys).union(rhs.cells.keys)
      for address in addresses {
        let a = lhs.cell(at: address)
        let b = rhs.cell(at: address)
        if a.raw != b.raw {
          return "\(lhs.name)!\(address.a1) raw \(a.raw) vs \(b.raw)"
        }
        if !sameFormat(a.format, b.format) {
          return
            "\(lhs.name)!\(address.a1) format \(formatDump(a.format)) vs \(formatDump(b.format))"
        }
        if a.importedFormulaResult != b.importedFormulaResult {
          return "\(lhs.name)!\(address.a1) saved result"
        }
      }
    }
    return nil
  }

  private func formatDump(_ format: CellFormat?) -> String {
    guard let format else { return "nil" }
    return
      "bold=\(format.bold) italic=\(format.italic) num=\(format.numberFormat) code=\(format.formatCode ?? "nil") decimals=\(String(describing: format.decimalPlaces)) default=\(format.isDefault)"
  }

  private func sameFormat(_ left: CellFormat?, _ right: CellFormat?) -> Bool {
    let a = left ?? CellFormat()
    let b = right ?? CellFormat()
    if a.isDefault && b.isDefault { return true }
    return a.bold == b.bold && a.italic == b.italic && a.numberFormat == b.numberFormat
      && a.formatCode == b.formatCode && a.decimalPlaces == b.decimalPlaces
  }

  private func recalcDifference(incremental: FormulaEngine, workbook: Workbook) -> String? {
    let full = FormulaEngine()
    full.recalculateEntireWorkbook(workbook)
    for sheet in workbook.sheets where sheet.name == workbook.activeSheet.name {
      let stored = full.formulaResults(on: sheet)
      for (address, cell) in sheet.cells where FormulaSyntax.isFormula(cell.raw) {
        let live = incremental.displayValue(at: address, sheet: sheet)
        let expected = stored[address] ?? .blank
        if AnswerValues.same(live, expected) { continue }
        return
          "\(sheet.name)!\(address.a1) incremental \(live.displayString) full \(expected.displayString)"
      }
    }
    return nil
  }
}

private struct SplitMix64 {
  var state: UInt64

  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }

  mutating func int(_ upper: Int) -> Int {
    guard upper > 0 else { return 0 }
    return Int(next() % UInt64(upper))
  }
}
