import AppKit
import SparkGridCore
import SwiftUI

/// The panel a column's filter button opens: sort, search, and a checklist of the column's values.
/// It stays open while values are checked, so several can change in one visit.
struct FilterPopoverView: View {
  @Bindable var viewModel: SpreadsheetViewModel
  let column: Int
  let title: String
  /// Called after every change, so the grid can lay out the rows that appeared or went away.
  let onChange: () -> Void
  let onDone: () -> Void

  @State private var search = ""
  @State private var mode: Mode = .values
  @State private var draft: [ColumnFilterRules.Rule] = []
  @State private var matchAll = true
  @State private var loadedRules = false

  enum Mode: String, CaseIterable, Identifiable {
    case values = "Values"
    case rules = "Rules"
    var id: String { rawValue }
  }

  private var selected: Set<String>? { viewModel.filterState?.selectedValuesByColumn[column] }

  private func matching(_ counts: [FilterValueCount]) -> [FilterValueCount] {
    let query = search.trimmingCharacters(in: .whitespaces)
    guard !query.isEmpty else { return counts }
    return counts.filter { $0.value.localizedCaseInsensitiveContains(query) }
  }

  var body: some View {
    // Counting reads every row in the filter, so do it once per redraw.
    let counts = viewModel.filterValueCounts(column: column)
    let shownCounts = matching(counts)
    let allValues = Set(counts.map(\.value))
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 6) {
        sortButton("Sort A to Z", ascending: true)
        sortButton("Sort Z to A", ascending: false)
      }

      Divider()

      SparkSegmentedPicker(
        selection: $mode, options: Mode.allCases.map { ($0, $0.rawValue) }, equalWidths: true)

      if mode == .rules {
        rulesPane
      } else {
        valuesPane(counts: counts, shownCounts: shownCounts, allValues: allValues)
      }

      HStack {
        Button("Clear Filter") {
          if mode == .rules {
            draft = []
            viewModel.setFilterRules(column: column, rules: nil)
            onChange()
          } else {
            setValues(nil)
          }
        }
        .disabled(!(viewModel.filterState?.isFiltering(column: column) ?? false))
        Spacer()
        Button("Done") {
          if mode == .rules { applyRules() }
          onDone()
        }
        .keyboardShortcut(.defaultAction)
      }
      .controlSize(.small)
    }
    .padding(12)
    .frame(width: 300)
    .tint(SparkStyle.accent)
    .onAppear(perform: loadRules)
  }

  @ViewBuilder
  private func valuesPane(
    counts: [FilterValueCount], shownCounts: [FilterValueCount], allValues: Set<String>
  ) -> some View {
    TextField("Search \(title)", text: $search)
      .textFieldStyle(.roundedBorder)
      .font(.system(size: 12))

    HStack {
      Button("Select All") { setValues(nil) }
      Spacer()
      Button("Deselect All") { setValues([]) }
    }
    .buttonStyle(.link)
    .font(.system(size: 12))

    ScrollView {
      LazyVStack(alignment: .leading, spacing: 0) {
        ForEach(shownCounts) { item in
          valueRow(item, allValues: allValues)
        }
        if shownCounts.isEmpty {
          Text("No values match.")
            .font(.system(size: 12))
            .foregroundStyle(SparkStyle.secondaryLabel)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
      }
      .padding(.vertical, 4)
    }
    .frame(maxHeight: 220)
    .fixedSize(horizontal: false, vertical: true)
    .overlay(
      RoundedRectangle(cornerRadius: 5).stroke(Color(nsColor: .separatorColor), lineWidth: 1))

  }

  // MARK: - Rules

  private static func title(for kind: ColumnFilterRules.Kind) -> String {
    switch kind {
    case .equals: return "is"
    case .notEquals: return "is not"
    case .contains: return "contains"
    case .notContains: return "does not contain"
    case .beginsWith: return "begins with"
    case .endsWith: return "ends with"
    case .greaterThan: return "is greater than"
    case .greaterOrEqual: return "is at least"
    case .lessThan: return "is less than"
    case .lessOrEqual: return "is at most"
    case .between: return "is between"
    case .top: return "is in the top"
    case .bottom: return "is in the bottom"
    }
  }

  /// Top, bottom and between fill both of a column's two rule slots in the file.
  private var draftIsFull: Bool {
    draft.count >= 2
      || draft.contains { $0.kind == .between || $0.kind == .top || $0.kind == .bottom }
  }

  private var rulesPane: some View {
    VStack(alignment: .leading, spacing: 8) {
      if draft.count > 1 {
        HStack(spacing: 6) {
          Text("Show rows that match")
          Picker("Match", selection: $matchAll) {
            Text("all").tag(true)
            Text("any").tag(false)
          }
          .labelsHidden()
          .fixedSize()
          Text("rules")
        }
        .font(.system(size: 12))
        .foregroundStyle(SparkStyle.secondaryLabel)
      }
      ForEach(draft.indices, id: \.self) { index in
        ruleRow(index)
      }
      if !draftIsFull {
        Button("+ Add rule") {
          draft.append(.init(kind: draft.isEmpty ? .contains : .equals, value: ""))
        }
        .buttonStyle(.link)
        .font(.system(size: 12))
      }
      if draft.isEmpty {
        Text(
          "Rules keep rows whose value contains some text, is greater than a number, is between two numbers, or is in the top 10."
        )
        .font(.system(size: 11))
        .foregroundStyle(SparkStyle.secondaryLabel)
        .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private func ruleRow(_ index: Int) -> some View {
    let kind = draft.indices.contains(index) ? draft[index].kind : .contains
    return VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 6) {
        Picker("Rule", selection: kindBinding(index)) {
          ForEach(ColumnFilterRules.Kind.allCases, id: \.self) { kind in
            Text(Self.title(for: kind)).tag(kind)
          }
        }
        .labelsHidden()
        Button {
          if draft.indices.contains(index) { draft.remove(at: index) }
        } label: {
          Image(systemName: "xmark")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(SparkStyle.secondaryLabel)
        }
        .buttonStyle(.plain)
        .help("Remove this rule")
      }
      HStack(spacing: 6) {
        TextField(kind == .top || kind == .bottom ? "10" : "Value", text: valueBinding(index))
          .textFieldStyle(.roundedBorder)
          .onSubmit(applyRules)
        if kind == .between {
          Text("and").font(.system(size: 12)).foregroundStyle(SparkStyle.secondaryLabel)
          TextField("Value", text: value2Binding(index))
            .textFieldStyle(.roundedBorder)
            .onSubmit(applyRules)
        }
        if kind == .top || kind == .bottom {
          Text("values").font(.system(size: 12)).foregroundStyle(SparkStyle.secondaryLabel)
        }
      }
    }
    .padding(8)
    .background(RoundedRectangle(cornerRadius: 6).stroke(SparkStyle.separator, lineWidth: 1))
  }

  private func kindBinding(_ index: Int) -> Binding<ColumnFilterRules.Kind> {
    Binding(
      get: { draft.indices.contains(index) ? draft[index].kind : .contains },
      set: { next in
        guard draft.indices.contains(index) else { return }
        draft[index].kind = next
        // Top, bottom and between take both slots.
        if next == .between || next == .top || next == .bottom {
          draft = [draft[index]]
        }
      })
  }

  private func valueBinding(_ index: Int) -> Binding<String> {
    Binding(
      get: { draft.indices.contains(index) ? draft[index].value : "" },
      set: { if draft.indices.contains(index) { draft[index].value = $0 } })
  }

  private func value2Binding(_ index: Int) -> Binding<String> {
    Binding(
      get: { draft.indices.contains(index) ? draft[index].value2 : "" },
      set: { if draft.indices.contains(index) { draft[index].value2 = $0 } })
  }

  private func loadRules() {
    guard !loadedRules else { return }
    loadedRules = true
    if let rules = viewModel.filterState?.rulesByColumn[column] {
      draft = rules.rules
      matchAll = rules.matchAll
      mode = .rules
    }
  }

  private func applyRules() {
    let filled = draft.filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
    viewModel.setFilterRules(
      column: column,
      rules: filled.isEmpty ? nil : ColumnFilterRules(rules: filled, matchAll: matchAll))
    onChange()
  }

  private func sortButton(_ label: String, ascending: Bool) -> some View {
    let isOn = viewModel.isFilterSorted(column: column, ascending: ascending)
    return Button {
      viewModel.filterSort(column: column, ascending: ascending)
      onChange()
    } label: {
      Text(label)
        .font(.system(size: 12, weight: isOn ? .semibold : .regular))
        .frame(maxWidth: .infinity)
    }
    .buttonStyle(.bordered)
    .controlSize(.small)
    .background(
      RoundedRectangle(cornerRadius: 5).fill(isOn ? SparkStyle.accent.opacity(0.22) : .clear)
    )
    .accessibilityAddTraits(isOn ? .isSelected : [])
    .help(isOn ? "Click again to put the rows back in their original order" : label)
  }

  private func valueRow(_ item: FilterValueCount, allValues: Set<String>) -> some View {
    let isOn = selected?.contains(item.value) ?? true
    return Toggle(
      isOn: Binding(
        get: { isOn },
        set: { _ in toggle(item.value, allValues: allValues) }
      )
    ) {
      HStack {
        Text(item.value.isEmpty ? "(Blanks)" : item.value)
          .lineLimit(1)
          .truncationMode(.tail)
        Spacer(minLength: 8)
        Text("\(item.count)")
          .monospacedDigit()
          .foregroundStyle(SparkStyle.secondaryLabel)
      }
      .font(.system(size: 12))
    }
    .toggleStyle(.checkbox)
    .padding(.horizontal, 8)
    .padding(.vertical, 3)
  }

  private func toggle(_ value: String, allValues all: Set<String>) {
    var next = selected ?? all
    if next.contains(value) {
      next.remove(value)
    } else {
      next.insert(value)
    }
    setValues(all.isSubset(of: next) ? nil : next)
  }

  private func setValues(_ values: Set<String>?) {
    viewModel.setFilterValues(column: column, values: values)
    onChange()
  }
}

/// Hosts the filter panel. The panel is its own window with an empty undo history, so ⌘Z
/// and ⇧⌘Z there would do nothing. They undo the sheet's last change instead.
final class FilterPopoverController: NSHostingController<FilterPopoverView>, NSMenuItemValidation {
  weak var sheetUndoManager: UndoManager?
  /// Called after an undo or redo, so the grid can lay out the rows that changed.
  var onUndo: (() -> Void)?

  @objc func undo(_ sender: Any?) {
    sheetUndoManager?.undo()
    onUndo?()
  }

  @objc func redo(_ sender: Any?) {
    sheetUndoManager?.redo()
    onUndo?()
  }

  func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    switch menuItem.action {
    case #selector(undo(_:)): return sheetUndoManager?.canUndo ?? false
    case #selector(redo(_:)): return sheetUndoManager?.canRedo ?? false
    default: return true
    }
  }
}
