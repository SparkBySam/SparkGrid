import AppKit
import SparkGridCore

/// System spell checking for text being typed in the cell editor and formula bar.
/// `NSTextView` draws the Mac underline and the standard suggestions / Ignore / Learn menu.
/// No word list ships with the app.
enum EditorSpellCheck {
  private static var isMarkingSpelling = false

  /// Prose is checked. A formula that starts with `=` and a numeric literal are not.
  /// Callers pass the edit string, never a calculated formula result.
  static func shouldCheck(_ text: String) -> Bool {
    if FormulaSyntax.isFormula(text) { return false }
    if case .number = CellValue.fromLiteralRaw(text) { return false }
    return true
  }

  /// Turns continuous spell checking on or off for `text`.
  /// Automatic correction stays off so a suggestion never rewrites the cell by itself.
  /// `refresh` asks the system checker to mark the current text again after attributes were replaced.
  static func apply(to textView: NSTextView, text: String, refresh: Bool = false) {
    let enabled = shouldCheck(text)
    if textView.isAutomaticSpellingCorrectionEnabled {
      textView.isAutomaticSpellingCorrectionEnabled = false
    }
    if textView.isGrammarCheckingEnabled {
      textView.isGrammarCheckingEnabled = false
    }
    if textView.isContinuousSpellCheckingEnabled != enabled {
      textView.isContinuousSpellCheckingEnabled = enabled
    }
    guard enabled else {
      clearMarks(on: textView)
      return
    }
    if refresh {
      markSystemSpelling(on: textView)
    }
  }

  /// Records the system spelling underline for misspelled prose.
  /// `NSTextView.checkText` can return without leaving that underline on the formula bar.
  /// The mark is the layout manager's spelling state, which is what the text view draws.
  /// `language` limits this call; it does not change the user's spell-checker language.
  static func markSystemSpelling(on textView: NSTextView, language: String? = nil) {
    guard !isMarkingSpelling else { return }
    guard shouldCheck(textView.string), let layout = textView.layoutManager else { return }
    let text = textView.string as NSString
    let length = text.length
    guard length > 0 else { return }
    isMarkingSpelling = true
    defer { isMarkingSpelling = false }

    if let container = textView.textContainer {
      layout.ensureLayout(for: container)
    }
    let full = NSRange(location: 0, length: length)
    layout.removeTemporaryAttribute(.spellingState, forCharacterRange: full)

    let spellLanguage = language ?? NSSpellChecker.shared.language()
    let tag = textView.spellCheckerDocumentTag
    let mark = NSNumber(value: NSAttributedString.SpellingState.spelling.rawValue)
    var location = 0
    while location < length {
      let miss = NSSpellChecker.shared.checkSpelling(
        of: textView.string,
        startingAt: location,
        language: spellLanguage,
        wrap: false,
        inSpellDocumentWithTag: tag,
        wordCount: nil
      )
      if miss.location == NSNotFound || miss.length <= 0 || miss.location >= length {
        break
      }
      let clamped = min(miss.length, length - miss.location)
      guard clamped > 0 else { break }
      let range = NSRange(location: miss.location, length: clamped)
      layout.addTemporaryAttribute(.spellingState, value: mark, forCharacterRange: range)
      let next = range.location + range.length
      if next <= location { break }
      location = next
    }
  }

  static func spellingLanguage(in options: [NSSpellChecker.OptionKey: Any]) -> String? {
    for value in options.values {
      guard let orthography = value as? NSOrthography else { continue }
      let language = orthography.dominantLanguage
      if !language.isEmpty {
        return language
      }
    }
    return nil
  }

  private static func clearMarks(on textView: NSTextView) {
    guard let layout = textView.layoutManager else { return }
    let length = (textView.string as NSString).length
    guard length > 0 else { return }
    layout.removeTemporaryAttribute(
      .spellingState,
      forCharacterRange: NSRange(location: 0, length: length)
    )
  }
}
