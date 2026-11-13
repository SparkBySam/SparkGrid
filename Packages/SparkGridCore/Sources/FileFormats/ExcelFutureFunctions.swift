import Foundation

/// Excel stores functions added after 2007 with an `_xlfn.` prefix, as in `_xlfn.XLOOKUP(...)`.
/// Saved without it, Excel shows #NAME? until the cell is typed again.
public nonisolated enum ExcelFutureFunctions {
  static let names: Set<String> = [
    "XLOOKUP", "XMATCH", "IFS", "MAXIFS", "MINIFS", "SWITCH", "CONCAT", "TEXTJOIN", "SEQUENCE",
    "IFNA", "XOR", "DAYS", "ISOWEEKNUM", "CEILING.MATH", "FLOOR.MATH", "RANK.EQ",
    "STDEV.S", "STDEV.P", "VAR.S", "VAR.P", "PERCENTILE.INC", "QUARTILE.INC", "MODE.SNGL",
    "FORECAST.LINEAR", "TEXTBEFORE", "TEXTAFTER", "UNICHAR", "UNICODE", "SORTBY", "UNIQUE",
  ]
  /// Saved as `_xlfn._xlws.FILTER` rather than `_xlfn.FILTER`.
  static let worksheetNames: Set<String> = ["FILTER", "SORT"]

  /// The formula text with each spill reference such as `G1#` or `Data!G1#` written the way
  /// files store it, `_xlfn.ANCHORARRAY(G1)`. A `#` in a saved formula makes Excel report the
  /// file as damaged and drop the formula. Text in double quotes is left alone.
  public static func anchorArrays(_ formula: String) -> String {
    guard formula.contains("#") else { return formula }
    var out: [Character] = []
    out.reserveCapacity(formula.count + 16)
    var inText = false
    func isSheetNameChar(_ c: Character) -> Bool {
      c.isLetter || c.isNumber || c == "_" || c == "."
    }
    for c in formula {
      if c == "\"" { inText.toggle() }
      guard c == "#", !inText, let last = out.last, last.isNumber else {
        out.append(c)
        continue
      }
      // Walk back over the cell address, then any sheet name before `!`.
      var start = out.count
      while start > 0, out[start - 1].isLetter || out[start - 1].isNumber || out[start - 1] == "$" {
        start -= 1
      }
      guard start < out.count, out[start].isLetter || out[start] == "$" else {
        out.append(c)
        continue
      }
      if start > 0, out[start - 1] == "!" {
        var s = start - 1
        if s > 0, out[s - 1] == "'" {
          s -= 1
          while s > 0 {
            s -= 1
            if out[s] == "'" {
              if s > 0, out[s - 1] == "'" {
                s -= 1
                continue
              }
              break
            }
          }
        } else {
          while s > 0, isSheetNameChar(out[s - 1]) { s -= 1 }
        }
        start = s
      }
      if start > 0, out[start - 1].isLetter || out[start - 1] == "_" || out[start - 1] == "." {
        out.append(c)
        continue
      }
      let reference = out[start...]
      out.replaceSubrange(start..., with: Array("_xlfn.ANCHORARRAY(") + reference + [")"])
    }
    return String(out)
  }

  /// The formula text (without `=`) with `_xlfn.` before each newer function call. Text in
  /// quotes and quoted sheet names are left alone, as are names that already carry a prefix.
  public static func prefixed(_ formula: String) -> String {
    guard formula.contains("(") else { return formula }
    let chars = Array(formula)
    var out = ""
    out.reserveCapacity(chars.count + 16)
    var i = 0
    func isNameChar(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "." || c == "_" }
    while i < chars.count {
      let c = chars[i]
      if c == "\"" || c == "'" {
        // Copy the quoted run; a doubled quote stays inside it.
        out.append(c)
        i += 1
        while i < chars.count {
          out.append(chars[i])
          if chars[i] == c {
            if i + 1 < chars.count, chars[i + 1] == c {
              out.append(chars[i + 1])
              i += 2
              continue
            }
            i += 1
            break
          }
          i += 1
        }
        continue
      }
      if isNameChar(c) {
        var j = i
        while j < chars.count, isNameChar(chars[j]) { j += 1 }
        let token = String(chars[i..<j])
        if j < chars.count, chars[j] == "(" {
          let upper = token.uppercased()
          if names.contains(upper) {
            out += "_xlfn."
          } else if worksheetNames.contains(upper) {
            out += "_xlfn._xlws."
          }
        }
        out += token
        i = j
        continue
      }
      out.append(c)
      i += 1
    }
    return out
  }
}
