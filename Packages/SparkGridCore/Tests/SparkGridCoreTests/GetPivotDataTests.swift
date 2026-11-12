import Calc
import GridCore
import Model
import XCTest

final class GetPivotDataTests: XCTestCase {
  /// A pivot drawn at A3 by Region (rows) and Product (columns), Sum of Amount.
  private func pivotSheet(formulas: [(String, String)]) -> Sheet {
    var sheet = Sheet(name: "Pivot 1")
    let grid: [[String]] = [
      ["Region", "Bike", "Helmet", "Grand Total"],
      ["East", "120", "40", "160"],
      ["West", "100", "30", "130"],
      ["Grand Total", "220", "70", "290"],
    ]
    for (r, row) in grid.enumerated() {
      for (c, value) in row.enumerated() {
        sheet.setCell(Cell(raw: value), at: CellAddress(row: 2 + r, col: c))
      }
    }
    for (index, (_, formula)) in formulas.enumerated() {
      sheet.setCell(Cell(raw: formula), at: CellAddress(row: index, col: 6))
    }
    sheet.fileExtras.sparkPivots = [
      SheetPivot(
        name: "PivotTable1", sourceSheet: "Sales",
        sourceRange: CellRange(start: .origin, end: CellAddress(row: 5, col: 3)),
        anchor: CellAddress(row: 2, col: 0),
        definition: PivotDefinition(
          rows: [0], columns: [2], values: [.init(field: 3, aggregate: .sum)]),
        drawnRows: 4, drawnColumns: 4,
        fieldNames: ["Region", "Rep", "Product", "Amount"])
    ]
    return sheet
  }

  private let cases: [(String, String)] = [
    ("grand", #"=GETPIVOTDATA("Sum of Amount",$A$3)"#),
    ("row", #"=GETPIVOTDATA("Amount",$A$3,"Region","West")"#),
    ("cell", #"=GETPIVOTDATA("Sum of Amount",B4,"region","east","Product","Helmet")"#),
    ("column", #"=GETPIVOTDATA("Sum of Amount",A3,"Product","Bike")"#),
    ("missing", #"=GETPIVOTDATA("Sum of Amount",A3,"Region","North")"#),
    ("not a pivot", #"=GETPIVOTDATA("Sum of Amount",H20)"#),
  ]
  private let expected: [CellValue] = [
    .number(290), .number(130), .number(40), .number(220), .error(.ref), .error(.ref),
  ]

  func testReadsTheDrawnTable() {
    let sheet = pivotSheet(formulas: cases)
    let engine = FormulaEngine()
    engine.rebuild(workbook: Workbook(sheets: [sheet]), recalculate: false)
    for (index, want) in expected.enumerated() {
      let got = engine.sheetDisplayValue(at: CellAddress(row: index, col: 6), sheet: sheet)
      XCTAssertEqual(got, want, cases[index].0)
    }
  }

  func testWholeWorkbookPassAgrees() {
    let sheet = pivotSheet(formulas: cases)
    let engine = FormulaEngine()
    engine.recalculateEntireWorkbook(Workbook(sheets: [sheet]), profile: false)
    let results = engine.formulaResults(on: sheet)
    for (index, want) in expected.enumerated() {
      XCTAssertEqual(results[CellAddress(row: index, col: 6)], want, cases[index].0)
    }
  }

  func testRedrawnCellsRecalculate() {
    var sheet = pivotSheet(formulas: cases)
    let engine = FormulaEngine()
    engine.rebuild(workbook: Workbook(sheets: [sheet]), recalculate: false)
    let west = CellAddress(row: 1, col: 6)
    XCTAssertEqual(engine.sheetDisplayValue(at: west, sheet: sheet), .number(130))
    let total = CellAddress(row: 4, col: 3)
    sheet.setCell(Cell(raw: "175"), at: total)
    _ = engine.cellsDidChange([total], sheet: sheet)
    XCTAssertEqual(engine.sheetDisplayValue(at: west, sheet: sheet), .number(175))
  }
}
