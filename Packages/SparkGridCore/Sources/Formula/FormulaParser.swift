import Foundation
import GridCore

public nonisolated struct FormulaParser {
  private var lexer: FormulaLexer
  private var current: FormulaToken = .eof

  public init(_ source: String) throws {
    self.lexer = FormulaLexer(source)
    self.current = try lexer.next()
  }

  public static func parse(_ source: String) throws -> FormulaExpr {
    var parser = try FormulaParser(source)
    let expr = try parser.parseExpression()
    guard parser.current == .eof else {
      throw FormulaParseError.unexpectedToken(parser.current)
    }
    return expr
  }

  private mutating func parseExpression() throws -> FormulaExpr {
    try parseComparison()
  }

  private mutating func parseComparison() throws -> FormulaExpr {
    var left = try parseConcat()
    while true {
      let op: BinaryOp?
      switch current {
      case .eq: op = .eq
      case .ne: op = .ne
      case .lt: op = .lt
      case .gt: op = .gt
      case .le: op = .le
      case .ge: op = .ge
      default: op = nil
      }
      guard let op else { break }
      try advance()
      let right = try parseConcat()
      left = .binary(op, left, right)
    }
    return left
  }

  private mutating func parseConcat() throws -> FormulaExpr {
    var left = try parseAddSub()
    while current == .amp {
      try advance()
      let right = try parseAddSub()
      left = .binary(.concat, left, right)
    }
    return left
  }

  private mutating func parseAddSub() throws -> FormulaExpr {
    var left = try parseMulDiv()
    while true {
      if current == .plus {
        try advance()
        left = .binary(.add, left, try parseMulDiv())
      } else if current == .minus {
        try advance()
        left = .binary(.subtract, left, try parseMulDiv())
      } else {
        break
      }
    }
    return left
  }

  private mutating func parseMulDiv() throws -> FormulaExpr {
    var left = try parsePower()
    while true {
      if current == .star {
        try advance()
        left = .binary(.multiply, left, try parsePower())
      } else if current == .slash {
        try advance()
        left = .binary(.divide, left, try parsePower())
      } else {
        break
      }
    }
    return left
  }

  private mutating func parsePower() throws -> FormulaExpr {
    var left = try parseUnary()
    if current == .caret {
      try advance()
      let right = try parsePower()
      left = .binary(.power, left, right)
    }
    return left
  }

  private mutating func parseUnary() throws -> FormulaExpr {
    if current == .plus {
      try advance()
      return .unary(.plus, try parseUnary())
    }
    if current == .minus {
      try advance()
      return .unary(.negate, try parseUnary())
    }
    // `%` binds tighter than a sign and `^`, as in other apps: -A2% is -(A2%), 2^50% is 2^0.5.
    var expr = try parseReference()
    while current == .percent {
      try advance()
      expr = .unary(.percent, expr)
    }
    return expr
  }

  /// A reference with `:` and space operators, as other apps read them: `B1:INDEX(B:B,5)`,
  /// `INDIRECT("B1"):INDIRECT("B3")` and `B1:B9 A3:D3` (the cells both share).
  private mutating func parseReference() throws -> FormulaExpr {
    var left = try parsePrimary()
    while Self.isReferenceLike(left) {
      if current == .colon {
        try advance()
        let right = try parsePrimary()
        guard Self.isReferenceLike(right) else { throw FormulaParseError.unexpectedToken(current) }
        if case .cellRef(let a) = left, case .cellRef(let b) = right {
          left = .range(a, b)
        } else {
          left = .call(FormulaExpr.rangeOperatorFunction, [left, right])
        }
        continue
      }
      if lexer.spaceBefore, Self.startsReference(current) {
        let right = try parseReference()
        guard Self.isReferenceLike(right) else { throw FormulaParseError.unexpectedToken(current) }
        left = .call(FormulaExpr.intersectionFunction, [left, right])
        continue
      }
      break
    }
    return left
  }

  /// A LAMBDA, or a LAMBDA already called that gives one (`LAMBDA(x,LAMBDA(y,x+y))(1)`).
  public static func isLambda(_ expr: FormulaExpr) -> Bool {
    switch expr {
    case .call(let name, let args):
      let upper = name.uppercased()
      if upper == "LAMBDA" || upper.hasSuffix(".LAMBDA") { return true }
      if name == FormulaExpr.lambdaCallFunction, let inner = args.first,
        case .call(_, let innerArgs) = inner, let body = innerArgs.last
      {
        return isLambda(body)
      }
      return false
    default:
      return false
    }
  }

  static func isReferenceLike(_ expr: FormulaExpr) -> Bool {
    switch expr {
    case .cellRef, .range, .namedRange: return true
    case .call(let name, _):
      let upper = name.uppercased()
      return [
        "INDIRECT", "OFFSET", "INDEX", FormulaExpr.rangeOperatorFunction,
        FormulaExpr.intersectionFunction, FormulaExpr.anchorArrayFunction,
      ].contains { upper == $0 || upper.hasSuffix("." + $0) }
    default: return false
    }
  }

  private static func startsReference(_ token: FormulaToken) -> Bool {
    switch token {
    case .cellRef, .range, .spillRef, .identifier: return true
    default: return false
    }
  }

  private mutating func parsePrimary() throws -> FormulaExpr {
    switch current {
    case .number(let value):
      try advance()
      return .number(value)
    case .string(let value):
      try advance()
      return .string(value)
    case .boolean(let value):
      try advance()
      return .boolean(value)
    case .error(let error):
      try advance()
      return .error(error)
    case .cellRef(let text):
      try advance()
      guard let parsed = A1Reference.parseFormulaRef(text) else {
        throw FormulaParseError.expectedToken("cell reference")
      }
      return .cellRef(parsed)
    case .spillRef(let text):
      try advance()
      guard let parsed = A1Reference.parseFormulaRef(text) else {
        throw FormulaParseError.expectedToken("cell reference")
      }
      // Saved files write `G1#` as `_xlfn.ANCHORARRAY(G1)`; both read the same.
      return .call(FormulaExpr.anchorArrayFunction, [.cellRef(parsed)])
    case .range(let text):
      try advance()
      guard let (start, end) = A1Reference.parseFormulaRange(text) else {
        throw FormulaParseError.expectedToken("range")
      }
      return .range(start, end)
    case .identifier(let name):
      try advance()
      if current == .lParen {
        try advance()
        var args: [FormulaExpr] = []
        if current != .rParen {
          var first = true
          repeat {
            if !first { try advance() }
            first = false
            // Nothing before the next comma or the closing parenthesis: an argument left out.
            if current == .comma || current == .rParen {
              args.append(.missing)
            } else {
              args.append(try parseExpression())
            }
          } while current == .comma
        }
        try expect(.rParen, named: ")")
        var call = FormulaExpr.call(name, args)
        // `LAMBDA(x,x*3)(7)`: values right after a LAMBDA call it there and then.
        while current == .lParen, Self.isLambda(call) {
          try advance()
          var values: [FormulaExpr] = [call]
          if current != .rParen {
            var first = true
            repeat {
              if !first { try advance() }
              first = false
              if current == .comma || current == .rParen {
                values.append(.missing)
              } else {
                values.append(try parseExpression())
              }
            } while current == .comma
          }
          try expect(.rParen, named: ")")
          call = .call(FormulaExpr.lambdaCallFunction, values)
        }
        return call
      }
      return .namedRange(name)
    case .lParen:
      try advance()
      let expr = try parseExpression()
      try expect(.rParen, named: ")")
      return expr
    case .lBrace:
      return try parseArrayConstant()
    default:
      throw FormulaParseError.unexpectedToken(current)
    }
  }

  /// `{1,2;3,4}`: rows split by `;`, items by `,`. Every row must be as long as the first.
  private mutating func parseArrayConstant() throws -> FormulaExpr {
    try advance()  // {
    var rows: [[FormulaExpr]] = []
    var row: [FormulaExpr] = []
    while true {
      row.append(try parseArrayItem())
      switch current {
      case .comma:
        try advance()
      case .semicolon:
        try advance()
        rows.append(row)
        row = []
      case .rBrace:
        try advance()
        rows.append(row)
        guard let width = rows.first?.count, rows.allSatisfy({ $0.count == width }) else {
          throw FormulaParseError.expectedToken("rows of the same length")
        }
        return .array(rows)
      default:
        throw FormulaParseError.expectedToken("}")
      }
    }
  }

  /// One item of a typed list: a number (a sign allowed), text, TRUE or FALSE, or an error.
  private mutating func parseArrayItem() throws -> FormulaExpr {
    var sign: Double = 1
    if current == .minus || current == .plus {
      if current == .minus { sign = -1 }
      try advance()
      guard case .number(let value) = current else {
        throw FormulaParseError.expectedToken("number")
      }
      try advance()
      return .number(sign * value)
    }
    switch current {
    case .number(let value):
      try advance()
      return .number(value)
    case .string(let value):
      try advance()
      return .string(value)
    case .boolean(let value):
      try advance()
      return .boolean(value)
    case .error(let error):
      try advance()
      return .error(error)
    default:
      throw FormulaParseError.expectedToken("a number, text, TRUE, FALSE or an error")
    }
  }

  private mutating func advance() throws {
    current = try lexer.next()
  }

  private mutating func expect(_ token: FormulaToken, named: String) throws {
    guard current == token else {
      throw FormulaParseError.expectedToken(named)
    }
    try advance()
  }
}

public nonisolated enum FormulaSyntax {
  public static func isFormula(_ raw: String) -> Bool {
    raw.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("=")
  }
}
