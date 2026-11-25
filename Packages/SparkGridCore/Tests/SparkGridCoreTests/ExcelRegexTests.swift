import Formula
import GridCore
import XCTest

@testable import Calc

/// Formulas typed into Excel 16.115 for Mac by script on Nov 23 2026, with Excel's answers, for the
/// 1.7 regular expression functions REGEXTEST, REGEXEXTRACT and REGEXREPLACE. Left out: a lazy
/// pattern that can match nothing (`a*?`), which Excel steps through differently.
final class ExcelRegexTests: XCTestCase {
  private let cells: [String: CellValue] = [
    "Data!A1": .string("Order 12-B, ship 2026-11-23"),
    "Data!A2": .string("alice@example.com; bob@test.org"),
    "Data!A3": .string("Hello World"),
    "Data!A5": .number(123.0),
    "Data!A6": .string("café 42 naïve"),
    "Data!B1": .string("x1"),
    "Data!B2": .string("y22"),
    "Data!B3": .string("z"),
  ]
  private let formulaCells: [String: String] = [:]
  private let hiddenRows: Set<String> = []
  private let sheets = ["Data"]
  private let names: [String: String] = [:]

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
      ("=REGEXTEST(A3,\"world\")", .bool(false)),
      ("=REGEXTEST(A3,\"world\",1)", .bool(true)),
      ("=REGEXTEST(A3,\"^Hello\")", .bool(true)),
      ("=REGEXTEST(A5,\"^\\d+$\")", .bool(true)),
      ("=REGEXTEST(A4,\"^$\")", .bool(true)),
      ("=REGEXTEST(A3,\"[\")", .error(.value)),
      ("=REGEXTEST(A3,\"o\",2)", .error(.value)),
      ("=REGEXTEST(A3,\"\\bWorld\\b\")", .bool(true)),
      ("=REGEXTEST(A3,\"(?i)WORLD\")", .bool(true)),
      ("=REGEXTEST(A6,\"^\\w+ \")", .bool(true)),
      ("=REGEXEXTRACT(A1,\"\\d+\")", .string("12")),
      ("=REGEXEXTRACT(A1,\"\\d+\",1)", .string("12")),
      ("=ROWS(REGEXEXTRACT(A1,\"\\d+\",1))", .number(1.0)),
      ("=COLUMNS(REGEXEXTRACT(A1,\"\\d+\",1))", .number(4.0)),
      ("=INDEX(REGEXEXTRACT(A1,\"\\d+\",1),3)", .string("11")),
      ("=INDEX(REGEXEXTRACT(A1,\"\\d+\",1),1,3)", .string("11")),
      ("=REGEXEXTRACT(A1,\"(\\d{4})-(\\d{2})-(\\d{2})\",2)", .string("2026")),
      ("=ROWS(REGEXEXTRACT(A1,\"(\\d{4})-(\\d{2})-(\\d{2})\",2))", .number(1.0)),
      ("=COLUMNS(REGEXEXTRACT(A1,\"(\\d{4})-(\\d{2})-(\\d{2})\",2))", .number(3.0)),
      ("=INDEX(REGEXEXTRACT(A1,\"(\\d{4})-(\\d{2})-(\\d{2})\",2),3)", .string("23")),
      ("=INDEX(REGEXEXTRACT(A1,\"(\\d{4})-(\\d{2})-(\\d{2})\",2),1,3)", .string("23")),
      ("=REGEXEXTRACT(A3,\"xyz\")", .error(.na)),
      ("=REGEXEXTRACT(A3,\"WORLD\",0,1)", .string("World")),
      ("=REGEXEXTRACT(A3,\"WORLD\",0,0)", .error(.na)),
      ("=COUNTA(REGEXEXTRACT(A2,\"[\\w.]+@[\\w.]+\",1))", .number(2.0)),
      ("=INDEX(REGEXEXTRACT(A2,\"[\\w.]+@[\\w.]+\",1),2)", .string("bob@test.org")),
      ("=REGEXEXTRACT(A2,\"(\\w+)@\",2)", .string("alice")),
      ("=REGEXEXTRACT(A3,\"o\",3)", .error(.value)),
      ("=REGEXEXTRACT(A3,\"(x)?Hello\",2)", .error(.na)),
      ("=INDEX(REGEXEXTRACT(A3,\"(x)?(Hello)\",2),2)", .string("Hello")),
      ("=REGEXEXTRACT(A3,\"xyz\",1)", .error(.na)),
      ("=REGEXEXTRACT(A3,\"xyz\",2)", .error(.value)),
      ("=REGEXEXTRACT(A6,\"\\w+\")", .string("café")),
      ("=REGEXEXTRACT(\"aaa\",\"a*?\")", .string("")),
      ("=LEN(REGEXEXTRACT(\"aaa\",\"a*?\"))", .number(0.0)),
      ("=REGEXEXTRACT(A5,\"\\d$\")", .string("3")),
      ("=REGEXEXTRACT(A3,\"(?<first>\\w+) (?<second>\\w+)\",2)", .string("Hello")),
      ("=REGEXREPLACE(A1,\"\\d\",\"#\")", .string("Order ##-B, ship ####-##-##")),
      ("=REGEXREPLACE(A1,\"\\d\",\"#\",2)", .string("Order 1#-B, ship 2026-11-23")),
      ("=REGEXREPLACE(A1,\"\\d\",\"#\",-1)", .string("Order 12-B, ship 2026-11-2#")),
      ("=REGEXREPLACE(A1,\"\\d\",\"#\",-2)", .string("Order 12-B, ship 2026-11-#3")),
      ("=REGEXREPLACE(A3,\"(\\w+) (\\w+)\",\"$2 $1\")", .string("World Hello")),
      ("=REGEXREPLACE(A3,\"o\",\"0\",0,1)", .string("Hell0 W0rld")),
      ("=REGEXREPLACE(A3,\"O\",\"0\",0,1)", .string("Hell0 W0rld")),
      ("=REGEXREPLACE(A3,\"O\",\"0\")", .string("Hello World")),
      ("=REGEXREPLACE(A3,\"o\",\"0\",5)", .string("Hello World")),
      ("=REGEXREPLACE(A3,\"l*\",\"-\")", .string("-H-e--o- -W-o-r--d-")),
      ("=REGEXREPLACE(A5,\"2\",\"x\")", .string("1x3")),
      ("=REGEXREPLACE(A3,\"World\",\"[$0]\")", .string("Hello [World]")),
      ("=REGEXREPLACE(A3,\"World\",\"$$\")", .string("Hello $")),
      ("=REGEXREPLACE(A3,\"(Wor)ld\",\"${1}k\")", .string("Hello Work")),
      ("=REGEXREPLACE(A3,\"[\",\"x\")", .error(.value)),
      ("=REGEXREPLACE(A6,\"\\w\",\"x\")", .string("xxxx xx xxxxx")),
      ("=REGEXREPLACE(A3,\"o\",\"0\",-5)", .string("Hello World")),
      ("=REGEXREPLACE(A3,\"o\",\"0\",1.7)", .string("Hell0 World")),
      ("=REGEXREPLACE(A3,\"\",\"-\")", .string("-H-e-l-l-o- -W-o-r-l-d-")),
      ("=REGEXREPLACE(A3,\"(?i)h\",\"J\")", .string("Jello World")),
      ("=REGEXTEST(A3,\"o\",1.5)", .bool(true)),
      ("=REGEXREPLACE(A3,\"(W)(o)\",\"$3\")", .error(.value)),
      ("=REGEXEXTRACT(A3,\"l+\",1)", .string("ll")),
      ("=ROWS(REGEXEXTRACT(A3,\"l+\",1))", .number(1.0)),
      ("=COLUMNS(REGEXEXTRACT(A3,\"l+\",1))", .number(2.0)),
      ("=REGEXEXTRACT(A3,\"World\",2)", .error(.value)),
      ("=COLUMNS(REGEXEXTRACT(A3,\"World\",2))", .error(.value)),
      ("=LEN(REGEXREPLACE(A3,\"\\s\",\"\\n\"))", .number(11.0)),
      ("=CODE(MID(REGEXREPLACE(A3,\"\\s\",\"\\n\"),6,1))", .number(10.0)),
      ("=REGEXREPLACE(A3,\"World\",\"$a\")", .error(.value)),
      ("=REGEXREPLACE(A3,\"(?<w>World)\",\"[${w}]\")", .string("Hello [World]")),
      ("=REGEXREPLACE(A3,\"World\",\"\\$\")", .string("Hello $")),
      ("=REGEXREPLACE(A3,\"World\",\"a\\\\b\")", .string("Hello a\\b")),
      ("=REGEXREPLACE(A3,\"World\",\"\\q\")", .error(.value)),
      ("=ROWS(REGEXTEST(B1:B3,\"\\d\"))", .number(3.0)),
      ("=INDEX(REGEXTEST(B1:B3,\"\\d\"),3)", .bool(false)),
      ("=ROWS(REGEXEXTRACT(B1:B3,\"\\d+\"))", .error(.value)),
      ("=COLUMNS(REGEXEXTRACT(B1:B3,\"\\d+\"))", .error(.value)),
      ("=INDEX(REGEXEXTRACT(B1:B3,\"\\d+\"),2)", .error(.value)),
      ("=INDEX(REGEXEXTRACT(B1:B3,\"\\d+\"),3)", .error(.value)),
      ("=ROWS(REGEXREPLACE(B1:B3,\"\\d\",\"#\"))", .number(3.0)),
      ("=INDEX(REGEXREPLACE(B1:B3,\"\\d\",\"#\"),2)", .string("y##")),
      ("=COLUMNS(REGEXEXTRACT(A3,\"o?\",1))", .number(12.0)),
      ("=REGEXTEST(A3,\"o\",TRUE)", .bool(true)),
      ("=REGEXTEST(A3,\"O\",TRUE)", .bool(true)),
      ("=REGEXTEST(A3,\"o\",\"1\")", .bool(true)),
      ("=REGEXTEST(A3,\"o\",-1)", .error(.value)),
      ("=REGEXEXTRACT(A3,\"o\",1.9)", .string("o")),
      ("=COLUMNS(REGEXEXTRACT(A3,\"o\",1.9))", .number(2.0)),
      ("=REGEXEXTRACT(A3,\"o\",-0.5)", .string("o")),
      ("=REGEXTEST(1/0,\"a\")", .error(.divZero)),
      ("=REGEXTEST(A3,1/0)", .error(.divZero)),
      ("=REGEXTEST(TRUE,\"TRUE\")", .bool(true)),
      ("=REGEXTEST(A3,\"\")", .bool(true)),
      ("=REGEXREPLACE(A3,\"o\",\"0\",0.5)", .string("Hell0 W0rld")),
      ("=REGEXREPLACE(A3,\"l\",\"L\",-2)", .string("HelLo World")),
      ("=REGEXEXTRACT(A3,\"(l)(o)?\",2)", .string("l")),
      ("=INDEX(REGEXEXTRACT(A3,\"(l)(o)?\",2),2)", .error(.na)),
      ("=REGEXTEST(\"a.b\",\"a\\.b\")", .bool(true)),
      ("=REGEXTEST(\"A\nB\",\"A.B\")", .bool(false)),
      ("=REGEXEXTRACT(A3,\"\\p{Lu}\",1)", .string("H")),
      ("=COLUMNS(REGEXEXTRACT(A3,\"\\p{Lu}\",1))", .number(2.0)),
    ]
    var failures: [String] = []
    for (formula, expected) in cases {
      let got = try value(formula)
      if case .number(let e) = expected, case .number(let g) = got,
        abs(g - e) <= max(1e-9, abs(e) * 1e-12)
      {
        continue
      }
      if got != expected { failures.append("\(formula): got \(got), Excel \(expected)") }
    }
    XCTAssert(failures.isEmpty, failures.joined(separator: "\n"))
  }
}
