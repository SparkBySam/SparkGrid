import Foundation
import GridCore

/// Shared catalog of built-in formula function names (uppercase).
public enum FormulaFunctions {
  public static let all: [String] = [
    "SUM", "AVERAGE", "COUNT", "COUNTA", "MIN", "MAX",
    "SUMIF", "AVERAGEIF", "COUNTIF", "SUMIFS", "COUNTIFS", "AVERAGEIFS",
    "COUNTBLANK", "SUMPRODUCT",
    "IF", "IFERROR", "IFNA", "IFS", "AND", "OR", "NOT",
    "ABS", "ROUND", "ROUNDUP", "ROUNDDOWN",
    "LEN", "LEFT", "RIGHT", "MID", "TRIM", "UPPER", "LOWER",
    "SUBSTITUTE", "TEXTJOIN", "CONCAT", "CONCATENATE", "TEXT", "CHAR", "REPT",
    "SEQUENCE",
    "COLUMN", "TRUE",
    "XLOOKUP", "XMATCH", "VLOOKUP", "HLOOKUP", "INDEX", "MATCH",
    "TODAY", "NOW", "DATE", "YEAR", "MONTH", "DAY",
    // 1.2 batch 1
    "INT", "SIGN", "SQRT", "PI", "MOD", "POWER", "CEILING", "CEILING.MATH", "FLOOR", "FLOOR.MATH",
    "PRODUCT", "MEDIAN", "LARGE", "SMALL", "RANK", "RANK.EQ", "MAXIFS", "MINIFS",
    "PROPER", "FIND", "SEARCH", "VALUE", "EXACT",
    "ISBLANK", "ISNUMBER", "ISTEXT", "ISERROR", "FALSE",
    "WEEKDAY", "HOUR", "MINUTE", "SECOND", "EDATE", "EOMONTH",
    "ROW", "ROWS", "COLUMNS",
    // 1.4 batch 2
    "PMT", "IPMT", "PPMT", "FV", "PV", "NPER", "RATE", "NPV", "IRR", "XNPV", "XIRR", "DAYS",
    "DATEDIF", "NETWORKDAYS", "WORKDAY", "WEEKNUM", "ISOWEEKNUM", "STDEV", "STDEV.S", "STDEVP",
    "STDEV.P", "VAR", "VAR.S", "VARP", "VAR.P", "PERCENTILE", "PERCENTILE.INC", "QUARTILE",
    "QUARTILE.INC", "MODE", "MODE.SNGL", "CORREL", "SLOPE", "INTERCEPT", "FORECAST",
    "FORECAST.LINEAR", "COUNTUNIQUE", "SUMSQ", "MROUND", "TRUNC", "EXP", "LN", "LOG", "LOG10",
    "FACT", "GCD", "LCM", "EVEN", "ODD", "SWITCH", "XOR", "ISEVEN", "ISODD", "ISLOGICAL", "ISNA",
    "ISERR", "NA", "CHOOSE", "HYPERLINK", "GETPIVOTDATA", "TEXTBEFORE", "TEXTAFTER", "CLEAN",
    "CODE", "UNICODE",
    "UNICHAR",
    // 1.4 spilling results
    "FILTER", "SORT", "SORTBY", "UNIQUE",
  ].sorted()

  public static func suggestions(matching prefix: String) -> [String] {
    let upper = prefix.uppercased()
    guard !upper.isEmpty else { return Array(all.prefix(12)) }
    return all.filter { $0.hasPrefix(upper) }
  }
}

/// Adjusts relative references when filling or copying formulas,
/// and shifts references after insert/delete row/column.
public nonisolated enum FormulaRewriter {
  public enum Axis {
    case row
    case column
  }

  public enum StructureChange {
    case insert(at: Int, count: Int)
    case delete(at: Int, count: Int)
  }

  /// Renames a defined-name token. Function calls keep their names.
  public static func renameDefinedName(_ raw: String, from old: String, to new: String) -> String {
    guard FormulaSyntax.isFormula(raw) else { return raw }
    guard old.caseInsensitiveCompare(new) != .orderedSame else { return raw }
    do {
      let expr = try FormulaParser.parse(raw)
      return "=" + serialize(renameExpr(expr, from: old, to: new))
    } catch {
      return raw
    }
  }

  /// Formula text normalized to a sheet anchor (shared fill / batch shape key).
  public static func shapeAnchorKey(raw: String, anchor: CellAddress) -> String {
    adjust(raw, rowDelta: -anchor.row, colDelta: -anchor.col)
  }

  /// Anchor key from an already-parsed expression (avoids re-parse during shape-strip planning).
  public static func shapeAnchorKey(expr: FormulaExpr, anchor: CellAddress) -> String {
    let anchored = adjustExpression(expr, rowDelta: -anchor.row, colDelta: -anchor.col)
    return serialize(anchored)
  }

  /// Expected stored formula text after shifting `expr` by row/column delta.
  public static func adjustedFormulaText(expr: FormulaExpr, rowDelta: Int, colDelta: Int) -> String
  {
    "=" + serialize(adjustExpression(expr, rowDelta: rowDelta, colDelta: colDelta))
  }

  /// Shift a parsed expression by relative row/column delta (fill / batch eval only).
  public static func adjustExpression(_ expr: FormulaExpr, rowDelta: Int, colDelta: Int)
    -> FormulaExpr
  {
    adjustExpr(expr, rowDelta: rowDelta, colDelta: colDelta)
  }

  /// Returns adjusted formula text (including leading `=`), or the original raw if not a formula / unparseable.
  public static func adjust(_ raw: String, rowDelta: Int, colDelta: Int) -> String {
    guard FormulaSyntax.isFormula(raw) else { return raw }
    guard rowDelta != 0 || colDelta != 0 else { return raw }
    do {
      let expr = try FormulaParser.parse(raw)
      let adjusted = adjustExpr(expr, rowDelta: rowDelta, colDelta: colDelta)
      return "=" + serialize(adjusted)
    } catch {
      return raw
    }
  }

  /// Shifts references that point at `mutatedSheet` after insert/delete.
  /// Absolute ($A$1) and relative refs both move — matching Excel structure edits.
  public static func shiftForStructure(
    _ raw: String,
    formulaSheetName: String,
    mutatedSheetName: String,
    axis: Axis,
    change: StructureChange
  ) -> String {
    guard FormulaSyntax.isFormula(raw) else { return raw }
    do {
      let expr = try FormulaParser.parse(raw)
      let shifted = shiftExpr(
        expr,
        formulaSheetName: formulaSheetName,
        mutatedSheetName: mutatedSheetName,
        axis: axis,
        change: change
      )
      return "=" + serialize(shifted)
    } catch {
      return raw
    }
  }

  private static func renameExpr(_ expr: FormulaExpr, from old: String, to new: String)
    -> FormulaExpr
  {
    switch expr {
    case .namedRange(let name):
      if name.caseInsensitiveCompare(old) == .orderedSame { return .namedRange(new) }
      return expr
    case .unary(let op, let inner):
      return .unary(op, renameExpr(inner, from: old, to: new))
    case .binary(let op, let lhs, let rhs):
      return .binary(op, renameExpr(lhs, from: old, to: new), renameExpr(rhs, from: old, to: new))
    case .call(let name, let args):
      return .call(name, args.map { renameExpr($0, from: old, to: new) })
    default:
      return expr
    }
  }

  // MARK: - Fill / paste adjust

  private static func adjustExpr(_ expr: FormulaExpr, rowDelta: Int, colDelta: Int) -> FormulaExpr {
    switch expr {
    case .number, .string, .boolean, .error, .namedRange:
      return expr
    case .cellRef(let ref):
      if let next = ref.adjusted(rowDelta: rowDelta, colDelta: colDelta) {
        return .cellRef(next)
      }
      return .error(.ref)
    case .range(let start, let end):
      guard let s = start.adjusted(rowDelta: rowDelta, colDelta: colDelta),
        let e = end.adjusted(rowDelta: rowDelta, colDelta: colDelta)
      else { return .error(.ref) }
      return .range(s, e)
    case .unary(let op, let inner):
      return .unary(op, adjustExpr(inner, rowDelta: rowDelta, colDelta: colDelta))
    case .binary(let op, let lhs, let rhs):
      return .binary(
        op,
        adjustExpr(lhs, rowDelta: rowDelta, colDelta: colDelta),
        adjustExpr(rhs, rowDelta: rowDelta, colDelta: colDelta)
      )
    case .call(let name, let args):
      return .call(name, args.map { adjustExpr($0, rowDelta: rowDelta, colDelta: colDelta) })
    }
  }

  // MARK: - Structure shift

  private static func shiftExpr(
    _ expr: FormulaExpr,
    formulaSheetName: String,
    mutatedSheetName: String,
    axis: Axis,
    change: StructureChange
  ) -> FormulaExpr {
    switch expr {
    case .number, .string, .boolean, .error, .namedRange:
      return expr
    case .cellRef(let ref):
      return shiftRef(
        ref,
        formulaSheetName: formulaSheetName,
        mutatedSheetName: mutatedSheetName,
        axis: axis,
        change: change
      ).map { .cellRef($0) } ?? .error(.ref)
    case .range(let start, let end):
      guard
        let (s, e) = shiftRange(
          start,
          end,
          formulaSheetName: formulaSheetName,
          mutatedSheetName: mutatedSheetName,
          axis: axis,
          change: change
        )
      else { return .error(.ref) }
      return .range(s, e)
    case .unary(let op, let inner):
      return .unary(
        op,
        shiftExpr(
          inner,
          formulaSheetName: formulaSheetName,
          mutatedSheetName: mutatedSheetName,
          axis: axis,
          change: change
        )
      )
    case .binary(let op, let lhs, let rhs):
      return .binary(
        op,
        shiftExpr(
          lhs,
          formulaSheetName: formulaSheetName,
          mutatedSheetName: mutatedSheetName,
          axis: axis,
          change: change
        ),
        shiftExpr(
          rhs,
          formulaSheetName: formulaSheetName,
          mutatedSheetName: mutatedSheetName,
          axis: axis,
          change: change
        )
      )
    case .call(let name, let args):
      return .call(
        name,
        args.map {
          shiftExpr(
            $0,
            formulaSheetName: formulaSheetName,
            mutatedSheetName: mutatedSheetName,
            axis: axis,
            change: change
          )
        }
      )
    }
  }

  /// Shifts a range as a whole. Inserts move each end on its own. A delete becomes `#REF!` only
  /// when every row (or column) of the range is deleted; otherwise the range shrinks by the
  /// deleted rows inside it, even when a deleted row is its first or last one.
  private static func shiftRange(
    _ start: FormulaRef,
    _ end: FormulaRef,
    formulaSheetName: String,
    mutatedSheetName: String,
    axis: Axis,
    change: StructureChange
  ) -> (FormulaRef, FormulaRef)? {
    guard case .delete(let index, let count) = change else {
      guard
        let s = shiftRef(
          start, formulaSheetName: formulaSheetName, mutatedSheetName: mutatedSheetName,
          axis: axis, change: change),
        let e = shiftRef(
          end, formulaSheetName: formulaSheetName, mutatedSheetName: mutatedSheetName,
          axis: axis, change: change)
      else { return nil }
      return (s, e)
    }
    let target = start.sheet ?? end.sheet ?? formulaSheetName
    guard target.caseInsensitiveCompare(mutatedSheetName) == .orderedSame, count > 0 else {
      return (start, end)
    }
    let first = axis == .row ? start.row : start.col
    let last = axis == .row ? end.row : end.col
    let low = min(first, last)
    let high = max(first, last)
    // A whole-row or whole-column reference along this axis does not move.
    guard low < FormulaRef.open else { return (start, end) }
    let deleteEnd = index.addingReportingOverflow(count)
    let afterDeleted = deleteEnd.overflow ? Int.max : deleteEnd.partialValue
    let highIsOpen = high >= FormulaRef.open
    if index <= low && afterDeleted > high && !highIsOpen { return nil }

    func moved(_ position: Int, isLow: Bool) -> Int {
      if position >= FormulaRef.open { return position }
      if position < index { return position }
      if position >= afterDeleted { return position - count }
      // Inside the deleted rows: the low end lands on the first row after them, the high end
      // on the last row before them.
      return isLow ? index : index - 1
    }
    let newLow = moved(low, isLow: true)
    let newHigh = moved(high, isLow: false)
    var s = start
    var e = end
    let startIsLow = first <= last
    let newFirst = startIsLow ? newLow : newHigh
    let newLast = startIsLow ? newHigh : newLow
    if axis == .row {
      s.row = newFirst
      e.row = newLast
    } else {
      s.col = newFirst
      e.col = newLast
    }
    return (s, e)
  }

  private static func shiftRef(
    _ ref: FormulaRef,
    formulaSheetName: String,
    mutatedSheetName: String,
    axis: Axis,
    change: StructureChange
  ) -> FormulaRef? {
    let target = ref.sheet ?? formulaSheetName
    guard target.caseInsensitiveCompare(mutatedSheetName) == .orderedSame else {
      return ref
    }

    switch (axis, change) {
    case (.row, .insert(let index, let count)):
      guard !ref.isRowOpen else { return ref }
      var next = ref
      if next.row >= index { next.row += count }
      return next
    case (.column, .insert(let index, let count)):
      guard !ref.isColOpen else { return ref }
      var next = ref
      if next.col >= index { next.col += count }
      return next
    case (.row, .delete(let index, let count)):
      guard !ref.isRowOpen else { return ref }
      if ref.row >= index && ref.row < index + count { return nil }
      var next = ref
      if next.row >= index + count { next.row -= count }
      return next
    case (.column, .delete(let index, let count)):
      guard !ref.isColOpen else { return ref }
      if ref.col >= index && ref.col < index + count { return nil }
      var next = ref
      if next.col >= index + count { next.col -= count }
      return next
    }
  }

  // MARK: - Serialize

  public static func serialize(_ expr: FormulaExpr) -> String {
    switch expr {
    case .number(let n):
      if n.rounded() == n, abs(n) < 1e15 {
        return String(Int(n))
      }
      return String(n)
    case .string(let s):
      let escaped = s.replacingOccurrences(of: "\"", with: "\"\"")
      return "\"\(escaped)\""
    case .boolean(let b):
      return b ? "TRUE" : "FALSE"
    case .error(let e):
      return e.displayCode
    case .namedRange(let name):
      return name
    case .cellRef(let ref):
      return A1Reference.format(ref)
    case .range(let start, let end):
      return A1Reference.formatRange(start: start, end: end)
    case .unary(let op, let inner):
      let prefix = op == .negate ? "-" : "+"
      let needsParens = needsParensForUnary(inner)
      let body = serialize(inner)
      return needsParens ? "\(prefix)(\(body))" : "\(prefix)\(body)"
    case .binary(let op, let lhs, let rhs):
      return serializeBinary(op, lhs, rhs)
    case .call(let name, let args):
      if name == FormulaExpr.anchorArrayFunction, args.count == 1,
        case .cellRef(let ref) = args[0]
      {
        return A1Reference.format(ref) + "#"
      }
      let joined = args.map(serialize).joined(separator: ",")
      return "\(name)(\(joined))"
    }
  }

  private static func serializeBinary(_ op: BinaryOp, _ lhs: FormulaExpr, _ rhs: FormulaExpr)
    -> String
  {
    let symbol: String
    switch op {
    case .add: symbol = "+"
    case .subtract: symbol = "-"
    case .multiply: symbol = "*"
    case .divide: symbol = "/"
    case .power: symbol = "^"
    case .concat: symbol = "&"
    case .eq: symbol = "="
    case .ne: symbol = "<>"
    case .lt: symbol = "<"
    case .gt: symbol = ">"
    case .le: symbol = "<="
    case .ge: symbol = ">="
    }
    // The tree holds the grouping, so it has to be written back. Without this,
    // `ROUND($E3*$J3*(1-$F3),2)` came back from a sort as `ROUND($E3*$J3*1-$F3,2)`.
    let left = serialize(lhs)
    let right = serialize(rhs)
    let level = precedence(op)
    let leftNeeds: Bool
    let rightNeeds: Bool
    if case .binary(let inner, _, _) = lhs {
      // `^` groups from the right in this parser, so an equal-level left side needs brackets.
      leftNeeds = precedence(inner) < level || (precedence(inner) == level && op == .power)
    } else {
      leftNeeds = false
    }
    if case .binary(let inner, _, _) = rhs {
      // Every other operator groups from the left, so an equal-level right side needs brackets.
      rightNeeds = precedence(inner) < level || (precedence(inner) == level && op != .power)
    } else {
      rightNeeds = false
    }
    return (leftNeeds ? "(\(left))" : left) + symbol + (rightNeeds ? "(\(right))" : right)
  }

  /// The parser's levels, loosest first: comparison, `&`, `+ -`, `* /`, `^`.
  private static func precedence(_ op: BinaryOp) -> Int {
    switch op {
    case .eq, .ne, .lt, .gt, .le, .ge: return 1
    case .concat: return 2
    case .add, .subtract: return 3
    case .multiply, .divide: return 4
    case .power: return 5
    }
  }

  private static func needsParensForUnary(_ expr: FormulaExpr) -> Bool {
    switch expr {
    case .binary, .unary: return true
    default: return false
    }
  }
}
