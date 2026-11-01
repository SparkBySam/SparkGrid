import AppKit
import Foundation
import SparkGridCore

enum MergeAxis: Sendable {
  /// One rectangle covering the whole selection.
  case all
  /// Merge each row across selected columns (Excel “Merge Across”).
  case horizontal
  /// Merge each column down selected rows.
  case vertical
}

extension SpreadsheetViewModel {
  enum MergeOutcome: Equatable {
    case cancelled
    case merged(count: Int)
    case nothingToMerge
  }

  /// Merges the selection. Warns when other cells have values that will be cleared
  /// (keeps the top-left cell of each merge, Excel-style).
  @discardableResult
  func mergeSelection(axis: MergeAxis = .all, confirmDiscard: Bool = true) -> MergeOutcome {
    commitEditIfNeeded()
    let range = selectionRange
    let n = range.normalized
    guard n.minRow != n.maxRow || n.minCol != n.maxCol else { return .nothingToMerge }

    let planned = plannedMerges(for: range, axis: axis)
    guard !planned.isEmpty else { return .nothingToMerge }

    if confirmDiscard, let warning = mergeWarningText(for: planned) {
      let alert = NSAlert()
      alert.messageText = "Merge Cells?"
      alert.informativeText = warning
      alert.alertStyle = .warning
      alert.addButton(withTitle: "Merge")
      alert.addButton(withTitle: "Cancel")
      guard alert.runModal() == .alertFirstButtonReturn else { return .cancelled }
    }

    var sheet = activeSheet
    let beforeMerges = sheet.mergedRanges
    let beforeCells = sheet.cells

    for plan in planned {
      let pn = plan.normalized
      sheet.mergedRanges.removeAll { merge in
        let m = merge.normalized
        return pn.minRow <= m.maxRow && pn.maxRow >= m.minRow
          && pn.minCol <= m.maxCol && pn.maxCol >= m.minCol
      }
    }
    sheet.mergedRanges.append(contentsOf: planned)

    for plan in planned {
      let pn = plan.normalized
      let topLeft = CellAddress(row: pn.minRow, col: pn.minCol)
      for row in pn.minRow...pn.maxRow {
        for col in pn.minCol...pn.maxCol {
          let address = CellAddress(row: row, col: col)
          guard address != topLeft else { continue }
          var cell = sheet.cell(at: address)
          if !cell.raw.isEmpty {
            cell.raw = ""
            sheet.setCell(cell, at: address)
          }
        }
      }
    }

    applyMergeMutation(
      sheet: sheet,
      undoMerges: beforeMerges,
      undoCells: beforeCells,
      actionName: mergeActionName(axis)
    )
    selectRange(
      from: CellAddress(row: n.minRow, col: n.minCol),
      to: CellAddress(row: n.maxRow, col: n.maxCol)
    )
    return .merged(count: planned.count)
  }

  func unmergeSelection() {
    commitEditIfNeeded()
    let range = selectionRange.normalized
    var sheet = activeSheet
    let before = sheet.mergedRanges
    sheet.mergedRanges.removeAll { merge in
      let m = merge.normalized
      return range.minRow <= m.maxRow && range.maxRow >= m.minRow
        && range.minCol <= m.maxCol && range.maxCol >= m.minCol
    }
    guard sheet.mergedRanges != before else { return }
    applyMergedRanges(sheet.mergedRanges, undoBefore: before, actionName: "Unmerge Cells")
  }

  var canMergeSelection: Bool {
    let n = selectionRange.normalized
    return n.minRow != n.maxRow || n.minCol != n.maxCol
  }

  var canMergeHorizontally: Bool {
    let n = selectionRange.normalized
    return n.minCol != n.maxCol
  }

  var canMergeVertically: Bool {
    let n = selectionRange.normalized
    return n.minRow != n.maxRow
  }

  var canUnmergeSelection: Bool {
    let range = selectionRange.normalized
    return activeSheet.mergedRanges.contains { merge in
      let m = merge.normalized
      return range.minRow <= m.maxRow && range.maxRow >= m.minRow
        && range.minCol <= m.maxCol && range.maxCol >= m.minCol
    }
  }

  func insertChart(kind: SheetChart.Kind) {
    beginInsertChart(preferredKind: kind)
  }

  /// The current selection when it covers more than one cell.
  /// A single cell is not a chart range, and nearby data is left alone.
  var chartSelectionRange: CellRange? {
    let range = selectionRange
    guard !range.isSingleCell else { return nil }
    return range
  }

  func beginInsertChart(preferredKind: SheetChart.Kind = .bar) {
    commitEditIfNeeded()
    editingChartID = nil
    pendingChartKind = preferredKind
    isInsertChartPresented = true
  }

  /// Opens the chart sheet on an existing chart so type, range, and series can change.
  func beginEditChart(id: UUID) {
    commitEditIfNeeded()
    guard activeSheet.charts.contains(where: { $0.id == id }) else { return }
    editingChartID = id
    selectChart(id: id)
    isInsertChartPresented = true
  }

  func selectChart(id: UUID?, scroll: Bool = true) {
    if id != nil { selectedImageID = nil }
    let changed = selectedChartID != id
    selectedChartID = id
    if scroll, let id {
      requestScrollToChart(id)
    }
    if changed {
      notifyGridRefresh()
    }
  }

  func chart(with id: UUID) -> SheetChart? {
    activeSheet.charts.first { $0.id == id }
  }

  /// Live frame while dragging. No undo until `commitChartFrame`.
  /// `frameIsCustom` stays as it was when the drag returns to `start`.
  func setChartFrame(
    id: UUID,
    anchorRow: Int,
    anchorCol: Int,
    rowSpan: Int,
    colSpan: Int,
    originXOffset: CGFloat = 0,
    originYOffset: CGFloat = 0,
    endXOffset: CGFloat = 0,
    endYOffset: CGFloat = 0,
    preservingCustomFrom start: SheetChart
  ) {
    guard let index = activeSheet.charts.firstIndex(where: { $0.id == id }) else { return }
    let row = max(0, anchorRow)
    let col = max(0, anchorCol)
    let originX = SheetChart.clampedPlacementOffset(originXOffset)
    let originY = SheetChart.clampedPlacementOffset(originYOffset)
    let endX = SheetChart.clampedPlacementOffset(endXOffset)
    let endY = SheetChart.clampedPlacementOffset(endYOffset)
    let snapped = originX == 0 && originY == 0 && endX == 0 && endY == 0
    let rows = max(snapped ? SheetChart.minimumSpan : 1, rowSpan)
    let cols = max(snapped ? SheetChart.minimumSpan : 1, colSpan)
    let changed =
      row != start.anchorRow || col != start.anchorCol
      || rows != start.rowSpan || cols != start.colSpan
      || originX != start.originXOffset || originY != start.originYOffset
      || endX != start.endXOffset || endY != start.endYOffset
    var sheet = activeSheet
    guard
      sheet.charts[index].anchorRow != row
        || sheet.charts[index].anchorCol != col
        || sheet.charts[index].rowSpan != rows
        || sheet.charts[index].colSpan != cols
        || sheet.charts[index].originXOffset != originX
        || sheet.charts[index].originYOffset != originY
        || sheet.charts[index].endXOffset != endX
        || sheet.charts[index].endYOffset != endY
        || sheet.charts[index].frameIsCustom != (start.frameIsCustom || changed)
    else { return }
    sheet.charts[index].anchorRow = row
    sheet.charts[index].anchorCol = col
    sheet.charts[index].rowSpan = rows
    sheet.charts[index].colSpan = cols
    sheet.charts[index].originXOffset = originX
    sheet.charts[index].originYOffset = originY
    sheet.charts[index].endXOffset = endX
    sheet.charts[index].endYOffset = endY
    sheet.charts[index].frameIsCustom = start.frameIsCustom || changed
    setActiveSheetPreservingFormulas(sheet)
    notifyGridRefresh()
  }

  func commitChartFrame(
    id: UUID,
    before: SheetChart,
    actionName: String = "Move Chart"
  ) {
    guard let after = chart(with: id) else { return }
    guard
      before.anchorRow != after.anchorRow
        || before.anchorCol != after.anchorCol
        || before.rowSpan != after.rowSpan
        || before.colSpan != after.colSpan
        || before.originXOffset != after.originXOffset
        || before.originYOffset != after.originYOffset
        || before.endXOffset != after.endXOffset
        || before.endYOffset != after.endYOffset
        || before.frameIsCustom != after.frameIsCustom
    else { return }
    let current = activeSheet.charts
    applyCharts(current, undoBefore: replacingChart(before, in: current), actionName: actionName)
  }

  /// Writes title, colors, legend, axis titles, or gridlines. One undo step.
  func updateChartContent(
    id: UUID,
    actionName: String,
    mutate: (inout SheetChart) -> Void
  ) {
    guard let index = activeSheet.charts.firstIndex(where: { $0.id == id }) else { return }
    var charts = activeSheet.charts
    let before = charts
    mutate(&charts[index])
    guard charts != before else { return }
    applyCharts(charts, undoBefore: before, actionName: actionName)
  }

  func requestScrollToChart(_ id: UUID) {
    chartScrollID = id
    chartScrollToken &+= 1
  }

  /// Inserts `chart` when its data range covers more than one cell.
  /// A single-cell range is refused so an empty selection cannot become a chart.
  @discardableResult
  func insertChart(_ chart: SheetChart) -> Bool {
    commitEditIfNeeded()
    guard !chart.dataRange.isSingleCell else { return false }
    var sheet = activeSheet
    let before = sheet.charts
    var next = chart
    if next.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      next.title = "\(next.kind.title) Chart"
    }
    sheet.charts.append(next)
    applyCharts(sheet.charts, undoBefore: before, actionName: "Insert Chart")
    selectedChartID = next.id
    requestScrollToChart(next.id)
    isInsertChartPresented = false
    editingChartID = nil
    return true
  }

  /// Replaces an existing chart. A single-cell range is refused and the chart stays as it was.
  /// The on-sheet anchor is whatever `chart` carries, so callers can keep the frame put.
  @discardableResult
  func updateChart(_ chart: SheetChart) -> Bool {
    commitEditIfNeeded()
    guard !chart.dataRange.isSingleCell else { return false }
    var sheet = activeSheet
    guard let index = sheet.charts.firstIndex(where: { $0.id == chart.id }) else { return false }
    let before = sheet.charts
    var next = chart
    sheet.charts[index] = next
    applyCharts(sheet.charts, undoBefore: before, actionName: "Edit Chart")
    selectedChartID = next.id
    isInsertChartPresented = false
    editingChartID = nil
    return true
  }

  func removeChart(id: UUID) {
    var sheet = activeSheet
    let before = sheet.charts
    sheet.charts.removeAll { $0.id == id }
    guard sheet.charts != before else { return }
    if selectedChartID == id { selectedChartID = nil }
    if editingChartID == id {
      editingChartID = nil
      isInsertChartPresented = false
    }
    applyCharts(sheet.charts, undoBefore: before, actionName: "Delete Chart")
  }

  // MARK: - Private

  private func plannedMerges(for range: CellRange, axis: MergeAxis) -> [CellRange] {
    let n = range.normalized
    switch axis {
    case .all:
      return [
        CellRange(
          start: CellAddress(row: n.minRow, col: n.minCol),
          end: CellAddress(row: n.maxRow, col: n.maxCol)
        )
      ]
    case .horizontal:
      guard n.minCol != n.maxCol else { return [] }
      return (n.minRow...n.maxRow).map { row in
        CellRange(
          start: CellAddress(row: row, col: n.minCol),
          end: CellAddress(row: row, col: n.maxCol)
        )
      }
    case .vertical:
      guard n.minRow != n.maxRow else { return [] }
      return (n.minCol...n.maxCol).map { col in
        CellRange(
          start: CellAddress(row: n.minRow, col: col),
          end: CellAddress(row: n.maxRow, col: col)
        )
      }
    }
  }

  private func mergeWarningText(for merges: [CellRange]) -> String? {
    var keptLines: [String] = []
    var clearedLines: [String] = []

    for merge in merges {
      let n = merge.normalized
      let topLeft = CellAddress(row: n.minRow, col: n.minCol)
      let keptRaw = activeSheet.cell(at: topLeft).raw
      if !keptRaw.isEmpty {
        keptLines.append("• \(topLeft.a1): \(preview(keptRaw))")
      } else {
        keptLines.append("• \(topLeft.a1): (empty)")
      }
      for row in n.minRow...n.maxRow {
        for col in n.minCol...n.maxCol {
          let address = CellAddress(row: row, col: col)
          guard address != topLeft else { continue }
          let raw = activeSheet.cell(at: address).raw
          guard !raw.isEmpty else { continue }
          clearedLines.append("• \(address.a1): \(preview(raw))")
          if clearedLines.count >= 8 {
            clearedLines.append("• …")
            break
          }
        }
        if clearedLines.count >= 8 { break }
      }
    }

    guard !clearedLines.isEmpty else { return nil }
    return """
      The top-left cell is kept; other values are cleared.

      Kept:
      \(keptLines.joined(separator: "\n"))

      Cleared:
      \(clearedLines.joined(separator: "\n"))
      """
  }

  private func preview(_ raw: String) -> String {
    raw.count > 40 ? String(raw.prefix(37)) + "…" : raw
  }

  private func mergeActionName(_ axis: MergeAxis) -> String {
    switch axis {
    case .all: return "Merge Cells"
    case .horizontal: return "Merge Across"
    case .vertical: return "Merge Vertically"
    }
  }

  private func applyMergeMutation(
    sheet: Sheet,
    undoMerges: [CellRange],
    undoCells: [CellAddress: Cell],
    actionName: String
  ) {
    let afterMerges = sheet.mergedRanges
    let afterCells = sheet.cells
    setActiveSheetPreservingFormulas(sheet)
    undoManager?.registerUndo(withTarget: self) { target in
      var restored = target.activeSheet
      restored.mergedRanges = undoMerges
      restored.replaceCells(undoCells)
      target.applyMergeMutation(
        sheet: restored,
        undoMerges: afterMerges,
        undoCells: afterCells,
        actionName: actionName
      )
    }
    undoManager?.setActionName(actionName)
    notifyGridRefresh()
  }

  private func applyMergedRanges(
    _ ranges: [CellRange],
    undoBefore: [CellRange],
    actionName: String
  ) {
    var sheet = activeSheet
    sheet.mergedRanges = ranges
    setActiveSheetPreservingFormulas(sheet)
    undoManager?.registerUndo(withTarget: self) { target in
      target.applyMergedRanges(undoBefore, undoBefore: ranges, actionName: actionName)
    }
    undoManager?.setActionName(actionName)
    notifyGridRefresh()
  }

  private func replacingChart(_ chart: SheetChart, in charts: [SheetChart]) -> [SheetChart] {
    guard let index = charts.firstIndex(where: { $0.id == chart.id }) else { return charts }
    var next = charts
    next[index] = chart
    return next
  }

  private func applyCharts(
    _ charts: [SheetChart],
    undoBefore: [SheetChart],
    actionName: String
  ) {
    var sheet = activeSheet
    sheet.charts = charts
    setActiveSheetPreservingFormulas(sheet)
    undoManager?.registerUndo(withTarget: self) { target in
      target.applyCharts(undoBefore, undoBefore: charts, actionName: actionName)
    }
    undoManager?.setActionName(actionName)
    notifyGridRefresh()
  }
}
