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
      // Text being typed (a dialog's field, the formula bar, a cell being edited) takes Cut,
      // Copy and Paste itself, as Select All does; otherwise they act on the cells. Pasting into
      // Formula Help's question went into the cell (Sam, Nov 20).
      Button("Cut") {
        if let text = FocusedText.current { text.cut(nil) } else { viewModel?.cutSelection() }
      }
      .keyboardShortcut(
        settings.keyEquivalent(for: .cut), modifiers: settings.eventModifiers(for: .cut)
      )
      .disabled(viewModel == nil)
      Button("Copy") {
        if let text = FocusedText.current {
          text.copy(nil)
        } else {
          viewModel?.copySelectionToPasteboard()
        }
      }
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

      Menu("Paste Special") {
        Button("Paste Values") { viewModel?.pasteValues() }
          .keyboardShortcut(
            settings.keyEquivalent(for: .pasteValues),
            modifiers: settings.eventModifiers(for: .pasteValues)
          )
        Button("Paste Formats") { viewModel?.pasteFormats() }
        Button("Paste Transposed") { viewModel?.pasteTransposed() }
      }
      .disabled(viewModel == nil)

      Button("Fill Down") { viewModel?.fillDown() }
        .keyboardShortcut(
          settings.keyEquivalent(for: .fillDown),
          modifiers: settings.eventModifiers(for: .fillDown)
        )
        .disabled(viewModel == nil)
      Button("Fill Right") { viewModel?.fillRight() }
        .keyboardShortcut(
          settings.keyEquivalent(for: .fillRight),
          modifiers: settings.eventModifiers(for: .fillRight)
        )
        .disabled(viewModel == nil)

      Menu("Clear") {
        Button("Clear All") { viewModel?.clearAll() }
        Button("Clear Contents") { viewModel?.clearContents() }
        Button("Clear Formats") { viewModel?.clearFormats() }
          .hotkey(.clearFormats, settings)
      }
      .disabled(viewModel == nil)

      Button("Convert to Values") { viewModel?.convertSelectionToValues() }
        .keyboardShortcut(
          settings.keyEquivalent(for: .convertToValues),
          modifiers: settings.eventModifiers(for: .convertToValues)
        )
        .disabled(viewModel == nil)
    }

    CommandGroup(after: .pasteboard) {
      Button("Select All") {
        // Text being typed (a cell, the formula bar, the name box, a dialog field) selects its
        // own text, as in any Mac app; otherwise the whole sheet is selected.
        if let editor = NSApp.keyWindow?.firstResponder as? NSText {
          editor.selectAll(nil)
        } else {
          viewModel?.selectAll()
        }
      }
      .hotkey(.selectAll, settings)
      .disabled(viewModel == nil)

      Divider()

      Button("Find…") { viewModel?.toggleFindBar(replace: false) }
        .hotkey(.find, settings)
        .disabled(viewModel == nil)
      Button("Find and Replace…") { viewModel?.toggleFindBar(replace: true) }
        .hotkey(.findAndReplace, settings)
        .disabled(viewModel == nil)
      Button("Find Next") { viewModel?.findNext() }
        .hotkey(.findNext, settings)
        .disabled(viewModel == nil)
      Button("Find Previous") { viewModel?.findPrevious() }
        .hotkey(.findPrevious, settings)
        .disabled(viewModel == nil)

      Divider()

      // Type a cell (U37), a range, Sheet2!A1 or a name in the name box and press Return.
      Button("Go To…") { viewModel?.nameBoxFocusRequests += 1 }
        .hotkey(.goTo, settings)
        .disabled(viewModel == nil)
      Button("Select Blank Cells") { viewModel?.selectBlankCells() }
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
