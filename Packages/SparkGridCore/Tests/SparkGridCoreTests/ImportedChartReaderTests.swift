import FileFormats
import GridCore
import Model
import XCTest

/// Charts from other apps are read from their kept chart part so Spark Grid can draw them.
final class ImportedChartReaderTests: XCTestCase {
  /// The stress workbook's column chart: no prefix, data across a row on another sheet.
  func testColumnChartAcrossARowOnAnotherSheet() throws {
    let chart = try XCTUnwrap(ImportedChartReader.read(xml: Self.columnChart))
    XCTAssertEqual(chart.kind, .column)
    XCTAssertEqual(chart.title, "Net sales by month")
    XCTAssertEqual(chart.valueAxisTitle, "Net ($)")
    XCTAssertEqual(chart.series.count, 1)
    let series = chart.series[0]
    XCTAssertEqual(series.categories?.sheetName, "Monthly Summary")
    XCTAssertEqual(
      series.categories?.range,
      CellRange(start: CellAddress(row: 3, col: 2), end: CellAddress(row: 3, col: 13)))
    XCTAssertEqual(series.values?.addresses.count, 12)
    XCTAssertFalse(chart.showsLegend)
  }

  func testPieChartNamesItsSeriesFromACell() throws {
    let chart = try XCTUnwrap(ImportedChartReader.read(xml: Self.pieChart))
    XCTAssertEqual(chart.kind, .pie)
    XCTAssertEqual(chart.title, "Deals by amount")
    XCTAssertEqual(chart.series[0].nameReference?.sheetName, "New in 1.2")
    XCTAssertEqual(chart.series[0].nameReference?.range.start, CellAddress(row: 56, col: 3))
    XCTAssertTrue(chart.showsLegend)
  }

  func testScatterChartReadsXAndYValues() throws {
    let chart = try XCTUnwrap(ImportedChartReader.read(xml: Self.scatterChart))
    XCTAssertEqual(chart.kind, .scatter)
    XCTAssertEqual(chart.series[0].categories?.range.start, CellAddress(row: 4, col: 2))
    XCTAssertEqual(chart.series[0].values?.range.end, CellAddress(row: 9, col: 7))
  }

  /// Excel's own output: `c:` prefixes, saved point values, a stacked horizontal bar, two series.
  func testPrefixedStackedBarWithSavedValuesAndColor() throws {
    let chart = try XCTUnwrap(ImportedChartReader.read(xml: Self.prefixedBarChart))
    XCTAssertEqual(chart.kind, .bar)
    XCTAssertTrue(chart.isStacked)
    XCTAssertEqual(chart.series.count, 2)
    XCTAssertEqual(chart.series[0].name, "East & West")
    XCTAssertEqual(chart.series[0].cachedCategories, ["Q1", "Q2"])
    XCTAssertEqual(chart.series[0].cachedValues, [10, 20.5])
    XCTAssertEqual(chart.series[0].colorHex, "4472C4")
    XCTAssertEqual(chart.series[1].values?.sheetName, nil)
    XCTAssertEqual(chart.title, "Revenue")
  }

  func testAChartWithNoPlotIsNotRead() {
    XCTAssertNil(ImportedChartReader.read(xml: "<c:chartSpace><c:chart/></c:chartSpace>"))
  }

  static let columnChart = #"""
    <chartSpace xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns="http://schemas.openxmlformats.org/drawingml/2006/chart"><chart><title><tx><rich><a:bodyPr /><a:p><a:pPr><a:defRPr /></a:pPr><a:r><a:t>Net sales by month</a:t></a:r></a:p></rich></tx></title><plotArea><barChart><barDir val="col" /><grouping val="clustered" /><ser><idx val="0" /><order val="0" /><spPr><a:ln><a:prstDash val="solid" /></a:ln></spPr><cat><numRef><f>'Monthly Summary'!$C$4:$N$4</f></numRef></cat><val><numRef><f>'Monthly Summary'!$C$65:$N$65</f></numRef></val></ser><gapWidth val="150" /><axId val="10" /><axId val="100" /></barChart><catAx><axId val="10" /><scaling><orientation val="minMax" /></scaling><axPos val="l" /><majorTickMark val="none" /><minorTickMark val="none" /><crossAx val="100" /><lblOffset val="100" /></catAx><valAx><axId val="100" /><scaling><orientation val="minMax" /></scaling><axPos val="l" /><majorGridlines /><title><tx><rich><a:bodyPr /><a:p><a:pPr><a:defRPr /></a:pPr><a:r><a:t>Net ($)</a:t></a:r></a:p></rich></tx></title><majorTickMark val="none" /><minorTickMark val="none" /><crossAx val="10" /></valAx></plotArea><plotVisOnly val="1" /><dispBlanksAs val="gap" /></chart></chartSpace>
    """#

  static let pieChart = #"""
    <chartSpace xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns="http://schemas.openxmlformats.org/drawingml/2006/chart"><chart><title><tx><rich><a:bodyPr /><a:p><a:pPr><a:defRPr /></a:pPr><a:r><a:t>Deals by amount</a:t></a:r></a:p></rich></tx></title><plotArea><pieChart><varyColors val="1" /><ser><idx val="0" /><order val="0" /><tx><strRef><f>'New in 1.2'!D57</f></strRef></tx><spPr><a:ln><a:prstDash val="solid" /></a:ln></spPr><cat><numRef><f>'New in 1.2'!$A$58:$A$62</f></numRef></cat><val><numRef><f>'New in 1.2'!$D$58:$D$62</f></numRef></val></ser><firstSliceAng val="0" /></pieChart></plotArea><legend><legendPos val="r" /></legend><plotVisOnly val="1" /><dispBlanksAs val="gap" /></chart></chartSpace>
    """#

  static let scatterChart = #"""
    <chartSpace xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns="http://schemas.openxmlformats.org/drawingml/2006/chart"><chart><title><tx><rich><a:bodyPr /><a:p><a:pPr><a:defRPr /></a:pPr><a:r><a:t>Value by position</a:t></a:r></a:p></rich></tx></title><plotArea><scatterChart><ser><idx val="0" /><order val="0" /><tx><strRef><f>'New in 1.2'!H4</f></strRef></tx><spPr><a:ln><a:prstDash val="solid" /></a:ln></spPr><marker><symbol val="none" /><spPr><a:ln><a:prstDash val="solid" /></a:ln></spPr></marker><xVal><numRef><f>'New in 1.2'!$C$5:$C$10</f></numRef></xVal><yVal><numRef><f>'New in 1.2'!$H$5:$H$10</f></numRef></yVal></ser><axId val="10" /><axId val="20" /></scatterChart><valAx><axId val="10" /><scaling><orientation val="minMax" /></scaling><axPos val="l" /><majorGridlines /><majorTickMark val="none" /><minorTickMark val="none" /><crossAx val="20" /></valAx><valAx><axId val="20" /><scaling><orientation val="minMax" /></scaling><axPos val="l" /><majorGridlines /><majorTickMark val="none" /><minorTickMark val="none" /><crossAx val="10" /></valAx></plotArea><legend><legendPos val="r" /></legend><plotVisOnly val="1" /><dispBlanksAs val="gap" /></chart></chartSpace>
    """#

  static let prefixedBarChart = #"""
    <c:chartSpace xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"><c:chart><c:title><c:tx><c:rich><a:p><a:r><a:t>Rev</a:t></a:r><a:r><a:t>enue</a:t></a:r></a:p></c:rich></c:tx></c:title><c:autoTitleDeleted val="0"/><c:plotArea><c:barChart><c:barDir val="bar"/><c:grouping val="stacked"/><c:ser><c:idx val="0"/><c:tx><c:strRef><c:f>Data!$B$1</c:f><c:strCache><c:ptCount val="1"/><c:pt idx="0"><c:v>East &amp; West</c:v></c:pt></c:strCache></c:strRef></c:tx><c:spPr><a:solidFill><a:srgbClr val="4472c4"/></a:solidFill></c:spPr><c:cat><c:strRef><c:f>Data!$A$2:$A$3</c:f><c:strCache><c:ptCount val="2"/><c:pt idx="0"><c:v>Q1</c:v></c:pt><c:pt idx="1"><c:v>Q2</c:v></c:pt></c:strCache></c:strRef></c:cat><c:val><c:numRef><c:f>Data!$B$2:$B$3</c:f><c:numCache><c:ptCount val="2"/><c:pt idx="0"><c:v>10</c:v></c:pt><c:pt idx="1"><c:v>20.5</c:v></c:pt></c:numCache></c:numRef></c:val></c:ser><c:ser><c:idx val="1"/><c:val><c:numRef><c:f>$C$2:$C$3</c:f></c:numRef></c:val></c:ser></c:barChart></c:plotArea></c:chart></c:chartSpace>
    """#
}
