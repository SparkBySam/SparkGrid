import AppKit
import SparkGridCore

/// Dropdown lists, comments and links a file carries on its cells.
extension SpreadsheetViewModel {
  /// Longest list a dropdown shows.
  static let dropdownItemLimit = 500

  /// The choices of the dropdown list on this cell, or nil when it has none.
  func dropdownItems(at address: CellAddress) -> [String]? {
    guard
      let rule = activeSheet.fileExtras.dataValidations.last(where: { rule in
        rule.attributes.contains(#"type="list""#) && rule.ranges.contains { $0.contains(address) }
      })
    else { return nil }
    if let items = rule.inlineListItems {
      return Array(items.prefix(Self.dropdownItemLimit))
    }
    guard let source = rule.listSourceFormula else { return nil }
    return listItems(fromSource: source)
  }

  /// Values in the cells a list rule points at, such as `$F$2:$F$9`, `Lists!$A$1:$A$5`, or a name.
  private func listItems(fromSource source: String) -> [String]? {
    var text = source.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.hasPrefix("=") { text.removeFirst() }
    let named =
      workbook.namedRanges[text.uppercased()]
      ?? DefinedNameFormula.make(
        name: "List", formula: text, sheets: workbook.sheets, localSheet: activeSheet.name)
    guard named.resolvesToRange,
      let sheetIndex = workbook.sheets.firstIndex(where: {
        $0.name.caseInsensitiveCompare(named.sheetName) == .orderedSame
      })
    else { return nil }
    let sheet = workbook.sheets[sheetIndex]
    let isActive = sheetIndex == workbook.activeSheetIndex
    let n = named.range.normalized
    var items: [String] = []
    rows: for row in n.minRow...n.maxRow {
      for col in n.minCol...n.maxCol {
        let address = CellAddress(row: row, col: col)
        let cell = sheet.cell(at: address)
        let text =
          isActive
          ? displayString(at: address)
          : (cell.importedFormulaResult ?? (FormulaSyntax.isFormula(cell.raw) ? "" : cell.raw))
        if !text.isEmpty { items.append(text) }
        if items.count >= Self.dropdownItemLimit { break rows }
      }
      // A whole-column source stops at the end of the data.
      if row > sheet.maxPopulatedRow { break }
    }
    return items
  }

  /// Puts a dropdown choice in the selected cell, as typing it would.
  func chooseDropdownItem(_ item: String, at address: CellAddress) {
    commitEditIfNeeded()
    setCellValue(item, at: address)
    syncEditTextFromSelection()
  }

  func comment(at address: CellAddress) -> CellComment? {
    let comments = activeSheet.fileExtras.comments
    guard !comments.isEmpty else { return nil }
    let anchor = activeSheet.mergeAnchor(for: address)
    return comments.first { $0.address == anchor }
  }

  func hyperlink(at address: CellAddress) -> CellHyperlink? {
    let links = activeSheet.fileExtras.hyperlinks
    guard !links.isEmpty else { return nil }
    return links.last { $0.range.contains(address) }
  }

  /// Text shown when the pointer rests on a cell with a comment or a link.
  func noteToolTip(at address: CellAddress) -> String? {
    var parts: [String] = []
    if let comment = comment(at: address) {
      parts.append(comment.author.isEmpty ? comment.text : "\(comment.author): \(comment.text)")
    }
    if let link = hyperlink(at: address) {
      if let tip = link.tooltip, !tip.isEmpty {
        parts.append(tip)
      } else if let target = link.target {
        parts.append(target)
      } else if let location = link.location {
        parts.append("Go to \(location)")
      }
    }
    return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
  }

  /// Opens a web or mail link in the browser or mail app, or selects the place a workbook link
  /// names. Other kinds of target, such as files, are not opened.
  func openHyperlink(_ link: CellHyperlink) {
    if let target = link.target, let url = URL(string: target),
      let scheme = url.scheme?.lowercased(), ["http", "https", "mailto"].contains(scheme)
    {
      NSWorkspace.shared.open(url)
      return
    }
    guard let location = link.location else { return }
    let ref = A1Reference.parseFormulaRef(location.replacingOccurrences(of: "$", with: ""))
    if let sheetName = ref?.sheet,
      let index = workbook.sheets.firstIndex(where: {
        $0.name.caseInsensitiveCompare(sheetName) == .orderedSame
      }), !workbook.sheets[index].isHidden
    {
      selectSheet(at: index)
    }
    if let ref {
      select(CellAddress(row: ref.row, col: ref.col))
    }
  }
}

extension SpreadsheetViewModel {
  /// True when the cell has a dropdown list. Cheaper than reading the list.
  func hasDropdown(at address: CellAddress) -> Bool {
    let rules = activeSheet.fileExtras.dataValidations
    guard !rules.isEmpty else { return false }
    return rules.contains { rule in
      rule.attributes.contains(#"type="list""#) && rule.ranges.contains { $0.contains(address) }
    }
  }
}

// MARK: - Making and changing dropdown lists and comments

extension SpreadsheetViewModel {
  /// Where a dropdown list's choices come from.
  enum DropdownSource: Equatable {
    /// Choices typed in, saved in the file as `"Open,Won,Lost"`.
    case items([String])
    /// Cells holding the choices, such as `$F$2:$F$9` or `Lists!$A$1:$A$5`.
    case cells(String)
  }

  /// The selection's ranges, for rules and comments.
  private var targetRanges: [CellRange] {
    selectionRanges.isEmpty ? [selectionRange] : selectionRanges
  }

  /// The list rule on the selected cell, if any.
  var selectedDropdownSource: DropdownSource? {
    let address = selectionAnchor
    guard
      let rule = activeSheet.fileExtras.dataValidations.last(where: { rule in
        rule.attributes.contains(#"type="list""#) && rule.ranges.contains { $0.contains(address) }
      })
    else { return nil }
    if let items = rule.inlineListItems { return .items(items) }
    return rule.listSourceFormula.map { .cells($0) }
  }

  /// Gives the selected cells a dropdown list, replacing any list they had.
  func setDropdown(_ source: DropdownSource) {
    let ranges = targetRanges
    let formula: String
    switch source {
    case .items(let items):
      let cleaned = items.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
      guard !cleaned.isEmpty else { return }
      // The file format keeps an inline list in one quoted string, comma separated.
      let joined = cleaned.map { $0.replacingOccurrences(of: ",", with: " ") }.joined(
        separator: ",")
      formula = "\"" + joined.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    case .cells(let reference):
      var text = reference.trimmingCharacters(in: .whitespacesAndNewlines)
      if text.hasPrefix("=") { text.removeFirst() }
      guard !text.isEmpty else { return }
      formula = text
    }
    let body = "<formula1>\(XLSXCodec.escapeXML(formula))</formula1>"
    updateFileExtras(actionName: "Dropdown List") { extras in
      extras.dataValidations = Self.removingLists(from: extras.dataValidations, in: ranges)
      extras.dataValidations.append(
        DataValidationRule(
          ranges: ranges,
          attributes: #"type="list" allowBlank="1" showErrorMessage="1""#,
          body: body
        ))
    }
    notifyGridRefresh()
  }

  /// Removes dropdown lists from the selected cells. The rest of each list stays.
  func removeDropdown() {
    let ranges = targetRanges
    updateFileExtras(actionName: "Remove Dropdown List") { extras in
      extras.dataValidations = Self.removingLists(from: extras.dataValidations, in: ranges)
    }
    notifyGridRefresh()
  }

  /// List rules with `ranges` cut out of them. Other kinds of rule are left alone.
  private static func removingLists(from rules: [DataValidationRule], in ranges: [CellRange])
    -> [DataValidationRule]
  {
    rules.compactMap { rule in
      guard rule.attributes.contains(#"type="list""#) else { return rule }
      var kept = rule.ranges
      for cut in ranges {
        kept = kept.flatMap { Self.subtract(cut, from: $0) }
      }
      guard !kept.isEmpty else { return nil }
      var next = rule
      next.ranges = kept
      return next
    }
  }

  /// `range` without the cells of `cut`, as up to four rectangles.
  static func subtract(_ cut: CellRange, from range: CellRange) -> [CellRange] {
    let r = range.normalized
    let c = cut.normalized
    let top = max(r.minRow, c.minRow)
    let bottom = min(r.maxRow, c.maxRow)
    let left = max(r.minCol, c.minCol)
    let right = min(r.maxCol, c.maxCol)
    guard top <= bottom, left <= right else { return [range] }
    func rect(_ r0: Int, _ c0: Int, _ r1: Int, _ c1: Int) -> CellRange? {
      guard r0 <= r1, c0 <= c1 else { return nil }
      return CellRange(start: CellAddress(row: r0, col: c0), end: CellAddress(row: r1, col: c1))
    }
    return [
      rect(r.minRow, r.minCol, top - 1, r.maxCol),
      rect(bottom + 1, r.minCol, r.maxRow, r.maxCol),
      rect(top, r.minCol, bottom, left - 1),
      rect(top, right + 1, bottom, r.maxCol),
    ].compactMap { $0 }
  }

  /// The comment on the selected cell, if any.
  var selectedComment: CellComment? { comment(at: selectionAnchor) }

  /// Adds or replaces the selected cell's comment. Empty text removes it.
  func setComment(_ text: String) {
    let address = activeSheet.mergeAnchor(for: selectionAnchor)
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let author = NSFullUserName()
    updateFileExtras(actionName: trimmed.isEmpty ? "Delete Comment" : "Comment") { extras in
      let existing = extras.comments.firstIndex { $0.address == address }
      if trimmed.isEmpty {
        if let existing { extras.comments.remove(at: existing) }
      } else if let existing {
        extras.comments[existing].text = trimmed
      } else {
        extras.comments.append(CellComment(address: address, author: author, text: trimmed))
      }
    }
    notifyGridRefresh()
  }

  func deleteComment() { setComment("") }
}
