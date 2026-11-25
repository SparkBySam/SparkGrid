import Foundation
import GridCore
import Model
import XCTest

@testable import FileFormats

/// The per-style scans of `styles.xml` (unlocked, rotation, clip) count `<xf>` elements in
/// order. Self-closing ones before a style with children must each count once (Nov 23).
final class StyleIndexScanTests: XCTestCase {
  private func archive(cellXfs: String) throws -> Data {
    let styles = """
      <?xml version="1.0" encoding="UTF-8"?>
      <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">\
      <cellXfs count="5">\(cellXfs)</cellXfs></styleSheet>
      """
    return try XCTUnwrap(XLSXCodec.zipArchive(files: ["xl/styles.xml": Data(styles.utf8)]))
  }

  func testSelfClosingStylesBeforeOneWithChildrenKeepTheirIndexes() throws {
    let data = try archive(
      cellXfs: #"<xf numFmtId="0" xfId="0" /><xf numFmtId="0" fontId="1" xfId="0"/>"#
        + #"<xf numFmtId="0" applyProtection="1" xfId="0"><protection locked="0" hidden="0" /></xf>"#
        + #"<xf numFmtId="0" xfId="0" />"#
        + #"<xf numFmtId="0" xfId="0"><alignment textRotation="45"/></xf>"#)
    XCTAssertEqual(XLSXCodec.importUnlockedStyleIndexes(archiveData: data), [2])
    XCTAssertEqual(XLSXCodec.importTextRotationsByStyleIndex(archiveData: data), [4: 45])
  }

  func testStylesWithChildrenOnlyStillWork() throws {
    let data = try archive(
      cellXfs: #"<xf xfId="0"><alignment/></xf><xf xfId="0"><protection locked="0"/></xf>"#)
    XCTAssertEqual(XLSXCodec.importUnlockedStyleIndexes(archiveData: data), [1])
  }

  /// The 1.7 stress workbook's Protected 1.4 sheet: its yellow cells are unlocked.
  func testStressWorkbookYellowCellsAreUnlocked() throws {
    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("Fixtures/Sales-Ops-Stress-2026-1.7.xlsx")
    // The workbook is git-ignored; SPARK_GRID_FIXTURES points at a folder that has it.
    let named = ProcessInfo.processInfo.environment["SPARK_GRID_FIXTURES"].map {
      URL(fileURLWithPath: $0).appendingPathComponent("Sales-Ops-Stress-2026-1.7.xlsx")
    }
    guard let data = (try? Data(contentsOf: url)) ?? named.flatMap({ try? Data(contentsOf: $0) })
    else {
      throw XCTSkip("The stress workbook is not in this checkout.")
    }
    let workbook = try XLSXCodec.importWorkbook(from: data)
    let sheet = try XCTUnwrap(workbook.sheets.first { $0.name == "Protected 1.4" })
    XCTAssertEqual(sheet.cell(at: .init(row: 5, col: 1)).format?.locked, false)
    XCTAssertNotEqual(sheet.cell(at: .init(row: 5, col: 3)).format?.locked, false)
  }
}
