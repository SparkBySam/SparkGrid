import Engine
import Formula
import Foundation
import GridCore
import Model
import XCTest

@testable import FileFormats

/// Allow Edit Ranges (`<protectedRanges>`) and Spark Grid's range locks, in the file and through
/// row and column changes.
final class RangeProtectionFileTests: XCTestCase {
  private func range(_ a1: String) -> CellRange {
    XLSXCodec.parseCellRange(a1)!
  }

  private func sheetXML(_ data: Data) throws -> String {
    try XCTUnwrap(
      XLSXCodec.zipEntryString(archiveData: data, entryPath: "xl/worksheets/sheet1.xml"))
  }

  func testEditableRangesSaveAndOpenAsOtherAppsWriteThem() throws {
    var sheet = Sheet(name: "Inputs")
    sheet.setCell(Cell(raw: "x"), at: .origin)
    sheet.fileExtras.protectionXML = SheetProtection.element(password: "sheet")
    sheet.fileExtras.editableRanges = [
      EditableRange(name: "Inputs", ranges: [range("B2:C9")]),
      EditableRange(
        name: "Rates", ranges: [range("E2:E5"), range("G2")],
        passwordAttributes: #"password="\#(SheetProtection.legacyHash("rate"))""#),
    ]
    let data = try XLSXCodec.exportWorkbook(Workbook(sheets: [sheet]))
    let xml = try sheetXML(data)
    // After sheetProtection, as the file format orders them.
    let protection = try XCTUnwrap(xml.range(of: "<sheetProtection"))
    let ranges = try XCTUnwrap(xml.range(of: "<protectedRanges>"))
    XCTAssertLessThan(protection.lowerBound, ranges.lowerBound)
    XCTAssertTrue(xml.contains(#"<protectedRange name="Inputs" sqref="B2:C9"/>"#), xml)
    XCTAssertTrue(xml.contains(#"name="Rates" sqref="E2:E5 G2" password=""#), xml)
    let back = try XLSXCodec.importWorkbook(from: data).activeSheet.fileExtras.editableRanges
    XCTAssertEqual(back, sheet.fileExtras.editableRanges)
    XCTAssertTrue(SheetProtection.verify("rate", against: back[1].xml))
    XCTAssertFalse(SheetProtection.verify("Rate", against: back[1].xml))
  }

  /// A file whose range has a newer, salted password keeps it as written.
  func testSaltedPasswordIsKeptAsWritten() throws {
    let xml =
      #"<protectedRanges><protectedRange algorithmName="SHA-512" hashValue="abc=" saltValue="c2FsdA==" spinCount="100000" sqref="A1:A3" name="Salted"/></protectedRanges>"#
    let ranges = XLSXCodec.editableRanges(in: xml)
    XCTAssertEqual(ranges.count, 1)
    XCTAssertEqual(ranges[0].name, "Salted")
    XCTAssertTrue(ranges[0].hasPassword)
    for part in [#"algorithmName="SHA-512""#, #"hashValue="abc=""#, #"spinCount="100000""#] {
      XCTAssertTrue(ranges[0].xml.contains(part), ranges[0].xml)
    }
  }

  func testRangeLocksSaveInSparkGridsOwnPart() throws {
    var sheet = Sheet(name: "Totals")
    sheet.setCell(Cell(raw: "x"), at: .origin)
    let lock = RangeLock(name: "Totals", ranges: [range("A10:D12")], passwordHash: "CBEB")
    sheet.fileExtras.rangeLocks = [lock]
    let data = try XLSXCodec.exportWorkbook(Workbook(sheets: [sheet]))
    XCTAssertNotNil(
      XLSXCodec.zipEntryData(archiveData: data, entryPath: "xl/sparkGrid/locks1.json"))
    // Other apps see no protection from a range lock.
    XCTAssertFalse(try sheetXML(data).contains("sheetProtection"))
    let back = try XLSXCodec.importWorkbook(from: data).activeSheet.fileExtras.rangeLocks
    XCTAssertEqual(back, [lock])
  }

  func testRangesMoveWithRowsAndColumns() {
    var sheet = Sheet(name: "S")
    sheet.fileExtras.editableRanges = [EditableRange(name: "E", ranges: [range("B5:B8")])]
    sheet.fileExtras.rangeLocks = [RangeLock(name: "L", ranges: [range("C10:D10")])]
    SheetStructureMutation.insertRows(into: &sheet, at: 0, count: 2)
    XCTAssertEqual(sheet.fileExtras.editableRanges.first?.ranges.map(\.a1Label), ["B7:B10"])
    XCTAssertEqual(sheet.fileExtras.rangeLocks.first?.ranges.map(\.a1Label), ["C12:D12"])
    SheetStructureMutation.deleteColumns(in: &sheet, at: 0, count: 1)
    XCTAssertEqual(sheet.fileExtras.editableRanges.first?.ranges.map(\.a1Label), ["A7:A10"])
    XCTAssertEqual(sheet.fileExtras.rangeLocks.first?.ranges.map(\.a1Label), ["B12:C12"])
    // Every cell of the range deleted: the range goes.
    SheetStructureMutation.deleteColumns(in: &sheet, at: 0, count: 1)
    XCTAssertTrue(sheet.fileExtras.editableRanges.isEmpty)
  }
}
