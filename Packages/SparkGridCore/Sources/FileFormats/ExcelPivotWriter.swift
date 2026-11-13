import Formula
import Foundation
import GridCore
import Model

/// Writes a pivot table Spark Grid made as a real pivot table other spreadsheet apps read: a
/// pivot cache over the source cells and a pivot table definition where the table is drawn. The
/// cache asks to be rebuilt when the file opens, so the other app draws and refreshes the table
/// itself, and its GETPIVOTDATA formulas find it.
///
/// The parts carry the Spark Grid pivot's id. When Spark Grid opens its own file it drops them
/// (the pivot is in Spark Grid's own settings) and writes them again on the next save. A save
/// from the other app keeps only its own parts; Spark Grid then reads them as that app's table.
public nonisolated enum ExcelPivotWriter {
  /// Marks parts written from a Spark Grid pivot.
  static let markerURI = "{5C2A86F1-1B4E-4D0C-9E57-53504152474B}"
  static let markerNamespace = "https://sparkgrid.app/xlsx/pivot"

  /// The workbook with a pivot table part and cache part added for each Spark Grid pivot that
  /// can be written. Pivots that redraw a table from the file already have one and are skipped.
  public static func addingParts(to workbook: Workbook) -> Workbook {
    var book = workbook
    var nextCacheID = (workbook.pivotCaches.map(\.cacheID).max() ?? 0) + 1
    for index in book.sheets.indices {
      for pivot in book.sheets[index].fileExtras.sparkPivots where pivot.linkedFilePivot == nil {
        guard let parts = parts(for: pivot, cacheID: nextCacheID, workbook: workbook) else {
          continue
        }
        book.sheets[index].fileExtras.pivotTables.append(parts.table)
        book.pivotCaches.append(parts.cache)
        nextCacheID += 1
      }
    }
    return book
  }

  /// Parts this writer made, by the Spark Grid pivot id they carry.
  static func sparkPivotID(in xml: Data) -> UUID? {
    guard let text = String(data: xml, encoding: .utf8), text.contains(markerURI),
      let range = text.range(of: #"sparkPivot id=""#)
    else { return nil }
    let rest = text[range.upperBound...]
    guard let end = rest.firstIndex(of: "\"") else { return nil }
    return UUID(uuidString: String(rest[..<end]))
  }

  /// Takes out the parts this writer added for pivots Spark Grid still has in its own settings.
  /// Parts for a pivot no longer there are kept, as any other app's table would be.
  static func droppingWrittenParts(from workbook: inout Workbook) {
    var dropped = Set<Int>()
    for index in workbook.sheets.indices {
      let ids = Set(workbook.sheets[index].fileExtras.sparkPivots.map(\.id))
      guard !ids.isEmpty else { continue }
      workbook.sheets[index].fileExtras.pivotTables.removeAll { part in
        guard let id = sparkPivotID(in: part.xml), ids.contains(id) else { return false }
        dropped.insert(part.cacheID)
        return true
      }
    }
    guard !dropped.isEmpty else { return }
    let stillUsed = Set(workbook.sheets.flatMap { $0.fileExtras.pivotTables.map(\.cacheID) })
    workbook.pivotCaches.removeAll {
      dropped.contains($0.cacheID) && !stillUsed.contains($0.cacheID)
    }
  }

  // MARK: - Parts

  static func parts(for pivot: SheetPivot, cacheID: Int, workbook: Workbook)
    -> (table: PivotTablePart, cache: PivotCachePart)?
  {
    let definition = pivot.definition
    // Date groups are kept by other apps as grouped cache fields; they stay values for now.
    guard definition.dateGroups.isEmpty, !definition.values.isEmpty,
      let source = workbook.sheets.first(where: {
        $0.name.caseInsensitiveCompare(pivot.sourceSheet) == .orderedSame
      })
    else { return nil }
    let r = pivot.sourceRange.normalized
    guard r.maxRow > r.minRow else { return nil }
    let columns = Array(r.minCol...r.maxCol)
    let headers = columns.map { col in
      label(for: value(source.cell(at: CellAddress(row: r.minRow, col: col))))
    }
    // Other apps need a name for every field, and distinct names.
    guard !headers.contains("(blank)"), Set(headers.map { $0.lowercased() }).count == headers.count
    else { return nil }
    let records: [[CellValue]] = ((r.minRow + 1)...r.maxRow).map { row in
      columns.map { value(source.cell(at: CellAddress(row: row, col: $0))) }
    }
    let fieldCount = columns.count
    let used =
      definition.rows + definition.columns + definition.values.map(\.field)
      + definition.filters.map(\.field)
    guard used.allSatisfy({ (0..<fieldCount).contains($0) }) else { return nil }
    let axisFields = Set(definition.rows + definition.columns + definition.filters.map(\.field))

    // Shared items: one per label, in the order Spark Grid shows them.
    var items: [Int: [(label: String, value: CellValue)]] = [:]
    for field in axisFields {
      var seen: [String: CellValue] = [:]
      for record in records {
        let v = record[field]
        let l = label(for: v)
        if seen[l] == nil { seen[l] = v }
      }
      items[field] = seen.map { ($0.key, $0.value) }.sorted { ordered($0.value, $1.value) }
    }

    let cacheXML = cacheDefinitionXML(
      pivot: pivot, sheetName: source.name, range: pivot.sourceRange, headers: headers,
      records: records, items: items)
    let tableXML = pivotTableXML(
      pivot: pivot, cacheID: cacheID, headers: headers, items: items)
    return (
      PivotTablePart(xml: Data(tableXML.utf8), cacheID: cacheID),
      PivotCachePart(cacheID: cacheID, definitionXML: Data(cacheXML.utf8), recordsXML: nil)
    )
  }

  private static func cacheDefinitionXML(
    pivot: SheetPivot, sheetName: String, range: CellRange, headers: [String],
    records: [[CellValue]], items: [Int: [(label: String, value: CellValue)]]
  ) -> String {
    var fields = ""
    for (field, header) in headers.enumerated() {
      let name = XLSXCodec.escapeXML(header)
      if let shared = items[field] {
        var body = ""
        var hasBlank = false
        var hasText = false
        var hasNumber = false
        for item in shared {
          switch item.value {
          case .number(let n):
            hasNumber = true
            body += #"<n v="\#(numberText(n))"/>"#
          case .bool(let b):
            hasText = true
            body += #"<b v="\#(b ? 1 : 0)"/>"#
          case .blank:
            hasBlank = true
            body += "<m/>"
          case .error(let e):
            hasText = true
            body += #"<e v="\#(XLSXCodec.escapeXML(e.displayCode))"/>"#
          default:
            if item.label == "(blank)" {
              hasBlank = true
              body += "<m/>"
            } else {
              hasText = true
              body += #"<s v="\#(XLSXCodec.escapeXML(item.label))"/>"#
            }
          }
        }
        var attributes = ""
        if !hasText && hasNumber {
          attributes += #" containsSemiMixedTypes="0" containsString="0""#
        }
        if hasNumber { attributes += #" containsNumber="1""# }
        if hasBlank { attributes += #" containsBlank="1""# }
        if hasText && hasNumber { attributes += #" containsMixedTypes="1""# }
        fields +=
          #"<cacheField name="\#(name)" numFmtId="0"><sharedItems\#(attributes) count="\#(shared.count)">\#(body)</sharedItems></cacheField>"#
      } else {
        // A field shown only as values: the app reads the numbers when it refreshes.
        let numbers = records.compactMap { record -> Double? in
          if case .number(let n) = record[field] { return n }
          return nil
        }
        let allNumbers = numbers.count == records.count && !numbers.isEmpty
        if allNumbers, let low = numbers.min(), let high = numbers.max() {
          let integers = numbers.allSatisfy { $0.rounded() == $0 }
          fields +=
            #"<cacheField name="\#(name)" numFmtId="0"><sharedItems containsSemiMixedTypes="0" containsString="0" containsNumber="1"\#(integers ? #" containsInteger="1""# : "") minValue="\#(numberText(low))" maxValue="\#(numberText(high))"/></cacheField>"#
        } else {
          fields += #"<cacheField name="\#(name)" numFmtId="0"><sharedItems/></cacheField>"#
        }
      }
    }
    let ref = range.a1Label
    return """
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <pivotCacheDefinition xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" \
      xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" \
      saveData="0" refreshOnLoad="1" createdVersion="6" refreshedVersion="6" \
      minRefreshableVersion="3" recordCount="\(records.count)">\
      <cacheSource type="worksheet"><worksheetSource ref="\(ref)" \
      sheet="\(XLSXCodec.escapeXML(sheetName))"/></cacheSource>\
      <cacheFields count="\(headers.count)">\(fields)</cacheFields>\
      \(marker(pivot.id))</pivotCacheDefinition>
      """
  }

  private static func pivotTableXML(
    pivot: SheetPivot, cacheID: Int, headers: [String],
    items: [Int: [(label: String, value: CellValue)]]
  ) -> String {
    let definition = pivot.definition
    let valueFields = Set(definition.values.map(\.field))
    var pivotFields = ""
    for field in headers.indices {
      var attributes = ""
      if definition.rows.contains(field) {
        attributes += #" axis="axisRow""#
      } else if definition.columns.contains(field) {
        attributes += #" axis="axisCol""#
      } else if definition.filters.contains(where: { $0.field == field }) {
        attributes += #" axis="axisPage" multipleItemSelectionAllowed="1""#
      }
      if valueFields.contains(field) { attributes += #" dataField="1""# }
      attributes += #" compact="0" outline="0" showAll="0""#
      if let shared = items[field] {
        let hidden = definition.filters.first { $0.field == field }?.hidden ?? []
        var list = ""
        for (index, item) in shared.enumerated() {
          list +=
            hidden.contains(item.label)
            ? #"<item h="1" x="\#(index)"/>"# : #"<item x="\#(index)"/>"#
        }
        list += #"<item t="default"/>"#
        pivotFields +=
          #"<pivotField\#(attributes)><items count="\#(shared.count + 1)">\#(list)</items></pivotField>"#
      } else {
        pivotFields += "<pivotField\(attributes)/>"
      }
    }

    func fieldList(_ tag: String, _ fields: [Int]) -> String {
      guard !fields.isEmpty else { return "" }
      return #"<\#(tag) count="\#(fields.count)">"#
        + fields.map { #"<field x="\#($0)"/>"# }.joined()
        + "</\(tag)>"
    }
    // Two or more value fields sit side by side across the columns.
    var columnFields = definition.columns
    if definition.values.count > 1 { columnFields.append(-2) }
    let pageFields =
      definition.filters.isEmpty
      ? ""
      : #"<pageFields count="\#(definition.filters.count)">"#
        + definition.filters.map { #"<pageField fld="\#($0.field)" hier="-1"/>"# }.joined()
        + "</pageFields>"
    var dataFields = ""
    for value in definition.values {
      let name = XLSXCodec.escapeXML("\(value.aggregate.label) of \(headers[value.field])")
      let subtotal = value.aggregate == .sum ? "" : #" subtotal="\#(value.aggregate.rawValue)""#
      dataFields +=
        #"<dataField name="\#(name)" fld="\#(value.field)"\#(subtotal) baseField="0" baseItem="0"/>"#
    }

    let rows = max(pivot.drawnRows, 2)
    let cols = max(pivot.drawnColumns, 1)
    let location = CellRange(
      start: pivot.anchor,
      end: CellAddress(row: pivot.anchor.row + rows - 1, col: pivot.anchor.col + cols - 1))
    let firstDataRow = definition.columns.isEmpty && definition.values.count < 2 ? 1 : 2
    let firstDataCol = max(definition.rows.count, 1)
    let pageAttributes =
      definition.filters.isEmpty
      ? "" : #" rowPageCount="\#(definition.filters.count)" colPageCount="1""#
    return """
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <pivotTableDefinition xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" \
      name="\(XLSXCodec.escapeXML(pivot.name))" cacheId="\(cacheID)" dataCaption="Values" \
      applyNumberFormats="0" applyBorderFormats="0" applyFontFormats="0" applyPatternFormats="0" \
      applyAlignmentFormats="0" applyWidthHeightFormats="1" updatedVersion="6" \
      minRefreshableVersion="3" useAutoFormatting="1" itemPrintTitles="1" createdVersion="6" \
      indent="0" compact="0" compactData="0" outline="1" outlineData="1" multipleFieldFilters="0">\
      <location ref="\(location.a1Label)" firstHeaderRow="1" firstDataRow="\(firstDataRow)" \
      firstDataCol="\(firstDataCol)"\(pageAttributes)/>\
      <pivotFields count="\(headers.count)">\(pivotFields)</pivotFields>\
      \(fieldList("rowFields", definition.rows))\(fieldList("colFields", columnFields))\
      \(pageFields)<dataFields count="\(definition.values.count)">\(dataFields)</dataFields>\
      <pivotTableStyleInfo name="PivotStyleLight16" showRowHeaders="1" showColHeaders="1" \
      showRowStripes="0" showColStripes="0" showLastColumn="1"/>\
      \(marker(pivot.id))</pivotTableDefinition>
      """
  }

  private static func marker(_ id: UUID) -> String {
    #"<extLst><ext uri="\#(markerURI)" xmlns:sg="\#(markerNamespace)"><sg:sparkPivot id="\#(id.uuidString)"/></ext></extLst>"#
  }

  // MARK: - Values, as the pivot engine reads them

  private static func value(_ cell: Cell) -> CellValue {
    if FormulaSyntax.isFormula(cell.raw) { return cell.cachedFormulaValue ?? .blank }
    if cell.raw.isEmpty, let spilled = cell.cachedFormulaValue { return spilled }
    return CellValue.fromLiteralRaw(cell.raw)
  }

  private static func numberText(_ n: Double) -> String {
    n.rounded() == n && abs(n) < 1e15 ? String(Int(n)) : String(n)
  }

  /// Matches `Pivot.label(for:)`: blanks and empty text are "(blank)".
  static func label(for value: CellValue) -> String {
    switch value {
    case .blank: return "(blank)"
    case .string(let text):
      let trimmed = text.trimmingCharacters(in: .whitespaces)
      return trimmed.isEmpty ? "(blank)" : trimmed
    default: return value.displayString
    }
  }

  /// Matches `Pivot.ordered`: numbers by value before text, text without regard to case,
  /// "(blank)" last.
  static func ordered(_ x: CellValue, _ y: CellValue) -> Bool {
    let lx = label(for: x)
    let ly = label(for: y)
    if lx == ly { return false }
    func number(_ v: CellValue) -> Double? {
      if case .number(let n) = v { return n }
      return nil
    }
    switch (number(x), number(y)) {
    case (let nx?, let ny?): if nx != ny { return nx < ny }
    case (.some, nil): return true
    case (nil, .some): return false
    default: break
    }
    if lx == "(blank)" { return false }
    if ly == "(blank)" { return true }
    let order = lx.localizedCaseInsensitiveCompare(ly)
    if order != .orderedSame { return order == .orderedAscending }
    return lx < ly
  }
}
