import AppKit
import SparkGridCore
import SwiftUI

/// Escape closes the Insert Function list. Return and other keys do not.
enum FormulaFunctionListKeys {
  static let escapeKeyCode: UInt16 = 53

  static func shouldClose(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) -> Bool {
    guard keyCode == escapeKeyCode else { return false }
    let flags = modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock)
    return flags.isEmpty
  }
}

struct FormulaFunctionPicker: View {
  var onChoose: (String) -> Void
  var onClose: () -> Void

  @State private var query = ""
  @FocusState private var searchFocused: Bool
  @State private var escapeMonitor: Any?

  private var groups: [FormulaFunctionGroup] {
    FormulaFunctionCatalog.groups(matching: query)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Insert Function")
        .font(.headline)

      TextField("Search functions", text: $query)
        .textFieldStyle(.roundedBorder)
        .focused($searchFocused)
        .onSubmit(chooseFirstMatch)

      if groups.isEmpty {
        Text("No matching functions")
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 2) {
            ForEach(groups, id: \.kind) { group in
              Text(group.kind.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 6)
                .padding(.horizontal, 8)
              ForEach(group.entries) { entry in
                FormulaFunctionPickerRow(entry: entry) {
                  onChoose(entry.name)
                }
              }
            }
          }
          .padding(.bottom, 4)
        }
      }
    }
    .padding(12)
    .frame(width: 360, height: 420, alignment: .topLeading)
    .onAppear {
      searchFocused = true
      installEscapeMonitor()
    }
    .onDisappear(perform: removeEscapeMonitor)
    .onExitCommand(perform: onClose)
  }

  private func chooseFirstMatch() {
    guard let name = groups.first?.entries.first?.name else { return }
    onChoose(name)
  }

  private func installEscapeMonitor() {
    guard escapeMonitor == nil else { return }
    escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      guard
        FormulaFunctionListKeys.shouldClose(
          keyCode: event.keyCode, modifierFlags: event.modifierFlags)
      else {
        return event
      }
      DispatchQueue.main.async { onClose() }
      return nil
    }
  }

  private func removeEscapeMonitor() {
    if let escapeMonitor {
      NSEvent.removeMonitor(escapeMonitor)
    }
    escapeMonitor = nil
  }
}

private struct FormulaFunctionPickerRow: View {
  let entry: FormulaFunctionEntry
  let onChoose: () -> Void
  @State private var hovered = false

  var body: some View {
    Button(action: onChoose) {
      VStack(alignment: .leading, spacing: 1) {
        Text(entry.name)
          .font(.system(size: 13, weight: .semibold, design: .monospaced))
          .foregroundStyle(Color(nsColor: .labelColor))
        Text(entry.signatureLine)
          .font(.system(size: 11))
          .foregroundStyle(Color(nsColor: .secondaryLabelColor))
          .lineLimit(1)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(
        RoundedRectangle(cornerRadius: 4)
          .fill(
            hovered ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.28) : Color.clear)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { hovered = $0 }
    .accessibilityLabel("\(entry.name), \(entry.signatureLine)")
  }
}
