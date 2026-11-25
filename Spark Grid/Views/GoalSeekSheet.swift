import AppKit
import SparkGridCore
import SwiftUI

/// Data ▸ Goal Seek: the input that makes a formula come out at a value. The answer is shown
/// first; Keep writes it as one undoable step, Cancel leaves the sheet as it was.
struct GoalSeekSheet: View {
  @Bindable var viewModel: SpreadsheetViewModel
  let onDismiss: () -> Void

  @State private var setCell: String
  @State private var goal = ""
  @State private var changingCell = ""
  @State private var outcome: GoalSeek.Outcome?
  @State private var message: String?
  @State private var working = false
  @State private var kept = false

  init(viewModel: SpreadsheetViewModel, onDismiss: @escaping () -> Void) {
    self.viewModel = viewModel
    self.onDismiss = onDismiss
    _setCell = State(initialValue: viewModel.selectionAnchor.a1)
  }

  var body: some View {
    SparkDialog(
      title: "Goal Seek",
      subtitle: "Find the input that gives a formula the result you want",
      primaryTitle: outcome == nil ? "Find" : "Keep",
      primaryDisabled: working || (outcome == nil && !canFind),
      onCancel: onDismiss,
      onPrimary: primary,
      leading: {
        if working {
          ProgressView().controlSize(.small)
          Text("Finding…").font(.system(size: 12)).foregroundStyle(SparkStyle.secondaryLabel)
        }
      },
      content: {
        SparkDialogGroup {
          row("Formula cell", text: $setCell, prompt: "B5")
          SparkDialogDivider()
          row("Should equal", text: $goal, prompt: "500")
          SparkDialogDivider()
          row("By changing", text: $changingCell, prompt: "B1")
        }
        if let outcome {
          Text(
            outcome.found
              ? "Found it: \(changingCell.uppercased()) = \(Self.shown(outcome.input)) gives "
                + "\(Self.shown(outcome.result))."
              : "No exact answer. The closest: \(changingCell.uppercased()) = "
                + "\(Self.shown(outcome.input)) gives \(Self.shown(outcome.result))."
          )
          .font(.system(size: 12))
          .foregroundStyle(SparkStyle.label)
          .fixedSize(horizontal: false, vertical: true)
        }
        if let message {
          Text(message).font(.system(size: 11)).foregroundStyle(Color(nsColor: .systemRed))
        }
      }
    )
    .onChange(of: setCell) { _, _ in outcome = nil }
    .onChange(of: goal) { _, _ in outcome = nil }
    .onChange(of: changingCell) { _, _ in outcome = nil }
  }

  private func row(_ label: String, text: Binding<String>, prompt: String) -> some View {
    SparkDialogRow(label: label) {
      TextField(prompt, text: text)
        .textFieldStyle(.roundedBorder)
        .frame(width: 160)
        // Return in a field is the main button: Find, then Keep (Sam, Nov 20).
        .onSubmit {
          if !working, outcome != nil || canFind { primary() }
        }
    }
  }

  private var canFind: Bool {
    Double(goal.trimmingCharacters(in: .whitespaces)) != nil
      && !setCell.trimmingCharacters(in: .whitespaces).isEmpty
      && !changingCell.trimmingCharacters(in: .whitespaces).isEmpty
  }

  private static func shown(_ x: Double) -> String {
    // Six decimals at most here; Keep writes the full answer.
    let rounded = abs(x) < 1e9 ? (x * 1e6).rounded() / 1e6 : x
    return CellValue.number(rounded).displayString
  }

  private func primary() {
    // Return can reach both the field and the default button: act once.
    guard !working, !kept else { return }
    if let outcome {
      kept = true
      viewModel.keepGoalSeek(outcome.input, at: changingCell)
      onDismiss()
      return
    }
    message = nil
    viewModel.commitEditIfNeeded()
    let book = viewModel.workbook
    guard let target = try? WorkbookShortcuts.locate(setCell, in: book),
      let input = try? WorkbookShortcuts.locate(changingCell, in: book),
      let value = Double(goal.trimmingCharacters(in: .whitespaces))
    else {
      message = "Give cells such as B5 or Sheet2!B5, and a number to reach."
      return
    }
    working = true
    // The search builds its own engine over the workbook, a moment on a big file: let the
    // spinner show first, so the window answers Return at once.
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(30))
      let result = GoalSeek.run(
        workbook: book,
        setSheet: book.sheets[target.sheet].name, setCell: target.address, goal: value,
        changingSheet: book.sheets[input.sheet].name, changingCell: input.address)
      working = false
      show(result)
    }
  }

  private func show(_ result: Result<GoalSeek.Outcome, GoalSeek.Failure>) {
    switch result {
    case .success(let found): outcome = found
    case .failure(.setCellHasNoFormula):
      message = "\(setCell.uppercased()) needs a formula that depends on the cell to change."
    case .failure(.changingCellHasFormula):
      message = "\(changingCell.uppercased()) holds a formula; pick a cell with a number in it."
    case .failure(.notANumber):
      message = "The formula doesn't give a number. Check the cells."
    }
  }
}

extension SpreadsheetViewModel {
  /// Writes Goal Seek's answer into its cell, as typing it would: one undo step.
  func keepGoalSeek(_ value: Double, at cellText: String) {
    guard let place = try? WorkbookShortcuts.locate(cellText, in: workbook) else { return }
    if place.sheet != workbook.activeSheetIndex { selectSheet(at: place.sheet) }
    let text =
      value == value.rounded() && abs(value) < 1e15
      ? String(Int(value)) : String(format: "%.15g", value)
    setCellValue(text, at: place.address)
    selection = place.address
    notifyGridRefresh()
  }
}

@MainActor
enum GoalSeekPresenter {
  static func present(from viewModel: SpreadsheetViewModel, in window: NSWindow? = nil) {
    viewModel.commitEditIfNeeded()
    SparkDialogPresenter.present(title: "Goal Seek", width: 400, in: window) { close in
      GoalSeekSheet(viewModel: viewModel, onDismiss: close)
    }
  }
}
