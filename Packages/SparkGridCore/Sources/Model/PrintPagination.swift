import Foundation

/// Splits a printed range into pages along row and column edges, so no row or column is cut
/// across two pages. Manual page breaks start a new page at their row or column.
public nonisolated enum PrintPagination {
  /// One printed page: the rows and columns it shows.
  public struct Page: Equatable, Sendable {
    public var rows: ClosedRange<Int>
    public var columns: ClosedRange<Int>

    public init(rows: ClosedRange<Int>, columns: ClosedRange<Int>) {
      self.rows = rows
      self.columns = columns
    }
  }

  /// Runs of indexes that each fit in `available`. `sizes[i]` is the size of `first + i`; a size of
  /// zero (a hidden row) takes no room. A break at index `b` starts a page at `b`. An item larger
  /// than a page gets a page to itself.
  public static func split(
    first: Int,
    sizes: [Double],
    available: Double,
    breaks: Set<Int> = []
  ) -> [ClosedRange<Int>] {
    guard !sizes.isEmpty else { return [] }
    let room = max(available, 1)
    var runs: [ClosedRange<Int>] = []
    var start = first
    var used = 0.0
    for (offset, size) in sizes.enumerated() {
      let index = first + offset
      if index > start, breaks.contains(index) || (used > 0 && used + size > room + 0.001) {
        runs.append(start...(index - 1))
        start = index
        used = 0
      }
      used += size
    }
    runs.append(start...(first + sizes.count - 1))
    return runs
  }

  /// Every page, in print order.
  /// - Parameters:
  ///   - overThenDown: true prints across a band of rows before moving down.
  public static func pages(
    rows: [ClosedRange<Int>],
    columns: [ClosedRange<Int>],
    overThenDown: Bool
  ) -> [Page] {
    var result: [Page] = []
    if overThenDown {
      for r in rows { for c in columns { result.append(Page(rows: r, columns: c)) } }
    } else {
      for c in columns { for r in rows { result.append(Page(rows: r, columns: c)) } }
    }
    return result
  }
}
