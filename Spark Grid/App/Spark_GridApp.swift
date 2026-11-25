//
//  Spark_GridApp.swift
//  Spark Grid
//

import AppKit
import SparkGridCore
import SwiftUI

@main
struct Spark_GridApp: App {
  @NSApplicationDelegateAdaptor(SparkGridAppDelegate.self) private var appDelegate

  init() {
    // Windows are not restored at launch: a restored window could not reopen its file, which the
    // sandbox lets Spark Grid open only when it is chosen again, so it would come back empty.
    UserDefaults.standard.register(defaults: ["NSQuitAlwaysKeepsWindows": false])
    if ProcessInfo.processInfo.environment["SPARK_GRID_BENCHMARK"] == "1" {
      PerformanceBenchmark.run()
    }
    #if DEBUG
      if ProcessInfo.processInfo.environment["SPARK_GRID_BUG_BASH"] == "1" {
        _ = BugBashRunner.runIfRequested()
      }
    #endif
  }

  var body: some Scene {
    // One window per workbook, each named by its own id. Files go to windows through
    // `WorkbookWindows`, so opening one never closes another.
    WindowGroup(id: "workbook", for: UUID.self) { $windowID in
      WorkbookWindowRoot(windowID: windowID)
        .environment(\.sparkGridAppDelegate, appDelegate)
    } defaultValue: {
      UUID()
    }
    .defaultSize(width: 1280, height: 800)
    .commands {
      SpreadsheetCommands()
      SpreadsheetFormatCommands()
      SpreadsheetStructureCommands()
      SpreadsheetDataCommands()
      SpreadsheetViewCommands()
      SpreadsheetFileCommands()
      SpreadsheetHelpCommands()
    }

    Window("Spark Grid Help", id: "help") {
      HelpView()
    }
    .defaultSize(width: 820, height: 560)

    Window("Welcome to Spark Grid", id: "welcome") {
      WelcomeView()
    }
    .windowResizability(.contentSize)
    .defaultPosition(.center)

    Window("What's New", id: "whatsnew") {
      WhatsNewView()
    }
    .windowResizability(.contentSize)
    .defaultPosition(.center)

    Settings {
      SettingsView()
    }
  }
}

/// One workbook window: its document, from `WorkbookWindows`, and the hooks that tie the window
/// to it.
private struct WorkbookWindowRoot: View {
  let windowID: UUID
  @Environment(\.openWindow) private var openWindow
  @Environment(\.sparkGridAppDelegate) private var appDelegate

  var body: some View {
    let store = WorkbookWindows.shared.store(for: windowID)
    SpreadsheetRootView(store: store)
      .background(WorkbookWindowBinder(id: windowID))
      .focusedSceneValue(\.documentStore, store)
      .task {
        WorkbookWindows.shared.openWindow = openWindow
        appDelegate?.workbookWindowIsReady()
        store.restartAutosave()
        // Welcome the first time Spark Grid opens; What's New the first time a version does.
        if let screen = LaunchIntro.screenForThisLaunch() {
          openWindow(id: screen.windowID)
        }
      }
      .onDisappear {
        WorkbookWindows.shared.closed(windowID)
      }
      .onOpenURL { url in
        WorkbookWindows.shared.open(url, preferring: store)
      }
      // A file opened from Finder goes to an existing window rather than making one.
      .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
  }
}
