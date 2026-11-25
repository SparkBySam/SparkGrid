import AppKit
import SparkGridCore
import SwiftUI

/// Insert ▸ Formula Help: write a formula from a sentence, or explain the selected cell's, with
/// the model built into the Mac. Nothing leaves the Mac.
struct FormulaHelpSheet: View {
  @Bindable var viewModel: SpreadsheetViewModel
  let onDismiss: () -> Void

  private enum Mode: String, CaseIterable, Identifiable {
    case write = "Write a formula"
    case explain = "Explain this formula"
    var id: String { rawValue }
  }

  @State private var mode: Mode
  @State private var request = ""
  @State private var suggestion: FormulaHelper.Suggestion?
  @State private var explanation = ""
  @State private var working = false
  @State private var failure: String?
  private let availability = FormulaHelper.availability
  private let cell: String
  private let formula: String?

  init(viewModel: SpreadsheetViewModel, onDismiss: @escaping () -> Void) {
    self.viewModel = viewModel
    self.onDismiss = onDismiss
    cell = viewModel.selectionAnchor.a1
    formula = viewModel.selectedFormula
    _mode = State(initialValue: viewModel.selectedFormula == nil ? .write : .explain)
  }

  private var unknownNames: [String] {
    guard let suggestion else { return [] }
    return FormulaHelper.unknownFunctions(in: suggestion.formula) ?? []
  }

  var body: some View {
    SparkDialog(
      title: "Formula Help",
      subtitle: "For \(cell) on \(viewModel.activeSheet.name) · runs on this Mac",
      primaryTitle: mode == .write ? (suggestion == nil ? "Write" : "Insert") : "Done",
      primaryDisabled: primaryDisabled,
      cancelTitle: "Close",
      onCancel: onDismiss,
      onPrimary: primary,
      leading: {
        if working { ProgressView().controlSize(.small) }
      },
      content: { content }
    )
    .task(id: mode) {
      if mode == .explain, explanation.isEmpty, let formula, availability == .available {
        await explain(formula)
      }
    }
  }

  private var primaryDisabled: Bool {
    guard availability == .available, !working else { return mode != .explain }
    switch mode {
    case .write:
      return suggestion == nil
        ? request.trimmingCharacters(in: .whitespaces).isEmpty
        : FormulaHelper.unknownFunctions(in: suggestion?.formula ?? "") == nil
    case .explain:
      return false
    }
  }

  @ViewBuilder private var content: some View {
    switch availability {
    case .unsupported:
      note(
        "Formula help uses Apple Intelligence, which needs macOS 26 or later on a Mac that "
          + "supports it. Everything else in Spark Grid works without it.")
    case .needsAppleIntelligence(let message):
      note(message)
    case .available:
      SparkSegmentedPicker(
        selection: $mode, options: Mode.allCases.map { ($0, $0.rawValue) }, equalWidths: true)
      switch mode {
      case .write: writeContent
      case .explain: explainContent
      }
      if let failure {
        Text(failure).font(.system(size: 11)).foregroundStyle(Color(nsColor: .systemRed))
      }
    }
  }

  @ViewBuilder private var writeContent: some View {
    TextField(
      "What should it work out? For example: total of Sales where Region is West",
      text: $request, axis: .vertical
    )
    .textFieldStyle(.roundedBorder)
    .lineLimit(2...4)
    .onSubmit { if suggestion == nil { primary() } }
    .onChange(of: request) { _, _ in suggestion = nil }
    if let suggestion {
      SparkDialogGroup {
        VStack(alignment: .leading, spacing: 8) {
          Text(suggestion.formula)
            .font(.system(size: 13, design: .monospaced))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
          Text("Result: " + viewModel.previewResult(of: suggestion.formula))
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(SparkStyle.label)
          if !suggestion.explanation.isEmpty {
            Text(suggestion.explanation)
              .font(.system(size: 12))
              .foregroundStyle(SparkStyle.secondaryLabel)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      if FormulaHelper.unknownFunctions(in: suggestion.formula) == nil {
        note("That formula doesn't read as a formula. Try asking another way.")
      } else if !unknownNames.isEmpty {
        note(
          "Spark Grid doesn't have \(unknownNames.joined(separator: ", ")); the cell would show #NAME?."
        )
      } else if viewModel.previewResult(of: suggestion.formula).hasPrefix("#") {
        Text(
          "This gives an error, so it's probably not what you asked for. Try naming the cells, "
            + "such as \u{201C}total of H12:H15\u{201D}."
        )
        .font(.system(size: 11))
        .foregroundStyle(Color(nsColor: .systemOrange))
        .fixedSize(horizontal: false, vertical: true)
      } else {
        note("Insert puts it in \(cell). Check the result: the model can be wrong.")
      }
    }
  }

  @ViewBuilder private var explainContent: some View {
    if let formula {
      Text(formula)
        .font(.system(size: 13, design: .monospaced))
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
      if explanation.isEmpty {
        note(working ? "Reading the formula…" : "")
      } else {
        Text(explanation)
          .font(.system(size: 13))
          .foregroundStyle(SparkStyle.label)
          .textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
      }
    } else {
      note("\(cell) has no formula. Select a cell with one to have it explained.")
    }
  }

  private func note(_ text: String) -> some View {
    Text(text)
      .font(.system(size: 11))
      .foregroundStyle(SparkStyle.secondaryLabel)
      .fixedSize(horizontal: false, vertical: true)
  }

  private func primary() {
    switch mode {
    case .explain:
      onDismiss()
    case .write:
      if let suggestion {
        viewModel.insertSuggestedFormula(suggestion.formula)
        onDismiss()
        return
      }
      let text = request.trimmingCharacters(in: .whitespaces)
      guard !text.isEmpty else { return }
      Task { await write(text) }
    }
  }

  private func write(_ text: String) async {
    working = true
    failure = nil
    defer { working = false }
    do {
      let context = viewModel.formulaHelpContext()
      var written = try await FormulaHelper.write(text, cell: cell, context: context)
      written = FormulaHelper.Suggestion(
        formula: tidied(written.formula), explanation: tidied(written.explanation))
      // An answer that gives an error is asked once more, saying what went wrong: asked for
      // "total of column H for rows 12 to 15" it wrote a SUMIFS that gave #VALUE! (Sam, Nov 20).
      let first = viewModel.previewResult(of: written.formula)
      if first.hasPrefix("#") {
        let retry = try await FormulaHelper.write(
          text + "\nYour last answer, \(written.formula), gave \(first). Write a simpler formula "
            + "that works, such as SUM, AVERAGE or COUNT of the cells asked for.",
          cell: cell, context: context)
        let again = FormulaHelper.Suggestion(
          formula: tidied(retry.formula), explanation: tidied(retry.explanation))
        if !viewModel.previewResult(of: again.formula).hasPrefix("#") { written = again }
      }
      suggestion = written
    } catch {
      failure = "Couldn't write a formula: \(error.localizedDescription)"
    }
  }

  /// The model's text without sheet names it doesn't need: this sheet's, and made-up ones such
  /// as Sheet1. Other sheets of the workbook keep theirs.
  private func tidied(_ text: String) -> String {
    let others = viewModel.workbook.sheets.map(\.name).filter { $0 != viewModel.activeSheet.name }
    return SheetPrefixes.keepingOnly(others, in: text)
  }

  private func explain(_ formula: String) async {
    working = true
    failure = nil
    defer { working = false }
    do {
      explanation = tidied(
        try await FormulaHelper.explain(
          formula, cell: cell, context: viewModel.formulaHelpContext()))
    } catch {
      failure = "Couldn't explain it: \(error.localizedDescription)"
    }
  }
}

@MainActor
enum FormulaHelpPresenter {
  static func present(from viewModel: SpreadsheetViewModel, in window: NSWindow? = nil) {
    viewModel.commitEditIfNeeded()
    SparkDialogPresenter.present(title: "Formula Help", width: 460, in: window) { close in
      FormulaHelpSheet(viewModel: viewModel, onDismiss: close)
    }
  }
}
