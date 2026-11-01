import AppKit
import Charts
import SparkGridCore
import SwiftUI

struct SpreadsheetChartsPanel: View {
  @Bindable var viewModel: SpreadsheetViewModel
  @Binding var isCollapsed: Bool

  static let expandedWidth: CGFloat = 360
  static let collapsedWidth: CGFloat = 28

  var body: some View {
    let charts = viewModel.activeSheet.charts
    if charts.isEmpty {
      EmptyView()
    } else {
      Group {
        if isCollapsed {
          collapsedBar
        } else {
          expandedPanel(charts: charts)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .background(SparkStyle.chrome)
    }
  }

  private var collapsedBar: some View {
    VStack(spacing: 8) {
      Button {
        withAnimation(.easeInOut(duration: 0.15)) { isCollapsed = false }
      } label: {
        Image(systemName: "chevron.left")
          .font(.system(size: 11, weight: .semibold))
          .frame(width: 28, height: 28)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help("Show charts")

      Text("Charts")
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(.secondary)
        .rotationEffect(.degrees(-90))
        .fixedSize()
        .frame(width: 28)

      Spacer(minLength: 0)
    }
    .padding(.top, 4)
  }

  private func expandedPanel(charts: [SheetChart]) -> some View {
    VStack(spacing: 0) {
      HStack(spacing: 6) {
        Text("Charts")
          .font(.system(size: 12, weight: .semibold))
        Spacer(minLength: 0)
        Button {
          withAnimation(.easeInOut(duration: 0.15)) { isCollapsed = true }
        } label: {
          Image(systemName: "sidebar.trailing")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Hide charts")
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 6)

      ChromeDivider()
        .padding(.horizontal, 10)

      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          ForEach(charts) { chart in
            chartCard(chart)
          }
        }
        .padding(10)
      }
    }
  }

  private func chartCard(_ chart: SheetChart) -> some View {
    let subtitle = seriesSubtitle(for: chart)
    let title = chart.title.trimmingCharacters(in: .whitespacesAndNewlines)
    let previewHeight = OnSheetChartGeometry.previewHeight(
      colSpan: chart.colSpan,
      rowSpan: chart.rowSpan,
      width: 320
    )
    return VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .top, spacing: 6) {
        VStack(alignment: .leading, spacing: 2) {
          Text(title.isEmpty ? "Untitled chart" : title)
            .font(.system(size: 13, weight: .semibold))
            .lineLimit(2)
          Text(subtitle)
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .lineLimit(2)
          Text(chart.placementDescription)
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        Spacer(minLength: 0)
        Button("Edit") {
          viewModel.beginEditChart(id: chart.id)
        }
        .buttonStyle(.borderless)
        .font(.system(size: 11, weight: .medium))
        .help("Edit chart type, range, and series")
        Button {
          viewModel.removeChart(id: chart.id)
        } label: {
          Image(systemName: "xmark")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 20, height: 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Delete chart")
      }
      SheetChartView(chart: chart, viewModel: viewModel)
        .frame(height: previewHeight)
        .contentShape(Rectangle())
        .onTapGesture {
          viewModel.selectChart(id: chart.id)
        }
      DisclosureGroup(isExpanded: formatExpanded(for: chart.id)) {
        ChartFormatFields(
          title: titleBinding(for: chart),
          showsLegend: flagBinding(for: chart, keyPath: \.showsLegend, actionName: "Chart Legend"),
          showsGridlines: flagBinding(
            for: chart, keyPath: \.showsGridlines, actionName: "Chart Gridlines"),
          categoryAxisTitle: textBinding(
            for: chart, keyPath: \.categoryAxisTitle, actionName: "Axis Title"),
          valueAxisTitle: textBinding(
            for: chart, keyPath: \.valueAxisTitle, actionName: "Axis Title"),
          seriesColor: ChartColorPaint.color(chart.resolvedSeriesColor),
          onSeriesColor: { color in
            viewModel.updateChartContent(id: chart.id, actionName: "Chart Color") {
              $0.seriesColor = ChartColorPaint.codable(color)
            }
          },
          points: plottedPoints(for: chart),
          pointColor: { ChartColorPaint.color(chart.resolvedColor(forPoint: $0)) },
          isPointOverride: { chart.pointColors[$0] != nil },
          onPointColor: { index, color in
            viewModel.updateChartContent(id: chart.id, actionName: "Chart Color") {
              $0.setPointColor(ChartColorPaint.codable(color), at: index)
            }
          },
          onClearPointColor: { index in
            viewModel.updateChartContent(id: chart.id, actionName: "Chart Color") {
              $0.setPointColor(nil, at: index)
            }
          }
        )
      } label: {
        Text("Format")
          .font(.system(size: 11, weight: .semibold))
      }
    }
    .padding(10)
    .background(SparkStyle.canvas, in: RoundedRectangle(cornerRadius: 8))
    .overlay(
      RoundedRectangle(cornerRadius: 8)
        .strokeBorder(
          viewModel.selectedChartID == chart.id ? SparkStyle.accent : Color.clear, lineWidth: 2)
    )
  }

  private func plottedPoints(for chart: SheetChart) -> [ChartPreviewSeries.Point] {
    ChartPreviewSeries.points(
      for: chart,
      labelFor: { viewModel.displayString(at: $0) },
      numberFor: { viewModel.displayValue(at: $0).asChartNumber }
    ).points
  }

  private func formatExpanded(for id: UUID) -> Binding<Bool> {
    Binding(
      get: { viewModel.selectedChartID == id },
      set: { expanded in
        viewModel.selectChart(id: expanded ? id : nil)
      }
    )
  }

  private func titleBinding(for chart: SheetChart) -> Binding<String> {
    Binding(
      get: { chart.title },
      set: { newValue in
        viewModel.updateChartContent(id: chart.id, actionName: "Chart Title") {
          $0.title = newValue
        }
      }
    )
  }

  private func textBinding(
    for chart: SheetChart,
    keyPath: WritableKeyPath<SheetChart, String>,
    actionName: String
  ) -> Binding<String> {
    Binding(
      get: { chart[keyPath: keyPath] },
      set: { newValue in
        viewModel.updateChartContent(id: chart.id, actionName: actionName) {
          $0[keyPath: keyPath] = newValue
        }
      }
    )
  }

  private func flagBinding(
    for chart: SheetChart,
    keyPath: WritableKeyPath<SheetChart, Bool>,
    actionName: String
  ) -> Binding<Bool> {
    Binding(
      get: { chart[keyPath: keyPath] },
      set: { newValue in
        viewModel.updateChartContent(id: chart.id, actionName: actionName) {
          $0[keyPath: keyPath] = newValue
        }
      }
    )
  }

  private func seriesSubtitle(for chart: SheetChart) -> String {
    let n = chart.dataRange.normalized
    let headerRow = chart.hasHeaderRow ? n.minRow : n.minRow
    let catCol = chart.categoryColumn ?? n.minCol
    let valCol = chart.valueColumn ?? min(n.maxCol, n.minCol + 1)
    let cat = viewModel.displayString(at: CellAddress(row: headerRow, col: catCol))
    let val = viewModel.displayString(at: CellAddress(row: headerRow, col: valCol))
    let series = ChartPreviewSeries.seriesDescription(
      for: chart,
      categoryHeader: chart.hasHeaderRow ? cat : "",
      valueHeader: chart.hasHeaderRow ? val : ""
    )
    return "\(series) · \(chart.dataRange.a1Description)"
  }
}

struct SheetChartView: View {
  let chart: SheetChart
  let viewModel: SpreadsheetViewModel

  private struct Point: Identifiable {
    let id: Int
    let label: String
    let value: Double
  }

  @State private var cachedPoints: [Point] = []
  @State private var cachedTotalCount = 0
  @State private var cachedToken = ""

  /// Points for this render. A cold cache still plots immediately so an on-sheet
  /// host does not stay empty when `onAppear` has not run yet.
  private var renderPoints: [Point] {
    if cachedToken == cacheToken { return cachedPoints }
    return Self.computePoints(chart: chart, viewModel: viewModel).points
  }

  private var renderTotalCount: Int {
    if cachedToken == cacheToken { return cachedTotalCount }
    return Self.computePoints(chart: chart, viewModel: viewModel).totalCount
  }

  /// Ideal room under the plot for category names. Charts subtracts the
  /// *actual* padding we hand it from the proposed height, so handing it
  /// this constant unconditionally let the padding alone exceed a small
  /// proposed height (side panel mid-resize, first layout, or an on-sheet
  /// card squeezed by its title) and Charts trapped computing a negative
  /// plot height inside `PositionScaleRange.plotFrame`. `plotSlot(in:)`
  /// scales the real padding down instead, so it can never reach that.
  static let plotBottomInset: CGFloat = 20
  /// Smallest interior height/width we ever ask Charts to lay out a plot
  /// into. Generous enough to leave room for Charts' own automatic axis
  /// insets too, not just our explicit bottom padding.
  static let minimumPlotHeight: CGFloat = 32
  static let minimumPlotWidth: CGFloat = 60
  /// Below this, the reserved strip under the plot is too thin to draw the
  /// category-label overlay without clipping it; the plot itself still draws.
  private static let minimumCategoryLabelPadding: CGFloat = 14
  private static let valueAxisTitleWidth: CGFloat = 16
  private static let categoryAxisTitleHeight: CGFloat = 14
  private static let legendHeight: CGFloat = 16
  private static let chromeSpacing: CGFloat = 2

  /// Bottom plot padding clamped so it can never reach `availableHeight`,
  /// no matter how small the proposed size is. `idealPadding` (20) used to
  /// be handed to `.chartPlotStyle` unconditionally; once `availableHeight`
  /// dropped below it (side panel mid-resize, first layout, or an on-sheet
  /// card squeezed by its title), Charts computed a negative plot height in
  /// `PositionScaleRange.plotFrame` and trapped.
  static func clampedBottomPadding(idealPadding: CGFloat, availableHeight: CGFloat) -> CGFloat {
    max(0, min(idealPadding, availableHeight - minimumPlotHeight))
  }

  /// Y domain Charts can turn into a position range. An empty, non-finite, or
  /// reversed domain makes `PositionScaleRange.plotFrame` trap even when the
  /// view is hundreds of points tall. Nil means "do not build a Chart".
  static func plotValueDomain(values: [Double]) -> ClosedRange<Double>? {
    let finite = values.filter(\.isFinite)
    guard let rawMax = finite.max(), let rawMin = finite.min() else { return nil }
    let lower = min(0, rawMin)
    let span = rawMax - lower
    let upper: Double
    if span > 0, span.isFinite {
      let pad = max(span * 0.08, 0.5)
      upper = rawMax + (pad.isFinite ? pad : 1)
    } else {
      upper = max(rawMax, 0) + 1
    }
    guard lower.isFinite, upper.isFinite, lower < upper else { return nil }
    return lower...upper
  }

  /// Category domain for indexes `0 ..< count`, inset by half a slot so the
  /// end bars stay inside the plot. No categories is an empty range.
  static func plotCategoryDomain(count: Int) -> ClosedRange<Double>? {
    guard count > 0 else { return nil }
    let lower = -0.5
    let upper = Double(count - 1) + 0.5
    guard lower.isFinite, upper.isFinite, lower < upper else { return nil }
    return lower...upper
  }

  var body: some View {
    GeometryReader { geo in
      chartStack(in: geo.size)
    }
    .onAppear { refreshPoints() }
    .onChange(of: cacheToken) { _, _ in
      refreshPoints()
    }
  }

  @ViewBuilder
  private func chartStack(in size: CGSize) -> some View {
    if size.width < 1 || size.height < 1 || !size.width.isFinite || !size.height.isFinite {
      EmptyView()
    } else if renderPoints.isEmpty {
      let inset: CGFloat = 8
      if let innerWidth = OnSheetChartGeometry.placedHeight(top: inset, bottom: size.width - inset),
        let innerHeight = OnSheetChartGeometry.placedHeight(top: inset, bottom: size.height - inset)
      {
        VStack(spacing: 6) {
          Text("Nothing to plot")
            .font(.system(size: 12, weight: .medium))
          Text(emptyDetail)
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .frame(width: innerWidth, height: innerHeight)
        .position(x: size.width / 2, y: size.height / 2)
      }
    } else if let chrome = chartChrome(in: size),
      let yDomain = Self.plotValueDomain(values: renderPoints.map(\.value)),
      let xDomain = Self.plotCategoryDomain(count: renderPoints.count)
    {
      VStack(alignment: .leading, spacing: Self.chromeSpacing) {
        HStack(alignment: .center, spacing: Self.chromeSpacing) {
          if chrome.showValueTitle {
            Text(chart.valueAxisTitle)
              .font(.system(size: 9, weight: .medium))
              .foregroundStyle(.secondary)
              .lineLimit(1)
              .fixedSize()
              .rotationEffect(.degrees(-90))
              .frame(width: Self.valueAxisTitleWidth, height: chrome.plotHeight)
          }
          chartBody(
            bottomPadding: chrome.bottomPadding,
            showAxisLabels: chrome.showAxisLabels,
            yDomain: yDomain,
            xDomain: xDomain
          )
          .frame(width: chrome.plotWidth, height: chrome.plotHeight)
        }
        .frame(width: size.width, height: chrome.plotHeight, alignment: .leading)
        if chrome.showCategoryTitle {
          Text(chart.categoryAxisTitle)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .frame(height: Self.categoryAxisTitleHeight)
        }
        if chrome.showLegend {
          chartLegend
            .frame(height: Self.legendHeight)
        }
        if captionHeight >= 1 {
          Text("Showing first \(ChartPreviewSeries.maxPreviewPoints) of \(renderTotalCount)")
            .font(.system(size: 9))
            .foregroundStyle(.tertiary)
            .frame(height: captionHeight, alignment: .leading)
        }
      }
      .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
  }

  private var chartLegend: some View {
    HStack(spacing: 6) {
      RoundedRectangle(cornerRadius: 2)
        .fill(seriesPaint())
        .frame(width: 10, height: 10)
      Text(legendTitle)
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .lineLimit(1)
      Spacer(minLength: 0)
    }
  }

  private var legendTitle: String {
    let n = chart.dataRange.normalized
    let valueColumn = chart.valueColumn ?? min(n.maxCol, n.minCol + 1)
    if chart.hasHeaderRow {
      let header = viewModel.displayString(at: CellAddress(row: n.minRow, col: valueColumn))
        .trimmingCharacters(in: .whitespacesAndNewlines)
      if !header.isEmpty { return header }
    }
    let title = chart.title.trimmingCharacters(in: .whitespacesAndNewlines)
    return title.isEmpty ? chart.kind.title : title
  }

  private var captionHeight: CGFloat {
    renderTotalCount > ChartPreviewSeries.maxPreviewPoints ? 14 : 0
  }

  private struct ChartChrome {
    var plotWidth: CGFloat
    var plotHeight: CGFloat
    var bottomPadding: CGFloat
    var showAxisLabels: Bool
    var showValueTitle: Bool
    var showCategoryTitle: Bool
    var showLegend: Bool
  }

  /// Chart slot sized from the proposed size. Legend, axis titles, and the
  /// truncated-series caption sit *outside* the `Chart`, and are dropped
  /// (legend, then axis titles) before the plot is allowed under
  /// `minimumPlotHeight`. Below that we don't construct a `Chart` at all:
  /// clamping our own padding to 0 still hands Charts a sliver it can trap
  /// on with its own automatic axis insets.
  private func chartChrome(in size: CGSize) -> ChartChrome? {
    guard size.width >= 1, size.height >= 1, size.width.isFinite, size.height.isFinite else {
      return nil
    }
    var showLegend = chart.showsLegend
    var showCategoryTitle = !chart.categoryAxisTitle.trimmingCharacters(in: .whitespacesAndNewlines)
      .isEmpty
    var showValueTitle = !chart.valueAxisTitle.trimmingCharacters(in: .whitespacesAndNewlines)
      .isEmpty

    func reservedHeight(legend: Bool, category: Bool) -> CGFloat {
      var bands: [CGFloat] = []
      if category { bands.append(Self.categoryAxisTitleHeight) }
      if legend { bands.append(Self.legendHeight) }
      if captionHeight >= 1 { bands.append(captionHeight) }
      guard !bands.isEmpty else { return 0 }
      return bands.reduce(0, +) + CGFloat(bands.count) * Self.chromeSpacing
    }

    var reserved = reservedHeight(legend: showLegend, category: showCategoryTitle)
    var plotHeight = size.height - reserved
    if plotHeight < Self.minimumPlotHeight, showLegend {
      showLegend = false
      reserved = reservedHeight(legend: false, category: showCategoryTitle)
      plotHeight = size.height - reserved
    }
    if plotHeight < Self.minimumPlotHeight, showCategoryTitle {
      showCategoryTitle = false
      reserved = reservedHeight(legend: false, category: false)
      plotHeight = size.height - reserved
    }
    guard let height = OnSheetChartGeometry.placedHeight(top: 0, bottom: plotHeight),
      height >= Self.minimumPlotHeight
    else {
      return nil
    }

    var plotWidth = size.width
    if showValueTitle {
      let candidate = size.width - Self.valueAxisTitleWidth - Self.chromeSpacing
      if candidate >= Self.minimumPlotWidth {
        plotWidth = candidate
      } else {
        showValueTitle = false
      }
    }
    guard plotWidth >= 1, plotWidth.isFinite else { return nil }
    let bottomPadding = Self.clampedBottomPadding(
      idealPadding: Self.plotBottomInset, availableHeight: height)
    return ChartChrome(
      plotWidth: plotWidth,
      plotHeight: height,
      bottomPadding: bottomPadding,
      showAxisLabels: plotWidth >= Self.minimumPlotWidth,
      showValueTitle: showValueTitle,
      showCategoryTitle: showCategoryTitle,
      showLegend: showLegend
    )
  }

  private var emptyDetail: String {
    switch chart.valueMode {
    case .count:
      return "No category labels in the selected range."
    case .values:
      return "Pick a numeric Value (Y) column, or switch Values to “Count of rows”."
    }
  }

  /// - Parameters:
  ///   - bottomPadding: Bottom plot padding, already clamped by `plotSlot(in:)`
  ///     so it never exceeds the height this view is given.
  ///   - showAxisLabels: Hides the leading value-axis labels (and the width
  ///     Charts reserves for them) once the proposed width is too narrow to
  ///     spare that room, e.g. mid-resize of the side panel.
  ///   - yDomain: Finite value domain with `lower < upper`. Built by
  ///     `plotValueDomain` so a Chart is never given an empty scale.
  ///   - xDomain: Category domain, same contract, from `plotCategoryDomain`.
  @ViewBuilder
  private func chartBody(
    bottomPadding: CGFloat,
    showAxisLabels: Bool,
    yDomain: ClosedRange<Double>,
    xDomain: ClosedRange<Double>
  ) -> some View {
    let points = renderPoints
    let labelIndexes = ChartCategoryLabelLayout.labelIndexes(count: points.count)
    let series = seriesPaint()
    // Paint each mark directly. `foregroundStyle(by:)` together with
    // `chartForegroundStyleScale` (keyed by the same indexes as the X axis)
    // makes Charts call `PositionScaleRange.plotFrame` with an empty range,
    // including on the 440×200 Insert Chart preview.
    Chart(points) { point in
      switch chart.kind {
      case .bar:
        BarMark(
          x: .value("Category", Double(point.id)),
          y: .value("Value", point.value)
        )
        .foregroundStyle(pointPaint(point))
      case .line:
        LineMark(
          x: .value("Category", Double(point.id)),
          y: .value("Value", point.value)
        )
        .foregroundStyle(series)
        .interpolationMethod(.catmullRom)
        PointMark(
          x: .value("Category", Double(point.id)),
          y: .value("Value", point.value)
        )
        .foregroundStyle(pointPaint(point))
        .symbolSize(points.count > 20 ? 28 : 46)
      case .area:
        AreaMark(
          x: .value("Category", Double(point.id)),
          y: .value("Value", point.value)
        )
        .foregroundStyle(series.opacity(0.28))
        LineMark(
          x: .value("Category", Double(point.id)),
          y: .value("Value", point.value)
        )
        .foregroundStyle(series)
        if chart.pointColors[point.id] != nil {
          PointMark(
            x: .value("Category", Double(point.id)),
            y: .value("Value", point.value)
          )
          .foregroundStyle(pointPaint(point))
          .symbolSize(36)
        }
      }
    }
    .chartYScale(domain: yDomain)
    .chartXScale(domain: xDomain)
    .chartPlotStyle { plot in
      plot.padding(.bottom, bottomPadding)
    }
    .chartYAxis {
      if showAxisLabels {
        AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
          if chart.showsGridlines {
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
              .foregroundStyle(Color.secondary.opacity(0.3))
          }
          AxisValueLabel {
            if let number = value.as(Double.self) {
              Text(Self.formatAxisNumber(number))
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            }
          }
        }
      }
    }
    .chartXAxis {
      if chart.showsGridlines {
        AxisMarks(values: labelIndexes.map(Double.init)) { _ in
          AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
            .foregroundStyle(Color.secondary.opacity(0.15))
        }
      }
    }
    .chartOverlay { proxy in
      GeometryReader { geo in
        if let plotAnchor = proxy.plotFrame {
          let plot = geo[plotAnchor].standardized
          if bottomPadding >= Self.minimumCategoryLabelPadding,
            OnSheetChartGeometry.placedHeight(top: plot.minY, bottom: plot.maxY) != nil
          {
            let placements = categoryPlacements(plot: plot, chartWidth: geo.size.width)
            ForEach(placements, id: \.index) { placement in
              Text(placement.text)
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: max(1, placement.width), alignment: .center)
                .position(x: placement.minX + placement.width / 2, y: plot.maxY + 9)
            }
          }
        }
      }
      .allowsHitTesting(false)
    }
    .chartLegend(.hidden)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func categoryPlacements(plot: CGRect, chartWidth: CGFloat) -> [ChartCategoryLabelLayout
    .Placement]
  {
    let points = renderPoints
    let indexes = ChartCategoryLabelLayout.labelIndexes(count: points.count)
    let lastIndex = indexes.last
    let items = indexes.compactMap { index -> ChartCategoryLabelLayout.Item? in
      guard points.indices.contains(index) else { return nil }
      let raw = points[index].label
      let text = index == lastIndex ? raw : Self.displayLabel(raw)
      return ChartCategoryLabelLayout.Item(index: index, text: text)
    }
    return ChartCategoryLabelLayout.placements(
      items: items,
      chartWidth: chartWidth,
      barCenterX: { index in
        ChartCategoryLabelLayout.barCenterX(
          index: index,
          count: renderPoints.count,
          plotMinX: plot.minX,
          plotWidth: plot.width
        )
      },
      labelWidth: { ChartCategoryLabelLayout.measure($0, fontSize: 8) }
    )
  }

  private func seriesPaint() -> Color {
    ChartColorPaint.color(chart.resolvedSeriesColor)
  }

  private func pointPaint(_ point: Point) -> Color {
    ChartColorPaint.color(chart.resolvedColor(forPoint: point.id))
  }

  private var cacheToken: String {
    let n = chart.dataRange.normalized
    // Use series config only — never a regenerating identity — so previews stay stable.
    return [
      String(viewModel.contentRevision),
      chart.kind.rawValue,
      chart.valueMode.rawValue,
      String(chart.hasHeaderRow),
      String(chart.categoryColumn ?? -1),
      String(chart.valueColumn ?? -1),
      String(n.minRow), String(n.maxRow), String(n.minCol), String(n.maxCol),
    ].joined(separator: "-")
  }

  private func refreshPoints() {
    let token = cacheToken
    guard token != cachedToken else { return }
    let computed = Self.computePoints(chart: chart, viewModel: viewModel)
    cachedTotalCount = computed.totalCount
    cachedPoints = computed.points
    cachedToken = token
  }

  private static func computePoints(
    chart: SheetChart,
    viewModel: SpreadsheetViewModel
  ) -> (points: [Point], totalCount: Int) {
    let all = ChartPreviewSeries.points(
      for: chart,
      labelFor: { viewModel.displayString(at: $0) },
      numberFor: { viewModel.displayValue(at: $0).asChartNumber }
    )
    let points = all.points.map { Point(id: $0.id, label: $0.label, value: $0.value) }
    return (points, all.totalCount)
  }

  private static func formatAxisNumber(_ value: Double) -> String {
    let absValue = abs(value)
    if absValue >= 1_000_000 {
      return String(format: "%.1fM", value / 1_000_000)
    }
    if absValue >= 10_000 {
      return String(format: "%.0fK", value / 1_000)
    }
    if value.rounded() == value, absValue < 1e9 {
      return String(Int(value))
    }
    return String(format: "%.1f", value)
  }

  private static func displayLabel(_ label: String) -> String {
    guard label.count > 12 else { return label }
    return String(label.prefix(11)) + "…"
  }
}

extension ChartMarkPalette.RGB {
  var color: Color {
    Color(red: red, green: green, blue: blue)
  }
}

/// Chart drawn on the sheet at its cell anchor. Clicks are handled by the grid.
struct OnSheetChartCard: View {
  let chart: SheetChart
  var viewModel: SpreadsheetViewModel

  var body: some View {
    let selected = viewModel.selectedChartID == chart.id
    GeometryReader { geo in
      cardContent(in: geo.size)
    }
    .background(SparkStyle.canvas, in: RoundedRectangle(cornerRadius: 6))
    .overlay(
      RoundedRectangle(cornerRadius: 6)
        .strokeBorder(
          selected ? SparkStyle.accent : SparkStyle.separator,
          lineWidth: selected ? 2 : 1)
    )
    .overlay {
      if selected {
        ChartFrameHandleMarks()
      }
    }
    .allowsHitTesting(false)
  }

  /// Title plus chart, only when each band is at least 1pt. A zero host
  /// frame used to inset this stack until the chart height was negative.
  /// An empty title is hidden so the plot can use the whole card.
  @ViewBuilder
  private func cardContent(in size: CGSize) -> some View {
    let pad: CGFloat = 6
    let title = chart.title.trimmingCharacters(in: .whitespacesAndNewlines)
    let titleHeight: CGFloat = title.isEmpty ? 0 : 14
    let spacing: CGFloat = title.isEmpty ? 0 : 2
    if let innerWidth = OnSheetChartGeometry.placedHeight(top: pad, bottom: size.width - pad),
      let innerHeight = OnSheetChartGeometry.placedHeight(top: pad, bottom: size.height - pad)
    {
      if let chartHeight = OnSheetChartGeometry.placedHeight(
        top: titleHeight + spacing,
        bottom: innerHeight
      ) {
        VStack(alignment: .leading, spacing: spacing) {
          if titleHeight >= 1 {
            Text(title)
              .font(.system(size: 11, weight: .semibold))
              .lineLimit(1)
              .padding(.horizontal, 2)
              .frame(maxWidth: .infinity, alignment: .leading)
              .frame(height: titleHeight)
          }
          SheetChartView(chart: chart, viewModel: viewModel)
            .frame(width: innerWidth, height: chartHeight)
        }
        .frame(width: innerWidth, height: innerHeight, alignment: .topLeading)
        .position(x: size.width / 2, y: size.height / 2)
      } else if titleHeight >= 1 {
        Text(title)
          .font(.system(size: 11, weight: .semibold))
          .lineLimit(1)
          .padding(.horizontal, 2)
          .frame(width: innerWidth, height: innerHeight, alignment: .topLeading)
          .position(x: size.width / 2, y: size.height / 2)
      }
    }
  }
}

/// Corner and edge handles drawn on a selected on-sheet chart.
private struct ChartFrameHandleMarks: View {
  var body: some View {
    GeometryReader { geo in
      let size = geo.size
      let points = [
        CGPoint(x: 0, y: 0),
        CGPoint(x: size.width / 2, y: 0),
        CGPoint(x: size.width, y: 0),
        CGPoint(x: 0, y: size.height / 2),
        CGPoint(x: size.width, y: size.height / 2),
        CGPoint(x: 0, y: size.height),
        CGPoint(x: size.width / 2, y: size.height),
        CGPoint(x: size.width, y: size.height),
      ]
      ForEach(Array(points.enumerated()), id: \.offset) { _, point in
        RoundedRectangle(cornerRadius: 1)
          .fill(Color.white)
          .overlay(
            RoundedRectangle(cornerRadius: 1)
              .strokeBorder(SparkStyle.accent, lineWidth: 1)
          )
          .frame(width: 8, height: 8)
          .position(point)
      }
    }
    .allowsHitTesting(false)
  }
}

/// Flipped so the card lines up with the grid's top-left coordinates.
/// `NSHostingView.isFlipped` is final and settable, so it cannot be overridden.
final class OnSheetChartHost: NSHostingView<OnSheetChartCard> {
  required init(rootView: OnSheetChartCard) {
    super.init(rootView: rootView)
    isFlipped = true
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    isFlipped = true
  }
}

enum ChartColorPaint {
  static func color(_ value: CodableColor) -> Color {
    Color(red: value.red, green: value.green, blue: value.blue, opacity: value.alpha)
  }

  static func codable(_ color: Color) -> CodableColor {
    CellFormatRenderer.codableColor(from: NSColor(color))
  }
}

/// Title, legend, axis titles, gridlines, series color, and per-point colors.
/// Shared by the side panel and Edit Chart.
struct ChartFormatFields: View {
  @Binding var title: String
  @Binding var showsLegend: Bool
  @Binding var showsGridlines: Bool
  @Binding var categoryAxisTitle: String
  @Binding var valueAxisTitle: String
  var seriesColor: Color
  var onSeriesColor: (Color) -> Void
  var points: [ChartPreviewSeries.Point]
  var pointColor: (Int) -> Color
  var isPointOverride: (Int) -> Bool
  var onPointColor: (Int, Color) -> Void
  var onClearPointColor: (Int) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      TextField("Chart title", text: $title)
      Toggle("Legend", isOn: $showsLegend)
      Toggle("Gridlines", isOn: $showsGridlines)
      TextField("Category axis title", text: $categoryAxisTitle, prompt: Text("Category"))
      TextField("Value axis title", text: $valueAxisTitle, prompt: Text("Value"))

      Text("Series color")
        .font(.system(size: 11, weight: .medium))
      HStack(spacing: 4) {
        ForEach(Array(ChartMarkPalette.swatches.enumerated()), id: \.offset) { _, swatch in
          Button {
            onSeriesColor(swatch.color)
          } label: {
            RoundedRectangle(cornerRadius: 3)
              .fill(swatch.color)
              .frame(width: 16, height: 16)
              .overlay(
                RoundedRectangle(cornerRadius: 3)
                  .strokeBorder(Color.primary.opacity(0.28), lineWidth: 1)
              )
          }
          .buttonStyle(.plain)
          .help("Series color")
        }
      }
      ColorPicker(
        "Custom series color",
        selection: Binding(get: { seriesColor }, set: onSeriesColor),
        supportsOpacity: false
      )
      .font(.system(size: 11))

      if !points.isEmpty {
        Text("Point colors")
          .font(.system(size: 11, weight: .medium))
        Text("Each bar or point uses the series color until you give it one of its own.")
          .font(.system(size: 10))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        ScrollView {
          VStack(alignment: .leading, spacing: 4) {
            ForEach(points) { point in
              HStack(spacing: 6) {
                Text(point.label)
                  .font(.system(size: 11))
                  .lineLimit(1)
                Spacer(minLength: 4)
                if isPointOverride(point.id) {
                  Button("Use series color") {
                    onClearPointColor(point.id)
                  }
                  .buttonStyle(.borderless)
                  .font(.system(size: 10))
                }
                ColorPicker(
                  point.label,
                  selection: Binding(
                    get: { pointColor(point.id) },
                    set: { onPointColor(point.id, $0) }
                  ),
                  supportsOpacity: false
                )
                .labelsHidden()
              }
            }
          }
        }
        .frame(maxHeight: 160)
      }
    }
    .padding(.top, 4)
  }
}
