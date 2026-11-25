import SparkGridCore
import SwiftUI

struct AutosaveStatusView: View {
  @Bindable var store: SpreadsheetDocumentStore
  @Bindable private var settings = AppSettings.shared
  @State private var showSettings = false

  var body: some View {
    Button {
      showSettings.toggle()
    } label: {
      statusIcon
    }
    .buttonStyle(.plain)
    .help(helpText)
    .popover(isPresented: $showSettings, arrowEdge: .bottom) {
      // The app's own look, as Settings › General › Saving, not system controls (Sam, Nov 20).
      VStack(alignment: .leading, spacing: 10) {
        Text("Autosave")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(SparkStyle.label)
        SparkDialogGroup {
          SparkDialogRow(label: "Save automatically") {
            Toggle("", isOn: $settings.autosaveEnabled)
              .labelsHidden()
              .toggleStyle(.switch)
              .controlSize(.small)
              .tint(SparkStyle.accent)
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
        Text(helpText)
          .font(.system(size: 11))
          .foregroundStyle(SparkStyle.secondaryLabel)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(14)
      .frame(width: 300)
      .background(SparkStyle.window)
    }
  }

  @ViewBuilder
  private var statusIcon: some View {
    Group {
      if !settings.autosaveEnabled {
        Image(systemName: "icloud.slash")
          .foregroundStyle(.secondary)
      } else if store.isAutosaving {
        ProgressView()
          .controlSize(.small)
          .scaleEffect(0.75)
      } else if !store.hasOpenFile {
        Image(systemName: "icloud")
          .foregroundStyle(.tertiary)
      } else if store.isDirty {
        Image(systemName: "icloud.and.arrow.up")
          .foregroundStyle(.secondary)
          .symbolEffect(.pulse, options: .repeating)
      } else {
        Image(systemName: "checkmark.icloud")
          .foregroundStyle(.secondary)
      }
    }
    .frame(width: 20, height: 20)
  }

  private var helpText: String {
    if !settings.autosaveEnabled {
      return "Autosave is off — click for settings"
    }
    if store.isAutosaving {
      return "Autosaving…"
    }
    if !store.hasOpenFile {
      return "Save this document to enable autosave"
    }
    if store.isDirty {
      return
        "Unsaved changes — autosaves \(AppSettings.label(forInterval: settings.autosaveIntervalSeconds).lowercased())"
    }
    return
      "All changes saved — autosaves \(AppSettings.label(forInterval: settings.autosaveIntervalSeconds).lowercased())"
  }
}

#Preview {
  AutosaveStatusView(store: SpreadsheetDocumentStore())
    .padding()
}
