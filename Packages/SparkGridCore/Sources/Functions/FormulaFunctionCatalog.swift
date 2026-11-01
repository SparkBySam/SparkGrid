import Formula
import Foundation

/// Insert Function list. Names come from `FormulaFunctions.all`, which is the
/// set the evaluator already calculates. This catalog does not add functions.
public enum FormulaFunctionKind: String, CaseIterable, Hashable {
  case math = "Math"
  case statistical = "Statistical"
  case logical = "Logical"
  case text = "Text"
  case lookup = "Lookup"
  case dateTime = "Date & Time"

  public var title: String { rawValue }
}

public struct FormulaFunctionEntry: Equatable, Identifiable {
  public var name: String
  public var kind: FormulaFunctionKind
  /// Argument list inside the parentheses. Empty when the function takes none.
  public var arguments: String

  public var id: String { name }

  /// One line, such as `SUM(number1, [number2], ...)` or `TODAY()`.
  public var signatureLine: String {
    arguments.isEmpty ? "\(name)()" : "\(name)(\(arguments))"
  }

  public func matches(_ query: String) -> Bool {
    let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
    if needle.isEmpty { return true }
    if name.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
      return true
    }
    if arguments.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
      return true
    }
    return false
  }
}

public struct FormulaFunctionGroup: Equatable {
  public var kind: FormulaFunctionKind
  public var entries: [FormulaFunctionEntry]
}

public struct FormulaFunctionInsertion: Equatable {
  public var text: String
  public var caretUTF16: Int
  public var arguments: String
  public var signatureLine: String
}

public enum FormulaFunctionCatalog {
  private static let defined: [FormulaFunctionEntry] = [
    FormulaFunctionEntry(name: "ABS", kind: .math, arguments: "number"),
    FormulaFunctionEntry(
      name: "SEQUENCE", kind: .math, arguments: "rows, [columns], [start], [step]"),
    FormulaFunctionEntry(name: "ROUND", kind: .math, arguments: "number, [num_digits]"),
    FormulaFunctionEntry(name: "ROUNDDOWN", kind: .math, arguments: "number, [num_digits]"),
    FormulaFunctionEntry(name: "ROUNDUP", kind: .math, arguments: "number, [num_digits]"),
    FormulaFunctionEntry(name: "SUM", kind: .math, arguments: "number1, [number2], ..."),
    FormulaFunctionEntry(name: "SUMIF", kind: .math, arguments: "range, criteria, [sum_range]"),
    FormulaFunctionEntry(
      name: "SUMIFS", kind: .math, arguments: "sum_range, criteria_range1, criteria1, ..."),
    FormulaFunctionEntry(name: "SUMPRODUCT", kind: .math, arguments: "array1, [array2], ..."),

    FormulaFunctionEntry(name: "AVERAGE", kind: .statistical, arguments: "number1, [number2], ..."),
    FormulaFunctionEntry(
      name: "AVERAGEIF", kind: .statistical, arguments: "range, criteria, [average_range]"),
    FormulaFunctionEntry(
      name: "AVERAGEIFS", kind: .statistical,
      arguments: "average_range, criteria_range1, criteria1, ..."),
    FormulaFunctionEntry(name: "COUNT", kind: .statistical, arguments: "value1, [value2], ..."),
    FormulaFunctionEntry(name: "COUNTA", kind: .statistical, arguments: "value1, [value2], ..."),
    FormulaFunctionEntry(name: "COUNTBLANK", kind: .statistical, arguments: "range"),
    FormulaFunctionEntry(name: "COUNTIF", kind: .statistical, arguments: "range, criteria"),
    FormulaFunctionEntry(
      name: "COUNTIFS", kind: .statistical, arguments: "criteria_range1, criteria1, ..."),
    FormulaFunctionEntry(name: "MAX", kind: .statistical, arguments: "number1, [number2], ..."),
    FormulaFunctionEntry(name: "MIN", kind: .statistical, arguments: "number1, [number2], ..."),

    FormulaFunctionEntry(name: "AND", kind: .logical, arguments: "logical1, [logical2], ..."),
    FormulaFunctionEntry(
      name: "IF", kind: .logical, arguments: "logical_test, value_if_true, [value_if_false]"),
    FormulaFunctionEntry(name: "IFERROR", kind: .logical, arguments: "value, value_if_error"),
    FormulaFunctionEntry(name: "IFNA", kind: .logical, arguments: "value, value_if_na"),
    FormulaFunctionEntry(
      name: "IFS", kind: .logical, arguments: "logical_test1, value_if_true1, ..."),
    FormulaFunctionEntry(name: "NOT", kind: .logical, arguments: "logical"),
    FormulaFunctionEntry(name: "OR", kind: .logical, arguments: "logical1, [logical2], ..."),

    FormulaFunctionEntry(name: "CONCAT", kind: .text, arguments: "text1, [text2], ..."),
    FormulaFunctionEntry(name: "CONCATENATE", kind: .text, arguments: "text1, [text2], ..."),
    FormulaFunctionEntry(name: "LEFT", kind: .text, arguments: "text, [num_chars]"),
    FormulaFunctionEntry(name: "LEN", kind: .text, arguments: "text"),
    FormulaFunctionEntry(name: "LOWER", kind: .text, arguments: "text"),
    FormulaFunctionEntry(name: "MID", kind: .text, arguments: "text, start_num, num_chars"),
    FormulaFunctionEntry(name: "RIGHT", kind: .text, arguments: "text, [num_chars]"),
    FormulaFunctionEntry(
      name: "SUBSTITUTE", kind: .text, arguments: "text, old_text, new_text, [instance_num]"),
    FormulaFunctionEntry(name: "TEXT", kind: .text, arguments: "value, format_text"),
    FormulaFunctionEntry(
      name: "TEXTJOIN", kind: .text, arguments: "delimiter, ignore_empty, text1, ..."),
    FormulaFunctionEntry(name: "CHAR", kind: .text, arguments: "number"),
    FormulaFunctionEntry(name: "REPT", kind: .text, arguments: "text, number_times"),
    FormulaFunctionEntry(name: "TRIM", kind: .text, arguments: "text"),
    FormulaFunctionEntry(name: "UPPER", kind: .text, arguments: "text"),

    FormulaFunctionEntry(name: "COLUMN", kind: .lookup, arguments: "[reference]"),
    FormulaFunctionEntry(name: "TRUE", kind: .logical, arguments: ""),

    FormulaFunctionEntry(
      name: "HLOOKUP", kind: .lookup,
      arguments: "lookup_value, table_array, row_index_num, [range_lookup]"),
    FormulaFunctionEntry(name: "INDEX", kind: .lookup, arguments: "array, row_num, [column_num]"),
    FormulaFunctionEntry(
      name: "MATCH", kind: .lookup, arguments: "lookup_value, lookup_array, [match_type]"),
    FormulaFunctionEntry(
      name: "VLOOKUP", kind: .lookup,
      arguments: "lookup_value, table_array, col_index_num, [range_lookup]"),
    FormulaFunctionEntry(
      name: "XLOOKUP", kind: .lookup,
      arguments: "lookup_value, lookup_array, return_array, [if_not_found], [match_mode]"),
    FormulaFunctionEntry(
      name: "XMATCH", kind: .lookup, arguments: "lookup_value, lookup_array, [match_mode]"),

    FormulaFunctionEntry(name: "DATE", kind: .dateTime, arguments: "year, month, day"),
    FormulaFunctionEntry(name: "DAY", kind: .dateTime, arguments: "serial_number"),
    FormulaFunctionEntry(name: "MONTH", kind: .dateTime, arguments: "serial_number"),
    FormulaFunctionEntry(name: "NOW", kind: .dateTime, arguments: ""),
    FormulaFunctionEntry(name: "TODAY", kind: .dateTime, arguments: ""),
    FormulaFunctionEntry(name: "YEAR", kind: .dateTime, arguments: "serial_number"),
    FormulaFunctionEntry(name: "INT", kind: .math, arguments: "number"),
    FormulaFunctionEntry(name: "SIGN", kind: .math, arguments: "number"),
    FormulaFunctionEntry(name: "SQRT", kind: .math, arguments: "number"),
    FormulaFunctionEntry(name: "PI", kind: .math, arguments: ""),
    FormulaFunctionEntry(name: "MOD", kind: .math, arguments: "number, divisor"),
    FormulaFunctionEntry(name: "POWER", kind: .math, arguments: "number, power"),
    FormulaFunctionEntry(name: "CEILING", kind: .math, arguments: "number, [significance]"),
    FormulaFunctionEntry(name: "CEILING.MATH", kind: .math, arguments: "number, [significance]"),
    FormulaFunctionEntry(name: "FLOOR", kind: .math, arguments: "number, [significance]"),
    FormulaFunctionEntry(name: "FLOOR.MATH", kind: .math, arguments: "number, [significance]"),
    FormulaFunctionEntry(name: "PRODUCT", kind: .math, arguments: "number1, [number2], ..."),
    FormulaFunctionEntry(name: "MEDIAN", kind: .statistical, arguments: "number1, [number2], ..."),
    FormulaFunctionEntry(name: "LARGE", kind: .statistical, arguments: "array, k"),
    FormulaFunctionEntry(name: "SMALL", kind: .statistical, arguments: "array, k"),
    FormulaFunctionEntry(name: "RANK", kind: .statistical, arguments: "number, ref, [order]"),
    FormulaFunctionEntry(name: "RANK.EQ", kind: .statistical, arguments: "number, ref, [order]"),
    FormulaFunctionEntry(
      name: "MAXIFS", kind: .statistical, arguments: "max_range, criteria_range1, criteria1, ..."),
    FormulaFunctionEntry(
      name: "MINIFS", kind: .statistical, arguments: "min_range, criteria_range1, criteria1, ..."),
    FormulaFunctionEntry(name: "PROPER", kind: .text, arguments: "text"),
    FormulaFunctionEntry(
      name: "FIND", kind: .text, arguments: "find_text, within_text, [start_num]"),
    FormulaFunctionEntry(
      name: "SEARCH", kind: .text, arguments: "find_text, within_text, [start_num]"),
    FormulaFunctionEntry(name: "VALUE", kind: .text, arguments: "text"),
    FormulaFunctionEntry(name: "EXACT", kind: .text, arguments: "text1, text2"),
    FormulaFunctionEntry(name: "ISBLANK", kind: .logical, arguments: "value"),
    FormulaFunctionEntry(name: "ISNUMBER", kind: .logical, arguments: "value"),
    FormulaFunctionEntry(name: "ISTEXT", kind: .logical, arguments: "value"),
    FormulaFunctionEntry(name: "ISERROR", kind: .logical, arguments: "value"),
    FormulaFunctionEntry(name: "FALSE", kind: .logical, arguments: ""),
    FormulaFunctionEntry(
      name: "WEEKDAY", kind: .dateTime, arguments: "serial_number, [return_type]"),
    FormulaFunctionEntry(name: "HOUR", kind: .dateTime, arguments: "serial_number"),
    FormulaFunctionEntry(name: "MINUTE", kind: .dateTime, arguments: "serial_number"),
    FormulaFunctionEntry(name: "SECOND", kind: .dateTime, arguments: "serial_number"),
    FormulaFunctionEntry(name: "EDATE", kind: .dateTime, arguments: "start_date, months"),
    FormulaFunctionEntry(name: "EOMONTH", kind: .dateTime, arguments: "start_date, months"),
    FormulaFunctionEntry(name: "ROW", kind: .lookup, arguments: "[reference]"),
    FormulaFunctionEntry(name: "ROWS", kind: .lookup, arguments: "array"),
    FormulaFunctionEntry(name: "COLUMNS", kind: .lookup, arguments: "array"),
  ]

  public static func groups(matching query: String) -> [FormulaFunctionGroup] {
    let implemented = Set(FormulaFunctions.all)
    return FormulaFunctionKind.allCases.compactMap { kind in
      let entries =
        defined
        .filter { $0.kind == kind && implemented.contains($0.name) && $0.matches(query) }
        .sorted { $0.name < $1.name }
      guard !entries.isEmpty else { return nil }
      return FormulaFunctionGroup(kind: kind, entries: entries)
    }
  }

  public static func entry(named name: String) -> FormulaFunctionEntry? {
    let upper = name.uppercased()
    guard FormulaFunctions.all.contains(upper) else { return nil }
    return defined.first { $0.name == upper }
  }

  /// `=NAME()` with the caret between the parentheses.
  public static func insertion(for name: String) -> FormulaFunctionInsertion? {
    guard let entry = entry(named: name) else { return nil }
    let text = "=\(entry.name)()"
    return FormulaFunctionInsertion(
      text: text,
      caretUTF16: text.utf16.count - 1,
      arguments: entry.arguments,
      signatureLine: entry.signatureLine
    )
  }
}
