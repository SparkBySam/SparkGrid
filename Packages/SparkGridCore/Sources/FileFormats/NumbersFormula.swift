import Formula
import Foundation
import GridCore

/// A Numbers formula as Spark Grid writes it. Numbers keeps a formula as nodes in postfix order
/// (`TSCE.ASTNodeArrayArchive`): operands first, then the operator or function that takes them.
/// Cell references are relative to the formula's cell unless marked absolute. Nil when a node or
/// function has no Spark Grid equivalent; the cell then keeps the value Numbers saved.
nonisolated enum NumbersFormula {
  /// What a reference needs to know about a table: the sheet it became, and its size and headers.
  /// Numbers leaves header rows and columns out of a whole row or column.
  struct Table {
    var sheetName: String
    var rows: Int
    var columns: Int
    var headerRows: Int
    var headerColumns: Int

    init(_ sheetName: String, model: ProtoMessage) {
      self.sheetName = sheetName
      rows = max(Int(model.varint(6) ?? 1), 1)
      columns = max(Int(model.varint(7) ?? 1), 1)
      headerRows = Int(model.varint(9) ?? 0)
      headerColumns = Int(model.varint(10) ?? 0)
    }

    init(sheetName: String, rows: Int, columns: Int, headerRows: Int, headerColumns: Int) {
      self.sheetName = sheetName
      self.rows = rows
      self.columns = columns
      self.headerRows = headerRows
      self.headerColumns = headerColumns
    }
  }

  private struct Part {
    var text: String
    /// How tightly it binds: 1 comparison, 2 `&`, 3 `+ -`, 4 `* /`, 5 `^`, 6 sign and `%`,
    /// 9 a single value, reference or call.
    var precedence: Int
  }

  private static let binary: [UInt64: (String, Int)] = [
    1: ("+", 3), 2: ("-", 3), 3: ("*", 4), 4: ("/", 4), 5: ("^", 5), 6: ("&", 2),
    7: (">", 1), 8: (">=", 1), 9: ("<", 1), 10: ("<=", 1), 11: ("=", 1), 12: ("<>", 1),
  ]

  static func text(
    _ nodes: [ProtoMessage], host: CellAddress, table: Table, tables: [String: Table]
  ) -> String? {
    var stack: [Part] = []
    for node in nodes {
      guard let type = node.varint(1) else { return nil }
      if let (op, precedence) = binary[type] {
        guard stack.count >= 2 else { return nil }
        let right = stack.removeLast()
        let left = stack.removeLast()
        let l = left.precedence < precedence ? "(\(left.text))" : left.text
        let r = right.precedence <= precedence ? "(\(right.text))" : right.text
        stack.append(Part(text: l + op + r, precedence: precedence))
        continue
      }
      switch type {
      case 13, 14:  // minus or plus sign
        guard let value = stack.popLast() else { return nil }
        let inner = value.precedence < 6 ? "(\(value.text))" : value.text
        stack.append(Part(text: (type == 13 ? "-" : "+") + inner, precedence: 6))
      case 15:  // percent
        guard let value = stack.popLast() else { return nil }
        let inner = value.precedence < 6 ? "(\(value.text))" : value.text
        stack.append(Part(text: inner + "%", precedence: 6))
      case 16:  // function: its index (2) and argument count (3)
        guard let index = node.varint(2), let name = functionNames[index],
          FormulaFunctions.all.contains(name)
        else { return nil }
        let count = Int(node.varint(3) ?? 0)
        guard stack.count >= count else { return nil }
        let args = stack.suffix(count).map(\.text)
        stack.removeLast(count)
        stack.append(Part(text: "\(name)(\(args.joined(separator: ",")))", precedence: 9))
      case 17:  // number
        guard let value = node.double(4) else { return nil }
        stack.append(Part(text: number(value), precedence: 9))
      case 18:  // true or false
        stack.append(Part(text: (node.varint(5) ?? 0) != 0 ? "TRUE" : "FALSE", precedence: 9))
      case 19:  // text
        let text = node.string(6) ?? ""
        stack.append(
          Part(text: "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\"", precedence: 9)
        )
      case 22:  // an argument left empty, as in IF(A2>1,,2)
        stack.append(Part(text: "", precedence: 9))
      case 25:  // parentheses around one value; more than one is an array
        guard (node.varint(13) ?? 1) == 1, let value = stack.popLast() else { return nil }
        stack.append(Part(text: "(\(value.text))", precedence: 9))
      case 34, 35:  // start and end of a lazily calculated argument, such as IF's branches
        continue
      case 30:  // a reference that no longer points anywhere
        stack.append(Part(text: "#REF!", precedence: 9))
      case 36:
        guard let ref = cellReference(node, host: host, table: table, tables: tables) else {
          return nil
        }
        stack.append(Part(text: ref, precedence: 9))
      case 67:
        guard let ref = rangeReference(node, host: host, table: table, tables: tables) else {
          return nil
        }
        stack.append(Part(text: ref, precedence: 9))
      default:
        return nil
      }
    }
    guard stack.count == 1 else { return nil }
    return stack[0].text
  }

  static func number(_ value: Double) -> String {
    if value == value.rounded(), abs(value) < 1e15 { return String(Int64(value)) }
    return "\(value)"
  }

  // MARK: References

  /// The table a reference points at (field 28 names another one) and the sheet prefix it needs.
  private static func target(_ node: ProtoMessage, table: Table, tables: [String: Table])
    -> (table: Table, prefix: String)?
  {
    guard let uid = node.message(28)?.message(1) else { return (table, "") }
    guard let other = tables[NumbersImporter.tableUID(uid)] else { return nil }
    return (other, A1Reference.encodeSheetName(other.sheetName) + "!")
  }

  /// A whole column, as Numbers means it: the table's rows below its header rows.
  private static func wholeColumn(_ c1: String, _ c2: String, in table: Table) -> String {
    let first = min(table.headerRows, table.rows - 1) + 1
    return "\(c1)\(first):\(c2)\(table.rows)"
  }

  /// A whole row, as Numbers means it: the table's columns after its header columns.
  private static func wholeRow(_ r1: String, _ r2: String, in table: Table) -> String {
    let first = A1Notation.columnLabel(for: min(table.headerColumns, table.columns - 1))
    let last = A1Notation.columnLabel(for: table.columns - 1)
    return "\(first)\(r1):\(last)\(r2)"
  }

  /// One cell, or a whole row or column (node 36): column (26) and row (27), each in zigzag form,
  /// an offset from the formula's cell, or an index when marked absolute (2).
  private static func cellReference(
    _ node: ProtoMessage, host: CellAddress, table: Table, tables: [String: Table]
  ) -> String? {
    guard let (target, prefix) = target(node, table: table, tables: tables) else { return nil }
    func axis(_ field: Int, base: Int) -> (index: Int, absolute: Bool)? {
      guard let part = node.message(field), let raw = part.varint(1) else { return nil }
      let absolute = (part.varint(2) ?? 0) != 0
      return (absolute ? zigzag(raw) : base + zigzag(raw), absolute)
    }
    let col = axis(26, base: host.col)
    let row = axis(27, base: host.row)
    switch (col, row) {
    case (let col?, let row?):
      guard col.index >= 0, row.index >= 0 else { return nil }
      return prefix + column(col.index, col.absolute) + rowText(row.index, row.absolute)
    case (let col?, nil):
      guard col.index >= 0 else { return nil }
      let c = column(col.index, col.absolute)
      return prefix + wholeColumn(c, c, in: target)
    case (nil, let row?):
      guard row.index >= 0 else { return nil }
      let r = String(row.index + 1)
      return prefix + wholeRow(r, r, in: target)
    default:
      return nil
    }
  }

  /// A range (node 67). Field 33 says which corners are absolute (1 top row, 2 left column,
  /// 3 bottom row, 4 right column); field 40 lists the relative columns (1) and rows (2) as
  /// offsets, then the absolute columns (3) and rows (4) as indexes, start before end. A side with
  /// no columns, or the largest column, spans every column.
  private static func rangeReference(
    _ node: ProtoMessage, host: CellAddress, table: Table, tables: [String: Table]
  ) -> String? {
    guard let (target, prefix) = target(node, table: table, tables: tables),
      let parts = node.message(40)
    else { return nil }
    let flags = node.message(33)
    func flag(_ field: Int) -> Bool { (flags?.varint(field) ?? 0) != 0 }
    func values(_ field: Int) -> [Int] {
      guard let m = parts.message(field) else { return [] }
      return [m.varint(1), m.varint(2)].compactMap { $0.map { Int(Int64(bitPattern: $0)) } }
    }
    func span(relative: [Int], absolute: [Int], startAbsolute: Bool, endAbsolute: Bool, base: Int)
      -> (Int, Bool, Int, Bool)?
    {
      var rel = relative[...]
      var abs = absolute[...]
      func next(_ isAbsolute: Bool, last: Bool) -> Int? {
        if isAbsolute {
          if let v = abs.first {
            if !last || abs.count > 1 { abs = abs.dropFirst() }
            return v
          }
          return nil
        }
        if let v = rel.first {
          if !last || rel.count > 1 { rel = rel.dropFirst() }
          return base + v
        }
        return nil
      }
      guard let start = next(startAbsolute, last: false) else { return nil }
      // One value of a kind serves both ends when they are the same.
      let end = next(endAbsolute, last: true) ?? start
      return (start, startAbsolute, end, endAbsolute)
    }
    let absCols = values(3)
    let wholeRows =
      (values(1).isEmpty && absCols.isEmpty) || absCols.contains(where: { $0 >= 16_383 })
    let absRows = values(4)
    let wholeColumns =
      (values(2).isEmpty && absRows.isEmpty) || absRows.contains(where: { $0 >= 1_048_575 })
    let rows = span(
      relative: values(2), absolute: absRows, startAbsolute: flag(1), endAbsolute: flag(3),
      base: host.row)
    let cols = span(
      relative: values(1), absolute: absCols, startAbsolute: flag(2), endAbsolute: flag(4),
      base: host.col)
    if wholeRows, !wholeColumns, let rows {
      guard rows.0 >= 0, rows.2 >= 0 else { return nil }
      return prefix + wholeRow(String(rows.0 + 1), String(rows.2 + 1), in: target)
    }
    if wholeColumns, !wholeRows, let cols {
      guard cols.0 >= 0, cols.2 >= 0 else { return nil }
      return prefix + wholeColumn(column(cols.0, cols.1), column(cols.2, cols.3), in: target)
    }
    guard let rows, let cols, rows.0 >= 0, rows.2 >= 0, cols.0 >= 0, cols.2 >= 0 else {
      return nil
    }
    return prefix + column(cols.0, cols.1) + rowText(rows.0, rows.1) + ":"
      + column(cols.2, cols.3) + rowText(rows.2, rows.3)
  }

  private static func zigzag(_ raw: UInt64) -> Int {
    Int(Int64(bitPattern: (raw >> 1) ^ (0 &- (raw & 1))))
  }

  private static func column(_ index: Int, _ absolute: Bool) -> String {
    (absolute ? "$" : "") + A1Notation.columnLabel(for: index)
  }

  private static func rowText(_ index: Int, _ absolute: Bool) -> String {
    (absolute ? "$" : "") + String(index + 1)
  }

  /// Numbers' function numbers, read from formulas Numbers 15.4 saved, one per function Spark
  /// Grid has. Functions Numbers lacks (IFNA, TEXT, STDEV.S and others) are not here.
  static let functionNames: [UInt64: String] = [
    1: "ABS",
    7: "AND",
    15: "AVERAGE",
    17: "CEILING",
    18: "CHAR",
    19: "CHOOSE",
    20: "CLEAN",
    21: "CODE",
    22: "COLUMN",
    23: "COLUMNS",
    25: "CONCATENATE",
    27: "CORREL",
    30: "COUNT",
    31: "COUNTA",
    32: "COUNTBLANK",
    33: "COUNTIF",
    39: "DATE",
    40: "DATEDIF",
    41: "DAY",
    47: "EDATE",
    48: "EVEN",
    49: "EXACT",
    50: "EXP",
    51: "FACT",
    53: "FIND",
    55: "FLOOR",
    56: "FORECAST",
    57: "FV",
    58: "GCD",
    59: "HLOOKUP",
    60: "HOUR",
    61: "HYPERLINK",
    62: "IF",
    63: "INDEX",
    65: "INT",
    66: "INTERCEPT",
    67: "IPMT",
    68: "IRR",
    69: "ISBLANK",
    70: "ISERROR",
    71: "ISEVEN",
    72: "ISODD",
    74: "LARGE",
    75: "LCM",
    76: "LEFT",
    77: "LEN",
    78: "LN",
    79: "LOG",
    80: "LOG10",
    82: "LOWER",
    83: "MATCH",
    84: "MAX",
    86: "MEDIAN",
    87: "MID",
    88: "MIN",
    90: "MINUTE",
    92: "MOD",
    93: "MODE",
    94: "MONTH",
    95: "MROUND",
    96: "NOT",
    97: "NOW",
    98: "NPER",
    99: "NPV",
    100: "ODD",
    102: "OR",
    103: "PERCENTILE",
    104: "PI",
    105: "PMT",
    107: "POWER",
    108: "PPMT",
    113: "PRODUCT",
    114: "PROPER",
    115: "PV",
    120: "RANK",
    121: "RATE",
    123: "REPT",
    124: "RIGHT",
    126: "ROUND",
    127: "ROUNDDOWN",
    128: "ROUNDUP",
    129: "ROW",
    130: "ROWS",
    131: "SEARCH",
    132: "SECOND",
    133: "SIGN",
    137: "SLOPE",
    138: "SMALL",
    139: "SQRT",
    140: "STDEV",
    142: "STDEVP",
    144: "SUBSTITUTE",
    145: "SUMIF",
    146: "SUMPRODUCT",
    147: "SUMSQ",
    154: "TODAY",
    155: "TRIM",
    157: "TRUNC",
    158: "UPPER",
    159: "VALUE",
    160: "VAR",
    162: "VARP",
    165: "VLOOKUP",
    166: "WEEKDAY",
    167: "YEAR",
    168: "SUM",
    203: "EOMONTH",
    204: "WORKDAY",
    206: "WEEKNUM",
    231: "SUMIFS",
    232: "AVERAGEIFS",
    233: "COUNTIFS",
    234: "AVERAGEIF",
    235: "IFERROR",
    249: "QUARTILE",
    260: "NETWORKDAYS",
    304: "ISNUMBER",
    305: "ISTEXT",
    309: "MAXIFS",
    310: "MINIFS",
    311: "XIRR",
    312: "XNPV",
    313: "IFS",
    314: "XLOOKUP",
    315: "XMATCH",
    318: "TEXTBEFORE",
    320: "TEXTAFTER",
    325: "GETPIVOTDATA",
    328: "TEXTJOIN",
    329: "CONCAT",
    335: "ISOWEEKNUM",
    336: "SWITCH",
    338: "SEQUENCE",
    342: "FILTER",
    343: "SORT",
    344: "SORTBY",
    345: "UNIQUE",
    382: "XOR",
    389: "DAYS",
  ]
}
