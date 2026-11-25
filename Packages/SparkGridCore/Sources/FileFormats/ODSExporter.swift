import Formula
import Foundation
import GridCore
import Model
import NumberFormat
import ZIPFoundation

/// Saves a workbook as an OpenDocument spreadsheet (.ods), the format LibreOffice and others use
/// (Sam, Nov 20: "saving as .ods"). Every sheet goes in: values, formulas in OpenFormula with
/// their results, number formats, bold, italic, underline, strikethrough, colors, fonts,
/// alignment, wrapping, borders, merged cells, column widths, row heights, hidden rows and
/// columns, and named ranges. Charts, pictures, comments, conditional formatting, data
/// validation, filters and sparklines are not written yet.
public nonisolated enum ODSExporter {
  public enum ExportError: Error, LocalizedError {
    case couldNotWrite

    public var errorDescription: String? { "Spark Grid could not write the .ods file." }
  }

  public static func exportWorkbook(_ workbook: Workbook) throws -> Data {
    var styles = StyleCatalog()
    var tables = ""
    for sheet in workbook.sheets {
      tables += tableXML(sheet, styles: &styles)
    }
    let parts: [String] = [
      #"<?xml version="1.0" encoding="UTF-8"?>"#,
      "<office:document-content \(namespaces) office:version=\"1.3\">",
      "<office:automatic-styles>\(styles.xml)</office:automatic-styles>",
      "<office:body><office:spreadsheet>\(tables)",
      namedExpressionsXML(workbook), "</office:spreadsheet></office:body>",
      "</office:document-content>",
    ]
    let content = parts.joined()
    return try package(content: Data(content.utf8))
  }

  // MARK: - Package

  static let mimeType = "application/vnd.oasis.opendocument.spreadsheet"

  static let namespaces =
    #"xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" "#
    + #"xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0" "#
    + #"xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" "#
    + #"xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" "#
    + #"xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0" "#
    + #"xmlns:number="urn:oasis:names:tc:opendocument:xmlns:datastyle:1.0" "#
    + #"xmlns:of="urn:oasis:names:tc:opendocument:xmlns:of:1.2" "#
    + #"xmlns:meta="urn:oasis:names:tc:opendocument:xmlns:meta:1.0""#

  /// The `mimetype` entry comes first and uncompressed, so other apps know the file by it.
  static func package(content: Data) throws -> Data {
    let header = #"<?xml version="1.0" encoding="UTF-8"?>"#
    let manifestParts: [String] = [
      header,
      #"<manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0" manifest:version="1.3">"#,
      #"<manifest:file-entry manifest:full-path="/" manifest:version="1.3" manifest:media-type="\#(mimeType)"/>"#,
      #"<manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/>"#,
      #"<manifest:file-entry manifest:full-path="styles.xml" manifest:media-type="text/xml"/>"#,
      #"<manifest:file-entry manifest:full-path="meta.xml" manifest:media-type="text/xml"/>"#,
      "</manifest:manifest>",
    ]
    let stylesParts: [String] = [
      header, "<office:document-styles \(namespaces) office:version=\"1.3\">",
      "<office:styles><style:default-style style:family=\"table-cell\">",
      "<style:text-properties fo:font-size=\"12pt\"/></style:default-style>",
      "<style:style style:name=\"Default\" style:family=\"table-cell\"/></office:styles>",
      "</office:document-styles>",
    ]
    let metaParts: [String] = [
      header, "<office:document-meta \(namespaces) office:version=\"1.3\"><office:meta>",
      "<meta:generator>Spark Grid</meta:generator></office:meta></office:document-meta>",
    ]
    let manifest = Data(manifestParts.joined().utf8)
    let stylesXML = Data(stylesParts.joined().utf8)
    let metaXML = Data(metaParts.joined().utf8)
    let entries: [(String, Data, CompressionMethod)] = [
      ("mimetype", Data(mimeType.utf8), .none),
      ("META-INF/manifest.xml", manifest, .deflate),
      ("styles.xml", stylesXML, .deflate),
      ("meta.xml", metaXML, .deflate),
      ("content.xml", content, .deflate),
    ]
    do {
      let archive = try Archive(data: Data(), accessMode: .create, pathEncoding: nil)
      for (path, data, method) in entries {
        try archive.addEntry(
          with: path, type: .file, uncompressedSize: Int64(data.count),
          compressionMethod: method
        ) { position, size in
          data.subdata(in: Int(position)..<Int(position) + size)
        }
      }
      guard let data = archive.data else { throw ExportError.couldNotWrite }
      return data
    } catch {
      throw ExportError.couldNotWrite
    }
  }

  // MARK: - Tables

  /// One sheet. Rows and cells with nothing in them are written once with a repeat count.
  static func tableXML(_ sheet: Sheet, styles: inout StyleCatalog) -> String {
    let lastRow = max(
      0, sheet.maxPopulatedRow, sheet.mergedRanges.map(\.normalized.maxRow).max() ?? 0)
    let lastCol = max(
      0, sheet.maxPopulatedColumn, sheet.mergedRanges.map(\.normalized.maxCol).max() ?? 0)
    let extras = sheet.fileExtras
    var xml = "<table:table table:name=\"\(escape(sheet.name))\""
    if sheet.isHidden { xml += #" table:display="false""# }
    xml += ">"

    // Columns: one entry per run of columns that look the same.
    let widestStyled = max(lastCol, sheet.columnWidths.keys.max() ?? 0)
    var col = 0
    while col <= widestStyled {
      let width = sheet.columnWidths[col] ?? Workbook.defaultColumnWidth
      let hidden = extras.hiddenColumns.contains(col)
      var run = 1
      while col + run <= widestStyled,
        (sheet.columnWidths[col + run] ?? Workbook.defaultColumnWidth) == width,
        extras.hiddenColumns.contains(col + run) == hidden
      {
        run += 1
      }
      let style = styles.columnStyle(width: width)
      xml += "<table:table-column table:style-name=\"\(style)\""
      if run > 1 { xml += " table:number-columns-repeated=\"\(run)\"" }
      if hidden { xml += #" table:visibility="collapse""# }
      xml += "/>"
      col += run
    }

    // Merged cells: the top-left cell spans; the others are covered.
    var spans: [CellAddress: (rows: Int, cols: Int)] = [:]
    var covered = Set<CellAddress>()
    for range in sheet.mergedRanges {
      let n = range.normalized
      spans[CellAddress(row: n.minRow, col: n.minCol)] = (
        n.maxRow - n.minRow + 1, n.maxCol - n.minCol + 1
      )
      for r in n.minRow...n.maxRow {
        for c in n.minCol...n.maxCol where r != n.minRow || c != n.minCol {
          covered.insert(CellAddress(row: r, col: c))
        }
      }
    }

    let mergeRows = Set(covered.map(\.row)).union(spans.keys.map(\.row))
    var cellsByRow: [Int: [Int: Cell]] = [:]
    for (address, cell) in sheet.cells where cell.hasContent || cell.format != nil {
      cellsByRow[address.row, default: [:]][address.col] = cell
    }
    var row = 0
    while row <= lastRow {
      let height = sheet.rowHeights[row]
      let hidden = extras.hiddenRows.contains(row)
      let rowCells = cellsByRow[row] ?? [:]
      if rowCells.isEmpty, !mergeRows.contains(row) {
        // A run of empty rows that look the same.
        var run = 1
        while row + run <= lastRow, cellsByRow[row + run] == nil,
          sheet.rowHeights[row + run] == height, extras.hiddenRows.contains(row + run) == hidden,
          !mergeRows.contains(row + run)
        {
          run += 1
        }
        xml += rowOpen(height: height, hidden: hidden, repeated: run, styles: &styles)
        xml +=
          "<table:table-cell table:number-columns-repeated=\"\(lastCol + 1)\"/></table:table-row>"
        row += run
        continue
      }
      xml += rowOpen(height: height, hidden: hidden, repeated: 1, styles: &styles)
      var col = 0
      var blanks = 0
      func flushBlanks() {
        guard blanks > 0 else { return }
        xml +=
          blanks == 1
          ? "<table:table-cell/>"
          : "<table:table-cell table:number-columns-repeated=\"\(blanks)\"/>"
        blanks = 0
      }
      while col <= lastCol {
        let address = CellAddress(row: row, col: col)
        if covered.contains(address) {
          flushBlanks()
          xml += "<table:covered-table-cell/>"
        } else if let cell = rowCells[col] {
          flushBlanks()
          xml += cellXML(cell, span: spans[address], sheetName: sheet.name, styles: &styles)
        } else if let span = spans[address] {
          flushBlanks()
          xml += cellXML(Cell(), span: span, sheetName: sheet.name, styles: &styles)
        } else {
          blanks += 1
        }
        col += 1
      }
      flushBlanks()
      xml += "</table:table-row>"
      row += 1
    }
    return xml + "</table:table>"
  }

  private static func rowOpen(
    height: CGFloat?, hidden: Bool, repeated: Int, styles: inout StyleCatalog
  ) -> String {
    let style = styles.rowStyle(height: height ?? Workbook.defaultRowHeight, custom: height != nil)
    var xml = "<table:table-row table:style-name=\"\(style)\""
    if repeated > 1 { xml += " table:number-rows-repeated=\"\(repeated)\"" }
    if hidden { xml += #" table:visibility="collapse""# }
    return xml + ">"
  }

  // MARK: - Cells

  static func cellXML(
    _ cell: Cell, span: (rows: Int, cols: Int)?, sheetName: String, styles: inout StyleCatalog
  ) -> String {
    var attributes = ""
    if let format = cell.format, let style = styles.cellStyle(format) {
      attributes += " table:style-name=\"\(style)\""
    }
    if let span {
      if span.cols > 1 { attributes += " table:number-columns-spanned=\"\(span.cols)\"" }
      if span.rows > 1 { attributes += " table:number-rows-spanned=\"\(span.rows)\"" }
    }
    let value: CellValue?
    if FormulaSyntax.isFormula(cell.raw) {
      if let formula = openFormula(cell.raw) {
        attributes += " table:formula=\"\(escape(formula))\""
      }
      value = cell.cachedFormulaValue
    } else if cell.hasContent {
      value = cell.literalValue
    } else {
      value = nil
    }
    var paragraphs: [String] = []
    if let value {
      switch value {
      case .number(let number):
        attributes += valueAttributes(number, format: cell.format)
        paragraphs = [ODSImporter.numberText(number)]
      case .bool(let flag):
        attributes +=
          " office:value-type=\"boolean\" office:boolean-value=\"\(flag ? "true" : "false")\""
        paragraphs = [flag ? "TRUE" : "FALSE"]
      case .error(let error):
        // A typed #N/A is the NA() formula; the other apps have no error values to type.
        if !FormulaSyntax.isFormula(cell.raw), error == .na {
          attributes += #" table:formula="of:=NA()""#
        }
        attributes += #" office:value-type="string""#
        paragraphs = [error.displayCode]
      case .string(let text):
        attributes += #" office:value-type="string""#
        paragraphs = text.components(separatedBy: "\n")
      case .blank:
        break
      }
    }
    guard !paragraphs.isEmpty else { return "<table:table-cell\(attributes)/>" }
    let body = paragraphs.map { "<text:p>\(escape($0))</text:p>" }.joined()
    return "<table:table-cell\(attributes)>\(body)</table:table-cell>"
  }

  /// The value and its type: a date, time, percentage or currency by the cell's number format.
  static func valueAttributes(_ number: Double, format: CellFormat?) -> String {
    let text = ODSImporter.numberText(number)
    switch format?.numberFormat ?? .general {
    case .percent:
      return " office:value-type=\"percentage\" office:value=\"\(text)\""
    case .currency:
      return " office:value-type=\"currency\" office:currency=\"USD\" office:value=\"\(text)\""
    case .date:
      if let date = dateText(number) {
        return " office:value-type=\"date\" office:date-value=\"\(date)\""
      }
    case .time:
      if number >= 0, number < 1 {
        return " office:value-type=\"time\" office:time-value=\"\(durationText(number))\""
      }
      if let date = dateText(number) {
        return " office:value-type=\"date\" office:date-value=\"\(date)\""
      }
    default:
      break
    }
    return " office:value-type=\"float\" office:value=\"\(text)\""
  }

  /// `2026-11-20`, or `2026-11-20T14:30:00` when the serial has a time of day.
  static func dateText(_ serial: Double) -> String? {
    guard serial.isFinite, serial >= 0, let date = ExcelDate.date(from: serial) else { return nil }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
    let day0 = String(format: "%04d-%02d-%02d", year, month, day)
    let seconds = (serial - serial.rounded(.down)) * 86_400
    guard seconds.rounded() >= 1 else { return day0 }
    return day0 + "T" + clockText(seconds)
  }

  /// `PT14H30M00S`.
  static func durationText(_ fraction: Double) -> String {
    let total = Int((fraction * 86_400).rounded())
    return String(format: "PT%02dH%02dM%02dS", total / 3600, (total / 60) % 60, total % 60)
  }

  private static func clockText(_ seconds: Double) -> String {
    let total = Int(seconds.rounded())
    return String(format: "%02d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
  }

  // MARK: - Formulas

  /// `=SUM(A1:B2,Sheet2!C3)` as `of:=SUM([.A1:.B2];[$Sheet2.C3])`. Nil when it does not parse.
  public static func openFormula(_ raw: String) -> String? {
    guard let expr = try? FormulaParser.parse(raw) else { return nil }
    return "of:=" + OpenFormulaPrinter.print(expr)
  }

  // MARK: - Named ranges

  static func namedExpressionsXML(_ workbook: Workbook) -> String {
    let names = workbook.namedRanges.values.sorted { $0.name < $1.name }
    guard !names.isEmpty else { return "" }
    var xml = "<table:named-expressions>"
    for name in names {
      if name.resolvesToRange {
        let n = name.range.normalized
        let sheet = OpenFormulaPrinter.sheetName(name.sheetName)
        let start = OpenFormulaPrinter.cell(row: n.minRow, col: n.minCol, absolute: true)
        let end = OpenFormulaPrinter.cell(row: n.maxRow, col: n.maxCol, absolute: true)
        let base = OpenFormulaPrinter.cell(row: 0, col: 0, absolute: true)
        let range = n.minRow == n.maxRow && n.minCol == n.maxCol ? start : "\(start):\(end)"
        xml +=
          "<table:named-range table:name=\"\(escape(name.name))\" "
          + "table:base-cell-address=\"\(escape("\(sheet).\(base)"))\" "
          + "table:cell-range-address=\"\(escape("\(sheet).\(range)"))\"/>"
      } else if let formula = name.refersTo, let open = openFormula("=" + formula) {
        xml +=
          "<table:named-expression table:name=\"\(escape(name.name))\" "
          + "table:expression=\"\(escape(open))\"/>"
      }
    }
    return xml + "</table:named-expressions>"
  }

  static func escape(_ text: String) -> String {
    var out = ""
    out.reserveCapacity(text.count)
    for character in text {
      switch character {
      case "&": out += "&amp;"
      case "<": out += "&lt;"
      case ">": out += "&gt;"
      case "\"": out += "&quot;"
      default:
        // Control characters other than tab and newline are not allowed in XML.
        if let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1,
          scalar.value < 0x20, scalar != "\t", scalar != "\n"
        {
          continue
        }
        out.append(character)
      }
    }
    return out
  }
}

// MARK: - OpenFormula

/// Prints a parsed formula in OpenFormula, the formula language of .ods files: references in
/// brackets (`[.A1]`, `[$'My Sheet'.A1:.B2]`), `;` between arguments, `TRUE()` and `FALSE()`.
nonisolated enum OpenFormulaPrinter {
  /// Functions other apps write with the `COM.MICROSOFT.` prefix in .ods files.
  static let microsoftFunctions: Set<String> = [
    "XLOOKUP", "XMATCH", "FILTER", "SORT", "SORTBY", "UNIQUE", "SEQUENCE", "RANDARRAY", "LET",
    "IFS", "SWITCH", "CONCAT", "TEXTJOIN", "MAXIFS", "MINIFS", "IFNA", "LAMBDA", "TEXTBEFORE",
    "TEXTAFTER", "TEXTSPLIT", "VSTACK", "HSTACK", "TOCOL", "TOROW", "WRAPROWS", "WRAPCOLS",
    "TAKE", "DROP", "CHOOSECOLS", "CHOOSEROWS", "EXPAND", "REGEXTEST", "REGEXEXTRACT",
    "REGEXREPLACE",
  ]

  static func print(_ expr: FormulaExpr) -> String {
    switch expr {
    case .number(let value): return ODSImporter.numberText(value)
    case .string(let text): return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    case .boolean(let flag): return flag ? "TRUE()" : "FALSE()"
    case .error(let error): return error == .na ? "NA()" : error.displayCode
    case .namedRange(let name): return name
    case .cellRef(let ref): return "[" + reference(ref, withSheet: true) + "]"
    case .range(let start, let end):
      // The end names its sheet only when it differs from the start's.
      let endSheet = end.sheet != nil && end.sheet != start.sheet
      return "[" + reference(start, withSheet: true) + ":"
        + reference(end, withSheet: endSheet, isEnd: true) + "]"
    case .unary(let op, let inner):
      switch op {
      case .negate: return "-" + wrapped(inner, below: 7)
      case .plus: return "+" + wrapped(inner, below: 7)
      case .percent: return wrapped(inner, below: 6) + "%"
      }
    case .binary(let op, let left, let right):
      let level = precedence(op)
      return wrapped(left, below: level) + symbol(op) + wrapped(right, below: level + 1)
    case .call(let name, let args):
      if name == FormulaExpr.rangeOperatorFunction, args.count == 2 {
        return print(args[0]) + ":" + print(args[1])
      }
      if name == FormulaExpr.intersectionFunction, args.count == 2 {
        return print(args[0]) + "!" + print(args[1])
      }
      if name == FormulaExpr.anchorArrayFunction, args.count == 1 {
        return print(args[0])
      }
      if name == FormulaExpr.lambdaCallFunction, let target = args.first {
        return print(target) + "(" + args.dropFirst().map(print).joined(separator: ";") + ")"
      }
      var plain = name.uppercased()
      for prefix in ["_XLFN._XLETA.", "_XLFN.", "_XLWS.", "_XLPM."] where plain.hasPrefix(prefix) {
        plain.removeFirst(prefix.count)
      }
      let written = microsoftFunctions.contains(plain) ? "COM.MICROSOFT." + plain : plain
      return written + "(" + args.map(print).joined(separator: ";") + ")"
    case .missing:
      return ""
    case .array(let rows):
      return "{" + rows.map { $0.map(print).joined(separator: ";") }.joined(separator: "|") + "}"
    }
  }

  private static func precedence(_ expr: FormulaExpr) -> Int {
    switch expr {
    case .binary(let op, _, _): return precedence(op)
    case .unary(.percent, _): return 6
    case .unary: return 7
    default: return 8
    }
  }

  private static func precedence(_ op: BinaryOp) -> Int {
    switch op {
    case .eq, .ne, .lt, .gt, .le, .ge: return 1
    case .concat: return 2
    case .add, .subtract: return 3
    case .multiply, .divide: return 4
    case .power: return 5
    }
  }

  private static func wrapped(_ expr: FormulaExpr, below level: Int) -> String {
    precedence(expr) < level ? "(" + print(expr) + ")" : print(expr)
  }

  private static func symbol(_ op: BinaryOp) -> String {
    switch op {
    case .add: return "+"
    case .subtract: return "-"
    case .multiply: return "*"
    case .divide: return "/"
    case .power: return "^"
    case .concat: return "&"
    case .eq: return "="
    case .ne: return "<>"
    case .lt: return "<"
    case .gt: return ">"
    case .le: return "<="
    case .ge: return ">="
    }
  }

  /// `.A1`, `.$A$1`, `$'My Sheet'.A1`. A whole column or row runs to the sheet's edge.
  static func reference(_ ref: FormulaRef, withSheet: Bool, isEnd: Bool = false) -> String {
    let sheet = withSheet && ref.sheet != nil ? sheetName(ref.sheet ?? "") : ""
    let row = ref.isRowOpen ? (isEnd ? 1_048_575 : 0) : ref.row
    let col = ref.isColOpen ? (isEnd ? 1023 : 0) : ref.col
    var text = sheet + "."
    if ref.absCol { text += "$" }
    text += A1Notation.columnLabel(for: col)
    if ref.absRow { text += "$" }
    text += String(row + 1)
    return text
  }

  static func cell(row: Int, col: Int, absolute: Bool) -> String {
    let dollar = absolute ? "$" : ""
    return dollar + A1Notation.columnLabel(for: col) + dollar + String(row + 1)
  }

  /// `$Sheet1` or `$'My Sheet'`.
  static func sheetName(_ name: String) -> String {
    let plain = name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    return plain ? "$" + name : "$'" + name.replacingOccurrences(of: "'", with: "''") + "'"
  }
}

// MARK: - Styles

/// The automatic styles content.xml needs, each written once and named in order.
nonisolated struct StyleCatalog {
  private var columns: [CGFloat: String] = [:]
  private var rows: [String: String] = [:]
  private var cells: [CellFormat: String] = [:]
  private var numbers: [String: String] = [:]
  private(set) var xml = ""

  mutating func columnStyle(width: CGFloat) -> String {
    if let name = columns[width] { return name }
    let name = "co\(columns.count + 1)"
    columns[width] = name
    xml +=
      "<style:style style:name=\"\(name)\" style:family=\"table-column\">"
      + "<style:table-column-properties fo:break-before=\"auto\" "
      + "style:column-width=\"\(Self.points(width))\"/></style:style>"
    return name
  }

  mutating func rowStyle(height: CGFloat, custom: Bool) -> String {
    let key = "\(height)-\(custom)"
    if let name = rows[key] { return name }
    let name = "ro\(rows.count + 1)"
    rows[key] = name
    xml +=
      "<style:style style:name=\"\(name)\" style:family=\"table-row\">"
      + "<style:table-row-properties style:row-height=\"\(Self.points(height))\" "
      + "fo:break-before=\"auto\" style:use-optimal-row-height=\"\(custom ? "false" : "true")\"/>"
      + "</style:style>"
    return name
  }

  /// Nil for a format that changes nothing.
  mutating func cellStyle(_ format: CellFormat) -> String? {
    guard format != CellFormat() else { return nil }
    if let name = cells[format] { return name }
    let name = "ce\(cells.count + 1)"
    cells[format] = name
    var attributes =
      "style:name=\"\(name)\" style:family=\"table-cell\" style:parent-style-name=\"Default\""
    if let data = numberStyle(format) { attributes += " style:data-style-name=\"\(data)\"" }

    var cell = ""
    if let fill = format.fillColor { cell += " fo:background-color=\"\(Self.hex(fill))\"" }
    if format.wrapText { cell += #" fo:wrap-option="wrap""# }
    switch format.verticalAlign {
    case .top: cell += #" style:vertical-align="top""#
    case .middle: cell += #" style:vertical-align="middle""#
    case .bottom: break
    }
    if format.textRotation != 0 {
      cell += " style:rotation-angle=\"\(format.textRotation)\""
    }
    for (side, edge) in [
      ("top", format.borders.top), ("bottom", format.borders.bottom),
      ("left", format.borders.left), ("right", format.borders.right),
    ] {
      guard let edge else { continue }
      cell += " fo:border-\(side)=\"\(Self.border(edge))\""
    }

    var paragraph = ""
    switch format.horizontalAlign {
    case .left: paragraph = #" fo:text-align="start""#
    case .center: paragraph = #" fo:text-align="center""#
    case .right: paragraph = #" fo:text-align="end""#
    case .general: break
    }

    var text = ""
    if format.bold { text += #" fo:font-weight="bold""# }
    if format.italic { text += #" fo:font-style="italic""# }
    if format.underline {
      text +=
        #" style:text-underline-style="solid" style:text-underline-width="auto" style:text-underline-color="font-color""#
    }
    if format.strikethrough { text += #" style:text-line-through-style="solid""# }
    if let color = format.textColor { text += " fo:color=\"\(Self.hex(color))\"" }
    if let size = format.fontSize { text += " fo:font-size=\"\(Self.points(size))\"" }
    if let family = format.fontFamily {
      text +=
        " style:font-name=\"\(ODSExporter.escape(family))\" fo:font-family=\"\(ODSExporter.escape(family))\""
    }

    xml += "<style:style \(attributes)>"
    if !cell.isEmpty { xml += "<style:table-cell-properties\(cell)/>" }
    if !paragraph.isEmpty { xml += "<style:paragraph-properties\(paragraph)/>" }
    if !text.isEmpty { xml += "<style:text-properties\(text)/>" }
    xml += "</style:style>"
    return name
  }

  /// A number style for the cell's number format, or nil for General.
  private mutating func numberStyle(_ format: CellFormat) -> String? {
    let decimals = format.decimalPlaces
    func number(_ places: Int, grouping: Bool) -> String {
      "<number:number number:decimal-places=\"\(places)\" number:min-decimal-places=\"\(places)\" "
        + "number:min-integer-digits=\"1\"\(grouping ? #" number:grouping="true""# : "")/>"
    }
    let key: String
    let body: String
    switch format.numberFormat {
    case .general:
      guard let decimals else { return nil }
      key = "n\(decimals)"
      body =
        "<number:number-style style:name=\"@\">\(number(decimals, grouping: false))</number:number-style>"
    case .number:
      let places = decimals ?? 2
      key = "g\(places)"
      body =
        "<number:number-style style:name=\"@\">\(number(places, grouping: true))</number:number-style>"
    case .currency:
      let places = decimals ?? 2
      key = "c\(places)"
      body =
        "<number:currency-style style:name=\"@\"><number:currency-symbol>$</number:currency-symbol>"
        + "\(number(places, grouping: true))</number:currency-style>"
    case .percent:
      let places = decimals ?? 0
      key = "p\(places)"
      body =
        "<number:percentage-style style:name=\"@\">\(number(places, grouping: false))"
        + "<number:text>%</number:text></number:percentage-style>"
    case .scientific:
      let places = decimals ?? 2
      key = "e\(places)"
      body =
        "<number:number-style style:name=\"@\"><number:scientific-number number:decimal-places=\"\(places)\" "
        + "number:min-decimal-places=\"\(places)\" number:min-integer-digits=\"1\" number:min-exponent-digits=\"2\"/>"
        + "</number:number-style>"
    case .date:
      key = "d"
      body =
        "<number:date-style style:name=\"@\"><number:month/><number:text>/</number:text>"
        + "<number:day/><number:text>/</number:text><number:year number:style=\"long\"/>"
        + "</number:date-style>"
    case .time:
      key = "t"
      body =
        "<number:time-style style:name=\"@\"><number:hours/><number:text>:</number:text>"
        + "<number:minutes number:style=\"long\"/><number:text> </number:text><number:am-pm/>"
        + "</number:time-style>"
    }
    if let name = numbers[key] { return name }
    let name = "N\(numbers.count + 1)"
    numbers[key] = name
    xml += body.replacingOccurrences(of: "style:name=\"@\"", with: "style:name=\"\(name)\"")
    return name
  }

  static func points(_ value: CGFloat) -> String {
    String(format: "%.2fpt", Double(value))
  }

  static func hex(_ color: CodableColor) -> String {
    func byte(_ v: Double) -> Int { Int((min(1, max(0, v)) * 255).rounded()) }
    return String(format: "#%02x%02x%02x", byte(color.red), byte(color.green), byte(color.blue))
  }

  static func border(_ edge: BorderEdge) -> String {
    let color = edge.color.map(hex) ?? "#000000"
    switch edge.style {
    case .thin: return "0.75pt solid \(color)"
    case .medium: return "1.5pt solid \(color)"
    case .thick: return "2.5pt solid \(color)"
    case .dashed: return "0.75pt dashed \(color)"
    case .dotted: return "0.75pt dotted \(color)"
    case .double: return "2.5pt double \(color)"
    }
  }
}
