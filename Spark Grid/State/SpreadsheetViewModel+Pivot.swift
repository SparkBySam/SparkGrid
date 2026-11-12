import Foundation
import SparkGridCore

/// Data ▸ PivotTable: a summary of a range drawn as cells on its own sheet. The settings stay
/// with that sheet, so the table can be edited and refreshed from its source.
extension SpreadsheetViewModel {
  /// The range a new pivot table would summarize: the selection, or the filled block around the
  /// active cell. It needs a header row and at least one row of data.
  var newPivotSourceRange: CellRange? {
    let range =
      selectionRange.isSingleCell ? contiguousRegion(around: selectionAnchor) : selectionRange
    guard let range else { return nil }
    let n = range.normalized
    guard n.maxRow > n.minRow, n.maxRow - n.minRow < 1_000_000 else { return nil }
    return CellRange(
      start: CellAddress(row: n.minRow, col: n.minCol),
      end: CellAddress(row: n.maxRow, col: n.maxCol))
  }

  /// The pivot table drawn under the active cell on this sheet.
  var selectedPivot: SheetPivot? {
    let pivots = activeSheet.fileExtras.sparkPivots
    guard !pivots.isEmpty else { return nil }
    let address = selectionAnchor
    return pivots.first { pivot in
      pivot.anchor == address || pivot.drawnRange?.contains(address) == true
    }
  }

  /// Pivot tables on this sheet: Spark Grid's own and ones the file brought.
  var hasPivots: Bool {
    !activeSheet.fileExtras.sparkPivots.isEmpty || !activeSheet.fileExtras.pivotTables.isEmpty
  }

  /// The source's column names, in order. Blank headers are named by position.
  func pivotFieldNames(_ pivot: SheetPivot) -> [String] {
    guard let sheet = pivotSourceSheet(pivot) else { return [] }
    let n = pivot.sourceRange.normalized
    return (n.minCol...n.maxCol).map { col in
      let text = formulaEngine.displayValue(at: CellAddress(row: n.minRow, col: col), sheet: sheet)
      let name = PivotTable.label(for: text)
      return name == "(blank)" ? "Column \(col - n.minCol + 1)" : name
    }
  }

  /// The source rows under the header.
  func pivotRecords(_ pivot: SheetPivot) -> [[CellValue]] {
    guard let sheet = pivotSourceSheet(pivot) else { return [] }
    let n = pivot.sourceRange.normalized
    guard n.maxRow > n.minRow else { return [] }
    return ((n.minRow + 1)...n.maxRow).map { row in
      (n.minCol...n.maxCol).map { col in
        formulaEngine.displayValue(at: CellAddress(row: row, col: col), sheet: sheet)
      }
    }
  }

  /// Each field's item labels, sorted, for filter choices. A grouped date field lists its groups.
  func pivotItems(
    _ pivot: SheetPivot, field: Int, group: PivotDefinition.DateGroup? = nil
  ) -> [String] {
    var starts: [String: Double] = [:]
    for record in pivotRecords(pivot) {
      let value = field < record.count ? record[field] : .blank
      if let group, case .number(let serial) = value,
        let grouped = PivotTable.dateGroup(serial: serial, by: group)
      {
        starts[grouped.label] = grouped.start
      } else {
        let label = PivotTable.label(for: value)
        if starts[label] == nil {
          if case .number(let n) = value { starts[label] = n } else { starts[label] = .nan }
        }
      }
    }
    return starts.keys.sorted { a, b in
      if a == "(blank)" { return false }
      if b == "(blank)" { return true }
      let x = starts[a] ?? .nan
      let y = starts[b] ?? .nan
      if !x.isNaN, !y.isNaN, x != y { return x < y }
      if !x.isNaN, y.isNaN { return true }
      if x.isNaN, !y.isNaN { return false }
      return a.localizedStandardCompare(b) == .orderedAscending
    }
  }

  /// True when the field's filled cells are formatted as dates, so they can be grouped.
  func pivotFieldIsDate(_ pivot: SheetPivot, field: Int) -> Bool {
    guard let sheet = pivotSourceSheet(pivot) else { return false }
    let n = pivot.sourceRange.normalized
    let col = n.minCol + field
    guard col <= n.maxCol, n.maxRow > n.minRow else { return false }
    var dates = 0
    var others = 0
    for row in (n.minRow + 1)...min(n.maxRow, n.minRow + 200) {
      let cell = sheet.cell(at: CellAddress(row: row, col: col))
      guard !cell.raw.isEmpty else { continue }
      let format = cell.format ?? CellFormat()
      let isDate =
        format.numberFormat == .date
        || format.formatCode.map { ExcelFormatCode.numberFormatKind(for: $0) == .date } == true
      if isDate { dates += 1 } else { others += 1 }
    }
    return dates > 0 && dates >= others
  }

  private func pivotSourceSheet(_ pivot: SheetPivot) -> Sheet? {
    workbook.sheets.first { $0.name.caseInsensitiveCompare(pivot.sourceSheet) == .orderedSame }
  }

  /// Makes a pivot table of the selection on a new sheet and returns it, ready for its fields.
  @discardableResult
  func createPivot() -> SheetPivot? {
    commitEditIfNeeded()
    guard let source = newPivotSourceRange else { return nil }
    let sourceSheet = activeSheet.name
    let used = Set(workbook.sheets.map { $0.name.lowercased() })
    var number = 1
    while used.contains("pivot \(number)") { number += 1 }
    let name = "Pivot \(number)"
    let before = workbook
    let beforeSelection = selectionAnchor
    // Adding a sheet records no undo of its own; the whole step is undone at once below.
    undoManager?.disableUndoRegistration()
    addSheet()
    let renamed = applyCommand(
      "sheet.rename", ["sheet": activeSheet.name, "name": name], incremental: false)
    let pivot = SheetPivot(
      name: "PivotTable\(number)", sourceSheet: sourceSheet, sourceRange: source,
      anchor: CellAddress(row: 2, col: 0), definition: PivotDefinition())
    if renamed {
      updateFileExtras(actionName: "PivotTable") { extras in
        extras.sparkPivots.append(pivot)
      }
      setCellValue("Choose fields with Data ▸ Edit PivotTable.", at: CellAddress(row: 0, col: 0))
    }
    undoManager?.enableUndoRegistration()
    guard renamed else {
      workbook = before
      return nil
    }
    registerWorkbookUndo(
      before: before, beforeSelection: beforeSelection, after: workbook,
      afterSelection: pivot.anchor, actionName: "PivotTable")
    select(pivot.anchor)
    return pivot
  }

  /// One undo step that puts the whole workbook back, and redo that puts it forward again.
  private func registerWorkbookUndo(
    before: Workbook, beforeSelection: CellAddress, after: Workbook,
    afterSelection: CellAddress, actionName: String
  ) {
    undoManager?.registerUndo(withTarget: self) { target in
      target.commitEditIfNeeded()
      target.workbook = before
      target.select(beforeSelection)
      target.notifyGridRefresh()
      target.registerWorkbookUndo(
        before: after, beforeSelection: afterSelection, after: before,
        afterSelection: beforeSelection, actionName: actionName)
    }
    undoManager?.setActionName(actionName)
  }

  /// Calculates `pivot` with `definition` and draws it, replacing what it drew before. One undo
  /// step. The pivot must be on the active sheet.
  func applyPivot(_ pivotID: UUID, definition: PivotDefinition) {
    commitEditIfNeeded()
    guard
      let index = activeSheet.fileExtras.sparkPivots.firstIndex(where: { $0.id == pivotID })
    else { return }
    var pivot = activeSheet.fileExtras.sparkPivots[index]
    let table = PivotTable.calculate(
      headers: pivotFieldNames(pivot), records: pivotRecords(pivot), definition: definition)
    let grid: [[String]] = (table?.cells ?? []).map { row in row.map(Self.pivotCellText) }
    let height = grid.count
    let width = grid.map(\.count).max() ?? 0
    // Blank what the last drawing covered beyond the new one.
    let oldRows = pivot.drawnRows
    let oldCols = pivot.drawnColumns
    let clearRows = max(oldRows, height)
    let clearCols = max(oldCols, width)
    var padded = grid.map { $0 + Array(repeating: "", count: max(0, clearCols - $0.count)) }
    while padded.count < clearRows {
      padded.append(Array(repeating: "", count: clearCols))
    }

    undoManager?.beginUndoGrouping()
    if clearRows > 0, clearCols > 0 {
      pasteGrid(padded, at: pivot.anchor, adjustFormulas: false, actionName: "PivotTable")
      let area = CellRange(
        start: pivot.anchor,
        end: CellAddress(
          row: pivot.anchor.row + clearRows - 1, col: pivot.anchor.col + clearCols - 1))
      let bold = table?.boldRows ?? []
      let anchorRow = pivot.anchor.row
      applyFormat(toRanges: [area], actionName: nil) { address, format in
        format.bold = bold.contains(address.row - anchorRow) && address.row - anchorRow < height
      }
    }
    // The note left by a new, empty pivot table goes once fields are chosen.
    if table != nil, activeSheet.cell(at: .origin).raw.hasPrefix("Choose fields with") {
      setCellValue("", at: .origin)
    }
    // A chart of the old table follows it to its new size.
    if let oldChart = Self.pivotChartRange(
      anchor: pivot.anchor, rows: oldRows, columns: oldCols, definition: pivot.definition),
      let newChart = Self.pivotChartRange(
        anchor: pivot.anchor, rows: height, columns: width, definition: definition)
    {
      retargetCharts(from: oldChart, to: newChart)
    }
    pivot.definition = definition
    pivot.drawnRows = height
    pivot.drawnColumns = width
    pivot.fieldNames = pivotFieldNames(pivot)
    let updated = pivot
    updateFileExtras(actionName: "PivotTable") { extras in
      if let i = extras.sparkPivots.firstIndex(where: { $0.id == pivotID }) {
        extras.sparkPivots[i] = updated
      }
      syncLinkedFilePivot(updated, extras: &extras)
    }
    undoManager?.endUndoGrouping()
    undoManager?.setActionName("PivotTable")
    syncEditTextFromSelection()
  }

  /// The part of a drawn pivot table a chart shows: the header row and item rows, without the
  /// grand total row or grand total columns.
  static func pivotChartRange(
    anchor: CellAddress, rows: Int, columns: Int, definition: PivotDefinition
  ) -> CellRange? {
    let totalColumns = definition.columns.isEmpty ? 0 : definition.values.count
    let height = rows - (definition.values.isEmpty ? 0 : 1)
    let width = columns - totalColumns
    guard height >= 2, width >= 1 else { return nil }
    return CellRange(
      start: anchor,
      end: CellAddress(row: anchor.row + height - 1, col: anchor.col + width - 1))
  }

  /// Data ▸ PivotChart: a chart of the selected pivot table that follows it when it changes.
  func beginPivotChart() {
    guard let pivot = selectedPivot ?? activeSheet.fileExtras.sparkPivots.first,
      let range = Self.pivotChartRange(
        anchor: pivot.anchor, rows: pivot.drawnRows, columns: pivot.drawnColumns,
        definition: pivot.definition)
    else { return }
    selectRange(from: range.start, to: range.end)
    beginInsertChart(preferredKind: .bar)
  }

  var canMakePivotChart: Bool {
    guard let pivot = selectedPivot ?? activeSheet.fileExtras.sparkPivots.first else {
      return false
    }
    return Self.pivotChartRange(
      anchor: pivot.anchor, rows: pivot.drawnRows, columns: pivot.drawnColumns,
      definition: pivot.definition) != nil
  }

  /// Draws every pivot table on this sheet again from its source. A pivot table another app
  /// saved is calculated by Spark Grid and drawn where it was; that app's table stays in the file,
  /// covers the new drawing, and rebuilds itself when the file next opens there. One undo step.
  func refreshPivots() {
    commitEditIfNeeded()
    let before = workbook
    let beforeSelection = selectionAnchor
    undoManager?.disableUndoRegistration()
    var skipped: [String] = []
    let linked = Set(activeSheet.fileExtras.sparkPivots.compactMap(\.linkedFilePivot))
    for part in activeSheet.fileExtras.pivotTables {
      let name = ExcelPivotReader.name(of: part.xml) ?? "A pivot table"
      if linked.contains(name) { continue }
      guard let cache = workbook.pivotCaches.first(where: { $0.cacheID == part.cacheID }) else {
        skipped.append("\(name): \(ExcelPivotReader.Unsupported.noSource.reason)")
        continue
      }
      switch ExcelPivotReader.read(
        pivotXML: part.xml, cacheDefinitionXML: cache.definitionXML, workbook: workbook)
      {
      case .failure(let why):
        skipped.append("\(name): \(why.reason)")
      case .success(let info):
        let n = info.location.normalized
        let pivot = SheetPivot(
          name: info.name, sourceSheet: info.sourceSheet, sourceRange: info.sourceRange,
          anchor: CellAddress(row: n.minRow, col: n.minCol), definition: info.definition,
          drawnRows: n.maxRow - n.minRow + 1, drawnColumns: n.maxCol - n.minCol + 1,
          linkedFilePivot: info.name)
        updateFileExtras(actionName: "Refresh PivotTable") { $0.sparkPivots.append(pivot) }
      }
    }
    for pivot in activeSheet.fileExtras.sparkPivots {
      applyPivot(pivot.id, definition: pivot.definition)
    }
    undoManager?.enableUndoRegistration()
    if workbook != before {
      registerWorkbookUndo(
        before: before, beforeSelection: beforeSelection, after: workbook,
        afterSelection: selectionAnchor, actionName: "Refresh PivotTable")
    }
    if !skipped.isEmpty {
      pivotNotice =
        "Spark Grid left \(skipped.count == 1 ? "this pivot table" : "these pivot tables") as the file drew "
        + "\(skipped.count == 1 ? "it" : "them"), because "
        + skipped.joined(separator: "; ") + "."
    }
  }

  /// Keeps another app's pivot table in step with Spark Grid's drawing of it: its area covers
  /// the drawn cells, and its cache rebuilds the table when the file opens in that app.
  private func syncLinkedFilePivot(_ pivot: SheetPivot, extras: inout SheetFileExtras) {
    guard let name = pivot.linkedFilePivot, let drawn = pivot.drawnRange,
      let index = extras.pivotTables.firstIndex(where: {
        ExcelPivotReader.name(of: $0.xml) == name
      })
    else { return }
    extras.pivotTables[index].xml = ExcelPivotReader.pivotXML(
      extras.pivotTables[index].xml, coveringAlso: drawn)
    let cacheID = extras.pivotTables[index].cacheID
    if let cache = workbook.pivotCaches.firstIndex(where: { $0.cacheID == cacheID }),
      !ExcelPivotReader.refreshesOnLoad(workbook.pivotCaches[cache].definitionXML)
    {
      workbook.pivotCaches[cache].definitionXML = ExcelPivotReader.cacheDefinitionXML(
        refreshingOnLoad: workbook.pivotCaches[cache].definitionXML)
    }
  }

  /// Text a pivot cell is written as. Whole numbers have no decimal point.
  static func pivotCellText(_ cell: PivotCell) -> String {
    switch cell {
    case .blank:
      return ""
    case .number(let n):
      if n == n.rounded(), abs(n) < 1e15 { return String(Int64(n)) }
      return String(n)
    case .text(let text):
      // A tab or line break would split the cell when written.
      return text.replacingOccurrences(of: "\t", with: " ")
        .replacingOccurrences(of: "\n", with: " ")
    }
  }
}
