import AppKit
import SparkGridCore
import SwiftUI

/// Intercepts `print:` in the responder chain for SwiftUI apps that don't adopt NSDocument printing.
private final class PrintingResponder: NSResponder {
  weak var appDelegate: SparkGridAppDelegate?

  @objc func print(_ sender: Any?) {
    appDelegate?.printDocument(sender)
  }
}

private struct SparkGridAppDelegateKey: EnvironmentKey {
  static let defaultValue: SparkGridAppDelegate? = nil
}

extension EnvironmentValues {
  var sparkGridAppDelegate: SparkGridAppDelegate? {
    get { self[SparkGridAppDelegateKey.self] }
    set { self[SparkGridAppDelegateKey.self] = newValue }
  }
}

final class SparkGridAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
  static weak var current: SparkGridAppDelegate?
  var onOpenFile: ((URL) -> Void)? {
    didSet { flushPendingOpenURL() }
  }
  weak var documentStore: SpreadsheetDocumentStore? {
    didSet { flushPendingOpenURL() }
  }
  var spreadsheetViewModel: SpreadsheetViewModel?
  private var pendingOpenURL: URL?

  private var printingResponder: PrintingResponder?
  private var printKeyMonitor: Any?
  private var saveKeyMonitor: Any?
  private lazy var cellFieldEditor: CellFieldEditor = {
    let editor = CellFieldEditor()
    editor.isFieldEditor = true
    return editor
  }()

  /// Files opened from Finder or `open` after launch arrive as an Apple Event. SwiftUI's own
  /// handler closed the spreadsheet window to open the file in a new one; with a single window,
  /// that quit the app. Once the window is up, the event comes here instead and the file opens
  /// in the window that is there. A file the app is launched with still goes through SwiftUI,
  /// which opens the window for it.
  private func takeOverOpenDocumentsEvent() {
    NSAppleEventManager.shared().setEventHandler(
      self,
      andSelector: #selector(handleOpenDocuments(_:withReply:)),
      forEventClass: AEEventClass(kCoreEventClass),
      andEventID: AEEventID(kAEOpenDocuments))
  }

  @objc private func handleOpenDocuments(
    _ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor
  ) {
    guard let list = event.paramDescriptor(forKeyword: keyDirectObject) else { return }
    var urls: [URL] = []
    if list.numberOfItems == 0, let url = list.fileURLValue {
      urls.append(url)
    } else if list.numberOfItems > 0 {
      for index in 1...list.numberOfItems {
        if let url = list.atIndex(index)?.fileURLValue { urls.append(url) }
      }
    }
    application(NSApp, open: urls)
  }

  func application(_ application: NSApplication, open urls: [URL]) {
    guard let url = urls.first else { return }
    openExternalFile(url)
  }

  private func openExternalFile(_ url: URL) {
    if let onOpenFile {
      onOpenFile(url)
    } else if let documentStore {
      do {
        try documentStore.load(from: url)
      } catch {
        pendingOpenURL = url
        let alert = NSAlert()
        alert.messageText = "Couldn't Open File"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
      }
    } else {
      pendingOpenURL = url
    }
  }

  private func flushPendingOpenURL() {
    guard let pending = pendingOpenURL else { return }
    if let onOpenFile {
      pendingOpenURL = nil
      onOpenFile(pending)
    } else if let documentStore {
      pendingOpenURL = nil
      do {
        try documentStore.load(from: pending)
      } catch {
        let alert = NSAlert()
        alert.messageText = "Couldn't Open File"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
      }
    }
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    Self.current = self
    takeOverOpenDocumentsEvent()
    installPrintKeyMonitor()
    installSaveKeyMonitor()
    configureMainWindow()
    configurePrintMenu()
  }

  func windowWillReturnFieldEditor(_ sender: NSWindow, to client: Any?) -> Any? {
    guard client is CellEditorTextField else { return nil }
    return cellFieldEditor
  }

  func applicationDidBecomeActive(_ notification: Notification) {
    configureMainWindow()
    configurePrintMenu()
  }

  func offerCrashRecoveryIfNeeded() {
    if ProcessInfo.processInfo.environment["SPARK_GRID_BENCHMARK"] == "1" { return }
    if CrashRecoveryStore.needsRestore() {
      let alert = NSAlert()
      alert.messageText = "Restore unsaved work?"
      alert.informativeText =
        "Spark Grid did not shut down cleanly. A recovery copy of the last edited workbook is available."
      alert.alertStyle = .warning
      alert.addButton(withTitle: "Restore")
      alert.addButton(withTitle: "Don't Restore")
      if alert.runModal() == .alertFirstButtonReturn {
        do {
          try documentStore?.restoreCrashRecovery()
          CrashRecoveryStore.clear()
        } catch {
          let failed = NSAlert()
          failed.messageText = "Couldn't Restore"
          failed.informativeText = error.localizedDescription
          failed.alertStyle = .warning
          failed.addButton(withTitle: "OK")
          failed.runModal()
        }
      } else {
        CrashRecoveryStore.clear()
      }
    }
    try? CrashRecoveryStore.beginSession()
  }

  func applicationWillTerminate(_ notification: Notification) {
    CrashRecoveryStore.noteCleanExit()
    if let printKeyMonitor {
      NSEvent.removeMonitor(printKeyMonitor)
      self.printKeyMonitor = nil
    }
    if let saveKeyMonitor {
      NSEvent.removeMonitor(saveKeyMonitor)
      self.saveKeyMonitor = nil
    }
  }

  private func installSaveKeyMonitor() {
    guard saveKeyMonitor == nil else { return }
    saveKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      guard AppSettings.shared.matches(.save, event: event) else { return event }
      // Leave save panels and alerts in control of their own keys.
      if NSApp.modalWindow != nil { return event }
      // Only eat the key when Save actually runs. Otherwise the File menu handles it.
      guard SparkGridSaveShortcut.perform() else { return event }
      return nil
    }
  }

  private func installPrintKeyMonitor() {
    guard printKeyMonitor == nil else { return }
    printKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self else { return event }
      guard event.modifierFlags.contains(.command),
        !event.modifierFlags.contains(.shift),
        !event.modifierFlags.contains(.option),
        event.charactersIgnoringModifiers?.lowercased() == "p"
      else {
        return event
      }
      self.printDocument(nil)
      return nil
    }
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard let documentStore else { return .terminateNow }
    return documentStore.terminationReply()
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    // Settings and other windows close on their own. Only the spreadsheet window asks to save,
    // and closing it closes the document; Settings used to take that path and quit the app.
    guard sender.identifier?.rawValue.hasPrefix("main") == true, let documentStore else {
      return true
    }
    return documentStore.allowWindowToClose(sender)
  }

  func resolvedSpreadsheetViewModel() -> SpreadsheetViewModel? {
    if let spreadsheetViewModel { return spreadsheetViewModel }
    guard let documentStore else { return nil }
    if let activeViewModel = documentStore.activeViewModel { return activeViewModel }
    return SpreadsheetViewModel(workbook: documentStore.document.workbook)
  }

  func registerSpreadsheetViewModel(
    _ viewModel: SpreadsheetViewModel, store: SpreadsheetDocumentStore
  ) {
    spreadsheetViewModel = viewModel
    documentStore = store
    store.activeViewModel = viewModel
  }

  func unregisterSpreadsheetViewModel(
    _ viewModel: SpreadsheetViewModel, store: SpreadsheetDocumentStore
  ) {
    if spreadsheetViewModel === viewModel {
      spreadsheetViewModel = nil
    }
    if store.activeViewModel === viewModel {
      store.activeViewModel = nil
    }
  }

  @objc func print(_ sender: Any?) {
    printDocument(sender)
  }

  @objc func printDocument(_ sender: Any?) {
    guard let spreadsheetViewModel = resolvedSpreadsheetViewModel() else {
      let alert = NSAlert()
      alert.messageText = "Can’t Print"
      alert.informativeText = "Open a spreadsheet window before printing."
      alert.alertStyle = .warning
      alert.addButton(withTitle: "OK")
      alert.runModal()
      return
    }
    SpreadsheetPrintController.printActiveSheet(
      from: spreadsheetViewModel,
      in: NSApp.keyWindow ?? NSApp.mainWindow
    )
  }

  private func configureMainWindow() {
    for window in NSApp.windows where window.canBecomeMain {
      if window.delegate !== self {
        window.delegate = self
      }
      installPrintingResponder(in: window)
      if window.identifier?.rawValue.hasPrefix("main") == true {
        // The title bar takes the toolbar's ground, so dark mode is one warm graphite band.
        window.titlebarAppearsTransparent = true
        window.backgroundColor = SparkTheme.chrome
      }
    }
  }

  private func installPrintingResponder(in window: NSWindow) {
    if printingResponder == nil {
      let responder = PrintingResponder()
      responder.appDelegate = self
      printingResponder = responder
    }
    guard let printingResponder, window.nextResponder !== printingResponder else { return }
    printingResponder.nextResponder = window.nextResponder
    window.nextResponder = printingResponder
  }

  private func configurePrintMenu() {
    guard let mainMenu = NSApp.mainMenu else { return }
    for menuItem in mainMenu.items {
      guard let submenu = menuItem.submenu else { continue }
      for item in submenu.items {
        let isPrintKey =
          item.keyEquivalent == "p"
          && item.keyEquivalentModifierMask.contains(.command)
          && !item.keyEquivalentModifierMask.contains(.shift)
          && !item.keyEquivalentModifierMask.contains(.option)
          && !item.keyEquivalentModifierMask.contains(.control)
        let isPrintAction =
          item.action == Selector("print:")
          || item.action == #selector(printDocument(_:))
          || item.action == #selector(print(_:))
          || item.title == "Print…"
          || item.title == "Print..."
        guard isPrintKey || isPrintAction else { continue }
        item.target = self
        item.action = #selector(printDocument(_:))
      }
    }
  }
}
