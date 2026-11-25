import Foundation
import SparkGridCore

#if canImport(FoundationModels)
  import FoundationModels
#endif

/// Chart help from the model built into the Mac (Apple Intelligence): a chart described in a
/// sentence becomes the Insert Chart choices (kind, columns, trendline, title), which the person
/// then checks before inserting. Runs on the Mac; nothing leaves it (Sam, Nov 20: "incorporate
/// Apple Intelligence for making charts, graphs").
enum ChartHelper {
  struct Suggestion: Equatable {
    var kind: SheetChart.Kind?
    var categoryColumn: Int?
    var valueColumns: [Int] = []
    var trendline: ChartTrendline.Kind?
    var title: String?
  }

  /// One column the model may use: its letter, header and whether it holds numbers.
  struct Column {
    var index: Int
    var letter: String
    var header: String
    var numeric: Bool
  }

  private static let instructions = """
    You choose charts for a spreadsheet app. Answer with these lines only, nothing else:
    kind: one of bar, horizontalBar, stackedBar, stackedHorizontalBar, line, area, stackedArea, \
    pie, doughnut, scatter
    category: the letter of the column for the labels along the axis
    values: the letters of the number columns to plot, comma separated
    trendline: none, linear, exponential, logarithmic, power or movingAverage
    title: a short title
    Use only the columns listed. Pie and doughnut take one values column. Use a trendline only \
    when asked for a trend.
    Example. Columns: A "Month" (text), B "Units" (numbers), C "Returns" (numbers). Request: \
    units by month with a trend.
    kind: line
    category: A
    values: B
    trendline: linear
    title: Units by month
    """

  static func suggest(_ request: String, columns: [Column]) async throws -> Suggestion {
    #if canImport(FoundationModels)
      if #available(macOS 26.0, *), FormulaHelper.availability == .available {
        let listed = columns.map {
          "\($0.letter) \"\($0.header.isEmpty ? "Column \($0.letter)" : $0.header)\" "
            + ($0.numeric ? "(numbers)" : "(text)")
        }.joined(separator: ", ")
        let session = LanguageModelSession(instructions: instructions)
        let answer = try await session.respond(to: "Columns: \(listed). Request: \(request)")
        return parse(answer.content, columns: columns)
      }
    #endif
    throw FormulaHelper.HelpError.unavailable
  }

  /// The choices in the model's answer, keeping only kinds and columns that exist.
  static func parse(_ answer: String, columns: [Column]) -> Suggestion {
    var suggestion = Suggestion()
    let byLetter = Dictionary(
      columns.map { ($0.letter.uppercased(), $0.index) }, uniquingKeysWith: { first, _ in first })
    func column(_ text: String) -> Int? {
      byLetter[text.trimmingCharacters(in: .whitespaces).uppercased()]
    }
    for line in answer.components(separatedBy: .newlines) {
      let parts = line.split(separator: ":", maxSplits: 1).map {
        $0.trimmingCharacters(in: .whitespaces)
      }
      guard parts.count == 2 else { continue }
      let value = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"'`*. "))
      switch parts[0].lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "*- ")) {
      case "kind":
        suggestion.kind = SheetChart.Kind.allCases.first {
          $0.rawValue.lowercased() == value.lowercased()
            || $0.title.lowercased() == value.lowercased()
        }
      case "category":
        suggestion.categoryColumn = column(value)
      case "values":
        suggestion.valueColumns = value.split(separator: ",").compactMap { column(String($0)) }
      case "trendline":
        suggestion.trendline = ChartTrendline.Kind.allCases.first {
          $0.rawValue.lowercased() == value.lowercased()
            || $0.title.lowercased() == value.lowercased()
        }
      case "title":
        suggestion.title = value.isEmpty ? nil : value
      default:
        break
      }
    }
    return suggestion
  }
}
