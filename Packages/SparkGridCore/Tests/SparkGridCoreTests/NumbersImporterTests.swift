import Foundation
import GridCore
import Model
import NumberFormat
import XCTest

@testable import FileFormats

/// Numbers documents saved by Numbers 15.4 (made with its AppleScript, values checked against
/// its own Excel export): every table opens as a sheet with its values.
final class NumbersImporterTests: XCTestCase {
  private func fixture(_ name: String) -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("Fixtures/\(name)")
  }

  private func raw(_ sheet: Sheet, _ a1: String) -> String {
    sheet.cell(at: XLSXCodec.parseCellRange(a1)!.start).raw
  }

  func testTextNumbersAndFormulaResults() throws {
    let book = try NumbersImporter.importWorkbook(from: fixture("numbers-values.numbers"))
    XCTAssertEqual(book.sheets.map(\.name), ["Groceries"])
    let sheet = book.sheets[0]
    XCTAssertEqual(raw(sheet, "A1"), "Item")
    XCTAssertEqual(raw(sheet, "B2"), "3")
    XCTAssertEqual(raw(sheet, "C2"), "1.25")
    XCTAssertEqual(raw(sheet, "C3"), "0.8")
    // Formulas come in as formulas, showing the results Numbers saved.
    XCTAssertEqual(raw(sheet, "D2"), "=B2*C2")
    XCTAssertEqual(
      sheet.cell(at: XLSXCodec.parseCellRange("D2")!.start).cachedFormulaValue, .number(3.75))
    XCTAssertEqual(raw(sheet, "D4"), "=SUM(D2:D3)")
    XCTAssertEqual(
      sheet.cell(at: XLSXCodec.parseCellRange("D4")!.start).cachedFormulaValue, .number(7.75))
    XCTAssertEqual(raw(sheet, "C6"), "-42.5")
    XCTAssertEqual(raw(sheet, "A7"), "Café ünïcode")
    XCTAssertEqual(sheet.frozenRows, 1)
  }

  func testTablesDatesAndManyRows() throws {
    let book = try NumbersImporter.importWorkbook(from: fixture("numbers-tables.numbers"))
    // A sheet with two tables gives two sheets, named for the sheet and the table.
    XCTAssertEqual(book.sheets.map(\.name), ["Data", "Mixed - Table 1", "Mixed - Second"])
    let data = book.sheets[0]
    // 600 rows cross the 256-row tiles Numbers stores cells in.
    XCTAssertEqual(raw(data, "A601"), "600")
    XCTAssertEqual(raw(data, "A257"), "256")
    XCTAssertEqual(raw(data, "B601"), "=A601*A601")
    XCTAssertEqual(
      data.cell(at: XLSXCodec.parseCellRange("B601")!.start).cachedFormulaValue, .number(360_000))
    // =1/0: an error keeps no saved result, so Spark Grid works it out (#DIV/0!).
    XCTAssertEqual(raw(data, "C2"), "=1/0")
    XCTAssertNil(data.cell(at: XLSXCodec.parseCellRange("C2")!.start).importedFormulaResult)
    let mixed = book.sheets[1]
    XCTAssertEqual(raw(mixed, "A2"), "46084")  // March 3, 2026
    XCTAssertEqual(
      mixed.cell(at: XLSXCodec.parseCellRange("A2")!.start).format?.numberFormat, .date)
    XCTAssertEqual(raw(mixed, "A3"), "46381.604166666664")  // Dec 25, 2026, 2:30 PM
    XCTAssertEqual(raw(mixed, "B2"), "0.075")
    XCTAssertEqual(raw(mixed, "C2"), "1234.5")
    XCTAssertEqual(
      mixed.cell(at: XLSXCodec.parseCellRange("C2")!.start).format?.numberFormat, .currency)
    XCTAssertEqual(raw(mixed, "D2"), "TRUE")
    XCTAssertEqual(raw(mixed, "E2"), "0.0625")  // 1 hour 30 minutes
    XCTAssertEqual(raw(book.sheets[2], "A2"), "99")
    // Formats as Numbers shows them.
    func code(_ a1: String) -> String? {
      mixed.cell(at: XLSXCodec.parseCellRange(a1)!.start).format?.formatCode
    }
    XCTAssertEqual(code("A2"), "m/d/yyyy")
    XCTAssertEqual(code("A3"), "m/d/yyyy h:mm AM/PM")
    XCTAssertEqual(code("B2"), "0.0%")
    XCTAssertEqual(code("C2"), "\"$\"#,##0.00")
    XCTAssertEqual(code("E2"), "[h]:mm:ss")
  }

  func testOtherFilesAreRefused() {
    XCTAssertThrowsError(
      try NumbersImporter.importWorkbook(fromArchiveData: Data("not a zip".utf8)))
    XCTAssertThrowsError(try NumbersImporter.importWorkbook(from: fixture("excel-pivots.xlsx")))
  }

  func testSnappyCopiesThatOverlap() throws {
    // "abcabcabca": three literal bytes, then a copy of 7 from 3 back that reads what it writes.
    let compressed: [UInt8] = [10, 0x08, 0x61, 0x62, 0x63, 0x0D, 0x03]
    var out: [UInt8] = []
    try NumbersArchive.snappyDecompress(compressed[...], into: &out)
    XCTAssertEqual(String(decoding: out, as: UTF8.self), "abcabcabca")
  }

  func testSheetNamesOtherAppsAccept() {
    XCTAssertEqual(NumbersImporter.uniqueName("Q1: Plan/Actual", taken: []), "Q1 PlanActual")
    XCTAssertEqual(NumbersImporter.uniqueName("Data", taken: ["data"]), "Data (2)")
    XCTAssertEqual(
      NumbersImporter.uniqueName(String(repeating: "x", count: 40), taken: []).count, 31)
  }
}
