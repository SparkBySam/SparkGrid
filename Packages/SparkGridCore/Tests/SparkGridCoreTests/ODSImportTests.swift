import Foundation
import GridCore
import Model
import NumberFormat
import XCTest

@testable import FileFormats

/// OpenDocument spreadsheets (.ods) open with their sheets, values, formulas and merges.
final class ODSImportTests: XCTestCase {
  private let content = """
    <?xml version="1.0" encoding="UTF-8"?>
    <office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" \
    xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" \
    xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" office:version="1.3">
    <office:body><office:spreadsheet>
    <table:table table:name="Sales">
      <table:table-column table:number-columns-repeated="4"/>
      <table:table-row>
        <table:table-cell office:value-type="string"><text:p>Item</text:p></table:table-cell>
        <table:table-cell office:value-type="string"><text:p>Qty</text:p></table:table-cell>
        <table:table-cell office:value-type="string"><text:p>When</text:p></table:table-cell>
        <table:table-cell office:value-type="string"><text:p>Code</text:p></table:table-cell>
      </table:table-row>
      <table:table-row>
        <table:table-cell office:value-type="string"><text:p>Pens <text:s text:c="2"/>blue</text:p></table:table-cell>
        <table:table-cell office:value-type="float" office:value="3.5"><text:p>3.5</text:p></table:table-cell>
        <table:table-cell office:value-type="date" office:date-value="2026-11-19T12:00:00"><text:p>19/11/26</text:p></table:table-cell>
        <table:table-cell office:value-type="string"><text:p>007</text:p></table:table-cell>
      </table:table-row>
      <table:table-row table:number-rows-repeated="2">
        <table:table-cell office:value-type="float" office:value="2"><text:p>2</text:p></table:table-cell>
        <table:table-cell table:number-columns-repeated="3"/>
      </table:table-row>
      <table:table-row>
        <table:table-cell table:formula="of:=SUM([.B2:.B4];[Totals.A1])" office:value-type="float" office:value="10.5"><text:p>10.5</text:p></table:table-cell>
        <table:table-cell office:value-type="percentage" office:value="0.25"><text:p>25%</text:p></table:table-cell>
        <table:table-cell office:value-type="time" office:time-value="PT18H00M00S"><text:p>18:00</text:p></table:table-cell>
        <table:table-cell office:value-type="boolean" office:boolean-value="true"><text:p>TRUE</text:p></table:table-cell>
      </table:table-row>
      <table:table-row>
        <table:table-cell table:number-columns-spanned="2" table:number-rows-spanned="1" office:value-type="string"><text:p>Merged</text:p></table:table-cell>
        <table:covered-table-cell/>
        <table:table-cell table:formula="of:=IF([$'My Data'.$A$1]&gt;1;&quot;a;b&quot;;[.A1])" office:value-type="string" office:string-value="a;b"><text:p>a;b</text:p></table:table-cell>
      </table:table-row>
      <table:table-row table:number-rows-repeated="1048570"><table:table-cell table:number-columns-repeated="1024"/></table:table-row>
    </table:table>
    <table:table table:name="Totals">
      <table:table-row><table:table-cell office:value-type="float" office:value="5"><text:p>5</text:p></table:table-cell></table:table-row>
    </table:table>
    </office:spreadsheet></office:body></office:document-content>
    """

  func testSheetsValuesAndFormulas() throws {
    let book = try ODSImporter.importWorkbook(contentXML: Data(content.utf8))
    XCTAssertEqual(book.sheets.map(\.name), ["Sales", "Totals"])
    let sales = book.sheets[0]
    func raw(_ row: Int, _ col: Int) -> String {
      sales.cell(at: CellAddress(row: row, col: col)).raw
    }
    XCTAssertEqual(raw(1, 0), "Pens   blue")
    XCTAssertEqual(raw(1, 1), "3.5")
    XCTAssertEqual(raw(1, 2), "46345.5")  // 19 Nov 2026, noon
    XCTAssertEqual(sales.cell(at: CellAddress(row: 1, col: 2)).format?.numberFormat, .date)
    XCTAssertEqual(raw(1, 3), "007")
    XCTAssertEqual(sales.cell(at: CellAddress(row: 1, col: 3)).isText, true)
    XCTAssertEqual(raw(2, 0), "2")
    XCTAssertEqual(raw(3, 0), "2")  // the repeated row
    XCTAssertEqual(raw(4, 0), "=SUM(B2:B4,Totals!A1)")
    XCTAssertEqual(sales.cell(at: CellAddress(row: 4, col: 0)).cachedFormulaValue, .number(10.5))
    XCTAssertEqual(raw(4, 1), "0.25")
    XCTAssertEqual(raw(4, 2), "0.75")
    XCTAssertEqual(raw(4, 3), "TRUE")
    XCTAssertEqual(raw(5, 0), "Merged")
    XCTAssertEqual(raw(5, 2), #"=IF('My Data'!$A$1>1,"a;b",A1)"#)
    XCTAssertEqual(
      sales.mergedRanges,
      [CellRange(start: CellAddress(row: 5, col: 0), end: CellAddress(row: 5, col: 1))])
    // The million empty rows at the end are not copied out.
    XCTAssertLessThan(sales.cells.count, 30)
    XCTAssertEqual(book.sheets[1].cell(at: .origin).raw, "5")
  }

  func testNotAnODSFile() {
    XCTAssertThrowsError(try ODSImporter.importWorkbook(fromArchiveData: Data("hello".utf8)))
  }
}
