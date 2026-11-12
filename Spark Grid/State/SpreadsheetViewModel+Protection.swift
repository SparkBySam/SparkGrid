import Foundation
import SparkGridCore

/// Sheet ▸ Protect Sheet and Format ▸ Locked. A protected sheet refuses changes to locked cells,
/// to its rows and columns, and to formatting, as other spreadsheet apps' protection does.
extension SpreadsheetViewModel {
  var isSheetProtected: Bool { SheetProtection.isOn(activeSheet.fileExtras.protectionXML) }

  var sheetProtectionHasPassword: Bool {
    SheetProtection.hasPassword(activeSheet.fileExtras.protectionXML)
  }

  static let protectedCellMessage =
    "The cell is on a protected sheet. To change it, choose Sheet > Unprotect Sheet."
  static let protectedSheetMessage =
    "The sheet is protected. To change its rows, columns or formatting, choose Sheet > Unprotect Sheet."

  /// False, with a message for the window to show, when protection stops a change.
  /// `structural` changes (rows, columns, sorting, formatting) are refused outright; content
  /// changes only where a cell is locked.
  func protectionAllows(
    _ ranges: [CellRange], structural: Bool = false,
    permission: SheetProtection.Permission? = nil
  ) -> Bool {
    guard isSheetProtected else { return true }
    // The protection the file carries can allow this kind of change, as "allow sorting" does.
    if let permission,
      SheetProtection.allows(permission, in: activeSheet.fileExtras.protectionXML)
    {
      return true
    }
    if !structural {
      var checked = 0
      var allUnlocked = true
      outer: for range in ranges {
        for address in range.allAddresses() {
          checked += 1
          if checked > 200_000 || activeSheet.cell(at: address).format?.locked ?? true {
            allUnlocked = false
            break outer
          }
        }
      }
      if allUnlocked { return true }
    }
    protectionNotice = structural ? Self.protectedSheetMessage : Self.protectedCellMessage
    return false
  }

  /// What an engine command would change, for the protection check. Nil lets it through.
  func protectionCheck(for id: String, _ arguments: [String: String]) -> (
    ranges: [CellRange], structural: Bool, permission: SheetProtection.Permission?
  )? {
    guard isSheetProtected else { return nil }
    if let sheet = arguments["sheet"],
      sheet.caseInsensitiveCompare(activeSheet.name) != .orderedSame
    {
      return nil
    }
    switch id {
    case "cell.set":
      guard let a = arguments["address"].flatMap(A1Reference.parseAddress) else { return nil }
      let address = CellAddress(row: a.row, col: a.col)
      return ([CellRange(start: address, end: address)], false, nil)
    case "edit.paste":
      guard let a = arguments["anchor"].flatMap(A1Reference.parseAddress),
        let text = arguments["text"]
      else { return nil }
      let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
      let width =
        lines.map { $0.split(separator: "\t", omittingEmptySubsequences: false).count }
        .max() ?? 1
      return (
        [
          CellRange(
            start: CellAddress(row: a.row, col: a.col),
            end: CellAddress(row: a.row + max(lines.count, 1) - 1, col: a.col + max(width, 1) - 1))
        ], false, nil
      )
    case "edit.fill":
      guard let source = arguments["source"].flatMap(A1Reference.parseRange),
        let end = arguments["end"].flatMap(A1Reference.parseAddress)
      else { return nil }
      return (
        [
          CellRange(
            start: CellAddress(row: source.0.row, col: source.0.col),
            end: CellAddress(row: end.row, col: end.col))
        ], false, nil
      )
    case "data.sort": return ([], true, .sort)
    case "sheet.insertRows": return ([], true, .insertRows)
    case "sheet.deleteRows": return ([], true, .deleteRows)
    case "sheet.insertColumns": return ([], true, .insertColumns)
    case "sheet.deleteColumns": return ([], true, .deleteColumns)
    default:
      return nil
    }
  }

  /// Turns protection on, with a password when one is given, allowing `allowing`.
  func protectSheet(password: String?, allowing: Set<SheetProtection.Permission> = []) {
    updateFileExtras(actionName: "Protect Sheet") { extras in
      extras.protectionXML = SheetProtection.element(password: password, allowing: allowing)
    }
  }

  /// Turns protection off when the password fits. False when it does not.
  @discardableResult
  func unprotectSheet(password: String = "") -> Bool {
    let xml = activeSheet.fileExtras.protectionXML
    guard SheetProtection.verify(password, against: xml) else { return false }
    updateFileExtras(actionName: "Unprotect Sheet") { $0.protectionXML = nil }
    return true
  }

  /// Format ▸ Locked: whether the selection is locked. Nil when it is mixed.
  var selectionLocked: Bool? {
    var seen: Bool?
    var count = 0
    for range in selectionRanges.isEmpty ? [selectionRange] : selectionRanges {
      for address in range.allAddresses() {
        count += 1
        if count > 10_000 { return seen }
        let locked = activeSheet.cell(at: address).format?.locked ?? true
        if let previous = seen, previous != locked { return nil }
        seen = locked
      }
    }
    return seen ?? true
  }

  func setSelectionLocked(_ locked: Bool) {
    commitEditIfNeeded()
    applyFormat(
      toRanges: selectionRanges.isEmpty ? [selectionRange] : selectionRanges,
      actionName: locked ? "Lock Cells" : "Unlock Cells"
    ) { _, format in
      format.locked = locked
    }
  }
}
