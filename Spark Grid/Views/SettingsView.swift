import AppKit
import SparkGridCore
import SwiftUI

struct SettingsView: View {
  @Bindable private var settings = AppSettings.shared
  @State private var recordingAction: HotkeyAction?
  @State private var recorderMonitor: Any?
  @State private var showAbout = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        SparkDialogSection(title: "Appearance")
        SparkDialogGroup {
          SparkDialogRow(label: "Color scheme") {
            Picker("Color scheme", selection: $settings.appearanceMode) {
              ForEach(AppearanceMode.allCases) { mode in
                Text(mode.title).tag(mode)
              }
            }
            .labelsHidden()
            .fixedSize()
          }
          SparkDialogDivider()
          SparkDialogRow(label: "Accent color") {
            Picker("Accent color", selection: $settings.useSystemAccent) {
              Text("Spark amber").tag(false)
              Text("macOS accent").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
          }
          SparkDialogDivider()
          SparkDialogRow(label: "Names under toolbar buttons") {
            Toggle("", isOn: $settings.showToolbarLabels)
              .toggleStyle(.switch)
              .controlSize(.small)
              .labelsHidden()
              .tint(SparkStyle.accent)
          }
        }

        SparkDialogSection(title: "Keyboard shortcuts")
        SparkDialogGroup {
          ForEach(Array(HotkeyAction.allCases.enumerated()), id: \.element) { index, action in
            if index > 0 { SparkDialogDivider() }
            SparkDialogRow(label: action.displayName) {
              Text(settings.shortcut(for: action).displayString)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(SparkStyle.secondaryLabel)
              Button(recordingAction == action ? "Press keys…" : "Change") {
                beginRecording(action)
              }
              .controlSize(.small)
            }
          }
        }
        HStack {
          Spacer()
          Button("Reset Shortcuts") {
            settings.resetShortcutsToDefaults()
          }
          .controlSize(.small)
        }

        SparkDialogSection(title: "About")
        SparkDialogGroup {
          linkRow("About Spark Grid") { showAbout = true }
          SparkDialogDivider()
          linkRow("Email support") { LegalLinks.openFeedback() }
          SparkDialogDivider()
          linkRow("Support page") { LegalLinks.openSupport() }
          SparkDialogDivider()
          linkRow("Terms of use and licenses") { LegalLinks.openTermsOfUse() }
          SparkDialogDivider()
          linkRow("Privacy policy") { LegalLinks.openPrivacy() }
          SparkDialogDivider()
          linkRow("Spark Suite") { LegalLinks.openSparkSuite() }
        }
      }
      .padding(20)
    }
    .frame(width: 480, height: 560)
    .background(SparkStyle.window)
    .preferredColorScheme(settings.appearanceMode.colorScheme)
    .aboutPanel(isPresented: $showAbout)
    .onDisappear { stopRecording() }
  }

  private func linkRow(_ title: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack {
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

  private func beginRecording(_ action: HotkeyAction) {
    stopRecording()
    recordingAction = action
    recorderMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      if let shortcut = StoredShortcut.from(event: event) {
        settings.setShortcut(shortcut, for: action)
        stopRecording()
        return nil
      }
      return event
    }
  }

  private func stopRecording() {
    if let monitor = recorderMonitor {
      NSEvent.removeMonitor(monitor)
      recorderMonitor = nil
    }
    recordingAction = nil
  }
}

#Preview {
  SettingsView()
}
