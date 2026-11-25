import AppKit
import SparkGridCore

/// Data validation: rules that say what a cell may hold (a whole number between 1 and 10, a date
/// after today, text no longer than 20 letters, a formula that must be TRUE). Files carry them
/// and Spark Grid kept them; since 1.7 a typed entry is checked against them, with the alert the
/// rule asks for, and Data › Data Validation makes and changes them (Sam, Nov 20).
extension SpreadsheetViewModel {
  /// The rule on this cell; the last one wins when rules overlap, as in other apps.
  func validationRule(at address: CellAddress) -> DataValidationRule? {
    activeSheet.fileExtras.dataValidations.last { $0.ranges.contains { $0.contains(address) } }
  }

  /// The rule's input message, shown when pointing at the cell.
  func validationPrompt(at address: CellAddress) -> String? {
    guard let parts = validationRule(at: address)?.parts, parts.showInput,
      !(parts.prompt.isEmpty && parts.promptTitle.isEmpty)
    else { return nil }
    return [parts.promptTitle, parts.prompt].filter { !$0.isEmpty }.joined(separator: "\n")
  }

  /// The rule `text` breaks if typed into `address`, when that rule shows an alert.
  func brokenValidationRule(for text: String, at address: CellAddress) -> DataValidationRule? {
    guard let rule = validationRule(at: address) else { return nil }
    let parts = rule.parts
    guard parts.showError, parts.kind != .any else { return nil }
    // Clearing a cell is not an entry, and a formula is checked by its owner, not here.
    guard !text.isEmpty, !FormulaSyntax.isFormula(text) else { return nil }
    return passes(text, rule: rule, parts: parts, at: address) ? nil : rule
  }

  /// What typing `text` puts in the cell, as the rule sees it.
  private static func enteredValue(_ text: String) -> CellValue {
    if text.hasPrefix("'") { return .string(String(text.dropFirst())) }
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    if let number = Double(trimmed) { return .number(number) }
    if let reading = TypedEntry.read(trimmed) { return .number(reading.value) }
    if let serial = FormulaEvaluator.dateSerial(trimmed) { return .number(serial) }
    if trimmed.caseInsensitiveCompare("TRUE") == .orderedSame { return .bool(true) }
    if trimmed.caseInsensitiveCompare("FALSE") == .orderedSame { return .bool(false) }
    return .string(text)
  }

  private func limit(_ formula: String, rule: DataValidationRule, at address: CellAddress)
    -> Double?
  {
    let trimmed = formula.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return nil }
    if let number = Double(trimmed) { return number }
    if let serial = FormulaEvaluator.dateSerial(trimmed) { return serial }
    let origin =
      rule.ranges.first.map { CellAddress(row: $0.normalized.minRow, col: $0.normalized.minCol) }
      ?? address
    let value = formulaEngine.evaluateConditionalFormula(
      trimmed, at: address, relativeTo: origin, sheet: activeSheet)
    return value.asNumber
  }

  private func passes(
    _ text: String, rule: DataValidationRule, parts: DataValidationRule.Parts,
    at address: CellAddress
  ) -> Bool {
    let value = Self.enteredValue(text)
    switch parts.kind {
    case .any:
      return true
    case .list:
      guard let items = dropdownItems(at: address) else { return true }
      let entered = text.trimmingCharacters(in: .whitespaces)
      return items.contains { $0.caseInsensitiveCompare(entered) == .orderedSame }
    case .custom:
      let origin =
        rule.ranges.first.map { CellAddress(row: $0.normalized.minRow, col: $0.normalized.minCol) }
        ?? address
      let result = formulaEngine.evaluateConditionalFormula(
        parts.formula1, at: address, relativeTo: origin, sheet: activeSheet,
        replacing: (address, value))
      switch result {
      case .bool(let b): return b
      case .number(let n): return n != 0
      default: return false
      }
    case .whole, .decimal, .date, .time, .textLength:
      let measured: Double
      if parts.kind == .textLength {
        measured = Double(
          (value.isNumber ? value.displayString : (value.asStringValue ?? text)).count)
      } else {
        guard case .number(let n) = value else { return false }
        if parts.kind == .whole, n != n.rounded() { return false }
        measured = n
      }
      guard let low = limit(parts.formula1, rule: rule, at: address) else { return true }
      let high = limit(parts.formula2, rule: rule, at: address) ?? low
      switch parts.comparison {
      case .between: return measured >= min(low, high) && measured <= max(low, high)
      case .notBetween: return measured < min(low, high) || measured > max(low, high)
      case .equal: return measured == low
      case .notEqual: return measured != low
      case .greaterThan: return measured > low
      case .lessThan: return measured < low
      case .greaterThanOrEqual: return measured >= low
      case .lessThanOrEqual: return measured <= low
      }
    }
  }

  /// Asks about an entry that breaks `rule`, on the window, as the rule's alert style says:
  /// Stop refuses it, Warning asks whether to keep it, Information tells and keeps it unless
  /// Cancel is chosen. `keep` gets the answer once; closing the sheet any other way is a no.
  func presentValidationAlert(
    _ rule: DataValidationRule, entry: String, at address: CellAddress,
    keep: @escaping (Bool) -> Void
  ) {
    var answered = false
    let answer: (Bool) -> Void = { value in
      guard !answered else { return }
      answered = true
      keep(value)
    }
    // After the cell's edit has finished: a sheet begun while the editor is ending its layout
    // pass sent the window into a loop of size changes.
    DispatchQueue.main.async { [weak self] in
      // On this workbook's window, also when another app is in front and none is key.
      let window = self.flatMap { WorkbookWindows.shared.window(showing: $0) }
      SparkDialogPresenter.present(
        title: "Data Validation", width: 360, in: window, onEnd: { answer(false) }
      ) { close in
        ValidationAlertSheet(
          parts: rule.parts, entry: entry, cell: address.a1,
          onAnswer: { value in
            answer(value)
            close()
          })
      }
    }
  }

  // MARK: - Making rules

  /// The rule on the selected cell, for the dialog to start from.
  var selectedValidationParts: DataValidationRule.Parts? {
    validationRule(at: selectionAnchor)?.parts
  }

  /// Gives the selected cells `parts` as their rule, replacing any rule they had there.
  func setValidation(_ parts: DataValidationRule.Parts) {
    let ranges = selectionRanges.isEmpty ? [selectionRange] : selectionRanges
    updateFileExtras(actionName: "Data Validation") { extras in
      extras.dataValidations = Self.removingRules(from: extras.dataValidations, in: ranges)
      extras.dataValidations.append(DataValidationRule(ranges: ranges, parts: parts))
    }
    notifyGridRefresh()
  }

  func clearValidation() {
    let ranges = selectionRanges.isEmpty ? [selectionRange] : selectionRanges
    updateFileExtras(actionName: "Clear Data Validation") { extras in
      extras.dataValidations = Self.removingRules(from: extras.dataValidations, in: ranges)
    }
    notifyGridRefresh()
  }

  /// Every rule with `ranges` cut out of it.
  static func removingRules(from rules: [DataValidationRule], in ranges: [CellRange])
    -> [DataValidationRule]
  {
    rules.compactMap { rule in
      var kept = rule.ranges
      for cut in ranges {
        kept = kept.flatMap { subtract(cut, from: $0) }
      }
      guard !kept.isEmpty else { return nil }
      var next = rule
      next.ranges = kept
      return next
    }
  }
}

extension CellValue {
  fileprivate var isNumber: Bool {
    if case .number = self { return true }
    return false
  }

  fileprivate var asStringValue: String? {
    if case .string(let s) = self { return s }
    return nil
  }
}
