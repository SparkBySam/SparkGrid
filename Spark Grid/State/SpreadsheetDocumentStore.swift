import AppKit
import Foundation
import Observation
import SparkGridCore
import UniformTypeIdentifiers

@Observable
@MainActor
final class SpreadsheetDocumentStore {
  var document = SpreadsheetDocument()
  /// Live grid view model for the open window; used by print and menu commands.
  var activeViewModel: SpreadsheetViewModel?

  /// The window's view model. Created once and kept across dirty and title updates.
  func attachedViewModel() -> SpreadsheetViewModel {
    if let activeViewModel { return activeViewModel }
    let created = SpreadsheetViewModel(workbook: document.workbook)
    activeViewModel = created
    return created
  }
  var fileURL: URL?
  @ObservationIgnored private var recoveryWriteInFlight = false
  @ObservationIgnored private var recoveryNeedsRewrite = false
  /// Main-thread hook once the active sheet can be drawn. The other sheets may still be loading.
  var onActiveSheetReady: ((Workbook) -> Void)?
  /// True while sheets after the active one are still being read. Edits stay on the grid.
  private(set) var isLoadingRemainder = false
  /// Bumped when a file load or new document replaces the workbook. Not an edit.
  private(set) var externalWorkbookToken: UInt64 = 0
  private(set) var isDirty = false
  private(set) var isAutosaving = false

  /// Edits since the last load, save, or new document. Not a content hash.
  private var changeCount: UInt64 = 0
  private var savedChangeCount: UInt64 = 0
  /// Grid whose `editStamp` has been adopted. A replacement grid is a new baseline.
  private weak var observedViewModel: SpreadsheetViewModel?
  private var observedEditStamp: UInt64 = 0
  private var autosaveTask: Task<Void, Never>?
  private var isForceClosing = false
  /// Export and file write already running off the current frame.
  private var saveInFlight = false
  private var inFlightChangeCount: UInt64 = 0
  private var inFlightWorkbookToken: UInt64 = 0
  private var queuedSave: WorkbookSaveSnapshot?
  private var queuedSaveReportsErrors = false
  /// Quit asked to terminate while a save was still writing.
  private var waitingToTerminate = false
  /// Close asked to dismiss this window once the save in flight finishes.
  private weak var windowWaitingForSave: NSWindow?
  /// Quit delivers `applicationShouldTerminate` and `windowShouldClose` for the same close.
  /// The second call reuses this answer so the save prompt appears once.
  private var answeredCloseAttempt: Bool?
  #if DEBUG
    /// BugBash sets this to count the save prompt without a modal alert.
    var unsavedPromptTestAnswer: UnsavedPromptTestAnswer?
    private(set) var unsavedPromptCount = 0

    enum UnsavedPromptTestAnswer {
      case save, discard, cancel
    }
  #endif

  var displayTitle: String {
    let base = fileURL?.lastPathComponent ?? "Untitled"
    return isDirty ? "\(base) — Edited" : base
  }

  var hasOpenFile: Bool { fileURL != nil }

  var hasMultipleSheets: Bool {
    document.workbook.sheets.count > 1
  }

  var isXLSXFile: Bool {
    guard let fileURL else { return false }
    return fileURL.pathExtension.lowercased() == "xlsx"
  }

  func newDocument() {
    guard confirmReplaceCurrentDocument() else { return }
    document = SpreadsheetDocument()
    fileURL = nil
    externalWorkbookToken &+= 1
    markClean()
    isAutosaving = false
    isForceClosing = false
    let generation = fileURL
    DispatchQueue.main.async { [weak self] in
      guard let self, self.fileURL == generation else { return }
      self.markClean()
    }
  }

  /// Imports every sheet before returning. The first paint must not run while
  /// another sheet is still absent, or cross-sheet formulas show `#REF!` and a
  /// tile thread can read column offsets for the wrong sheet.
  func load(from url: URL, finishesInBackground: Bool = true) throws {
    _ = finishesInBackground
    guard confirmReplaceCurrentDocument() else { return }
    let accessing = url.startAccessingSecurityScopedResource()
    defer {
      if accessing {
        url.stopAccessingSecurityScopedResource()
      }
    }

    let loading = WorkbookLoadingWindow(filename: url.lastPathComponent)
    var closedLoading = false
    func closeLoading() {
      if closedLoading { return }
      closedLoading = true
      loading.close()
    }
    defer { closeLoading() }
    RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))

    final class Box: @unchecked Sendable {
      var document: SpreadsheetDocument?
      var error: Error?
    }
    let box = Box()
    let group = DispatchGroup()
    group.enter()
    DispatchQueue.global(qos: .userInitiated).async {
      defer { group.leave() }
      do {
        let data = try Data(contentsOf: url)
        if Self.opensAsWorkbook(data, url: url) {
          box.document = SpreadsheetDocument(workbook: try XLSXCodec.importWorkbook(from: data))
        } else {
          box.document = try SpreadsheetDocument.load(from: url)
        }
      } catch {
        box.error = error
      }
    }
    while group.wait(timeout: .now()) == .timedOut {
      RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
    }
    if let error = box.error, box.document == nil {
      isLoadingRemainder = false
      throw error
    }
    guard let loaded = box.document else {
      isLoadingRemainder = false
      throw box.error ?? CocoaError(.fileReadUnknown)
    }
    isLoadingRemainder = false
    document = loaded
    fileURL = url
    externalWorkbookToken &+= 1
    markClean()
    isAutosaving = false
    noteRecent(url)
    onActiveSheetReady?(loaded.workbook)
    let loadedURL = url
    DispatchQueue.main.async { [weak self] in
      guard let self, self.fileURL == loadedURL else { return }
      self.markClean()
    }
  }

  private static func opensAsWorkbook(_ data: Data, url: URL) -> Bool {
    let ext = url.pathExtension.lowercased()
    if ext == "xlsx" || ext == "xlsm" { return true }
    return data.starts(with: [0x50, 0x4B, 0x03, 0x04])
      || data.starts(with: [0x50, 0x4B, 0x05, 0x06])
  }

  /// Copies the workbook and starts the write. The window returns before the export finishes.
  func save(to url: URL? = nil) throws {
    guard let snapshot = makeSaveSnapshot(to: url) else { return }
    enqueueBackgroundWrite(snapshot, reportErrors: true)
  }

  /// Direct workbook writes that do not go through the live grid (tests).
  func noteEdit() {
    changeCount &+= 1
    isDirty = true
    scheduleCrashRecovery()
  }

  func documentDidChange() {
    adoptAttachedEdits()
    let dirty = computeDirtyState()
    guard dirty != isDirty else { return }
    isDirty = dirty
  }

  func autosaveIfNeeded() {
    guard AppSettings.shared.autosaveEnabled, fileURL != nil, isDirty else { return }
    performAutosave()
  }

  /// Quit and the last window. A save already in flight keeps the process until the file is written.
  func terminationReply() -> NSApplication.TerminateReply {
    guard attemptClose() else { return .terminateCancel }
    if saveInFlight || queuedSave != nil, !discardsPendingAutosave {
      waitingToTerminate = true
      return .terminateLater
    }
    return .terminateNow
  }

  /// The close button stays interactive while an export finishes, then dismisses the window.
  /// Quit already deferred termination, so that close may proceed without waiting on this frame.
  func allowWindowToClose(_ window: NSWindow) -> Bool {
    guard attemptClose() else { return false }
    if waitingToTerminate { return true }
    if saveInFlight || queuedSave != nil, !discardsPendingAutosave {
      windowWaitingForSave = window
      return false
    }
    return true
  }

  /// Don't Save was chosen and only an autosave is running. Quitting does not wait for it: the
  /// write is atomic, so a stopped autosave leaves the last complete save on disk.
  private var discardsPendingAutosave: Bool {
    isForceClosing && isAutosaving && queuedSave == nil
  }

  /// Prompts to save when closing with unsaved changes. Returns whether the app may close.
  /// A second call in the same quit reuses the first answer instead of asking again.
  @discardableResult
  func attemptClose() -> Bool {
    if isForceClosing { return true }
    if let answeredCloseAttempt { return answeredCloseAttempt }
    let allowed: Bool
    switch askToSaveUnsavedChanges() {
    case nil:
      allowed = true
    case .save:
      allowed = saveInteractively()
    case .discard:
      isForceClosing = true
      allowed = true
    case .cancel:
      allowed = false
    }
    answeredCloseAttempt = allowed
    DispatchQueue.main.async { [weak self] in
      self?.answeredCloseAttempt = nil
    }
    return allowed
  }

  @discardableResult
  func saveInteractively() -> Bool {
    SpreadsheetEditorFlush.commitForSave()
    if fileURL == nil && document.workbook.isEffectivelyEmpty {
      return true
    }

    if let url = fileURL {
      if !isXLSXFile, hasMultipleSheets, !confirmActiveSheetOnlySave() {
        return false
      }
      do {
        try save(to: url)
        return true
      } catch {
        presentSaveError(error)
        return false
      }
    }

    let panel = NSSavePanel()
    panel.allowedContentTypes = [.spreadsheetML, .commaSeparatedText]
    panel.nameFieldStringValue = suggestedSaveFilename()
    panel.canCreateDirectories = true
    panel.allowsOtherFileTypes = false
    panel.isExtensionHidden = false
    panel.title = "Save Spreadsheet"
    panel.message =
      "Choose Excel Workbook (.xlsx) to keep all sheets, or CSV for the active sheet only."
    guard panel.runModal() == .OK, let url = panel.url else { return false }

    if url.pathExtension.lowercased() != "xlsx", hasMultipleSheets, !confirmActiveSheetOnlySave() {
      return false
    }

    do {
      try save(to: url)
      return true
    } catch {
      presentSaveError(error)
      return false
    }
  }

  func restartAutosave() {
    autosaveTask?.cancel()
    autosaveTask = nil
    guard AppSettings.shared.autosaveEnabled else { return }

    autosaveTask = Task { [weak self] in
      while !Task.isCancelled {
        let interval = max(5, AppSettings.shared.autosaveIntervalSeconds)
        try? await Task.sleep(for: .seconds(interval))
        guard !Task.isCancelled else { return }
        await self?.performAutosave()
      }
    }
  }

  func stopAutosave() {
    autosaveTask?.cancel()
    autosaveTask = nil
  }

  // MARK: - Private

  private enum UnsavedChangesChoice {
    case save
    case discard
    case cancel
  }

  /// Same dialog quit uses. Nil when there is nothing unsaved.
  /// An in-progress cell edit is committed first so it counts as a change.
  private func askToSaveUnsavedChanges() -> UnsavedChangesChoice? {
    SpreadsheetEditorFlush.commitForSave()
    if let viewModel = activeViewModel {
      viewModel.syncAutoFilterToActiveSheet()
      document.workbook = viewModel.workbook
    }
    documentDidChange()
    guard isDirty, !unfinishedSaveCoversCurrentChanges() else { return nil }
    return promptForUnsavedChanges()
  }

  /// New, Open, and a Finder open. Cancel leaves the current workbook in place.
  private func confirmReplaceCurrentDocument() -> Bool {
    if isForceClosing { return true }
    switch askToSaveUnsavedChanges() {
    case nil, .discard:
      return true
    case .save:
      return saveInteractively()
    case .cancel:
      return false
    }
  }

  private func promptForUnsavedChanges() -> UnsavedChangesChoice {
    #if DEBUG
      unsavedPromptCount += 1
      if let unsavedPromptTestAnswer {
        switch unsavedPromptTestAnswer {
        case .save: return .save
        case .discard: return .discard
        case .cancel: return .cancel
        }
      }
    #endif
    let alert = NSAlert()
    alert.messageText = "Do you want to save the changes you made?"
    let documentName = fileURL?.lastPathComponent ?? "Untitled"
    alert.informativeText = "Your changes to \"\(documentName)\" will be lost if you don't save."
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Save")
    alert.addButton(withTitle: "Don't Save")
    alert.addButton(withTitle: "Cancel")

    switch alert.runModal() {
    case .alertFirstButtonReturn:
      return .save
    case .alertSecondButtonReturn:
      return .discard
    default:
      return .cancel
    }
  }

  private func performAutosave() {
    guard AppSettings.shared.autosaveEnabled, fileURL != nil, isDirty, !isAutosaving else { return }
    guard !saveInFlight, queuedSave == nil else { return }
    guard let snapshot = makeSaveSnapshot(to: nil) else { return }
    enqueueBackgroundWrite(snapshot, reportErrors: false)
  }

  /// Workbook copy taken on the main thread. Export and the file write run elsewhere.
  private struct WorkbookSaveSnapshot: Sendable {
    var workbook: Workbook
    var destination: URL
    var xlsx: Bool
    var changeCount: UInt64
    var workbookToken: UInt64
    var accessingSecurityScope: Bool
    var formulaStamp: FormulaSaveStamp
  }

  private func makeSaveSnapshot(to url: URL?) -> WorkbookSaveSnapshot? {
    if let viewModel = activeViewModel {
      viewModel.syncAutoFilterToActiveSheet()
      document.workbook = viewModel.workbook
    }
    documentDidChange()
    let destination = url ?? fileURL
    guard let destination else { return nil }
    let accessing = destination.startAccessingSecurityScopedResource()
    let stamp = activeViewModel?.formulaEngine.formulaSaveStamp() ?? .empty
    return WorkbookSaveSnapshot(
      workbook: document.workbook,
      destination: destination,
      xlsx: destination.pathExtension.lowercased() == "xlsx",
      changeCount: changeCount,
      workbookToken: externalWorkbookToken,
      accessingSecurityScope: accessing,
      formulaStamp: stamp
    )
  }

  /// One write at a time. A newer save replaces the queued snapshot; the window does not wait.
  private func enqueueBackgroundWrite(_ snapshot: WorkbookSaveSnapshot, reportErrors: Bool) {
    if saveInFlight {
      if let queuedSave, queuedSave.accessingSecurityScope {
        queuedSave.destination.stopAccessingSecurityScopedResource()
      }
      queuedSave = snapshot
      queuedSaveReportsErrors = reportErrors
      return
    }
    beginBackgroundWrite(snapshot, reportErrors: reportErrors)
  }

  private func beginBackgroundWrite(_ snapshot: WorkbookSaveSnapshot, reportErrors: Bool) {
    saveInFlight = true
    inFlightChangeCount = snapshot.changeCount
    inFlightWorkbookToken = snapshot.workbookToken
    if !reportErrors {
      isAutosaving = true
    }
    let destination = snapshot.destination
    let generation = snapshot.changeCount
    let workbookToken = snapshot.workbookToken
    let accessingSecurityScope = snapshot.accessingSecurityScope
    Task.detached(priority: reportErrors ? .userInitiated : .utility) {
      var failure: String?
      do {
        try SpreadsheetDocumentStore.write(snapshot)
      } catch {
        failure = error.localizedDescription
      }
      let message = failure
      await MainActor.run { [weak self] in
        guard let self else {
          if accessingSecurityScope {
            destination.stopAccessingSecurityScopedResource()
          }
          return
        }
        self.finishBackgroundWrite(
          destination: destination,
          generation: generation,
          workbookToken: workbookToken,
          accessingSecurityScope: accessingSecurityScope,
          reportErrors: reportErrors,
          failure: message
        )
      }
    }
  }

  private func finishBackgroundWrite(
    destination: URL,
    generation: UInt64,
    workbookToken: UInt64,
    accessingSecurityScope: Bool,
    reportErrors: Bool,
    failure: String?
  ) {
    if accessingSecurityScope {
      destination.stopAccessingSecurityScopedResource()
    }
    let stillThisDocument = externalWorkbookToken == workbookToken
    let superseded = queuedSave != nil
    if let failure {
      if !superseded, reportErrors || waitingToTerminate || windowWaitingForSave != nil {
        presentSaveError(
          NSError(
            domain: "SparkGridSave",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: failure]
          ))
      }
    } else if stillThisDocument, !superseded {
      fileURL = destination
      if changeCount == generation {
        markClean()
      }
      noteRecent(destination)
    }
    saveInFlight = false
    if !reportErrors {
      isAutosaving = false
    }
    if let next = queuedSave {
      let report = queuedSaveReportsErrors
      queuedSave = nil
      beginBackgroundWrite(next, reportErrors: report)
      return
    }
    let savedCurrentDocument = failure == nil && !isDirty
    if waitingToTerminate {
      waitingToTerminate = false
      windowWaitingForSave = nil
      NSApp.reply(toApplicationShouldTerminate: savedCurrentDocument)
      return
    }
    if let window = windowWaitingForSave {
      windowWaitingForSave = nil
      if savedCurrentDocument {
        window.close()
      }
    }
  }

  /// True when the snapshot already running includes every edit now in the document.
  private func unfinishedSaveCoversCurrentChanges() -> Bool {
    let token = externalWorkbookToken
    if saveInFlight, inFlightChangeCount == changeCount, inFlightWorkbookToken == token {
      return true
    }
    if let queuedSave, queuedSave.changeCount == changeCount, queuedSave.workbookToken == token {
      return true
    }
    return false
  }

  nonisolated private static func write(_ snapshot: WorkbookSaveSnapshot) throws {
    try BackgroundWriteGuard.requireBackgroundThread()
    if snapshot.xlsx {
      let workbook = FormulaCacheWriter.prepare(
        snapshot.workbook, stamp: snapshot.formulaStamp)
      let data = try XLSXCodec.exportWorkbook(workbook, includeFormulaCaches: true)
      try data.write(to: snapshot.destination, options: .atomic)
    } else {
      let csv = CSVCodec.exportCSV(from: snapshot.workbook.activeSheet)
      try csv.write(to: snapshot.destination, atomically: true, encoding: .utf8)
    }
  }

  private func markClean() {
    if let viewModel = activeViewModel {
      observedViewModel = viewModel
      observedEditStamp = viewModel.editStamp
    }
    changeCount = 0
    savedChangeCount = 0
    isDirty = false
  }

  /// Counts edit-stamp movement on the attached grid. A new grid is a baseline, not an edit.
  private func adoptAttachedEdits() {
    guard let viewModel = activeViewModel else { return }
    if observedViewModel !== viewModel {
      observedViewModel = viewModel
      observedEditStamp = viewModel.editStamp
      return
    }
    let stamp = viewModel.editStamp
    guard stamp != observedEditStamp else { return }
    if stamp > observedEditStamp {
      changeCount &+= stamp - observedEditStamp
    } else {
      changeCount &+= 1
    }
    observedEditStamp = stamp
    scheduleCrashRecovery()
  }

  private func computeDirtyState() -> Bool {
    changeCount != savedChangeCount
  }

  private var recoveryTask: Task<Void, Never>?

  /// Writes a recovery copy off the main thread after edits. A clean quit deletes it.
  private func scheduleCrashRecovery() {
    if ProcessInfo.processInfo.environment["SPARK_GRID_BENCHMARK"] == "1" { return }
    recoveryTask?.cancel()
    recoveryTask = Task { @MainActor in
      try? await Task.sleep(nanoseconds: 2_000_000_000)
      guard !Task.isCancelled else { return }
      if let viewModel = activeViewModel {
        viewModel.syncAutoFilterToActiveSheet()
        document.workbook = viewModel.workbook
      }
      // One recovery write at a time. Cancelling this task does not stop a write already
      // running, so edits used to stack several full recalculations at once.
      guard !recoveryWriteInFlight else {
        recoveryNeedsRewrite = true
        return
      }
      recoveryWriteInFlight = true
      let workbook = document.workbook
      let stamp = activeViewModel?.formulaEngine.formulaSaveStamp() ?? .empty
      let path = fileURL?.path
      let directory = CrashRecoveryStore.defaultDirectory()
      await Task.detached(priority: .utility) {
        // The copy only has to bring the cells back. When every result is stale (after a sort),
        // recalculating takes seconds to minutes, so the results are left out and a restore
        // calculates them.
        let prepared =
          stamp.recalculateAllFormulas
          ? FormulaCacheWriter.withoutFormulaResults(workbook)
          : FormulaCacheWriter.prepare(workbook, stamp: stamp)
        try? CrashRecoveryStore.write(workbook: prepared, documentPath: path, in: directory)
      }.value
      recoveryWriteInFlight = false
      if recoveryNeedsRewrite {
        recoveryNeedsRewrite = false
        scheduleCrashRecovery()
      }
    }
  }

  func restoreCrashRecovery() throws {
    let loaded = try CrashRecoveryStore.load()
    document = SpreadsheetDocument(workbook: loaded.workbook)
    if let path = loaded.documentPath {
      let url = URL(fileURLWithPath: path)
      if FileManager.default.fileExists(atPath: url.path) {
        fileURL = url
      }
    }
    externalWorkbookToken &+= 1
    markClean()
  }

  private func noteRecent(_ url: URL) {
    NSDocumentController.shared.noteNewRecentDocumentURL(url)
  }

  private func suggestedSaveFilename() -> String {
    if let fileURL {
      return fileURL.lastPathComponent
    }
    let sheetName = document.workbook.activeSheet.name
    return "\(sheetName).xlsx"
  }

  private func confirmActiveSheetOnlySave() -> Bool {
    let sheetName = document.workbook.activeSheet.name
    let alert = NSAlert()
    alert.messageText = "Save Active Sheet Only?"
    alert.informativeText =
      "CSV files contain one sheet. Only \"\(sheetName)\" will be saved; other sheets in this workbook won't be included."
    alert.alertStyle = .informational
    alert.addButton(withTitle: "Save")
    alert.addButton(withTitle: "Cancel")
    return alert.runModal() == .alertFirstButtonReturn
  }

  private func presentOpenError(_ error: Error) {
    let alert = NSAlert()
    alert.messageText = "Couldn't Open Spreadsheet"
    alert.informativeText = error.localizedDescription
    alert.alertStyle = .warning
    alert.runModal()
  }

  private func presentSaveError(_ error: Error) {
    let alert = NSAlert()
    alert.messageText = "Couldn't Save Spreadsheet"
    alert.informativeText = error.localizedDescription
    alert.alertStyle = .warning
    alert.runModal()
  }
}

/// Shown on the main thread while `SpreadsheetDocument.load` runs off it.
private final class WorkbookLoadingWindow {
  private var window: NSWindow?

  init(filename: String) {
    let content = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 64))
    let spinner = NSProgressIndicator(frame: NSRect(x: 18, y: 22, width: 20, height: 20))
    spinner.style = .spinning
    spinner.controlSize = .small
    spinner.startAnimation(nil)
    let label = NSTextField(labelWithString: "Opening \(filename)…")
    label.frame = NSRect(x: 48, y: 22, width: 312, height: 20)
    label.lineBreakMode = .byTruncatingMiddle
    label.font = SparkBrandFonts.body(size: 13, weight: 500)
    label.textColor = SparkTheme.label
    content.addSubview(spinner)
    content.addSubview(label)

    let panel = NSWindow(
      contentRect: content.frame,
      styleMask: [.titled],
      backing: .buffered,
      defer: false
    )
    panel.title = "Opening"
    panel.titlebarAppearsTransparent = true
    panel.backgroundColor = SparkTheme.chrome
    panel.contentView = content
    panel.isReleasedWhenClosed = false
    panel.center()
    panel.orderFrontRegardless()
    panel.displayIfNeeded()
    window = panel
  }

  func close() {
    window?.orderOut(nil)
    window?.close()
    window = nil
  }
}
