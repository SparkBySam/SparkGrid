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
      VStack(alignment: .leading, spacing: 12) {
        Text("Autosave")
          .font(.headline)
        Toggle("Enable autosave", isOn: $settings.autosaveEnabled)
        if settings.autosaveEnabled {
          Picker("Save interval", selection: $settings.autosaveIntervalSeconds) {
            ForEach(AppSettings.autosaveIntervalOptions, id: \.self) { seconds in
              Text(AppSettings.label(forInterval: seconds)).tag(seconds)
            }
          }
        }
        Text(helpText)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(14)
      .frame(width: 260)
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
