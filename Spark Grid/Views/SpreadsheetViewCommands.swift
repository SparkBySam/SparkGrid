import SparkGridCore
import SwiftUI

struct SpreadsheetViewCommands: Commands {
  @FocusedValue(\.spreadsheetViewModel) private var viewModel: SpreadsheetViewModel?

  var body: some Commands {
    // CommandMenu("View") is a second top-level menu. Zoom belongs in the
    // system View menu, which already holds fullscreen and other view commands.
    CommandGroup(before: .toolbar) {
      Button("Zoom In") { viewModel?.zoomIn() }
        .keyboardShortcut("+", modifiers: .command)
        .disabled(viewModel == nil)
      Button("Zoom Out") { viewModel?.zoomOut() }
        .keyboardShortcut("-", modifiers: .command)
        .disabled(viewModel == nil)
      Button("Actual Size") { viewModel?.zoomActualSize() }
        .keyboardShortcut("0", modifiers: .command)
        .disabled(viewModel == nil)
      Divider()
    }
  }
}
