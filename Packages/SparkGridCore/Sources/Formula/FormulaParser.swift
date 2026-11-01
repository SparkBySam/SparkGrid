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
    return try parsePrimary()
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
          repeat {
            if current == .comma { try advance() }
            args.append(try parseExpression())
          } while current == .comma
        }
        try expect(.rParen, named: ")")
        return .call(name, args)
      }
      return .namedRange(name)
    case .lParen:
      try advance()
      let expr = try parseExpression()
      try expect(.rParen, named: ")")
      return expr
    default:
      throw FormulaParseError.unexpectedToken(current)
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
