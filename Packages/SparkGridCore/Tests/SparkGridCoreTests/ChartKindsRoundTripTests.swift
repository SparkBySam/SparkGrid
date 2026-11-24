import FileFormats
import GridCore
import Model
import XCTest

/// Pie, scatter, and charts with more than one series save as charts other apps draw, and come
/// back as the same chart.
final class ChartKindsRoundTripTests: XCTestCase {
  private func salesSheet(with chart: SheetChart) -> Sheet {
    var sheet = Sheet(name: "Sales")
    let rows = [
      ["Month", "East", "West", "North"], ["Jan", "10", "20", "5"], ["Feb", "15", "25", "8"],
    ]
    for (row, values) in rows.enumerated() {
      for (col, value) in values.enumerated() {
        sheet.setCell(Cell(raw: value), at: CellAddress(row: row, col: col))
      }
    }
    sheet.charts = [chart]
    return sheet
  }

  private let range = CellRange(start: .origin, end: CellAddress(row: 2, col: 3))

  private func savedChart(_ chart: SheetChart) throws -> (
    reopened: SheetChart?, part: ImportedChart?
  ) {
    let data = try XLSXCodec.exportWorkbook(Workbook(sheets: [salesSheet(with: chart)]))
    let reopened = try XLSXCodec.importWorkbook(from: data).sheets[0].charts.first
    let xml = XLSXCodec.zipEntryString(archiveData: data, entryPath: "xl/charts/chart1.xml") ?? ""
    return (reopened, ImportedChartReader.read(xml: xml))
  }

  func testBarWithThreeSeriesSavesEachSeries() throws {
    let chart = SheetChart(
      kind: .bar, title: "Sales", dataRange: range, categoryColumn: 0, valueColumn: 1,
      extraValueColumns: [2, 3], anchorRow: 5, anchorCol: 0)
    let saved = try savedChart(chart)
    XCTAssertEqual(saved.reopened?.extraValueColumns, [2, 3])
    let part = try XCTUnwrap(saved.part)
    XCTAssertEqual(part.kind, .column)
    XCTAssertEqual(part.series.count, 3)
    XCTAssertEqual(part.series[2].nameReference?.range.start, CellAddress(row: 0, col: 3))
    XCTAssertEqual(part.series[2].values?.range.start, CellAddress(row: 1, col: 3))
  }

  /// Error bars from a column save as custom plus-and-minus bars before the series' values,
  /// and the chart reopens with its error bar column.
  func testErrorBarsSaveFromTheirColumn() throws {
    let chart = SheetChart(
      kind: .line, title: "East", dataRange: range, categoryColumn: 0, valueColumn: 1,
      anchorRow: 5, anchorCol: 0, errorBarColumn: 3)
    XCTAssertTrue(chart.drawsErrorBars)
    let data = try XLSXCodec.exportWorkbook(Workbook(sheets: [salesSheet(with: chart)]))
    if let out = ProcessInfo.processInfo.environment["SPARK_GRID_ERRBARS_OUT"] {
      try data.write(to: URL(fileURLWithPath: out))
    }
    let xml = XLSXCodec.zipEntryString(archiveData: data, entryPath: "xl/charts/chart1.xml") ?? ""
    XCTAssertTrue(xml.contains("<c:errValType val=\"cust\"/>"))
    XCTAssertTrue(
      xml.contains("<c:plus><c:numRef><c:f>&apos;Sales&apos;!D2:D3</c:f></c:numRef></c:plus>"))
    let errBars = try XCTUnwrap(xml.range(of: "<c:errBars>"))
    let cat = try XCTUnwrap(xml.range(of: "<c:cat>"))
    XCTAssertLessThan(errBars.lowerBound, cat.lowerBound)
    let reopened = try XLSXCodec.importWorkbook(from: data).sheets[0].charts.first
    XCTAssertEqual(reopened?.errorBarColumn, 3)

    var twoSeries = chart
    twoSeries.extraValueColumns = [2]
    XCTAssertFalse(twoSeries.drawsErrorBars)
  }

  func testPieSavesAsAPieWithOneSeries() throws {
    let chart = SheetChart(
      kind: .pie, title: "Share", dataRange: range, categoryColumn: 0, valueColumn: 1,
      extraValueColumns: [2], anchorRow: 5, anchorCol: 0)
    let saved = try savedChart(chart)
    XCTAssertEqual(saved.reopened?.kind, .pie)
    let part = try XCTUnwrap(saved.part)
    XCTAssertEqual(part.kind, .pie)
    XCTAssertEqual(part.series.count, 1)
  }

  func testScatterSavesXAndYValues() throws {
    let chart = SheetChart(
      kind: .scatter, title: "East vs West", dataRange: range, categoryColumn: 1, valueColumn: 2,
      anchorRow: 5, anchorCol: 0)
    let saved = try savedChart(chart)
    XCTAssertEqual(saved.reopened?.kind, .scatter)
    let part = try XCTUnwrap(saved.part)
    XCTAssertEqual(part.kind, .scatter)
    XCTAssertEqual(part.series[0].categories?.range.start, CellAddress(row: 1, col: 1))
    XCTAssertEqual(part.series[0].values?.range.start, CellAddress(row: 1, col: 2))
  }
}
