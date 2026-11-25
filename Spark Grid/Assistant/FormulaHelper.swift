import Foundation
import SparkGridCore

#if canImport(FoundationModels)
  import FoundationModels
#endif

/// Formula help from the language model built into the Mac (Apple Intelligence): explain the
/// selected cell's formula, or write one from a sentence. It runs on the Mac and sends nothing
/// anywhere, so Spark Grid still never uses the network (Sam, Nov 18 and Nov 20: "Apple model
/// built in for everyday formula help; no bundled model").
enum FormulaHelper {
  enum Availability: Equatable {
    case available
    /// A Mac that has the model but has not turned on Apple Intelligence, or is still
    /// downloading it.
    case needsAppleIntelligence(String)
    /// An older macOS, or a Mac without Apple Intelligence.
    case unsupported
  }

  static var availability: Availability {
    #if canImport(FoundationModels)
      if #available(macOS 26.0, *) {
        switch SystemLanguageModel.default.availability {
        case .available:
          return .available
        case .unavailable(.appleIntelligenceNotEnabled):
          return .needsAppleIntelligence(
            "Turn on Apple Intelligence in System Settings to use formula help.")
        case .unavailable(.modelNotReady):
          return .needsAppleIntelligence(
            "Apple Intelligence is still getting ready on this Mac. Try again in a little while.")
        case .unavailable:
          return .unsupported
        }
      }
    #endif
    return .unsupported
  }

  struct Suggestion: Equatable {
    var formula: String
    var explanation: String
  }

  enum HelpError: LocalizedError {
    case unavailable
    var errorDescription: String? { "Formula help needs Apple Intelligence on this Mac." }
  }

  private static let instructions = """
    You help people with spreadsheet formulas in Spark Grid, a spreadsheet app whose formulas \
    work like Excel's. Use only functions Excel has, and only the conditions the person asks \
    for. Refer to cells on this sheet with plain A1 addresses such as B2:B9, with no sheet \
    name. Only for a cell on one of the other sheets named below, write 'Sheet name'!A1. Use the data \
    rows only, never the header or total rows. Keep explanations short and plain. Never invent \
    data that is not in the description of the sheet.
    """

  /// Worked answers in the form wanted. The model on the Mac follows an example far better than
  /// a description: without these it put SUMIFS's arguments in the wrong order, and with
  /// guided generation one answer took two and a half minutes (tried Nov 20).
  private static let writeInstructions =
    instructions + """

      Reply with the formula alone on the first line, starting with =, then one short sentence \
      explaining it. Argument order matters:
      SUMIFS(sum_range, criteria_range1, criteria1, ...)
      COUNTIFS(criteria_range1, criteria1, ...)
      AVERAGEIFS(average_range, criteria_range1, criteria1, ...)
      XLOOKUP(lookup_value, lookup_array, return_array, [if_not_found])
      Example: "Amount" in C and "Region" in B, data rows 2 to 50. Request: total amount for East.
      =SUMIFS(C2:C50,B2:B50,"East")
      Adds the amounts on rows whose region is East.
      Example: same sheet. Request: total of column C.
      =SUM(C2:C50)
      Adds every amount in column C.
      """

  /// A plain-language explanation of `formula`, typed in `cell`.
  static func explain(_ formula: String, cell: String, context: String) async throws -> String {
    #if canImport(FoundationModels)
      if #available(macOS 26.0, *), availability == .available {
        let session = LanguageModelSession(instructions: instructions)
        let prompt = """
          \(context)

          Explain in two to four short sentences what this formula in \(cell) does and what its \
          result means:
          \(formula)
          """
        return try await session.respond(to: prompt).content
          .trimmingCharacters(in: .whitespacesAndNewlines)
      }
    #endif
    throw HelpError.unavailable
  }

  /// A formula for `request`, to go in `cell`, with a sentence on how it works.
  static func write(_ request: String, cell: String, context: String) async throws -> Suggestion {
    #if canImport(FoundationModels)
      if #available(macOS 26.0, *), availability == .available {
        let session = LanguageModelSession(instructions: writeInstructions)
        let prompt = """
          \(context)

          The formula goes in \(cell). Request: \(request)
          """
        let answer = try await session.respond(to: prompt).content
        return parse(answer)
      }
    #endif
    throw HelpError.unavailable
  }

  /// The formula line and the explanation after it, from the model's answer.
  static func parse(_ answer: String) -> Suggestion {
    var lines = answer.replacingOccurrences(of: "```", with: "")
      .components(separatedBy: .newlines)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty && $0.lowercased() != "excel" }
    let index = lines.firstIndex { $0.hasPrefix("=") } ?? 0
    var formula = lines.isEmpty ? "" : lines.remove(at: index)
    formula = formula.trimmingCharacters(in: CharacterSet(charactersIn: "`"))
    if !formula.hasPrefix("=") { formula = "=" + formula }
    return Suggestion(formula: formula, explanation: lines.joined(separator: " "))
  }

  /// Names in `formula` that are not functions Spark Grid has, so the sheet can say so before
  /// the formula goes in. Nil when the formula does not parse.
  static func unknownFunctions(in formula: String) -> [String]? {
    guard let expr = try? FormulaParser.parse(formula) else { return nil }
    let known = Set(FormulaFunctions.all)
    var names: [String] = []
    func walk(_ e: FormulaExpr) {
      switch e {
      case .call(let name, let args):
        let plain = FormulaEvaluator.plainFunctionName(name)
        if !known.contains(plain), !names.contains(plain) { names.append(plain) }
        args.forEach(walk)
      case .unary(_, let inner): walk(inner)
      case .binary(_, let l, let r):
        walk(l)
        walk(r)
      case .array(let rows):
        for row in rows { row.forEach(walk) }
      default: break
      }
    }
    walk(expr)
    // Names the parser gives `:`, the space operator and `G1#` are not functions people type.
    return names.filter { !$0.hasPrefix("SG.") && $0 != FormulaExpr.anchorArrayFunction }
  }
}
