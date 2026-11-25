import AppKit
import Foundation
import SparkGridCore

// AppleScript: the commands in `SparkGrid.sdef`. Each works on an open workbook window, the
// front one unless the script names another with `in workbook "Budget.xlsx"`.

/// Shared by the commands: finding the workbook, and reporting what went wrong.
@MainActor
enum WorkbookScripting {
  /// A workbook's name as a script names it: its file name, the Numbers document it came from,
  /// or Untitled.
  static func name(of store: SpreadsheetDocumentStore) -> String {
    store.fileURL?.lastPathComponent ?? store.importedName ?? "Untitled"
  }

  /// The workbook `name` names, with or without its extension, or the front one.
  static func store(named name: String?) throws -> SpreadsheetDocumentStore {
    let open = WorkbookWindows.shared.allStores
    guard let name = name?.trimmingCharacters(in: .whitespaces), !name.isEmpty else {
      guard let front = WorkbookWindows.shared.frontStore else {
        throw ScriptFailure("No workbook is open.")
      }
      return front
    }
    let found = open.first { store in
      let full = Self.name(of: store)
      let bare = (full as NSString).deletingPathExtension
      return full.caseInsensitiveCompare(name) == .orderedSame
        || bare.caseInsensitiveCompare(name) == .orderedSame
    }
    guard let found else { throw ScriptFailure("No open workbook is named “\(name)”.") }
    return found
  }

  /// The window's view model: what the grid shows, with every edit in it.
  static func viewModel(of store: SpreadsheetDocumentStore) throws -> SpreadsheetViewModel {
    guard !store.showsStartScreen else {
      throw ScriptFailure("The window shows the start screen, not a workbook.")
    }
    return store.attachedViewModel()
  }

  /// Runs `body` with `sheet` showing, then shows the sheet that was showing before.
  static func onSheet<T>(
    _ sheet: Int, of viewModel: SpreadsheetViewModel, _ body: () throws -> T
  ) rethrows -> T {
    let before = viewModel.workbook.activeSheetIndex
    if sheet != before { viewModel.selectSheet(at: sheet) }
    defer { if sheet != before { viewModel.selectSheet(at: before) } }
    return try body()
  }
}

struct ScriptFailure: Error {
  let message: String
  init(_ message: String) { self.message = message }
}

/// Base for the commands: runs on the main actor and turns a failure into a script error.
class SparkGridScriptCommand: NSScriptCommand {
  override func performDefaultImplementation() -> Any? {
    MainActor.assumeIsolated {
      do {
        return try run()
      } catch let failure as ScriptFailure {
        scriptErrorNumber = errOSAGeneralError
        scriptErrorString = failure.message
      } catch {
        scriptErrorNumber = errOSAGeneralError
        scriptErrorString = error.localizedDescription
      }
      return nil
    }
  }

  @MainActor
  func run() throws -> Any? { nil }

  func text(_ key: String) -> String? {
    evaluatedArguments?[key] as? String
  }

  /// A four-character enumerator code, such as `SGpl`.
  func code(_ key: String) -> FourCharCode? {
    (evaluatedArguments?[key] as? NSNumber).map { FourCharCode(truncatingIfNeeded: $0.intValue) }
  }

  static func fourCharCode(_ text: String) -> FourCharCode {
    text.utf8.reduce(0) { ($0 << 8) | FourCharCode($1) }
  }
}

/// `open`. With a scripting dictionary, Cocoa takes the open-documents event for the command
/// it names, Finder's opens included; this sends the files where Finder's went before.
@objc(SGOpenCommand)
final class SGOpenCommand: SparkGridScriptCommand {
  @MainActor
  override func run() throws -> Any? {
    let urls: [URL]
    switch directParameter {
    case let url as URL: urls = [url]
    case let list as [URL]: urls = list
    case let list as [Any]: urls = list.compactMap { $0 as? URL }
    default: urls = []
    }
    guard !urls.isEmpty else { throw ScriptFailure("Give a file to open.") }
    guard let delegate = SparkGridAppDelegate.current else {
      throw ScriptFailure("Spark Grid is still starting.")
    }
    delegate.application(NSApp, open: urls)
    return nil
  }
}

@objc(SGWorkbookNamesCommand)
final class SGWorkbookNamesCommand: SparkGridScriptCommand {
  @MainActor
  override func run() throws -> Any? {
    WorkbookWindows.shared.allStores.filter { !$0.showsStartScreen }.map(WorkbookScripting.name)
  }
}

@objc(SGCellValueCommand)
final class SGCellValueCommand: SparkGridScriptCommand {
  @MainActor
  override func run() throws -> Any? {
    guard let cell = directParameter as? String else {
      throw ScriptFailure("Name a cell, such as B2.")
    }
    let store = try WorkbookScripting.store(named: text("workbook"))
    let viewModel = try WorkbookScripting.viewModel(of: store)
    let place = try WorkbookShortcuts.locate(cell, in: viewModel.workbook)
    let plain = code("reading") == Self.fourCharCode("SGpl")
    return WorkbookScripting.onSheet(place.sheet, of: viewModel) {
      plain
        ? WorkbookShortcuts.plainText(viewModel.displayValue(at: place.address))
        : viewModel.displayString(at: place.address)
    }
  }
}

@objc(SGPutValueCommand)
final class SGPutValueCommand: SparkGridScriptCommand {
  @MainActor
  override func run() throws -> Any? {
    guard let value = directParameter as? String else {
      throw ScriptFailure("Give the value to put, such as 1200 or =SUM(B2:B9).")
    }
    guard let cell = text("cell") else { throw ScriptFailure("Name a cell, such as B2.") }
    let store = try WorkbookScripting.store(named: text("workbook"))
    let viewModel = try WorkbookScripting.viewModel(of: store)
    let place = try WorkbookShortcuts.locate(cell, in: viewModel.workbook)
    WorkbookScripting.onSheet(place.sheet, of: viewModel) {
      viewModel.setCellValue(value, at: place.address)
    }
    store.documentDidChange()
    return nil
  }
}

@objc(SGSaveWorkbookCommand)
final class SGSaveWorkbookCommand: SparkGridScriptCommand {
  @MainActor
  override func run() throws -> Any? {
    let store = try WorkbookScripting.store(named: text("workbook"))
    guard store.fileURL != nil else {
      throw ScriptFailure(
        "“\(WorkbookScripting.name(of: store))” has no file yet. Save it once in Spark Grid.")
    }
    try store.save()
    return nil
  }
}

@objc(SGExportWorkbookCommand)
final class SGExportWorkbookCommand: SparkGridScriptCommand {
  @MainActor
  override func run() throws -> Any? {
    guard let destination = evaluatedArguments?["destination"] as? URL else {
      throw ScriptFailure("Give a file to write, such as POSIX file \"/Users/me/Report.pdf\".")
    }
    let store = try WorkbookScripting.store(named: text("workbook"))
    let viewModel = try WorkbookScripting.viewModel(of: store)
    let sheet = try WorkbookShortcuts.sheetIndex(text("sheet"), in: viewModel.workbook)
    let title = (WorkbookScripting.name(of: store) as NSString).deletingPathExtension
    let pdf = code("format") != Self.fourCharCode("SGcv")
    let everySheet = (evaluatedArguments?["everySheet"] as? Bool) ?? false
    let data = try WorkbookScripting.onSheet(sheet, of: viewModel) {
      pdf
        ? try WorkbookShortcuts.pdfData(viewModel, title: title, everySheet: everySheet)
        : Data(WorkbookShortcuts.csvText(viewModel).utf8)
    }
    let accessing = destination.startAccessingSecurityScopedResource()
    defer { if accessing { destination.stopAccessingSecurityScopedResource() } }
    do {
      try data.write(to: destination, options: .atomic)
    } catch {
      throw ScriptFailure(
        "Spark Grid couldn’t write \(destination.path): \(error.localizedDescription)")
    }
    return nil
  }
}

// MARK: - Ranges and sheets (for AI connectors such as spark-grid-mcp, and for scripts)

extension WorkbookScripting {
  /// The most cells one range command reads or writes, so a script cannot ask for the whole grid.
  static let maxCells = 200_000

  /// The sheet and range `text` names: `A1:C9` on the sheet showing, or `Sales!A1:C9`. One cell
  /// is a range of one.
  static func locateRange(_ text: String, in workbook: Workbook) throws -> (
    sheet: Int, range: CellRange
  ) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let expr = try? FormulaParser.parse("=" + trimmed) else {
      throw ScriptFailure("“\(text)” isn’t a range. Use one such as A1:C9, or Sales!A1:C9.")
    }
    let start: FormulaRef
    let end: FormulaRef
    switch expr {
    case .range(let a, let b):
      start = a
      end = b
    case .cellRef(let a):
      start = a
      end = a
    default:
      throw ScriptFailure("“\(text)” isn’t a range. Use one such as A1:C9, or Sales!A1:C9.")
    }
    guard !start.isRowOpen, !start.isColOpen, !end.isRowOpen, !end.isColOpen else {
      throw ScriptFailure("Give the range’s rows and columns, such as A1:C9 rather than A:C.")
    }
    let sheet = try WorkbookShortcuts.sheetIndex(start.sheet ?? end.sheet, in: workbook)
    let range = CellRange(
      start: CellAddress(row: min(start.row, end.row), col: min(start.col, end.col)),
      end: CellAddress(row: max(start.row, end.row), col: max(start.col, end.col)))
    let cells = (range.end.row - range.start.row + 1) * (range.end.col - range.start.col + 1)
    guard cells <= maxCells else {
      throw ScriptFailure("That range has \(cells) cells; ask for \(maxCells) or fewer at a time.")
    }
    return (sheet, range)
  }

  /// The smallest range holding every cell with something in it, or nil on an empty sheet.
  static func usedRange(of sheet: Sheet) -> CellRange? {
    var minRow = Int.max
    var minCol = Int.max
    var maxRow = -1
    var maxCol = -1
    for (address, cell) in sheet.cells where cell.hasContent {
      minRow = min(minRow, address.row)
      minCol = min(minCol, address.col)
      maxRow = max(maxRow, address.row)
      maxCol = max(maxCol, address.col)
    }
    guard maxRow >= 0 else { return nil }
    return CellRange(
      start: CellAddress(row: minRow, col: minCol), end: CellAddress(row: maxRow, col: maxCol))
  }

  /// Rows of text as an AppleScript list of lists. Cocoa scripting does not turn nested Swift
  /// arrays into one, so the result is built by hand.
  static func listOfRows(_ rows: [[String]]) -> NSAppleEventDescriptor {
    let list = NSAppleEventDescriptor.list()
    for (r, row) in rows.enumerated() {
      let inner = NSAppleEventDescriptor.list()
      for (c, value) in row.enumerated() {
        inner.insert(NSAppleEventDescriptor(string: value), at: c + 1)
      }
      list.insert(inner, at: r + 1)
    }
    return list
  }

  /// Rows of text from a script's list of lists (or one list, as one row). Inner lists can
  /// arrive as unconverted Apple event lists, so those are read item by item.
  static func rows(from value: Any?) throws -> [[String]] {
    func items(_ value: Any) -> [Any]? {
      if let list = value as? [Any] { return list }
      if let descriptor = value as? NSAppleEventDescriptor,
        descriptor.descriptorType == typeAEList
      {
        guard descriptor.numberOfItems > 0 else { return [] }
        return (1...descriptor.numberOfItems).compactMap { descriptor.atIndex($0) }
      }
      return nil
    }
    func text(_ item: Any) -> String {
      if let string = item as? String { return string }
      if let number = item as? NSNumber { return number.stringValue }
      if let descriptor = item as? NSAppleEventDescriptor {
        return descriptor.stringValue ?? ""
      }
      return "\(item)"
    }
    guard let value, let list = items(value), !list.isEmpty else {
      throw ScriptFailure(
        "Give the values as a list of rows, such as {{\"Name\", \"Total\"}, {\"Ann\", 120}}.")
    }
    if list.allSatisfy({ items($0) != nil }) {
      return list.map { (items($0) ?? []).map(text) }
    }
    return [list.map(text)]
  }
}

@objc(SGSheetNamesCommand)
final class SGSheetNamesCommand: SparkGridScriptCommand {
  @MainActor
  override func run() throws -> Any? {
    let store = try WorkbookScripting.store(named: text("workbook"))
    let viewModel = try WorkbookScripting.viewModel(of: store)
    return viewModel.workbook.sheets.map(\.name)
  }
}

@objc(SGRangeValuesCommand)
final class SGRangeValuesCommand: SparkGridScriptCommand {
  @MainActor
  override func run() throws -> Any? {
    guard let rangeText = directParameter as? String else {
      throw ScriptFailure("Name a range, such as A1:C9.")
    }
    let store = try WorkbookScripting.store(named: text("workbook"))
    let viewModel = try WorkbookScripting.viewModel(of: store)
    let place = try WorkbookScripting.locateRange(rangeText, in: viewModel.workbook)
    let plain = code("reading") == Self.fourCharCode("SGpl")
    let rows = WorkbookScripting.onSheet(place.sheet, of: viewModel) {
      (place.range.start.row...place.range.end.row).map { row in
        (place.range.start.col...place.range.end.col).map { col in
          let address = CellAddress(row: row, col: col)
          return plain
            ? WorkbookShortcuts.plainText(viewModel.displayValue(at: address))
            : viewModel.displayString(at: address)
        }
      }
    }
    return WorkbookScripting.listOfRows(rows)
  }
}

@objc(SGRangeFormulasCommand)
final class SGRangeFormulasCommand: SparkGridScriptCommand {
  @MainActor
  override func run() throws -> Any? {
    guard let rangeText = directParameter as? String else {
      throw ScriptFailure("Name a range, such as A1:C9.")
    }
    let store = try WorkbookScripting.store(named: text("workbook"))
    let viewModel = try WorkbookScripting.viewModel(of: store)
    let place = try WorkbookScripting.locateRange(rangeText, in: viewModel.workbook)
    let sheet = viewModel.workbook.sheets[place.sheet]
    return WorkbookScripting.listOfRows(
      (place.range.start.row...place.range.end.row).map { row in
        (place.range.start.col...place.range.end.col).map { col in
          sheet.cell(at: CellAddress(row: row, col: col)).editableText
        }
      })
  }
}

@objc(SGPutValuesCommand)
final class SGPutValuesCommand: SparkGridScriptCommand {
  @MainActor
  override func run() throws -> Any? {
    let rows = try WorkbookScripting.rows(from: directParameter)
    guard let cellText = text("cell") else {
      throw ScriptFailure("Name the first cell, such as B2.")
    }
    let store = try WorkbookScripting.store(named: text("workbook"))
    let viewModel = try WorkbookScripting.viewModel(of: store)
    let place = try WorkbookShortcuts.locate(cellText, in: viewModel.workbook)
    let count = rows.reduce(0) { $0 + $1.count }
    guard count <= WorkbookScripting.maxCells else {
      throw ScriptFailure(
        "That is \(count) cells; put \(WorkbookScripting.maxCells) or fewer at a time.")
    }
    WorkbookScripting.onSheet(place.sheet, of: viewModel) {
      viewModel.pasteGrid(
        rows, at: place.address, adjustFormulas: false, actionName: "Put Values", readsAsTyped: true
      )
    }
    store.documentDidChange()
    return nil
  }
}

@objc(SGUsedRangeCommand)
final class SGUsedRangeCommand: SparkGridScriptCommand {
  @MainActor
  override func run() throws -> Any? {
    let store = try WorkbookScripting.store(named: text("workbook"))
    let viewModel = try WorkbookScripting.viewModel(of: store)
    let index = try WorkbookShortcuts.sheetIndex(text("sheet"), in: viewModel.workbook)
    guard let range = WorkbookScripting.usedRange(of: viewModel.workbook.sheets[index]) else {
      return ""
    }
    return range.a1Label
  }
}

@objc(SGAddSheetCommand)
final class SGAddSheetCommand: SparkGridScriptCommand {
  @MainActor
  override func run() throws -> Any? {
    let store = try WorkbookScripting.store(named: text("workbook"))
    let viewModel = try WorkbookScripting.viewModel(of: store)
    let before = viewModel.workbook.sheets.count
    viewModel.addSheet()
    guard viewModel.workbook.sheets.count > before else {
      throw ScriptFailure("Spark Grid couldn’t add a sheet to this workbook.")
    }
    let index = viewModel.workbook.activeSheetIndex
    if let wanted = (directParameter as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
      !wanted.isEmpty
    {
      viewModel.renameSheet(at: index, to: wanted)
    }
    store.documentDidChange()
    return viewModel.workbook.sheets[index].name
  }
}
