import AppKit
import SparkGridCore
import SwiftUI

/// Data ▸ Text to Columns. Pick what separates the fields; the preview shows the first rows.
struct TextToColumnsSheet: View {
  @Bindable var viewModel: SpreadsheetViewModel
  let source: CellRange
  let onDismiss: () -> Void

  @State private var comma: Bool
  @State private var tab: Bool
  @State private var semicolon = false
  @State private var space: Bool
  @State private var other = ""
  @State private var mergeRepeats = false
  @State private var fixedWidth = false
  @State private var breaksText = ""

  private static let previewRows = 6

  init(viewModel: SpreadsheetViewModel, source: CellRange, onDismiss: @escaping () -> Void) {
    self.viewModel = viewModel
    self.source = source
    self.onDismiss = onDismiss
    // Start with the separator the first filled cells use most.
    let sample = (0..<20).compactMap { offset -> String? in
      let n = source.normalized
      guard n.minRow + offset <= n.maxRow else { return nil }
      return viewModel.activeSheet.cell(at: CellAddress(row: n.minRow + offset, col: n.minCol)).raw
    }.joined(separator: "\n")
    let tabs = sample.filter { $0 == "\t" }.count
    let commas = sample.filter { $0 == "," }.count
    _tab = State(initialValue: tabs > 0 && tabs >= commas)
    _comma = State(initialValue: commas > 0 && commas > tabs)
    _space = State(initialValue: tabs == 0 && commas == 0)
    // Lined-up text with no separators suggests breaks where every row has a gap.
    let lines = sample.split(separator: "\n").map(String.init)
    let suggested = TextSplitter.suggestedBreaks(lines)
    _breaksText = State(initialValue: suggested.map(String.init).joined(separator: ", "))
    // Columns lined up with runs of spaces, and no commas or tabs: start in fixed width.
    _fixedWidth = State(
      initialValue: tabs == 0 && commas == 0 && sample.contains("  ") && !suggested.isEmpty)
  }

  /// Break positions typed as "8, 15, 30".
  private var breaks: [Int] {
    breaksText.split(whereSeparator: { $0 == "," || $0 == " " })
      .compactMap { Int($0) }.filter { $0 > 0 }
  }

  private var options: TextSplitter.Options {
    if fixedWidth { return .fixedWidth(breaks) }
    var set = Set<Character>()
    if comma { set.insert(",") }
    if tab { set.insert("\t") }
    if semicolon { set.insert(";") }
    if space { set.insert(" ") }
    for c in other { set.insert(c) }
    return TextSplitter.Options(delimiters: set, mergeRepeats: mergeRepeats)
  }

  private var preview: [[String]] {
    viewModel.textToColumnsGrid(source, options: options, rowLimit: Self.previewRows)
  }

  private var width: Int {
    viewModel.textToColumnsGrid(source, options: options).map(\.count).max() ?? 1
  }

  private var subtitle: String {
    let n = source.normalized
    let rows = n.maxRow - n.minRow + 1
    return "\(source.a1Label), \(rows) row\(rows == 1 ? "" : "s")"
  }

  var body: some View {
    let columns = width
    let overwrites = viewModel.textToColumnsOverwriteCount(source, width: columns)
    SparkDialog(
      title: "Text to Columns",
      subtitle: subtitle,
      primaryTitle: "Split",
      primaryDisabled: !options.splits || columns < 2,
      onCancel: onDismiss,
      onPrimary: split
    ) {
      SparkSegmentedPicker(
        selection: $fixedWidth,
        options: [(false, "Separated by characters"), (true, "Fixed width")],
        equalWidths: true)
      if fixedWidth {
        SparkDialogGroup {
          SparkDialogRow(label: "Break after characters") {
            TextField(String("8, 15, 30"), text: $breaksText)
              .textFieldStyle(.roundedBorder)
              .font(.system(size: 12, design: .monospaced))
              .frame(width: 150)
          }
        }
        Text(
          "Positions count characters from the start of each cell. Spaces around each piece are removed."
        )
        .font(.system(size: 11))
        .foregroundStyle(SparkStyle.secondaryLabel)
      } else {
        SparkDialogSection(title: "Split at")
        SparkDialogGroup {
          toggleRow("Comma", $comma)
          SparkDialogDivider()
          toggleRow("Tab", $tab)
          SparkDialogDivider()
          toggleRow("Semicolon", $semicolon)
          SparkDialogDivider()
          toggleRow("Space", $space)
          SparkDialogDivider()
          SparkDialogRow(label: "Other") {
            TextField("", text: $other)
              .textFieldStyle(.roundedBorder)
              .frame(width: 60)
          }
          SparkDialogDivider()
          toggleRow("Treat repeats as one", $mergeRepeats)
        }
      }

      SparkDialogSection(title: "Preview")
      previewTable
      if overwrites > 0 {
        Text(
          "Replaces \(overwrites) filled cell\(overwrites == 1 ? "" : "s") to the right. Undo puts them back."
        )
        .font(.system(size: 12))
        .foregroundStyle(SparkStyle.secondaryLabel)
      }
    }
  }

  private func split() {
    viewModel.applyTextToColumns(source, options: options)
    onDismiss()
  }

  private func toggleRow(_ label: String, _ isOn: Binding<Bool>) -> some View {
    SparkDialogRow(label: label) {
      Toggle("", isOn: isOn)
        .toggleStyle(.switch)
        .controlSize(.small)
        .labelsHidden()
        .tint(SparkStyle.accent)
    }
  }

  private var previewTable: some View {
    let rows = preview
    let count = min(rows.map(\.count).max() ?? 1, 8)
    return ScrollView(.horizontal) {
      Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
        ForEach(Array(rows.enumerated()), id: \.offset) { _, fields in
          GridRow {
            ForEach(0..<count, id: \.self) { col in
              Text(col < fields.count ? fields[col] : "")
                .font(.system(size: 12))
                .lineLimit(1)
                .frame(width: 96, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .border(SparkStyle.separator, width: 0.5)
            }
          }
        }
      }
    }
    .frame(maxHeight: 180)
  }
}

enum TextToColumnsPresenter {
  @MainActor
  static func present(from viewModel: SpreadsheetViewModel, in window: NSWindow? = nil) {
    viewModel.commitEditIfNeeded()
    guard let source = viewModel.textToColumnsSource() else {
      let alert = NSAlert()
      alert.messageText = "Select one column"
      alert.informativeText = "Text to Columns splits the cells of a single column."
      alert.runModal()
      return
    }
    SparkDialogPresenter.present(title: "Text to Columns", width: 460, in: window) { close in
      TextToColumnsSheet(viewModel: viewModel, source: source, onDismiss: close)
    }
  }
}
