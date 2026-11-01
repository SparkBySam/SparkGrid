import AppKit
import Foundation
import SparkGridCore

/// Tab-separated grid clipboard encoding (compatible with Excel, Google Sheets, Numbers).
enum SpreadsheetClipboard {
  /// Custom pasteboard type for formula paste with relative adjustment.
  static let formulaGridType = NSPasteboard.PasteboardType("app.sparkgrid.formula-grid")
  /// Conditional-format rules clipped to the copied bounds.
  static let conditionalFormatType = NSPasteboard.PasteboardType(
    "app.sparkgrid.conditional-formats")

  struct FormulaGridPayload: Codable, Equatable {
    var originRow: Int
    var originCol: Int
    var grid: [[String]]
  }

  /// Rules clipped to the copied cell block. Formula predicates are relative to each rule's top-left.
  struct ConditionalFormatClipboardPayload: Codable, Equatable {
    var originRow: Int
    var originCol: Int
    var rules: [ConditionalFormatRule]
  }

  struct CopyRegion: Equatable {
    var text: String
    /// Bounds actually written into `text`. Nil when a huge selection contains no cells.
    var bounds: CellRange?
  }

  /// `skippingRow` leaves rows out of the copy, such as rows a filter hides.
  static func copyText(
    from sheet: Sheet, range: CellRange, skippingRow: (Int) -> Bool = { _ in false }
  ) -> String {
    copyRegion(from: sheet, range: range, skippingRow: skippingRow).text
  }

  static func copyRegion(
    from sheet: Sheet, range: CellRange, skippingRow: (Int) -> Bool = { _ in false }
  ) -> CopyRegion {
    guard let bounds = boundsForCopy(from: sheet, range: range) else {
      return CopyRegion(text: "", bounds: nil)
    }
    return CopyRegion(
      text: gridText(from: sheet, bounds: bounds, skippingRow: skippingRow), bounds: bounds)
  }

  /// For huge selections (e.g. whole sheet), only the populated sub-range is copied.
  private static func boundsForCopy(from sheet: Sheet, range: CellRange) -> CellRange? {
    let bounds = range.normalized
    let rowCount = bounds.maxRow - bounds.minRow + 1
    let colCount = bounds.maxCol - bounds.minCol + 1
    if rowCount * colCount > 4_000, let used = sheet.populatedBounds {
      let usedNorm = used.normalized
      let minRow = max(bounds.minRow, usedNorm.minRow)
      let maxRow = min(bounds.maxRow, usedNorm.maxRow)
      let minCol = max(bounds.minCol, usedNorm.minCol)
      let maxCol = min(bounds.maxCol, usedNorm.maxCol)
      guard minRow <= maxRow, minCol <= maxCol else { return nil }
      return CellRange(
        start: CellAddress(row: minRow, col: minCol),
        end: CellAddress(row: maxRow, col: maxCol)
      )
    }
    return CellRange(
      start: CellAddress(row: bounds.minRow, col: bounds.minCol),
      end: CellAddress(row: bounds.maxRow, col: bounds.maxCol)
    )
  }

  private static func gridText(
    from sheet: Sheet, bounds: CellRange, skippingRow: (Int) -> Bool
  ) -> String {
    let n = bounds.normalized
    let rowCount = n.maxRow - n.minRow + 1
    let colCount = n.maxCol - n.minCol + 1
    var rows: [String] = []
    rows.reserveCapacity(rowCount)
    for row in n.minRow...n.maxRow where !skippingRow(row) {
      var fields: [String] = []
      fields.reserveCapacity(colCount)
      for col in n.minCol...n.maxCol {
        fields.append(escapeField(sheet.cell(at: CellAddress(row: row, col: col)).raw))
      }
      rows.append(fields.joined(separator: "\t"))
    }
    return rows.joined(separator: "\n")
  }

  static func grid(
    from sheet: Sheet, range: CellRange, skippingRow: (Int) -> Bool = { _ in false }
  ) -> [[String]] {
    let bounds = range.normalized
    var grid: [[String]] = []
    for row in bounds.minRow...bounds.maxRow where !skippingRow(row) {
      var fields: [String] = []
      for col in bounds.minCol...bounds.maxCol {
        fields.append(sheet.cell(at: CellAddress(row: row, col: col)).raw)
      }
      grid.append(fields)
    }
    return grid
  }

  /// Parses TSV/CSV-style clipboard text. Quoted fields may contain tabs and newlines
  /// (Excel Alt+Enter / wrap) without splitting into extra rows or columns.
  static func parseGrid(_ text: String) -> [[String]] {
    let normalized =
      text
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")

    guard !normalized.isEmpty else { return [] }

    var grid: [[String]] = []
    var row: [String] = []
    var field = ""
    var inQuotes = false
    var index = normalized.startIndex

    while index < normalized.endIndex {
      let character = normalized[index]
      if inQuotes {
        if character == "\"" {
          let next = normalized.index(after: index)
          if next < normalized.endIndex, normalized[next] == "\"" {
            field.append("\"")
            index = next
          } else {
            inQuotes = false
          }
        } else {
          field.append(character)
        }
      } else {
        switch character {
        case "\"":
          inQuotes = true
        case "\t":
          row.append(field)
          field = ""
        case "\n":
          row.append(field)
          field = ""
          grid.append(row)
          row = []
        default:
          field.append(character)
        }
      }
      index = normalized.index(after: index)
    }

    row.append(field)
    // Trailing newline after the last record is common on pasteboards.
    if !(row.count == 1 && row[0].isEmpty && !grid.isEmpty) {
      grid.append(row)
    }
    return grid
  }

  /// Quote fields that contain tabs, newlines, or quotes (Excel-compatible TSV).
  static func escapeField(_ value: String) -> String {
    if value.contains(where: { $0 == "\t" || $0 == "\n" || $0 == "\r" || $0 == "\"" }) {
      return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
    return value
  }

  static var hasContent: Bool {
    NSPasteboard.general.string(forType: .string) != nil
  }

  static func writeText(
    _ text: String,
    conditionalFormats: ConditionalFormatClipboardPayload? = nil
  ) {
    let board = NSPasteboard.general
    board.clearContents()
    board.setString(text, forType: .string)
    writeConditionalFormats(conditionalFormats, to: board)
  }

  static func writeFormulaGrid(
    _ payload: FormulaGridPayload,
    tsv: String,
    conditionalFormats: ConditionalFormatClipboardPayload? = nil
  ) {
    let board = NSPasteboard.general
    board.clearContents()
    board.setString(tsv, forType: .string)
    if let data = try? JSONEncoder().encode(payload) {
      board.setData(data, forType: formulaGridType)
    }
    writeConditionalFormats(conditionalFormats, to: board)
  }

  static func readFormulaGrid() -> FormulaGridPayload? {
    guard let data = NSPasteboard.general.data(forType: formulaGridType) else { return nil }
    return try? JSONDecoder().decode(FormulaGridPayload.self, from: data)
  }

  static func readConditionalFormats() -> ConditionalFormatClipboardPayload? {
    guard let data = NSPasteboard.general.data(forType: conditionalFormatType) else { return nil }
    return try? JSONDecoder().decode(ConditionalFormatClipboardPayload.self, from: data)
  }

  private static func writeConditionalFormats(
    _ payload: ConditionalFormatClipboardPayload?,
    to board: NSPasteboard
  ) {
    guard let payload, !payload.rules.isEmpty,
      let data = try? JSONEncoder().encode(payload)
    else { return }
    board.setData(data, forType: conditionalFormatType)
  }
}
