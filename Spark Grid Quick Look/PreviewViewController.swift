import AppKit
import QuickLookUI
import SparkGridCore
import UniformTypeIdentifiers

/// Finder Quick Look preview: spreadsheet grid with basic cell editing and Save.
/// ObjC name must match NSExtensionPrincipalClass in Info.plist (`PreviewViewController`).
@objc(PreviewViewController)
final class PreviewViewController: NSViewController, QLPreviewingController {
  private var session: PreviewSession?
  private let tableController = PreviewTableController()

  private let chromeStack = NSStackView()
  private let titleLabel = NSTextField(labelWithString: "")
  private let statusLabel = NSTextField(labelWithString: "")
  private let sheetPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
  private let saveButton = NSButton(title: "Save", target: nil, action: nil)
  private let openButton = NSButton(title: "Open in Spark Grid", target: nil, action: nil)
  private let scrollView = NSScrollView()

  /// Code-only controller — do not look for PreviewViewController.nib.
  override var nibName: NSNib.Name? { nil }

  override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
    super.init(nibName: nil, bundle: nibBundleOrNil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    return nil
  }

  override func loadView() {
    view = NSView(frame: NSRect(x: 0, y: 0, width: 720, height: 480))
    view.wantsLayer = true

    chromeStack.orientation = .vertical
    chromeStack.alignment = .leading
    chromeStack.spacing = 8
    chromeStack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
    chromeStack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(chromeStack)

    titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
    titleLabel.lineBreakMode = .byTruncatingMiddle
    titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    statusLabel.font = .systemFont(ofSize: 11)
    statusLabel.textColor = .secondaryLabelColor
    statusLabel.lineBreakMode = .byTruncatingTail

    sheetPopUp.target = self
    sheetPopUp.action = #selector(sheetChanged(_:))
    sheetPopUp.isHidden = true

    saveButton.target = self
    saveButton.action = #selector(saveClicked(_:))
    saveButton.keyEquivalent = "s"
    saveButton.keyEquivalentModifierMask = [.command]
    saveButton.isEnabled = false

    openButton.target = self
    openButton.action = #selector(openClicked(_:))

    let spacer = NSView()
    spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    let topRow = NSStackView(views: [titleLabel, spacer, sheetPopUp, saveButton, openButton])
    topRow.orientation = .horizontal
    topRow.alignment = .centerY
    topRow.spacing = 8
    topRow.distribution = .fill
    titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.borderType = .bezelBorder
    scrollView.documentView = tableController.tableView
    scrollView.translatesAutoresizingMaskIntoConstraints = false

    chromeStack.addArrangedSubview(topRow)
    chromeStack.addArrangedSubview(statusLabel)
    chromeStack.addArrangedSubview(scrollView)

    NSLayoutConstraint.activate([
      chromeStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      chromeStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      chromeStack.topAnchor.constraint(equalTo: view.topAnchor),
      chromeStack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 200),
      topRow.widthAnchor.constraint(equalTo: chromeStack.widthAnchor, constant: -24),
      statusLabel.widthAnchor.constraint(equalTo: chromeStack.widthAnchor, constant: -24),
      scrollView.widthAnchor.constraint(equalTo: chromeStack.widthAnchor, constant: -24),
    ])

    tableController.onEdit = { [weak self] in
      self?.refreshChrome()
    }
  }

  func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
    // Call handler promptly; heavy parse stays off the main thread.
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let accessed = url.startAccessingSecurityScopedResource()
      defer {
        if accessed { url.stopAccessingSecurityScopedResource() }
      }

      do {
        let data = try Data(contentsOf: url)
        let name = url.deletingPathExtension().lastPathComponent
        let type = UTType(filenameExtension: url.pathExtension)
        let workbook = try SpreadsheetDocument.workbook(
          from: data,
          sheetName: name.isEmpty ? "Sheet1" : name,
          contentType: type
        )
        DispatchQueue.main.async {
          guard let self else {
            handler(nil)
            return
          }
          let session = PreviewSession(fileURL: url, workbook: workbook)
          self.session = session
          self.tableController.session = session
          self.configureChrome(for: url, session: session)
          self.tableController.reload()
          handler(nil)
        }
      } catch {
        DispatchQueue.main.async {
          handler(error)
        }
      }
    }
  }

  private func configureChrome(for url: URL, session: PreviewSession) {
    titleLabel.stringValue = url.lastPathComponent
    sheetPopUp.removeAllItems()
    if session.sheetNames.count > 1 {
      sheetPopUp.isHidden = false
      sheetPopUp.addItems(withTitles: session.sheetNames)
      sheetPopUp.selectItem(at: session.activeSheetIndex)
    } else {
      sheetPopUp.isHidden = true
    }
    refreshChrome()
  }

  private func refreshChrome() {
    guard let session else {
      statusLabel.stringValue = ""
      saveButton.isEnabled = false
      return
    }
    var parts: [String] = []
    parts.append("\(session.previewRowCount) × \(session.previewColumnCount)")
    if session.isTruncated {
      parts.append("showing first \(PreviewSession.maxPreviewRows) rows")
    }
    if session.isDirty {
      parts.append("Edited — press ⌘S to save")
    } else {
      parts.append("Double-click a cell to edit")
    }
    statusLabel.stringValue = parts.joined(separator: " · ")
    saveButton.isEnabled = session.isDirty
  }

  @objc private func sheetChanged(_ sender: NSPopUpButton) {
    guard let session else { return }
    session.activeSheetIndex = sender.indexOfSelectedItem
    tableController.reload()
    refreshChrome()
  }

  @objc private func saveClicked(_ sender: Any?) {
    guard let session else { return }
    do {
      try session.save()
      refreshChrome()
    } catch {
      presentError(error)
    }
  }

  @objc private func openClicked(_ sender: Any?) {
    guard let session else { return }
    if session.isDirty {
      let alert = NSAlert()
      alert.messageText = "Save changes before opening?"
      alert.informativeText = "Spark Grid will open the file on disk."
      alert.addButton(withTitle: "Save and Open")
      alert.addButton(withTitle: "Open Without Saving")
      alert.addButton(withTitle: "Cancel")
      switch alert.runModal() {
      case .alertFirstButtonReturn:
        do {
          try session.save()
        } catch {
          presentError(error)
          return
        }
      case .alertSecondButtonReturn:
        break
      default:
        return
      }
    }
    guard
      let appURL = NSWorkspace.shared.urlForApplication(
        withBundleIdentifier: "com.sparkbysam.SparkGrid")
    else {
      NSWorkspace.shared.open(session.fileURL)
      return
    }
    let configuration = NSWorkspace.OpenConfiguration()
    NSWorkspace.shared.open(
      [session.fileURL],
      withApplicationAt: appURL,
      configuration: configuration
    )
  }
}
