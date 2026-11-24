import AppIntents
import AppKit
import Foundation
import SparkGridCore
import UniformTypeIdentifiers

// Shortcuts actions: open a workbook, read or change a cell, and export a PDF or CSV. All but
// Open work on the file given without showing it, and give back what they make.

/// Why a Shortcuts action could not finish, in words for the person running it.
enum WorkbookShortcutError: Error, CustomLocalizedStringResourceConvertible, LocalizedError {
  case cellNotUnderstood(String)
  case noSuchSheet(String)
  case noFileLocation
  case unreadable(String)

  var message: String {
    switch self {
    case .cellNotUnderstood(let text):
      "“\(text)” isn’t a cell. Use a cell such as B2, or Sales!B2 for a cell on another sheet."
    case .noSuchSheet(let name):
      "The workbook has no sheet named “\(name)”."
    case .noFileLocation:
      "Spark Grid was given the file’s contents but not where it is, so it can’t open it. Pass the file from Files or Finder."
    case .unreadable(let reason):
      "Spark Grid couldn’t read the file: \(reason)"
    }
  }

  var localizedStringResource: LocalizedStringResource { "\(message)" }
  var errorDescription: String? { message }
}

/// Reading the file a Shortcut passes, and finding a cell in it.
enum WorkbookShortcuts {

  /// The workbook in `file`. Read from where the file is when Shortcuts says, else from a copy
  /// of its contents.
  static func workbook(in file: IntentFile) async throws -> Workbook {
    let url: URL
    var temporaryFolder: URL?
    var accessing = false
    if let location = file.fileURL {
      url = location
      accessing = location.startAccessingSecurityScopedResource()
    } else {
      let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("Shortcuts", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      url = folder.appendingPathComponent(file.filename)
      try file.data.write(to: url)
      temporaryFolder = folder
    }
    defer {
      if accessing { url.stopAccessingSecurityScopedResource() }
      if let temporaryFolder { try? FileManager.default.removeItem(at: temporaryFolder) }
    }
    do {
      return try await Task.detached(priority: .userInitiated) {
        try SpreadsheetDocumentStore.readDocument(at: url).workbook
      }.value
    } catch {
      throw WorkbookShortcutError.unreadable(error.localizedDescription)
    }
  }

  /// The sheet and cell `text` names: `B2` on the sheet the file opens to, or `Sales!B2`.
  static func locate(_ text: String, in workbook: Workbook) throws -> (
    sheet: Int, address: CellAddress
  ) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let expr = try? FormulaParser.parse("=" + trimmed), case .cellRef(let ref) = expr,
      !ref.isRowOpen, !ref.isColOpen
    else { throw WorkbookShortcutError.cellNotUnderstood(text) }
    guard let sheetName = ref.sheet else {
      return (workbook.activeSheetIndex, CellAddress(row: ref.row, col: ref.col))
    }
    guard
      let index = workbook.sheets.firstIndex(where: {
        $0.name.caseInsensitiveCompare(sheetName) == .orderedSame
      })
    else { throw WorkbookShortcutError.noSuchSheet(sheetName) }
    return (index, CellAddress(row: ref.row, col: ref.col))
  }

  /// The sheet named `name`, or the one the file opens to when none is given.
  static func sheetIndex(_ name: String?, in workbook: Workbook) throws -> Int {
    guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
      return workbook.activeSheetIndex
    }
    guard
      let index = workbook.sheets.firstIndex(where: {
        $0.name.caseInsensitiveCompare(name) == .orderedSame
      })
    else { throw WorkbookShortcutError.noSuchSheet(name) }
    return index
  }

  /// The workbook calculated, showing `sheet`.
  @MainActor
  static func calculated(_ workbook: Workbook, showing sheet: Int) async -> SpreadsheetViewModel {
    var showing = workbook
    showing.activeSheetIndex = sheet
    let viewModel = SpreadsheetViewModel(workbook: showing)
    await viewModel.calculateMissingResults()
    viewModel.formulaEngine.finishPendingCrossSheet()
    return viewModel
  }

  /// A value without its format: 1200.5 rather than $1,200.50, a date as its serial number.
  static func plainText(_ value: CellValue) -> String {
    switch value {
    case .number(let n):
      if n == n.rounded(), abs(n) < 1e15 { return String(Int64(n)) }
      return String(n)
    case .bool(let b): return b ? "TRUE" : "FALSE"
    case .string(let s): return s
    case .error(let e): return e.displayCode
    case .blank: return ""
    }
  }

  /// The pages printing makes, as a PDF: the sheet showing, or every sheet.
  @MainActor
  static func pdfData(_ viewModel: SpreadsheetViewModel, title: String, everySheet: Bool) throws
    -> Data
  {
    var options = SpreadsheetPrintOptions.default(for: viewModel, documentTitle: title)
    if everySheet { options.scope = .workbook }
    return try SpreadsheetPDFExporter.pdfData(
      pages: options.pages(for: viewModel), options: options, workbook: viewModel.workbook
    ).data
  }

  /// The sheet showing as CSV, each cell as it is shown.
  @MainActor
  static func csvText(_ viewModel: SpreadsheetViewModel) -> String {
    let sheet = viewModel.activeSheet
    guard sheet.maxPopulatedRow >= 0, sheet.maxPopulatedColumn >= 0 else { return "" }
    let rows = (0...sheet.maxPopulatedRow).map { row in
      (0...sheet.maxPopulatedColumn).map { col in
        viewModel.displayString(at: CellAddress(row: row, col: col))
      }
    }
    return CSVCodec.exportCSV(rows: rows)
  }

  static func baseName(_ file: IntentFile) -> String {
    let name = (file.filename as NSString).deletingPathExtension
    return name.isEmpty ? "Workbook" : name
  }
}

// MARK: - Open

struct OpenWorkbookIntent: AppIntent {
  static let title: LocalizedStringResource = "Open Workbook"
  static let description = IntentDescription(
    "Opens a spreadsheet or Numbers document in Spark Grid.")
  static let openAppWhenRun = true

  @Parameter(
    title: "Workbook",
    supportedTypeIdentifiers: [
      "org.openxmlformats.spreadsheetml.sheet", "public.comma-separated-values-text",
      "com.apple.iwork.numbers.sffnumbers", "com.apple.iwork.numbers.numbers",
      "org.oasis-open.opendocument.spreadsheet",
    ])
  var file: IntentFile

  static var parameterSummary: some ParameterSummary {
    Summary("Open \(\.$file) in Spark Grid")
  }

  @MainActor
  func perform() async throws -> some IntentResult {
    guard let url = file.fileURL else { throw WorkbookShortcutError.noFileLocation }
    // Kept for as long as the window has the file, so saving can write to it.
    _ = url.startAccessingSecurityScopedResource()
    WorkbookWindows.shared.open(url)
    NSApp.activate()
    return .result()
  }
}

// MARK: - Get Cell

enum CellReading: String, AppEnum {
  case shown
  case value

  static let typeDisplayRepresentation: TypeDisplayRepresentation = "Cell Reading"
  static let caseDisplayRepresentations: [CellReading: DisplayRepresentation] = [
    .shown: DisplayRepresentation(
      title: "As Shown", subtitle: "With its format, such as $1,200.50 or Mar 4, 2026"),
    .value: DisplayRepresentation(
      title: "Value", subtitle: "Without its format, such as 1200.5; a date as its serial number"),
  ]
}

struct GetCellIntent: AppIntent {
  static let title: LocalizedStringResource = "Get Cell from Workbook"
  static let description = IntentDescription(
    "Gets a cell from a spreadsheet or Numbers document, with formulas calculated. Name the cell like B2 for the sheet the file opens to, or Sales!B2 for another sheet."
  )

  @Parameter(
    title: "Workbook",
    supportedTypeIdentifiers: [
      "org.openxmlformats.spreadsheetml.sheet", "public.comma-separated-values-text",
      "com.apple.iwork.numbers.sffnumbers", "com.apple.iwork.numbers.numbers",
      "org.oasis-open.opendocument.spreadsheet",
    ])
  var file: IntentFile

  @Parameter(title: "Cell", inputOptions: String.IntentInputOptions(autocorrect: false))
  var cell: String

  @Parameter(title: "Reading", default: .shown)
  var reading: CellReading

  static var parameterSummary: some ParameterSummary {
    Summary("Get \(\.$cell) from \(\.$file)") {
      \.$reading
    }
  }

  @MainActor
  func perform() async throws -> some IntentResult & ReturnsValue<String> {
    let workbook = try await WorkbookShortcuts.workbook(in: file)
    let place = try WorkbookShortcuts.locate(cell, in: workbook)
    let viewModel = await WorkbookShortcuts.calculated(workbook, showing: place.sheet)
    let text =
      switch reading {
      case .shown: viewModel.displayString(at: place.address)
      case .value: WorkbookShortcuts.plainText(viewModel.displayValue(at: place.address))
      }
    return .result(value: text)
  }
}

// MARK: - Set Cell

struct SetCellIntent: AppIntent {
  static let title: LocalizedStringResource = "Set Cell in Workbook"
  static let description = IntentDescription(
    "Puts a value or formula in a cell, as typing it would, and gives back the changed workbook. Save it with Save File. A Numbers document comes back as an .xlsx workbook."
  )

  @Parameter(
    title: "Workbook",
    supportedTypeIdentifiers: [
      "org.openxmlformats.spreadsheetml.sheet", "public.comma-separated-values-text",
      "com.apple.iwork.numbers.sffnumbers", "com.apple.iwork.numbers.numbers",
      "org.oasis-open.opendocument.spreadsheet",
    ])
  var file: IntentFile

  @Parameter(title: "Cell", inputOptions: String.IntentInputOptions(autocorrect: false))
  var cell: String

  @Parameter(title: "Value", inputOptions: String.IntentInputOptions(autocorrect: false))
  var value: String

  static var parameterSummary: some ParameterSummary {
    Summary("Set \(\.$cell) in \(\.$file) to \(\.$value)")
  }

  @MainActor
  func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
    let workbook = try await WorkbookShortcuts.workbook(in: file)
    let place = try WorkbookShortcuts.locate(cell, in: workbook)
    let viewModel = await WorkbookShortcuts.calculated(workbook, showing: place.sheet)
    viewModel.setCellValue(value, at: place.address)
    viewModel.formulaEngine.finishPendingCrossSheet()
    var changed = viewModel.workbook
    changed.activeSheetIndex = workbook.activeSheetIndex
    let stamp = viewModel.formulaEngine.formulaSaveStamp()
    let name = WorkbookShortcuts.baseName(file)
    let csv = file.filename.lowercased().hasSuffix(".csv")
    let data: Data =
      if csv {
        Data(CSVCodec.exportCSV(from: changed.activeSheet).utf8)
      } else {
        try await Task.detached(priority: .userInitiated) {
          try XLSXCodec.exportWorkbook(
            FormulaCacheWriter.prepare(changed, stamp: stamp), includeFormulaCaches: true)
        }.value
      }
    let output = IntentFile(
      data: data, filename: name + (csv ? ".csv" : ".xlsx"),
      type: csv ? .commaSeparatedText : .spreadsheetML)
    return .result(value: output)
  }
}

// MARK: - Export

enum WorkbookExportFormat: String, AppEnum {
  case pdf
  case csv

  static let typeDisplayRepresentation: TypeDisplayRepresentation = "Export Format"
  static let caseDisplayRepresentations: [WorkbookExportFormat: DisplayRepresentation] = [
    .pdf: "PDF",
    .csv: "CSV",
  ]
}

struct ExportWorkbookIntent: AppIntent {
  static let title: LocalizedStringResource = "Export Workbook"
  static let description = IntentDescription(
    "Makes a PDF or CSV from a spreadsheet or Numbers document, with formulas calculated. The PDF has the pages printing makes; the CSV has one sheet's cells as they are shown."
  )

  @Parameter(
    title: "Workbook",
    supportedTypeIdentifiers: [
      "org.openxmlformats.spreadsheetml.sheet", "public.comma-separated-values-text",
      "com.apple.iwork.numbers.sffnumbers", "com.apple.iwork.numbers.numbers",
      "org.oasis-open.opendocument.spreadsheet",
    ])
  var file: IntentFile

  @Parameter(title: "Format", default: .pdf)
  var format: WorkbookExportFormat

  @Parameter(
    title: "Sheet",
    description: "The sheet to export. Left empty, the sheet the file opens to.",
    inputOptions: String.IntentInputOptions(autocorrect: false))
  var sheet: String?

  @Parameter(
    title: "Every Sheet", description: "For a PDF: every sheet, one after another.", default: false)
  var everySheet: Bool

  static var parameterSummary: some ParameterSummary {
    When(\.$format, .equalTo, .pdf) {
      Summary("Export \(\.$file) as \(\.$format)") {
        \.$sheet
        \.$everySheet
      }
    } otherwise: {
      Summary("Export \(\.$file) as \(\.$format)") {
        \.$sheet
      }
    }
  }

  @MainActor
  func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
    let workbook = try await WorkbookShortcuts.workbook(in: file)
    let index = try WorkbookShortcuts.sheetIndex(sheet, in: workbook)
    let viewModel = await WorkbookShortcuts.calculated(workbook, showing: index)
    let name = WorkbookShortcuts.baseName(file)
    switch format {
    case .pdf:
      let data = try WorkbookShortcuts.pdfData(viewModel, title: name, everySheet: everySheet)
      return .result(value: IntentFile(data: data, filename: name + ".pdf", type: .pdf))
    case .csv:
      let sheet = viewModel.activeSheet
      let text = WorkbookShortcuts.csvText(viewModel)
      let filename = workbook.sheets.count > 1 ? "\(name) - \(sheet.name).csv" : "\(name).csv"
      return .result(
        value: IntentFile(data: Data(text.utf8), filename: filename, type: .commaSeparatedText))
    }
  }
}
