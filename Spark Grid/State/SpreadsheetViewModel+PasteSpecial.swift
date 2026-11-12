import AppKit
import Foundation
import SparkGridCore

/// Edit > Paste Special: values only, formats only, and transposed.
extension SpreadsheetViewModel {
  /// The copied cells, from the selection, with each one's result and format.
  func cellsPayload(for bounds: CellRange) -> SpreadsheetClipboard.CellsPayload? {
    let n = bounds.normalized
    var rows: [[SpreadsheetClipboard.CellCopy]] = []
    var sourceRows: [Int] = []
    for row in n.minRow...n.maxRow where !isRowHiddenByFilter(row) {
      var cells: [SpreadsheetClipboard.CellCopy] = []
      for col in n.minCol...n.maxCol {
        let address = CellAddress(row: row, col: col)
        let cell = activeSheet.cell(at: address)
        let value =
          FormulaSyntax.isFormula(cell.raw)
          ? literalString(from: displayValue(at: address)) : cell.raw
        cells.append(.init(raw: cell.raw, value: value, format: cell.format))
      }
      rows.append(cells)
      sourceRows.append(row)
    }
    guard !rows.isEmpty else { return nil }
    return .init(originRow: n.minRow, originCol: n.minCol, rows: rows, sourceRows: sourceRows)
  }

  /// Whether Paste Special has something to paste.
  var canPasteSpecial: Bool { SpreadsheetClipboard.readCells() != nil }

  /// Results only: no formulas, no formats.
  func pasteValues() {
    commitEditIfNeeded()
    if let cells = SpreadsheetClipboard.readCells() {
      pasteText(cells.rows.map { $0.map(\.value) }, actionName: "Paste Values")
      return
    }
    // Text from another app has no formulas or formats to drop.
    guard let text = NSPasteboard.general.string(forType: .string) else { return }
    let grid = SpreadsheetClipboard.parseGrid(text)
    pasteText(grid.isEmpty ? [[text]] : grid, actionName: "Paste Values")
  }

  /// Formats only; the cells keep their values.
  func pasteFormats() {
    commitEditIfNeeded()
    guard let cells = SpreadsheetClipboard.readCells() else { return }
    pasteCellFormats(cells, at: selectionAnchor, actionName: "Paste Formats")
  }

  /// Rows become columns. Formulas move with their cells, so a reference to a cell beside it
  /// still points beside it. Formats come along.
  func pasteTransposed() {
    commitEditIfNeeded()
    guard let cells = SpreadsheetClipboard.readCells() else { return }
    let origin = selectionAnchor
    let height = cells.rows.count
    let width = cells.rows.map(\.count).max() ?? 0
    guard height > 0, width > 0 else { return }
    var grid = Array(repeating: Array(repeating: "", count: height), count: width)
    var formats: [CellAddress: CellFormat?] = [:]
    for (r, row) in cells.rows.enumerated() {
      for (c, cell) in row.enumerated() {
        let source = CellAddress(row: cells.sourceRows[r], col: cells.originCol + c)
        let target = CellAddress(row: origin.row + c, col: origin.col + r)
        grid[c][r] =
          FormulaSyntax.isFormula(cell.raw)
          ? FormulaRewriter.adjust(
            cell.raw, rowDelta: target.row - source.row, colDelta: target.col - source.col)
          : cell.raw
        formats[target] = cell.format
      }
    }
    undoManager?.beginUndoGrouping()
    pasteText(grid, actionName: "Paste Transposed")
    applyCopiedFormats(formats, actionName: nil)
    undoManager?.endUndoGrouping()
    undoManager?.setActionName("Paste Transposed")
  }

  /// Puts each copied cell's format on the cell at the same offset from `origin`. A selection
  /// bigger than the copy repeats the copied block across it.
  func pasteCellFormats(
    _ cells: SpreadsheetClipboard.CellsPayload, at origin: CellAddress, actionName: String?
  ) {
    applyFormatBlock(cells.rows.map { $0.map(\.format) }, at: origin, actionName: actionName)
  }

  /// `block[r][c]` goes on the cell at `origin + (r, c)`, repeated across a bigger selection.
  func applyFormatBlock(_ block: [[CellFormat?]], at origin: CellAddress, actionName: String?) {
    let height = block.count
    let width = block.map(\.count).max() ?? 0
    guard height > 0, width > 0 else { return }
    let selection = selectionRange.normalized
    let target: CellRange
    if !selectionRange.isSingleCell, selection.maxRow - selection.minRow + 1 >= height,
      selection.maxCol - selection.minCol + 1 >= width
    {
      target = selectionRange
    } else {
      target = CellRange(
        start: origin,
        end: CellAddress(row: origin.row + height - 1, col: origin.col + width - 1))
    }
    let t = target.normalized
    var formats: [CellAddress: CellFormat?] = [:]
    for row in t.minRow...t.maxRow {
      for col in t.minCol...t.maxCol {
        let r = (row - t.minRow) % height
        let c = (col - t.minCol) % width
        guard c < block[r].count else { continue }
        formats[CellAddress(row: row, col: col)] = block[r][c]
      }
    }
    applyCopiedFormats(formats, actionName: actionName)
  }

  // MARK: - Format Painter

  /// Picks up the selection's formats; the next selection made with the mouse gets them.
  /// Clicking it again, or Escape, puts it away.
  func toggleFormatPainter() {
    commitEditIfNeeded()
    if formatPainterBlock != nil {
      formatPainterBlock = nil
      return
    }
    let n = selectionRange.normalized
    guard (n.maxRow - n.minRow + 1) * (n.maxCol - n.minCol + 1) <= 10_000 else { return }
    formatPainterBlock = (n.minRow...n.maxRow).map { row in
      (n.minCol...n.maxCol).map { col in
        activeSheet.cell(at: CellAddress(row: row, col: col)).format
      }
    }
  }

  /// Called when a mouse selection ends.
  func applyFormatPainterIfActive() {
    guard let block = formatPainterBlock else { return }
    formatPainterBlock = nil
    let n = selectionRange.normalized
    applyFormatBlock(
      block, at: CellAddress(row: n.minRow, col: n.minCol), actionName: "Format Painter")
  }

  private func applyCopiedFormats(_ formats: [CellAddress: CellFormat?], actionName: String?) {
    guard !formats.isEmpty else { return }
    let ranges = formats.keys.map { CellRange(start: $0, end: $0) }
    applyFormat(toRanges: ranges, actionName: actionName) { address, format in
      format = (formats[address] ?? nil) ?? CellFormat()
    }
  }

  /// Writes the grid from `selectionAnchor` as typed text, one undo step.
  private func pasteText(_ grid: [[String]], actionName: String) {
    pasteGrid(grid, at: selectionAnchor, adjustFormulas: false, actionName: actionName)
    syncEditTextFromSelection()
  }
}
