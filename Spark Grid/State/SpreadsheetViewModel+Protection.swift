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
    // A locked range refuses any change to its cells, protected sheet or not.
    if let lock = rangeLock(touching: ranges) {
      protectionNotice =
        "\(lock.name) is locked. To change it, choose Sheet > Remove Range Lock."
      return false
    }
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
      var needsPassword: EditableRange?
      outer: for range in ranges {
        for address in range.allAddresses() {
          checked += 1
          if checked > 200_000 {
            allUnlocked = false
            break outer
          }
          if activeSheet.cell(at: address).format?.locked == false { continue }
          // Allow Edit Ranges: open without a password, or once its password is given.
          if let editable = activeSheet.fileExtras.editableRanges.first(where: {
            $0.covers(address)
          }) {
            if isOpen(editable) { continue }
            needsPassword = needsPassword ?? editable
          }
          allUnlocked = false
          break outer
        }
      }
      if allUnlocked { return true }
      if let needsPassword {
        protectionNotice =
          "\(needsPassword.name) needs its password. Choose Sheet > Unlock Edit Range."
        return false
      }
    }
    protectionNotice = structural ? Self.protectedSheetMessage : Self.protectedCellMessage
    return false
  }

  /// What an engine command would change, for the protection check. Nil lets it through.
  func protectionCheck(for id: String, _ arguments: [String: String]) -> (
    ranges: [CellRange], structural: Bool, permission: SheetProtection.Permission?
  )? {
    // Range locks apply on any sheet; the rest only when the sheet is protected.
    guard isSheetProtected || !activeSheet.fileExtras.rangeLocks.isEmpty else { return nil }
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
    case "data.sort":
      let range = arguments["range"].flatMap(A1Reference.parseRange).map {
        CellRange(start: $0.0, end: $0.1)
      }
      return (range.map { [$0] } ?? [], true, .sort)
    case "sheet.insertRows": return ([], true, .insertRows)
    case "sheet.deleteRows":
      return (deletedSpan(arguments, axis: .row), true, .deleteRows)
    case "sheet.insertColumns": return ([], true, .insertColumns)
    case "sheet.deleteColumns":
      return (deletedSpan(arguments, axis: .column), true, .deleteColumns)
    default:
      return nil
    }
  }

  /// Turns protection on, with a password when one is given, allowing `allowing`.
  func protectSheet(password: String?, allowing: Set<SheetProtection.Permission> = []) {
    updateFileExtrasClearingUndo { extras in
      extras.protectionXML = SheetProtection.element(password: password, allowing: allowing)
    }
  }

  /// Turns protection off when the password fits. False when it does not.
  @discardableResult
  func unprotectSheet(password: String = "") -> Bool {
    let xml = activeSheet.fileExtras.protectionXML
    guard SheetProtection.verify(password, against: xml) else { return false }
    updateFileExtrasClearingUndo { $0.protectionXML = nil }
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

// MARK: - Range locks and editable ranges

extension SpreadsheetViewModel {
  enum SpanAxis { case row, column }

  /// The rows or columns a delete takes, across the whole sheet, so a lock inside refuses it.
  func deletedSpan(_ arguments: [String: String], axis: SpanAxis) -> [CellRange] {
    guard let index = arguments["index"].flatMap({ Int($0) }), index >= 0 else { return [] }
    let count = max(1, arguments["count"].flatMap { Int($0) } ?? 1)
    switch axis {
    case .row:
      return [
        CellRange(
          start: CellAddress(row: index, col: 0),
          end: CellAddress(row: index + count - 1, col: 16_383))
      ]
    case .column:
      return [
        CellRange(
          start: CellAddress(row: 0, col: index),
          end: CellAddress(row: 1_048_575, col: index + count - 1))
      ]
    }
  }

  /// The first range lock on the active sheet that `ranges` touch.
  func rangeLock(touching ranges: [CellRange]) -> RangeLock? {
    let locks = activeSheet.fileExtras.rangeLocks
    guard !locks.isEmpty else { return nil }
    for range in ranges {
      if let lock = locks.first(where: { $0.intersects(range) }) { return lock }
    }
    return nil
  }

  private var selectedRanges: [CellRange] {
    selectionRanges.isEmpty ? [selectionRange] : selectionRanges
  }

  /// Range locks the selection touches.
  var selectedRangeLocks: [RangeLock] {
    activeSheet.fileExtras.rangeLocks.filter { lock in
      selectedRanges.contains(where: lock.intersects)
    }
  }

  var canLockRange: Bool { !selectedRanges.isEmpty && selectedRangeLocks.isEmpty }

  /// Sheet ▸ Lock Range: the selection is locked on its own, with an optional password. Undo
  /// is emptied, as protecting a sheet empties it, so Undo cannot take the lock off.
  func lockSelectedRange(name: String, password: String?) {
    let ranges = selectedRanges
    guard !ranges.isEmpty else { return }
    let label = name.trimmingCharacters(in: .whitespaces)
    let lock = RangeLock(
      name: label.isEmpty ? ranges.map(\.a1Label).joined(separator: ", ") : label,
      ranges: ranges,
      passwordHash: password.flatMap { $0.isEmpty ? nil : SheetProtection.legacyHash($0) })
    updateFileExtrasClearingUndo { $0.rangeLocks.append(lock) }
  }

  /// Sheet ▸ Remove Range Lock. False when the password does not fit.
  @discardableResult
  func removeRangeLock(_ id: UUID, password: String = "") -> Bool {
    guard let lock = activeSheet.fileExtras.rangeLocks.first(where: { $0.id == id }) else {
      return false
    }
    if let hash = lock.passwordHash, SheetProtection.legacyHash(password) != hash { return false }
    updateFileExtrasClearingUndo { $0.rangeLocks.removeAll { $0.id == id } }
    return true
  }

  // MARK: Allow Edit Ranges

  private func editableKey(_ range: EditableRange) -> String {
    "\(activeSheet.id.uuidString)|\(range.name.lowercased())"
  }

  /// Open for editing on a protected sheet: no password, or its password given this session.
  func isOpen(_ range: EditableRange) -> Bool {
    !range.hasPassword || unlockedEditableRanges.contains(editableKey(range))
  }

  /// Editable ranges can be set up only while the sheet is unprotected, as in other apps.
  var canEditEditableRanges: Bool { !isSheetProtected }

  /// Adds the selection as an editable range, with an optional password.
  func addEditableRange(name: String, password: String?) {
    guard canEditEditableRanges else { return }
    let ranges = selectedRanges
    guard !ranges.isEmpty else { return }
    var label = name.trimmingCharacters(in: .whitespaces)
    let existing = Set(activeSheet.fileExtras.editableRanges.map { $0.name.lowercased() })
    if label.isEmpty || existing.contains(label.lowercased()) {
      var number = activeSheet.fileExtras.editableRanges.count + 1
      while existing.contains("range\(number)") { number += 1 }
      label = label.isEmpty ? "Range\(number)" : "\(label) \(number)"
    }
    let attributes =
      password.flatMap { $0.isEmpty ? nil : #"password="\#(SheetProtection.legacyHash($0))""# }
      ?? ""
    let range = EditableRange(name: label, ranges: ranges, passwordAttributes: attributes)
    updateFileExtras(actionName: "Allow Edit Range") { $0.editableRanges.append(range) }
  }

  func removeEditableRange(named name: String) {
    guard canEditEditableRanges else { return }
    updateFileExtras(actionName: "Remove Edit Range") { extras in
      extras.editableRanges.removeAll { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }
  }

  /// Editable ranges with a password that the selection touches and that are still closed.
  var closedEditableRangesAtSelection: [EditableRange] {
    activeSheet.fileExtras.editableRanges.filter { range in
      !isOpen(range)
        && selectedRanges.contains { selection in
          range.ranges.contains { RangeLock(name: "", ranges: [$0]).intersects(selection) }
        }
    }
  }

  /// Sheet ▸ Unlock Edit Range: opens the range for editing until the file is closed.
  @discardableResult
  func unlockEditableRange(named name: String, password: String) -> Bool {
    guard
      let range = activeSheet.fileExtras.editableRanges.first(where: {
        $0.name.caseInsensitiveCompare(name) == .orderedSame
      }), SheetProtection.verify(password, against: range.xml)
    else { return false }
    unlockedEditableRanges.insert(editableKey(range))
    protectionNotice = nil
    return true
  }
}
