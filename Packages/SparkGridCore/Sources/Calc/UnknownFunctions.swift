import Formula
import Foundation
import GridCore
import Model

/// Function names formulas have called that Spark Grid does not have (BAHTTEXT, say). A cell
/// that calls one shows the result its file saved, not `#NAME?`; the formula itself is saved back
/// unchanged, so the app that wrote it calculates it again.
public enum UnknownFunctions {
  private static let lock = NSLock()
  nonisolated(unsafe) private static var names: Set<String> = []

  static func note(_ name: String) {
    lock.lock()
    names.insert(name.uppercased())
    lock.unlock()
  }

  public static func contains(_ name: String) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return names.contains(name.uppercased())
  }

  /// True when `expr` calls a function Spark Grid has met and does not have.
  public static func called(in expr: FormulaExpr) -> Bool {
    switch expr {
    case .call(let name, let args):
      return contains(FormulaEvaluator.plainFunctionName(name)) || args.contains(where: called)
    case .unary(_, let inner):
      return called(in: inner)
    case .binary(_, let left, let right):
      return called(in: left) || called(in: right)
    case .array(let rows):
      return rows.contains { $0.contains(where: called) }
    default:
      return false
    }
  }

  /// True when `expr` calls a function Spark Grid does not have, whether or not a calculation
  /// has met it yet. A file opened with its results is shown without calculating, so a save
  /// could not tell and wrote BAHTTEXT with no result (found in testing, Nov 19). A name that is
  /// not in the function list is tried once, with every cell read as empty, to find out.
  public static func callsUnknownFunction(_ expr: FormulaExpr) -> Bool {
    if called(in: expr) { return true }
    let known = Set(FormulaFunctions.all)
    guard callNames(in: expr).contains(where: { !known.contains($0) }) else { return false }
    let probe = FormulaEvaluator { _ in .blank }
    _ = probe.evaluate(expr)
    return called(in: expr)
  }

  private static func callNames(in expr: FormulaExpr) -> [String] {
    switch expr {
    case .call(let name, let args):
      return [FormulaEvaluator.plainFunctionName(name).uppercased()] + args.flatMap(callNames)
    case .unary(_, let inner):
      return callNames(in: inner)
    case .binary(_, let left, let right):
      return callNames(in: left) + callNames(in: right)
    case .array(let rows):
      return rows.flatMap { $0.flatMap(callNames) }
    default:
      return []
    }
  }

  /// The result `cell`'s file saved, when Spark Grid calculated `#NAME?` only because the formula
  /// calls a function it does not have.
  public static func savedResult(for cell: Cell, evaluated: CellValue, expr: FormulaExpr?)
    -> CellValue?
  {
    guard case .error(.name) = evaluated, let saved = cell.cachedFormulaValue else { return nil }
    if case .error(.name) = saved { return nil }
    if case .string(let text) = saved, FormulaSyntax.isFormula(text) { return nil }
    guard let expr = expr ?? (try? FormulaParser.parse(cell.raw)), callsUnknownFunction(expr)
    else { return nil }
    return saved
  }
}
