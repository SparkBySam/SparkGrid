import Foundation

/// Sheet names in front of cell references (`Report!B2`, `'Q1 Sales'!B2:B9`).
public enum SheetPrefixes {
  /// `text` with the sheet name taken off every reference except those to `otherSheets`: the
  /// sheet the formula is on needs none, and a sheet the workbook doesn't have is a guess. Formula
  /// Help's model wrote `=SUMIF(Sheet1!B2:B5,1200)` and "the values in Sheet1!B2:B5" for a sheet
  /// named Report (Sam, Nov 20). Text in double quotes, as in a formula's strings, is left alone.
  public static func keepingOnly(_ otherSheets: [String], in text: String) -> String {
    let others = Set(otherSheets.map { $0.lowercased() })
    var result = ""
    var index = text.startIndex
    var inString = false
    while index < text.endIndex {
      let char = text[index]
      if char == "\"" {
        inString.toggle()
        result.append(char)
        index = text.index(after: index)
        continue
      }
      if !inString, let (name, end) = prefix(at: index, in: text),
        startsReference(at: end, in: text)
      {
        // A name glued to what came before (`XSheet1!`) is not a prefix starting here.
        let previous = result.last
        let standsAlone =
          previous.map { !($0.isLetter || $0.isNumber || $0 == "_" || $0 == ".") }
          ?? true
        if standsAlone {
          if others.contains(name.lowercased()) {
            result += text[index..<end]
          }
          index = end
          continue
        }
      }
      result.append(char)
      index = text.index(after: index)
    }
    return result
  }

  /// A sheet name and `!` starting at `index`: `'Any name'!` or `Name!`. The name and the
  /// index after the `!`.
  private static func prefix(at index: String.Index, in text: String) -> (String, String.Index)? {
    if text[index] == "'" {
      var name = ""
      var i = text.index(after: index)
      while i < text.endIndex {
        if text[i] == "'" {
          let next = text.index(after: i)
          if next < text.endIndex, text[next] == "'" {
            name.append("'")
            i = text.index(after: next)
            continue
          }
          guard next < text.endIndex, text[next] == "!", !name.isEmpty else { return nil }
          return (name, text.index(after: next))
        }
        name.append(text[i])
        i = text.index(after: i)
      }
      return nil
    }
    guard text[index].isLetter || text[index] == "_" else { return nil }
    var i = index
    while i < text.endIndex,
      text[i].isLetter || text[i].isNumber || text[i] == "_" || text[i] == "."
    {
      i = text.index(after: i)
    }
    guard i < text.endIndex, text[i] == "!" else { return nil }
    return (String(text[index..<i]), text.index(after: i))
  }

  /// A cell, column or row reference begins here: `B2`, `$B$2`, `B:B`, `2:2`.
  private static func startsReference(at index: String.Index, in text: String) -> Bool {
    guard index < text.endIndex else { return false }
    let char = text[index]
    return char == "$" || char.isLetter || char.isNumber
  }
}
