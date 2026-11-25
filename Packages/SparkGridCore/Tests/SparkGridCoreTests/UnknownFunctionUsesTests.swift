import Calc
import FileFormats
import GridCore
import Model
import XCTest

/// The open-time warning lists the functions a workbook calls that Spark Grid cannot calculate,
/// and leaves out its own names and LET's.
final class UnknownFunctionUsesTests: XCTestCase {
  func testListsUnknownFunctionsMostUsedFirst() {
    var sheet = Sheet(name: "Data")
    let formulas = [
      "=SUM(1,2)", "=CUBEVALUE(\"Sales\",\"[Year].[2026]\")*2", "=CUBEVALUE(\"Sales\")",
      "=WEBSERVICE(\"https://example.com\")", "=Hyp(3,4)", "=LET(f,LAMBDA(x,x*2),f(5))",
      "=A1+1",
    ]
    for (row, raw) in formulas.enumerated() {
      sheet.setCell(Cell(raw: raw), at: CellAddress(row: row, col: 0))
    }
    var book = Workbook(sheets: [Sheet(name: "Empty"), sheet])
    book.namedRanges["HYP"] = NamedRange(
      formulaName: "Hyp", refersTo: "LAMBDA(a,b,SQRT(a^2+b^2))", sheetName: "Data")

    let uses = UnknownFunctions.uses(in: book)
    XCTAssertEqual(uses.map(\.name), ["CUBEVALUE", "WEBSERVICE"])
    XCTAssertEqual(uses[0].cells, 2)
    XCTAssertEqual(uses[0].sheet, "Data")
    XCTAssertEqual(uses[0].address, CellAddress(row: 1, col: 0))
  }

  func testNothingToReport() {
    var sheet = Sheet(name: "S")
    sheet.setCell(Cell(raw: "=XLOOKUP(1,A2:A3,B2:B3)"), at: .origin)
    XCTAssertTrue(UnknownFunctions.uses(in: Workbook(sheets: [sheet])).isEmpty)
  }

  /// A file to try the warning by hand:
  /// SPARK_GRID_UNKNOWN_OUT=/path/file.xlsx swift test --filter testWriteSampleFile
  func testWriteSampleFile() throws {
    guard let out = ProcessInfo.processInfo.environment["SPARK_GRID_UNKNOWN_OUT"] else {
      throw XCTSkip("Set SPARK_GRID_UNKNOWN_OUT to write the sample file.")
    }
    var sheet = Sheet(name: "Report")
    sheet.setCell(Cell(raw: "Sales"), at: .origin)
    sheet.setCell(
      Cell(
        raw: "=CUBEVALUE(\"Sales\",\"[2026]\")", importedFormulaResult: "1200",
        importedFormulaValueType: .number), at: CellAddress(row: 0, col: 1))
    sheet.setCell(
      Cell(
        raw: "=CUBEVALUE(\"Sales\",\"[2025]\")", importedFormulaResult: "900",
        importedFormulaValueType: .number), at: CellAddress(row: 1, col: 1))
    sheet.setCell(Cell(raw: "=B1-B2"), at: CellAddress(row: 2, col: 1))
    sheet.setCell(
      Cell(
        raw: "=WEBSERVICE(\"https://example.com/rate\")", importedFormulaResult: "1.08",
        importedFormulaValueType: .number), at: CellAddress(row: 4, col: 1))
    try XLSXCodec.exportWorkbook(Workbook(sheets: [sheet]), includeFormulaCaches: true)
      .write(to: URL(fileURLWithPath: out))
  }
}
