import Foundation
import GridCore
import Model
import XCTest

@testable import Calc
@testable import FileFormats
@testable import Formula

/// SEM and the MEAN names calculate in Spark Grid, save as formulas other apps calculate the same
/// way, and come back as typed.
final class SparkOnlyFunctionTests: XCTestCase {
  func testExcelForm() {
    XCTAssertEqual(
      SparkOnlyFunctions.excelForm("SEM(B2:B9)"), "(STDEV.S(B2:B9)/SQRT(COUNT(B2:B9)))")
    XCTAssertEqual(
      SparkOnlyFunctions.excelForm("ROUND(sem(A1:A4,C1),2)+MEAN.geom(A1:A4)"),
      "ROUND((STDEV.S(A1:A4,C1)/SQRT(COUNT(A1:A4,C1))),2)+GEOMEAN(A1:A4)")
    XCTAssertEqual(
      SparkOnlyFunctions.excelForm("MEAN(MEAN.HARM(A1:A2),3)"), "AVERAGE(HARMEAN(A1:A2),3)")
    // Strings, sheet names and longer names are left alone.
    XCTAssertEqual(
      SparkOnlyFunctions.excelForm(#""MEAN(1)"&'SEM(x'!A1&MEANING(1)&X.SEM(2)"#),
      #""MEAN(1)"&'SEM(x'!A1&MEANING(1)&X.SEM(2)"#)
    XCTAssertTrue(SparkOnlyFunctions.uses("=1+sem(A1:A3)"))
    XCTAssertFalse(SparkOnlyFunctions.uses("=SEMESTER(1)+\"SEM(\""))
  }

  func testCalculatesLikeItsExcelForm() {
    var sheet = Sheet(name: "Data")
    for (row, value) in ["2", "4", "4", "4", "5", "5", "7", "9"].enumerated() {
      sheet.setCell(Cell(raw: value), at: CellAddress(row: row, col: 0))
    }
    let formulas = [
      "=SEM(A1:A8)", "=(STDEV.S(A1:A8)/SQRT(COUNT(A1:A8)))", "=MEAN(A1:A8)", "=MEAN.ARITH(A1:A8)",
      "=MEAN.GEOM(A1:A8)", "=GEOMEAN(A1:A8)", "=MEAN.HARM(A1:A8)", "=HARMEAN(A1:A8)",
    ]
    for (row, formula) in formulas.enumerated() {
      sheet.setCell(Cell(raw: formula), at: CellAddress(row: row, col: 1))
    }
    let engine = FormulaEngine()
    engine.rebuild(workbook: Workbook(sheets: [sheet]), recalculate: false)
    func value(_ row: Int) -> CellValue {
      engine.sheetDisplayValue(at: CellAddress(row: row, col: 1), sheet: sheet)
    }
    guard case .number(let sem) = value(0) else { return XCTFail("SEM \(value(0))") }
    XCTAssertEqual(sem, 2.138089935 / 8.0.squareRoot(), accuracy: 1e-9)
    XCTAssertEqual(value(0), value(1))
    XCTAssertEqual(value(2), .number(5))
    XCTAssertEqual(value(3), .number(5))
    XCTAssertEqual(value(4), value(5))
    XCTAssertEqual(value(6), value(7))
  }

  func testSavesTheExcelFormAndReopensAsTyped() throws {
    var sheet = Sheet(name: "Data")
    sheet.setCell(Cell(raw: "3"), at: CellAddress(row: 0, col: 0))
    sheet.setCell(Cell(raw: "5"), at: CellAddress(row: 1, col: 0))
    sheet.setCell(Cell(raw: "=SEM(A1:A2)"), at: CellAddress(row: 0, col: 1))
    sheet.setCell(Cell(raw: "=Mean(A1:A2)*2"), at: CellAddress(row: 1, col: 1))
    let data = try XLSXCodec.exportWorkbook(Workbook(sheets: [sheet]))
    if let out = ProcessInfo.processInfo.environment["SPARK_GRID_SEM_OUT"] {
      try data.write(to: URL(fileURLWithPath: out))
    }
    let xml =
      XLSXCodec.zipEntryString(archiveData: data, entryPath: "xl/worksheets/sheet1.xml") ?? ""
    XCTAssertTrue(xml.contains("<f>(_xlfn.STDEV.S(A1:A2)/SQRT(COUNT(A1:A2)))</f>"), xml)
    XCTAssertTrue(xml.contains("<f>AVERAGE(A1:A2)*2</f>"))
    let reopened = try XLSXCodec.importWorkbook(from: data).sheets[0]
    XCTAssertEqual(reopened.cell(at: CellAddress(row: 0, col: 1)).raw, "=SEM(A1:A2)")
    XCTAssertEqual(reopened.cell(at: CellAddress(row: 1, col: 1)).raw, "=Mean(A1:A2)*2")
  }
}
