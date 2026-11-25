import AppKit
import SparkGridCore
import SwiftUI

/// File › Browse Versions: the versions of this workbook the Mac has kept, newest first. Open a
/// Copy shows one in a new window; Restore puts it in place of the workbook, and Undo takes that
/// back.
struct VersionsSheet: View {
  let store: SpreadsheetDocumentStore
  let onDismiss: () -> Void

  @State private var versions: [NSFileVersion] = []
  @State private var selection: Int?
  @State private var failure: String?

  private var fileName: String { store.fileURL?.lastPathComponent ?? "This workbook" }

  var body: some View {
    SparkDialog(
      title: "Versions",
      subtitle: fileName,
      primaryTitle: "Restore",
      primaryDisabled: selection == nil,
      cancelTitle: "Close",
      onCancel: onDismiss,
      onPrimary: restore,
      leading: {
        Button("Open a Copy", action: openCopy).disabled(selection == nil)
      },
      content: {
        if versions.isEmpty {
          Text(
            "No earlier versions yet. Spark Grid keeps one each time you save, and while "
              + "autosave is on, one every ten minutes."
          )
          .font(.system(size: 12))
          .foregroundStyle(SparkStyle.secondaryLabel)
          .fixedSize(horizontal: false, vertical: true)
        } else {
          SparkDialogGroup {
            ScrollView {
              VStack(spacing: 0) {
                ForEach(Array(versions.enumerated()), id: \.offset) { index, version in
                  row(index, version)
                  if index < versions.count - 1 { SparkDialogDivider() }
                }
              }
            }
            .frame(maxHeight: 260)
          }
          Text("Restore replaces the workbook with the version you pick. Edit › Undo puts it back.")
            .font(.system(size: 11))
            .foregroundStyle(SparkStyle.secondaryLabel)
            .fixedSize(horizontal: false, vertical: true)
        }
        if let failure {
          Text(failure).font(.system(size: 11)).foregroundStyle(.red)
        }
      }
    )
    .onAppear {
      if let url = store.fileURL { versions = WorkbookVersions.versions(of: url) }
    }
  }

  private func row(_ index: Int, _ version: NSFileVersion) -> some View {
    Button {
      selection = index
    } label: {
      HStack {
        Text(WorkbookVersions.title(of: version))
          .font(.system(size: 13))
          .foregroundStyle(selection == index ? Color.white : SparkStyle.label)
        Spacer()
        if index == versions.count - 1 {
          Text("Oldest")
            .font(.system(size: 11))
            .foregroundStyle(
              selection == index ? Color.white.opacity(0.8) : SparkStyle.secondaryLabel)
        }
      }
      .padding(.horizontal, 12)
      .frame(minHeight: 32)
      .background(selection == index ? SparkStyle.accent : Color.clear)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(selection == index ? .isSelected : [])
  }

  private func load(_ version: NSFileVersion) -> Workbook? {
    let url = store.fileURL
    let accessing = url?.startAccessingSecurityScopedResource() ?? false
    defer { if accessing { url?.stopAccessingSecurityScopedResource() } }
    do {
      return try SpreadsheetDocumentStore.readDocument(at: version.url).workbook
    } catch {
      failure = "Couldn't read that version: \(error.localizedDescription)"
      return nil
    }
  }

  private func openCopy() {
    guard let selection, selection < versions.count else { return }
    let version = versions[selection]
    let base = store.fileURL?.deletingPathExtension().lastPathComponent ?? "Workbook"
    let name = "\(base) (\(WorkbookVersions.title(of: version)))"
    // The version can be read only while the workbook's own file is open to the app, so a
    // temporary copy is what the new window opens.
    guard let copy = WorkbookVersions.temporaryCopy(of: version, from: store.fileURL) else {
      failure = "Couldn't read that version."
      return
    }
    WorkbookWindows.shared.newWindow(.copy(copy, name))
    onDismiss()
  }

  private func restore() {
    guard let selection, selection < versions.count,
      let viewModel = store.activeViewModel,
      let workbook = load(versions[selection])
    else { return }
    let before = viewModel.workbook
    viewModel.workbook = workbook
    viewModel.registerWorkbookStructureUndo(before: before, action: "Restore Version")
    viewModel.notifyGridRefresh()
    onDismiss()
  }
}
