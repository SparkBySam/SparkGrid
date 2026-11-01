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
}

public nonisolated enum UnaryOp: Equatable, Hashable {
  case negate
  case plus
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
