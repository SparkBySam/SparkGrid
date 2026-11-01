import AppKit
import SparkGridCore
import SwiftUI

struct SpreadsheetCommands: Commands {
  @Bindable private var settings = AppSettings.shared
  @FocusedValue(\.spreadsheetViewModel) private var viewModel: SpreadsheetViewModel?

  var body: some Commands {
    CommandGroup(replacing: .appInfo) {
      Button("About Spark Grid") {
        NotificationCenter.default.post(name: AppUINotifications.showAbout, object: nil)
      }
    }

    CommandGroup(replacing: .undoRedo) {
      Button("Undo") { NSApp.sendAction(Selector(("undo:")), to: nil, from: nil) }
        .keyboardShortcut(
          settings.keyEquivalent(for: .undo), modifiers: settings.eventModifiers(for: .undo))
      Button("Redo") { NSApp.sendAction(Selector(("redo:")), to: nil, from: nil) }
        .keyboardShortcut(
          settings.keyEquivalent(for: .redo), modifiers: settings.eventModifiers(for: .redo))
    }

    CommandGroup(replacing: .pasteboard) {
      Button("Cut") { viewModel?.cutSelection() }
        .keyboardShortcut(
          settings.keyEquivalent(for: .cut), modifiers: settings.eventModifiers(for: .cut)
        )
        .disabled(viewModel == nil)
      Button("Copy") { viewModel?.copySelectionToPasteboard() }
        .keyboardShortcut(
          settings.keyEquivalent(for: .copy), modifiers: settings.eventModifiers(for: .copy)
        )
        .disabled(viewModel == nil)
      Button("Paste") { SpreadsheetPaste.perform(on: viewModel) }
        .keyboardShortcut(
          settings.keyEquivalent(for: .paste), modifiers: settings.eventModifiers(for: .paste)
        )
        .disabled(viewModel == nil)

      Divider()

      Button("Copy Formulas") { viewModel?.copyFormulas() }
        .keyboardShortcut(
          settings.keyEquivalent(for: .copyFormulas),
          modifiers: settings.eventModifiers(for: .copyFormulas)
        )
        .disabled(viewModel == nil)
      Button("Paste Formulas") { viewModel?.pasteFormulasFromPasteboard() }
        .keyboardShortcut(
          settings.keyEquivalent(for: .pasteFormulas),
          modifiers: settings.eventModifiers(for: .pasteFormulas)
        )
        .disabled(viewModel == nil)

      Button("Convert to Values") { viewModel?.convertSelectionToValues() }
        .keyboardShortcut(
          settings.keyEquivalent(for: .convertToValues),
          modifiers: settings.eventModifiers(for: .convertToValues)
        )
        .disabled(viewModel == nil)
    }

    CommandGroup(after: .pasteboard) {
      Button("Select All") { viewModel?.selectAll() }
        .keyboardShortcut("a", modifiers: .command)
        .disabled(viewModel == nil)

      Divider()

      Button("Find…") { viewModel?.toggleFindBar(replace: false) }
        .keyboardShortcut("f", modifiers: .command)
        .disabled(viewModel == nil)
      Button("Find and Replace…") { viewModel?.toggleFindBar(replace: true) }
        .keyboardShortcut("f", modifiers: [.command, .option])
        .disabled(viewModel == nil)
      Button("Find Next") { viewModel?.findNext() }
        .keyboardShortcut("g", modifiers: .command)
        .disabled(viewModel == nil)
      Button("Find Previous") { viewModel?.findPrevious() }
        .keyboardShortcut("g", modifiers: [.command, .shift])
        .disabled(viewModel == nil)
    }
  }
}

private struct SpreadsheetViewModelFocusedValueKey: FocusedValueKey {
  typealias Value = SpreadsheetViewModel
}

extension FocusedValues {
  var spreadsheetViewModel: SpreadsheetViewModel? {
    get { self[SpreadsheetViewModelFocusedValueKey.self] }
    set { self[SpreadsheetViewModelFocusedValueKey.self] = newValue }
  }
}
