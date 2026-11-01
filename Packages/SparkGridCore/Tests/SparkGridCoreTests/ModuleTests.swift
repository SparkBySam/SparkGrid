import FileFormats
import Formula
import GridCore
import Model
import NumberFormat
import XCTest

@testable import Engine

@MainActor
final class ModuleTests: XCTestCase {
  func testFormulaParserReadsAddition() throws {
    let expr = try FormulaParser.parse("=1+2")
    XCTAssertEqual(expr, .binary(.add, .number(1), .number(2)))
  }

  func testNumberFormatKindAndCode() {
    XCTAssertEqual(ExcelFormatCode.numberFormatKind(for: "0.00"), .number)
    XCTAssertEqual(ExcelFormatCode.formatted(1.5, code: "0.00", fractionDigits: nil), "1.50")
  }

  func testCSVRoundTripKeepsText() {
    var sheet = Sheet(name: "Sheet1")
    sheet.setCell(Cell(raw: "hello"), at: .origin)
    let csv = CSVCodec.exportCSV(from: sheet)
    let cells = CSVCodec.importCSV(csv)
    XCTAssertEqual(cells[CellAddress.origin]?.raw, "hello")
  }

  @MainActor
  func testXLSXRoundTripKeepsFormulaAndCache() throws {
    var sheet = Sheet(name: "Sheet1")
    var formula = Cell(raw: "=1+2")
    formula.importedFormulaResult = "3"
    formula.importedFormulaValueType = .number
    formula.format = CellFormat(bold: true, numberFormat: .number)
    sheet.setCell(formula, at: .origin)
    let workbook = Workbook(sheets: [sheet])
    let data = try XLSXCodec.exportWorkbook(workbook, includeFormulaCaches: true)
    let imported = try XLSXCodec.importWorkbook(from: data)
    let cell = imported.sheets[0].cell(at: .origin)
    XCTAssertEqual(cell.raw, "=1+2")
    XCTAssertEqual(cell.importedFormulaResult, "3")
    XCTAssertEqual(cell.format?.bold, true)
    XCTAssertEqual(cell.format?.numberFormat, .number)
  }

  func testAnswerTokensMatchValues() {
    XCTAssertEqual(AnswerValues.parseToken("n:18"), .number(18))
    XCTAssertEqual(AnswerValues.parseToken("s:Tools"), .string("Tools"))
    XCTAssertEqual(AnswerValues.parseToken("b:TRUE"), .bool(true))
    XCTAssertEqual(AnswerValues.parseToken("e:#N/A"), .error(.na))
    XCTAssertEqual(AnswerValues.parseToken("blank"), .blank)
    XCTAssertTrue(AnswerValues.same(.bool(true), .number(1)))
    XCTAssertTrue(AnswerValues.same(.error(.arrayResult), .error(.value)))
    XCTAssertFalse(AnswerValues.same(.number(2), .number(3)))
  }
}
