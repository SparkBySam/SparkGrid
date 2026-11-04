import AppKit
import SparkGridCore
import SwiftUI

struct SpreadsheetRootView: View {
  @Bindable var store: SpreadsheetDocumentStore
  @Bindable private var settings = AppSettings.shared
  @State private var showAbout = false

  var body: some View {
    SpreadsheetWindowView(store: store) {
      store.documentDidChange()
    }
    .id(store.fileURL?.absoluteString ?? "untitled")
    .preferredColorScheme(settings.appearanceMode.colorScheme)
    .aboutPanel(isPresented: $showAbout)
    .onReceive(NotificationCenter.default.publisher(for: AppUINotifications.showAbout)) { _ in
      showAbout = true
    }
    .background {
      SpreadsheetWindowTitle(store: store)
    }
    .onChange(of: settings.autosaveEnabled) { _, _ in
      store.restartAutosave()
    }
    .onChange(of: settings.autosaveIntervalSeconds) { _, _ in
      store.restartAutosave()
    }
  }
}

/// Title updates live here so the root view does not refresh when dirty state changes.
/// The title goes on this document's own window, which may not be the one in front: a file
/// opened in the background, or one of several open documents.
private struct SpreadsheetWindowTitle: View {
  @Bindable var store: SpreadsheetDocumentStore

  var body: some View {
    WindowTitleSetter(title: store.displayTitle)
      .frame(width: 0, height: 0)
  }
}

private struct WindowTitleSetter: NSViewRepresentable {
  let title: String

  func makeNSView(context: Context) -> TitleView { TitleView() }

  func updateNSView(_ view: TitleView, context: Context) {
    view.title = title
    view.apply()
  }

  final class TitleView: NSView {
    var title = ""

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      apply()
    }

    func apply() {
      guard let window, window.title != title else { return }
      window.title = title
    }
  }
}

#Preview {
  SpreadsheetRootView(store: SpreadsheetDocumentStore())
}
