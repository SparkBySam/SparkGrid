import Foundation
import GridCore

/// A cell reference inside a formula, optionally sheet-qualified, with absolute flags.
public nonisolated struct FormulaRef: Equatable, Hashable, Sendable {
  /// Sentinel for open-ended row/column bounds (e.g. `A2:A`, `A:A`).
  public static let open = Int.max / 4

  public var sheet: String?
  public var row: Int
  public var col: Int
  public var absRow: Bool
  public var absCol: Bool

  public init(sheet: String? = nil, row: Int, col: Int, absRow: Bool, absCol: Bool) {
    self.sheet = sheet
    self.row = row
    self.col = col
    self.absRow = absRow
    self.absCol = absCol
  }

  public var address: CellAddress {
    CellAddress(row: isRowOpen ? 0 : row, col: isColOpen ? 0 : col)
  }

  public var isRowOpen: Bool { row >= Self.open }
  public var isColOpen: Bool { col >= Self.open }
  public var isLocal: Bool { sheet == nil }

  public func isOnSheet(_ name: String) -> Bool {
    guard let sheet else { return true }
    return sheet.caseInsensitiveCompare(name) == .orderedSame
  }

  public func adjusted(rowDelta: Int, colDelta: Int) -> FormulaRef? {
    let newRow: Int
    if isRowOpen || absRow {
      newRow = row
    } else {
      newRow = row + rowDelta
      guard newRow >= 0 else { return nil }
    }
    let newCol: Int
    if isColOpen || absCol {
      newCol = col
    } else {
      newCol = col + colDelta
      guard newCol >= 0 else { return nil }
    }
    return FormulaRef(sheet: sheet, row: newRow, col: newCol, absRow: absRow, absCol: absCol)
  }
}

public nonisolated indirect enum FormulaExpr: Equatable, Hashable {
  /// `G1#` parses as a call of this function on `G1`, the name files save it under.
  public static let anchorArrayFunction = "ANCHORARRAY"
  /// `X:Y` where X or Y is not a plain cell, as in `B1:INDEX(B:B,5)` or `INDIRECT("B1"):B9`.
  public static let rangeOperatorFunction = "SG.RANGE"
  /// `X Y`, two references with a space between: the cells they share.
  public static let intersectionFunction = "SG.INTERSECT"

  case number(Double)
  case string(String)
  case boolean(Bool)
  case error(FormulaError)
  case namedRange(String)
  case cellRef(FormulaRef)
  case range(FormulaRef, FormulaRef)
  case unary(UnaryOp, FormulaExpr)
  case binary(BinaryOp, FormulaExpr, FormulaExpr)
  case call(String, [FormulaExpr])
  /// An argument left out between commas, as in `IF(A2>1,,2)` or `VLOOKUP(A1,B:C,2,)`. It reads
  /// as a blank: 0 to arithmetic and FALSE to a yes-or-no argument, as other apps read it.
  case missing
  /// A list typed in the formula, as in `{1,2,3}`, `{1;2;3}` or `{1,2;3,4}`: rows of numbers,
  /// text, TRUE/FALSE or errors. Commas separate items in a row, semicolons separate rows.
  case array([[FormulaExpr]])
}

public nonisolated enum UnaryOp: Equatable, Hashable {
  case negate
  case plus
  /// Postfix `%`: the value divided by 100.
  case percent
}

public nonisolated enum BinaryOp: Equatable, Hashable {
  case add
  case subtract
  case multiply
  case divide
  case power
  case concat
  case eq
  case ne
  case lt
  case gt
  case le
  case ge
}
