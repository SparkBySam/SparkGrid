import SparkGridCore
import SwiftUI

/// Insert Chart chooser: kind, category column, value mode / column, live preview.
/// A single-cell selection still opens this menu and waits for a real range.
struct InsertChartSheet: View {
  @Bindable var viewModel: SpreadsheetViewModel
  @Environment(\.dismiss) private var dismiss

  @State private var kind: SheetChart.Kind = .bar
  @State private var categoryColumn: Int = 0
  @State private var valueColumn: Int = 0
  /// More value columns, each its own series.
  @State private var extraValueColumns: [Int] = []
  /// Column of plus-or-minus amounts for error bars; nil for none.
  @State private var errorBarColumn: Int?
  /// A trendline through the first series; nil draws none.
  @State private var trendline: ChartTrendline?
  @State private var hasHeaderRow = true
  @State private var valueMode: SheetChart.ValueMode = .values
  @State private var didConfigure = false
  /// Stable id so live preview does not regenerate UUIDs every body pass (that caused a layout loop).
  @State private var draftID = UUID()
  @State private var columnOptions: [ChartPreviewSeries.ColumnOption] = []
  /// Set when Insert Chart opened with only the active cell selected.
  @State private var mustChooseRange = false
  @State private var rangeText = ""
  /// Explicit chart range. Stays nil until the selection or the range field covers more than one cell.
  @State private var dataRange: CellRange?
  /// On-sheet frame kept while editing so a type or range change does not move the chart.
  @State private var keptAnchor: KeptAnchor?
  @State private var titleText = ""
  @State private var titleEdited = false
  @State private var showsLegend = false
  @State private var showsGridlines = true
  @State private var categoryAxisTitle = ""
  @State private var valueAxisTitle = ""
  @State private var seriesColor: CodableColor?
  @State private var pointColors: [Int: CodableColor] = [:]
  @State private var frameIsCustom = false
  @FocusState private var rangeFieldFocused: Bool
  @State private var chartRequest = ""
  @State private var describing = false
  @State private var describeNote: String?

  private struct KeptAnchor {
    var row: Int
    var col: Int
    var rowSpan: Int
    var colSpan: Int
    var originXOffset: CGFloat
    var originYOffset: CGFloat
    var endXOffset: CGFloat
    var endYOffset: CGFloat
  }

  private var isEditing: Bool { viewModel.editingChartID != nil }

  private var draftChart: SheetChart? {
    guard let dataRange, !dataRange.isSingleCell else { return nil }
    let n = dataRange.normalized
    let anchorRow: Int
    let anchorCol: Int
    let rowSpan: Int
    let colSpan: Int
    if let keptAnchor {
      anchorRow = keptAnchor.row
      anchorCol = keptAnchor.col
      rowSpan = keptAnchor.rowSpan
      colSpan = keptAnchor.colSpan
    } else {
      anchorRow = min(viewModel.activeSheet.effectiveRowCount - 1, n.maxRow + 2)
      anchorCol = n.minCol
      rowSpan = 12
      colSpan = 8
    }
    return SheetChart(
      id: draftID,
      kind: kind,
      title: resolvedTitle,
      dataRange: dataRange,
      categoryColumn: categoryColumn,
      valueColumn: valueColumn,
      extraValueColumns: kind.allowsMoreSeries && valueMode == .values
        ? extraValueColumns.filter { $0 != valueColumn } : [],
      hasHeaderRow: hasHeaderRow,
      valueMode: valueMode,
      anchorRow: anchorRow,
      anchorCol: anchorCol,
      rowSpan: rowSpan,
      colSpan: colSpan,
      originXOffset: keptAnchor?.originXOffset ?? 0,
      originYOffset: keptAnchor?.originYOffset ?? 0,
      endXOffset: keptAnchor?.endXOffset ?? 0,
      endYOffset: keptAnchor?.endYOffset ?? 0,
      seriesColor: seriesColor,
      pointColors: pointColors,
      showsLegend: showsLegend,
      showsGridlines: showsGridlines,
      categoryAxisTitle: categoryAxisTitle,
      valueAxisTitle: valueAxisTitle,
      frameIsCustom: frameIsCustom,
      errorBarColumn: errorBarColumn.flatMap {
        $0 == valueColumn || extraValueColumns.contains($0) ? nil : $0
      },
      trendline: kind.allowsTrendline && valueMode == .values ? trendline : nil
    )
  }

  /// A new chart takes the series description until the title field is edited.
  /// An existing chart keeps the title it was saved with.
  private var resolvedTitle: String {
    if titleEdited { return titleText }
    return draftTitle
  }

  private var titleField: Binding<String> {
    Binding(
      get: { resolvedTitle },
      set: { newValue in
        titleEdited = true
        titleText = newValue
      }
    )
  }

  private var draftTitle: String {
    guard let dataRange, let chart = titleChart(for: dataRange) else { return "" }
    let cat = header(for: categoryColumn)
    let val = header(for: valueColumn)
    return ChartPreviewSeries.seriesDescription(
      for: chart,
      categoryHeader: cat,
      valueHeader: val
    )
  }

  private var canInsert: Bool {
    guard let chart = draftChart, !columnOptions.isEmpty else { return false }
    let series = ChartPreviewSeries.points(
      for: chart,
      labelFor: { viewModel.displayString(at: $0) },
      numberFor: { viewModel.displayValue(at: $0).asChartNumber }
    )
    return !series.points.isEmpty
  }

  var body: some View {
    SparkDialog(
      title: isEditing ? "Edit Chart" : "Insert Chart",
      subtitle: subtitle,
      primaryTitle: isEditing ? "Update Chart" : "Insert",
      primaryDisabled: !canInsert,
      onCancel: { dismiss() },
      onPrimary: {
        guard let chart = draftChart else { return }
        let saved = isEditing ? viewModel.updateChart(chart) : viewModel.insertChart(chart)
        guard saved else { return }
        dismiss()
      }
    ) {
      if AppSettings.shared.usesAppleIntelligence, FormulaHelper.availability == .available,
        dataRange != nil
      {
        describeRow
      }
      typeTiles
      HStack(alignment: .top, spacing: 12) {
        ScrollView {
          VStack(alignment: .leading, spacing: 12) {
            dataGroup
            if let chart = draftChart {
              SparkDialogSection(title: "Format")
              ChartFormatFields(
                title: titleField,
                showsLegend: $showsLegend,
                showsGridlines: $showsGridlines,
                categoryAxisTitle: $categoryAxisTitle,
                valueAxisTitle: $valueAxisTitle,
                seriesColor: ChartColorPaint.color(chart.resolvedSeriesColor),
                onSeriesColor: { seriesColor = ChartColorPaint.codable($0) },
                points: plottedPoints(for: chart),
                pointColor: { ChartColorPaint.color(chart.resolvedColor(forPoint: $0)) },
                isPointOverride: { pointColors[$0] != nil },
                onPointColor: { index, color in
                  pointColors[index] = ChartColorPaint.codable(color)
                },
                onClearPointColor: { pointColors[$0] = nil }
              )
              .padding(12)
              .background(RoundedRectangle(cornerRadius: 8).fill(SparkStyle.chrome))
              .overlay(RoundedRectangle(cornerRadius: 8).stroke(SparkStyle.separator, lineWidth: 1))
            }
          }
        }
        .frame(width: 300)
        .frame(maxHeight: 420)

        VStack(alignment: .leading, spacing: 6) {
          if let chart = draftChart {
            let title = chart.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty {
              Text(title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
            }
          }
          preview
            .frame(height: previewHeight)
            .clipped()
          if let chart = draftChart {
            Text(chart.placementDescription)
              .font(.system(size: 10))
              .foregroundStyle(SparkStyle.secondaryLabel)
          }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 8).fill(SparkStyle.chrome))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(SparkStyle.separator, lineWidth: 1))
      }
    }
    .frame(width: 720)
    .onAppear(perform: configureDefaultsIfNeeded)
    .onChange(of: rangeText) { _, _ in
      commitRangeText()
    }
  }

  private var subtitle: String {
    guard let dataRange else { return "Choose the cells to chart" }
    return "Data from \(dataRange.a1Description)"
  }

  private static func symbol(for kind: SheetChart.Kind) -> String {
    switch kind {
    case .bar: return "chart.bar.fill"
    case .line: return "chart.xyaxis.line"
    case .area: return "chart.line.uptrend.xyaxis"
    case .pie: return "chart.pie.fill"
    case .scatter: return "chart.dots.scatter"
    case .horizontalBar: return "align.horizontal.left.fill"
    case .stackedBar: return "square.split.1x2.fill"
    case .stackedHorizontalBar: return "square.split.2x1.fill"
    case .stackedArea: return "mountain.2.fill"
    case .doughnut: return "circle.circle"
    }
  }

  /// Describe the chart in words and Apple Intelligence fills in the choices below.
  private var describeRow: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 8) {
        Image(systemName: "sparkles").foregroundStyle(SparkStyle.accent)
        TextField(
          "Describe it, such as \u{201C}units by month as a line with a trend\u{201D}",
          text: $chartRequest
        )
        .textFieldStyle(.roundedBorder)
        .onSubmit(describe)
        if describing {
          ProgressView().controlSize(.small)
        }
        Button("Suggest", action: describe)
          .disabled(describing || chartRequest.trimmingCharacters(in: .whitespaces).isEmpty)
        SparkInfoButton(
          title: "Describe a chart",
          text: "Apple Intelligence on this Mac reads the column headers and your sentence, then "
            + "picks the chart kind, columns, trendline and title below. Nothing leaves the Mac. "
            + "Check the preview before inserting: the model can be wrong. Turn it off in "
            + "Settings › AI.")
      }
      if let describeNote {
        Text(describeNote)
          .font(.system(size: 11))
          .foregroundStyle(SparkStyle.secondaryLabel)
      }
    }
  }

  private func describe() {
    let text = chartRequest.trimmingCharacters(in: .whitespaces)
    guard !text.isEmpty, !describing else { return }
    let columns = columnOptions.map { option in
      ChartHelper.Column(
        index: option.column,
        letter: CellAddress(row: 0, col: option.column).a1.filter(\.isLetter),
        header: option.header, numeric: option.isMostlyNumeric)
    }
    describing = true
    describeNote = nil
    Task { @MainActor in
      defer { describing = false }
      do {
        let suggestion = try await ChartHelper.suggest(text, columns: columns)
        apply(suggestion)
      } catch {
        describeNote = "Couldn't suggest a chart: \(error.localizedDescription)"
      }
    }
  }

  private func apply(_ suggestion: ChartHelper.Suggestion) {
    var changed: [String] = []
    if let chosen = suggestion.kind {
      kind = chosen
      changed.append(chosen.title)
    }
    if let category = suggestion.categoryColumn {
      categoryColumn = category
    }
    let values = suggestion.valueColumns.filter { $0 != categoryColumn }
    if let first = values.first {
      valueColumn = first
      extraValueColumns = kind.isRound ? [] : Array(values.dropFirst())
      changed.append(values.map { header(for: $0) }.filter { !$0.isEmpty }.joined(separator: ", "))
    }
    if kind.allowsTrendline, let line = suggestion.trendline {
      trendline = ChartTrendline(kind: line)
      changed.append("\(line.title.lowercased()) trendline")
    } else if suggestion.trendline == nil {
      trendline = nil
    }
    if let title = suggestion.title {
      titleText = title
      titleEdited = true
    }
    describeNote =
      changed.isEmpty
      ? "No suggestion fit these columns. Try naming them."
      : "Suggested: " + changed.filter { !$0.isEmpty }.joined(separator: " · ")
        + ". Check the preview."
  }

  /// What each kind is for, behind its tile's "i".
  private static func purpose(of kind: SheetChart.Kind) -> String {
    switch kind {
    case .bar: return "Compares amounts across a few categories, side by side."
    case .line: return "Shows how values change over time or in order. Good with a trendline."
    case .area: return "A line chart filled below: change over time with a sense of size."
    case .pie: return "Parts of one whole. Best with a handful of slices."
    case .scatter: return "Two number columns against each other, to see a relationship."
    case .horizontalBar: return "Bars running across: easier to read with long category names."
    case .stackedBar: return "Each bar split into series, so totals and their parts both show."
    case .stackedHorizontalBar: return "Stacked bars running across, for long names."
    case .stackedArea: return "Series piled on each other over time: the total and its parts."
    case .doughnut: return "A pie with a hole in the middle; parts of one whole."
    }
  }

  private var typeTiles: some View {
    LazyVGrid(
      columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8
    ) {
      ForEach(SheetChart.Kind.allCases) { item in
        let selected = kind == item
        Button {
          kind = item
        } label: {
          VStack(spacing: 4) {
            Image(systemName: Self.symbol(for: item))
              .font(.system(size: 18))
            Text(item.title)
              .font(.system(size: 12, weight: selected ? .semibold : .regular))
              .lineLimit(1)
              .minimumScaleFactor(0.8)
          }
          .foregroundStyle(selected ? SparkStyle.label : SparkStyle.secondaryLabel)
          .frame(maxWidth: .infinity)
          .frame(height: 52)
          .background(
            RoundedRectangle(cornerRadius: 8)
              .fill(selected ? SparkStyle.accent.opacity(0.14) : SparkStyle.chrome)
          )
          .overlay(
            RoundedRectangle(cornerRadius: 8)
              .stroke(
                selected ? SparkStyle.accent : SparkStyle.separator, lineWidth: selected ? 2 : 1)
          )
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : AccessibilityTraits())
        .overlay(alignment: .topTrailing) {
          SparkInfoButton(title: item.title, text: Self.purpose(of: item), size: 11)
            .padding(4)
        }
      }
    }
  }

  private var dataGroup: some View {
    SparkDialogGroup {
      SparkDialogRow(label: "Data") {
        TextField("A1:D12", text: $rangeText)
          .textFieldStyle(.roundedBorder)
          .font(.system(size: 12, design: .monospaced))
          .frame(width: 96)
          .focused($rangeFieldFocused)
          .autocorrectionDisabled()
          .onSubmit(commitRangeText)
        Button("Use Selection") {
          if let selection = viewModel.chartSelectionRange {
            adopt(selection)
          }
        }
        .controlSize(.small)
        .disabled(viewModel.chartSelectionRange == nil)
      }
      if dataRange != nil {
        SparkDialogDivider()
        SparkDialogRow(label: "First row is headers") {
          Toggle("", isOn: $hasHeaderRow)
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
            .tint(SparkStyle.accent)
        }
        SparkDialogDivider()
        SparkDialogRow(label: kind == .scatter ? "X values" : "Labels") {
          Picker("Labels", selection: $categoryColumn) {
            ForEach(columnOptions) { option in
              Text(option.displayName).tag(option.column)
            }
          }
          .labelsHidden()
          .fixedSize()
        }
        SparkDialogDivider()
        SparkDialogRow(label: "Values") {
          Picker("Values", selection: $valueMode) {
            ForEach(SheetChart.ValueMode.allCases) { mode in
              Text(mode.title).tag(mode)
            }
          }
          .labelsHidden()
          .fixedSize()
        }
        if valueMode == .values {
          SparkDialogDivider()
          if kind.allowsMoreSeries {
            // One check per column, each a line or set of bars: what is ticked is what is drawn
            // (a Reddit note, Nov 19: "Value column" plus "More series" read as one line).
            SparkDialogRow(label: "Series") {
              seriesChecks
            }
            if kind == .bar || kind == .line {
              SparkDialogDivider()
              SparkDialogRow(label: "Error bars") {
                errorBarPicker
              }
            }
            if kind.allowsTrendline {
              trendlineRows
            }
          } else {
            SparkDialogRow(label: "Values") {
              Picker("Value column", selection: $valueColumn) {
                ForEach(columnOptions) { option in
                  Text(option.displayName).tag(option.column)
                }
              }
              .labelsHidden()
              .fixedSize()
            }
          }
        }
      }
    }
  }

  /// None, or a line fitted through the first series, with its equation and R² if wanted.
  @ViewBuilder
  private var trendlineRows: some View {
    SparkDialogDivider()
    SparkDialogRow(label: "Trendline") {
      SparkInfoButton(
        title: "Trendlines",
        text: "A line fitted through the points to show the trend. Linear is a straight line. "
          + "Exponential suits values that grow by a steady percentage; logarithmic, ones that "
          + "rise fast then level off; power, ones that grow in proportion to a power of x. A "
          + "moving average follows the average of the last few points. R² near 1 means a "
          + "close fit.")
      Picker(
        "Trendline",
        selection: Binding(
          get: { trendline?.kind },
          set: { newKind in
            if let newKind {
              var next = trendline ?? ChartTrendline()
              next.kind = newKind
              trendline = next
            } else {
              trendline = nil
            }
          })
      ) {
        Text("None").tag(ChartTrendline.Kind?.none)
        ForEach(ChartTrendline.Kind.allCases) { item in
          Text(item.title).tag(ChartTrendline.Kind?.some(item))
        }
      }
      .labelsHidden()
      .fixedSize()
      .help("A line fitted through the first series, as other spreadsheet apps draw one.")
    }
    if let line = trendline {
      SparkDialogDivider()
      if line.kind == .movingAverage {
        SparkDialogRow(label: "Period") {
          Stepper(
            "\(line.period) points",
            value: Binding(
              get: { line.period },
              set: { trendline?.period = max(2, $0) }),
            in: 2...50
          )
          .controlSize(.small)
          .font(.system(size: 12))
        }
      } else {
        SparkDialogRow(label: "Show") {
          HStack(spacing: 10) {
            Toggle(
              "Equation",
              isOn: Binding(
                get: { line.showsEquation }, set: { trendline?.showsEquation = $0 }))
            Toggle(
              "R²",
              isOn: Binding(
                get: { line.showsRSquared }, set: { trendline?.showsRSquared = $0 }))
          }
          .toggleStyle(.checkbox)
          .controlSize(.small)
        }
      }
    }
  }

  /// None, or a column holding each value's plus-or-minus amount (a standard error column,
  /// say). Drawn when the chart has one series.
  private var errorBarPicker: some View {
    let ticked = Set([valueColumn] + extraValueColumns)
    let choices = columnOptions.filter {
      $0.column != categoryColumn && !ticked.contains($0.column) && $0.isMostlyNumeric
    }
    return Picker("Error bars", selection: $errorBarColumn) {
      Text("None").tag(Int?.none)
      ForEach(choices) { option in
        Text("± \(option.displayName)").tag(Int?.some(option.column))
      }
    }
    .labelsHidden()
    .fixedSize()
    .disabled(choices.isEmpty || extraValueColumns.contains { $0 != valueColumn })
    .help(
      extraValueColumns.contains { $0 != valueColumn }
        ? "Error bars draw on a chart with one series."
        : "A column with each value's plus-or-minus amount, such as its standard error.")
  }

  /// Every column but the labels, each a check; the first ticked is the chart's first series.
  /// At least one stays ticked.
  private var seriesChecks: some View {
    let choices = columnOptions.filter { $0.column != categoryColumn }
    let ticked = [valueColumn] + extraValueColumns.filter { $0 != valueColumn }
    return VStack(alignment: .trailing, spacing: 3) {
      ForEach(choices) { option in
        Toggle(
          option.displayName,
          isOn: Binding(
            get: { ticked.contains(option.column) },
            set: { on in
              if on {
                if !ticked.contains(option.column) { extraValueColumns.append(option.column) }
              } else if option.column == valueColumn {
                guard let next = extraValueColumns.first(where: { $0 != valueColumn }) else {
                  return
                }
                valueColumn = next
                extraValueColumns.removeAll { $0 == next }
              } else {
                extraValueColumns.removeAll { $0 == option.column }
              }
            })
        )
        .toggleStyle(.checkbox)
        .disabled(ticked == [option.column])
      }
    }
  }

  @ViewBuilder
  private var preview: some View {
    if let chart = draftChart {
      SheetChartView(chart: chart, viewModel: viewModel)
    } else {
      Text(footerText)
        .font(.system(size: 12))
        .foregroundStyle(SparkStyle.secondaryLabel)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(8)
    }
  }

  private var footerText: String {
    if let dataRange {
      return
        "Range \(dataRange.a1Description). Pick a label column and either a numeric column or “Count of rows”."
    }
    if rangeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return "Type a range such as A1:D12, or select cells and click Use Selection."
    }
    return "Enter a range such as A1:D12."
  }

  private var previewHeight: CGFloat {
    guard let chart = draftChart else { return 200 }
    return OnSheetChartGeometry.previewHeight(
      colSpan: chart.colSpan,
      rowSpan: chart.rowSpan,
      width: 380,
      minHeight: 160,
      maxHeight: 220
    )
  }

  private func plottedPoints(for chart: SheetChart) -> [ChartPreviewSeries.Point] {
    ChartPreviewSeries.points(
      for: chart,
      labelFor: { viewModel.displayString(at: $0) },
      numberFor: { viewModel.displayValue(at: $0).asChartNumber }
    ).points
  }

  private func resetFormat() {
    titleText = ""
    titleEdited = false
    showsLegend = false
    showsGridlines = true
    categoryAxisTitle = ""
    valueAxisTitle = ""
    seriesColor = nil
    pointColors = [:]
    frameIsCustom = false
  }

  private func header(for column: Int) -> String {
    columnOptions.first(where: { $0.column == column })?.header ?? ""
  }

  private func titleChart(for range: CellRange) -> SheetChart? {
    guard !range.isSingleCell else { return nil }
    return SheetChart(
      id: draftID,
      kind: kind,
      dataRange: range,
      categoryColumn: categoryColumn,
      valueColumn: valueColumn,
      hasHeaderRow: hasHeaderRow,
      valueMode: valueMode,
      anchorRow: 0,
      anchorCol: 0
    )
  }

  private func configureDefaultsIfNeeded() {
    guard !didConfigure else { return }
    didConfigure = true
    if let existing = editingChart() {
      load(existing)
      return
    }
    kind = viewModel.pendingChartKind
    keptAnchor = nil
    resetFormat()
    if let selection = viewModel.chartSelectionRange {
      mustChooseRange = false
      adopt(selection)
    } else {
      mustChooseRange = true
      dataRange = nil
      rangeText = ""
      columnOptions = []
      rangeFieldFocused = true
    }
  }

  private func editingChart() -> SheetChart? {
    guard let id = viewModel.editingChartID else { return nil }
    return viewModel.activeSheet.charts.first { $0.id == id }
  }

  /// Fills the sheet from a chart already on the grid. The range field stays editable.
  private func load(_ chart: SheetChart) {
    draftID = chart.id
    kind = chart.kind
    extraValueColumns = chart.extraValueColumns
    errorBarColumn = chart.errorBarColumn
    trendline = chart.trendline
    keptAnchor = KeptAnchor(
      row: chart.anchorRow,
      col: chart.anchorCol,
      rowSpan: chart.rowSpan,
      colSpan: chart.colSpan,
      originXOffset: chart.originXOffset,
      originYOffset: chart.originYOffset,
      endXOffset: chart.endXOffset,
      endYOffset: chart.endYOffset
    )
    mustChooseRange = true
    let text = chart.dataRange.a1Description
    let parsed = ChartDataRangeParser.parse(text)
    dataRange = parsed
    rangeText = text
    titleEdited = true
    titleText = chart.title
    showsLegend = chart.showsLegend
    showsGridlines = chart.showsGridlines
    categoryAxisTitle = chart.categoryAxisTitle
    valueAxisTitle = chart.valueAxisTitle
    seriesColor = chart.seriesColor
    pointColors = chart.pointColors
    frameIsCustom = chart.frameIsCustom
    guard let parsed else {
      columnOptions = []
      return
    }
    columnOptions = ChartPreviewSeries.columnOptions(
      in: parsed,
      labelFor: { viewModel.displayString(at: $0) },
      numberFor: { viewModel.displayValue(at: $0).asChartNumber }
    )
    hasHeaderRow = chart.hasHeaderRow
    valueMode = chart.valueMode
    let suggestion = ChartPreviewSeries.suggest(
      in: parsed,
      labelFor: { viewModel.displayString(at: $0) },
      numberFor: { viewModel.displayValue(at: $0).asChartNumber }
    )
    let category = chart.categoryColumn ?? suggestion.categoryColumn
    let value = chart.valueColumn ?? suggestion.valueColumn
    if columnOptions.contains(where: { $0.column == category }) {
      categoryColumn = category
    } else {
      categoryColumn = suggestion.categoryColumn
    }
    if columnOptions.contains(where: { $0.column == value }) {
      valueColumn = value
    } else {
      valueColumn = suggestion.valueColumn
    }
  }

  private func commitRangeText() {
    let parsed = ChartDataRangeParser.parse(rangeText)
    guard parsed != dataRange else { return }
    if let parsed {
      adopt(parsed, keepSeries: dataRange != nil && !columnOptions.isEmpty)
    } else {
      dataRange = nil
      columnOptions = []
    }
  }

  private func adopt(_ range: CellRange, keepSeries: Bool = false) {
    guard !range.isSingleCell else {
      dataRange = nil
      columnOptions = []
      return
    }
    let previousCategory = categoryColumn
    let previousValue = valueColumn
    dataRange = range
    // The field always shows the range in use.
    if ChartDataRangeParser.parse(rangeText) != range {
      rangeText = range.a1Label
    }
    columnOptions = ChartPreviewSeries.columnOptions(
      in: range,
      labelFor: { viewModel.displayString(at: $0) },
      numberFor: { viewModel.displayValue(at: $0).asChartNumber }
    )
    let suggestion = ChartPreviewSeries.suggest(
      in: range,
      labelFor: { viewModel.displayString(at: $0) },
      numberFor: { viewModel.displayValue(at: $0).asChartNumber }
    )
    if keepSeries, columnOptions.contains(where: { $0.column == previousCategory }) {
      categoryColumn = previousCategory
    } else {
      categoryColumn = suggestion.categoryColumn
    }
    if keepSeries, columnOptions.contains(where: { $0.column == previousValue }) {
      valueColumn = previousValue
    } else {
      valueColumn = suggestion.valueColumn
    }
    if !keepSeries {
      hasHeaderRow = suggestion.hasHeaderRow
      valueMode = suggestion.valueMode
    }
  }
}

/// Closed multi-cell ranges for Insert Chart (`A1:D12`).
/// A blank field, a single cell, and an open row or column are not chart ranges.
enum ChartDataRangeParser {
  static func parse(_ text: String) -> CellRange? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !trimmed.contains("!") else { return nil }
    let compact = trimmed.replacingOccurrences(of: " ", with: "")
    guard let (start, end) = A1Reference.parseFormulaRange(compact),
      !start.isRowOpen, !start.isColOpen,
      !end.isRowOpen, !end.isColOpen
    else { return nil }
    let range = CellRange(start: start.address, end: end.address)
    guard !range.isSingleCell else { return nil }
    return range
  }
}

extension CellRange {
  var a1Description: String {
    let n = normalized
    let start = CellAddress(row: n.minRow, col: n.minCol).a1
    let end = CellAddress(row: n.maxRow, col: n.maxCol).a1
    return start == end ? start : "\(start):\(end)"
  }
}
