import Calc
import CoreGraphics
import Formula
import Foundation
import GridCore
import Model
import NumberFormat

/// One engine command. Programmatic `run` never opens a dialog.
public struct EngineCommand: Equatable, Sendable {
  public var id: String
  public var label: String
  public var shortcut: String
  public var parameters: String

  public init(id: String, label: String, shortcut: String, parameters: String) {
    self.id = id
    self.label = label
    self.shortcut = shortcut
    self.parameters = parameters
  }
}

public struct CommandOutcome: Equatable, Sendable {
  public var ok: Bool
  public var message: String

  public init(ok: Bool, message: String) {
    self.ok = ok
    self.message = message
  }
}

/// What the last successful command changed, so a caller can recalculate.
public struct WorkbookChange: Equatable, Sendable {
  public var structural: Bool
  public var addresses: [CellAddress]
  public var sheetName: String

  public init(structural: Bool, addresses: [CellAddress], sheetName: String) {
    self.structural = structural
    self.addresses = addresses
    self.sheetName = sheetName
  }
}

/// Workbook edits the fuzzer and the command-line tool can run without AppKit.
public final class WorkbookSession {
  public private(set) var workbook: Workbook
  public private(set) var lastChange: WorkbookChange
  /// After a `data.sort`, the source row of each data row, top to bottom.
  /// Passing it back reversed through `order` puts the rows where they were.
  public private(set) var lastSortOrder: [Int] = []
  private var undoStack: [Workbook] = []
  private var redoStack: [Workbook] = []

  public static let commands: [EngineCommand] = [
    EngineCommand(
      id: "cell.set",
      label: "Set Cell",
      shortcut: "",
      parameters: "sheet (optional), address (A1), raw"
    ),
    EngineCommand(
      id: "edit.paste",
      label: "Paste",
      shortcut: "⌘V",
      parameters:
        "sheet (optional), anchor (A1), text (tab-separated rows), rowDelta, colDelta"
    ),
    EngineCommand(
      id: "edit.fill",
      label: "Fill",
      shortcut: "",
      parameters: "sheet (optional), source (A1:B2), end (C10)"
    ),
    EngineCommand(
      id: "sheet.insertRows",
      label: "Insert Rows",
      shortcut: "",
      parameters: "sheet (optional), index (0-based), count"
    ),
    EngineCommand(
      id: "sheet.deleteRows",
      label: "Delete Rows",
      shortcut: "",
      parameters: "sheet (optional), index (0-based), count"
    ),
    EngineCommand(
      id: "sheet.insertColumns",
      label: "Insert Columns",
      shortcut: "",
      parameters: "sheet (optional), index (0-based), count"
    ),
    EngineCommand(
      id: "sheet.deleteColumns",
      label: "Delete Columns",
      shortcut: "",
      parameters: "sheet (optional), index (0-based), count"
    ),
    EngineCommand(
      id: "data.sort",
      label: "Sort",
      shortcut: "",
      parameters:
        "sheet (optional), range (A1:B4), column (0-based), ascending, header, then (optional: column:asc or column:desc, comma-separated), order (optional: source rows, comma-separated)"
    ),
    EngineCommand(
      id: "edit.undo",
      label: "Undo",
      shortcut: "⌘Z",
      parameters: "none"
    ),
    EngineCommand(
      id: "edit.redo",
      label: "Redo",
      shortcut: "⇧⌘Z",
      parameters: "none"
    ),
    EngineCommand(
      id: "sheet.add",
      label: "Add Sheet",
      shortcut: "",
      parameters: "name (optional)"
    ),
    EngineCommand(
      id: "sheet.rename",
      label: "Rename Sheet",
      shortcut: "",
      parameters: "sheet (optional), name"
    ),
    EngineCommand(
      id: "sheet.delete",
      label: "Delete Sheet",
      shortcut: "",
      parameters: "sheet (optional)"
    ),
  ]

  public init(workbook: Workbook = Workbook()) {
    self.workbook = workbook
    let name = workbook.sheets.first?.name ?? "Sheet1"
    self.lastChange = WorkbookChange(structural: true, addresses: [], sheetName: name)
  }

  /// Skips the main-actor deinit hop that aborts in
  /// `TaskLocal.StopLookupScope` on macOS 15.4–15.7 and 26.0–26.3.
  nonisolated deinit {}

  public var canUndo: Bool { !undoStack.isEmpty }
  public var canRedo: Bool { !redoStack.isEmpty }

  public func isEnabled(_ id: String) -> Bool {
    switch id {
    case "edit.undo":
      return canUndo
    case "edit.redo":
      return canRedo
    case "sheet.delete":
      return workbook.sheets.count > 1 && known(id)
    default:
      return known(id)
    }
  }

  /// Missing parameters are an error. Nothing here presents a panel.
  public func run(id: String, arguments: [String: String] = [:]) -> CommandOutcome {
    switch id {
    case "edit.undo":
      guard undo() else { return CommandOutcome(ok: false, message: "Nothing to undo") }
      return CommandOutcome(ok: true, message: "")
    case "edit.redo":
      guard redo() else { return CommandOutcome(ok: false, message: "Nothing to redo") }
      return CommandOutcome(ok: true, message: "")
    default:
      break
    }
    guard known(id) else { return CommandOutcome(ok: false, message: "Unknown command \(id)") }
    var copy = workbook
    let applied = perform(id, arguments: arguments, to: &copy, sortDisplay: nil)
    guard applied.ok else { return CommandOutcome(ok: false, message: applied.message) }
    undoStack.append(workbook)
    redoStack.removeAll()
    workbook = copy
    lastChange = applied.change
    return CommandOutcome(ok: true, message: "")
  }

  /// Applies one command to `workbook` without storing an undo snapshot.
  /// `edit.undo` and `edit.redo` stay on `undo()` and `redo()`.
  /// Pass `sortDisplay` when the caller already has calculated text, so sort does not recalculate.
  public func apply(
    id: String,
    arguments: [String: String] = [:],
    to workbook: inout Workbook,
    sortDisplay: ((Sheet, CellAddress) -> (key: String, number: Double?))? = nil
  ) -> CommandOutcome {
    switch id {
    case "edit.undo", "edit.redo":
      return CommandOutcome(ok: false, message: "\(id) uses undo() and redo() on the session")
    default:
      break
    }
    guard known(id) else { return CommandOutcome(ok: false, message: "Unknown command \(id)") }
    let applied = perform(id, arguments: arguments, to: &workbook, sortDisplay: sortDisplay)
    guard applied.ok else { return CommandOutcome(ok: false, message: applied.message) }
    lastChange = applied.change
    return CommandOutcome(ok: true, message: "")
  }

  @discardableResult
  public func undo() -> Bool {
    guard let previous = undoStack.popLast() else { return false }
    redoStack.append(workbook)
    workbook = previous
    lastChange = WorkbookChange(
      structural: true,
      addresses: [],
      sheetName: workbook.activeSheet.name
    )
    return true
  }

  @discardableResult
  public func redo() -> Bool {
    guard let next = redoStack.popLast() else { return false }
    undoStack.append(workbook)
    workbook = next
    lastChange = WorkbookChange(
      structural: true,
      addresses: [],
      sheetName: workbook.activeSheet.name
    )
    return true
  }

  private func known(_ id: String) -> Bool {
    Self.commands.contains { $0.id == id }
  }

  private struct Applied {
    var ok: Bool
    var message: String
    var change: WorkbookChange
  }

  private func perform(
    _ id: String,
    arguments: [String: String],
    to workbook: inout Workbook,
    sortDisplay: ((Sheet, CellAddress) -> (key: String, number: Double?))?
  ) -> Applied {
    switch id {
    case "cell.set":
      return setCell(arguments, workbook: &workbook)
    case "edit.paste":
      return paste(arguments, workbook: &workbook)
    case "edit.fill":
      return fill(arguments, workbook: &workbook)
    case "sheet.insertRows":
      return mutateStructure(arguments, workbook: &workbook, axis: .row, inserting: true)
    case "sheet.deleteRows":
      return mutateStructure(arguments, workbook: &workbook, axis: .row, inserting: false)
    case "sheet.insertColumns":
      return mutateStructure(arguments, workbook: &workbook, axis: .column, inserting: true)
    case "sheet.deleteColumns":
      return mutateStructure(arguments, workbook: &workbook, axis: .column, inserting: false)
    case "data.sort":
      return sort(arguments, workbook: &workbook, sortDisplay: sortDisplay)
    case "sheet.add":
      return addSheet(arguments, workbook: &workbook)
    case "sheet.rename":
      return renameSheet(arguments, workbook: &workbook)
    case "sheet.delete":
      return deleteSheet(arguments, workbook: &workbook)
    default:
      return Applied(ok: false, message: "Unknown command \(id)", change: emptyChange(workbook))
    }
  }

  private func setCell(_ arguments: [String: String], workbook: inout Workbook) -> Applied {
    guard let addressText = arguments["address"], let address = parseAddress(addressText) else {
      return Applied(ok: false, message: "cell.set needs address", change: emptyChange(workbook))
    }
    guard let raw = arguments["raw"] else {
      return Applied(ok: false, message: "cell.set needs raw", change: emptyChange(workbook))
    }
    guard raw.utf8.count <= 1_000_000 else {
      return Applied(ok: false, message: "cell.set raw is too long", change: emptyChange(workbook))
    }
    guard address.row >= 0, address.col >= 0, address.row < InputBounds.maxStructureCount,
      address.col < InputBounds.maxStructureCount
    else {
      return Applied(
        ok: false, message: "cell.set address is out of range", change: emptyChange(workbook))
    }
    guard let index = sheetIndex(arguments["sheet"], workbook: workbook) else {
      return Applied(
        ok: false, message: "cell.set sheet was not found", change: emptyChange(workbook))
    }
    var sheet = workbook.sheets[index]
    var cell = sheet.cell(at: address)
    cell.raw = raw
    cell.importedFormulaResult = nil
    cell.importedFormulaValueType = nil
    applyPercentLiteralIfNeeded(to: &cell)
    applyDateLiteralIfNeeded(to: &cell)
    sheet.setCell(cell, at: address)
    workbook.sheets[index] = sheet
    return Applied(
      ok: true,
      message: "",
      change: WorkbookChange(structural: false, addresses: [address], sheetName: sheet.name)
    )
  }

  private func paste(_ arguments: [String: String], workbook: inout Workbook) -> Applied {
    guard let anchorText = arguments["anchor"], let anchor = parseAddress(anchorText) else {
      return Applied(ok: false, message: "edit.paste needs anchor", change: emptyChange(workbook))
    }
    guard let text = arguments["text"] else {
      return Applied(ok: false, message: "edit.paste needs text", change: emptyChange(workbook))
    }
    guard text.utf8.count <= InputBounds.maxMaterializedCells else {
      return Applied(
        ok: false, message: "edit.paste text is too large", change: emptyChange(workbook))
    }
    let rows = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map {
      String($0).split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
    }
    let rowCount = rows.count
    let colCount = rows.map(\.count).max() ?? 0
    guard InputBounds.materializedCount(rows: rowCount, cols: colCount) != nil else {
      return Applied(ok: false, message: "edit.paste is too large", change: emptyChange(workbook))
    }
    guard anchor.row <= Int.max - rowCount, anchor.col <= Int.max - max(colCount, 1) else {
      return Applied(
        ok: false, message: "edit.paste origin overflows", change: emptyChange(workbook))
    }
    guard let index = sheetIndex(arguments["sheet"], workbook: workbook) else {
      return Applied(
        ok: false, message: "edit.paste sheet was not found", change: emptyChange(workbook))
    }
    let rowDelta = intArgument(arguments, "rowDelta") ?? 0
    let colDelta = intArgument(arguments, "colDelta") ?? 0
    var sheet = workbook.sheets[index]
    var addresses: [CellAddress] = []
    for (rowOffset, fields) in rows.enumerated() {
      for (colOffset, field) in fields.enumerated() {
        let address = CellAddress(row: anchor.row + rowOffset, col: anchor.col + colOffset)
        guard address.row < InputBounds.maxStructureCount,
          address.col < InputBounds.maxStructureCount
        else {
          return Applied(
            ok: false, message: "edit.paste lands past the grid cap", change: emptyChange(workbook))
        }
        let raw =
          (rowDelta == 0 && colDelta == 0)
          ? field
          : FormulaRewriter.adjust(field, rowDelta: rowDelta, colDelta: colDelta)
        var cell = sheet.cell(at: address)
        cell.raw = raw
        cell.importedFormulaResult = nil
        cell.importedFormulaValueType = nil
        applyPercentLiteralIfNeeded(to: &cell)
        sheet.setCell(cell, at: address)
        addresses.append(address)
      }
    }
    workbook.sheets[index] = sheet
    return Applied(
      ok: true,
      message: "",
      change: WorkbookChange(structural: false, addresses: addresses, sheetName: sheet.name)
    )
  }

  private func fill(_ arguments: [String: String], workbook: inout Workbook) -> Applied {
    guard let sourceText = arguments["source"], let source = parseRange(sourceText) else {
      return Applied(ok: false, message: "edit.fill needs source", change: emptyChange(workbook))
    }
    guard let endText = arguments["end"], let end = parseAddress(endText) else {
      return Applied(ok: false, message: "edit.fill needs end", change: emptyChange(workbook))
    }
    let sourceRange = CellRange(start: source.start, end: source.end).normalized
    let fillRange = CellRange(
      start: CellAddress(row: sourceRange.minRow, col: sourceRange.minCol),
      end: end
    ).normalized
    let srcRowCount = InputBounds.span(from: sourceRange.minRow, through: sourceRange.maxRow)
    let srcColCount = InputBounds.span(from: sourceRange.minCol, through: sourceRange.maxCol)
    let fillRows = InputBounds.span(from: fillRange.minRow, through: fillRange.maxRow)
    let fillCols = InputBounds.span(from: fillRange.minCol, through: fillRange.maxCol)
    guard srcRowCount > 0, srcColCount > 0,
      InputBounds.materializedCount(rows: fillRows, cols: fillCols) != nil
    else {
      return Applied(ok: false, message: "edit.fill is too large", change: emptyChange(workbook))
    }
    guard let index = sheetIndex(arguments["sheet"], workbook: workbook) else {
      return Applied(
        ok: false, message: "edit.fill sheet was not found", change: emptyChange(workbook))
    }
    var sheet = workbook.sheets[index]
    var addresses: [CellAddress] = []
    // A fill down continues each source column as a series; a fill across, each source row.
    // `series` "0" copies instead.
    let continues = arguments["series"] != "0"
    let fillsDown = fillRows > srcRowCount && fillCols == srcColCount
    let fillsAcross = fillCols > srcColCount && fillRows == srcRowCount
    var seriesByLine: [Int: FillSeries] = [:]
    if continues && (fillsDown || fillsAcross) {
      let lines =
        fillsDown
        ? sourceRange.minCol...sourceRange.maxCol : sourceRange.minRow...sourceRange.maxRow
      for line in lines {
        let cells =
          fillsDown
          ? (sourceRange.minRow...sourceRange.maxRow).map {
            sheet.cell(at: CellAddress(row: $0, col: line))
          }
          : (sourceRange.minCol...sourceRange.maxCol).map {
            sheet.cell(at: CellAddress(row: line, col: $0))
          }
        if let series = FillSeries.plan(cells) {
          seriesByLine[line] = series
        }
      }
    }
    for row in fillRange.minRow...fillRange.maxRow {
      for col in fillRange.minCol...fillRange.maxCol {
        if row >= sourceRange.minRow && row <= sourceRange.maxRow && col >= sourceRange.minCol
          && col <= sourceRange.maxCol
        {
          continue
        }
        let srcRow = sourceRange.minRow + positiveMod(row - sourceRange.minRow, srcRowCount)
        let srcCol = sourceRange.minCol + positiveMod(col - sourceRange.minCol, srcColCount)
        let srcAddress = CellAddress(row: srcRow, col: srcCol)
        let destAddress = CellAddress(row: row, col: col)
        let sourceCell = sheet.cell(at: srcAddress)
        let value: String
        if fillsDown, let series = seriesByLine[col] {
          value = series.value(at: row - sourceRange.minRow)
        } else if fillsAcross, let series = seriesByLine[row] {
          value = series.value(at: col - sourceRange.minCol)
        } else {
          value = FormulaRewriter.adjust(
            sourceCell.raw,
            rowDelta: destAddress.row - srcAddress.row,
            colDelta: destAddress.col - srcAddress.col
          )
        }
        var cell = sheet.cell(at: destAddress)
        cell.raw = value
        cell.importedFormulaResult = nil
        cell.importedFormulaValueType = nil
        if sourceCell.format == nil {
          applyPercentLiteralIfNeeded(to: &cell)
        }
        if let format = sourceCell.format {
          cell.format = format
        }
        sheet.setCell(cell, at: destAddress)
        addresses.append(destAddress)
      }
    }
    workbook.sheets[index] = sheet
    return Applied(
      ok: true,
      message: "",
      change: WorkbookChange(structural: false, addresses: addresses, sheetName: sheet.name)
    )
  }

  private func mutateStructure(
    _ arguments: [String: String],
    workbook: inout Workbook,
    axis: FormulaRewriter.Axis,
    inserting: Bool
  ) -> Applied {
    guard let index = intArgument(arguments, "index"), index >= 0,
      index < InputBounds.maxStructureCount
    else {
      return Applied(
        ok: false, message: "structure command needs index", change: emptyChange(workbook))
    }
    let requested = intArgument(arguments, "count") ?? 1
    let count = InputBounds.cappedCount(requested)
    guard count > 0, index <= Int.max - count else {
      return Applied(
        ok: false, message: "structure count is out of range", change: emptyChange(workbook))
    }
    guard let sheetIndex = sheetIndex(arguments["sheet"], workbook: workbook) else {
      return Applied(
        ok: false, message: "structure sheet was not found", change: emptyChange(workbook))
    }
    let sheetName = workbook.sheets[sheetIndex].name
    let change: FormulaRewriter.StructureChange =
      inserting ? .insert(at: index, count: count) : .delete(at: index, count: count)
    rewriteFormulas(in: &workbook, mutatedSheetName: sheetName, axis: axis, change: change)
    shiftNamedRanges(in: &workbook, mutatedSheetName: sheetName, axis: axis, change: change)
    switch (axis, inserting) {
    case (.row, true):
      SheetStructureMutation.insertRows(into: &workbook.sheets[sheetIndex], at: index, count: count)
    case (.row, false):
      SheetStructureMutation.deleteRows(in: &workbook.sheets[sheetIndex], at: index, count: count)
    case (.column, true):
      SheetStructureMutation.insertColumns(
        into: &workbook.sheets[sheetIndex], at: index, count: count)
    case (.column, false):
      SheetStructureMutation.deleteColumns(
        in: &workbook.sheets[sheetIndex], at: index, count: count)
    }
    return Applied(
      ok: true,
      message: "",
      change: WorkbookChange(structural: true, addresses: [], sheetName: sheetName)
    )
  }

  private func addSheet(_ arguments: [String: String], workbook: inout Workbook) -> Applied {
    let preferred = arguments["name"] ?? ""
    guard preferred.utf8.count <= 200 else {
      return Applied(
        ok: false, message: "sheet.add name is too long", change: emptyChange(workbook))
    }
    let name = uniqueSheetName(preferred.isEmpty ? "Sheet" : preferred, workbook: workbook)
    workbook.sheets.append(Sheet(name: name))
    return Applied(
      ok: true,
      message: "",
      change: WorkbookChange(structural: true, addresses: [], sheetName: name)
    )
  }

  private func renameSheet(_ arguments: [String: String], workbook: inout Workbook) -> Applied {
    guard let newName = arguments["name"]?.trimmingCharacters(in: .whitespacesAndNewlines),
      !newName.isEmpty, newName.utf8.count <= 200
    else {
      return Applied(ok: false, message: "sheet.rename needs name", change: emptyChange(workbook))
    }
    guard let index = sheetIndex(arguments["sheet"], workbook: workbook) else {
      return Applied(
        ok: false, message: "sheet.rename sheet was not found", change: emptyChange(workbook))
    }
    let oldName = workbook.sheets[index].name
    if oldName.caseInsensitiveCompare(newName) != .orderedSame,
      sheetIndex(newName, workbook: workbook) != nil
    {
      return Applied(
        ok: false, message: "sheet.rename name is already used", change: emptyChange(workbook))
    }
    workbook.sheets[index].name = newName
    for key in Array(workbook.namedRanges.keys) {
      guard var named = workbook.namedRanges[key] else { continue }
      guard named.sheetName.caseInsensitiveCompare(oldName) == .orderedSame else { continue }
      named.sheetName = newName
      workbook.namedRanges[key] = named
    }
    return Applied(
      ok: true,
      message: "",
      change: WorkbookChange(structural: true, addresses: [], sheetName: newName)
    )
  }

  private func deleteSheet(_ arguments: [String: String], workbook: inout Workbook) -> Applied {
    guard workbook.sheets.count > 1 else {
      return Applied(
        ok: false, message: "sheet.delete cannot remove the last sheet",
        change: emptyChange(workbook))
    }
    guard let index = sheetIndex(arguments["sheet"], workbook: workbook) else {
      return Applied(
        ok: false, message: "sheet.delete sheet was not found", change: emptyChange(workbook))
    }
    workbook.sheets.remove(at: index)
    if workbook.activeSheetIndex >= workbook.sheets.count {
      workbook.activeSheetIndex = workbook.sheets.count - 1
    } else if index < workbook.activeSheetIndex {
      workbook.activeSheetIndex -= 1
    }
    let remaining = workbook.activeSheet.name
    return Applied(
      ok: true,
      message: "",
      change: WorkbookChange(structural: true, addresses: [], sheetName: remaining)
    )
  }

  private func sort(
    _ arguments: [String: String],
    workbook: inout Workbook,
    sortDisplay: ((Sheet, CellAddress) -> (key: String, number: Double?))?
  ) -> Applied {
    guard let rangeText = arguments["range"], let range = parseRange(rangeText) else {
      return Applied(ok: false, message: "data.sort needs range", change: emptyChange(workbook))
    }
    guard let column = intArgument(arguments, "column") else {
      return Applied(ok: false, message: "data.sort needs column", change: emptyChange(workbook))
    }
    let ascending = (arguments["ascending"] ?? "true").lowercased() != "false"
    let hasHeader = (arguments["header"] ?? "false").lowercased() == "true"
    let n = range.normalized
    // More sort levels: `then` is "column:asc,column:desc", applied in turn to break ties.
    var levels: [(column: Int, ascending: Bool)] = [(column, ascending)]
    for item in (arguments["then"] ?? "").split(separator: ",") {
      let parts = item.split(separator: ":").map { $0.trimmingCharacters(in: .whitespaces) }
      guard let col = parts.first.flatMap({ Int($0) }) else {
        return Applied(
          ok: false, message: "data.sort then needs column:asc or column:desc",
          change: emptyChange(workbook))
      }
      levels.append((col, parts.count < 2 || parts[1].lowercased() != "desc"))
    }
    guard levels.count <= 64, levels.allSatisfy({ $0.column >= n.minCol && $0.column <= n.maxCol })
    else {
      return Applied(
        ok: false, message: "data.sort column is outside the range", change: emptyChange(workbook))
    }
    guard let sheetIndex = sheetIndex(arguments["sheet"], workbook: workbook) else {
      return Applied(
        ok: false, message: "data.sort sheet was not found", change: emptyChange(workbook))
    }
    let headerOffset = hasHeader ? 1 : 0
    let firstDataRow = n.minRow + headerOffset
    guard firstDataRow <= n.maxRow else {
      return Applied(
        ok: false, message: "data.sort range has no data rows", change: emptyChange(workbook))
    }
    let source: Sheet
    let display: (CellAddress) -> (key: String, number: Double?)
    if let sortDisplay {
      source = workbook.sheets[sheetIndex]
      display = { address in sortDisplay(source, address) }
    } else {
      var probe = workbook
      probe.activeSheetIndex = sheetIndex
      let engine = FormulaEngine()
      engine.rebuild(workbook: probe, recalculate: true)
      source = probe.activeSheet
      display = { address in
        let value = engine.displayValue(at: address, sheet: source)
        let key = value.displayString
        return (key, self.sortNumber(for: key, value: value))
      }
    }

    struct SortKey {
      var text: String
      var number: Double?
    }

    struct RowPack {
      var rowIndex: Int
      var cells: [Int: Cell]
      var height: CGFloat?
      /// One key per sort level.
      var keys: [SortKey]
    }

    var packs: [RowPack] = []
    for row in firstDataRow...n.maxRow {
      var cells: [Int: Cell] = [:]
      for col in n.minCol...n.maxCol {
        let address = CellAddress(row: row, col: col)
        if let cell = source.cells[address] {
          cells[col] = cell
        }
      }
      let keys = levels.map { level -> SortKey in
        let shown = display(CellAddress(row: row, col: level.column))
        return SortKey(text: shown.key, number: shown.number)
      }
      packs.append(
        RowPack(
          rowIndex: row,
          cells: cells,
          height: source.rowHeights[row],
          keys: keys
        )
      )
    }
    func compare(_ lhs: SortKey, _ rhs: SortKey) -> ComparisonResult {
      if let left = lhs.number, let right = rhs.number {
        return left == right
          ? .orderedSame : (left < right ? .orderedAscending : .orderedDescending)
      } else if lhs.number != nil {
        return .orderedAscending
      } else if rhs.number != nil {
        return .orderedDescending
      }
      return lhs.text.localizedStandardCompare(rhs.text)
    }
    func sortsBefore(_ lhs: RowPack, _ rhs: RowPack) -> Bool {
      for (index, level) in levels.enumerated() {
        guard lhs.keys.indices.contains(index), rhs.keys.indices.contains(index) else { break }
        let cmp = compare(lhs.keys[index], rhs.keys[index])
        if cmp == .orderedSame { continue }
        return level.ascending ? cmp == .orderedAscending : cmp == .orderedDescending
      }
      return lhs.rowIndex < rhs.rowIndex
    }

    if let orderText = arguments["order"] {
      // An explicit order places each listed source row in turn. It must name every data row once.
      let order = orderText.split(separator: ",").compactMap {
        Int($0.trimmingCharacters(in: .whitespaces))
      }
      let byRow = Dictionary(uniqueKeysWithValues: packs.map { ($0.rowIndex, $0) })
      guard order.count == packs.count, Set(order).count == order.count,
        order.allSatisfy({ byRow[$0] != nil })
      else {
        return Applied(
          ok: false, message: "data.sort order must list each data row once",
          change: emptyChange(workbook))
      }
      packs = order.compactMap { byRow[$0] }
    } else {
      packs.sort(by: sortsBefore)
    }
    lastSortOrder = packs.map(\.rowIndex)

    var sheet = source
    for row in firstDataRow...n.maxRow {
      for col in n.minCol...n.maxCol {
        sheet.cells.removeValue(forKey: CellAddress(row: row, col: col))
      }
      sheet.rowHeights.removeValue(forKey: row)
    }
    for (offset, pack) in packs.enumerated() {
      let newRow = firstDataRow + offset
      let rowDelta = newRow - pack.rowIndex
      for (col, cell) in pack.cells {
        var next = cell
        if rowDelta != 0 {
          next.raw = FormulaRewriter.adjust(cell.raw, rowDelta: rowDelta, colDelta: 0)
        }
        sheet.cells[CellAddress(row: newRow, col: col)] = next
      }
      if let height = pack.height {
        sheet.rowHeights[newRow] = height
      }
    }
    var rowMap: [Int: Int] = [:]
    for (offset, pack) in packs.enumerated() {
      rowMap[pack.rowIndex] = firstDataRow + offset
    }
    func remapFullyContained(_ range: CellRange) -> CellRange? {
      let bounds = range.normalized
      guard bounds.minCol >= n.minCol, bounds.maxCol <= n.maxCol, bounds.minRow >= firstDataRow,
        bounds.maxRow <= n.maxRow
      else { return nil }
      var mappedRows: [Int] = []
      mappedRows.reserveCapacity(bounds.maxRow - bounds.minRow + 1)
      for row in bounds.minRow...bounds.maxRow {
        guard let mapped = rowMap[row] else { return nil }
        mappedRows.append(mapped)
      }
      guard let newMin = mappedRows.min(), let newMax = mappedRows.max() else { return nil }
      return CellRange(
        start: CellAddress(row: newMin, col: bounds.minCol),
        end: CellAddress(row: newMax, col: bounds.maxCol)
      )
    }
    sheet.mergedRanges = sheet.mergedRanges.map { remapFullyContained($0) ?? $0 }
    sheet.conditionalFormats = sheet.conditionalFormats.map { rule in
      var next = rule
      if let remapped = remapFullyContained(rule.range) {
        next.range = remapped
      }
      return next
    }
    sheet.charts = sheet.charts.map { chart in
      var next = chart
      if let remapped = remapFullyContained(chart.dataRange) {
        next.dataRange = remapped
      }
      return next
    }
    // Comments and links in sorted cells travel with their rows.
    func movedAddress(_ address: CellAddress) -> CellAddress? {
      guard address.col >= n.minCol, address.col <= n.maxCol, let row = rowMap[address.row]
      else { return nil }
      return CellAddress(row: row, col: address.col)
    }
    sheet.fileExtras.comments = sheet.fileExtras.comments.map { comment in
      var next = comment
      if let moved = movedAddress(comment.address) { next.address = moved }
      return next
    }
    sheet.fileExtras.hyperlinks = sheet.fileExtras.hyperlinks.map { link in
      var next = link
      if let moved = remapFullyContained(link.range) { next.range = moved }
      return next
    }
    sheet.recomputePopulatedExtents()
    sheet.rebuildFormulaIngestIndex()
    workbook.sheets[sheetIndex] = sheet
    return Applied(
      ok: true,
      message: "",
      change: WorkbookChange(structural: true, addresses: [], sheetName: sheet.name)
    )
  }

  private func emptyChange(_ workbook: Workbook) -> WorkbookChange {
    WorkbookChange(structural: true, addresses: [], sheetName: workbook.activeSheet.name)
  }

  private func sheetIndex(_ name: String?, workbook: Workbook) -> Int? {
    if let name, !name.isEmpty {
      return workbook.sheets.firstIndex { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }
    let index = workbook.activeSheetIndex
    guard workbook.sheets.indices.contains(index) else { return nil }
    return index
  }

  private func uniqueSheetName(_ preferred: String, workbook: Workbook) -> String {
    if sheetIndex(preferred, workbook: workbook) == nil { return preferred }
    var suffix = 2
    while suffix < 10_000 {
      let candidate = "\(preferred) \(suffix)"
      if sheetIndex(candidate, workbook: workbook) == nil { return candidate }
      suffix += 1
    }
    return "Sheet \(workbook.sheets.count + 1)"
  }

  private func sortNumber(for key: String, value: CellValue) -> Double? {
    if let number = value.asNumber { return number }
    let stripped =
      key
      .replacingOccurrences(of: ",", with: "")
      .replacingOccurrences(of: "%", with: "")
      .replacingOccurrences(of: "$", with: "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return Double(stripped)
  }

  private func applyPercentLiteralIfNeeded(to cell: inout Cell) {
    let trimmed = cell.raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasSuffix("%"), !FormulaSyntax.isFormula(trimmed) else { return }
    let number = String(trimmed.dropLast())
      .trimmingCharacters(in: .whitespaces)
      .replacingOccurrences(of: ",", with: "")
    guard Double(number) != nil else { return }
    var format = cell.format ?? CellFormat()
    guard format.numberFormat == .general else { return }
    format.numberFormat = .percent
    if format.decimalPlaces == nil {
      format.decimalPlaces = 2
    }
    cell.format = format
  }

  /// A typed date such as `2/28/2026` or `2026-02-28` is stored as a date serial with a date
  /// format, as other spreadsheet apps do, so it sorts, sums and filters as a date. A cell that
  /// already has another number format keeps the text as typed.
  private func applyDateLiteralIfNeeded(to cell: inout Cell) {
    let trimmed = cell.raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !FormulaSyntax.isFormula(trimmed), Double(trimmed) == nil,
      let serial = ColumnFilterRules.dateSerial(trimmed), serial >= 1
    else { return }
    var format = cell.format ?? CellFormat()
    guard format.numberFormat == .general || format.numberFormat == .date else { return }
    format.numberFormat = .date
    cell.raw = String(Int(serial))
    cell.format = format
  }

  private func intArgument(_ arguments: [String: String], _ key: String) -> Int? {
    guard let raw = arguments[key] else { return nil }
    return Int(raw)
  }

  private func parseAddress(_ text: String) -> CellAddress? {
    guard let parsed = A1Reference.parseAddress(text) else { return nil }
    return CellAddress(row: parsed.row, col: parsed.col)
  }

  private func parseRange(_ text: String) -> CellRange? {
    let parts = text.split(separator: ":").map(String.init)
    if parts.count == 1, let address = parseAddress(parts[0]) {
      return CellRange(start: address, end: address)
    }
    guard parts.count == 2, let start = parseAddress(parts[0]), let end = parseAddress(parts[1])
    else { return nil }
    return CellRange(start: start, end: end)
  }

  private func positiveMod(_ value: Int, _ modulus: Int) -> Int {
    guard modulus > 0 else { return 0 }
    let remainder = value % modulus
    return remainder >= 0 ? remainder : remainder + modulus
  }

  private func rewriteFormulas(
    in workbook: inout Workbook,
    mutatedSheetName: String,
    axis: FormulaRewriter.Axis,
    change: FormulaRewriter.StructureChange
  ) {
    for sheetIndex in workbook.sheets.indices {
      let sheetName = workbook.sheets[sheetIndex].name
      var cells = workbook.sheets[sheetIndex].cells
      var changed = false
      for (address, cell) in cells where FormulaSyntax.isFormula(cell.raw) {
        let next = FormulaRewriter.shiftForStructure(
          cell.raw,
          formulaSheetName: sheetName,
          mutatedSheetName: mutatedSheetName,
          axis: axis,
          change: change
        )
        if next != cell.raw {
          var updated = cell
          updated.raw = next
          // A moved reference keeps its answer. One that now points at deleted cells does not,
          // so its saved result goes and the file asks to be calculated on open.
          if next.contains("#REF!"), !cell.raw.contains("#REF!") {
            updated.importedFormulaResult = nil
            updated.importedFormulaValueType = nil
          }
          cells[address] = updated
          changed = true
        }
      }
      if changed {
        workbook.sheets[sheetIndex].cells = cells
      }
    }
  }

  private func shiftNamedRanges(
    in workbook: inout Workbook,
    mutatedSheetName: String,
    axis: FormulaRewriter.Axis,
    change: FormulaRewriter.StructureChange
  ) {
    var next: [String: NamedRange] = [:]
    for (key, named) in workbook.namedRanges {
      guard named.resolvesToRange else {
        next[key] = named
        continue
      }
      guard named.sheetName.caseInsensitiveCompare(mutatedSheetName) == .orderedSame else {
        next[key] = named
        continue
      }
      let start = FormulaRef(
        sheet: named.sheetName,
        row: named.startRow,
        col: named.startCol,
        absRow: false,
        absCol: false
      )
      let end = FormulaRef(
        sheet: named.sheetName,
        row: named.endRow,
        col: named.endCol,
        absRow: false,
        absCol: false
      )
      let shifted = FormulaRewriter.shiftForStructure(
        "=\(A1Reference.formatRange(start: start, end: end))",
        formulaSheetName: named.sheetName,
        mutatedSheetName: mutatedSheetName,
        axis: axis,
        change: change
      )
      if shifted == "=#REF!" { continue }
      let body = shifted.hasPrefix("=") ? String(shifted.dropFirst()) : shifted
      guard let (startRef, endRef) = A1Reference.parseFormulaRange(body) else { continue }
      next[key] = NamedRange(
        name: named.name,
        sheetName: named.sheetName,
        range: CellRange(start: startRef.address, end: endRef.address)
      )
    }
    workbook.namedRanges = next
  }
}
