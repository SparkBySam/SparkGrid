import Foundation
import GridCore
import Model
import XCTest

@testable import FileFormats

/// Spark Grid notes what it saved in its own parts as a custom document property, which other
/// apps keep when they save; on open, extras the note names but the file no longer has are listed.
final class SparkGridNoteTests: XCTestCase {
  private func lockedWorkbook() -> Workbook {
    var sheet = Sheet(name: "Totals")
    sheet.setCell(Cell(raw: "x"), at: .origin)
    sheet.fileExtras.rangeLocks = [
      RangeLock(name: "Totals", ranges: [XLSXCodec.parseCellRange("A1:B2")!])
    ]
    return Workbook(sheets: [sheet])
  }

  private func parts(_ data: Data) throws -> [String: Data] {
    let package = try ZipPackage(archiveData: data)
    var files: [String: Data] = [:]
    for path in package.entryPaths { files[path] = package.data(for: path) }
    return files
  }

  func testNoteIsWrittenAndLinked() throws {
    let data = try XLSXCodec.exportWorkbook(lockedWorkbook())
    let files = try parts(data)
    let custom = String(decoding: try XCTUnwrap(files["docProps/custom.xml"]), as: UTF8.self)
    XCTAssertTrue(custom.contains(#"name="SparkGridExtras""#), custom)
    XCTAssertTrue(custom.contains("<vt:lpwstr>locks=1</vt:lpwstr>"), custom)
    let rels = String(decoding: try XCTUnwrap(files["_rels/.rels"]), as: UTF8.self)
    XCTAssertTrue(rels.contains("docProps/custom.xml"))
    let types = String(decoding: try XCTUnwrap(files["[Content_Types].xml"]), as: UTF8.self)
    XCTAssertTrue(types.contains("/docProps/custom.xml"))
    // Opened again as saved: nothing is missing.
    XCTAssertEqual(try XLSXCodec.importWorkbook(from: data).removedSparkGridExtras, [])
  }

  func testNoNoteWithoutExtras() throws {
    var sheet = Sheet(name: "Plain")
    sheet.setCell(Cell(raw: "1"), at: .origin)
    let files = try parts(try XLSXCodec.exportWorkbook(Workbook(sheets: [sheet])))
    XCTAssertNil(files["docProps/custom.xml"])
    XCTAssertFalse(String(decoding: files["_rels/.rels"]!, as: UTF8.self).contains("custom"))
  }

  func testAnotherAppDroppingSparkGridPartsIsNoticed() throws {
    var files = try parts(try XLSXCodec.exportWorkbook(lockedWorkbook()))
    // What another app's save does: parts it does not know are gone, the property stays.
    for path in files.keys where path.hasPrefix("xl/sparkGrid/") { files[path] = nil }
    let resaved = try XCTUnwrap(XLSXCodec.zipArchive(files: files))
    let reopened = try XLSXCodec.importWorkbook(from: resaved)
    XCTAssertEqual(reopened.removedSparkGridExtras, [.locks])
    XCTAssertTrue(reopened.sheets[0].fileExtras.rangeLocks.isEmpty)
    // Saving again writes a note of what the workbook holds now, so the warning shows once.
    let again = try XLSXCodec.importWorkbook(from: XLSXCodec.exportWorkbook(reopened))
    XCTAssertEqual(again.removedSparkGridExtras, [])
  }

  /// A file Spark Grid saved with a range lock, then saved by Excel 16.115: Excel kept the note
  /// and dropped `xl/sparkGrid/`, lock and all (saved path and author name replaced).
  func testExcelsSaveIsNoticed() throws {
    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("Fixtures/excel-dropped-extras.xlsx")
    let data = try Data(contentsOf: url)
    XCTAssertFalse(try parts(data).keys.contains { $0.hasPrefix("xl/sparkGrid/") })
    let book = try XLSXCodec.importWorkbook(from: data)
    XCTAssertEqual(book.removedSparkGridExtras, [.locks])
    XCTAssertEqual(book.sheets[0].cell(at: CellAddress(row: 0, col: 2)).raw, "edited in Excel")
  }

  func testTheFilesOwnPropertiesAreKept() throws {
    var workbook = lockedWorkbook()
    workbook.xlsxCustomPropertiesData = Data(
      #"<?xml version="1.0"?><Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/custom-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes"><property fmtid="{D5CDD505-2E9C-101B-9397-08002B2CF9AE}" pid="2" name="Client"><vt:lpwstr>North</vt:lpwstr></property><property fmtid="{D5CDD505-2E9C-101B-9397-08002B2CF9AE}" pid="3" name="SparkGridExtras"><vt:lpwstr>pivots=4</vt:lpwstr></property></Properties>"#
        .utf8)
    let custom = String(
      decoding: try XCTUnwrap(try parts(XLSXCodec.exportWorkbook(workbook))["docProps/custom.xml"]),
      as: UTF8.self)
    XCTAssertTrue(custom.contains(#"pid="2" name="Client"><vt:lpwstr>North"#), custom)
    // The old note is replaced by what this save holds.
    XCTAssertTrue(custom.contains(#"pid="3" name="SparkGridExtras"><vt:lpwstr>locks=1"#), custom)
    XCTAssertFalse(custom.contains("pivots=4"))
  }
}
