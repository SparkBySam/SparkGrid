import Formula
import Foundation
import GridCore
import Model

/// Reads a pivot table another app saved: where it is drawn, where its data comes from, and which
/// fields it shows, as a `PivotDefinition` Spark Grid can calculate. Features Spark Grid cannot
/// calculate leave the table as the file drew it.
public nonisolated enum ExcelPivotReader {
  public struct Pivot: Equatable, Sendable {
    public var name: String
    /// The cells the table covers, without its filter rows above.
    public var location: CellRange
    public var sourceSheet: String
    public var sourceRange: CellRange
    public var definition: PivotDefinition
  }

  public enum Unsupported: Error, Equatable, Sendable {
    case noSource
    case calculatedField
    case groupedField
    case summary(String)
    case unreadable

    /// Why Spark Grid leaves the table alone, for the message it shows.
    public var reason: String {
      switch self {
      case .noSource: "its data is not a range in this workbook"
      case .calculatedField: "it has a calculated field"
      case .groupedField: "it groups items, such as dates by month"
      case .summary(let kind): "it summarizes with \(kind)"
      case .unreadable: "Spark Grid could not read its settings"
      }
    }
  }

  /// The pivot table's name, as the file gives it.
  public static func name(of pivotXML: Data) -> String? {
    guard let text = String(data: pivotXML, encoding: .utf8) else { return nil }
    return XLSXCodec.tagAttributes(in: text, localName: "pivotTableDefinition").first?["name"]
  }

  /// True when the cache already asks to be rebuilt on open.
  public static func refreshesOnLoad(_ cacheDefinitionXML: Data) -> Bool {
    guard let text = String(data: cacheDefinitionXML, encoding: .utf8) else { return false }
    let root = XLSXCodec.tagAttributes(in: text, localName: "pivotCacheDefinition").first
    return root?["refreshOnLoad"] == "1" || root?["refreshOnLoad"] == "true"
  }

  /// The pivot table in `pivotXML`, whose cache is `cacheDefinitionXML`.
  public static func read(
    pivotXML: Data, cacheDefinitionXML: Data, workbook: Workbook
  ) -> Result<Pivot, Unsupported> {
    guard let table = String(data: pivotXML, encoding: .utf8),
      let cache = String(data: cacheDefinitionXML, encoding: .utf8),
      let root = XLSXCodec.tagAttributes(in: table, localName: "pivotTableDefinition").first,
      let ref = XLSXCodec.tagAttributes(in: table, localName: "location").first?["ref"],
      let location = A1Reference.parseRange(ref)
    else { return .failure(.unreadable) }

    // Source: a range on a sheet, or a table or name.
    guard let source = XLSXCodec.tagAttributes(in: cache, localName: "worksheetSource").first,
      let resolved = sourceRange(source, workbook: workbook)
    else { return .failure(.noSource) }

    let cacheFields = elements(in: cache, named: "cacheField")
    if cacheFields.contains(where: { $0.attributes["formula"] != nil }) {
      return .failure(.calculatedField)
    }
    if cacheFields.contains(where: { $0.body.contains("fieldGroup") }) {
      return .failure(.groupedField)
    }
    // Each field's shared items, as the labels Spark Grid groups by.
    let sharedLabels: [[String]] = cacheFields.map { field in
      sharedItemLabels(in: field.body)
    }

    func fieldIndexes(_ section: String) -> [Int] {
      guard let body = elements(in: table, named: section).first?.body else { return [] }
      return XLSXCodec.tagAttributes(in: body, localName: "field")
        .compactMap { $0["x"].flatMap(Int.init) }
        .filter { $0 >= 0 }  // -2 marks where the values go
    }
    let rows = fieldIndexes("rowFields")
    let columns = fieldIndexes("colFields")

    var values: [PivotDefinition.ValueField] = []
    for data in XLSXCodec.tagAttributes(in: table, localName: "dataField") {
      guard let field = data["fld"].flatMap(Int.init) else { continue }
      let aggregate: PivotDefinition.Aggregate
      switch data["subtotal"] ?? "sum" {
      case "sum": aggregate = .sum
      case "count": aggregate = .count
      case "average": aggregate = .average
      case "min": aggregate = .min
      case "max": aggregate = .max
      case let other: return .failure(.summary(other))
      }
      // A value shown as a percentage or a running total is not a plain sum.
      if let show = data["showDataAs"], show != "normal" { return .failure(.summary(show)) }
      values.append(.init(field: field, aggregate: aggregate))
    }

    // Hidden items on any field, and a page field showing one item, become filters.
    var hidden: [Int: Set<String>] = [:]
    let pivotFields = elements(in: table, named: "pivotField")
    for (index, field) in pivotFields.enumerated() {
      let labels = index < sharedLabels.count ? sharedLabels[index] : []
      for item in XLSXCodec.tagAttributes(in: field.body, localName: "item")
      where item["h"] == "1" || item["h"] == "true" {
        guard let x = item["x"].flatMap(Int.init), x < labels.count else { continue }
        hidden[index, default: []].insert(labels[x])
      }
    }
    var filterFields: [Int] = []
    for page in XLSXCodec.tagAttributes(in: table, localName: "pageField") {
      guard let field = page["fld"].flatMap(Int.init) else { continue }
      filterFields.append(field)
      if let item = page["item"].flatMap(Int.init), field < sharedLabels.count,
        item < sharedLabels[field].count
      {
        let shown = sharedLabels[field][item]
        hidden[field] = Set(sharedLabels[field].filter { $0 != shown })
      }
    }
    var filters = filterFields.map { PivotDefinition.Filter(field: $0, hidden: hidden[$0] ?? []) }
    for (field, labels) in hidden.sorted(by: { $0.key < $1.key })
    where !filterFields.contains(field) && !labels.isEmpty {
      filters.append(.init(field: field, hidden: labels))
    }

    let definition = PivotDefinition(
      rows: rows, columns: columns, values: values, filters: filters)
    return .success(
      Pivot(
        name: root["name"] ?? "PivotTable",
        location: CellRange(start: location.0, end: location.1),
        sourceSheet: resolved.sheet,
        sourceRange: resolved.range,
        definition: definition))
  }

  private static func sourceRange(_ source: [String: String], workbook: Workbook) -> (
    sheet: String, range: CellRange
  )? {
    if let ref = source["ref"], let sheet = source["sheet"],
      let range = A1Reference.parseRange(ref),
      workbook.sheets.contains(where: { $0.name.caseInsensitiveCompare(sheet) == .orderedSame })
    {
      return (sheet, CellRange(start: range.0, end: range.1))
    }
    guard let name = source["name"] else { return nil }
    for sheet in workbook.sheets {
      for table in sheet.fileExtras.tables {
        let tableName =
          XLSXCodec.tagAttributes(in: table.xml, localName: "table").first?["name"]
          ?? XLSXCodec.tagAttributes(in: table.xml, localName: "table").first?["displayName"]
        if tableName?.caseInsensitiveCompare(name) == .orderedSame {
          return (sheet.name, table.range)
        }
      }
    }
    if let named = workbook.namedRanges[name.uppercased()], named.resolvesToRange {
      return (named.sheetName, named.range)
    }
    return nil
  }

  /// A cache field's shared items as the labels a pivot shows: text as written, numbers as the
  /// grid shows them, dates as their serial number, blanks as "(blank)".
  static func sharedItemLabels(in body: String) -> [String] {
    guard let start = body.range(of: "<sharedItems") else { return [] }
    let items = body[start.lowerBound...]
    var labels: [String] = []
    let pattern = #"<(s|n|d|b|m|e)\b([^>]*?)/?>"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    let text = String(items)
    let ns = text as NSString
    for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
      let kind = ns.substring(with: match.range(at: 1))
      let attrs = XLSXCodec.attributes(ofTag: "<x " + ns.substring(with: match.range(at: 2)))
      let value = attrs["v"] ?? ""
      switch kind {
      case "s":
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        labels.append(trimmed.isEmpty ? "(blank)" : trimmed)
      case "n":
        labels.append(Double(value).map { CellValue.number($0).displayString } ?? value)
      case "d":
        labels.append(dateSerial(value).map { CellValue.number($0).displayString } ?? value)
      case "b":
        labels.append(CellValue.bool(value == "1" || value == "true").displayString)
      case "m":
        labels.append("(blank)")
      default:
        labels.append(value)
      }
    }
    return labels
  }

  /// `2026-01-05T00:00:00` as days since 30 Dec 1899.
  static func dateSerial(_ text: String) -> Double? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
    formatter.timeZone = TimeZone(identifier: "UTC")
    guard let date = formatter.date(from: text) ?? formatter.date(from: text + "Z") else {
      return nil
    }
    let epoch = Date(timeIntervalSince1970: -2_209_161_600)  // 1899-12-30T00:00:00Z
    return (date.timeIntervalSince(epoch) / 86_400).rounded()
  }

  struct Element {
    var attributes: [String: String]
    var body: String
  }

  /// Elements with this local name, with their attributes and inner XML ("" when self-closed).
  static func elements(in xml: String, named name: String) -> [Element] {
    let pattern = "<(?:\\w+:)?\(name)\\b([^>]*?)(?:/>|>([\\s\\S]*?)</(?:\\w+:)?\(name)>)"
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    let ns = xml as NSString
    return regex.matches(in: xml, range: NSRange(location: 0, length: ns.length)).map { match in
      let attrs = XLSXCodec.attributes(ofTag: "<x " + ns.substring(with: match.range(at: 1)))
      let body =
        match.range(at: 2).location == NSNotFound ? "" : ns.substring(with: match.range(at: 2))
      return Element(attributes: attrs, body: body)
    }
  }

  // MARK: - Writing back

  /// The pivot table's XML with its location widened to cover `range` too.
  public static func pivotXML(_ xml: Data, coveringAlso range: CellRange) -> Data {
    guard var text = String(data: xml, encoding: .utf8),
      let ref = XLSXCodec.tagAttributes(in: text, localName: "location").first?["ref"],
      let old = A1Reference.parseRange(ref),
      let refRange = text.range(of: #"ref="\#(ref)""#)
    else { return xml }
    let a = CellRange(start: old.0, end: old.1).normalized
    let b = range.normalized
    let union = CellRange(
      start: CellAddress(row: min(a.minRow, b.minRow), col: min(a.minCol, b.minCol)),
      end: CellAddress(row: max(a.maxRow, b.maxRow), col: max(a.maxCol, b.maxCol)))
    text.replaceSubrange(refRange, with: #"ref="\#(union.a1Label)""#)
    return Data(text.utf8)
  }

  /// The cache definition with `refreshOnLoad="1"`, so the app that made the table draws it
  /// again from the data when the file next opens there.
  public static func cacheDefinitionXML(refreshingOnLoad xml: Data) -> Data {
    guard var text = String(data: xml, encoding: .utf8),
      let tag = XLSXCodec.openTags(in: text, localName: "pivotCacheDefinition").first,
      let range = text.range(of: tag)
    else { return xml }
    var updated = tag
    if let existing = updated.range(
      of: #"\srefreshOnLoad="[^"]*""#, options: .regularExpression)
    {
      updated.replaceSubrange(existing, with: #" refreshOnLoad="1""#)
    } else {
      let close = updated.hasSuffix("/>") ? "/>" : ">"
      updated = String(updated.dropLast(close.count)) + #" refreshOnLoad="1""# + close
    }
    text.replaceSubrange(range, with: updated)
    return Data(text.utf8)
  }
}
