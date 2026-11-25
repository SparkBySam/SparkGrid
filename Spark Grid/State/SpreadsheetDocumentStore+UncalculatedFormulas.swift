import AppKit
import SparkGridCore
import UniformTypeIdentifiers

/// After a file opens, says so if its formulas call functions Spark Grid does not have: which
/// ones, what that means for those cells, and a way to keep a copy of the file as it is (a Reddit
/// comment, Nov 20: "Worst thing for a spreadsheet user is breaking it without knowing").
extension SpreadsheetDocumentStore {
  /// Scripted runs (the bug test, benchmarks, unit tests) open files without anyone to read it.
  nonisolated static var isAutomatedRun: Bool {
    let environment = ProcessInfo.processInfo.environment
    return environment["SPARK_GRID_BUG_BASH"] == "1" || environment["SPARK_GRID_BENCHMARK"] == "1"
      || environment["XCTestConfigurationFilePath"] != nil
  }

  /// Looks for the functions off the main thread, then shows the note on the window.
  func checkForUncalculatedFormulas(in workbook: Workbook, from url: URL, imported: Bool) {
    guard AppSettings.shared.warnsAboutUncalculatedFormulas, !Self.isAutomatedRun else { return }
    let token = externalWorkbookToken
    Task.detached(priority: .utility) { [weak self] in
      let uses = UnknownFunctions.uses(in: workbook)
      guard !uses.isEmpty else { return }
      await MainActor.run { [weak self] in
        guard let self, self.externalWorkbookToken == token else { return }
        self.presentUncalculatedFormulas(uses, from: url, imported: imported)
      }
    }
  }

  private func presentUncalculatedFormulas(
    _ uses: [UnknownFunctions.Use], from url: URL, imported: Bool
  ) {
    guard let window = WorkbookWindows.shared.window(of: self) else { return }
    let kind: UncalculatedFormulasSheet.FileKind =
      Self.isPlainText(url) ? .plainText : (imported ? .imported : .saved)
    SparkDialogPresenter.present(title: "Functions", width: 420, in: window) { close in
      UncalculatedFormulasSheet(
        uses: uses,
        fileName: url.lastPathComponent,
        showsSheetNames: document.workbook.sheets.count > 1,
        kind: kind,
        onShow: { [weak self] use in
          close()
          self?.showCell(use)
        },
        onSaveCopy: { [weak self] in
          close()
          // After the sheet is gone, so the save panel can take its place on the window.
          DispatchQueue.main.async { self?.saveCopyOfOriginal(url, in: window) }
        },
        onDone: { dontTellAgain in
          if dontTellAgain { AppSettings.shared.warnsAboutUncalculatedFormulas = false }
          close()
        })
    }
  }

  /// CSV and other text files keep formulas as text and no results.
  static func isPlainText(_ url: URL) -> Bool {
    ["csv", "tsv", "txt", "tab"].contains(url.pathExtension.lowercased())
  }

  private func showCell(_ use: UnknownFunctions.Use) {
    guard let viewModel = activeViewModel,
      let index = viewModel.workbook.sheets.firstIndex(where: { $0.name == use.sheet })
    else { return }
    if index != viewModel.workbook.activeSheetIndex { viewModel.selectSheet(at: index) }
    viewModel.selection = use.address
    // Scrolled to, as Go To does: it was selected off screen (Sam's test, Nov 20).
    viewModel.scrollRequestToken &+= 1
    viewModel.notifyGridRefresh()
  }

  /// Copies the file as it is on disk, before any change here is saved, to a place the person
  /// picks.
  private func saveCopyOfOriginal(_ url: URL, in window: NSWindow) {
    let panel = NSSavePanel()
    let ext = url.pathExtension
    panel.nameFieldStringValue =
      url.deletingPathExtension().lastPathComponent + " (original)" + (ext.isEmpty ? "" : ".\(ext)")
    if let type = UTType(filenameExtension: ext) { panel.allowedContentTypes = [type] }
    panel.canCreateDirectories = true
    // Beside the file it copies.
    panel.directoryURL = url.deletingLastPathComponent()
    panel.message = "Keep a copy of the file as it was when you opened it."
    panel.beginSheetModal(for: window) { response in
      guard response == .OK, let destination = panel.url else { return }
      let reading = url.startAccessingSecurityScopedResource()
      defer { if reading { url.stopAccessingSecurityScopedResource() } }
      do {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
          try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: url, to: destination)
      } catch {
        let failed = NSAlert(error: error)
        failed.messageText = "Couldn't save the copy"
        failed.beginSheetModal(for: window)
      }
    }
  }
}
