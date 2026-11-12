import AppKit
import SparkGridCore
import SwiftUI

/// Data ▸ Dropdown List: the choices for the selected cells, typed in or taken from cells.
struct DropdownListSheet: View {
  @Bindable var viewModel: SpreadsheetViewModel
  let onDismiss: () -> Void

  private enum Mode: String, CaseIterable, Identifiable {
    case items = "Type the choices"
    case cells = "Use cells"
    var id: String { rawValue }
  }

  @State private var mode: Mode = .items
  @State private var itemsText = ""
  @State private var cellsText = ""
  private let hasList: Bool

  init(viewModel: SpreadsheetViewModel, onDismiss: @escaping () -> Void) {
    self.viewModel = viewModel
    self.onDismiss = onDismiss
    switch viewModel.selectedDropdownSource {
    case .items(let items):
      _itemsText = State(initialValue: items.joined(separator: "\n"))
      hasList = true
    case .cells(let reference):
      _mode = State(initialValue: .cells)
      _cellsText = State(initialValue: reference)
      hasList = true
    case nil:
      hasList = false
    }
  }

  private var items: [String] {
    itemsText.split(whereSeparator: \.isNewline)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
  }

  /// Other spreadsheet apps reject a typed-in list longer than this, so it is not saved.
  private static let inlineListLimit = 255

  private var itemsTooLong: Bool {
    items.joined(separator: ",").count > Self.inlineListLimit
  }

  private var canApply: Bool {
    switch mode {
    case .items: return !items.isEmpty && !itemsTooLong
    case .cells: return !cellsText.trimmingCharacters(in: .whitespaces).isEmpty
    }
  }

  var body: some View {
    SparkDialog(
      title: hasList ? "Edit Dropdown List" : "Dropdown List",
      subtitle: "Applies to \(viewModel.selectionRange.a1Label)",
      primaryTitle: "Apply",
      primaryDisabled: !canApply,
      onCancel: onDismiss,
      onPrimary: apply,
      leading: {
        if hasList {
          Button("Remove List", role: .destructive) {
            viewModel.removeDropdown()
            onDismiss()
          }
        }
      },
      content: {
        SparkSegmentedPicker(
          selection: $mode, options: Mode.allCases.map { ($0, $0.rawValue) }, equalWidths: true)

        switch mode {
        case .items:
          VStack(alignment: .leading, spacing: 6) {
            TextEditor(text: $itemsText)
              .font(.system(size: 13))
              .frame(height: 150)
              .scrollContentBackground(.hidden)
              .padding(6)
              .background(RoundedRectangle(cornerRadius: 8).fill(SparkStyle.chrome))
              .overlay(RoundedRectangle(cornerRadius: 8).stroke(SparkStyle.separator, lineWidth: 1))
            if itemsTooLong {
              Text(
                "That list is too long to save in the file. Put the choices in cells and use those."
              )
              .font(.system(size: 11))
              .foregroundStyle(Color(nsColor: .systemRed))
            } else {
              Text("One choice per line. Commas inside a choice become spaces.")
                .font(.system(size: 11))
                .foregroundStyle(SparkStyle.secondaryLabel)
            }
          }
        case .cells:
          SparkDialogGroup {
            SparkDialogRow(label: "Cells") {
              TextField("$F$2:$F$9 or Lists!$A$1:$A$20", text: $cellsText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
                .frame(width: 220)
            }
          }
          Text("The list shows the values in these cells. A defined name works too.")
            .font(.system(size: 11))
            .foregroundStyle(SparkStyle.secondaryLabel)
        }
      }
    )
  }

  private func apply() {
    switch mode {
    case .items: viewModel.setDropdown(.items(items))
    case .cells: viewModel.setDropdown(.cells(cellsText))
    }
    onDismiss()
  }
}

/// Insert ▸ Comment: a note on the selected cell.
struct CommentSheet: View {
  @Bindable var viewModel: SpreadsheetViewModel
  let onDismiss: () -> Void

  @State private var text: String
  private let existing: CellComment?

  init(viewModel: SpreadsheetViewModel, onDismiss: @escaping () -> Void) {
    self.viewModel = viewModel
    self.onDismiss = onDismiss
    existing = viewModel.selectedComment
    _text = State(initialValue: viewModel.selectedComment?.text ?? "")
  }

  var body: some View {
    SparkDialog(
      title: existing == nil ? "Add Comment" : "Edit Comment",
      subtitle: subtitle,
      primaryTitle: existing == nil ? "Add" : "Save",
      primaryDisabled: text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      onCancel: onDismiss,
      onPrimary: {
        viewModel.setComment(text)
        onDismiss()
      },
      leading: {
        if existing != nil {
          Button("Delete Comment", role: .destructive) {
            viewModel.deleteComment()
            onDismiss()
          }
        }
      },
      content: {
        TextEditor(text: $text)
          .font(.system(size: 13))
          .frame(height: 120)
          .scrollContentBackground(.hidden)
          .padding(6)
          .background(RoundedRectangle(cornerRadius: 8).fill(SparkStyle.chrome))
          .overlay(RoundedRectangle(cornerRadius: 8).stroke(SparkStyle.separator, lineWidth: 1))
      }
    )
  }

  private var subtitle: String {
    let cell = viewModel.selectionAnchor.a1
    if let existing, !existing.author.isEmpty { return "\(cell) · by \(existing.author)" }
    return cell
  }
}

@MainActor
enum CellNotePresenter {
  static func presentDropdown(from viewModel: SpreadsheetViewModel, in window: NSWindow? = nil) {
    viewModel.commitEditIfNeeded()
    SparkDialogPresenter.present(title: "Dropdown List", width: 420, in: window) { close in
      DropdownListSheet(viewModel: viewModel, onDismiss: close)
    }
  }

  static func presentComment(from viewModel: SpreadsheetViewModel, in window: NSWindow? = nil) {
    viewModel.commitEditIfNeeded()
    SparkDialogPresenter.present(title: "Comment", width: 400, in: window) { close in
      CommentSheet(viewModel: viewModel, onDismiss: close)
    }
  }
}
