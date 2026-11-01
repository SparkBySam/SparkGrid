import Foundation
import GridCore

/// Shared formula-token autocomplete for the in-cell editor and formula bar.
public enum FormulaAutocomplete {
  public struct Result {
    public var text: String
    public var cursor: Int
  }

  /// Auto-popup only after this many letters — avoids `A` → `ABS` while typing ranges.
  public static let minimumAutoPopupLength = 2

  public static func suggestions(matching partial: String, namedRanges: [String]) -> [String] {
    guard !partial.isEmpty, partial.first?.isLetter == true else { return [] }
    // Digits in the token mean it's an A1-style ref fragment (A1, B12), not a function.
    if partial.contains(where: \.isNumber) { return [] }

    let upper = partial.uppercased()
    // An exact function (`SUM`) is finished. Offering SUMIF here would swallow Return.
    if FormulaFunctions.all.contains(upper) {
      return [upper]
    }

    var items = FormulaFunctions.suggestions(matching: partial)
    let names =
      namedRanges
      .filter { $0.uppercased().hasPrefix(upper) }
      .sorted()
    for name in names where !items.contains(name) {
      items.append(name)
    }
    return items
  }

  /// Whether the completions popup / `complete(_:)` should run for this caret position.
  public static func shouldOfferPopup(
    in text: String,
    utf16Cursor: Int,
    namedRanges: [String]
  ) -> Bool {
    guard text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("=") else { return false }
    guard let partial = partialWord(in: text, utf16Cursor: utf16Cursor) else { return false }
    guard partial.token.count >= minimumAutoPopupLength else { return false }
    guard !isReferenceContext(in: text, tokenRange: partial.nsRange) else { return false }
    let matches = suggestions(matching: partial.token, namedRanges: namedRanges)
    guard !matches.isEmpty else { return false }
    // An exact token (`=SUM`) is finished. Another popup would swallow Return
    // and accept SUM again instead of committing the cell.
    if isExactCompletion(partial: partial.token, matches: matches) {
      return false
    }
    return true
  }

  /// The caret token is already one of the suggestions (`SUM` == `SUM`).
  public static func isExactCompletion(partial: String, completion: String) -> Bool {
    guard !partial.isEmpty else { return false }
    return completion.caseInsensitiveCompare(partial) == .orderedSame
  }

  public static func isExactCompletion(partial: String, matches: [String]) -> Bool {
    matches.contains { isExactCompletion(partial: partial, completion: $0) }
  }

  /// Best single suggestion for Tab-to-complete, if any.
  public static func bestSuggestion(matching partial: String, namedRanges: [String]) -> String? {
    let items = suggestions(matching: partial, namedRanges: namedRanges)
    guard let first = items.first else { return nil }
    if items.count == 1 { return first }
    if let exact = items.first(where: { $0.caseInsensitiveCompare(partial) == .orderedSame }) {
      return exact
    }
    return first
  }

  public static func partialWord(in text: String, utf16Cursor: Int) -> (
    nsRange: NSRange, token: String
  )? {
    let ns = text as NSString
    let cursor = max(0, min(utf16Cursor, ns.length))
    guard cursor > 0 else { return nil }

    var start = cursor
    while start > 0 {
      let idx = start - 1
      let ch = ns.character(at: idx)
      guard let scalar = UnicodeScalar(ch) else { break }
      if CharacterSet.alphanumerics.contains(scalar) || scalar == "_" {
        start = idx
      } else {
        break
      }
    }
    guard cursor > start else { return nil }
    let range = NSRange(location: start, length: cursor - start)
    let token = ns.substring(with: range)
    guard token.first?.isLetter == true else { return nil }
    return (range, token)
  }

  /// True when the token sits in an A1 / range / sheet-ref position (e.g. `A2:A`, `$A`, `Sheet1!B`).
  public static func isReferenceContext(in text: String, tokenRange: NSRange) -> Bool {
    let ns = text as NSString
    guard tokenRange.location > 0 else { return false }

    // Skip spaces between the operator and the token.
    var i = tokenRange.location
    while i > 0 {
      let ch = ns.character(at: i - 1)
      if ch == 32 || ch == 9 {  // space / tab
        i -= 1
        continue
      }
      break
    }
    guard i > 0 else { return false }

    let prev = ns.character(at: i - 1)
    // After ':' → range endpoint (`A2:A`). After '!' → sheet-qualified ref.
    // After '$' → absolute column/row marker mid-ref.
    // 58 is ':', 33 is '!', 36 is '$'.
    if prev == 58 || prev == 33 || prev == 36 {
      return true
    }
    return false
  }

  /// Replaces the partial token with `suggestion`. Function names get a trailing `(`.
  public static func apply(
    suggestion: String,
    to text: String,
    utf16Cursor: Int,
    namedRanges: [String]
  ) -> Result? {
    guard let partial = partialWord(in: text, utf16Cursor: utf16Cursor) else { return nil }
    guard !isReferenceContext(in: text, tokenRange: partial.nsRange) else { return nil }
    let ns = text as NSString
    let isNamedRange = namedRanges.contains {
      $0.caseInsensitiveCompare(suggestion) == .orderedSame
    }
    let isKnownFunction = FormulaFunctions.all.contains(suggestion.uppercased())
    var insertion = suggestion
    if isKnownFunction && !isNamedRange {
      insertion += "("
    }
    let updated = ns.replacingCharacters(in: partial.nsRange, with: insertion)
    let newCursor = partial.nsRange.location + (insertion as NSString).length
    return Result(text: updated, cursor: newCursor)
  }

  public static func tabComplete(
    text: String,
    utf16Cursor: Int,
    namedRanges: [String]
  ) -> Result? {
    guard text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("=") else { return nil }
    guard let partial = partialWord(in: text, utf16Cursor: utf16Cursor) else { return nil }
    guard !isReferenceContext(in: text, tokenRange: partial.nsRange) else { return nil }
    // Require 2+ chars for Tab as well so a lone `A` never becomes `ABS`.
    guard partial.token.count >= minimumAutoPopupLength else { return nil }
    guard let suggestion = bestSuggestion(matching: partial.token, namedRanges: namedRanges) else {
      return nil
    }
    // Already complete function name without '(': still add '(' on Tab.
    if suggestion.caseInsensitiveCompare(partial.token) == .orderedSame,
      FormulaFunctions.all.contains(suggestion.uppercased()),
      !namedRanges.contains(where: { $0.caseInsensitiveCompare(suggestion) == .orderedSame })
    {
      let ns = text as NSString
      let after = partial.nsRange.location + partial.nsRange.length
      if after < ns.length {
        let next = ns.character(at: after)
        if next == 40 {  // "("
          return nil
        }
      }
      let insertion = suggestion + "("
      let updated = ns.replacingCharacters(in: partial.nsRange, with: insertion)
      return Result(
        text: updated, cursor: partial.nsRange.location + (insertion as NSString).length)
    }
    if suggestion.caseInsensitiveCompare(partial.token) == .orderedSame {
      return nil
    }
    return apply(
      suggestion: suggestion,
      to: text,
      utf16Cursor: utf16Cursor,
      namedRanges: namedRanges
    )
  }
}
