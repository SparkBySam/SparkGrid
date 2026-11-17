import Calc
import Engine
import FileFormats
import Formula
import Foundation
import GridCore
import Model
import XCTest

/// Every start screen template calculates without an error value, and saves and opens again.
final class WorkbookTemplateTests: XCTestCase {
  /// A fixed day, a Wednesday, so the dates are the same on every run.
  private let day: Date = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c.date(from: DateComponents(year: 2026, month: 11, day: 18))!
  }()

  private var calendar: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
  }

  private func results(_ workbook: Workbook) -> [CellAddress: CellValue] {
    let engine = FormulaEngine()
    engine.recalculateEntireWorkbook(workbook)
    return engine.formulaResults(on: workbook.sheets[0])
  }

  private func value(_ results: [CellAddress: CellValue], _ a1: String) -> CellValue? {
    results[XLSXCodec.parseCellRange(a1)!.start]
  }

  func testTenTemplatesInThreeCategories() {
    XCTAssertEqual(WorkbookTemplate.allCases.count, 10)
    for category in WorkbookTemplate.Category.allCases {
      XCTAssertFalse(WorkbookTemplate.allCases.filter { $0.category == category }.isEmpty)
    }
  }

  func testEveryFormulaCalculates() {
    for template in WorkbookTemplate.allCases {
      let book = template.makeWorkbook(today: day, calendar: calendar)
      XCTAssertEqual(book.sheets.first?.name, template.name)
      let formulas = book.sheets[0].cells.filter { FormulaSyntax.isFormula($0.value.raw) }
      XCTAssertFalse(formulas.isEmpty, template.name)
      let values = results(book)
      for (address, cell) in formulas {
        let result = values[address]
        XCTAssertFalse(
          result?.isError ?? false,
          "\(template.name) \(address.a1) \(cell.raw) gave \(String(describing: result))")
      }
    }
  }

  func testTheSampleNumbersAddUp() {
    let budget = results(
      WorkbookTemplate.monthlyBudget.makeWorkbook(today: day, calendar: calendar))
    XCTAssertEqual(value(budget, "C8"), .number(4650))
    XCTAssertEqual(value(budget, "C20"), .number(3582))
    XCTAssertEqual(value(budget, "C22"), .number(1068))

    let invoice = results(WorkbookTemplate.invoice.makeWorkbook(today: day, calendar: calendar))
    XCTAssertEqual(value(invoice, "E23"), .number(940))
    XCTAssertEqual(value(invoice, "E25"), .number(1015.2))

    let loan = results(WorkbookTemplate.loanCalculator.makeWorkbook(today: day, calendar: calendar))
    guard case .number(let payment)? = value(loan, "E3") else { return XCTFail("no payment") }
    XCTAssertEqual(payment, 489.15, accuracy: 0.01)
    // The schedule ends after the 60th payment, at zero.
    XCTAssertEqual(value(loan, "A69"), .number(60))
    XCTAssertEqual(value(loan, "A70"), .string(""))
    guard case .number(let last)? = value(loan, "G69") else { return XCTFail("no balance") }
    XCTAssertEqual(last, 0, accuracy: 0.05)

    let time = results(WorkbookTemplate.timesheet.makeWorkbook(today: day, calendar: calendar))
    XCTAssertEqual(value(time, "A8"), .string("Monday"))
    XCTAssertEqual(value(time, "F16"), .number(39.75))
    XCTAssertEqual(value(time, "F19"), .number(874.5))

    let pipeline = results(
      WorkbookTemplate.salesPipeline.makeWorkbook(today: day, calendar: calendar))
    XCTAssertEqual(value(pipeline, "H3"), .number(15000))
    XCTAssertEqual(value(pipeline, "F7"), .number(0.5))

    let stock = results(WorkbookTemplate.inventory.makeWorkbook(today: day, calendar: calendar))
    XCTAssertEqual(value(stock, "H3"), .number(3))
  }

  func testTemplatesSaveAndOpenAgain() throws {
    for template in WorkbookTemplate.allCases {
      let book = template.makeWorkbook(today: day, calendar: calendar)
      let data = try XLSXCodec.exportWorkbook(book)
      let back = try XLSXCodec.importWorkbook(from: data)
      let sheet = back.sheets[0]
      XCTAssertEqual(sheet.name, template.name)
      for (address, cell) in book.sheets[0].cells where !cell.raw.isEmpty {
        // Opening keeps the prefix saved files give newer functions (a separate fix).
        let opened = sheet.cell(at: address).raw.replacingOccurrences(of: "_xlfn.", with: "")
        XCTAssertEqual(opened, cell.raw, "\(template.name) \(address.a1)")
      }
      XCTAssertEqual(
        sheet.fileExtras.dataValidations.count, book.sheets[0].fileExtras.dataValidations.count,
        template.name)
      XCTAssertEqual(
        sheet.conditionalFormats.count, book.sheets[0].conditionalFormats.count, template.name)
      XCTAssertEqual(sheet.frozenRows, book.sheets[0].frozenRows, template.name)
    }
  }
}
