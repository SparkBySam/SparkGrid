import Formula
import Foundation
import GridCore
import Model

/// Reads and writes the parts of a file the app keeps but does not edit: hidden rows, columns and
/// sheets, groups, protection, page setup, dropdown rules, links, comments, tables, charts it does
/// not draw, and pivot tables.
extension XLSXCodec {
  // MARK: - Import

  /// Fills `sheet.fileExtras` from the elements the streaming reader kept and the parts they link to.
  static func importFileExtras(
    into sheet: inout Sheet,
    kept: [String: [String]],
    package: (String) -> Data?,
    worksheetPath: String
  ) {
    var extras = sheet.fileExtras
    // A file saves the rows its filter hides as hidden rows. Those belong to the filter, which
    // hides them again, so clearing the filter shows them.
    if let filter = sheet.autoFilter, filter.hasCriteria, !extras.hiddenRows.isEmpty {
      let rows = filter.dataRows
      extras.hiddenRows = extras.hiddenRows.filter { !rows.contains($0) }
    }
    extras.sheetPropertiesXML = kept["sheetPr"]?.first
    extras.protectionXML = kept["sheetProtection"]?.first
    var layout = ""
    for name in [
      "printOptions", "pageMargins", "pageSetup", "headerFooter", "rowBreaks", "colBreaks",
    ] {
      guard let xml = kept[name]?.first else { continue }
      // A page setup points at a printer settings part the app does not keep.
      layout += name == "pageSetup" ? removingAttribute("r:id", from: xml) : xml
    }
    let split = SheetFileExtras.splittingPageBreaks(from: layout)
    extras.pageLayoutXML = split.layout
    extras.rowBreaks = split.rows
    extras.columnBreaks = split.columns

    if let xml = kept["dataValidations"]?.first {
      extras.dataValidations = dataValidationRules(in: xml)
    }

    let relsPath = relationshipsPath(for: worksheetPath)
    let rels =
      package(relsPath).flatMap { String(data: $0, encoding: .utf8) }
      .map(relationships(in:)) ?? [:]
    func linkedPart(_ id: String?) -> (path: String, data: Data)? {
      guard let id, let rel = rels[id], !rel.external else { return nil }
      let path = partPath(rel.target, base: worksheetPath)
      guard let data = package(path) else { return nil }
      return (path, data)
    }

    if let xml = kept["hyperlinks"]?.first {
      extras.hyperlinks = hyperlinks(in: xml, rels: rels)
    }

    if let rel = rels.values.first(where: { $0.type.hasSuffix("/comments") && !$0.external }) {
      let path = partPath(rel.target, base: worksheetPath)
      if let data = package(path), let xml = String(data: data, encoding: .utf8) {
        extras.comments = comments(in: xml)
      }
    }

    if let xml = kept["tableParts"]?.first {
      for attributes in tagAttributes(in: xml, localName: "tablePart") {
        guard let part = linkedPart(attributes["r:id"]),
          let tableXML = String(data: part.data, encoding: .utf8),
          let root = tagAttributes(in: tableXML, localName: "table").first,
          let ref = root["ref"], let range = parseCellRange(ref)
        else { continue }
        extras.tables.append(SheetTable(range: range, xml: tableXML))
      }
    }

    if let drawing = kept["drawing"]?.first,
      let id = tagAttributes(in: drawing, localName: "drawing").first?["r:id"],
      let part = linkedPart(id),
      let drawingXML = String(data: part.data, encoding: .utf8)
    {
      extras.foreignCharts = foreignCharts(
        in: drawingXML,
        drawingPath: part.path,
        skipping: sheet.charts.count,
        package: package
      )
    }

    for rel in rels.values where rel.type.hasSuffix("/pivotTable") && !rel.external {
      let path = partPath(rel.target, base: worksheetPath)
      guard let data = package(path), let xml = String(data: data, encoding: .utf8),
        let root = tagAttributes(in: xml, localName: "pivotTableDefinition").first,
        let cacheID = root["cacheId"].flatMap({ Int($0) })
      else { continue }
      extras.pivotTables.append(PivotTablePart(xml: data, cacheID: cacheID))
    }
    sheet.fileExtras = extras
  }

  /// Sheet states and pivot caches from `xl/workbook.xml`.
  static func importWorkbookExtras(into workbook: inout Workbook, package: (String) -> Data?) {
    guard let data = package("xl/workbook.xml"), let xml = String(data: data, encoding: .utf8)
    else { return }
    let sheetTags = tagAttributes(in: xml, localName: "sheet")
    for (index, attributes) in sheetTags.enumerated() where workbook.sheets.indices.contains(index)
    {
      switch attributes["state"] {
      case "hidden": workbook.sheets[index].fileExtras.visibility = .hidden
      case "veryHidden": workbook.sheets[index].fileExtras.visibility = .veryHidden
      default: break
      }
    }
    if !workbook.sheets.contains(where: { !$0.isHidden }), !workbook.sheets.isEmpty {
      workbook.sheets[0].fileExtras.visibility = .visible
    }
    if let first = workbook.sheets.firstIndex(where: { !$0.isHidden }),
      workbook.sheets.indices.contains(workbook.activeSheetIndex),
      workbook.sheets[workbook.activeSheetIndex].isHidden
    {
      workbook.activeSheetIndex = first
    }

    let caches = tagAttributes(in: xml, localName: "pivotCache")
    guard !caches.isEmpty,
      let relsData = package("xl/_rels/workbook.xml.rels"),
      let relsXML = String(data: relsData, encoding: .utf8)
    else { return }
    let rels = relationships(in: relsXML)
    for attributes in caches {
      guard let cacheID = attributes["cacheId"].flatMap({ Int($0) }),
        let rel = attributes["r:id"].flatMap({ rels[$0] })
      else { continue }
      let path = partPath(rel.target, base: "xl/workbook.xml")
      guard let definition = package(path) else { continue }
      var records: Data?
      if let cacheRels = package(relationshipsPath(for: path))
        .flatMap({ String(data: $0, encoding: .utf8) })
        .map(relationships(in:)),
        let recordsRel = cacheRels.values.first(where: { $0.type.hasSuffix("/pivotCacheRecords") })
      {
        records = package(partPath(recordsRel.target, base: path))
      }
      workbook.pivotCaches.append(
        PivotCachePart(cacheID: cacheID, definitionXML: definition, recordsXML: records))
    }
    // Parts Spark Grid wrote for its own pivots are written again from them on the next save.
    ExcelPivotWriter.droppingWrittenParts(from: &workbook)
  }

  static func dataValidationRules(in xml: String) -> [DataValidationRule] {
    var rules: [DataValidationRule] = []
    for element in elements(in: xml, localName: "dataValidation") {
      guard let tagEnd = element.firstIndex(of: ">") else { continue }
      let openTag = String(element[..<tagEnd])
      let selfClosing = openTag.hasSuffix("/")
      guard let attributes = tagAttributes(in: element, localName: "dataValidation").first,
        let sqref = attributes["sqref"]
      else { continue }
      let ranges = sqref.split(separator: " ").compactMap { parseCellRange(String($0)) }
      guard !ranges.isEmpty else { continue }
      var attributeText = removingAttribute("sqref", from: openTag)
      if let space = attributeText.firstIndex(where: { $0 == " " || $0 == "\n" || $0 == "\t" }) {
        attributeText = String(attributeText[space...])
      } else {
        attributeText = ""
      }
      if selfClosing { attributeText = String(attributeText.dropLast()) }
      var body = ""
      if !selfClosing, let close = element.range(of: "</", options: .backwards) {
        let start = element.index(after: tagEnd)
        if start <= close.lowerBound {
          body = String(element[start..<close.lowerBound])
        }
      }
      rules.append(
        DataValidationRule(
          ranges: ranges,
          attributes: attributeText.trimmingCharacters(in: .whitespacesAndNewlines),
          body: body
        ))
    }
    return rules
  }

  static func hyperlinks(in xml: String, rels: [String: Relationship]) -> [CellHyperlink] {
    tagAttributes(in: xml, localName: "hyperlink").compactMap { attributes in
      guard let ref = attributes["ref"], let range = parseCellRange(ref) else { return nil }
      let target = attributes["r:id"].flatMap { rels[$0] }.map(\.target)
      let location = attributes["location"]
      guard target != nil || location != nil else { return nil }
      return CellHyperlink(
        range: range,
        target: target,
        location: location,
        display: attributes["display"],
        tooltip: attributes["tooltip"]
      )
    }
  }

  static func comments(in xml: String) -> [CellComment] {
    let authors = elements(in: xml, localName: "author").map { innerText(of: $0) }
    var found: [CellComment] = []
    for element in elements(in: xml, localName: "comment") {
      guard let attributes = tagAttributes(in: element, localName: "comment").first,
        let ref = attributes["ref"], let parsed = A1Reference.parseAddress(ref)
      else { continue }
      let authorIndex = attributes["authorId"].flatMap { Int($0) } ?? 0
      let author = authors.indices.contains(authorIndex) ? authors[authorIndex] : ""
      let text = elements(in: element, localName: "t").map { innerText(of: $0) }.joined()
      found.append(
        CellComment(
          address: CellAddress(row: parsed.row, col: parsed.col), author: author, text: text))
    }
    return found
  }

  /// Charts in a drawing, after the first `skipping` (the app's own, which its sidecar restores).
  static func foreignCharts(
    in drawingXML: String,
    drawingPath: String,
    skipping: Int,
    package: (String) -> Data?
  ) -> [ForeignChart] {
    let rels =
      package(relationshipsPath(for: drawingPath))
      .flatMap { String(data: $0, encoding: .utf8) }
      .map(relationships(in:)) ?? [:]
    var charts: [ForeignChart] = []
    var seen = 0
    let namespaces =
      (openTags(in: drawingXML, localName: "wsDr").first.map(attributes(ofTag:)) ?? [:])
      .filter { $0.key.hasPrefix("xmlns") }
      .sorted { $0.key < $1.key }
    var anchors: [(offset: Int, xml: String)] = []
    for name in ["twoCellAnchor", "oneCellAnchor", "absoluteAnchor"] {
      for anchor in elements(in: drawingXML, localName: name) {
        let offset =
          drawingXML.range(of: anchor).map {
            drawingXML.distance(from: drawingXML.startIndex, to: $0.lowerBound)
          } ?? 0
        anchors.append((offset, anchor))
      }
    }
    // Drawing order, so the app's own charts (written first) are the ones skipped.
    for (_, anchor) in anchors.sorted(by: { $0.offset < $1.offset }) {
      guard let frame = elements(in: anchor, localName: "graphicFrame").first,
        let chartTag = tagAttributes(in: frame, localName: "chart").first,
        let id = chartTag["r:id"]
      else { continue }
      seen += 1
      if seen <= skipping { continue }
      guard let rel = rels[id], !rel.external,
        let chartData = package(partPath(rel.target, base: drawingPath)),
        let chartXML = String(data: chartData, encoding: .utf8)
      else { continue }
      // The chart's own parts (styles, colors, embedded data) are not kept, so drop links to them.
      var cleaned = chartXML
      for name in ["externalData", "userShapes"] {
        for element in elements(in: cleaned, localName: name) {
          cleaned = cleaned.replacingOccurrences(of: element, with: "")
        }
      }
      var anchorXML = anchor.replacingOccurrences(
        of: #"r:id="\#(id)""#, with: #"r:id="\#(ForeignChart.chartIDPlaceholder)""#)
      // The anchor may use prefixes its drawing declared. Declare them on the anchor itself,
      // skipping any it already declares: a repeated attribute makes the XML invalid.
      let declared = Set(openingTagAttributes(anchorXML).keys)
      let missing = namespaces.filter { !declared.contains($0.key) }
        .map { #" \#($0.key)="\#(escapeXML($0.value))""# }.joined()
      if !missing.isEmpty, let close = anchorXML.firstIndex(of: ">") {
        let insertAt = anchorXML[..<close].hasSuffix("/") ? anchorXML.index(before: close) : close
        anchorXML.insert(contentsOf: missing, at: insertAt)
      }
      charts.append(
        ForeignChart(
          anchorXML: anchorXML,
          from: elements(in: anchor, localName: "from").first.flatMap(marker(in:)),
          to: elements(in: anchor, localName: "to").first.flatMap(marker(in:)),
          chartXML: Data(cleaned.utf8)
        ))
    }
    return charts
  }

  private static func marker(in xml: String) -> DrawingMarker? {
    func value(_ name: String) -> Int? {
      elements(in: xml, localName: name).first.flatMap { Int(innerText(of: $0)) }
    }
    guard let col = value("col"), let row = value("row") else { return nil }
    return DrawingMarker(
      col: col, colOffset: value("colOff") ?? 0, row: row, rowOffset: value("rowOff") ?? 0)
  }

  // MARK: - Export

  /// `<cols>`: widths, hidden columns and groups.
  static func columnsXML(_ sheet: Sheet) -> String {
    let extras = sheet.fileExtras
    var columns = Set(sheet.columnWidths.keys)
    columns.formUnion(extras.hiddenColumns)
    columns.formUnion(extras.columnOutlineLevels.keys)
    columns.formUnion(extras.collapsedColumns)
    guard !columns.isEmpty else { return "" }
    var items = ""
    var spanStart: Int?
    var spanEnd = 0
    var spanAttributes = ""
    func flush() {
      guard let start = spanStart else { return }
      items += #"<col min="\#(start + 1)" max="\#(spanEnd + 1)"\#(spanAttributes)/>"#
      spanStart = nil
    }
    for col in columns.sorted() where col >= 0 {
      var attributes = ""
      if let width = sheet.columnWidths[col] {
        attributes += #" width="\#(width / 7)" customWidth="1""#
      } else {
        // Excel reads a `<col>` with no width as zero wide: grouped columns opened hidden.
        attributes += #" width="\#(Workbook.defaultColumnWidth / 7)""#
      }
      if extras.hiddenColumns.contains(col) { attributes += #" hidden="1""# }
      if let level = extras.columnOutlineLevels[col] { attributes += #" outlineLevel="\#(level)""# }
      if extras.collapsedColumns.contains(col) { attributes += #" collapsed="1""# }
      // Neighboring columns with the same settings share one `<col>`, as files that hide
      // every column past the data do.
      if spanStart != nil, col == spanEnd + 1, attributes == spanAttributes {
        spanEnd = col
        continue
      }
      flush()
      spanStart = col
      spanEnd = col
      spanAttributes = attributes
    }
    flush()
    return "<cols>\(items)</cols>"
  }

  /// Rows the file marks hidden, grouped or collapsed, whether or not they hold cells.
  static func rowsWithFileAttributes(_ sheet: Sheet) -> Set<Int> {
    let extras = sheet.fileExtras
    var rows = extras.hiddenRows
    rows.formUnion(extras.rowOutlineLevels.keys)
    rows.formUnion(extras.collapsedRows)
    return rows
  }

  static func rowAttributesXML(_ sheet: Sheet, row: Int) -> String {
    let extras = sheet.fileExtras
    var attributes = ""
    if extras.hiddenRows.contains(row) { attributes += #" hidden="1""# }
    if let level = extras.rowOutlineLevels[row] { attributes += #" outlineLevel="\#(level)""# }
    if extras.collapsedRows.contains(row) { attributes += #" collapsed="1""# }
    return attributes
  }

  static func dataValidationsXML(_ rules: [DataValidationRule]) -> String {
    guard !rules.isEmpty else { return "" }
    let items = rules.map { rule -> String in
      let sqref = rule.ranges.map(rangeReference).joined(separator: " ")
      let attributes = rule.attributes.isEmpty ? "" : " \(rule.attributes)"
      if rule.body.isEmpty {
        return #"<dataValidation\#(attributes) sqref="\#(sqref)"/>"#
      }
      return #"<dataValidation\#(attributes) sqref="\#(sqref)">\#(rule.body)</dataValidation>"#
    }.joined()
    return #"<dataValidations count="\#(rules.count)">\#(items)</dataValidations>"#
  }

  /// Hyperlink elements, with external targets as `rId` + index (see `worksheetRelationships`).
  static func hyperlinksXML(_ links: [CellHyperlink], firstExternalID: Int) -> String {
    guard !links.isEmpty else { return "" }
    var external = firstExternalID
    let items = links.map { link -> String in
      var attributes = #" ref="\#(rangeReference(link.range))""#
      if link.target != nil {
        attributes += #" r:id="rId\#(external)""#
        external += 1
      }
      if let location = link.location { attributes += #" location="\#(escapeXML(location))""# }
      if let display = link.display { attributes += #" display="\#(escapeXML(display))""# }
      if let tooltip = link.tooltip { attributes += #" tooltip="\#(escapeXML(tooltip))""# }
      return "<hyperlink\(attributes)/>"
    }.joined()
    return "<hyperlinks>\(items)</hyperlinks>"
  }

  static func commentsXML(_ comments: [CellComment]) -> Data {
    var authors: [String] = []
    var authorIndex: [String: Int] = [:]
    for comment in comments where authorIndex[comment.author] == nil {
      authorIndex[comment.author] = authors.count
      authors.append(comment.author)
    }
    let authorsXML = authors.map { "<author>\(escapeXML($0))</author>" }.joined()
    let list = comments.map { comment -> String in
      let id = authorIndex[comment.author] ?? 0
      return
        #"<comment ref="\#(comment.address.a1)" authorId="\#(id)"><text><r><t xml:space="preserve">\#(escapeXML(comment.text))</t></r></text></comment>"#
    }.joined()
    let xml = """
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <comments xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><authors>\(authorsXML)</authors><commentList>\(list)</commentList></comments>
      """
    return Data(xml.utf8)
  }

  /// The legacy drawing other apps read to place comment boxes.
  static func commentsVML(_ comments: [CellComment]) -> Data {
    var shapes = ""
    for (index, comment) in comments.enumerated() {
      let row = comment.address.row
      let col = comment.address.col
      shapes += """
        <v:shape id="_x0000_s\(1025 + index)" type="#_x0000_t202" style="position:absolute;margin-left:59.25pt;margin-top:1.5pt;width:108pt;height:59.25pt;z-index:\(index + 1);visibility:hidden" fillcolor="#ffffe1" o:insetmode="auto"><v:fill color2="#ffffe1"/><v:shadow on="t" color="black" obscured="t"/><v:path o:connecttype="none"/><v:textbox style="mso-direction-alt:auto"><div style="text-align:left"></div></v:textbox><x:ClientData ObjectType="Note"><x:MoveWithCells/><x:SizeWithCells/><x:Anchor>\(col + 1), 15, \(row), 2, \(col + 3), 15, \(row + 4), 4</x:Anchor><x:AutoFill>False</x:AutoFill><x:Row>\(row)</x:Row><x:Column>\(col)</x:Column></x:ClientData></v:shape>
        """
    }
    let xml = """
      <xml xmlns:v="urn:schemas-microsoft-com:vml" xmlns:o="urn:schemas-microsoft-com:office:office" xmlns:x="urn:schemas-microsoft-com:office:excel"><o:shapelayout v:ext="edit"><o:idmap v:ext="edit" data="1"/></o:shapelayout><v:shapetype id="_x0000_t202" coordsize="21600,21600" o:spt="202" path="m,l,21600r21600,l21600,xe"><v:stroke joinstyle="miter"/><v:path gradientshapeok="t" o:connecttype="rect"/></v:shapetype>\(shapes)</xml>
      """
    return Data(xml.utf8)
  }

  /// A kept table with its `ref` (and its filter's) set to `range`.
  static func tableXML(_ table: SheetTable) -> Data {
    let ref = rangeReference(table.range)
    var xml = table.xml
    for name in ["table", "autoFilter"] {
      guard let tag = openTags(in: xml, localName: name).first else { continue }
      xml = xml.replacingOccurrences(of: tag, with: settingAttribute("ref", to: ref, in: tag))
    }
    return Data(xml.utf8)
  }

  static func foreignChartAnchorXML(_ chart: ForeignChart, relationshipID: String) -> String {
    func markerXML(_ prefix: String, _ name: String, _ marker: DrawingMarker) -> String {
      let p = prefix
      return
        "<\(p)\(name)><\(p)col>\(marker.col)</\(p)col><\(p)colOff>\(marker.colOffset)</\(p)colOff><\(p)row>\(marker.row)</\(p)row><\(p)rowOff>\(marker.rowOffset)</\(p)rowOff></\(p)\(name)>"
    }
    var xml = withoutRepeatedAttributes(
      chart.anchorXML.replacingOccurrences(
        of: ForeignChart.chartIDPlaceholder, with: relationshipID))
    for (name, marker) in [("from", chart.from), ("to", chart.to)] {
      guard let marker, let element = elements(in: xml, localName: name).first else { continue }
      let prefix = element.dropFirst().prefix { $0 != ":" && $0 != ">" && $0 != " " }
      let written = element.dropFirst().contains(":") && !prefix.isEmpty ? "\(prefix):" : ""
      xml = xml.replacingOccurrences(of: element, with: markerXML(written, name, marker))
    }
    return xml
  }

  /// The element with repeated attributes on its opening tag removed (the first is kept).
  /// Spark Grid 1.2 saved some chart anchors with namespaces declared twice, which other apps
  /// reject.
  public static func withoutRepeatedAttributes(_ element: String) -> String {
    guard let close = element.firstIndex(of: ">") else { return element }
    var openTag = String(element[...close])
    let pattern = #"\s([A-Za-z_][\w:.-]*)\s*=\s*("[^"]*"|'[^']*')"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return element }
    let ns = openTag as NSString
    var seen = Set<String>()
    var repeats: [NSRange] = []
    for match in regex.matches(in: openTag, range: NSRange(location: 0, length: ns.length)) {
      if !seen.insert(ns.substring(with: match.range(at: 1))).inserted {
        repeats.append(match.range)
      }
    }
    guard !repeats.isEmpty else { return element }
    for range in repeats.reversed() {
      if let swiftRange = Range(range, in: openTag) { openTag.removeSubrange(swiftRange) }
    }
    return openTag + element[element.index(after: close)...]
  }

  /// `<pivotCacheDefinition>` pointing at its records as `rId1`, or at nothing when there are none.
  static func pivotCacheDefinitionXML(_ cache: PivotCachePart) -> Data {
    guard var xml = String(data: cache.definitionXML, encoding: .utf8),
      let tag = openTags(in: xml, localName: "pivotCacheDefinition").first
    else { return cache.definitionXML }
    let rewritten =
      cache.recordsXML == nil
      ? removingAttribute("r:id", from: tag) : settingAttribute("r:id", to: "rId1", in: tag)
    xml = xml.replacingOccurrences(of: tag, with: rewritten)
    return Data(xml.utf8)
  }

  static func rangeReference(_ range: CellRange) -> String {
    let n = range.normalized
    let start = CellAddress(row: n.minRow, col: n.minCol).a1
    let end = CellAddress(row: n.maxRow, col: n.maxCol).a1
    return start == end ? start : "\(start):\(end)"
  }

  // MARK: - Small XML helpers

  struct Relationship {
    var type: String
    var target: String
    var external: Bool
  }

  static func relationshipsPath(for partPath: String) -> String {
    let file = (partPath as NSString).lastPathComponent
    let dir = (partPath as NSString).deletingLastPathComponent
    return dir.isEmpty ? "_rels/\(file).rels" : "\(dir)/_rels/\(file).rels"
  }

  static func partPath(_ target: String, base: String) -> String {
    if target.hasPrefix("/") { return String(target.dropFirst()) }
    return resolveZipPath(basePath: base, relativeTarget: target)
  }

  static func relationships(in xml: String) -> [String: Relationship] {
    var found: [String: Relationship] = [:]
    for attributes in tagAttributes(in: xml, localName: "Relationship") {
      guard let id = attributes["Id"], let type = attributes["Type"],
        let target = attributes["Target"]
      else { continue }
      found[id] = Relationship(
        type: type, target: target, external: attributes["TargetMode"] == "External")
    }
    return found
  }

  /// Whole elements with this local name, any prefix, outermost first. Nested same-name
  /// elements are part of their parent's text.
  static func elements(in xml: String, localName: String) -> [String] {
    var found: [String] = []
    var index = xml.startIndex
    while let open = nextTag(in: xml, from: index, localName: localName, closing: false) {
      let tagText = xml[open]
      if tagText.hasSuffix("/>") {
        found.append(String(tagText))
        index = open.upperBound
        continue
      }
      var depth = 1
      var cursor = open.upperBound
      var end: String.Index?
      while depth > 0 {
        let nextOpen = nextTag(in: xml, from: cursor, localName: localName, closing: false)
        guard let nextClose = nextTag(in: xml, from: cursor, localName: localName, closing: true)
        else { break }
        if let nextOpen, nextOpen.lowerBound < nextClose.lowerBound {
          if !xml[nextOpen].hasSuffix("/>") { depth += 1 }
          cursor = nextOpen.upperBound
        } else {
          depth -= 1
          cursor = nextClose.upperBound
          if depth == 0 { end = nextClose.upperBound }
        }
      }
      guard let end else { break }
      found.append(String(xml[open.lowerBound..<end]))
      index = end
    }
    return found
  }

  /// Opening tags with this local name, as written.
  static func openTags(in xml: String, localName: String) -> [String] {
    var found: [String] = []
    var index = xml.startIndex
    while let open = nextTag(in: xml, from: index, localName: localName, closing: false) {
      found.append(String(xml[open]))
      index = open.upperBound
    }
    return found
  }

  /// Attributes of each opening tag with this local name. Values are unescaped.
  static func tagAttributes(in xml: String, localName: String) -> [[String: String]] {
    openTags(in: xml, localName: localName).map(attributes(ofTag:))
  }

  static func attributes(ofTag tag: String) -> [String: String] {
    var result: [String: String] = [:]
    let scalars = Array(tag.unicodeScalars)
    var i = 0
    // Skip `<name`.
    while i < scalars.count, !isSpace(scalars[i]) { i += 1 }
    while i < scalars.count {
      while i < scalars.count, isSpace(scalars[i]) { i += 1 }
      let nameStart = i
      while i < scalars.count, scalars[i] != "=", !isSpace(scalars[i]), scalars[i] != "/",
        scalars[i] != ">"
      {
        i += 1
      }
      let name = String(String.UnicodeScalarView(scalars[nameStart..<i]))
      while i < scalars.count, isSpace(scalars[i]) { i += 1 }
      guard i < scalars.count, scalars[i] == "=" else {
        i += 1
        continue
      }
      i += 1
      while i < scalars.count, isSpace(scalars[i]) { i += 1 }
      guard i < scalars.count, scalars[i] == "\"" || scalars[i] == "'" else { break }
      let quote = scalars[i]
      i += 1
      let valueStart = i
      while i < scalars.count, scalars[i] != quote { i += 1 }
      let value = String(String.UnicodeScalarView(scalars[valueStart..<min(i, scalars.count)]))
      if !name.isEmpty { result[name] = decodeXMLEntities(value) }
      i += 1
    }
    return result
  }

  static func removingAttribute(_ name: String, from tag: String) -> String {
    let escaped = NSRegularExpression.escapedPattern(for: name)
    let pattern = #"\s\#(escaped)\s*=\s*("[^"]*"|'[^']*')"#
    return tag.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
  }

  static func settingAttribute(_ name: String, to value: String, in tag: String) -> String {
    let removed = removingAttribute(name, from: tag)
    let insertion = #" \#(name)="\#(escapeXML(value))""#
    // After the element name.
    guard
      let nameEnd = removed.dropFirst().firstIndex(where: {
        $0 == " " || $0 == "/" || $0 == ">" || $0 == "\n" || $0 == "\t"
      })
    else { return removed }
    var result = removed
    result.insert(contentsOf: insertion, at: nameEnd)
    return result
  }

  private static func innerText(of element: String) -> String {
    guard let open = element.firstIndex(of: ">"), !element[..<open].hasSuffix("/"),
      let close = element.range(of: "</", options: .backwards),
      element.index(after: open) <= close.lowerBound
    else { return "" }
    return decodeXMLEntities(String(element[element.index(after: open)..<close.lowerBound]))
  }

  private static func isSpace(_ scalar: Unicode.Scalar) -> Bool {
    scalar == " " || scalar == "\n" || scalar == "\t" || scalar == "\r"
  }

  /// The next `<name` or `<prefix:name` tag (or its closing tag), whole.
  private static func nextTag(
    in xml: String, from start: String.Index, localName: String, closing: Bool
  ) -> Range<String.Index>? {
    var index = start
    while let open = xml.range(of: "<", range: index..<xml.endIndex) {
      var cursor = open.upperBound
      let isClose = cursor < xml.endIndex && xml[cursor] == "/"
      if isClose { cursor = xml.index(after: cursor) }
      guard
        let nameEnd = xml[cursor...].firstIndex(where: {
          $0 == " " || $0 == ">" || $0 == "/" || $0 == "\t" || $0 == "\n" || $0 == "\r"
        })
      else { return nil }
      let rawName = xml[cursor..<nameEnd]
      let local = rawName.split(separator: ":").last.map(String.init) ?? String(rawName)
      guard let tagEnd = xml.range(of: ">", range: nameEnd..<xml.endIndex) else { return nil }
      if isClose == closing, local == localName {
        return open.lowerBound..<tagEnd.upperBound
      }
      index = tagEnd.upperBound
    }
    return nil
  }
}

// MARK: - Export parts and relationships

extension XLSXCodec {
  /// Relationship ids in a sheet's rels file. The app's drawing, when present, is `rId1`.
  struct WorksheetRelationshipIDs {
    var firstHyperlink: Int
    /// The comments part; its drawing is the next id.
    var comments: Int?
    var tables: [Int]
    var pivotTables: [Int]
  }

  static func worksheetRelationshipIDs(_ sheet: Sheet, hasDrawing: Bool)
    -> WorksheetRelationshipIDs
  {
    let extras = sheet.fileExtras
    var next = hasDrawing ? 2 : 1
    let firstHyperlink = next
    next += extras.hyperlinks.filter { $0.target != nil }.count
    var comments: Int?
    if !extras.comments.isEmpty {
      comments = next
      next += 2
    }
    let tables = Array(next..<(next + extras.tables.count))
    next += extras.tables.count
    let pivotTables = Array(next..<(next + extras.pivotTables.count))
    return WorksheetRelationshipIDs(
      firstHyperlink: firstHyperlink, comments: comments, tables: tables, pivotTables: pivotTables)
  }

  /// Global part numbers, so tables and pivot tables on different sheets get different files.
  struct KeptPartNumbers {
    var firstTable: [Int]
    var firstPivotTable: [Int]
    /// Pivot cache file number by cache id.
    var cacheNumbers: [Int: Int]
  }

  static func keptPartNumbers(_ workbook: Workbook) -> KeptPartNumbers {
    var firstTable: [Int] = []
    var firstPivot: [Int] = []
    var table = 1
    var pivot = 1
    for sheet in workbook.sheets {
      firstTable.append(table)
      firstPivot.append(pivot)
      table += sheet.fileExtras.tables.count
      pivot += sheet.fileExtras.pivotTables.count
    }
    var cacheNumbers: [Int: Int] = [:]
    for (index, cache) in workbook.pivotCaches.enumerated() where cacheNumbers[cache.cacheID] == nil
    {
      cacheNumbers[cache.cacheID] = index + 1
    }
    return KeptPartNumbers(
      firstTable: firstTable, firstPivotTable: firstPivot, cacheNumbers: cacheNumbers)
  }

  /// The sheet's rels file, after writing the comment, table and pivot table parts it points at.
  static func worksheetRelsXML(
    _ sheet: Sheet,
    sheetIndex: Int,
    hasDrawing: Bool,
    numbers: KeptPartNumbers,
    into files: inout [String: Data]
  ) -> Data? {
    let extras = sheet.fileExtras
    let ids = worksheetRelationshipIDs(sheet, hasDrawing: hasDrawing)
    let sheetNum = sheetIndex + 1
    let base = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
    var rels = ""
    if hasDrawing {
      rels +=
        #"<Relationship Id="rId1" Type="\#(base)/drawing" Target="../drawings/drawing\#(sheetNum).xml"/>"#
    }
    var linkID = ids.firstHyperlink
    for link in extras.hyperlinks {
      guard let target = link.target else { continue }
      rels +=
        #"<Relationship Id="rId\#(linkID)" Type="\#(base)/hyperlink" Target="\#(escapeXML(target))" TargetMode="External"/>"#
      linkID += 1
    }
    if let comments = ids.comments {
      files["xl/comments\(sheetNum).xml"] = commentsXML(extras.comments)
      files["xl/drawings/vmlDrawing\(sheetNum).vml"] = commentsVML(extras.comments)
      rels +=
        #"<Relationship Id="rId\#(comments)" Type="\#(base)/comments" Target="../comments\#(sheetNum).xml"/>"#
      rels +=
        #"<Relationship Id="rId\#(comments + 1)" Type="\#(base)/vmlDrawing" Target="../drawings/vmlDrawing\#(sheetNum).vml"/>"#
    }
    let firstTable =
      numbers.firstTable.indices.contains(sheetIndex) ? numbers.firstTable[sheetIndex] : 1
    for (offset, table) in extras.tables.enumerated() {
      let number = firstTable + offset
      files["xl/tables/table\(number).xml"] = tableXML(table)
      rels +=
        #"<Relationship Id="rId\#(ids.tables[offset])" Type="\#(base)/table" Target="../tables/table\#(number).xml"/>"#
    }
    let firstPivot =
      numbers.firstPivotTable.indices.contains(sheetIndex) ? numbers.firstPivotTable[sheetIndex] : 1
    for (offset, pivot) in extras.pivotTables.enumerated() {
      let number = firstPivot + offset
      files["xl/pivotTables/pivotTable\(number).xml"] = pivot.xml
      if let cache = numbers.cacheNumbers[pivot.cacheID] {
        files["xl/pivotTables/_rels/pivotTable\(number).xml.rels"] = relationshipsFile(
          #"<Relationship Id="rId1" Type="\#(base)/pivotCacheDefinition" Target="../pivotCache/pivotCacheDefinition\#(cache).xml"/>"#
        )
      }
      rels +=
        #"<Relationship Id="rId\#(ids.pivotTables[offset])" Type="\#(base)/pivotTable" Target="../pivotTables/pivotTable\#(number).xml"/>"#
    }
    return rels.isEmpty ? nil : relationshipsFile(rels)
  }

  /// Pivot cache parts and their workbook relationships, numbered from `firstID`.
  static func appendPivotCacheParts(
    _ workbook: Workbook, numbers: KeptPartNumbers, firstID: Int, into files: inout [String: Data]
  ) -> (rels: String, element: String) {
    guard !workbook.pivotCaches.isEmpty else { return ("", "") }
    let base = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
    var rels = ""
    var caches = ""
    var written = Set<Int>()
    for cache in workbook.pivotCaches {
      guard let number = numbers.cacheNumbers[cache.cacheID], written.insert(number).inserted
      else { continue }
      files["xl/pivotCache/pivotCacheDefinition\(number).xml"] = pivotCacheDefinitionXML(cache)
      if let records = cache.recordsXML {
        files["xl/pivotCache/pivotCacheRecords\(number).xml"] = records
        files["xl/pivotCache/_rels/pivotCacheDefinition\(number).xml.rels"] = relationshipsFile(
          #"<Relationship Id="rId1" Type="\#(base)/pivotCacheRecords" Target="pivotCacheRecords\#(number).xml"/>"#
        )
      }
      let id = firstID + number - 1
      rels +=
        #"<Relationship Id="rId\#(id)" Type="\#(base)/pivotCacheDefinition" Target="pivotCache/pivotCacheDefinition\#(number).xml"/>"#
      caches += #"<pivotCache cacheId="\#(cache.cacheID)" r:id="rId\#(id)"/>"#
    }
    return (rels, "<pivotCaches>\(caches)</pivotCaches>")
  }

  /// Content type overrides for the kept parts already in `files`.
  static func keptPartContentTypes(_ files: [String: Data]) -> String {
    let types: [(prefix: String, type: String)] = [
      ("xl/comments", "application/vnd.openxmlformats-officedocument.spreadsheetml.comments+xml"),
      ("xl/tables/table", "application/vnd.openxmlformats-officedocument.spreadsheetml.table+xml"),
      (
        "xl/pivotTables/pivotTable",
        "application/vnd.openxmlformats-officedocument.spreadsheetml.pivotTable+xml"
      ),
      (
        "xl/pivotCache/pivotCacheDefinition",
        "application/vnd.openxmlformats-officedocument.spreadsheetml.pivotCacheDefinition+xml"
      ),
      (
        "xl/pivotCache/pivotCacheRecords",
        "application/vnd.openxmlformats-officedocument.spreadsheetml.pivotCacheRecords+xml"
      ),
      ("xl/metadata.xml", sheetMetadataContentType),
    ]
    var overrides = ""
    for path in files.keys.sorted() where path.hasSuffix(".xml") && !path.contains("/_rels/") {
      guard let type = types.first(where: { path.hasPrefix($0.prefix) })?.type else { continue }
      overrides += #"<Override PartName="/\#(path)" ContentType="\#(type)"/>"#
    }
    return overrides
  }

  static func relationshipsFile(_ body: String) -> Data {
    Data(
      """
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\(body)</Relationships>
      """.utf8)
  }
}

// MARK: - Table columns

extension XLSXCodec {
  /// A kept table's XML after `count` columns are inserted at `offset` (0 is the table's first
  /// column), with `names` for the new columns. Filter columns after the insert move right.
  public static func tableXML(
    _ xml: String, insertingColumns count: Int, atOffset offset: Int, names: [String]
  ) -> String {
    guard count > 0, var columns = tableColumnElements(xml) else { return xml }
    let ids = columns.compactMap { column in openingTagAttributes(column)["id"].flatMap { Int($0) }
    }
    var nextID = (ids.max() ?? 0) + 1
    var inserted: [String] = []
    for index in 0..<count {
      let name = names.indices.contains(index) ? names[index] : "Column\(nextID)"
      inserted.append(#"<tableColumn id="\#(nextID)" name="\#(escapeXML(name))"/>"#)
      nextID += 1
    }
    let at = min(max(0, offset), columns.count)
    columns.insert(contentsOf: inserted, at: at)
    let shifted = shiftingFilterColumns(xml) { $0 >= at ? $0 + count : $0 }
    return replacingTableColumns(shifted, with: columns)
  }

  /// A kept table's XML after `count` columns from `offset` are deleted, or nil when no column
  /// is left. Filters on deleted columns go; the rest move left.
  public static func tableXML(_ xml: String, removingColumns count: Int, atOffset offset: Int)
    -> String?
  {
    guard count > 0, var columns = tableColumnElements(xml) else { return xml }
    let lower = max(0, offset)
    let upper = min(columns.count, offset + count)
    guard lower < upper else { return xml }
    columns.removeSubrange(lower..<upper)
    guard !columns.isEmpty else { return nil }
    let removed = upper - lower
    let shifted = shiftingFilterColumns(xml) { colID in
      if colID >= lower && colID < upper { return nil }
      return colID >= upper ? colID - removed : colID
    }
    return replacingTableColumns(shifted, with: columns)
  }

  /// Names of a kept table's columns, in order.
  public static func tableColumnNames(_ xml: String) -> [String] {
    (tableColumnElements(xml) ?? []).compactMap { openingTagAttributes($0)["name"] }
  }

  private static func openingTagAttributes(_ element: String) -> [String: String] {
    guard let end = element.firstIndex(of: ">") else { return [:] }
    return attributes(ofTag: String(element[...end]))
  }

  /// The name a kept table goes by in formulas and the name box, such as `Deals`.
  public static func tableName(_ xml: String) -> String? {
    let attributes = tagAttributes(in: xml, localName: "table").first
    return attributes?["displayName"] ?? attributes?["name"]
  }

  /// False when the table says it has no header row.
  public static func tableHasHeaderRow(_ xml: String) -> Bool {
    tagAttributes(in: xml, localName: "table").first?["headerRowCount"] != "0"
  }

  private static func tableColumnElements(_ xml: String) -> [String]? {
    guard let list = elements(in: xml, localName: "tableColumns").first else { return nil }
    return elements(in: list, localName: "tableColumn")
  }

  private static func replacingTableColumns(_ xml: String, with columns: [String]) -> String {
    guard let list = elements(in: xml, localName: "tableColumns").first,
      let open = openTags(in: list, localName: "tableColumns").first
    else { return xml }
    var opening = settingAttribute("count", to: String(columns.count), in: open)
    var closing = "</tableColumns>"
    if open.hasSuffix("/>") {
      opening = String(opening.dropLast(2)) + ">"
    } else if let lastClose = list.range(of: "</", options: .backwards) {
      closing = String(list[lastClose.lowerBound...])
    }
    let rebuilt = opening + columns.joined() + closing
    return xml.replacingOccurrences(of: list, with: rebuilt)
  }

  /// Applies `move` to each `filterColumn colId`; a nil result removes that filter.
  private static func shiftingFilterColumns(_ xml: String, _ move: (Int) -> Int?) -> String {
    var result = xml
    for element in elements(in: xml, localName: "filterColumn") {
      guard let open = openTags(in: element, localName: "filterColumn").first,
        let colID = attributes(ofTag: open)["colId"].flatMap({ Int($0) })
      else { continue }
      if let moved = move(colID) {
        let rewritten = element.replacingOccurrences(
          of: open, with: settingAttribute("colId", to: String(moved), in: open))
        result = result.replacingOccurrences(of: element, with: rewritten)
      } else {
        result = result.replacingOccurrences(of: element, with: "")
      }
    }
    return result
  }
}
