import AppKit
import SparkGridCore
import SwiftUI

struct SpreadsheetDataCommands: Commands {
  @FocusedValue(\.spreadsheetViewModel) private var viewModel: SpreadsheetViewModel?

  var body: some Commands {
    CommandMenu("Data") {
      Button("Sort Range…") {
        guard let viewModel else { return }
        SortRangePresenter.present(from: viewModel)
      }
      .disabled(viewModel == nil)

      Divider()

      Button("Create a Filter") {
        viewModel?.createFilter()
      }
      .disabled(viewModel == nil)

      Button("Clear Filter") {
        viewModel?.clearFilter()
      }
      .disabled(viewModel?.filterState == nil)

      Divider()

      Button("Dropdown List…") {
        guard let viewModel else { return }
        CellNotePresenter.presentDropdown(from: viewModel)
      }
      .disabled(viewModel == nil)
    }
  }
}
