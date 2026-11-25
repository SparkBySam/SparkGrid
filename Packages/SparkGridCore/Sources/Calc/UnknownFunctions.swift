import Formula
import Foundation
import GridCore
import Model

/// Function names formulas have called that Spark Grid does not have (CUBEVALUE, say). A cell
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

  /// Names a formula gives values itself: LET's names and LAMBDA's parameters, which it may
  /// then call (`LET(f,LAMBDA(x,x*2),f(5))`).
  static func boundNames(in expr: FormulaExpr) -> Set<String> {
    switch expr {
    case .call(let name, let args):
      var names = Set(args.flatMap { boundNames(in: $0) })
      let plain = FormulaEvaluator.plainFunctionName(name)
      if plain == "LET" {
        for index in stride(from: 0, to: args.count - 1, by: 2) {
          if case .namedRange(let bound) = args[index] {
            names.insert(withoutParameterPrefix(bound))
          }
        }
      } else if plain == "LAMBDA" {
        for arg in args.dropLast() {
          if case .namedRange(let bound) = arg { names.insert(withoutParameterPrefix(bound)) }
        }
      }
      return names
    case .unary(_, let inner):
      return boundNames(in: inner)
    case .binary(_, let left, let right):
      return boundNames(in: left).union(boundNames(in: right))
    case .array(let rows):
      return Set(rows.flatMap { $0.flatMap { boundNames(in: $0) } })
    default:
      return []
    }
  }

  /// `_xlpm.x`, as files save a LAMBDA parameter, as `X`.
  private static func withoutParameterPrefix(_ name: String) -> String {
    let upper = name.uppercased()
    return upper.hasPrefix("_XLPM.") ? String(upper.dropFirst(6)) : upper
  }

  /// One function a workbook's formulas call that Spark Grid does not have.
  public struct Use: Equatable, Sendable {
    public var name: String
    /// Formula cells that call it.
    public var cells: Int
    /// The first such cell, by sheet order, row and column.
    public var sheet: String
    public var address: CellAddress
  }

  /// The functions `workbook`'s formulas call that Spark Grid cannot calculate, most-used first.
  /// Names the workbook defines (a LAMBDA saved as a name, say) are its own, not unknown. Run off
  /// the main thread: every formula is parsed.
  public static func uses(in workbook: Workbook) -> [Use] {
    let known = Set(FormulaFunctions.all)
    let defined = Set(workbook.namedRanges.keys.map { $0.uppercased() })
    var found: [String: Use] = [:]
    // Names already found to be calculable, so each is tried once.
    var calculable = Set<String>()
    for sheet in workbook.sheets {
      let formulas = sheet.cells.filter { FormulaSyntax.isFormula($0.value.raw) }
        .sorted { ($0.key.row, $0.key.col) < ($1.key.row, $1.key.col) }
      for (address, cell) in formulas {
        // A formula with no call in it cannot call an unknown function.
        guard cell.raw.contains("("), let expr = try? FormulaParser.parse(cell.raw) else {
          continue
        }
        let local = boundNames(in: expr)
        let candidates = Set(callNames(in: expr)).filter {
          !known.contains($0) && !defined.contains($0) && !calculable.contains($0)
            && !local.contains(withoutParameterPrefix($0))
            && !$0.hasPrefix("SG.") && $0 != FormulaExpr.anchorArrayFunction
        }
        guard !candidates.isEmpty else { continue }
        _ = callsUnknownFunction(expr)
        for name in candidates {
          guard contains(name) else {
            calculable.insert(name)
            continue
          }
          if var use = found[name] {
            use.cells += 1
            found[name] = use
          } else {
            found[name] = Use(name: name, cells: 1, sheet: sheet.name, address: address)
          }
        }
      }
    }
    return found.values.sorted { ($1.cells, $0.name) < ($0.cells, $1.name) }
  }
}
