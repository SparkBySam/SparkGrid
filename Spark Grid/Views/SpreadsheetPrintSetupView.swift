import SparkGridCore
import SwiftUI

struct SpreadsheetPrintSetupView: View {
  @Bindable var viewModel: SpreadsheetViewModel
  @State private var options: SpreadsheetPrintOptions
  /// Export as PDF opens this window with Save PDF as its main button.
  let exportsPDF: Bool
  let onCancel: () -> Void
  let onPrint: (SpreadsheetPrintOptions) -> Void
  let onSavePDF: (SpreadsheetPrintOptions) -> Void

  init(
    viewModel: SpreadsheetViewModel,
    options: SpreadsheetPrintOptions,
    exportsPDF: Bool = false,
    onCancel: @escaping () -> Void,
    onPrint: @escaping (SpreadsheetPrintOptions) -> Void,
    onSavePDF: @escaping (SpreadsheetPrintOptions) -> Void
  ) {
    self._viewModel = Bindable(wrappedValue: viewModel)
    _options = State(initialValue: options)
    self.exportsPDF = exportsPDF
    self.onCancel = onCancel
    self.onPrint = onPrint
    self.onSavePDF = onSavePDF
  }

  private var pages: [SpreadsheetPrintPage] {
    viewModel.commitEditIfNeeded()
    return options.pages(for: viewModel)
  }

  private var previewContent: SpreadsheetPrintPreviewContent {
    SpreadsheetPrintPreviewContent(
      contentRevision: viewModel.contentRevision,
      options: options,
      pages: pages,
      workbook: viewModel.workbook
    )
  }

  private var rangeSummary: String {
    guard let page = pages.first else { return "No content" }
    let range = page.range.normalized
    let start = CellAddress(row: range.minRow, col: range.minCol).a1
    let end = CellAddress(row: range.maxRow, col: range.maxCol).a1
    if start == end { return start }
    return "\(start):\(end)"
  }

  private var hasFrozenRows: Bool { viewModel.activeSheet.frozenRows > 0 }
  private var hasFrozenColumns: Bool { viewModel.activeSheet.frozenColumns > 0 }

  var body: some View {
    VStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 2) {
        Text(exportsPDF ? "Export as PDF" : "Print")
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(SparkStyle.label)
        Text("\(viewModel.activeSheet.name) · \(scopeLabel)")
          .font(.system(size: 12))
          .foregroundStyle(SparkStyle.secondaryLabel)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 20)
      .padding(.top, 16)
      .padding(.bottom, 12)

      HStack(alignment: .top, spacing: 16) {
        previewPane
        ScrollView {
          settings
        }
        .frame(width: 330)
      }
      .padding(.horizontal, 20)
      .padding(.bottom, 16)
      .frame(maxHeight: .infinity)

      Divider()

      HStack(spacing: 8) {
        Text(pageCountLabel)
          .font(.system(size: 12))
          .foregroundStyle(SparkStyle.secondaryLabel)
        Spacer()
        Button("Cancel", action: onCancel)
          .keyboardShortcut(.cancelAction)
        Button(exportsPDF ? "Print…" : "Save as PDF…") {
          if exportsPDF { onPrint(options) } else { onSavePDF(options) }
        }
        .disabled(pages.isEmpty)
        Button(exportsPDF ? "Save PDF…" : "Print…") {
          if exportsPDF { onSavePDF(options) } else { onPrint(options) }
        }
        .keyboardShortcut(.defaultAction)
        .buttonStyle(.borderedProminent)
        .tint(SparkStyle.accent)
        .disabled(pages.isEmpty)
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 12)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(SparkStyle.window)
  }

  private var pageCountLabel: String {
    if pages.isEmpty { return "Nothing to print" }
    if options.scope == .workbook {
      return "\(pages.count) \(pages.count == 1 ? "sheet" : "sheets")"
    }
    return "Range \(rangeSummary)"
  }

  private var previewPane: some View {
    Group {
      if pages.isEmpty {
        ContentUnavailableView(
          "Nothing to print",
          systemImage: "printer",
          description: Text("Choose a different print range.")
        )
      } else {
        SpreadsheetPrintPagePreview(content: previewContent)
          .id(previewContent.renderToken)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(RoundedRectangle(cornerRadius: 8).fill(SparkStyle.chrome))
    .overlay(RoundedRectangle(cornerRadius: 8).stroke(SparkStyle.separator, lineWidth: 1))
  }

  private var scopeLabel: String {
    switch options.scope {
    case .printArea:
      return "Printing the print area"
    case .selectedCells:
      return "Printing \(rangeSummary)"
    case .populatedCells:
      return "Printing the cells in use"
    case .wholeSheet:
      return "Printing the whole sheet"
    case .workbook:
      return "Printing every sheet"
    }
  }

  private func menuPicker<Value: Hashable, Items: View>(
    _ label: String, selection: Binding<Value>, @ViewBuilder items: () -> Items
  ) -> some View {
    let content = items()
    return SparkDialogRow(label: label) {
      Picker(label, selection: selection) { content }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
    }
  }

  private func switchRow(_ label: String, isOn: Binding<Bool>, disabled: Bool = false) -> some View
  {
    SparkDialogRow(label: label) {
      Toggle("", isOn: isOn)
        .toggleStyle(.switch)
        .controlSize(.small)
        .labelsHidden()
        .tint(SparkStyle.accent)
        .disabled(disabled)
    }
    .opacity(disabled ? 0.5 : 1)
  }

  private var settings: some View {
    VStack(alignment: .leading, spacing: 12) {
      SparkDialogSection(title: "What to print")
      SparkDialogGroup {
        menuPicker("Print", selection: $options.scope) {
          ForEach(SpreadsheetPrintScope.allCases) { scope in
            if options.canUseScope(scope, viewModel: viewModel) {
              Text(scope.rawValue).tag(scope)
            }
          }
        }
        SparkDialogDivider()
        switchRow("Gridlines", isOn: $options.showGridlines)
        SparkDialogDivider()
        switchRow("Repeat frozen rows", isOn: $options.repeatFrozenRows, disabled: !hasFrozenRows)
        SparkDialogDivider()
        switchRow(
          "Repeat frozen columns", isOn: $options.repeatFrozenColumns, disabled: !hasFrozenColumns)
      }
      if !hasFrozenRows && !hasFrozenColumns {
        Text("Freeze rows or columns (Sheet ▸ Freeze) to repeat them on every page.")
          .font(.system(size: 11))
          .foregroundStyle(SparkStyle.secondaryLabel)
          .fixedSize(horizontal: false, vertical: true)
      }

      SparkDialogSection(title: "Page")
      SparkDialogGroup {
        SparkDialogRow(label: "Orientation") {
          SparkSegmentedPicker(
            selection: $options.isLandscape, options: [(false, "Portrait"), (true, "Landscape")],
            equalWidths: true)
        }
        SparkDialogDivider()
        menuPicker("Paper", selection: $options.paper) {
          ForEach(SpreadsheetPrintPaper.allCases) { Text($0.rawValue).tag($0) }
        }
        SparkDialogDivider()
        menuPicker("Fit", selection: $options.scale) {
          ForEach(SpreadsheetPrintScale.allCases) { Text($0.rawValue).tag($0) }
        }
        SparkDialogDivider()
        menuPicker("Margins", selection: $options.margins) {
          ForEach(SpreadsheetPrintMarginPreset.allCases) { Text($0.rawValue).tag($0) }
        }
        SparkDialogDivider()
        menuPicker("Page order", selection: $options.pageOrder) {
          ForEach(SpreadsheetPrintPageOrder.allCases) { Text($0.rawValue).tag($0) }
        }
        SparkDialogDivider()
        menuPicker("Across the page", selection: $options.horizontalAlign) {
          ForEach(SpreadsheetPrintHorizontalAlign.allCases) { Text($0.rawValue).tag($0) }
        }
        SparkDialogDivider()
        menuPicker("Down the page", selection: $options.verticalAlign) {
          ForEach(SpreadsheetPrintVerticalAlign.allCases) { Text($0.rawValue).tag($0) }
        }
      }

      SparkDialogSection(title: "Header & footer")
      SparkDialogGroup {
        switchRow("Page numbers", isOn: $options.headersFooters.pageNumbers)
        SparkDialogDivider()
        switchRow("Workbook title", isOn: $options.headersFooters.workbookTitle)
        SparkDialogDivider()
        switchRow("Sheet name", isOn: $options.headersFooters.sheetName)
        SparkDialogDivider()
        switchRow("Date", isOn: $options.headersFooters.currentDate)
        SparkDialogDivider()
        switchRow("Time", isOn: $options.headersFooters.currentTime)
      }
    }
  }
}
