import Engine
import FileFormats
import GridCore
import Model
import XCTest

final class PivotTests: XCTestCase {
  private let headers = ["Region", "Rep", "Product", "Amount"]
  private let records: [[CellValue]] = [
    [.string("West"), .string("Ann"), .string("Bike"), .number(100)],
    [.string("East"), .string("Bo"), .string("Helmet"), .number(40)],
    [.string("West"), .string("Ann"), .string("Helmet"), .number(30)],
    [.string("East"), .string("Cy"), .string("Bike"), .number(120)],
    [.string("West"), .string("Di"), .string("Bike"), .string("n/a")],
    [.blank, .blank, .blank, .blank],
    [.string("north "), .string("Ed"), .string("Bike"), .number(5)],
  ]

  private func texts(_ row: [PivotCell]) -> [String] {
    row.map {
      switch $0 {
      case .blank: ""
      case .text(let t): t
      case .number(let n): n == n.rounded() ? String(Int(n)) : String(n)
      }
    }
  }

  func testSumByRowField() throws {
    let table = try XCTUnwrap(
      PivotTable.calculate(
        headers: headers, records: records,
        definition: PivotDefinition(rows: [0], values: [.init(field: 3, aggregate: .sum)])))
    XCTAssertEqual(
      table.cells.map(texts),
      [
        ["Region", "Sum of Amount"],
        ["East", "160"],
        ["north", "5"],
        ["West", "130"],
        ["Grand Total", "295"],
      ])
    XCTAssertEqual(table.boldRows, [0, 4])
  }

  func testCountCountsTextButSumSkipsIt() throws {
    let table = try XCTUnwrap(
      PivotTable.calculate(
        headers: headers, records: records,
        definition: PivotDefinition(
          rows: [0],
          values: [.init(field: 3, aggregate: .count), .init(field: 3, aggregate: .average)])))
    XCTAssertEqual(texts(table.cells[3]), ["West", "3", "65"])
    XCTAssertEqual(texts(table.cells[0]), ["Region", "Count of Amount", "Average of Amount"])
  }

  func testRowsAndColumns() throws {
    let table = try XCTUnwrap(
      PivotTable.calculate(
        headers: headers, records: records,
        definition: PivotDefinition(
          rows: [0], columns: [2], values: [.init(field: 3, aggregate: .sum)])))
    XCTAssertEqual(
      table.cells.map(texts),
      [
        ["Region", "Bike", "Helmet", "Grand Total"],
        ["East", "120", "40", "160"],
        ["north", "5", "", "5"],
        ["West", "100", "30", "130"],
        ["Grand Total", "225", "70", "295"],
      ])
  }

  func testFilterLeavesItemsOut() throws {
    let table = try XCTUnwrap(
      PivotTable.calculate(
        headers: headers, records: records,
        definition: PivotDefinition(
          rows: [1], values: [.init(field: 3, aggregate: .max)],
          filters: [.init(field: 0, hidden: ["East", "north"])])))
    XCTAssertEqual(
      table.cells.map(texts),
      [["Rep", "Max of Amount"], ["Ann", "100"], ["Di", ""], ["Grand Total", "100"]])
  }

  func testNumbersSortByValue() throws {
    let table = try XCTUnwrap(
      PivotTable.calculate(
        headers: ["Size", "Qty"],
        records: [
          [.number(10), .number(1)], [.number(9), .number(2)], [.string("big"), .number(3)],
        ],
        definition: PivotDefinition(rows: [0], values: [.init(field: 1, aggregate: .sum)])))
    XCTAssertEqual(table.cells.dropFirst().map { texts($0)[0] }, ["9", "10", "big", "Grand Total"])
  }

  func testNothingChosenGivesNil() {
    XCTAssertNil(
      PivotTable.calculate(headers: headers, records: records, definition: PivotDefinition()))
  }
}

final class PivotFileTests: XCTestCase {
  func testPivotSettingsSaveAndReopen() throws {
    var source = Sheet(name: "Sales Data")
    source.setCell(Cell(raw: "Region"), at: CellAddress(row: 0, col: 0))
    source.setCell(Cell(raw: "West"), at: CellAddress(row: 1, col: 0))
    var pivotSheet = Sheet(name: "Pivot 1")
    pivotSheet.setCell(Cell(raw: "Region"), at: CellAddress(row: 2, col: 0))
    let pivot = SheetPivot(
      name: "PivotTable1", sourceSheet: "Sales Data",
      sourceRange: CellRange(start: .origin, end: CellAddress(row: 1, col: 0)),
      anchor: CellAddress(row: 2, col: 0),
      definition: PivotDefinition(
        rows: [0], values: [.init(field: 0, aggregate: .count)],
        filters: [.init(field: 0, hidden: ["East"])]),
      drawnRows: 3, drawnColumns: 2)
    pivotSheet.fileExtras.sparkPivots = [pivot]
    let data = try XLSXCodec.exportWorkbook(Workbook(sheets: [source, pivotSheet]))
    XCTAssertNotNil(
      XLSXCodec.zipEntryData(archiveData: data, entryPath: "xl/sparkGrid/pivots2.json"))
    XCTAssertNil(XLSXCodec.zipEntryData(archiveData: data, entryPath: "xl/sparkGrid/pivots1.json"))
    let back = try XLSXCodec.importWorkbook(from: data)
    XCTAssertEqual(back.sheets[1].fileExtras.sparkPivots, [pivot])
    XCTAssertTrue(back.sheets[0].fileExtras.sparkPivots.isEmpty)
  }

  func testRenamingTheSourceSheetFollows() {
    var workbook = Workbook(sheets: [Sheet(name: "Data"), Sheet(name: "Pivot 1")])
    workbook.sheets[1].fileExtras.sparkPivots = [
      SheetPivot(
        name: "P", sourceSheet: "Data", sourceRange: CellRange(start: .origin, end: .origin),
        anchor: .origin, definition: PivotDefinition())
    ]
    let commands = WorkbookSession()
    let outcome = commands.apply(
      id: "sheet.rename", arguments: ["sheet": "Data", "name": "Sales"], to: &workbook)
    XCTAssertTrue(outcome.ok)
    XCTAssertEqual(workbook.sheets[1].fileExtras.sparkPivots.first?.sourceSheet, "Sales")
  }
}

final class PivotStructureTests: XCTestCase {
  func testInsertingRowsAboveMovesThePivot() {
    var sheet = Sheet(name: "Pivot 1")
    sheet.fileExtras.sparkPivots = [
      SheetPivot(
        name: "P", sourceSheet: "Data", sourceRange: CellRange(start: .origin, end: .origin),
        anchor: CellAddress(row: 2, col: 1), definition: PivotDefinition())
    ]
    SheetStructureMutation.insertRows(into: &sheet, at: 0, count: 2)
    XCTAssertEqual(sheet.fileExtras.sparkPivots.first?.anchor, CellAddress(row: 4, col: 1))
    SheetStructureMutation.deleteColumns(in: &sheet, at: 1, count: 1)
    XCTAssertTrue(sheet.fileExtras.sparkPivots.isEmpty)
  }
}

final class PivotDateGroupTests: XCTestCase {
  // 46023 is Jan 1 2026; 46113 is Apr 1 2026; 45658 is Jan 1 2025.
  func testDateGroupLabels() {
    XCTAssertEqual(PivotTable.dateGroup(serial: 46023, by: .year)?.label, "2026")
    XCTAssertEqual(PivotTable.dateGroup(serial: 46113, by: .quarter)?.label, "Q2 2026")
    XCTAssertEqual(PivotTable.dateGroup(serial: 46023.75, by: .month)?.label, "Jan 2026")
    XCTAssertEqual(PivotTable.dateGroup(serial: 46027, by: .day)?.label, "Jan 5, 2026")
    XCTAssertEqual(PivotTable.dateGroup(serial: 46120, by: .quarter)?.start, 46113)
  }

  func testMonthsGroupAndSortByDate() throws {
    let records: [[CellValue]] = [
      [.number(46113), .number(5)],  // Apr 1 2026
      [.number(46023), .number(1)],  // Jan 1 2026
      [.number(46030), .number(2)],  // Jan 8 2026
      [.number(45658), .number(7)],  // Jan 1 2025
      [.string("unknown"), .number(3)],
    ]
    let table = try XCTUnwrap(
      PivotTable.calculate(
        headers: ["Date", "Qty"], records: records,
        definition: PivotDefinition(
          rows: [0], values: [.init(field: 1, aggregate: .sum)], dateGroups: [0: .month])))
    let labels = table.cells.dropFirst().map { row -> String in
      if case .text(let t) = row[0] { return t }
      return ""
    }
    XCTAssertEqual(labels, ["Jan 2025", "Jan 2026", "Apr 2026", "unknown", "Grand Total"])
    XCTAssertEqual(table.cells[2][1], .number(3))
  }
}
