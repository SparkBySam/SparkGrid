import Charts
import Observation
import SparkGridCore
import SwiftUI

/// Where the pointer rests over a chart card, in the card's own coordinates. The grid sets it;
/// the card itself takes no mouse events, so clicks and drags still reach the grid.
@Observable
final class ChartHover {
  var location: CGPoint?

  /// The card's coordinate space, which `location` is in.
  static let space = "chart-card"
}

/// A chart from another app, drawn on the sheet where the file placed it. It reads its cells
/// each time the workbook changes. It can be moved, resized and edited; edits rewrite its own
/// chart part, so other apps open the same chart.
struct ImportedChartCard: View {
  let placement: SpreadsheetViewModel.ImportedChartPlacement
  var viewModel: SpreadsheetViewModel
  var hover: ChartHover?

  private var selected: Bool { viewModel.selectedImportedChartID == placement.id }

  var body: some View {
    let series = viewModel.importedChartSeries(placement.chart)
    GeometryReader { geo in
      let pad: CGFloat = 8
      let title = placement.chart.title.trimmingCharacters(in: .whitespacesAndNewlines)
      let titleHeight: CGFloat = title.isEmpty ? 0 : 16
      let plotHeight = geo.size.height - pad * 2 - titleHeight
      let plotWidth = geo.size.width - pad * 2
      VStack(alignment: .leading, spacing: 0) {
        if !title.isEmpty {
          Text(title)
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .center)
            .frame(height: titleHeight)
        }
        if plotHeight >= 40, plotWidth >= 60 {
          ImportedChartPlot(chart: placement.chart, series: series, hover: hover)
            .frame(width: plotWidth, height: plotHeight)
        }
      }
      .padding(pad)
    }
    .coordinateSpace(name: ChartHover.space)
    .background(SparkStyle.canvas, in: RoundedRectangle(cornerRadius: 6))
    .overlay(
      RoundedRectangle(cornerRadius: 6)
        .strokeBorder(
          selected ? SparkStyle.accent : SparkStyle.separator, lineWidth: selected ? 2 : 1)
    )
    .overlay {
      if selected { ChartFrameHandleMarks() }
    }
    .allowsHitTesting(false)
  }
}

/// The plot for one imported chart.
struct ImportedChartPlot: View {
  let chart: ImportedChart
  let series: [SpreadsheetViewModel.ImportedChartSeriesData]
  var hover: ChartHover?

  private struct Mark: Identifiable {
    let id: String
    let seriesName: String
    let label: String
    let x: Double?
    let value: Double
  }

  private var marks: [Mark] {
    series.flatMap { line in
      line.points.map {
        Mark(
          id: "\(line.id)-\($0.id)", seriesName: seriesName(line), label: $0.label, x: $0.x,
          value: $0.value)
      }
    }
  }

  private var showsLegend: Bool {
    chart.showsLegend || series.count > 1
  }

  var body: some View {
    let marks = marks
    if marks.isEmpty {
      Text("No data to show")
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      switch chart.kind {
      case .pie, .doughnut:
        pie(marks)
      case .scatter:
        scatter(marks)
      default:
        cartesian(marks)
      }
    }
  }

  /// One horizontal bar, or one series' piece of a stacked bar, placed on a numbered row.
  private struct RowBar: Identifiable {
    let id: String
    let seriesName: String
    let start: Double
    let end: Double
    let low: Double
    let high: Double
  }

  /// Categories in the order the file lists them, top row first.
  private func rowCategories(_ marks: [Mark]) -> [String] {
    var seen = Set<String>()
    return marks.map(\.label).filter { seen.insert($0).inserted }
  }

  /// Horizontal bars with category text on the Y axis drew as hairlines between the rows, with
  /// the labels over them. Each category gets a numbered row instead; row 0 is at the bottom.
  private func rowBars(_ marks: [Mark], categories: [String]) -> [RowBar] {
    let rowOf = Dictionary(
      categories.enumerated().map { ($1, Double(categories.count - 1 - $0)) },
      uniquingKeysWith: { first, _ in first })
    let names = seriesNames
    let width = 0.8 / Double(max(1, names.count))
    var positive: [String: Double] = [:]
    var negative: [String: Double] = [:]
    return marks.compactMap { mark in
      guard let row = rowOf[mark.label] else { return nil }
      if chart.isStacked {
        let start: Double
        if mark.value >= 0 {
          start = positive[mark.label, default: 0]
          positive[mark.label] = start + mark.value
        } else {
          start = negative[mark.label, default: 0]
          negative[mark.label] = start + mark.value
        }
        return RowBar(
          id: mark.id, seriesName: mark.seriesName, start: start, end: start + mark.value,
          low: row - 0.35, high: row + 0.35)
      }
      // Side by side: the first series on top within its row.
      let slot = Double(names.count - 1 - (names.firstIndex(of: mark.seriesName) ?? 0))
      let low = row - 0.4 + slot * width
      return RowBar(
        id: mark.id, seriesName: mark.seriesName, start: 0, end: mark.value,
        low: low, high: low + width * 0.9)
    }
  }

  @ViewBuilder
  private func horizontalBars(_ marks: [Mark], domain: ClosedRange<Double>) -> some View {
    let categories = rowCategories(marks)
    let rows = Array(0..<categories.count).map(Double.init)
    let top = Double(categories.count) - 0.5
    Chart(rowBars(marks, categories: categories)) { bar in
      RectangleMark(
        xStart: .value("Start", bar.start), xEnd: .value("End", bar.end),
        yStart: .value("Row", bar.low), yEnd: .value("Row", bar.high)
      )
      .foregroundStyle(by: .value("Series", bar.seriesName))
    }
    .chartXScale(domain: domain)
    .chartXAxis {
      AxisMarks { value in
        AxisGridLine()
        AxisValueLabel {
          if let number = value.as(Double.self) {
            Text(ImportedChartPlot.axisLabel(number, style: valueStyle))
          }
        }
      }
    }
    .chartYScale(domain: -0.5...top)
    .chartYAxis {
      AxisMarks(position: .leading, values: rows) { value in
        AxisValueLabel(Self.rowLabel(value.as(Double.self), categories))
      }
    }
    .chartForegroundStyleScale(domain: seriesNames, range: seriesColors)
    .chartLegend(showsLegend ? .visible : .hidden)
    .chartOverlay { proxy in hoverLayer(proxy, marks) }
    .chartXAxisLabel(chart.valueAxisTitle)
    .chartYAxisLabel(chart.categoryAxisTitle)
  }

  /// The category drawn at a row number, or nil off the rows.
  private static func rowCategory(_ row: Double?, _ categories: [String]) -> String? {
    guard let row, row.isFinite else { return nil }
    let index = categories.count - 1 - Int(row.rounded())
    return categories.indices.contains(index) ? categories[index] : nil
  }

  private static func rowLabel(_ row: Double?, _ categories: [String]) -> String {
    rowCategory(row, categories) ?? ""
  }

  @ViewBuilder
  private func cartesian(_ marks: [Mark]) -> some View {
    let values = stackedExtremes(marks)
    if let domain = SheetChartView.plotValueDomain(values: values) {
      if chart.kind == .bar {
        horizontalBars(marks, domain: domain)
      } else {
        verticalPlot(marks, domain: domain)
      }
    }
  }

  @ViewBuilder
  private func verticalPlot(_ marks: [Mark], domain: ClosedRange<Double>) -> some View {
    Chart(marks) { mark in
      switch chart.kind {
      case .line:
        LineMark(x: .value("Category", mark.label), y: .value("Value", mark.value))
          .foregroundStyle(by: .value("Series", mark.seriesName))
        PointMark(x: .value("Category", mark.label), y: .value("Value", mark.value))
          .foregroundStyle(by: .value("Series", mark.seriesName))
          .symbolSize(16)
      case .area:
        // Areas stack unless told not to; a file's standard area chart overlaps them.
        AreaMark(
          x: .value("Category", mark.label), y: .value("Value", mark.value),
          stacking: chart.isStacked ? .standard : .unstacked
        )
        .foregroundStyle(by: .value("Series", mark.seriesName))
      default:
        if chart.isStacked {
          BarMark(x: .value("Category", mark.label), y: .value("Value", mark.value))
            .foregroundStyle(by: .value("Series", mark.seriesName))
        } else {
          BarMark(x: .value("Category", mark.label), y: .value("Value", mark.value))
            .foregroundStyle(by: .value("Series", mark.seriesName))
            .position(by: .value("Series", mark.seriesName))
        }
      }
    }
    .modifier(ValueDomain(domain: domain, style: valueStyle))
    .chartForegroundStyleScale(domain: seriesNames, range: seriesColors)
    .chartLegend(showsLegend ? .visible : .hidden)
    .chartOverlay { proxy in hoverLayer(proxy, marks) }
    .chartXAxisLabel(chart.categoryAxisTitle)
    .chartYAxisLabel(chart.valueAxisTitle)
  }

  @ViewBuilder
  private func scatter(_ marks: [Mark]) -> some View {
    let points = marks.compactMap { mark in mark.x.map { (mark, $0) } }
    if let yDomain = SheetChartView.plotValueDomain(values: points.map(\.0.value)),
      let xDomain = SheetChartView.plotValueDomain(values: points.map(\.1))
    {
      Chart(points, id: \.0.id) { mark, x in
        PointMark(x: .value("X", x), y: .value("Y", mark.value))
          .foregroundStyle(by: .value("Series", mark.seriesName))
      }
      .chartXScale(domain: xDomain)
      .chartYScale(domain: yDomain)
      .chartForegroundStyleScale(domain: seriesNames, range: seriesColors)
      .chartLegend(showsLegend ? .visible : .hidden)
      .chartOverlay { proxy in hoverLayer(proxy, marks) }
      .chartXAxisLabel(chart.categoryAxisTitle)
      .chartYAxisLabel(chart.valueAxisTitle)
    }
  }

  /// The first series as slices; other apps draw a pie from one series.
  @ViewBuilder
  private func pie(_ marks: [Mark]) -> some View {
    let firstSeries = marks.first?.seriesName
    let slices = marks.filter { $0.seriesName == firstSeries && $0.value > 0 }
    if !slices.isEmpty {
      Chart(slices) { slice in
        SectorMark(
          angle: .value("Value", slice.value),
          innerRadius: .ratio(chart.kind == .doughnut ? 0.5 : 0),
          angularInset: 1
        )
        .foregroundStyle(by: .value("Category", slice.label))
      }
      .chartLegend(.visible)
      .chartOverlay { proxy in hoverLayer(proxy, slices) }
    }
  }

  // MARK: - Hover

  /// A small label beside the pointer naming the bar, point, or slice under it.
  private func hoverLayer(_ proxy: ChartProxy, _ marks: [Mark]) -> some View {
    GeometryReader { geo in
      if let location = hover?.location, let plotAnchor = proxy.plotFrame {
        let origin = geo.frame(in: .named(ChartHover.space)).origin
        let local = CGPoint(x: location.x - origin.x, y: location.y - origin.y)
        let plot = geo[plotAnchor]
        if plot.contains(local),
          let text = hoverText(
            proxy, marks, at: CGPoint(x: local.x - plot.minX, y: local.y - plot.minY),
            plot: plot.size)
        {
          ChartHoverBubble(text: text)
            .position(
              x: min(max(local.x, 70), max(70, geo.size.width - 70)),
              y: max(16, local.y - 22))
        }
      }
    }
    .allowsHitTesting(false)
  }

  private func hoverText(_ proxy: ChartProxy, _ marks: [Mark], at point: CGPoint, plot: CGSize)
    -> String?
  {
    switch chart.kind {
    case .pie, .doughnut:
      return sliceText(marks, at: point, plot: plot)
    case .scatter:
      var best: (Mark, CGFloat)?
      for mark in marks {
        guard let x = mark.x, let position = proxy.position(for: (x, mark.value)) else {
          continue
        }
        let distance = hypot(position.x - point.x, position.y - point.y)
        if distance <= 14, distance < (best?.1 ?? .infinity) { best = (mark, distance) }
      }
      guard let (mark, _) = best, let x = mark.x else { return nil }
      return "\(mark.seriesName)\n\(Self.fullLabel(x, style: .plain)), \(format(mark.value))"
    case .bar:
      guard
        let label = Self.rowCategory(
          proxy.value(atY: point.y, as: Double.self), rowCategories(marks))
      else { return nil }
      return categoryText(label, marks)
    default:
      guard let label = proxy.value(atX: point.x, as: String.self) else { return nil }
      return categoryText(label, marks)
    }
  }

  /// The category and each series' value in it.
  private func categoryText(_ label: String, _ marks: [Mark]) -> String? {
    let hits = marks.filter { $0.label == label }
    guard !hits.isEmpty else { return nil }
    if hits.count == 1, series.count == 1 {
      return "\(label)\n\(format(hits[0].value))"
    }
    return ([label] + hits.map { "\($0.seriesName): \(format($0.value))" }).joined(separator: "\n")
  }

  /// The slice whose angle holds the pointer. Slices run clockwise from the top.
  private func sliceText(_ slices: [Mark], at point: CGPoint, plot: CGSize) -> String? {
    let center = CGPoint(x: plot.width / 2, y: plot.height / 2)
    let dx = point.x - center.x
    let dy = point.y - center.y
    let radius = min(plot.width, plot.height) / 2
    let distance = hypot(dx, dy)
    guard distance <= radius, chart.kind != .doughnut || distance >= radius * 0.5 else {
      return nil
    }
    var angle = atan2(dx, -dy)
    if angle < 0 { angle += 2 * .pi }
    let total = slices.reduce(0) { $0 + $1.value }
    guard total > 0 else { return nil }
    var start: Double = 0
    for slice in slices {
      let end = start + slice.value / total * 2 * .pi
      if Double(angle) >= start, Double(angle) < end {
        let share = (slice.value / total).formatted(.percent.precision(.fractionLength(0...1)))
        return "\(slice.label)\n\(format(slice.value)) (\(share))"
      }
      start = end
    }
    return nil
  }

  private func format(_ value: Double) -> String {
    Self.fullLabel(value, style: valueStyle)
  }

  /// A value in full, in its cells' style: `$3,976,281`, `12.5%`, `1,024`.
  static func fullLabel(_ value: Double, style: SpreadsheetViewModel.ImportedChartValueStyle)
    -> String
  {
    switch style {
    case .percent:
      return value.formatted(.percent.precision(.fractionLength(0...2)))
    case .currency(let symbol):
      let digits = abs(value).formatted(.number.precision(.fractionLength(0...2)))
      return (value < 0 ? "-" : "") + symbol + digits
    case .plain:
      return value.formatted(.number.precision(.fractionLength(0...4)))
    }
  }

  // MARK: - Helpers

  private func seriesName(_ line: SpreadsheetViewModel.ImportedChartSeriesData) -> String {
    line.name.isEmpty ? "Series \(line.id + 1)" : line.name
  }

  private var seriesNames: [String] { series.map(seriesName) }

  private var seriesColors: [Color] {
    series.enumerated().map { index, line in
      if let hex = line.colorHex, let color = Self.color(hex: hex) { return color }
      return Self.palette[index % Self.palette.count]
    }
  }

  /// Highest and lowest totals a stacked chart reaches, or every value when bars stand apart.
  private func stackedExtremes(_ marks: [Mark]) -> [Double] {
    guard chart.isStacked, chart.kind != .line else { return marks.map(\.value) }
    var positive: [String: Double] = [:]
    var negative: [String: Double] = [:]
    for mark in marks {
      if mark.value >= 0 {
        positive[mark.label, default: 0] += mark.value
      } else {
        negative[mark.label, default: 0] += mark.value
      }
    }
    return Array(positive.values) + Array(negative.values) + [0]
  }

  static let palette: [Color] = [
    Color(red: 0.27, green: 0.45, blue: 0.77), Color(red: 0.93, green: 0.49, blue: 0.19),
    Color(red: 0.65, green: 0.65, blue: 0.65), Color(red: 1.0, green: 0.75, blue: 0.0),
    Color(red: 0.36, green: 0.61, blue: 0.84), Color(red: 0.44, green: 0.68, blue: 0.28),
  ]

  static func color(hex: String) -> Color? {
    guard hex.count == 6, let value = Int(hex, radix: 16) else { return nil }
    return Color(
      red: Double((value >> 16) & 0xFF) / 255,
      green: Double((value >> 8) & 0xFF) / 255,
      blue: Double(value & 0xFF) / 255)
  }

  private var valueStyle: SpreadsheetViewModel.ImportedChartValueStyle {
    series.first?.valueStyle ?? .plain
  }

  /// `$4M`, `250K`, `25%`: short labels for a value axis, in the cells' own style.
  static func axisLabel(_ value: Double, style: SpreadsheetViewModel.ImportedChartValueStyle)
    -> String
  {
    if case .percent = style {
      return value.formatted(.percent.precision(.fractionLength(0...1)))
    }
    let magnitude = abs(value)
    let short: String
    if magnitude >= 1_000_000_000 {
      short = (value / 1_000_000_000).formatted(.number.precision(.fractionLength(0...1))) + "B"
    } else if magnitude >= 1_000_000 {
      short = (value / 1_000_000).formatted(.number.precision(.fractionLength(0...1))) + "M"
    } else if magnitude >= 10_000 {
      short = (value / 1_000).formatted(.number.precision(.fractionLength(0...1))) + "K"
    } else {
      short = value.formatted(.number.precision(.fractionLength(0...2)))
    }
    if case .currency(let symbol) = style {
      return short.hasPrefix("-") ? "-" + symbol + short.dropFirst() : symbol + short
    }
    return short
  }

  /// The value axis's range and labels on the axis it runs along.
  private struct ValueDomain: ViewModifier {
    let domain: ClosedRange<Double>
    let style: SpreadsheetViewModel.ImportedChartValueStyle

    func body(content: Content) -> some View {
      content.chartYScale(domain: domain)
        .chartYAxis {
          AxisMarks(position: .leading) { value in
            AxisGridLine()
            AxisValueLabel {
              if let number = value.as(Double.self) {
                Text(ImportedChartPlot.axisLabel(number, style: style))
              }
            }
          }
        }
    }
  }
}

/// The label a chart shows beside the pointer.
struct ChartHoverBubble: View {
  let text: String

  var body: some View {
    Text(text)
      .font(.system(size: 11))
      .multilineTextAlignment(.leading)
      .padding(.horizontal, 7)
      .padding(.vertical, 4)
      .background(SparkStyle.chrome, in: RoundedRectangle(cornerRadius: 5))
      .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(SparkStyle.separator, lineWidth: 1))
      .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
      .fixedSize()
  }
}

/// Flipped so the card lines up with the grid's top-left coordinates.
final class ImportedChartHost: NSHostingView<ImportedChartCard> {
  required init(rootView: ImportedChartCard) {
    super.init(rootView: rootView)
    isFlipped = true
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    isFlipped = true
  }
}
