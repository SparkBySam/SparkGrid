import Formula
import Foundation
import Functions
import GridCore
import Model
import NumberFormat

/// Cross-sheet formula updates that run after the viewed sheet has already refreshed.
/// The edit path only schedules this. A sheet opened early is shown first; this pass
/// fills its values afterward.
public nonisolated enum CrossSheetBackground {
  public struct Request: Sendable {
    public var token: UInt64
    public var workbook: Workbook
    public var editedSheetName: String
    public var editedSheet: Sheet
    public var editedAddresses: [CellAddress]
    public var calculatedEdits: [CellAddress: CellValue]
    public var graph: WorkbookDependencyGraph?
    /// Nil updates every affected formula. A name updates that sheet and the
    /// precedents required to do it.
    public var onlySheetName: String?
  }

  public struct Outcome: Sendable {
    public var valuesBySheet: [String: [CellAddress: CellValue]]
  }

  public static func graphInput(for workbook: Workbook) -> WorkbookGraphInput {
    var sheets: [WorkbookGraphInput.Sheet] = []
    var sheetIDsByName: [String: Int] = [:]
    sheets.reserveCapacity(workbook.sheets.count)
    for sheet in workbook.sheets {
      let sheetID = sheets.count
      let key = sheet.name.lowercased()
      if sheetIDsByName[key] == nil {
        sheetIDsByName[key] = sheetID
      }
      var columns: [[WorkbookGraphInput.Cell]] = []
      columns.reserveCapacity(sheet.formulaIngestByColumn.count)
      for column in sheet.formulaIngestByColumn.keys.sorted() {
        let entries = sheet.formulaIngestByColumn[column] ?? []
        var cells: [WorkbookGraphInput.Cell] = []
        cells.reserveCapacity(entries.count)
        for (address, raw) in entries {
          cells.append(WorkbookGraphInput.Cell(row: address.row, col: address.col, raw: raw))
        }
        columns.append(cells)
      }
      sheets.append(
        WorkbookGraphInput.Sheet(
          name: key,
          sheetID: sheetID,
          maxRow: max(0, sheet.effectiveRowCount - 1),
          maxCol: max(0, sheet.effectiveColumnCount - 1),
          columns: columns
        )
      )
    }
    var names: [WorkbookGraphInput.Name] = []
    for named in workbook.namedRanges.values where named.resolvesToRange {
      guard let sheetID = sheetIDsByName[named.sheetName.lowercased()] else { continue }
      names.append(
        WorkbookGraphInput.Name(
          key: named.name.uppercased(),
          sheetID: sheetID,
          minRow: min(named.startRow, named.endRow),
          maxRow: max(named.startRow, named.endRow),
          minCol: min(named.startCol, named.endCol),
          maxCol: max(named.startCol, named.endCol)
        )
      )
    }
    return WorkbookGraphInput(
      sheets: sheets,
      names: names,
      sheetIDsByName: sheetIDsByName,
      fallbackMaxRow: max(0, Workbook.defaultRowCount - 1),
      fallbackMaxCol: max(0, Workbook.defaultColumnCount - 1)
    )
  }

  public static func compute(_ request: Request) -> Outcome {
    var workbook = request.workbook
    if let index = workbook.sheets.firstIndex(where: {
      $0.name.caseInsensitiveCompare(request.editedSheetName) == .orderedSame
    }) {
      workbook.sheets[index] = request.editedSheet
    }
    let graph = request.graph ?? WorkbookDependencyGraph.build(graphInput(for: workbook))
    guard let editedSheetID = graph.sheetID(for: request.editedSheetName) else {
      return Outcome(valuesBySheet: [:])
    }

    var overrides: [FormulaCoord: CellValue] = [:]
    overrides.reserveCapacity(request.calculatedEdits.count)
    for (address, value) in request.calculatedEdits {
      overrides[FormulaCoord(sheetID: editedSheetID, row: address.row, col: address.col)] = value
    }

    var sheetsByID: [Int: Sheet] = [:]
    sheetsByID.reserveCapacity(workbook.sheets.count)
    for sheet in workbook.sheets {
      if let sheetID = graph.sheetID(for: sheet.name) {
        sheetsByID[sheetID] = sheet
      }
    }

    var affected: [FormulaCoord: Int] = [:]
    var seen: Set<FormulaCoord> = []
    var queue: [FormulaCoord] = []
    func enqueue(_ coord: FormulaCoord) {
      if seen.insert(coord).inserted {
        queue.append(coord)
      }
    }
    for address in request.editedAddresses {
      enqueue(FormulaCoord(sheetID: editedSheetID, row: address.row, col: address.col))
    }
    for address in request.calculatedEdits.keys {
      enqueue(FormulaCoord(sheetID: editedSheetID, row: address.row, col: address.col))
    }

    var head = 0
    while head < queue.count {
      let coord = queue[head]
      head += 1
      for formulaID in graph.formulaIDsReading(
        sheetID: coord.sheetID, row: coord.row, col: coord.col)
      {
        guard graph.formulaCoords.indices.contains(formulaID) else { continue }
        let formulaCoord = graph.formulaCoords[formulaID]
        if overrides[formulaCoord] != nil {
          enqueue(formulaCoord)
          continue
        }
        if affected[formulaCoord] == nil {
          affected[formulaCoord] = formulaID
          enqueue(formulaCoord)
        }
      }
    }

    let context = EvaluationContext(
      workbook: workbook,
      graph: graph,
      sheetsByID: sheetsByID,
      overrides: overrides,
      affected: affected
    )
    let limitSheetID = request.onlySheetName.flatMap { graph.sheetID(for: $0) }
    evaluateInOrder(
      context,
      affected: affected,
      graph: graph,
      limitSheetID: request.onlySheetName == nil ? nil : limitSheetID
    )

    return outcome(memo: context.memo, graph: graph)
  }

  /// Every formula, ignoring imported caches. Used when a structural edit made those caches stale.
  public static func calculateAllFormulas(in workbook: Workbook) -> Outcome {
    let graph = WorkbookDependencyGraph.build(graphInput(for: workbook))
    let sheetsByID = sheetsByID(in: workbook, graph: graph)
    var affected: [FormulaCoord: Int] = [:]
    affected.reserveCapacity(graph.formulaCoords.count)
    for formulaID in graph.formulaCoords.indices {
      affected[graph.formulaCoords[formulaID]] = formulaID
    }
    let context = EvaluationContext(
      workbook: workbook,
      graph: graph,
      sheetsByID: sheetsByID,
      overrides: [:],
      affected: affected
    )
    evaluateInOrder(context, affected: affected, graph: graph, limitSheetID: nil)
    return outcome(memo: context.memo, graph: graph)
  }

  /// Formulas that have no cached `<v>` yet. Formulas that already have one stay as stored values.
  public static func calculateFormulasWithoutCaches(in workbook: Workbook) -> Outcome {
    let graph = WorkbookDependencyGraph.build(graphInput(for: workbook))
    let sheetsByID = sheetsByID(in: workbook, graph: graph)
    var affected: [FormulaCoord: Int] = [:]
    for formulaID in graph.formulaCoords.indices {
      let coord = graph.formulaCoords[formulaID]
      guard let sheet = sheetsByID[coord.sheetID] else { continue }
      let cell = sheet.cell(at: CellAddress(row: coord.row, col: coord.col))
      guard FormulaSyntax.isFormula(cell.raw), cell.importedFormulaResult == nil else { continue }
      affected[coord] = formulaID
    }
    guard !affected.isEmpty else { return Outcome(valuesBySheet: [:]) }
    let context = EvaluationContext(
      workbook: workbook,
      graph: graph,
      sheetsByID: sheetsByID,
      overrides: [:],
      affected: affected
    )
    evaluateInOrder(context, affected: affected, graph: graph, limitSheetID: nil)
    return outcome(memo: context.memo, graph: graph)
  }

  /// Precedents first, on an explicit stack. A long chain must not recurse once per link.
  private static func evaluateInOrder(
    _ context: EvaluationContext,
    affected: [FormulaCoord: Int],
    graph: WorkbookDependencyGraph,
    limitSheetID: Int?
  ) {
    let order = formulaIDsInDependencyOrder(affected: affected, graph: graph)
    for formulaID in order {
      guard graph.formulaCoords.indices.contains(formulaID) else { continue }
      let coord = graph.formulaCoords[formulaID]
      if let limitSheetID, coord.sheetID != limitSheetID { continue }
      context.evaluate(formulaID: formulaID, at: coord)
    }
  }

  private static func formulaIDsInDependencyOrder(
    affected: [FormulaCoord: Int],
    graph: WorkbookDependencyGraph
  ) -> [Int] {
    var ordered: [Int] = []
    ordered.reserveCapacity(affected.count)
    var state: [Int: UInt8] = [:]
    state.reserveCapacity(affected.count)
    var stack: [(id: Int, emit: Bool)] = []
    stack.reserveCapacity(affected.count)
    for id in affected.values {
      stack.append((id, false))
      while let frame = stack.popLast() {
        if frame.emit {
          state[frame.id] = 2
          ordered.append(frame.id)
          continue
        }
        if (state[frame.id] ?? 0) != 0 { continue }
        state[frame.id] = 1
        stack.append((frame.id, true))
        guard graph.cellPrecedents.indices.contains(frame.id) else { continue }
        for precedent in graph.cellPrecedents[frame.id] {
          guard let precedentID = affected[precedent] else { continue }
          if state[precedentID] == nil {
            stack.append((precedentID, false))
          }
        }
      }
    }
    return ordered
  }

  private static func sheetsByID(in workbook: Workbook, graph: WorkbookDependencyGraph) -> [Int:
    Sheet]
  {
    var sheetsByID: [Int: Sheet] = [:]
    sheetsByID.reserveCapacity(workbook.sheets.count)
    for sheet in workbook.sheets {
      if let sheetID = graph.sheetID(for: sheet.name) {
        sheetsByID[sheetID] = sheet
      }
    }
    return sheetsByID
  }

  private static func outcome(memo: [FormulaCoord: CellValue], graph: WorkbookDependencyGraph)
    -> Outcome
  {
    var valuesBySheet: [String: [CellAddress: CellValue]] = [:]
    for (coord, value) in memo {
      guard graph.sheetNames.indices.contains(coord.sheetID) else { continue }
      // Written in place. Copying the sheet's dictionary out and back for every value made
      // this quadratic: 105,000 results on one sheet took most of a minute.
      valuesBySheet[graph.sheetNames[coord.sheetID], default: [:]][
        CellAddress(row: coord.row, col: coord.col)] = value
    }
    return Outcome(valuesBySheet: valuesBySheet)
  }
}

private nonisolated final class EvaluationContext {
  let workbook: Workbook
  let graph: WorkbookDependencyGraph
  let sheetsByID: [Int: Sheet]
  let overrides: [FormulaCoord: CellValue]
  let affected: [FormulaCoord: Int]
  var memo: [FormulaCoord: CellValue] = [:]
  var visiting: Set<FormulaCoord> = []
  var expressions: [FormulaCoord: FormulaExpr] = [:]
  var currentSheetID = 0
  var currentSheetName = ""
  /// Range snapshots and lookup tables shared by every formula in this pass. Formulas run precedents first and
  /// results never change once set, so a range read once holds for the rest of the pass.
  /// Without it each SUMIFS re-read its whole columns: 1,200 over 15,000 rows took 6 minutes.
  let aggregateRangeCache = FormulaAggregateRangeCache()
  let lookupTableCache = FormulaLookupTableCache()

  init(
    workbook: Workbook,
    graph: WorkbookDependencyGraph,
    sheetsByID: [Int: Sheet],
    overrides: [FormulaCoord: CellValue],
    affected: [FormulaCoord: Int]
  ) {
    self.workbook = workbook
    self.graph = graph
    self.sheetsByID = sheetsByID
    self.overrides = overrides
    self.affected = affected
  }

  func evaluate(formulaID: Int, at coord: FormulaCoord) {
    _ = value(at: coord)
    if memo[coord] != nil { return }
    guard affected[coord] == formulaID else { return }
    _ = evaluateFormula(at: coord)
  }

  func value(at coord: FormulaCoord) -> CellValue {
    if let cached = memo[coord] { return cached }
    if let override = overrides[coord] { return override }
    if affected[coord] != nil {
      return evaluateFormula(at: coord)
    }
    return storedValue(sheetID: coord.sheetID, row: coord.row, col: coord.col)
  }

  func evaluateFormula(at coord: FormulaCoord) -> CellValue {
    if let cached = memo[coord] { return cached }
    if !visiting.insert(coord).inserted {
      let cycle = CellValue.error(.cycle)
      memo[coord] = cycle
      return cycle
    }
    defer { visiting.remove(coord) }

    let previousSheetID = currentSheetID
    let previousSheetName = currentSheetName
    currentSheetID = coord.sheetID
    currentSheetName = sheetsByID[coord.sheetID]?.name ?? ""
    defer {
      currentSheetID = previousSheetID
      currentSheetName = previousSheetName
    }

    let cell =
      sheetsByID[coord.sheetID]?.cell(at: CellAddress(row: coord.row, col: coord.col)) ?? Cell()
    let raw = cell.raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let expr: FormulaExpr
    if let parsed = expressions[coord] {
      expr = parsed
    } else if FormulaSyntax.isFormula(raw), let parsed = try? FormulaParser.parse(raw) {
      expressions[coord] = parsed
      expr = parsed
    } else if FormulaSyntax.isFormula(raw) {
      let value = CellValue.error(.error)
      memo[coord] = value
      return value
    } else {
      let unresolved = cell.cachedFormulaValue ?? CellValue.fromLiteralRaw(cell.raw)
      memo[coord] = unresolved
      return unresolved
    }

    var evaluator = FormulaEvaluator { [self] ref in
      self.lookup(ref)
    }
    evaluator.evaluationOrigin = CellAddress(row: coord.row, col: coord.col)
    evaluator.formulaSheetName = currentSheetName
    evaluator.aggregateRangeCache = aggregateRangeCache
    evaluator.lookupTableCache = lookupTableCache
    evaluator.namedRangeLookup = { [self] name in
      self.namedRangeExpr(named: name)
    }
    evaluator.sheetExtent = { [self] sheetName in
      self.extent(for: sheetName)
    }
    let value = evaluator.evaluate(expr)
    memo[coord] = value
    return value
  }

  func lookup(_ ref: FormulaRef) -> CellValue {
    let sheetID: Int
    if let name = ref.sheet {
      guard let resolved = graph.sheetID(for: name) else { return .error(.ref) }
      sheetID = resolved
    } else {
      sheetID = currentSheetID
    }
    return value(at: FormulaCoord(sheetID: sheetID, row: ref.row, col: ref.col))
  }

  func storedValue(sheetID: Int, row: Int, col: Int) -> CellValue {
    guard let sheet = sheetsByID[sheetID] else { return .blank }
    let cell = sheet.cell(at: CellAddress(row: row, col: col))
    if FormulaSyntax.isFormula(cell.raw) {
      if let imported = cell.cachedFormulaValue {
        if case .string(let text) = imported, FormulaSyntax.isFormula(text) {
          return evaluateFormula(at: FormulaCoord(sheetID: sheetID, row: row, col: col))
        }
        return imported
      }
      return evaluateFormula(at: FormulaCoord(sheetID: sheetID, row: row, col: col))
    }
    return CellValue.fromLiteralRaw(cell.raw)
  }

  func extent(for sheetName: String?) -> (maxRow: Int, maxCol: Int) {
    let resolved = sheetName ?? currentSheetName
    if let sheet = workbook.sheets.first(where: {
      $0.name.caseInsensitiveCompare(resolved) == .orderedSame
    }) {
      return (max(0, sheet.effectiveRowCount - 1), max(0, sheet.effectiveColumnCount - 1))
    }
    return (max(0, Workbook.defaultRowCount - 1), max(0, Workbook.defaultColumnCount - 1))
  }

  func namedRangeExpr(named name: String) -> FormulaExpr? {
    guard let named = workbook.namedRange(named: name), named.resolvesToRange else { return nil }
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
    if start.row == end.row, start.col == end.col {
      return .cellRef(start)
    }
    return .range(start, end)
  }
}
