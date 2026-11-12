import Calc
import Engine
import GridCore
import Model
import XCTest

@testable import FileFormats

/// Spilled results save as other spreadsheet apps save them, and open back as spilled results.
final class SpillFileTests: XCTestCase {
  private func spilledWorkbook() -> Workbook {
    var sheet = Sheet(name: "Data")
    for (row, name) in ["Cy", "Ann", "Bo"].enumerated() {
      sheet.setCell(Cell(raw: name), at: CellAddress(row: row, col: 0))
    }
    let anchor = CellAddress(row: 0, col: 2)
    sheet.setCell(Cell(raw: "=SORT(A1:A3)"), at: anchor)
    var anchorCell = sheet.cell(at: anchor)
    anchorCell.importedFormulaResult = "Ann"
    anchorCell.importedFormulaValueType = .string
    sheet.setCell(anchorCell, at: anchor)
    let unique = CellAddress(row: 0, col: 3)
    sheet.setCell(Cell(raw: "=UNIQUE(A1:A3)"), at: unique)
    let result = ArrayResult(
      rows: 3, cols: 1, values: [.string("Ann"), .string("Bo"), .string("Cy")])
    let numbers = ArrayResult(rows: 3, cols: 1, values: [.number(1), .number(2), .number(3)])
    SpillLayout.apply([anchor: result, unique: numbers], to: &sheet)
    return Workbook(sheets: [sheet])
  }

  func testSavesSpillingFormulas() throws {
    let data = try XLSXCodec.exportWorkbook(spilledWorkbook())
    let xml = try XCTUnwrap(
      XLSXCodec.zipEntryString(archiveData: data, entryPath: "xl/worksheets/sheet1.xml"))
    XCTAssertTrue(xml.contains(#"cm="1"><f t="array" ref="C1:C3">_xlfn._xlws.SORT(A1:A3)</f>"#))
    XCTAssertTrue(xml.contains(#"<f t="array" ref="D1:D3">_xlfn.UNIQUE(A1:A3)</f>"#))
    XCTAssertTrue(xml.contains(#"<c r="C2" t="inlineStr"><is><t xml:space="preserve">Bo</t>"#))
    XCTAssertTrue(xml.contains(#"<c r="D3"><v>3</v></c>"#))
    XCTAssertNotNil(XLSXCodec.zipEntryString(archiveData: data, entryPath: "xl/metadata.xml"))
    let types = try XCTUnwrap(
      XLSXCodec.zipEntryString(archiveData: data, entryPath: "[Content_Types].xml"))
    XCTAssertTrue(types.contains("/xl/metadata.xml"))
    let rels = try XCTUnwrap(
      XLSXCodec.zipEntryString(archiveData: data, entryPath: "xl/_rels/workbook.xml.rels"))
    XCTAssertTrue(rels.contains("relationships/sheetMetadata"))
  }

  func testOpensSpilledResults() throws {
    let data = try XLSXCodec.exportWorkbook(spilledWorkbook())
    let sheet = try XLSXCodec.importWorkbook(from: data).activeSheet
    let anchor = CellAddress(row: 0, col: 2)
    XCTAssertEqual(sheet.fileExtras.spills[anchor]?.a1Label, "C1:C3")
    let member = sheet.cell(at: CellAddress(row: 1, col: 2))
    XCTAssertTrue(member.isSpilled)
    XCTAssertEqual(member.literalValue, .string("Bo"))
    XCTAssertEqual(sheet.cell(at: CellAddress(row: 2, col: 3)).literalValue, .number(3))
    XCTAssertTrue(sheet.cell(at: anchor).raw.uppercased().contains("SORT(A1:A3)"))
  }

  func testWorkbookWithoutSpillsHasNoMetadataPart() throws {
    var sheet = Sheet(name: "S")
    sheet.setCell(Cell(raw: "=SUM(1,2)"), at: CellAddress(row: 0, col: 0))
    let data = try XLSXCodec.exportWorkbook(Workbook(sheets: [sheet]))
    XCTAssertNil(XLSXCodec.zipEntryString(archiveData: data, entryPath: "xl/metadata.xml"))
  }
}
