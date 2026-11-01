import Formula
import Foundation
import GridCore
import Model
import NumberFormat

public nonisolated enum CSVCodec {
  /// Parse CSV/TSV text into a sparse sheet cell map.
  public static func importCSV(_ text: String) -> [CellAddress: Cell] {
    let normalized = normalizeLineEndings(stripBOM(text))
    let delimiter = detectDelimiter(in: normalized)
    var cells: [CellAddress: Cell] = [:]
    let rows = parseRows(from: normalized, delimiter: delimiter)
    for (rowIndex, fields) in rows.enumerated() {
      for (colIndex, field) in fields.enumerated() {
        let value = field.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { continue }
        var cell = Cell(raw: value)
        if let format = inferredFormat(for: value) {
          cell.format = format
        }
        cells[CellAddress(row: rowIndex, col: colIndex)] = cell
      }
    }
    return cells
  }

  /// Detect simple typed literals so display matches what the formula bar shows (e.g. `12.5%`).
  private static func inferredFormat(for value: String) -> CellFormat? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.hasSuffix("%"),
      Double(
        String(trimmed.dropLast())
          .trimmingCharacters(in: .whitespaces)
          .replacingOccurrences(of: ",", with: "")
      ) != nil
    {
      var format = CellFormat()
      format.numberFormat = .percent
      format.decimalPlaces = 2
      return format
    }
    if trimmed.hasPrefix("$"),
      Double(String(trimmed.dropFirst()).replacingOccurrences(of: ",", with: "")) != nil
    {
      var format = CellFormat()
      format.numberFormat = .currency
      format.decimalPlaces = 2
      return format
    }
    return nil
  }

  /// Export the active sheet to CSV text.
  public static func exportCSV(from sheet: Sheet) -> String {
    let maxRow = sheet.maxPopulatedRow
    let maxCol = sheet.maxPopulatedColumn
    guard maxRow >= 0, maxCol >= 0 else { return "" }

    var lines: [String] = []
    lines.reserveCapacity(maxRow + 1)
    for row in 0...maxRow {
      var fields: [String] = []
      fields.reserveCapacity(maxCol + 1)
      for col in 0...maxCol {
        let value = sheet.cell(at: CellAddress(row: row, col: col)).raw
        fields.append(escapeField(value))
      }
      lines.append(fields.joined(separator: ","))
    }
    return lines.joined(separator: "\n")
  }

  // MARK: - Parsing

  private static func stripBOM(_ text: String) -> String {
    guard text.first == "\u{FEFF}" else { return text }
    return String(text.dropFirst())
  }

  /// Excel and many exports use CRLF; Swift can treat `\r\n` as one Character that is not `==` to `\r` or `\n`.
  private static func normalizeLineEndings(_ text: String) -> String {
    text
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
  }

  private static func detectDelimiter(in text: String) -> Character {
    let sample = text.prefix(8_192)
    let firstLine =
      sample.split(whereSeparator: \.isNewline).first.map(String.init) ?? String(sample)
    let commaCount = firstLine.filter { $0 == "," }.count
    let tabCount = firstLine.filter { $0 == "\t" }.count
    let semicolonCount = firstLine.filter { $0 == ";" }.count
    if tabCount > commaCount && tabCount > semicolonCount { return "\t" }
    if semicolonCount > commaCount { return ";" }
    return ","
  }

  private static func parseRows(from text: String, delimiter: Character) -> [[String]] {
    var rows: [[String]] = []
    var currentRow: [String] = []
    var currentField = ""
    var inQuotes = false
    var index = text.startIndex

    func finishField() {
      currentRow.append(currentField)
      currentField = ""
    }

    func finishRow() {
      finishField()
      if !currentRow.isEmpty {
        rows.append(currentRow)
      }
      currentRow = []
    }

    while index < text.endIndex {
      let char = text[index]

      if inQuotes {
        if char == "\"" {
          let next = text.index(after: index)
          if next < text.endIndex, text[next] == "\"" {
            currentField.append("\"")
            index = next
          } else {
            inQuotes = false
          }
        } else {
          currentField.append(char)
        }
      } else if char == "\"" {
        inQuotes = true
      } else if char == delimiter {
        finishField()
      } else if char == "\n" {
        finishRow()
      } else {
        currentField.append(char)
      }

      index = text.index(after: index)
    }

    if inQuotes {
      finishField()
    }
    if !currentField.isEmpty || !currentRow.isEmpty {
      finishField()
      if !currentRow.isEmpty {
        rows.append(currentRow)
      }
    }

    return rows
  }

  private static func escapeField(_ value: String) -> String {
    let needsQuotes =
      value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r")
    guard needsQuotes else { return value }
    return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
  }
}
