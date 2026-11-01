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
  @State private var store = SpreadsheetDocumentStore()

  init() {
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
    // Single window avoids a blank "Untitled" WindowGroup instance racing file-open.
    Window("Spark Grid", id: "main") {
      SpreadsheetRootView(store: store)
        .environment(\.sparkGridAppDelegate, appDelegate)
        .task {
          bindOpenHandling()
          store.restartAutosave()
        }
        .onOpenURL { url in
          openFile(url)
        }
    }
    .defaultSize(width: 1280, height: 800)
    .commands {
      SpreadsheetCommands()
      SpreadsheetFormatCommands()
      SpreadsheetStructureCommands()
      SpreadsheetDataCommands()
      SpreadsheetViewCommands()
      SpreadsheetFileCommands(store: store)
    }

    Settings {
      SettingsView()
    }
  }

  @MainActor
  private func bindOpenHandling() {
    appDelegate.documentStore = store
    appDelegate.offerCrashRecoveryIfNeeded()
    appDelegate.onOpenFile = { url in
      Task { @MainActor in
        openFile(url)
      }
    }
  }

  @MainActor
  private func openFile(_ url: URL) {
    do {
      try store.load(from: url)
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
