import AppKit
import SparkGridCore
import SwiftUI
import UniformTypeIdentifiers

struct SpreadsheetFileCommands: Commands {
  @Bindable var store: SpreadsheetDocumentStore
  @Bindable private var settings = AppSettings.shared

  var body: some Commands {
    CommandGroup(replacing: .newItem) {
      Button("New Spreadsheet") {
        store.newDocument()
      }
      .keyboardShortcut("n", modifiers: .command)
    }

    CommandGroup(after: .newItem) {
      Button("Open…") {
        openPanel()
      }
      .keyboardShortcut("o", modifiers: .command)

      Button("Save") {
        _ = store.saveInteractively()
      }
      .keyboardShortcut(
        settings.keyEquivalent(for: .save), modifiers: settings.eventModifiers(for: .save)
      )
      .disabled(store.fileURL == nil && store.document.workbook.isEffectivelyEmpty)

      Button("Save As…") {
        saveAsPanel()
      }
      .keyboardShortcut("s", modifiers: [.command, .shift])
    }
  }

  private func openPanel() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.spreadsheetML, .commaSeparatedText, .plainText]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    guard panel.runModal() == .OK, let url = panel.url else { return }
    try? store.load(from: url)
  }

  private func saveAsPanel() {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.spreadsheetML, .commaSeparatedText]
    let baseName =
      store.fileURL?.deletingPathExtension().lastPathComponent
      ?? store.document.workbook.activeSheet.name
    // Default to Excel so formatting/CF/filters survive round-trip.
    panel.nameFieldStringValue = "\(baseName).xlsx"
    panel.canCreateDirectories = true
    panel.isExtensionHidden = false
    if #available(macOS 15.0, *) {
      panel.currentContentType = .spreadsheetML
    }
    guard panel.runModal() == .OK, let url = panel.url else { return }
    let destination = normalizedSaveURL(url, panel: panel)
    if destination.pathExtension.lowercased() != "xlsx",
      store.hasMultipleSheets,
      !confirmCSVOnly()
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

  private func confirmCSVOnly() -> Bool {
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
