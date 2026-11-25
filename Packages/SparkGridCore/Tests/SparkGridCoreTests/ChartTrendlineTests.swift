import FileFormats
import GridCore
import Model
import XCTest

/// Trendlines fit as other spreadsheet apps fit them (results checked against their LINEST,
/// LOGEST and RSQ), save in the chart part, and read back from files.
final class ChartTrendlineTests: XCTestCase {
  func testLinearFitAndRSquared() throws {
    let fit = try XCTUnwrap(
      ChartTrendline(kind: .linear).fit(x: [1, 2, 3, 4, 5], y: [2, 4.1, 5.9, 8.2, 9.8]))
    XCTAssertEqual(fit.b, 1.97, accuracy: 1e-9)
    XCTAssertEqual(fit.a, 0.09, accuracy: 1e-9)
    XCTAssertEqual(try XCTUnwrap(fit.rSquared), 0.99766, accuracy: 1e-5)
    XCTAssertEqual(fit.equation, "y = 1.97x + 0.09")
  }

  func testExponentialFit() throws {
    let ys = [1, 2, 3, 4].map { 3 * exp(0.5 * Double($0)) }
    let fit = try XCTUnwrap(ChartTrendline(kind: .exponential).fit(x: [1, 2, 3, 4], y: ys))
    XCTAssertEqual(fit.a, 3, accuracy: 1e-9)
    XCTAssertEqual(fit.b, 0.5, accuracy: 1e-9)
    XCTAssertEqual(try XCTUnwrap(fit.value(at: 5)), 3 * exp(2.5), accuracy: 1e-6)
    XCTAssertNil(ChartTrendline(kind: .exponential).fit(x: [1, 2], y: [1, -1]))
  }

  func testLogarithmicAndPowerFits() throws {
    let xs: [Double] = [1, 2, 4, 8]
    let log = try XCTUnwrap(
      ChartTrendline(kind: .logarithmic).fit(x: xs, y: xs.map { 2 + 3 * Foundation.log($0) }))
    XCTAssertEqual(log.a, 2, accuracy: 1e-9)
    XCTAssertEqual(log.b, 3, accuracy: 1e-9)
    let power = try XCTUnwrap(
      ChartTrendline(kind: .power).fit(x: xs, y: xs.map { 1.5 * pow($0, 0.7) }))
    XCTAssertEqual(power.a, 1.5, accuracy: 1e-9)
    XCTAssertEqual(power.b, 0.7, accuracy: 1e-9)
    XCTAssertEqual(power.rSquared ?? 0, 1, accuracy: 1e-12)
  }

  func testMovingAverage() throws {
    let fit = try XCTUnwrap(
      ChartTrendline(kind: .movingAverage, period: 3).fit(x: [1, 2, 3, 4, 5], y: [3, 6, 9, 3, 0]))
    XCTAssertEqual(fit.averages.map(\.x), [3, 4, 5])
    XCTAssertEqual(fit.averages.map(\.y), [6, 6, 4])
    XCTAssertNil(fit.equation)
  }

  private func sheet(with chart: SheetChart) -> Sheet {
    var sheet = Sheet(name: "Sales")
    let rows = [
      ["Month", "East", "West"], ["Jan", "10", "20"], ["Feb", "15", "25"], ["Mar", "18", "22"],
    ]
    for (row, values) in rows.enumerated() {
      for (col, value) in values.enumerated() {
        sheet.setCell(Cell(raw: value), at: CellAddress(row: row, col: col))
      }
    }
    sheet.charts = [chart]
    return sheet
  }

  private let range = CellRange(start: .origin, end: CellAddress(row: 3, col: 2))

  func testTrendlineSavesAndReadsBack() throws {
    let chart = SheetChart(
      kind: .line, title: "East", dataRange: range, categoryColumn: 0, valueColumn: 1,
      anchorRow: 6, anchorCol: 0,
      trendline: ChartTrendline(kind: .linear, showsEquation: true, showsRSquared: true))
    XCTAssertTrue(chart.drawsTrendline)
    XCTAssertTrue(chart.usesSeriesPlot)
    let data = try XLSXCodec.exportWorkbook(Workbook(sheets: [sheet(with: chart)]))
    if let out = ProcessInfo.processInfo.environment["SPARK_GRID_TRENDLINE_OUT"] {
      try data.write(to: URL(fileURLWithPath: out))
    }
    let xml = XLSXCodec.zipEntryString(archiveData: data, entryPath: "xl/charts/chart1.xml") ?? ""
    XCTAssertTrue(xml.contains(#"<c:trendlineType val="linear"/>"#))
    XCTAssertTrue(xml.contains(#"<c:dispEq val="1"/>"#))
    let trend = try XCTUnwrap(xml.range(of: "<c:trendline>"))
    let cat = try XCTUnwrap(xml.range(of: "<c:cat>"))
    XCTAssertLessThan(trend.lowerBound, cat.lowerBound)

    let part = try XCTUnwrap(ImportedChartReader.read(xml: xml))
    XCTAssertEqual(part.series[0].trendline?.kind, .linear)
    XCTAssertEqual(part.series[0].trendline?.showsRSquared, true)
    // The series keeps its own color, not the trendline's grey.
    XCTAssertNotEqual(part.series[0].colorHex, "595959")

    let reopened = try XLSXCodec.importWorkbook(from: data).sheets[0].charts.first
    XCTAssertEqual(reopened?.trendline, chart.trendline)
  }

  func testMovingAverageSavesItsPeriod() throws {
    let chart = SheetChart(
      kind: .bar, dataRange: range, categoryColumn: 0, valueColumn: 1, anchorRow: 6,
      anchorCol: 0, trendline: ChartTrendline(kind: .movingAverage, period: 3))
    let data = try XLSXCodec.exportWorkbook(Workbook(sheets: [sheet(with: chart)]))
    let xml = XLSXCodec.zipEntryString(archiveData: data, entryPath: "xl/charts/chart1.xml") ?? ""
    XCTAssertTrue(xml.contains(#"<c:trendlineType val="movingAvg"/><c:period val="3"/>"#))
    XCTAssertEqual(ImportedChartReader.read(xml: xml)?.series[0].trendline?.period, 3)
  }

  func testStackedKindsHaveNoTrendline() {
    let chart = SheetChart(
      kind: .stackedBar, dataRange: range, anchorRow: 6, anchorCol: 0,
      trendline: ChartTrendline())
    XCTAssertFalse(chart.drawsTrendline)
  }

  /// Each new kind saves as the chart other apps draw for it.
  func testNewKindsSaveAsTheirChartParts() throws {
    let expected: [(SheetChart.Kind, ImportedChart.Kind, Bool, Int)] = [
      (.horizontalBar, .bar, false, 2), (.stackedBar, .column, true, 2),
      (.stackedHorizontalBar, .bar, true, 2), (.stackedArea, .area, true, 2),
      (.doughnut, .doughnut, false, 1),
    ]
    for (kind, partKind, stacked, seriesCount) in expected {
      let chart = SheetChart(
        kind: kind, title: kind.title, dataRange: range, categoryColumn: 0, valueColumn: 1,
        extraValueColumns: [2], anchorRow: 6, anchorCol: 0)
      XCTAssertTrue(chart.usesSeriesPlot, kind.rawValue)
      let data = try XLSXCodec.exportWorkbook(Workbook(sheets: [sheet(with: chart)]))
      let xml =
        XLSXCodec.zipEntryString(archiveData: data, entryPath: "xl/charts/chart1.xml") ?? ""
      let part = try XCTUnwrap(ImportedChartReader.read(xml: xml), kind.rawValue)
      XCTAssertEqual(part.kind, partKind, kind.rawValue)
      XCTAssertEqual(part.isStacked, stacked, kind.rawValue)
      XCTAssertEqual(part.series.count, seriesCount, kind.rawValue)
      XCTAssertEqual(
        try XLSXCodec.importWorkbook(from: data).sheets[0].charts.first?.kind, kind)
    }
  }

  /// What another app needs to draw the chart as Spark Grid does (found opening the 1.7 charts in
  /// Excel, Nov 20): axes written as shown, horizontal bars with the first category on top, the
  /// first of several series named by its header, and a doughnut's slices each in their color.
  func testChartPartsDrawTheSameElsewhere() throws {
    func xml(_ kind: SheetChart.Kind, extra: [Int] = [2]) throws -> String {
      let chart = SheetChart(
        kind: kind, title: kind.title, dataRange: range, categoryColumn: 0, valueColumn: 1,
        extraValueColumns: extra, anchorRow: 6, anchorCol: 0)
      let data = try XLSXCodec.exportWorkbook(Workbook(sheets: [sheet(with: chart)]))
      return XLSXCodec.zipEntryString(archiveData: data, entryPath: "xl/charts/chart1.xml") ?? ""
    }
    let bars = try xml(.horizontalBar)
    XCTAssertEqual(bars.components(separatedBy: #"<c:delete val="0"/>"#).count - 1, 2)
    XCTAssertTrue(bars.contains(#"<c:orientation val="maxMin"/>"#))
    XCTAssertTrue(bars.contains(#"<c:crosses val="max"/>"#))
    XCTAssertTrue(
      bars.contains("<c:tx><c:strRef><c:f>&apos;Sales&apos;!B1</c:f></c:strRef></c:tx>"))
    let doughnut = try xml(.doughnut, extra: [])
    XCTAssertFalse(doughnut.contains("<c:ser>\n") && doughnut.contains("<c:spPr><a:solidFill>"))
    XCTAssertEqual(ImportedChartReader.read(xml: doughnut)?.series.first?.colorHex, nil)
  }

  /// Writes a workbook with every new kind and each trendline, to look at by hand:
  /// SPARK_GRID_CHARTS_DEMO_OUT=/path/demo.xlsx swift test --filter testWriteDemoWorkbook
  func testWriteDemoWorkbook() throws {
    guard let out = ProcessInfo.processInfo.environment["SPARK_GRID_CHARTS_DEMO_OUT"] else {
      throw XCTSkip("Set SPARK_GRID_CHARTS_DEMO_OUT to write the demo workbook.")
    }
    var sheet = Sheet(name: "Demo")
    let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug"]
    let east = [12, 15, 19, 26, 30, 41, 47, 60]
    let west = [20, 18, 22, 21, 25, 24, 28, 27]
    sheet.setCell(Cell(raw: "Month"), at: CellAddress(row: 0, col: 0))
    sheet.setCell(Cell(raw: "East"), at: CellAddress(row: 0, col: 1))
    sheet.setCell(Cell(raw: "West"), at: CellAddress(row: 0, col: 2))
    for row in 0..<months.count {
      sheet.setCell(Cell(raw: months[row]), at: CellAddress(row: row + 1, col: 0))
      sheet.setCell(Cell(raw: "\(east[row])"), at: CellAddress(row: row + 1, col: 1))
      sheet.setCell(Cell(raw: "\(west[row])"), at: CellAddress(row: row + 1, col: 2))
    }
    let data = CellRange(start: .origin, end: CellAddress(row: months.count, col: 2))
    let charts: [(SheetChart.Kind, [Int], ChartTrendline?)] = [
      (.horizontalBar, [2], nil), (.stackedBar, [2], nil), (.stackedHorizontalBar, [2], nil),
      (.stackedArea, [2], nil), (.doughnut, [], nil),
      (.line, [], ChartTrendline(kind: .exponential, showsEquation: true, showsRSquared: true)),
      (.bar, [], ChartTrendline(kind: .movingAverage, period: 3)),
      (.scatter, [], ChartTrendline(kind: .linear, showsEquation: true, showsRSquared: true)),
    ]
    sheet.charts = charts.enumerated().map { index, item in
      SheetChart(
        kind: item.0, title: item.0.title + (item.2.map { " · \($0.kind.title)" } ?? ""),
        dataRange: data, categoryColumn: item.0 == .scatter ? 2 : 0, valueColumn: 1,
        extraValueColumns: item.1, anchorRow: 11 + (index / 2) * 14, anchorCol: (index % 2) * 7,
        rowSpan: 13, colSpan: 6, showsLegend: !item.1.isEmpty || item.0 == .doughnut,
        frameIsCustom: true, trendline: item.2)
    }
    try XLSXCodec.exportWorkbook(Workbook(sheets: [sheet])).write(to: URL(fileURLWithPath: out))
  }
}
