import AppKit
import SparkGridCore
import SwiftUI
import UniformTypeIdentifiers

struct SpreadsheetStructureCommands: Commands {
  @FocusedValue(\.spreadsheetViewModel) private var focusedViewModel: SpreadsheetViewModel?
  @Bindable private var settings = AppSettings.shared

  private var viewModel: SpreadsheetViewModel? {
    focusedViewModel ?? SparkGridAppDelegate.current?.resolvedSpreadsheetViewModel()
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

      let outlineAxis = viewModel?.outlineAxisForSelection ?? .rows
      let outline = viewModel?.hasOutline ?? (rows: false, columns: false)
      Button {
        viewModel?.groupSelection(outlineAxis)
      } label: {
        Text(outlineAxis == .rows ? "Group Rows" : "Group Columns")
      }
      .keyboardShortcut("k", modifiers: [.command, .shift])
      .disabled(viewModel == nil)
      Button {
        viewModel?.ungroupSelection(outlineAxis)
      } label: {
        Text(outlineAxis == .rows ? "Ungroup Rows" : "Ungroup Columns")
      }
      .keyboardShortcut("j", modifiers: [.command, .shift])
      .disabled(outlineAxis == .rows ? !outline.rows : !outline.columns)
      Button("Collapse or Expand Group") {
        viewModel?.toggleOutlineGroupAtSelection(outlineAxis)
      }
      .disabled(outlineAxis == .rows ? !outline.rows : !outline.columns)
      Button("Collapse All Groups") {
        viewModel?.showOutlineLevel(0, .rows)
        viewModel?.showOutlineLevel(0, .columns)
      }
      .disabled(!outline.rows && !outline.columns)
      Button("Expand All Groups") {
        viewModel?.showOutlineLevel(nil, .rows)
        viewModel?.showOutlineLevel(nil, .columns)
      }
      .disabled(!outline.rows && !outline.columns)
      let rowDepth = viewModel?.outlineDepth(.rows) ?? 0
      let columnDepth = viewModel?.outlineDepth(.columns) ?? 0
      Menu("Show Row Levels") {
        ForEach(Array(1...max(rowDepth + 1, 1)), id: \.self) { level in
          Button("Level \(level)") { viewModel?.showOutlineLevelButton(level, .rows) }
        }
      }
      .disabled(rowDepth == 0)
      Menu("Show Column Levels") {
        ForEach(Array(1...max(columnDepth + 1, 1)), id: \.self) { level in
          Button("Level \(level)") { viewModel?.showOutlineLevelButton(level, .columns) }
        }
      }
      .disabled(columnDepth == 0)

      Divider()

      Button("Insert Page Break") { viewModel?.insertPageBreak() }
        .disabled(viewModel?.canInsertPageBreak != true)
      Button("Remove Page Break") { viewModel?.removePageBreak() }
        .disabled(viewModel?.canRemovePageBreak != true)
      Button("Reset All Page Breaks") { viewModel?.resetAllPageBreaks() }
        .disabled(viewModel?.hasPageBreaks != true)

      Divider()

      Button(viewModel?.isSheetProtected == true ? "Unprotect Sheet…" : "Protect Sheet…") {
        guard let viewModel else { return }
        SheetProtectionPresenter.toggle(from: viewModel)
      }
      .disabled(viewModel == nil)

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
      Button("AutoSum") { viewModel?.autoSum() }
        .keyboardShortcut(
          settings.keyEquivalent(for: .autoSum), modifiers: settings.eventModifiers(for: .autoSum)
        )
        .disabled(viewModel == nil)

      Button("Table") { viewModel?.createTable() }
        .disabled(viewModel?.newTableRange == nil)

      Button("Picture…") {
        Self.insertPicture(viewModel: viewModel)
      }
      .disabled(viewModel == nil)

      Button(viewModel?.selectedComment == nil ? "Comment…" : "Edit Comment…") {
        guard let viewModel else { return }
        CellNotePresenter.presentComment(from: viewModel)
      }
      .disabled(viewModel == nil)

      Button(viewModel?.selectedHyperlink == nil ? "Link…" : "Edit Link…") {
        guard let viewModel else { return }
        LinkPresenter.present(from: viewModel)
      }
      .keyboardShortcut("k", modifiers: .command)
      .disabled(viewModel == nil)

      if viewModel?.selectedHyperlink != nil {
        Button("Remove Link") { viewModel?.removeLink() }
      }

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
        SparkGridAppDelegate.current?.printDocument(nil)
      }
      .keyboardShortcut("p", modifiers: .command)

      Button("Export as PDF…") {
        SparkGridAppDelegate.current?.exportPDF(nil)
      }

      Menu("Print Area") {
        Button("Set Print Area") { viewModel?.setPrintArea() }
          .disabled(viewModel == nil)
        Button("Clear Print Area") { viewModel?.clearPrintArea() }
          .disabled(viewModel?.printArea == nil)
      }
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
