import AppKit
import SparkGridCore
import SwiftUI
import UniformTypeIdentifiers

struct SpreadsheetStructureCommands: Commands {
  @FocusedValue(\.spreadsheetViewModel) private var focusedViewModel: SpreadsheetViewModel?

  private var viewModel: SpreadsheetViewModel? {
    focusedViewModel ?? (NSApp.delegate as? SparkGridAppDelegate)?.resolvedSpreadsheetViewModel()
  }

  var body: some Commands {
    CommandMenu("Sheet") {
      let axis = viewModel?.selectionAxis ?? .cells

      Button {
        viewModel?.insertRowsAbove()
      } label: {
        Text(viewModel?.insertRowAboveTitle ?? "Insert Row Above")
      }
      .disabled(viewModel == nil || axis == .column)
      Button {
        viewModel?.insertRowsBelow()
      } label: {
        Text(viewModel?.insertRowBelowTitle ?? "Insert Row Below")
      }
      .disabled(viewModel == nil || axis == .column)
      Button("Delete Row(s)") { viewModel?.deleteSelectedRows() }
        .disabled(viewModel == nil || axis == .column)
      Button("Hide Rows") { viewModel?.hideSelected(.rows) }
        .disabled(viewModel == nil || axis != .row)
      Button("Unhide Rows") { viewModel?.unhideSelected(.rows) }
        .disabled(viewModel?.canUnhideInSelection.rows != true)

      Divider()

      Button {
        viewModel?.insertColumnsLeft()
      } label: {
        Text(viewModel?.insertColumnLeftTitle ?? "Insert Column Left")
      }
      .disabled(viewModel == nil || axis == .row)
      Button {
        viewModel?.insertColumnsRight()
      } label: {
        Text(viewModel?.insertColumnRightTitle ?? "Insert Column Right")
      }
      .disabled(viewModel == nil || axis == .row)
      Button("Delete Column(s)") { viewModel?.deleteSelectedColumns() }
        .disabled(viewModel == nil || axis == .row)
      Button("Hide Columns") { viewModel?.hideSelected(.columns) }
        .disabled(viewModel == nil || axis != .column)
      Button("Unhide Columns") { viewModel?.unhideSelected(.columns) }
        .disabled(viewModel?.canUnhideInSelection.columns != true)

      Divider()

      Button("Hide Sheet") {
        guard let viewModel else { return }
        viewModel.setSheetHidden(true, at: viewModel.workbook.activeSheetIndex)
      }
      .disabled(viewModel?.canHideActiveSheet != true)
      // Right-clicking a tab was the only way back to a hidden sheet.
      let hiddenSheets = viewModel?.unhideableSheets ?? []
      Menu("Unhide Sheet") {
        ForEach(hiddenSheets, id: \.index) { hidden in
          Button(hidden.name) { viewModel?.setSheetHidden(false, at: hidden.index) }
        }
      }
      .disabled(hiddenSheets.isEmpty)

      Divider()

      Button("Freeze Panes") {
        guard viewModel?.freezePanesAtSelection() == true else {
          SpreadsheetGridNSView.presentFreezeRequiresOffsetAlert(axis: .both)
          return
        }
      }
      .disabled(viewModel == nil)
      Button {
        guard viewModel?.freezeRowsAtSelection() == true else {
          SpreadsheetGridNSView.presentFreezeRequiresOffsetAlert(axis: .rows)
          return
        }
      } label: {
        Text(viewModel?.freezeRowsTitle ?? "Freeze up to row 1")
      }
      .disabled(viewModel == nil)
      Button {
        guard viewModel?.freezeColumnsAtSelection() == true else {
          SpreadsheetGridNSView.presentFreezeRequiresOffsetAlert(axis: .columns)
          return
        }
      } label: {
        Text(viewModel?.freezeColumnsTitle ?? "Freeze up to column A")
      }
      .disabled(viewModel == nil)
      Button("Unfreeze Panes") { viewModel?.unfreezePanes() }
        .disabled(viewModel == nil)

      Divider()

      Menu("Merge Cells") {
        Button("Merge All") { viewModel?.mergeSelection(axis: .all) }
          .disabled(viewModel?.canMergeSelection != true)
        Button("Merge Across") { viewModel?.mergeSelection(axis: .horizontal) }
          .disabled(viewModel?.canMergeHorizontally != true)
        Button("Merge Vertically") { viewModel?.mergeSelection(axis: .vertical) }
          .disabled(viewModel?.canMergeVertically != true)
        Divider()
        Button("Unmerge Cells") { viewModel?.unmergeSelection() }
          .disabled(viewModel?.canUnmergeSelection != true)
      }
      .disabled(viewModel == nil)

      Divider()

      Button("Name Manager…") {
        guard let viewModel else { return }
        NameManagerPresenter.present(from: viewModel)
      }
      .disabled(viewModel == nil)
      Button("Define Named Range…") {
        Self.promptDefineNamedRange(viewModel: viewModel)
      }
      .disabled(viewModel == nil)
    }

    CommandMenu("Insert") {
      Button("Picture…") {
        Self.insertPicture(viewModel: viewModel)
      }
      .disabled(viewModel == nil)

      Button(viewModel?.selectedComment == nil ? "Comment…" : "Edit Comment…") {
        guard let viewModel else { return }
        CellNotePresenter.presentComment(from: viewModel)
      }
      .disabled(viewModel == nil)

      Divider()

      Menu("Chart") {
        Button("Chart…") { viewModel?.beginInsertChart() }
        Divider()
        Button("Bar Chart…") { viewModel?.beginInsertChart(preferredKind: .bar) }
        Button("Line Chart…") { viewModel?.beginInsertChart(preferredKind: .line) }
        Button("Area Chart…") { viewModel?.beginInsertChart(preferredKind: .area) }
      }
      .disabled(viewModel == nil)
    }

    CommandGroup(replacing: .printItem) {
      Button("Print…") {
        (NSApp.delegate as? SparkGridAppDelegate)?.printDocument(nil)
      }
      .keyboardShortcut("p", modifiers: .command)
    }
  }

  private static func insertPicture(viewModel: SpreadsheetViewModel?) {
    guard let viewModel else { return }
    let panel = NSOpenPanel()
    panel.title = "Insert Picture"
    panel.allowedContentTypes = [.png, .jpeg, .gif, .tiff]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    guard panel.runModal() == .OK, let url = panel.url else { return }
    viewModel.insertImageFromFile(url: url)
  }

  private static func promptDefineNamedRange(viewModel: SpreadsheetViewModel?) {
    guard let viewModel else { return }
    let alert = NSAlert()
    alert.messageText = "Define Named Range"
    alert.informativeText =
      "Name the current selection (\(viewModel.selectionRange.start.a1):\(viewModel.selectionRange.end.a1))."
    alert.alertStyle = .informational
    alert.addButton(withTitle: "Define")
    alert.addButton(withTitle: "Cancel")
    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
    field.placeholderString = "Sales"
    alert.accessoryView = field
    alert.window.initialFirstResponder = field
    let response = alert.runModal()
    guard response == .alertFirstButtonReturn else { return }
    viewModel.defineNamedRange(name: field.stringValue)
  }
}
