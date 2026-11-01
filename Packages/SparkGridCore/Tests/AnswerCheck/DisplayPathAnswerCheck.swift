import GridCore
import Model
import XCTest

@testable import Engine

/// The four paths stay wired without the private corpus.
/// This workbook's formulas are `=1+1`, so a failure here is the harness, not the KPI file.
@MainActor
final class DisplayPathAnswerCheck: XCTestCase {
  func testFourPathsAgreeWhenTheEditIsRestored() {
    let workbook = sampleWorkbook(juneCache: "2")
    let paths = AnswerComparison.comparePaths(
      in: workbook,
      editSheetNames: ["June", "January"],
      exempt: []
    )
    XCTAssertEqual(paths.map(\.name), ["paint", "shuffled", "edits", "full"])
    for path in paths {
      XCTAssertEqual(path.checked, 2, path.name)
      XCTAssertEqual(path.mismatches.map(\.key), [], path.name)
    }
    XCTAssertEqual(paths.first { $0.name == "edits" }?.editedSheets, 2)
  }

  func testExemptionDropsOnlyTheNamedCell() {
    let workbook = sampleWorkbook(juneCache: "9")
    let key = "june!b1"
    let open = AnswerComparison.comparePaths(in: workbook, editSheetNames: [], exempt: [])
    for path in open {
      XCTAssertEqual(path.mismatches.map(\.key), ["June!B1"], path.name)
    }
    let exempted = AnswerComparison.comparePaths(
      in: workbook,
      editSheetNames: [],
      exempt: [key]
    )
    for path in exempted {
      XCTAssertEqual(path.mismatches.map(\.key), [], path.name)
      XCTAssertEqual(path.checked, 2, path.name)
    }
  }

  private func sampleWorkbook(juneCache: String) -> Workbook {
    let january = Sheet(
      name: "January",
      cells: [
        CellAddress(row: 0, col: 0): Cell(raw: "4"),
        CellAddress(row: 0, col: 1): Cell(
          raw: "=1+1",
          importedFormulaResult: "2",
          importedFormulaValueType: .number
        ),
      ]
    )
    let june = Sheet(
      name: "June",
      cells: [
        CellAddress(row: 0, col: 0): Cell(raw: "5"),
        CellAddress(row: 0, col: 1): Cell(
          raw: "=1+1",
          importedFormulaResult: juneCache,
          importedFormulaValueType: .number
        ),
      ]
    )
    return Workbook(sheets: [january, june])
  }
}
