import Calc
import Engine
import Foundation
import GridCore
import Model
import XCTest

@testable import FileFormats

/// A range or a one-value function given a range, typed on its own in a cell, spills a value
/// for each cell, as in other apps (Excel 16.115). A formula a file saved the pre-spill way
/// opens as one value.
final class RangeSpillTests: XCTestCase {
  private func laidOut(_ sheet: Sheet) -> (Sheet, FormulaEngine) {
    var sheet = sheet
    let engine = FormulaEngine()
    for _ in 0..<4 {
      engine.rebuild(sheet: sheet, recalculate: true)
      var arrays: [CellAddress: ArrayResult] = [:]
      for anchor in SpillLayout.anchors(in: sheet) {
        arrays[anchor] = engine.spillArray(at: anchor, sheet: sheet, activeSheet: sheet)
      }
      let outcome = SpillLayout.apply(arrays, to: &sheet)
      if outcome.changedCells.isEmpty && outcome.changedAnchors.isEmpty { break }
    }
    engine.rebuild(sheet: sheet, recalculate: true)
    return (sheet, engine)
  }

  private func data() -> Sheet {
    var sheet = Sheet(name: "Data")
    for (row, word) in ["a", "bb", "ccc"].enumerated() {
      sheet.setCell(Cell(raw: word), at: CellAddress(row: row, col: 0))
      sheet.setCell(Cell(raw: String(row + 1)), at: CellAddress(row: row, col: 1))
    }
    return sheet
  }

  private func shown(_ engine: FormulaEngine, _ sheet: Sheet, _ a1s: [String]) -> [String] {
    a1s.map { a1 in
      let address = XLSXCodec.parseCellRange(a1)!.start
      return engine.sheetDisplayValue(at: address, sheet: sheet).displayString
    }
  }

  func testRangesAndOneValueFunctionsSpill() {
    var sheet = data()
    sheet.setCell(Cell(raw: "=LEN(A1:A3)"), at: CellAddress(row: 0, col: 3))
    sheet.setCell(Cell(raw: "=B1:B3*10"), at: CellAddress(row: 0, col: 4))
    sheet.setCell(Cell(raw: "=A1:A3"), at: CellAddress(row: 0, col: 5))
    sheet.setCell(Cell(raw: "=ROW(B1:B3)"), at: CellAddress(row: 0, col: 6))
    sheet.setCell(Cell(raw: "=SUM(B1:B3)"), at: CellAddress(row: 0, col: 7))
    let (laid, engine) = laidOut(sheet)
    XCTAssertEqual(shown(engine, laid, ["D1", "D2", "D3"]), ["1", "2", "3"])
    XCTAssertEqual(shown(engine, laid, ["E1", "E2", "E3"]), ["10", "20", "30"])
    XCTAssertEqual(shown(engine, laid, ["F1", "F2", "F3"]), ["a", "bb", "ccc"])
    XCTAssertEqual(shown(engine, laid, ["G1", "G2", "G3"]), ["1", "2", "3"])
    // A total stays one value.
    XCTAssertEqual(shown(engine, laid, ["H1", "H2"]), ["6", ""])
    XCTAssertNil(laid.fileExtras.spills[CellAddress(row: 0, col: 7)])
  }

  /// Saved and opened again, the spills open as spills; a file's pre-spill formula does not
  /// spill until it is typed again.
  func testFilesKeepEachKind() throws {
    var sheet = data()
    sheet.setCell(Cell(raw: "=B1:B3*10"), at: CellAddress(row: 0, col: 4))
    let (laid, _) = laidOut(sheet)
    let saved = try XLSXCodec.exportWorkbook(Workbook(sheets: [laid]))
    let reopened = try XLSXCodec.importWorkbook(from: saved).sheets[0]
    XCTAssertNil(reopened.cell(at: CellAddress(row: 0, col: 4)).opensAsOneValue)
    XCTAssertEqual(SpillLayout.anchors(in: reopened), [CellAddress(row: 0, col: 4)])

    // The same formula written as other apps wrote it before results could spill.
    var legacy = data()
    legacy.setCell(Cell(raw: "=B1:B3*10"), at: CellAddress(row: 0, col: 4))
    legacy.setCell(Cell(raw: "=SUM(B1:B3)"), at: CellAddress(row: 0, col: 5))
    var xlsx = try XLSXCodec.exportWorkbook(Workbook(sheets: [legacy]))
    xlsx = try Self.withoutArrayMarks(xlsx)
    var opened = try XLSXCodec.importWorkbook(from: xlsx).sheets[0]
    XCTAssertEqual(opened.cell(at: CellAddress(row: 0, col: 4)).opensAsOneValue, true)
    XCTAssertTrue(SpillLayout.anchors(in: opened).isEmpty)
    // Typed again, it spills.
    var session = WorkbookSession(workbook: Workbook(sheets: [opened]))
    _ = session.run(id: "cell.set", arguments: ["address": "E1", "raw": "=B1:B3*10"])
    opened = session.workbook.sheets[0]
    XCTAssertNil(opened.cell(at: CellAddress(row: 0, col: 4)).opensAsOneValue)
    XCTAssertEqual(SpillLayout.anchors(in: opened), [CellAddress(row: 0, col: 4)])
  }

  /// The worksheet XML with every array mark taken out, as a file from before spills.
  private static func withoutArrayMarks(_ data: Data) throws -> Data {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("a.xlsx")
    try data.write(to: file)
    let unzip = Process()
    unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
    unzip.arguments = ["-q", file.path, "-d", dir.appendingPathComponent("x").path]
    try unzip.run()
    unzip.waitUntilExit()
    let sheetURL = dir.appendingPathComponent("x/xl/worksheets/sheet1.xml")
    var xml = try String(contentsOf: sheetURL, encoding: .utf8)
    xml = xml.replacingOccurrences(of: #" cm="1""#, with: "")
    xml = xml.replacingOccurrences(
      of: #"<f t="array" ref="[A-Z0-9:]+">"#, with: "<f>", options: .regularExpression)
    try xml.write(to: sheetURL, atomically: true, encoding: .utf8)
    let zip = Process()
    zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
    zip.currentDirectoryURL = dir.appendingPathComponent("x")
    zip.arguments = ["-q", "-r", "../b.xlsx", "."]
    try zip.run()
    zip.waitUntilExit()
    return try Data(contentsOf: dir.appendingPathComponent("b.xlsx"))
  }
}
