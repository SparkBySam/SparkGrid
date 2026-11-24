import Foundation
import GridCore
import Model
import NumberFormat

/// Opens an OpenDocument spreadsheet (.ods, as LibreOffice and others save it): every sheet's
/// values, text, dates, times, true/false and formulas with the results the file saved, and merged
/// cells. Formatting is not read yet. The workbook is new in Spark Grid, so saving asks where
/// to put it and never writes over the .ods (asked for on Reddit, Nov 19).
public nonisolated enum ODSImporter {
  public enum ImportError: Error, LocalizedError {
    case notODS

    public var errorDescription: String? {
      "This file is not an OpenDocument spreadsheet Spark Grid can read."
    }
  }

  /// More cells than this from repeated rows and columns are not copied out: a file can repeat
  /// one formatted cell a million times to reach the sheet's edge.
  static let maxRepeatedCells = 200_000

  public static func importWorkbook(from url: URL) throws -> Workbook {
    try importWorkbook(fromArchiveData: Data(contentsOf: url))
  }

  public static func importWorkbook(fromArchiveData data: Data) throws -> Workbook {
    let package: ZipPackage
    do {
      package = try ZipPackage(archiveData: data)
    } catch XLSXCodec.CodecError.tooLarge {
      throw XLSXCodec.CodecError.tooLarge
    } catch {
      throw ImportError.notODS
    }
    guard let content = package.data(for: "content.xml") else { throw ImportError.notODS }
    return try importWorkbook(contentXML: content)
  }

  static func importWorkbook(contentXML: Data) throws -> Workbook {
    let reader = ContentReader()
    let parser = XMLParser(data: contentXML)
    parser.delegate = reader
    parser.shouldProcessNamespaces = false
    guard parser.parse() || !reader.sheets.isEmpty else { throw ImportError.notODS }
    guard !reader.sheets.isEmpty else { throw ImportError.notODS }
    return Workbook(sheets: reader.sheets)
  }

  // MARK: - Values

  /// `PT10H30M05.5S` as a fraction of a day.
  static func dayFraction(fromDuration text: String) -> Double? {
    guard text.hasPrefix("PT") || text.hasPrefix("-PT") else { return nil }
    let negative = text.hasPrefix("-")
    var number = ""
    var seconds = 0.0
    for character in text.drop(while: { $0 != "T" }).dropFirst() {
      if character.isNumber || character == "." {
        number.append(character)
        continue
      }
      guard let value = Double(number) else { return nil }
      switch character {
      case "H": seconds += value * 3600
      case "M": seconds += value * 60
      case "S": seconds += value
      default: return nil
      }
      number = ""
    }
    let fraction = seconds / 86_400
    return negative ? -fraction : fraction
  }

  /// `2026-11-19` or `2026-11-19T10:30:00` as a serial date.
  static func serial(fromDate text: String) -> Double? {
    let parts = text.split(separator: "T", maxSplits: 1)
    let day = parts[0].split(separator: "-")
    guard day.count == 3, let year = Int(day[0]), let month = Int(day[1]), let date = Int(day[2])
    else { return nil }
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = date
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    guard let start = calendar.date(from: components) else { return nil }
    var serial = ExcelDate.serial(from: start)
    if parts.count == 2 {
      let clock = parts[1].split(separator: ":")
      if clock.count >= 2, let hours = Double(clock[0]), let minutes = Double(clock[1]) {
        let seconds = clock.count > 2 ? Double(clock[2].prefix { $0 != "Z" && $0 != "+" }) ?? 0 : 0
        serial += (hours * 3600 + minutes * 60 + seconds) / 86_400
      }
    }
    return serial
  }

  static func numberText(_ value: Double) -> String {
    if value.rounded() == value, abs(value) < 1e15 { return String(Int64(value)) }
    return String(value)
  }

  // MARK: - Formulas

  /// An OpenFormula formula (`of:=SUM([.A1:.B2];[Sheet2.C3])`) as Spark Grid writes it
  /// (`=SUM(A1:B2,Sheet2!C3)`).
  static func formula(fromOpenFormula text: String) -> String {
    var body = Substring(text)
    for prefix in ["of:", "msoxl:", "oooc:"] where body.hasPrefix(prefix) {
      body = body.dropFirst(prefix.count)
    }
    if !body.hasPrefix("=") { body = "=" + body }
    var out = ""
    var index = body.startIndex
    while index < body.endIndex {
      let character = body[index]
      switch character {
      case "\"":
        // A string literal, copied as it is ("" is a quote inside it).
        var end = body.index(after: index)
        while end < body.endIndex {
          if body[end] == "\"" {
            let next = body.index(after: end)
            if next < body.endIndex, body[next] == "\"" {
              end = body.index(after: next)
              continue
            }
            break
          }
          end = body.index(after: end)
        }
        let stop = end < body.endIndex ? body.index(after: end) : end
        out += body[index..<stop]
        index = stop
      case "[":
        guard let close = body[index...].firstIndex(of: "]") else {
          out += body[index...]
          index = body.endIndex
          continue
        }
        out += reference(String(body[body.index(after: index)..<close]))
        index = body.index(after: close)
      case ";":
        out.append(",")
        index = body.index(after: index)
      default:
        out.append(character)
        index = body.index(after: index)
      }
    }
    return out.replacingOccurrences(of: "COM.MICROSOFT.", with: "", options: .caseInsensitive)
  }

  /// `.A1`, `.A1:.B2`, `$Sheet1.A1`, `'My Sheet'.A1:.B2` as `A1`, `A1:B2`, `Sheet1!A1`,
  /// `'My Sheet'!A1:B2`.
  static func reference(_ text: String) -> String {
    if text.contains("#REF!") { return "#REF!" }
    var sheet: String?
    var ends: [String] = []
    for part in splitOutsideQuotes(text, on: ":") {
      var piece = part
      if piece.hasPrefix("$") && piece.dropFirst().hasPrefix("'") { piece.removeFirst() }
      guard let dot = lastIndexOutsideQuotes(of: ".", in: piece) else {
        ends.append(piece)
        continue
      }
      var name = String(piece[piece.startIndex..<dot])
      if name.hasPrefix("$") { name.removeFirst() }
      if !name.isEmpty, sheet == nil { sheet = name }
      ends.append(String(piece[piece.index(after: dot)...]))
    }
    let cells = ends.joined(separator: ":")
    guard let sheet else { return cells }
    return sheet + "!" + cells
  }

  private static func splitOutsideQuotes(_ text: String, on separator: Character) -> [String] {
    var parts: [String] = []
    var current = ""
    var quoted = false
    for character in text {
      if character == "'" { quoted.toggle() }
      if character == separator, !quoted {
        parts.append(current)
        current = ""
      } else {
        current.append(character)
      }
    }
    parts.append(current)
    return parts
  }

  private static func lastIndexOutsideQuotes(of target: Character, in text: String)
    -> String.Index?
  {
    var quoted = false
    var found: String.Index?
    var index = text.startIndex
    while index < text.endIndex {
      let character = text[index]
      if character == "'" { quoted.toggle() }
      if character == target, !quoted { found = index }
      index = text.index(after: index)
    }
    return found
  }

  // MARK: - content.xml

  private final class ContentReader: NSObject, XMLParserDelegate {
    var sheets: [Sheet] = []
    private var sheet: Sheet?
    private var row = 0
    private var col = 0
    private var rowRepeat = 1
    private var copiedCells = 0

    // The cell being read.
    private var inCell = false
    private var cellAttributes: [String: String] = [:]
    private var cellRepeat = 1
    private var paragraphs: [String] = []
    private var paragraph = ""
    private var textDepth = 0
    private var rowCells: [(col: Int, cell: Cell)] = []

    func parser(
      _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
      qualifiedName qName: String?, attributes: [String: String] = [:]
    ) {
      switch elementName {
      case "table:table":
        sheet = Sheet(name: attributes["table:name"] ?? "Sheet\(sheets.count + 1)")
        row = 0
      case "table:table-row":
        col = 0
        rowCells = []
        rowRepeat = max(1, Int(attributes["table:number-rows-repeated"] ?? "1") ?? 1)
      case "table:table-cell", "table:covered-table-cell":
        inCell = true
        cellAttributes = attributes
        cellRepeat = max(1, Int(attributes["table:number-columns-repeated"] ?? "1") ?? 1)
        paragraphs = []
        if elementName == "table:table-cell" { noteMerge(attributes) }
      case "text:p", "text:h":
        guard inCell else { return }
        textDepth += 1
        paragraph = ""
      case "text:s":
        guard textDepth > 0 else { return }
        paragraph += String(repeating: " ", count: max(1, Int(attributes["text:c"] ?? "1") ?? 1))
      case "text:tab":
        if textDepth > 0 { paragraph += "\t" }
      case "text:line-break":
        if textDepth > 0 { paragraph += "\n" }
      default:
        break
      }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
      if textDepth > 0 { paragraph += string }
    }

    func parser(
      _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
      qualifiedName qName: String?
    ) {
      switch elementName {
      case "text:p", "text:h":
        guard textDepth > 0 else { return }
        textDepth -= 1
        paragraphs.append(paragraph)
      case "table:table-cell", "table:covered-table-cell":
        inCell = false
        if let cell = makeCell() {
          let copies = min(cellRepeat, max(1, ODSImporter.maxRepeatedCells - copiedCells))
          for offset in 0..<copies { rowCells.append((col + offset, cell)) }
        }
        col += cellRepeat
      case "table:table-row":
        let copies =
          rowCells.isEmpty
          ? 0 : min(rowRepeat, max(1, ODSImporter.maxRepeatedCells - copiedCells))
        for offset in 0..<copies {
          for (column, cell) in rowCells {
            sheet?.setCell(cell, at: CellAddress(row: row + offset, col: column))
            copiedCells += 1
          }
        }
        row += rowRepeat
      case "table:table":
        if let sheet { sheets.append(sheet) }
        sheet = nil
      default:
        break
      }
    }

    private func noteMerge(_ attributes: [String: String]) {
      let across = Int(attributes["table:number-columns-spanned"] ?? "1") ?? 1
      let down = Int(attributes["table:number-rows-spanned"] ?? "1") ?? 1
      guard across > 1 || down > 1 else { return }
      sheet?.mergedRanges.append(
        CellRange(
          start: CellAddress(row: row, col: col),
          end: CellAddress(row: row + max(1, down) - 1, col: col + max(1, across) - 1)))
    }

    private func makeCell() -> Cell? {
      let type = cellAttributes["office:value-type"] ?? cellAttributes["calcext:value-type"]
      let text = paragraphs.joined(separator: "\n")
      var value: String?
      var valueType: ImportedFormulaValueType = .string
      var format: CellFormat?
      switch type {
      case "float", "percentage", "currency":
        if let number = Double(cellAttributes["office:value"] ?? "") {
          value = ODSImporter.numberText(number)
          valueType = .number
          if type == "percentage" { format = CellFormat(numberFormat: .percent) }
          if type == "currency" { format = CellFormat(numberFormat: .currency) }
        }
      case "date":
        if let serial = ODSImporter.serial(fromDate: cellAttributes["office:date-value"] ?? "") {
          value = ODSImporter.numberText(serial)
          valueType = .number
          format = CellFormat(numberFormat: .date)
        }
      case "time":
        if let fraction = ODSImporter.dayFraction(
          fromDuration: cellAttributes["office:time-value"] ?? "")
        {
          value = ODSImporter.numberText(fraction)
          valueType = .number
          format = CellFormat(numberFormat: .time)
        }
      case "boolean":
        value = (cellAttributes["office:boolean-value"] ?? "") == "true" ? "TRUE" : "FALSE"
        valueType = .boolean
      case "string":
        value = cellAttributes["office:string-value"] ?? text
      case "error":
        value = text
        valueType = .error
      default:
        if !text.isEmpty { value = text }
      }
      if let formula = cellAttributes["table:formula"] {
        let typeOfResult: ImportedFormulaValueType =
          text.hasPrefix("#") && value == text ? .error : valueType
        return Cell(
          raw: ODSImporter.formula(fromOpenFormula: formula), format: format,
          importedFormulaResult: value, importedFormulaValueType: value == nil ? nil : typeOfResult)
      }
      guard let value, !value.isEmpty else { return nil }
      var cell = Cell(raw: value, format: format)
      // Text such as 007 or 1-2 stays text.
      if valueType == .string { cell.markTextIfNeeded() }
      return cell
    }
  }
}
