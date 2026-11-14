import AppKit
import SparkGridCore
import SwiftUI

/// Sheet ▸ Lock Range: the selection locked on its own, with an optional name and password.
struct LockRangeDialog: View {
  @Bindable var viewModel: SpreadsheetViewModel
  let onDismiss: () -> Void
  @State private var name = ""
  @State private var password = ""
  @State private var confirm = ""

  private var mismatch: Bool { !password.isEmpty && password != confirm }

  var body: some View {
    SparkDialog(
      title: "Lock Range",
      subtitle: viewModel.selectionRange.a1Label,
      primaryTitle: "Lock",
      primaryDisabled: mismatch,
      onCancel: onDismiss,
      onPrimary: lock
    ) {
      SparkDialogGroup {
        SparkDialogRow(label: "Name (optional)") {
          TextField("", text: $name)
            .textFieldStyle(.roundedBorder)
            .frame(width: 180)
        }
        SparkDialogDivider()
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
      Text(
        mismatch
          ? "The passwords don't match."
          : "Nothing in the range can be typed over, formatted, cleared, sorted or deleted until the lock is removed, whether the sheet is protected or not. Other apps open the cells unlocked."
      )
      .font(.system(size: 12))
      .foregroundStyle(mismatch ? Color.red : SparkStyle.secondaryLabel)
      .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func lock() {
    viewModel.lockSelectedRange(name: name, password: password.isEmpty ? nil : password)
    onDismiss()
  }
}

/// Sheet ▸ Remove Range Lock, for a lock with a password.
struct RemoveRangeLockDialog: View {
  @Bindable var viewModel: SpreadsheetViewModel
  let lock: RangeLock
  let onDismiss: () -> Void
  @State private var password = ""
  @State private var wrong = false

  var body: some View {
    SparkDialog(
      title: "Remove Range Lock",
      subtitle: lock.name,
      primaryTitle: "Remove Lock",
      primaryDisabled: password.isEmpty,
      onCancel: onDismiss,
      onPrimary: remove
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
        Text("That password doesn't unlock this range.")
          .font(.system(size: 12))
          .foregroundStyle(Color.red)
      }
    }
  }

  private func remove() {
    if viewModel.removeRangeLock(lock.id, password: password) {
      onDismiss()
    } else {
      wrong = true
    }
  }
}

/// Sheet ▸ Allow Edit Ranges: ranges a protected sheet still lets people edit.
struct EditableRangesDialog: View {
  @Bindable var viewModel: SpreadsheetViewModel
  let onDismiss: () -> Void
  @State private var name = ""
  @State private var password = ""
  @State private var confirm = ""

  private var mismatch: Bool { !password.isEmpty && password != confirm }

  var body: some View {
    SparkDialog(
      title: "Allow Edit Ranges",
      subtitle: viewModel.activeSheet.name,
      primaryTitle: "Add \(viewModel.selectionRange.a1Label)",
      primaryDisabled: mismatch || !viewModel.canEditEditableRanges,
      onCancel: onDismiss,
      onPrimary: add
    ) {
      let ranges = viewModel.activeSheet.fileExtras.editableRanges
      if !ranges.isEmpty {
        SparkDialogGroup {
          ForEach(Array(ranges.enumerated()), id: \.offset) { index, range in
            if index > 0 { SparkDialogDivider() }
            SparkDialogRow(label: range.name) {
              HStack(spacing: 8) {
                Text(range.ranges.map(\.a1Label).joined(separator: ", "))
                  .font(.system(size: 12))
                  .foregroundStyle(SparkStyle.secondaryLabel)
                if range.hasPassword {
                  Image(systemName: "key").foregroundStyle(SparkStyle.secondaryLabel)
                }
                Button("Remove") { viewModel.removeEditableRange(named: range.name) }
                  .disabled(!viewModel.canEditEditableRanges)
              }
            }
          }
        }
      }
      SparkDialogSection(title: "Add the selection")
      SparkDialogGroup {
        SparkDialogRow(label: "Name (optional)") {
          TextField("", text: $name)
            .textFieldStyle(.roundedBorder)
            .frame(width: 180)
        }
        SparkDialogDivider()
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
      Text(
        !viewModel.canEditEditableRanges
          ? "Unprotect the sheet to add or remove ranges."
          : mismatch
            ? "The passwords don't match."
            : "When the sheet is protected, these cells can still be edited. A range with a password opens for editing once the password is given (Sheet > Unlock Edit Range)."
      )
      .font(.system(size: 12))
      .foregroundStyle(mismatch ? Color.red : SparkStyle.secondaryLabel)
      .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func add() {
    viewModel.addEditableRange(name: name, password: password.isEmpty ? nil : password)
    name = ""
    password = ""
    confirm = ""
  }
}

/// Sheet ▸ Unlock Edit Range: a password-protected editable range opened until the file closes.
struct UnlockEditRangeDialog: View {
  @Bindable var viewModel: SpreadsheetViewModel
  let range: EditableRange
  let onDismiss: () -> Void
  @State private var password = ""
  @State private var wrong = false

  var body: some View {
    SparkDialog(
      title: "Unlock Edit Range",
      subtitle: range.name,
      primaryTitle: "Unlock",
      primaryDisabled: password.isEmpty,
      onCancel: onDismiss,
      onPrimary: unlock
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
        Text("That password doesn't open this range.")
          .font(.system(size: 12))
          .foregroundStyle(Color.red)
      }
    }
  }

  private func unlock() {
    if viewModel.unlockEditableRange(named: range.name, password: password) {
      onDismiss()
    } else {
      wrong = true
    }
  }
}

enum RangeProtectionPresenter {
  @MainActor
  static func lockRange(from viewModel: SpreadsheetViewModel, in window: NSWindow? = nil) {
    viewModel.commitEditIfNeeded()
    SparkDialogPresenter.present(title: "Lock Range", width: 440, in: window) { close in
      LockRangeDialog(viewModel: viewModel, onDismiss: close)
    }
  }

  @MainActor
  static func removeRangeLock(from viewModel: SpreadsheetViewModel, in window: NSWindow? = nil) {
    viewModel.commitEditIfNeeded()
    guard let lock = viewModel.selectedRangeLocks.first else { return }
    guard lock.passwordHash != nil else {
      viewModel.removeRangeLock(lock.id)
      return
    }
    SparkDialogPresenter.present(title: "Remove Range Lock", width: 400, in: window) { close in
      RemoveRangeLockDialog(viewModel: viewModel, lock: lock, onDismiss: close)
    }
  }

  @MainActor
  static func editableRanges(from viewModel: SpreadsheetViewModel, in window: NSWindow? = nil) {
    viewModel.commitEditIfNeeded()
    SparkDialogPresenter.present(title: "Allow Edit Ranges", width: 480, in: window) { close in
      EditableRangesDialog(viewModel: viewModel, onDismiss: close)
    }
  }

  @MainActor
  static func unlockEditRange(from viewModel: SpreadsheetViewModel, in window: NSWindow? = nil) {
    viewModel.commitEditIfNeeded()
    guard let range = viewModel.closedEditableRangesAtSelection.first else { return }
    SparkDialogPresenter.present(title: "Unlock Edit Range", width: 400, in: window) { close in
      UnlockEditRangeDialog(viewModel: viewModel, range: range, onDismiss: close)
    }
  }
}
