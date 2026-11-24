import Foundation
import SparkGridCore
import UniformTypeIdentifiers

/// In-memory spreadsheet session for Quick Look preview + basic cell edits.
final class PreviewSession {
  static let maxPreviewRows = 5_000

  private(set) var fileURL: URL
  private(set) var workbook: Workbook
  private(set) var isCSV: Bool
  private(set) var isDirty = false
  /// Display text and styles, with results for formulas the file saved none for.
  private(set) var presentation: PreviewPresentation

  var activeSheetIndex: Int {
    get { workbook.activeSheetIndex }
    set {
      guard workbook.sheets.indices.contains(newValue) else { return }
      workbook.activeSheetIndex = newValue
    }
  }

  var sheetNames: [String] { workbook.sheets.map(\.name) }

  var activeSheet: Sheet { workbook.activeSheet }

  /// Rows shown in the preview table (may be truncated for large sheets).
  var previewRowCount: Int {
    let populated = max(activeSheet.maxPopulatedRow + 1, 1)
    return min(populated, Self.maxPreviewRows)
  }

  var previewColumnCount: Int {
    max(activeSheet.maxPopulatedColumn + 1, 1)
  }

  var isTruncated: Bool {
    activeSheet.maxPopulatedRow + 1 > Self.maxPreviewRows
  }

  /// `presentation` is made in the background, before the session.
  init(fileURL: URL, presentation: PreviewPresentation) {
    self.fileURL = fileURL
    self.workbook = presentation.workbook
    self.presentation = presentation
    self.isCSV = Self.isDelimitedText(url: fileURL)
  }

  /// Some formulas have no saved result and the workbook is too large to calculate here.
  var hasUncalculatedFormulas: Bool { presentation.hasUncalculatedFormulas }

  func displayValue(row: Int, column: Int) -> String {
    presentation.text(sheet: workbook.activeSheetIndex, at: CellAddress(row: row, col: column))
  }

  func style(row: Int, column: Int, darkMode: Bool) -> PreviewPresentation.Style {
    presentation.style(
      sheet: workbook.activeSheetIndex, at: CellAddress(row: row, col: column), darkMode: darkMode)
  }

  func rowHeight(_ row: Int) -> CGFloat {
    max(activeSheet.rowHeight(for: row, default: 22), 14)
  }

  func columnWidth(_ column: Int) -> CGFloat {
    CGFloat(presentation.columnWidth(sheet: workbook.activeSheetIndex, column: column, default: 80))
  }

  func rawValue(row: Int, column: Int) -> String {
    activeSheet.cell(at: CellAddress(row: row, col: column)).raw
  }

  func setRawValue(_ value: String, row: Int, column: Int) {
    let address = CellAddress(row: row, col: column)
    var sheet = workbook.activeSheet
    var cell = sheet.cell(at: address)
    if value == cell.raw { return }
    cell.raw = value
    if value.isEmpty {
      cell.format = nil
    } else if cell.format == nil, let inferred = Self.inferredFormat(for: value) {
      cell.format = inferred
    }
    sheet.setCell(cell, at: address)
    workbook.activeSheet = sheet
    // An edited formula has no saved result; calculating again also updates what reads it.
    presentation = PreviewPresentation.make(workbook)
    isDirty = true
  }

  func save() throws {
    let accessed = fileURL.startAccessingSecurityScopedResource()
    defer {
      if accessed { fileURL.stopAccessingSecurityScopedResource() }
    }

    if isCSV {
      let csv = CSVCodec.exportCSV(from: workbook.activeSheet)
      guard let data = csv.data(using: .utf8) else {
        throw CocoaError(.fileWriteInapplicableStringEncoding)
      }
      try data.write(to: fileURL, options: .atomic)
    } else {
      let data = try XLSXCodec.exportWorkbook(workbook)
      try data.write(to: fileURL, options: .atomic)
    }
    isDirty = false
  }

  private static func isDelimitedText(url: URL) -> Bool {
    let ext = url.pathExtension.lowercased()
    if ext == "csv" || ext == "tsv" || ext == "txt" { return true }
    if let type = UTType(filenameExtension: ext) {
      if type.conforms(to: .commaSeparatedText) || type.conforms(to: .plainText) {
        return true
      }
      return type.identifier == "public.tab-separated-values-text"
        || type.identifier == "public.tab-separated-values"
        || type.identifier == "com.apple.csv"
        || type.identifier == "public.comma-separated-values"
    }
    return false
  }

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
}
