import AppKit
import SparkGridCore
import SwiftUI

/// Data ▸ Data Validation: what the selected cells may hold, the message shown when pointing at
/// them, and the alert when an entry breaks the rule. Lists have their own dialog.
struct DataValidationSheet: View {
  @Bindable var viewModel: SpreadsheetViewModel
  let onDismiss: () -> Void

  @State private var parts: DataValidationRule.Parts
  private let hadRule: Bool

  private static let kinds: [(DataValidationRule.Kind, String)] = [
    (.whole, "Whole number"), (.decimal, "Decimal"), (.date, "Date"), (.time, "Time"),
    (.textLength, "Text length"), (.custom, "Custom formula"),
  ]
  private static let comparisons: [(DataValidationRule.Comparison, String)] = [
    (.between, "between"), (.notBetween, "not between"), (.equal, "equal to"),
    (.notEqual, "not equal to"), (.greaterThan, "greater than"), (.lessThan, "less than"),
    (.greaterThanOrEqual, "greater than or equal to"),
    (.lessThanOrEqual, "less than or equal to"),
  ]

  init(viewModel: SpreadsheetViewModel, onDismiss: @escaping () -> Void) {
    self.viewModel = viewModel
    self.onDismiss = onDismiss
    let existing = viewModel.selectedValidationParts
    hadRule = existing != nil
    var start = existing ?? DataValidationRule.Parts()
    if start.kind == .any || start.kind == .list { start.kind = .whole }
    _parts = State(initialValue: start)
  }

  private var canApply: Bool {
    !parts.formula1.trimmingCharacters(in: .whitespaces).isEmpty
      && (parts.kind == .custom || !parts.comparison.takesTwo
        || !parts.formula2.trimmingCharacters(in: .whitespaces).isEmpty)
  }

  private var valueHint: String {
    switch parts.kind {
    case .date: return "1/1/2026 or =TODAY()"
    case .time: return "9:00 or 0.375"
    default: return "10, $B$1 or =B1*2"
    }
  }

  var body: some View {
    SparkDialog(
      title: "Data Validation",
      subtitle: "Applies to \(viewModel.selectionRange.a1Label)",
      primaryTitle: "Apply",
      primaryDisabled: !canApply,
      onCancel: onDismiss,
      onPrimary: apply,
      leading: {
        if hadRule {
          Button("Clear Rule", role: .destructive) {
            viewModel.clearValidation()
            onDismiss()
          }
        }
      },
      content: {
        SparkDialogGroup {
          SparkDialogRow(label: "Allow") {
            Picker("", selection: $parts.kind) {
              ForEach(Self.kinds, id: \.0) { kind, title in Text(title).tag(kind) }
            }
            .labelsHidden()
            .frame(width: 190)
          }
          if parts.kind != .custom {
            SparkDialogDivider()
            SparkDialogRow(label: parts.kind == .textLength ? "Length is" : "Value is") {
              Picker("", selection: $parts.comparison) {
                ForEach(Self.comparisons, id: \.0) { c, title in Text(title).tag(c) }
              }
              .labelsHidden()
              .frame(width: 190)
            }
          }
          SparkDialogDivider()
          SparkDialogRow(
            label: parts.kind == .custom
              ? "Formula" : (parts.comparison.takesTwo ? "Minimum" : "Value")
          ) {
            TextField(
              parts.kind == .custom ? "=COUNTIF($A:$A,A1)=1" : valueHint, text: $parts.formula1
            )
            .textFieldStyle(.roundedBorder)
            .frame(width: 190)
          }
          if parts.kind != .custom, parts.comparison.takesTwo {
            SparkDialogDivider()
            SparkDialogRow(label: "Maximum") {
              TextField(valueHint, text: $parts.formula2)
                .textFieldStyle(.roundedBorder)
                .frame(width: 190)
            }
          }
          SparkDialogDivider()
          SparkDialogRow(label: "Allow empty cells") {
            Toggle("", isOn: $parts.allowBlank).toggleStyle(.switch).controlSize(.small)
              .labelsHidden().tint(SparkStyle.accent)
          }
        }
        if parts.kind == .custom {
          Text("The formula is written for the first selected cell and must give TRUE.")
            .font(.system(size: 11))
            .foregroundStyle(SparkStyle.secondaryLabel)
        }

        SparkDialogSection(title: "Message when pointing at a cell")
        SparkDialogGroup {
          SparkDialogRow(label: "Title") {
            TextField("Optional", text: $parts.promptTitle).textFieldStyle(.roundedBorder)
              .frame(width: 190)
          }
          SparkDialogDivider()
          SparkDialogRow(label: "Message") {
            TextField("Optional", text: $parts.prompt).textFieldStyle(.roundedBorder)
              .frame(width: 190)
          }
        }

        SparkDialogSection(title: "When an entry breaks the rule")
        SparkDialogGroup {
          SparkDialogRow(label: "Show an alert") {
            Toggle("", isOn: $parts.showError).toggleStyle(.switch).controlSize(.small)
              .labelsHidden().tint(SparkStyle.accent)
          }
          if parts.showError {
            SparkDialogDivider()
            SparkDialogRow(label: "Alert") {
              SparkSegmentedPicker(
                selection: $parts.alertStyle,
                options: [(.stop, "Stop"), (.warning, "Warning"), (.information, "Info")],
                equalWidths: true
              )
              .frame(width: 190)
              SparkInfoButton(
                title: "Alert styles",
                text: "Stop refuses an entry that breaks the rule. Warning asks whether to keep "
                  + "it anyway. Info says it breaks the rule and keeps it unless you cancel.")
            }
            SparkDialogDivider()
            SparkDialogRow(label: "Title") {
              TextField("Optional", text: $parts.errorTitle).textFieldStyle(.roundedBorder)
                .frame(width: 190)
            }
            SparkDialogDivider()
            SparkDialogRow(label: "Message") {
              TextField("Optional", text: $parts.error).textFieldStyle(.roundedBorder)
                .frame(width: 190)
            }
          }
        }
        Text(
          "Stop refuses the entry, Warning asks whether to keep it, Info tells and keeps it. "
            + "For a list of choices, use Data › Dropdown List."
        )
        .font(.system(size: 11))
        .foregroundStyle(SparkStyle.secondaryLabel)
        .fixedSize(horizontal: false, vertical: true)
      }
    )
  }

  private func apply() {
    var rule = parts
    rule.showInput = !(rule.prompt.isEmpty && rule.promptTitle.isEmpty)
    viewModel.setValidation(rule)
    onDismiss()
  }
}
