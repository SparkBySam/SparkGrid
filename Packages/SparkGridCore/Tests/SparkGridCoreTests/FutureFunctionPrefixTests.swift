import Foundation
import GridCore
import Model
import XCTest

@testable import FileFormats

/// Files store newer functions as `_xlfn.XLOOKUP(` and spill references as
/// `_xlfn.ANCHORARRAY(G1)`. Opened, formulas read as typed; saved, the file gets the prefixes back.
final class FutureFunctionPrefixTests: XCTestCase {
  func testUnprefixedRemovesWhatSavingAdds() {
    XCTAssertEqual(
      ExcelFutureFunctions.unprefixed(#"IF(D7="","",_xlfn.XLOOKUP(D7,B1:B3,C1:C3,0))"#),
      #"IF(D7="","",XLOOKUP(D7,B1:B3,C1:C3,0))"#)
    XCTAssertEqual(
      ExcelFutureFunctions.unprefixed("=_xlfn._xlws.SORT(_xlfn.UNIQUE(A1:A9))"),
      "=SORT(UNIQUE(A1:A9))")
    XCTAssertEqual(
      ExcelFutureFunctions.unprefixed("_XLFN.STDEV.S(B1:B3)+_xlfn.ifs(A1,1,TRUE,2)"),
      "STDEV.S(B1:B3)+ifs(A1,1,TRUE,2)")
    XCTAssertEqual(
      ExcelFutureFunctions.unprefixed(
        "ROWS(_xlfn.ANCHORARRAY(G1))+SUM(_xlfn.ANCHORARRAY(Data!$B$2))"),
      "ROWS(G1#)+SUM(Data!$B$2#)")
    XCTAssertEqual(
      ExcelFutureFunctions.unprefixed("COUNT(_xlfn.ANCHORARRAY('My ''Q'' Data'!A10))"),
      "COUNT('My ''Q'' Data'!A10#)")
  }

  func testUnprefixedLeavesTextAndUnknownNames() {
    let unchanged = [
      #""_xlfn.XLOOKUP("&A1"#,
      "'_xlfn.IFS(x'!A1+1",
      "_xlfn.LAMBDA(x,x+1)(2)",
      "_xlfn.ANCHORARRAY(A1:B2)",
      "_xlfn.ANCHORARRAY(INDEX(A:A,1))",
      "my_xlookup+SUM(A1:A3)",
      "SUM(A1:A3)",
    ]
    for formula in unchanged {
      XCTAssertEqual(ExcelFutureFunctions.unprefixed(formula), formula, formula)
    }
  }

  /// Saving what opening gives back writes the file's text again.
  func testSavedTextSurvivesARoundTrip() {
    let stored = [
      #"IF(D7="","",_xlfn.XLOOKUP(D7,B1:B3,C1:C3,0))"#,
      "_xlfn._xlws.FILTER(A1:A9,B1:B9>0)",
      "COUNTA(_xlfn.UNIQUE(A1:A3))&_xlfn.TEXTJOIN(\",\",TRUE,A1:A3)",
      "ROWS(_xlfn.ANCHORARRAY(G1))",
      "SUM(_xlfn.ANCHORARRAY('My ''Q'' Data'!A10))",
      "_xlfn.LAMBDA(x,x+1)(2)",
    ]
    for text in stored {
      let typed = ExcelFutureFunctions.unprefixed(text)
      XCTAssertEqual(
        ExcelFutureFunctions.prefixed(ExcelFutureFunctions.anchorArrays(typed)), text, text)
    }
  }

  func testSaveAndReopenShowsFormulasAsTyped() throws {
    var sheet = Sheet(name: "Data")
    let formulas = [
      #"=IF(A1="","",XLOOKUP(A1,B1:B3,C1:C3,0))"#,
      "=TEXTJOIN(\",\",TRUE,B1:B3)",
      "=IFS(A1>1,\"big\",TRUE,\"small\")",
      "=CONCAT(B1,B2)",
    ]
    for (row, formula) in formulas.enumerated() {
      sheet.setCell(Cell(raw: formula), at: CellAddress(row: row, col: 4))
    }
    sheet.setCell(Cell(raw: "=SORT(B1:B3)"), at: CellAddress(row: 0, col: 6))
    sheet.setCell(Cell(raw: "=ROWS(G1#)"), at: CellAddress(row: 0, col: 7))
    sheet.conditionalFormats = [
      ConditionalFormatRule(
        range: CellRange(start: CellAddress(row: 0, col: 0), end: CellAddress(row: 2, col: 0)),
        predicate: .formula("=XMATCH(A1,B$1:B$3,0)>1"), style: .redFill)
    ]
    var workbook = Workbook(sheets: [sheet])
    workbook.namedRanges["PICK"] = NamedRange(
      formulaName: "Pick", refersTo: "XLOOKUP(Data!$A$1,Data!$B$1:$B$3,Data!$C$1:$C$3)",
      sheetName: "Data")

    let data = try XLSXCodec.exportWorkbook(workbook)
    let xml = try XCTUnwrap(
      XLSXCodec.zipEntryString(archiveData: data, entryPath: "xl/worksheets/sheet1.xml"))
    XCTAssertTrue(xml.contains("_xlfn.XLOOKUP(A1,B1:B3,C1:C3,0)"), xml)
    XCTAssertTrue(xml.contains("_xlfn.ANCHORARRAY(G1)"), xml)
    XCTAssertTrue(xml.contains("<formula>_xlfn.XMATCH(A1,B$1:B$3,0)&gt;1</formula>"), xml)
    XCTAssertFalse(xml.contains("_xlfn._xlfn."), xml)
    let book = try XCTUnwrap(
      XLSXCodec.zipEntryString(archiveData: data, entryPath: "xl/workbook.xml"))
    XCTAssertTrue(book.contains(">_xlfn.XLOOKUP(Data!$A$1"), book)

    let reopened = try XLSXCodec.importWorkbook(from: data)
    let back = reopened.sheets[0]
    for (row, formula) in formulas.enumerated() {
      XCTAssertEqual(back.cell(at: CellAddress(row: row, col: 4)).raw, formula)
    }
    XCTAssertEqual(back.cell(at: CellAddress(row: 0, col: 6)).raw, "=SORT(B1:B3)")
    XCTAssertEqual(back.cell(at: CellAddress(row: 0, col: 7)).raw, "=ROWS(G1#)")
    XCTAssertEqual(back.conditionalFormats.first?.predicate, .formula("=XMATCH(A1,B$1:B$3,0)>1"))
    XCTAssertEqual(
      reopened.namedRanges["PICK"]?.refersTo, "XLOOKUP(Data!$A$1,Data!$B$1:$B$3,Data!$C$1:$C$3)")

    // Saved a second time, the file is the same.
    let again = try XLSXCodec.exportWorkbook(reopened)
    XCTAssertEqual(
      try XLSXCodec.zipEntryString(archiveData: again, entryPath: "xl/worksheets/sheet1.xml"), xml)
  }

  /// Files Excel saved open with every formula as typed, and their values unchanged.
  func testExcelSavedFilesOpenWithoutPrefixes() throws {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    var formulas = 0
    for name in ["excel-dynamic-arrays.xlsx", "excel-1.4-features.xlsx", "excel-pivots.xlsx"] {
      let data = try Data(contentsOf: root.appendingPathComponent("Fixtures/\(name)"))
      for sheet in try XLSXCodec.importWorkbook(from: data).sheets {
        for (address, cell) in sheet.cells where cell.raw.hasPrefix("=") {
          formulas += 1
          XCTAssertFalse(
            cell.raw.uppercased().contains("_XLFN."), "\(name) \(address.a1) \(cell.raw)")
        }
      }
    }
    XCTAssertGreaterThan(formulas, 10)
  }

  /// Shared formulas: the first cell holds the text, the rest are shifted from it.
  func testSharedFormulasOpenWithoutPrefixes() throws {
    var sheet = Sheet(name: "S")
    for row in 0..<4 {
      sheet.setCell(
        Cell(raw: "=XLOOKUP(A\(row + 1),B1:B3,C1:C3)"), at: CellAddress(row: row, col: 4))
    }
    let data = try XLSXCodec.exportWorkbook(Workbook(sheets: [sheet]))
    let back = try XLSXCodec.importWorkbook(from: data).sheets[0]
    for row in 0..<4 {
      XCTAssertEqual(
        back.cell(at: CellAddress(row: row, col: 4)).raw, "=XLOOKUP(A\(row + 1),B1:B3,C1:C3)")
    }
  }

  /// LET's names are saved as `_xlpm.` names, and read back as typed (Nov 18).
  func testLetNamesReadBackAsTyped() {
    let typed = "=LET(total,SUM(A1:A3),n,COUNT(A1:A3),total/n)"
    let saved = ExcelFutureFunctions.prefixed(String(typed.dropFirst()))
    XCTAssertTrue(saved.contains("_xlpm.total"), saved)
    XCTAssertEqual("=" + ExcelFutureFunctions.unprefixed(saved), typed)
    XCTAssertEqual(
      ExcelFutureFunctions.unprefixed("=_xlfn.TEXTJOIN(\",\",TRUE,_xlfn.SORT(A1:A3))"),
      "=TEXTJOIN(\",\",TRUE,SORT(A1:A3))")
    // Quoted text keeps its prefix-like words.
    XCTAssertEqual(ExcelFutureFunctions.unprefixed("=\"_xlpm.x\"&A1"), "=\"_xlpm.x\"&A1")
  }
}
