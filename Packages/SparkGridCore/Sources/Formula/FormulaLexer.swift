import Foundation
import GridCore

public nonisolated enum FormulaToken: Equatable {
  case number(Double)
  case string(String)
  case boolean(Bool)
  case error(FormulaError)
  case identifier(String)
  case cellRef(String)
  case range(String)
  case plus
  case minus
  case star
  case slash
  case caret
  case amp
  case eq
  case ne
  case lt
  case gt
  case le
  case ge
  case lParen
  case rParen
  case comma
  case colon
  case eof
}

public nonisolated struct FormulaLexer {
  private let chars: [Character]
  private var index = 0

  public init(_ source: String) {
    var text = source.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.hasPrefix("=") {
      text = String(text.dropFirst())
    }
    self.chars = Array(text)
  }

  public mutating func next() throws -> FormulaToken {
    skipWhitespace()
    guard index < chars.count else { return .eof }

    let ch = chars[index]

    if ch == "\"" {
      return try readString()
    }
    if ch == "'" {
      return try readQuotedSheetReference()
    }
    if ch == "#" {
      return try readErrorLiteral()
    }
    if ch.isNumber || (ch == "." && peekIsDigit()) {
      return try readNumber()
    }
    if ch.isLetter || ch == "$" || ch == "_" {
      return try readIdentifierOrReference()
    }

    index += 1
    switch ch {
    case "+": return .plus
    case "-": return .minus
    case "*": return .star
    case "/": return .slash
    case "^": return .caret
    case "&": return .amp
    case "(": return .lParen
    case ")": return .rParen
    case ",": return .comma
    case ":": return .colon
    case "=": return .eq
    case "<":
      if match("=") { return .le }
      if match(">") { return .ne }
      return .lt
    case ">":
      if match("=") { return .ge }
      return .gt
    default:
      throw FormulaParseError.unexpectedCharacter(ch)
    }
  }

  private mutating func readString() throws -> FormulaToken {
    index += 1  // opening quote
    var value = ""
    while index < chars.count {
      let ch = chars[index]
      index += 1
      if ch == "\"" {
        if index < chars.count, chars[index] == "\"" {
          value.append("\"")
          index += 1
          continue
        }
        return .string(value)
      }
      value.append(ch)
    }
    throw FormulaParseError.unterminatedString
  }

  private mutating func readQuotedSheetReference() throws -> FormulaToken {
    index += 1  // opening '
    var sheet = ""
    while index < chars.count {
      let ch = chars[index]
      index += 1
      if ch == "'" {
        if index < chars.count, chars[index] == "'" {
          sheet.append("'")
          index += 1
          continue
        }
        break
      }
      sheet.append(ch)
    }
    guard index < chars.count, chars[index] == "!" else {
      throw FormulaParseError.expectedToken("!")
    }
    index += 1
    return try readSheetQualifiedReference(sheetName: sheet)
  }

  private mutating func readErrorLiteral() throws -> FormulaToken {
    let start = index
    while index < chars.count {
      let ch = chars[index]
      if ch.isWhitespace || ch == "," || ch == ")" || ch == "(" || ch == "+" || ch == "-"
        || ch == "*" || ch == "/" || ch == "^" || ch == "&" || ch == "=" || ch == "<" || ch == ">"
        || ch == ":"
      {
        break
      }
      index += 1
      if ch == "!" || ch == "?" { break }
    }
    let text = String(chars[start..<index]).uppercased()
    if let error = FormulaError(displayCode: text) {
      return .error(error)
    }
    throw FormulaParseError.unexpectedCharacter("#")
  }

  private mutating func readNumber() throws -> FormulaToken {
    let start = index
    while index < chars.count, chars[index].isNumber {
      index += 1
    }

    // Row range like `2:2` / `1:10` (no decimal / exponent).
    if index < chars.count, chars[index] == ":",
      !chars[start..<index].contains(where: { $0 == "." || $0 == "e" || $0 == "E" })
    {
      let left = String(chars[start..<index])
      let afterColon = index + 1
      var end = afterColon
      if end < chars.count, chars[end] == "$" { end += 1 }
      while end < chars.count, chars[end].isNumber {
        end += 1
      }
      if end > afterColon {
        let rhs = String(chars[afterColon..<end])
        if A1Reference.isValidRangeEndpointToken(left), A1Reference.isValidRangeEndpointToken(rhs) {
          index = end
          return .range("\(left):\(rhs)")
        }
      }
    }

    if index < chars.count, chars[index] == "." {
      index += 1
      while index < chars.count, chars[index].isNumber {
        index += 1
      }
    }
    if index < chars.count, chars[index] == "e" || chars[index] == "E" {
      index += 1
      if index < chars.count, chars[index] == "+" || chars[index] == "-" {
        index += 1
      }
      while index < chars.count, chars[index].isNumber {
        index += 1
      }
    }
    let text = String(chars[start..<index])
    guard let value = Double(text) else {
      throw FormulaParseError.invalidNumber(text)
    }
    return .number(value)
  }

  private mutating func readIdentifierOrReference() throws -> FormulaToken {
    let start = index
    while index < chars.count {
      let ch = chars[index]
      if ch.isLetter || ch.isNumber || ch == "$" || ch == "_" || ch == "." {
        index += 1
      } else {
        break
      }
    }
    let text = String(chars[start..<index])

    // Sheet-qualified: Sheet1!A1 or Sheet1!A1:B2
    if index < chars.count, chars[index] == "!" {
      index += 1
      return try readSheetQualifiedReference(sheetName: text)
    }

    // Range: A1:B2
    if index < chars.count, chars[index] == ":" {
      let afterColon = index + 1
      var end = afterColon
      while end < chars.count {
        let ch = chars[end]
        if ch.isLetter || ch.isNumber || ch == "$" {
          end += 1
        } else {
          break
        }
      }
      if end > afterColon {
        let rhs = String(chars[afterColon..<end])
        if A1Reference.isValidRangeEndpointToken(text), A1Reference.isValidRangeEndpointToken(rhs) {
          index = end
          return .range("\(text):\(rhs)")
        }
      }
    }

    let upper = text.uppercased()
    if upper == "TRUE" || upper == "FALSE" {
      if nextNonWhitespaceIsOpenParen() {
        return .identifier(upper)
      }
      return .boolean(upper == "TRUE")
    }
    if A1Reference.isValidAddressToken(text) {
      return .cellRef(text)
    }
    return .identifier(upper)
  }

  private mutating func readSheetQualifiedReference(sheetName: String) throws -> FormulaToken {
    skipWhitespace()
    guard index < chars.count else {
      throw FormulaParseError.expectedToken("cell reference")
    }
    let refStart = index
    while index < chars.count {
      let ch = chars[index]
      if ch.isLetter || ch.isNumber || ch == "$" {
        index += 1
      } else {
        break
      }
    }
    let left = String(chars[refStart..<index])
    guard A1Reference.isValidRangeEndpointToken(left) else {
      throw FormulaParseError.expectedToken("cell reference")
    }

    if index < chars.count, chars[index] == ":" {
      let afterColon = index + 1
      var end = afterColon
      while end < chars.count {
        let ch = chars[end]
        if ch.isLetter || ch.isNumber || ch == "$" {
          end += 1
        } else {
          break
        }
      }
      if end > afterColon {
        let rhs = String(chars[afterColon..<end])
        if A1Reference.isValidRangeEndpointToken(rhs) {
          index = end
          return .range("\(sheetName)!\(left):\(rhs)")
        }
      }
    }

    // Bare Sheet1!A (column-only) isn't a cell reference — require a full address.
    guard A1Reference.isValidAddressToken(left) else {
      throw FormulaParseError.expectedToken("cell reference")
    }
    return .cellRef("\(sheetName)!\(left)")
  }

  private func nextNonWhitespaceIsOpenParen() -> Bool {
    var i = index
    while i < chars.count, chars[i].isWhitespace {
      i += 1
    }
    return i < chars.count && chars[i] == "("
  }

  private mutating func skipWhitespace() {
    while index < chars.count, chars[index].isWhitespace {
      index += 1
    }
  }

  private mutating func match(_ expected: Character) -> Bool {
    guard index < chars.count, chars[index] == expected else { return false }
    index += 1
    return true
  }

  private func peekIsDigit() -> Bool {
    let next = index + 1
    return next < chars.count && chars[next].isNumber
  }
}

public nonisolated enum FormulaParseError: Error, Equatable {
  case unexpectedCharacter(Character)
  case unterminatedString
  case invalidNumber(String)
  case unexpectedToken(FormulaToken)
  case expectedToken(String)
}
