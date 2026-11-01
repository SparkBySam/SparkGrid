import SparkGridCore
import SwiftUI

struct FindReplaceBar: View {
  @Bindable var viewModel: SpreadsheetViewModel
  @State private var findQueryDebounceTask: Task<Void, Never>?
  @FocusState private var findFieldFocused: Bool

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
        .frame(width: 20)

      TextField("Find", text: $viewModel.findQuery)
        .textFieldStyle(.plain)
        .focused($findFieldFocused)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(SparkStyle.field, in: RoundedRectangle(cornerRadius: 5))
        .overlay(
          RoundedRectangle(cornerRadius: 5)
            .strokeBorder(SpreadsheetChrome.chromeBorderColor, lineWidth: 1)
        )
        .frame(minWidth: 140, maxWidth: 220)
        .onSubmit { viewModel.findNext() }
        .onChange(of: viewModel.findQuery) { _, _ in
          findQueryDebounceTask?.cancel()
          findQueryDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 175_000_000)
            guard !Task.isCancelled else { return }
            viewModel.refreshFindMatches(selectCurrent: true)
          }
        }

      if viewModel.isFindReplaceMode {
        TextField("Replace", text: $viewModel.findReplaceText)
          .textFieldStyle(.plain)
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .background(SparkStyle.field, in: RoundedRectangle(cornerRadius: 5))
          .overlay(
            RoundedRectangle(cornerRadius: 5)
              .strokeBorder(SpreadsheetChrome.chromeBorderColor, lineWidth: 1)
          )
          .frame(minWidth: 120, maxWidth: 180)
      }

      FindBarIconButton(systemName: "chevron.up", help: "Previous") {
        viewModel.findPrevious()
      }
      .disabled(viewModel.findMatches.isEmpty)

      FindBarIconButton(systemName: "chevron.down", help: "Next") {
        viewModel.findNext()
      }
      .disabled(viewModel.findMatches.isEmpty)

      if viewModel.isFindReplaceMode {
        Button("Replace") { _ = viewModel.replaceCurrent() }
          .buttonStyle(.borderless)
          .disabled(viewModel.findMatches.isEmpty)

        Button("Replace All") { _ = viewModel.replaceAll() }
          .buttonStyle(.borderless)
          .disabled(viewModel.findMatches.isEmpty)
      }

      Text(matchLabel)
        .font(.system(size: 11, weight: .medium).monospacedDigit())
        .foregroundStyle(viewModel.findMatches.isEmpty ? .tertiary : .secondary)
        .frame(minWidth: 56, alignment: .leading)

      Menu {
        Toggle("Match Case", isOn: $viewModel.findMatchCase)
        Toggle("Entire Cell", isOn: $viewModel.findEntireCell)
        Divider()
        Picker("Scope", selection: $viewModel.findScope) {
          Text("Sheet").tag(FindScope.sheet)
          Text("Selection").tag(FindScope.selection)
        }
      } label: {
        Image(systemName: "ellipsis.circle")
          .font(.system(size: 13))
          .foregroundStyle(.secondary)
          .frame(width: 24, height: 24)
          .contentShape(Rectangle())
      }
      .menuStyle(.borderlessButton)
      .help("Find options")
      .onChange(of: viewModel.findMatchCase) { _, _ in
        viewModel.refreshFindMatches(selectCurrent: true)
      }
      .onChange(of: viewModel.findEntireCell) { _, _ in
        viewModel.refreshFindMatches(selectCurrent: true)
      }
      .onChange(of: viewModel.findScope) { _, newScope in
        if newScope == .selection {
          viewModel.captureFindScopeRange()
        } else {
          viewModel.findScopeRange = nil
        }
        viewModel.refreshFindMatches(selectCurrent: true)
      }

      Spacer(minLength: 0)

      Button {
        viewModel.hideFindBar()
      } label: {
        Image(systemName: "xmark")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(.secondary)
          .frame(width: 24, height: 24)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help("Close")
    }
    .padding(.horizontal, 12)
    .frame(height: SpreadsheetChrome.findBarHeight)
    .background(SparkStyle.chrome)
    .foregroundStyle(SparkStyle.label)
    .onAppear {
      claimFindField()
    }
    .onDisappear {
      findQueryDebounceTask?.cancel()
    }
  }

  /// The find field takes the key window before the cell editor can.
  private func claimFindField() {
    SpreadsheetGridNSView.endEditingInKeyWindowForFind()
    findFieldFocused = true
    DispatchQueue.main.async {
      guard viewModel.isFindBarVisible else { return }
      SpreadsheetGridNSView.endEditingInKeyWindowForFind()
      findFieldFocused = true
    }
  }

  private var matchLabel: String {
    guard !viewModel.findMatches.isEmpty else { return "No matches" }
    let index = viewModel.findMatchIndex + 1
    return "\(index) of \(viewModel.findMatches.count)"
  }
}

private struct FindBarIconButton: View {
  let systemName: String
  let help: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: systemName)
        .font(.system(size: 11, weight: .semibold))
        .frame(width: 24, height: 24)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(help)
  }
}
