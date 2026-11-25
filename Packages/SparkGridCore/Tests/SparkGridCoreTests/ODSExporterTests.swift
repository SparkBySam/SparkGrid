import GridCore
import Model
import NumberFormat
import XCTest

@testable import FileFormats

/// Saving as .ods: formulas in OpenFormula, and a workbook that opens again with the same
/// sheets, values, formulas, formats and merged cells.
final class ODSExporterTests: XCTestCase {
  func testOpenFormula() {
    let cases: [(String, String)] = [
      ("=SUM(A1:B2,Sheet2!C3)", "of:=SUM([.A1:.B2];[$Sheet2.C3])"),
      ("='My Sheet'!$A$1*2", "of:=[$'My Sheet'.$A$1]*2"),
      ("=-2^2", "of:=-2^2"),
      ("=-(2^2)", "of:=-(2^2)"),
      ("=(1+2)*3", "of:=(1+2)*3"),
      ("=1-(2-3)", "of:=1-(2-3)"),
      ("=1-2-3", "of:=1-2-3"),
      ("=IF(A1>1,\"a,b \"\"c\"\"\",TRUE)", "of:=IF([.A1]>1;\"a,b \"\"c\"\"\";TRUE())"),
      ("=XLOOKUP(A1,B:B,C:C)", "of:=COM.MICROSOFT.XLOOKUP([.A1];[.B1:.B1048576];[.C1:.C1048576])"),
      ("=A1&\"%\"&10%", "of:=[.A1]&\"%\"&10%"),
      ("={1,2;3,4}", "of:={1;2|3;4}"),
      ("=IF(A1,,2)", "of:=IF([.A1];;2)"),
    ]
    for (raw, expected) in cases {
      XCTAssertEqual(ODSExporter.openFormula(raw), expected, raw)
    }
  }

  /// Every OpenFormula the exporter writes reads back as the formula it came from.
  func testFormulasReadBack() throws {
    for raw in [
      "=SUM(A1:B2,'Other Sheet'!C3)", "=IF(A1>1,\"a;b\",FALSE)", "=-2^2", "=(1+2)*3",
      "=VLOOKUP(A1,$B$2:$C$9,2,FALSE)",
    ] {
      let open = try XCTUnwrap(ODSExporter.openFormula(raw))
      XCTAssertEqual(
        ODSImporter.formula(fromOpenFormula: open),
        raw.replacingOccurrences(of: "FALSE", with: "FALSE()"), raw)
    }
  }

  func testWorkbookRoundTrip() throws {
    var sales = Sheet(name: "Sales & Co")
    sales.setCell(Cell(raw: "Region"), at: CellAddress(row: 0, col: 0))
    sales.setCell(Cell(raw: "Amount"), at: CellAddress(row: 0, col: 1))
    sales.setCell(Cell(raw: "East"), at: CellAddress(row: 1, col: 0))
    sales.setCell(Cell(raw: "1250.5"), at: CellAddress(row: 1, col: 1))
    var zip = Cell(raw: "02134")
    zip.markTextIfNeeded()
    sales.setCell(zip, at: CellAddress(row: 2, col: 0))
    sales.setCell(
      Cell(raw: "0.25", format: CellFormat(numberFormat: .percent)), at: CellAddress(row: 2, col: 1)
    )
    sales.setCell(
      Cell(raw: "46346", format: CellFormat(numberFormat: .date)), at: CellAddress(row: 3, col: 1))
    sales.setCell(Cell(raw: "TRUE"), at: CellAddress(row: 4, col: 1))
    var bold = CellFormat()
    bold.bold = true
    sales.setCell(
      Cell(
        raw: "=SUM(B2:B3)", format: bold, importedFormulaResult: "1250.75",
        importedFormulaValueType: .number),
      at: CellAddress(row: 9, col: 1))
    sales.setCell(Cell(raw: "Merged"), at: CellAddress(row: 6, col: 0))
    sales.mergedRanges = [
      CellRange(start: CellAddress(row: 6, col: 0), end: CellAddress(row: 7, col: 2))
    ]
    sales.columnWidths[0] = 140
    var other = Sheet(name: "Other")
    other.setCell(Cell(raw: "='Sales & Co'!B2*2"), at: .origin)

    let data = try ODSExporter.exportWorkbook(Workbook(sheets: [sales, other]))
    // The mimetype comes first and uncompressed, so the file is known by it.
    XCTAssertEqual(
      String(data: data.subdata(in: 30..<38), encoding: .ascii), "mimetype")
    if let out = ProcessInfo.processInfo.environment["SPARK_GRID_ODS_OUT"] {
      try data.write(to: URL(fileURLWithPath: out))
    }

    let book = try ODSImporter.importWorkbook(fromArchiveData: data)
    XCTAssertEqual(book.sheets.map(\.name), ["Sales & Co", "Other"])
    let back = book.sheets[0]
    XCTAssertEqual(back.cell(at: CellAddress(row: 1, col: 1)).raw, "1250.5")
    XCTAssertEqual(back.cell(at: CellAddress(row: 2, col: 0)).raw, "02134")
    XCTAssertEqual(back.cell(at: CellAddress(row: 2, col: 0)).isText, true)
    XCTAssertEqual(back.cell(at: CellAddress(row: 2, col: 1)).format?.numberFormat, .percent)
    XCTAssertEqual(back.cell(at: CellAddress(row: 3, col: 1)).raw, "46346")
    XCTAssertEqual(back.cell(at: CellAddress(row: 3, col: 1)).format?.numberFormat, .date)
    XCTAssertEqual(back.cell(at: CellAddress(row: 4, col: 1)).raw, "TRUE")
    let sum = back.cell(at: CellAddress(row: 9, col: 1))
    XCTAssertEqual(sum.raw, "=SUM(B2:B3)")
    XCTAssertEqual(sum.importedFormulaResult, "1250.75")
    XCTAssertEqual(back.cell(at: CellAddress(row: 6, col: 0)).raw, "Merged")
    XCTAssertEqual(back.mergedRanges, sales.mergedRanges)
    XCTAssertEqual(book.sheets[1].cell(at: .origin).raw, "='Sales & Co'!B2*2")
  }
}
