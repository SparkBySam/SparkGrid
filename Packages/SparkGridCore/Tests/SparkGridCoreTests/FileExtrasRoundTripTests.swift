import Calc
import Engine
import FileFormats
import Foundation
import GridCore
import Model
import XCTest

/// A save keeps what the file had: hidden rows, columns and sheets, groups, protection, page
/// setup, dropdown rules, links, comments, tables, charts the app does not draw, and pivot tables.
final class FileExtrasRoundTripTests: XCTestCase {
  private func address(_ a1: String) -> CellAddress {
    guard let range = XLSXCodec.parseCellRange(a1) else { return .origin }
    return range.start
  }

  private func range(_ a1: String) -> CellRange {
    XLSXCodec.parseCellRange(a1) ?? .singleOrigin
  }

  private func sampleWorkbook() -> Workbook {
    var data = Sheet(name: "Data")
    data.setCell(Cell(raw: "Region"), at: address("A1"))
    data.setCell(Cell(raw: "North"), at: address("A2"))
    data.setCell(Cell(raw: "10"), at: address("B2"))
    var extras = SheetFileExtras()
    extras.hiddenRows = [6]
    extras.hiddenColumns = [5]
    extras.rowOutlineLevels = [7: 1]
    extras.sheetPropertiesXML = #"<sheetPr><tabColor rgb="FFFF8800"/></sheetPr>"#
    extras.protectionXML = #"<sheetProtection sheet="1" objects="1" scenarios="1"/>"#
    extras.pageLayoutXML =
      #"<pageMargins left="0.7" right="0.7" top="0.75" bottom="0.75" header="0.3" footer="0.3"/><pageSetup orientation="landscape"/><headerFooter><oddHeader>&amp;CQuarterly</oddHeader></headerFooter>"#
    extras.dataValidations = [
      DataValidationRule(
        ranges: [range("A2:A5")],
        attributes: #"type="list" allowBlank="1" showErrorMessage="1""#,
        body: "<formula1>&quot;North,South&quot;</formula1>"
      )
    ]
    extras.hyperlinks = [
      CellHyperlink(range: range("E1"), target: "https://sparkgridapp.com", display: "Docs"),
      CellHyperlink(range: range("E2"), location: "Other!A1"),
    ]
    extras.comments = [CellComment(address: address("B2"), author: "Sam", text: "Check <this>")]
    extras.tables = [
      SheetTable(
        range: range("A1:B5"),
        xml:
          #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><table xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" id="1" name="Sales" displayName="Sales" ref="A1:B5"><autoFilter ref="A1:B5"/><tableColumns count="2"><tableColumn id="1" name="Region"/><tableColumn id="2" name="Q1"/></tableColumns></table>"#
      )
    ]
    data.fileExtras = extras

    var hidden = Sheet(name: "Other")
    hidden.setCell(Cell(raw: "secret"), at: .origin)
    hidden.fileExtras.visibility = .hidden
    return Workbook(sheets: [data, hidden])
  }

  func testSaveKeepsWhatTheFileHad() throws {
    let saved = try XLSXCodec.exportWorkbook(sampleWorkbook())
    let reopened = try XLSXCodec.importWorkbook(from: saved)
    let before = sampleWorkbook()
    XCTAssertEqual(reopened.sheets.count, 2)
    let extras = reopened.sheets[0].fileExtras
    let expected = before.sheets[0].fileExtras
    XCTAssertEqual(extras.hiddenRows, expected.hiddenRows)
    XCTAssertEqual(extras.hiddenColumns, expected.hiddenColumns)
    XCTAssertEqual(extras.rowOutlineLevels, expected.rowOutlineLevels)
    XCTAssertEqual(extras.sheetPropertiesXML, expected.sheetPropertiesXML)
    XCTAssertEqual(extras.protectionXML, expected.protectionXML)
    XCTAssertEqual(extras.pageLayoutXML, expected.pageLayoutXML)
    XCTAssertEqual(extras.dataValidations, expected.dataValidations)
    XCTAssertEqual(extras.dataValidations.first?.inlineListItems, ["North", "South"])
    XCTAssertEqual(extras.hyperlinks, expected.hyperlinks)
    XCTAssertEqual(extras.comments, expected.comments)
    XCTAssertEqual(extras.tables.map(\.range), expected.tables.map(\.range))
    XCTAssertEqual(reopened.sheets[1].fileExtras.visibility, .hidden)
    XCTAssertEqual(reopened.activeSheetIndex, 0)
  }

  func testHiddenRowsAndColumnsHaveNoSize() {
    let sheet = sampleWorkbook().sheets[0]
    XCTAssertEqual(sheet.rowHeight(for: 6, default: 22), 0)
    XCTAssertEqual(sheet.rowHeight(for: 5, default: 22), 22)
    XCTAssertEqual(sheet.columnWidth(for: 5, default: 80), 0)
  }

  func testTheFirstVisibleSheetOpensWhenTheFirstSheetIsHidden() throws {
    var workbook = sampleWorkbook()
    workbook.sheets[0].fileExtras.visibility = .hidden
    workbook.sheets[1].fileExtras.visibility = .visible
    let reopened = try XLSXCodec.importWorkbook(from: try XLSXCodec.exportWorkbook(workbook))
    XCTAssertEqual(reopened.sheets[0].fileExtras.visibility, .hidden)
    XCTAssertEqual(reopened.activeSheetIndex, 1)
  }

  func testEveryHiddenSheetStillSavesOneVisible() throws {
    var workbook = sampleWorkbook()
    workbook.sheets[0].fileExtras.visibility = .hidden
    let reopened = try XLSXCodec.importWorkbook(from: try XLSXCodec.exportWorkbook(workbook))
    XCTAssertTrue(reopened.sheets.contains { !$0.isHidden })
  }

  func testInsertingAndDeletingRowsMovesWhatTheFileKept() {
    var sheet = sampleWorkbook().sheets[0]
    SheetStructureMutation.insertRows(into: &sheet, at: 1, count: 2)
    XCTAssertEqual(sheet.fileExtras.hiddenRows, [8])
    XCTAssertEqual(sheet.fileExtras.rowOutlineLevels, [9: 1])
    XCTAssertEqual(sheet.fileExtras.dataValidations.first?.ranges, [range("A4:A7")])
    XCTAssertEqual(sheet.fileExtras.comments.first?.address, address("B4"))
    XCTAssertEqual(sheet.fileExtras.tables.first?.range, range("A1:B7"))

    // Deleting the table's last rows keeps the rest of it.
    SheetStructureMutation.deleteRows(in: &sheet, at: 5, count: 3)
    XCTAssertEqual(sheet.fileExtras.tables.first?.range, range("A1:B5"))
    XCTAssertEqual(sheet.fileExtras.dataValidations.first?.ranges, [range("A4:A5")])
    XCTAssertEqual(sheet.fileExtras.hiddenRows, [5])
  }

  func testAddingAColumnInsideATableAddsItToTheTable() throws {
    var sheet = sampleWorkbook().sheets[0]
    SheetStructureMutation.insertColumns(into: &sheet, at: 1, count: 1)
    let table = try XCTUnwrap(sheet.fileExtras.tables.first)
    XCTAssertEqual(table.range, range("A1:C5"))
    XCTAssertEqual(XLSXCodec.tableColumnNames(table.xml), ["Region", "Column1", "Q1"])
    XCTAssertTrue(table.xml.contains(#"<tableColumns count="3">"#))
    XCTAssertEqual(sheet.cell(at: address("B1")).raw, "Column1")
    XCTAssertEqual(sheet.cell(at: address("C2")).raw, "10")
    XCTAssertEqual(sheet.fileExtras.hiddenColumns, [6])
  }

  func testDeletingAColumnInsideATableRemovesItFromTheTable() throws {
    var sheet = sampleWorkbook().sheets[0]
    SheetStructureMutation.deleteColumns(in: &sheet, at: 1, count: 1)
    let table = try XCTUnwrap(sheet.fileExtras.tables.first)
    XCTAssertEqual(table.range, range("A1:A5"))
    XCTAssertEqual(XLSXCodec.tableColumnNames(table.xml), ["Region"])
    XCTAssertTrue(table.xml.contains(#"<tableColumns count="1">"#))

    // Deleting every column of the table drops it.
    SheetStructureMutation.deleteColumns(in: &sheet, at: 0, count: 1)
    XCTAssertTrue(sheet.fileExtras.tables.isEmpty)
  }

  func testTableFiltersFollowTheirColumns() {
    let xml =
      #"<table ref="A1:C5"><autoFilter ref="A1:C5"><filterColumn colId="1"><filters><filter val="x"/></filters></filterColumn><filterColumn colId="2"><filters><filter val="y"/></filters></filterColumn></autoFilter><tableColumns count="3"><tableColumn id="1" name="A"/><tableColumn id="2" name="B"/><tableColumn id="3" name="C"/></tableColumns></table>"#
    let inserted = XLSXCodec.tableXML(xml, insertingColumns: 1, atOffset: 1, names: ["New"])
    XCTAssertEqual(XLSXCodec.tableColumnNames(inserted), ["A", "New", "B", "C"])
    XCTAssertTrue(inserted.contains(#"<filterColumn colId="2"><filters><filter val="x"/>"#))
    XCTAssertTrue(inserted.contains(#"<tableColumn id="4" name="New"/>"#))
    let removed = XLSXCodec.tableXML(xml, removingColumns: 1, atOffset: 1)
    XCTAssertEqual(removed.map(XLSXCodec.tableColumnNames), ["A", "C"])
    XCTAssertFalse(removed?.contains(#"val="x""#) ?? true)
    XCTAssertTrue(removed?.contains(#"<filterColumn colId="1"><filters><filter val="y"/>"#) == true)
  }

  func testSavedTableRefFollowsItsRange() throws {
    var workbook = sampleWorkbook()
    SheetStructureMutation.insertRows(into: &workbook.sheets[0], at: 3, count: 1)
    let saved = try XLSXCodec.exportWorkbook(workbook)
    let table = XLSXCodec.zipEntryString(archiveData: saved, entryPath: "xl/tables/table1.xml")
    XCTAssertTrue(table?.contains(#"<table "#) == true)
    XCTAssertTrue(table?.contains(#"ref="A1:B6""#) == true)
    XCTAssertTrue(table?.contains(#"<autoFilter ref="A1:B6"/>"#) == true)
  }

  func testChartsAndPivotTablesTheAppDoesNotDrawAreKept() throws {
    var workbook = sampleWorkbook()
    let chartXML = Data(
      #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><c:chartSpace xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart"><c:chart><c:plotArea><c:pieChart/></c:plotArea></c:chart></c:chartSpace>"#
        .utf8)
    let anchor =
      #"<xdr:twoCellAnchor><xdr:from><xdr:col>3</xdr:col><xdr:colOff>0</xdr:colOff><xdr:row>2</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:from><xdr:to><xdr:col>8</xdr:col><xdr:colOff>0</xdr:colOff><xdr:row>12</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:to><xdr:graphicFrame macro=""><xdr:nvGraphicFramePr><xdr:cNvPr id="3" name="Pie"/><xdr:cNvGraphicFramePr/></xdr:nvGraphicFramePr><xdr:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/></xdr:xfrm><a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/chart"><c:chart r:id="SPARK_CHART_ID"/></a:graphicData></a:graphic></xdr:graphicFrame><xdr:clientData/></xdr:twoCellAnchor>"#
    workbook.sheets[0].fileExtras.foreignCharts = [
      ForeignChart(
        anchorXML: anchor,
        from: DrawingMarker(col: 3, colOffset: 0, row: 2, rowOffset: 0),
        to: DrawingMarker(col: 8, colOffset: 0, row: 12, rowOffset: 0),
        chartXML: chartXML
      )
    ]
    let pivotXML = Data(
      #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><pivotTableDefinition xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" name="PivotTable1" cacheId="5"><location ref="H1:I4" firstHeaderRow="1" firstDataRow="1" firstDataCol="1"/></pivotTableDefinition>"#
        .utf8)
    workbook.sheets[1].fileExtras.pivotTables = [PivotTablePart(xml: pivotXML, cacheID: 5)]
    workbook.pivotCaches = [
      PivotCachePart(
        cacheID: 5,
        definitionXML: Data(
          #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><pivotCacheDefinition xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" r:id="rId7" recordCount="1"><cacheSource type="worksheet"><worksheetSource ref="A1:B5" sheet="Data"/></cacheSource></pivotCacheDefinition>"#
            .utf8),
        recordsXML: Data(
          #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><pivotCacheRecords xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="0"/>"#
            .utf8)
      )
    ]

    // Inserting rows above the chart moves it down.
    SheetStructureMutation.insertRows(into: &workbook.sheets[0], at: 0, count: 1)
    let saved = try XLSXCodec.exportWorkbook(workbook)
    let reopened = try XLSXCodec.importWorkbook(from: saved)

    let charts = reopened.sheets[0].fileExtras.foreignCharts
    XCTAssertEqual(charts.count, 1)
    XCTAssertEqual(charts.first?.from?.row, 3)
    XCTAssertEqual(charts.first?.to?.row, 13)
    XCTAssertEqual(charts.first?.chartXML, chartXML)

    XCTAssertEqual(reopened.sheets[1].fileExtras.pivotTables.map(\.cacheID), [5])
    XCTAssertEqual(reopened.pivotCaches.map(\.cacheID), [5])
    XCTAssertNotNil(reopened.pivotCaches.first?.recordsXML)
    let definition = reopened.pivotCaches.first.flatMap {
      String(data: $0.definitionXML, encoding: .utf8)
    }
    XCTAssertTrue(definition?.contains(#"r:id="rId1""#) == true)
    let workbookXML = XLSXCodec.zipEntryString(archiveData: saved, entryPath: "xl/workbook.xml")
    XCTAssertTrue(workbookXML?.contains(#"<pivotCache cacheId="5""#) == true)
    let types = XLSXCodec.zipEntryString(archiveData: saved, entryPath: "[Content_Types].xml")
    XCTAssertTrue(types?.contains("/xl/pivotTables/pivotTable1.xml") == true)
    XCTAssertTrue(types?.contains("/xl/charts/chart1k1.xml") == true)
  }

  func testTrueAndFalseSaveAndReopenAsBooleans() throws {
    var sheet = Sheet(name: "Flags")
    sheet.setCell(Cell(raw: "TRUE"), at: CellAddress(row: 0, col: 0))
    sheet.setCell(Cell(raw: "false"), at: CellAddress(row: 1, col: 0))
    let saved = try XLSXCodec.exportWorkbook(Workbook(sheets: [sheet]))
    let xml = XLSXCodec.zipEntryString(archiveData: saved, entryPath: "xl/worksheets/sheet1.xml")
    XCTAssertTrue(xml?.contains(#"<c r="A1" t="b"><v>1</v></c>"#) == true)
    XCTAssertTrue(xml?.contains(#"<c r="A2" t="b"><v>0</v></c>"#) == true)
    let reopened = try XLSXCodec.importWorkbook(from: saved)
    XCTAssertEqual(reopened.sheets[0].cell(at: CellAddress(row: 0, col: 0)).raw, "TRUE")
    XCTAssertEqual(reopened.sheets[0].cell(at: CellAddress(row: 1, col: 0)).raw, "FALSE")
  }

  /// Every part of a saved file must be well-formed XML, or other apps throw it away.
  private func assertEveryPartParses(
    _ saved: Data, file: StaticString = #filePath, line: UInt = #line
  )
    throws
  {
    let names = [
      "xl/workbook.xml", "xl/worksheets/sheet1.xml", "xl/worksheets/sheet2.xml",
      "xl/drawings/drawing1.xml", "xl/drawings/_rels/drawing1.xml.rels", "xl/comments1.xml",
      "xl/drawings/vmlDrawing1.vml", "xl/tables/table1.xml", "[Content_Types].xml",
    ]
    for name in names {
      guard let part = XLSXCodec.zipEntryData(archiveData: saved, entryPath: name) else { continue }
      XCTAssertTrue(
        XMLParser(data: part).parse(), "\(name) is not well-formed", file: file, line: line)
    }
  }

  func testKeptChartsDeclareEachNamespaceOnce() throws {
    var workbook = sampleWorkbook()
    // The anchor already declares the prefixes its drawing declares, as some files do.
    let anchor =
      #"<oneCellAnchor xmlns="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><from><col>3</col><colOff>0</colOff><row>2</row><rowOff>0</rowOff></from><ext cx="100" cy="100"/><graphicFrame><nvGraphicFramePr><cNvPr id="1" name="Chart 1"/><cNvGraphicFramePr/></nvGraphicFramePr><xfrm/><a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/chart"><c:chart r:id="SPARK_CHART_ID"/></a:graphicData></a:graphic></graphicFrame><clientData/></oneCellAnchor>"#
    workbook.sheets[0].fileExtras.foreignCharts = [
      ForeignChart(
        anchorXML: anchor, from: DrawingMarker(col: 3, colOffset: 0, row: 2, rowOffset: 0), to: nil,
        chartXML: Data(
          #"<c:chartSpace xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart"/>"#.utf8)
      )
    ]
    // Saved, reopened and saved again, as a person editing the file would.
    let first = try XLSXCodec.exportWorkbook(workbook)
    let second = try XLSXCodec.exportWorkbook(try XLSXCodec.importWorkbook(from: first))
    try assertEveryPartParses(first)
    try assertEveryPartParses(second)
    let drawing = XLSXCodec.zipEntryString(
      archiveData: second, entryPath: "xl/drawings/drawing1.xml")
    // Declared once on the root and once on the anchor.
    XCTAssertEqual(drawing?.components(separatedBy: "xmlns:a=").count, 3)
  }

  func testAnchorsSavedWithRepeatedNamespacesAreCleaned() {
    let repeated =
      #"<oneCellAnchor xmlns:a="x" xmlns:c="y" xmlns:a="x"><from/></oneCellAnchor>"#
    XCTAssertEqual(
      XLSXCodec.withoutRepeatedAttributes(repeated),
      #"<oneCellAnchor xmlns:a="x" xmlns:c="y"><from/></oneCellAnchor>"#)
  }

  func testAFormulaThatLosesItsCellsDropsItsSavedResult() throws {
    var workbook = Workbook(sheets: [Sheet(name: "Data")])
    workbook.sheets[0].setCell(Cell(raw: "5"), at: address("B1"))
    workbook.sheets[0].setCell(
      Cell(raw: "=B1*2", importedFormulaResult: "10", importedFormulaValueType: .number),
      at: address("C1"))
    workbook.sheets[0].setCell(
      Cell(raw: "=A1+1", importedFormulaResult: "1", importedFormulaValueType: .number),
      at: address("D1"))
    let outcome = WorkbookSession().apply(
      id: "sheet.deleteColumns", arguments: ["sheet": "Data", "index": "1", "count": "1"],
      to: &workbook)
    XCTAssertTrue(outcome.ok)
    let lost = workbook.sheets[0].cell(at: address("B1"))
    XCTAssertEqual(lost.raw, "=#REF!*2")
    XCTAssertNil(lost.importedFormulaResult)
    // A formula whose reference only moved keeps its answer.
    XCTAssertEqual(workbook.sheets[0].cell(at: address("C1")).importedFormulaResult, "1")
    let saved = try XLSXCodec.exportWorkbook(workbook)
    let book = XLSXCodec.zipEntryString(archiveData: saved, entryPath: "xl/workbook.xml")
    XCTAssertTrue(book?.contains("fullCalcOnLoad") == true)
  }

  func testTextHighlightRulesKeepTheirCellAndText() throws {
    var sheet = Sheet(name: "Orders")
    sheet.setCell(Cell(raw: "Loss"), at: address("N2"))
    sheet.setCell(Cell(raw: "Win"), at: address("N3"))
    let plain = try XLSXCodec.exportWorkbook(Workbook(sheets: [sheet]))
    // The rule as another app writes it: cell value equals the text "Loss", on N2:N5.
    let rule =
      #"<conditionalFormatting sqref="N2:N5"><cfRule type="cellIs" priority="1" operator="equal" dxfId="0"><formula>"Loss"</formula></cfRule></conditionalFormatting>"#
    let sheetXML = try XCTUnwrap(
      XLSXCodec.zipEntryString(archiveData: plain, entryPath: "xl/worksheets/sheet1.xml"))
    let withRule = sheetXML.replacingOccurrences(of: "</sheetData>", with: "</sheetData>" + rule)
    let source = try XCTUnwrap(
      XLSXCodec.replacingZipEntries(
        plain, entries: ["xl/worksheets/sheet1.xml": Data(withRule.utf8)]))
    let opened = try XLSXCodec.importWorkbook(from: source)
    XCTAssertEqual(opened.sheets[0].conditionalFormats.first?.predicate, .formula(#"=N2="Loss""#))
    let saved = try XLSXCodec.exportWorkbook(opened)
    let savedXML = XLSXCodec.zipEntryString(
      archiveData: saved, entryPath: "xl/worksheets/sheet1.xml")
    XCTAssertTrue(savedXML?.contains("<formula>N2=&quot;Loss&quot;</formula>") == true)

    // The grid highlights the matching cell, not the cell beside it.
    let engine = FormulaEngine()
    engine.rebuild(workbook: opened, recalculate: true)
    let highlight = #"=N2="Loss""#
    let origin = address("N2")
    XCTAssertEqual(
      engine.evaluateConditionalFormula(
        highlight, at: address("N2"), relativeTo: origin, sheet: opened.sheets[0]),
      .bool(true))
    XCTAssertEqual(
      engine.evaluateConditionalFormula(
        highlight, at: address("N3"), relativeTo: origin, sheet: opened.sheets[0]),
      .bool(false))
  }

  func testOldSaveDataWithoutExtrasStillDecodes() throws {
    let encoded = try JSONEncoder().encode(Sheet(name: "Plain"))
    let decoded = try JSONDecoder().decode(Sheet.self, from: encoded)
    XCTAssertEqual(decoded.fileExtras, SheetFileExtras())
    XCTAssertFalse(String(data: encoded, encoding: .utf8)?.contains("fileExtras") ?? true)
  }
}
