import AppKit
import SparkGridCore
import SwiftUI

/// Format ▸ Cells. A list of number types on the left; on the right, a sample from the selection
/// and only the options that type has. Conditional formatting has its own dialog.
struct CellFormatViewerSheet: View {
  enum Category: String, CaseIterable, Identifiable {
    case general, number, currency, percent, scientific, date, time, custom

    var id: String { rawValue }

    var title: String {
      switch self {
      case .general: return "General"
      case .number: return "Number"
      case .currency: return "Currency"
      case .percent: return "Percent"
      case .scientific: return "Scientific"
      case .date: return "Date"
      case .time: return "Time"
      case .custom: return "Custom"
      }
    }

    var usesDecimals: Bool { [.number, .currency, .percent, .scientific].contains(self) }
    var usesThousands: Bool { self == .number || self == .currency }
  }

  enum Negative: String, CaseIterable, Identifiable {
    case minus, minusRed, parentheses, parenthesesRed
    var id: String { rawValue }
    var title: String {
      switch self {
      case .minus: return "-1,234.10"
      case .minusRed: return "-1,234.10 in red"
      case .parentheses: return "(1,234.10)"
      case .parenthesesRed: return "(1,234.10) in red"
      }
    }
  }

  static let dateCodes = ["m/d/yyyy", "mmm d, yyyy", "mmmm d, yyyy", "d-mmm-yy", "yyyy-mm-dd"]
  static let timeCodes = ["h:mm AM/PM", "h:mm:ss AM/PM", "HH:mm", "HH:mm:ss"]

  /// What the dialog would apply.
  struct Draft: Equatable {
    var category: Category = .general
    var decimals = 2
    var thousands = true
    var negative: Negative = .minus
    var dateCode = CellFormatViewerSheet.dateCodes[0]
    var timeCode = CellFormatViewerSheet.timeCodes[0]
    var customCode = ""

    /// The number format code, or nil for General.
    var code: String? {
      let zeros = decimals > 0 ? "." + String(repeating: "0", count: decimals) : ""
      switch category {
      case .general:
        return nil
      case .number, .currency:
        let body = (category == .currency ? "$" : "") + (thousands ? "#,##0" : "0") + zeros
        switch negative {
        case .minus: return body
        case .minusRed: return "\(body);[Red]-\(body)"
        case .parentheses: return "\(body);(\(body))"
        case .parenthesesRed: return "\(body);[Red](\(body))"
        }
      case .percent:
        return "0\(zeros)%"
      case .scientific:
        return "0\(zeros)E+00"
      case .date:
        return dateCode
      case .time:
        return timeCode
      case .custom:
        let trimmed = customCode.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.caseInsensitiveCompare("General") == .orderedSame
          ? nil : trimmed
      }
    }

    /// The draft that writes `format`, or a custom code when no preset matches it.
    static func reading(_ format: CellFormat) -> Draft {
      let code = format.formatCode?.trimmingCharacters(in: .whitespacesAndNewlines)
      let stored = (code?.isEmpty == false ? code : nil) ?? format.viewerFormatCode
      if stored.caseInsensitiveCompare("General") == .orderedSame { return Draft() }
      for category in Category.allCases where category != .general && category != .custom {
        for candidate in candidates(for: category) where candidate.code == stored {
          return candidate
        }
      }
      var custom = Draft()
      custom.category = .custom
      custom.customCode = stored
      return custom
    }

    private static func candidates(for category: Category) -> [Draft] {
      var found: [Draft] = []
      var base = Draft()
      base.category = category
      switch category {
      case .date:
        for code in dateCodes {
          base.dateCode = code
          found.append(base)
        }
      case .time:
        for code in timeCodes {
          base.timeCode = code
          found.append(base)
        }
      default:
        for decimals in 0...10 {
          base.decimals = decimals
          for thousands in [true, false] {
            base.thousands = thousands
            for negative in Negative.allCases {
              base.negative = negative
              found.append(base)
            }
          }
        }
      }
      return found
    }
  }

  @Bindable var viewModel: SpreadsheetViewModel
  let onDismiss: () -> Void

  @State private var draft = Draft()
  @State private var loaded = false
  @State private var formatFieldFocusToken = 0

  var body: some View {
    SparkDialog(
      title: "Format Cells",
      subtitle: "Applies to \(viewModel.selectionRange.a1Label)",
      primaryTitle: "Apply",
      onCancel: { runPanel(.close) },
      onPrimary: { runPanel(.apply) },
      leading: {
        Button("Clear Format") {
          viewModel.setFormatCode(nil)
          draft = Draft()
        }
      },
      content: {
        HStack(alignment: .top, spacing: 12) {
          categoryList
          VStack(alignment: .leading, spacing: 12) {
            sample
            options
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    )
    .onAppear {
      guard !loaded else { return }
      loaded = true
      draft = Draft.reading(viewModel.selectedFormat)
    }
  }

  private var categoryList: some View {
    VStack(alignment: .leading, spacing: 1) {
      ForEach(Category.allCases) { item in
        Button {
          select(item)
        } label: {
          Text(item.title)
            .font(.system(size: 13, weight: draft.category == item ? .semibold : .regular))
            .foregroundStyle(SparkStyle.label)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(
              RoundedRectangle(cornerRadius: 5)
                .fill(draft.category == item ? SparkStyle.accent.opacity(0.22) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(draft.category == item ? .isSelected : AccessibilityTraits())
      }
    }
    .padding(4)
    .frame(width: 150)
    .background(RoundedRectangle(cornerRadius: 8).fill(SparkStyle.chrome))
    .overlay(RoundedRectangle(cornerRadius: 8).stroke(SparkStyle.separator, lineWidth: 1))
  }

  private var sample: some View {
    let (value, raw, isExample) = sampleSource
    var format = viewModel.selectedFormat
    format.numberFormat = draft.code.map { ExcelFormatCode.numberFormatKind(for: $0) } ?? .general
    format.formatCode = draft.code
    format.decimalPlaces = nil
    let shown = CellFormatRenderer.displayText(for: value, format: format, fallbackRaw: raw)
    var negative: String?
    if case .number(let number) = value, draft.category == .number || draft.category == .currency {
      negative = CellFormatRenderer.displayText(
        for: .number(-abs(number)), format: format, fallbackRaw: "")
    }
    let negativeIsRed = draft.negative == .minusRed || draft.negative == .parenthesesRed
    return VStack(alignment: .leading, spacing: 2) {
      Text(isExample ? "Sample (example value)" : "Sample")
        .font(.system(size: 11))
        .foregroundStyle(SparkStyle.secondaryLabel)
      Text(shown.isEmpty ? " " : shown)
        .font(.system(size: 22, weight: .semibold))
        .monospacedDigit()
        .foregroundStyle(SparkStyle.label)
        .lineLimit(1)
      if let negative {
        Text(negative)
          .font(.system(size: 12))
          .monospacedDigit()
          .foregroundStyle(negativeIsRed ? Color(nsColor: .systemRed) : SparkStyle.secondaryLabel)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .background(RoundedRectangle(cornerRadius: 8).fill(SparkStyle.chrome))
    .overlay(RoundedRectangle(cornerRadius: 8).stroke(SparkStyle.separator, lineWidth: 1))
  }

  /// The selected cell's value, or an example that suits the type when the cell is empty.
  private var sampleSource: (CellValue, String, Bool) {
    let address = viewModel.selection
    let value = viewModel.displayValue(at: address)
    if case .blank = value {
      switch draft.category {
      case .date: return (.number(46_327), "", true)
      case .time: return (.number(0.75), "", true)
      case .percent: return (.number(0.256), "", true)
      default: return (.number(1234.5), "", true)
      }
    }
    return (value, viewModel.activeSheet.cell(at: address).raw, false)
  }

  @ViewBuilder private var options: some View {
    switch draft.category {
    case .general:
      Text("Shows the value as it was typed.")
        .font(.system(size: 12))
        .foregroundStyle(SparkStyle.secondaryLabel)
    case .number, .currency, .percent, .scientific:
      SparkDialogGroup {
        SparkDialogRow(label: "Decimal places") {
          Stepper(value: $draft.decimals, in: 0...10) {
            Text("\(draft.decimals)")
              .monospacedDigit()
              .frame(minWidth: 18, alignment: .trailing)
          }
          .fixedSize()
        }
        if draft.category.usesThousands {
          SparkDialogDivider()
          SparkDialogRow(label: "Thousands separator") {
            Toggle("", isOn: $draft.thousands)
              .toggleStyle(.switch)
              .controlSize(.small)
              .labelsHidden()
              .tint(SparkStyle.accent)
          }
          SparkDialogDivider()
          SparkDialogRow(label: "Negative numbers") {
            Picker("Negative numbers", selection: $draft.negative) {
              ForEach(Negative.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
          }
        }
      }
    case .date:
      SparkDialogGroup {
        SparkDialogRow(label: "Style") {
          Picker("Style", selection: $draft.dateCode) {
            ForEach(Self.dateCodes, id: \.self) { Text(example(for: $0, value: 46_327)).tag($0) }
          }
          .labelsHidden()
          .fixedSize()
        }
      }
    case .time:
      SparkDialogGroup {
        SparkDialogRow(label: "Style") {
          Picker("Style", selection: $draft.timeCode) {
            ForEach(Self.timeCodes, id: \.self) { Text(example(for: $0, value: 0.75)).tag($0) }
          }
          .labelsHidden()
          .fixedSize()
        }
      }
    case .custom:
      VStack(alignment: .leading, spacing: 6) {
        CellFormatCodeField(
          text: $draft.customCode,
          focusToken: formatFieldFocusToken,
          onSubmit: { runPanel(.apply) }
        )
        .frame(height: 24)
        Text("Sections are positive; negative; zero; text. Put words in quotes.")
          .font(.system(size: 11))
          .foregroundStyle(SparkStyle.secondaryLabel)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private func example(for code: String, value: Double) -> String {
    var format = CellFormat()
    format.formatCode = code
    format.numberFormat = ExcelFormatCode.numberFormatKind(for: code)
    return CellFormatRenderer.displayText(for: .number(value), format: format, fallbackRaw: "")
  }

  private func select(_ next: Category) {
    if next == .custom, draft.customCode.isEmpty {
      draft.customCode = draft.code ?? ""
    }
    draft.category = next
    if next == .custom {
      formatFieldFocusToken += 1
    }
  }

  private func runPanel(_ action: CellFormatPanelAction) {
    CellFormatPanel.perform(action, store: applyDraft, close: onDismiss)
  }

  private func applyDraft() {
    viewModel.setFormatCode(draft.code)
  }
}

enum CellFormatViewerPresenter {
  @MainActor
  static func present(from viewModel: SpreadsheetViewModel, in window: NSWindow? = nil) {
    viewModel.commitEditIfNeeded()
    SparkDialogPresenter.present(title: "Format Cells", width: 540, in: window) { close in
      CellFormatViewerSheet(viewModel: viewModel, onDismiss: close)
    }
  }
}

/// Apply stores the draft and closes the panel. Close dismisses without storing.
/// Clicking the parent window leaves the sheet up and does not store.
enum CellFormatPanelAction: Equatable {
  case apply
  case close
  case clickAway
}

struct CellFormatPanelResult: Equatable {
  var storesDraft: Bool
  var closes: Bool
}

enum CellFormatPanel {
  static func result(for action: CellFormatPanelAction) -> CellFormatPanelResult {
    switch action {
    case .apply:
      return CellFormatPanelResult(storesDraft: true, closes: true)
    case .close:
      return CellFormatPanelResult(storesDraft: false, closes: true)
    case .clickAway:
      return CellFormatPanelResult(storesDraft: false, closes: false)
    }
  }

  static func perform(
    _ action: CellFormatPanelAction,
    store: () -> Void,
    close: () -> Void
  ) {
    let outcome = result(for: action)
    if outcome.storesDraft { store() }
    if outcome.closes { close() }
  }
}

/// Edit → Paste and the grid’s ⌘V. The format field takes the paste while it is editing.
enum SpreadsheetPaste {
  static func perform(on viewModel: SpreadsheetViewModel?) {
    if CellFormatCodePaste.pasteIntoEditingField() { return }
    viewModel?.pasteFromPasteboard()
  }
}

enum CellFormatCodePaste {
  static weak var editingField: CellFormatCodeTextField?

  /// Swallows the paste shortcut while the format field is editing so the grid command does not run.
  static func handleKeyDown(_ event: NSEvent) -> NSEvent? {
    guard let field = editingField, AppSettings.shared.matches(.paste, event: event) else {
      return event
    }
    field.insertPasteboardReplacingSelection()
    return nil
  }

  static func pasteIntoEditingField() -> Bool {
    guard let field = editingField ?? fieldFromFirstResponder() else { return false }
    field.insertPasteboardReplacingSelection()
    return true
  }

  private static func fieldFromFirstResponder() -> CellFormatCodeTextField? {
    let responder = NSApp.keyWindow?.firstResponder
    if let field = responder as? CellFormatCodeTextField { return field }
    if let textView = responder as? NSTextView,
      let field = textView.delegate as? CellFormatCodeTextField
    {
      return field
    }
    return nil
  }
}

/// Format code box. Paste stays in this field while it is focused.
private struct CellFormatCodeField: NSViewRepresentable {
  @Binding var text: String
  var focusToken: Int
  var onSubmit: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(text: $text, onSubmit: onSubmit)
  }

  func makeNSView(context: Context) -> CellFormatCodeTextField {
    let field = CellFormatCodeTextField()
    field.stringValue = text
    field.placeholderString = "#,##0.00;(#,##0.00);0;@"
    field.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    field.isBezeled = true
    field.bezelStyle = .roundedBezel
    field.delegate = context.coordinator
    field.cell?.isScrollable = true
    field.cell?.wraps = false
    field.cell?.lineBreakMode = .byClipping
    field.setAccessibilityLabel("Format code")
    field.onTextChange = { context.coordinator.text = $0 }
    return field
  }

  func updateNSView(_ field: CellFormatCodeTextField, context: Context) {
    context.coordinator.onSubmit = onSubmit
    field.onTextChange = { context.coordinator.text = $0 }
    field.delegate = context.coordinator
    if field.liveText != text {
      field.replaceLiveText(text)
    }
    if focusToken != context.coordinator.appliedFocusToken {
      context.coordinator.appliedFocusToken = focusToken
      if focusToken != 0 {
        DispatchQueue.main.async {
          field.window?.makeFirstResponder(field)
        }
      }
    }
  }

  final class Coordinator: NSObject, NSTextFieldDelegate {
    @Binding var text: String
    var onSubmit: () -> Void
    var appliedFocusToken = 0

    init(text: Binding<String>, onSubmit: @escaping () -> Void) {
      _text = text
      self.onSubmit = onSubmit
    }

    func controlTextDidChange(_ notification: Notification) {
      guard let field = notification.object as? CellFormatCodeTextField else { return }
      text = field.liveText
    }

    func control(
      _ control: NSControl,
      textView: NSTextView,
      doCommandBy commandSelector: Selector
    ) -> Bool {
      if commandSelector == #selector(NSResponder.insertNewline(_:)) {
        onSubmit()
        return true
      }
      return false
    }
  }
}

final class CellFormatCodeTextField: NSTextField {
  var onTextChange: ((String) -> Void)?
  private var pasteMonitor: Any?

  var isInterceptingPaste: Bool { pasteMonitor != nil }

  var liveText: String {
    if let editor = currentEditor() as? NSTextView { return editor.string }
    return stringValue
  }

  func replaceLiveText(_ text: String) {
    if let editor = currentEditor() as? NSTextView {
      if editor.string != text {
        editor.string = text
      }
    } else if stringValue != text {
      stringValue = text
    }
  }

  /// Plain-text paste at the caret, drawn with the same attributes as typed text.
  /// Replacing into the text storage keeps a black foreground from the pasteboard.
  func insertPasteboardReplacingSelection() {
    guard let pasted = NSPasteboard.general.string(forType: .string) else { return }
    if let editor = ensureEditor(), let storage = editor.textStorage {
      let ns = editor.string as NSString
      var range = editor.selectedRange()
      if range.location == NSNotFound || range.location > ns.length {
        range = NSRange(location: ns.length, length: 0)
      } else if NSMaxRange(range) > ns.length {
        range.length = max(0, ns.length - range.location)
      }
      let typed = attributesMatchingTypedText(in: editor)
      let inserted = NSRange(location: range.location, length: (pasted as NSString).length)
      storage.beginEditing()
      storage.replaceCharacters(in: range, with: pasted)
      if inserted.length > 0, NSMaxRange(inserted) <= storage.length {
        storage.setAttributes(typed, range: inserted)
      }
      storage.endEditing()
      let caret = range.location + (pasted as NSString).length
      editor.setSelectedRange(
        NSRange(location: min(caret, (editor.string as NSString).length), length: 0))
      editor.typingAttributes = typed
      editor.didChangeText()
      if inserted.length > 0, let storage = editor.textStorage,
        NSMaxRange(inserted) <= storage.length
      {
        storage.beginEditing()
        storage.setAttributes(typed, range: inserted)
        storage.endEditing()
      }
    } else {
      stringValue = pasted
    }
    onTextChange?(liveText)
  }

  /// Font and foreground used for characters typed in this field.
  private func attributesMatchingTypedText(in editor: NSTextView) -> [NSAttributedString.Key: Any] {
    var attrs = editor.typingAttributes
    if attrs[.font] == nil {
      attrs[.font] =
        editor.font ?? font
        ?? NSFont.monospacedSystemFont(
          ofSize: NSFont.systemFontSize,
          weight: .regular
        )
    }
    if attrs[.foregroundColor] == nil {
      attrs[.foregroundColor] = textColor ?? NSColor.labelColor
    }
    return attrs
  }

  override func becomeFirstResponder() -> Bool {
    let ok = super.becomeFirstResponder()
    if ok { beginInterceptingPaste() }
    return ok
  }

  override func textDidBeginEditing(_ notification: Notification) {
    beginInterceptingPaste()
    super.textDidBeginEditing(notification)
  }

  override func textDidEndEditing(_ notification: Notification) {
    endInterceptingPaste()
    super.textDidEndEditing(notification)
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if window == nil {
      endInterceptingPaste()
    }
  }

  private func beginInterceptingPaste() {
    CellFormatCodePaste.editingField = self
    guard pasteMonitor == nil else { return }
    pasteMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      CellFormatCodePaste.handleKeyDown(event)
    }
  }

  private func endInterceptingPaste() {
    if CellFormatCodePaste.editingField === self {
      CellFormatCodePaste.editingField = nil
    }
    if let pasteMonitor {
      NSEvent.removeMonitor(pasteMonitor)
      self.pasteMonitor = nil
    }
  }

  private func ensureEditor() -> NSTextView? {
    if let editor = currentEditor() as? NSTextView { return editor }
    window?.makeFirstResponder(self)
    return currentEditor() as? NSTextView
  }
}
