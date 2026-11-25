import Formula
import Foundation
import GridCore
import Model

/// Data › Goal Seek: the value for one input cell that makes a formula cell come out at a goal,
/// as other spreadsheet apps find it. The search runs on its own engine over a copy of the
/// workbook, so nothing on screen changes until the answer is kept.
public enum GoalSeek {
  public struct Outcome: Equatable, Sendable {
    /// The input value found (or the closest one tried).
    public var input: Double
    /// What the formula gives with that input.
    public var result: Double
    public var found: Bool
    public var iterations: Int
  }

  public enum Failure: Error, Equatable {
    case setCellHasNoFormula, changingCellHasFormula, notANumber
  }

  public static func run(
    workbook: Workbook,
    setSheet: String, setCell: CellAddress, goal: Double,
    changingSheet: String, changingCell: CellAddress,
    maxIterations: Int = 100
  ) -> Result<Outcome, Failure> {
    guard
      let setIndex = workbook.sheets.firstIndex(where: {
        $0.name.caseInsensitiveCompare(setSheet) == .orderedSame
      }),
      let changeIndex = workbook.sheets.firstIndex(where: {
        $0.name.caseInsensitiveCompare(changingSheet) == .orderedSame
      })
    else { return .failure(.notANumber) }
    guard FormulaSyntax.isFormula(workbook.sheets[setIndex].cell(at: setCell).raw) else {
      return .failure(.setCellHasNoFormula)
    }
    let changingRaw = workbook.sheets[changeIndex].cell(at: changingCell).raw
    guard !FormulaSyntax.isFormula(changingRaw) else { return .failure(.changingCellHasFormula) }

    var book = workbook
    book.activeSheetIndex = changeIndex
    let engine = FormulaEngine()
    engine.rebuild(workbook: book, recalculate: false)
    engine.prepareDependencyGraph()
    let targetSheetName = book.sheets[setIndex].name

    func evaluate(_ x: Double) -> Double? {
      var sheet = book.sheets[changeIndex]
      var cell = sheet.cell(at: changingCell)
      cell.raw = Self.text(x)
      cell.isText = nil
      sheet.setCell(cell, at: changingCell)
      book.sheets[changeIndex] = sheet
      engine.adoptWorkbook(book)
      _ = engine.cellsDidChange([changingCell], sheet: sheet)
      engine.finishPendingCrossSheet()
      let value =
        setIndex == changeIndex
        ? engine.displayValue(at: setCell, sheet: sheet)
        : engine.value(onSheet: targetSheetName, at: setCell)
      return value.asNumber.flatMap { $0.isFinite ? $0 : nil }
    }

    let tolerance = 1e-7 * max(1, abs(goal))
    var x0 = Double(changingRaw.trimmingCharacters(in: .whitespaces)) ?? 0
    guard var f0 = evaluate(x0).map({ $0 - goal }) else { return .failure(.notANumber) }
    var best = (x: x0, f: f0)
    if abs(f0) <= tolerance {
      return .success(Outcome(input: x0, result: f0 + goal, found: true, iterations: 0))
    }
    var x1 = x0 == 0 ? 1 : x0 * 1.01
    var iterations = 0
    while iterations < maxIterations {
      iterations += 1
      guard let f1 = evaluate(x1).map({ $0 - goal }) else {
        // An input the formula cannot take: step back toward the last good one.
        x1 = (x0 + x1) / 2
        continue
      }
      if abs(f1) < abs(best.f) { best = (x1, f1) }
      if abs(f1) <= tolerance {
        return .success(Outcome(input: x1, result: f1 + goal, found: true, iterations: iterations))
      }
      var next: Double
      if f1 != f0, x1 != x0 {
        next = x1 - f1 * (x1 - x0) / (f1 - f0)
      } else {
        // Flat here: try further away.
        next = x1 == 0 ? 1 : x1 * 2
      }
      if !next.isFinite { next = x1 * 2 }
      // Do not jump more than a thousandfold at once.
      let limit = max(1, abs(x1)) * 1000
      next = min(max(next, x1 - limit), x1 + limit)
      x0 = x1
      f0 = f1
      x1 = next
    }
    _ = evaluate(best.x)
    return .success(
      Outcome(input: best.x, result: best.f + goal, found: false, iterations: iterations))
  }

  /// A number as typed text, with enough digits to read back the same.
  static func text(_ x: Double) -> String {
    x == x.rounded() && abs(x) < 1e15 ? String(Int(x)) : String(format: "%.15g", x)
  }
}
