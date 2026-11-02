import AppKit
import Foundation
import Observation
import SparkGridCore

/// What a workbook edit does to the cells on screen.
enum GridContentInvalidation {
  /// Insert, delete, sort, filter, zoom, freeze, sheet switch, or a large paste.
  case full
  /// Displayed values changed. The grid repaints these cells and keeps structure.
  case cells(Set<CellAddress>)
  /// The rest of an open file arrived. Repaint stored values. Keep scroll and selection.
  case repaint
}

/// UI state and mutations for the active workbook. Undo integrates with the document undo manager.
@Observable
@MainActor
final class SpreadsheetViewModel {
  /// When true, `workbook` didSet skips a full formula rebuild (format-only / batched edits).
  private var suspendFormulaRebuild = false
  /// When true, workbook writes are not document edits (tab switch, load sync).
  private var suppressEditStamp = false
  /// Real workbook edits. Tab switches, selection, scrolling, and zoom leave this alone.
  private(set) var editStamp: UInt64 = 0
  /// Bumped when a newer open or edit should ignore a background calculation.
  private var openCalculationGeneration: UInt64 = 0

  var workbook: Workbook {
    didSet {
      if !suppressEditStamp {
        editStamp &+= 1
      }
      contentRevision &+= 1
      if suspendFormulaRebuild { return }
      // A file open paints the active sheet, then appends the others. The grid
      // already shows stored values; do not rebuild or repaint that sheet.
      if suppressEditStamp, workbook.activeSheet.id == oldValue.activeSheet.id,
        workbook.sheets.count > oldValue.sheets.count
      {
        formulaEngine.replaceWorkbookKeepingValues(workbook)
        onGridInvalidation?(.repaint)
        return
      }
      structureRevision &+= 1
      hiddenRowsCache = nil
      conditionalFormatCache.removeAll(keepingCapacity: true)
      conditionalFormatCacheRevision = -1
      if !suppressEditStamp {
        openCalculationGeneration &+= 1
        formulaEngine.setPaintsStoredResultsOnly(false)
      }
      formulaEngine.rebuild(workbook: workbook, trustImportedCaches: suppressEditStamp)
      if suppressEditStamp {
        beginOpenCalculationIfNeeded()
      }
      onGridInvalidation?(.full)
    }
  }
  private var savedSelections: [UUID: SavedSelection] = [:]
  var selectionAnchor: CellAddress = .origin
  var selectionEnd: CellAddress = .origin
  /// All selected regions. The last entry is the active range (matches anchor/end).
  private(set) var selectionRanges: [CellRange] = [.singleOrigin]
  var isEditing = false
  var editText = ""
  /// One-line argument signature shown under the formula bar after Insert Function.
  var formulaArgumentHint: String?
  /// Bumped when Insert Function should place the formula-bar caret. Zero means none.
  var formulaCaretToken = 0
  var formulaCaretUTF16 = 0
  /// Bumps when formula edit text / focus changes so the grid can redraw ref highlights.
  private(set) var formulaHighlightRevision = 0
  /// Which formula reference token is focused (clicked in the formula bar).
  var focusedFormulaHighlightIndex: Int? = nil
  private(set) var contentRevision = 0
  /// Bumps for insert, delete, sort, sheet replacement, and other structural edits.
  /// A value edit leaves this alone so the grid can repaint only changed cells.
  private(set) var structureRevision = 0
  private(set) var gridRefreshToken = 0
  /// Cells published by the last value edit. The benchmark reads this.
  private(set) var lastPublishedCellCount = 0
  private(set) var selectionRevision = 0
  /// Bumped when find/navigation wants the grid to scroll the selection into view.
  var scrollRequestToken = 0
  /// Selected embedded picture on the active sheet, if any.
  var selectedImageID: UUID?
  /// Selected on-sheet chart, if any.
  var selectedChartID: UUID?
  /// Chart opened in the Insert Chart sheet for editing. Nil while inserting.
  var editingChartID: UUID?
  /// Bumped when the grid should scroll an on-sheet chart into view.
  var chartScrollToken = 0
  var chartScrollID: UUID?

  /// Insert Chart sheet presentation.
  var isInsertChartPresented = false
  var pendingChartKind: SheetChart.Kind = .bar

  // MARK: - Find / Replace
  var isFindBarVisible = false
  var isFindReplaceMode = false
  var findQuery = ""
  var findReplaceText = ""
  var findMatchCase = false
  var findEntireCell = false
  var findScope: FindScope = .sheet
  /// Stable range for Find-in-Selection so jumping to a match does not shrink search scope.
  var findScopeRange: CellRange?
  var findMatches: [CellAddress] = []
  var findMatchIndex: Int = -1

  // MARK: - Filter / Zoom
  var filterState: SheetFilterState? {
    didSet {
      hiddenRowsCache = nil
      // Keep sheet-backed AutoFilter in sync for save / xlsx export.
      if !isRestoringFilterFromSheet {
        syncAutoFilterToActiveSheet()
      }
      // Chevrons / hidden rows are grid-visual — always refresh when filter changes.
      if oldValue != filterState {
        notifyGridRefresh()
      }
    }
  }
  /// The row order before a sort from the filter popover, so clicking that sort again puts it back.
  var filterSortMemory: FilterSortMemory?
  /// Cached rows hidden by the active filter (invalidated on filter/content changes).
  var hiddenRowsCache: Set<Int>?
  /// Avoid write-back loops when restoring filter from the sheet.
  var isRestoringFilterFromSheet = false
  /// Cache for conditional-format overlays (invalidated with contentRevision).
  var conditionalFormatCache: [CellAddress: ConditionalPaint] = [:]
  var conditionalFormatCacheRevision: Int = -1
  /// Numbers in each conditional-format range, reset with `conditionalFormatCache`.
  var conditionalRangeNumbers: [ConditionalRangeKey: [Double]] = [:]
  /// View zoom (0.5…2.0). Scales cell geometry in the grid.
  var zoomScale: CGFloat = 1.0 {
    didSet {
      let clamped = min(2.0, max(0.5, zoomScale))
      if abs(clamped - zoomScale) > 0.0001 {
        zoomScale = clamped
        return
      }
      if oldValue != zoomScale {
        notifyGridRefresh()
      }
    }
  }

  weak var undoManager: UndoManager?

  /// The grid drops its caches on `.full` and repaints `.cells` in place.
  var onGridInvalidation: ((GridContentInvalidation) -> Void)?

  /// Evaluates `=` formulas; display helpers use this cache.
  let formulaEngine = FormulaEngine()
  /// Workbook edits that the fuzzer and `spark-grid-cli run` also perform.
  private let engineCommands = WorkbookSession()
  /// Where each data row came from in the last sort. See `WorkbookSession.lastSortOrder`.
  var lastSortOrder: [Int] { engineCommands.lastSortOrder }

  /// Colored references for the formula being edited, or the selected cell's formula (preview).
  var formulaReferenceHighlights: [FormulaRefHighlight] {
    let raw = formulaTextForReferenceHighlights
    guard FormulaSyntax.isFormula(raw) else { return [] }
    let sheet = activeSheet
    return FormulaReferenceScanner.highlights(
      in: raw,
      maxRow: sheet.effectiveRowCount - 1,
      maxCol: sheet.effectiveColumnCount - 1
    )
  }

  /// Formula text that drives grid/formula-bar reference coloring.
  private var formulaTextForReferenceHighlights: String {
    if isEditing { return editText }
    return selectedCell.raw
  }

  func noteFormulaEditTextChanged() {
    // Grid ref overlays only matter for formulas (or clearing a prior focus chip).
    guard FormulaSyntax.isFormula(editText) || focusedFormulaHighlightIndex != nil else { return }
    formulaHighlightRevision &+= 1
  }

  func updateFormulaHighlightFocus(atUTF16 location: Int) {
    let raw = formulaTextForReferenceHighlights
    guard FormulaSyntax.isFormula(raw) else {
      if focusedFormulaHighlightIndex != nil {
        focusedFormulaHighlightIndex = nil
        formulaHighlightRevision &+= 1
      }
      return
    }
    // Allow caret focus while editing; when only selected, keep a stable preview.
    guard isEditing else { return }
    let newIndex = FormulaReferenceScanner.highlightIndex(
      atUTF16: location,
      in: formulaReferenceHighlights
    )
    guard newIndex != focusedFormulaHighlightIndex else { return }
    focusedFormulaHighlightIndex = newIndex
    formulaHighlightRevision &+= 1
  }

  func focusFormulaHighlight(atUTF16 location: Int) {
    updateFormulaHighlightFocus(atUTF16: location)
  }

  func notifyGridRefresh() {
    gridRefreshToken &+= 1
  }

  /// The open sheet is drawn while later sheets are still being read.
  func setAwaitingRemainder(_ awaiting: Bool) {
    formulaEngine.setAwaitingRemainder(awaiting)
  }

  /// Value edits that touch more cells than this repaint the whole grid.
  private static let fullPaintCellCount = 256

  private func publishExternalChanges(_ changes: [String: Set<CellAddress>]) {
    let active = activeSheet.name
    let addresses =
      changes.first { $0.key.caseInsensitiveCompare(active) == .orderedSame }?.value ?? []
    guard !addresses.isEmpty else { return }
    publishChangedCells(addresses, editedCount: addresses.count)
  }

  private func publishChangedCells(_ addresses: Set<CellAddress>, editedCount: Int) {
    lastPublishedCellCount = addresses.count
    if editedCount > Self.fullPaintCellCount || valueEditChangesFilterVisibility(addresses) {
      structureRevision &+= 1
      hiddenRowsCache = nil
      conditionalFormatCache.removeAll(keepingCapacity: true)
      conditionalFormatCacheRevision = -1
      onGridInvalidation?(.full)
      return
    }
    // A changed value can flip a highlight rule or move a color scale. Only cells on screen
    // are worked out again.
    conditionalFormatCache.removeAll(keepingCapacity: true)
    conditionalFormatCacheRevision = -1
    onGridInvalidation?(.cells(addresses))
  }

  /// An idle autofilter range does not hide rows. Visibility changes only when a
  /// column that already has selected values contains one of the edited results.
  private func valueEditChangesFilterVisibility(_ changed: Set<CellAddress>) -> Bool {
    guard let filter = filterState, filter.hasCriteria else { return false }
    let range = filter.range.normalized
    for address in changed {
      guard address.row > range.minRow, address.row <= range.maxRow else { continue }
      guard address.col >= range.minCol, address.col <= range.maxCol else { continue }
      if filter.isFiltering(column: address.col) { return true }
    }
    return false
  }

  private func noteSelectionChanged() {
    selectionRevision &+= 1
    focusedFormulaHighlightIndex = nil
    // Keep dashed formula overlays in sync when leaving/entering formula cells.
    formulaHighlightRevision &+= 1
  }

  init(workbook: Workbook) {
    self.workbook = workbook
    formulaEngine.onExternalValues = { [weak self] changes in
      self?.publishExternalChanges(changes)
    }
    formulaEngine.rebuild(workbook: workbook)
    beginOpenCalculationIfNeeded()
    syncEditTextFromSelection()
    // Pull AutoFilter from the sheet so Excel header-row filters appear immediately.
    isRestoringFilterFromSheet = true
    filterState = workbook.activeSheet.autoFilter
    isRestoringFilterFromSheet = false
  }

  func displayValue(at address: CellAddress) -> CellValue {
    formulaEngine.displayValue(at: address, sheet: activeSheet)
  }

  /// Grid text. Hides formula source that `displayValue` still returns for the answer check.
  func sheetDisplayValue(at address: CellAddress, cell: Cell) -> CellValue {
    formulaEngine.sheetDisplayValue(at: address, sheet: activeSheet, cell: cell)
  }

  /// A file with no stored formula results paints blanks, then fills them in.
  /// Calculation stays off the draw that has to accept the first click.
  private func beginOpenCalculationIfNeeded() {
    guard workbookNeedsOpenCalculation() else {
      formulaEngine.setPaintsStoredResultsOnly(false)
      return
    }
    formulaEngine.setPaintsStoredResultsOnly(true)
    openCalculationGeneration &+= 1
    let generation = openCalculationGeneration
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      // A struct copy still shares cell storage. Build dictionaries the background
      // calc can read while the open grid keeps the live workbook.
      let snapshot = self.workbookCopyForCalculation(self.workbook)
      DispatchQueue.global(qos: .userInitiated).async { [weak self] in
        // The dependency-ordered pass, not `recalculateEntireWorkbook`. On a 114,599-formula
        // workbook it takes 8 s instead of 12 in Release, and the whole-workbook pass showed
        // Daily Q1's unqualified SUM(F5:F64) totals with Monthly Summary's F5:F64 answers.
        let outcome = CrossSheetBackground.calculateFormulasWithoutCaches(in: snapshot)
        var results: [String: [CellAddress: CellValue]] = [:]
        for (name, values) in outcome.valuesBySheet {
          results[name.lowercased()] = values
        }
        DispatchQueue.main.async { [weak self] in
          guard let self, generation == self.openCalculationGeneration else { return }
          self.formulaEngine.installCalculatedResults(results)
          // Highlights, filtered rows and painted cells were worked out from the blanks shown
          // while this ran. A rule like Flag = "Loss" stayed unhighlighted after a reopen.
          self.structureRevision &+= 1
          self.hiddenRowsCache = nil
          self.conditionalFormatCache.removeAll(keepingCapacity: true)
          self.conditionalFormatCacheRevision = -1
          self.conditionalRangeNumbers.removeAll(keepingCapacity: true)
          self.onGridInvalidation?(.full)
        }
      }
    }
  }

  /// Cell dictionaries the background calculation owns. The open grid keeps the original.
  private func workbookCopyForCalculation(_ workbook: Workbook) -> Workbook {
    var copy = workbook
    copy.sheets = workbook.sheets.map { sheet in
      var sheetCopy = sheet
      var cells: [CellAddress: Cell] = [:]
      cells.reserveCapacity(sheet.cells.count)
      for (address, cell) in sheet.cells {
        cells[address] = cell
      }
      sheetCopy.cells = cells
      return sheetCopy
    }
    return copy
  }

  private func workbookNeedsOpenCalculation() -> Bool {
    for sheet in workbook.sheets {
      for (_, cell) in sheet.cells {
        guard FormulaSyntax.isFormula(cell.raw) else { continue }
        if cell.cachedFormulaValue == nil { return true }
      }
    }
    return false
  }

  /// Full workbook recalc using grouped aggregate range scans (does not run on open).
  @discardableResult
  func recalculateEntireWorkbook() -> TimeInterval {
    let elapsed = formulaEngine.recalculateEntireWorkbook(workbook)
    notifyGridRefresh()
    return elapsed
  }

  func displayString(at address: CellAddress) -> String {
    let cell = activeSheet.cell(at: address)
    return formulaEngine.displayString(at: address, sheet: activeSheet, format: cell.format)
  }

  /// Sheets-style explanation when the selected cell evaluates to a formula error.
  var selectedFormulaErrorExplanation: String? {
    guard !isEditing else { return nil }
    let value = displayValue(at: selectionAnchor)
    guard let error = value.formulaError else { return nil }
    return "\(error.displayCode) — \(error.explanation)"
  }

  var selection: CellAddress {
    get { selectionAnchor }
    set {
      replaceSelection(with: CellRange(start: newValue, end: newValue))
    }
  }

  var selectionRange: CellRange {
    CellRange(start: selectionAnchor, end: selectionEnd)
  }

  enum SelectionAxis: Equatable {
    case cells
    case row
    case column
    case sheet
  }

  var selectionAxis: SelectionAxis {
    let ranges = selectionRanges
    guard !ranges.isEmpty else { return .cells }
    let sheet = activeSheet
    let allSheet = ranges.allSatisfy { range in
      let n = range.normalized
      return n.minRow == 0 && n.maxRow >= sheet.effectiveRowCount - 1
        && n.minCol == 0 && n.maxCol >= sheet.effectiveColumnCount - 1
    }
    if allSheet { return .sheet }
    let allColumns = ranges.allSatisfy { range in
      let n = range.normalized
      return n.minRow == 0 && n.maxRow >= sheet.effectiveRowCount - 1
    }
    if allColumns { return .column }
    let allRows = ranges.allSatisfy { range in
      let n = range.normalized
      return n.minCol == 0 && n.maxCol >= sheet.effectiveColumnCount - 1
    }
    if allRows { return .row }
    return .cells
  }

  var hasMultipleSelectionRanges: Bool { selectionRanges.count > 1 }

  func isAddressSelected(_ address: CellAddress) -> Bool {
    selectionRanges.contains { $0.contains(address) }
  }

  func isColumnInSelection(_ col: Int) -> Bool {
    selectionRanges.contains { range in
      let n = range.normalized
      return col >= n.minCol && col <= n.maxCol
    }
  }

  func isRowInSelection(_ row: Int) -> Bool {
    selectionRanges.contains { range in
      let n = range.normalized
      return row >= n.minRow && row <= n.maxRow
    }
  }

  private func replaceSelection(with range: CellRange) {
    let clamped = CellRange(start: clamp(range.start), end: clamp(range.end))
    selectionAnchor = clamped.start
    selectionEnd = clamped.end
    selectionRanges = [clamped]
    noteSelectionChanged()
  }

  private func setPrimaryRange(from start: CellAddress, to end: CellAddress) {
    let clamped = CellRange(start: clamp(start), end: clamp(end))
    selectionAnchor = clamped.start
    selectionEnd = clamped.end
    if selectionRanges.isEmpty {
      selectionRanges = [clamped]
    } else {
      selectionRanges[selectionRanges.count - 1] = clamped
    }
    noteSelectionChanged()
  }

  var activeSheet: Sheet {
    get { workbook.activeSheet }
    set {
      workbook.activeSheet = newValue
    }
  }

  /// Workbook assignment that must not mark the document edited.
  func withoutRecordingEdit(_ body: () -> Void) {
    let previous = suppressEditStamp
    suppressEditStamp = true
    defer { suppressEditStamp = previous }
    body()
  }

  /// Member writes sometimes skip `workbook` didSet. Count the edit once when they do.
  private func finishWorkbookMutation(stampBefore: UInt64) {
    if !suppressEditStamp, editStamp == stampBefore {
      editStamp &+= 1
    }
  }

  /// A width or height change moves no value, so conditional colors stay valid. Dropping them
  /// on every drag step recomputed each color scale per frame and made resizing hitch.
  private func setSheetSizeKeepingPaintCache(_ sheet: Sheet) {
    let cacheWasCurrent = conditionalFormatCacheRevision == contentRevision
    setActiveSheetPreservingFormulas(sheet)
    if cacheWasCurrent {
      conditionalFormatCacheRevision = contentRevision
    }
  }

  /// Format-only sheet writes — avoids re-parsing every formula on the sheet.
  func setActiveSheetPreservingFormulas(_ sheet: Sheet) {
    let stampBefore = editStamp
    suspendFormulaRebuild = true
    workbook.activeSheet = sheet
    suspendFormulaRebuild = false
    finishWorkbookMutation(stampBefore: stampBefore)
  }

  /// Value edits — incremental formula update instead of a full rebuild.
  private func setActiveSheet(_ sheet: Sheet, formulaCellsChanged addresses: [CellAddress]) {
    let stampBefore = editStamp
    suspendFormulaRebuild = true
    workbook.activeSheet = sheet
    suspendFormulaRebuild = false
    finishWorkbookMutation(stampBefore: stampBefore)
    guard !addresses.isEmpty else { return }
    let changes = formulaEngine.cellsDidChange(addresses, sheet: sheet)
    let changed = changes[sheet.name] ?? Set(addresses)
    publishChangedCells(changed, editedCount: addresses.count)
  }

  var selectedCell: Cell {
    activeSheet.cell(at: selectionAnchor)
  }

  var formulaBarText: String {
    get { isEditing ? editText : selectedCell.editableText }
    set {
      editText = newValue
      if !isEditing { isEditing = true }
      noteFormulaEditTextChanged()
    }
  }

  var showsFormulaArgumentHint: Bool {
    isEditing && formulaArgumentHint?.isEmpty == false
  }

  /// Puts `=NAME()` in the active cell's formula bar, caret between the parentheses.
  func insertFormulaFunction(_ name: String) {
    guard let insertion = FormulaFunctionCatalog.insertion(for: name) else { return }
    formulaBarText = insertion.text
    formulaArgumentHint = insertion.signatureLine
    formulaCaretUTF16 = insertion.caretUTF16
    formulaCaretToken += 1
  }

  func syncEditTextFromSelection() {
    editText = selectedCell.editableText
  }

  func selectRange(from start: CellAddress, to end: CellAddress) {
    commitEditIfNeeded()
    let expanded = activeSheet.selectionExpandedForMerges(CellRange(start: start, end: end))
    replaceSelection(with: expanded)
    syncEditTextFromSelection()
    isEditing = false
  }

  func extendSelection(to end: CellAddress) {
    let tip = clamp(end)
    selectionEnd = tip
    // Expand for merges in the painted range only — never move the drag origin
    // to the normalized top-left (that breaks right→left / bottom→top drags).
    let expanded = activeSheet.selectionExpandedForMerges(
      CellRange(start: selectionAnchor, end: tip)
    )
    let painted = CellRange(start: clamp(expanded.start), end: clamp(expanded.end))
    if selectionRanges.isEmpty {
      selectionRanges = [painted]
    } else {
      selectionRanges[selectionRanges.count - 1] = painted
    }
    noteSelectionChanged()
  }

  /// ⌘-click a cell to add it, or to drop it when it is already highlighted.
  func commandClickCell(_ address: CellAddress) {
    commitEditIfNeeded()
    let target = clamp(address)
    if isAddressSelected(target) {
      commandDeselectDrag = (start: target, base: selectionRanges)
      // Like Excel, the last highlighted cell stays. An empty selection would
      // still act on the anchor cell the user just unhighlighted.
      let remaining = selectionRangesWithout(target)
      guard let active = remaining.last else {
        isEditing = false
        return
      }
      selectionRanges = remaining
      selectionAnchor = active.start
      selectionEnd = active.end
      noteSelectionChanged()
    } else {
      let single = CellRange(start: target, end: target)
      selectionRanges.append(single)
      selectionAnchor = target
      selectionEnd = target
      noteSelectionChanged()
    }
    syncEditTextFromSelection()
    isEditing = false
  }

  /// The cell a ⌘-drag started on and the ranges before it. The drag
  /// unhighlights the rectangle from that cell to the pointer.
  private var commandDeselectDrag: (start: CellAddress, base: [CellRange])?

  /// ⌘-drag that began on a highlighted cell: drop the rectangle from that cell to `end`.
  func extendCommandDeselect(to end: CellAddress) {
    guard let drag = commandDeselectDrag else { return }
    let cut = CellRange(start: drag.start, end: clamp(end))
    let remaining = drag.base.flatMap { rangeSplitting($0, without: cut) }
    // The last highlighted cell stays, as with a single ⌘-click.
    guard let active = remaining.last else { return }
    selectionRanges = remaining
    selectionAnchor = active.start
    selectionEnd = active.end
    noteSelectionChanged()
    syncEditTextFromSelection()
  }

  func endCommandDeselect() {
    commandDeselectDrag = nil
  }

  /// Ranges with `target` punched out. A rectangle becomes the blocks around that cell.
  private func selectionRangesWithout(_ target: CellAddress) -> [CellRange] {
    let cut = CellRange(start: target, end: target)
    return selectionRanges.flatMap { rangeSplitting($0, without: cut) }
  }

  /// `range` minus `cut`: up to four blocks above, below, left, and right of the overlap.
  private func rangeSplitting(_ range: CellRange, without cut: CellRange) -> [CellRange] {
    let n = range.normalized
    let c = cut.normalized
    let top = max(n.minRow, c.minRow)
    let bottom = min(n.maxRow, c.maxRow)
    let left = max(n.minCol, c.minCol)
    let right = min(n.maxCol, c.maxCol)
    guard top <= bottom, left <= right else { return [range] }
    var parts: [CellRange] = []
    func add(rowStart: Int, rowEnd: Int, colStart: Int, colEnd: Int) {
      guard rowStart <= rowEnd, colStart <= colEnd else { return }
      parts.append(
        CellRange(
          start: CellAddress(row: rowStart, col: colStart),
          end: CellAddress(row: rowEnd, col: colEnd)
        ))
    }
    add(rowStart: n.minRow, rowEnd: top - 1, colStart: n.minCol, colEnd: n.maxCol)
    add(rowStart: bottom + 1, rowEnd: n.maxRow, colStart: n.minCol, colEnd: n.maxCol)
    add(rowStart: top, rowEnd: bottom, colStart: n.minCol, colEnd: left - 1)
    add(rowStart: top, rowEnd: bottom, colStart: right + 1, colEnd: n.maxCol)
    return parts
  }

  /// ⌘-click a column header to add that column, or to drop it when any of it is highlighted.
  func commandClickColumn(_ col: Int) {
    commitEditIfNeeded()
    let sheet = activeSheet
    let clampedCol = max(0, min(sheet.effectiveColumnCount - 1, col))
    let columnRange = CellRange(
      start: CellAddress(row: 0, col: clampedCol),
      end: CellAddress(row: sheet.effectiveRowCount - 1, col: clampedCol)
    )

    let deepestRow = selectionRanges.map { $0.normalized.maxRow }.max() ?? 0
    let cut = CellRange(
      start: CellAddress(row: 0, col: clampedCol),
      end: CellAddress(row: max(sheet.effectiveRowCount - 1, deepestRow), col: clampedCol)
    )
    if isColumnInSelection(clampedCol) {
      // Drop every highlighted cell in the column, even inside a larger block.
      // The last highlighted cell stays, as with a single cell.
      let remaining = selectionRanges.flatMap { rangeSplitting($0, without: cut) }
      guard let active = remaining.last else {
        isEditing = false
        return
      }
      selectionRanges = remaining
      selectionAnchor = active.start
      selectionEnd = active.end
      noteSelectionChanged()
    } else {
      selectionRanges.append(columnRange)
      selectionAnchor = columnRange.start
      selectionEnd = columnRange.end
      noteSelectionChanged()
    }
    syncEditTextFromSelection()
    isEditing = false
  }

  /// ⌘-click a row header to add that row, or to drop it when any of it is highlighted.
  func commandClickRow(_ row: Int) {
    commitEditIfNeeded()
    let sheet = activeSheet
    let clampedRow = max(0, min(sheet.effectiveRowCount - 1, row))
    let rowRange = CellRange(
      start: CellAddress(row: clampedRow, col: 0),
      end: CellAddress(row: clampedRow, col: sheet.effectiveColumnCount - 1)
    )

    let widestCol = selectionRanges.map { $0.normalized.maxCol }.max() ?? 0
    let cut = CellRange(
      start: CellAddress(row: clampedRow, col: 0),
      end: CellAddress(row: clampedRow, col: max(sheet.effectiveColumnCount - 1, widestCol))
    )
    if isRowInSelection(clampedRow) {
      // Drop every highlighted cell in the row, even inside a larger block.
      // The last highlighted cell stays, as with a single cell.
      let remaining = selectionRanges.flatMap { rangeSplitting($0, without: cut) }
      guard let active = remaining.last else {
        isEditing = false
        return
      }
      selectionRanges = remaining
      selectionAnchor = active.start
      selectionEnd = active.end
      noteSelectionChanged()
    } else {
      selectionRanges.append(rowRange)
      selectionAnchor = rowRange.start
      selectionEnd = rowRange.end
      noteSelectionChanged()
    }
    syncEditTextFromSelection()
    isEditing = false
  }

  /// ⌘A / Edit → Select All: always the entire sheet.
  func selectAll() {
    commitEditIfNeeded()
    let sheet = activeSheet
    let wholeEnd = CellAddress(
      row: sheet.effectiveRowCount - 1,
      col: sheet.effectiveColumnCount - 1
    )
    replaceSelection(with: CellRange(start: .origin, end: wholeEnd))
    syncEditTextFromSelection()
    isEditing = false
  }

  /// Corner-header click: used range first, then whole sheet (Excel-style).
  func selectUsedRangeOrAll() {
    commitEditIfNeeded()
    let sheet = activeSheet
    let wholeEnd = CellAddress(
      row: sheet.effectiveRowCount - 1,
      col: sheet.effectiveColumnCount - 1
    )

    if let used = sheet.populatedBounds {
      let usedNorm = used.normalized
      let current = selectionRange.normalized
      let alreadyUsed =
        !hasMultipleSelectionRanges
        && current.minRow == usedNorm.minRow
        && current.maxRow == usedNorm.maxRow
        && current.minCol == usedNorm.minCol
        && current.maxCol == usedNorm.maxCol
      if alreadyUsed {
        replaceSelection(with: CellRange(start: .origin, end: wholeEnd))
      } else {
        replaceSelection(
          with: CellRange(
            start: CellAddress(row: usedNorm.minRow, col: usedNorm.minCol),
            end: CellAddress(row: usedNorm.maxRow, col: usedNorm.maxCol)
          ))
      }
    } else {
      replaceSelection(with: CellRange(start: .origin, end: wholeEnd))
    }
    syncEditTextFromSelection()
    isEditing = false
  }

  func toggleSelectAll() {
    if selectionAxis == .sheet {
      select(.origin)
    } else {
      selectUsedRangeOrAll()
    }
  }

  func moveSelection(rowDelta: Int, colDelta: Int, extending: Bool = false) {
    commitEditIfNeeded()
    if extending {
      var endRow = selectionEnd.row + rowDelta
      var endCol = selectionEnd.col + colDelta
      endRow = max(0, min(activeSheet.effectiveRowCount - 1, endRow))
      endCol = max(0, min(activeSheet.effectiveColumnCount - 1, endCol))
      if rowDelta != 0 {
        endRow = nextVisibleRow(from: selectionEnd.row, delta: rowDelta) ?? endRow
      }
      if colDelta != 0 {
        endCol = nextVisibleColumn(from: selectionEnd.col, delta: colDelta) ?? endCol
      }
      selectionEnd = CellAddress(row: endRow, col: endCol)
      setPrimaryRange(from: selectionAnchor, to: selectionEnd)
    } else {
      var nextRow = selectionAnchor.row + rowDelta
      var nextCol = selectionAnchor.col + colDelta
      nextRow = max(0, min(activeSheet.effectiveRowCount - 1, nextRow))
      nextCol = max(0, min(activeSheet.effectiveColumnCount - 1, nextCol))
      if rowDelta != 0 {
        nextRow = nextVisibleRow(from: selectionAnchor.row, delta: rowDelta) ?? nextRow
      }
      if colDelta != 0 {
        nextCol = nextVisibleColumn(from: selectionAnchor.col, delta: colDelta) ?? nextCol
      }
      let next = CellAddress(row: nextRow, col: nextCol)
      replaceSelection(with: CellRange(start: next, end: next))
    }
    syncEditTextFromSelection()
    isEditing = false
  }

  /// ⌘-arrow: jump to the edge of the data, as Excel's Ctrl-arrow does. From a filled cell
  /// with a filled neighbour, go to the last filled cell of that run. Otherwise go to the next
  /// filled cell, or to the edge of the used range when nothing else is filled that way.
  /// Rows the filter hides, and rows and columns the file hides, are skipped.
  func jumpSelection(rowStep: Int, colStep: Int, extending: Bool = false) {
    commitEditIfNeeded()
    let sheet = activeSheet
    let start = extending ? selectionEnd : selectionAnchor
    let maxRow = sheet.effectiveRowCount - 1
    let maxCol = sheet.effectiveColumnCount - 1
    func filled(_ address: CellAddress) -> Bool { !sheet.cell(at: address).raw.isEmpty }
    func step(_ address: CellAddress) -> CellAddress? {
      var row = address.row + rowStep
      var col = address.col + colStep
      while row >= 0, row <= maxRow, rowStep != 0, isRowHidden(row) {
        row += rowStep
      }
      while col >= 0, col <= maxCol, colStep != 0, sheet.isColumnHidden(col) {
        col += colStep
      }
      guard row >= 0, row <= maxRow, col >= 0, col <= maxCol else { return nil }
      return CellAddress(row: row, col: col)
    }

    var target = start
    if filled(start), let next = step(start), filled(next) {
      target = next
      while let further = step(target), filled(further) {
        target = further
      }
    } else {
      var probe = start
      var found: CellAddress?
      let used = sheet.populatedBounds?.normalized
      while let next = step(probe) {
        probe = next
        if filled(next) {
          found = next
          break
        }
        // Past the used range there is nothing left to find.
        if let used, next.row > used.maxRow || next.col > used.maxCol { break }
      }
      if let found {
        target = found
      } else if rowStep < 0 || colStep < 0 {
        target = CellAddress(
          row: rowStep < 0 ? 0 : start.row, col: colStep < 0 ? 0 : start.col)
      } else if let used {
        // Stop at the end of the data, not at the sheet's last row.
        target = CellAddress(
          row: rowStep > 0 ? max(start.row, used.maxRow) : start.row,
          col: colStep > 0 ? max(start.col, used.maxCol) : start.col)
      }
    }

    if extending {
      selectionEnd = target
      setPrimaryRange(from: selectionAnchor, to: target)
    } else {
      replaceSelection(with: CellRange(start: target, end: target))
    }
    syncEditTextFromSelection()
    isEditing = false
  }

  private func nextVisibleRow(from row: Int, delta: Int) -> Int? {
    guard delta != 0 else { return row }
    let step = delta > 0 ? 1 : -1
    var remaining = abs(delta)
    var current = row
    let maxRow = activeSheet.effectiveRowCount - 1
    while remaining > 0 {
      current += step
      if current < 0 || current > maxRow { return nil }
      if !isRowHidden(current) {
        remaining -= 1
      }
    }
    return current
  }

  private func nextVisibleColumn(from col: Int, delta: Int) -> Int? {
    guard delta != 0 else { return col }
    let sheet = activeSheet
    let step = delta > 0 ? 1 : -1
    var remaining = abs(delta)
    var current = col
    let maxCol = sheet.effectiveColumnCount - 1
    while remaining > 0 {
      current += step
      if current < 0 || current > maxCol { return nil }
      if !sheet.isColumnHidden(current) {
        remaining -= 1
      }
    }
    return current
  }

  /// Hidden by the filter or by the file.
  func isRowHidden(_ row: Int) -> Bool {
    activeSheet.isRowHidden(row) || isRowHiddenByFilter(row)
  }

  func select(_ address: CellAddress) {
    selectRange(from: address, to: address)
  }

  func selectColumn(_ col: Int) {
    selectColumns(from: col, to: col)
  }

  func selectColumns(from startCol: Int, to endCol: Int) {
    commitEditIfNeeded()
    let sheet = activeSheet
    let a = max(0, min(sheet.effectiveColumnCount - 1, startCol))
    let b = max(0, min(sheet.effectiveColumnCount - 1, endCol))
    replaceSelection(
      with: CellRange(
        start: CellAddress(row: 0, col: a),
        end: CellAddress(row: sheet.effectiveRowCount - 1, col: b)
      ))
    syncEditTextFromSelection()
    isEditing = false
  }

  func toggleColumnSelection(_ col: Int) {
    let clampedCol = max(0, min(activeSheet.effectiveColumnCount - 1, col))
    let range = selectionRange.normalized
    if !hasMultipleSelectionRanges,
      selectionAxis == .column,
      range.minCol == clampedCol,
      range.maxCol == clampedCol
    {
      select(CellAddress(row: 0, col: clampedCol))
    } else {
      selectColumn(clampedCol)
    }
  }

  func selectRow(_ row: Int) {
    selectRows(from: row, to: row)
  }

  func selectRows(from startRow: Int, to endRow: Int) {
    commitEditIfNeeded()
    let sheet = activeSheet
    let a = max(0, min(sheet.effectiveRowCount - 1, startRow))
    let b = max(0, min(sheet.effectiveRowCount - 1, endRow))
    replaceSelection(
      with: CellRange(
        start: CellAddress(row: a, col: 0),
        end: CellAddress(row: b, col: sheet.effectiveColumnCount - 1)
      ))
    syncEditTextFromSelection()
    isEditing = false
  }

  func toggleRowSelection(_ row: Int) {
    let clampedRow = max(0, min(activeSheet.effectiveRowCount - 1, row))
    let range = selectionRange.normalized
    if !hasMultipleSelectionRanges,
      selectionAxis == .row,
      range.minRow == clampedRow,
      range.maxRow == clampedRow
    {
      select(CellAddress(row: clampedRow, col: 0))
    } else {
      selectRow(clampedRow)
    }
  }

  func beginEditing(preserveSelection: Bool = true) {
    if !preserveSelection { return }
    formulaArgumentHint = nil
    editText = selectedCell.editableText
    isEditing = true
    focusedFormulaHighlightIndex = nil
    noteFormulaEditTextChanged()
  }

  func commitEdit() {
    formulaArgumentHint = nil
    let address = selectionAnchor
    let newValue = editText
    let cell = activeSheet.cell(at: address)
    // Unchanged text, including a percent or date shown as `29.8%` or `2/28/2026`, is no edit.
    guard newValue != cell.raw, newValue != cell.editableText else {
      isEditing = false
      noteFormulaEditTextChanged()
      return
    }
    setCellValue(newValue, at: address)
    isEditing = false
    noteFormulaEditTextChanged()
  }

  func cancelEdit() {
    formulaArgumentHint = nil
    syncEditTextFromSelection()
    isEditing = false
    noteFormulaEditTextChanged()
  }

  func commitEditIfNeeded() {
    guard isEditing else { return }
    commitEdit()
  }

  func setCellValue(_ value: String, at address: CellAddress) {
    let oldValue = activeSheet.cell(at: address).raw
    guard value != oldValue else { return }
    guard writeCell(value, at: address) else { return }
    registerUndo(address: address, oldValue: oldValue, newValue: value)
    if address == selectionAnchor && !isEditing {
      editText = value
    }
  }

  /// `cell.set`. Percent literals pick up a percent format inside the command.
  private func writeCell(_ value: String, at address: CellAddress) -> Bool {
    applyCommand(
      "cell.set",
      [
        "sheet": activeSheet.name,
        "address": address.a1,
        "raw": value,
      ],
      incremental: true
    )
  }

  /// Commands that move or remove rows, which a remembered sort order cannot survive.
  static let rowMovingCommands: Set<String> = [
    "data.sort", "sheet.insertRows", "sheet.deleteRows", "sheet.insertColumns",
    "sheet.deleteColumns", "sheet.delete",
  ]

  @discardableResult
  func applyCommand(
    _ id: String,
    _ arguments: [String: String],
    incremental: Bool
  ) -> Bool {
    var next = workbook
    let outcome = engineCommands.apply(
      id: id,
      arguments: arguments,
      to: &next,
      sortDisplay: id == "data.sort"
        ? { _, address in
          self.sortKey(at: address)
        } : nil
    )
    guard outcome.ok else { return false }
    if Self.rowMovingCommands.contains(id) {
      filterSortMemory = nil
    }
    let change = engineCommands.lastChange
    if incremental, !change.structural,
      next.sheets.count == workbook.sheets.count,
      workbook.sheets.indices.contains(workbook.activeSheetIndex),
      change.sheetName.caseInsensitiveCompare(activeSheet.name) == .orderedSame
    {
      setActiveSheet(
        next.sheets[workbook.activeSheetIndex],
        formulaCellsChanged: change.addresses
      )
    } else {
      workbook = next
    }
    return true
  }

  private func sortKey(at address: CellAddress) -> (key: String, number: Double?) {
    let key = displayString(at: address)
    let number =
      displayValue(at: address).asNumber
      ?? Double(
        key.replacingOccurrences(of: ",", with: "")
          .replacingOccurrences(of: "%", with: "")
          .replacingOccurrences(of: "$", with: "")
          .trimmingCharacters(in: .whitespacesAndNewlines)
      )
    return (key, number)
  }

  func applyFormulaBar() {
    commitEdit()
  }

  /// Commits whatever is currently in the formula bar (source of truth = field text).
  func commitFormulaBarText(_ text: String) {
    editText = text
    isEditing = true
    commitEdit()
  }

  func autoFitColumn(_ col: Int, recordUndo: Bool = true) {
    var sheet = activeSheet
    let oldWidth = sheet.columnWidth(for: col, default: Workbook.defaultColumnWidth)
    var maxWidth = Workbook.defaultColumnWidth
    let lastRow = max(sheet.maxPopulatedRow, 0)
    for row in 0...min(lastRow, activeSheet.effectiveRowCount - 1) {
      let address = CellAddress(row: row, col: col)
      let cell = sheet.cell(at: address)
      let text = displayString(at: address)
      guard !text.isEmpty else { continue }
      let width = CellFormatRenderer.measuredWidth(for: text, format: cell.format) + 16
      maxWidth = max(maxWidth, width)
    }
    let newWidth = min(max(maxWidth, 48), 420)
    guard abs(oldWidth - newWidth) > 0.5 else { return }
    sheet.columnWidths[col] = newWidth
    setSheetSizeKeepingPaintCache(sheet)
    if recordUndo {
      registerColumnWidthUndo(
        col: col, oldWidth: oldWidth, newWidth: newWidth, actionName: "Auto Fit Column")
    }
  }

  func autoFitRow(_ row: Int, recordUndo: Bool = true) {
    var sheet = activeSheet
    let oldHeight = sheet.rowHeight(for: row, default: Workbook.defaultRowHeight)
    var maxHeight = Workbook.defaultRowHeight
    let lastCol = max(sheet.maxPopulatedColumn, 0)
    for col in 0...min(lastCol, activeSheet.effectiveColumnCount - 1) {
      let address = CellAddress(row: row, col: col)
      let cell = sheet.cell(at: address)
      let text = displayString(at: address)
      guard !text.isEmpty else { continue }
      let height: CGFloat
      if cell.format?.textDisplay == .wrap {
        height = CellTextLayout.preferredWrappedRowHeight(
          text: text,
          format: cell.format ?? CellFormat(),
          columnWidth: sheet.columnWidth(for: col, default: Workbook.defaultColumnWidth)
        )
      } else {
        height = CellFormatRenderer.measuredHeight(for: text, format: cell.format) + 8
      }
      maxHeight = max(maxHeight, height)
    }
    let newHeight = min(max(maxHeight, 22), 200)
    guard abs(oldHeight - newHeight) > 0.5 else { return }
    sheet.rowHeights[row] = newHeight
    setSheetSizeKeepingPaintCache(sheet)
    if recordUndo {
      registerRowHeightUndo(
        row: row, oldHeight: oldHeight, newHeight: newHeight, actionName: "Auto Fit Row")
    }
  }

  func autoFitAllColumns() {
    let before = activeSheet.columnWidths
    let lastCol = max(activeSheet.maxPopulatedColumn, activeSheet.effectiveColumnCount - 1)
    for col in 0...lastCol {
      autoFitColumn(col, recordUndo: false)
    }
    registerColumnWidthsUndo(
      before: before, after: activeSheet.columnWidths, actionName: "Auto Fit Columns")
  }

  func autoFitAllRows() {
    let before = activeSheet.rowHeights
    let lastRow = max(activeSheet.maxPopulatedRow, activeSheet.effectiveRowCount - 1)
    for row in 0...lastRow where !isRowHiddenByFilter(row) {
      autoFitRow(row, recordUndo: false)
    }
    registerRowHeightsUndo(
      before: before, after: activeSheet.rowHeights, actionName: "Auto Fit Rows")
  }

  func columnWidth(for col: Int) -> CGFloat {
    activeSheet.columnWidth(for: col, default: Workbook.defaultColumnWidth)
  }

  func rowHeight(for row: Int) -> CGFloat {
    activeSheet.rowHeight(for: row, default: Workbook.defaultRowHeight)
  }

  func setColumnWidth(_ col: Int, width: CGFloat, recordUndo: Bool = true) {
    var sheet = activeSheet
    let oldWidth = sheet.columnWidth(for: col, default: Workbook.defaultColumnWidth)
    let newWidth = min(max(width, 24), 600)
    guard abs(oldWidth - newWidth) > 0.5 else { return }
    sheet.columnWidths[col] = newWidth
    setSheetSizeKeepingPaintCache(sheet)
    if recordUndo {
      registerColumnWidthUndo(
        col: col, oldWidth: oldWidth, newWidth: newWidth, actionName: "Resize Column")
    }
  }

  func setRowHeight(_ row: Int, height: CGFloat, recordUndo: Bool = true) {
    var sheet = activeSheet
    let oldHeight = sheet.rowHeight(for: row, default: Workbook.defaultRowHeight)
    let newHeight = min(max(height, 16), 400)
    guard abs(oldHeight - newHeight) > 0.5 else { return }
    sheet.rowHeights[row] = newHeight
    setSheetSizeKeepingPaintCache(sheet)
    if recordUndo {
      registerRowHeightUndo(
        row: row, oldHeight: oldHeight, newHeight: newHeight, actionName: "Resize Row")
    }
  }

  /// Call once after a drag-resize gesture (undo is deferred until mouse up).
  func commitColumnWidthResize(col: Int, from oldWidth: CGFloat) {
    registerColumnWidthUndo(
      col: col,
      oldWidth: oldWidth,
      newWidth: columnWidth(for: col),
      actionName: "Resize Column"
    )
  }

  func commitRowHeightResize(row: Int, from oldHeight: CGFloat) {
    registerRowHeightUndo(
      row: row,
      oldHeight: oldHeight,
      newHeight: rowHeight(for: row),
      actionName: "Resize Row"
    )
  }

  private func registerColumnWidthUndo(
    col: Int,
    oldWidth: CGFloat,
    newWidth: CGFloat,
    actionName: String
  ) {
    guard abs(oldWidth - newWidth) > 0.5 else { return }
    undoManager?.registerUndo(withTarget: self) { target in
      target.setColumnWidth(col, width: oldWidth, recordUndo: false)
      target.notifyGridRefresh()
      target.undoManager?.registerUndo(withTarget: target) { inner in
        inner.setColumnWidth(col, width: newWidth, recordUndo: false)
        inner.notifyGridRefresh()
      }
    }
    undoManager?.setActionName(actionName)
  }

  private func registerRowHeightUndo(
    row: Int,
    oldHeight: CGFloat,
    newHeight: CGFloat,
    actionName: String
  ) {
    guard abs(oldHeight - newHeight) > 0.5 else { return }
    undoManager?.registerUndo(withTarget: self) { target in
      target.setRowHeight(row, height: oldHeight, recordUndo: false)
      target.notifyGridRefresh()
      target.undoManager?.registerUndo(withTarget: target) { inner in
        inner.setRowHeight(row, height: newHeight, recordUndo: false)
        inner.notifyGridRefresh()
      }
    }
    undoManager?.setActionName(actionName)
  }

  private func registerColumnWidthsUndo(
    before: [Int: CGFloat],
    after: [Int: CGFloat],
    actionName: String
  ) {
    guard before != after else { return }
    undoManager?.registerUndo(withTarget: self) { target in
      var workbook = target.workbook
      var sheet = workbook.activeSheet
      sheet.columnWidths = before
      workbook.activeSheet = sheet
      target.workbook = workbook
      target.notifyGridRefresh()
      target.undoManager?.registerUndo(withTarget: target) { inner in
        var workbook = inner.workbook
        var sheet = workbook.activeSheet
        sheet.columnWidths = after
        workbook.activeSheet = sheet
        inner.workbook = workbook
        inner.notifyGridRefresh()
      }
    }
    undoManager?.setActionName(actionName)
  }

  private func registerRowHeightsUndo(
    before: [Int: CGFloat],
    after: [Int: CGFloat],
    actionName: String
  ) {
    guard before != after else { return }
    undoManager?.registerUndo(withTarget: self) { target in
      var workbook = target.workbook
      var sheet = workbook.activeSheet
      sheet.rowHeights = before
      workbook.activeSheet = sheet
      target.workbook = workbook
      target.notifyGridRefresh()
      target.undoManager?.registerUndo(withTarget: target) { inner in
        var workbook = inner.workbook
        var sheet = workbook.activeSheet
        sheet.rowHeights = after
        workbook.activeSheet = sheet
        inner.workbook = workbook
        inner.notifyGridRefresh()
      }
    }
    undoManager?.setActionName(actionName)
  }

  // MARK: - Sheets

  func addSheet() {
    commitEditIfNeeded()
    var next = workbook
    let preferred = "Sheet\(next.sheets.count + 1)"
    let outcome = engineCommands.apply(
      id: "sheet.add",
      arguments: ["name": preferred],
      to: &next
    )
    guard outcome.ok else { return }
    if let index = next.sheets.firstIndex(where: { $0.name == engineCommands.lastChange.sheetName })
    {
      next.activeSheetIndex = index
    }
    workbook = next
    selection = .origin
    syncEditTextFromSelection()
    isEditing = false
  }

  /// The selection each sheet had when another one was shown, as other spreadsheet apps keep it.
  private struct SavedSelection {
    var anchor: CellAddress
    var end: CellAddress
    var ranges: [CellRange]
  }

  func selectSheet(at index: Int) {
    commitEditIfNeeded()
    guard index >= 0, index < workbook.sheets.count else { return }
    if index != workbook.activeSheetIndex {
      savedSelections[activeSheet.id] = SavedSelection(
        anchor: selectionAnchor, end: selectionEnd, ranges: selectionRanges)
    }
    withoutRecordingEdit {
      // One activation. `workbook` didSet would rebuild again and drop the
      // values `activateSheet` just kept for the other sheets.
      suspendFormulaRebuild = true
      workbook.activeSheetIndex = index
      suspendFormulaRebuild = false
      formulaEngine.activateSheet(workbook)
      restoreFilterFromActiveSheet()
    }
    invalidateFindMatches()
    if let saved = savedSelections[activeSheet.id] {
      selectionAnchor = clamp(saved.anchor)
      selectionEnd = clamp(saved.end)
      selectionRanges = saved.ranges.map { CellRange(start: clamp($0.start), end: clamp($0.end)) }
      if selectionRanges.isEmpty { selectionRanges = [selectionRange] }
      noteSelectionChanged()
    } else {
      selection = .origin
    }
    syncEditTextFromSelection()
    isEditing = false
  }

  func deleteSheet(at index: Int) {
    commitEditIfNeeded()
    guard workbook.sheets.count > 1 else { return }
    guard workbook.sheets.indices.contains(index) else { return }
    // A hidden sheet cannot be left as the only one; one tab always shows.
    if !workbook.sheets[index].isHidden, workbook.sheets.filter({ !$0.isHidden }).count <= 1 {
      return
    }

    let name = workbook.sheets[index].name
    let wasActive = index == workbook.activeSheetIndex
    let stampBefore = editStamp
    var next = workbook
    let outcome = engineCommands.apply(id: "sheet.delete", arguments: ["sheet": name], to: &next)
    guard outcome.ok else { return }
    // The tab after a deleted one may be hidden; show the nearest visible sheet instead.
    if next.activeSheet.isHidden {
      let active = next.activeSheetIndex
      if let visible = next.sheets.indices.filter({ !next.sheets[$0].isHidden })
        .min(by: { abs($0 - active) < abs($1 - active) })
      {
        next.activeSheetIndex = visible
      }
    }
    workbook = next
    if wasActive {
      restoreFilterFromActiveSheet()
    }
    finishWorkbookMutation(stampBefore: stampBefore)
    contentRevision &+= 1
    invalidateFindMatches()
    selection = .origin
    syncEditTextFromSelection()
    isEditing = false
  }

  /// Moves a sheet tab, as a drag in the tab bar does. Formulas name sheets rather than
  /// positions, so none change. The file keeps this order: export writes tabs in array order.
  func moveSheet(from source: Int, to destination: Int) {
    commitEditIfNeeded()
    guard workbook.sheets.indices.contains(source),
      workbook.sheets.indices.contains(destination), source != destination
    else { return }
    let activeID = workbook.activeSheet.id
    var next = workbook
    let sheet = next.sheets.remove(at: source)
    next.sheets.insert(sheet, at: destination)
    next.activeSheetIndex = next.sheets.firstIndex { $0.id == activeID } ?? 0
    workbook = next
    restoreFilterFromActiveSheet()
    undoManager?.registerUndo(withTarget: self) { target in
      target.moveSheet(from: destination, to: source)
    }
    undoManager?.setActionName("Move Sheet")
  }

  /// Hidden sheets a person may show again. Sheets the file marks very hidden are not listed.
  var unhideableSheets: [(index: Int, name: String)] {
    workbook.sheets.enumerated().compactMap { index, sheet in
      sheet.fileExtras.visibility == .hidden ? (index, sheet.name) : nil
    }
  }

  /// Whether Hide Sheet applies: another sheet stays visible.
  var canHideActiveSheet: Bool {
    workbook.sheets.filter { !$0.isHidden }.count > 1
  }

  /// Hides or shows a sheet's tab. The last visible sheet cannot be hidden.
  func setSheetHidden(_ hidden: Bool, at index: Int) {
    guard workbook.sheets.indices.contains(index) else { return }
    let before = workbook.sheets[index].fileExtras.visibility
    let after: SheetFileExtras.Visibility = hidden ? .hidden : .visible
    guard before != after else { return }
    if hidden, workbook.sheets.filter({ !$0.isHidden }).count <= 1 { return }
    commitEditIfNeeded()
    setSheetVisibility(after, at: index)
    undoManager?.registerUndo(withTarget: self) { target in
      target.setSheetVisibility(before, at: index)
      target.undoManager?.registerUndo(withTarget: target) { inner in
        inner.setSheetVisibility(after, at: index)
      }
    }
    undoManager?.setActionName(hidden ? "Hide Sheet" : "Unhide Sheet")
  }

  private func setSheetVisibility(_ visibility: SheetFileExtras.Visibility, at index: Int) {
    guard workbook.sheets.indices.contains(index) else { return }
    let stampBefore = editStamp
    suspendFormulaRebuild = true
    workbook.sheets[index].fileExtras.visibility = visibility
    suspendFormulaRebuild = false
    finishWorkbookMutation(stampBefore: stampBefore)
    // The tab beside the hidden one, as Delete does, not the first tab in the workbook.
    let sheets = workbook.sheets
    if visibility != .visible, index == workbook.activeSheetIndex,
      let next = sheets.indices.first(where: { $0 > index && !sheets[$0].isHidden })
        ?? sheets.indices.last(where: { $0 < index && !sheets[$0].isHidden })
    {
      selectSheet(at: next)
    } else if visibility == .visible {
      selectSheet(at: index)
    }
  }

  func renameSheet(at index: Int, to name: String) {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    guard workbook.sheets.indices.contains(index) else { return }
    let stampBefore = editStamp
    var next = workbook
    let outcome = engineCommands.apply(
      id: "sheet.rename",
      arguments: ["sheet": workbook.sheets[index].name, "name": trimmed],
      to: &next
    )
    guard outcome.ok else { return }
    workbook = next
    finishWorkbookMutation(stampBefore: stampBefore)
  }

  // MARK: - Formatting

  var selectedFormat: CellFormat {
    selectedCell.format ?? CellFormat()
  }

  /// Text display shared by every selected cell. Nil when the selection mixes modes.
  /// Covered merge cells follow the anchor and are not a second mode.
  var uniformTextDisplay: CellFormat.TextDisplay? {
    // The toolbar asks on every render, including while scrolling. With a whole row selected
    // the answer scans every cell on the sheet, so it is kept until the cells or selection change.
    let key = UniformTextDisplayKey(
      contentRevision: contentRevision, ranges: selectionRanges, anchor: selectionAnchor)
    if let cached = uniformTextDisplayCache, cached.key == key { return cached.value }
    let value = computeUniformTextDisplay()
    uniformTextDisplayCache = (key, value)
    return value
  }

  private struct UniformTextDisplayKey: Equatable {
    var contentRevision: Int
    var ranges: [CellRange]
    var anchor: CellAddress
  }

  @ObservationIgnored private var uniformTextDisplayCache:
    (key: UniformTextDisplayKey, value: CellFormat.TextDisplay?)?

  private func computeUniformTextDisplay() -> CellFormat.TextDisplay? {
    let sheet = activeSheet
    var uniform: CellFormat.TextDisplay?
    var counted = 0
    for range in selectionRanges {
      let bounds = range.normalized
      let area = (bounds.maxRow - bounds.minRow + 1) * (bounds.maxCol - bounds.minCol + 1)
      // A whole row or column is thousands of mostly empty cells, checked on every toolbar
      // redraw. Look at the cells that exist; any cell left over is blank, which is Overflow.
      if area > 4_000, sheet.mergedRanges.isEmpty {
        var seen = 0
        for (address, cell) in sheet.cells where range.contains(address) {
          seen += 1
          let display = cell.format?.textDisplay ?? .overflow
          if let uniform, uniform != display { return nil }
          uniform = display
        }
        if seen < area {
          if let uniform, uniform != .overflow { return nil }
          uniform = .overflow
        }
        counted += area
        continue
      }
      for row in bounds.minRow...bounds.maxRow {
        for col in bounds.minCol...bounds.maxCol {
          let address = CellAddress(row: row, col: col)
          if sheet.isCoveredByMerge(address) { continue }
          let display = sheet.cell(at: address).format?.textDisplay ?? .overflow
          counted += 1
          if let uniform, uniform != display { return nil }
          uniform = display
        }
      }
    }
    if counted > 0 { return uniform }
    return sheet.cell(at: selectionAnchor).format?.textDisplay ?? .overflow
  }

  /// Label on the wrap toolbar control. A mixed selection does not name Overflow, Wrap, or Clip.
  var textDisplayToolbarTitle: String {
    uniformTextDisplay?.toolbarTitle ?? CellFormat.TextDisplay.mixedToolbarTitle
  }

  func toggleBold() { updateSelectedFormat { $0.bold.toggle() } }
  func toggleItalic() { updateSelectedFormat { $0.italic.toggle() } }
  func toggleUnderline() { updateSelectedFormat { $0.underline.toggle() } }
  func toggleStrikethrough() { updateSelectedFormat { $0.strikethrough.toggle() } }
  func setTextDisplay(_ display: CellFormat.TextDisplay) {
    updateSelectedFormat { $0.textDisplay = display }
  }

  func setFontFamily(_ family: String) {
    updateSelectedFormat { $0.fontFamily = family }
  }

  func setFontSize(_ size: CGFloat) {
    let clamped = min(max(size, 6), 72)
    updateSelectedFormat { $0.fontSize = clamped }
  }

  func adjustFontSize(by delta: CGFloat) {
    let current = selectedFormat.fontSize ?? CellFormatRenderer.defaultFontSize
    setFontSize(current + delta)
  }

  func setTextColor(_ color: CodableColor?) {
    updateSelectedFormat { $0.textColor = color }
  }

  func setFillColor(_ color: CodableColor?) {
    updateSelectedFormat { $0.fillColor = color }
  }

  /// Banded rows: even data rows get `bandColor`, odd rows clear fill. Header row is skipped when requested.
  /// Every selected range is done in one pass with one undo step.
  func applyAlternatingRowColors(bandColor: CodableColor, hasHeader: Bool) {
    commitEditIfNeeded()
    let ranges = selectionRanges.isEmpty ? [selectionRange] : selectionRanges
    let bands: [CellRange] = ranges.compactMap { range in
      let n = range.normalized
      let first = hasHeader ? n.minRow + 1 : n.minRow
      guard first <= n.maxRow else { return nil }
      return CellRange(
        start: CellAddress(row: first, col: n.minCol),
        end: CellAddress(row: n.maxRow, col: n.maxCol))
    }
    let firstRows = bands.map { ($0, $0.normalized.minRow) }
    applyFormat(toRanges: bands, actionName: "Alternating Row Colors") { address, format in
      let first = firstRows.first { $0.0.contains(address) }?.1 ?? address.row
      format.fillColor = (address.row - first) % 2 == 0 ? bandColor : nil
    }
  }

  func setHorizontalAlign(_ align: CellFormat.HorizontalAlign) {
    updateSelectedFormat { $0.horizontalAlign = align }
  }

  func setVerticalAlign(_ align: CellFormat.VerticalAlign) {
    updateSelectedFormat { $0.verticalAlign = align }
  }

  func setTextRotation(_ degrees: Int) {
    updateSelectedFormat { $0.textRotation = degrees }
  }

  func setNumberFormat(_ numberFormat: CellFormat.NumberFormat) {
    updateSelectedFormat { format in
      format.numberFormat = numberFormat
      format.formatCode = nil
      if format.decimalPlaces == nil {
        format.decimalPlaces = defaultDecimalPlaces(for: numberFormat)
      }
    }
  }

  /// Stores a custom number-format code. Empty or General clears it.
  /// Preset formats go through `setNumberFormat`, which removes a custom code.
  func setFormatCode(_ raw: String?) {
    updateSelectedFormat { format in
      let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      if trimmed.isEmpty || trimmed.caseInsensitiveCompare("General") == .orderedSame {
        format.numberFormat = .general
        format.formatCode = nil
        format.decimalPlaces = nil
        return
      }
      format.formatCode = trimmed
      format.numberFormat = ExcelFormatCode.numberFormatKind(for: trimmed)
      format.decimalPlaces = nil
    }
  }

  /// Default color used when applying border presets from the toolbar.
  var borderColor: CodableColor?
  /// Line style used when applying border presets (thin, dashed, dotted, …).
  var borderStyle: BorderStyle = .thin

  func setBorderColor(_ color: CodableColor?) {
    borderColor = color
  }

  func setBorderStyle(_ style: BorderStyle) {
    borderStyle = style
  }

  func applyBorderPreset(_ preset: BorderPreset) {
    commitEditIfNeeded()
    let edge = BorderEdge.styled(borderStyle, color: borderColor)
    let thickEdge = BorderEdge.styled(.thick, color: borderColor)
    undoManager?.beginUndoGrouping()
    for range in selectionRanges {
      applyBorderPreset(preset, to: range, edge: edge, thickEdge: thickEdge)
    }
    undoManager?.endUndoGrouping()
    undoManager?.setActionName("Format Cells")
  }

  private func applyBorderPreset(
    _ preset: BorderPreset,
    to range: CellRange,
    edge: BorderEdge,
    thickEdge: BorderEdge
  ) {
    let n = range.normalized
    switch preset {
    case .none:
      applyBorderMutation(in: range) { _, borders in
        borders = .none
      }
    case .all:
      applyBorderMutation(in: range) { _, borders in
        borders = CellBorders(top: edge, bottom: edge, left: edge, right: edge)
      }
    case .outside:
      applyBorderMutation(in: range) { address, borders in
        if address.row == n.minRow { borders.top = edge }
        if address.row == n.maxRow { borders.bottom = edge }
        if address.col == n.minCol { borders.left = edge }
        if address.col == n.maxCol { borders.right = edge }
      }
    case .inside:
      applyBorderMutation(in: range) { address, borders in
        if address.row > n.minRow { borders.top = edge }
        if address.row < n.maxRow { borders.bottom = edge }
        if address.col > n.minCol { borders.left = edge }
        if address.col < n.maxCol { borders.right = edge }
      }
    case .top:
      applyBorderMutation(in: range) { address, borders in
        if address.row == n.minRow { borders.top = edge }
      }
    case .bottom:
      applyBorderMutation(in: range) { address, borders in
        if address.row == n.maxRow { borders.bottom = edge }
      }
    case .left:
      applyBorderMutation(in: range) { address, borders in
        if address.col == n.minCol { borders.left = edge }
      }
    case .right:
      applyBorderMutation(in: range) { address, borders in
        if address.col == n.maxCol { borders.right = edge }
      }
    case .thickOutside:
      applyBorderMutation(in: range) { address, borders in
        if address.row == n.minRow { borders.top = thickEdge }
        if address.row == n.maxRow { borders.bottom = thickEdge }
        if address.col == n.minCol { borders.left = thickEdge }
        if address.col == n.maxCol { borders.right = thickEdge }
      }
    }
  }

  /// Address-aware border edits in one sheet write, with one undo step.
  private func applyBorderMutation(
    in range: CellRange,
    mutate: (CellAddress, inout CellBorders) -> Void
  ) {
    applyFormat(toRanges: [range], actionName: nil) { address, format in
      mutate(address, &format.borders)
    }
  }

  private func updateFormat(in range: CellRange, mutate: (inout CellFormat) -> Void) {
    applyFormat(to: range, mutate: mutate)
  }

  private func mutateBorders(at address: CellAddress, mutate: (inout CellBorders) -> Void) {
    applyFormatMutation(at: address) { format in
      mutate(&format.borders)
    }
  }

  func increaseDecimalPlaces() {
    updateSelectedFormat { format in
      let current = displayedDecimalPlaces(for: format)
      format.decimalPlaces = min(current + 1, 10)
      format.numberFormat = format.numberFormat == .general ? .number : format.numberFormat
    }
  }

  func decreaseDecimalPlaces() {
    updateSelectedFormat { format in
      let current = displayedDecimalPlaces(for: format)
      format.decimalPlaces = max(current - 1, 0)
    }
  }

  private func displayedDecimalPlaces(for format: CellFormat) -> Int {
    if let explicit = format.decimalPlaces { return explicit }
    if let code = format.formatCode, let digits = ExcelFormatCode.fractionDigits(in: code) {
      return digits
    }
    return defaultDecimalPlaces(for: format.numberFormat)
  }

  private func defaultDecimalPlaces(for format: CellFormat.NumberFormat) -> Int {
    switch format {
    case .general: return 0
    case .number, .currency, .percent, .scientific: return 2
    case .date, .time: return 0
    }
  }

  private func updateSelectedFormat(_ mutate: (inout CellFormat) -> Void) {
    commitEditIfNeeded()
    undoManager?.beginUndoGrouping()
    for range in selectionRanges {
      applyFormat(to: range, mutate: mutate)
    }
    undoManager?.endUndoGrouping()
    undoManager?.setActionName("Format Cells")
  }

  private func applyFormat(to range: CellRange, mutate: (inout CellFormat) -> Void) {
    applyFormat(toRanges: [range], actionName: nil) { _, format in mutate(&format) }
  }

  /// Formats every cell in `ranges` in one pass over one copy of the sheet, with one undo step.
  /// Empty cells are visited too, so a fill reaches them.
  private func applyFormat(
    toRanges ranges: [CellRange],
    actionName: String?,
    mutate: (CellAddress, inout CellFormat) -> Void
  ) {
    var sheet = activeSheet
    var before: [CellAddress: CellFormat?] = [:]
    var after: [CellAddress: CellFormat?] = [:]
    for range in ranges {
      for address in range.allAddresses() where after[address] == nil {
        var cell = sheet.cell(at: address)
        let oldFormat = cell.format ?? CellFormat()
        var format = oldFormat
        mutate(address, &format)
        guard format != oldFormat else { continue }
        let stored: CellFormat? = format.isDefault ? nil : format
        before[address] = cell.format
        after[address] = stored
        cell.format = stored
        sheet.setCell(cell, at: address)
      }
    }
    guard !after.isEmpty else { return }
    setActiveSheetPreservingFormulas(sheet)
    notifyGridRefresh()
    registerFormatsUndo(before: before, after: after)
    if let actionName {
      undoManager?.setActionName(actionName)
    } else if after.count > 2_000 {
      undoManager?.setActionName("Format Cells")
    }
  }

  /// One undo step that puts the formats in `before` back, and redo that puts `after` back.
  private func registerFormatsUndo(
    before: [CellAddress: CellFormat?], after: [CellAddress: CellFormat?]
  ) {
    let sheetID = activeSheet.id
    undoManager?.registerUndo(withTarget: self) { target in
      target.setFormats(before, sheetID: sheetID)
      target.registerFormatsUndo(before: after, after: before)
    }
  }

  /// Sets formats on the sheet with this id, in one pass.
  private func setFormats(_ formats: [CellAddress: CellFormat?], sheetID: UUID) {
    guard let index = workbook.sheets.firstIndex(where: { $0.id == sheetID }) else { return }
    if index != workbook.activeSheetIndex { selectSheet(at: index) }
    var sheet = activeSheet
    for (address, format) in formats {
      var cell = sheet.cell(at: address)
      cell.format = format
      sheet.setCell(cell, at: address)
    }
    setActiveSheetPreservingFormulas(sheet)
    notifyGridRefresh()
  }

  private func applyFormatMutation(at address: CellAddress, mutate: (inout CellFormat) -> Void) {
    applyFormat(to: CellRange(start: address, end: address), mutate: mutate)
  }

  private func clamp(_ address: CellAddress) -> CellAddress {
    let sheet = activeSheet
    return CellAddress(
      row: max(0, min(sheet.effectiveRowCount - 1, address.row)),
      col: max(0, min(sheet.effectiveColumnCount - 1, address.col))
    )
  }

  func clearSelection() {
    commitEditIfNeeded()
    for range in selectionRanges {
      clearRange(range, actionName: "Clear")
    }
    syncEditTextFromSelection()
  }

  // MARK: - Structure

  /// Rows a row insert will add. A whole-column selection does not count every sheet row.
  var rowInsertCount: Int {
    guard selectionAxis != .column else { return 1 }
    return structureSelectionBounds(.row).count
  }

  /// Columns a column insert will add. A whole-row selection does not count every sheet column.
  var columnInsertCount: Int {
    guard selectionAxis != .row else { return 1 }
    return structureSelectionBounds(.column).count
  }

  var insertRowAboveTitle: String {
    Self.structureInsertTitle(
      count: rowInsertCount, singular: "Row", plural: "Rows", placement: "Above")
  }

  var insertRowBelowTitle: String {
    Self.structureInsertTitle(
      count: rowInsertCount, singular: "Row", plural: "Rows", placement: "Below")
  }

  var insertColumnLeftTitle: String {
    Self.structureInsertTitle(
      count: columnInsertCount, singular: "Column", plural: "Columns", placement: "Left")
  }

  var insertColumnRightTitle: String {
    Self.structureInsertTitle(
      count: columnInsertCount, singular: "Column", plural: "Columns", placement: "Right")
  }

  static func structureInsertTitle(count: Int, singular: String, plural: String, placement: String)
    -> String
  {
    if count <= 1 {
      return "Insert \(singular) \(placement)"
    }
    return "Insert \(count) \(plural) \(placement)"
  }

  func insertRowsAbove(count: Int? = nil) {
    let bounds = structureSelectionBounds(.row)
    insertRows(at: bounds.min, count: resolvedInsertCount(count, fallback: rowInsertCount))
  }

  func insertRowsBelow(count: Int? = nil) {
    let bounds = structureSelectionBounds(.row)
    insertRows(at: bounds.max + 1, count: resolvedInsertCount(count, fallback: rowInsertCount))
  }

  func insertColumnsLeft(count: Int? = nil) {
    let bounds = structureSelectionBounds(.column)
    insertColumns(at: bounds.min, count: resolvedInsertCount(count, fallback: columnInsertCount))
  }

  func insertColumnsRight(count: Int? = nil) {
    let bounds = structureSelectionBounds(.column)
    let insertCount = resolvedInsertCount(count, fallback: columnInsertCount)
    let insertAt = bounds.max + 1
    let axis = selectionAxis
    insertColumns(at: insertAt, count: insertCount)
    let newEndCol = insertAt + insertCount - 1
    if axis == .column {
      selectColumns(from: insertAt, to: newEndCol)
    } else {
      let rows = structureSelectionBounds(.row)
      selectRange(
        from: CellAddress(row: rows.min, col: insertAt),
        to: CellAddress(row: rows.max, col: newEndCol)
      )
    }
    scrollRequestToken &+= 1
  }

  private func resolvedInsertCount(_ explicit: Int?, fallback: Int) -> Int {
    max(1, explicit ?? fallback)
  }

  private enum StructureInsertAxis {
    case row
    case column
  }

  /// Distinct selected indexes on one axis, plus the outer edges of that selection.
  /// A contiguous block's count is its span. Gaps in a multi-range selection are not counted.
  private func structureSelectionBounds(_ axis: StructureInsertAxis) -> (
    min: Int, max: Int, count: Int
  ) {
    let ranges = selectionRanges.isEmpty ? [selectionRange] : selectionRanges
    var seen = Set<Int>()
    var minIndex = Int.max
    var maxIndex = Int.min
    for range in ranges {
      let n = range.normalized
      let lower = axis == .row ? n.minRow : n.minCol
      let upper = axis == .row ? n.maxRow : n.maxCol
      guard upper >= lower else { continue }
      minIndex = min(minIndex, lower)
      maxIndex = max(maxIndex, upper)
      for index in lower...upper {
        seen.insert(index)
      }
    }
    guard !seen.isEmpty else { return (0, 0, 1) }
    return (minIndex, maxIndex, seen.count)
  }

  /// Selected indexes on one axis, collapsed into contiguous runs. Gaps stay.
  private func selectedStructureRuns(_ axis: StructureInsertAxis) -> [IndexRun] {
    let ranges = selectionRanges.isEmpty ? [selectionRange] : selectionRanges
    if ranges.count == 1 {
      let n = ranges[0].normalized
      let lower = axis == .row ? n.minRow : n.minCol
      let upper = axis == .row ? n.maxRow : n.maxCol
      guard upper >= lower else { return [] }
      return [IndexRun(start: lower, count: upper - lower + 1)]
    }
    var seen = Set<Int>()
    for range in ranges {
      let n = range.normalized
      let lower = axis == .row ? n.minRow : n.minCol
      let upper = axis == .row ? n.maxRow : n.maxCol
      guard upper >= lower else { continue }
      for index in lower...upper {
        seen.insert(index)
      }
    }
    let sorted = seen.sorted()
    guard let first = sorted.first else { return [] }
    var runs: [IndexRun] = []
    var start = first
    var previous = first
    for index in sorted.dropFirst() {
      if index == previous + 1 {
        previous = index
      } else {
        runs.append(IndexRun(start: start, count: previous - start + 1))
        start = index
        previous = index
      }
    }
    runs.append(IndexRun(start: start, count: previous - start + 1))
    return runs
  }

  private struct IndexRun {
    var start: Int
    var count: Int
  }

  func deleteSelectedRows() {
    // A whole-column selection is not a row delete. The menu hides this action.
    if selectionAxis == .column {
      deleteRows(at: selectionAnchor.row, count: 1)
      return
    }
    let runs = selectedStructureRuns(.row)
    guard let first = runs.first else { return }
    if runs.count == 1 {
      deleteRows(at: first.start, count: first.count)
      return
    }
    // Higher rows first so earlier indexes stay put. One undo for the set.
    undoManager?.beginUndoGrouping()
    for run in runs.reversed() {
      deleteRows(at: run.start, count: run.count)
    }
    undoManager?.endUndoGrouping()
    undoManager?.setActionName("Delete Rows")
  }

  func deleteSelectedColumns() {
    let range = selectionRange.normalized
    let sheet = activeSheet
    let spansFullHeight = range.minRow == 0 && range.maxRow >= sheet.effectiveRowCount - 1
    if spansFullHeight {
      deleteColumns(at: range.minCol, count: range.maxCol - range.minCol + 1)
    } else {
      deleteColumns(at: selectionAnchor.col, count: 1)
    }
  }

  /// Menu title for freezing every row through the bottom of the selection.
  var freezeRowsTitle: String {
    "Freeze up to row \(freezeThroughRow + 1)"
  }

  /// Menu title for freezing every column through the right edge of the selection.
  var freezeColumnsTitle: String {
    "Freeze up to column \(CellAddress(row: 0, col: freezeThroughColumn).columnLabel)"
  }

  /// Bottom selected row. A column or whole-sheet selection does not choose a row,
  /// so the anchor row is the line (the sheet span is not a row the user picked).
  private var freezeThroughRow: Int {
    switch selectionAxis {
    case .column, .sheet:
      return selectionAnchor.row
    case .row, .cells:
      return structureSelectionBounds(.row).max
    }
  }

  /// Rightmost selected column. A row or whole-sheet selection does not choose a column,
  /// so the anchor column is the line.
  private var freezeThroughColumn: Int {
    switch selectionAxis {
    case .row, .sheet:
      return selectionAnchor.col
    case .column, .cells:
      return structureSelectionBounds(.column).max
    }
  }

  @discardableResult
  func freezePanesAtSelection() -> Bool {
    commitEditIfNeeded()
    // Freeze the selected row/column and everything above/to the left (inclusive).
    let rows = selectionAnchor.row + 1
    let cols = selectionAnchor.col + 1
    guard rows > 0 || cols > 0 else { return false }
    return applyFreeze(rows: rows, cols: cols)
  }

  @discardableResult
  func freezeRowsAtSelection() -> Bool {
    commitEditIfNeeded()
    let rows = freezeThroughRow + 1
    guard rows > 0 else { return false }
    return applyFreeze(rows: rows, cols: activeSheet.frozenColumns)
  }

  @discardableResult
  func freezeColumnsAtSelection() -> Bool {
    commitEditIfNeeded()
    let cols = freezeThroughColumn + 1
    guard cols > 0 else { return false }
    return applyFreeze(rows: activeSheet.frozenRows, cols: cols)
  }

  func unfreezePanes() {
    commitEditIfNeeded()
    guard activeSheet.frozenRows > 0 || activeSheet.frozenColumns > 0 else { return }
    applyFreeze(rows: 0, cols: 0)
  }

  @discardableResult
  private func applyFreeze(rows: Int, cols: Int) -> Bool {
    var updatedWorkbook = workbook
    var sheet = updatedWorkbook.activeSheet
    let oldFrozenRows = sheet.frozenRows
    let oldFrozenColumns = sheet.frozenColumns
    sheet.frozenRows = rows
    sheet.frozenColumns = cols
    updatedWorkbook.activeSheet = sheet
    suspendFormulaRebuild = true
    workbook = updatedWorkbook
    suspendFormulaRebuild = false
    notifyGridRefresh()
    registerFreezeUndo(
      oldRows: oldFrozenRows,
      oldCols: oldFrozenColumns,
      newRows: sheet.frozenRows,
      newCols: sheet.frozenColumns
    )
    return true
  }

  /// Fills from the source to `end`. Numbers, dates, numbered text and month or day names
  /// continue as a series unless `copyOnly` (Option held while dragging the fill handle).
  func fillSelection(from source: CellRange? = nil, to end: CellAddress, copyOnly: Bool = false) {
    commitEditIfNeeded()
    let sourceRange = (source ?? selectionRange).normalized
    let fillRange = CellRange(
      start: CellAddress(row: sourceRange.minRow, col: sourceRange.minCol),
      end: clamp(end)
    ).normalized

    let srcRowCount = InputBounds.span(from: sourceRange.minRow, through: sourceRange.maxRow)
    let srcColCount = InputBounds.span(from: sourceRange.minCol, through: sourceRange.maxCol)
    let fillRows = InputBounds.span(from: fillRange.minRow, through: fillRange.maxRow)
    let fillCols = InputBounds.span(from: fillRange.minCol, through: fillRange.maxCol)
    guard srcRowCount > 0, srcColCount > 0 else { return }
    guard InputBounds.materializedCount(rows: fillRows, cols: fillCols) != nil else { return }

    let sourceLabel = CellRange(
      start: CellAddress(row: sourceRange.minRow, col: sourceRange.minCol),
      end: CellAddress(row: sourceRange.maxRow, col: sourceRange.maxCol)
    ).a1Label
    let snapshot = workbook
    guard
      applyCommand(
        "edit.fill",
        [
          "sheet": activeSheet.name,
          "source": sourceLabel,
          "end": clamp(end).a1,
          "series": copyOnly ? "0" : "1",
        ],
        incremental: true
      )
    else { return }
    registerWorkbookStructureUndo(before: snapshot, action: "Fill")

    selectionEnd = CellAddress(row: fillRange.maxRow, col: fillRange.maxCol)
    setPrimaryRange(from: selectionAnchor, to: selectionEnd)
    syncEditTextFromSelection()
  }

  private func insertRows(at index: Int, count: Int) {
    mutateStructure(
      "sheet.insertRows",
      index: index,
      count: count,
      action: "Insert Rows",
      clampAfter: false
    )
  }

  private func deleteRows(at index: Int, count: Int) {
    mutateStructure(
      "sheet.deleteRows",
      index: index,
      count: count,
      action: "Delete Rows",
      clampAfter: true
    )
  }

  private func insertColumns(at index: Int, count: Int) {
    mutateStructure(
      "sheet.insertColumns",
      index: index,
      count: count,
      action: "Insert Columns",
      clampAfter: false
    )
  }

  private func deleteColumns(at index: Int, count: Int) {
    mutateStructure(
      "sheet.deleteColumns",
      index: index,
      count: count,
      action: "Delete Columns",
      clampAfter: true
    )
  }

  private func mutateStructure(
    _ id: String,
    index: Int,
    count: Int,
    action: String,
    clampAfter: Bool
  ) {
    let count = InputBounds.cappedCount(count)
    guard count > 0 else { return }
    commitEditIfNeeded()
    let snapshot = workbook
    guard
      applyCommand(
        id,
        [
          "sheet": activeSheet.name,
          "index": String(index),
          "count": String(count),
        ],
        incremental: false
      )
    else { return }
    registerWorkbookStructureUndo(before: snapshot, action: action)
    if clampAfter {
      clampSelectionToSheet()
    }
  }

  func registerWorkbookStructureUndo(before: Workbook, action: String) {
    let after = workbook
    undoManager?.registerUndo(withTarget: self) { target in
      // A remembered sort order no longer matches the rows once they change under it.
      target.filterSortMemory = nil
      target.workbook = before
      target.clampSelectionToSheet()
      target.undoManager?.registerUndo(withTarget: target) { inner in
        inner.filterSortMemory = nil
        inner.workbook = after
        inner.clampSelectionToSheet()
      }
    }
    undoManager?.setActionName(action)
  }

  func clampSelectionToSheet() {
    selectionRanges = selectionRanges.map { range in
      CellRange(start: clamp(range.start), end: clamp(range.end))
    }
    if selectionRanges.isEmpty {
      replaceSelection(with: .singleOrigin)
    } else {
      let active = selectionRanges[selectionRanges.count - 1]
      selectionAnchor = active.start
      selectionEnd = active.end
      noteSelectionChanged()
    }
    syncEditTextFromSelection()
  }

  private func registerFreezeUndo(oldRows: Int, oldCols: Int, newRows: Int, newCols: Int) {
    undoManager?.registerUndo(withTarget: self) { target in
      var workbook = target.workbook
      var sheet = workbook.activeSheet
      sheet.frozenRows = oldRows
      sheet.frozenColumns = oldCols
      workbook.activeSheet = sheet
      target.workbook = workbook
      target.notifyGridRefresh()
      target.undoManager?.registerUndo(withTarget: target) { inner in
        var workbook = inner.workbook
        var sheet = workbook.activeSheet
        sheet.frozenRows = newRows
        sheet.frozenColumns = newCols
        workbook.activeSheet = sheet
        inner.workbook = workbook
        inner.notifyGridRefresh()
      }
    }
    undoManager?.setActionName("Freeze Panes")
  }

  /// Replaces formulas in the selection with their evaluated display values.
  func convertSelectionToValues() {
    commitEditIfNeeded()
    undoManager?.beginUndoGrouping()
    var changed = false
    for range in selectionRanges {
      let n = range.normalized
      for row in n.minRow...n.maxRow {
        for col in n.minCol...n.maxCol {
          let address = CellAddress(row: row, col: col)
          let raw = activeSheet.cell(at: address).raw
          guard FormulaSyntax.isFormula(raw) else { continue }
          let literal = literalString(from: displayValue(at: address))
          setCellValue(literal, at: address)
          changed = true
        }
      }
    }
    undoManager?.endUndoGrouping()
    if changed {
      undoManager?.setActionName("Convert to Values")
    }
    syncEditTextFromSelection()
  }

  /// Defines a workbook named range covering the primary selection.
  func defineNamedRange(name: String) {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    let upper = trimmed.uppercased()
    guard upper.first?.isLetter == true,
      upper.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" })
    else { return }

    let snapshot = workbook
    var wb = workbook
    wb.setNamedRange(
      NamedRange(name: trimmed, sheetName: activeSheet.name, range: selectionRange)
    )
    workbook = wb

    undoManager?.registerUndo(withTarget: self) { target in
      target.workbook = snapshot
      target.undoManager?.registerUndo(withTarget: target) { inner in
        inner.workbook = wb
      }
    }
    undoManager?.setActionName("Define Named Range")
  }

  private func literalString(from value: CellValue) -> String {
    switch value {
    case .blank:
      return ""
    case .error(let error):
      return error.displayCode
    case .bool(let flag):
      return flag ? "TRUE" : "FALSE"
    case .number, .string:
      return value.displayString
    }
  }

  // MARK: - Clipboard

  private struct SelectionCopy {
    var text: String
    var conditionalFormats: SpreadsheetClipboard.ConditionalFormatClipboardPayload?
  }

  /// Copies cell text plus conditional-format rules that cover the selection.
  @discardableResult
  func copySelectionToPasteboard() -> Bool {
    guard let copy = makeSelectionCopy() else { return false }
    SpreadsheetClipboard.writeText(copy.text, conditionalFormats: copy.conditionalFormats)
    return true
  }

  private func makeSelectionCopy() -> SelectionCopy? {
    guard selectionRanges.contains(where: { rangeHasContent($0) || rangeHasConditionalFormat($0) })
    else {
      return nil
    }
    if selectionRanges.count == 1 {
      let range = selectionRange
      let region: SpreadsheetClipboard.CopyRegion
      if rangeHasContent(range) {
        region = SpreadsheetClipboard.copyRegion(
          from: activeSheet, range: range, skippingRow: isRowHiddenByFilter)
      } else if let bounds = ConditionalFormatPaste.coveredBounds(
        on: activeSheet, intersecting: range)
      {
        region = SpreadsheetClipboard.copyRegion(
          from: activeSheet, range: bounds, skippingRow: isRowHiddenByFilter)
      } else {
        return nil
      }
      let formats = region.bounds.flatMap {
        ConditionalFormatPaste.capture(from: activeSheet, bounds: $0)
      }
      return SelectionCopy(text: region.text, conditionalFormats: formats)
    }
    let blocks = selectionRanges.map {
      SpreadsheetClipboard.copyText(
        from: activeSheet, range: $0, skippingRow: isRowHiddenByFilter)
    }
    return SelectionCopy(text: blocks.joined(separator: "\n\n"), conditionalFormats: nil)
  }

  /// Copies cell raw values (including formulas) and records origin for relative paste.
  func copyFormulas() {
    guard selectionRanges.contains(where: { rangeHasContent($0) || rangeHasConditionalFormat($0) })
    else { return }
    let range = selectionRange.normalized
    let bounds = CellRange(
      start: CellAddress(row: range.minRow, col: range.minCol),
      end: CellAddress(row: range.maxRow, col: range.maxCol)
    )
    // Rows the filter hides are not copied, as in Excel.
    let grid = SpreadsheetClipboard.grid(
      from: activeSheet, range: bounds, skippingRow: isRowHiddenByFilter)
    let tsv = SpreadsheetClipboard.copyText(
      from: activeSheet, range: bounds, skippingRow: isRowHiddenByFilter)
    let formats = ConditionalFormatPaste.capture(from: activeSheet, bounds: bounds)
    SpreadsheetClipboard.writeFormulaGrid(
      .init(originRow: range.minRow, originCol: range.minCol, grid: grid),
      tsv: tsv,
      conditionalFormats: formats
    )
  }

  private func selectionRangeHasContent() -> Bool {
    selectionRanges.contains { rangeHasContent($0) }
  }

  private func rangeHasContent(_ range: CellRange) -> Bool {
    let n = range.normalized
    for (address, cell) in activeSheet.cells {
      guard !cell.raw.isEmpty else { continue }
      if address.row >= n.minRow, address.row <= n.maxRow,
        address.col >= n.minCol, address.col <= n.maxCol
      {
        return true
      }
    }
    return false
  }

  private func rangeHasConditionalFormat(_ range: CellRange) -> Bool {
    activeSheet.conditionalFormats.contains {
      ConditionalFormatPaste.intersection($0.range, range) != nil
    }
  }

  func cutSelection() {
    guard let copy = makeSelectionCopy() else { return }
    for range in selectionRanges {
      clearRange(range, actionName: "Cut")
    }
    SpreadsheetClipboard.writeText(copy.text, conditionalFormats: copy.conditionalFormats)
  }

  func pasteFromPasteboard() {
    if pasteImageFromPasteboard() {
      syncEditTextFromSelection()
      return
    }
    guard let text = NSPasteboard.general.string(forType: .string) else { return }
    let formats = SpreadsheetClipboard.readConditionalFormats()
    let grid = SpreadsheetClipboard.parseGrid(text)
    if grid.isEmpty {
      setCellValue(text, at: selectionAnchor)
      pasteCopiedConditionalFormats(formats, at: selectionAnchor)
    } else {
      pasteGrid(grid, at: selectionAnchor, adjustFormulas: false, conditionalFormats: formats)
    }
    syncEditTextFromSelection()
  }

  /// Pastes formulas with relative references adjusted from the copy origin.
  func pasteFormulasFromPasteboard() {
    let formats = SpreadsheetClipboard.readConditionalFormats()
    if let payload = SpreadsheetClipboard.readFormulaGrid() {
      let origin = CellAddress(row: payload.originRow, col: payload.originCol)
      pasteGrid(
        payload.grid,
        at: selectionAnchor,
        adjustFormulas: true,
        sourceOrigin: origin,
        actionName: "Paste Formulas",
        conditionalFormats: formats
      )
      syncEditTextFromSelection()
      return
    }

    guard let text = NSPasteboard.general.string(forType: .string) else { return }
    let grid = SpreadsheetClipboard.parseGrid(text)
    if grid.isEmpty {
      let adjusted = FormulaRewriter.adjust(text, rowDelta: 0, colDelta: 0)
      setCellValue(adjusted, at: selectionAnchor)
      pasteCopiedConditionalFormats(formats, at: selectionAnchor, actionName: "Paste Formulas")
    } else {
      // External paste: treat clipboard top-left as if it came from the destination (no shift),
      // but still rewrite if user copied via ⌘C then pastes with ⌘⇧V from same sheet — without
      // origin we paste verbatim like normal paste.
      pasteGrid(
        grid,
        at: selectionAnchor,
        adjustFormulas: false,
        actionName: "Paste Formulas",
        conditionalFormats: formats
      )
    }
    syncEditTextFromSelection()
  }

  private func pasteGrid(
    _ grid: [[String]],
    at origin: CellAddress,
    adjustFormulas: Bool,
    sourceOrigin: CellAddress? = nil,
    actionName: String = "Paste",
    conditionalFormats: SpreadsheetClipboard.ConditionalFormatClipboardPayload? = nil
  ) {
    let rowDelta = adjustFormulas ? origin.row - (sourceOrigin?.row ?? origin.row) : 0
    let colDelta = adjustFormulas ? origin.col - (sourceOrigin?.col ?? origin.col) : 0
    let pasteRows = grid.count
    let pasteCols = grid.map(\.count).max() ?? 0
    guard InputBounds.materializedCount(rows: pasteRows, cols: pasteCols) != nil else { return }

    var clipped: [[String]] = []
    for (rowOffset, row) in grid.enumerated() {
      let rowIndex = origin.row + rowOffset
      if rowIndex >= activeSheet.effectiveRowCount { break }
      var fields: [String] = []
      for (colOffset, value) in row.enumerated() {
        let colIndex = origin.col + colOffset
        if colIndex >= activeSheet.effectiveColumnCount { break }
        fields.append(value)
      }
      clipped.append(fields)
    }
    guard clipped.contains(where: { !$0.isEmpty }) else { return }
    let text = clipped.map { $0.joined(separator: "\t") }.joined(separator: "\n")
    let snapshot = workbook
    guard
      applyCommand(
        "edit.paste",
        [
          "sheet": activeSheet.name,
          "anchor": origin.a1,
          "text": text,
          "rowDelta": String(rowDelta),
          "colDelta": String(colDelta),
        ],
        incremental: true
      )
    else { return }
    pasteCopiedConditionalFormats(
      conditionalFormats,
      at: origin,
      actionName: actionName,
      recordUndo: false
    )
    registerWorkbookStructureUndo(before: snapshot, action: actionName)

    if let lastRow = grid.indices.last, let lastCol = grid[lastRow].indices.last {
      selectionEnd = CellAddress(row: origin.row + lastRow, col: origin.col + lastCol)
      setPrimaryRange(from: selectionAnchor, to: selectionEnd)
    }
  }

  /// Clears the cells in `range` on rows the filter shows. Hidden rows keep their values, as in Excel.
  private func clearRange(_ range: CellRange, actionName: String = "Clear") {
    undoManager?.beginUndoGrouping()
    let addresses = activeSheet.cells.keys.filter {
      range.contains($0) && !isRowHiddenByFilter($0.row)
    }
    for address in addresses {
      let oldValue = activeSheet.cell(at: address).raw
      guard !oldValue.isEmpty else { continue }
      setCellValue("", at: address)
    }
    undoManager?.endUndoGrouping()
    undoManager?.setActionName(actionName)
  }

  // MARK: - Undo

  private func registerUndo(address: CellAddress, oldValue: String, newValue: String) {
    undoManager?.registerUndo(withTarget: self) { target in
      target.setCellValue(oldValue, at: address, skipUndo: true)
      target.undoManager?.registerUndo(withTarget: target) { inner in
        inner.setCellValue(newValue, at: address, skipUndo: true)
      }
    }
    undoManager?.setActionName("Edit Cell")
  }

  func undo() {
    undoManager?.undo()
  }

  func redo() {
    undoManager?.redo()
  }

  private func setCellValue(_ value: String, at address: CellAddress, skipUndo: Bool) {
    if skipUndo {
      guard writeCell(value, at: address) else { return }
      if address == selectionAnchor {
        syncEditTextFromSelection()
      }
    } else {
      setCellValue(value, at: address)
    }
  }
}
