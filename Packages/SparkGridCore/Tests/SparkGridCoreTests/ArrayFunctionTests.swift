import Formula
import GridCore
import XCTest

@testable import Calc

final class ArrayFunctionTests: XCTestCase {
  /// Region, Rep, Amount in A1:C7 with a header.
  private let cells: [String: CellValue] = {
    let rows: [[CellValue]] = [
      [.string("Region"), .string("Rep"), .string("Amount")],
      [.string("West"), .string("Ann"), .number(100)],
      [.string("East"), .string("bo"), .number(40)],
      [.string("west"), .string("Cy"), .number(30)],
      [.string("North"), .string("Di"), .number(5)],
      [.string("East"), .string("Ed"), .number(120)],
      [.string("East"), .string("Bo"), .number(40)],
    ]
    var out: [String: CellValue] = [:]
    for (r, row) in rows.enumerated() {
      for (c, value) in row.enumerated() {
        out[CellAddress(row: r, col: c).a1] = value
      }
    }
    return out
  }()

  private func array(_ formula: String) throws -> ArrayResult {
    let cells = self.cells
    let evaluator = FormulaEvaluator { ref in cells[ref.address.a1] ?? .blank }
    return evaluator.evaluateArray(try FormulaParser.parse(formula))
  }

  private func scalar(_ formula: String) throws -> CellValue {
    let cells = self.cells
    let evaluator = FormulaEvaluator { ref in cells[ref.address.a1] ?? .blank }
    return evaluator.evaluate(try FormulaParser.parse(formula))
  }

  private func texts(_ a: ArrayResult) -> [[String]] {
    (0..<a.rows).map { r in (0..<a.cols).map { a.value(row: r, col: $0).displayString } }
  }

  func testFilterRowsByCondition() throws {
    let a = try array(#"=FILTER(B2:C7,A2:A7="east")"#)
    XCTAssertEqual(texts(a), [["bo", "40"], ["Ed", "120"], ["Bo", "40"]])
    let both = try array(#"=FILTER(B2:B7,(A2:A7="East")*(C2:C7>50))"#)
    XCTAssertEqual(texts(both), [["Ed"]])
    XCTAssertEqual(try array(#"=FILTER(B2:B7,A2:A7="South")"#).first, .error(.calc))
    XCTAssertEqual(try array(#"=FILTER(B2:B7,A2:A7="South","none")"#).first, .string("none"))
    XCTAssertEqual(try array(#"=FILTER(B2:B7,A2:A3="West")"#).first, .error(.value))
  }

  func testSortAndSortBy() throws {
    XCTAssertEqual(
      texts(try array("=SORT(C2:C7)")).map { $0[0] }, ["5", "30", "40", "40", "100", "120"])
    XCTAssertEqual(
      texts(try array("=SORT(A2:C7,3,-1)")).map { $0[1] }, ["Ed", "Ann", "bo", "Bo", "Cy", "Di"])
    XCTAssertEqual(
      texts(try array("=SORTBY(B2:B7,A2:A7,1,C2:C7,-1)")).map { $0[0] },
      ["Ed", "bo", "Bo", "Di", "Ann", "Cy"])
    XCTAssertEqual(try array("=SORT(A2:C7,4)").first, .error(.value))
  }

  func testUniqueIgnoresCase() throws {
    XCTAssertEqual(texts(try array("=UNIQUE(A2:A7)")).map { $0[0] }, ["West", "East", "North"])
    XCTAssertEqual(texts(try array("=UNIQUE(A2:A7,FALSE,TRUE)")).map { $0[0] }, ["North"])
    XCTAssertEqual(texts(try array("=UNIQUE(B2:C7)")).count, 5)
    XCTAssertEqual(
      texts(try array("=SORT(UNIQUE(A2:A7))")).map { $0[0] }, ["East", "North", "West"])
  }

  func testSequenceAndScalarUse() throws {
    let s = try array("=SEQUENCE(2,3,10,5)")
    XCTAssertEqual(s.rows, 2)
    XCTAssertEqual(texts(s), [["10", "15", "20"], ["25", "30", "35"]])
    XCTAssertEqual(try scalar(#"=SUM(FILTER(C2:C7,A2:A7="East"))"#), .number(200))
    XCTAssertEqual(try scalar(#"=COUNTA(UNIQUE(A2:A7))"#), .number(3))
    XCTAssertEqual(try scalar("=SEQUENCE(1)"), .number(1))
    XCTAssertEqual(try scalar(#"=_xlfn._xlws.FILTER(C2:C7,A2:A7="North")"#), .number(5))
    XCTAssertEqual(texts(try array("=FILTER(C2:C7,C2:C7>50)*2")).map { $0[0] }, ["200", "240"])
    XCTAssertTrue(FormulaEvaluator.spills(try FormulaParser.parse("=SORT(A1:A3)*2")))
    XCTAssertFalse(FormulaEvaluator.spills(try FormulaParser.parse("=SUM(FILTER(A1:A3,B1:B3))")))
  }

  func testRowsColumnsAndIndexTakeResults() throws {
    XCTAssertEqual(try scalar("=ROWS(UNIQUE(A2:A7))"), .number(3))
    XCTAssertEqual(try scalar("=COLUMNS(SEQUENCE(2,4))"), .number(4))
    XCTAssertEqual(try scalar("=INDEX(SORT(C2:C7,1,-1),1)"), .number(120))
    XCTAssertEqual(try scalar(#"=INDEX(FILTER(B2:C7,A2:A7="East"),2,1)"#), .string("Ed"))
    XCTAssertEqual(try scalar("=INDEX(SEQUENCE(1,5),3)"), .number(3))
    XCTAssertEqual(try scalar("=INDEX(SORT(C2:C7),9)"), .error(.ref))
    XCTAssertEqual(try scalar(#"=ROWS(FILTER(C2:C7,A2:A7="Moon"))"#), .error(.calc))
  }
}
