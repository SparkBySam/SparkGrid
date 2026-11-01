import AppKit
import SparkGridCore
import SwiftUI

/// AppKit formula bar using NSTextView so ref colors survive focus/editing.
struct FormulaBarTextField: NSViewRepresentable {
  @Binding var text: String
  /// Observed copy of the formula bar contents so in-cell typing mirrors here live.
  var liveText: String
  /// Bumped by Insert Function. Zero means no pending caret placement.
  var caretToken: Int = 0
  var caretUTF16: Int = 0
  var namedRanges: [String]
  var highlights: [FormulaRefHighlight]
  var focusedHighlightIndex: Int?
  var visibleHeight: CGFloat = 18
  var onSubmit: (String) -> Void
  var onTextChange: () -> Void
  var onBeginEditing: () -> Void
  var onCaretMoved: (Int) -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  func makeNSView(context: Context) -> FormulaBarContainerView {
    let container = FormulaBarContainerView()
    container.textView.delegate = context.coordinator
    context.coordinator.textView = container.textView
    container.textView.string = liveText
    container.setVisibleHeight(visibleHeight)
    context.coordinator.applyAttributes(force: true)
    return container
  }

  func updateNSView(_ nsView: FormulaBarContainerView, context: Context) {
    context.coordinator.parent = self
    context.coordinator.textView = nsView.textView
    nsView.setVisibleHeight(visibleHeight)

    let textView = nsView.textView
    let isFocused = textView.window?.firstResponder === textView

    if caretToken != 0, caretToken != context.coordinator.appliedCaretToken {
      context.coordinator.applyCaretRequest(token: caretToken, utf16: caretUTF16)
    } else if !isFocused, textView.string != liveText {
      // Mirror selection / in-cell typing whenever the bar isn't focused.
      textView.string = liveText
      context.coordinator.lastAppliedKey = ""
    }

    context.coordinator.applyAttributes(force: false)
  }

  final class Coordinator: NSObject, NSTextViewDelegate {
    var parent: FormulaBarTextField
    weak var textView: FormulaBarNSTextView?
    private var isApplyingAttributes = false
    private var isSubmitting = false
    var lastAppliedKey = ""
    var appliedCaretToken = 0
    private var didBeginEditing = false
    /// True after formula reference colors were written, so leaving a formula can restore plain text once.
    private var showingFormulaAttributes = false

    init(_ parent: FormulaBarTextField) {
      self.parent = parent
    }

    private func highlightKey(for text: String) -> String {
      let spans = parent.highlights.map {
        "\($0.utf16Range.location):\($0.utf16Range.length):\($0.colorIndex)"
      }.joined(separator: ",")
      return "\(text)|\(parent.focusedHighlightIndex ?? -1)|\(spans)"
    }

    func applyAttributes(force: Bool) {
      guard let textView, let storage = textView.textStorage else { return }
      let raw = textView.string

      // Prose keeps the text storage stable so the system spelling underline can stick.
      // Leaving a formula restores plain typing attributes once.
      if EditorSpellCheck.shouldCheck(raw) {
        let leftFormula = showingFormulaAttributes
        if leftFormula {
          applyPlainTypingAttributes(textView: textView, storage: storage)
          showingFormulaAttributes = false
        }
        EditorSpellCheck.apply(to: textView, text: raw, refresh: leftFormula)
        lastAppliedKey = highlightKey(for: raw)
        return
      }

      EditorSpellCheck.apply(to: textView, text: raw, refresh: false)

      // Numbers are not formulas. Leave the text alone so formula colors are not applied.
      guard FormulaSyntax.isFormula(raw) else {
        if showingFormulaAttributes {
          applyPlainTypingAttributes(textView: textView, storage: storage)
          showingFormulaAttributes = false
        }
        lastAppliedKey = highlightKey(for: raw)
        return
      }

      let key = highlightKey(for: raw)
      if !force, key == lastAppliedKey { return }
      guard !isApplyingAttributes else { return }

      isApplyingAttributes = true
      defer { isApplyingAttributes = false }

      let font =
        textView.font
        ?? .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
      let color = SparkTheme.label
      let attributed = FormulaReferenceScanner.attributedFormula(
        raw,
        highlights: parent.highlights,
        focusedIndex: parent.focusedHighlightIndex,
        baseFont: font,
        baseColor: color
      )

      let selected = textView.selectedRange
      storage.beginEditing()
      storage.setAttributedString(attributed)
      storage.endEditing()
      textView.typingAttributes = [
        .font: font,
        .foregroundColor: color,
        .backgroundColor: NSColor.clear,
      ]

      let maxLen = storage.length
      let loc = min(selected.location, maxLen)
      let len = min(selected.length, max(0, maxLen - loc))
      let next = NSRange(location: loc, length: len)
      if textView.selectedRange != next {
        textView.setSelectedRange(next)
      }
      showingFormulaAttributes = true
      lastAppliedKey = key
    }

    private func applyPlainTypingAttributes(textView: FormulaBarNSTextView, storage: NSTextStorage)
    {
      guard !isApplyingAttributes else { return }
      isApplyingAttributes = true
      defer { isApplyingAttributes = false }

      let font =
        textView.font
        ?? .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
      let color = SparkTheme.label
      let selected = textView.selectedRange
      let plain = NSAttributedString(
        string: textView.string,
        attributes: [
          .font: font,
          .foregroundColor: color,
          .backgroundColor: NSColor.clear,
        ]
      )
      storage.beginEditing()
      storage.setAttributedString(plain)
      storage.endEditing()
      textView.typingAttributes = [
        .font: font,
        .foregroundColor: color,
        .backgroundColor: NSColor.clear,
      ]
      let maxLen = storage.length
      let loc = min(selected.location, maxLen)
      let len = min(selected.length, max(0, maxLen - loc))
      let next = NSRange(location: loc, length: len)
      if textView.selectedRange != next {
        textView.setSelectedRange(next)
      }
    }

    func textDidBeginEditing(_ notification: Notification) {
      guard !didBeginEditing else { return }
      didBeginEditing = true
      parent.onBeginEditing()
      lastAppliedKey = ""
      applyAttributes(force: true)
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.lastAppliedKey = ""
        self.applyAttributes(force: true)
        self.emitCaret()
      }
    }

    func textDidEndEditing(_ notification: Notification) {
      didBeginEditing = false
      guard !isSubmitting, let textView else { return }
      let value = textView.string
      parent.text = value
      parent.onSubmit(value)
    }

    func textDidChange(_ notification: Notification) {
      guard let textView, !isApplyingAttributes else { return }
      parent.text = textView.string
      parent.onTextChange()
      lastAppliedKey = ""
      applyAttributes(force: true)
      emitCaret()
      maybeOfferCompletions()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
      guard !isApplyingAttributes else { return }
      emitCaret()
      DispatchQueue.main.async { [weak self] in
        self?.applyAttributes(force: false)
      }
    }

    func textView(
      _ textView: NSTextView,
      doCommandBy commandSelector: Selector
    ) -> Bool {
      if commandSelector == #selector(NSResponder.insertNewline(_:))
        || commandSelector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:))
      {
        // Option+Return inserts a line break (Excel Alt+Enter); Return commits.
        if NSApp.currentEvent?.modifierFlags.contains(.option) == true {
          textView.insertText("\n", replacementRange: textView.selectedRange)
          return true
        }
        submit()
        return true
      }
      if commandSelector == #selector(NSResponder.insertTab(_:)) {
        return applyTabCompletion()
      }
      return false
    }

    func textView(
      _ textView: NSTextView,
      completions words: [String],
      forPartialWordRange charRange: NSRange,
      indexOfSelectedItem index: UnsafeMutablePointer<Int>?
    ) -> [String] {
      guard textView.string.hasPrefix("=") else { return [] }
      guard
        FormulaAutocomplete.shouldOfferPopup(
          in: textView.string,
          utf16Cursor: charRange.location + charRange.length,
          namedRanges: parent.namedRanges
        )
      else { return [] }
      let partial = (textView.string as NSString).substring(with: charRange)
      index?.pointee = 0
      return FormulaAutocomplete.suggestions(
        matching: partial,
        namedRanges: parent.namedRanges
      )
    }

    private func emitCaret() {
      guard let textView else { return }
      parent.onCaretMoved(textView.selectedRange.location)
    }

    func applyCaretRequest(token: Int, utf16: Int) {
      guard let textView else { return }
      appliedCaretToken = token
      let text = parent.liveText
      if textView.string != text {
        isApplyingAttributes = true
        textView.string = text
        isApplyingAttributes = false
        lastAppliedKey = ""
      }
      applyAttributes(force: true)
      placeCaret(in: textView, utf16: utf16)
      DispatchQueue.main.async { [weak self] in
        guard let self, let textView = self.textView else { return }
        guard self.appliedCaretToken == token else { return }
        guard textView.string == self.parent.liveText else { return }
        textView.window?.makeFirstResponder(textView)
        self.placeCaret(in: textView, utf16: utf16)
        self.parent.onCaretMoved(min(max(0, utf16), (textView.string as NSString).length))
      }
    }

    private func placeCaret(in textView: FormulaBarNSTextView, utf16: Int) {
      let length = (textView.string as NSString).length
      let location = min(max(0, utf16), length)
      textView.setSelectedRange(NSRange(location: location, length: 0))
      textView.scrollRangeToVisible(NSRange(location: location, length: 0))
    }

    private func submit() {
      guard let textView else { return }
      let value = textView.string
      parent.text = value
      isSubmitting = true
      parent.onSubmit(value)
      resignToGrid()
      isSubmitting = false
      didBeginEditing = false
    }

    private func resignToGrid() {
      guard let window = textView?.window else { return }
      if let grid = findSpreadsheetGrid(in: window.contentView) {
        window.makeFirstResponder(grid)
      } else {
        window.makeFirstResponder(nil)
      }
    }

    private func findSpreadsheetGrid(in view: NSView?) -> NSView? {
      guard let view else { return nil }
      if view is SpreadsheetGridNSView { return view }
      for child in view.subviews {
        if let found = findSpreadsheetGrid(in: child) { return found }
      }
      return nil
    }

    private func applyTabCompletion() -> Bool {
      guard let textView else { return false }
      guard
        let result = FormulaAutocomplete.tabComplete(
          text: textView.string,
          utf16Cursor: textView.selectedRange.location,
          namedRanges: parent.namedRanges
        )
      else { return false }
      textView.string = result.text
      textView.setSelectedRange(NSRange(location: result.cursor, length: 0))
      parent.text = result.text
      parent.onTextChange()
      lastAppliedKey = ""
      applyAttributes(force: true)
      emitCaret()
      return true
    }

    private func maybeOfferCompletions() {
      guard let textView else { return }
      let cursor = textView.selectedRange.location
      guard
        FormulaAutocomplete.shouldOfferPopup(
          in: textView.string,
          utf16Cursor: cursor,
          namedRanges: parent.namedRanges
        )
      else {
        NSObject.cancelPreviousPerformRequests(
          withTarget: self,
          selector: #selector(triggerComplete),
          object: nil
        )
        return
      }
      NSObject.cancelPreviousPerformRequests(
        withTarget: self,
        selector: #selector(triggerComplete),
        object: nil
      )
      perform(#selector(triggerComplete), with: nil, afterDelay: 0.12)
    }

    @objc private func triggerComplete() {
      guard let textView, !isApplyingAttributes else { return }
      textView.complete(nil)
    }
  }
}

/// Hosts the formula-bar text view with a stable width in SwiftUI stacks.
final class FormulaBarContainerView: NSView {
  let textView = FormulaBarNSTextView()
  private var visibleHeight: CGFloat = 18

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    setup()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    return nil
  }

  func setVisibleHeight(_ height: CGFloat) {
    let next = max(18, height)
    guard abs(visibleHeight - next) > 0.5 else { return }
    visibleHeight = next
    // Document can grow taller than the viewport so multiline cells scroll when collapsed.
    textView.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    invalidateIntrinsicContentSize()
    needsLayout = true
  }

  private func setup() {
    let scroll = NSScrollView()
    scroll.drawsBackground = false
    scroll.backgroundColor = .clear
    scroll.borderType = .noBorder
    scroll.hasVerticalScroller = true
    scroll.hasHorizontalScroller = false
    scroll.autohidesScrollers = true
    scroll.scrollerStyle = .overlay
    scroll.translatesAutoresizingMaskIntoConstraints = false

    textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    textView.textColor = .labelColor
    textView.backgroundColor = .clear
    textView.drawsBackground = false
    textView.isRichText = true
    textView.allowsUndo = true
    textView.isEditable = true
    textView.isSelectable = true
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
    textView.textContainer?.widthTracksTextView = true
    textView.textContainer?.heightTracksTextView = false
    textView.textContainer?.lineFragmentPadding = 2
    textView.textContainerInset = NSSize(width: 0, height: 1)
    textView.minSize = .zero
    textView.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    textView.insertionPointColor = .labelColor
    textView.focusRingType = .none
    textView.autoresizingMask = [.width]

    scroll.documentView = textView
    addSubview(scroll)

    NSLayoutConstraint.activate([
      scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
      scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
      scroll.topAnchor.constraint(equalTo: topAnchor),
      scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
  }

  override var intrinsicContentSize: NSSize {
    NSSize(width: NSView.noIntrinsicMetric, height: visibleHeight)
  }

  override func layout() {
    super.layout()
    // Keep the text view as wide as the visible clip so wrapping/clipping is correct.
    if let clip = textView.enclosingScrollView?.contentView {
      var frame = textView.frame
      frame.size.width = max(clip.bounds.width, 1)
      let usedHeight: CGFloat
      if let container = textView.textContainer,
        let layoutManager = textView.layoutManager
      {
        usedHeight = layoutManager.usedRect(for: container).height
      } else {
        usedHeight = visibleHeight
      }
      frame.size.height = max(visibleHeight, usedHeight)
      textView.frame = frame
      textView.textContainer?.containerSize = NSSize(
        width: max(clip.bounds.width - 4, 1),
        height: CGFloat.greatestFiniteMagnitude
      )
    }
  }
}

final class FormulaBarNSTextView: NSTextView {
  private var isReplacingString = false
  private var isApplyingSpellPolicy = false
  private var isClaimingFocus = false
  private var spellCheckSyncPending = false

  override var acceptsFirstResponder: Bool { true }

  /// Replacing the string puts continuous checking and automatic correction back
  /// to the text view defaults. Prose has to win after that replacement returns.
  override var string: String {
    get { super.string }
    set {
      if isReplacingString || isApplyingSpellPolicy {
        super.string = newValue
        return
      }
      isReplacingString = true
      isAutomaticSpellingCorrectionEnabled = false
      isGrammarCheckingEnabled = false
      super.string = newValue
      restoreAssignedString(newValue)
      applySpellPolicy()
      isReplacingString = false
    }
  }

  /// Automatic correction can rewrite a misspelling while the string is replaced.
  /// Put the assigned characters back so prose such as `recieve` can be underlined.
  private func restoreAssignedString(_ newValue: String) {
    guard super.string != newValue, let storage = textStorage else { return }
    isApplyingSpellPolicy = true
    let length = (storage.string as NSString).length
    storage.beginEditing()
    storage.replaceCharacters(in: NSRange(location: 0, length: length), with: newValue)
    storage.endEditing()
    isApplyingSpellPolicy = false
  }

  override func didChangeText() {
    // Applying the policy can notify a text change. Ignore that re-entry so
    // AppKit does not put the defaults back on top of the policy.
    if isApplyingSpellPolicy {
      return
    }
    if isReplacingString {
      super.didChangeText()
      return
    }
    isReplacingString = true
    isAutomaticSpellingCorrectionEnabled = false
    isGrammarCheckingEnabled = false
    super.didChangeText()
    isReplacingString = false
    applySpellPolicy()
    scheduleSpellCheckSync()
  }

  private func applySpellPolicy() {
    guard !isApplyingSpellPolicy else { return }
    // Spell checking marks the focused editor. Take focus only when nobody else has it,
    // so mirroring text into the bar does not steal the grid.
    if !isClaimingFocus, let window, window.firstResponder == nil {
      isClaimingFocus = true
      window.makeFirstResponder(self)
      isClaimingFocus = false
    }
    isApplyingSpellPolicy = true
    EditorSpellCheck.apply(
      to: self,
      text: string,
      refresh: EditorSpellCheck.shouldCheck(string)
    )
    isApplyingSpellPolicy = false
  }

  override func checkText(
    in range: NSRange,
    types checkingTypes: NSTextCheckingTypes,
    options: [NSSpellChecker.OptionKey: Any] = [:]
  ) {
    // A formula is not checked. Prose still gets a spelling underline if `super`
    // returns before the system mark is on the layout manager.
    guard EditorSpellCheck.shouldCheck(string) else { return }
    super.checkText(in: range, types: checkingTypes, options: options)
    guard !isApplyingSpellPolicy else { return }
    isApplyingSpellPolicy = true
    EditorSpellCheck.markSystemSpelling(
      on: self,
      language: EditorSpellCheck.spellingLanguage(in: options)
    )
    isApplyingSpellPolicy = false
  }

  /// A keystroke can restore the defaults after `didChangeText` returns.
  /// Apply the same policy once more on the next turn.
  private func scheduleSpellCheckSync() {
    guard !spellCheckSyncPending else { return }
    spellCheckSyncPending = true
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.spellCheckSyncPending = false
      self.applySpellPolicy()
    }
  }

  override func becomeFirstResponder() -> Bool {
    let ok = super.becomeFirstResponder()
    if ok {
      isRichText = true
      applySpellPolicy()
    }
    return ok
  }

  override func paste(_ sender: Any?) {
    pasteAsPlainText(sender)
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if AppSettings.shared.matches(.save, event: event) {
      return SparkGridSaveShortcut.perform()
    }
    return super.performKeyEquivalent(with: event)
  }

  override func keyDown(with event: NSEvent) {
    if AppSettings.shared.matches(.save, event: event) {
      if SparkGridSaveShortcut.perform() { return }
    }
    super.keyDown(with: event)
  }

  override func insertText(_ insertString: Any, replacementRange: NSRange) {
    if let event = NSApp.currentEvent,
      event.type == .keyDown,
      AppSettings.shared.matches(.save, event: event)
    {
      _ = SparkGridSaveShortcut.perform()
      return
    }
    super.insertText(insertString, replacementRange: replacementRange)
    applySpellPolicy()
  }

  override func insertCompletion(
    _ word: String,
    forPartialWordRange charRange: NSRange,
    movement: Int,
    isFinal flag: Bool
  ) {
    let ns = string as NSString
    let partial: String
    if charRange.location != NSNotFound, charRange.length >= 0, NSMaxRange(charRange) <= ns.length {
      partial = ns.substring(with: charRange)
    } else {
      partial = ""
    }
    let before = string
    super.insertCompletion(word, forPartialWordRange: charRange, movement: movement, isFinal: flag)
    let commitOnReturn =
      flag
      && movement == NSTextMovement.`return`.rawValue
      && (before == string
        || FormulaAutocomplete.isExactCompletion(partial: partial, completion: word))
    guard commitOnReturn else { return }
    let editor = self
    DispatchQueue.main.async {
      guard editor.window?.firstResponder === editor else { return }
      editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
    }
  }
}

enum SparkGridSaveShortcut {
  @MainActor
  @discardableResult
  static func perform() -> Bool {
    let delegate = (NSApp.delegate as? SparkGridAppDelegate) ?? SparkGridAppDelegate.current
    guard let store = delegate?.documentStore else { return false }
    _ = store.saveInteractively()
    return true
  }
}
