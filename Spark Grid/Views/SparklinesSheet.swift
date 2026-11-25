import AppKit
import SparkGridCore
import SwiftUI

/// Insert ▸ Sparklines: small line, column or win/loss charts inside cells, one for each row or
/// column of the data.
struct SparklinesSheet: View {
  @Bindable var viewModel: SpreadsheetViewModel
  let onDismiss: () -> Void

  @State private var kind: SparklineGroup.Kind = .line
  @State private var dataText: String
  @State private var locationText: String
  @State private var color = Color(nsColor: SparklineLayerView.color(SparklineGroup.defaultColor))
  @State private var showsMarkers = false
  @State private var showsHighLow = false
  @State private var message: String?

  init(viewModel: SpreadsheetViewModel, onDismiss: @escaping () -> Void) {
    self.viewModel = viewModel
    self.onDismiss = onDismiss
    // A whole column, row or sheet selected stops at the last row and column with data.
    let picked = viewModel.selectionRange.normalized
    let sheet = viewModel.activeSheet
    let selected = (
      minRow: picked.minRow, maxRow: max(picked.minRow, min(picked.maxRow, sheet.maxPopulatedRow)),
      minCol: picked.minCol,
      maxCol: max(picked.minCol, min(picked.maxCol, sheet.maxPopulatedColumn))
    )
    let data = CellRange(
      start: CellAddress(row: selected.minRow, col: selected.minCol),
      end: CellAddress(row: selected.maxRow, col: selected.maxCol))
    _dataText = State(initialValue: data.a1Description)
    // Data across a row or a block: the column to its right. Data down one column: the cell
    // under it.
    let location: CellRange
    if selected.minCol == selected.maxCol, selected.minRow != selected.maxRow {
      let cell = CellAddress(row: selected.maxRow + 1, col: selected.minCol)
      location = CellRange(start: cell, end: cell)
    } else {
      location = CellRange(
        start: CellAddress(row: selected.minRow, col: selected.maxCol + 1),
        end: CellAddress(row: selected.maxRow, col: selected.maxCol + 1))
    }
    _locationText = State(initialValue: location.a1Description)
  }

  var body: some View {
    SparkDialog(
      title: "Insert Sparklines",
      subtitle: "Small charts inside cells, one for each row or column of data",
      primaryTitle: "Insert",
      primaryDisabled: dataRange == nil || locationRange == nil,
      onCancel: onDismiss,
      onPrimary: insert,
      content: {
        HStack(spacing: 8) {
          SparkSegmentedPicker(
            selection: $kind, options: SparklineGroup.Kind.allCases.map { ($0, $0.title) },
            equalWidths: true)
          SparkInfoButton(
            title: "Sparkline types",
            text: "Line follows the numbers' rise and fall. Column shows each number as a bar, "
              + "negatives below the line. Win/Loss shows only whether each number is above zero "
              + "(up) or below (down), for results such as wins and losses or month-on-month "
              + "change.")
        }
        SparkDialogGroup {
          SparkDialogRow(label: "Data") {
            field("B2:M5", text: $dataText)
          }
          SparkDialogDivider()
          SparkDialogRow(label: "Put in") {
            field("N2:N5", text: $locationText)
          }
          SparkDialogDivider()
          SparkDialogRow(label: "Color") {
            ColorPicker("Color", selection: $color, supportsOpacity: false)
              .labelsHidden()
          }
          SparkDialogDivider()
          SparkDialogRow(label: "Show") {
            HStack(spacing: 10) {
              if kind == .line {
                Toggle("Markers", isOn: $showsMarkers)
              }
              Toggle("High and low", isOn: $showsHighLow)
            }
            .toggleStyle(.checkbox)
            .controlSize(.small)
          }
        }
        if let message {
          Text(message)
            .font(.system(size: 11))
            .foregroundStyle(Color(nsColor: .systemRed))
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    )
  }

  private func field(_ prompt: String, text: Binding<String>) -> some View {
    TextField(prompt, text: text)
      .textFieldStyle(.roundedBorder)
      .font(.system(size: 12, design: .monospaced))
      .frame(width: 140)
      .autocorrectionDisabled()
  }

  private var dataRange: (sheet: String?, range: CellRange)? {
    Self.parse(dataText)
  }

  private var locationRange: CellRange? {
    guard let place = Self.parse(locationText), place.sheet == nil else { return nil }
    return place.range
  }

  /// `B2:M5`, `B2`, or `'Sheet 2'!B2:M5`.
  static func parse(_ text: String) -> (sheet: String?, range: CellRange)? {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    if let (start, end) = A1Reference.parseFormulaRange(trimmed) {
      return (start.sheet ?? end.sheet, CellRange(start: start.address, end: end.address))
    }
    if let ref = A1Reference.parseFormulaRef(trimmed) {
      return (ref.sheet, CellRange(start: ref.address, end: ref.address))
    }
    return nil
  }

  private func insert() {
    guard let data = dataRange, let locations = locationRange else { return }
    let rgb = NSColor(color).usingColorSpace(.sRGB) ?? .systemBlue
    let hex = String(
      format: "%02X%02X%02X", Int(rgb.redComponent * 255), Int(rgb.greenComponent * 255),
      Int(rgb.blueComponent * 255))
    if let problem = viewModel.insertSparklines(
      kind: kind, data: data.range, dataSheet: data.sheet, locations: locations, colorHex: hex,
      showsMarkers: kind == .line && showsMarkers, showsHighLow: showsHighLow)
    {
      message = problem
      return
    }
    onDismiss()
  }
}

@MainActor
enum SparklinesPresenter {
  static func present(from viewModel: SpreadsheetViewModel, in window: NSWindow? = nil) {
    viewModel.commitEditIfNeeded()
    SparkDialogPresenter.present(title: "Insert Sparklines", width: 420, in: window) { close in
      SparklinesSheet(viewModel: viewModel, onDismiss: close)
    }
  }
}
