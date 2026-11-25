import Engine
import FileFormats
import GridCore
import Model
import XCTest

/// Sparklines lay out one per row or column, save in the worksheet's extension list as other
/// apps write them, read back, and move with inserted and deleted rows.
final class SparklineTests: XCTestCase {
  private func range(_ text: String) -> CellRange {
    XLSXCodec.parseCellRange(text)!
  }

  func testLayoutOnePerRowOrColumn() throws {
    let rows = try XCTUnwrap(
      SparklineGroup.layout(data: range("B2:E4"), locations: range("F2:F4")))
    XCTAssertEqual(rows.map(\.location.a1), ["F2", "F3", "F4"])
    XCTAssertEqual(rows[1].data, range("B3:E3"))
    let columns = try XCTUnwrap(
      SparklineGroup.layout(data: range("B2:D9"), locations: range("B10:D10")))
    XCTAssertEqual(columns[2].data, range("D2:D9"))
    XCTAssertEqual(
      SparklineGroup.layout(data: range("B2:E2"), locations: range("F2"))?.first?.data,
      range("B2:E2"))
    XCTAssertNil(SparklineGroup.layout(data: range("B2:E4"), locations: range("F2:F3")))
    XCTAssertNil(SparklineGroup.layout(data: range("B2:E4"), locations: range("F2")))
  }

  private func workbook(_ groups: [SparklineGroup]) -> Workbook {
    var sheet = Sheet(name: "Q's Sales")
    for row in 0..<3 {
      for col in 0..<4 {
        sheet.setCell(Cell(raw: "\(row * 4 + col - 3)"), at: CellAddress(row: row, col: col))
      }
    }
    sheet.fileExtras.sparklines = groups
    return Workbook(sheets: [sheet, Sheet(name: "Other")])
  }

  func testSparklinesSaveAndReadBack() throws {
    let groups = [
      SparklineGroup(
        kind: .column, colorHex: "112233", showsHighLow: true,
        sparklines: try XCTUnwrap(
          SparklineGroup.layout(data: range("A1:D3"), locations: range("E1:E3")))),
      SparklineGroup(
        kind: .winLoss,
        sparklines: [
          .init(location: CellAddress(row: 5, col: 0), dataSheet: "Other", data: range("A1:A9"))
        ]),
    ]
    let data = try XLSXCodec.exportWorkbook(workbook(groups))
    if let out = ProcessInfo.processInfo.environment["SPARK_GRID_SPARKLINES_OUT"] {
      try data.write(to: URL(fileURLWithPath: out))
    }
    let xml =
      XLSXCodec.zipEntryString(archiveData: data, entryPath: "xl/worksheets/sheet1.xml") ?? ""
    XCTAssertTrue(xml.contains(#"<x14:sparklineGroup displayEmptyCellsAs="gap" type="column""#))
    XCTAssertTrue(
      xml.contains("<xm:f>&apos;Q&apos;&apos;s Sales&apos;!A2:D2</xm:f><xm:sqref>E2</xm:sqref>"))
    XCTAssertTrue(xml.hasSuffix("</extLst></worksheet>"))

    let reopened = try XLSXCodec.importWorkbook(from: data).sheets[0].fileExtras.sparklines
    XCTAssertEqual(reopened.count, 2)
    XCTAssertEqual(reopened[0].kind, .column)
    XCTAssertEqual(reopened[0].colorHex, "112233")
    XCTAssertTrue(reopened[0].showsHighLow)
    XCTAssertEqual(reopened[0].sparklines.map(\.location.a1), ["E1", "E2", "E3"])
    XCTAssertNil(reopened[0].sparklines[0].dataSheet)
    XCTAssertEqual(reopened[1].kind, .winLoss)
    XCTAssertEqual(reopened[1].sparklines[0].dataSheet, "Other")
  }

  func testSparklinesMoveWithRows() throws {
    var sheet = Sheet(name: "S")
    sheet.fileExtras.sparklines = [
      SparklineGroup(
        sparklines: try XCTUnwrap(
          SparklineGroup.layout(data: range("A2:D4"), locations: range("E2:E4"))))
    ]
    SheetStructureMutation.insertRows(into: &sheet, at: 0, count: 2)
    var lines = sheet.fileExtras.sparklines[0].sparklines
    XCTAssertEqual(lines.map(\.location.a1), ["E4", "E5", "E6"])
    XCTAssertEqual(lines[0].data, range("A4:D4"))
    SheetStructureMutation.deleteRows(in: &sheet, at: 4, count: 1)
    lines = sheet.fileExtras.sparklines[0].sparklines
    XCTAssertEqual(lines.map(\.location.a1), ["E4", "E5"])
    SheetStructureMutation.deleteColumns(in: &sheet, at: 4, count: 1)
    XCTAssertTrue(sheet.fileExtras.sparklines.isEmpty)
  }
}
