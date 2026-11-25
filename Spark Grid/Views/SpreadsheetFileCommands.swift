import AppKit
import SparkGridCore
import SwiftUI
import UniformTypeIdentifiers

struct SpreadsheetFileCommands: Commands {
  /// The front workbook window's document. Nil when no workbook window is in front.
  @FocusedValue(\.documentStore) private var store: SpreadsheetDocumentStore?
  @Bindable private var settings = AppSettings.shared

  var body: some Commands {
    CommandGroup(replacing: .newItem) {
      // A new workbook opens in a new window, as other Mac apps do.
      Button("New Spreadsheet") {
        WorkbookWindows.shared.newWindow(.blank)
      }
      .hotkey(.newWorkbook, settings)

      Button("New from Template…") {
        if let store, !store.showsStartScreen, store.fileURL == nil, store.importedName == nil,
          !store.isDirty, store.document.workbook.isEffectivelyEmpty
        {
          // A blank window shows the templates in place.
          store.showStartScreen()
        } else {
          WorkbookWindows.shared.newWindow(.startScreen)
        }
      }
      .hotkey(.newFromTemplate, settings)
      .disabled(store?.showsStartScreen == true)
    }

    CommandGroup(after: .newItem) {
      Button("Open…") {
        SpreadsheetOpenPanel.run(preferring: store)
      }
      .hotkey(.open, settings)

      Button("Save") {
        _ = store?.saveInteractively()
      }
      .keyboardShortcut(
        settings.keyEquivalent(for: .save), modifiers: settings.eventModifiers(for: .save)
      )
      .disabled(
        store == nil
          || (store?.fileURL == nil && store?.document.workbook.isEffectivelyEmpty == true))

      Button("Save As…") {
        if let store { saveAsPanel(store) }
      }
      .hotkey(.saveAs, settings)
      .disabled(store == nil)

      Button("Browse Versions…") {
        guard let store else { return }
        SparkDialogPresenter.present(
          title: "Versions", width: 420, in: WorkbookWindows.shared.window(of: store)
        ) { close in
          VersionsSheet(store: store, onDismiss: close)
        }
      }
      .disabled(store?.fileURL == nil)

      Divider()

      // Mail, Messages, AirDrop and the rest, with the workbook as it is now.
      if let store, store.canShare {
        ShareLink(
          "Share", item: SharedWorkbook(store: store, isCSV: store.sharesAsCSV),
          preview: SharePreview(store.shareFilename))
      } else {
        Button("Share") {}.disabled(true)
      }
    }
  }

  private func saveAsPanel(_ store: SpreadsheetDocumentStore) {
    let panel = NSSavePanel()
    // Tab-separated text and a web page joined in 1.7 (Sam, Nov 20: "more save as formats").
    panel.allowedContentTypes = [
      .spreadsheetML, .openDocumentSpreadsheet, .commaSeparatedText, .tabSeparatedText, .html,
    ]
    panel.message =
      "Excel Workbook (.xlsx) and OpenDocument (.ods) keep all sheets. CSV and tab-separated text "
      + "keep the active sheet. A web page (.html) shows every sheet as it looks; the window "
      + "keeps its own file."
    let baseName =
      store.fileURL?.deletingPathExtension().lastPathComponent
      ?? store.document.workbook.activeSheet.name
    // A CSV stays a CSV and an .ods an .ods unless the person picks another type (a Reddit
    // note, Nov 19); everything else defaults to .xlsx so formatting, rules and filters survive.
    let currentExtension = store.fileURL?.pathExtension.lowercased()
    let keepsCSV = currentExtension == "csv"
    let keepsODS = currentExtension == "ods"
    panel.nameFieldStringValue = "\(baseName).\(keepsCSV ? "csv" : keepsODS ? "ods" : "xlsx")"
    panel.canCreateDirectories = true
    panel.isExtensionHidden = false
    if #available(macOS 15.0, *) {
      // A Format menu with .xlsx, .ods and CSV, so the choice shows (1.7).
      panel.showsContentTypes = true
      panel.currentContentType =
        keepsCSV ? .commaSeparatedText : keepsODS ? .openDocumentSpreadsheet : .spreadsheetML
    }
    guard panel.runModal() == .OK, let url = panel.url else { return }
    let destination = normalizedSaveURL(url, panel: panel)
    if SpreadsheetDocumentStore.keepsOneSheet(destination),
      store.hasMultipleSheets,
      !confirmCSVOnly(store)
    {
      return
    }
    try? store.save(to: destination)
  }

  /// Fixes macOS Save panel appending `.csv` onto names that already end in `.xlsx`.
  private func normalizedSaveURL(_ url: URL, panel: NSSavePanel) -> URL {
    var destination = url
    let lower = destination.lastPathComponent.lowercased()
    if lower.hasSuffix(".xlsx.csv") || lower.contains(".xlsx.") {
      let trimmed = destination.lastPathComponent
        .replacingOccurrences(of: ".xlsx.csv", with: ".xlsx", options: .caseInsensitive)
        .replacingOccurrences(of: ".xlsx.xlsx", with: ".xlsx", options: .caseInsensitive)
      destination = destination.deletingLastPathComponent().appendingPathComponent(trimmed)
    }
    if #available(macOS 15.0, *),
      let type = panel.currentContentType,
      type.conforms(to: .spreadsheetML) || type.identifier == UTType.spreadsheetML.identifier
    {
      if destination.pathExtension.lowercased() != "xlsx" {
        destination = destination.deletingPathExtension().appendingPathExtension("xlsx")
      }
    } else if #available(macOS 15.0, *),
      panel.currentContentType?.identifier == UTType.openDocumentSpreadsheet.identifier,
      destination.pathExtension.lowercased() != "ods"
    {
      destination = destination.deletingPathExtension().appendingPathExtension("ods")
    } else if destination.pathExtension.lowercased().isEmpty {
      destination = destination.appendingPathExtension("xlsx")
    }
    return destination
  }

  private func confirmCSVOnly(_ store: SpreadsheetDocumentStore) -> Bool {
    let sheetName = store.document.workbook.activeSheet.name
    let alert = NSAlert()
    alert.messageText = "Save Active Sheet Only?"
    alert.informativeText =
      "CSV files contain one sheet. Only \"\(sheetName)\" will be saved; other sheets in this workbook won't be included."
    alert.alertStyle = .informational
    alert.addButton(withTitle: "Save")
    alert.addButton(withTitle: "Cancel")
    return alert.runModal() == .alertFirstButtonReturn
  }
}

/// The front workbook, for File ▸ Share. The file is written only when a way to share is
/// picked, so it has every edit up to then.
struct SharedWorkbook: Transferable {
  let store: SpreadsheetDocumentStore
  /// Worked out when the menu is built: the exporting conditions can run off the main thread.
  let isCSV: Bool

  static var transferRepresentation: some TransferRepresentation {
    FileRepresentation(exportedContentType: .spreadsheetML) { item in
      SentTransferredFile(try await item.write())
    }
    .exportingCondition { !$0.isCSV }
    FileRepresentation(exportedContentType: .commaSeparatedText) { item in
      SentTransferredFile(try await item.write())
    }
    .exportingCondition { $0.isCSV }
  }

  private func write() async throws -> URL {
    let copy = await MainActor.run { store.shareCopy() }
    return try await Task.detached(priority: .userInitiated) {
      try SpreadsheetDocumentStore.writeShareCopy(copy)
    }.value
  }
}

enum SpreadsheetOpenPanel {
  @MainActor
  /// Opens the chosen file in `preferred` when that window is unused, else as `WorkbookWindows`
  /// decides: the window that has it, or a new one.
  static func run(preferring preferred: SpreadsheetDocumentStore?) {
    let panel = NSOpenPanel()
    // The files Spark Grid reads: the two it saves, and Numbers documents. Plain text let any
    // text file be picked, and it opened as a one-column CSV.
    panel.allowedContentTypes = UTType.spreadsheetsSparkGridOpens
    panel.allowsOtherFileTypes = false
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    // A Numbers package is a folder; this keeps it one item to pick.
    panel.treatsFilePackagesAsDirectories = false
    guard panel.runModal() == .OK, let url = panel.url else { return }
    WorkbookWindows.shared.open(url, preferring: preferred)
  }
}

private struct DocumentStoreFocusedValueKey: FocusedValueKey {
  typealias Value = SpreadsheetDocumentStore
}

extension FocusedValues {
  /// The document of the workbook window in front.
  var documentStore: SpreadsheetDocumentStore? {
    get { self[DocumentStoreFocusedValueKey.self] }
    set { self[DocumentStoreFocusedValueKey.self] = newValue }
  }
}
