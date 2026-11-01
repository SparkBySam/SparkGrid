import Foundation
import SparkGridCore

/// Conditional-format rules carried with a cell copy.
///
/// Rules that intersect the copied bounds are clipped to that bounds, then
/// retargeted onto the paste destination. Formula predicates shift with
/// `FormulaRewriter`, the same adjustment a relative formula paste uses.
enum ConditionalFormatPaste {
  static func capture(
    from sheet: Sheet,
    bounds: CellRange
  ) -> SpreadsheetClipboard.ConditionalFormatClipboardPayload? {
    let rules = sheet.conditionalFormats.compactMap { clip($0, to: bounds) }
    guard !rules.isEmpty else { return nil }
    let origin = topLeft(bounds)
    return SpreadsheetClipboard.ConditionalFormatClipboardPayload(
      originRow: origin.row,
      originCol: origin.col,
      rules: rules
    )
  }

  static func retargetedRules(
    _ payload: SpreadsheetClipboard.ConditionalFormatClipboardPayload,
    to destination: CellAddress,
    maxRow: Int,
    maxCol: Int
  ) -> [ConditionalFormatRule] {
    let rowDelta = destination.row - payload.originRow
    let colDelta = destination.col - payload.originCol
    return payload.rules.compactMap { rule in
      retarget(rule, rowDelta: rowDelta, colDelta: colDelta, maxRow: maxRow, maxCol: maxCol)
    }
  }

  /// Smallest range covering every rule that intersects `range`.
  static func coveredBounds(on sheet: Sheet, intersecting range: CellRange) -> CellRange? {
    var minRow = Int.max
    var maxRow = Int.min
    var minCol = Int.max
    var maxCol = Int.min
    var found = false
    for rule in sheet.conditionalFormats {
      guard let hit = intersection(rule.range, range) else { continue }
      let n = hit.normalized
      found = true
      minRow = min(minRow, n.minRow)
      maxRow = max(maxRow, n.maxRow)
      minCol = min(minCol, n.minCol)
      maxCol = max(maxCol, n.maxCol)
    }
    guard found else { return nil }
    return CellRange(
      start: CellAddress(row: minRow, col: minCol),
      end: CellAddress(row: maxRow, col: maxCol)
    )
  }

  static func intersection(_ a: CellRange, _ b: CellRange) -> CellRange? {
    let an = a.normalized
    let bn = b.normalized
    let minRow = max(an.minRow, bn.minRow)
    let maxRow = min(an.maxRow, bn.maxRow)
    let minCol = max(an.minCol, bn.minCol)
    let maxCol = min(an.maxCol, bn.maxCol)
    guard minRow <= maxRow, minCol <= maxCol else { return nil }
    return CellRange(
      start: CellAddress(row: minRow, col: minCol),
      end: CellAddress(row: maxRow, col: maxCol)
    )
  }

  static func sameAppearance(_ lhs: ConditionalFormatRule, _ rhs: ConditionalFormatRule) -> Bool {
    let a = lhs.range.normalized
    let b = rhs.range.normalized
    return a.minRow == b.minRow && a.maxRow == b.maxRow && a.minCol == b.minCol
      && a.maxCol == b.maxCol
      && lhs.stopIfTrue == rhs.stopIfTrue
      && lhs.predicate == rhs.predicate
      && lhs.style == rhs.style
  }

  private static func clip(_ rule: ConditionalFormatRule, to bounds: CellRange)
    -> ConditionalFormatRule?
  {
    guard let clipped = intersection(rule.range, bounds) else { return nil }
    let from = topLeft(rule.range)
    let to = topLeft(clipped)
    var next = rule
    next.range = clipped
    next.predicate = shift(rule.predicate, rowDelta: to.row - from.row, colDelta: to.col - from.col)
    return next
  }

  private static func retarget(
    _ rule: ConditionalFormatRule,
    rowDelta: Int,
    colDelta: Int,
    maxRow: Int,
    maxCol: Int
  ) -> ConditionalFormatRule? {
    let n = rule.range.normalized
    let minRow = max(0, n.minRow + rowDelta)
    let maxRowClamped = min(maxRow, n.maxRow + rowDelta)
    let minCol = max(0, n.minCol + colDelta)
    let maxColClamped = min(maxCol, n.maxCol + colDelta)
    guard minRow <= maxRowClamped, minCol <= maxColClamped else { return nil }
    var next = rule
    next.id = UUID()
    next.range = CellRange(
      start: CellAddress(row: minRow, col: minCol),
      end: CellAddress(row: maxRowClamped, col: maxColClamped)
    )
    next.predicate = shift(
      rule.predicate,
      rowDelta: minRow - n.minRow,
      colDelta: minCol - n.minCol
    )
    return next
  }

  private static func shift(
    _ predicate: ConditionalFormatPredicate,
    rowDelta: Int,
    colDelta: Int
  ) -> ConditionalFormatPredicate {
    guard case .formula(let raw) = predicate, rowDelta != 0 || colDelta != 0 else {
      return predicate
    }
    return .formula(shiftFormula(raw, rowDelta: rowDelta, colDelta: colDelta))
  }

  /// Moves relative references by the paste offset. Absolute references stay put.
  private static func shiftFormula(_ raw: String, rowDelta: Int, colDelta: Int) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return raw }
    let hadEquals = trimmed.hasPrefix("=")
    let source = hadEquals ? trimmed : "=\(trimmed)"
    let adjusted = FormulaRewriter.adjust(source, rowDelta: rowDelta, colDelta: colDelta)
    if hadEquals || !adjusted.hasPrefix("=") { return adjusted }
    return String(adjusted.dropFirst())
  }

  private static func topLeft(_ range: CellRange) -> CellAddress {
    let n = range.normalized
    return CellAddress(row: n.minRow, col: n.minCol)
  }
}
