import Formula
import XCTest

final class FormulaRewriterTests: XCTestCase {
  /// A sort moved this formula down a row and wrote it back without its brackets,
  /// which changed every Net value on the stress workbook's Orders sheet.
  func testMovingAFormulaKeepsItsBrackets() {
    XCTAssertEqual(
      FormulaRewriter.adjust("=ROUND($E3*$J3*(1-$F3),2)", rowDelta: 1, colDelta: 0),
      "=ROUND($E4*$J4*(1-$F4),2)"
    )
  }

  /// Rewriting must never change what a formula means: the text it writes parses back
  /// to the same tree, shifted by the move.
  func testRewrittenFormulasParseToTheSameTree() throws {
    let formulas = [
      "=A1*(B1+C1)",
      "=(A1+B1)*C1",
      "=A1-(B1-C1)",
      "=A1-B1-C1",
      "=A1/(B1/C1)",
      "=A1/B1/C1",
      "=(A1^B1)^C1",
      "=A1^(B1^C1)",
      "=-(A1+B1)",
      "=-A1^2",
      "=A1&(B1&C1)",
      "=(A1>B1)=TRUE",
      "=A1>(B1+C1)",
      "=(A1&B1)+1",
      "=SUM(A1:A3)*(1-B1)",
    ]
    for formula in formulas {
      let moved = FormulaRewriter.adjust(formula, rowDelta: 2, colDelta: 1)
      let expected = FormulaRewriter.adjustExpression(
        try FormulaParser.parse(formula), rowDelta: 2, colDelta: 1)
      XCTAssertEqual(try FormulaParser.parse(moved), expected, "\(formula) became \(moved)")
    }
  }
}
