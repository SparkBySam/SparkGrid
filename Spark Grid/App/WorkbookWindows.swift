import AppKit
import SparkGridCore
import SwiftUI

/// Every workbook window and the document it shows. Each window has its own store, named by the
/// window's id (the `WindowGroup` value). Opening a file puts it in the front window when that
/// window is an unused blank one, brings forward a window that already has it, and otherwise
/// opens a new window for it.
@MainActor
final class WorkbookWindows {
  static let shared = WorkbookWindows()

  /// What a new window does once its store exists.
  enum Start {
    case blank
    case startScreen
    case open(URL)
  }

  private var stores: [UUID: SpreadsheetDocumentStore] = [:]
  private var windows: [UUID: WeakWindow] = [:]
  private var starts: [UUID: Start] = [:]
  /// Most recent first, so the front window can be found without asking AppKit.
  private var order: [UUID] = []
  /// SwiftUI's action for opening a window, kept from the first window's environment.
  var openWindow: OpenWindowAction?

  private struct WeakWindow {
    weak var window: NSWindow?
  }

  /// The store for a window, made the first time it is asked for.
  func store(for id: UUID) -> SpreadsheetDocumentStore {
    if let store = stores[id] { return store }
    let store = SpreadsheetDocumentStore()
    stores[id] = store
    order.insert(id, at: 0)
    switch starts.removeValue(forKey: id) {
    case .open(let url)?:
      store.showsStartScreen = false
      // After the window is on screen, so an error alert has a window to sit over.
      DispatchQueue.main.async { Self.load(url, into: store) }
    case .startScreen?:
      store.showsStartScreen = true
    case .blank?:
      store.showsStartScreen = false
    case nil:
      // A window the app opened by itself: at launch, as Settings says.
      break
    }
    return store
  }

  /// Takes a store made elsewhere as a window's document (BugBash's quit and close checks).
  func adopt(_ store: SpreadsheetDocumentStore, id: UUID) {
    stores[id] = store
    order.insert(id, at: 0)
  }

  func attach(_ window: NSWindow, to id: UUID) {
    windows[id] = WeakWindow(window: window)
  }

  func closed(_ id: UUID) {
    stores[id]?.stopAutosave()
    stores[id] = nil
    windows[id] = nil
    order.removeAll { $0 == id }
  }

  func becameKey(_ id: UUID) {
    order.removeAll { $0 == id }
    order.insert(id, at: 0)
  }

  /// The store of the window in front, or of the last workbook window that was.
  var frontStore: SpreadsheetDocumentStore? {
    if let key = NSApp.keyWindow, let id = id(of: key), let store = stores[id] { return store }
    return allStores.first
  }

  /// The documents of windows on screen, most recent first. SwiftUI can build a window's view
  /// more than once, for windows it never shows; those stores have no window and do not count.
  var allStores: [SpreadsheetDocumentStore] {
    order.compactMap { id in windows[id]?.window != nil ? stores[id] : nil }
  }

  func store(for window: NSWindow) -> SpreadsheetDocumentStore? {
    id(of: window).flatMap { stores[$0] }
  }

  private func id(of window: NSWindow) -> UUID? {
    windows.first { $0.value.window === window }?.key
  }

  func window(of store: SpreadsheetDocumentStore) -> NSWindow? {
    guard let id = stores.first(where: { $0.value === store })?.key else { return nil }
    return windows[id]?.window
  }

  // MARK: Opening

  /// A store with nothing in it yet: no file, no changes, an empty workbook.
  private static func isUnused(_ store: SpreadsheetDocumentStore) -> Bool {
    store.fileURL == nil && store.importedName == nil && !store.isDirty
      && store.document.workbook.isEffectivelyEmpty
  }

  /// Opens a file: in `preferred` (or the front window) when that is unused, in the window that
  /// already has it, or in a new window.
  func open(_ url: URL, preferring preferred: SpreadsheetDocumentStore? = nil) {
    let standardized = url.standardizedFileURL
    if let existing = allStores.first(where: { $0.fileURL?.standardizedFileURL == standardized }),
      let window = window(of: existing)
    {
      window.makeKeyAndOrderFront(nil)
      return
    }
    if let target = preferred ?? frontStore, Self.isUnused(target) {
      Self.load(url, into: target)
      return
    }
    newWindow(.open(url))
  }

  func newWindow(_ start: Start = .blank) {
    let id = UUID()
    starts[id] = start
    if let openWindow {
      openWindow(id: "workbook", value: id)
    } else {
      starts[id] = nil
    }
  }

  private static func load(_ url: URL, into store: SpreadsheetDocumentStore) {
    do {
      try store.load(from: url)
    } catch {
      let alert = NSAlert()
      alert.messageText = "Couldn't Open \u{201C}\(url.lastPathComponent)\u{201D}"
      alert.informativeText = error.localizedDescription
      alert.alertStyle = .warning
      alert.addButton(withTitle: "OK")
      alert.runModal()
    }
  }

  // MARK: Quitting

  private var quitWaitingOn = 0
  private var quitSucceeded = true

  /// Asks each window with unsaved changes in turn, front first. Cancel in any stops the quit.
  /// Saves still being written are waited for, all of them, before the app quits.
  func terminationReply() -> NSApplication.TerminateReply {
    var later: [SpreadsheetDocumentStore] = []
    for store in allStores {
      if store.isDirty, let window = window(of: store) {
        window.makeKeyAndOrderFront(nil)
      }
      switch store.terminationReply() {
      case .terminateCancel:
        return .terminateCancel
      case .terminateLater:
        later.append(store)
      default:
        break
      }
    }
    guard !later.isEmpty else { return .terminateNow }
    quitWaitingOn = later.count
    quitSucceeded = true
    for store in later {
      store.onTerminationSaveFinished = { [weak self] succeeded in
        guard let self else { return }
        self.quitSucceeded = self.quitSucceeded && succeeded
        self.quitWaitingOn -= 1
        if self.quitWaitingOn == 0 {
          NSApp.reply(toApplicationShouldTerminate: self.quitSucceeded)
        }
      }
    }
    return .terminateLater
  }
}

/// Tells `WorkbookWindows` which window a workbook view is in, and when that window becomes key.
struct WorkbookWindowBinder: NSViewRepresentable {
  let id: UUID

  func makeNSView(context: Context) -> BinderView {
    let view = BinderView()
    view.id = id
    return view
  }

  func updateNSView(_ view: BinderView, context: Context) {
    view.id = id
  }

  final class BinderView: NSView {
    var id: UUID?
    private var observer: NSObjectProtocol?

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      if let observer { NotificationCenter.default.removeObserver(observer) }
      observer = nil
      guard let window, let id else { return }
      // Not brought back at launch: its file could not be reopened without being chosen again.
      window.isRestorable = false
      WorkbookWindows.shared.attach(window, to: id)
      observer = NotificationCenter.default.addObserver(
        forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
      ) { _ in
        MainActor.assumeIsolated { WorkbookWindows.shared.becameKey(id) }
      }
    }

    deinit {
      if let observer { NotificationCenter.default.removeObserver(observer) }
    }
  }
}
