import AppKit
import SparkGridCore
import SwiftUI

struct NameManagerSheet: View {
  @Bindable var viewModel: SpreadsheetViewModel
  let onDismiss: () -> Void

  @State private var selectedName: String?
  @State private var nameText = ""
  @State private var refersText = ""
  @State private var editingOriginal: String?
  @State private var errorMessage: String?

  var body: some View {
    SparkDialog(
      title: "Name Manager",
      subtitle: subtitle,
      primaryTitle: editingOriginal == nil ? "Add" : "Apply",
      primaryDisabled: nameText.trimmingCharacters(in: .whitespaces).isEmpty,
      cancelTitle: "Done",
      onCancel: onDismiss,
      onPrimary: apply,
      leading: {
        if editingOriginal != nil {
          Button("Delete Name", role: .destructive) { deleteSelected() }
        }
      },
      content: {
        HStack(alignment: .top, spacing: 12) {
          namesList
            .frame(width: 240)
          editor
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(height: 320)
      }
    )
    .frame(width: 640)
    .onChange(of: selectedName) { _, name in
      guard let name, let named = viewModel.workbook.namedRange(named: name) else { return }
      load(named)
      viewModel.revealDefinedName(named)
    }
  }

  private var subtitle: String {
    let count = viewModel.definedNames.count
    if let editingOriginal { return "Editing \(editingOriginal)" }
    return count == 0 ? "No defined names yet" : "\(count) defined \(count == 1 ? "name" : "names")"
  }

  private var namesList: some View {
    VStack(spacing: 0) {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 1) {
          ForEach(viewModel.definedNames, id: \.name) { named in
            nameRow(named)
          }
          if viewModel.definedNames.isEmpty {
            Text("Click + to name the selected cells.")
              .font(.system(size: 12))
              .foregroundStyle(SparkStyle.secondaryLabel)
              .padding(10)
          }
        }
        .padding(4)
      }
      Divider()
      HStack(spacing: 2) {
        Button(action: beginNew) {
          Image(systemName: "plus")
            .font(.system(size: 11, weight: .semibold))
            .frame(width: 22, height: 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help("New name for the selection")
        Button(action: deleteSelected) {
          Image(systemName: "minus")
            .font(.system(size: 11, weight: .semibold))
            .frame(width: 22, height: 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(editingOriginal == nil)
        .help("Delete the selected name")
        Spacer()
      }
      .padding(4)
    }
    .background(RoundedRectangle(cornerRadius: 8).fill(SparkStyle.chrome))
    .overlay(RoundedRectangle(cornerRadius: 8).stroke(SparkStyle.separator, lineWidth: 1))
  }

  private func nameRow(_ named: NamedRange) -> some View {
    let selected = selectedName == named.name
    return Button {
      selectedName = named.name
    } label: {
      VStack(alignment: .leading, spacing: 1) {
        Text(named.name)
          .font(.system(size: 12, weight: selected ? .semibold : .regular))
          .foregroundStyle(SparkStyle.label)
        Text(named.referenceText)
          .font(.system(size: 11, design: .monospaced))
          .foregroundStyle(SparkStyle.secondaryLabel)
          .lineLimit(1)
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 6)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 5).fill(selected ? SparkStyle.accent.opacity(0.22) : .clear)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private var editor: some View {
    VStack(alignment: .leading, spacing: 8) {
      SparkDialogGroup {
        SparkDialogRow(label: "Name") {
          TextField("Sales", text: $nameText)
            .textFieldStyle(.roundedBorder)
            .frame(width: 200)
        }
        SparkDialogDivider()
        SparkDialogRow(label: "Refers to") {
          TextField("Sheet1!$A$1:$B$5", text: $refersText)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 12, design: .monospaced))
            .frame(width: 200)
        }
      }
      if let named = editingOriginal.flatMap({ viewModel.workbook.namedRange(named: $0) }),
        !named.resolvesToRange
      {
        Text("This name is a formula, not a range. It is kept as written.")
          .font(.system(size: 11))
          .foregroundStyle(SparkStyle.secondaryLabel)
      }
      if let errorMessage {
        Text(errorMessage)
          .font(.system(size: 11))
          .foregroundStyle(Color(nsColor: .systemRed))
      }
    }
  }

  private func load(_ named: NamedRange) {
    editingOriginal = named.name
    nameText = named.name
    refersText = named.referenceText
    errorMessage = nil
  }

  private func beginNew() {
    selectedName = nil
    editingOriginal = nil
    nameText = ""
    errorMessage = nil
    let draft = NamedRange(
      name: "Name",
      sheetName: viewModel.activeSheet.name,
      range: viewModel.selectionRange
    )
    refersText = draft.referenceText
  }

  private func apply() {
    errorMessage = viewModel.upsertDefinedName(
      originalName: editingOriginal,
      name: nameText,
      refersTo: refersText
    )
    guard errorMessage == nil else { return }
    let saved = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
    selectedName = saved
    if let named = viewModel.workbook.namedRange(named: saved) {
      load(named)
    }
  }

  private func deleteSelected() {
    guard let editingOriginal else { return }
    viewModel.deleteDefinedName(named: editingOriginal)
    self.editingOriginal = nil
    selectedName = nil
    nameText = ""
    refersText = ""
    errorMessage = nil
  }
}

enum NameManagerPresenter {
  @MainActor
  static func present(from viewModel: SpreadsheetViewModel, in window: NSWindow? = nil) {
    viewModel.commitEditIfNeeded()
    SparkDialogPresenter.present(title: "Name Manager", width: 640, in: window) { close in
      NameManagerSheet(viewModel: viewModel, onDismiss: close)
    }
  }
}
