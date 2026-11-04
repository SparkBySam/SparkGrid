import AppKit
import SparkGridCore

/// Charts from other apps, drawn from the cells they name. Their chart parts are saved unchanged.
extension SpreadsheetViewModel {
  /// One chart from the file, where it sits, and what it shows.
  struct ImportedChartPlacement: Identifiable, Equatable {
    /// Position among the sheet's kept charts.
    let id: Int
    let chart: ImportedChart
    let from: DrawingMarker
    let to: DrawingMarker?
    /// Width and height in points, for a chart anchored at one cell.
    let size: CGSize?
  }

  /// One plotted point. `x` is set for scatter charts.
  struct ImportedChartPoint: Identifiable, Equatable {
    let id: Int
    let label: String
    let x: Double?
    let value: Double
  }

  /// How a value axis labels its numbers, from the first value cell's format.
  enum ImportedChartValueStyle: Equatable {
    case plain
    case currency(symbol: String)
    case percent
  }

  struct ImportedChartSeriesData: Identifiable, Equatable {
    let id: Int
    let name: String
    let colorHex: String?
    let points: [ImportedChartPoint]
    let valueStyle: ImportedChartValueStyle
  }

  /// Most points drawn per series. A chart over a whole column stays responsive.
  static let importedChartPointLimit = 2_000

  /// The active sheet's charts from other apps that Spark Grid can draw.
  var importedChartPlacements: [ImportedChartPlacement] {
    let kept = activeSheet.fileExtras.foreignCharts
    guard !kept.isEmpty else { return [] }
    return kept.enumerated().compactMap { index, part in
      guard let from = part.from, let chart = importedChart(for: part.chartXML) else { return nil }
      return ImportedChartPlacement(
        id: index, chart: chart, from: from, to: part.to,
        size: part.to == nil ? Self.oneCellAnchorSize(part.anchorXML) : nil)
    }
  }

  /// Each series' points from the cells it names, or from the values the file saved where a
  /// cell cannot be read, such as a sheet the file no longer has.
  func importedChartSeries(_ chart: ImportedChart) -> [ImportedChartSeriesData] {
    chart.series.enumerated().map { index, series in
      let name: String
      if let ref = series.nameReference, let first = ref.addresses.first {
        let shown = chartText(sheetName: ref.sheetName, at: first)
        name = shown.isEmpty ? series.name : shown
      } else {
        name = series.name
      }
      let valueCells = Array((series.values?.addresses ?? []).prefix(Self.importedChartPointLimit))
      let categoryCells = Array(
        (series.categories?.addresses ?? []).prefix(Self.importedChartPointLimit))
      let count = max(
        valueCells.count, min(series.cachedValues.count, Self.importedChartPointLimit))
      var points: [ImportedChartPoint] = []
      points.reserveCapacity(count)
      for point in 0..<count {
        var value: Double?
        if point < valueCells.count {
          value = chartNumber(sheetName: series.values?.sheetName, at: valueCells[point])
        }
        if value == nil, point < series.cachedValues.count {
          value = series.cachedValues[point]
        }
        guard let value, value.isFinite else { continue }
        var label = ""
        var x: Double?
        if point < categoryCells.count {
          let sheet = series.categories?.sheetName
          label = chartText(sheetName: sheet, at: categoryCells[point])
          x = chartNumber(sheetName: sheet, at: categoryCells[point])
        }
        if label.isEmpty, point < series.cachedCategories.count {
          label = series.cachedCategories[point]
          x = x ?? Double(label)
        }
        if label.isEmpty { label = "\(point + 1)" }
        points.append(ImportedChartPoint(id: point, label: label, x: x, value: value))
      }
      return ImportedChartSeriesData(
        id: index, name: name, colorHex: series.colorHex, points: points,
        valueStyle: chartValueStyle(sheetName: series.values?.sheetName, at: valueCells.first))
    }
  }

  /// A Spark Grid chart as series: one per value column, named by its header cell. Count mode
  /// plots how many rows hold each category, as one series.
  func seriesPlot(for chart: SheetChart) -> (
    chart: ImportedChart, series: [ImportedChartSeriesData]
  ) {
    let kind: ImportedChart.Kind
    switch chart.kind {
    case .bar: kind = .column
    case .line: kind = .line
    case .area: kind = .area
    case .pie: kind = .pie
    case .scatter: kind = .scatter
    }
    let n = chart.dataRange.normalized
    let hasHeader = chart.hasHeaderRow && n.maxRow > n.minRow
    let firstRow = hasHeader ? n.minRow + 1 : n.minRow
    let categoryColumn = chart.categoryColumn ?? n.minCol
    let valueColumn = chart.valueColumn ?? min(n.maxCol, n.minCol + (n.minCol == n.maxCol ? 0 : 1))
    func column(_ col: Int) -> ImportedChart.Reference {
      ImportedChart.Reference(
        sheetName: nil,
        range: CellRange(
          start: CellAddress(row: firstRow, col: col), end: CellAddress(row: n.maxRow, col: col)))
    }
    let base = ImportedChart(
      kind: kind, title: chart.title, series: [], showsLegend: chart.showsLegend,
      categoryAxisTitle: chart.categoryAxisTitle, valueAxisTitle: chart.valueAxisTitle)

    if chart.valueMode == .count {
      let counted = ChartPreviewSeries.points(
        for: chart,
        labelFor: { self.displayString(at: $0) },
        numberFor: { self.displayValue(at: $0).asChartNumber })
      let points = counted.points.map {
        ImportedChartPoint(id: $0.id, label: $0.label, x: Double($0.id), value: $0.value)
      }
      let name = chart.title.isEmpty ? "Count" : chart.title
      return (
        base,
        [
          ImportedChartSeriesData(
            id: 0, name: name, colorHex: nil, points: points, valueStyle: .plain)
        ]
      )
    }

    var columns = [valueColumn]
    if chart.kind.allowsMoreSeries {
      columns += chart.extraValueColumns.filter { $0 != valueColumn }
    }
    var plotted = base
    plotted.series = columns.map { col in
      ImportedChart.Series(
        nameReference: hasHeader
          ? ImportedChart.Reference(
            sheetName: nil,
            range: CellRange(
              start: CellAddress(row: n.minRow, col: col), end: CellAddress(row: n.minRow, col: col)
            ))
          : nil,
        categories: column(categoryColumn),
        values: column(col))
    }
    var series = importedChartSeries(plotted)
    // The first series keeps the chart's own color.
    if let first = series.first, columns.count == 1 || chart.seriesColor != nil {
      let color = chart.resolvedSeriesColor
      series[0] = ImportedChartSeriesData(
        id: first.id, name: first.name.isEmpty ? chart.title : first.name,
        colorHex: String(
          format: "%02X%02X%02X", Int(color.red * 255), Int(color.green * 255),
          Int(color.blue * 255)),
        points: first.points, valueStyle: first.valueStyle)
    }
    return (plotted, series)
  }

  // MARK: - Select, move, delete

  func selectImportedChart(_ id: Int?) {
    guard selectedImportedChartID != id else { return }
    if id != nil {
      selectedChartID = nil
      selectedImageID = nil
    }
    selectedImportedChartID = id
  }

  /// Puts a chart from the file at new anchor cells. The file's own anchor moves with it, so
  /// other apps show it in the same place.
  func moveImportedChart(_ id: Int, from: DrawingMarker, to: DrawingMarker?) {
    guard activeSheet.fileExtras.foreignCharts.indices.contains(id) else { return }
    updateFileExtras(actionName: "Move Chart") { extras in
      extras.foreignCharts[id].from = from
      if extras.foreignCharts[id].to != nil { extras.foreignCharts[id].to = to }
    }
  }

  /// Gives a chart from the file a new frame. A chart anchored at two cells gets both new
  /// cells; one anchored at a single cell keeps its own size, `<xdr:ext>`, in EMU.
  func resizeImportedChart(_ id: Int, from: DrawingMarker, to: DrawingMarker?, size: CGSize) {
    guard activeSheet.fileExtras.foreignCharts.indices.contains(id) else { return }
    updateFileExtras(actionName: "Resize Chart") { extras in
      var part = extras.foreignCharts[id]
      part.from = from
      if part.to != nil {
        part.to = to
      } else {
        part.anchorXML = DrawingAnchorXML.withSize(part.anchorXML, size)
      }
      extras.foreignCharts[id] = part
    }
  }

  /// The chart as the Edit Chart sheet starts it.
  func importedChartEdit(_ id: Int) -> ImportedChartEdit? {
    guard let chart = importedChartPlacements.first(where: { $0.id == id })?.chart else {
      return nil
    }
    return ImportedChartEdit(chart: chart, sheetName: activeSheet.name)
  }

  /// Rewrites the chart's own part. False when a reference in `edit` isn't one.
  @discardableResult
  func applyImportedChartEdit(_ id: Int, _ edit: ImportedChartEdit) -> Bool {
    let parts = activeSheet.fileExtras.foreignCharts
    guard parts.indices.contains(id),
      let data = ImportedChartWriter.apply(
        edit, to: parts[id].chartXML, sheetName: activeSheet.name)
    else { return false }
    guard data != parts[id].chartXML else { return true }
    updateFileExtras(actionName: "Edit Chart") { extras in
      extras.foreignCharts[id].chartXML = data
    }
    return true
  }

  /// Selects a chart from the file and scrolls the grid to it.
  func showImportedChart(_ id: Int) {
    selectImportedChart(id)
    chartScrollID = nil
    importedChartScrollID = id
    chartScrollToken &+= 1
    notifyGridRefresh()
  }

  func beginEditImportedChart(_ id: Int) {
    guard activeSheet.fileExtras.foreignCharts.indices.contains(id) else { return }
    selectImportedChart(id)
    editingImportedChartID = id
  }

  /// A copy two rows down, selected.
  func duplicateImportedChart(_ id: Int) {
    let parts = activeSheet.fileExtras.foreignCharts
    guard parts.indices.contains(id) else { return }
    // Saving numbers every object in the drawing, so the copy needs no id of its own here.
    let copy = DrawingAnchorXML.shifted(parts[id], rows: 2)
    updateFileExtras(actionName: "Duplicate Chart") { extras in
      extras.foreignCharts.append(copy)
    }
    selectImportedChart(activeSheet.fileExtras.foreignCharts.count - 1)
  }

  /// Draws the chart above or below the sheet's other charts from the file.
  func reorderImportedChart(_ id: Int, toFront: Bool) {
    let parts = activeSheet.fileExtras.foreignCharts
    guard parts.indices.contains(id), parts.count > 1 else { return }
    let target = toFront ? parts.count - 1 : 0
    guard target != id else { return }
    updateFileExtras(actionName: toFront ? "Bring to Front" : "Send to Back") { extras in
      let part = extras.foreignCharts.remove(at: id)
      extras.foreignCharts.insert(part, at: target)
    }
    selectImportedChart(target)
  }

  func deleteImportedChart(_ id: Int) {
    guard activeSheet.fileExtras.foreignCharts.indices.contains(id) else { return }
    selectedImportedChartID = nil
    updateFileExtras(actionName: "Delete Chart") { extras in
      extras.foreignCharts.remove(at: id)
    }
  }

  // MARK: - Private

  private func importedChart(for xml: Data) -> ImportedChart? {
    if let cached = importedChartCache[xml] { return cached }
    let chart = ImportedChartReader.read(xml)
    importedChartCache[xml] = .some(chart)
    return chart
  }

  private func chartSheet(named name: String?) -> Sheet? {
    guard let name else { return activeSheet }
    return workbook.sheets.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
  }

  private func chartValue(sheetName: String?, at address: CellAddress) -> CellValue? {
    guard let sheet = chartSheet(named: sheetName) else { return nil }
    // The sheet being edited is read from the view's own copy. The engine's copy of it is
    // replaced only on a full rebuild, so a typed value read old until then.
    let value =
      sheet.id == activeSheet.id
      ? formulaEngine.sheetDisplayValue(at: address, sheet: sheet)
      : formulaEngine.value(onSheet: sheet.name, at: address)
    if case .error = value { return nil }
    return value
  }

  private func chartNumber(sheetName: String?, at address: CellAddress) -> Double? {
    guard let value = chartValue(sheetName: sheetName, at: address) else { return nil }
    if case .bool = value { return nil }
    return value.asNumber
  }

  /// The cell as its sheet shows it, with its number format, such as `Jan` or `$12,000`.
  private func chartText(sheetName: String?, at address: CellAddress) -> String {
    guard let sheet = chartSheet(named: sheetName),
      let value = chartValue(sheetName: sheetName, at: address)
    else { return "" }
    let cell = sheet.cell(at: address)
    return CellFormatRenderer.displayText(for: value, format: cell.format, fallbackRaw: cell.raw)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func chartValueStyle(sheetName: String?, at address: CellAddress?)
    -> ImportedChartValueStyle
  {
    guard let address, let format = chartSheet(named: sheetName)?.cell(at: address).format else {
      return .plain
    }
    switch format.numberFormat {
    case .percent:
      return .percent
    case .currency:
      let code = format.formatCode ?? ""
      for symbol in ["€", "£", "¥"] where code.contains(symbol) {
        return .currency(symbol: symbol)
      }
      return .currency(symbol: "$")
    default:
      return .plain
    }
  }

  /// `<xdr:ext cx="5760000" cy="2700000"/>` in points; 12,700 EMU make a point.
  private static func oneCellAnchorSize(_ anchorXML: String) -> CGSize? {
    guard
      let range = anchorXML.range(
        of: #"<(?:\w+:)?ext\s+cx="(\d+)"\s+cy="(\d+)""#, options: .regularExpression)
    else { return nil }
    let tag = String(anchorXML[range])
    let numbers = tag.split(whereSeparator: { !$0.isNumber }).compactMap { Double($0) }
    guard numbers.count >= 2 else { return nil }
    let width = numbers[numbers.count - 2] / 12_700
    let height = numbers[numbers.count - 1] / 12_700
    guard width >= 1, height >= 1 else { return nil }
    return CGSize(width: width, height: height)
  }
}
