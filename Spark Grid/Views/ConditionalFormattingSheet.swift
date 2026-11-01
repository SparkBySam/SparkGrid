import AppKit
import SparkGridCore
import SwiftUI

struct ConditionalFormattingSheet: View {
  @Bindable var viewModel: SpreadsheetViewModel
  let onDismiss: () -> Void

  @State private var ruleType: RuleType = .highlightCells
  @State private var editingRuleID: UUID?

  // Highlight Cells
  @State private var highlightKind: HighlightKind = .greaterThan
  @State private var valueText = "100"
  @State private var value2Text = "200"

  // Format (highlight / formula)
  @State private var fillColor = Color(
    nsColor: NSColor(calibratedRed: 0.96, green: 0.78, blue: 0.78, alpha: 1))
  @State private var textColor = Color(nsColor: .labelColor)
  @State private var useCustomTextColor = false
  @State private var formatBold = false
  @State private var formatItalic = false
  /// Bold value loaded with the rule being edited. Nil while creating a rule.
  @State private var loadedBold: Bool?
  /// Italic value loaded with the rule. Kept when it is an explicit false.
  @State private var loadedItalic: Bool?
  /// True after the user clicks Bold, so check-then-uncheck is stored as off.
  @State private var boldTouched = false

  // Formula
  @State private var formulaText = "=A1>100"

  // Color scale
  @State private var scaleMinColor = Color(
    nsColor: NSColor(calibratedRed: 0.99, green: 0.72, blue: 0.72, alpha: 1))
  @State private var scaleMidColor = Color(
    nsColor: NSColor(calibratedRed: 1.0, green: 0.95, blue: 0.7, alpha: 1))
  @State private var scaleMaxColor = Color(
    nsColor: NSColor(calibratedRed: 0.72, green: 0.9, blue: 0.72, alpha: 1))
  @State private var useMidStop = true

  // Data Bars
  @State private var dataBarColor = Color(
    nsColor: NSColor(calibratedRed: 0.39, green: 0.58, blue: 0.93, alpha: 1))
  @State private var dataBarShowValue = true

  // Icon Sets
  @State private var iconSetStyle: IconSetStyle = .threeTrafficLights

  enum RuleType: String, CaseIterable, Identifiable {
    case highlightCells = "Highlight Cells"
    case formula = "Formula"
    case colorScale = "Color Scale"
    case dataBars = "Data Bars"
    case iconSets = "Icon Sets"
    var id: String { rawValue }
  }

  enum HighlightKind: String, CaseIterable, Identifiable {
    case greaterThan = "Greater than"
    case lessThan = "Less than"
    case greaterOrEqual = "Greater or equal"
    case lessOrEqual = "Less or equal"
    case equal = "Equal to"
    case notEqual = "Not equal to"
    case between = "Between"
    case notBetween = "Not between"
    case textContains = "Text contains"
    case blanks = "Blanks"
    case nonBlanks = "Non-blanks"
    var id: String { rawValue }

    var needsValue: Bool {
      switch self {
      case .blanks, .nonBlanks: return false
      default: return true
      }
    }

    var needsSecondValue: Bool {
      self == .between || self == .notBetween
    }

    var valueLabel: String {
      switch self {
      case .textContains: return "Text"
      case .between, .notBetween: return "Minimum"
      default: return "Value"
      }
    }
  }

  private static let fillPresets: [(String, Color)] = [
    ("Red", Color(nsColor: NSColor(calibratedRed: 0.96, green: 0.78, blue: 0.78, alpha: 1))),
    ("Yellow", Color(nsColor: NSColor(calibratedRed: 1.0, green: 0.95, blue: 0.7, alpha: 1))),
    ("Green", Color(nsColor: NSColor(calibratedRed: 0.78, green: 0.94, blue: 0.78, alpha: 1))),
    ("Blue", Color(nsColor: NSColor(calibratedRed: 0.78, green: 0.88, blue: 0.98, alpha: 1))),
    ("Orange", Color(nsColor: NSColor(calibratedRed: 1.0, green: 0.88, blue: 0.72, alpha: 1))),
    ("Purple", Color(nsColor: NSColor(calibratedRed: 0.9, green: 0.82, blue: 0.96, alpha: 1))),
    ("Gray", Color(nsColor: NSColor(calibratedRed: 0.88, green: 0.88, blue: 0.9, alpha: 1))),
  ]

  private var selectionRangeLabel: String {
    let ranges =
      viewModel.selectionRanges.isEmpty
      ? [viewModel.selectionRange]
      : viewModel.selectionRanges
    return ranges.map(Self.rangeLabel).joined(separator: ", ")
  }

  private var rules: [ConditionalFormatRule] {
    viewModel.activeSheet.conditionalFormats
  }

  private var canApply: Bool {
    switch ruleType {
    case .highlightCells:
      return buildHighlightPredicate() != nil
    case .formula:
      return !normalizedFormula().isEmpty
    case .colorScale, .dataBars, .iconSets:
      return true
    }
  }

  private var applyButtonTitle: String {
    editingRuleID == nil ? "Apply Rule" : "Update Rule"
  }

  var body: some View {
    SparkDialog(
      title: "Conditional Formatting",
      subtitle: subtitle,
      primaryTitle: applyButtonTitle,
      primaryDisabled: !canApply,
      cancelTitle: "Done",
      onCancel: onDismiss,
      onPrimary: applyNewRule,
      leading: {
        if let editingRuleID {
          Button("Delete Rule", role: .destructive) {
            viewModel.removeConditionalFormatRules(ids: [editingRuleID])
            startNewRule()
          }
        } else if !rules.isEmpty {
          Button("Clear All", role: .destructive) {
            viewModel.replaceConditionalFormats([], actionName: "Clear Conditional Formats")
          }
        }
      },
      content: {
        HStack(alignment: .top, spacing: 12) {
          rulesList
            .frame(width: 240)
          newRulePane
            .frame(maxWidth: .infinity)
        }
        .frame(height: 400)
      }
    )
  }

  private var subtitle: String {
    if let editingRuleID, let rule = rules.first(where: { $0.id == editingRuleID }) {
      return "Editing a rule on \(Self.rangeLabel(rule.range))"
    }
    return "New rule for \(selectionRangeLabel)"
  }

  /// Every rule on the sheet, first rule first. The selected one is in the editor.
  private var rulesList: some View {
    VStack(spacing: 0) {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 1) {
          ForEach(rules) { rule in
            ruleListRow(rule)
          }
          if rules.isEmpty {
            Text("No rules on \(viewModel.activeSheet.name) yet.")
              .font(.system(size: 12))
              .foregroundStyle(SparkStyle.secondaryLabel)
              .padding(10)
          }
        }
        .padding(4)
      }
      Divider()
      HStack(spacing: 2) {
        listButton("plus", help: "New rule") { startNewRule() }
        listButton("minus", help: "Delete the selected rule") {
          guard let editingRuleID else { return }
          viewModel.removeConditionalFormatRules(ids: [editingRuleID])
          startNewRule()
        }
        .disabled(editingRuleID == nil)
        Spacer()
        listButton("chevron.up", help: "Check this rule earlier") { moveSelected(-1) }
          .disabled(selectedIndex.map { $0 == 0 } ?? true)
        listButton("chevron.down", help: "Check this rule later") { moveSelected(1) }
          .disabled(selectedIndex.map { $0 >= rules.count - 1 } ?? true)
      }
      .padding(4)
    }
    .background(RoundedRectangle(cornerRadius: 8).fill(SparkStyle.chrome))
    .overlay(RoundedRectangle(cornerRadius: 8).stroke(SparkStyle.separator, lineWidth: 1))
  }

  private var selectedIndex: Int? {
    guard let editingRuleID else { return nil }
    return rules.firstIndex { $0.id == editingRuleID }
  }

  private func moveSelected(_ direction: Int) {
    guard let index = selectedIndex else { return }
    moveRule(at: index, direction: direction)
  }

  private func startNewRule() {
    editingRuleID = nil
    finishBoldEdit()
  }

  private func listButton(_ symbol: String, help: String, action: @escaping () -> Void)
    -> some View
  {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 11, weight: .semibold))
        .frame(width: 22, height: 20)
        .contentShape(Rectangle())
    }
    .buttonStyle(.borderless)
    .help(help)
  }

  private func ruleListRow(_ rule: ConditionalFormatRule) -> some View {
    let selected = editingRuleID == rule.id
    return Button {
      beginEditing(rule)
    } label: {
      HStack(spacing: 8) {
        ruleStylePreview(rule)
          .frame(width: 26, height: 18)
        VStack(alignment: .leading, spacing: 1) {
          Text(rule.predicate.title)
            .font(.system(size: 12, weight: selected ? .semibold : .regular))
            .foregroundStyle(SparkStyle.label)
            .lineLimit(2)
          Text(Self.rangeLabel(rule.range))
            .font(.system(size: 11))
            .foregroundStyle(SparkStyle.secondaryLabel)
        }
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 6)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 5).fill(selected ? SparkStyle.accent.opacity(0.22) : .clear)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private var newRulePane: some View {
    Form {
      Picker("Type", selection: $ruleType) {
        ForEach(RuleType.allCases) { type in
          Text(type.rawValue).tag(type)
        }
      }

      switch ruleType {
      case .highlightCells:
        highlightFields
        formatFields
      case .formula:
        formulaFields
        formatFields
      case .colorScale:
        colorScaleFields
      case .dataBars:
        dataBarFields
      case .iconSets:
        iconSetFields
      }
    }
    .formStyle(.grouped)
    .padding(.horizontal, 8)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }

  @ViewBuilder
  private var highlightFields: some View {
    Section("Condition") {
      Picker("Rule", selection: $highlightKind) {
        ForEach(HighlightKind.allCases) { kind in
          Text(kind.rawValue).tag(kind)
        }
      }

      if highlightKind.needsValue {
        TextField(highlightKind.valueLabel, text: $valueText)
      }

      if highlightKind.needsSecondValue {
        TextField("Maximum", text: $value2Text)
      }
    }
  }

  private var formulaFields: some View {
    Section("Condition") {
      TextField("Formula", text: $formulaText)
      Text("Evaluated relative to the top-left cell of each applied range.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  @ViewBuilder
  private var formatFields: some View {
    Section("Format") {
      ColorPicker("Fill", selection: $fillColor, supportsOpacity: false)

      HStack(spacing: 8) {
        ForEach(Self.fillPresets, id: \.0) { preset in
          Button {
            fillColor = preset.1
          } label: {
            RoundedRectangle(cornerRadius: 3)
              .fill(preset.1)
              .frame(width: 22, height: 16)
              .overlay(
                RoundedRectangle(cornerRadius: 3)
                  .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
              )
          }
          .buttonStyle(.plain)
          .help(preset.0)
        }
      }

      Toggle("Custom text color", isOn: $useCustomTextColor)
      if useCustomTextColor {
        ColorPicker("Text", selection: $textColor, supportsOpacity: false)
      }

      Toggle(
        "Bold",
        isOn: Binding(
          get: { formatBold },
          set: { newValue in
            formatBold = newValue
            boldTouched = true
          }
        ))
      Toggle("Italic", isOn: $formatItalic)
    }
  }

  @ViewBuilder
  private var colorScaleFields: some View {
    Section("Color Scale") {
      Text("Colors interpolate across numeric values in the range (low → mid → high).")
        .font(.caption)
        .foregroundStyle(.secondary)

      ColorPicker("Minimum", selection: $scaleMinColor, supportsOpacity: false)
      Toggle("Midpoint", isOn: $useMidStop)
      if useMidStop {
        ColorPicker("Midpoint", selection: $scaleMidColor, supportsOpacity: false)
      }
      ColorPicker("Maximum", selection: $scaleMaxColor, supportsOpacity: false)

      HStack(spacing: 0) {
        scaleMinColor
        if useMidStop { scaleMidColor }
        scaleMaxColor
      }
      .frame(height: 18)
      .clipShape(RoundedRectangle(cornerRadius: 4))
      .overlay(
        RoundedRectangle(cornerRadius: 4)
          .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
      )
    }
  }

  @ViewBuilder
  private var dataBarFields: some View {
    Section("Data Bars") {
      ColorPicker("Bar color", selection: $dataBarColor, supportsOpacity: false)
      Toggle("Show cell value", isOn: $dataBarShowValue)
      Text("Bar length is relative to the min/max of numeric values in the range.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  @ViewBuilder
  private var iconSetFields: some View {
    Section("Icon Set") {
      Picker("Style", selection: $iconSetStyle) {
        ForEach(IconSetStyle.allCases, id: \.self) { style in
          Text(style.title).tag(style)
        }
      }
      Text("Icons are assigned by percentile thresholds (33% / 67%) within the range.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  @ViewBuilder
  private func ruleStylePreview(_ rule: ConditionalFormatRule) -> some View {
    switch rule.predicate {
    case .colorScale(let stops):
      HStack(spacing: 0) {
        ForEach(Array(stops.enumerated()), id: \.offset) { _, stop in
          colorFromCodable(stop.color)
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: 3))
      .overlay(
        RoundedRectangle(cornerRadius: 3).strokeBorder(
          Color(nsColor: .separatorColor), lineWidth: 0.5))
    case .dataBar(let style):
      RoundedRectangle(cornerRadius: 3)
        .fill(colorFromCodable(style.color))
        .overlay(
          RoundedRectangle(cornerRadius: 3).strokeBorder(
            Color(nsColor: .separatorColor), lineWidth: 0.5))
    case .iconSet:
      Image(systemName: "circle.grid.3x3.fill")
        .foregroundStyle(.secondary)
    default:
      RoundedRectangle(cornerRadius: 3)
        .fill(rule.style.fillColor.map(colorFromCodable) ?? Color(nsColor: .controlBackgroundColor))
        .overlay(
          RoundedRectangle(cornerRadius: 3).strokeBorder(
            Color(nsColor: .separatorColor), lineWidth: 0.5))
    }
  }

  private func ruleStyleSummary(_ rule: ConditionalFormatRule) -> String {
    switch rule.predicate {
    case .colorScale, .dataBar, .iconSet:
      return rule.predicate.title
    default:
      var parts: [String] = []
      if rule.style.fillColor != nil { parts.append("Fill") }
      if rule.style.textColor != nil { parts.append("Text") }
      if rule.style.bold == true { parts.append("Bold") }
      if rule.style.italic == true { parts.append("Italic") }
      return parts.isEmpty ? "No format" : parts.joined(separator: " · ")
    }
  }

  private func applyNewRule() {
    if let editingID = editingRuleID {
      guard let rule = buildRule(for: viewModel.selectionRange) else { return }
      var updated = rule
      updated.id = editingID
      // Keep the existing range when editing.
      if let existing = rules.first(where: { $0.id == editingID }) {
        updated.range = existing.range
      }
      var next = rules
      if let index = next.firstIndex(where: { $0.id == editingID }) {
        next[index] = updated
      } else {
        next.append(updated)
      }
      viewModel.replaceConditionalFormats(next, actionName: "Update Conditional Format")
      editingRuleID = nil
      finishBoldEdit()
      return
    }

    let ranges =
      viewModel.selectionRanges.isEmpty
      ? [viewModel.selectionRange]
      : viewModel.selectionRanges
    var applied = false
    for range in ranges {
      guard let rule = buildRule(for: range) else { continue }
      viewModel.addConditionalFormatRule(rule)
      applied = true
    }
    if applied {
      finishBoldEdit()
    }
  }

  private func finishBoldEdit() {
    loadedBold = nil
    loadedItalic = nil
    boldTouched = false
  }

  private func buildRule(for range: CellRange) -> ConditionalFormatRule? {
    switch ruleType {
    case .highlightCells:
      guard let predicate = buildHighlightPredicate() else { return nil }
      return ConditionalFormatRule(range: range, predicate: predicate, style: buildFormatStyle())

    case .formula:
      let formula = normalizedFormula()
      guard !formula.isEmpty else { return nil }
      return ConditionalFormatRule(
        range: range, predicate: .formula(formula), style: buildFormatStyle())

    case .colorScale:
      return ConditionalFormatRule(
        range: range,
        stopIfTrue: false,
        predicate: .colorScale(buildColorScaleStops()),
        style: ConditionalFormatStyle()
      )

    case .dataBars:
      let style = DataBarStyle(
        color: CellFormatRenderer.codableColor(from: NSColor(dataBarColor)),
        showValue: dataBarShowValue
      )
      return ConditionalFormatRule(
        range: range,
        stopIfTrue: false,
        predicate: .dataBar(style),
        style: ConditionalFormatStyle()
      )

    case .iconSets:
      return ConditionalFormatRule(
        range: range,
        stopIfTrue: false,
        predicate: .iconSet(iconSetStyle),
        style: ConditionalFormatStyle()
      )
    }
  }

  private func buildFormatStyle() -> ConditionalFormatStyle {
    let previous = editingRuleID == nil ? nil : loadedBold
    let previousItalic = editingRuleID == nil ? nil : loadedItalic
    let style = ConditionalFormatStyle(
      bold: nil,
      italic: ConditionalFormatStyle.preservedCheckbox(
        isOn: formatItalic, previous: previousItalic),
      textColor: useCustomTextColor
        ? CellFormatRenderer.codableColor(from: NSColor(textColor))
        : nil,
      fillColor: CellFormatRenderer.codableColor(from: NSColor(fillColor))
    )
    return style.withBoldCheckbox(isOn: formatBold, previous: previous, touched: boldTouched)
  }

  private func buildColorScaleStops() -> [ColorScaleStop] {
    var stops: [ColorScaleStop] = [
      ColorScaleStop(
        type: .min,
        value: nil,
        color: CellFormatRenderer.codableColor(from: NSColor(scaleMinColor))
      )
    ]
    if useMidStop {
      stops.append(
        ColorScaleStop(
          type: .percentile,
          value: 50,
          color: CellFormatRenderer.codableColor(from: NSColor(scaleMidColor))
        )
      )
    }
    stops.append(
      ColorScaleStop(
        type: .max,
        value: nil,
        color: CellFormatRenderer.codableColor(from: NSColor(scaleMaxColor))
      )
    )
    return stops
  }

  private func buildHighlightPredicate() -> ConditionalFormatPredicate? {
    switch highlightKind {
    case .greaterThan:
      guard let v = Self.parseNumber(valueText) else { return nil }
      return .greaterThan(v)
    case .lessThan:
      guard let v = Self.parseNumber(valueText) else { return nil }
      return .lessThan(v)
    case .greaterOrEqual:
      guard let v = Self.parseNumber(valueText) else { return nil }
      return .greaterOrEqual(v)
    case .lessOrEqual:
      guard let v = Self.parseNumber(valueText) else { return nil }
      return .lessOrEqual(v)
    case .equal:
      guard let v = Self.parseNumber(valueText) else { return nil }
      return .equal(v)
    case .notEqual:
      guard let v = Self.parseNumber(valueText) else { return nil }
      return .notEqual(v)
    case .between:
      guard let a = Self.parseNumber(valueText), let b = Self.parseNumber(value2Text) else {
        return nil
      }
      return .between(a, b)
    case .notBetween:
      guard let a = Self.parseNumber(valueText), let b = Self.parseNumber(value2Text) else {
        return nil
      }
      return .notBetween(a, b)
    case .textContains:
      let text = valueText
      guard !text.isEmpty else { return nil }
      return .textContains(text)
    case .blanks:
      return .blanks
    case .nonBlanks:
      return .nonBlanks
    }
  }

  private func beginEditing(_ rule: ConditionalFormatRule) {
    editingRuleID = rule.id
    loadRuleIntoForm(rule)
  }

  private func loadRuleIntoForm(_ rule: ConditionalFormatRule) {
    loadedBold = rule.style.bold
    formatBold = rule.style.bold == true
    boldTouched = false
    loadedItalic = rule.style.italic
    formatItalic = rule.style.italic == true
    if let fill = rule.style.fillColor, let ns = CellFormatRenderer.nsColor(fill) {
      fillColor = Color(nsColor: ns)
    }
    if let text = rule.style.textColor, let ns = CellFormatRenderer.nsColor(text) {
      textColor = Color(nsColor: ns)
      useCustomTextColor = true
    } else {
      useCustomTextColor = false
    }

    switch rule.predicate {
    case .greaterThan(let v):
      ruleType = .highlightCells
      highlightKind = .greaterThan
      valueText = Self.formatNumber(v)
    case .lessThan(let v):
      ruleType = .highlightCells
      highlightKind = .lessThan
      valueText = Self.formatNumber(v)
    case .greaterOrEqual(let v):
      ruleType = .highlightCells
      highlightKind = .greaterOrEqual
      valueText = Self.formatNumber(v)
    case .lessOrEqual(let v):
      ruleType = .highlightCells
      highlightKind = .lessOrEqual
      valueText = Self.formatNumber(v)
    case .equal(let v):
      ruleType = .highlightCells
      highlightKind = .equal
      valueText = Self.formatNumber(v)
    case .notEqual(let v):
      ruleType = .highlightCells
      highlightKind = .notEqual
      valueText = Self.formatNumber(v)
    case .between(let a, let b):
      ruleType = .highlightCells
      highlightKind = .between
      valueText = Self.formatNumber(a)
      value2Text = Self.formatNumber(b)
    case .notBetween(let a, let b):
      ruleType = .highlightCells
      highlightKind = .notBetween
      valueText = Self.formatNumber(a)
      value2Text = Self.formatNumber(b)
    case .textContains(let s):
      ruleType = .highlightCells
      highlightKind = .textContains
      valueText = s
    case .blanks:
      ruleType = .highlightCells
      highlightKind = .blanks
    case .nonBlanks:
      ruleType = .highlightCells
      highlightKind = .nonBlanks
    case .formula(let f):
      ruleType = .formula
      formulaText = f
    case .colorScale(let stops):
      ruleType = .colorScale
      if let first = stops.first, let ns = CellFormatRenderer.nsColor(first.color) {
        scaleMinColor = Color(nsColor: ns)
      }
      if stops.count >= 3 {
        useMidStop = true
        if let ns = CellFormatRenderer.nsColor(stops[1].color) {
          scaleMidColor = Color(nsColor: ns)
        }
        if let ns = CellFormatRenderer.nsColor(stops[2].color) {
          scaleMaxColor = Color(nsColor: ns)
        }
      } else if let last = stops.last, let ns = CellFormatRenderer.nsColor(last.color) {
        useMidStop = false
        scaleMaxColor = Color(nsColor: ns)
      }
    case .dataBar(let style):
      ruleType = .dataBars
      if let ns = CellFormatRenderer.nsColor(style.color) {
        dataBarColor = Color(nsColor: ns)
      }
      dataBarShowValue = style.showValue
    case .iconSet(let style):
      ruleType = .iconSets
      iconSetStyle = style
    }
  }

  private func moveRule(at index: Int, direction: Int) {
    var next = rules
    let target = index + direction
    guard next.indices.contains(index), next.indices.contains(target) else { return }
    next.swapAt(index, target)
    viewModel.replaceConditionalFormats(next, actionName: "Reorder Conditional Formats")
  }

  private func normalizedFormula() -> String {
    var formula = formulaText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !formula.isEmpty else { return "" }
    if !formula.hasPrefix("=") { formula = "=\(formula)" }
    return formula
  }

  private func colorFromCodable(_ color: CodableColor) -> Color {
    if let ns = CellFormatRenderer.nsColor(color) {
      return Color(nsColor: ns)
    }
    return Color(
      red: color.red,
      green: color.green,
      blue: color.blue,
      opacity: color.alpha
    )
  }

  static func parseNumber(_ raw: String) -> Double? {
    var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return nil }
    text = text.replacingOccurrences(of: "$", with: "")
    text = text.replacingOccurrences(of: ",", with: "")
    let isPercent = text.hasSuffix("%")
    if isPercent {
      text = String(text.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    guard let value = Double(text) else { return nil }
    return isPercent ? value / 100.0 : value
  }

  private static func formatNumber(_ value: Double) -> String {
    if value.rounded() == value, abs(value) < 1e12 {
      return String(Int(value))
    }
    return String(value)
  }

  private static func rangeLabel(_ range: CellRange) -> String {
    let n = range.normalized
    let start = CellAddress(row: n.minRow, col: n.minCol).a1
    let end = CellAddress(row: n.maxRow, col: n.maxCol).a1
    return start == end ? start : "\(start):\(end)"
  }
}

// MARK: - AppKit presenter

enum ConditionalFormattingPresenter {
  @MainActor
  static func present(from viewModel: SpreadsheetViewModel, in window: NSWindow? = nil) {
    viewModel.commitEditIfNeeded()
    SparkDialogPresenter.present(title: "Conditional Formatting", width: 760, in: window) {
      close in
      ConditionalFormattingSheet(viewModel: viewModel, onDismiss: close)
    }
  }
}
