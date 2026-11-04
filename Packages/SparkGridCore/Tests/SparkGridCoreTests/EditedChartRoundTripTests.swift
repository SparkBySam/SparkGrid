import FileFormats
import Foundation
import GridCore
import Model
import XCTest

/// A chart from another app that was edited, resized, duplicated and reordered in Spark Grid
/// saves as a valid file and reopens as it was left, twice over.
final class EditedChartRoundTripTests: XCTestCase {
  private static let twoCell =
    #"<xdr:twoCellAnchor><xdr:from><xdr:col>3</xdr:col><xdr:colOff>0</xdr:colOff><xdr:row>2</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:from><xdr:to><xdr:col>8</xdr:col><xdr:colOff>0</xdr:colOff><xdr:row>12</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:to><xdr:graphicFrame macro=""><xdr:nvGraphicFramePr><xdr:cNvPr id="2" name="Revenue"/><xdr:cNvGraphicFramePr/></xdr:nvGraphicFramePr><xdr:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/></xdr:xfrm><a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/chart"><c:chart r:id="SPARK_CHART_ID"/></a:graphicData></a:graphic></xdr:graphicFrame><xdr:clientData/></xdr:twoCellAnchor>"#

  private static let oneCell =
    #"<xdr:oneCellAnchor><xdr:from><xdr:col>10</xdr:col><xdr:colOff>0</xdr:colOff><xdr:row>2</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:from><xdr:ext cx="5760000" cy="2700000"/><xdr:graphicFrame macro=""><xdr:nvGraphicFramePr><xdr:cNvPr id="3" name="Net"/><xdr:cNvGraphicFramePr/></xdr:nvGraphicFramePr><xdr:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/></xdr:xfrm><a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/chart"><c:chart r:id="SPARK_CHART_ID"/></a:graphicData></a:graphic></xdr:graphicFrame><xdr:clientData/></xdr:oneCellAnchor>"#

  private func workbook() throws -> Workbook {
    var data = Sheet(name: "Data")
    for (row, values) in [["Q", "East", "West"], ["Q1", "10", "4"], ["Q2", "20", "6"]].enumerated()
    {
      for (col, value) in values.enumerated() {
        data.setCell(Cell(raw: value), at: CellAddress(row: row, col: col))
      }
    }
    // One of Spark Grid's own charts and a picture share the drawing with the file's charts.
    data.charts = [
      SheetChart(
        title: "Own", dataRange: CellRange(start: .origin, end: CellAddress(row: 2, col: 1)),
        anchorRow: 14, anchorCol: 0)
    ]
    data.images = [
      SheetImage(
        anchorRow: 20, anchorCol: 0, widthEMU: 127_000, heightEMU: 127_000, imageData: Self.png)
    ]
    data.fileExtras.foreignCharts = [
      ForeignChart(
        anchorXML: Self.twoCell,
        from: DrawingMarker(col: 3, colOffset: 0, row: 2, rowOffset: 0),
        to: DrawingMarker(col: 8, colOffset: 0, row: 12, rowOffset: 0),
        chartXML: Data(ImportedChartReaderTests.prefixedBarChart.utf8)),
      ForeignChart(
        anchorXML: Self.oneCell,
        from: DrawingMarker(col: 10, colOffset: 0, row: 2, rowOffset: 0), to: nil,
        chartXML: Data(ImportedChartReaderTests.columnChart.utf8)),
    ]
    return Workbook(sheets: [data])
  }

  /// Every edit the app makes to a file's chart, done the way the app does it.
  private func edited() throws -> Workbook {
    var book = try workbook()
    var parts = book.sheets[0].fileExtras.foreignCharts
    // Edit Chart: bars to stacked columns, a new title, a third series.
    let chart = try XCTUnwrap(ImportedChartReader.read(parts[0].chartXML))
    var edit = ImportedChartEdit(chart: chart, sheetName: "Data")
    edit.kind = .column
    edit.title = "Revenue by quarter"
    edit.series.append(ImportedChartEdit.Series(name: "North", valuesFormula: "C2:C3"))
    parts[0].chartXML = try XCTUnwrap(
      ImportedChartWriter.apply(edit, to: parts[0].chartXML, sheetName: "Data"))
    // Resize the one-cell chart to 300 by 200 points.
    parts[1].anchorXML = DrawingAnchorXML.withSize(
      parts[1].anchorXML, CGSize(width: 300, height: 200))
    // Duplicate the first, then send the copy to the back.
    let copy = DrawingAnchorXML.shifted(parts[0], rows: 2)
    parts.insert(copy, at: 0)
    book.sheets[0].fileExtras.foreignCharts = parts
    return book
  }

  func testEditedChartsReopenAsLeft() throws {
    let saved = try XLSXCodec.exportWorkbook(try edited())
    let reopened = try XLSXCodec.importWorkbook(from: saved).sheets[0]
    let parts = reopened.fileExtras.foreignCharts
    XCTAssertEqual(parts.count, 3)
    XCTAssertEqual(reopened.charts.count, 1)
    XCTAssertEqual(reopened.images.count, 1)

    let copy = try XCTUnwrap(ImportedChartReader.read(parts[0].chartXML))
    let original = try XCTUnwrap(ImportedChartReader.read(parts[1].chartXML))
    for chart in [copy, original] {
      XCTAssertEqual(chart.kind, .column)
      XCTAssertEqual(chart.title, "Revenue by quarter")
      XCTAssertEqual(chart.series.count, 3)
    }
    XCTAssertEqual(parts[0].from?.row, 4, "the copy sits two rows lower")
    XCTAssertEqual(parts[0].to?.row, 14)
    XCTAssertEqual(parts[1].from?.row, 2)

    XCTAssertTrue(parts[2].anchorXML.contains(#"cx="3810000" cy="2540000""#), parts[2].anchorXML)
  }

  func testTheSavedFileIsValid() throws {
    let saved = try XLSXCodec.exportWorkbook(try edited())
    try saved.write(
      to: FileManager.default.temporaryDirectory.appendingPathComponent("edited-charts.xlsx"))
    try assertValidPackage(saved)
    let drawing = try XCTUnwrap(
      XLSXCodec.zipEntryString(archiveData: saved, entryPath: "xl/drawings/drawing1.xml"))
    let ids = matches(#"cNvPr id="(\d+)""#, in: drawing)
    XCTAssertEqual(ids.count, 5, "own chart, picture and three kept charts")
    XCTAssertEqual(Set(ids).count, ids.count, "every object in a drawing has its own id: \(ids)")
  }

  func testSavingAgainKeepsEverything() throws {
    let first = try XLSXCodec.exportWorkbook(try edited())
    let second = try XLSXCodec.exportWorkbook(try XLSXCodec.importWorkbook(from: first))
    try assertValidPackage(second)
    let a = try XLSXCodec.importWorkbook(from: first).sheets[0].fileExtras.foreignCharts
    let b = try XLSXCodec.importWorkbook(from: second).sheets[0].fileExtras.foreignCharts
    XCTAssertEqual(a.map(\.chartXML), b.map(\.chartXML))
    XCTAssertEqual(a.map(\.from), b.map(\.from))
    XCTAssertEqual(a.map(\.to), b.map(\.to))
  }

  // MARK: - Helpers

  /// Every XML part parses, every relationship points at a part in the file, and every chart
  /// part has a content type.
  private func assertValidPackage(_ data: Data, line: UInt = #line) throws {
    let names = try XCTUnwrap(XLSXCodec.zipEntryNames(archiveData: data))
    for name in names where name.hasSuffix(".xml") || name.hasSuffix(".rels") {
      let part = try XCTUnwrap(XLSXCodec.zipEntryData(archiveData: data, entryPath: name))
      XCTAssertTrue(XMLParser(data: part).parse(), "\(name) is not well-formed", line: line)
    }
    for rels in names where rels.hasSuffix(".rels") {
      let xml = try XCTUnwrap(XLSXCodec.zipEntryString(archiveData: data, entryPath: rels))
      let folder = (rels as NSString).deletingLastPathComponent  // …/_rels
      let base = (folder as NSString).deletingLastPathComponent
      for tag in matches(#"<Relationship ([^>]*)/>"#, in: xml) where !tag.contains("External") {
        guard let target = matches(#"Target="([^"]+)""#, in: tag).first else { continue }
        let joined = target.hasPrefix("/") ? target : "/\(base)/\(target)"
        let path = String((joined as NSString).standardizingPath.dropFirst())
        XCTAssertTrue(names.contains(path), "\(rels) points at missing \(path)", line: line)
      }
    }
    let types = try XCTUnwrap(
      XLSXCodec.zipEntryString(archiveData: data, entryPath: "[Content_Types].xml"))
    for chart in names where chart.hasPrefix("xl/charts/") && chart.hasSuffix(".xml") {
      XCTAssertTrue(types.contains("/\(chart)"), "\(chart) has no content type", line: line)
    }
  }

  private func matches(_ pattern: String, in text: String) -> [String] {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    let ns = text as NSString
    return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map {
      ns.substring(with: $0.range(at: 1))
    }
  }

  /// A 1×1 PNG.
  private static let png = Data(
    base64Encoded:
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
  )!
}
