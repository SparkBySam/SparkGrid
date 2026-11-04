import Formula
import Foundation
import GridCore
import Model

/// Reads what a chart from another app shows out of its kept chart part (`xl/charts/chartN.xml`).
/// Only the first plot in a chart is read. A combined chart shows its first kind.
public nonisolated enum ImportedChartReader {
  public static func read(_ data: Data) -> ImportedChart? {
    guard let raw = String(data: data, encoding: .utf8) else { return nil }
    return read(xml: raw)
  }

  public static func read(xml raw: String) -> ImportedChart? {
    // Files write `c:barChart` or, from some generators, a bare `barChart`. Drop the prefixes.
    let xml = raw.replacingOccurrences(
      of: #"<(/?)[A-Za-z0-9]+:"#, with: "<$1", options: .regularExpression)
    guard let plotArea = element("plotArea", in: xml) else { return nil }

    let kinds: [(tag: String, kind: ImportedChart.Kind)] = [
      ("barChart", .column), ("bar3DChart", .column), ("lineChart", .line),
      ("line3DChart", .line), ("areaChart", .area), ("area3DChart", .area),
      ("pieChart", .pie), ("pie3DChart", .pie), ("ofPieChart", .pie),
      ("doughnutChart", .doughnut), ("scatterChart", .scatter),
    ]
    var found: (body: String, kind: ImportedChart.Kind, at: String.Index)?
    for (tag, kind) in kinds {
      guard let match = elementWithRange(tag, in: plotArea) else { continue }
      if let earlier = found, earlier.at <= match.range.lowerBound { continue }
      found = (match.body, kind, match.range.lowerBound)
    }
    guard let plot = found else { return nil }

    var kind = plot.kind
    if kind == .column, attribute("val", ofEmpty: "barDir", in: plot.body) == "bar" {
      kind = .bar
    }
    let grouping = attribute("val", ofEmpty: "grouping", in: plot.body) ?? ""
    let isStacked = grouping == "stacked" || grouping == "percentStacked"

    let series = elements("ser", in: plot.body).compactMap {
      readSeries($0, scatter: kind == .scatter)
    }
    guard !series.isEmpty else { return nil }

    let chartBody = element("chart", in: xml) ?? xml
    let beforePlot =
      chartBody.range(of: "<plotArea").map { String(chartBody[..<$0.lowerBound]) } ?? ""
    var title = element("title", in: beforePlot).map(titleText) ?? ""
    let deleted = attribute("val", ofEmpty: "autoTitleDeleted", in: beforePlot) == "1"
    if title.isEmpty, !deleted, series.count == 1, kind != .scatter {
      // A one-series chart with no title of its own shows the series name.
      title = series[0].name
    }

    var categoryAxisTitle = ""
    var valueAxisTitle = ""
    if let catAx = element("catAx", in: plotArea) ?? element("dateAx", in: plotArea),
      let axisTitle = element("title", in: catAx)
    {
      categoryAxisTitle = titleText(axisTitle)
    }
    if let valAx = element("valAx", in: plotArea), let axisTitle = element("title", in: valAx) {
      valueAxisTitle = titleText(axisTitle)
    }

    return ImportedChart(
      kind: kind,
      title: title,
      isStacked: isStacked,
      series: series,
      showsLegend: xml.contains("<legend"),
      categoryAxisTitle: categoryAxisTitle,
      valueAxisTitle: valueAxisTitle
    )
  }

  // MARK: - Series

  private static func readSeries(_ body: String, scatter: Bool) -> ImportedChart.Series? {
    var series = ImportedChart.Series()
    if let tx = element("tx", in: body) {
      if let ref = element("f", in: tx).flatMap(reference) {
        series.nameReference = ref
      }
      series.name = element("v", in: tx).map(unescape) ?? cachedStrings(tx).first ?? ""
    }
    let categoryTag = scatter ? "xVal" : "cat"
    let valueTag = scatter ? "yVal" : "val"
    if let cat = element(categoryTag, in: body) {
      series.categories = element("f", in: cat).flatMap(reference)
      series.cachedCategories = cachedStrings(cat)
    }
    if let val = element(valueTag, in: body) {
      series.values = element("f", in: val).flatMap(reference)
      series.cachedValues = cachedStrings(val).map { Double($0) }
    }
    if let fill = element("spPr", in: body),
      let rgb = attribute("val", ofEmpty: "srgbClr", in: fill)
    {
      series.colorHex = rgb.uppercased()
    }
    guard series.values != nil || !series.cachedValues.isEmpty else { return nil }
    return series
  }

  /// `'Monthly Summary'!$C$4:$N$4`, `Sheet1!B2`, or a bare `B2:B9`.
  public static func reference(_ formula: String) -> ImportedChart.Reference? {
    let text = unescape(formula).trimmingCharacters(in: .whitespacesAndNewlines)
    if let (start, end) = A1Reference.parseFormulaRange(text) {
      return ImportedChart.Reference(
        sheetName: start.sheet ?? end.sheet,
        range: CellRange(start: start.address, end: end.address))
    }
    if let ref = A1Reference.parseFormulaRef(text) {
      return ImportedChart.Reference(
        sheetName: ref.sheet, range: CellRange(start: ref.address, end: ref.address))
    }
    return nil
  }

  /// Point values from a `strCache` or `numCache`, by index, with gaps left empty.
  private static func cachedStrings(_ body: String) -> [String] {
    let cache = element("strCache", in: body) ?? element("numCache", in: body) ?? ""
    guard !cache.isEmpty else { return [] }
    let count = attribute("val", ofEmpty: "ptCount", in: cache).flatMap(Int.init) ?? 0
    var values = Array(repeating: "", count: min(max(count, 0), 100_000))
    for point in matches(#"<pt\b([^>]*)>(.*?)</pt>"#, in: cache) {
      guard let index = attributeValue("idx", in: point[0]).flatMap(Int.init), index >= 0 else {
        continue
      }
      let value = element("v", in: point[1]).map(unescape) ?? ""
      if index >= values.count {
        guard index < 100_000 else { continue }
        values.append(contentsOf: Array(repeating: "", count: index - values.count + 1))
      }
      values[index] = value
    }
    return values
  }

  private static func titleText(_ title: String) -> String {
    let runs = matches(#"<t(?:\s[^>]*)?>(.*?)</t>"#, in: title).map { unescape($0[0]) }
    if !runs.isEmpty { return runs.joined() }
    return cachedStrings(title).first ?? ""
  }

  // MARK: - XML helpers

  private static func element(_ tag: String, in xml: String) -> String? {
    elementWithRange(tag, in: xml)?.body
  }

  private static func elementWithRange(_ tag: String, in xml: String)
    -> (body: String, range: Range<String.Index>)?
  {
    guard
      let range = xml.range(
        of: #"<\#(tag)(?:\s[^>]*)?>([\s\S]*?)</\#(tag)>"#, options: .regularExpression)
    else { return nil }
    let whole = String(xml[range])
    guard let open = whole.firstIndex(of: ">"),
      let close = whole.range(of: "</\(tag)>", options: .backwards)
    else { return nil }
    return (String(whole[whole.index(after: open)..<close.lowerBound]), range)
  }

  private static func elements(_ tag: String, in xml: String) -> [String] {
    matches(#"<\#(tag)(?:\s[^>]*)?>([\s\S]*?)</\#(tag)>"#, in: xml).map { $0[0] }
  }

  /// The attribute on an element written `<tag val="…"/>`.
  private static func attribute(_ name: String, ofEmpty tag: String, in xml: String) -> String? {
    guard let range = xml.range(of: #"<\#(tag)\b[^>]*>"#, options: .regularExpression) else {
      return nil
    }
    return attributeValue(name, in: String(xml[range]))
  }

  private static func attributeValue(_ name: String, in tag: String) -> String? {
    guard
      let range = tag.range(of: #"\b\#(name)\s*=\s*"[^"]*""#, options: .regularExpression)
    else { return nil }
    let pair = tag[range]
    guard let first = pair.firstIndex(of: "\""), let last = pair.lastIndex(of: "\""), first < last
    else { return nil }
    return String(pair[pair.index(after: first)..<last])
  }

  /// Capture groups of every match.
  private static func matches(_ pattern: String, in text: String) -> [[String]] {
    guard
      let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
    else { return [] }
    let ns = text as NSString
    return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { match in
      (1..<match.numberOfRanges).map { index in
        let range = match.range(at: index)
        return range.location == NSNotFound ? "" : ns.substring(with: range)
      }
    }
  }

  private static func unescape(_ text: String) -> String {
    text.replacingOccurrences(of: "&lt;", with: "<")
      .replacingOccurrences(of: "&gt;", with: ">")
      .replacingOccurrences(of: "&quot;", with: "\"")
      .replacingOccurrences(of: "&apos;", with: "'")
      .replacingOccurrences(of: "&amp;", with: "&")
  }
}
