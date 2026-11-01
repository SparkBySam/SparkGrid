import AppKit
import SwiftUI

/// The layout every Spark Grid dialog shares, after the filter panel: a title and what it applies
/// to, grouped rows with the label left and the control right, and a footer with a secondary
/// action on the left and Cancel plus the main action on the right. Sized to its content.
struct SparkDialog<Content: View, Leading: View>: View {
  let title: String
  let subtitle: String
  let primaryTitle: String
  var primaryDisabled = false
  var cancelTitle = "Cancel"
  let onCancel: () -> Void
  let onPrimary: () -> Void
  @ViewBuilder var leading: () -> Leading
  @ViewBuilder var content: () -> Content

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(SparkStyle.label)
        Text(subtitle)
          .font(.system(size: 12))
          .foregroundStyle(SparkStyle.secondaryLabel)
      }
      .padding(.horizontal, 20)
      .padding(.top, 16)
      .padding(.bottom, 12)

      VStack(alignment: .leading, spacing: 12) {
        content()
      }
      .padding(.horizontal, 20)
      .padding(.bottom, 16)

      Divider()

      HStack(spacing: 8) {
        leading()
        Spacer(minLength: 12)
        Button(cancelTitle, action: onCancel)
          .keyboardShortcut(.cancelAction)
        Button(primaryTitle, action: onPrimary)
          .keyboardShortcut(.defaultAction)
          .buttonStyle(.borderedProminent)
          .tint(SparkStyle.accent)
          .disabled(primaryDisabled)
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 12)
    }
    .background(SparkStyle.window)
    .fixedSize(horizontal: false, vertical: true)
  }
}

extension SparkDialog where Leading == EmptyView {
  init(
    title: String,
    subtitle: String,
    primaryTitle: String,
    primaryDisabled: Bool = false,
    onCancel: @escaping () -> Void,
    onPrimary: @escaping () -> Void,
    @ViewBuilder content: @escaping () -> Content
  ) {
    self.title = title
    self.subtitle = subtitle
    self.primaryTitle = primaryTitle
    self.primaryDisabled = primaryDisabled
    self.onCancel = onCancel
    self.onPrimary = onPrimary
    self.leading = { EmptyView() }
    self.content = content
  }
}

/// A rounded group of rows. Put `SparkDialogDivider()` between rows.
struct SparkDialogGroup<Content: View>: View {
  @ViewBuilder var content: () -> Content

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      content()
    }
    .background(
      RoundedRectangle(cornerRadius: 8).fill(SparkStyle.chrome)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 8).stroke(SparkStyle.separator, lineWidth: 1)
    )
  }
}

/// The hairline between rows of a group.
struct SparkDialogDivider: View {
  var body: some View {
    Divider().padding(.leading, 12)
  }
}

/// One row: the label on the left, the control on the right.
struct SparkDialogRow<Control: View>: View {
  let label: String
  @ViewBuilder var control: () -> Control

  var body: some View {
    HStack(spacing: 10) {
      Text(label)
        .font(.system(size: 13))
        .foregroundStyle(SparkStyle.label)
      Spacer(minLength: 8)
      control()
    }
    .padding(.horizontal, 12)
    .frame(minHeight: 36)
  }
}

/// A small capitalized heading above a group.
struct SparkDialogSection: View {
  let title: String

  var body: some View {
    Text(title.uppercased())
      .font(.system(size: 11, weight: .semibold))
      .tracking(0.4)
      .foregroundStyle(SparkStyle.secondaryLabel)
      .padding(.horizontal, 2)
      .padding(.bottom, -4)
  }
}

/// Shows a dialog as a sheet on the document window. One dialog per window at a time.
@MainActor
enum SparkDialogPresenter {
  private final class Controller: NSObject, NSWindowDelegate {
    var window: NSWindow?

    func windowWillClose(_ notification: Notification) {
      window = nil
    }

    func close() {
      if let window, let sheetParent = window.sheetParent {
        sheetParent.endSheet(window)
      } else {
        window?.close()
      }
      window = nil
    }
  }

  private static var controllers: [ObjectIdentifier: Controller] = [:]

  /// `content` receives the close action.
  static func present<Content: View>(
    title: String,
    width: CGFloat,
    in window: NSWindow? = nil,
    content: (@escaping () -> Void) -> Content
  ) {
    let parent = window ?? NSApp.keyWindow ?? NSApp.mainWindow
    let key = parent.map { ObjectIdentifier($0) }
    if let key, let existing = controllers[key] {
      existing.close()
      controllers[key] = nil
    }
    let controller = Controller()
    let close: () -> Void = {
      controller.close()
      if let key { controllers[key] = nil }
    }
    let hosting = NSHostingController(rootView: content(close).frame(width: width))
    hosting.sizingOptions = [.preferredContentSize]
    let sheetWindow = NSWindow(contentViewController: hosting)
    sheetWindow.title = title
    sheetWindow.styleMask = [.titled, .closable]
    controller.window = sheetWindow
    sheetWindow.delegate = controller
    if let key { controllers[key] = controller }
    if let parent {
      parent.beginSheet(sheetWindow) { _ in
        controller.window = nil
        if let key { controllers[key] = nil }
      }
    } else {
      sheetWindow.center()
      sheetWindow.makeKeyAndOrderFront(nil)
    }
  }
}
