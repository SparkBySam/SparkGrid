import SparkGridCore
import SwiftUI

/// Insert ▸ Link: a web or email address, or a place in this workbook, for the selected cells.
struct LinkSheet: View {
  @Bindable var viewModel: SpreadsheetViewModel
  let onDismiss: () -> Void

  private enum Mode: String, CaseIterable, Identifiable {
    case web = "Web or email"
    case place = "Place in this workbook"
    var id: String { rawValue }
  }

  @State private var mode: Mode = .web
  @State private var text: String
  @State private var address = ""
  @State private var place = ""
  private let existing: CellHyperlink?

  init(viewModel: SpreadsheetViewModel, onDismiss: @escaping () -> Void) {
    self.viewModel = viewModel
    self.onDismiss = onDismiss
    let link = viewModel.selectedHyperlink
    existing = link
    let cell = viewModel.activeSheet.cell(at: viewModel.selectionAnchor).raw
    _text = State(initialValue: FormulaSyntax.isFormula(cell) ? "" : cell)
    if let location = link?.location {
      _mode = State(initialValue: .place)
      _place = State(initialValue: location)
    } else if let target = link?.target {
      _address = State(
        initialValue: target.hasPrefix("mailto:") ? String(target.dropFirst(7)) : target)
    }
  }

  private var isFormulaCell: Bool {
    FormulaSyntax.isFormula(viewModel.activeSheet.cell(at: viewModel.selectionAnchor).raw)
  }

  private var placeIsValid: Bool {
    SpreadsheetViewModel.workbookPlace(
      place, in: viewModel.workbook, activeSheet: viewModel.activeSheet.name) != nil
  }

  private var canApply: Bool {
    switch mode {
    case .web: return SpreadsheetViewModel.webAddress(from: address) != nil
    case .place: return placeIsValid
    }
  }

  /// Sheets, then defined names, for the place menu.
  private var placeChoices: [String] {
    let sheets = viewModel.workbook.sheets.filter { !$0.isHidden }.map { sheet -> String in
      let quoted =
        sheet.name.range(of: #"^[A-Za-z_][A-Za-z0-9_.]*$"#, options: .regularExpression) == nil
        ? "'" + sheet.name.replacingOccurrences(of: "'", with: "''") + "'" : sheet.name
      return quoted + "!A1"
    }
    let names = viewModel.workbook.namedRanges.values
      .filter { $0.resolvesToRange && !$0.name.lowercased().hasPrefix("_xlnm.") }
      .map(\.name).sorted()
    return sheets + names
  }

  var body: some View {
    SparkDialog(
      title: existing == nil ? "Insert Link" : "Edit Link",
      subtitle: "Applies to \(viewModel.selectionRange.a1Label)",
      primaryTitle: existing == nil ? "Insert" : "Save",
      primaryDisabled: !canApply,
      onCancel: onDismiss,
      onPrimary: apply,
      leading: {
        if existing != nil {
          Button("Remove Link", role: .destructive) {
            viewModel.removeLink()
            onDismiss()
          }
        }
      },
      content: {
        SparkSegmentedPicker(
          selection: $mode, options: Mode.allCases.map { ($0, $0.rawValue) }, equalWidths: true)
        SparkDialogGroup {
          SparkDialogRow(label: "Text") {
            TextField(isFormulaCell ? "The cell's formula stays" : "Shown in the cell", text: $text)
              .textFieldStyle(.roundedBorder)
              .frame(width: 240)
              .disabled(isFormulaCell)
          }
          SparkDialogDivider()
          switch mode {
          case .web:
            SparkDialogRow(label: "Address") {
              TextField(String("example.com or name@example.com"), text: $address)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
            }
          case .place:
            SparkDialogRow(label: "Go to") {
              HStack(spacing: 6) {
                TextField(String("Sheet2!B4 or a name"), text: $place)
                  .textFieldStyle(.roundedBorder)
                  .font(.system(size: 12, design: .monospaced))
                  .frame(width: 190)
                Menu {
                  ForEach(placeChoices, id: \.self) { choice in
                    Button(choice) { place = choice }
                  }
                } label: {
                  Image(systemName: "list.bullet")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
              }
            }
          }
        }
        Text(hint)
          .font(.system(size: 11))
          .foregroundStyle(
            mode == .place && !place.isEmpty && !placeIsValid
              ? Color(nsColor: .systemRed) : SparkStyle.secondaryLabel)
      }
    )
  }

  private var hint: String {
    switch mode {
    case .web:
      return "Command-click the cell to open the link."
    case .place:
      if !place.isEmpty, !placeIsValid { return "No sheet, cell or name by that name." }
      return "A cell, a range or a defined name. Command-click the cell to go there."
    }
  }

  private func apply() {
    switch mode {
    case .web: viewModel.setLink(text: text, destination: .web(address))
    case .place: viewModel.setLink(text: text, destination: .place(place))
    }
    onDismiss()
  }
}

@MainActor
enum LinkPresenter {
  static func present(from viewModel: SpreadsheetViewModel, in window: NSWindow? = nil) {
    viewModel.commitEditIfNeeded()
    SparkDialogPresenter.present(title: "Link", width: 440, in: window) { close in
      LinkSheet(viewModel: viewModel, onDismiss: close)
    }
  }
}
