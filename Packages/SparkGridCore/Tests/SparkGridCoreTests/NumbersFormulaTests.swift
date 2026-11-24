import Calc
import Foundation
import GridCore
import Model
import XCTest

@testable import FileFormats

/// Numbers formulas come in as Spark Grid formulas: two files of formulas typed in Numbers 15.4,
/// checked against Numbers' own Excel export, and recalculated to the results Numbers saved.
final class NumbersFormulaTests: XCTestCase {
  private func book(_ name: String) throws -> Workbook {
    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("Fixtures/\(name)")
    return try NumbersImporter.importWorkbook(from: url)
  }

  private func formulas(_ sheet: Sheet) -> [String] {
    (3..<60).compactMap { row in
      let raw = sheet.cell(at: CellAddress(row: row, col: 2)).raw
      return raw.isEmpty ? nil : raw
    }
  }

  func testFormulasAsTyped() throws {
    let calc = try book("numbers-formulas.numbers").sheets[0]
    XCTAssertEqual(
      formulas(calc),
      [
        "=A2+B2", "=A2-B2*2", "=(A2+B2)/2", "=A2^2", "=-A2", #"=A2&"x""#, "=A2>B2", "=A2<>B2",
        // A whole column is the table below its header row, as Numbers' own export writes it.
        "=SUM(A2:B2)", "=SUM(A2:A39)", "=$A$2*B2", "=A$2+$B2", "=AVERAGE(A2,B2,10)",
        #"=IF(A2>B2,"big","small")"#, "=ROUND(A2/7,2)", "=COUNT(A2:B3)", "=MAX(A2:B3)",
        "=MIN(A2:B3)", "=VLOOKUP(5,A2:B3,2,FALSE)", #"=CONCATENATE("a","b")"#, #"=LEN("hello")"#,
        "=TODAY()", "=DATE(2026,3,4)",
        // Typed before the sheet it names existed, so Numbers saved it as a broken reference.
        "=#REF!*2",
        "=50%", "=A2*1500", "=TRUE", #"=IFERROR(1/0,"none")"#, #"=SUMIF(A2:A3,">1")"#,
        "=INDEX(A2:B3,2,1)", "=PMT(0.05/12,60,-10000)", "=ABS(-3)", "=AND(TRUE,FALSE)",
        #"=UPPER("abc")"#, "=A2%",
      ])
  }

  func testReferencesToRangesTablesAndSheets() throws {
    let workbook = try book("numbers-references.numbers")
    XCTAssertEqual(workbook.sheets.map(\.name), ["Main - Table 1", "Main - Rates", "Other"])
    XCTAssertEqual(
      formulas(workbook.sheets[0]),
      [
        // A whole row leaves out the header column; Numbers saved 11, not 18.
        "=SUM($A$2:$B$3)", "=SUM($A2:B$3)", "=SUM(B2:G3)", "=SUM('Main - Rates'!A1:A2)",
        "='Main - Rates'!A1*10", "=Other!A1+1", "=SUM(Other!A1:A2)", "=COUNT(A2:A20)", "=A2>=B2",
        "=A2<=B2", "=A2=B2", "=A2<B2", "=+A2", #"="say ""hi""""#, "=IF(A2>1,,2)",
        "=XLOOKUP(5,A2:A3,B2:B3)",
      ])
  }

  /// Spark Grid's own calculation of every imported formula gives the result Numbers saved.
  func testSparkGridCalculatesWhatNumbersSaved() throws {
    for name in ["numbers-formulas.numbers", "numbers-references.numbers"] {
      let workbook = try book(name)
      let engine = FormulaEngine()
      engine.recalculateEntireWorkbook(workbook, profile: false)
      for sheet in workbook.sheets {
        let results = engine.formulaResults(on: sheet)
        for (address, cell) in sheet.cells where cell.raw.hasPrefix("=") {
          // TODAY changes; an error keeps no saved result.
          guard let saved = cell.cachedFormulaValue, !cell.raw.contains("TODAY") else { continue }
          let ours = results[address] ?? .blank
          switch (saved, ours) {
          case (.number(let a), .number(let b)):
            XCTAssertEqual(a, b, accuracy: 1e-9, "\(name) \(address.a1) \(cell.raw)")
          default:
            XCTAssertEqual(saved, ours, "\(name) \(address.a1) \(cell.raw)")
          }
        }
      }
    }
  }

  func testUnknownFunctionsKeepTheValue() {
    // Function 9999 is not one Numbers has; the cell keeps the result instead.
    var node = Data([0x08, 16, 0x10])
    node.append(contentsOf: [0xCF, 0x4E, 0x18, 0])
    let nodes = [ProtoMessage(node)]
    let table = NumbersFormula.Table(
      sheetName: "S", rows: 10, columns: 4, headerRows: 1, headerColumns: 0)
    XCTAssertNil(NumbersFormula.text(nodes, host: .origin, table: table, tables: [:]))
  }
}
