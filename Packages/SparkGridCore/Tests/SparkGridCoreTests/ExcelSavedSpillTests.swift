import Calc
import Engine
import Foundation
import GridCore
import Model
import XCTest

@testable import FileFormats

/// `Fixtures/excel-dynamic-arrays.xlsx` was saved by Excel 16.115 for Mac (Nov 12 2026) from a
/// Spark Grid file with FILTER, SORT, SORTBY and UNIQUE. Only the saved path and the last-author
/// name were replaced afterwards. Its spills must open as spills, with Excel's values.
final class ExcelSavedSpillTests: XCTestCase {
  private func fixture() throws -> Sheet {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let data = try Data(
      contentsOf: root.appendingPathComponent("Fixtures/excel-dynamic-arrays.xlsx"))
    return try XLSXCodec.importWorkbook(from: data).activeSheet
  }

  private func address(_ a1: String) -> CellAddress {
    let letters = a1.prefix { $0.isLetter }
    let col = letters.unicodeScalars.reduce(0) { $0 * 26 + Int($1.value) - 64 } - 1
    return CellAddress(row: Int(a1.dropFirst(letters.count))! - 1, col: col)
  }

  /// What Excel calculated, read back from the file Excel saved.
  private let excelColumns: [String: [String]] = [
    "E": ["Ann", "Ann", "Bo", "Cy", "Di", "Ed"],
    "F": ["East", "West", "North"],
    "G": ["Cy", "Ann", "Di"],
    "H": ["Ann", "Di", "Cy", "Bo", "Ann", "Ed"],
    "I": ["Ann", "Di", "Cy", "Bo", "Ann", "Ed"],
    "J": ["West", "North", "East", "East", "West", "West"],
    "K": ["340", "340", "120", "90", "60", "15"],
  ]

  func testOpensExcelsSpillsAsSpills() throws {
    let sheet = try fixture()
    let spills = sheet.fileExtras.spills.mapValues(\.a1Label)
    XCTAssertEqual(spills[address("E1")], "E1:E6")
    XCTAssertEqual(spills[address("F1")], "F1:F3")
    XCTAssertEqual(spills[address("G1")], "G1:G3")
    XCTAssertEqual(spills[address("H1")], "H1:H6")
    XCTAssertEqual(spills[address("I1")], "I1:K6")
    // One-cell arrays (a COUNTA of UNIQUE, a FILTER with one result, a blocked spill) are not
    // spills.
    for single in ["M2", "N1", "E10"] { XCTAssertNil(spills[address(single)], single) }
    for (column, values) in excelColumns {
      for (offset, value) in values.enumerated() {
        let a1 = "\(column)\(offset + 1)"
        let cell = sheet.cell(at: address(a1))
        XCTAssertEqual(cell.importedFormulaResult, value, a1)
        if offset > 0 || column == "J" || column == "K" {
          XCTAssertTrue(cell.isSpilled, "\(a1) should be a spilled result, not typed")
        }
      }
    }
    XCTAssertEqual(sheet.cell(at: address("E12")).raw, "blocker")
  }

  /// Recalculated the way the app does after opening, the spills give Excel's answers, and the
  /// spill that Excel saved as blocked is blocked.
  func testRecalculatedSpillsMatchExcel() throws {
    var sheet = try fixture()
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
    for (column, values) in excelColumns {
      for (offset, value) in values.enumerated() {
        let a1 = "\(column)\(offset + 1)"
        let shown = engine.sheetDisplayValue(at: address(a1), sheet: sheet)
        XCTAssertEqual(shown.displayString, value, a1)
      }
    }
    XCTAssertTrue(sheet.fileExtras.blockedSpills.contains(address("E10")))
    XCTAssertEqual(engine.displayValue(at: address("M2"), sheet: sheet), .number(5))
    XCTAssertEqual(engine.displayValue(at: address("N1"), sheet: sheet), .string("none"))
    // Saved by Excel as ROWS(_xlfn.ANCHORARRAY(G1)); Excel showed 3.
    XCTAssertEqual(engine.displayValue(at: address("M1"), sheet: sheet), .number(3))
  }
}
