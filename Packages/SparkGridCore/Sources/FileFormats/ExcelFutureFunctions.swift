import Formula
import Foundation

/// Excel stores functions added after 2007 with an `_xlfn.` prefix, as in `_xlfn.XLOOKUP(...)`.
/// Saved without it, Excel shows #NAME? until the cell is typed again.
public nonisolated enum ExcelFutureFunctions {
  static let names: Set<String> = [
    "XLOOKUP", "XMATCH", "IFS", "MAXIFS", "MINIFS", "SWITCH", "CONCAT", "TEXTJOIN", "SEQUENCE",
    "IFNA", "XOR", "DAYS", "ISOWEEKNUM", "CEILING.MATH", "FLOOR.MATH", "RANK.EQ",
    "STDEV.S", "STDEV.P", "VAR.S", "VAR.P", "PERCENTILE.INC", "QUARTILE.INC", "MODE.SNGL",
    "FORECAST.LINEAR", "TEXTBEFORE", "TEXTAFTER", "UNICHAR", "UNICODE", "SORTBY", "UNIQUE",
    "LET", "TEXTSPLIT", "VSTACK", "HSTACK", "TAKE", "DROP", "CHOOSECOLS", "CHOOSEROWS",
    "WRAPROWS", "WRAPCOLS", "TOCOL", "TOROW", "RANDARRAY",
    "REGEXTEST", "REGEXEXTRACT", "REGEXREPLACE",
    "COVARIANCE.P", "COVARIANCE.S", "NORM.DIST", "NORM.INV", "NORM.S.DIST", "NORM.S.INV",
    "NUMBERVALUE", "PERCENTRANK.EXC", "PERCENTRANK.INC", "RANK.AVG", "SKEW.P",
    // 1.7 batch 4
    "AGGREGATE", "NETWORKDAYS.INTL", "WORKDAY.INTL", "SHEET", "SHEETS", "FORMULATEXT", "COT",
    "CSC", "SEC", "COTH", "CSCH", "SECH", "ACOT", "ACOTH", "CEILING.PRECISE", "FLOOR.PRECISE",
    "COMBINA", "PERMUTATIONA", "GAMMA", "GAMMALN.PRECISE", "GAUSS", "PHI", "ARABIC", "BASE",
    "DECIMAL", "BITAND", "BITOR", "BITXOR", "BITLSHIFT", "BITRSHIFT", "ERF.PRECISE",
    "ERFC.PRECISE", "VALUETOTEXT", "ARRAYTOTEXT", "ENCODEURL",
    // 1.7 batch 5
    "BETA.DIST", "BETA.INV", "BINOM.DIST", "BINOM.DIST.RANGE", "BINOM.INV", "CHISQ.DIST",
    "CHISQ.DIST.RT", "CHISQ.INV", "CHISQ.INV.RT", "CHISQ.TEST", "CONFIDENCE.NORM", "CONFIDENCE.T",
    "EXPON.DIST", "F.DIST", "F.DIST.RT", "F.INV", "F.INV.RT", "F.TEST", "GAMMA.DIST", "GAMMA.INV",
    "HYPGEOM.DIST", "LOGNORM.DIST", "LOGNORM.INV", "MODE.MULT", "NEGBINOM.DIST", "POISSON.DIST",
    "T.DIST", "T.DIST.2T", "T.DIST.RT", "T.INV", "T.INV.2T", "T.TEST", "WEIBULL.DIST", "Z.TEST",
    "MUNIT",
    // 1.7 batch 6
    "LAMBDA", "MAP", "REDUCE", "SCAN", "BYROW", "BYCOL", "MAKEARRAY", "ISOMITTED", "EXPAND",
    "GROUPBY", "PIVOTBY",
    // 1.7 batch 7
    "IMCOSH", "IMCOT", "IMCSC", "IMCSCH", "IMSEC", "IMSECH", "IMSINH", "IMTAN", "PDURATION", "RRI",
  ]
  /// Functions that take a LAMBDA, or a built-in function by name.
  static let lambdaTakers: Set<String> = [
    "MAP", "REDUCE", "SCAN", "BYROW", "BYCOL", "MAKEARRAY", "GROUPBY", "PIVOTBY",
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

  /// The formula text as typed, from the text a file stores: `_xlfn.XLOOKUP(` becomes
  /// `XLOOKUP(`, `_xlfn._xlws.FILTER(` becomes `FILTER(`, and `_xlfn.ANCHORARRAY(G1)` becomes
  /// `G1#`, and `_xlpm.total` (a LET name) becomes `total`. Only names `prefixed` and
  /// `anchorArrays` add back are changed, so saving writes the file's text again; other prefixed names (functions Spark Grid does not have) keep theirs.
  /// Text in double quotes and quoted sheet names are left alone. Works with or without `=`.
  public static func unprefixed(_ formula: String) -> String {
    let utf8 = formula.utf8
    // Most formulas have no prefix; find that without copying.
    var hasPrefix = false
    var previous: UInt8 = 0
    for byte in utf8 {
      if previous == UInt8(ascii: "_"), byte | 0x20 == UInt8(ascii: "x") {
        hasPrefix = true
        break
      }
      previous = byte
    }
    guard hasPrefix else { return formula }

    let bytes = Array(utf8)
    var out: [UInt8] = []
    out.reserveCapacity(bytes.count)
    var changed = false
    var i = 0
    func isNameByte(_ b: UInt8) -> Bool {
      (b >= 0x30 && b <= 0x39) || (b | 0x20 >= 0x61 && b | 0x20 <= 0x7A) || b == 0x2E || b == 0x5F
        || b >= 0x80
    }
    /// The length of `prefix` (lowercase ASCII) at `start`, matched without case, or 0.
    func prefixLength(_ prefix: String, at start: Int, end: Int) -> Int {
      var k = start
      for p in prefix.utf8 {
        guard k < end, bytes[k] | 0x20 == p | 0x20 else { return 0 }
        k += 1
      }
      return k - start
    }
    while i < bytes.count {
      let b = bytes[i]
      if b == UInt8(ascii: "\"") || b == UInt8(ascii: "'") {
        // Copy the quoted run; a doubled quote stays inside it.
        out.append(b)
        i += 1
        while i < bytes.count {
          out.append(bytes[i])
          if bytes[i] == b {
            if i + 1 < bytes.count, bytes[i + 1] == b {
              out.append(bytes[i + 1])
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
      guard isNameByte(b) else {
        out.append(b)
        i += 1
        continue
      }
      var j = i
      while j < bytes.count, isNameByte(bytes[j]) { j += 1 }
      // `_xlpm.total`, a LET name as files store it, reads as `total`; saving adds it back.
      let pm = prefixLength("_xlpm.", at: i, end: j)
      if pm > 0, j > i + pm {
        out.append(contentsOf: bytes[(i + pm)..<j])
        changed = true
        i = j
        continue
      }
      let fn = prefixLength("_xlfn.", at: i, end: j)
      // `_xlfn._xleta.SUM`, a function given by name to BYROW and the like, reads as `SUM`.
      let eta = fn > 0 ? prefixLength("_xleta.", at: i + fn, end: j) : 0
      if eta > 0, j > i + fn + eta, j >= bytes.count || bytes[j] != UInt8(ascii: "(") {
        out.append(contentsOf: bytes[(i + fn + eta)..<j])
        changed = true
        i = j
        continue
      }
      if fn > 0, j < bytes.count, bytes[j] == UInt8(ascii: "(") {
        let ws = prefixLength("_xlws.", at: i + fn, end: j)
        let bare = String(decoding: bytes[(i + fn + ws)..<j], as: UTF8.self)
        let upper = bare.uppercased()
        if names.contains(upper) || worksheetNames.contains(upper) {
          out.append(contentsOf: bare.utf8)
          changed = true
          i = j
          continue
        }
        if ws == 0, upper == "ANCHORARRAY", let (reference, close) = anchorArgument(bytes, open: j)
        {
          out.append(contentsOf: reference.utf8)
          out.append(UInt8(ascii: "#"))
          changed = true
          i = close + 1
          continue
        }
      }
      out.append(contentsOf: bytes[i..<j])
      i = j
    }
    return changed ? String(decoding: out, as: UTF8.self) : formula
  }

  /// The reference inside `ANCHORARRAY(` at `open` and the index of its `)`, when it is one
  /// reference that `anchorArrays` writes back the same way from `reference#`.
  private static func anchorArgument(_ bytes: [UInt8], open: Int) -> (String, Int)? {
    var k = open + 1
    while k < bytes.count {
      let b = bytes[k]
      if b == UInt8(ascii: "'") {
        k += 1
        while k < bytes.count {
          if bytes[k] == UInt8(ascii: "'") {
            if k + 1 < bytes.count, bytes[k + 1] == UInt8(ascii: "'") {
              k += 2
              continue
            }
            break
          }
          k += 1
        }
        k += 1
        continue
      }
      if b == UInt8(ascii: ")") { break }
      if b == UInt8(ascii: "(") || b == UInt8(ascii: "\"") || b == UInt8(ascii: ",")
        || b == UInt8(ascii: " ") || b == UInt8(ascii: ":")
      {
        return nil
      }
      k += 1
    }
    guard k < bytes.count, k > open + 1 else { return nil }
    let reference = String(decoding: bytes[(open + 1)..<k], as: UTF8.self)
    guard anchorArrays(reference + "#") == "_xlfn.ANCHORARRAY(" + reference + ")" else {
      return nil
    }
    return (reference, k)
  }

  /// The formula text (without `=`) with `_xlfn.` before each newer function call, and
  /// `_xlpm.` before each name a LET gives and its uses inside that LET, as files store them.
  /// Text in quotes and quoted sheet names are left alone, as are names that already carry a
  /// prefix.
  public static func prefixed(_ formula: String) -> String {
    guard formula.contains("(") else { return formula }
    // Spark Grid's own functions go out as the formulas other apps calculate.
    let formula = SparkOnlyFunctions.excelForm(formula)
    let chars = Array(formula)
    var out = ""
    out.reserveCapacity(chars.count + 16)
    var i = 0
    func isNameChar(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "." || c == "_" }
    /// Each open parenthesis: whether it is a LET, which argument is being read, and the names
    /// it has given so far.
    /// `takesLambda`: BYROW, MAP and the others, where a bare function name is a function.
    var frames:
      [(isLet: Bool, isLambda: Bool, takesLambda: Bool, argument: Int, names: Set<String>)] =
        []
    func letNameInScope(_ upper: String) -> Bool {
      frames.contains { ($0.isLet || $0.isLambda) && $0.names.contains(upper) }
    }
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
        let upper = token.uppercased()
        if j < chars.count, chars[j] == "(" {
          if names.contains(upper) {
            out += "_xlfn."
          } else if worksheetNames.contains(upper) {
            out += "_xlfn._xlws."
          }
          out += token
          let plain = upper.hasPrefix("_XLFN.") ? String(upper.dropFirst(6)) : upper
          frames.append(
            (
              isLet: plain == "LET", isLambda: plain == "LAMBDA",
              takesLambda: lambdaTakers.contains(plain), argument: 0, names: []
            ))
          out.append("(")
          i = j + 1
          continue
        }
        let startsName = c.isLetter || c == "_"
        let afterSheet = i > 0 && (chars[i - 1] == "!" || chars[i - 1] == "$")
        if startsName, !afterSheet, !upper.hasPrefix("_XLPM."), !isCellReference(token) {
          var k = j
          while k < chars.count, chars[k] == " " { k += 1 }
          // A LET names a value in each even argument followed by another argument; a LAMBDA
          // names a parameter in each argument but the last.
          if var frame = frames.last,
            (frame.isLet && frame.argument % 2 == 0) || frame.isLambda,
            k < chars.count, chars[k] == ","
          {
            frame.names.insert(upper)
            frames[frames.count - 1] = frame
            out += "_xlpm."
          } else if letNameInScope(upper) {
            out += "_xlpm."
          } else if let frame = frames.last, frame.takesLambda,
            FormulaFunctions.all.contains(upper), !upper.hasPrefix("_XLFN.")
          {
            out += "_xlfn._xleta."
          }
        }
        out += token
        i = j
        continue
      }
      switch c {
      case "(":
        frames.append((isLet: false, isLambda: false, takesLambda: false, argument: 0, names: []))
      case ")": if !frames.isEmpty { frames.removeLast() }
      case ",": if !frames.isEmpty { frames[frames.count - 1].argument += 1 }
      default: break
      }
      out.append(c)
      i += 1
    }
    return out
  }

  /// A1, $B$2, AB10: a cell, not a name.
  private static func isCellReference(_ token: String) -> Bool {
    let plain = token.replacingOccurrences(of: "$", with: "")
    let letters = plain.prefix { $0.isLetter }
    let digits = plain.dropFirst(letters.count)
    return (1...3).contains(letters.count) && !digits.isEmpty && digits.allSatisfy(\.isNumber)
  }
}
