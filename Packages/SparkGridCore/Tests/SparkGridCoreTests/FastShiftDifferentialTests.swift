import FileFormats
import Foundation
import GridCore
import Model
import XCTest

@testable import Formula

/// Moving references in a formula's text without parsing it must give the formula the parser's
/// shift gives: the same once both are parsed, and the same text when the formula was already in
/// standard form. Formulas the text path does not handle go to the parser.
final class FastShiftDifferentialTests: XCTestCase {
  private struct Scenario {
    var axis: FormulaRewriter.Axis
    var change: FormulaRewriter.StructureChange
    var mutated: String
  }

  private func scenarios(formulaSheet: String) -> [Scenario] {
    var list: [Scenario] = []
    for axis in [FormulaRewriter.Axis.row, .column] {
      for index in [0, 1, 2, 4, 9, 30] {
        for count in [1, 3] {
          for sheet in [formulaSheet, "Data", "O'Brien"] {
            list.append(
              Scenario(axis: axis, change: .insert(at: index, count: count), mutated: sheet))
            list.append(
              Scenario(axis: axis, change: .delete(at: index, count: count), mutated: sheet))
          }
        }
      }
    }
    return list
  }

  private func canonical(_ raw: String) -> String? {
    guard let expr = try? FormulaParser.parse(raw) else { return nil }
    return "=" + FormulaRewriter.serialize(expr)
  }

  /// Compares the two paths for every formula and scenario. Returns how many the text path took.
  @discardableResult
  private func compare(
    _ formulas: [(sheet: String, raw: String)], file: StaticString = #filePath, line: UInt = #line
  ) -> (fast: Int, total: Int) {
    var fast = 0
    var total = 0
    var failures = 0
    for (sheet, raw) in formulas {
      // A formula the parser cannot read is left as written by that path; the text path may
      // still move its references. Neither can be calculated, so only readable ones compare.
      guard let rawStandard = canonical(raw) else { continue }
      for scenario in scenarios(formulaSheet: sheet) {
        total += 1
        let parsed = FormulaRewriter.parsedShiftForStructure(
          raw, formulaSheetName: sheet, mutatedSheetName: scenario.mutated, axis: scenario.axis,
          change: scenario.change)
        guard
          let quick = FormulaRewriter.fastShiftForStructure(
            raw, formulaSheetName: sheet, mutatedSheetName: scenario.mutated,
            axis: scenario.axis, change: scenario.change)
        else { continue }
        fast += 1
        let standard = rawStandard == raw
        let same = standard ? quick == parsed : canonical(quick) == parsed
        if !same {
          failures += 1
          if failures <= 20 {
            XCTFail(
              "\(raw) on \(sheet), \(scenario.axis) \(scenario.change) on \(scenario.mutated): "
                + "text \(quick), parser \(parsed)", file: file, line: line)
          }
        }
      }
    }
    return (fast, total)
  }

  func testHandWrittenFormulas() {
    let formulas: [String] = [
      "=A1", "=$A$1+B2*C$3-$D4", "=SUM(A2:A10)", "=SUM(A10:A2)", "=SUM($B$2:$B$40)/COUNT(B2:B40)",
      "=Data!A5+'My Sheet'!B6", "=SUM(Data!A1:A10)", "=SUM('My Sheet'!$A$1:$C$9)",
      "='O''Brien'!A3*2", "=VLOOKUP(A2,Data!$A$2:$D$301,4,FALSE)",
      #"=IF(A1="A1","B2",C3)"#, #"=CONCAT("Sheet1!A1",A1)"#, "=LOG10(A5)+ATAN2(B1,B2)",
      "=1E5+A1", "=2.5E-3*B7", "=A1:A3", "=SUM(A:A)", "=SUM(2:4)", "=SUM($A:$C)",
      "=Tax_2024+A1", "=my.name*B3", "=TRUE+A2", "=IFERROR(A1,#N/A)", "=SORT(A1:A9)",
      "=C1#", "=Table1[Amount]", "={1,2,3}", "= A1 + B2", "=sum(a1:a5)", "=a1+$b$2",
      "=ROUND($K11307-$E11307*VLOOKUP($D11307,Products!$A$2:$D$301,4,FALSE),2)",
      #"=IF($L9075<0,"Loss",IF($F9075>=Config!$B$6,"Review","OK"))"#,
      "=XFD1048576", "=A1048576+B1", "=SUM(A1:XFD1)", "=Data!A1:B2", "=-A3^2&B4",
      "=INDEX(Data!B2:B40,MATCH(A1,Data!A2:A40,0))", "=OFFSET(A1,1,1)", "=A01",
      "=SUMIFS(C:C,A:A,\"x\",B2:B9,\">0\")", "=Café!A1", #"="Café"&A1"#,
    ]
    compare(formulas.map { ("Sheet1", $0) })
  }

  /// Formulas built from random pieces, with a fixed seed so a failure repeats.
  func testGeneratedFormulas() {
    var rng = SeededGenerator(seed: 20_261_113)
    let sheets = ["", "Data!", "'My Sheet'!", "'O''Brien'!", "Sheet1!", "sheet1!"]
    func cell() -> String {
      let col = ["A", "B", "c", "AA", "XF", "Z"][Int(rng.next() % 6)]
      let row = [1, 2, 3, 5, 9, 10, 31, 100][Int(rng.next() % 8)]
      let absCol = rng.next() % 4 == 0 ? "$" : ""
      let absRow = rng.next() % 4 == 0 ? "$" : ""
      return "\(absCol)\(col)\(absRow)\(row)"
    }
    func operand() -> String {
      switch rng.next() % 7 {
      case 0: return sheets[Int(rng.next() % 6)] + cell()
      case 1: return sheets[Int(rng.next() % 6)] + cell() + ":" + cell()
      case 2: return "SUM(\(cell()):\(cell()))"
      case 3: return #""\#(cell())""#
      case 4: return String(rng.next() % 100)
      case 5:
        return "IF(\(cell())>\(rng.next() % 9),\(cell()),\(sheets[Int(rng.next() % 6)])\(cell()))"
      default: return cell()
      }
    }
    var formulas: [(String, String)] = []
    for _ in 0..<3_000 {
      var text = "=" + operand()
      for _ in 0..<Int(rng.next() % 3) {
        text += ["+", "-", "*", "/", "&", ","][Int(rng.next() % 6)] + operand()
      }
      // A list needs a function around it.
      if text.contains(",") { text = "=SUM(" + text.dropFirst() + ")" }
      formulas.append(("Sheet1", text))
    }
    let counts = compare(formulas)
    XCTAssertGreaterThan(Double(counts.fast) / Double(counts.total), 0.6, "\(counts)")
  }

  func testFixtureFormulas() throws {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    var paths = [
      "Fixtures/Q3-Enterprise-Pipeline.xlsx", "Fixtures/shared_formula_many_cells.xlsx",
      "Fixtures/excel-1.4-features.xlsx", "Fixtures/excel-dynamic-arrays.xlsx",
    ].map { root.appendingPathComponent($0).path }
    // A larger workbook when one is named, as on a developer's machine.
    if let extra = ProcessInfo.processInfo.environment["SPARK_GRID_SHIFT_CHECK_FILE"] {
      paths.append(extra)
    }
    var formulas: [(String, String)] = []
    for path in paths {
      let book = try XLSXCodec.importWorkbook(from: Data(contentsOf: URL(fileURLWithPath: path)))
      for sheet in book.sheets {
        for cell in sheet.cells.values where FormulaSyntax.isFormula(cell.raw) {
          formulas.append((sheet.name, cell.raw))
        }
      }
    }
    // A sample keeps the run short when a large workbook is named.
    if formulas.count > 6_000 {
      var rng = SeededGenerator(seed: 7)
      formulas = (0..<6_000).map { _ in formulas[Int(rng.next() % UInt64(formulas.count))] }
    }
    let counts = compare(formulas)
    print("[shift check] \(formulas.count) formulas, text path \(counts.fast) of \(counts.total)")
  }
}

private struct SeededGenerator {
  var state: UInt64
  init(seed: UInt64) { state = seed }
  mutating func next() -> UInt64 {
    state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
    return state >> 11
  }
}
