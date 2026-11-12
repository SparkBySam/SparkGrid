import AppKit
import SparkGridCore
import SwiftUI

/// Sheet ▸ Protect Sheet: an optional password, typed twice.
struct ProtectSheetDialog: View {
  @Bindable var viewModel: SpreadsheetViewModel
  let onDismiss: () -> Void
  @State private var password = ""
  @State private var confirm = ""
  @State private var allowed: Set<SheetProtection.Permission> = []

  private var mismatch: Bool { !password.isEmpty && password != confirm }

  private func allowBinding(_ permission: SheetProtection.Permission) -> Binding<Bool> {
    Binding(
      get: { allowed.contains(permission) },
      set: { on in
        if on { allowed.insert(permission) } else { allowed.remove(permission) }
      })
  }

  var body: some View {
    SparkDialog(
      title: "Protect Sheet",
      subtitle:
        "Locked cells, rows, columns and formatting on \(viewModel.activeSheet.name) can't be changed",
      primaryTitle: "Protect",
      primaryDisabled: mismatch,
      onCancel: onDismiss,
      onPrimary: protect
    ) {
      SparkDialogGroup {
        SparkDialogRow(label: "Password (optional)") {
          SecureField("", text: $password)
            .textFieldStyle(.roundedBorder)
            .frame(width: 180)
        }
        SparkDialogDivider()
        SparkDialogRow(label: "Confirm") {
          SecureField("", text: $confirm)
            .textFieldStyle(.roundedBorder)
            .frame(width: 180)
        }
      }
      SparkDialogSection(title: "Still allow")
      SparkDialogGroup {
        let permissions = SheetProtection.Permission.allCases
        let half = (permissions.count + 1) / 2
        HStack(alignment: .top, spacing: 0) {
          ForEach(
            [Array(permissions.prefix(half)), Array(permissions.dropFirst(half))], id: \.self
          ) { column in
            VStack(alignment: .leading, spacing: 6) {
              ForEach(column, id: \.self) { permission in
                Toggle(permission.title, isOn: allowBinding(permission))
                  .toggleStyle(.checkbox)
                  .font(.system(size: 13))
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
        .padding(12)
      }
      Text(
        mismatch
          ? "The passwords don't match."
          : "To leave some cells open for typing, select them and turn off Format > Locked first. Protection guards against mistakes; it does not encrypt the file."
      )
      .font(.system(size: 12))
      .foregroundStyle(mismatch ? Color.red : SparkStyle.secondaryLabel)
      .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func protect() {
    viewModel.protectSheet(password: password.isEmpty ? nil : password, allowing: allowed)
    onDismiss()
  }
}

/// Sheet ▸ Unprotect Sheet, for a sheet with a password.
struct UnprotectSheetDialog: View {
  @Bindable var viewModel: SpreadsheetViewModel
  let onDismiss: () -> Void
  @State private var password = ""
  @State private var wrong = false

  var body: some View {
    SparkDialog(
      title: "Unprotect Sheet",
      subtitle: viewModel.activeSheet.name,
      primaryTitle: "Unprotect",
      primaryDisabled: password.isEmpty,
      onCancel: onDismiss,
      onPrimary: unprotect
    ) {
      SparkDialogGroup {
        SparkDialogRow(label: "Password") {
          SecureField("", text: $password)
            .textFieldStyle(.roundedBorder)
            .frame(width: 180)
            .onChange(of: password) { wrong = false }
        }
      }
      if wrong {
        Text("That password doesn't unlock this sheet.")
          .font(.system(size: 12))
          .foregroundStyle(Color.red)
      }
    }
  }

  private func unprotect() {
    if viewModel.unprotectSheet(password: password) {
      onDismiss()
    } else {
      wrong = true
    }
  }
}

enum SheetProtectionPresenter {
  @MainActor
  static func toggle(from viewModel: SpreadsheetViewModel, in window: NSWindow? = nil) {
    viewModel.commitEditIfNeeded()
    if viewModel.isSheetProtected {
      guard viewModel.sheetProtectionHasPassword else {
        viewModel.unprotectSheet()
        return
      }
      SparkDialogPresenter.present(title: "Unprotect Sheet", width: 400, in: window) { close in
        UnprotectSheetDialog(viewModel: viewModel, onDismiss: close)
      }
    } else {
      SparkDialogPresenter.present(title: "Protect Sheet", width: 440, in: window) { close in
        ProtectSheetDialog(viewModel: viewModel, onDismiss: close)
      }
    }
  }
}
