import FileFormats
import GridCore
import Model
import XCTest

/// Edit Chart rewrites a chart from another app in its own part, and the reader sees the edit.
final class ImportedChartWriterTests: XCTestCase {
  private func edited(
    _ xml: String, sheet: String = "Data", _ change: (inout ImportedChartEdit) -> Void
  ) throws -> (chart: ImportedChart, xml: String) {
    let data = Data(xml.utf8)
    let chart = try XCTUnwrap(ImportedChartReader.read(data))
    var edit = ImportedChartEdit(chart: chart, sheetName: sheet)
    change(&edit)
    let written = try XCTUnwrap(ImportedChartWriter.apply(edit, to: data, sheetName: sheet))
    let text = try XCTUnwrap(String(data: written, encoding: .utf8))
    return (try XCTUnwrap(ImportedChartReader.read(written), text), text)
  }

  func testNoChangeKeepsWhatTheFileSays() throws {
    let result = try edited(ImportedChartReaderTests.prefixedBarChart) { _ in }
    XCTAssertEqual(
      result.chart, ImportedChartReader.read(xml: ImportedChartReaderTests.prefixedBarChart))
    XCTAssertTrue(result.xml.contains("<c:numCache>"))
  }

  func testTitleKeepsTheFilesFontAndPrefix() throws {
    let result = try edited(ImportedChartReaderTests.prefixedBarChart) { $0.title = "Sales" }
    XCTAssertEqual(result.chart.title, "Sales")
    XCTAssertTrue(result.xml.contains("<a:t>Sales</a:t>"), result.xml)
    XCTAssertFalse(result.xml.contains("enue"))
    XCTAssertFalse(
      result.xml.contains(
        "xmlns:c=\"http://schemas.openxmlformats.org/drawingml/2006/chart\" xmlns:c"))
  }

  func testEmptyTitleIsDeletedNotFilledFromTheSeries() throws {
    let result = try edited(ImportedChartReaderTests.columnChart, sheet: "Monthly Summary") {
      $0.title = ""
    }
    XCTAssertEqual(result.chart.title, "")
    XCTAssertTrue(result.xml.contains(#"autoTitleDeleted val="1""#), result.xml)
  }

  func testStackedBarBecomesClusteredColumns() throws {
    let result = try edited(ImportedChartReaderTests.prefixedBarChart) {
      $0.kind = .column
      $0.isStacked = false
    }
    XCTAssertEqual(result.chart.kind, .column)
    XCTAssertFalse(result.chart.isStacked)
    XCTAssertEqual(result.chart.series.count, 2)
    XCTAssertTrue(result.xml.contains(#"<c:barDir val="col"/>"#), result.xml)
  }

  func testColumnsBecomeALineWithTheSeriesColorOnTheLine() throws {
    let result = try edited(ImportedChartReaderTests.prefixedBarChart) { $0.kind = .line }
    XCTAssertEqual(result.chart.kind, .line)
    XCTAssertEqual(result.chart.series[0].colorHex, "4472C4")
    XCTAssertEqual(result.chart.series[0].cachedValues, [10, 20.5])
    XCTAssertTrue(result.xml.contains("<c:lineChart>"))
    XCTAssertTrue(result.xml.contains("<a:ln"), result.xml)
    XCTAssertFalse(result.xml.contains("barChart"))
    XCTAssertFalse(result.xml.contains("invertIfNegative"))
  }

  func testLegendAndAxisTitles() throws {
    let result = try edited(ImportedChartReaderTests.columnChart, sheet: "Monthly Summary") {
      $0.showsLegend = true
      $0.categoryAxisTitle = "Month"
      $0.valueAxisTitle = ""
    }
    XCTAssertTrue(result.chart.showsLegend)
    XCTAssertEqual(result.chart.categoryAxisTitle, "Month")
    XCTAssertEqual(result.chart.valueAxisTitle, "")
  }

  func testSeriesRangeNameAndColorAndAnAddedSeries() throws {
    let result = try edited(ImportedChartReaderTests.prefixedBarChart) { edit in
      edit.series[0].valuesFormula = "B2:B4"
      edit.series[0].nameFormula = ""
      edit.series[0].name = "East"
      edit.series[1].colorHex = "FF0000"
      edit.series.append(
        ImportedChartEdit.Series(name: "North", valuesFormula: "'Other Sheet'!D2:D4"))
    }
    let series = result.chart.series
    XCTAssertEqual(series.count, 3)
    XCTAssertEqual(series[0].name, "East")
    XCTAssertEqual(series[0].values?.sheetName, "Data")
    XCTAssertEqual(series[0].values?.range.end, CellAddress(row: 3, col: 1))
    XCTAssertEqual(series[0].cachedValues, [], "stale saved points are dropped")
    XCTAssertEqual(series[0].cachedCategories, ["Q1", "Q2"], "untouched labels keep theirs")
    XCTAssertEqual(series[1].colorHex, "FF0000")
    XCTAssertEqual(series[2].name, "North")
    XCTAssertEqual(series[2].values?.sheetName, "Other Sheet")
    XCTAssertTrue(result.xml.contains(#"<c:idx val="2"/>"#), result.xml)
  }

  func testRemovingASeries() throws {
    let result = try edited(ImportedChartReaderTests.prefixedBarChart) { edit in
      edit.series.removeFirst()
    }
    XCTAssertEqual(result.chart.series.count, 1)
    XCTAssertEqual(result.chart.series[0].values?.range.start, CellAddress(row: 1, col: 2))
  }

  func testABadRangeIsRefused() throws {
    let data = Data(ImportedChartReaderTests.prefixedBarChart.utf8)
    let chart = try XCTUnwrap(ImportedChartReader.read(data))
    var edit = ImportedChartEdit(chart: chart, sheetName: "Data")
    edit.series[0].valuesFormula = "not a range"
    XCTAssertNil(ImportedChartWriter.apply(edit, to: data, sheetName: "Data"))
  }

  func testPieKeepsItsKind() throws {
    let result = try edited(ImportedChartReaderTests.pieChart, sheet: "New in 1.2") {
      $0.kind = .line
      $0.title = "Share"
    }
    XCTAssertEqual(result.chart.kind, .pie)
    XCTAssertEqual(result.chart.title, "Share")
  }

  func testFormulaQuotesSheetNames() {
    XCTAssertEqual(
      ImportedChartEdit.qualifiedFormula("C4:N4", sheetName: "Monthly Summary"),
      "'Monthly Summary'!$C$4:$N$4")
    XCTAssertEqual(ImportedChartEdit.qualifiedFormula("=Data!B2", sheetName: "X"), "Data!$B$2")
    XCTAssertNil(ImportedChartEdit.qualifiedFormula("hello", sheetName: "X"))
  }
}
