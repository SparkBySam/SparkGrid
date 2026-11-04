import SparkGridCore
import SwiftUI

/// Find Duplicates: choose the columns that make two rows the same, see what matches, then
/// highlight the rows for now or remove the repeats.
struct DuplicatesSheet: View {
  var viewModel: SpreadsheetViewModel
  @Environment(\.dismiss) private var dismiss
  @State private var range: CellRange?
  @State private var hasHeader = true
  @State private var columns: Set<Int> = []
  @State private var unique = false
  @State private var message: String?

  var body: some View {
    SparkDialog(
      title: "Duplicates",
      subtitle: subtitle,
      primaryTitle: primaryTitle,
      primaryDisabled: primaryDisabled,
      onCancel: close,
      onPrimary: primary,
      leading: {
        if !unique {
          Button("Highlight") { highlight() }
            .disabled(request == nil || scan?.groups.isEmpty != false)
            .help("Shade the matching rows until you clear them. The file isn't changed.")
        }
      },
      content: { content }
    )
    .frame(width: 520)
    .onAppear(perform: configure)
  }

  // MARK: - Content

  @ViewBuilder
  private var content: some View {
    if let range {
      SparkDialogGroup {
        SparkDialogRow(label: "Cells") {
          Text(range.a1Label)
            .font(.system(size: 12, design: .monospaced))
          Spacer(minLength: 8)
          Button("Use Selection") { adoptSelection() }
            .controlSize(.small)
        }
        SparkDialogDivider()
        SparkDialogRow(label: "First row is headers") {
          Toggle("", isOn: $hasHeader).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
        SparkDialogDivider()
        SparkDialogRow(label: "Find") {
          Picker("", selection: $unique) {
            Text("Repeated rows").tag(false)
            Text("Rows that appear once").tag(true)
          }
          .labelsHidden()
          .pickerStyle(.segmented)
          .frame(width: 280)
        }
      }

      HStack {
        SparkDialogSection(title: "Rows match when these columns match")
        Spacer()
        Button("All") { columns = Set(allColumns) }
          .buttonStyle(.link)
          .font(.system(size: 11))
        Button("None") { columns = [] }
          .buttonStyle(.link)
          .font(.system(size: 11))
      }
      SparkDialogGroup {
        ScrollView {
          VStack(alignment: .leading, spacing: 6) {
            ForEach(allColumns, id: \.self) { col in
              Toggle(isOn: columnBinding(col)) {
                HStack(spacing: 8) {
                  Text(A1Notation.columnLabel(for: col))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(SparkStyle.secondaryLabel)
                    .frame(width: 26, alignment: .leading)
                  Text(columnName(col))
                    .lineLimit(1)
                }
              }
              .toggleStyle(.checkbox)
            }
          }
          .padding(10)
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 150)
      }

      summary
    } else {
      Text("Select the cells to check, or click inside a table.")
        .foregroundStyle(SparkStyle.secondaryLabel)
    }
  }

  private var summary: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(summaryTitle)
        .font(.system(size: 13, weight: .semibold))
      if let detail = summaryDetail {
        Text(detail)
          .font(.system(size: 11))
          .foregroundStyle(SparkStyle.secondaryLabel)
          .fixedSize(horizontal: false, vertical: true)
      }
      if !unique, let scan, !scan.groups.isEmpty {
        ForEach(Array(scan.groups.prefix(3).enumerated()), id: \.offset) { _, rows in
          Text(groupLine(rows))
            .font(.system(size: 11, design: .monospaced))
            .lineLimit(1)
            .truncationMode(.tail)
        }
        if scan.groups.count > 3 {
          Text("and \(scan.groups.count - 3) more")
            .font(.system(size: 11))
            .foregroundStyle(SparkStyle.secondaryLabel)
        }
      }
      if let message {
        Text(message)
          .font(.system(size: 11))
          .foregroundStyle(.red)
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: 8).fill(SparkStyle.chrome))
    .overlay(RoundedRectangle(cornerRadius: 8).stroke(SparkStyle.separator, lineWidth: 1))
  }

  // MARK: - State

  private var allColumns: [Int] {
    guard let range else { return [] }
    let n = range.normalized
    return Array(n.minCol...n.maxCol)
  }

  private var request: SpreadsheetViewModel.DuplicateRequest? {
    guard let range, !columns.isEmpty else { return nil }
    return SpreadsheetViewModel.DuplicateRequest(
      sheetID: viewModel.activeSheet.id, range: range, hasHeader: hasHeader,
      columns: columns.sorted(), unique: unique)
  }

  private var scan: SpreadsheetViewModel.DuplicateScan? {
    request.map { viewModel.scanDuplicates($0) }
  }

  private var subtitle: String {
    "Compared ignoring capitals and extra spaces. Rows a filter hides are left out."
  }

  private var primaryTitle: String {
    if unique { return "Highlight" }
    let count = scan?.repeatRows.count ?? 0
    return count == 0 ? "Remove" : "Remove \(count) \(count == 1 ? "Row" : "Rows")"
  }

  private var primaryDisabled: Bool {
    guard let scan else { return true }
    return unique ? scan.uniqueRows.isEmpty : scan.repeatRows.isEmpty
  }

  private var summaryTitle: String {
    guard let scan else { return "Choose at least one column" }
    if unique {
      let count = scan.uniqueRows.count
      return count == 0
        ? "Every row repeats" : "\(count) \(count == 1 ? "row appears" : "rows appear") once"
    }
    guard !scan.groups.isEmpty else { return "No repeated rows" }
    let groups = scan.groups.count
    return "\(scan.duplicateRowCount) rows repeat, in \(groups) \(groups == 1 ? "group" : "groups")"
  }

  private var summaryDetail: String? {
    guard let scan, !unique, !scan.groups.isEmpty else { return nil }
    let removed = scan.repeatRows.count
    return
      "Remove keeps the first row of each group and deletes the other \(removed), moving the rows "
      + "below up. Undo puts them back."
  }

  /// `Rows 4, 9, 12: Acme · East`
  private func groupLine(_ rows: [Int]) -> String {
    let first = rows[0]
    let values = columns.sorted().map {
      viewModel.displayString(at: CellAddress(row: first, col: $0))
    }
    let shown = rows.prefix(6).map { String($0 + 1) }.joined(separator: ", ")
    let more = rows.count > 6 ? "…" : ""
    return "Rows \(shown)\(more): \(values.joined(separator: " · "))"
  }

  private func columnName(_ col: Int) -> String {
    guard let range, hasHeader else { return "Column \(A1Notation.columnLabel(for: col))" }
    let text = viewModel.displayString(
      at: CellAddress(row: range.normalized.minRow, col: col))
    return text.isEmpty ? "Column \(A1Notation.columnLabel(for: col))" : text
  }

  private func columnBinding(_ col: Int) -> Binding<Bool> {
    Binding(
      get: { columns.contains(col) },
      set: { on in
        if on { columns.insert(col) } else { columns.remove(col) }
        message = nil
      })
  }

  private func configure() {
    guard range == nil else { return }
    adoptSelection()
  }

  private func adoptSelection() {
    range = viewModel.duplicateRange()
    if let range {
      hasHeader = viewModel.duplicateRangeLooksHeaded(range)
      columns = Set(allColumns)
    }
    message = nil
  }

  // MARK: - Actions

  private func close() {
    viewModel.isDuplicatesSheetPresented = false
    dismiss()
  }

  private func highlight() {
    guard let request else { return }
    viewModel.showDuplicateHighlight(request)
    close()
  }

  private func primary() {
    if unique {
      highlight()
      return
    }
    guard let request else { return }
    switch viewModel.removeDuplicates(request) {
    case .removed:
      viewModel.clearDuplicateHighlight()
      close()
    case .noneFound:
      message = "No repeated rows to remove."
    case .filterHidesRows:
      message = "A filter is hiding rows here. Clear the filter first, so no hidden row is removed."
    case .nothingToCheck:
      message = "Choose at least two rows to check."
    }
  }
}
