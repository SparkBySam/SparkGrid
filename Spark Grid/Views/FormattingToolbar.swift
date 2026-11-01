import AppKit
import SparkGridCore
import SwiftUI

struct FormattingToolbar: View {
  @Bindable var viewModel: SpreadsheetViewModel
  @Bindable var store: SpreadsheetDocumentStore
  @Bindable private var settings = AppSettings.shared
  let undoManager: UndoManager?

  @State private var textColor: Color = .primary
  @State private var fillColor: Color = .clear
  @State private var borderColor: Color = .primary
  @State private var fontSizeText = "12"
  @State private var showFillPopover = false
  @State private var showBorderPopover = false
  @State private var bandHasHeader = true
  @State private var bandColor = Color(nsColor: NSColor.systemBlue.withAlphaComponent(0.22))
  /// Prevents ColorPicker `onChange` from writing synced swatch values back onto the selection.
  @State private var suppressColorApply = false
  /// Bumped on each sync so delayed clear only applies to the latest suppress cycle.
  @State private var colorSyncGeneration = 0

  private var showLabels: Bool { settings.showToolbarLabels }
  private var toolbarHeight: CGFloat { SpreadsheetChrome.toolbarHeight(showLabels: showLabels) }
  private var dividerHeight: CGFloat { showLabels ? 36 : 30 }
  private var iconAreaHeight: CGFloat { 24 }

  var body: some View {
    HStack(spacing: 0) {
      ScrollView(.horizontal, showsIndicators: false) {
        toolbarContent
          .fixedSize(horizontal: true, vertical: false)
      }
      .frame(maxWidth: .infinity)

      AutosaveStatusView(store: store)
        .padding(.horizontal, 10)
    }
    .frame(maxWidth: .infinity)
    .frame(height: toolbarHeight)
    .background(toolbarBackground)
    .overlay(alignment: .bottom) { ChromeDivider() }
    .onChange(of: viewModel.selection) { _, _ in
      syncColorsFromSelection()
      syncFontSizeFromSelection()
    }
    .onAppear {
      syncColorsFromSelection()
      syncFontSizeFromSelection()
    }
  }

  private var toolbarContent: some View {
    HStack(spacing: 8) {
      historyGroup
      toolbarDivider
      numberGroup
      toolbarDivider
      fontGroup
      toolbarDivider
      styleGroup
      toolbarDivider
      colorGroup
      toolbarDivider
      mergeGroup
      toolbarDivider
      alignGroup
      toolbarDivider
      dataGroup
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 4)
    .foregroundStyle(SparkStyle.label)
  }

  private var toolbarBackground: Color {
    SparkStyle.chrome
  }

  // MARK: - Groups

  private var historyGroup: some View {
    HStack(spacing: 4) {
      ToolbarIconButton(
        systemName: "arrow.uturn.backward", title: "Undo", showLabel: showLabels, active: false
      ) {
        viewModel.undo()
      }
      .disabled(!(undoManager?.canUndo ?? false))

      ToolbarIconButton(
        systemName: "arrow.uturn.forward", title: "Redo", showLabel: showLabels, active: false
      ) {
        viewModel.redo()
      }
      .disabled(!(undoManager?.canRedo ?? false))
    }
  }

  private var numberGroup: some View {
    HStack(spacing: 4) {
      ToolbarIconButton(
        systemName: "dollarsign",
        title: "Currency",
        showLabel: showLabels,
        active: viewModel.selectedFormat.numberFormat == .currency
      ) {
        viewModel.setNumberFormat(.currency)
      }

      ToolbarIconButton(
        systemName: "percent",
        title: "Percent",
        showLabel: showLabels,
        active: viewModel.selectedFormat.numberFormat == .percent
      ) {
        viewModel.setNumberFormat(.percent)
      }

      ToolbarDecimalButton(decrease: true, title: "Decimals", showLabel: showLabels) {
        viewModel.decreaseDecimalPlaces()
      }

      ToolbarDecimalButton(decrease: false, title: "Decimals", showLabel: showLabels) {
        viewModel.increaseDecimalPlaces()
      }

      ToolbarMenuButton(title: "Format", showLabel: showLabels, width: showLabels ? 44 : 32) {
        Button("General") { viewModel.setNumberFormat(.general) }
        Button("Number") { viewModel.setNumberFormat(.number) }
        Button("Scientific") { viewModel.setNumberFormat(.scientific) }
        Divider()
        Button("Cell Format…") { CellFormatViewerPresenter.present(from: viewModel) }
      } label: {
        Text("123")
          .font(.system(size: 13, weight: .medium, design: .monospaced))
      }
    }
  }

  private var fontGroup: some View {
    HStack(spacing: 8) {
      Picker("Font", selection: fontFamilyBinding) {
        ForEach(CellFormatRenderer.fontFamilies, id: \.self) { family in
          Text(family).tag(family)
        }
      }
      .labelsHidden()
      .frame(width: 130)

      HStack(spacing: 4) {
        ToolbarIconButton(
          systemName: "minus", title: "Smaller", showLabel: showLabels, active: false
        ) {
          viewModel.adjustFontSize(by: -1)
          syncFontSizeFromSelection()
        }
        FontSizeTextField(text: $fontSizeText, onSubmit: applyFontSizeFromField)
          .frame(width: 32)
        ToolbarIconButton(systemName: "plus", title: "Larger", showLabel: showLabels, active: false)
        {
          viewModel.adjustFontSize(by: 1)
          syncFontSizeFromSelection()
        }
      }
    }
  }

  private var styleGroup: some View {
    HStack(spacing: 4) {
      ToolbarIconButton(
        systemName: "bold", title: "Bold", showLabel: showLabels,
        active: viewModel.selectedFormat.bold
      ) {
        viewModel.toggleBold()
      }

      ToolbarIconButton(
        systemName: "italic", title: "Italic", showLabel: showLabels,
        active: viewModel.selectedFormat.italic
      ) {
        viewModel.toggleItalic()
      }

      ToolbarIconButton(
        systemName: "strikethrough", title: "Strike", showLabel: showLabels,
        active: viewModel.selectedFormat.strikethrough
      ) {
        viewModel.toggleStrikethrough()
      }

      ToolbarIconButton(
        systemName: "underline", title: "Underline", showLabel: showLabels,
        active: viewModel.selectedFormat.underline
      ) {
        viewModel.toggleUnderline()
      }
    }
  }

  private var colorGroup: some View {
    HStack(spacing: 6) {
      // Text color: swatch alone opens the system ColorPicker (no redundant chevron).
      ToolbarColorSwatch(
        title: "Text",
        showLabel: showLabels,
        selection: $textColor,
        suppressColorApply: suppressColorApply,
        onColorChange: { color in
          if color == .clear {
            viewModel.setTextColor(nil)
          } else {
            viewModel.setTextColor(CellFormatRenderer.codableColor(from: NSColor(color)))
          }
        }
      ) {
        Text("A")
          .font(.system(size: 15, weight: .semibold))
          .underline(true, color: textColor)
      }

      ToolbarSwatchDisclosure(
        title: "Fill",
        showLabel: showLabels,
        selection: $fillColor,
        isPopoverPresented: $showFillPopover,
        suppressColorApply: suppressColorApply,
        onColorChange: applyFillColor,
        icon: {
          Image(systemName: "paintbrush.fill")
            .font(.system(size: 14))
            .foregroundStyle(fillColor == .clear ? Color(nsColor: .labelColor) : fillColor)
            .overlay(alignment: .bottom) {
              RoundedRectangle(cornerRadius: 1)
                .fill(fillColor == .clear ? Color(nsColor: .labelColor).opacity(0.25) : fillColor)
                .frame(height: 3)
                .padding(.horizontal, 1)
                .offset(y: 4)
            }
        },
        popoverContent: {
          FillToolbarPopoverContent(
            bandHasHeader: $bandHasHeader,
            bandColor: $bandColor,
            onNoFill: {
              beginColorApplySuppress()
              fillColor = .clear
              viewModel.setFillColor(nil)
              scheduleColorApplySuppressClear()
              showFillPopover = false
            },
            onApplyBands: {
              viewModel.applyAlternatingRowColors(
                bandColor: CellFormatRenderer.codableColor(from: NSColor(bandColor)),
                hasHeader: bandHasHeader
              )
              showFillPopover = false
            }
          )
        }
      )

      ToolbarSwatchDisclosure(
        title: "Borders",
        showLabel: showLabels,
        selection: $borderColor,
        isPopoverPresented: $showBorderPopover,
        suppressColorApply: suppressColorApply,
        chartOnLeading: false,
        onColorChange: { color in
          if color == .clear {
            viewModel.setBorderColor(nil)
          } else {
            viewModel.setBorderColor(CellFormatRenderer.codableColor(from: NSColor(color)))
          }
        },
        icon: {
          Image(systemName: "square.split.2x2")
            .font(.system(size: 13))
            .overlay(alignment: .bottom) {
              BorderStylePreview(style: viewModel.borderStyle, color: borderColor)
                .frame(height: 3)
                .padding(.horizontal, 2)
                .offset(y: 3)
            }
        },
        popoverContent: {
          BorderPopoverContent(
            viewModel: viewModel,
            borderColor: borderColor,
            onApplyPreset: { preset in
              viewModel.applyBorderPreset(preset)
              showBorderPopover = false
            }
          )
        }
      )
    }
  }

  private var mergeGroup: some View {
    HStack(spacing: 4) {
      Menu {
        Button("Merge All") { viewModel.mergeSelection(axis: .all) }
          .disabled(!viewModel.canMergeSelection)
        Button("Merge Across") { viewModel.mergeSelection(axis: .horizontal) }
          .disabled(!viewModel.canMergeHorizontally)
        Button("Merge Vertically") { viewModel.mergeSelection(axis: .vertical) }
          .disabled(!viewModel.canMergeVertically)
        Divider()
        Button("Unmerge") { viewModel.unmergeSelection() }
          .disabled(!viewModel.canUnmergeSelection)
      } label: {
        VStack(spacing: 2) {
          Image(systemName: "rectangle.split.2x1")
            .font(.system(size: 13))
            .frame(width: showLabels ? 48 : 32, height: showLabels ? 24 : 32)
          if showLabels {
            Text("Merge")
              .font(.system(size: 9))
              .lineLimit(1)
          }
        }
        .frame(minWidth: 40)
        .contentShape(Rectangle())
      }
      .menuStyle(.borderlessButton)
      .help("Merge cells")
    }
  }

  private var alignGroup: some View {
    HStack(spacing: 4) {
      ToolbarMenuButton(title: "Align", showLabel: showLabels, width: 32) {
        Button {
          viewModel.setHorizontalAlign(.left)
        } label: {
          Label("Align left", systemImage: "text.alignleft")
        }
        Button {
          viewModel.setHorizontalAlign(.center)
        } label: {
          Label("Align center", systemImage: "text.aligncenter")
        }
        Button {
          viewModel.setHorizontalAlign(.right)
        } label: {
          Label("Align right", systemImage: "text.alignright")
        }
      } label: {
        Image(systemName: horizontalAlignIcon)
          .font(.system(size: 13))
      }

      ToolbarMenuButton(title: "Vertical", showLabel: showLabels, width: 32) {
        Button {
          viewModel.setVerticalAlign(.top)
        } label: {
          Label("Align top", systemImage: "arrow.up.to.line")
        }
        Button {
          viewModel.setVerticalAlign(.middle)
        } label: {
          Label("Align middle", systemImage: "arrow.up.and.down")
        }
        Button {
          viewModel.setVerticalAlign(.bottom)
        } label: {
          Label("Align bottom", systemImage: "arrow.down.to.line")
        }
      } label: {
        Image(systemName: "arrow.up.and.down.text.horizontal")
          .font(.system(size: 13))
      }

      TextDisplayToolbarMenu(viewModel: viewModel)

      RotateToolbarMenu(
        viewModel: viewModel,
        showLabel: showLabels,
        iconHeight: iconAreaHeight
      )
    }
  }

  /// Filter turns the table around the selection into a filter, and turns it off again.
  private var dataGroup: some View {
    ToolbarIconButton(
      systemName: "line.3.horizontal.decrease",
      title: "Filter",
      showLabel: showLabels,
      active: viewModel.filterState != nil
    ) {
      if viewModel.filterState == nil {
        viewModel.createFilter()
      } else {
        viewModel.clearFilter()
      }
    }
  }

  private var toolbarDivider: some View {
    Rectangle()
      .fill(SpreadsheetChrome.chromeDividerColor)
      .frame(width: SpreadsheetChrome.dividerHeight, height: dividerHeight)
  }

  private var fontFamilyBinding: Binding<String> {
    Binding(
      get: { viewModel.selectedFormat.fontFamily ?? CellFormatRenderer.defaultFontFamily },
      set: { viewModel.setFontFamily($0) }
    )
  }

  private var horizontalAlignIcon: String {
    switch viewModel.selectedFormat.horizontalAlign {
    case .center: return "text.aligncenter"
    case .right: return "text.alignright"
    default: return "text.alignleft"
    }
  }

  private func syncColorsFromSelection() {
    beginColorApplySuppress()
    let format = viewModel.selectedFormat
    if let text = format.textColor, let ns = CellFormatRenderer.nsColor(text) {
      textColor = Color(nsColor: ns)
    } else {
      textColor = Color(nsColor: .labelColor)
    }
    if let fill = format.fillColor, let ns = CellFormatRenderer.nsColor(fill) {
      fillColor = Color(nsColor: ns)
    } else {
      fillColor = .clear
    }
    if let border = viewModel.borderColor, let ns = CellFormatRenderer.nsColor(border) {
      borderColor = Color(nsColor: ns)
    } else if let edgeColor = format.borders.top?.color
      ?? format.borders.bottom?.color
      ?? format.borders.left?.color
      ?? format.borders.right?.color,
      let ns = CellFormatRenderer.nsColor(edgeColor)
    {
      borderColor = Color(nsColor: ns)
    } else {
      borderColor = Color(nsColor: .labelColor)
    }
    // ColorPicker can fire after the binding update; clear only after a short delay,
    // and only if no newer sync started.
    scheduleColorApplySuppressClear()
  }

  private func beginColorApplySuppress() {
    colorSyncGeneration &+= 1
    suppressColorApply = true
  }

  private func scheduleColorApplySuppressClear() {
    let generation = colorSyncGeneration
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
      guard colorSyncGeneration == generation else { return }
      suppressColorApply = false
    }
  }

  private func syncFontSizeFromSelection() {
    let size = Int(viewModel.selectedFormat.fontSize ?? CellFormatRenderer.defaultFontSize)
    fontSizeText = "\(size)"
  }

  private func applyFillColor(_ color: Color) {
    guard !suppressColorApply else { return }
    if color == .clear {
      viewModel.setFillColor(nil)
    } else {
      viewModel.setFillColor(CellFormatRenderer.codableColor(from: NSColor(color)))
    }
  }

  private func applyFontSizeFromField() {
    guard let size = Double(fontSizeText) else {
      syncFontSizeFromSelection()
      return
    }
    viewModel.setFontSize(CGFloat(size))
    syncFontSizeFromSelection()
  }
}

/// Font size field that can be typed into, but won't steal focus on app launch.
private struct FontSizeTextField: NSViewRepresentable {
  @Binding var text: String
  var onSubmit: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(text: $text, onSubmit: onSubmit)
  }

  func makeNSView(context: Context) -> ClickToFocusTextField {
    let field = ClickToFocusTextField(string: text)
    field.delegate = context.coordinator
    field.isBordered = false
    field.isBezeled = false
    field.drawsBackground = false
    field.focusRingType = .default
    field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
    field.alignment = .center
    return field
  }

  func updateNSView(_ field: ClickToFocusTextField, context: Context) {
    context.coordinator.onSubmit = onSubmit
    if field.stringValue != text {
      field.stringValue = text
    }
    field.delegate = context.coordinator
  }

  final class Coordinator: NSObject, NSTextFieldDelegate {
    @Binding var text: String
    var onSubmit: () -> Void

    init(text: Binding<String>, onSubmit: @escaping () -> Void) {
      _text = text
      self.onSubmit = onSubmit
    }

    func controlTextDidChange(_ notification: Notification) {
      guard let field = notification.object as? NSTextField else { return }
      let filtered = field.stringValue.filter(\.isNumber)
      if filtered != field.stringValue {
        field.stringValue = filtered
      }
      text = filtered
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector)
      -> Bool
    {
      if commandSelector == #selector(NSResponder.insertNewline(_:)) {
        onSubmit()
        control.window?.makeFirstResponder(nil)
        return true
      }
      return false
    }
  }
}

private final class ClickToFocusTextField: NSTextField {
  private var allowsKeyboardFocus = false

  override var acceptsFirstResponder: Bool {
    allowsKeyboardFocus
  }

  override func mouseDown(with event: NSEvent) {
    allowsKeyboardFocus = true
    window?.makeFirstResponder(self)
    super.mouseDown(with: event)
  }
}

// MARK: - Toolbar controls

/// Text color: icon opens the color chart; custom color is secondary.
private struct ToolbarColorSwatch<Icon: View>: View {
  let title: String
  var showLabel = false
  @Binding var selection: Color
  var suppressColorApply = false
  let onColorChange: (Color) -> Void
  @ViewBuilder var icon: () -> Icon

  private var controlHeight: CGFloat { showLabel ? 24 : 32 }
  private let swatchWidth: CGFloat = 30

  var body: some View {
    VStack(spacing: 2) {
      ToolbarColorChartButton(
        selection: $selection,
        suppressColorApply: suppressColorApply,
        onColorChange: onColorChange,
        width: swatchWidth,
        height: controlHeight
      ) {
        icon()
      }
      .overlay(
        RoundedRectangle(cornerRadius: 5)
          .strokeBorder(SpreadsheetChrome.chromeBorderColor, lineWidth: 0.5)
      )

      if showLabel {
        Text(title)
          .font(.system(size: 9))
          .lineLimit(1)
          .minimumScaleFactor(0.8)
      }
    }
    .frame(minWidth: 40)
    .help(title)
    .accessibilityLabel(title)
  }
}

/// Fill / Borders: split control — chart + disclosure (layout flips for Borders).
private struct ToolbarSwatchDisclosure<Icon: View, PopoverContent: View>: View {
  let title: String
  var showLabel = false
  @Binding var selection: Color
  @Binding var isPopoverPresented: Bool
  var suppressColorApply = false
  /// Fill: icon = chart, chevron = extras. Borders: icon = extras, chevron = chart.
  var chartOnLeading = true
  let onColorChange: (Color) -> Void
  @ViewBuilder var icon: () -> Icon
  @ViewBuilder var popoverContent: () -> PopoverContent

  private var controlHeight: CGFloat { showLabel ? 24 : 32 }
  private let swatchWidth: CGFloat = 30
  private let chevronWidth: CGFloat = 14

  var body: some View {
    VStack(spacing: 2) {
      HStack(spacing: 0) {
        if chartOnLeading {
          chartSegment
          segmentDivider
          optionsSegment
        } else {
          optionsSegment
          segmentDivider
          chartSegment
        }
      }
      .frame(width: swatchWidth + 1 + chevronWidth, height: controlHeight)
      .overlay(
        RoundedRectangle(cornerRadius: 5)
          .strokeBorder(SpreadsheetChrome.chromeBorderColor, lineWidth: 0.5)
      )
      .clipShape(RoundedRectangle(cornerRadius: 5))
      .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
        popoverContent()
          .padding(12)
          .frame(minWidth: 220)
      }

      if showLabel {
        Text(title)
          .font(.system(size: 9))
          .lineLimit(1)
          .minimumScaleFactor(0.8)
      }
    }
    .frame(minWidth: 48)
    .help(title)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(title)
  }

  private var chartSegment: some View {
    Group {
      if chartOnLeading {
        ToolbarColorChartButton(
          selection: $selection,
          suppressColorApply: suppressColorApply,
          onColorChange: onColorChange,
          width: swatchWidth,
          height: controlHeight
        ) {
          icon()
        }
      } else {
        ToolbarColorChartButton(
          selection: $selection,
          suppressColorApply: suppressColorApply,
          onColorChange: onColorChange,
          width: chevronWidth,
          height: controlHeight,
          showsChevronLabel: true
        ) {
          EmptyView()
        }
      }
    }
  }

  private var optionsSegment: some View {
    Group {
      if chartOnLeading {
        Button {
          isPopoverPresented.toggle()
        } label: {
          Image(systemName: "chevron.down")
            .font(.system(size: 7, weight: .bold))
            .foregroundStyle(.secondary)
            .frame(width: chevronWidth, height: controlHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(title) options")
      } else {
        Button {
          isPopoverPresented.toggle()
        } label: {
          icon()
            .frame(width: swatchWidth, height: controlHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(title) styles")
      }
    }
  }

  private var segmentDivider: some View {
    Rectangle()
      .fill(SpreadsheetChrome.chromeBorderColor)
      .frame(width: 1, height: controlHeight - 8)
  }
}

private struct ToolbarColorChartButton<Label: View>: View {
  @Binding var selection: Color
  var suppressColorApply = false
  let onColorChange: (Color) -> Void
  var width: CGFloat
  var height: CGFloat
  var showsChevronLabel = false
  @ViewBuilder var label: () -> Label
  @State private var showChart = false

  var body: some View {
    Button {
      showChart = true
    } label: {
      Group {
        if showsChevronLabel {
          Image(systemName: "chevron.down")
            .font(.system(size: 7, weight: .bold))
            .foregroundStyle(.secondary)
        } else {
          label()
        }
      }
      .frame(width: width, height: height)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(suppressColorApply)
    .help(showsChevronLabel ? "Border color" : "Color")
    .popover(isPresented: $showChart, arrowEdge: .bottom) {
      ToolbarColorChartPopover(
        selection: $selection,
        onPick: { color in
          showChart = false
          if color == .clear {
            selection = .clear
          } else {
            selection = color
          }
          guard !suppressColorApply else { return }
          onColorChange(color)
        },
        onCustomColor: {
          showChart = false
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            ToolbarColorPanel.present(color: NSColor(selection)) { newColor in
              selection = Color(nsColor: newColor)
              guard !suppressColorApply else { return }
              onColorChange(Color(nsColor: newColor))
            }
          }
        }
      )
    }
  }
}

private struct ToolbarColorChartPopover: View {
  @Binding var selection: Color
  let onPick: (Color) -> Void
  let onCustomColor: () -> Void

  private let columns = Array(repeating: GridItem(.fixed(22), spacing: 5), count: 10)

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      LazyVGrid(columns: columns, spacing: 5) {
        Button {
          onPick(.clear)
        } label: {
          ToolbarNoColorSwatch()
        }
        .buttonStyle(.plain)
        .help("No color")

        ForEach(Array(ToolbarColorChart.swatches.enumerated()), id: \.offset) { _, swatch in
          Button {
            onPick(swatch)
          } label: {
            RoundedRectangle(cornerRadius: 3)
              .fill(swatch)
              .frame(width: 22, height: 22)
              .overlay {
                RoundedRectangle(cornerRadius: 3)
                  .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5)
              }
          }
          .buttonStyle(.plain)
        }
      }

      Button("Pick Custom Color…", action: onCustomColor)
        .buttonStyle(.link)
        .font(.caption)
        .frame(width: ToolbarColorChart.gridWidth, alignment: .center)
    }
    .padding(12)
    .frame(width: ToolbarColorChart.gridWidth + 24)
  }
}

private struct ToolbarNoColorSwatch: View {
  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 3)
        .fill(SparkStyle.canvas)
      RoundedRectangle(cornerRadius: 3)
        .strokeBorder(Color.primary.opacity(0.20), lineWidth: 0.5)
      GeometryReader { geo in
        Path { path in
          path.move(to: CGPoint(x: 3, y: geo.size.height - 3))
          path.addLine(to: CGPoint(x: geo.size.width - 3, y: 3))
        }
        .stroke(Color.red.opacity(0.85), lineWidth: 1.5)
      }
    }
    .frame(width: 22, height: 22)
  }
}

/// 7×10 grid: row 1 = no-color + 9 grays, rows 2–7 = spectrum.
private enum ToolbarColorChart {
  static let graySwatches: [Color] = [
    .white,
    Color(white: 0.9),
    Color(white: 0.8),
    Color(white: 0.7),
    Color(white: 0.6),
    Color(white: 0.5),
    Color(white: 0.4),
    Color(white: 0.28),
    .black,
  ]

  static let spectrum: [Color] = {
    let hues: [CGFloat] = [0, 0.04, 0.08, 0.15, 0.33, 0.55, 0.58, 0.66, 0.75, 0.83]
    let levels: [CGFloat] = [0.94, 0.80, 0.66, 0.52, 0.38, 0.26]
    var colors: [Color] = []
    colors.reserveCapacity(60)
    for level in levels {
      for hue in hues {
        colors.append(Color(hue: hue, saturation: 0.68, brightness: level))
      }
    }
    return colors
  }()

  static var swatches: [Color] {
    graySwatches + spectrum
  }

  static let gridWidth: CGFloat = CGFloat(10) * 22 + CGFloat(9) * 5
}

/// Full color panel for custom picks from the chart popover.
@MainActor
private enum ToolbarColorPanel {
  private static let coordinator = Coordinator()
  private static var onChange: ((NSColor) -> Void)?

  static func present(color: NSColor, onChange: @escaping (NSColor) -> Void) {
    self.onChange = onChange
    let panel = NSColorPanel.shared
    panel.setTarget(coordinator)
    panel.setAction(#selector(Coordinator.changed(_:)))
    panel.isContinuous = true
    panel.color = color
    panel.orderFront(nil)
  }

  private final class Coordinator: NSObject {
    @objc func changed(_ sender: Any?) {
      ToolbarColorPanel.onChange?(NSColorPanel.shared.color)
    }
  }
}

private struct FillToolbarPopoverContent: View {
  @Binding var bandHasHeader: Bool
  @Binding var bandColor: Color
  var onNoFill: () -> Void
  var onApplyBands: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Button("No Fill", action: onNoFill)
        .buttonStyle(.bordered)

      Divider()

      Text("Alternating Row Colors")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)

      Toggle("First row is header", isOn: $bandHasHeader)

      HStack(spacing: 8) {
        Text("Band color")
          .font(.caption)
        ColorPicker("", selection: $bandColor, supportsOpacity: false)
          .labelsHidden()
      }

      HStack(spacing: 8) {
        bandPresetButton("Blue", color: Color(nsColor: .systemBlue).opacity(0.22))
        bandPresetButton("Gray", color: Color(nsColor: .systemGray).opacity(0.22))
        bandPresetButton("Green", color: Color(nsColor: .systemGreen).opacity(0.22))
      }

      Button("Apply to Selection", action: onApplyBands)
        .buttonStyle(.borderedProminent)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
  }

  private func bandPresetButton(_ title: String, color: Color) -> some View {
    Button(title) { bandColor = color }
      .buttonStyle(.bordered)
      .font(.caption)
  }
}

private struct BorderPopoverContent: View {
  @Bindable var viewModel: SpreadsheetViewModel
  var borderColor: Color
  var onApplyPreset: (BorderPreset) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Line Style")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)

      VStack(spacing: 2) {
        ForEach(BorderStyle.allCases, id: \.self) { style in
          Button {
            viewModel.setBorderStyle(style)
          } label: {
            HStack(spacing: 8) {
              BorderStylePreview(style: style, color: borderColor)
                .frame(width: 56, height: 12)
              Text(style.title)
                .foregroundStyle(SparkStyle.label)
              Spacer(minLength: 0)
              if viewModel.borderStyle == style {
                Image(systemName: "checkmark")
                  .foregroundStyle(SparkStyle.accent)
              }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(
              viewModel.borderStyle == style
                ? SparkStyle.accent.opacity(0.12)
                : Color.clear,
              in: RoundedRectangle(cornerRadius: 4)
            )
          }
          .buttonStyle(.plain)
        }
      }

      Divider()

      Text("Borders")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)

      VStack(spacing: 2) {
        ForEach(BorderPreset.allCases, id: \.self) { preset in
          Button {
            onApplyPreset(preset)
          } label: {
            Label(preset.title, systemImage: preset.systemImage)
              .frame(maxWidth: .infinity, alignment: .leading)
              .contentShape(Rectangle())
              .padding(.horizontal, 6)
              .padding(.vertical, 5)
          }
          .buttonStyle(.plain)
        }
      }
    }
  }
}

private struct BorderStylePreview: View {
  var style: BorderStyle
  var color: Color

  var body: some View {
    Canvas { context, size in
      let stroke = color == .clear ? Color(nsColor: .labelColor) : color
      let y = size.height / 2
      var path = Path()

      switch style {
      case .thin, .medium, .thick:
        path.move(to: CGPoint(x: 0, y: y))
        path.addLine(to: CGPoint(x: size.width, y: y))
        context.stroke(
          path,
          with: .color(stroke),
          style: StrokeStyle(lineWidth: style == .thin ? 1 : (style == .medium ? 1.5 : 2.5))
        )
      case .dashed:
        path.move(to: CGPoint(x: 0, y: y))
        path.addLine(to: CGPoint(x: size.width, y: y))
        context.stroke(
          path,
          with: .color(stroke),
          style: StrokeStyle(lineWidth: 1.2, dash: [4, 2])
        )
      case .dotted:
        path.move(to: CGPoint(x: 0, y: y))
        path.addLine(to: CGPoint(x: size.width, y: y))
        context.stroke(
          path,
          with: .color(stroke),
          style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [0.5, 2.5])
        )
      case .double:
        var top = Path()
        top.move(to: CGPoint(x: 0, y: y - 1.5))
        top.addLine(to: CGPoint(x: size.width, y: y - 1.5))
        var bottom = Path()
        bottom.move(to: CGPoint(x: 0, y: y + 1.5))
        bottom.addLine(to: CGPoint(x: size.width, y: y + 1.5))
        context.stroke(top, with: .color(stroke), lineWidth: 1)
        context.stroke(bottom, with: .color(stroke), lineWidth: 1)
      }
    }
  }
}

private struct TextDisplayToolbarMenu: View {
  @Bindable var viewModel: SpreadsheetViewModel

  /// Nil when the selection mixes modes, so the menu does not check one of them.
  private var uniform: CellFormat.TextDisplay? { viewModel.uniformTextDisplay }
  private var title: String { viewModel.textDisplayToolbarTitle }
  private var isActive: Bool { uniform == .wrap || uniform == .clip }

  var body: some View {
    ToolbarMenuButton(title: title, showLabel: true, width: 32, titleWidth: 64) {
      textItem(.overflow)
      textItem(.wrap)
      textItem(.clip)
    } label: {
      Image(systemName: "text.word.spacing")
        .font(.system(size: 13, weight: isActive ? .semibold : .regular))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
          isActive ? SparkStyle.accent.opacity(0.22) : Color.clear,
          in: RoundedRectangle(cornerRadius: 4)
        )
    }
    .help("Overflow, wrap, or clip text")
    .accessibilityLabel(title)
  }

  @ViewBuilder
  private func textItem(_ display: CellFormat.TextDisplay) -> some View {
    Button {
      viewModel.setTextDisplay(display)
    } label: {
      if uniform == display {
        Label(display.toolbarTitle, systemImage: "checkmark")
      } else {
        Text(display.toolbarTitle)
      }
    }
  }
}

private struct RotateToolbarMenu: View {
  @Bindable var viewModel: SpreadsheetViewModel
  var showLabel: Bool
  var iconHeight: CGFloat

  private var isActive: Bool { viewModel.selectedFormat.textRotation != 0 }

  var body: some View {
    ToolbarMenuButton(title: "Rotate", showLabel: showLabel, width: 32) {
      Button("None") { viewModel.setTextRotation(0) }
      Divider()
      Button("Tilt up") { viewModel.setTextRotation(-45) }
      Button("Tilt down") { viewModel.setTextRotation(45) }
      Button("Stack vertically") { viewModel.setTextRotation(CellFormat.stackedTextRotation) }
      Button("Rotate up") { viewModel.setTextRotation(-90) }
      Button("Rotate down") { viewModel.setTextRotation(90) }
    } label: {
      Image(systemName: "arrow.trianglehead.counterclockwise.rotate.90")
        .font(.system(size: 13, weight: isActive ? .semibold : .regular))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
          isActive ? SparkStyle.accent.opacity(0.22) : Color.clear,
          in: RoundedRectangle(cornerRadius: 4)
        )
    }
  }
}

private struct ToolbarDecimalButton: View {
  let decrease: Bool
  let title: String
  var showLabel = false
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 2) {
        HStack(spacing: 1) {
          if decrease {
            Image(systemName: "chevron.left")
              .font(.system(size: 7, weight: .bold))
          }
          Text(".0")
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
          if !decrease {
            Image(systemName: "chevron.right")
              .font(.system(size: 7, weight: .bold))
          }
        }
        .frame(width: 32, height: showLabel ? 24 : 32)

        if showLabel {
          Text(title)
            .font(.system(size: 9))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
      }
      .frame(minWidth: 40)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(decrease ? "Decrease decimals" : "Increase decimals")
  }
}

private struct ToolbarIconButton: View {
  let systemName: String
  let title: String
  var showLabel = false
  var active = false
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 2) {
        Image(systemName: systemName)
          .font(.system(size: 13, weight: active ? .semibold : .regular))
          .frame(width: 32, height: showLabel ? 24 : 32)
          .background(
            active ? SparkStyle.accent.opacity(0.22) : Color.clear,
            in: RoundedRectangle(cornerRadius: 4))

        if showLabel {
          Text(title)
            .font(.system(size: 9))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
      }
      .frame(minWidth: 40)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(title)
  }
}

private struct ToolbarMenuButton<Label: View, MenuContent: View>: View {
  let title: String
  var showLabel = false
  var width: CGFloat = 32
  /// Wider than the icon when the caption is a word like "Overflow".
  var titleWidth: CGFloat? = nil
  @ViewBuilder var menuContent: () -> MenuContent
  @ViewBuilder var label: () -> Label

  var body: some View {
    Menu {
      menuContent()
    } label: {
      VStack(spacing: 2) {
        label()
          .frame(width: width, height: showLabel ? 24 : 32)

        if showLabel {
          Text(title)
            .font(.system(size: 9))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: titleWidth ?? max(width, 40))
        }
      }
      .frame(minWidth: 40)
      .contentShape(Rectangle())
    }
    .menuStyle(.borderlessButton)
    .buttonStyle(.plain)
    .fixedSize(horizontal: true, vertical: false)
    .help(title)
  }
}
