import Foundation
import SparkGridCore

extension SpreadsheetViewModel {
  var definedNames: [NamedRange] {
    workbook.namedRanges.values.sorted {
      $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }
  }

  /// Adds or edits a defined name. Range references update the sheet; formulas such as OFFSET stay unresolved.
  /// Returns an error message, or nil when the name was saved.
  func upsertDefinedName(originalName: String?, name: String, refersTo: String) -> String? {
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedRef = refersTo.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else { return "Enter a name." }
    guard !trimmedRef.isEmpty else { return "Enter what this name refers to." }

    let original = originalName.flatMap { workbook.namedRange(named: $0) }
    let sameName = original?.name.caseInsensitiveCompare(trimmedName) == .orderedSame
    if original == nil || sameName != true {
      guard Self.isAcceptableDefinedName(trimmedName) else {
        return "Names start with a letter and can’t be a cell reference."
      }
    }
    let newKey = trimmedName.uppercased()
    if workbook.namedRanges[newKey] != nil, original?.name.uppercased() != newKey {
      return "A name called \(trimmedName) already exists."
    }

    let named = DefinedNameFormula.make(
      name: trimmedName,
      formula: trimmedRef,
      sheets: workbook.sheets,
      localSheet: activeSheet.name
    )
    commitEditIfNeeded()
    let before = workbook
    var wb = workbook
    if let original, original.name.uppercased() != newKey {
      wb.namedRanges.removeValue(forKey: original.name.uppercased())
      rewriteDefinedName(in: &wb, from: original.name, to: trimmedName)
    }
    wb.setNamedRange(named)
    workbook = wb
    registerDefinedNameUndo(
      before: before, after: workbook, action: original == nil ? "Add Name" : "Edit Name")
    if named.resolvesToRange {
      revealDefinedName(named)
    }
    return nil
  }

  func deleteDefinedName(named name: String) {
    guard workbook.namedRange(named: name) != nil else { return }
    commitEditIfNeeded()
    let before = workbook
    var wb = workbook
    wb.removeNamedRange(named: name)
    workbook = wb
    registerDefinedNameUndo(before: before, after: workbook, action: "Delete Name")
  }

  /// Selects a static range on its sheet. Formula names are left where they are.
  func revealDefinedName(_ named: NamedRange) {
    guard named.resolvesToRange else { return }
    commitEditIfNeeded()
    if let index = workbook.sheets.firstIndex(where: {
      $0.name.caseInsensitiveCompare(named.sheetName) == .orderedSame
    }), index != workbook.activeSheetIndex {
      selectSheet(at: index)
    }
    selectRange(
      from: CellAddress(row: named.startRow, col: named.startCol),
      to: CellAddress(row: named.endRow, col: named.endCol)
    )
    scrollRequestToken &+= 1
  }

  static func isAcceptableDefinedName(_ name: String) -> Bool {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.first?.isLetter == true,
      trimmed.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" })
    else { return false }
    return A1Reference.parseAddress(trimmed) == nil
  }

  private func rewriteDefinedName(in workbook: inout Workbook, from old: String, to new: String) {
    guard old.caseInsensitiveCompare(new) != .orderedSame else { return }
    for index in workbook.sheets.indices {
      var cells = workbook.sheets[index].cells
      var changed = false
      for (address, cell) in cells {
        let next = FormulaRewriter.renameDefinedName(cell.raw, from: old, to: new)
        guard next != cell.raw else { continue }
        var updated = cell
        updated.raw = next
        cells[address] = updated
        changed = true
      }
      if changed {
        workbook.sheets[index].cells = cells
      }
    }
  }

  private func registerDefinedNameUndo(before: Workbook, after: Workbook, action: String) {
    undoManager?.registerUndo(withTarget: self) { target in
      target.workbook = before
      target.undoManager?.registerUndo(withTarget: target) { inner in
        inner.workbook = after
      }
    }
    undoManager?.setActionName(action)
  }
}

extension SpreadsheetViewModel {
  /// The name box: jumps to an address (`B200`), a range (`A1:C5`), a cell on another sheet
  /// (`Lists!A1`), a defined name, or a table. Returns false when the text is none of those.
  @discardableResult
  func goTo(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }
    if let named = workbook.namedRange(named: trimmed), named.resolvesToRange {
      revealDefinedName(named)
      return true
    }
    if revealTable(named: trimmed) { return true }
    let target = DefinedNameFormula.make(
      name: "GoTo", formula: trimmed, sheets: workbook.sheets, localSheet: activeSheet.name)
    // Past the last column (XFD) or row, text like `ADeals1` is a typo, not a far-off cell.
    guard target.resolvesToRange, target.endCol < 16_384, target.endRow < 1_048_576,
      let index = workbook.sheets.firstIndex(where: {
        $0.name.caseInsensitiveCompare(target.sheetName) == .orderedSame
      }),
      !workbook.sheets[index].isHidden
    else { return false }
    revealDefinedName(target)
    return true
  }

  /// Selects the table with this name, on whichever visible sheet holds it.
  private func revealTable(named name: String) -> Bool {
    for (index, sheet) in workbook.sheets.enumerated() where !sheet.isHidden {
      guard
        let table = sheet.fileExtras.tables.first(where: {
          XLSXCodec.tableName($0.xml)?.caseInsensitiveCompare(name) == .orderedSame
        })
      else { continue }
      commitEditIfNeeded()
      if index != workbook.activeSheetIndex { selectSheet(at: index) }
      selectRange(from: table.range.start, to: table.range.end)
      scrollRequestToken &+= 1
      return true
    }
    return false
  }

  /// Text the name box shows: the active cell, or the selected range.
  var nameBoxText: String {
    let range = selectionRange
    return range.isSingleCell ? selection.a1 : range.a1Label
  }
}
