import AppKit
import Foundation
import SparkGridCore

/// A conditional-format range by its corners, for caching the numbers in it.
struct ConditionalRangeKey: Hashable {
  var minRow: Int
  var maxRow: Int
  var minCol: Int
  var maxCol: Int
}

extension SpreadsheetViewModel {
  /// Full conditional paint (format + data bars / icons).
  func resolvedPaint(at address: CellAddress) -> ConditionalPaint {
    let rules = activeSheet.conditionalFormats
    let cell = activeSheet.cell(at: address)
    guard !rules.isEmpty else {
      return ConditionalPaint(format: cell.format)
    }
    if conditionalFormatCacheRevision != contentRevision {
      conditionalFormatCache.removeAll(keepingCapacity: true)
      conditionalRangeNumbers.removeAll(keepingCapacity: true)
      conditionalFormatCacheRevision = contentRevision
    }
    if let index = conditionalFormatCache.index(forKey: address) {
      return conditionalFormatCache[index].value
    }
    let value = displayValue(at: address)
    let text = formulaEngine.displayString(at: address, sheet: activeSheet, format: cell.format)
    let resolved = ConditionalFormatEvaluator.resolvedPaint(
      at: address,
      base: cell.format,
      rules: rules,
      value: value,
      displayString: text,
      numberFormat: cell.format?.numberFormat,
      numericValuesInRange: { [weak self] range in
        guard let self else { return [] }
        return self.numericValues(in: range)
      },
      evaluateFormula: { [weak self] raw, addr, origin in
        guard let self else { return .blank }
        return self.formulaEngine.evaluateConditionalFormula(
          raw,
          at: addr,
          relativeTo: origin,
          sheet: self.activeSheet
        )
      }
    )
    conditionalFormatCache[address] = resolved
    return resolved
  }

  /// Format used for painting a cell (base + conditional formatting overlays).
  func resolvedFormat(at address: CellAddress) -> CellFormat? {
    resolvedPaint(at: address).format
  }

  /// A color scale or data bar needs every number in its range to place one cell. Without
  /// this cache each cell re-read the whole range: on a 5,700-cell scale, painting after a
  /// resize took the main thread for seconds and scrolling stayed slow.
  private func numericValues(in range: CellRange) -> [Double] {
    let n = range.normalized
    let key = ConditionalRangeKey(
      minRow: n.minRow, maxRow: n.maxRow, minCol: n.minCol, maxCol: n.maxCol)
    if let cached = conditionalRangeNumbers[key] {
      return cached
    }
    let values = readNumericValues(in: range)
    conditionalRangeNumbers[key] = values
    return values
  }

  private func readNumericValues(in range: CellRange) -> [Double] {
    let n = range.normalized
    var values: [Double] = []
    for row in n.minRow...n.maxRow {
      for col in n.minCol...n.maxCol {
        if let number = displayValue(at: CellAddress(row: row, col: col)).asNumber {
          values.append(number)
        }
      }
    }
    return values
  }

  func addConditionalFormatRule(_ rule: ConditionalFormatRule) {
    commitEditIfNeeded()
    var sheet = activeSheet
    let before = sheet.conditionalFormats
    sheet.conditionalFormats.append(rule)
    applyConditionalFormats(
      sheet.conditionalFormats, undoBefore: before, actionName: "Add Conditional Format")
  }

  func removeConditionalFormatRules(ids: Set<UUID>) {
    guard !ids.isEmpty else { return }
    commitEditIfNeeded()
    var sheet = activeSheet
    let before = sheet.conditionalFormats
    sheet.conditionalFormats.removeAll { ids.contains($0.id) }
    guard sheet.conditionalFormats != before else { return }
    applyConditionalFormats(
      sheet.conditionalFormats, undoBefore: before, actionName: "Remove Conditional Format")
  }

  func clearConditionalFormats(intersecting range: CellRange) {
    commitEditIfNeeded()
    var sheet = activeSheet
    let before = sheet.conditionalFormats
    sheet.conditionalFormats.removeAll { rule in
      rangesIntersect(rule.range, range)
    }
    guard sheet.conditionalFormats != before else { return }
    applyConditionalFormats(
      sheet.conditionalFormats, undoBefore: before, actionName: "Clear Conditional Formats")
  }

  func replaceConditionalFormatRule(_ rule: ConditionalFormatRule) {
    var rules = activeSheet.conditionalFormats
    guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
    rules[index] = rule
    replaceConditionalFormats(rules, actionName: "Edit Conditional Format")
  }

  func replaceConditionalFormats(
    _ rules: [ConditionalFormatRule], actionName: String = "Conditional Format"
  ) {
    commitEditIfNeeded()
    let before = activeSheet.conditionalFormats
    guard before != rules else { return }
    applyConditionalFormats(rules, undoBefore: before, actionName: actionName)
  }

  func restoreFilterFromActiveSheet() {
    isRestoringFilterFromSheet = true
    filterState = activeSheet.autoFilter
    isRestoringFilterFromSheet = false
    // Ensure chevrons appear even when workbook contentRevision already advanced.
    notifyGridRefresh()
  }

  func syncAutoFilterToActiveSheet() {
    var sheet = activeSheet
    guard sheet.autoFilter != filterState else { return }
    sheet.autoFilter = filterState
    setActiveSheetPreservingFormulas(sheet)
  }

  func pasteCopiedConditionalFormats(
    _ payload: SpreadsheetClipboard.ConditionalFormatClipboardPayload?,
    at origin: CellAddress,
    actionName: String = "Paste",
    recordUndo: Bool = true
  ) {
    guard let payload else { return }
    let sheet = activeSheet
    let pasted = ConditionalFormatPaste.retargetedRules(
      payload,
      to: origin,
      maxRow: sheet.effectiveRowCount - 1,
      maxCol: sheet.effectiveColumnCount - 1
    )
    guard !pasted.isEmpty else { return }
    var next = sheet.conditionalFormats
    var changed = false
    for rule in pasted {
      if next.contains(where: { ConditionalFormatPaste.sameAppearance($0, rule) }) { continue }
      next.append(rule)
      changed = true
    }
    guard changed else { return }
    applyConditionalFormats(
      next,
      undoBefore: sheet.conditionalFormats,
      actionName: actionName,
      recordUndo: recordUndo
    )
  }

  private func applyConditionalFormats(
    _ rules: [ConditionalFormatRule],
    undoBefore: [ConditionalFormatRule],
    actionName: String,
    recordUndo: Bool = true
  ) {
    var sheet = activeSheet
    sheet.conditionalFormats = rules
    setActiveSheetPreservingFormulas(sheet)
    conditionalFormatCache.removeAll(keepingCapacity: true)
    conditionalFormatCacheRevision = -1
    if recordUndo {
      undoManager?.registerUndo(withTarget: self) { target in
        target.applyConditionalFormats(undoBefore, undoBefore: rules, actionName: actionName)
      }
      undoManager?.setActionName(actionName)
    }
    notifyGridRefresh()
  }

  private func rangesIntersect(_ a: CellRange, _ b: CellRange) -> Bool {
    let an = a.normalized
    let bn = b.normalized
    return an.minRow <= bn.maxRow && an.maxRow >= bn.minRow
      && an.minCol <= bn.maxCol && an.maxCol >= bn.minCol
  }
}
