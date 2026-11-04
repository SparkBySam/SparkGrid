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

  /// A data bar from 0 to 1.5 kept that scale through a save. It used to come back min to max,
  /// so a 0.75 bar in a column of 0.5 to 1.0 drew half full instead of a half of 1.5.
  func testDataBarScaleRoundTripsAndSetsBarLength() throws {
    let a1 = CellAddress(row: 0, col: 0)
    var sheet = Sheet(name: "Data")
    for (row, value) in ["0.5", "0.75", "1"].enumerated() {
      sheet.setCell(Cell(raw: value), at: CellAddress(row: row, col: 0))
    }
    let style = DataBarStyle(
      color: DataBarStyle.blue.color, showValue: true,
      low: DataBarBound(type: .number, value: 0), high: DataBarBound(type: .number, value: 1.5))
    let range = CellRange(start: a1, end: CellAddress(row: 2, col: 0))
    sheet.conditionalFormats = [
      ConditionalFormatRule(range: range, predicate: .dataBar(style), style: .redFill)
    ]
    let data = try XLSXCodec.exportWorkbook(Workbook(sheets: [sheet]))
    let reopened = try XLSXCodec.importWorkbook(from: data).sheets[0]
    guard case .dataBar(let saved) = reopened.conditionalFormats.first?.predicate else {
      return XCTFail("data bar did not reopen")
    }
    XCTAssertEqual(saved.low, style.low)
    XCTAssertEqual(saved.high, style.high)

    let paint = ConditionalFormatEvaluator.resolvedPaint(
      at: CellAddress(row: 1, col: 0), base: nil, rules: reopened.conditionalFormats,
      value: .number(0.75), displayString: "0.75", numberFormat: nil,
      numericValuesInRange: { _ in [0.5, 0.75, 1] },
      evaluateFormula: { _, _, _ in .blank })
    XCTAssertEqual(paint.dataBarFraction ?? 0, 0.5, accuracy: 1e-9)
  }

  /// An icon set from a file keeps its own thresholds (here 10 and 50) and its reversed order
  /// through a save, and those thresholds pick the icons.
  func testIconSetKeepsItsThresholdsAndDirection() throws {
    let a1 = CellAddress(row: 0, col: 0)
    var sheet = Sheet(name: "Data")
    for (row, value) in ["5", "20", "80"].enumerated() {
      sheet.setCell(Cell(raw: value), at: CellAddress(row: row, col: 0))
    }
    let thresholds = [
      DataBarBound(type: .number, value: 0), DataBarBound(type: .number, value: 10),
      DataBarBound(type: .number, value: 50),
    ]
    sheet.conditionalFormats = [
      ConditionalFormatRule(
        range: CellRange(start: a1, end: CellAddress(row: 2, col: 0)),
        predicate: .iconSet(.threeTrafficLights), iconThresholds: thresholds, iconReverse: true)
    ]
    let data = try XLSXCodec.exportWorkbook(Workbook(sheets: [sheet]))
    let rule = try XCTUnwrap(
      XLSXCodec.importWorkbook(from: data).sheets[0].conditionalFormats.first)
    XCTAssertEqual(rule.iconThresholds, thresholds)
    XCTAssertEqual(rule.iconReverse, true)
    let icons = [5.0, 20, 80].map { value in
      ConditionalFormatEvaluator.resolvedPaint(
        at: a1, base: nil, rules: [rule], value: .number(value), displayString: "",
        numberFormat: nil, numericValuesInRange: { _ in [5, 20, 80] },
        evaluateFormula: { _, _, _ in .blank }
      ).icon
    }
    // Reversed: the lowest values get the first (green) icon.
    XCTAssertEqual(icons, [.greenCircle, .yellowCircle, .redCircle])
  }

  /// A bar with min and max ends still starts at 0, as it always has.
  func testDataBarWithMinAndMaxKeepsTheAutomaticScale() throws {
    let a1 = CellAddress(row: 0, col: 0)
    var sheet = Sheet(name: "Data")
    sheet.setCell(Cell(raw: "5"), at: a1)
    sheet.conditionalFormats = [
      ConditionalFormatRule(
        range: CellRange(start: a1, end: a1), predicate: .dataBar(.blue), style: .redFill)
    ]
    let data = try XLSXCodec.exportWorkbook(Workbook(sheets: [sheet]))
    let reopened = try XLSXCodec.importWorkbook(from: data).sheets[0]
    guard case .dataBar(let saved) = reopened.conditionalFormats.first?.predicate else {
      return XCTFail("data bar did not reopen")
    }
    XCTAssertNil(saved.low)
    XCTAssertNil(saved.high)
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
