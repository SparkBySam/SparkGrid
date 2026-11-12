import AppKit
import Foundation
import SparkGridCore

/// Insert ▸ Link (⌘K): web and email links, and links to a place in the workbook. A cell's
/// =HYPERLINK formula is followed the same way. ⌘-click follows a link.
extension SpreadsheetViewModel {
  /// Where a link goes.
  enum LinkDestination: Equatable {
    /// A web address or `mailto:` address.
    case web(String)
    /// A cell, range or name in this workbook, such as `Summary!B4` or `Totals`.
    case place(String)
  }

  /// The blue Excel gives a cell when a link is inserted.
  static let linkTextColor = CodableColor(
    red: 5.0 / 255, green: 99.0 / 255, blue: 193.0 / 255, alpha: 1)

  var selectedHyperlink: CellHyperlink? { hyperlink(at: selectionAnchor) }

  /// `example.com` becomes `https://example.com`, `pat@example.com` becomes a mail link. Text
  /// that already names its kind, such as `http:` or `mailto:`, is kept.
  static func webAddress(from text: String) -> String? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !trimmed.contains(" ") else { return nil }
    if trimmed.range(of: #"^[A-Za-z][A-Za-z0-9+.-]*:"#, options: .regularExpression) != nil {
      return trimmed
    }
    if trimmed.contains("@"), !trimmed.contains("/") { return "mailto:" + trimmed }
    return "https://" + trimmed
  }

  /// What a link shows when no text is given: the address without `mailto:`, or the place.
  static func defaultLinkText(for destination: LinkDestination) -> String {
    switch destination {
    case .web(let address):
      return address.hasPrefix("mailto:") ? String(address.dropFirst(7)) : address
    case .place(let place):
      return place
    }
  }

  /// The selected cells, or the merge holding the active cell.
  private var linkRange: CellRange {
    if selectionRange.isSingleCell, let merge = activeSheet.mergeContaining(selectionAnchor) {
      return merge
    }
    let n = selectionRange.normalized
    return CellRange(
      start: CellAddress(row: n.minRow, col: n.minCol),
      end: CellAddress(row: n.maxRow, col: n.maxCol))
  }

  /// Links the selection. The active cell shows `text`, or the address when both the text and
  /// the cell are empty. A cell holding a formula keeps it.
  func setLink(text: String, destination: LinkDestination) {
    commitEditIfNeeded()
    let range = linkRange
    guard protectionAllows([range], permission: .insertHyperlinks) else { return }
    let link: CellHyperlink
    switch destination {
    case .web(let address):
      guard let target = Self.webAddress(from: address) else { return }
      link = CellHyperlink(range: range, target: target)
    case .place(let place):
      let trimmed = place.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { return }
      link = CellHyperlink(range: range, location: trimmed)
    }
    let editing = selectedHyperlink != nil
    let anchor = range.normalized
    let anchorAddress = CellAddress(row: anchor.minRow, col: anchor.minCol)
    let current = activeSheet.cell(at: anchorAddress).raw
    let wanted = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let shown: String?
    if FormulaSyntax.isFormula(current) {
      shown = nil
    } else if !wanted.isEmpty {
      shown = wanted == current ? nil : wanted
    } else if current.isEmpty {
      let address = link.target.map { LinkDestination.web($0) } ?? .place(link.location ?? "")
      shown = Self.defaultLinkText(for: address)
    } else {
      shown = nil
    }

    undoManager?.beginUndoGrouping()
    updateFileExtras(actionName: editing ? "Edit Link" : "Insert Link") { extras in
      extras.hyperlinks.removeAll { Self.ranges(range, contains: $0.range) }
      extras.hyperlinks.append(link)
    }
    if let shown { setCellValue(shown, at: anchorAddress) }
    if !editing {
      applyFormat(toRanges: [range], actionName: nil) { _, format in
        format.textColor = Self.linkTextColor
        format.underline = true
      }
    }
    undoManager?.endUndoGrouping()
    undoManager?.setActionName(editing ? "Edit Link" : "Insert Link")
    syncEditTextFromSelection()
    notifyGridRefresh()
  }

  /// Takes the links off the selected cells. Text keeps its value; the link blue and underline
  /// go, as other spreadsheet apps do.
  func removeLink() {
    commitEditIfNeeded()
    let range = linkRange
    guard protectionAllows([range], permission: .insertHyperlinks) else { return }
    let n = range.normalized
    let touched = activeSheet.fileExtras.hyperlinks.filter { link in
      let l = link.range.normalized
      return l.minRow <= n.maxRow && l.maxRow >= n.minRow && l.minCol <= n.maxCol
        && l.maxCol >= n.minCol
    }
    guard !touched.isEmpty else { return }
    undoManager?.beginUndoGrouping()
    updateFileExtras(actionName: "Remove Link") { extras in
      extras.hyperlinks.removeAll { touched.contains($0) }
    }
    applyFormat(toRanges: touched.map(\.range), actionName: nil) { _, format in
      if format.textColor == Self.linkTextColor { format.textColor = nil }
      format.underline = false
    }
    undoManager?.endUndoGrouping()
    undoManager?.setActionName("Remove Link")
    notifyGridRefresh()
  }

  private static func ranges(_ outer: CellRange, contains inner: CellRange) -> Bool {
    let o = outer.normalized
    let i = inner.normalized
    return i.minRow >= o.minRow && i.maxRow <= o.maxRow && i.minCol >= o.minCol
      && i.maxCol <= o.maxCol
  }

  // MARK: - Following

  /// The link on a cell, from the sheet's links or from a =HYPERLINK formula in the cell.
  func followableLink(at address: CellAddress) -> CellHyperlink? {
    if let link = hyperlink(at: address) { return link }
    guard let target = hyperlinkFormulaTarget(at: address) else { return nil }
    let range = CellRange(start: address, end: address)
    if target.hasPrefix("#") {
      return CellHyperlink(range: range, location: String(target.dropFirst()))
    }
    if Self.workbookPlace(target, in: workbook) != nil, !target.contains(":/") {
      return CellHyperlink(range: range, location: target)
    }
    return CellHyperlink(range: range, target: Self.webAddress(from: target) ?? target)
  }

  /// The first argument of a cell's =HYPERLINK(address, [text]), worked out.
  func hyperlinkFormulaTarget(at address: CellAddress) -> String? {
    let raw = activeSheet.cell(at: address).raw
    guard FormulaSyntax.isFormula(raw),
      let expr = try? FormulaParser.parse(raw),
      case .call(let name, let args) = expr,
      name.uppercased() == "HYPERLINK", !args.isEmpty
    else { return nil }
    if case .string(let text) = args[0] { return text }
    // IF(TRUE, a, b) is a; the rest of the formula is evaluated as written.
    guard let open = raw.range(of: "HYPERLINK(", options: .caseInsensitive) else { return nil }
    let rewritten = "=IF(TRUE," + raw[open.upperBound...]
    let value = formulaEngine.evaluateConditionalFormula(
      rewritten, at: address, relativeTo: address, sheet: activeSheet)
    let text = literalString(from: value)
    return text.isEmpty ? nil : text
  }

  /// The sheet and range a place names: `Sheet2!B4`, `'Q1 Sales'!A1:C9`, `B4` on this sheet,
  /// or a defined name.
  static func workbookPlace(_ place: String, in workbook: Workbook, activeSheet: String? = nil)
    -> (sheet: String, range: CellRange)?
  {
    var text = place.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.hasPrefix("#") { text.removeFirst() }
    if text.hasPrefix("=") { text.removeFirst() }
    guard !text.isEmpty else { return nil }
    if let named = workbook.namedRanges[text.uppercased()], named.resolvesToRange {
      return (named.sheetName, named.range)
    }
    let ends: (FormulaRef, FormulaRef)
    if let pair = A1Reference.parseFormulaRange(text) {
      ends = pair
    } else if let ref = A1Reference.parseFormulaRef(text) {
      ends = (ref, ref)
    } else {
      return nil
    }
    let sheetName = ends.0.sheet ?? activeSheet ?? workbook.activeSheet.name
    guard
      workbook.sheets.contains(where: {
        $0.name.caseInsensitiveCompare(sheetName) == .orderedSame
      })
    else { return nil }
    return (sheetName, CellRange(start: ends.0.address, end: ends.1.address))
  }

  /// Opens a web or mail link, or goes to the place a workbook link names. Other kinds of
  /// address, such as files, are not opened.
  func openHyperlink(_ link: CellHyperlink) {
    if let target = link.target, let url = URL(string: target),
      let scheme = url.scheme?.lowercased(), ["http", "https", "mailto"].contains(scheme)
    {
      NSWorkspace.shared.open(url)
      return
    }
    guard let location = link.location,
      let place = Self.workbookPlace(location, in: workbook, activeSheet: activeSheet.name),
      let index = workbook.sheets.firstIndex(where: {
        $0.name.caseInsensitiveCompare(place.sheet) == .orderedSame
      }), !workbook.sheets[index].isHidden
    else { return }
    if index != workbook.activeSheetIndex { selectSheet(at: index) }
    selectRange(from: place.range.start, to: place.range.end)
  }
}
