import GridCore
import Model
import XCTest

@testable import FileFormats

/// Clip has no standard alignment flag. Spark Grid saves it in its own namespace, marked
/// mc:Ignorable so other apps skip it, and still reads the bare attribute older builds wrote.
final class ClipMarkerTests: XCTestCase {
  private func clipWorkbook() -> Workbook {
    var sheet = Sheet(name: "Sheet1")
    var cell = Cell(raw: "clip me")
    var format = CellFormat()
    format.textDisplay = .clip
    cell.format = format
    sheet.setCell(cell, at: CellAddress(row: 0, col: 0))
    sheet.setCell(Cell(raw: "plain"), at: CellAddress(row: 1, col: 0))
    return Workbook(sheets: [sheet])
  }

  func testClipIsSavedInAnIgnorableNamespaceAndReadBack() throws {
    let data = try XLSXCodec.exportWorkbook(clipWorkbook())
    let styles = try XCTUnwrap(
      XLSXCodec.zipEntryString(archiveData: data, entryPath: "xl/styles.xml"))
    XCTAssertTrue(styles.contains(#"mc:Ignorable="sg""#))
    XCTAssertTrue(styles.contains(#"xmlns:sg="urn:sparkgrid:xlsx:2026""#))
    XCTAssertTrue(styles.contains(#"sg:textDisplay="clip""#))
    XCTAssertFalse(styles.contains("sparkTextDisplay"))
    let sheet = try XLSXCodec.importWorkbook(from: data).activeSheet
    XCTAssertEqual(sheet.cell(at: CellAddress(row: 0, col: 0)).format?.textDisplay, .clip)
    XCTAssertNotEqual(sheet.cell(at: CellAddress(row: 1, col: 0)).format?.textDisplay, .clip)
  }

  func testFilesWithoutClipKeepThePlainStyleSheet() throws {
    var sheet = Sheet(name: "Sheet1")
    sheet.setCell(Cell(raw: "plain"), at: CellAddress(row: 0, col: 0))
    let data = try XLSXCodec.exportWorkbook(Workbook(sheets: [sheet]))
    let styles = try XCTUnwrap(
      XLSXCodec.zipEntryString(archiveData: data, entryPath: "xl/styles.xml"))
    XCTAssertFalse(styles.contains("mc:Ignorable"))
  }

  func testFilesSavedByOlderBuildsStillOpenClipped() throws {
    let data = try XLSXCodec.exportWorkbook(clipWorkbook())
    var styles = try XCTUnwrap(
      XLSXCodec.zipEntryString(archiveData: data, entryPath: "xl/styles.xml"))
    styles = styles.replacingOccurrences(
      of: #"sg:textDisplay="clip""#, with: #"sparkTextDisplay="clip""#)
    styles = styles.replacingOccurrences(
      of: #" xmlns:mc="[^"]*" xmlns:sg="[^"]*" mc:Ignorable="sg""#, with: "",
      options: .regularExpression)
    XCTAssertFalse(styles.contains("mc:Ignorable"))
    let legacy = try XCTUnwrap(
      XLSXCodec.replacingZipEntry(
        archiveData: data, entryPath: "xl/styles.xml", with: Data(styles.utf8)))
    let sheet = try XLSXCodec.importWorkbook(from: legacy).activeSheet
    XCTAssertEqual(sheet.cell(at: CellAddress(row: 0, col: 0)).format?.textDisplay, .clip)
  }
}
