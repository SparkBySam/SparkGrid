import AppKit
import SparkGridCore

/// Edit › Select Blank Cells: the empty cells in the selection, or in the part of the sheet that
/// holds data when one cell is selected (asked for on Reddit, Nov 19). Typing then fills the
/// first; Delete Rows removes their rows.
extension SpreadsheetViewModel {
  /// More ranges than this make the grid slow to draw; the person gets told instead.
  static let maxBlankRanges = 20_000

  func selectBlankCells() {
    let sheet = activeSheet
    var areas = selectionRanges.map(\.normalized)
    if areas.count == 1, areas[0].minRow == areas[0].maxRow, areas[0].minCol == areas[0].maxCol {
      guard sheet.maxPopulatedRow >= 0, sheet.maxPopulatedColumn >= 0 else {
        tellNoBlankCells("This sheet is empty.")
        return
      }
      areas = [
        CellRange(
          start: .origin,
          end: CellAddress(row: sheet.maxPopulatedRow, col: sheet.maxPopulatedColumn)
        ).normalized
      ]
    }
    var ranges: [CellRange] = []
    for area in areas {
      // Each row's runs of empty cells; a run the same as the one above grows down instead.
      var open: [ClosedRange<Int>: CellRange] = [:]
      for row in area.minRow...area.maxRow {
        var runs: [ClosedRange<Int>] = []
        var start: Int?
        for col in area.minCol...area.maxCol {
          let address = CellAddress(row: row, col: col)
          let empty = sheet.cell(at: address).raw.isEmpty && !isCoveredByMerge(address, in: sheet)
          if empty, start == nil { start = col }
          if !empty, let begin = start {
            runs.append(begin...(col - 1))
            start = nil
          }
        }
        if let begin = start { runs.append(begin...area.maxCol) }
        var next: [ClosedRange<Int>: CellRange] = [:]
        for run in runs {
          if let above = open.removeValue(forKey: run) {
            next[run] = CellRange(
              start: above.start, end: CellAddress(row: row, col: run.upperBound))
          } else {
            next[run] = CellRange(
              start: CellAddress(row: row, col: run.lowerBound),
              end: CellAddress(row: row, col: run.upperBound))
          }
        }
        ranges.append(contentsOf: open.values)
        open = next
        if ranges.count + open.count > Self.maxBlankRanges {
          tellNoBlankCells(
            "There are too many separate blank areas to select. Select a smaller range first.")
          return
        }
      }
      ranges.append(contentsOf: open.values)
    }
    guard !ranges.isEmpty else {
      tellNoBlankCells("No cells in the selection are blank.")
      return
    }
    ranges.sort {
      ($0.start.row, $0.start.col) < ($1.start.row, $1.start.col)
    }
    replaceSelection(withRanges: ranges)
  }

  private func isCoveredByMerge(_ address: CellAddress, in sheet: Sheet) -> Bool {
    guard let merge = sheet.mergeContaining(address) else { return false }
    let n = merge.normalized
    return CellAddress(row: n.minRow, col: n.minCol) != address
  }

  private func tellNoBlankCells(_ message: String) {
    let alert = NSAlert()
    alert.messageText = "No blank cells selected"
    alert.informativeText = message
    alert.alertStyle = .informational
    alert.addButton(withTitle: "OK")
    if let window = NSApp.keyWindow {
      alert.beginSheetModal(for: window)
    } else {
      alert.runModal()
    }
  }
}
