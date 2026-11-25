import SparkGridCore
import SwiftUI

struct SpreadsheetViewCommands: Commands {
  @FocusedValue(\.spreadsheetViewModel) private var viewModel: SpreadsheetViewModel?
  @Bindable private var settings = AppSettings.shared

  var body: some Commands {
    // CommandMenu("View") is a second top-level menu. Zoom belongs in the
    // system View menu, which already holds fullscreen and other view commands.
    CommandGroup(before: .toolbar) {
      Button("Zoom In") { viewModel?.zoomIn() }
        .hotkey(.zoomIn, settings)
        .disabled(viewModel == nil)
      Button("Zoom Out") { viewModel?.zoomOut() }
        .hotkey(.zoomOut, settings)
        .disabled(viewModel == nil)
      Button("Actual Size") { viewModel?.zoomActualSize() }
        .hotkey(.actualSize, settings)
        .disabled(viewModel == nil)
      Divider()
    }
  }
}
