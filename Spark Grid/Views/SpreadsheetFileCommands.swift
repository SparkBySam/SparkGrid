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
      .keyboardShortcut("n", modifiers: .command)

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
      .keyboardShortcut("n", modifiers: [.command, .shift])
      .disabled(store?.showsStartScreen == true)
    }

    CommandGroup(after: .newItem) {
      Button("Open…") {
        SpreadsheetOpenPanel.run(preferring: store)
      }
      .keyboardShortcut("o", modifiers: .command)

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
      .keyboardShortcut("s", modifiers: [.command, .shift])
      .disabled(store == nil)

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
    panel.allowedContentTypes = [.spreadsheetML, .commaSeparatedText]
    let baseName =
      store.fileURL?.deletingPathExtension().lastPathComponent
      ?? store.document.workbook.activeSheet.name
    // A CSV stays a CSV unless the person picks .xlsx (a Reddit note, Nov 19); everything else
    // defaults to .xlsx so formatting, rules and filters survive.
    let keepsCSV = store.fileURL?.pathExtension.lowercased() == "csv"
    panel.nameFieldStringValue = "\(baseName).\(keepsCSV ? "csv" : "xlsx")"
    panel.canCreateDirectories = true
    panel.isExtensionHidden = false
    if #available(macOS 15.0, *) {
      panel.currentContentType = keepsCSV ? .commaSeparatedText : .spreadsheetML
    }
    guard panel.runModal() == .OK, let url = panel.url else { return }
    let destination = normalizedSaveURL(url, panel: panel)
    if destination.pathExtension.lowercased() != "xlsx",
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
