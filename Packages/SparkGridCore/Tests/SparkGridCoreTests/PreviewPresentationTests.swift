import Calc
import Engine
import FileFormats
import Formula
import Foundation
import GridCore
import Model
import Rendering
import XCTest

/// The Finder preview shows what the grid shows: results for formulas a file saved without,
/// numbers on the right, and dark-mode text that follows a light fill.
final class PreviewPresentationTests: XCTestCase {
  private func address(_ a1: String) -> CellAddress {
    XLSXCodec.parseCellRange(a1)!.start
  }

  func testFormulasWithoutSavedResultsAreCalculated() throws {
    // A template saved before anything recalculated: its formulas carry no results.
    let book = WorkbookTemplate.invoice.makeWorkbook()
    let data = try XLSXCodec.exportWorkbook(book)
    let opened = try XLSXCodec.importWorkbook(from: data)
    let preview = PreviewPresentation.make(opened)
    XCTAssertFalse(preview.hasUncalculatedFormulas)
    XCTAssertEqual(preview.text(sheet: 0, at: address("E25")), "$1,015.20")
    XCTAssertEqual(preview.text(sheet: 0, at: address("E12")), "$340.00")
  }

  func testSavedResultsAreUsedWithoutCalculating() {
    var sheet = Sheet(name: "S")
    sheet.setCell(Cell(raw: "=1+1", importedFormulaResult: "7"), at: address("A1"))
    let preview = PreviewPresentation.make(Workbook(sheets: [sheet]))
    XCTAssertEqual(preview.text(sheet: 0, at: address("A1")), "7")
  }

  func testAlignmentAndColorsFollowTheGrid() {
    var sheet = Sheet(name: "S")
    let light = CodableColor(red: 0.9, green: 0.95, blue: 0.9, alpha: 1)
    sheet.setCell(
      Cell(raw: "Total", format: CellFormat(bold: true, fillColor: light)), at: address("A1"))
    sheet.setCell(Cell(raw: "42"), at: address("B1"))
    sheet.setCell(Cell(raw: "=1/0"), at: address("C1"))
    let preview = PreviewPresentation.make(Workbook(sheets: [sheet]))
    let total = preview.style(sheet: 0, at: address("A1"), darkMode: true)
    XCTAssertEqual(total.alignment, .left)
    XCTAssertTrue(total.bold)
    XCTAssertEqual(total.textColor, CodableColor(red: 0, green: 0, blue: 0, alpha: 1))
    XCTAssertNil(preview.style(sheet: 0, at: address("A1"), darkMode: false).textColor)
    XCTAssertEqual(preview.style(sheet: 0, at: address("B1"), darkMode: false).alignment, .right)
    let error = preview.style(sheet: 0, at: address("C1"), darkMode: false)
    XCTAssertTrue(error.isError)
    XCTAssertEqual(preview.text(sheet: 0, at: address("C1")), "#DIV/0!")
  }

  func testLargeUncalculatedWorkbooksAreLeftForTheApp() {
    var sheet = Sheet(name: "Big")
    var cells: [CellAddress: Cell] = [:]
    for row in 0...PreviewPresentation.maxFormulasToCalculate {
      cells[CellAddress(row: row, col: 0)] = Cell(raw: "=\(row)+1")
    }
    sheet.replaceCells(cells)
    let preview = PreviewPresentation.make(Workbook(sheets: [sheet]))
    XCTAssertTrue(preview.hasUncalculatedFormulas)
    XCTAssertEqual(preview.text(sheet: 0, at: CellAddress(row: 0, col: 0)), "")
  }
}
