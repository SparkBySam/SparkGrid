import FileFormats
import GridCore
import Model
import NumberFormat
import XCTest

final class XLSXExportTests: XCTestCase {
  func testParallelExportRoundTripsTextFormatsAndCaches() throws {
    let bold = CellFormat(bold: true, numberFormat: .number)
    let filled = CellFormat(
      fillColor: CodableColor(red: 51.0 / 255, green: 102.0 / 255, blue: 153.0 / 255, alpha: 1)
    )
    var data = Sheet(name: "Data")
    data.setCell(Cell(raw: "North"), at: CellAddress(row: 0, col: 0))
    data.setCell(Cell(raw: "12"), at: CellAddress(row: 0, col: 1))
    data.setCell(
      Cell(
        raw: "=\"a<b\"",
        importedFormulaResult: "a<b",
        importedFormulaValueType: .string
      ),
      at: CellAddress(row: 0, col: 2)
    )
    data.setCell(Cell(raw: "", format: filled), at: CellAddress(row: 0, col: 3))
    data.setCell(Cell(raw: "North", format: bold), at: CellAddress(row: 0, col: 25))
    data.setCell(Cell(raw: "South"), at: CellAddress(row: 0, col: 26))
    data.rowHeights[2] = 30

    var other = Sheet(name: "Other")
    other.setCell(Cell(raw: "North", format: bold), at: CellAddress(row: 4, col: 0))
    other.setCell(
      Cell(
        raw: "=1+2",
        format: bold,
        importedFormulaResult: "3",
        importedFormulaValueType: .number
      ),
      at: CellAddress(row: 4, col: 1)
    )

    let workbook = Workbook(sheets: [data, other])
    let first = try XLSXCodec.exportWorkbook(workbook, includeFormulaCaches: true)
    let second = try XLSXCodec.exportWorkbook(workbook, includeFormulaCaches: true)
    XCTAssertEqual(first, second)

    let shared = XLSXCodec.zipEntryString(archiveData: first, entryPath: "xl/sharedStrings.xml")
    XCTAssertTrue(shared?.contains("uniqueCount=\"2\"") == true)

    let imported = try XLSXCodec.importWorkbook(from: first)
    let dataSheet = imported.sheets[0]
    XCTAssertEqual(dataSheet.cell(at: CellAddress(row: 0, col: 0)).raw, "North")
    XCTAssertEqual(dataSheet.cell(at: CellAddress(row: 0, col: 1)).raw, "12")
    XCTAssertEqual(dataSheet.cell(at: CellAddress(row: 0, col: 2)).raw, "=\"a<b\"")
    XCTAssertEqual(dataSheet.cell(at: CellAddress(row: 0, col: 2)).importedFormulaResult, "a<b")
    XCTAssertEqual(
      dataSheet.cell(at: CellAddress(row: 0, col: 3)).format?.fillColor, filled.fillColor)
    XCTAssertEqual(dataSheet.cell(at: CellAddress(row: 0, col: 25)).raw, "North")
    XCTAssertEqual(dataSheet.cell(at: CellAddress(row: 0, col: 25)).format?.bold, true)
    XCTAssertEqual(dataSheet.cell(at: CellAddress(row: 0, col: 26)).raw, "South")
    XCTAssertEqual(dataSheet.rowHeights[2], 30)

    let otherSheet = imported.sheets[1]
    XCTAssertEqual(otherSheet.cell(at: CellAddress(row: 4, col: 0)).raw, "North")
    XCTAssertEqual(otherSheet.cell(at: CellAddress(row: 4, col: 0)).format?.bold, true)
    XCTAssertEqual(otherSheet.cell(at: CellAddress(row: 4, col: 1)).raw, "=1+2")
    XCTAssertEqual(otherSheet.cell(at: CellAddress(row: 4, col: 1)).importedFormulaResult, "3")
    XCTAssertEqual(otherSheet.cell(at: CellAddress(row: 4, col: 1)).format?.numberFormat, .number)
  }

  /// A conditional format writes a `<dxf>` without `numFmtId`, which CoreXLSX rejected. That
  /// failed the whole style parse, and every cell in a saved file reopened unformatted.
  func testCellFormatsSurviveAConditionalFormat() throws {
    let a1 = CellAddress(row: 0, col: 0)
    let b1 = CellAddress(row: 0, col: 1)
    var sheet = Sheet(name: "Data")
    sheet.setCell(Cell(raw: "Total", format: CellFormat(bold: true)), at: a1)
    sheet.setCell(Cell(raw: "5", format: CellFormat(numberFormat: .currency)), at: b1)
    sheet.conditionalFormats = [
      ConditionalFormatRule(
        range: CellRange(start: b1, end: b1), predicate: .greaterThan(1), style: .redFill)
    ]
    let data = try XLSXCodec.exportWorkbook(Workbook(sheets: [sheet]))
    let reopened = try XLSXCodec.importWorkbook(from: data).sheets[0]
    XCTAssertEqual(reopened.cell(at: a1).format?.bold, true)
    XCTAssertEqual(reopened.cell(at: b1).format?.numberFormat, .currency)
    XCTAssertEqual(reopened.conditionalFormats.count, 1)
  }

  /// Tabs reopen in the order they were saved, and a formula still finds its sheet by name.
  func testMovedSheetOrderRoundTrips() throws {
    let a1 = CellAddress(row: 0, col: 0)
    var data = Sheet(name: "Data")
    data.setCell(Cell(raw: "7"), at: a1)
    var summary = Sheet(name: "Summary")
    summary.setCell(Cell(raw: "=Data!A1*2"), at: a1)
    let notes = Sheet(name: "Notes")
    // Summary was dragged in front of Data.
    let saved = try XLSXCodec.exportWorkbook(Workbook(sheets: [summary, notes, data]))
    let reopened = try XLSXCodec.importWorkbook(from: saved)
    XCTAssertEqual(reopened.sheets.map(\.name), ["Summary", "Notes", "Data"])
    XCTAssertEqual(reopened.sheets[0].cell(at: a1).raw, "=Data!A1*2")
  }

  func testDeflateShrinksRepeatedText() throws {
    var sheet = Sheet(name: "Data")
    for row in 0..<2_000 {
      sheet.setCell(Cell(raw: "Repeated label"), at: CellAddress(row: row, col: 0))
      sheet.setCell(Cell(raw: "12"), at: CellAddress(row: row, col: 1))
    }
    let data = try XLSXCodec.exportWorkbook(Workbook(sheets: [sheet]))
    XCTAssertLessThan(data.count, 80_000)
    let imported = try XLSXCodec.importWorkbook(from: data)
    XCTAssertEqual(
      imported.sheets[0].cell(at: CellAddress(row: 1_999, col: 0)).raw, "Repeated label")
    XCTAssertEqual(imported.sheets[0].cell(at: CellAddress(row: 0, col: 1)).raw, "12")
  }
}
