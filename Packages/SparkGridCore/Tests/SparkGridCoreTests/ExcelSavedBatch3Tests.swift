import Calc
import Engine
import Foundation
import GridCore
import Model
import XCTest

@testable import FileFormats

/// `Fixtures/excel-functions-batch3.xlsx`: a Spark Grid file using every 1.5 batch 3 function
/// and typed lists such as `{1,2;3,4}`, opened, fully recalculated and saved by Excel 16.115 for
/// Mac (Nov 18 2026). Only the last-author name and saved path were replaced afterwards.
/// Column G has each formula as text, column H the formula; spills start in row 2 from K.
final class ExcelSavedBatch3Tests: XCTestCase {
  private func fixture() throws -> Sheet {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let data = try Data(
      contentsOf: root.appendingPathComponent("Fixtures/excel-functions-batch3.xlsx"))
    return try XLSXCodec.importWorkbook(from: data).activeSheet
  }

  func testRecalculatedValuesMatchExcel() throws {
    var sheet = try fixture()
    var excel: [CellAddress: Cell] = [:]
    for (address, cell) in sheet.cells where cell.importedFormulaResult != nil || cell.isSpilled {
      excel[address] = cell
    }
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
    XCTAssertEqual(excel.count, 146)
    for (address, saved) in excel {
      let value = saved.importedFormulaResult ?? saved.raw
      let shown = engine.sheetDisplayValue(at: address, sheet: sheet)
      let label = sheet.cell(at: CellAddress(row: address.row, col: 6)).raw
      switch shown {
      case .bool(let b) where saved.importedFormulaValueType == .boolean:
        XCTAssertEqual(value == "1", b, "\(address.a1) \(label)")
      case .number(let n):
        guard let expected = Double(value) else {
          XCTFail("\(address.a1) \(label): Excel \(value), Spark Grid \(n)")
          continue
        }
        XCTAssertEqual(
          n, expected, accuracy: max(1e-9, abs(expected) * 1e-9), "\(address.a1) \(label)")
      default:
        XCTAssertEqual(shown.displayString, value, "\(address.a1) \(label)")
      }
    }
  }

  /// The typed lists and TRANSPOSE open as spills, in the size Excel saved them.
  func testSpillsOpenAsSaved() throws {
    let spills = try fixture().fileExtras.spills.mapValues(\.a1Label)
    let anchor = { (a1: String) in XLSXCodec.parseCellRange(a1)!.start }
    XCTAssertEqual(spills[anchor("K2")], "K2:M2")
    XCTAssertEqual(spills[anchor("O2")], "O2:O4")
    XCTAssertEqual(spills[anchor("S2")], "S2:T3")
    XCTAssertEqual(spills[anchor("W2")], "W2:Z2")
    XCTAssertEqual(spills[anchor("AA2")], "AA2:AC3")
  }
}
