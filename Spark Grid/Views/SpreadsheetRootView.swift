import AppKit
import SparkGridCore
import SwiftUI

struct SpreadsheetRootView: View {
  @Bindable var store: SpreadsheetDocumentStore
  @Bindable private var settings = AppSettings.shared
  @State private var showAbout = false

  var body: some View {
    ZStack {
      SpreadsheetWindowView(store: store) {
        store.documentDidChange()
      }
      .id(store.fileURL?.absoluteString ?? "untitled")
      .accessibilityHidden(store.showsStartScreen && !store.startScreenReturnsToDocument)
      // At launch the start screen covers the blank workbook it gives way to.
      if store.showsStartScreen && !store.startScreenReturnsToDocument {
        StartScreenView(store: store)
      }
      // Close and Quit wait for a big workbook's save to finish; without a sign the window
      // looked stuck for several seconds (Sam, Nov 19).
      if store.isSavingBeforeClosing {
        SavingBeforeClosingBadge(name: store.fileURL?.lastPathComponent ?? store.displayTitle)
      }
    }
    .sheet(isPresented: startScreenSheet) {
      StartScreenView(store: store, isSheet: true)
        .frame(width: 1040, height: 700)
    }
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

  /// From File > New from Template over an open workbook.
  private var startScreenSheet: Binding<Bool> {
    Binding(
      get: { store.showsStartScreen && store.startScreenReturnsToDocument },
      set: { if !$0 { store.dismissStartScreen() } })
  }
}

/// "Saving…" in the middle of the window while Close or Quit waits for the file to be written.
private struct SavingBeforeClosingBadge: View {
  let name: String

  var body: some View {
    VStack(spacing: 10) {
      ProgressView().controlSize(.regular)
      Text("Saving \u{201C}\(name)\u{201D}…")
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(SparkStyle.label)
      Text("The window closes when the file is written.")
        .font(.system(size: 11))
        .foregroundStyle(SparkStyle.secondaryLabel)
    }
    .padding(.horizontal, 24)
    .padding(.vertical, 18)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    .shadow(radius: 12)
    .accessibilityElement(children: .combine)
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
