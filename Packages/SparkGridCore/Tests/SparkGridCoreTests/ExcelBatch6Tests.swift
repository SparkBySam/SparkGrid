import Formula
import GridCore
import XCTest

@testable import Calc

/// Formulas typed into Excel 16.115 for Mac by script on Nov 20 2026, with Excel's answers, for the
/// 1.7 batch 6 LAMBDA, GROUPBY and PIVOTBY functions. Formula cells among the data hold what Excel calculated for them.
final class ExcelBatch6Tests: XCTestCase {
  private let cells: [String: CellValue] = [
    "Data!A1": .string("Region"),
    "Data!B1": .string("Product"),
    "Data!C1": .string("Sales"),
    "Data!A2": .string("East"),
    "Data!B2": .string("A"),
    "Data!C2": .number(10.0),
    "Data!A3": .string("West"),
    "Data!B3": .string("B"),
    "Data!C3": .number(20.0),
    "Data!A4": .string("East"),
    "Data!B4": .string("B"),
    "Data!C4": .number(30.0),
    "Data!A5": .string("North"),
    "Data!B5": .string("A"),
    "Data!C5": .number(5.0),
    "Data!A6": .string("West"),
    "Data!B6": .string("A"),
    "Data!C6": .number(15.0),
    "Data!A7": .string("East"),
    "Data!B7": .string("A"),
    "Data!C7": .number(25.0),
    "Data!A8": .string("north"),
    "Data!B8": .string("B"),
    "Data!C8": .number(7.0),
    "Data!A9": .string("West"),
    "Data!B9": .string("B"),
    "Data!C9": .number(12.0),
    "Data!E1": .number(1.0),
    "Data!E2": .number(2.0),
    "Data!E3": .number(3.0),
    "Data!F1": .number(1.0),
    "Data!G1": .number(2.0),
    "Data!F2": .number(3.0),
    "Data!G2": .number(4.0),
  ]
  private let formulaCells: [String: String] = [:]
  private let hiddenRows: Set<String> = []
  private let sheets = ["Data"]
  private let names: [String: String] = [
    "Hyp": "=LAMBDA(a,b,SQRT(a^2+b^2))", "Tax": "=0.07",
    "Twice": "=LAMBDA(x,[y],IF(ISOMITTED(y),x*2,x*y))", "Fact": "=LAMBDA(n,IF(n<=1,1,n*Fact(n-1)))",
    "Grow": "=LAMBDA(v,v*(1+Tax))",
  ]

  private func value(_ formula: String) throws -> CellValue {
    var evaluator = FormulaEvaluator { [self] ref in self.read(ref) }
    evaluator.formulaSheetName = sheets[0]
    evaluator.sheetNames = { [sheets] in sheets }
    evaluator.formulaText = { [formulaCells] sheet, address in
      formulaCells["\(sheet)!\(address.a1)"]
    }
    evaluator.holdsFormula = { [formulaCells] sheet, address in
      formulaCells["\(sheet)!\(address.a1)"] != nil
    }
    evaluator.rowHidden = { [hiddenRows] sheet, row in hiddenRows.contains("\(sheet)!\(row)") }
    evaluator.namedRangeLookup = { [names] name in
      names.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }
        .flatMap { try? FormulaParser.parse($0.value) }
    }
    return evaluator.evaluate(try FormulaParser.parse(formula))
  }

  private func read(_ ref: FormulaRef) -> CellValue {
    let key = "\(ref.sheet ?? sheets[0])!\(ref.address.a1)"
    if let value = cells[key] { return value }
    if let formula = formulaCells[key], formula != "" {
      return (try? self.value(formula)) ?? .blank
    }
    return .blank
  }

  func testMatchesExcel() throws {
    let cases: [(String, CellValue)] = [
      ("=Hyp(3,4)", .number(5.0)),
      ("=Hyp(E1,E2)", .number(2.23606797749979)),
      ("=Tax*100", .number(7.0)),
      ("=Fact(5)", .number(120.0)),
      ("=Grow(100)", .number(107.0)),
      ("=SUM(MAP(E1:E3,LAMBDA(x,x*x)))", .number(14.0)),
      ("=INDEX(MAP(E1:E3,LAMBDA(x,x*10)),3)", .number(30.0)),
      ("=INDEX(MAP(E1:E3,E1:E3,LAMBDA(a,b,a+b)),2)", .number(4.0)),
      ("=REDUCE(0,E1:E3,LAMBDA(a,b,a+b))", .number(6.0)),
      ("=REDUCE(1,F1:G2,LAMBDA(a,b,a*b))", .number(24.0)),
      ("=REDUCE(,E1:E3,LAMBDA(a,b,a+b))", .number(6.0)),
      ("=INDEX(SCAN(0,E1:E3,LAMBDA(a,b,a+b)),3)", .number(6.0)),
      ("=INDEX(SCAN(1,F1:G2,LAMBDA(a,b,a*b)),2,2)", .number(24.0)),
      ("=INDEX(SCAN(\"\",{\"a\",\"b\",\"c\"},LAMBDA(a,b,a&b)),3)", .string("abc")),
      ("=INDEX(BYROW(F1:G2,LAMBDA(r,SUM(r))),2)", .number(7.0)),
      ("=INDEX(BYCOL(F1:G2,LAMBDA(c,MAX(c))),2)", .number(4.0)),
      ("=ROWS(BYROW(F1:G2,LAMBDA(r,SUM(r))))", .number(2.0)),
      ("=COLUMNS(BYCOL(F1:G2,LAMBDA(c,SUM(c))))", .number(2.0)),
      ("=INDEX(BYROW(F1:G2,SUM),1)", .number(3.0)),
      ("=INDEX(BYCOL(F1:G2,AVERAGE),2)", .number(3.0)),
      ("=BYROW(F1:G2,LAMBDA(r,r))", .error(.calc)),
      ("=INDEX(MAKEARRAY(3,4,LAMBDA(r,c,r*c)),3,4)", .number(12.0)),
      ("=SUM(MAKEARRAY(2,2,LAMBDA(r,c,r+c)))", .number(12.0)),
      ("=MAKEARRAY(0,2,LAMBDA(r,c,1))", .error(.value)),
      ("=LAMBDA(x,x+1)", .error(.calc)),
      ("=MAP(E1:E3,LAMBDA(x,y,x+y))", .error(.value)),
      ("=INDEX(EXPAND(F1:G2,3,3),3,3)", .error(.na)),
      ("=INDEX(EXPAND(F1:G2,3,3,0),3,3)", .number(0.0)),
      ("=INDEX(EXPAND(F1:G2,3),3,1)", .error(.na)),
      ("=INDEX(EXPAND(F1:G2,2,3,\"-\"),1,3)", .string("-")),
      ("=EXPAND(F1:G2,1,2)", .error(.value)),
      ("=ROWS(EXPAND(E1:E3,5))", .number(5.0)),
      ("=ROWS(GROUPBY(A2:A9,C2:C9,SUM))", .number(4.0)),
      ("=INDEX(GROUPBY(A2:A9,C2:C9,SUM),1,1)", .string("East")),
      ("=INDEX(GROUPBY(A2:A9,C2:C9,SUM),1,2)", .number(65.0)),
      ("=INDEX(GROUPBY(A2:A9,C2:C9,SUM),2,1)", .string("North")),
      ("=INDEX(GROUPBY(A2:A9,C2:C9,SUM),2,2)", .number(12.0)),
      ("=INDEX(GROUPBY(A2:A9,C2:C9,SUM),4,1)", .string("Total")),
      ("=INDEX(GROUPBY(A2:A9,C2:C9,SUM),4,2)", .number(124.0)),
      ("=INDEX(GROUPBY(A1:A9,C1:C9,SUM,3),1,1)", .string("Region")),
      ("=INDEX(GROUPBY(A1:A9,C1:C9,SUM,3),1,2)", .string("Sales")),
      ("=ROWS(GROUPBY(A1:A9,C1:C9,SUM))", .number(4.0)),
      ("=INDEX(GROUPBY(A2:A9,C2:C9,AVERAGE,0,0),3,2)", .number(15.6666666666667)),
      ("=ROWS(GROUPBY(A2:A9,C2:C9,SUM,0,0))", .number(3.0)),
      ("=INDEX(GROUPBY(A2:A9,C2:C9,SUM,0,1,-2),1,1)", .string("East")),
      ("=INDEX(GROUPBY(A2:A9,C2:C9,SUM,0,-1),1,1)", .string("Total")),
      ("=INDEX(GROUPBY(A2:A9,C2:C9,COUNT,0,1),1,2)", .number(3.0)),
      ("=INDEX(GROUPBY(A2:B9,C2:C9,SUM,0,0),2,2)", .string("B")),
      ("=COLUMNS(GROUPBY(A2:B9,C2:C9,SUM,0,0))", .number(3.0)),
      ("=INDEX(GROUPBY(A2:A9,C2:C9,SUM,0,1,1,B2:B9=\"A\"),1,2)", .number(35.0)),
      ("=INDEX(GROUPBY(A2:A9,C2:C9,LAMBDA(v,MAX(v)-MIN(v)),0,0),1,2)", .number(20.0)),
      ("=INDEX(GROUPBY(A2:A9,C2:C9,SUM,2),1,1)", .string("Row Field 1")),
      ("=INDEX(GROUPBY(A2:A9,C2:C9,SUM,2),1,2)", .string("Value 1")),
      ("=ROWS(PIVOTBY(A2:A9,B2:B9,C2:C9,SUM))", .number(5.0)),
      ("=COLUMNS(PIVOTBY(A2:A9,B2:B9,C2:C9,SUM))", .number(4.0)),
      ("=INDEX(PIVOTBY(A2:A9,B2:B9,C2:C9,SUM),1,2)", .string("A")),
      ("=INDEX(PIVOTBY(A2:A9,B2:B9,C2:C9,SUM),1,4)", .string("Total")),
      ("=INDEX(PIVOTBY(A2:A9,B2:B9,C2:C9,SUM),2,1)", .string("East")),
      ("=INDEX(PIVOTBY(A2:A9,B2:B9,C2:C9,SUM),2,2)", .number(35.0)),
      ("=INDEX(PIVOTBY(A2:A9,B2:B9,C2:C9,SUM),3,3)", .number(7.0)),
      ("=INDEX(PIVOTBY(A2:A9,B2:B9,C2:C9,SUM),5,4)", .number(124.0)),
      ("=INDEX(PIVOTBY(A2:A9,B2:B9,C2:C9,SUM),4,3)", .number(32.0)),
      ("=INDEX(PIVOTBY(A2:A9,B2:B9,C2:C9,SUM,0,0,1,0),2,2)", .number(35.0)),
      ("=COLUMNS(PIVOTBY(A2:A9,B2:B9,C2:C9,SUM,0,0,1,0))", .number(3.0)),
      ("=INDEX(PIVOTBY(A2:A9,B2:B9,C2:C9,SUM,0,1,-1),2,1)", .string("West")),
      ("=INDEX(PIVOTBY(A2:A9,B2:B9,C2:C9,COUNT),3,2)", .number(1.0)),
      ("=INDEX(PIVOTBY(A2:A9,B2:B9,C2:C9,SUM),1,1)", .string("")),
    ]
    var failures: [String] = []
    for (formula, expected) in cases {
      let got = try value(formula)
      if case .number(let e) = expected, case .number(let g) = got,
        abs(g - e) <= max(1e-9, abs(e) * 1e-9)
      {
        continue
      }
      if got != expected { failures.append("\(formula): got \(got), Excel \(expected)") }
    }
    XCTAssert(failures.isEmpty, failures.joined(separator: "\n"))
  }
}
