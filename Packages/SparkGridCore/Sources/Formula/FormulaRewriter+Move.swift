import Foundation
import GridCore

extension FormulaRewriter {
  /// After cells in `rows` and `columns` on `movedSheetName` move by `rowDelta` and `colDelta`, a formula's
  /// references into them follow, as when cells are dragged to a new place in other spreadsheet
  /// apps: a cell inside the block, or a range wholly inside it, moves; anything else stays.
  public static func movingReferences(
    _ raw: String,
    formulaSheetName: String,
    movedSheetName: String,
    rows: ClosedRange<Int>,
    columns: ClosedRange<Int>,
    rowDelta: Int,
    colDelta: Int
  ) -> String {
    guard FormulaSyntax.isFormula(raw), rowDelta != 0 || colDelta != 0,
      let expr = try? FormulaParser.parse(raw)
    else { return raw }
    func onMovedSheet(_ ref: FormulaRef) -> Bool {
      (ref.sheet ?? formulaSheetName).caseInsensitiveCompare(movedSheetName) == .orderedSame
    }
    func inside(_ ref: FormulaRef) -> Bool {
      onMovedSheet(ref) && rows.contains(ref.row) && columns.contains(ref.col)
    }
    func moved(_ ref: FormulaRef) -> FormulaRef {
      var next = ref
      next.row += rowDelta
      next.col += colDelta
      return next
    }
    var changed = false
    func walk(_ expr: FormulaExpr) -> FormulaExpr {
      switch expr {
      case .cellRef(let ref)
      where inside(ref) && ref.row + rowDelta >= 0 && ref.col + colDelta >= 0:
        changed = true
        return .cellRef(moved(ref))
      case .range(let start, let end)
      where inside(start) && inside(end) && min(start.row, end.row) + rowDelta >= 0
        && min(start.col, end.col) + colDelta >= 0:
        changed = true
        return .range(moved(start), moved(end))
      case .unary(let op, let inner):
        return .unary(op, walk(inner))
      case .binary(let op, let lhs, let rhs):
        return .binary(op, walk(lhs), walk(rhs))
      case .call(let name, let args):
        return .call(name, args.map(walk))
      default:
        return expr
      }
    }
    let next = walk(expr)
    return changed ? "=" + serialize(next) : raw
  }
}
