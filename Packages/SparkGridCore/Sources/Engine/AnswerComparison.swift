import Calc
import Formula
import Foundation
import GridCore
import Model

/// Compares calculated formula results with saved caches or an external answer file.
public enum AnswerValues {
  /// True when two calculated results are the same value.
  /// Booleans match 1 and 0. Numbers match within a tiny relative tolerance.
  /// Errors match on the code the cell shows, so `#VALUE!` covers both value errors.
  public static func same(_ lhs: CellValue, _ rhs: CellValue) -> Bool {
    switch (lhs, rhs) {
    case (.blank, .blank):
      return true
    case (.blank, .string(let text)), (.string(let text), .blank):
      return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    case (.string(let left), .string(let right)):
      return left == right
    case (.bool(let left), .bool(let right)):
      return left == right
    case (.bool(let flag), .number(let number)):
      return number == (flag ? 1 : 0)
    case (.number(let number), .bool(let flag)):
      return number == (flag ? 1 : 0)
    case (.number(let left), .number(let right)):
      if left == right { return true }
      let scale = max(abs(left), abs(right), 1)
      return abs(left - right) <= scale * 1e-9
    case (.error(let left), .error(let right)):
      return left.displayCode == right.displayCode
    default:
      return false
    }
  }

  /// Token written by the ledger generator: `n:18`, `s:text`, `b:TRUE`, `e:#N/A`, or `blank`.
  public static func parseToken(_ token: String) -> CellValue? {
    if token == "blank" { return .blank }
    if token.hasPrefix("n:") {
      guard let number = Double(String(token.dropFirst(2))) else { return nil }
      return .number(number)
    }
    if token.hasPrefix("s:") {
      return .string(String(token.dropFirst(2)))
    }
    if token.hasPrefix("b:") {
      switch String(token.dropFirst(2)).uppercased() {
      case "TRUE": return .bool(true)
      case "FALSE": return .bool(false)
      default: return nil
      }
    }
    if token.hasPrefix("e:") {
      guard let error = FormulaError(displayCode: String(token.dropFirst(2))) else { return nil }
      return .error(error)
    }
    return nil
  }
}

public struct AnswerMismatch: Equatable, Sendable {
  public var key: String
  public var expected: String
  public var actual: String

  public init(key: String, expected: String, actual: String) {
    self.key = key
    self.expected = expected
    self.actual = actual
  }
}

public struct AnswerPathResult: Equatable, Sendable {
  public var name: String
  public var checked: Int
  public var mismatches: [AnswerMismatch]
  /// Sheets that received a scripted edit. Zero on the paths that do not edit.
  public var editedSheets: Int

  public init(name: String, checked: Int, mismatches: [AnswerMismatch], editedSheets: Int = 0) {
    self.name = name
    self.checked = checked
    self.mismatches = mismatches
    self.editedSheets = editedSheets
  }
}

public enum AnswerComparison {
  /// Fixed seed for the shuffled display path. The walk uses this generator, not the clock.
  public static let displayShuffleSeed: UInt64 = 1

  /// Drops imported formula caches so the next calculation cannot reuse them.
  public static func clearingFormulaCaches(_ workbook: Workbook) -> Workbook {
    var copy = workbook
    for sheetIndex in copy.sheets.indices {
      var cells = copy.sheets[sheetIndex].cells
      var changed = false
      for (address, cell) in cells {
        guard FormulaSyntax.isFormula(cell.raw) else { continue }
        guard cell.importedFormulaResult != nil || cell.importedFormulaValueType != nil else {
          continue
        }
        var next = cell
        next.importedFormulaResult = nil
        next.importedFormulaValueType = nil
        cells[address] = next
        changed = true
      }
      if changed {
        copy.sheets[sheetIndex].cells = cells
        copy.sheets[sheetIndex].rebuildFormulaIngestIndex()
      }
    }
    return copy
  }

  /// Saved `<v>` values for formula cells, keyed `Sheet!A1`.
  public static func savedFormulaResults(in workbook: Workbook) -> [String: CellValue] {
    var saved: [String: CellValue] = [:]
    for sheet in workbook.sheets {
      for (address, cell) in sheet.cells {
        guard FormulaSyntax.isFormula(cell.raw), let cached = cell.cachedFormulaValue else {
          continue
        }
        saved[cellKey(sheet: sheet.name, address: address)] = cached
      }
    }
    return saved
  }

  /// Full recalculation. The grid does not call this on open or while painting.
  public static func calculatedFormulaResults(in workbook: Workbook) -> [String: CellValue] {
    let engine = FormulaEngine()
    engine.recalculateEntireWorkbook(workbook)
    var results: [String: CellValue] = [:]
    for sheet in workbook.sheets {
      let stored = engine.formulaResults(on: sheet)
      for (address, cell) in sheet.cells where FormulaSyntax.isFormula(cell.raw) {
        let key = cellKey(sheet: sheet.name, address: address)
        results[key] = stored[address] ?? .blank
      }
    }
    return results
  }

  public static func cellKey(sheet: String, address: CellAddress) -> String {
    "\(sheet)!\(address.a1)"
  }

  /// Saved results against full recalculation only.
  /// The corpus check uses `comparePaths`, which also walks the display path.
  public static func compareSavedResults(in workbook: Workbook, exempt: Set<String> = []) -> (
    checked: Int, mismatches: [AnswerMismatch]
  ) {
    let expected = savedFormulaResults(in: workbook)
    let cleared = clearingFormulaCaches(workbook)
    let calculated = calculatedFormulaResults(in: cleared)
    return alignedMismatches(expected: expected, actual: calculated, exempt: exempt)
  }

  /// Saved results on the four paths the corpus gate requires.
  /// Paint order and the shuffled order call `sheetDisplayValue`.
  /// The edit path does that again after `cell.set` and the cross-sheet catch-up.
  /// Full recalculation stays as its own path.
  /// `editSheetNames` are the sheets the edit path changes, then restores.
  public static func comparePaths(
    in workbook: Workbook,
    editSheetNames: [String],
    exempt: Set<String> = []
  ) -> [AnswerPathResult] {
    let expected = savedFormulaResults(in: workbook)
    let cleared = clearingFormulaCaches(workbook)
    let paint = displayResults(in: cleared, order: .paint)
    let shuffled = displayResults(in: cleared, order: .shuffled(seed: displayShuffleSeed))
    let edited = displayResultsAfterEdits(in: cleared, sheetNames: editSheetNames)
    let full = calculatedFormulaResults(in: cleared)
    return [
      pathResult(name: "paint", expected: expected, actual: paint, exempt: exempt),
      pathResult(name: "shuffled", expected: expected, actual: shuffled, exempt: exempt),
      pathResult(
        name: "edits",
        expected: expected,
        actual: edited.values,
        exempt: exempt,
        editedSheets: edited.editedSheets
      ),
      pathResult(name: "full", expected: expected, actual: full, exempt: exempt),
    ]
  }

  private enum DisplayOrder {
    case paint
    case shuffled(seed: UInt64)
  }

  private struct FormulaVisit {
    var sheetIndex: Int
    var address: CellAddress
  }

  private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
      state &+= 0x9E37_79B9_7F4A_7C15
      var mixed = state
      mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
      mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
      return mixed ^ (mixed >> 31)
    }
  }

  private static func displayResults(in workbook: Workbook, order: DisplayOrder) -> [String:
    CellValue]
  {
    var book = workbook
    if !book.sheets.isEmpty {
      book.activeSheetIndex = 0
    }
    let engine = FormulaEngine()
    engine.rebuild(workbook: book, recalculate: false)
    return readDisplayValues(engine: engine, book: book, order: order)
  }

  /// Sets a literal, restores it, and rewrites the first formula to itself.
  /// Each step goes through `cell.set` and then the cross-sheet catch-up.
  /// Restoring the literal keeps a correct engine on the saved results.
  private static func displayResultsAfterEdits(
    in workbook: Workbook,
    sheetNames: [String]
  ) -> (values: [String: CellValue], editedSheets: Int) {
    var book = workbook
    if !book.sheets.isEmpty {
      book.activeSheetIndex = 0
    }
    let engine = FormulaEngine()
    engine.rebuild(workbook: book, recalculate: false)
    engine.prepareDependencyGraph()
    let session = WorkbookSession()
    var editedSheets = 0
    for name in sheetNames {
      guard
        let index = book.sheets.firstIndex(where: {
          $0.name.caseInsensitiveCompare(name) == .orderedSame
        })
      else { continue }
      book.activeSheetIndex = index
      engine.activateSheet(book)
      let sheet = book.sheets[index]
      var didEdit = false
      if let address = firstFormulaAddress(on: sheet) {
        let raw = sheet.cell(at: address).raw
        if applyCellSet(
          engine: engine, session: session, book: &book, sheetName: sheet.name, address: address,
          raw: raw)
        {
          didEdit = true
        }
      }
      if let address = firstLiteralAddress(on: book.sheets[index]) {
        let original = book.sheets[index].cell(at: address).raw
        let temporary = original.trimmingCharacters(in: .whitespacesAndNewlines) == "0" ? "1" : "0"
        if applyCellSet(
          engine: engine, session: session, book: &book, sheetName: sheet.name, address: address,
          raw: temporary)
        {
          didEdit = true
          _ = applyCellSet(
            engine: engine, session: session, book: &book, sheetName: sheet.name, address: address,
            raw: original)
        }
      }
      if didEdit {
        editedSheets += 1
      }
    }
    engine.adoptWorkbook(book)
    let values = readDisplayValues(engine: engine, book: book, order: .paint)
    return (values, editedSheets)
  }

  private static func applyCellSet(
    engine: FormulaEngine,
    session: WorkbookSession,
    book: inout Workbook,
    sheetName: String,
    address: CellAddress,
    raw: String
  ) -> Bool {
    let outcome = session.apply(
      id: "cell.set",
      arguments: [
        "sheet": sheetName,
        "address": address.a1,
        "raw": raw,
      ],
      to: &book
    )
    guard outcome.ok else { return false }
    engine.adoptWorkbook(book)
    let change = session.lastChange
    guard book.sheets.indices.contains(book.activeSheetIndex) else { return false }
    engine.cellsDidChange(change.addresses, sheet: book.sheets[book.activeSheetIndex])
    engine.finishPendingCrossSheet()
    return true
  }

  private static func firstFormulaAddress(on sheet: Sheet) -> CellAddress? {
    sheet.cells.keys.sorted().first { address in
      FormulaSyntax.isFormula(sheet.cell(at: address).raw)
    }
  }

  private static func firstLiteralAddress(on sheet: Sheet) -> CellAddress? {
    sheet.cells.keys.sorted().first { address in
      !FormulaSyntax.isFormula(sheet.cell(at: address).raw)
    }
  }

  private static func readDisplayValues(
    engine: FormulaEngine,
    book: Workbook,
    order: DisplayOrder
  ) -> [String: CellValue] {
    var book = book
    let visits = formulaVisits(in: book, order: order)
    var results: [String: CellValue] = [:]
    results.reserveCapacity(visits.count)
    var activeIndex = book.activeSheetIndex
    for visit in visits {
      if visit.sheetIndex != activeIndex {
        book.activeSheetIndex = visit.sheetIndex
        engine.activateSheet(book)
        activeIndex = visit.sheetIndex
      }
      let sheet = book.sheets[visit.sheetIndex]
      let value = engine.sheetDisplayValue(at: visit.address, sheet: sheet)
      results[cellKey(sheet: sheet.name, address: visit.address)] = value
    }
    return results
  }

  private static func formulaVisits(in workbook: Workbook, order: DisplayOrder) -> [FormulaVisit] {
    var visits: [FormulaVisit] = []
    for (sheetIndex, sheet) in workbook.sheets.enumerated() {
      let addresses = sheet.cells.keys.filter { address in
        FormulaSyntax.isFormula(sheet.cell(at: address).raw)
      }.sorted()
      visits.reserveCapacity(visits.count + addresses.count)
      for address in addresses {
        visits.append(FormulaVisit(sheetIndex: sheetIndex, address: address))
      }
    }
    if case .shuffled(let seed) = order {
      return shuffled(visits, seed: seed)
    }
    return visits
  }

  private static func shuffled(_ visits: [FormulaVisit], seed: UInt64) -> [FormulaVisit] {
    var items = visits
    guard items.count > 1 else { return items }
    var generator = SplitMix64(state: seed)
    for index in stride(from: items.count - 1, through: 1, by: -1) {
      let swap = Int(generator.next() % UInt64(index + 1))
      items.swapAt(index, swap)
    }
    return items
  }

  private static func pathResult(
    name: String,
    expected: [String: CellValue],
    actual: [String: CellValue],
    exempt: Set<String>,
    editedSheets: Int = 0
  ) -> AnswerPathResult {
    let result = alignedMismatches(expected: expected, actual: actual, exempt: exempt)
    return AnswerPathResult(
      name: name,
      checked: result.checked,
      mismatches: result.mismatches,
      editedSheets: editedSheets
    )
  }

  private static func alignedMismatches(
    expected: [String: CellValue],
    actual: [String: CellValue],
    exempt: Set<String>
  ) -> (checked: Int, mismatches: [AnswerMismatch]) {
    var aligned: [String: CellValue] = [:]
    aligned.reserveCapacity(expected.count)
    for key in expected.keys {
      aligned[key] = actual[key] ?? .blank
    }
    return mismatches(expected: expected, actual: aligned, exempt: exempt)
  }

  public static func mismatches(
    expected: [String: CellValue],
    actual: [String: CellValue],
    exempt: Set<String> = []
  ) -> (checked: Int, mismatches: [AnswerMismatch]) {
    var keys = Set(expected.keys)
    keys.formUnion(actual.keys)
    var failures: [AnswerMismatch] = []
    for key in keys.sorted() {
      if exempt.contains(key.lowercased()) { continue }
      let want = expected[key] ?? .blank
      let got = actual[key] ?? .blank
      if AnswerValues.same(want, got) { continue }
      failures.append(
        AnswerMismatch(key: key, expected: want.displayString, actual: got.displayString)
      )
    }
    return (keys.count, failures)
  }
}
