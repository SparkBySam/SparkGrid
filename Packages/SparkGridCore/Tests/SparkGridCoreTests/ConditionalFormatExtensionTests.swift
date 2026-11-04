import FileFormats
import GridCore
import Model
import XCTest

/// Rules in a worksheet's Excel 2010 extension block (`x14:conditionalFormatting`).
final class ConditionalFormatExtensionTests: XCTestCase {
  private let dxfs = [ConditionalFormatStyle.redFill]

  private func rules(_ worksheetXML: String) -> [ConditionalFormatRule] {
    var sheet = Sheet(name: "Data")
    XLSXCodec.importConditionalFormatting(
      into: &sheet, worksheetXML: worksheetXML, dxfs: dxfs, themeScheme: ThemeColorScheme())
    return sheet.conditionalFormats
  }

  /// Each rule is saved once. A second copy in an extension block kept Google Sheets from
  /// showing any of them.
  func testSaveWritesEachRuleOnce() throws {
    var sheet = Sheet(name: "Data")
    sheet.setCell(Cell(raw: "12"), at: CellAddress(row: 0, col: 0))
    let a1 = CellRange(start: CellAddress(row: 0, col: 0), end: CellAddress(row: 0, col: 0))
    sheet.conditionalFormats = [
      ConditionalFormatRule(range: a1, predicate: .greaterThan(10), style: .redFill)
    ]
    let data = try XLSXCodec.exportWorkbook(Workbook(sheets: [sheet]))
    let xml =
      XLSXCodec.zipEntryString(archiveData: data, entryPath: "xl/worksheets/sheet1.xml") ?? ""
    XCTAssertFalse(xml.contains("x14:conditionalFormatting"))
    XCTAssertEqual(xml.components(separatedBy: "<cfRule ").count - 1, 1)
    XCTAssertEqual(try XLSXCodec.importWorkbook(from: data).sheets[0].conditionalFormats.count, 1)
  }

  /// Excel keeps most rules in the sheet and only some in the extension. Both kinds open.
  func testRulesInTheSheetAndTheExtensionBothOpen() {
    let xml = """
      <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" \
      xmlns:x14="http://schemas.microsoft.com/office/spreadsheetml/2009/9/main" \
      xmlns:xm="http://schemas.microsoft.com/office/excel/2006/main"><sheetData/>\
      <conditionalFormatting sqref="A1:A5"><cfRule type="cellIs" dxfId="0" priority="2" \
      operator="greaterThan"><formula>10</formula></cfRule></conditionalFormatting>\
      <extLst><ext uri="{78C0D931-6437-407d-A8EE-F0AAD7539E65}"><x14:conditionalFormattings>\
      <x14:conditionalFormatting><x14:cfRule type="expression" priority="1" \
      id="{00000000-0000-0000-0000-000000000001}"><xm:f>Other!A1&gt;0</xm:f><x14:dxf><x14:fill>\
      <x14:patternFill><x14:bgColor rgb="FFFFC7CE"/></x14:patternFill></x14:fill></x14:dxf>\
      </x14:cfRule><xm:sqref>B1:B5</xm:sqref></x14:conditionalFormatting>\
      </x14:conditionalFormattings></ext></extLst></worksheet>
      """
    let opened = rules(xml)
    XCTAssertEqual(opened.count, 2, "\(opened)")
    XCTAssertTrue(opened.contains { $0.predicate == .greaterThan(10) })
    XCTAssertTrue(opened.contains { if case .formula = $0.predicate { true } else { false } })
  }

  /// Files saved by Spark Grid 1.2 and earlier have every rule twice: in the sheet and again in
  /// an extension block. Each opens once.
  func testOlderSparkGridCopiesOpenOnce() {
    let xml = """
      <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData/>\
      <conditionalFormatting sqref="A1:A5"><cfRule type="cellIs" dxfId="0" priority="1" \
      operator="greaterThan"><formula>10</formula></cfRule></conditionalFormatting>\
      <extLst><ext uri="{78C0FAFA-122D-4D67-B399-A730565E8757}" \
      xmlns:x14="http://schemas.microsoft.com/office/spreadsheetml/2009/9/main">\
      <x14:conditionalFormattings><x14:conditionalFormatting \
      xmlns:xm="http://schemas.microsoft.com/office/excel/2006/main"><xm:sqref>A1:A5</xm:sqref>\
      <x14:cfRule type="cellIs" priority="1" operator="greaterThan"><x14:dxf><x14:fill>\
      <x14:patternFill patternType="solid"><x14:fgColor rgb="FFFF0000"/><x14:bgColor \
      rgb="FFFF0000"/></x14:patternFill></x14:fill></x14:dxf><xm:f>10</xm:f></x14:cfRule>\
      </x14:conditionalFormatting></x14:conditionalFormattings></ext></extLst></worksheet>
      """
    let opened = rules(xml)
    XCTAssertEqual(opened.count, 1, "\(opened)")
    XCTAssertEqual(opened.first?.predicate, .greaterThan(10))
  }

  /// Excel writes a data bar in the sheet with a link to a fuller copy in the extension.
  /// It opens once.
  func testLinkedDataBarOpensOnce() {
    let xml = """
      <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" \
      xmlns:x14="http://schemas.microsoft.com/office/spreadsheetml/2009/9/main" \
      xmlns:xm="http://schemas.microsoft.com/office/excel/2006/main"><sheetData/>\
      <conditionalFormatting sqref="A1:A5"><cfRule type="dataBar" priority="1"><dataBar>\
      <cfvo type="min"/><cfvo type="max"/><color rgb="FF638EC6"/></dataBar><extLst>\
      <ext uri="{B025F937-C7B1-47D3-B67F-A62EFF666E3E}"><x14:id>{AAAA0000-0000-0000-0000-000000000002}\
      </x14:id></ext></extLst></cfRule></conditionalFormatting>\
      <extLst><ext uri="{78C0D931-6437-407d-A8EE-F0AAD7539E65}"><x14:conditionalFormattings>\
      <x14:conditionalFormatting><x14:cfRule type="dataBar" \
      id="{AAAA0000-0000-0000-0000-000000000002}"><x14:dataBar minLength="0" maxLength="100">\
      <x14:cfvo type="autoMin"/><x14:cfvo type="autoMax"/></x14:dataBar></x14:cfRule>\
      <xm:sqref>A1:A5</xm:sqref></x14:conditionalFormatting></x14:conditionalFormattings>\
      </ext></extLst></worksheet>
      """
    let opened = rules(xml)
    XCTAssertEqual(opened.count, 1, "\(opened)")
    guard case .dataBar = opened.first?.predicate else { return XCTFail("\(opened)") }
  }
}
