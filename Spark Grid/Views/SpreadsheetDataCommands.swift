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

      Divider()

      Button("Create Table") { viewModel?.createTable() }
        .disabled(viewModel?.newTableRange == nil)
      Menu("Table Style") {
        ForEach(SpreadsheetViewModel.tableStyles) { style in
          Button(style.title) {
            if let index = viewModel?.selectedTableIndex {
              viewModel?.setTableStyle(style.name, at: index)
            }
          }
        }
      }
      .disabled(viewModel?.selectedTableIndex == nil)
      Button("Remove Table") {
        if let index = viewModel?.selectedTableIndex { viewModel?.removeTable(at: index) }
      }
      .disabled(viewModel?.selectedTableIndex == nil)

      Divider()

      Button("Find Duplicates…") { viewModel?.isDuplicatesSheetPresented = true }
        .disabled(viewModel == nil)
      Button("Highlight Duplicates") { viewModel?.highlightRepeats(unique: false) }
        .disabled(viewModel == nil)
      Button("Highlight Unique Values") { viewModel?.highlightRepeats(unique: true) }
        .disabled(viewModel == nil)
      Button("Remove Duplicates…") { viewModel?.isDuplicatesSheetPresented = true }
        .disabled(viewModel == nil)
      Button("Clear Duplicate Highlights") { viewModel?.clearDuplicateHighlight() }
        .disabled(viewModel?.duplicateHighlight == nil)
    }
  }
}
