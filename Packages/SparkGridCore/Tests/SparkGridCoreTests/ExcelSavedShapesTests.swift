import Calc
import Engine
import Foundation
import GridCore
import Model
import XCTest

@testable import FileFormats

/// `Fixtures/excel-array-shapes.xlsx`: a Spark Grid file with LET, VSTACK, HSTACK, TAKE, DROP,
/// CHOOSECOLS, CHOOSEROWS, WRAPROWS, WRAPCOLS, TOCOL, TOROW, TEXTSPLIT and RANDARRAY, opened,
/// fully recalculated and saved by Excel 16.115 for Mac (Nov 17 2026). Only the last-author name
/// and saved path were replaced afterwards. Excel read every function and LET name Spark Grid
/// saved, and Spark Grid recalculates every cell to Excel's answer.
final class ExcelSavedShapesTests: XCTestCase {
  private func fixture() throws -> Sheet {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let data = try Data(contentsOf: root.appendingPathComponent("Fixtures/excel-array-shapes.xlsx"))
    return try XLSXCodec.importWorkbook(from: data).activeSheet
  }

  private func address(_ a1: String) -> CellAddress {
    XLSXCodec.parseCellRange(a1)!.start
  }

  /// What Excel showed in each cell, as it saved it.
  private func excelValues(_ sheet: Sheet) -> [CellAddress: String] {
    var out: [CellAddress: String] = [:]
    for (address, cell) in sheet.cells {
      out[address] = cell.importedFormulaResult ?? cell.raw
    }
    return out
  }

  func testSpillsOpenAsExcelSavedThem() throws {
    let sheet = try fixture()
    let spills = sheet.fileExtras.spills.mapValues(\.a1Label)
    let expected = [
      "G1": "G1:G3", "H1": "H1:I3", "K1": "K1:L3", "N1": "N1:O2", "Q1": "Q1:R3", "T1": "T1:U4",
      "W1": "W1:Y2", "A7": "A7:B8", "D7": "D7:E8", "G7": "G7:G10", "I7": "I7:K7",
      "I9": "I9:J10", "M7": "M7:O7", "M9": "M9:O9", "Q9": "Q9:R10", "X7": "X7:X9",
    ]
    for (anchor, range) in expected {
      XCTAssertEqual(spills[address(anchor)], range, anchor)
    }
    // Excel keeps the prefixes in what it saves; Spark Grid reads them and shows the names as
    // typed (`total`, not `_xlpm.total`), adding the prefixes back when it saves.
    let let1 = sheet.cell(at: address("F1")).raw
    XCTAssertFalse(let1.lowercased().contains("_xlpm."), let1)
    XCTAssertFalse(let1.lowercased().contains("_xlfn."), let1)
    XCTAssertTrue(let1.contains("total"), let1)
  }

  func testRecalculatedValuesMatchExcel() throws {
    var sheet = try fixture()
    let excel = excelValues(sheet)
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
    XCTAssertEqual(excel.count, 91)
    for (address, value) in excel {
      let shown = engine.sheetDisplayValue(at: address, sheet: sheet)
      if case .number(let n) = shown, let expected = Double(value) {
        XCTAssertEqual(n, expected, accuracy: 1e-9, address.a1)
      } else {
        XCTAssertEqual(shown.displayString, value, address.a1)
      }
    }
  }
}
