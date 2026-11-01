import Foundation

/// Zero-based row and column index into a sheet.
/// `nonisolated` so Hashable/Codable work under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
public nonisolated struct CellAddress: Hashable, Codable, Sendable {
  public var row: Int
  public var col: Int

  public init(row: Int, col: Int) {
    self.row = row
    self.col = col
  }

  public static let origin = CellAddress(row: 0, col: 0)
}

extension CellAddress: Comparable {
  public static func < (lhs: CellAddress, rhs: CellAddress) -> Bool {
    if lhs.row != rhs.row { return lhs.row < rhs.row }
    return lhs.col < rhs.col
  }
}

extension CellAddress {
  /// Column label for headers and the formula bar (A, B, …, Z, AA, …).
  public var columnLabel: String { A1Notation.columnLabel(for: col) }

  /// A1-style reference (e.g. `B3`).
  public var a1: String { "\(columnLabel)\(row + 1)" }
}
