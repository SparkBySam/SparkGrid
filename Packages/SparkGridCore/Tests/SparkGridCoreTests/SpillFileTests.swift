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

  // MARK: - What Excel 16.115 accepted and rejected (checked by hand, Nov 12 2026)

  private func sheetXML(_ workbook: Workbook) throws -> String {
    let data = try XLSXCodec.exportWorkbook(workbook)
    return try XCTUnwrap(
      XLSXCodec.zipEntryString(archiveData: data, entryPath: "xl/worksheets/sheet1.xml"))
  }

  /// `<v>#SPILL!</v>` in an error cell made Excel report the file as damaged.
  func testBlockedSpillSavesAsAnArrayWithTextResult() throws {
    var sheet = Sheet(name: "Data")
    sheet.setCell(Cell(raw: "a"), at: CellAddress(row: 0, col: 0))
    sheet.setCell(Cell(raw: "b"), at: CellAddress(row: 1, col: 0))
    let anchor = CellAddress(row: 0, col: 2)
    var formula = Cell(raw: "=UNIQUE(A1:A2)")
    formula.importedFormulaResult = "#SPILL!"
    formula.importedFormulaValueType = .error
    sheet.setCell(formula, at: anchor)
    sheet.setCell(Cell(raw: "in the way"), at: CellAddress(row: 1, col: 2))
    sheet.fileExtras.blockedSpills.insert(anchor)
    let workbook = Workbook(sheets: [sheet])
    let xml = try sheetXML(workbook)
    XCTAssertTrue(
      xml.contains(
        #"<c r="C1" t="str" cm="1"><f t="array" ref="C1">_xlfn.UNIQUE(A1:A2)</f><v>#SPILL!</v>"#),
      xml)
    XCTAssertFalse(xml.contains(#"t="e""#))
    let data = try XLSXCodec.exportWorkbook(workbook)
    XCTAssertNotNil(XLSXCodec.zipEntryString(archiveData: data, entryPath: "xl/metadata.xml"))
    // Opened again, the one-cell array is not a spill.
    let reopened = try XLSXCodec.importWorkbook(from: data).activeSheet
    XCTAssertNil(reopened.fileExtras.spills[anchor])
    XCTAssertEqual(reopened.cell(at: CellAddress(row: 1, col: 2)).raw, "in the way")
  }

  func testNewerErrorResultsSaveAsText() throws {
    var sheet = Sheet(name: "S")
    var cell = Cell(raw: "=FILTER(A1:A2,A1:A2>5)")
    cell.importedFormulaResult = "#CALC!"
    cell.importedFormulaValueType = .error
    sheet.setCell(cell, at: CellAddress(row: 0, col: 1))
    var div = Cell(raw: "=1/0")
    div.importedFormulaResult = "#DIV/0!"
    div.importedFormulaValueType = .error
    sheet.setCell(div, at: CellAddress(row: 1, col: 1))
    let xml = try sheetXML(Workbook(sheets: [sheet]))
    XCTAssertTrue(xml.contains(#"<c r="B1" t="str" cm="1">"#), xml)
    XCTAssertTrue(xml.contains("<v>#CALC!</v>"))
    XCTAssertTrue(xml.contains(#"<c r="B2" t="e"><f>1/0</f><v>#DIV/0!</v>"#), xml)
  }

  /// A formula that can spill but fills one cell is saved as an array, as Excel saves it.
  func testOneCellSpillingFormulaSavesAsAnArray() throws {
    var sheet = Sheet(name: "S")
    sheet.setCell(Cell(raw: "=COUNTA(UNIQUE(A1:A3))"), at: CellAddress(row: 0, col: 1))
    sheet.setCell(Cell(raw: "=SUM(A1:A3)"), at: CellAddress(row: 1, col: 1))
    let xml = try sheetXML(Workbook(sheets: [sheet]))
    XCTAssertTrue(
      xml.contains(#"cm="1"><f t="array" ref="B1">COUNTA(_xlfn.UNIQUE(A1:A3))</f>"#), xml)
    XCTAssertTrue(xml.contains(#"<c r="B2"><f>SUM(A1:A3)</f>"#), xml)
  }

  /// `ROWS(G1#)` saved as typed made Excel report the file as damaged.
  func testSpillReferenceSavesAsAnchorArray() throws {
    XCTAssertEqual(ExcelFutureFunctions.anchorArrays("ROWS(G1#)"), "ROWS(_xlfn.ANCHORARRAY(G1))")
    XCTAssertEqual(
      ExcelFutureFunctions.anchorArrays("SUM($G$1#)+Data!B2#"),
      "SUM(_xlfn.ANCHORARRAY($G$1))+_xlfn.ANCHORARRAY(Data!B2)")
    XCTAssertEqual(
      ExcelFutureFunctions.anchorArrays("COUNT('My ''Q'' Data'!A10#)"),
      "COUNT(_xlfn.ANCHORARRAY('My ''Q'' Data'!A10))")
    XCTAssertEqual(ExcelFutureFunctions.anchorArrays(#""A1#"&B1"#), #""A1#"&B1"#)
    XCTAssertEqual(ExcelFutureFunctions.anchorArrays("IFERROR(A1,#N/A)"), "IFERROR(A1,#N/A)")
    XCTAssertEqual(ExcelFutureFunctions.anchorArrays("SUM(A1:B2)"), "SUM(A1:B2)")
    var sheet = Sheet(name: "S")
    sheet.setCell(Cell(raw: "=ROWS(G1#)"), at: CellAddress(row: 0, col: 0))
    let xml = try sheetXML(Workbook(sheets: [sheet]))
    XCTAssertTrue(xml.contains("<f>ROWS(_xlfn.ANCHORARRAY(G1))</f>"), xml)
  }
}
