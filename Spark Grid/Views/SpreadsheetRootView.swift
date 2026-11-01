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
private struct SpreadsheetWindowTitle: View {
  @Bindable var store: SpreadsheetDocumentStore

  var body: some View {
    Color.clear
      .frame(width: 0, height: 0)
      .onAppear {
        WindowTitleUpdater.apply(title: store.displayTitle)
      }
      .onChange(of: store.displayTitle) { _, title in
        WindowTitleUpdater.apply(title: title)
      }
      .onChange(of: store.isDirty) { _, _ in
        WindowTitleUpdater.apply(title: store.displayTitle)
      }
  }
}

#Preview {
  SpreadsheetRootView(store: SpreadsheetDocumentStore())
}
