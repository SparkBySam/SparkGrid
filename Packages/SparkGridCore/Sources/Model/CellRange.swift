import Formula
import Foundation
import GridCore
import NumberFormat

public nonisolated struct CellRange: Codable, Equatable, Sendable {
  public var start: CellAddress
  public var end: CellAddress

  public init(start: CellAddress, end: CellAddress) {
    self.start = start
    self.end = end
  }

  public static let singleOrigin = CellRange(start: .origin, end: .origin)

  public var normalized: (minRow: Int, maxRow: Int, minCol: Int, maxCol: Int) {
    (
      min(start.row, end.row),
      max(start.row, end.row),
      min(start.col, end.col),
      max(start.col, end.col)
    )
  }

  public func contains(_ address: CellAddress) -> Bool {
    let n = normalized
    return address.row >= n.minRow && address.row <= n.maxRow
      && address.col >= n.minCol && address.col <= n.maxCol
  }

  public func allAddresses() -> [CellAddress] {
    let n = normalized
    var addresses: [CellAddress] = []
    for row in n.minRow...n.maxRow {
      for col in n.minCol...n.maxCol {
        addresses.append(CellAddress(row: row, col: col))
      }
    }
    return addresses
  }

  public var isSingleCell: Bool {
    start == end
  }

  public var a1Label: String {
    let n = normalized
    let start = CellAddress(row: n.minRow, col: n.minCol).a1
    let end = CellAddress(row: n.maxRow, col: n.maxCol).a1
    return start == end ? start : "\(start):\(end)"
  }

  /// `A1` or `A1:B2` on the current sheet. Sheet-qualified and open-ended text is left alone.
  public static func fromA1(_ text: String) -> CellRange? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !trimmed.contains("!") else { return nil }
    if let (start, end) = A1Reference.parseFormulaRange(trimmed) {
      guard start.sheet == nil, end.sheet == nil,
        !start.isRowOpen, !start.isColOpen, !end.isRowOpen, !end.isColOpen
      else { return nil }
      return CellRange(start: start.address, end: end.address)
    }
    if let ref = A1Reference.parseFormulaRef(trimmed), ref.sheet == nil, !ref.isRowOpen,
      !ref.isColOpen
    {
      return CellRange(start: ref.address, end: ref.address)
    }
    return nil
  }
}
