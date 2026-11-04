import AppKit
import SparkGridCore
import SwiftUI

/// Edit Chart for a chart from another app. Changes are written into the chart's own part, so
/// other apps open the edited chart.
struct EditImportedChartSheet: View {
  var viewModel: SpreadsheetViewModel
  let chartID: Int
  @Environment(\.dismiss) private var dismiss
  @State private var edit: ImportedChartEdit?
  @State private var failed = false

  var body: some View {
    SparkDialog(
      title: "Edit Chart",
      subtitle: subtitle,
      primaryTitle: "Update Chart",
      primaryDisabled: edit == nil || !isValid,
      onCancel: { close() },
      onPrimary: save
    ) {
      if let binding = Binding($edit) {
        content(binding)
      } else {
        Text("This chart can't be read.")
          .foregroundStyle(SparkStyle.secondaryLabel)
      }
    }
    .frame(width: 560)
    .onAppear {
      if edit == nil { edit = viewModel.importedChartEdit(chartID) }
    }
  }

  private var subtitle: String {
    failed
      ? "A range couldn't be used. Check the ranges in red."
      : "Changes are saved in the chart itself, so other apps show them too."
  }

  private func close() {
    viewModel.editingImportedChartID = nil
    dismiss()
  }

  private func save() {
    guard let edit else { return }
    if viewModel.applyImportedChartEdit(chartID, edit) {
      close()
    } else {
      failed = true
    }
  }

  // MARK: - Content

  @ViewBuilder
  private func content(_ edit: Binding<ImportedChartEdit>) -> some View {
    if edit.wrappedValue.canChangeKind {
      kindTiles(edit)
    }
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        SparkDialogGroup {
          SparkDialogRow(label: "Title") {
            TextField("No title", text: edit.title)
              .textFieldStyle(.roundedBorder)
              .frame(width: 260)
          }
          if edit.wrappedValue.canStack {
            SparkDialogDivider()
            SparkDialogRow(label: "Stacked") {
              Toggle("", isOn: edit.isStacked).labelsHidden().toggleStyle(.switch)
                .controlSize(.small)
            }
          }
          SparkDialogDivider()
          SparkDialogRow(label: "Legend") {
            Toggle("", isOn: edit.showsLegend).labelsHidden().toggleStyle(.switch)
              .controlSize(.small)
          }
          if edit.wrappedValue.hasAxes, edit.wrappedValue.kind != .scatter {
            SparkDialogDivider()
            SparkDialogRow(label: "Label axis title") {
              TextField("None", text: edit.categoryAxisTitle)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
            }
            SparkDialogDivider()
            SparkDialogRow(label: "Value axis title") {
              TextField("None", text: edit.valueAxisTitle)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
            }
          }
        }

        SparkDialogSection(title: "Series")
        ForEach(edit.series.indices, id: \.self) { index in
          seriesGroup(edit, index: index)
        }
        if edit.wrappedValue.kind != .pie, edit.wrappedValue.kind != .doughnut {
          Button {
            addSeries(edit)
          } label: {
            Label("Add Series", systemImage: "plus")
          }
          .controlSize(.small)
        }
      }
    }
    .frame(maxHeight: 460)
  }

  private func kindTiles(_ edit: Binding<ImportedChartEdit>) -> some View {
    HStack(spacing: 8) {
      ForEach(ImportedChartEdit.switchableKinds, id: \.self) { kind in
        let selected = edit.wrappedValue.kind == kind
        Button {
          edit.wrappedValue.kind = kind
          if kind == .line { edit.wrappedValue.isStacked = false }
        } label: {
          VStack(spacing: 4) {
            Image(systemName: Self.symbol(kind)).font(.system(size: 18))
            Text(Self.title(kind))
              .font(.system(size: 12, weight: selected ? .semibold : .regular))
          }
          .foregroundStyle(selected ? SparkStyle.label : SparkStyle.secondaryLabel)
          .frame(maxWidth: .infinity)
          .frame(height: 52)
          .background(
            RoundedRectangle(cornerRadius: 8)
              .fill(selected ? SparkStyle.accent.opacity(0.14) : SparkStyle.chrome)
          )
          .overlay(
            RoundedRectangle(cornerRadius: 8)
              .stroke(
                selected ? SparkStyle.accent : SparkStyle.separator, lineWidth: selected ? 2 : 1)
          )
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : AccessibilityTraits())
      }
    }
  }

  private func seriesGroup(_ edit: Binding<ImportedChartEdit>, index: Int) -> some View {
    let series = edit.series[index]
    let scatter = edit.wrappedValue.kind == .scatter
    return SparkDialogGroup {
      SparkDialogRow(label: "Name") {
        if series.wrappedValue.nameFormula.isEmpty {
          TextField("Series \(index + 1)", text: series.name)
            .textFieldStyle(.roundedBorder)
            .frame(width: 180)
        } else {
          rangeField(series.nameFormula, placeholder: "B1", allowsEmpty: true)
        }
        Spacer(minLength: 4)
        if edit.wrappedValue.canColorSeries {
          ColorPicker(
            "",
            selection: Binding(
              get: { color(for: series.wrappedValue, at: index) },
              set: { series.wrappedValue.colorHex = Self.hex($0) }),
            supportsOpacity: false
          )
          .labelsHidden()
          .help("Series color")
        }
        if edit.wrappedValue.series.count > 1 {
          Button {
            edit.wrappedValue.series.remove(at: index)
          } label: {
            Image(systemName: "minus.circle")
          }
          .buttonStyle(.borderless)
          .help("Remove this series")
        }
      }
      SparkDialogDivider()
      SparkDialogRow(label: scatter ? "X values" : "Labels") {
        rangeField(series.categoriesFormula, placeholder: "A2:A13", allowsEmpty: true)
      }
      SparkDialogDivider()
      SparkDialogRow(label: scatter ? "Y values" : "Values") {
        rangeField(series.valuesFormula, placeholder: "B2:B13", allowsEmpty: false)
      }
    }
  }

  private func rangeField(_ text: Binding<String>, placeholder: String, allowsEmpty: Bool)
    -> some View
  {
    let valid = Self.isValidRange(text.wrappedValue, allowsEmpty: allowsEmpty)
    return TextField(placeholder, text: text)
      .textFieldStyle(.roundedBorder)
      .font(.system(size: 12, design: .monospaced))
      .autocorrectionDisabled()
      .frame(width: 260)
      .overlay(
        RoundedRectangle(cornerRadius: 5)
          .stroke(valid ? Color.clear : Color.red, lineWidth: 1.5)
      )
  }

  // MARK: - Helpers

  private var isValid: Bool {
    guard let edit else { return false }
    return edit.series.allSatisfy { series in
      Self.isValidRange(series.valuesFormula, allowsEmpty: false)
        && Self.isValidRange(series.categoriesFormula, allowsEmpty: true)
        && Self.isValidRange(series.nameFormula, allowsEmpty: true)
    }
  }

  static func isValidRange(_ text: String, allowsEmpty: Bool) -> Bool {
    if text.trimmingCharacters(in: .whitespaces).isEmpty { return allowsEmpty }
    return ImportedChartEdit.qualifiedFormula(text, sheetName: "Sheet") != nil
  }

  /// A new series reads the column after the last series' values, with the same labels.
  private func addSeries(_ edit: Binding<ImportedChartEdit>) {
    let last = edit.wrappedValue.series.last
    var values = ""
    if let formula = last?.valuesFormula,
      let reference = ImportedChartReader.reference(formula)
    {
      var next = reference
      let n = reference.range.normalized
      if n.minCol == n.maxCol {
        next.range = CellRange(
          start: CellAddress(row: n.minRow, col: n.maxCol + 1),
          end: CellAddress(row: n.maxRow, col: n.maxCol + 1))
      } else {
        next.range = CellRange(
          start: CellAddress(row: n.maxRow + 1, col: n.minCol),
          end: CellAddress(row: n.maxRow + 1, col: n.maxCol))
      }
      values = ImportedChartEdit.formula(next, sheetName: viewModel.activeSheet.name)
    }
    edit.wrappedValue.series.append(
      ImportedChartEdit.Series(
        name: "Series \(edit.wrappedValue.series.count + 1)",
        categoriesFormula: last?.categoriesFormula ?? "",
        valuesFormula: values))
  }

  private func color(for series: ImportedChartEdit.Series, at index: Int) -> Color {
    if let hex = series.colorHex, let color = ImportedChartPlot.color(hex: hex) { return color }
    return ImportedChartPlot.palette[index % ImportedChartPlot.palette.count]
  }

  static func hex(_ color: Color) -> String? {
    guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
    func byte(_ value: CGFloat) -> Int { Int((min(1, max(0, value)) * 255).rounded()) }
    return String(
      format: "%02X%02X%02X", byte(rgb.redComponent), byte(rgb.greenComponent),
      byte(rgb.blueComponent))
  }

  private static func symbol(_ kind: ImportedChart.Kind) -> String {
    switch kind {
    case .column: return "chart.bar.fill"
    case .bar: return "chart.bar.xaxis"
    case .line: return "chart.xyaxis.line"
    case .area: return "chart.line.uptrend.xyaxis"
    case .pie: return "chart.pie.fill"
    case .doughnut: return "circle.circle"
    case .scatter: return "chart.dots.scatter"
    }
  }

  static func title(_ kind: ImportedChart.Kind) -> String {
    switch kind {
    case .column: return "Column"
    case .bar: return "Bar"
    case .line: return "Line"
    case .area: return "Area"
    case .pie: return "Pie"
    case .doughnut: return "Doughnut"
    case .scatter: return "Scatter"
    }
  }
}
