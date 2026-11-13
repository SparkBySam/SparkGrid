import Foundation
import GridCore
import Model
import XCTest

@testable import FileFormats

/// Spark Grid's pivot tables are saved as real pivot tables, so other apps refresh them and
/// their GETPIVOTDATA formulas find them (checked in Excel 16.115, Nov 13 2026).
final class ExcelPivotWriterTests: XCTestCase {
  private func salesSheet() -> Sheet {
    var sheet = Sheet(name: "Sales")
    let rows: [[String]] = [
      ["Region", "Rep", "Date", "Amount", "Units"],
      ["West", "Ann", "46023", "100", "3"], ["East", "Bo", "46030", "40", "1"],
      ["West", "Cy", "46113", "30", "2"], ["East", "Di", "45658", "120", "5"],
      ["North", "Ed", "46200", "75", "2"], ["West", "Ann", "46210", "55", "1"],
      ["North", "Fay", "45700", "20", "4"], ["East", "Bo", "46100", "65", "2"],
    ]
    for (r, row) in rows.enumerated() {
      for (c, value) in row.enumerated() {
        sheet.setCell(Cell(raw: value), at: CellAddress(row: r, col: c))
      }
    }
    return sheet
  }

  private func workbook(_ definitions: [PivotDefinition], linked: String? = nil) -> Workbook {
    var pivots = Sheet(name: "Pivots")
    pivots.fileExtras.sparkPivots = definitions.enumerated().map { index, definition in
      SheetPivot(
        name: "PivotTable\(index + 1)", sourceSheet: "Sales",
        sourceRange: CellRange(start: .origin, end: CellAddress(row: 8, col: 4)),
        anchor: CellAddress(row: 2, col: index * 10), definition: definition, drawnRows: 5,
        drawnColumns: 2, fieldNames: ["Region", "Rep", "Date", "Amount", "Units"],
        linkedFilePivot: linked)
    }
    return Workbook(sheets: [salesSheet(), pivots])
  }

  private let byRegion = PivotDefinition(rows: [0], values: [.init(field: 3, aggregate: .sum)])
  private let filtered = PivotDefinition(
    rows: [1], values: [.init(field: 3, aggregate: .average)],
    filters: [.init(field: 0, hidden: ["North"])])
  private let twoValues = PivotDefinition(
    rows: [0], columns: [1],
    values: [.init(field: 3, aggregate: .sum), .init(field: 4, aggregate: .count)])

  func testSavedPivotsReadBackAsTheSameTables() throws {
    let book = workbook([byRegion, filtered, twoValues])
    let data = try XLSXCodec.exportWorkbook(book)
    let names = try XCTUnwrap(XLSXCodec.zipEntryNames(archiveData: data))
    XCTAssertEqual(names.filter { $0.hasPrefix("xl/pivotTables/pivotTable") }.count, 3, "\(names)")
    XCTAssertEqual(names.filter { $0.hasPrefix("xl/pivotCache/pivotCacheDefinition") }.count, 3)
    for (index, definition) in [byRegion, filtered, twoValues].enumerated() {
      let table = try XCTUnwrap(
        XLSXCodec.zipEntryData(
          archiveData: data, entryPath: "xl/pivotTables/pivotTable\(index + 1).xml"))
      let cache = try XCTUnwrap(
        XLSXCodec.zipEntryData(
          archiveData: data, entryPath: "xl/pivotCache/pivotCacheDefinition\(index + 1).xml"))
      XCTAssertTrue(ExcelPivotReader.refreshesOnLoad(cache))
      let read = try ExcelPivotReader.read(
        pivotXML: table, cacheDefinitionXML: cache, workbook: book
      )
      .get()
      XCTAssertEqual(read.name, "PivotTable\(index + 1)")
      XCTAssertEqual(read.sourceSheet, "Sales")
      XCTAssertEqual(read.sourceRange.a1Label, "A1:E9")
      XCTAssertEqual(read.definition.rows, definition.rows)
      XCTAssertEqual(read.definition.columns, definition.columns)
      XCTAssertEqual(read.definition.values, definition.values)
      XCTAssertEqual(read.definition.filters, definition.filters)
    }
  }

  /// Opened again in Spark Grid, the pivot is Spark Grid's; the parts written for other apps are
  /// written again on the next save, not kept beside it.
  func testOwnFileReopensWithoutDuplicateTables() throws {
    let first = try XLSXCodec.exportWorkbook(workbook([byRegion, filtered]))
    let reopened = try XLSXCodec.importWorkbook(from: first)
    let pivots = try XCTUnwrap(reopened.sheets.first { $0.name == "Pivots" })
    XCTAssertEqual(pivots.fileExtras.sparkPivots.count, 2)
    XCTAssertTrue(pivots.fileExtras.pivotTables.isEmpty)
    XCTAssertTrue(reopened.pivotCaches.isEmpty)
    let second = try XLSXCodec.exportWorkbook(reopened)
    let names = try XCTUnwrap(XLSXCodec.zipEntryNames(archiveData: second))
    XCTAssertEqual(names.filter { $0.hasPrefix("xl/pivotTables/pivotTable") }.count, 2, "\(names)")
  }

  /// Dates grouped by quarter or month stay values for now, and a pivot that redraws a table
  /// from the file keeps that file's table instead of a second one.
  func testDateGroupedAndLinkedPivotsAreNotWrittenAgain() throws {
    let grouped = PivotDefinition(
      rows: [2], values: [.init(field: 3, aggregate: .sum)], dateGroups: [2: .quarter])
    for book in [workbook([grouped]), workbook([byRegion], linked: "PivotTable1")] {
      let data = try XLSXCodec.exportWorkbook(book)
      let names = try XCTUnwrap(XLSXCodec.zipEntryNames(archiveData: data))
      XCTAssertFalse(names.contains { $0.hasPrefix("xl/pivotTables/") }, "\(names)")
    }
  }

  /// `Fixtures/excel-pivots.xlsx`: Spark Grid's pivots, opened, refreshed and saved by Excel
  /// 16.115 (saved path and names replaced). Excel keeps them as its own pivot tables and drops
  /// Spark Grid's settings, so they open as that app's tables.
  func testExcelsSaveOpensAsExcelPivotTables() throws {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let data = try Data(contentsOf: root.appendingPathComponent("Fixtures/excel-pivots.xlsx"))
    let book = try XLSXCodec.importWorkbook(from: data)
    let expected: [String: PivotDefinition] = [
      "Pivot 1": byRegion,
      "Pivot 2": PivotDefinition(
        rows: [0], columns: [1], values: [.init(field: 3, aggregate: .sum)]),
      "Pivot 3": filtered,
      "Pivot 4": PivotDefinition(
        rows: [0], values: [.init(field: 3, aggregate: .sum), .init(field: 4, aggregate: .count)]),
    ]
    for (name, definition) in expected {
      let sheet = try XCTUnwrap(book.sheets.first { $0.name == name }, name)
      XCTAssertTrue(sheet.fileExtras.sparkPivots.isEmpty, name)
      let part = try XCTUnwrap(sheet.fileExtras.pivotTables.first, name)
      let cache = try XCTUnwrap(book.pivotCaches.first { $0.cacheID == part.cacheID }, name)
      let read = try ExcelPivotReader.read(
        pivotXML: part.xml, cacheDefinitionXML: cache.definitionXML, workbook: book
      ).get()
      XCTAssertEqual(read.definition.rows, definition.rows, name)
      XCTAssertEqual(read.definition.columns, definition.columns, name)
      XCTAssertEqual(read.definition.values, definition.values, name)
      XCTAssertEqual(read.definition.filters, definition.filters, name)
    }
    // The date-grouped pivot was never written as a pivot table: it is the drawn values.
    let grouped = try XCTUnwrap(book.sheets.first { $0.name == "Pivot 5" })
    XCTAssertTrue(grouped.fileExtras.pivotTables.isEmpty)
    XCTAssertEqual(grouped.cell(at: CellAddress(row: 3, col: 0)).raw, "Q1 2025")
  }
}
