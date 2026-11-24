import Engine
import Foundation
import GridCore
import Model
import NumberFormat
import XCTest

/// A formula typed into a General cell takes the format Excel 16.115 gives it (asked by
/// AppleScript on Nov 18, 35 formulas): =DATE(...) a date, =PMT(...) money, =A1+1 A1's format.
@MainActor
final class FormulaAutoFormatTests: XCTestCase {
  private func session() -> WorkbookSession {
    var sheet = Sheet(name: "Sheet1")
    func put(_ row: Int, _ raw: String, _ code: String, _ kind: CellFormat.NumberFormat) {
      var format = CellFormat()
      format.numberFormat = kind
      format.formatCode = code
      sheet.setCell(Cell(raw: raw, format: format), at: CellAddress(row: row, col: 0))
    }
    put(0, "45000", "m/d/yyyy", .date)
    put(1, "1234.5", "$#,##0.00", .currency)
    put(2, "0.25", "0%", .percent)
    put(3, "0.5", "h:mm", .time)
    sheet.setCell(Cell(raw: "7"), at: CellAddress(row: 4, col: 0))
    return WorkbookSession(workbook: Workbook(sheets: [sheet]))
  }

  func testFormatsMatchExcel() {
    let money = "$#,##0.00_);[Red]($#,##0.00)"
    let excel: [(String, String?)] = [
      ("=DATE(2026,3,1)", "m/d/yy"), ("=TODAY()", "m/d/yy"), ("=NOW()", "m/d/yy h:mm"),
      ("=EDATE(A1,1)", nil), ("=EOMONTH(A1,0)", nil), ("=WORKDAY(A1,5)", nil),
      ("=DATEVALUE(\"3/1/2026\")", nil), ("=TIME(9,30,0)", "h:mm AM/PM"),
      ("=TIMEVALUE(\"9:30\")", nil), ("=PMT(0.05/12,360,200000)", money),
      ("=FV(0.05,10,-100)", money), ("=PV(0.05,10,-100)", money), ("=NPV(0.1,100,200)", money),
      ("=IPMT(0.05/12,1,360,200000)", money), ("=A1+1", "m/d/yyyy"), ("=A1", "m/d/yyyy"),
      ("=A2*2", nil), ("=SUM(A2,A2)", "$#,##0.00"), ("=A3*2", nil), ("=A4+A4", "h:mm"),
      ("=A5+A1", "m/d/yyyy"), ("=A1-A5", "m/d/yyyy"), ("=MAX(A1,A1)", nil), ("=YEAR(A1)", nil),
      ("=A2+A3", "$#,##0.00"), ("=ROUND(A2,0)", "$#,##0.00"), ("=IF(TRUE,A1,0)", nil),
      ("=A5*A2", nil), ("=DATEDIF(A1,A1+30,\"d\")", nil), ("=DAYS(A1+30,A1)", nil),
      ("=A1+A1", nil), ("=DOLLAR(5)", nil), ("=RATE(360,-1000,200000)", "0%"),
      ("=EFFECT(0.05,12)", nil), ("=SLN(1000,100,5)", money),
    ]
    let session = session()
    for (row, (formula, code)) in excel.enumerated() {
      _ = session.run(id: "cell.set", arguments: ["address": "C\(row + 1)", "raw": formula])
      let cell = session.workbook.activeSheet.cell(at: CellAddress(row: row, col: 2))
      XCTAssertEqual(cell.format?.formatCode, code, formula)
    }
  }

  /// A cell with a format of its own keeps it.
  func testOwnFormatStays() {
    let session = session()
    _ = session.run(id: "cell.set", arguments: ["address": "A3", "raw": "=DATE(2026,1,1)"])
    XCTAssertEqual(
      session.workbook.activeSheet.cell(at: CellAddress(row: 2, col: 0)).format?.formatCode, "0%")
  }
}
