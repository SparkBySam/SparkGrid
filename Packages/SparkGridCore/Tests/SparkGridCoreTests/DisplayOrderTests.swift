import GridCore
import Model
import XCTest

@testable import Calc

/// Month columns count a label inside a one-day window (`COLUMN()` plus `DATE`).
/// A total visited before those columns has to land on the same counts as a
/// top-to-bottom paint.
@MainActor
final class DisplayOrderTests: XCTestCase {
  func testDayWindowCountsMatchWhenTheColumnTotalIsVisitedFirst() {
    let workbook = dayWindowWorkbook()
    let paint = displayed(workbook: workbook, order: paintOrder)
    let totalFirst = displayed(workbook: workbook, order: columnTotalFirst)

    let dayOne = CellAddress(row: 5, col: 19)
    let dayTwo = CellAddress(row: 5, col: 20)
    let total = CellAddress(row: 8, col: 19)
    XCTAssertEqual(paint[dayOne], .number(1))
    XCTAssertEqual(paint[dayTwo], .number(1))
    XCTAssertEqual(paint[total], .number(1))
    XCTAssertEqual(totalFirst[dayOne], paint[dayOne])
    XCTAssertEqual(totalFirst[dayTwo], paint[dayTwo])
    XCTAssertEqual(totalFirst[total], paint[total])
  }

  func testDayWindowCountsMatchWhenTheRowTotalIsVisitedFirst() {
    let workbook = dayWindowWorkbook()
    let paint = displayed(workbook: workbook, order: paintOrder)
    let totalFirst = displayed(workbook: workbook, order: rowTotalFirst)

    let dayOne = CellAddress(row: 5, col: 19)
    let dayThree = CellAddress(row: 5, col: 21)
    let total = CellAddress(row: 5, col: 24)
    XCTAssertEqual(paint[dayOne], .number(1))
    XCTAssertEqual(paint[dayThree], .number(0))
    XCTAssertEqual(paint[total], .number(2))
    XCTAssertEqual(totalFirst[dayOne], paint[dayOne])
    XCTAssertEqual(totalFirst[dayThree], paint[dayThree])
    XCTAssertEqual(totalFirst[total], paint[total])
  }

  /// A sheet switch keeps calculated values and drops parsed formulas. The total
  /// then reads the day window, which reads `$R6` and calculates R6 again inside
  /// the count. The count's `COLUMN()` must stay on its own column.
  func testDayWindowCountsMatchAfterASheetSwitch() {
    var workbook = dayWindowWorkbook()
    workbook.sheets.append(Sheet(name: "May", cells: [:]))
    let paint = displayed(workbook: workbook, order: paintOrder)

    let label = CellAddress(row: 5, col: 17)
    let dayOne = CellAddress(row: 5, col: 19)
    let total = CellAddress(row: 8, col: 19)
    let engine = FormulaEngine()
    engine.rebuild(workbook: workbook, recalculate: false)
    let april = workbook.sheets[0]
    _ = engine.sheetDisplayValue(at: label, sheet: april)
    workbook.activeSheetIndex = 1
    engine.activateSheet(workbook)
    workbook.activeSheetIndex = 0
    engine.activateSheet(workbook)

    XCTAssertEqual(paint[dayOne], .number(1))
    XCTAssertEqual(engine.sheetDisplayValue(at: total, sheet: april), paint[total])
    XCTAssertEqual(engine.sheetDisplayValue(at: dayOne, sheet: april), paint[dayOne])
  }

  /// Excel columns T–V are one day apart via `COLUMN()-19`. Row 9 totals column T.
  /// Column Y totals the three day windows on row 6.
  private func dayWindowWorkbook() -> Workbook {
    var cells: [CellAddress: Cell] = [:]
    cells[CellAddress(row: 5, col: 0)] = Cell(raw: "alpha")
    cells[CellAddress(row: 6, col: 0)] = Cell(raw: "beta")
    cells[CellAddress(row: 5, col: 17)] = Cell(raw: "=A6")
    cells[CellAddress(row: 6, col: 17)] = Cell(raw: "=A7")

    let window =
      "=COUNTIFS($C$10:$C$12,$R6,$B$10:$B$12,\">=\"&DATE(2026,4,COLUMN()-19),$B$10:$B$12,\"<\"&DATE(2026,4,COLUMN()-19)+1)"
    let windowNextRow =
      "=COUNTIFS($C$10:$C$12,$R7,$B$10:$B$12,\">=\"&DATE(2026,4,COLUMN()-19),$B$10:$B$12,\"<\"&DATE(2026,4,COLUMN()-19)+1)"
    for col in 19...21 {
      cells[CellAddress(row: 5, col: col)] = Cell(raw: window)
      cells[CellAddress(row: 6, col: col)] = Cell(raw: windowNextRow)
    }
    cells[CellAddress(row: 8, col: 19)] = Cell(raw: "=SUM(T6:T7)")
    cells[CellAddress(row: 5, col: 24)] = Cell(raw: "=SUM(T6:V6)")

    // April 1, April 1, April 2. Only the alpha rows fall in the day windows.
    let april1 = excelSerial(year: 2026, month: 4, day: 1)
    let april2 = excelSerial(year: 2026, month: 4, day: 2)
    cells[CellAddress(row: 9, col: 1)] = Cell(raw: format(april1))
    cells[CellAddress(row: 10, col: 1)] = Cell(raw: format(april1))
    cells[CellAddress(row: 11, col: 1)] = Cell(raw: format(april2))
    cells[CellAddress(row: 9, col: 2)] = Cell(raw: "alpha")
    cells[CellAddress(row: 10, col: 2)] = Cell(raw: "other")
    cells[CellAddress(row: 11, col: 2)] = Cell(raw: "alpha")

    return Workbook(sheets: [Sheet(name: "April", cells: cells)])
  }

  private var paintOrder: [CellAddress] {
    [
      CellAddress(row: 5, col: 17),
      CellAddress(row: 5, col: 19),
      CellAddress(row: 5, col: 20),
      CellAddress(row: 5, col: 21),
      CellAddress(row: 5, col: 24),
      CellAddress(row: 6, col: 17),
      CellAddress(row: 6, col: 19),
      CellAddress(row: 6, col: 20),
      CellAddress(row: 6, col: 21),
      CellAddress(row: 8, col: 19),
    ]
  }

  private var columnTotalFirst: [CellAddress] {
    [CellAddress(row: 8, col: 19)] + paintOrder.filter { $0 != CellAddress(row: 8, col: 19) }
  }

  private var rowTotalFirst: [CellAddress] {
    [CellAddress(row: 5, col: 24)] + paintOrder.filter { $0 != CellAddress(row: 5, col: 24) }
  }

  private func displayed(workbook: Workbook, order: [CellAddress]) -> [CellAddress: CellValue] {
    let engine = FormulaEngine()
    engine.rebuild(workbook: workbook, recalculate: false)
    let sheet = workbook.sheets[0]
    var values: [CellAddress: CellValue] = [:]
    for address in order {
      values[address] = engine.sheetDisplayValue(at: address, sheet: sheet)
    }
    return values
  }

  private func excelSerial(year: Int, month: Int, day: Int) -> Double {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    let date = Calendar.current.date(from: components) ?? Date()
    return ExcelDate.serial(from: date)
  }

  private func format(_ number: Double) -> String {
    if number.rounded() == number {
      return String(Int(number))
    }
    return String(number)
  }
}
