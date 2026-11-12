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
  case financial = "Financial"

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
    FormulaFunctionEntry(name: "PMT", kind: .financial, arguments: "rate, nper, pv, [fv], [type]"),
    FormulaFunctionEntry(
      name: "IPMT", kind: .financial,
      arguments: "rate, per, nper, pv, [fv], [type]"),
    FormulaFunctionEntry(
      name: "PPMT", kind: .financial,
      arguments: "rate, per, nper, pv, [fv], [type]"),
    FormulaFunctionEntry(name: "FV", kind: .financial, arguments: "rate, nper, pmt, [pv], [type]"),
    FormulaFunctionEntry(name: "PV", kind: .financial, arguments: "rate, nper, pmt, [fv], [type]"),
    FormulaFunctionEntry(name: "NPER", kind: .financial, arguments: "rate, pmt, pv, [fv], [type]"),
    FormulaFunctionEntry(
      name: "RATE", kind: .financial,
      arguments: "nper, pmt, pv, [fv], [type], [guess]"),
    FormulaFunctionEntry(name: "NPV", kind: .financial, arguments: "rate, value1, [value2], ..."),
    FormulaFunctionEntry(name: "IRR", kind: .financial, arguments: "values, [guess]"),
    FormulaFunctionEntry(name: "XNPV", kind: .financial, arguments: "rate, values, dates"),
    FormulaFunctionEntry(name: "XIRR", kind: .financial, arguments: "values, dates, [guess]"),
    FormulaFunctionEntry(name: "DAYS", kind: .dateTime, arguments: "end_date, start_date"),
    FormulaFunctionEntry(name: "DATEDIF", kind: .dateTime, arguments: "start_date, end_date, unit"),
    FormulaFunctionEntry(
      name: "NETWORKDAYS", kind: .dateTime,
      arguments: "start_date, end_date, [holidays]"),
    FormulaFunctionEntry(
      name: "WORKDAY", kind: .dateTime,
      arguments: "start_date, days, [holidays]"),
    FormulaFunctionEntry(
      name: "WEEKNUM", kind: .dateTime,
      arguments: "serial_number, [return_type]"),
    FormulaFunctionEntry(name: "ISOWEEKNUM", kind: .dateTime, arguments: "date"),
    FormulaFunctionEntry(name: "STDEV", kind: .statistical, arguments: "number1, [number2], ..."),
    FormulaFunctionEntry(name: "STDEV.S", kind: .statistical, arguments: "number1, [number2], ..."),
    FormulaFunctionEntry(name: "STDEVP", kind: .statistical, arguments: "number1, [number2], ..."),
    FormulaFunctionEntry(name: "STDEV.P", kind: .statistical, arguments: "number1, [number2], ..."),
    FormulaFunctionEntry(name: "VAR", kind: .statistical, arguments: "number1, [number2], ..."),
    FormulaFunctionEntry(name: "VAR.S", kind: .statistical, arguments: "number1, [number2], ..."),
    FormulaFunctionEntry(name: "VARP", kind: .statistical, arguments: "number1, [number2], ..."),
    FormulaFunctionEntry(name: "VAR.P", kind: .statistical, arguments: "number1, [number2], ..."),
    FormulaFunctionEntry(name: "PERCENTILE", kind: .statistical, arguments: "array, k"),
    FormulaFunctionEntry(name: "PERCENTILE.INC", kind: .statistical, arguments: "array, k"),
    FormulaFunctionEntry(name: "QUARTILE", kind: .statistical, arguments: "array, quart"),
    FormulaFunctionEntry(name: "QUARTILE.INC", kind: .statistical, arguments: "array, quart"),
    FormulaFunctionEntry(name: "MODE", kind: .statistical, arguments: "number1, [number2], ..."),
    FormulaFunctionEntry(
      name: "MODE.SNGL", kind: .statistical,
      arguments: "number1, [number2], ..."),
    FormulaFunctionEntry(name: "CORREL", kind: .statistical, arguments: "array1, array2"),
    FormulaFunctionEntry(name: "SLOPE", kind: .statistical, arguments: "known_ys, known_xs"),
    FormulaFunctionEntry(name: "INTERCEPT", kind: .statistical, arguments: "known_ys, known_xs"),
    FormulaFunctionEntry(name: "FORECAST", kind: .statistical, arguments: "x, known_ys, known_xs"),
    FormulaFunctionEntry(
      name: "FORECAST.LINEAR", kind: .statistical,
      arguments: "x, known_ys, known_xs"),
    FormulaFunctionEntry(
      name: "COUNTUNIQUE", kind: .statistical,
      arguments: "value1, [value2], ..."),
    FormulaFunctionEntry(name: "SUMSQ", kind: .math, arguments: "number1, [number2], ..."),
    FormulaFunctionEntry(name: "MROUND", kind: .math, arguments: "number, multiple"),
    FormulaFunctionEntry(name: "TRUNC", kind: .math, arguments: "number, [num_digits]"),
    FormulaFunctionEntry(name: "EXP", kind: .math, arguments: "number"),
    FormulaFunctionEntry(name: "LN", kind: .math, arguments: "number"),
    FormulaFunctionEntry(name: "LOG", kind: .math, arguments: "number, [base]"),
    FormulaFunctionEntry(name: "LOG10", kind: .math, arguments: "number"),
    FormulaFunctionEntry(name: "FACT", kind: .math, arguments: "number"),
    FormulaFunctionEntry(name: "GCD", kind: .math, arguments: "number1, [number2], ..."),
    FormulaFunctionEntry(name: "LCM", kind: .math, arguments: "number1, [number2], ..."),
    FormulaFunctionEntry(name: "EVEN", kind: .math, arguments: "number"),
    FormulaFunctionEntry(name: "ODD", kind: .math, arguments: "number"),
    FormulaFunctionEntry(
      name: "SWITCH", kind: .logical,
      arguments: "expression, value1, result1, ..., [default]"),
    FormulaFunctionEntry(name: "XOR", kind: .logical, arguments: "logical1, [logical2], ..."),
    FormulaFunctionEntry(name: "ISEVEN", kind: .logical, arguments: "number"),
    FormulaFunctionEntry(name: "ISODD", kind: .logical, arguments: "number"),
    FormulaFunctionEntry(name: "ISLOGICAL", kind: .logical, arguments: "value"),
    FormulaFunctionEntry(name: "ISNA", kind: .logical, arguments: "value"),
    FormulaFunctionEntry(name: "ISERR", kind: .logical, arguments: "value"),
    FormulaFunctionEntry(name: "NA", kind: .logical, arguments: ""),
    FormulaFunctionEntry(
      name: "CHOOSE", kind: .lookup,
      arguments: "index_num, value1, [value2], ..."),
    FormulaFunctionEntry(
      name: "HYPERLINK", kind: .lookup,
      arguments: "link_location, [friendly_name]"),
    FormulaFunctionEntry(
      name: "FILTER", kind: .lookup, arguments: "array, include, [if_empty]"),
    FormulaFunctionEntry(
      name: "SORT", kind: .lookup, arguments: "array, [sort_index], [sort_order], [by_col]"),
    FormulaFunctionEntry(
      name: "SORTBY", kind: .lookup,
      arguments: "array, by_array1, [sort_order1], [by_array2, sort_order2], ..."),
    FormulaFunctionEntry(
      name: "UNIQUE", kind: .lookup, arguments: "array, [by_col], [exactly_once]"),
    FormulaFunctionEntry(
      name: "GETPIVOTDATA", kind: .lookup,
      arguments: "data_field, pivot_table, [field1, item1], ..."),
    FormulaFunctionEntry(
      name: "TEXTBEFORE", kind: .text,
      arguments: "text, delimiter, [instance_num], [match_mode], [match_end], [if_not_found]"),
    FormulaFunctionEntry(
      name: "TEXTAFTER", kind: .text,
      arguments: "text, delimiter, [instance_num], [match_mode], [match_end], [if_not_found]"),
    FormulaFunctionEntry(name: "CLEAN", kind: .text, arguments: "text"),
    FormulaFunctionEntry(name: "CODE", kind: .text, arguments: "text"),
    FormulaFunctionEntry(name: "UNICODE", kind: .text, arguments: "text"),
    FormulaFunctionEntry(name: "UNICHAR", kind: .text, arguments: "number"),
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
