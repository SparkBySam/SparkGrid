import AppKit
import SparkGridCore
import SwiftUI

struct SettingsView: View {
  @Bindable private var settings = AppSettings.shared
  @State private var showAbout = false
  @State private var tab: SettingsTab = .general

  /// The tabs are drawn here rather than by a system tab view: its toolbar marks the selected
  /// tab in the macOS accent, so with Spark amber chosen it stayed blue.
  enum SettingsTab: CaseIterable {
    case general, shortcuts, about

    var title: String {
      switch self {
      case .general: "General"
      case .shortcuts: "Shortcuts"
      case .about: "About"
      }
    }

    var systemImage: String {
      switch self {
      case .general: "gearshape"
      case .shortcuts: "keyboard"
      case .about: "info.circle"
      }
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      tabBar
      Rectangle().fill(SparkStyle.chromeDivider).frame(height: 1)
      switch tab {
      case .general: GeneralSettingsTab(settings: settings)
      case .shortcuts: ShortcutSettingsTab(settings: settings)
      case .about: aboutTab
      }
    }
    .frame(width: 540)
    .background(SparkStyle.window)
    .background(SettingsWindowTitle(title: tab.title))
    .preferredColorScheme(settings.appearanceMode.colorScheme)
    .aboutPanel(isPresented: $showAbout)
  }

  private var tabBar: some View {
    let accent = SparkStyle.accent
    return HStack(spacing: 4) {
      ForEach(SettingsTab.allCases, id: \.self) { item in
        let selected = item == tab
        Button {
          tab = item
        } label: {
          VStack(spacing: 3) {
            Image(systemName: item.systemImage)
              .font(.system(size: 19))
              .frame(height: 22)
            Text(item.title)
              .font(.system(size: 11))
          }
          .foregroundStyle(selected ? accent : SparkStyle.secondaryLabel)
          .frame(width: 72, height: 50)
          .background(
            RoundedRectangle(cornerRadius: 7)
              .fill(selected ? SparkStyle.field : Color.clear)
          )
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 8)
    .background(SparkStyle.chrome)
  }

  private var aboutTab: some View {
    VStack(alignment: .leading, spacing: 12) {
      SparkDialogGroup {
        linkRow("About Spark Grid", systemImage: "info.circle") { showAbout = true }
        SparkDialogDivider()
        linkRow("Email support", systemImage: "envelope") { LegalLinks.openFeedback() }
        SparkDialogDivider()
        linkRow("Support page", systemImage: "questionmark.circle") { LegalLinks.openSupport() }
        SparkDialogDivider()
        linkRow("Terms of use and licenses", systemImage: "doc.text") {
          LegalLinks.openTermsOfUse()
        }
        SparkDialogDivider()
        linkRow("Privacy policy", systemImage: "hand.raised") { LegalLinks.openPrivacy() }
        SparkDialogDivider()
        linkRow("Spark Suite", systemImage: "square.grid.2x2") { LegalLinks.openSparkSuite() }
      }
      Spacer(minLength: 0)
    }
    .padding(20)
    .frame(height: 320, alignment: .top)
  }

  private func linkRow(_ title: String, systemImage: String, action: @escaping () -> Void)
    -> some View
  {
    Button(action: action) {
      HStack(spacing: 10) {
        Image(systemName: systemImage)
          .foregroundStyle(SparkStyle.secondaryLabel)
          .frame(width: 18)
        Text(title)
          .font(.system(size: 13))
          .foregroundStyle(SparkStyle.label)
        Spacer()
        Image(systemName: "chevron.right")
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(SparkStyle.secondaryLabel)
      }
      .padding(.horizontal, 12)
      .frame(minHeight: 36)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

// MARK: - General

private struct GeneralSettingsTab: View {
  @Bindable var settings: AppSettings

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      SparkDialogSection(title: "Appearance")
      SparkDialogGroup {
        SparkDialogRow(label: "Color scheme") {
          SparkSegmentedPicker(
            selection: $settings.appearanceMode,
            options: AppearanceMode.allCases.map { ($0, $0.title) }, equalWidths: true)
        }
        SparkDialogDivider()
        SparkDialogRow(label: "Accent color") {
          SparkSegmentedPicker(
            selection: $settings.useSystemAccent,
            options: [(false, "Spark amber"), (true, "macOS accent")])
        }
        SparkDialogDivider()
        SparkDialogRow(label: "Names under toolbar buttons") {
          toggle($settings.showToolbarLabels)
        }
      }

      SparkDialogSection(title: "Saving")
      SparkDialogGroup {
        SparkDialogRow(label: "Save changes automatically") {
          toggle($settings.autosaveEnabled)
        }
        SparkDialogDivider()
        SparkDialogRow(label: "How often") {
          Picker("How often", selection: $settings.autosaveIntervalSeconds) {
            ForEach(AppSettings.autosaveIntervalOptions, id: \.self) { seconds in
              Text(AppSettings.label(forInterval: seconds)).tag(seconds)
            }
          }
          .labelsHidden()
          .fixedSize()
          .disabled(!settings.autosaveEnabled)
        }
      }
      Text(
        "Only files that have been saved once are saved automatically. A new workbook waits for "
          + "Save."
      )
      .font(.system(size: 11))
      .foregroundStyle(SparkStyle.secondaryLabel)
      .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
    }
    .padding(20)
    .frame(height: 320, alignment: .top)
  }

  private func toggle(_ binding: Binding<Bool>) -> some View {
    Toggle("", isOn: binding)
      .toggleStyle(.switch)
      .controlSize(.small)
      .labelsHidden()
      .tint(SparkStyle.accent)
  }
}

// MARK: - Shortcuts

/// A shortcut another action already has, waiting for the person to choose.
private struct ShortcutConflict: Equatable {
  var action: HotkeyAction
  var shortcut: StoredShortcut
  var other: HotkeyAction
}

private struct ShortcutNotice: Equatable {
  var action: HotkeyAction
  var text: String
}

private struct ShortcutSettingsTab: View {
  @Bindable var settings: AppSettings
  @State private var search = ""
  @State private var recording: HotkeyAction?
  @State private var monitor: Any?
  @State private var conflict: ShortcutConflict?
  @State private var notice: ShortcutNotice?

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        TextField("Search shortcuts", text: $search)
          .textFieldStyle(.roundedBorder)
          .frame(width: 220)
        Spacer()
        Button("Reset All") {
          stopRecording()
          conflict = nil
          notice = nil
          settings.resetShortcutsToDefaults()
        }
        .controlSize(.small)
      }
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          ForEach(HotkeyAction.Group.allCases) { group in
            let actions = visible(in: group)
            if !actions.isEmpty {
              SparkDialogSection(title: group.rawValue)
              SparkDialogGroup {
                ForEach(Array(actions.enumerated()), id: \.element) { index, action in
                  if index > 0 { SparkDialogDivider() }
                  row(action)
                }
              }
            }
          }
          if HotkeyAction.Group.allCases.allSatisfy({ visible(in: $0).isEmpty }) {
            Text("No shortcut matches \u{201C}\(search)\u{201D}.")
              .foregroundStyle(SparkStyle.secondaryLabel)
          }
        }
      }
      Text("Click a shortcut, then press the new keys. Esc cancels.")
        .font(.system(size: 11))
        .foregroundStyle(SparkStyle.secondaryLabel)
    }
    .padding(20)
    .frame(height: 460, alignment: .top)
    .onDisappear { stopRecording() }
  }

  private func visible(in group: HotkeyAction.Group) -> [HotkeyAction] {
    let query = search.trimmingCharacters(in: .whitespaces).lowercased()
    return HotkeyAction.allCases.filter { action in
      guard action.group == group else { return false }
      guard !query.isEmpty else { return true }
      return action.displayName.lowercased().contains(query)
        || action.detail.lowercased().contains(query)
        || settings.shortcut(for: action).displayString.lowercased().contains(query)
    }
  }

  private func row(_ action: HotkeyAction) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        VStack(alignment: .leading, spacing: 1) {
          Text(action.displayName)
            .font(.system(size: 13))
            .foregroundStyle(SparkStyle.label)
          if !action.detail.isEmpty {
            Text(action.detail)
              .font(.system(size: 11))
              .foregroundStyle(SparkStyle.secondaryLabel)
          }
        }
        Spacer(minLength: 8)
        if settings.shortcut(for: action) != settings.defaultShortcut(for: action) {
          Button {
            settings.resetShortcut(for: action)
            notice = nil
          } label: {
            Image(systemName: "arrow.uturn.backward")
          }
          .buttonStyle(.borderless)
          .help("Back to \(settings.defaultShortcut(for: action).displayString)")
        }
        keyButton(action)
      }
      if let conflict, conflict.action == action {
        HStack(spacing: 8) {
          Text("\(conflict.shortcut.displayString) is used by \(conflict.other.displayName).")
            .font(.system(size: 11))
          Spacer()
          Button("Use Here") { swap(conflict) }
            .controlSize(.small)
            .help("\(conflict.other.displayName) gets this action's old shortcut")
          Button("Cancel") { self.conflict = nil }
            .controlSize(.small)
        }
        .foregroundStyle(SparkStyle.label)
      }
      if let notice, notice.action == action {
        Text(notice.text)
          .font(.system(size: 11))
          .foregroundStyle(.orange)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
  }

  private func keyButton(_ action: HotkeyAction) -> some View {
    let isRecording = recording == action
    return Button {
      if isRecording { stopRecording() } else { beginRecording(action) }
    } label: {
      Text(isRecording ? "Type shortcut…" : settings.shortcut(for: action).displayString)
        .font(.system(size: 12, weight: .medium, design: isRecording ? .default : .rounded))
        .foregroundStyle(isRecording ? SparkStyle.accent : SparkStyle.label)
        .frame(minWidth: 96)
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
          RoundedRectangle(cornerRadius: 6)
            .fill(isRecording ? SparkStyle.accent.opacity(0.14) : SparkStyle.chrome)
        )
        .overlay(
          RoundedRectangle(cornerRadius: 6)
            .stroke(isRecording ? SparkStyle.accent : SparkStyle.separator, lineWidth: 1)
        )
    }
    .buttonStyle(.plain)
    .help("Click, then press the new shortcut")
  }

  private func beginRecording(_ action: HotkeyAction) {
    stopRecording()
    conflict = nil
    notice = nil
    recording = action
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      if event.keyCode == 53 {
        stopRecording()
      } else {
        record(event, for: action)
      }
      return nil
    }
  }

  private func record(_ event: NSEvent, for action: HotkeyAction) {
    let needed: NSEvent.ModifierFlags = [.command, .option, .control]
    guard let shortcut = StoredShortcut.from(event: event),
      !NSEvent.ModifierFlags(rawValue: shortcut.modifiers).intersection(needed).isEmpty
    else {
      notice = ShortcutNotice(
        action: action, text: "Include ⌘, ⌥ or ⌃ so the keys don't type into a cell.")
      return
    }
    stopRecording()
    if let reserved = AppSettings.reservedShortcuts[shortcut] {
      notice = ShortcutNotice(
        action: action, text: "\(shortcut.displayString) is \(reserved) and can't be changed.")
      return
    }
    if let other = settings.action(using: shortcut, except: action) {
      conflict = ShortcutConflict(action: action, shortcut: shortcut, other: other)
      return
    }
    settings.setShortcut(shortcut, for: action)
  }

  /// Gives the shortcut to the action and its old one to the action that had it.
  private func swap(_ pending: ShortcutConflict) {
    let previous = settings.shortcut(for: pending.action)
    settings.setShortcut(pending.shortcut, for: pending.action)
    settings.setShortcut(previous, for: pending.other)
    notice = ShortcutNotice(
      action: pending.action,
      text: "\(pending.other.displayName) now uses \(previous.displayString).")
    conflict = nil
  }

  private func stopRecording() {
    if let monitor {
      NSEvent.removeMonitor(monitor)
      self.monitor = nil
    }
    recording = nil
  }
}

#Preview {
  SettingsView()
}

/// The Settings window shows the open tab's name, as the system tab view did.
private struct SettingsWindowTitle: NSViewRepresentable {
  let title: String

  func makeNSView(context: Context) -> NSView { NSView() }

  func updateNSView(_ view: NSView, context: Context) {
    DispatchQueue.main.async { view.window?.title = title }
  }
}
