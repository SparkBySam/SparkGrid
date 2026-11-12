import Foundation

/// Data ▸ Text to Columns: splits one cell's text into fields.
public nonisolated enum TextSplitter {
  public struct Options: Equatable, Sendable {
    /// Characters that end a field.
    public var delimiters: Set<Character>
    /// Several delimiters in a row count as one, as with runs of spaces.
    public var mergeRepeats: Bool
    /// Text in double quotes stays in one field, delimiters and all; `""` inside is one quote.
    public var quotes: Bool

    /// Fixed width: a field ends after each of these character counts. Delimiters are then
    /// ignored and each field loses its surrounding spaces.
    public var breaks: [Int]

    public init(
      delimiters: Set<Character>, mergeRepeats: Bool = false, quotes: Bool = true,
      breaks: [Int] = []
    ) {
      self.delimiters = delimiters
      self.mergeRepeats = mergeRepeats
      self.quotes = quotes
      self.breaks = breaks
    }

    public static func fixedWidth(_ breaks: [Int]) -> Options {
      Options(delimiters: [], breaks: breaks)
    }

    /// Splitting will do something: some separator, or some break.
    public var splits: Bool { !breaks.isEmpty || !delimiters.isEmpty }
  }

  public static func split(_ text: String, options: Options) -> [String] {
    if !options.breaks.isEmpty { return splitFixed(text, at: options.breaks) }
    guard !options.delimiters.isEmpty, !text.isEmpty else { return [text] }
    var fields: [String] = []
    var current = ""
    var inQuotes = false
    var fieldStarted = false
    var lastWasDelimiter = false
    let chars = Array(text)
    var i = 0
    while i < chars.count {
      let c = chars[i]
      if options.quotes, c == "\"" {
        if inQuotes {
          if i + 1 < chars.count, chars[i + 1] == "\"" {
            current.append("\"")
            i += 2
            continue
          }
          inQuotes = false
        } else if !fieldStarted {
          inQuotes = true
        } else {
          current.append(c)
        }
        fieldStarted = true
        lastWasDelimiter = false
        i += 1
        continue
      }
      if !inQuotes, options.delimiters.contains(c) {
        if !(options.mergeRepeats && lastWasDelimiter) {
          fields.append(current)
          current = ""
        }
        fieldStarted = false
        lastWasDelimiter = true
        i += 1
        continue
      }
      current.append(c)
      fieldStarted = true
      lastWasDelimiter = false
      i += 1
    }
    fields.append(current)
    return fields
  }

  /// Cuts after each break position, counted in characters from the start of the text.
  static func splitFixed(_ text: String, at breaks: [Int]) -> [String] {
    let chars = Array(text)
    var cuts = Array(Set(breaks.filter { $0 > 0 })).sorted()
    cuts = cuts.filter { $0 < chars.count }
    var fields: [String] = []
    var start = 0
    for cut in cuts + [chars.count] {
      let end = max(start, min(cut, chars.count))
      fields.append(String(chars[start..<end]).trimmingCharacters(in: .whitespaces))
      start = end
    }
    // A line shorter than the last break still has a field for every break.
    while fields.count < Set(breaks.filter { $0 > 0 }).count + 1 { fields.append("") }
    return fields
  }

  /// Break positions for lined-up text: where every line has a space and at least one line
  /// starts a new word right after it.
  public static func suggestedBreaks(_ lines: [String]) -> [Int] {
    let rows = lines.map(Array.init).filter { !$0.isEmpty }
    guard rows.count >= 1, let longest = rows.map(\.count).max(), longest > 1 else { return [] }
    func isBlank(_ row: [Character], _ i: Int) -> Bool { i >= row.count || row[i] == " " }
    var breaks: [Int] = []
    for i in 1..<longest {
      let blankBefore = rows.allSatisfy { isBlank($0, i - 1) }
      let wordStarts = rows.contains { i < $0.count && $0[i] != " " }
      if blankBefore, wordStarts { breaks.append(i) }
    }
    return breaks
  }
}
