import Engine
import Formula
import GridCore
import Model
import XCTest

@testable import FileFormats

final class PrintPaginationTests: XCTestCase {
  func testRowsSplitOnTheirEdgesNeverInsideARow() {
    // Ten rows of 20 points; 50 points of room fits two whole rows per page.
    let runs = PrintPagination.split(
      first: 0, sizes: Array(repeating: 20, count: 10), available: 50)
    XCTAssertEqual(runs, [0...1, 2...3, 4...5, 6...7, 8...9])
  }

  func testManualBreakStartsANewPage() {
    let runs = PrintPagination.split(
      first: 0, sizes: Array(repeating: 20, count: 10), available: 1000, breaks: [4, 7])
    XCTAssertEqual(runs, [0...3, 4...6, 7...9])
  }

  func testHiddenRowsTakeNoRoomAndATallRowGetsItsOwnPage() {
    XCTAssertEqual(
      PrintPagination.split(first: 5, sizes: [20, 0, 0, 20, 20], available: 40), [5...8, 9...9])
    XCTAssertEqual(
      PrintPagination.split(first: 0, sizes: [10, 90, 10], available: 50), [0...0, 1...1, 2...2])
  }

  func testBreakAtTheFirstRowIsIgnored() {
    XCTAssertEqual(
      PrintPagination.split(first: 3, sizes: [1, 1], available: 10, breaks: [3]), [3...4])
  }

  func testPageOrder() {
    let across = PrintPagination.pages(
      rows: [0...1, 2...3], columns: [0...0, 1...1], overThenDown: true)
    XCTAssertEqual(across.map(\.columns), [0...0, 1...1, 0...0, 1...1])
    let down = PrintPagination.pages(
      rows: [0...1, 2...3], columns: [0...0, 1...1], overThenDown: false)
    XCTAssertEqual(down.map(\.rows), [0...1, 2...3, 0...1, 2...3])
  }
}

final class PrintLayoutFileTests: XCTestCase {
  private func range(_ a: String, _ b: String) -> CellRange {
    let (start, end) = A1Reference.parseRange("\(a):\(b)")!
    return CellRange(start: start, end: end)
  }

  func testPrintAreasAndBreaksSaveOnEachSheet() throws {
    var first = Sheet(name: "Q1 Sales")
    first.setCell(Cell(raw: "x"), at: CellAddress(row: 0, col: 0))
    first.fileExtras.printArea = range("A1", "D20")
    first.fileExtras.rowBreaks = [10, 15]
    first.fileExtras.columnBreaks = [2]
    var second = Sheet(name: "Owner's")
    second.setCell(Cell(raw: "y"), at: CellAddress(row: 0, col: 0))
    second.fileExtras.printArea = range("B2", "C5")

    let data = try XLSXCodec.exportWorkbook(Workbook(sheets: [first, second]))
    let workbookXML = try XCTUnwrap(
      XLSXCodec.zipEntryString(archiveData: data, entryPath: "xl/workbook.xml"))
    XCTAssertTrue(
      workbookXML.contains(
        #"<definedName name="_xlnm.Print_Area" localSheetId="0">&apos;Q1 Sales&apos;!$A$1:$D$20</definedName>"#
      ))
    XCTAssertTrue(
      workbookXML.contains(#"localSheetId="1">&apos;Owner&apos;&apos;s&apos;!$B$2:$C$5<"#))
    let sheetXML = try XCTUnwrap(
      XLSXCodec.zipEntryString(archiveData: data, entryPath: "xl/worksheets/sheet1.xml"))
    XCTAssertTrue(sheetXML.contains(#"<brk id="10" max="16383" man="1"/>"#))
    XCTAssertTrue(sheetXML.contains(#"<colBreaks count="1" manualBreakCount="1"><brk id="2""#))

    let reopened = try XLSXCodec.importWorkbook(from: data)
    XCTAssertEqual(reopened.sheets[0].fileExtras.printArea, range("A1", "D20"))
    XCTAssertEqual(reopened.sheets[0].fileExtras.rowBreaks, [10, 15])
    XCTAssertEqual(reopened.sheets[0].fileExtras.columnBreaks, [2])
    XCTAssertEqual(reopened.sheets[1].fileExtras.printArea, range("B2", "C5"))
    XCTAssertTrue(reopened.namedRanges.isEmpty, "print areas are not workbook names")
  }

  func testOnlyManualBreaksAreKept() {
    let split = SheetFileExtras.splittingPageBreaks(
      from:
        #"<pageMargins left="0.7"/><rowBreaks count="2" manualBreakCount="1"><brk id="12" max="16383" man="1"/><brk id="40" max="16383"/></rowBreaks>"#
    )
    XCTAssertEqual(split.rows, [12])
    XCTAssertEqual(split.layout, #"<pageMargins left="0.7"/>"#)
  }

  func testWholeColumnPrintAreaReads() {
    XCTAssertEqual(
      XLSXCodec.singleRange("Data!$A:$C", sheetName: "Data"),
      CellRange(start: CellAddress(row: 0, col: 0), end: CellAddress(row: 1_048_575, col: 2)))
    XCTAssertNil(XLSXCodec.singleRange("Data!$A$1:$B$2,Data!$D$1:$E$2", sheetName: "Data"))
  }

  func testInsertingRowsMovesBreaksAndPrintArea() {
    var sheet = Sheet(name: "S")
    sheet.fileExtras.printArea = range("A1", "B10")
    sheet.fileExtras.rowBreaks = [5]
    SheetStructureMutation.insertRows(into: &sheet, at: 2, count: 3)
    XCTAssertEqual(sheet.fileExtras.printArea, range("A1", "B13"))
    XCTAssertEqual(sheet.fileExtras.rowBreaks, [8])
    SheetStructureMutation.deleteRows(in: &sheet, at: 8, count: 1)
    XCTAssertEqual(sheet.fileExtras.rowBreaks, [])
  }
}
