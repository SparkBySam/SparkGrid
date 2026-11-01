import Engine
import GridCore
import Model
import NumberFormat
import XCTest

/// The fill handle continues numbers, dates, numbered text, and month and day names.
final class FillSeriesTests: XCTestCase {
  private func values(_ raws: [String], count: Int, format: CellFormat? = nil) -> [String] {
    guard let series = FillSeries.plan(raws.map { Cell(raw: $0, format: format) }) else {
      return []
    }
    return (raws.count..<(raws.count + count)).map { series.value(at: $0) }
  }

  func testNumbersKeepTheirStep() {
    XCTAssertEqual(values(["1", "2"], count: 3), ["3", "4", "5"])
    XCTAssertEqual(values(["10", "20", "30"], count: 2), ["40", "50"])
    XCTAssertEqual(values(["0.1", "0.2"], count: 2), ["0.3", "0.4"])
    XCTAssertEqual(values(["5", "3"], count: 2), ["1", "-1"])
  }

  func testOneNumberIsCopiedButOneDateSteps() {
    XCTAssertNil(FillSeries.plan([Cell(raw: "7")]))
    XCTAssertEqual(
      values(["46000"], count: 2, format: CellFormat(numberFormat: .date)), ["46001", "46002"])
  }

  func testNumberedTextCounts() {
    XCTAssertEqual(values(["Item 1"], count: 2), ["Item 2", "Item 3"])
    XCTAssertEqual(values(["Q1", "Q3"], count: 1), ["Q5"])
    XCTAssertEqual(values(["Week 09"], count: 2), ["Week 10", "Week 11"])
  }

  func testMonthAndDayNamesGoOn() {
    XCTAssertEqual(values(["Nov"], count: 3), ["Dec", "Jan", "Feb"])
    XCTAssertEqual(values(["MONDAY"], count: 1), ["TUESDAY"])
    XCTAssertEqual(values(["Jan", "Mar"], count: 2), ["May", "Jul"])
  }

  func testFormulasPlainTextAndBlanksAreCopied() {
    XCTAssertNil(FillSeries.plan([Cell(raw: "=A1+1"), Cell(raw: "=A2+1")]))
    XCTAssertNil(FillSeries.plan([Cell(raw: "North")]))
    XCTAssertNil(FillSeries.plan([Cell(raw: "1"), Cell(raw: "")]))
  }

  func testFillCommandContinuesDownAndCopiesOnRequest() {
    var workbook = Workbook(sheets: [Sheet(name: "Data")])
    workbook.sheets[0].setCell(Cell(raw: "1"), at: CellAddress(row: 0, col: 0))
    workbook.sheets[0].setCell(Cell(raw: "2"), at: CellAddress(row: 1, col: 0))
    workbook.sheets[0].setCell(Cell(raw: "=A1*2"), at: CellAddress(row: 0, col: 1))
    workbook.sheets[0].setCell(Cell(raw: "=A2*2"), at: CellAddress(row: 1, col: 1))
    let commands = WorkbookSession()
    var series = workbook
    _ = commands.apply(
      id: "edit.fill", arguments: ["sheet": "Data", "source": "A1:B2", "end": "B4"], to: &series)
    XCTAssertEqual(series.sheets[0].cell(at: CellAddress(row: 3, col: 0)).raw, "4")
    XCTAssertEqual(series.sheets[0].cell(at: CellAddress(row: 3, col: 1)).raw, "=A4*2")

    var copied = workbook
    _ = commands.apply(
      id: "edit.fill",
      arguments: ["sheet": "Data", "source": "A1:B2", "end": "B4", "series": "0"],
      to: &copied)
    XCTAssertEqual(copied.sheets[0].cell(at: CellAddress(row: 3, col: 0)).raw, "2")
  }
}

/// Sorting by more than one column breaks ties with the next level.
final class MultiLevelSortTests: XCTestCase {
  func testThenByBreaksTies() {
    var workbook = Workbook(sheets: [Sheet(name: "Data")])
    let rows = [["Region", "ARR"], ["West", "5"], ["East", "9"], ["West", "8"], ["East", "2"]]
    for (r, row) in rows.enumerated() {
      for (c, value) in row.enumerated() {
        workbook.sheets[0].setCell(Cell(raw: value), at: CellAddress(row: r, col: c))
      }
    }
    let outcome = WorkbookSession().apply(
      id: "data.sort",
      arguments: [
        "sheet": "Data", "range": "A1:B5", "column": "0", "ascending": "true", "header": "true",
        "then": "1:desc",
      ],
      to: &workbook)
    XCTAssertTrue(outcome.ok)
    let sorted = (1...4).map {
      workbook.sheets[0].cell(at: CellAddress(row: $0, col: 0)).raw + " "
        + workbook.sheets[0].cell(at: CellAddress(row: $0, col: 1)).raw
    }
    XCTAssertEqual(sorted, ["East 9", "East 2", "West 8", "West 5"])
  }
}
