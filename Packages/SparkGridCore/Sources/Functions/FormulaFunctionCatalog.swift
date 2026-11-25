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
  case engineering = "Engineering"
  case database = "Database"
  case information = "Information"

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
    FormulaFunctionEntry(
      name: "RANDARRAY", kind: .math,
      arguments: "[rows], [columns], [min], [max], [whole_number]"),
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
    FormulaFunctionEntry(
      name: "LET", kind: .logical, arguments: "name1, value1, [name2, value2], ..., calculation"),
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
      arguments:
        "lookup_value, lookup_array, return_array, [if_not_found], [match_mode], [search_mode]"),
    FormulaFunctionEntry(
      name: "XMATCH", kind: .lookup, arguments: "lookup_value, lookup_array, [match_mode]"),
    FormulaFunctionEntry(
      name: "INDIRECT", kind: .lookup, arguments: "ref_text, [a1]"),
    FormulaFunctionEntry(name: "CELL", kind: .lookup, arguments: "info_type, [reference]"),
    FormulaFunctionEntry(
      name: "OFFSET", kind: .lookup, arguments: "reference, rows, cols, [height], [width]"),
    FormulaFunctionEntry(
      name: "LOOKUP", kind: .lookup, arguments: "lookup_value, lookup_vector, [result_vector]"),
    FormulaFunctionEntry(
      name: "ADDRESS", kind: .lookup,
      arguments: "row_num, column_num, [abs_num], [a1], [sheet_text]"),

    FormulaFunctionEntry(name: "DATE", kind: .dateTime, arguments: "year, month, day"),
    FormulaFunctionEntry(name: "DAY", kind: .dateTime, arguments: "serial_number"),
    FormulaFunctionEntry(name: "MONTH", kind: .dateTime, arguments: "serial_number"),
    FormulaFunctionEntry(name: "NOW", kind: .dateTime, arguments: ""),
    FormulaFunctionEntry(name: "TODAY", kind: .dateTime, arguments: ""),
    FormulaFunctionEntry(name: "YEAR", kind: .dateTime, arguments: "serial_number"),
    FormulaFunctionEntry(
      name: "YEARFRAC", kind: .dateTime, arguments: "start_date, end_date, [basis]"),
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
    FormulaFunctionEntry(name: "ISREF", kind: .logical, arguments: "value"),
    FormulaFunctionEntry(name: "ISFORMULA", kind: .logical, arguments: "reference"),
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
      name: "VSTACK", kind: .lookup, arguments: "array1, [array2], ..."),
    FormulaFunctionEntry(
      name: "HSTACK", kind: .lookup, arguments: "array1, [array2], ..."),
    FormulaFunctionEntry(name: "TAKE", kind: .lookup, arguments: "array, rows, [columns]"),
    FormulaFunctionEntry(name: "DROP", kind: .lookup, arguments: "array, rows, [columns]"),
    FormulaFunctionEntry(
      name: "CHOOSECOLS", kind: .lookup, arguments: "array, col_num1, [col_num2], ..."),
    FormulaFunctionEntry(
      name: "CHOOSEROWS", kind: .lookup, arguments: "array, row_num1, [row_num2], ..."),
    FormulaFunctionEntry(
      name: "WRAPROWS", kind: .lookup, arguments: "vector, wrap_count, [pad_with]"),
    FormulaFunctionEntry(
      name: "WRAPCOLS", kind: .lookup, arguments: "vector, wrap_count, [pad_with]"),
    FormulaFunctionEntry(
      name: "TOCOL", kind: .lookup, arguments: "array, [ignore], [scan_by_column]"),
    FormulaFunctionEntry(
      name: "TOROW", kind: .lookup, arguments: "array, [ignore], [scan_by_column]"),
    FormulaFunctionEntry(
      name: "GETPIVOTDATA", kind: .lookup,
      arguments: "data_field, pivot_table, [field1, item1], ..."),
    FormulaFunctionEntry(
      name: "TEXTBEFORE", kind: .text,
      arguments: "text, delimiter, [instance_num], [match_mode], [match_end], [if_not_found]"),
    FormulaFunctionEntry(
      name: "TEXTAFTER", kind: .text,
      arguments: "text, delimiter, [instance_num], [match_mode], [match_end], [if_not_found]"),
    FormulaFunctionEntry(
      name: "TEXTSPLIT", kind: .text,
      arguments:
        "text, col_delimiter, [row_delimiter], [ignore_empty], [match_mode], [pad_with]"),
    FormulaFunctionEntry(
      name: "REGEXTEST", kind: .text, arguments: "text, pattern, [case_sensitivity]"),
    FormulaFunctionEntry(
      name: "REGEXEXTRACT", kind: .text,
      arguments: "text, pattern, [return_mode], [case_sensitivity]"),
    FormulaFunctionEntry(
      name: "REGEXREPLACE", kind: .text,
      arguments: "text, pattern, replacement, [occurrence], [case_sensitivity]"),
    FormulaFunctionEntry(name: "CLEAN", kind: .text, arguments: "text"),
    FormulaFunctionEntry(name: "CODE", kind: .text, arguments: "text"),
    FormulaFunctionEntry(name: "UNICODE", kind: .text, arguments: "text"),
    FormulaFunctionEntry(name: "UNICHAR", kind: .text, arguments: "number"),
    // 1.5 batch 3
    FormulaFunctionEntry(name: "SIN", kind: .math, arguments: "number"),
    FormulaFunctionEntry(name: "COS", kind: .math, arguments: "number"),
    FormulaFunctionEntry(name: "TAN", kind: .math, arguments: "number"),
    FormulaFunctionEntry(name: "ASIN", kind: .math, arguments: "number"),
    FormulaFunctionEntry(name: "ACOS", kind: .math, arguments: "number"),
    FormulaFunctionEntry(name: "ATAN", kind: .math, arguments: "number"),
    FormulaFunctionEntry(name: "ATAN2", kind: .math, arguments: "x_num, y_num"),
    FormulaFunctionEntry(name: "SINH", kind: .math, arguments: "number"),
    FormulaFunctionEntry(name: "COSH", kind: .math, arguments: "number"),
    FormulaFunctionEntry(name: "TANH", kind: .math, arguments: "number"),
    FormulaFunctionEntry(name: "ASINH", kind: .math, arguments: "number"),
    FormulaFunctionEntry(name: "ACOSH", kind: .math, arguments: "number"),
    FormulaFunctionEntry(name: "ATANH", kind: .math, arguments: "number"),
    FormulaFunctionEntry(name: "DEGREES", kind: .math, arguments: "angle"),
    FormulaFunctionEntry(name: "RADIANS", kind: .math, arguments: "angle"),
    FormulaFunctionEntry(name: "SQRTPI", kind: .math, arguments: "number"),
    FormulaFunctionEntry(name: "COMBIN", kind: .math, arguments: "number, number_chosen"),
    FormulaFunctionEntry(name: "PERMUT", kind: .statistical, arguments: "number, number_chosen"),
    FormulaFunctionEntry(name: "QUOTIENT", kind: .math, arguments: "numerator, denominator"),
    FormulaFunctionEntry(name: "RAND", kind: .math, arguments: ""),
    FormulaFunctionEntry(name: "RANDBETWEEN", kind: .math, arguments: "bottom, top"),
    FormulaFunctionEntry(name: "AVERAGEA", kind: .statistical, arguments: "value1, [value2], ..."),
    FormulaFunctionEntry(name: "MAXA", kind: .statistical, arguments: "value1, [value2], ..."),
    FormulaFunctionEntry(name: "MINA", kind: .statistical, arguments: "value1, [value2], ..."),
    FormulaFunctionEntry(name: "STDEVA", kind: .statistical, arguments: "value1, [value2], ..."),
    FormulaFunctionEntry(name: "STDEVPA", kind: .statistical, arguments: "value1, [value2], ..."),
    FormulaFunctionEntry(name: "VARA", kind: .statistical, arguments: "value1, [value2], ..."),
    FormulaFunctionEntry(name: "VARPA", kind: .statistical, arguments: "value1, [value2], ..."),
    FormulaFunctionEntry(name: "GEOMEAN", kind: .statistical, arguments: "number1, [number2], ..."),
    FormulaFunctionEntry(name: "HARMEAN", kind: .statistical, arguments: "number1, [number2], ..."),
    FormulaFunctionEntry(name: "SEM", kind: .statistical, arguments: "number1, [number2], ..."),
    FormulaFunctionEntry(name: "MEAN", kind: .statistical, arguments: "number1, [number2], ..."),
    FormulaFunctionEntry(
      name: "MEAN.ARITH", kind: .statistical, arguments: "number1, [number2], ..."),
    FormulaFunctionEntry(
      name: "MEAN.GEOM", kind: .statistical, arguments: "number1, [number2], ..."),
    FormulaFunctionEntry(
      name: "MEAN.HARM", kind: .statistical, arguments: "number1, [number2], ..."),
    FormulaFunctionEntry(name: "DEVSQ", kind: .statistical, arguments: "number1, [number2], ..."),
    FormulaFunctionEntry(name: "AVEDEV", kind: .statistical, arguments: "number1, [number2], ..."),
    FormulaFunctionEntry(name: "SKEW", kind: .statistical, arguments: "number1, [number2], ..."),
    FormulaFunctionEntry(name: "SKEW.P", kind: .statistical, arguments: "number1, [number2], ..."),
    FormulaFunctionEntry(name: "KURT", kind: .statistical, arguments: "number1, [number2], ..."),
    FormulaFunctionEntry(name: "TRIMMEAN", kind: .statistical, arguments: "array, percent"),
    FormulaFunctionEntry(
      name: "STANDARDIZE", kind: .statistical,
      arguments: "x, mean, standard_dev"),
    FormulaFunctionEntry(name: "FISHER", kind: .statistical, arguments: "x"),
    FormulaFunctionEntry(name: "FISHERINV", kind: .statistical, arguments: "y"),
    FormulaFunctionEntry(name: "COVARIANCE.S", kind: .statistical, arguments: "array1, array2"),
    FormulaFunctionEntry(name: "COVARIANCE.P", kind: .statistical, arguments: "array1, array2"),
    FormulaFunctionEntry(name: "COVAR", kind: .statistical, arguments: "array1, array2"),
    FormulaFunctionEntry(name: "PEARSON", kind: .statistical, arguments: "array1, array2"),
    FormulaFunctionEntry(name: "RSQ", kind: .statistical, arguments: "known_ys, known_xs"),
    FormulaFunctionEntry(name: "RANK.AVG", kind: .statistical, arguments: "number, ref, [order]"),
    FormulaFunctionEntry(
      name: "PERCENTRANK", kind: .statistical,
      arguments: "array, x, [significance]"),
    FormulaFunctionEntry(
      name: "PERCENTRANK.INC", kind: .statistical,
      arguments: "array, x, [significance]"),
    FormulaFunctionEntry(
      name: "PERCENTRANK.EXC", kind: .statistical,
      arguments: "array, x, [significance]"),
    FormulaFunctionEntry(name: "PERCENTILE.EXC", kind: .statistical, arguments: "array, k"),
    FormulaFunctionEntry(name: "QUARTILE.EXC", kind: .statistical, arguments: "array, quart"),
    FormulaFunctionEntry(
      name: "NORM.DIST", kind: .statistical,
      arguments: "x, mean, standard_dev, cumulative"),
    FormulaFunctionEntry(
      name: "NORMDIST", kind: .statistical,
      arguments: "x, mean, standard_dev, cumulative"),
    FormulaFunctionEntry(name: "NORM.S.DIST", kind: .statistical, arguments: "z, cumulative"),
    FormulaFunctionEntry(name: "NORMSDIST", kind: .statistical, arguments: "z"),
    FormulaFunctionEntry(
      name: "NORM.INV", kind: .statistical,
      arguments: "probability, mean, standard_dev"),
    FormulaFunctionEntry(
      name: "NORMINV", kind: .statistical,
      arguments: "probability, mean, standard_dev"),
    FormulaFunctionEntry(name: "NORM.S.INV", kind: .statistical, arguments: "probability"),
    FormulaFunctionEntry(name: "NORMSINV", kind: .statistical, arguments: "probability"),
    FormulaFunctionEntry(
      name: "REPLACE", kind: .text,
      arguments: "old_text, start_num, num_chars, new_text"),
    FormulaFunctionEntry(name: "FIXED", kind: .text, arguments: "number, [decimals], [no_commas]"),
    FormulaFunctionEntry(name: "DOLLAR", kind: .text, arguments: "number, [decimals]"),
    FormulaFunctionEntry(name: "T", kind: .text, arguments: "value"),
    FormulaFunctionEntry(
      name: "NUMBERVALUE", kind: .text,
      arguments: "text, [decimal_separator], [group_separator]"),
    FormulaFunctionEntry(name: "TIME", kind: .dateTime, arguments: "hour, minute, second"),
    FormulaFunctionEntry(name: "TIMEVALUE", kind: .dateTime, arguments: "time_text"),
    FormulaFunctionEntry(name: "DATEVALUE", kind: .dateTime, arguments: "date_text"),
    FormulaFunctionEntry(
      name: "DAYS360", kind: .dateTime,
      arguments: "start_date, end_date, [method]"),
    FormulaFunctionEntry(name: "N", kind: .logical, arguments: "value"),
    FormulaFunctionEntry(name: "ISNONTEXT", kind: .logical, arguments: "value"),
    FormulaFunctionEntry(name: "TYPE", kind: .logical, arguments: "value"),
    FormulaFunctionEntry(name: "ERROR.TYPE", kind: .logical, arguments: "error_val"),
    FormulaFunctionEntry(name: "SLN", kind: .financial, arguments: "cost, salvage, life"),
    FormulaFunctionEntry(name: "SYD", kind: .financial, arguments: "cost, salvage, life, per"),
    FormulaFunctionEntry(
      name: "DDB", kind: .financial,
      arguments: "cost, salvage, life, period, [factor]"),
    FormulaFunctionEntry(
      name: "DB", kind: .financial,
      arguments: "cost, salvage, life, period, [month]"),
    FormulaFunctionEntry(name: "EFFECT", kind: .financial, arguments: "nominal_rate, npery"),
    FormulaFunctionEntry(name: "NOMINAL", kind: .financial, arguments: "effect_rate, npery"),
    FormulaFunctionEntry(name: "ISPMT", kind: .financial, arguments: "rate, per, nper, pv"),
    FormulaFunctionEntry(
      name: "CUMIPMT", kind: .financial,
      arguments: "rate, nper, pv, start_period, end_period, type"),
    FormulaFunctionEntry(
      name: "CUMPRINC", kind: .financial,
      arguments: "rate, nper, pv, start_period, end_period, type"),
    FormulaFunctionEntry(
      name: "MIRR", kind: .financial,
      arguments: "values, finance_rate, reinvest_rate"),
    FormulaFunctionEntry(name: "TRANSPOSE", kind: .lookup, arguments: "array"),
    // 1.7 batch 7
    FormulaFunctionEntry(
      name: "COUPDAYBS", kind: .financial, arguments: "settlement, maturity, frequency, [basis]"),
    FormulaFunctionEntry(
      name: "COUPDAYS", kind: .financial, arguments: "settlement, maturity, frequency, [basis]"),
    FormulaFunctionEntry(
      name: "COUPDAYSNC", kind: .financial, arguments: "settlement, maturity, frequency, [basis]"),
    FormulaFunctionEntry(
      name: "COUPNCD", kind: .financial, arguments: "settlement, maturity, frequency, [basis]"),
    FormulaFunctionEntry(
      name: "COUPNUM", kind: .financial, arguments: "settlement, maturity, frequency, [basis]"),
    FormulaFunctionEntry(
      name: "COUPPCD", kind: .financial, arguments: "settlement, maturity, frequency, [basis]"),
    FormulaFunctionEntry(
      name: "PRICE", kind: .financial,
      arguments: "settlement, maturity, rate, yld, redemption, frequency, [basis]"),
    FormulaFunctionEntry(
      name: "YIELD", kind: .financial,
      arguments: "settlement, maturity, rate, pr, redemption, frequency, [basis]"),
    FormulaFunctionEntry(
      name: "DURATION", kind: .financial,
      arguments: "settlement, maturity, coupon, yld, frequency, [basis]"),
    FormulaFunctionEntry(
      name: "MDURATION", kind: .financial,
      arguments: "settlement, maturity, coupon, yld, frequency, [basis]"),
    FormulaFunctionEntry(
      name: "ACCRINT", kind: .financial,
      arguments: "issue, first_interest, settlement, rate, par, frequency, [basis], [calc_method]"),
    FormulaFunctionEntry(
      name: "ACCRINTM", kind: .financial, arguments: "issue, settlement, rate, par, [basis]"),
    FormulaFunctionEntry(
      name: "DISC", kind: .financial, arguments: "settlement, maturity, pr, redemption, [basis]"),
    FormulaFunctionEntry(
      name: "INTRATE", kind: .financial,
      arguments: "settlement, maturity, investment, redemption, [basis]"),
    FormulaFunctionEntry(
      name: "RECEIVED", kind: .financial,
      arguments: "settlement, maturity, investment, discount, [basis]"),
    FormulaFunctionEntry(
      name: "PRICEDISC", kind: .financial,
      arguments: "settlement, maturity, discount, redemption, [basis]"),
    FormulaFunctionEntry(
      name: "YIELDDISC", kind: .financial,
      arguments: "settlement, maturity, pr, redemption, [basis]"),
    FormulaFunctionEntry(
      name: "PRICEMAT", kind: .financial,
      arguments: "settlement, maturity, issue, rate, yld, [basis]"),
    FormulaFunctionEntry(
      name: "YIELDMAT", kind: .financial,
      arguments: "settlement, maturity, issue, rate, pr, [basis]"),
    FormulaFunctionEntry(
      name: "TBILLPRICE", kind: .financial, arguments: "settlement, maturity, discount"),
    FormulaFunctionEntry(
      name: "TBILLYIELD", kind: .financial, arguments: "settlement, maturity, pr"),
    FormulaFunctionEntry(
      name: "TBILLEQ", kind: .financial, arguments: "settlement, maturity, discount"),
    FormulaFunctionEntry(
      name: "VDB", kind: .financial,
      arguments: "cost, salvage, life, start_period, end_period, [factor], [no_switch]"),
    FormulaFunctionEntry(
      name: "AMORLINC", kind: .financial,
      arguments: "cost, date_purchased, first_period, salvage, period, rate, [basis]"),
    FormulaFunctionEntry(
      name: "AMORDEGRC", kind: .financial,
      arguments: "cost, date_purchased, first_period, salvage, period, rate, [basis]"),
    FormulaFunctionEntry(name: "FVSCHEDULE", kind: .financial, arguments: "principal, schedule"),
    FormulaFunctionEntry(
      name: "DOLLARDE", kind: .financial, arguments: "fractional_dollar, fraction"),
    FormulaFunctionEntry(name: "DOLLARFR", kind: .financial, arguments: "decimal_dollar, fraction"),
    FormulaFunctionEntry(name: "PDURATION", kind: .financial, arguments: "rate, pv, fv"),
    FormulaFunctionEntry(name: "RRI", kind: .financial, arguments: "nper, pv, fv"),
    FormulaFunctionEntry(
      name: "CONVERT", kind: .engineering, arguments: "number, from_unit, to_unit"),
    FormulaFunctionEntry(
      name: "COMPLEX", kind: .engineering, arguments: "real_num, i_num, [suffix]"),
    FormulaFunctionEntry(name: "BESSELJ", kind: .engineering, arguments: "x, n"),
    FormulaFunctionEntry(name: "BESSELY", kind: .engineering, arguments: "x, n"),
    FormulaFunctionEntry(name: "BESSELI", kind: .engineering, arguments: "x, n"),
    FormulaFunctionEntry(name: "BESSELK", kind: .engineering, arguments: "x, n"),
    FormulaFunctionEntry(name: "IMABS", kind: .engineering, arguments: "inumber"),
    FormulaFunctionEntry(name: "IMAGINARY", kind: .engineering, arguments: "inumber"),
    FormulaFunctionEntry(name: "IMARGUMENT", kind: .engineering, arguments: "inumber"),
    FormulaFunctionEntry(name: "IMCONJUGATE", kind: .engineering, arguments: "inumber"),
    FormulaFunctionEntry(name: "IMCOS", kind: .engineering, arguments: "inumber"),
    FormulaFunctionEntry(name: "IMCOSH", kind: .engineering, arguments: "inumber"),
    FormulaFunctionEntry(name: "IMCOT", kind: .engineering, arguments: "inumber"),
    FormulaFunctionEntry(name: "IMCSC", kind: .engineering, arguments: "inumber"),
    FormulaFunctionEntry(name: "IMCSCH", kind: .engineering, arguments: "inumber"),
    FormulaFunctionEntry(name: "IMEXP", kind: .engineering, arguments: "inumber"),
    FormulaFunctionEntry(name: "IMLN", kind: .engineering, arguments: "inumber"),
    FormulaFunctionEntry(name: "IMLOG10", kind: .engineering, arguments: "inumber"),
    FormulaFunctionEntry(name: "IMLOG2", kind: .engineering, arguments: "inumber"),
    FormulaFunctionEntry(name: "IMREAL", kind: .engineering, arguments: "inumber"),
    FormulaFunctionEntry(name: "IMSEC", kind: .engineering, arguments: "inumber"),
    FormulaFunctionEntry(name: "IMSECH", kind: .engineering, arguments: "inumber"),
    FormulaFunctionEntry(name: "IMSIN", kind: .engineering, arguments: "inumber"),
    FormulaFunctionEntry(name: "IMSINH", kind: .engineering, arguments: "inumber"),
    FormulaFunctionEntry(name: "IMSQRT", kind: .engineering, arguments: "inumber"),
    FormulaFunctionEntry(name: "IMTAN", kind: .engineering, arguments: "inumber"),
    FormulaFunctionEntry(name: "IMDIV", kind: .engineering, arguments: "inumber1, inumber2"),
    FormulaFunctionEntry(name: "IMSUB", kind: .engineering, arguments: "inumber1, inumber2"),
    FormulaFunctionEntry(name: "IMPOWER", kind: .engineering, arguments: "inumber, number"),
    FormulaFunctionEntry(
      name: "IMPRODUCT", kind: .engineering, arguments: "inumber1, [inumber2], ..."),
    FormulaFunctionEntry(name: "IMSUM", kind: .engineering, arguments: "inumber1, [inumber2], ..."),
    // 1.7 batch 6
    FormulaFunctionEntry(
      name: "LAMBDA", kind: .logical, arguments: "[parameter1, ...], calculation"),
    FormulaFunctionEntry(name: "MAP", kind: .logical, arguments: "array1, [array2, ...], lambda"),
    FormulaFunctionEntry(
      name: "REDUCE", kind: .logical, arguments: "[initial_value], array, lambda"),
    FormulaFunctionEntry(name: "SCAN", kind: .logical, arguments: "[initial_value], array, lambda"),
    FormulaFunctionEntry(name: "BYROW", kind: .logical, arguments: "array, lambda"),
    FormulaFunctionEntry(name: "BYCOL", kind: .logical, arguments: "array, lambda"),
    FormulaFunctionEntry(name: "MAKEARRAY", kind: .logical, arguments: "rows, columns, lambda"),
    FormulaFunctionEntry(name: "ISOMITTED", kind: .information, arguments: "argument"),
    FormulaFunctionEntry(
      name: "EXPAND", kind: .lookup, arguments: "array, rows, [columns], [pad_with]"),
    FormulaFunctionEntry(
      name: "GROUPBY", kind: .lookup,
      arguments:
        "row_fields, values, function, [field_headers], [total_depth], [sort_order], [filter_array]"
    ),
    FormulaFunctionEntry(
      name: "PIVOTBY", kind: .lookup,
      arguments:
        "row_fields, col_fields, values, function, [field_headers], [row_total_depth], [row_sort_order], [col_total_depth], [col_sort_order], [filter_array]"
    ),
    // 1.7 batch 5
    FormulaFunctionEntry(
      name: "BETA.DIST", kind: .statistical, arguments: "x, alpha, beta, cumulative, [A], [B]"),
    FormulaFunctionEntry(
      name: "BETA.INV", kind: .statistical, arguments: "probability, alpha, beta, [A], [B]"),
    FormulaFunctionEntry(
      name: "BETADIST", kind: .statistical, arguments: "x, alpha, beta, [A], [B]"),
    FormulaFunctionEntry(
      name: "BETAINV", kind: .statistical, arguments: "probability, alpha, beta, [A], [B]"),
    FormulaFunctionEntry(
      name: "BINOM.DIST", kind: .statistical,
      arguments: "number_s, trials, probability_s, cumulative"),
    FormulaFunctionEntry(
      name: "BINOMDIST", kind: .statistical,
      arguments: "number_s, trials, probability_s, cumulative"),
    FormulaFunctionEntry(
      name: "BINOM.DIST.RANGE", kind: .statistical,
      arguments: "trials, probability_s, number_s, [number_s2]"),
    FormulaFunctionEntry(
      name: "BINOM.INV", kind: .statistical, arguments: "trials, probability_s, alpha"),
    FormulaFunctionEntry(
      name: "CRITBINOM", kind: .statistical, arguments: "trials, probability_s, alpha"),
    FormulaFunctionEntry(
      name: "NEGBINOM.DIST", kind: .statistical,
      arguments: "number_f, number_s, probability_s, cumulative"),
    FormulaFunctionEntry(
      name: "NEGBINOMDIST", kind: .statistical, arguments: "number_f, number_s, probability_s"),
    FormulaFunctionEntry(
      name: "HYPGEOM.DIST", kind: .statistical,
      arguments: "sample_s, number_sample, population_s, number_pop, cumulative"),
    FormulaFunctionEntry(
      name: "HYPGEOMDIST", kind: .statistical,
      arguments: "sample_s, number_sample, population_s, number_pop"),
    FormulaFunctionEntry(
      name: "POISSON.DIST", kind: .statistical, arguments: "x, mean, cumulative"),
    FormulaFunctionEntry(name: "POISSON", kind: .statistical, arguments: "x, mean, cumulative"),
    FormulaFunctionEntry(
      name: "EXPON.DIST", kind: .statistical, arguments: "x, lambda, cumulative"),
    FormulaFunctionEntry(name: "EXPONDIST", kind: .statistical, arguments: "x, lambda, cumulative"),
    FormulaFunctionEntry(
      name: "WEIBULL.DIST", kind: .statistical, arguments: "x, alpha, beta, cumulative"),
    FormulaFunctionEntry(
      name: "WEIBULL", kind: .statistical, arguments: "x, alpha, beta, cumulative"),
    FormulaFunctionEntry(
      name: "GAMMA.DIST", kind: .statistical, arguments: "x, alpha, beta, cumulative"),
    FormulaFunctionEntry(
      name: "GAMMADIST", kind: .statistical, arguments: "x, alpha, beta, cumulative"),
    FormulaFunctionEntry(
      name: "GAMMA.INV", kind: .statistical, arguments: "probability, alpha, beta"),
    FormulaFunctionEntry(
      name: "GAMMAINV", kind: .statistical, arguments: "probability, alpha, beta"),
    FormulaFunctionEntry(
      name: "CHISQ.DIST", kind: .statistical, arguments: "x, deg_freedom, cumulative"),
    FormulaFunctionEntry(name: "CHISQ.DIST.RT", kind: .statistical, arguments: "x, deg_freedom"),
    FormulaFunctionEntry(name: "CHIDIST", kind: .statistical, arguments: "x, deg_freedom"),
    FormulaFunctionEntry(
      name: "CHISQ.INV", kind: .statistical, arguments: "probability, deg_freedom"),
    FormulaFunctionEntry(
      name: "CHISQ.INV.RT", kind: .statistical, arguments: "probability, deg_freedom"),
    FormulaFunctionEntry(name: "CHIINV", kind: .statistical, arguments: "probability, deg_freedom"),
    FormulaFunctionEntry(
      name: "CHISQ.TEST", kind: .statistical, arguments: "actual_range, expected_range"),
    FormulaFunctionEntry(
      name: "CHITEST", kind: .statistical, arguments: "actual_range, expected_range"),
    FormulaFunctionEntry(
      name: "F.DIST", kind: .statistical, arguments: "x, deg_freedom1, deg_freedom2, cumulative"),
    FormulaFunctionEntry(
      name: "F.DIST.RT", kind: .statistical, arguments: "x, deg_freedom1, deg_freedom2"),
    FormulaFunctionEntry(
      name: "FDIST", kind: .statistical, arguments: "x, deg_freedom1, deg_freedom2"),
    FormulaFunctionEntry(
      name: "F.INV", kind: .statistical, arguments: "probability, deg_freedom1, deg_freedom2"),
    FormulaFunctionEntry(
      name: "F.INV.RT", kind: .statistical, arguments: "probability, deg_freedom1, deg_freedom2"),
    FormulaFunctionEntry(
      name: "FINV", kind: .statistical, arguments: "probability, deg_freedom1, deg_freedom2"),
    FormulaFunctionEntry(name: "F.TEST", kind: .statistical, arguments: "array1, array2"),
    FormulaFunctionEntry(name: "FTEST", kind: .statistical, arguments: "array1, array2"),
    FormulaFunctionEntry(
      name: "LOGNORM.DIST", kind: .statistical, arguments: "x, mean, standard_dev, cumulative"),
    FormulaFunctionEntry(
      name: "LOGNORMDIST", kind: .statistical, arguments: "x, mean, standard_dev"),
    FormulaFunctionEntry(
      name: "LOGNORM.INV", kind: .statistical, arguments: "probability, mean, standard_dev"),
    FormulaFunctionEntry(
      name: "LOGINV", kind: .statistical, arguments: "probability, mean, standard_dev"),
    FormulaFunctionEntry(
      name: "T.DIST", kind: .statistical, arguments: "x, deg_freedom, cumulative"),
    FormulaFunctionEntry(name: "T.DIST.2T", kind: .statistical, arguments: "x, deg_freedom"),
    FormulaFunctionEntry(name: "T.DIST.RT", kind: .statistical, arguments: "x, deg_freedom"),
    FormulaFunctionEntry(name: "TDIST", kind: .statistical, arguments: "x, deg_freedom, tails"),
    FormulaFunctionEntry(name: "T.INV", kind: .statistical, arguments: "probability, deg_freedom"),
    FormulaFunctionEntry(
      name: "T.INV.2T", kind: .statistical, arguments: "probability, deg_freedom"),
    FormulaFunctionEntry(name: "TINV", kind: .statistical, arguments: "probability, deg_freedom"),
    FormulaFunctionEntry(
      name: "T.TEST", kind: .statistical, arguments: "array1, array2, tails, type"),
    FormulaFunctionEntry(
      name: "TTEST", kind: .statistical, arguments: "array1, array2, tails, type"),
    FormulaFunctionEntry(name: "Z.TEST", kind: .statistical, arguments: "array, x, [sigma]"),
    FormulaFunctionEntry(name: "ZTEST", kind: .statistical, arguments: "array, x, [sigma]"),
    FormulaFunctionEntry(
      name: "CONFIDENCE.NORM", kind: .statistical, arguments: "alpha, standard_dev, size"),
    FormulaFunctionEntry(
      name: "CONFIDENCE", kind: .statistical, arguments: "alpha, standard_dev, size"),
    FormulaFunctionEntry(
      name: "CONFIDENCE.T", kind: .statistical, arguments: "alpha, standard_dev, size"),
    FormulaFunctionEntry(
      name: "PROB", kind: .statistical, arguments: "x_range, prob_range, lower_limit, [upper_limit]"
    ),
    FormulaFunctionEntry(name: "STEYX", kind: .statistical, arguments: "known_y's, known_x's"),
    FormulaFunctionEntry(
      name: "FREQUENCY", kind: .statistical, arguments: "data_array, bins_array"),
    FormulaFunctionEntry(
      name: "MODE.MULT", kind: .statistical, arguments: "number1, [number2], ..."),
    FormulaFunctionEntry(
      name: "LINEST", kind: .statistical, arguments: "known_y's, [known_x's], [const], [stats]"),
    FormulaFunctionEntry(
      name: "LOGEST", kind: .statistical, arguments: "known_y's, [known_x's], [const], [stats]"),
    FormulaFunctionEntry(
      name: "TREND", kind: .statistical, arguments: "known_y's, [known_x's], [new_x's], [const]"),
    FormulaFunctionEntry(
      name: "GROWTH", kind: .statistical, arguments: "known_y's, [known_x's], [new_x's], [const]"),
    FormulaFunctionEntry(name: "MMULT", kind: .math, arguments: "array1, array2"),
    FormulaFunctionEntry(name: "MINVERSE", kind: .math, arguments: "array"),
    FormulaFunctionEntry(name: "MDETERM", kind: .math, arguments: "array"),
    FormulaFunctionEntry(name: "MUNIT", kind: .math, arguments: "dimension"),
    // 1.7 batch 4
    FormulaFunctionEntry(
      name: "SUBTOTAL", kind: .math, arguments: "function_num, ref1, [ref2], ..."),
    FormulaFunctionEntry(
      name: "AGGREGATE", kind: .math, arguments: "function_num, options, ref1, [ref2 or k], ..."),
    FormulaFunctionEntry(name: "DAVERAGE", kind: .database, arguments: "database, field, criteria"),
    FormulaFunctionEntry(name: "DCOUNT", kind: .database, arguments: "database, [field], criteria"),
    FormulaFunctionEntry(
      name: "DCOUNTA", kind: .database, arguments: "database, [field], criteria"),
    FormulaFunctionEntry(name: "DGET", kind: .database, arguments: "database, field, criteria"),
    FormulaFunctionEntry(name: "DMAX", kind: .database, arguments: "database, field, criteria"),
    FormulaFunctionEntry(name: "DMIN", kind: .database, arguments: "database, field, criteria"),
    FormulaFunctionEntry(name: "DPRODUCT", kind: .database, arguments: "database, field, criteria"),
    FormulaFunctionEntry(name: "DSTDEV", kind: .database, arguments: "database, field, criteria"),
    FormulaFunctionEntry(name: "DSTDEVP", kind: .database, arguments: "database, field, criteria"),
    FormulaFunctionEntry(name: "DSUM", kind: .database, arguments: "database, field, criteria"),
    FormulaFunctionEntry(name: "DVAR", kind: .database, arguments: "database, field, criteria"),
    FormulaFunctionEntry(name: "DVARP", kind: .database, arguments: "database, field, criteria"),
    FormulaFunctionEntry(
      name: "NETWORKDAYS.INTL", kind: .dateTime,
      arguments: "start_date, end_date, [weekend], [holidays]"),
    FormulaFunctionEntry(
      name: "WORKDAY.INTL", kind: .dateTime, arguments: "start_date, days, [weekend], [holidays]"),
    FormulaFunctionEntry(name: "SHEET", kind: .information, arguments: "[value]"),
    FormulaFunctionEntry(name: "SHEETS", kind: .information, arguments: "[reference]"),
    FormulaFunctionEntry(name: "FORMULATEXT", kind: .lookup, arguments: "reference"),
    FormulaFunctionEntry(name: "AREAS", kind: .lookup, arguments: "reference"),
    FormulaFunctionEntry(name: "COT", kind: .math, arguments: "number"),
    FormulaFunctionEntry(name: "CSC", kind: .math, arguments: "number"),
    FormulaFunctionEntry(name: "SEC", kind: .math, arguments: "number"),
    FormulaFunctionEntry(name: "COTH", kind: .math, arguments: "number"),
    FormulaFunctionEntry(name: "CSCH", kind: .math, arguments: "number"),
    FormulaFunctionEntry(name: "SECH", kind: .math, arguments: "number"),
    FormulaFunctionEntry(name: "ACOT", kind: .math, arguments: "number"),
    FormulaFunctionEntry(name: "ACOTH", kind: .math, arguments: "number"),
    FormulaFunctionEntry(name: "CEILING.PRECISE", kind: .math, arguments: "number, [significance]"),
    FormulaFunctionEntry(name: "ISO.CEILING", kind: .math, arguments: "number, [significance]"),
    FormulaFunctionEntry(name: "FLOOR.PRECISE", kind: .math, arguments: "number, [significance]"),
    FormulaFunctionEntry(name: "COMBINA", kind: .math, arguments: "number, number_chosen"),
    FormulaFunctionEntry(
      name: "PERMUTATIONA", kind: .statistical, arguments: "number, number_chosen"),
    FormulaFunctionEntry(name: "FACTDOUBLE", kind: .math, arguments: "number"),
    FormulaFunctionEntry(name: "MULTINOMIAL", kind: .math, arguments: "number1, [number2], ..."),
    FormulaFunctionEntry(name: "SERIESSUM", kind: .math, arguments: "x, n, m, coefficients"),
    FormulaFunctionEntry(name: "SUMX2MY2", kind: .math, arguments: "array_x, array_y"),
    FormulaFunctionEntry(name: "SUMX2PY2", kind: .math, arguments: "array_x, array_y"),
    FormulaFunctionEntry(name: "SUMXMY2", kind: .math, arguments: "array_x, array_y"),
    FormulaFunctionEntry(name: "GAMMA", kind: .statistical, arguments: "x"),
    FormulaFunctionEntry(name: "GAMMALN", kind: .statistical, arguments: "x"),
    FormulaFunctionEntry(name: "GAMMALN.PRECISE", kind: .statistical, arguments: "x"),
    FormulaFunctionEntry(name: "GAUSS", kind: .statistical, arguments: "z"),
    FormulaFunctionEntry(name: "PHI", kind: .statistical, arguments: "x"),
    FormulaFunctionEntry(name: "ROMAN", kind: .math, arguments: "number, [form]"),
    FormulaFunctionEntry(name: "ARABIC", kind: .math, arguments: "text"),
    FormulaFunctionEntry(name: "BASE", kind: .math, arguments: "number, radix, [min_length]"),
    FormulaFunctionEntry(name: "DECIMAL", kind: .math, arguments: "text, radix"),
    FormulaFunctionEntry(name: "BIN2DEC", kind: .engineering, arguments: "number"),
    FormulaFunctionEntry(name: "BIN2HEX", kind: .engineering, arguments: "number, [places]"),
    FormulaFunctionEntry(name: "BIN2OCT", kind: .engineering, arguments: "number, [places]"),
    FormulaFunctionEntry(name: "OCT2BIN", kind: .engineering, arguments: "number, [places]"),
    FormulaFunctionEntry(name: "OCT2DEC", kind: .engineering, arguments: "number"),
    FormulaFunctionEntry(name: "OCT2HEX", kind: .engineering, arguments: "number, [places]"),
    FormulaFunctionEntry(name: "HEX2BIN", kind: .engineering, arguments: "number, [places]"),
    FormulaFunctionEntry(name: "HEX2DEC", kind: .engineering, arguments: "number"),
    FormulaFunctionEntry(name: "HEX2OCT", kind: .engineering, arguments: "number, [places]"),
    FormulaFunctionEntry(name: "DEC2BIN", kind: .engineering, arguments: "number, [places]"),
    FormulaFunctionEntry(name: "DEC2HEX", kind: .engineering, arguments: "number, [places]"),
    FormulaFunctionEntry(name: "DEC2OCT", kind: .engineering, arguments: "number, [places]"),
    FormulaFunctionEntry(name: "BITAND", kind: .engineering, arguments: "number1, number2"),
    FormulaFunctionEntry(name: "BITOR", kind: .engineering, arguments: "number1, number2"),
    FormulaFunctionEntry(name: "BITXOR", kind: .engineering, arguments: "number1, number2"),
    FormulaFunctionEntry(name: "BITLSHIFT", kind: .engineering, arguments: "number, shift_amount"),
    FormulaFunctionEntry(name: "BITRSHIFT", kind: .engineering, arguments: "number, shift_amount"),
    FormulaFunctionEntry(name: "DELTA", kind: .engineering, arguments: "number1, [number2]"),
    FormulaFunctionEntry(name: "GESTEP", kind: .engineering, arguments: "number, [step]"),
    FormulaFunctionEntry(name: "ERF", kind: .engineering, arguments: "lower_limit, [upper_limit]"),
    FormulaFunctionEntry(name: "ERF.PRECISE", kind: .engineering, arguments: "x"),
    FormulaFunctionEntry(name: "ERFC", kind: .engineering, arguments: "x"),
    FormulaFunctionEntry(name: "ERFC.PRECISE", kind: .engineering, arguments: "x"),
    FormulaFunctionEntry(name: "LENB", kind: .text, arguments: "text"),
    FormulaFunctionEntry(name: "LEFTB", kind: .text, arguments: "text, [num_bytes]"),
    FormulaFunctionEntry(name: "RIGHTB", kind: .text, arguments: "text, [num_bytes]"),
    FormulaFunctionEntry(name: "MIDB", kind: .text, arguments: "text, start_num, num_bytes"),
    FormulaFunctionEntry(
      name: "FINDB", kind: .text, arguments: "find_text, within_text, [start_num]"),
    FormulaFunctionEntry(
      name: "SEARCHB", kind: .text, arguments: "find_text, within_text, [start_num]"),
    FormulaFunctionEntry(
      name: "REPLACEB", kind: .text, arguments: "old_text, start_num, num_bytes, new_text"),
    FormulaFunctionEntry(name: "ASC", kind: .text, arguments: "text"),
    FormulaFunctionEntry(name: "DBCS", kind: .text, arguments: "text"),
    FormulaFunctionEntry(name: "VALUETOTEXT", kind: .text, arguments: "value, [format]"),
    FormulaFunctionEntry(name: "ARRAYTOTEXT", kind: .text, arguments: "array, [format]"),
    FormulaFunctionEntry(name: "BAHTTEXT", kind: .text, arguments: "number"),
    FormulaFunctionEntry(name: "ENCODEURL", kind: .text, arguments: "text"),
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
