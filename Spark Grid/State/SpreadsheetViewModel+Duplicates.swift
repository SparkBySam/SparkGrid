import Foundation
import SparkGridCore

/// Finding repeated rows: a live, temporary highlight, and Remove Duplicates.
extension SpreadsheetViewModel {
  /// Which rows to compare and how.
  struct DuplicateRequest: Equatable {
    var sheetID: UUID
    var range: CellRange
    var hasHeader: Bool
    /// Absolute columns that must all match for two rows to count as the same.
    var columns: [Int]
    /// Shade rows that appear once instead of rows that repeat.
    var unique: Bool
  }

  struct DuplicateScanKey: Equatable {
    var request: DuplicateRequest
    var contentRevision: Int
    var engineRevision: Int
  }

  struct DuplicateScan: Equatable {
    /// Rows that share their values with another row, in groups, first row first.
    var groups: [[Int]]
    /// Rows whose values appear once.
    var uniqueRows: [Int]
    /// Rows that Remove Duplicates would delete: each group but its first row.
    var repeatRows: [Int] { groups.flatMap { $0.dropFirst() } }
    var duplicateRowCount: Int { groups.reduce(0) { $0 + $1.count } }
  }

  /// The block the Duplicates tools start from: the selection, or the table around one cell,
  /// cut to the filled part of the sheet.
  func duplicateRange() -> CellRange? {
    var range = selectionRange
    if range.isSingleCell { range = filterRangeForSingleCell(selectionAnchor) }
    guard let filled = activeSheet.populatedBounds?.normalized else { return nil }
    let n = range.normalized
    let clipped = CellRange(
      start: CellAddress(row: max(n.minRow, filled.minRow), col: max(n.minCol, filled.minCol)),
      end: CellAddress(row: min(n.maxRow, filled.maxRow), col: min(n.maxCol, filled.maxCol)))
    let c = clipped.normalized
    guard c.minRow <= c.maxRow, c.minCol <= c.maxCol else { return nil }
    return clipped
  }

  /// True when the first row reads as column names: all text, and the next row isn't.
  func duplicateRangeLooksHeaded(_ range: CellRange) -> Bool {
    let n = range.normalized
    guard n.maxRow > n.minRow else { return false }
    let first = (n.minCol...n.maxCol).map { displayValue(at: CellAddress(row: n.minRow, col: $0)) }
    guard first.allSatisfy({ if case .string(let text) = $0 { !text.isEmpty } else { false } })
    else { return false }
    let second = (n.minCol...n.maxCol).map {
      displayValue(at: CellAddress(row: n.minRow + 1, col: $0))
    }
    return second.contains { if case .string = $0 { false } else { true } }
      || first != second
  }

  /// Rows compared on `columns`, ignoring case and surrounding spaces. Rows a filter hides
  /// and rows blank in every compared column are left out.
  func scanDuplicates(_ request: DuplicateRequest) -> DuplicateScan {
    let key = DuplicateScanKey(
      request: request, contentRevision: contentRevision,
      engineRevision: formulaEngine.cacheRevision)
    if let cached = duplicateScanCache, cached.key == key { return cached.scan }
    let n = request.range.normalized
    let firstRow = n.minRow + (request.hasHeader ? 1 : 0)
    var order: [String] = []
    var rowsByKey: [String: [Int]] = [:]
    if firstRow <= n.maxRow, !request.columns.isEmpty {
      for row in firstRow...n.maxRow where !isRowHiddenByFilter(row) {
        let parts = request.columns.map {
          displayString(at: CellAddress(row: row, col: $0))
            .trimmingCharacters(in: .whitespaces).lowercased()
        }
        guard parts.contains(where: { !$0.isEmpty }) else { continue }
        let rowKey = parts.joined(separator: "\u{1F}")
        if rowsByKey[rowKey] == nil { order.append(rowKey) }
        rowsByKey[rowKey, default: []].append(row)
      }
    }
    var scan = DuplicateScan(groups: [], uniqueRows: [])
    for rowKey in order {
      let rows = rowsByKey[rowKey] ?? []
      if rows.count > 1 {
        scan.groups.append(rows)
      } else {
        scan.uniqueRows.append(contentsOf: rows)
      }
    }
    duplicateScanCache = (key, scan)
    return scan
  }

  /// The shaded cells for the active sheet, worked out again after each edit.
  var duplicateHighlightCells: Set<CellAddress> {
    guard let request = duplicateHighlight, request.sheetID == activeSheet.id else { return [] }
    let scan = scanDuplicates(request)
    let rows = request.unique ? scan.uniqueRows : scan.groups.flatMap { $0 }
    var cells = Set<CellAddress>()
    for row in rows {
      for col in request.columns { cells.insert(CellAddress(row: row, col: col)) }
    }
    return cells
  }

  /// `12 duplicate rows in 4 groups` or `9 unique rows`, for the bottom bar.
  var duplicateHighlightSummary: String? {
    guard let request = duplicateHighlight, request.sheetID == activeSheet.id else { return nil }
    let scan = scanDuplicates(request)
    if request.unique {
      let count = scan.uniqueRows.count
      return count == 0 ? "No unique rows" : "\(count) unique \(count == 1 ? "row" : "rows")"
    }
    guard !scan.groups.isEmpty else { return "No duplicates" }
    let rows = scan.duplicateRowCount
    let groups = scan.groups.count
    return "\(rows) duplicate rows in \(groups) \(groups == 1 ? "group" : "groups")"
  }

  /// Shades repeated, or one-off, values in the selection until cleared. A single cell
  /// compares down its own column.
  func highlightRepeats(unique: Bool) {
    commitEditIfNeeded()
    guard let range = duplicateRange() else { return }
    var request = DuplicateRequest(
      sheetID: activeSheet.id, range: range, hasHeader: duplicateRangeLooksHeaded(range),
      columns: Array(range.normalized.minCol...range.normalized.maxCol), unique: unique)
    if selectionRange.isSingleCell { request.columns = [selectionAnchor.col] }
    showDuplicateHighlight(request)
  }

  func showDuplicateHighlight(_ request: DuplicateRequest) {
    duplicateHighlight = request
    notifyGridRefresh()
  }

  func clearDuplicateHighlight() {
    guard duplicateHighlight != nil else { return }
    duplicateHighlight = nil
    duplicateScanCache = nil
    notifyGridRefresh()
  }

  /// Keeps the shading as a highlight rule saved with the file.
  func keepDuplicateHighlightAsRule() {
    guard let request = duplicateHighlight, request.sheetID == activeSheet.id else { return }
    let n = request.range.normalized
    let firstRow = n.minRow + (request.hasHeader ? 1 : 0)
    guard firstRow <= n.maxRow else { return }
    let before = activeSheet.conditionalFormats
    let added = request.columns.map { col in
      ConditionalFormatRule(
        range: CellRange(
          start: CellAddress(row: firstRow, col: col), end: CellAddress(row: n.maxRow, col: col)),
        predicate: request.unique ? .uniqueValues : .duplicateValues,
        style: request.unique ? .greenFill : .redFill)
    }
    applyConditionalFormats(
      before + added, undoBefore: before,
      actionName: request.unique ? "Highlight Unique Values" : "Highlight Duplicates")
    clearDuplicateHighlight()
  }
}
