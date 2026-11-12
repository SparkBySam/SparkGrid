import AppKit
import SparkGridCore
import SwiftUI

/// Data ▸ Sort. Columns by header name, an order that fits each column's values, and further
/// levels that break ties.
struct SortRangeSheet: View {
  @Bindable var viewModel: SpreadsheetViewModel
  let onDismiss: () -> Void

  private let range: CellRange
  private let columns: [Int]

  struct Level: Identifiable {
    let id = UUID()
    var column: Int
    var ascending: Bool
  }

  @State private var levels: [Level]
  @State private var hasHeader: Bool

  /// Most sort levels offered.
  private static let maxLevels = 8

  init(viewModel: SpreadsheetViewModel, onDismiss: @escaping () -> Void) {
    self.viewModel = viewModel
    self.onDismiss = onDismiss
    let range = viewModel.effectiveSortRange()
    let n = range.normalized
    self.range = range
    self.columns = Array(n.minCol...n.maxCol)
    let selected = viewModel.selectionAnchor.col
    let first = (n.minCol...n.maxCol).contains(selected) ? selected : n.minCol
    _levels = State(initialValue: [Level(column: first, ascending: true)])
    _hasHeader = State(
      initialValue: n.maxRow > n.minRow && Self.looksLikeHeader(viewModel: viewModel, range: range))
  }

  var body: some View {
    SparkDialog(
      title: "Sort",
      subtitle: subtitle,
      primaryTitle: "Sort",
      primaryDisabled: dataRowCount < 1,
      onCancel: onDismiss,
      onPrimary: sort
    ) {
      SparkDialogGroup {
        SparkDialogRow(label: "First row is a header") {
          Toggle("", isOn: $hasHeader)
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
            .tint(SparkStyle.accent)
        }
      }

      SparkDialogSection(title: "Sort by")
      SparkDialogGroup {
        ForEach(Array(levels.enumerated()), id: \.element.id) { index, level in
          if index > 0 { SparkDialogDivider() }
          levelRow(index: index, level: level)
        }
        if levels.count < min(Self.maxLevels, columns.count) {
          SparkDialogDivider()
          HStack {
            Button("+ Add level", action: addLevel)
              .buttonStyle(.link)
              .tint(SparkStyle.accent)
              .font(.system(size: 12))
            Spacer()
          }
          .padding(.horizontal, 12)
          .frame(minHeight: 32)
        }
      }
    }
  }

  private func levelRow(index: Int, level: Level) -> some View {
    HStack(spacing: 8) {
      if index > 0 {
        Text("Then by")
          .font(.system(size: 12))
          .foregroundStyle(SparkStyle.secondaryLabel)
          .fixedSize()
      }
      Picker("Column", selection: columnBinding(index)) {
        ForEach(columns, id: \.self) { col in
          Text(columnName(col)).tag(col)
        }
      }
      .labelsHidden()
      .frame(minWidth: 120)

      let labels = orderLabels(for: level.column)
      SparkSegmentedPicker(
        selection: orderBinding(index), options: [(true, labels.up), (false, labels.down)],
        equalWidths: true)

      if index > 0 {
        Button {
          levels.remove(at: index)
        } label: {
          Image(systemName: "xmark")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(SparkStyle.secondaryLabel)
            .frame(width: 18, height: 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Remove this level")
      }
    }
    .padding(.horizontal, 12)
    .frame(minHeight: 40)
  }

  // MARK: - Labels

  private var subtitle: String {
    let rows = dataRowCount
    return "Applies to \(range.a1Label) · \(rows) \(rows == 1 ? "row" : "rows")"
  }

  private var dataRowCount: Int {
    let n = range.normalized
    return max(0, n.maxRow - n.minRow + 1 - (hasHeader ? 1 : 0))
  }

  /// The header text when the first row is a header, otherwise "Column C".
  private func columnName(_ col: Int) -> String {
    let letter = A1Notation.columnLabel(for: col)
    guard hasHeader else { return "Column \(letter)" }
    let header = viewModel.displayString(
      at: CellAddress(row: range.normalized.minRow, col: col)
    ).trimmingCharacters(in: .whitespacesAndNewlines)
    return header.isEmpty ? "Column \(letter)" : header
  }

  /// A to Z for text, low to high for numbers, old to new for dates.
  private func orderLabels(for col: Int) -> (up: String, down: String) {
    let n = range.normalized
    let first = n.minRow + (hasHeader ? 1 : 0)
    guard first <= n.maxRow else { return ("A to Z", "Z to A") }
    var numbers = 0
    var texts = 0
    var dates = 0
    for row in first...min(n.maxRow, first + 50) {
      let address = CellAddress(row: row, col: col)
      let text = viewModel.displayString(at: address)
      if text.isEmpty { continue }
      if case .number = viewModel.displayValue(at: address) {
        if viewModel.activeSheet.cell(at: address).format?.numberFormat == .date {
          dates += 1
        } else {
          numbers += 1
        }
      } else {
        texts += 1
      }
    }
    if dates > 0, dates >= numbers, dates >= texts { return ("Old to new", "New to old") }
    if numbers > texts { return ("Low to high", "High to low") }
    return ("A to Z", "Z to A")
  }

  private static func looksLikeHeader(viewModel: SpreadsheetViewModel, range: CellRange) -> Bool {
    viewModel.rangeLooksLikeItHasHeader(range)
  }

  // MARK: - Actions

  private func columnBinding(_ index: Int) -> Binding<Int> {
    Binding(
      get: { levels.indices.contains(index) ? levels[index].column : columns.first ?? 0 },
      set: { if levels.indices.contains(index) { levels[index].column = $0 } }
    )
  }

  private func orderBinding(_ index: Int) -> Binding<Bool> {
    Binding(
      get: { levels.indices.contains(index) ? levels[index].ascending : true },
      set: { if levels.indices.contains(index) { levels[index].ascending = $0 } }
    )
  }

  private func addLevel() {
    let used = Set(levels.map(\.column))
    let next = columns.first { !used.contains($0) } ?? columns.first ?? 0
    levels.append(Level(column: next, ascending: true))
  }

  private func sort() {
    guard let first = levels.first else { return }
    viewModel.sortRange(
      column: first.column,
      direction: first.ascending ? .ascending : .descending,
      hasHeader: hasHeader,
      then: levels.dropFirst().map {
        (column: $0.column, direction: $0.ascending ? .ascending : .descending)
      }
    )
    onDismiss()
  }
}

enum SortRangePresenter {
  @MainActor
  static func present(from viewModel: SpreadsheetViewModel, in window: NSWindow? = nil) {
    viewModel.commitEditIfNeeded()
    SparkDialogPresenter.present(title: "Sort", width: 460, in: window) { close in
      SortRangeSheet(viewModel: viewModel, onDismiss: close)
    }
  }
}
