import SparkGridCore
import SwiftUI

/// Data ▸ Edit PivotTable: which source columns become rows, columns, values and filters.
struct PivotFieldsSheet: View {
  @Bindable var viewModel: SpreadsheetViewModel
  let pivot: SheetPivot
  let onDismiss: () -> Void

  private enum Area: String, CaseIterable, Identifiable {
    case rows = "Rows"
    case columns = "Columns"
    case values = "Values"
    case filters = "Filters"
    var id: String { rawValue }
  }

  @State private var definition: PivotDefinition
  @State private var openFilter: Int?
  private let fields: [String]
  /// Fields whose cells are dates, which can be grouped.
  private let dateFields: Set<Int>

  init(viewModel: SpreadsheetViewModel, pivot: SheetPivot, onDismiss: @escaping () -> Void) {
    self.viewModel = viewModel
    self.pivot = pivot
    self.onDismiss = onDismiss
    fields = viewModel.pivotFieldNames(pivot)
    dateFields = Set(fields.indices.filter { viewModel.pivotFieldIsDate(pivot, field: $0) })
    _definition = State(initialValue: pivot.definition)
  }

  private var sourceLabel: String {
    "\(pivot.sourceSheet) \(pivot.sourceRange.a1Label)"
  }

  var body: some View {
    SparkDialog(
      title: "PivotTable Fields",
      subtitle: "From \(sourceLabel)",
      primaryTitle: "Update",
      primaryDisabled: false,
      onCancel: onDismiss,
      onPrimary: {
        viewModel.applyPivot(pivot.id, definition: definition)
        onDismiss()
      },
      leading: { EmptyView() },
      content: {
        HStack(alignment: .top, spacing: 14) {
          fieldList
          VStack(alignment: .leading, spacing: 10) {
            ForEach(Area.allCases) { area in
              areaBox(area)
            }
          }
          .frame(width: 270, alignment: .leading)
        }
      }
    )
  }

  // MARK: - Field list

  private var fieldList: some View {
    VStack(alignment: .leading, spacing: 4) {
      SparkDialogSection(title: "Fields")
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(fields.indices, id: \.self) { index in
            HStack {
              Text(fields[index])
                .font(.system(size: 13))
                .foregroundStyle(isUsed(index) ? SparkStyle.secondaryLabel : SparkStyle.label)
                .lineLimit(1)
              Spacer(minLength: 6)
              Menu {
                Button("Add to Rows") { add(index, to: .rows) }
                Button("Add to Columns") { add(index, to: .columns) }
                Button("Add to Values") { add(index, to: .values) }
                Button("Add to Filters") { add(index, to: .filters) }
              } label: {
                Image(systemName: "plus.circle")
              }
              .menuStyle(.borderlessButton)
              .menuIndicator(.hidden)
              .fixedSize()
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 28)
          }
        }
      }
      .frame(width: 210, height: 330)
      .background(RoundedRectangle(cornerRadius: 8).fill(SparkStyle.chrome))
      .overlay(RoundedRectangle(cornerRadius: 8).stroke(SparkStyle.separator, lineWidth: 1))
    }
  }

  private func isUsed(_ field: Int) -> Bool {
    definition.rows.contains(field) || definition.columns.contains(field)
      || definition.values.contains { $0.field == field }
      || definition.filters.contains { $0.field == field }
  }

  private func add(_ field: Int, to area: Area) {
    switch area {
    case .rows:
      definition.columns.removeAll { $0 == field }
      if !definition.rows.contains(field) { definition.rows.append(field) }
    case .columns:
      definition.rows.removeAll { $0 == field }
      if !definition.columns.contains(field) { definition.columns.append(field) }
    case .values:
      // Text columns are counted; number columns are summed, as other apps choose.
      let numeric = viewModel.pivotRecords(pivot).contains { record in
        if field < record.count, case .number = record[field] { return true }
        return false
      }
      definition.values.append(.init(field: field, aggregate: numeric ? .sum : .count))
    case .filters:
      if !definition.filters.contains(where: { $0.field == field }) {
        definition.filters.append(.init(field: field))
      }
    }
  }

  // MARK: - Areas

  @ViewBuilder
  private func areaBox(_ area: Area) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      SparkDialogSection(title: area.rawValue)
      SparkDialogGroup {
        let items = entries(area)
        if items.isEmpty {
          Text("Add a field with +")
            .font(.system(size: 12))
            .foregroundStyle(SparkStyle.secondaryLabel)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
        } else {
          ForEach(Array(items.enumerated()), id: \.offset) { position, index in
            if position > 0 { SparkDialogDivider() }
            entryRow(area, index: index)
          }
        }
      }
    }
  }

  /// Indexes into the area's own list.
  private func entries(_ area: Area) -> [Int] {
    switch area {
    case .rows: return Array(definition.rows.indices)
    case .columns: return Array(definition.columns.indices)
    case .values: return Array(definition.values.indices)
    case .filters: return Array(definition.filters.indices)
    }
  }

  @ViewBuilder
  private func entryRow(_ area: Area, index: Int) -> some View {
    HStack(spacing: 8) {
      switch area {
      case .rows:
        Text(fields[safe: definition.rows[index]] ?? "?").lineLimit(1)
        Spacer()
        dateGroupPicker(definition.rows[index])
      case .columns:
        Text(fields[safe: definition.columns[index]] ?? "?").lineLimit(1)
        Spacer()
        dateGroupPicker(definition.columns[index])
      case .values:
        let field = definition.values[index].field
        Text(fields[safe: field] ?? "?").lineLimit(1)
        Spacer()
        Picker("", selection: $definition.values[index].aggregate) {
          ForEach(PivotDefinition.Aggregate.allCases, id: \.self) { aggregate in
            Text(aggregate.label).tag(aggregate)
          }
        }
        .labelsHidden()
        .fixedSize()
      case .filters:
        let filter = definition.filters[index]
        Text(fields[safe: filter.field] ?? "?").lineLimit(1)
        Spacer()
        Button(filterSummary(filter)) { openFilter = index }
          .buttonStyle(.link)
          .popover(
            isPresented: Binding(
              get: { openFilter == index }, set: { if !$0 { openFilter = nil } })
          ) {
            filterChoices(index)
          }
      }
      Button {
        remove(area, index: index)
      } label: {
        Image(systemName: "minus.circle")
      }
      .buttonStyle(.borderless)
    }
    .font(.system(size: 13))
    .padding(.horizontal, 12)
    .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
  }

  /// Year, quarter, month or day for a date field; nothing for other fields.
  @ViewBuilder
  private func dateGroupPicker(_ field: Int) -> some View {
    if dateFields.contains(field) {
      Picker(
        "",
        selection: Binding(
          get: { definition.dateGroups[field] },
          set: { definition.dateGroups[field] = $0 })
      ) {
        Text("Each date").tag(PivotDefinition.DateGroup?.none)
        ForEach(PivotDefinition.DateGroup.allCases, id: \.self) { group in
          Text("By \(group.label.lowercased())").tag(PivotDefinition.DateGroup?.some(group))
        }
      }
      .labelsHidden()
      .fixedSize()
    }
  }

  private func remove(_ area: Area, index: Int) {
    switch area {
    case .rows: definition.rows.remove(at: index)
    case .columns: definition.columns.remove(at: index)
    case .values: definition.values.remove(at: index)
    case .filters: definition.filters.remove(at: index)
    }
  }

  private func filterSummary(_ filter: PivotDefinition.Filter) -> String {
    filter.hidden.isEmpty ? "All" : "\(filter.hidden.count) hidden"
  }

  private func filterChoices(_ index: Int) -> some View {
    let field = definition.filters[index].field
    let items = viewModel.pivotItems(pivot, field: field, group: definition.dateGroups[field])
    return VStack(alignment: .leading, spacing: 6) {
      HStack {
        Button("Show All") { definition.filters[index].hidden = [] }
        Button("Hide All") { definition.filters[index].hidden = Set(items) }
      }
      .buttonStyle(.link)
      ScrollView {
        VStack(alignment: .leading, spacing: 4) {
          ForEach(items, id: \.self) { item in
            Toggle(
              item,
              isOn: Binding(
                get: { !definition.filters[index].hidden.contains(item) },
                set: { shown in
                  if shown {
                    definition.filters[index].hidden.remove(item)
                  } else {
                    definition.filters[index].hidden.insert(item)
                  }
                }))
          }
        }
      }
      .frame(maxHeight: 260)
    }
    .padding(12)
    .frame(width: 240)
  }
}

extension Array {
  fileprivate subscript(safe index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}

@MainActor
enum PivotPresenter {
  /// Makes a pivot table of the selection on a new sheet, then asks for its fields.
  static func create(from viewModel: SpreadsheetViewModel, in window: NSWindow? = nil) {
    guard let pivot = viewModel.createPivot() else { return }
    editFields(of: pivot, from: viewModel, in: window)
  }

  static func editSelected(from viewModel: SpreadsheetViewModel, in window: NSWindow? = nil) {
    guard let pivot = viewModel.selectedPivot ?? viewModel.activeSheet.fileExtras.sparkPivots.first
    else { return }
    editFields(of: pivot, from: viewModel, in: window)
  }

  private static func editFields(
    of pivot: SheetPivot, from viewModel: SpreadsheetViewModel, in window: NSWindow?
  ) {
    viewModel.commitEditIfNeeded()
    SparkDialogPresenter.present(title: "PivotTable Fields", width: 540, in: window) { close in
      PivotFieldsSheet(viewModel: viewModel, pivot: pivot, onDismiss: close)
    }
  }
}
