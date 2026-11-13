import FileFormats
import Foundation
import GridCore
import Model
import XCTest

/// `Fixtures/excel-1.4-features.xlsx` was made by Spark Grid's own commands (two pivot tables, a
/// pivot chart, GETPIVOTDATA, a print area, page breaks, row and column groups, links and a
/// protected sheet), then opened and saved by Excel 16.115 for Mac (Nov 13 2026). Only the saved
/// path and author names were replaced afterwards. What Excel kept must open as it was made.
final class ExcelSavedFeaturesTests: XCTestCase {
  private func workbook() throws -> Workbook {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let data = try Data(
      contentsOf: root.appendingPathComponent("Fixtures/excel-1.4-features.xlsx"))
    return try XLSXCodec.importWorkbook(from: data)
  }

  private func sheet(_ name: String) throws -> Sheet {
    try XCTUnwrap(try workbook().sheets.first { $0.name == name }, name)
  }

  func testPrintAreaBreaksAndGroups() throws {
    let report = try sheet("Report")
    let extras = report.fileExtras
    XCTAssertEqual(extras.printArea?.a1Label, "A1:D25")
    XCTAssertEqual(extras.rowBreaks, [12])
    XCTAssertEqual(extras.columnBreaks, [2])
    XCTAssertEqual(extras.rowOutlineLevels, [1: 1, 2: 2, 3: 2, 4: 1, 5: 1])
    XCTAssertEqual(extras.columnOutlineLevels, [1: 1, 2: 1])
    // Grouped, not hidden, and at the default width: Excel had saved them zero wide before.
    XCTAssertTrue(extras.hiddenColumns.isEmpty)
    XCTAssertNil(report.columnWidths[1])
    XCTAssertNil(report.columnWidths[2])
  }

  func testLinks() throws {
    let links = try sheet("Report").fileExtras.hyperlinks.sorted {
      $0.range.start.row < $1.range.start.row
    }
    XCTAssertEqual(links.count, 3)
    XCTAssertEqual(links[0].target, "https://example.com/spark")
    XCTAssertEqual(links[1].target, "mailto:hello@example.com")
    XCTAssertEqual(links[2].location, "Sales!D5")
  }

  func testProtectionKeepsPasswordAndAllowances() throws {
    let xml = try sheet("Locked").fileExtras.protectionXML
    XCTAssertTrue(SheetProtection.hasPassword(xml))
    XCTAssertTrue(SheetProtection.verify("spark", against: xml))
    XCTAssertFalse(SheetProtection.verify("Spark", against: xml))
    XCTAssertEqual(SheetProtection.permissions(in: xml), [.sort, .formatColumns])
  }

  /// Excel keeps Spark Grid's pivot tables as the values drawn; it drops the settings that make
  /// them editable, so they open as plain cells.
  func testPivotTablesOpenAsTheirValues() throws {
    let pivot = try sheet("Pivot 1")
    let shown = (2...6).map { row in
      (0...1).map { pivot.cell(at: CellAddress(row: row, col: $0)).raw }
    }
    XCTAssertEqual(
      shown,
      [
        ["Region", "Sum of Amount"], ["East", "225"], ["North", "95"], ["West", "185"],
        ["Grand Total", "505"],
      ])
    XCTAssertTrue(pivot.fileExtras.sparkPivots.isEmpty)
  }
}
