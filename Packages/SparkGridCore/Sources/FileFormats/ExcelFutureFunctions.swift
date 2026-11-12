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
