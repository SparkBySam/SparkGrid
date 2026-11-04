import Formula
import Foundation
import GridCore
import Model

/// What the Edit Chart sheet can change on a chart from another app.
public nonisolated struct ImportedChartEdit: Equatable, Sendable {
  public struct Series: Equatable, Sendable {
    /// The series' place in the chart as read. Nil for a series added in the sheet.
    public var sourceIndex: Int?
    /// The legend name, used when `nameFormula` is empty.
    public var name: String
    /// A cell the name is read from, such as `'Monthly Summary'!$B$4`. Empty for a typed name.
    public var nameFormula: String
    /// Category labels, or X values for a scatter chart. Empty for none.
    public var categoriesFormula: String
    public var valuesFormula: String
    /// `RRGGBB`. Nil leaves the file's own colors.
    public var colorHex: String?

    public init(
      sourceIndex: Int? = nil, name: String = "", nameFormula: String = "",
      categoriesFormula: String = "", valuesFormula: String = "", colorHex: String? = nil
    ) {
      self.sourceIndex = sourceIndex
      self.name = name
      self.nameFormula = nameFormula
      self.categoriesFormula = categoriesFormula
      self.valuesFormula = valuesFormula
      self.colorHex = colorHex
    }
  }

  public var kind: ImportedChart.Kind
  public var title: String
  public var isStacked: Bool
  public var showsLegend: Bool
  public var categoryAxisTitle: String
  public var valueAxisTitle: String
  public var series: [Series]

  /// The chart as it is, with each reference written out against `sheetName` when it names
  /// no sheet of its own.
  public init(chart: ImportedChart, sheetName: String) {
    kind = chart.kind
    title = chart.title
    isStacked = chart.isStacked
    showsLegend = chart.showsLegend
    categoryAxisTitle = chart.categoryAxisTitle
    valueAxisTitle = chart.valueAxisTitle
    series = chart.series.enumerated().map { index, series in
      Series(
        sourceIndex: index,
        name: series.name,
        nameFormula: series.nameReference.map { Self.formula($0, sheetName: sheetName) } ?? "",
        categoriesFormula: series.categories.map { Self.formula($0, sheetName: sheetName) } ?? "",
        valuesFormula: series.values.map { Self.formula($0, sheetName: sheetName) } ?? "",
        colorHex: series.colorHex)
    }
  }

  /// Column, bar, line and area charts can change into one another.
  public var canChangeKind: Bool { Self.switchableKinds.contains(kind) }
  public static let switchableKinds: [ImportedChart.Kind] = [.column, .bar, .line, .area]
  public var canStack: Bool { kind == .column || kind == .bar || kind == .area }
  public var hasAxes: Bool { kind != .pie && kind != .doughnut }
  /// Pie slices take their colors per point, and scatter points from their markers.
  public var canColorSeries: Bool { Self.switchableKinds.contains(kind) }

  /// `'Monthly Summary'!$C$4:$N$4`.
  public static func formula(_ reference: ImportedChart.Reference, sheetName: String) -> String {
    let n = reference.range.normalized
    let sheet = reference.sheetName ?? sheetName
    let start = FormulaRef(sheet: sheet, row: n.minRow, col: n.minCol, absRow: true, absCol: true)
    if n.minRow == n.maxRow, n.minCol == n.maxCol { return A1Reference.format(start) }
    let end = FormulaRef(sheet: sheet, row: n.maxRow, col: n.maxCol, absRow: true, absCol: true)
    return A1Reference.formatRange(start: start, end: end)
  }

  /// A typed reference with the sheet named, as a chart must store it. Nil when it isn't one.
  public static func qualifiedFormula(_ text: String, sheetName: String) -> String? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: CharacterSet(charactersIn: "="))
    guard !trimmed.isEmpty, let reference = ImportedChartReader.reference(trimmed) else {
      return nil
    }
    return formula(reference, sheetName: sheetName)
  }
}

/// Writes an `ImportedChartEdit` into a kept chart part. Only what changed is rewritten, so the
/// file's own styling stays wherever it can.
public nonisolated enum ImportedChartWriter {
  static let chartURI = "http://schemas.openxmlformats.org/drawingml/2006/chart"
  static let drawingURI = "http://schemas.openxmlformats.org/drawingml/2006/main"

  /// The edited part, or nil when the part can't be read or `edit` has a reference that isn't
  /// one. `sheetName` is the chart's own sheet, named in references that leave it out.
  public static func apply(_ edit: ImportedChartEdit, to data: Data, sheetName: String) -> Data? {
    guard let chart = ImportedChartReader.read(data),
      let document = try? XMLDocument(data: data, options: [.nodePreserveAll]),
      let root = document.rootElement()
    else { return nil }
    let before = ImportedChartEdit(chart: chart, sheetName: sheetName)
    var writer = Writer(root: root, sheetName: sheetName)
    guard writer.apply(edit, before: before) else { return nil }
    return document.xmlData(options: [.nodeCompactEmptyElement])
  }

  private struct Writer {
    let root: XMLElement
    let sheetName: String
    let chartPrefix: String
    let drawingPrefix: String

    init(root: XMLElement, sheetName: String) {
      self.root = root
      self.sheetName = sheetName
      let chart = root.prefix ?? ""
      chartPrefix = chart.isEmpty ? "" : "\(chart):"
      if let found = root.resolvePrefix(forNamespaceURI: drawingURI) {
        drawingPrefix = found.isEmpty ? "" : "\(found):"
      } else {
        if let namespace = XMLNode.namespace(withName: "a", stringValue: drawingURI) as? XMLNode {
          root.addNamespace(namespace)
        }
        drawingPrefix = "a:"
      }
    }

    mutating func apply(_ edit: ImportedChartEdit, before: ImportedChartEdit) -> Bool {
      guard let chart = child(root, "chart"), let plotArea = child(chart, "plotArea"),
        var plot = firstPlot(in: plotArea)
      else { return false }

      if edit.series != before.series {
        guard rewriteSeries(edit, before: before, in: plot) else { return false }
      }
      let kind = edit.canChangeKind || edit.kind == before.kind ? edit.kind : before.kind
      if before.canChangeKind, kind != before.kind || edit.isStacked != before.isStacked {
        plot = convert(plot, in: plotArea, to: kind, stacked: edit.isStacked)
      }
      if edit.title != before.title { setTitle(edit.title, in: chart) }
      if edit.showsLegend != before.showsLegend { setLegend(edit.showsLegend, in: chart) }
      if edit.hasAxes, kind != .scatter {
        if edit.categoryAxisTitle != before.categoryAxisTitle,
          let axis = child(plotArea, "catAx") ?? child(plotArea, "dateAx")
        {
          setAxisTitle(edit.categoryAxisTitle, on: axis, rotated: kind == .bar)
        }
        if edit.valueAxisTitle != before.valueAxisTitle, let axis = child(plotArea, "valAx") {
          setAxisTitle(edit.valueAxisTitle, on: axis, rotated: kind != .bar)
        }
      }
      return true
    }

    // MARK: Series

    private func rewriteSeries(
      _ edit: ImportedChartEdit, before: ImportedChartEdit, in plot: XMLElement
    ) -> Bool {
      let old = children(plot, "ser")
      guard !old.isEmpty, !edit.series.isEmpty else { return false }
      let scatter = local(plot) == "scatterChart"
      let line = local(plot) == "lineChart"
      var nextIndex = old.compactMap { Int(val(child($0, "idx")) ?? "") }.max() ?? -1
      var nextOrder = old.compactMap { Int(val(child($0, "order")) ?? "") }.max() ?? -1
      var rebuilt: [XMLElement] = []
      for series in edit.series {
        let ser: XMLElement
        let original: ImportedChartEdit.Series?
        if let source = series.sourceIndex, old.indices.contains(source),
          before.series.indices.contains(source)
        {
          ser = clone(old[source])
          original = before.series[source]
        } else {
          nextIndex += 1
          nextOrder += 1
          ser = make("ser")
          ser.addChild(make("idx", val: "\(nextIndex)"))
          ser.addChild(make("order", val: "\(nextOrder)"))
          if local(plot) == "barChart" { ser.addChild(make("invertIfNegative", val: "0")) }
          original = nil
        }
        if original?.name != series.name || original?.nameFormula != series.nameFormula {
          setName(series, on: ser)
        }
        if original?.categoriesFormula != series.categoriesFormula {
          guard
            setReference(
              series.categoriesFormula, on: ser, tag: scatter ? "xVal" : "cat",
              numeric: scatter, before: scatter ? "yVal" : "val")
          else { return false }
        }
        if original?.valuesFormula != series.valuesFormula {
          guard !series.valuesFormula.isEmpty,
            setReference(
              series.valuesFormula, on: ser, tag: scatter ? "yVal" : "val", numeric: true,
              before: nil)
          else { return false }
        }
        if original?.colorHex != series.colorHex, edit.canColorSeries, let hex = series.colorHex {
          setColor(hex, on: ser, asLine: line)
        }
        if original == nil, line, child(ser, "smooth") == nil {
          ser.addChild(make("smooth", val: "0"))
        }
        rebuilt.append(ser)
      }
      guard let first = old.first, var at = position(of: first, in: plot) else { return false }
      for ser in old { ser.detach() }
      for ser in rebuilt {
        plot.insertChild(ser, at: at)
        at += 1
      }
      return true
    }

    private func setName(_ series: ImportedChartEdit.Series, on ser: XMLElement) {
      if let tx = child(ser, "tx") { tx.detach() }
      let tx = make("tx")
      if let formula = ImportedChartEdit.qualifiedFormula(series.nameFormula, sheetName: sheetName)
      {
        let ref = make("strRef")
        ref.addChild(make("f", text: formula))
        tx.addChild(ref)
      } else if !series.name.isEmpty {
        tx.addChild(make("v", text: series.name))
      } else {
        return
      }
      insert(tx, in: ser, after: ["idx", "order"])
    }

    /// Points `tag` at `formula`, dropping the saved points so no app shows stale ones.
    private func setReference(
      _ formula: String, on ser: XMLElement, tag: String, numeric: Bool, before next: String?
    ) -> Bool {
      let existing = child(ser, tag)
      if formula.trimmingCharacters(in: .whitespaces).isEmpty {
        existing?.detach()
        return true
      }
      guard let qualified = ImportedChartEdit.qualifiedFormula(formula, sheetName: sheetName)
      else { return false }
      let element = make(tag)
      let ref = make(numeric ? "numRef" : "strRef")
      ref.addChild(make("f", text: qualified))
      element.addChild(ref)
      if let existing, let at = position(of: existing, in: ser) {
        ser.replaceChild(at: at, with: element)
      } else if let next, let following = child(ser, next),
        let at = position(of: following, in: ser)
      {
        ser.insertChild(element, at: at)
      } else {
        // After everything that comes before values in every series kind.
        insert(
          element, in: ser,
          after: [
            "idx", "order", "tx", "spPr", "invertIfNegative", "pictureOptions", "marker", "dPt",
            "dLbls", "trendline", "errBars", "cat", "xVal",
          ])
      }
      return true
    }

    private func setColor(_ hex: String, on ser: XMLElement, asLine: Bool) {
      child(ser, "spPr")?.detach()
      insert(colorProperties(hex, asLine: asLine), in: ser, after: ["idx", "order", "tx"])
    }

    private func colorProperties(_ hex: String, asLine: Bool) -> XMLElement {
      let fill = makeA("solidFill")
      let color = makeA("srgbClr")
      color.addAttribute(attribute("val", hex.uppercased()))
      fill.addChild(color)
      let properties = make("spPr")
      if asLine {
        let line = makeA("ln")
        line.addAttribute(attribute("w", "28575"))
        line.addAttribute(attribute("cap", "rnd"))
        line.addChild(fill)
        line.addChild(makeA("round"))
        properties.addChild(line)
      } else {
        properties.addChild(fill)
      }
      return properties
    }

    /// The series' color as the file sets it: a fill, or a line's fill.
    private func seriesColor(_ ser: XMLElement) -> String? {
      guard let properties = child(ser, "spPr") else { return nil }
      let fill =
        child(properties, "solidFill")
        ?? child(properties, "ln").flatMap {
          child($0, "solidFill")
        }
      return fill.flatMap { child($0, "srgbClr") }?.attribute(forName: "val")?.stringValue
    }

    // MARK: Kind and stacking

    private func convert(
      _ plot: XMLElement, in plotArea: XMLElement, to kind: ImportedChart.Kind, stacked: Bool
    ) -> XMLElement {
      let target: String
      switch kind {
      case .line: target = "lineChart"
      case .area: target = "areaChart"
      default: target = "barChart"
      }
      let stack = stacked && kind != .line
      if local(plot) == target {
        if target == "barChart" { setVal("barDir", kind == .bar ? "bar" : "col", in: plot) }
        setGrouping(stack, in: plot, bar: target == "barChart")
        if target == "barChart" { setOverlap(stack, in: plot) }
        setAxisPositions(in: plotArea, horizontal: kind == .bar)
        return plot
      }

      let next = make(target)
      if target == "barChart" { next.addChild(make("barDir", val: kind == .bar ? "bar" : "col")) }
      next.addChild(
        make(
          "grouping",
          val: stack ? "stacked" : (target == "barChart" ? "clustered" : "standard")))
      next.addChild(make("varyColors", val: "0"))
      for ser in children(plot, "ser") {
        next.addChild(convertSeries(ser, to: target))
      }
      if let labels = child(plot, "dLbls") { next.addChild(clone(labels)) }
      if target == "barChart" {
        next.addChild(make("gapWidth", val: val(child(plot, "gapWidth")) ?? "150"))
        if stack { next.addChild(make("overlap", val: "100")) }
      }
      if target == "lineChart" { next.addChild(make("marker", val: "1")) }
      for axis in children(plot, "axId") { next.addChild(clone(axis)) }
      if let at = position(of: plot, in: plotArea) {
        plotArea.replaceChild(at: at, with: next)
      }
      setAxisPositions(in: plotArea, horizontal: kind == .bar)
      return next
    }

    /// The series with only what every kind accepts, in the order the target kind wants.
    private func convertSeries(_ ser: XMLElement, to target: String) -> XMLElement {
      let next = make("ser")
      func copy(_ name: String) {
        for element in children(ser, name) { next.addChild(clone(element)) }
      }
      copy("idx")
      copy("order")
      // Every series needs an order; some files leave it out.
      if child(ser, "order") == nil {
        next.addChild(make("order", val: val(child(ser, "idx")) ?? "0"))
      }
      copy("tx")
      if let hex = seriesColor(ser) {
        next.addChild(colorProperties(hex, asLine: target == "lineChart"))
      }
      if target == "barChart" { next.addChild(make("invertIfNegative", val: "0")) }
      copy("dLbls")
      copy("cat")
      copy("val")
      if target == "lineChart" { next.addChild(make("smooth", val: "0")) }
      copy("extLst")
      return next
    }

    private func setGrouping(_ stacked: Bool, in plot: XMLElement, bar: Bool) {
      let value = stacked ? "stacked" : (bar ? "clustered" : "standard")
      if child(plot, "grouping") != nil {
        setVal("grouping", value, in: plot)
      } else {
        insert(make("grouping", val: value), in: plot, after: ["barDir"])
      }
    }

    private func setOverlap(_ stacked: Bool, in plot: XMLElement) {
      child(plot, "overlap")?.detach()
      guard stacked else { return }
      insert(
        make("overlap", val: "100"), in: plot,
        after: ["barDir", "grouping", "varyColors", "ser", "dLbls", "gapWidth"])
    }

    /// Horizontal bars put categories on the left and values along the bottom.
    private func setAxisPositions(in plotArea: XMLElement, horizontal: Bool) {
      for name in ["catAx", "dateAx"] {
        for axis in children(plotArea, name) { setVal("axPos", horizontal ? "l" : "b", in: axis) }
      }
      for axis in children(plotArea, "valAx") { setVal("axPos", horizontal ? "b" : "l", in: axis) }
    }

    // MARK: Titles and legend

    private func setTitle(_ text: String, in chart: XMLElement) {
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      let existing = child(chart, "title")
      if trimmed.isEmpty {
        existing?.detach()
        if child(chart, "autoTitleDeleted") != nil {
          setVal("autoTitleDeleted", "1", in: chart)
        } else {
          chart.insertChild(make("autoTitleDeleted", val: "1"), at: 0)
        }
        return
      }
      if child(chart, "autoTitleDeleted") != nil { setVal("autoTitleDeleted", "0", in: chart) }
      if let existing, replaceRichText(trimmed, in: existing) { return }
      existing?.detach()
      chart.insertChild(titleElement(trimmed, rotated: false), at: 0)
    }

    private func setAxisTitle(_ text: String, on axis: XMLElement, rotated: Bool) {
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      let existing = child(axis, "title")
      if trimmed.isEmpty {
        existing?.detach()
        return
      }
      if let existing, replaceRichText(trimmed, in: existing) { return }
      existing?.detach()
      insert(
        titleElement(trimmed, rotated: rotated), in: axis,
        after: ["axId", "scaling", "delete", "axPos", "majorGridlines", "minorGridlines"])
    }

    /// Puts `text` in the title's first run and drops the others, keeping the file's font.
    private func replaceRichText(_ text: String, in title: XMLElement) -> Bool {
      guard let rich = child(title, "tx").flatMap({ child($0, "rich") }) else { return false }
      let paragraphs = children(rich, "p")
      guard let first = paragraphs.first, let run = children(first, "r").first,
        let textElement = children(run, "t").first
      else { return false }
      textElement.stringValue = text
      for extra in children(first, "r").dropFirst() { extra.detach() }
      for extra in children(first, "fld") { extra.detach() }
      for extra in paragraphs.dropFirst() { extra.detach() }
      return true
    }

    private func titleElement(_ text: String, rotated: Bool) -> XMLElement {
      let body = makeA("bodyPr")
      if rotated {
        body.addAttribute(attribute("rot", "-5400000"))
        body.addAttribute(attribute("vert", "horz"))
      }
      let run = makeA("r")
      run.addChild(makeA("t", text: text))
      let paragraph = makeA("p")
      paragraph.addChild(run)
      let rich = make("rich")
      rich.addChild(body)
      rich.addChild(makeA("lstStyle"))
      rich.addChild(paragraph)
      let tx = make("tx")
      tx.addChild(rich)
      let title = make("title")
      title.addChild(tx)
      title.addChild(make("overlay", val: "0"))
      return title
    }

    private func setLegend(_ shows: Bool, in chart: XMLElement) {
      if !shows {
        child(chart, "legend")?.detach()
        return
      }
      guard child(chart, "legend") == nil else { return }
      let legend = make("legend")
      legend.addChild(make("legendPos", val: "b"))
      legend.addChild(make("overlay", val: "0"))
      insert(legend, in: chart, after: ["plotArea"])
    }

    // MARK: XML helpers

    private func firstPlot(in plotArea: XMLElement) -> XMLElement? {
      let kinds: Set<String> = [
        "barChart", "bar3DChart", "lineChart", "line3DChart", "areaChart", "area3DChart",
        "pieChart", "pie3DChart", "ofPieChart", "doughnutChart", "scatterChart",
      ]
      return elementChildren(plotArea).first { kinds.contains(local($0)) }
    }

    private func local(_ element: XMLElement) -> String {
      element.localName ?? element.name ?? ""
    }

    private func elementChildren(_ element: XMLElement) -> [XMLElement] {
      (element.children ?? []).compactMap { $0 as? XMLElement }
    }

    private func children(_ element: XMLElement, _ name: String) -> [XMLElement] {
      elementChildren(element).filter { local($0) == name }
    }

    private func child(_ element: XMLElement?, _ name: String) -> XMLElement? {
      guard let element else { return nil }
      return children(element, name).first
    }

    private func val(_ element: XMLElement?) -> String? {
      element?.attribute(forName: "val")?.stringValue
    }

    private func setVal(_ name: String, _ value: String, in parent: XMLElement) {
      guard let element = child(parent, name) else { return }
      if let existing = element.attribute(forName: "val") {
        existing.stringValue = value
      } else {
        element.addAttribute(attribute("val", value))
      }
    }

    private func position(of node: XMLNode, in parent: XMLElement) -> Int? {
      parent.children?.firstIndex { $0 === node }
    }

    /// Inserts after the last child named in `after`, or first when none is there.
    private func insert(_ element: XMLElement, in parent: XMLElement, after names: [String]) {
      let wanted = Set(names)
      let nodes = parent.children ?? []
      let last = nodes.lastIndex { node in
        (node as? XMLElement).map { wanted.contains(local($0)) } ?? false
      }
      parent.insertChild(element, at: last.map { $0 + 1 } ?? 0)
    }

    private func make(_ name: String, val value: String? = nil, text: String? = nil) -> XMLElement {
      let element = XMLElement(name: chartPrefix + name, uri: chartURI)
      if let value { element.addAttribute(attribute("val", value)) }
      if let text { element.stringValue = text }
      return element
    }

    private func makeA(_ name: String, text: String? = nil) -> XMLElement {
      let element = XMLElement(name: drawingPrefix + name, uri: drawingURI)
      if let text { element.stringValue = text }
      return element
    }

    /// A deep copy. `copy()` on an element always returns an element.
    private func clone(_ element: XMLElement) -> XMLElement {
      (element.copy() as? XMLElement) ?? XMLElement(name: element.name ?? "")
    }

    private func attribute(_ name: String, _ value: String) -> XMLNode {
      let node = XMLNode(kind: .attribute)
      node.name = name
      node.stringValue = value
      return node
    }
  }
}
