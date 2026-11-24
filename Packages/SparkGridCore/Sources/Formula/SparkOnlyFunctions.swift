import Foundation

/// Functions Spark Grid has that other spreadsheet apps do not (asked for on Reddit, Nov 19):
/// SEM, the standard error of the mean, and MEAN, MEAN.ARITH, MEAN.GEOM and MEAN.HARM. A file
/// stores each as the formula other apps calculate the same way, so it works everywhere;
/// Spark Grid keeps what was typed beside the sheet and shows it again on open.
public enum SparkOnlyFunctions {
  /// Each name and the function other apps know it by. SEM has no single equivalent.
  static let renames: [String: String] = [
    "MEAN": "AVERAGE", "MEAN.ARITH": "AVERAGE", "MEAN.GEOM": "GEOMEAN", "MEAN.HARM": "HARMEAN",
  ]
  public static let names: Set<String> = Set(renames.keys).union(["SEM"])

  /// True when `formula` calls one of these functions outside a string.
  public static func uses(_ formula: String) -> Bool {
    var found = false
    _ = rewrite(formula) { _ in
      found = true
      return nil
    }
    return found
  }

  /// `formula` with each of these functions written the way other apps calculate it:
  /// `SEM(B2:B9)` becomes `(STDEV.S(B2:B9)/SQRT(COUNT(B2:B9)))`, `MEAN(` becomes `AVERAGE(`.
  public static func excelForm(_ formula: String) -> String {
    rewrite(formula) { call in
      if call.name == "SEM" {
        let args = excelForm(call.arguments)
        return "(STDEV.S(\(args))/SQRT(COUNT(\(args))))"
      }
      guard let other = renames[call.name] else { return nil }
      return "\(other)(\(excelForm(call.arguments)))"
    }
  }

  struct Call {
    let name: String
    let arguments: String
  }

  /// Walks `formula`, outside strings and quoted sheet names, and replaces each call to one of
  /// these functions with what `replace` returns (nil keeps it).
  private static func rewrite(_ formula: String, replace: (Call) -> String?) -> String {
    let chars = Array(formula)
    var out = ""
    var index = 0
    while index < chars.count {
      let character = chars[index]
      if character == "\"" || character == "'" {
        // A string or quoted sheet name, copied whole (a doubled quote stays inside it).
        var end = index + 1
        while end < chars.count {
          if chars[end] == character {
            if end + 1 < chars.count, chars[end + 1] == character {
              end += 2
              continue
            }
            break
          }
          end += 1
        }
        out += String(chars[index...min(end, chars.count - 1)])
        index = end + 1
        continue
      }
      if character.isLetter, index == 0 || !isNamePart(chars[index - 1]) {
        var end = index
        while end < chars.count, isNamePart(chars[end]) { end += 1 }
        let name = String(chars[index..<end]).uppercased()
        if end < chars.count, chars[end] == "(", names.contains(name),
          let close = matchingClose(chars, open: end)
        {
          let arguments = String(chars[(end + 1)..<close])
          if let replaced = replace(Call(name: name, arguments: arguments)) {
            out += replaced
            index = close + 1
            continue
          }
        }
        out += String(chars[index..<end])
        index = end
        continue
      }
      out.append(character)
      index += 1
    }
    return out
  }

  private static func isNamePart(_ character: Character) -> Bool {
    character.isLetter || character.isNumber || character == "." || character == "_"
  }

  private static func matchingClose(_ chars: [Character], open: Int) -> Int? {
    var depth = 0
    var quote: Character?
    var index = open
    while index < chars.count {
      let character = chars[index]
      if let current = quote {
        if character == current { quote = nil }
      } else if character == "\"" || character == "'" {
        quote = character
      } else if character == "(" {
        depth += 1
      } else if character == ")" {
        depth -= 1
        if depth == 0 { return index }
      }
      index += 1
    }
    return nil
  }
}
