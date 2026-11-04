import AppKit
import Foundation
import SparkGridCore

/// A sort started from the filter popover, and where every row was before it.
struct FilterSortMemory: Equatable {
  var sheetID: UUID
  var range: CellRange
  var column: Int
  var ascending: Bool
  /// `originRows[i]` is the row the data in row `firstDataRow + i` held before the first sort.
  var originRows: [Int]
}

/// One value in a filter list, with how many rows hold it.
struct FilterValueCount: Equatable, Identifiable {
  var value: String
  var count: Int
  var id: String { value }
}

extension SpreadsheetViewModel {
  // MARK: - Find / Replace

  func showFindBar(replace: Bool) {
    isFindReplaceMode = replace
    isFindBarVisible = true
    if findScope == .selection {
      captureFindScopeRange()
    }
    refreshFindMatches(selectCurrent: true)
  }

  /// ⌘F / ⌥⌘F: open when hidden; switch mode when the other is requested; close on same-mode toggle.
  func toggleFindBar(replace: Bool) {
    if isFindBarVisible {
      if isFindReplaceMode != replace {
        isFindReplaceMode = replace
      } else {
        hideFindBar()
      }
    } else {
      showFindBar(replace: replace)
    }
  }

  func hideFindBar() {
    isFindBarVisible = false
    findMatches = []
    findMatchIndex = -1
    findScopeRange = nil
  }

  /// Drop cached matches when the active sheet or filter set changes.
  func invalidateFindMatches() {
    findMatches = []
    findMatchIndex = -1
    if isFindBarVisible {
      refreshFindMatches(selectCurrent: true)
    }
  }

  /// Capture the current selection as a stable Find-in-Selection range.
  func captureFindScopeRange() {
    guard findScope == .selection else {
      findScopeRange = nil
      return
    }
    if selectionRanges.count > 1 {
      findScopeRange = Self.boundingUnion(of: selectionRanges)
    } else {
      findScopeRange = selectionRange.normalizedRange
    }
  }

  func refreshFindMatches(selectCurrent: Bool = false) {
    if findScope == .selection, findScopeRange == nil {
      captureFindScopeRange()
    } else if findScope != .selection {
      findScopeRange = nil
    }
    findMatches = collectFindMatches()
    if findMatches.isEmpty {
      findMatchIndex = -1
      return
    }
    if selectCurrent {
      // Prefer a match at/after the selection.
      let start = selectionAnchor
      if let idx = findMatches.firstIndex(where: { $0 >= start }) {
        findMatchIndex = idx
      } else {
        findMatchIndex = 0
      }
      jumpToCurrentFindMatch()
    } else if findMatchIndex >= findMatches.count {
      findMatchIndex = findMatches.count - 1
    } else if findMatchIndex < 0 {
      findMatchIndex = 0
    }
  }

  func findNext() {
    guard !findQuery.isEmpty else {
      showFindBar(replace: isFindReplaceMode)
      return
    }
    // After close / sheet switch / empty cache, land on the current match first
    // instead of skipping straight to the next one.
    if findMatches.isEmpty {
      refreshFindMatches(selectCurrent: true)
      return
    }
    findMatchIndex = (findMatchIndex + 1) % findMatches.count
    jumpToCurrentFindMatch()
  }

  func findPrevious() {
    guard !findQuery.isEmpty else {
      showFindBar(replace: isFindReplaceMode)
      return
    }
    if findMatches.isEmpty {
      refreshFindMatches(selectCurrent: true)
      return
    }
    findMatchIndex = (findMatchIndex - 1 + findMatches.count) % findMatches.count
    jumpToCurrentFindMatch()
  }

  @discardableResult
  func replaceCurrent() -> Bool {
    refreshFindMatches()
    guard findMatchIndex >= 0, findMatchIndex < findMatches.count else { return false }
    let address = findMatches[findMatchIndex]
    guard replaceMatch(at: address) else { return false }
    refreshFindMatches()
    if findMatches.isEmpty {
      findMatchIndex = -1
      return true
    }
    findMatchIndex = min(findMatchIndex, findMatches.count - 1)
    jumpToCurrentFindMatch()
    return true
  }

  func replaceAll() -> Int {
    let matches = collectFindMatches()
    guard !matches.isEmpty else { return 0 }
    undoManager?.beginUndoGrouping()
    var count = 0
    for address in matches {
      if replaceMatch(at: address) { count += 1 }
    }
    undoManager?.endUndoGrouping()
    undoManager?.setActionName("Replace All")
    refreshFindMatches()
    return count
  }

  private func jumpToCurrentFindMatch() {
    guard findMatchIndex >= 0, findMatchIndex < findMatches.count else { return }
    let address = findMatches[findMatchIndex]
    select(address)
    requestScrollSelectionIntoView()
  }

  func requestScrollSelectionIntoView() {
    scrollRequestToken &+= 1
  }

  private func collectFindMatches() -> [CellAddress] {
    let query = findQuery
    guard !query.isEmpty else { return [] }
    let range: CellRange
    switch findScope {
    case .sheet:
      range = activeSheet.populatedRangeFromOrigin
    case .selection:
      range = findScopeRange ?? selectionRange.normalizedRange
    }
    let n = range.normalized
    var matches: [CellAddress] = []
    for row in n.minRow...n.maxRow {
      if isRowHiddenByFilter(row) { continue }
      for col in n.minCol...n.maxCol {
        let address = CellAddress(row: row, col: col)
        if cellMatchesFind(at: address) {
          matches.append(address)
        }
      }
    }
    return matches
  }

  private func cellMatchesFind(at address: CellAddress) -> Bool {
    let query = findQuery
    guard !query.isEmpty else { return false }
    let haystack = displayString(at: address)
    if findEntireCell {
      if findMatchCase {
        return haystack == query
      }
      return haystack.caseInsensitiveCompare(query) == .orderedSame
    }
    if findMatchCase {
      return haystack.contains(query)
    }
    return haystack.range(of: query, options: .caseInsensitive) != nil
  }

  private func replaceMatch(at address: CellAddress) -> Bool {
    let cell = activeSheet.cell(at: address)
    let display = displayString(at: address)
    guard cellMatchesFind(at: address) else { return false }

    if FormulaSyntax.isFormula(cell.raw) {
      // Prefer replacing inside raw formula text when the query appears there;
      // otherwise leave formulas alone when the match came only from computed display.
      let raw = cell.raw
      if let replaced = replacing(in: raw, query: findQuery, replacement: findReplaceText) {
        setCellValue(replaced, at: address)
        return true
      }
      return false
    }

    if findEntireCell {
      setCellValue(findReplaceText, at: address)
      return true
    }
    if let replaced = replacing(in: display, query: findQuery, replacement: findReplaceText) {
      setCellValue(replaced, at: address)
      return true
    }
    return false
  }

  private func replacing(in text: String, query: String, replacement: String) -> String? {
    guard !query.isEmpty else { return nil }
    if findMatchCase {
      guard text.contains(query) else { return nil }
      return text.replacingOccurrences(of: query, with: replacement)
    }

    // Case-insensitive: walk once left-to-right. Never re-search from the start,
    // or replacements that still contain the query (e.g. a → aa) loop forever.
    var result = ""
    result.reserveCapacity(text.count)
    var searchStart = text.startIndex
    var replaced = false
    while searchStart < text.endIndex,
      let match = text.range(
        of: query, options: .caseInsensitive, range: searchStart..<text.endIndex)
    {
      result.append(contentsOf: text[searchStart..<match.lowerBound])
      result.append(replacement)
      searchStart = match.upperBound
      replaced = true
    }
    guard replaced else { return nil }
    result.append(contentsOf: text[searchStart..<text.endIndex])
    return result
  }

  // MARK: - Sort

  func sortRange(
    column: Int,
    direction: SortDirection,
    hasHeader: Bool,
    then: [(column: Int, direction: SortDirection)] = []
  ) {
    commitEditIfNeeded()
    let range = effectiveSortRange()
    let n = range.normalized
    guard n.maxRow >= n.minRow, n.maxCol >= n.minCol else { return }
    guard column >= n.minCol, column <= n.maxCol else { return }

    let headerOffset = hasHeader ? 1 : 0
    let firstDataRow = n.minRow + headerOffset
    guard firstDataRow <= n.maxRow else { return }

    let rangeLabel = CellRange(
      start: CellAddress(row: n.minRow, col: n.minCol),
      end: CellAddress(row: n.maxRow, col: n.maxCol)
    ).a1Label
    guard
      applyCommand(
        "data.sort",
        [
          "sheet": activeSheet.name,
          "range": rangeLabel,
          "column": String(column),
          "ascending": direction == .ascending ? "true" : "false",
          "header": hasHeader ? "true" : "false",
          "then": then.map { "\($0.column):\($0.direction == .ascending ? "asc" : "desc")" }
            .joined(separator: ","),
        ],
        incremental: false
      )
    else { return }
    registerSortUndo(
      sheetName: activeSheet.name, rangeLabel: rangeLabel, column: column, hasHeader: hasHeader,
      firstDataRow: firstDataRow, appliedOrder: lastSortOrder, action: "Sort Range")
    notifyGridRefresh()
  }

  func effectiveSortRange() -> CellRange {
    let range = selectionRange
    if range.isSingleCell {
      return activeSheet.populatedBounds ?? .singleOrigin
    }
    return range
  }

  // MARK: - Filter

  func createFilter() {
    commitEditIfNeeded()
    var range = selectionRange
    if range.isSingleCell {
      range = filterRangeForSingleCell(selectionAnchor)
    } else if let trimmed = trimmedFilterRange(from: range) {
      range = trimmed
    }
    var n = range.normalized
    // If the block starts below row 1 and the row above looks like headers, include it.
    if n.minRow > 0 {
      let headerRow = n.minRow - 1
      var headerHasContent = false
      for col in n.minCol...n.maxCol {
        if !activeSheet.cell(at: CellAddress(row: headerRow, col: col)).raw.isEmpty {
          headerHasContent = true
          break
        }
      }
      if headerHasContent {
        range = CellRange(
          start: CellAddress(row: headerRow, col: n.minCol),
          end: CellAddress(row: n.maxRow, col: n.maxCol)
        )
        n = range.normalized
      }
    }
    guard n.maxRow > n.minRow else {
      let alert = NSAlert()
      alert.messageText = "Select at least two rows to create a filter."
      alert.informativeText = "Filters need a header row and at least one data row."
      alert.alertStyle = .informational
      alert.addButton(withTitle: "OK")
      // Attached to the window, so the rest of the app stays usable.
      if let window = NSApp.keyWindow {
        alert.beginSheetModal(for: window)
      } else {
        alert.runModal()
      }
      return
    }
    applyFilterChange(SheetFilterState(range: range), action: "Create Filter")
  }

  /// Every filter change goes through here, so Undo puts the previous filter back.
  func applyFilterChange(_ next: SheetFilterState?, action: String) {
    let before = filterState
    guard before != next else { return }
    filterState = next
    if next?.range != before?.range {
      filterSortMemory = nil
    }
    notifyGridRefresh()
    undoManager?.registerUndo(withTarget: self) { target in
      target.applyFilterChange(before, action: action)
    }
    undoManager?.setActionName(action)
  }

  /// Shrinks a large/empty-padded selection to the content table Excel would filter.
  private func trimmedFilterRange(from range: CellRange) -> CellRange? {
    let sheet = activeSheet
    let n = range.normalized
    let isWholeSheet =
      selectionAxis == .sheet
      || (n.minRow == 0 && n.minCol == 0
        && n.maxRow >= sheet.effectiveRowCount - 1
        && n.maxCol >= sheet.effectiveColumnCount - 1)

    if isWholeSheet, let used = sheet.populatedBounds,
      used.normalized.maxRow > used.normalized.minRow
    {
      return used
    }

    func hasContent(row: Int, col: Int) -> Bool {
      !sheet.cell(at: CellAddress(row: row, col: col)).raw.isEmpty
    }

    var minRow: Int?
    var maxRow: Int?
    var minCol: Int?
    var maxCol: Int?
    for row in n.minRow...n.maxRow {
      for col in n.minCol...n.maxCol {
        guard hasContent(row: row, col: col) else { continue }
        minRow = min(minRow ?? row, row)
        maxRow = max(maxRow ?? row, row)
        minCol = min(minCol ?? col, col)
        maxCol = max(maxCol ?? col, col)
      }
    }
    guard let minRow, let maxRow, let minCol, let maxCol, maxRow > minRow else {
      // Selection has no multi-row content — fall back to used range when it fits.
      if let used = sheet.populatedBounds,
        used.normalized.maxRow > used.normalized.minRow,
        n.minRow <= used.normalized.minRow,
        n.maxRow >= used.normalized.maxRow
      {
        return used
      }
      return nil
    }
    return CellRange(
      start: CellAddress(row: minRow, col: minCol),
      end: CellAddress(row: maxRow, col: maxCol)
    )
  }

  /// Range used when Create Filter is invoked from a single selected cell.
  func filterRangeForSingleCell(_ seed: CellAddress) -> CellRange {
    if let region = contiguousRegion(around: seed),
      region.normalized.maxRow > region.normalized.minRow
    {
      return region
    }
    // Only fall back to the used range when the selection sits inside it.
    if let bounds = activeSheet.populatedBounds, bounds.contains(seed) {
      return bounds
    }
    return .singleOrigin
  }

  /// Expands from `seed` to the largest filled rectangle (no empty border gaps).
  func contiguousRegion(around seed: CellAddress) -> CellRange? {
    let sheet = activeSheet
    func hasContent(row: Int, col: Int) -> Bool {
      !sheet.cell(at: CellAddress(row: row, col: col)).raw.isEmpty
    }

    // Empty seed outside any table → no region (do not silently grab distant used range).
    guard hasContent(row: seed.row, col: seed.col) else {
      if let bounds = sheet.populatedBounds, bounds.contains(seed) {
        return bounds
      }
      return nil
    }

    var minRow = seed.row
    var maxRow = seed.row
    var minCol = seed.col
    var maxCol = seed.col
    var expanded = true
    let rowLimit = sheet.effectiveRowCount - 1
    let colLimit = sheet.effectiveColumnCount - 1

    // Each direction grows as far as it can before the others are checked again. Growing one
    // row per pass re-scanned every column each time: on a 15,000-row table that took seconds.
    while expanded {
      expanded = false
      while minRow > 0, (minCol...maxCol).contains(where: { hasContent(row: minRow - 1, col: $0) })
      {
        minRow -= 1
        expanded = true
      }
      while maxRow < rowLimit,
        (minCol...maxCol).contains(where: { hasContent(row: maxRow + 1, col: $0) })
      {
        maxRow += 1
        expanded = true
      }
      while minCol > 0, (minRow...maxRow).contains(where: { hasContent(row: $0, col: minCol - 1) })
      {
        minCol -= 1
        expanded = true
      }
      while maxCol < colLimit,
        (minRow...maxRow).contains(where: { hasContent(row: $0, col: maxCol + 1) })
      {
        maxCol += 1
        expanded = true
      }
    }

    return CellRange(
      start: CellAddress(row: minRow, col: minCol),
      end: CellAddress(row: maxRow, col: maxCol)
    )
  }

  func clearFilter() {
    guard filterState != nil else { return }
    applyFilterChange(nil, action: "Remove Filter")
  }

  /// Shows every row again but keeps the filter buttons.
  func clearAllFilterCriteria() {
    guard var state = filterState, state.hasCriteria else { return }
    state.selectedValuesByColumn.removeAll()
    state.rulesByColumn.removeAll()
    applyFilterChange(state, action: "Clear Filters")
  }

  /// Clears criteria for one column and removes its filter affordance.
  func clearColumnFilter(_ column: Int) {
    guard var state = filterState, state.isColumnActive(column) else { return }
    state.selectedValuesByColumn.removeValue(forKey: column)
    state.rulesByColumn.removeValue(forKey: column)
    state.excludedColumns.insert(column)
    let n = state.range.normalized
    let remaining = (n.minCol...n.maxCol).filter { state.isColumnActive($0) }
    applyFilterChange(remaining.isEmpty ? nil : state, action: "Clear Filter")
  }

  func setFilterValues(column: Int, values: Set<String>?) {
    guard var state = filterState else { return }
    state.excludedColumns.remove(column)
    // A column filters by values or by rules, not both.
    state.rulesByColumn.removeValue(forKey: column)
    if let values {
      state.selectedValuesByColumn[column] = values
    } else {
      state.selectedValuesByColumn.removeValue(forKey: column)
    }
    applyFilterChange(state, action: "Filter")
  }

  /// Filters a column by rules (contains, greater than, top 10). Nil clears them.
  func setFilterRules(column: Int, rules: ColumnFilterRules?) {
    guard var state = filterState else { return }
    state.excludedColumns.remove(column)
    state.selectedValuesByColumn.removeValue(forKey: column)
    if let rules, !rules.rules.isEmpty {
      state.rulesByColumn[column] = rules
    } else {
      state.rulesByColumn.removeValue(forKey: column)
    }
    applyFilterChange(state, action: "Filter")
  }

  // MARK: - Filter popover

  /// Each value in `column` with its row count. Rows hidden by other columns' filters are left out,
  /// so a column's list narrows to what the other filters leave.
  func filterValueCounts(column: Int) -> [FilterValueCount] {
    guard let filter = filterState, filter.isColumnActive(column) else { return [] }
    let n = filter.range.normalized
    guard n.maxRow > n.minRow else { return [] }
    let sheet = activeSheet
    var counts: [String: Int] = [:]
    let cutoffs = filter.cutoffs(sheet: sheet) { self.displayString(at: $0) }
    for row in (n.minRow + 1)...n.maxRow {
      if filter.isRowHidden(
        row, sheet: sheet, displayString: { self.displayString(at: $0) }, excludingColumn: column,
        cutoffs: cutoffs)
      {
        continue
      }
      counts[displayString(at: CellAddress(row: row, col: column)), default: 0] += 1
    }
    return counts.map { FilterValueCount(value: $0.key, count: $0.value) }
      .sorted { $0.value.localizedStandardCompare($1.value) == .orderedAscending }
  }

  /// Rows shown and data rows in all, while a filter hides at least one row.
  var filterRowCounts: (shown: Int, total: Int)? {
    guard let filter = filterState, filter.hasCriteria else { return nil }
    let total = filter.dataRows.count
    let hidden = hiddenRowsForPrint().count
    return (total - hidden, total)
  }

  /// The first shown row after rows the filter hides. Its row number is drawn in the accent.
  /// True for a row a filter with criteria is showing. Its number is drawn in the accent, as
  /// other spreadsheet apps color every row of a filtered list, not only those after a gap.
  func isShownByActiveFilter(_ row: Int) -> Bool {
    guard let filter = filterState, filter.hasCriteria, filter.dataRows.contains(row) else {
      return false
    }
    return !isRowHiddenByFilter(row)
  }

  /// True while the filter's rows are sorted by `column` from the popover in this direction.
  func isFilterSorted(column: Int, ascending: Bool) -> Bool {
    guard let memory = currentFilterSortMemory() else { return false }
    return memory.column == column && memory.ascending == ascending
  }

  /// Sorts the filter's rows by `column`. The same sort again puts the rows back
  /// in the order they had before the first sort.
  func filterSort(column: Int, ascending: Bool) {
    commitEditIfNeeded()
    guard let filter = filterState else { return }
    let range = filter.range
    let n = range.normalized
    let firstDataRow = n.minRow + 1
    guard firstDataRow < n.maxRow else { return }
    let memory = currentFilterSortMemory()
    var arguments = [
      "sheet": activeSheet.name,
      "range": range.a1Label,
      "column": String(column),
      "ascending": ascending ? "true" : "false",
      "header": "true",
    ]

    if let memory, memory.column == column, memory.ascending == ascending {
      // Row firstDataRow + k gets back the data that started there.
      var currentRowOfOrigin: [Int: Int] = [:]
      for (offset, origin) in memory.originRows.enumerated() {
        currentRowOfOrigin[origin] = firstDataRow + offset
      }
      let order = (firstDataRow...n.maxRow).compactMap { currentRowOfOrigin[$0] }
      arguments["order"] = order.map(String.init).joined(separator: ",")
      guard applyCommand("data.sort", arguments, incremental: false) else { return }
      filterSortMemory = nil
      registerSortUndo(
        sheetName: activeSheet.name, rangeLabel: range.a1Label, column: column, hasHeader: true,
        firstDataRow: firstDataRow, appliedOrder: lastSortOrder, action: "Unsort")
    } else {
      guard applyCommand("data.sort", arguments, incremental: false) else { return }
      let moved = lastSortOrder
      // A sort on top of a sort still remembers the order from before the first one.
      let originRows =
        memory.map { earlier in moved.map { earlier.originRows[$0 - firstDataRow] } } ?? moved
      registerSortUndo(
        sheetName: activeSheet.name, rangeLabel: range.a1Label, column: column, hasHeader: true,
        firstDataRow: firstDataRow, appliedOrder: moved, action: "Sort")
      filterSortMemory = FilterSortMemory(
        sheetID: activeSheet.id, range: range, column: column, ascending: ascending,
        originRows: originRows)
    }
    notifyGridRefresh()
  }

  /// What Remove Duplicates did, for the message that follows it.
  enum RemoveDuplicatesOutcome: Equatable {
    case removed(count: Int, kept: Int)
    case noneFound
    /// A filter is hiding rows in the range; clear it first.
    case filterHidesRows
    case nothingToCheck
  }

  /// Removes rows that repeat an earlier row in the compared columns, ignoring case. The first
  /// of each stays and the rows below close up, as one undo step.
  @discardableResult
  func removeDuplicates(_ request: DuplicateRequest) -> RemoveDuplicatesOutcome {
    commitEditIfNeeded()
    let range = request.range
    let hasHeader = request.hasHeader
    let n = range.normalized
    let firstDataRow = n.minRow + (hasHeader ? 1 : 0)
    guard firstDataRow < n.maxRow, !request.columns.isEmpty else { return .nothingToCheck }
    if filterState != nil, (firstDataRow...n.maxRow).contains(where: isRowHiddenByFilter) {
      return .filterHidesRows
    }
    let repeats = scanDuplicates(request).repeatRows.sorted()
    guard !repeats.isEmpty else { return .noneFound }
    let repeatSet = Set(repeats)
    let kept = (firstDataRow...n.maxRow).filter { !repeatSet.contains($0) }

    let rangeLabel = range.a1Label
    undoManager?.beginUndoGrouping()
    // The repeats move below the rows that stay, then those bottom rows are cleared.
    guard
      applyCommand(
        "data.sort",
        [
          "sheet": activeSheet.name, "range": rangeLabel, "column": String(n.minCol),
          "header": hasHeader ? "true" : "false",
          "order": (kept + repeats).map(String.init).joined(separator: ","),
        ],
        incremental: false)
    else {
      undoManager?.endUndoGrouping()
      return .nothingToCheck
    }
    registerSortUndo(
      sheetName: activeSheet.name, rangeLabel: rangeLabel, column: n.minCol,
      hasHeader: hasHeader, firstDataRow: firstDataRow, appliedOrder: lastSortOrder,
      action: "Remove Duplicates")
    clearRange(
      CellRange(
        start: CellAddress(row: n.maxRow - repeats.count + 1, col: n.minCol),
        end: CellAddress(row: n.maxRow, col: n.maxCol)),
      actionName: "Remove Duplicates")
    undoManager?.endUndoGrouping()
    undoManager?.setActionName("Remove Duplicates")
    notifyGridRefresh()
    return .removed(count: repeats.count, kept: kept.count)
  }

  /// Undo for a sort keeps the row order, not copies of the workbook. On a 15,000-row sheet each
  /// copy is hundreds of megabytes, and the undo history kept one pair for every sort.
  /// `appliedOrder[i]` is the row whose data the sort moved into `firstDataRow + i`.
  private func registerSortUndo(
    sheetName: String, rangeLabel: String, column: Int, hasHeader: Bool, firstDataRow: Int,
    appliedOrder: [Int], action: String
  ) {
    guard !appliedOrder.isEmpty else { return }
    var restoring = Array(repeating: 0, count: appliedOrder.count)
    for (offset, source) in appliedOrder.enumerated() {
      restoring[source - firstDataRow] = firstDataRow + offset
    }
    undoManager?.registerUndo(withTarget: self) { target in
      // Puts each row back, then offers the same sort again as the redo.
      target.filterSortMemory = nil
      guard
        target.applyCommand(
          "data.sort",
          [
            "sheet": sheetName, "range": rangeLabel, "column": String(column),
            "header": hasHeader ? "true" : "false",
            "order": restoring.map(String.init).joined(separator: ","),
          ],
          incremental: false)
      else { return }
      target.registerSortUndo(
        sheetName: sheetName, rangeLabel: rangeLabel, column: column, hasHeader: hasHeader,
        firstDataRow: firstDataRow, appliedOrder: restoring, action: action)
      target.notifyGridRefresh()
    }
    undoManager?.setActionName(action)
  }

  /// The remembered sort, only while it still fits the active sheet's filter.
  private func currentFilterSortMemory() -> FilterSortMemory? {
    guard let memory = filterSortMemory, let filter = filterState,
      memory.sheetID == activeSheet.id, memory.range == filter.range,
      memory.originRows.count == filter.dataRows.count
    else { return nil }
    return memory
  }

  func isRowHiddenByFilter(_ row: Int) -> Bool {
    guard filterState != nil else { return false }
    if hiddenRowsCache == nil {
      hiddenRowsCache = rebuildHiddenRowsCache()
    }
    return hiddenRowsCache?.contains(row) ?? false
  }

  /// Rows collapsed by the active filter; empty when no filter is applied.
  func hiddenRowsForPrint() -> Set<Int> {
    guard filterState != nil else { return [] }
    if hiddenRowsCache == nil {
      hiddenRowsCache = rebuildHiddenRowsCache()
    }
    return hiddenRowsCache ?? []
  }

  private func rebuildHiddenRowsCache() -> Set<Int> {
    guard let filterState else { return [] }
    let n = filterState.range.normalized
    guard n.maxRow > n.minRow else { return [] }
    var hidden = Set<Int>()
    let sheet = activeSheet
    let shown: (CellAddress) -> String = { [weak self] address in
      self?.displayString(at: address) ?? ""
    }
    let cutoffs = filterState.cutoffs(sheet: sheet, displayString: shown)
    for row in (n.minRow + 1)...n.maxRow
    where filterState.isRowHidden(row, sheet: sheet, displayString: shown, cutoffs: cutoffs) {
      hidden.insert(row)
    }
    return hidden
  }

  func isFilterHeaderCell(row: Int, col: Int) -> Bool {
    guard let filterState else { return false }
    let n = filterState.range.normalized
    return row == n.minRow && filterState.isColumnActive(col)
  }

  func isFilterColumn(_ col: Int) -> Bool {
    filterState?.isColumnActive(col) ?? false
  }

  /// Last sheet row that currently has non-zero height (skips filter-hidden rows).
  func lastVisibleRowIndex() -> Int {
    let last = activeSheet.effectiveRowCount - 1
    guard last >= 0 else { return 0 }
    for row in stride(from: last, through: 0, by: -1) {
      if !isRowHiddenByFilter(row) { return row }
    }
    return 0
  }

  // MARK: - Zoom

  func zoomIn() {
    zoomScale = min(2.0, (zoomScale * 1.25 * 100).rounded() / 100)
  }

  func zoomOut() {
    zoomScale = max(0.5, (zoomScale / 1.25 * 100).rounded() / 100)
  }

  func zoomActualSize() {
    zoomScale = 1.0
  }
}

extension CellRange {
  fileprivate var normalizedRange: CellRange {
    let n = normalized
    return CellRange(
      start: CellAddress(row: n.minRow, col: n.minCol),
      end: CellAddress(row: n.maxRow, col: n.maxCol)
    )
  }
}

extension SpreadsheetViewModel {
  static func boundingUnion(of ranges: [CellRange]) -> CellRange {
    guard var result = ranges.first?.normalizedRange else { return .singleOrigin }
    for range in ranges.dropFirst() {
      let a = result.normalized
      let b = range.normalized
      result = CellRange(
        start: CellAddress(row: min(a.minRow, b.minRow), col: min(a.minCol, b.minCol)),
        end: CellAddress(row: max(a.maxRow, b.maxRow), col: max(a.maxCol, b.maxCol))
      )
    }
    return result
  }
}
