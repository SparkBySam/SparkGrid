import Foundation
import SparkGridCore

/// The numbers in the selection, shown at the bottom right, and AutoSum.
extension SpreadsheetViewModel {
  enum SelectionStat: String, CaseIterable, Identifiable {
    case sum, average, minimum, maximum, count, countNumbers

    var id: String { rawValue }

    var title: String {
      switch self {
      case .sum: return "Sum"
      case .average: return "Average"
      case .minimum: return "Min"
      case .maximum: return "Max"
      case .count: return "Count"
      case .countNumbers: return "Count Numbers"
      }
    }
  }

  struct SelectionStats: Equatable {
    /// Cells with anything in them.
    var count = 0
    var numericCount = 0
    var sum: Double = 0
    var minimum: Double = .infinity
    var maximum: Double = -.infinity
    /// The first number's format, so a sum of dollars reads as dollars.
    var format: CellFormat?

    func value(_ stat: SelectionStat) -> Double? {
      switch stat {
      case .sum: return numericCount > 0 ? sum : nil
      case .average: return numericCount > 0 ? sum / Double(numericCount) : nil
      case .minimum: return numericCount > 0 ? minimum : nil
      case .maximum: return numericCount > 0 ? maximum : nil
      case .count: return Double(count)
      case .countNumbers: return Double(numericCount)
      }
    }
  }

  /// A cell on its own shows nothing. Rows a filter hides are left out, as other apps do.
  var selectionStats: SelectionStats? {
    let ranges = selectionRanges.isEmpty ? [selectionRange] : selectionRanges
    guard ranges.count > 1 || !(ranges.first?.isSingleCell ?? true) else { return nil }
    let key = SelectionStatsKey(
      contentRevision: contentRevision, engineRevision: formulaEngine.cacheRevision,
      ranges: ranges)
    if let cached = selectionStatsCache, cached.key == key { return cached.stats }
    let stats = computeSelectionStats(ranges)
    selectionStatsCache = (key, stats)
    return stats
  }

  struct SelectionStatsKey: Equatable {
    var contentRevision: Int
    var engineRevision: Int
    var ranges: [CellRange]
  }

  private func computeSelectionStats(_ ranges: [CellRange]) -> SelectionStats {
    let sheet = activeSheet
    var stats = SelectionStats()
    var visited = Set<CellAddress>()
    func visit(_ address: CellAddress) {
      guard visited.insert(address).inserted, !isRowHiddenByFilter(address.row),
        !sheet.isCoveredByMerge(address)
      else { return }
      let value = displayValue(at: address)
      switch value {
      case .blank:
        return
      case .number(let number) where number.isFinite:
        stats.count += 1
        stats.numericCount += 1
        stats.sum += number
        stats.minimum = min(stats.minimum, number)
        stats.maximum = max(stats.maximum, number)
        if stats.format == nil { stats.format = sheet.cell(at: address).format }
      default:
        stats.count += 1
      }
    }
    for range in ranges {
      let n = range.normalized
      let area = (n.maxRow - n.minRow + 1) * (n.maxCol - n.minCol + 1)
      // A whole column is a million mostly empty cells. Visit the cells that exist.
      if area > 50_000 {
        for address in sheet.cells.keys where range.contains(address) {
          visit(address)
        }
      } else {
        for row in n.minRow...n.maxRow {
          for col in n.minCol...n.maxCol {
            visit(CellAddress(row: row, col: col))
          }
        }
      }
    }
    return stats
  }

  /// A statistic as the cells it came from would show it: `$41,362,409` or `1,024.5`.
  func selectionStatText(_ stat: SelectionStat, in stats: SelectionStats) -> String? {
    guard let value = stats.value(stat) else { return nil }
    if stat == .count || stat == .countNumbers {
      return value.formatted(.number.precision(.fractionLength(0)))
    }
    let format = stats.format ?? CellFormat()
    if format.numberFormat == .general || format.numberFormat == .date
      || format.numberFormat == .time
    {
      return value.formatted(.number.precision(.fractionLength(0...2)))
    }
    return CellFormatRenderer.displayText(for: .number(value), format: format, fallbackRaw: "")
  }

  // MARK: - AutoSum

  /// Adds the numbers above, or else to the left of, the selected cell. With several cells
  /// selected, each column gets a total in the first empty cell below it. One undo step.
  func autoSum() {
    commitEditIfNeeded()
    let range = selectionRange.normalized
    undoManager?.beginUndoGrouping()
    defer {
      undoManager?.endUndoGrouping()
      undoManager?.setActionName("AutoSum")
    }
    if selectionRange.isSingleCell {
      let target = selectionAnchor
      if let block = numberRun(from: target, rowStep: -1, colStep: 0)
        ?? numberRun(from: target, rowStep: 0, colStep: -1)
      {
        setCellValue("=SUM(\(block.a1Label))", at: target)
      }
      return
    }
    // A whole column or row stops at the filled part of the sheet, so the total goes under it.
    guard let filled = activeSheet.populatedBounds?.normalized else { return }
    let lastRow = min(range.maxRow, filled.maxRow)
    let lastCol = min(range.maxCol, filled.maxCol)
    guard range.minRow <= lastRow, range.minCol <= lastCol else { return }
    for col in range.minCol...lastCol {
      let top = CellAddress(row: range.minRow, col: col)
      let bottom = CellAddress(row: lastRow, col: col)
      let hasNumber = (range.minRow...lastRow).contains {
        displayValue(at: CellAddress(row: $0, col: col)).asNumber != nil
      }
      guard hasNumber else { continue }
      var below = lastRow + 1
      while below < activeSheet.effectiveRowCount,
        !activeSheet.cell(at: CellAddress(row: below, col: col)).raw.isEmpty
      {
        below += 1
      }
      guard below < activeSheet.effectiveRowCount else { continue }
      setCellValue(
        "=SUM(\(CellRange(start: top, end: bottom).a1Label))",
        at: CellAddress(row: below, col: col))
    }
  }

  /// The block of numbers next to `start`, walking up or left, skipping a header above it.
  private func numberRun(from start: CellAddress, rowStep: Int, colStep: Int) -> CellRange? {
    var end: CellAddress?
    var first: CellAddress?
    var row = start.row + rowStep
    var col = start.col + colStep
    while row >= 0, col >= 0 {
      let address = CellAddress(row: row, col: col)
      guard displayValue(at: address).asNumber != nil else { break }
      if end == nil { end = address }
      first = address
      row += rowStep
      col += colStep
    }
    guard let first, let end else { return nil }
    return CellRange(start: first, end: end)
  }
}
