import CoreXLSX
import Formula
import Foundation
import GridCore
import Model
import NumberFormat

extension XLSXCodec {
  // MARK: - Sheet extras (freeze, autofilter, CF, merges, theme) from / into worksheet XML

  public static func importFreezePanes(from worksheet: Worksheet, into sheet: inout Sheet) {
    guard let pane = worksheet.sheetViews?.items.first?.pane else { return }
    let state = pane.state?.lowercased() ?? ""
    guard state == "frozen" || state == "frozensplit" else { return }
    if let y = pane.ySplit.flatMap(Double.init), y > 0 {
      sheet.frozenRows = Int(y.rounded(.down))
    }
    if let x = pane.xSplit.flatMap(Double.init), x > 0 {
      sheet.frozenColumns = Int(x.rounded(.down))
    }
  }

  public static func importMergeCells(from worksheet: Worksheet, into sheet: inout Sheet) {
    for merge in worksheet.mergeCells?.items ?? [] {
      guard let range = parseCellRange(merge.reference) else { continue }
      sheet.mergedRanges.append(range)
    }
  }

  public static func importThemeScheme(archiveData: Data) -> ThemeColorScheme {
    guard let xml = zipEntryString(archiveData: archiveData, entryPath: "xl/theme/theme1.xml")
    else { return ThemeColorScheme() }
    return ThemeColorScheme.parse(themeXML: xml)
  }

  public static func importThemeStyleColors(
    archiveData: Data,
    scheme: ThemeColorScheme
  ) -> ThemeResolvedStyleColors {
    guard let xml = zipEntryString(archiveData: archiveData, entryPath: "xl/styles.xml")
    else { return ThemeResolvedStyleColors() }
    return ThemeColorLookup.parseStyleColors(stylesXML: xml, scheme: scheme)
  }

  public static func importAutoFilter(
    into sheet: inout Sheet, archiveData: Data, worksheetPath: String
  ) {
    guard let xml = zipEntryString(archiveData: archiveData, entryPath: worksheetPath) else {
      return
    }
    guard
      let blockRange = xml.range(
        of: #"<autoFilter\b[^>]*(?:/>|>[\s\S]*?</autoFilter>)"#,
        options: .regularExpression
      )
    else { return }
    let block = String(xml[blockRange])
    guard let refRange = block.range(of: #"ref="[^"]+""#, options: .regularExpression) else {
      return
    }
    let quoted = String(block[refRange])
    guard let q1 = quoted.firstIndex(of: "\""),
      let q2 = quoted.lastIndex(of: "\""),
      q1 < q2
    else { return }
    let ref = String(quoted[quoted.index(after: q1)..<q2])
    guard let range = parseCellRange(ref) else { return }

    var selected: [Int: Set<String>] = [:]
    let colPattern = #"<filterColumn\b([^>]*)>(.*?)</filterColumn>"#
    if let colRegex = try? NSRegularExpression(
      pattern: colPattern, options: [.dotMatchesLineSeparators])
    {
      let ns = block as NSString
      for match in colRegex.matches(in: block, range: NSRange(location: 0, length: ns.length)) {
        let attrs = ns.substring(with: match.range(at: 1))
        let body = ns.substring(with: match.range(at: 2))
        guard let colId = attributeValue(attrs, name: "colId").flatMap(Int.init) else { continue }
        let absoluteCol = range.normalized.minCol + colId
        var values = Set<String>()
        let filterPattern = #"<filter\b([^>]*)/?\s*>"#
        if let filterRegex = try? NSRegularExpression(pattern: filterPattern) {
          let bodyNS = body as NSString
          for fMatch in filterRegex.matches(
            in: body, range: NSRange(location: 0, length: bodyNS.length))
          {
            let fAttrs = bodyNS.substring(with: fMatch.range(at: 1))
            if let val = attributeValue(fAttrs, name: "val") {
              values.insert(decodeXMLEntities(val))
            }
          }
        }
        if !values.isEmpty {
          selected[absoluteCol] = values
        }
      }
    }
    sheet.autoFilter = SheetFilterState(range: range, selectedValuesByColumn: selected)
  }

  public static func importConditionalFormatting(
    into sheet: inout Sheet,
    archiveData: Data,
    worksheetPath: String,
    dxfs: [ConditionalFormatStyle],
    themeScheme: ThemeColorScheme
  ) {
    guard let xml = zipEntryString(archiveData: archiveData, entryPath: worksheetPath) else {
      return
    }
    importConditionalFormatting(
      into: &sheet, worksheetXML: xml, dxfs: dxfs, themeScheme: themeScheme)
  }

  public static func importConditionalFormatting(
    into sheet: inout Sheet,
    worksheetXML xml: String,
    dxfs: [ConditionalFormatStyle],
    themeScheme: ThemeColorScheme
  ) {
    let x14Blocks = extractX14ConditionalFormattingBlocks(from: xml)
    if !x14Blocks.isEmpty {
      let before = sheet.conditionalFormats.count
      for block in x14Blocks {
        importConditionalFormattingBlock(
          sqref: block.sqref,
          body: block.body,
          into: &sheet,
          dxfs: dxfs,
          themeScheme: themeScheme,
          x14Formulas: true
        )
      }
      if sheet.conditionalFormats.count > before {
        return
      }
    }

    let blockPattern = #"<conditionalFormatting\b([^>]*)>(.*?)</conditionalFormatting>"#
    guard
      let blockRegex = try? NSRegularExpression(
        pattern: blockPattern,
        options: [.dotMatchesLineSeparators]
      )
    else { return }
    let nsxml = xml as NSString
    let full = NSRange(location: 0, length: nsxml.length)

    for match in blockRegex.matches(in: xml, options: [], range: full) {
      let attrs = nsxml.substring(with: match.range(at: 1))
      let body = nsxml.substring(with: match.range(at: 2))
      guard let sqref = attributeValue(attrs, name: "sqref") else { continue }
      importConditionalFormattingBlock(
        sqref: sqref,
        body: body,
        into: &sheet,
        dxfs: dxfs,
        themeScheme: themeScheme,
        x14Formulas: false
      )
    }
  }

  private struct ConditionalFormattingBlock {
    public var sqref: String
    public var body: String
  }

  private static func extractX14ConditionalFormattingBlocks(from xml: String)
    -> [ConditionalFormattingBlock]
  {
    let blockPattern = #"<x14:conditionalFormatting\b[^>]*>(.*?)</x14:conditionalFormatting>"#
    guard
      let blockRegex = try? NSRegularExpression(
        pattern: blockPattern,
        options: [.dotMatchesLineSeparators]
      )
    else { return [] }
    let nsxml = xml as NSString
    let full = NSRange(location: 0, length: nsxml.length)
    var blocks: [ConditionalFormattingBlock] = []
    for match in blockRegex.matches(in: xml, options: [], range: full) {
      let body = nsxml.substring(with: match.range(at: 1))
      let sqref = xmSqref(in: body) ?? ""
      guard !sqref.isEmpty else { continue }
      blocks.append(ConditionalFormattingBlock(sqref: sqref, body: body))
    }
    return blocks
  }

  private static func xmSqref(in body: String) -> String? {
    guard
      let range = body.range(
        of: #"<xm:sqref>([\s\S]*?)</xm:sqref>"#,
        options: .regularExpression
      )
    else { return nil }
    let token = String(body[range])
    guard let open = token.range(of: ">"), let close = token.range(of: "</xm:sqref>") else {
      return nil
    }
    return String(token[open.upperBound..<close.lowerBound]).trimmingCharacters(
      in: .whitespacesAndNewlines)
  }

  private static func importConditionalFormattingBlock(
    sqref: String,
    body: String,
    into sheet: inout Sheet,
    dxfs: [ConditionalFormatStyle],
    themeScheme: ThemeColorScheme,
    x14Formulas: Bool
  ) {
    let ranges =
      sqref
      .split(whereSeparator: \.isWhitespace)
      .compactMap { parseCellRange(String($0)) }
    guard !ranges.isEmpty else { return }

    let rulePattern =
      x14Formulas
      ? #"<x14:cfRule\b([^>]*)>(.*?)</x14:cfRule>|<x14:cfRule\b([^>]*)/>"#
      : #"<cfRule\b([^>]*)>(.*?)</cfRule>|<cfRule\b([^>]*)/>"#
    guard
      let ruleRegex = try? NSRegularExpression(
        pattern: rulePattern,
        options: [.dotMatchesLineSeparators]
      )
    else { return }
    let bodyNS = body as NSString
    let bodyFull = NSRange(location: 0, length: bodyNS.length)

    for ruleMatch in ruleRegex.matches(in: body, options: [], range: bodyFull) {
      let ruleAttrs: String
      let ruleBody: String
      if ruleMatch.range(at: 1).location != NSNotFound {
        ruleAttrs = bodyNS.substring(with: ruleMatch.range(at: 1))
        ruleBody = bodyNS.substring(with: ruleMatch.range(at: 2))
      } else {
        ruleAttrs = bodyNS.substring(with: ruleMatch.range(at: 3))
        ruleBody = ""
      }

      let type = attributeValue(ruleAttrs, name: "type") ?? ""
      let stop = attributeValue(ruleAttrs, name: "stopIfTrue") != "0"
      let formulas = x14Formulas ? xmFormulaValues(in: ruleBody) : formulaValues(in: ruleBody)
      let inlineStyle = parseDxfBody(ruleBody, themeScheme: themeScheme)
      let dxfId = attributeValue(ruleAttrs, name: "dxfId").flatMap(Int.init) ?? 0
      let referencedStyle = (dxfId >= 0 && dxfId < dxfs.count) ? dxfs[dxfId] : .redFill
      let style = inlineStyle.hasAny ? inlineStyle : referencedStyle

      let predicate: ConditionalFormatPredicate?
      switch type {
      case "expression":
        guard let formula = formulas.first, !formula.isEmpty else { continue }
        predicate = .formula(formula.hasPrefix("=") ? formula : "=\(formula)")
      case "cellIs":
        let op = attributeValue(ruleAttrs, name: "operator") ?? ""
        let first = ranges[0].normalized
        predicate = cellIsPredicate(
          operator: op, formulas: formulas,
          origin: CellAddress(row: first.minRow, col: first.minCol))
      case "containsText":
        if let text = attributeValue(ruleAttrs, name: "text") ?? formulas.first {
          predicate = .textContains(text)
        } else {
          predicate = nil
        }
      case "containsBlanks":
        predicate = .blanks
      case "notContainsBlanks":
        predicate = .nonBlanks
      case "colorScale":
        predicate = colorScalePredicate(in: ruleBody, themeScheme: themeScheme)
      case "dataBar":
        predicate = dataBarPredicate(in: ruleBody, themeScheme: themeScheme)
      case "iconSet":
        predicate = iconSetPredicate(in: ruleBody, ruleAttrs: ruleAttrs)
      default:
        predicate = nil
      }

      guard let predicate else { continue }
      let ruleStyle: ConditionalFormatStyle
      switch predicate {
      case .colorScale, .dataBar, .iconSet:
        ruleStyle = ConditionalFormatStyle()
      default:
        ruleStyle = style
      }
      for range in ranges {
        sheet.conditionalFormats.append(
          ConditionalFormatRule(
            range: range, stopIfTrue: stop, predicate: predicate, style: ruleStyle)
        )
      }
    }
  }

  public static func importDifferentialFormats(
    archiveData: Data,
    themeScheme: ThemeColorScheme
  ) -> [ConditionalFormatStyle] {
    guard let xml = zipEntryString(archiveData: archiveData, entryPath: "xl/styles.xml") else {
      return []
    }
    guard
      let dxfsRange = xml.range(of: #"<dxfs\b[^>]*>[\s\S]*?</dxfs>"#, options: .regularExpression)
    else { return [] }
    let dxfsXML = String(xml[dxfsRange])
    let dxfPattern = #"<dxf>(.*?)</dxf>"#
    guard
      let regex = try? NSRegularExpression(
        pattern: dxfPattern,
        options: [.dotMatchesLineSeparators]
      )
    else { return [] }
    let ns = dxfsXML as NSString
    var styles: [ConditionalFormatStyle] = []
    for match in regex.matches(
      in: dxfsXML, options: [], range: NSRange(location: 0, length: ns.length))
    {
      let body = ns.substring(with: match.range(at: 1))
      styles.append(parseDxfBody(body, themeScheme: themeScheme))
    }
    return styles
  }

  public static func parseDxfBody(_ body: String, themeScheme: ThemeColorScheme)
    -> ConditionalFormatStyle
  {
    var style = ConditionalFormatStyle()
    // `<b/>` is on. `<b val="0"/>` is off. A tag's presence is not "on" —
    // Excel writes val="0" for an unchecked Bold box, next to the fill and text color.
    style.bold = fontToggle(in: body, element: "b")
    style.italic = fontToggle(in: body, element: "i")
    if let fill = firstColor(in: body, near: "bgColor", themeScheme: themeScheme)
      ?? firstColor(in: body, near: "fgColor", themeScheme: themeScheme)
      ?? firstColor(in: body, near: "patternFill", themeScheme: themeScheme)
    {
      style.fillColor = fill
    }
    if let fontBlock = body.range(
      of: #"<(?:x14:)?font\b[^>]*>[\s\S]*?</(?:x14:)?font>"#,
      options: .regularExpression
    ) {
      if let text = firstColor(in: String(body[fontBlock]), near: "color", themeScheme: themeScheme)
      {
        style.textColor = text
      }
    }
    return style
  }

  public static func underlinedFontIndices(archiveData: Data) -> Set<Int> {
    guard let xml = zipEntryString(archiveData: archiveData, entryPath: "xl/styles.xml") else {
      return []
    }
    guard
      let fontsRange = xml.range(
        of: #"<fonts\b[^>]*>[\s\S]*?</fonts>"#, options: .regularExpression)
    else { return [] }
    let fontsXML = String(xml[fontsRange])
    let fontPattern = #"<font>(.*?)</font>"#
    guard
      let regex = try? NSRegularExpression(
        pattern: fontPattern,
        options: [.dotMatchesLineSeparators]
      )
    else { return [] }
    let ns = fontsXML as NSString
    var underlined = Set<Int>()
    for (index, match) in regex.matches(
      in: fontsXML,
      options: [],
      range: NSRange(location: 0, length: ns.length)
    ).enumerated() {
      let body = ns.substring(with: match.range(at: 1))
      if body.contains("<u") {
        underlined.insert(index)
      }
    }
    return underlined
  }

  public static func importSparkCharts(into sheet: inout Sheet, archiveData: Data, sheetIndex: Int)
  {
    let path = "xl/sparkGrid/charts\(sheetIndex + 1).json"
    guard let xml = zipEntryString(archiveData: archiveData, entryPath: path),
      let data = xml.data(using: .utf8),
      let charts = try? JSONDecoder().decode([SheetChart].self, from: data)
    else { return }
    sheet.charts = charts.map { $0.positionedUnderData() }
  }

  public static func sheetViewsXML(frozenRows: Int, frozenColumns: Int) -> String {
    guard frozenRows > 0 || frozenColumns > 0 else { return "" }
    let topLeft = CellAddress(row: frozenRows, col: frozenColumns).a1
    return """
      <sheetViews><sheetView workbookViewId="0"><pane xSplit="\(frozenColumns)" ySplit="\(frozenRows)" topLeftCell="\(topLeft)" activePane="bottomRight" state="frozen"/></sheetView></sheetViews>
      """
  }

  public static func mergeCellsXML(_ ranges: [CellRange]) -> String {
    guard !ranges.isEmpty else { return "" }
    let items = ranges.map { range -> String in
      let n = range.normalized
      let start = CellAddress(row: n.minRow, col: n.minCol).a1
      let end = CellAddress(row: n.maxRow, col: n.maxCol).a1
      let ref = start == end ? start : "\(start):\(end)"
      return #"<mergeCell ref="\#(ref)"/>"#
    }.joined()
    return #"<mergeCells count="\#(ranges.count)">\#(items)</mergeCells>"#
  }

  public static func autoFilterXML(_ filter: SheetFilterState?) -> String {
    guard let filter else { return "" }
    let n = filter.range.normalized
    let start = CellAddress(row: n.minRow, col: n.minCol).a1
    let end = CellAddress(row: n.maxRow, col: n.maxCol).a1
    let ref = start == end ? start : "\(start):\(end)"
    var columnsXML = ""
    for col in n.minCol...n.maxCol {
      let colId = col - n.minCol
      if let rules = filter.rulesByColumn[col], let body = filterRulesXML(rules) {
        columnsXML += #"<filterColumn colId="\#(colId)">\#(body)</filterColumn>"#
        continue
      }
      guard let values = filter.selectedValuesByColumn[col], !values.isEmpty else { continue }
      let filters = values.sorted().map { #"<filter val="\#(escapeXML($0))"/>"# }.joined()
      columnsXML +=
        #"<filterColumn colId="\#(colId)"><filters>\#(filters)</filters></filterColumn>"#
    }
    if columnsXML.isEmpty {
      return #"<autoFilter ref="\#(ref)"/>"#
    }
    return #"<autoFilter ref="\#(ref)">\#(columnsXML)</autoFilter>"#
  }

  /// A column's rules as `customFilters` (at most two) or `top10`.
  static func filterRulesXML(_ rules: ColumnFilterRules) -> String? {
    if let rule = rules.rules.first(where: { $0.kind == .top || $0.kind == .bottom }),
      let count = Int(rule.value.trimmingCharacters(in: .whitespaces)), count > 0
    {
      let top = rule.kind == .top ? "1" : "0"
      return #"<top10 top="\#(top)" val="\#(count)"/>"#
    }
    func wildcardSafe(_ text: String) -> String {
      text.replacingOccurrences(of: "~", with: "~~")
        .replacingOccurrences(of: "*", with: "~*")
        .replacingOccurrences(of: "?", with: "~?")
    }
    var items: [(op: String?, val: String)] = []
    for rule in rules.rules {
      let v = rule.value.trimmingCharacters(in: .whitespaces)
      switch rule.kind {
      case .equals: items.append((nil, v))
      case .notEquals: items.append(("notEqual", v))
      case .contains: items.append((nil, "*\(wildcardSafe(v))*"))
      case .notContains: items.append(("notEqual", "*\(wildcardSafe(v))*"))
      case .beginsWith: items.append((nil, "\(wildcardSafe(v))*"))
      case .endsWith: items.append((nil, "*\(wildcardSafe(v))"))
      case .greaterThan: items.append(("greaterThan", v))
      case .greaterOrEqual: items.append(("greaterThanOrEqual", v))
      case .lessThan: items.append(("lessThan", v))
      case .lessOrEqual: items.append(("lessThanOrEqual", v))
      case .between:
        items.append(("greaterThanOrEqual", v))
        items.append(("lessThanOrEqual", rule.value2.trimmingCharacters(in: .whitespaces)))
      case .top, .bottom: break
      }
    }
    items = Array(items.prefix(2))
    guard !items.isEmpty else { return nil }
    let between = rules.rules.contains { $0.kind == .between }
    let and = (rules.matchAll || between) && items.count > 1 ? #" and="1""# : ""
    let filters = items.map { item -> String in
      let op = item.op.map { #" operator="\#($0)""# } ?? ""
      return #"<customFilter\#(op) val="\#(escapeXML(item.val))"/>"#
    }.joined()
    return "<customFilters\(and)>\(filters)</customFilters>"
  }

  /// Rules from a column's `customFilters` or `top10`, as `filterRulesXML` writes them.
  public static func filterRules(
    customFilters: [(op: String?, val: String)], matchAll: Bool, top10: (top: Bool, count: Int)?
  ) -> ColumnFilterRules? {
    if let top10 {
      return ColumnFilterRules(
        rules: [.init(kind: top10.top ? .top : .bottom, value: String(top10.count))])
    }
    func unescaped(_ text: String) -> String {
      var out = ""
      var escaping = false
      for ch in text {
        if escaping {
          out.append(ch)
          escaping = false
        } else if ch == "~" {
          escaping = true
        } else {
          out.append(ch)
        }
      }
      return out
    }
    func isWildcard(_ text: String, at index: String.Index) -> Bool {
      guard text[index] == "*" else { return false }
      return index == text.startIndex || text[text.index(before: index)] != "~"
    }
    let filters = Array(customFilters.prefix(2))
    if filters.count == 2, matchAll, filters[0].op == "greaterThanOrEqual",
      filters[1].op == "lessThanOrEqual"
    {
      return ColumnFilterRules(
        rules: [.init(kind: .between, value: filters[0].val, value2: filters[1].val)])
    }
    var rules: [ColumnFilterRules.Rule] = []
    for filter in filters {
      let v = filter.val
      let starts = !v.isEmpty && isWildcard(v, at: v.startIndex)
      let ends = v.count > 1 && isWildcard(v, at: v.index(before: v.endIndex))
      let inner: String = {
        var t = Substring(v)
        if starts { t = t.dropFirst() }
        if ends { t = t.dropLast() }
        return unescaped(String(t))
      }()
      switch filter.op ?? "equal" {
      case "equal":
        if starts && ends {
          rules.append(.init(kind: .contains, value: inner))
        } else if ends {
          rules.append(.init(kind: .beginsWith, value: inner))
        } else if starts {
          rules.append(.init(kind: .endsWith, value: inner))
        } else {
          rules.append(.init(kind: .equals, value: inner))
        }
      case "notEqual":
        rules.append(.init(kind: starts && ends ? .notContains : .notEquals, value: inner))
      case "greaterThan": rules.append(.init(kind: .greaterThan, value: v))
      case "greaterThanOrEqual": rules.append(.init(kind: .greaterOrEqual, value: v))
      case "lessThan": rules.append(.init(kind: .lessThan, value: v))
      case "lessThanOrEqual": rules.append(.init(kind: .lessOrEqual, value: v))
      default: continue
      }
    }
    return rules.isEmpty ? nil : ColumnFilterRules(rules: rules, matchAll: matchAll)
  }

  public static func conditionalFormattingXML(
    _ rules: [ConditionalFormatRule],
    dxfIndex: (ConditionalFormatStyle) -> Int
  ) -> String {
    guard !rules.isEmpty else { return "" }
    var grouped: [String: [(ConditionalFormatRule, Int)]] = [:]
    for (priority, rule) in rules.enumerated() {
      let n = rule.range.normalized
      let start = CellAddress(row: n.minRow, col: n.minCol).a1
      let end = CellAddress(row: n.maxRow, col: n.maxCol).a1
      let sqref = start == end ? start : "\(start):\(end)"
      grouped[sqref, default: []].append((rule, priority + 1))
    }

    var xml = ""
    for (sqref, items) in grouped.sorted(by: { $0.key < $1.key }) {
      xml += #"<conditionalFormatting sqref="\#(sqref)">"#
      for (rule, priority) in items {
        let stop = rule.stopIfTrue ? "" : #" stopIfTrue="0""#
        switch rule.predicate {
        case .greaterThan(let v):
          let dxfId = dxfIndex(rule.style)
          xml +=
            #"<cfRule type="cellIs" dxfId="\#(dxfId)" priority="\#(priority)"\#(stop) operator="greaterThan"><formula>\#(escapeXML(stringFromNumber(v)))</formula></cfRule>"#
        case .lessThan(let v):
          let dxfId = dxfIndex(rule.style)
          xml +=
            #"<cfRule type="cellIs" dxfId="\#(dxfId)" priority="\#(priority)"\#(stop) operator="lessThan"><formula>\#(escapeXML(stringFromNumber(v)))</formula></cfRule>"#
        case .greaterOrEqual(let v):
          let dxfId = dxfIndex(rule.style)
          xml +=
            #"<cfRule type="cellIs" dxfId="\#(dxfId)" priority="\#(priority)"\#(stop) operator="greaterThanOrEqual"><formula>\#(escapeXML(stringFromNumber(v)))</formula></cfRule>"#
        case .lessOrEqual(let v):
          let dxfId = dxfIndex(rule.style)
          xml +=
            #"<cfRule type="cellIs" dxfId="\#(dxfId)" priority="\#(priority)"\#(stop) operator="lessThanOrEqual"><formula>\#(escapeXML(stringFromNumber(v)))</formula></cfRule>"#
        case .equal(let v):
          let dxfId = dxfIndex(rule.style)
          xml +=
            #"<cfRule type="cellIs" dxfId="\#(dxfId)" priority="\#(priority)"\#(stop) operator="equal"><formula>\#(escapeXML(stringFromNumber(v)))</formula></cfRule>"#
        case .notEqual(let v):
          let dxfId = dxfIndex(rule.style)
          xml +=
            #"<cfRule type="cellIs" dxfId="\#(dxfId)" priority="\#(priority)"\#(stop) operator="notEqual"><formula>\#(escapeXML(stringFromNumber(v)))</formula></cfRule>"#
        case .between(let a, let b):
          let dxfId = dxfIndex(rule.style)
          xml +=
            #"<cfRule type="cellIs" dxfId="\#(dxfId)" priority="\#(priority)"\#(stop) operator="between"><formula>\#(escapeXML(stringFromNumber(a)))</formula><formula>\#(escapeXML(stringFromNumber(b)))</formula></cfRule>"#
        case .notBetween(let a, let b):
          let dxfId = dxfIndex(rule.style)
          xml +=
            #"<cfRule type="cellIs" dxfId="\#(dxfId)" priority="\#(priority)"\#(stop) operator="notBetween"><formula>\#(escapeXML(stringFromNumber(a)))</formula><formula>\#(escapeXML(stringFromNumber(b)))</formula></cfRule>"#
        case .textContains(let text):
          let dxfId = dxfIndex(rule.style)
          xml +=
            #"<cfRule type="containsText" dxfId="\#(dxfId)" priority="\#(priority)"\#(stop) operator="containsText" text="\#(escapeXML(text))"><formula>NOT(ISERROR(SEARCH("\#(escapeXML(text))",A1)))</formula></cfRule>"#
        case .blanks:
          let dxfId = dxfIndex(rule.style)
          xml +=
            #"<cfRule type="containsBlanks" dxfId="\#(dxfId)" priority="\#(priority)"\#(stop)/>"#
        case .nonBlanks:
          let dxfId = dxfIndex(rule.style)
          xml +=
            #"<cfRule type="notContainsBlanks" dxfId="\#(dxfId)" priority="\#(priority)"\#(stop)/>"#
        case .formula(let raw):
          let dxfId = dxfIndex(rule.style)
          let formula = raw.hasPrefix("=") ? String(raw.dropFirst()) : raw
          xml +=
            #"<cfRule type="expression" dxfId="\#(dxfId)" priority="\#(priority)"\#(stop)><formula>\#(escapeXML(formula))</formula></cfRule>"#
        case .colorScale(let stops):
          xml += #"<cfRule type="colorScale" priority="\#(priority)"\#(stop)><colorScale>"#
          for stop in stops {
            switch stop.type {
            case .min:
              xml += #"<cfvo type="min"/>"#
            case .max:
              xml += #"<cfvo type="max"/>"#
            case .number:
              xml += #"<cfvo type="num" val="\#(escapeXML(stringFromNumber(stop.value ?? 0)))"/>"#
            case .percent:
              xml +=
                #"<cfvo type="percent" val="\#(escapeXML(stringFromNumber(stop.value ?? 0)))"/>"#
            case .percentile:
              xml +=
                #"<cfvo type="percentile" val="\#(escapeXML(stringFromNumber(stop.value ?? 50)))"/>"#
            }
          }
          for stop in stops {
            xml += #"<color rgb="FF\#(rgbHex(stop.color))"/>"#
          }
          xml += "</colorScale></cfRule>"
        case .dataBar(let style):
          let show = style.showValue ? "" : #" showValue="0""#
          xml +=
            #"<cfRule type="dataBar" priority="\#(priority)"\#(stop)><dataBar\#(show)><cfvo type="min"/><cfvo type="max"/><color rgb="FF\#(rgbHex(style.color))"/></dataBar></cfRule>"#
        case .iconSet(let style):
          xml +=
            #"<cfRule type="iconSet" priority="\#(priority)"\#(stop)><iconSet iconSet="\#(style.excelName)"><cfvo type="percent" val="0"/><cfvo type="percent" val="33"/><cfvo type="percent" val="67"/></iconSet></cfRule>"#
        }
      }
      xml += "</conditionalFormatting>"
    }
    return xml
  }

  /// Excel 2010+ extension block (inline dxfs) — improves Mac Excel compatibility.
  public static func x14ConditionalFormattingXML(_ rules: [ConditionalFormatRule]) -> String {
    guard !rules.isEmpty else { return "" }
    var grouped: [String: [(ConditionalFormatRule, Int)]] = [:]
    for (priority, rule) in rules.enumerated() {
      let n = rule.range.normalized
      let start = CellAddress(row: n.minRow, col: n.minCol).a1
      let end = CellAddress(row: n.maxRow, col: n.maxCol).a1
      let sqref = start == end ? start : "\(start):\(end)"
      grouped[sqref, default: []].append((rule, priority + 1))
    }

    var blocks = ""
    for (sqref, items) in grouped.sorted(by: { $0.key < $1.key }) {
      blocks +=
        #"<x14:conditionalFormatting xmlns:xm="http://schemas.microsoft.com/office/excel/2006/main">"#
      blocks += #"<xm:sqref>\#(sqref)</xm:sqref>"#
      for (rule, priority) in items {
        blocks += x14CfRuleXML(rule, priority: priority)
      }
      blocks += "</x14:conditionalFormatting>"
    }

    return """
      <extLst>
        <ext uri="{78C0FAFA-122D-4D67-B399-A730565E8757}" xmlns:x14="http://schemas.microsoft.com/office/spreadsheetml/2009/9/main">
          <x14:conditionalFormattings>\(blocks)</x14:conditionalFormattings>
        </ext>
      </extLst>
      """
  }

  private static func x14CfRuleXML(_ rule: ConditionalFormatRule, priority: Int) -> String {
    let stop = rule.stopIfTrue ? "" : #" stopIfTrue="0""#
    switch rule.predicate {
    case .greaterThan(let v):
      return x14CellIsRule(
        priority: priority,
        stop: stop,
        operator: "greaterThan",
        formulas: [stringFromNumber(v)],
        style: rule.style
      )
    case .lessThan(let v):
      return x14CellIsRule(
        priority: priority,
        stop: stop,
        operator: "lessThan",
        formulas: [stringFromNumber(v)],
        style: rule.style
      )
    case .greaterOrEqual(let v):
      return x14CellIsRule(
        priority: priority,
        stop: stop,
        operator: "greaterThanOrEqual",
        formulas: [stringFromNumber(v)],
        style: rule.style
      )
    case .lessOrEqual(let v):
      return x14CellIsRule(
        priority: priority,
        stop: stop,
        operator: "lessThanOrEqual",
        formulas: [stringFromNumber(v)],
        style: rule.style
      )
    case .equal(let v):
      return x14CellIsRule(
        priority: priority,
        stop: stop,
        operator: "equal",
        formulas: [stringFromNumber(v)],
        style: rule.style
      )
    case .notEqual(let v):
      return x14CellIsRule(
        priority: priority,
        stop: stop,
        operator: "notEqual",
        formulas: [stringFromNumber(v)],
        style: rule.style
      )
    case .between(let a, let b):
      return x14CellIsRule(
        priority: priority,
        stop: stop,
        operator: "between",
        formulas: [stringFromNumber(a), stringFromNumber(b)],
        style: rule.style
      )
    case .notBetween(let a, let b):
      return x14CellIsRule(
        priority: priority,
        stop: stop,
        operator: "notBetween",
        formulas: [stringFromNumber(a), stringFromNumber(b)],
        style: rule.style
      )
    case .textContains(let text):
      return x14CellIsRule(
        priority: priority,
        stop: stop,
        operator: "containsText",
        formulas: [text],
        style: rule.style,
        text: text
      )
    case .blanks:
      return
        #"<x14:cfRule type="containsBlanks" priority="\#(priority)"\#(stop)>\#(x14DxfXML(rule.style))</x14:cfRule>"#
    case .nonBlanks:
      return
        #"<x14:cfRule type="notContainsBlanks" priority="\#(priority)"\#(stop)>\#(x14DxfXML(rule.style))</x14:cfRule>"#
    case .formula(let raw):
      let formula = raw.hasPrefix("=") ? String(raw.dropFirst()) : raw
      return
        #"<x14:cfRule type="expression" priority="\#(priority)"\#(stop)>\#(x14DxfXML(rule.style))<xm:f>\#(escapeXML(formula))</xm:f></x14:cfRule>"#
    case .colorScale(let stops):
      var xml = #"<x14:cfRule type="colorScale" priority="\#(priority)"\#(stop)><x14:colorScale>"#
      for stop in stops {
        switch stop.type {
        case .min: xml += #"<x14:cfvo type="min"/>"#
        case .max: xml += #"<x14:cfvo type="max"/>"#
        case .number:
          xml += #"<x14:cfvo type="num" val="\#(escapeXML(stringFromNumber(stop.value ?? 0)))"/>"#
        case .percent:
          xml +=
            #"<x14:cfvo type="percent" val="\#(escapeXML(stringFromNumber(stop.value ?? 0)))"/>"#
        case .percentile:
          xml +=
            #"<x14:cfvo type="percentile" val="\#(escapeXML(stringFromNumber(stop.value ?? 50)))"/>"#
        }
      }
      for stop in stops {
        xml += #"<x14:color rgb="FF\#(rgbHex(stop.color))"/>"#
      }
      xml += "</x14:colorScale></x14:cfRule>"
      return xml
    case .dataBar(let style):
      let show = style.showValue ? "" : #" showValue="0""#
      return
        #"<x14:cfRule type="dataBar" priority="\#(priority)"\#(stop)><x14:dataBar\#(show)><x14:cfvo type="min"/><x14:cfvo type="max"/><x14:color rgb="FF\#(rgbHex(style.color))"/></x14:dataBar></x14:cfRule>"#
    case .iconSet(let style):
      return
        #"<x14:cfRule type="iconSet" priority="\#(priority)"\#(stop)><x14:iconSet iconSet="\#(style.excelName)"><x14:cfvo type="percent" val="0"/><x14:cfvo type="percent" val="33"/><x14:cfvo type="percent" val="67"/></x14:iconSet></x14:cfRule>"#
    }
  }

  private static func x14CellIsRule(
    priority: Int,
    stop: String,
    operator op: String,
    formulas: [String],
    style: ConditionalFormatStyle,
    text: String? = nil
  ) -> String {
    let textAttr = text.map { #" text="\#(escapeXML($0))""# } ?? ""
    let formulaXML = formulas.map { #"<xm:f>\#(escapeXML($0))</xm:f>"# }.joined()
    return
      #"<x14:cfRule type="cellIs" priority="\#(priority)"\#(stop) operator="\#(op)"\#(textAttr)>\#(x14DxfXML(style))\#(formulaXML)</x14:cfRule>"#
  }

  private static func x14DxfXML(_ style: ConditionalFormatStyle) -> String {
    guard style.hasAny else { return "" }
    var font = ""
    font += dxfToggleXML("x14:b", style.bold)
    font += dxfToggleXML("x14:i", style.italic)
    if let rgb = style.textColor.map(rgbHex) {
      font += #"<x14:color rgb="FF\#(rgb)"/>"#
    }
    let fontXML = font.isEmpty ? "" : "<x14:font>\(font)</x14:font>"
    var fillXML = ""
    if let rgb = style.fillColor.map(rgbHex) {
      fillXML =
        #"<x14:fill><x14:patternFill patternType="solid"><x14:bgColor rgb="FF\#(rgb)"/></x14:patternFill></x14:fill>"#
    }
    return "<x14:dxf>\(fontXML)\(fillXML)</x14:dxf>"
  }

  public static func dxfsXML(_ dxfs: [ConditionalFormatStyle]) -> String {
    guard !dxfs.isEmpty else { return #"<dxfs count="0"/>"# }
    var body = ""
    for style in dxfs {
      var font = ""
      font += dxfToggleXML("b", style.bold)
      font += dxfToggleXML("i", style.italic)
      if let rgb = style.textColor.map(rgbHex) {
        font += #"<color rgb="FF\#(rgb)"/>"#
      }
      let fontXML = font.isEmpty ? "" : "<font>\(font)</font>"
      var fillXML = ""
      if let rgb = style.fillColor.map(rgbHex) {
        fillXML =
          #"<fill><patternFill patternType="solid"><bgColor rgb="FF\#(rgb)"/></patternFill></fill>"#
      }
      body += "<dxf>\(fontXML)\(fillXML)</dxf>"
    }
    return #"<dxfs count="\#(dxfs.count)">\#(body)</dxfs>"#
  }

  public static func sparkChartsJSON(_ charts: [SheetChart]) -> Data? {
    guard !charts.isEmpty else { return nil }
    return try? JSONEncoder().encode(charts)
  }

  /// `nil` omits the element. `true` is `<b/>`. `false` is `<b val="0"/>`.
  private static func dxfToggleXML(_ element: String, _ value: Bool?) -> String {
    switch value {
    case .some(true):
      return "<\(element)/>"
    case .some(false):
      return #"<\#(element) val="0"/>"#
    case .none:
      return ""
    }
  }

  /// Bold or italic inside a differential font. Missing means "don't change".
  /// `val="0"` / `false` / `off` means explicitly off. Any other present tag means on.
  private static func fontToggle(in body: String, element: String) -> Bool? {
    let scope: String
    if let font = body.range(
      of: #"<(?:x14:)?font\b[^>]*>[\s\S]*?</(?:x14:)?font>"#,
      options: .regularExpression
    ) {
      scope = String(body[font])
    } else {
      scope = body
    }
    let pattern = #"<(?:x14:)?\#(element)\b([^>/]*)/?\s*>"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let ns = scope as NSString
    let full = NSRange(location: 0, length: ns.length)
    guard let match = regex.firstMatch(in: scope, options: [], range: full) else { return nil }
    let attrs =
      match.range(at: 1).location == NSNotFound ? "" : ns.substring(with: match.range(at: 1))
    guard let raw = attributeValue(attrs, name: "val") else { return true }
    switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "0", "false", "off":
      return false
    default:
      return true
    }
  }

  public static func rgbHex(_ color: CodableColor) -> String {
    let r = Int((color.red * 255).rounded())
    let g = Int((color.green * 255).rounded())
    let b = Int((color.blue * 255).rounded())
    return String(format: "%02X%02X%02X", r, g, b)
  }

  // MARK: - Private helpers

  private static func colorScalePredicate(
    in body: String,
    themeScheme: ThemeColorScheme
  ) -> ConditionalFormatPredicate? {
    guard
      let scaleRange = body.range(
        of: #"<(?:x14:)?colorScale>[\s\S]*?</(?:x14:)?colorScale>"#,
        options: .regularExpression
      )
    else { return nil }
    let scale = String(body[scaleRange])
    let cfvoPattern = #"<(?:x14:)?cfvo\b([^>]*)/?\s*>"#
    let colorPattern = #"<(?:x14:)?color\b([^>]*)/?\s*>"#
    guard let cfvoRegex = try? NSRegularExpression(pattern: cfvoPattern),
      let colorRegex = try? NSRegularExpression(pattern: colorPattern)
    else { return nil }
    let ns = scale as NSString
    let full = NSRange(location: 0, length: ns.length)
    let cfvos = cfvoRegex.matches(in: scale, range: full).map {
      ns.substring(with: $0.range(at: 1))
    }
    let colors = colorRegex.matches(in: scale, range: full).map {
      ns.substring(with: $0.range(at: 1))
    }
    guard cfvos.count >= 2, colors.count == cfvos.count else { return nil }

    var stops: [ColorScaleStop] = []
    for (index, attrs) in cfvos.enumerated() {
      let typeRaw = attributeValue(attrs, name: "type") ?? "min"
      let type: ColorScaleStop.StopType
      switch typeRaw {
      case "min": type = .min
      case "max": type = .max
      case "num", "number": type = .number
      case "percent": type = .percent
      case "percentile": type = .percentile
      default: type = .number
      }
      let value = attributeValue(attrs, name: "val").flatMap(Double.init)
      let colorAttrs = colors[index]
      let color =
        ThemeColorLookup.resolve(fromAttributes: colorAttrs, scheme: themeScheme)
        ?? colorFromRGBHex(attributeValue(colorAttrs, name: "rgb") ?? "")
        ?? CodableColor(red: 0.99, green: 0.8, blue: 0.8, alpha: 1)
      stops.append(ColorScaleStop(type: type, value: value, color: color))
    }
    return .colorScale(stops)
  }

  private static func dataBarPredicate(
    in body: String,
    themeScheme: ThemeColorScheme
  ) -> ConditionalFormatPredicate? {
    guard
      let barRange = body.range(
        of: #"<(?:x14:)?dataBar\b[^>]*>[\s\S]*?</(?:x14:)?dataBar>"#,
        options: .regularExpression
      ) ?? body.range(of: #"<(?:x14:)?dataBar\b[^>]*/>"#, options: .regularExpression)
    else { return nil }
    let bar = String(body[barRange])
    let showValue = !(bar.contains(#"showValue="0""#) || bar.contains("showValue='0'"))
    var color = DataBarStyle.blue.color
    if let colorRange = bar.range(
      of: #"<(?:x14:)?color\b([^>]*)/?\s*>"#, options: .regularExpression)
    {
      let token = String(bar[colorRange])
      if let themed = ThemeColorLookup.resolve(fromAttributes: token, scheme: themeScheme) {
        color = themed
      } else if let rgb = attributeValue(token, name: "rgb"), let parsed = colorFromRGBHex(rgb) {
        color = parsed
      }
    }
    return .dataBar(DataBarStyle(color: color, showValue: showValue))
  }

  private static func iconSetPredicate(in body: String, ruleAttrs: String)
    -> ConditionalFormatPredicate?
  {
    var name = attributeValue(ruleAttrs, name: "iconSet")
    if name == nil,
      let range = body.range(of: #"(?:iconSet|x14:iconSet)="[^"]+""#, options: .regularExpression)
    {
      let token = String(body[range])
      if let q1 = token.firstIndex(of: "\""),
        let q2 = token.lastIndex(of: "\""),
        q1 < q2
      {
        name = String(token[token.index(after: q1)..<q2])
      }
    }
    guard let name, let style = IconSetStyle.fromExcelName(name) else {
      return .iconSet(.threeTrafficLights)
    }
    return .iconSet(style)
  }

  /// `origin` is the first cell of the rule's range: a text comparison becomes a formula
  /// written for that cell, as other spreadsheet apps read it.
  private static func cellIsPredicate(
    operator op: String, formulas: [String], origin: CellAddress
  )
    -> ConditionalFormatPredicate?
  {
    let numericValues = formulas.compactMap { parseNumericFormulaValue($0) }
    switch op {
    case "greaterThan":
      guard let v = numericValues.first else { return nil }
      return .greaterThan(v)
    case "lessThan":
      guard let v = numericValues.first else { return nil }
      return .lessThan(v)
    case "greaterThanOrEqual":
      guard let v = numericValues.first else { return nil }
      return .greaterOrEqual(v)
    case "lessThanOrEqual":
      guard let v = numericValues.first else { return nil }
      return .lessOrEqual(v)
    case "equal":
      if let v = numericValues.first { return .equal(v) }
      guard let text = formulas.first else { return nil }
      return textCellIsFormulaPredicate(operator: "=", text: text, origin: origin)
    case "notEqual":
      if let v = numericValues.first { return .notEqual(v) }
      guard let text = formulas.first else { return nil }
      return textCellIsFormulaPredicate(operator: "<>", text: text, origin: origin)
    case "between":
      guard numericValues.count >= 2 else { return nil }
      return .between(numericValues[0], numericValues[1])
    case "notBetween":
      guard numericValues.count >= 2 else { return nil }
      return .notBetween(numericValues[0], numericValues[1])
    default:
      return nil
    }
  }

  private static func parseNumericFormulaValue(_ raw: String) -> Double? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if trimmed.hasPrefix("\""), trimmed.hasSuffix("\""), trimmed.count >= 2 {
      return nil
    }
    return Double(trimmed.replacingOccurrences(of: ",", with: ""))
  }

  /// A cellIs text comparison as a formula for the rule's first cell, such as `=N2="Large"`.
  /// The file writes the operand as formula text, such as `"Large"` with its quotes.
  private static func textCellIsFormulaPredicate(
    operator op: String, text: String, origin: CellAddress
  )
    -> ConditionalFormatPredicate
  {
    // The operand is already formula text (a quoted string or a reference), so it is used as is.
    let operand = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return .formula("=\(origin.a1)\(op)\(operand)")
  }

  private static func xmFormulaValues(in body: String) -> [String] {
    let pattern = #"<xm:f>([\s\S]*?)</xm:f>"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    let ns = body as NSString
    return regex.matches(in: body, range: NSRange(location: 0, length: ns.length)).map { match in
      decodeXMLEntities(
        ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines))
    }
  }

  private static func formulaValues(in body: String) -> [String] {
    let pattern = #"<formula>([\s\S]*?)</formula>"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    let ns = body as NSString
    return regex.matches(in: body, range: NSRange(location: 0, length: ns.length)).map { match in
      decodeXMLEntities(
        ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines))
    }
  }

  private static func attributeValue(_ attrs: String, name: String) -> String? {
    guard let range = attrs.range(of: #"\#(name)="[^"]*""#, options: .regularExpression) else {
      return nil
    }
    let token = String(attrs[range])
    guard let q1 = token.firstIndex(of: "\""),
      let q2 = token.lastIndex(of: "\""),
      q1 < q2
    else { return nil }
    return String(token[token.index(after: q1)..<q2])
  }

  public static func parseCellRange(_ ref: String) -> CellRange? {
    let trimmed = ref.trimmingCharacters(in: .whitespacesAndNewlines)
    if let (start, end) = A1Reference.parseRange(trimmed) {
      return CellRange(start: start, end: end)
    }
    if let parsed = A1Reference.parseAddress(trimmed) {
      let address = CellAddress(row: parsed.row, col: parsed.col)
      return CellRange(start: address, end: address)
    }
    return nil
  }

  private static func firstColor(
    in xml: String,
    near marker: String,
    themeScheme: ThemeColorScheme
  ) -> CodableColor? {
    guard let markerRange = xml.range(of: marker) else { return nil }
    let window = String(xml[markerRange.lowerBound...])
    if let tagRange = window.range(of: #"<[^>]+>"#, options: .regularExpression) {
      let tag = String(window[tagRange])
      if let themed = ThemeColorLookup.resolve(fromAttributes: tag, scheme: themeScheme) {
        return themed
      }
    }
    guard let rgbRange = window.range(of: #"rgb="[A-Fa-f0-9]{6,8}""#, options: .regularExpression)
    else { return nil }
    let token = String(window[rgbRange])
    guard let q1 = token.firstIndex(of: "\""),
      let q2 = token.lastIndex(of: "\""),
      q1 < q2
    else { return nil }
    return colorFromRGBHex(String(token[token.index(after: q1)..<q2]))
  }

  private static func colorFromRGBHex(_ rgb: String) -> CodableColor? {
    guard !rgb.isEmpty else { return nil }
    let hex = rgb.count == 8 ? String(rgb.suffix(6)) : rgb
    guard let value = UInt32(hex, radix: 16) else { return nil }
    let r = Double((value >> 16) & 0xFF) / 255
    let g = Double((value >> 8) & 0xFF) / 255
    let b = Double(value & 0xFF) / 255
    return CodableColor(red: r, green: g, blue: b, alpha: 1)
  }

  private static func stringFromNumber(_ value: Double) -> String {
    if value.rounded() == value, abs(value) < 1e12 {
      return String(Int(value))
    }
    return String(value)
  }
}
