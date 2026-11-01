import Formula
import Foundation
import Functions
import GridCore
import Model
import NumberFormat

/// One cell in a workbook. `sheetID` indexes `WorkbookDependencyGraph.sheetNames`.
public nonisolated struct FormulaCoord: Hashable, Sendable {
  public var sheetID: Int
  public var row: Int
  public var col: Int
}

/// A rectangular read. Stored as a range — never expanded into cells.
public nonisolated struct FormulaRangeRef: Hashable, Sendable {
  public var sheetID: Int
  public var minRow: Int
  public var maxRow: Int
  public var minCol: Int
  public var maxCol: Int
}

/// Workbook-wide precedents. Cell edges are coordinates. Range edges live in an interval index.
public nonisolated struct WorkbookDependencyGraph: Sendable {
  /// Lowercased sheet names. Index is `FormulaCoord.sheetID`.
  public var sheetNames: [String]
  public var formulaCoords: [FormulaCoord]
  /// Parallel to `formulaCoords`: single-cell precedents.
  public var cellPrecedents: [[FormulaCoord]]
  /// Parallel to `formulaCoords`: range precedents, not expanded.
  public var rangePrecedents: [[FormulaRangeRef]]
  /// Cell → formulas that reference that cell directly.
  public var cellDependents: [FormulaCoord: [Int]]
  /// Per precedent sheet, range → formulas whose ranges contain a cell.
  public var rangeIndex: [Int: FormulaRangeIntervalIndex]

  public func sheetID(for name: String) -> Int? {
    let key = name.lowercased()
    for (index, sheet) in sheetNames.enumerated() where sheet == key {
      return index
    }
    return nil
  }

  /// Formulas that read this cell, including formulas on other sheets.
  public func formulaIDsReading(sheet: String, row: Int, col: Int) -> [Int] {
    guard let sheetID = sheetID(for: sheet) else { return [] }
    return formulaIDsReading(sheetID: sheetID, row: row, col: col)
  }

  public func formulaIDsReading(sheetID: Int, row: Int, col: Int) -> [Int] {
    let coord = FormulaCoord(sheetID: sheetID, row: row, col: col)
    var ids = cellDependents[coord] ?? []
    if let index = rangeIndex[sheetID] {
      ids.append(contentsOf: index.formulaIDs(row: row, col: col))
    }
    return ids
  }
}

/// Point query over rectangles. Each range is stored on O(log rows) segment nodes, not on each cell.
public nonisolated struct FormulaRangeIntervalIndex: Sendable {
  private struct Span {
    public var minCol: Int
    public var maxCol: Int
    public var formula: Int
  }

  private struct Node {
    public var lo: Int
    public var hi: Int
    public var left: Int
    public var right: Int
    public var spans: [Span]
  }

  private var nodes: [Node]
  private var root: Int

  public init(ranges: [(minRow: Int, maxRow: Int, minCol: Int, maxCol: Int, formula: Int)]) {
    var built: [Node] = []
    var rootIndex = -1
    if let maxRow = ranges.map(\.maxRow).max(), maxRow >= 0 {
      let domain = Self.domainSize(covering: maxRow)
      built.append(Node(lo: 0, hi: domain - 1, left: -1, right: -1, spans: []))
      rootIndex = 0
      for range in ranges {
        guard range.minRow <= range.maxRow, range.minCol <= range.maxCol else { continue }
        let span = Span(minCol: range.minCol, maxCol: range.maxCol, formula: range.formula)
        Self.insert(
          &built,
          index: rootIndex,
          minRow: max(0, range.minRow),
          maxRow: min(domain - 1, range.maxRow),
          span: span
        )
      }
    }
    nodes = built
    root = rootIndex
  }

  public func formulaIDs(row: Int, col: Int) -> [Int] {
    guard root >= 0, row >= nodes[root].lo, row <= nodes[root].hi else { return [] }
    var ids: [Int] = []
    var index = root
    while index >= 0 {
      let node = nodes[index]
      for span in node.spans where col >= span.minCol && col <= span.maxCol {
        ids.append(span.formula)
      }
      if node.lo == node.hi { break }
      let mid = node.lo + (node.hi - node.lo) / 2
      index = row <= mid ? node.left : node.right
    }
    return ids
  }

  private static func domainSize(covering maxRow: Int) -> Int {
    var size = 1
    var shift = 0
    while size <= maxRow && shift < 30 {
      size <<= 1
      shift += 1
    }
    return size
  }

  private static func insert(
    _ nodes: inout [Node],
    index: Int,
    minRow: Int,
    maxRow: Int,
    span: Span
  ) {
    var stack: [(Int, Int, Int)] = [(index, minRow, maxRow)]
    while let (nodeIndex, lo, hi) = stack.popLast() {
      guard lo <= hi else { continue }
      let nodeLo = nodes[nodeIndex].lo
      let nodeHi = nodes[nodeIndex].hi
      if lo <= nodeLo && nodeHi <= hi {
        nodes[nodeIndex].spans.append(span)
        continue
      }
      let mid = nodeLo + (nodeHi - nodeLo) / 2
      if lo <= mid {
        let child = ensureChild(&nodes, parent: nodeIndex, left: true, mid: mid)
        stack.append((child, lo, hi))
      }
      if hi > mid {
        let child = ensureChild(&nodes, parent: nodeIndex, left: false, mid: mid)
        stack.append((child, lo, hi))
      }
    }
  }

  private static func ensureChild(
    _ nodes: inout [Node],
    parent: Int,
    left: Bool,
    mid: Int
  ) -> Int {
    let existing = left ? nodes[parent].left : nodes[parent].right
    if existing >= 0 { return existing }
    let childLo = left ? nodes[parent].lo : mid + 1
    let childHi = left ? mid : nodes[parent].hi
    let child = nodes.count
    nodes.append(Node(lo: childLo, hi: childHi, left: -1, right: -1, spans: []))
    if left {
      nodes[parent].left = child
    } else {
      nodes[parent].right = child
    }
    return child
  }
}

/// Plain formula text copied off the workbook so the graph can be built away from the main thread.
public nonisolated struct WorkbookGraphInput: Sendable {
  public struct Cell: Sendable {
    public var row: Int
    public var col: Int
    public var raw: String
  }

  public struct Sheet: Sendable {
    public var name: String
    public var sheetID: Int
    public var maxRow: Int
    public var maxCol: Int
    public var columns: [[Cell]]
  }

  public struct Name: Sendable {
    public var key: String
    public var sheetID: Int
    public var minRow: Int
    public var maxRow: Int
    public var minCol: Int
    public var maxCol: Int
  }

  public var sheets: [Sheet]
  public var names: [Name]
  public var sheetIDsByName: [String: Int]
  public var fallbackMaxRow: Int
  public var fallbackMaxCol: Int
}

extension WorkbookDependencyGraph {
  public nonisolated static func build(_ input: WorkbookGraphInput) -> WorkbookDependencyGraph {
    let namesByKey = Dictionary(uniqueKeysWithValues: input.names.map { ($0.key, $0) })
    var perSheet: [[BuiltFormula]] = Array(repeating: [], count: input.sheets.count)
    let lock = NSLock()
    DispatchQueue.concurrentPerform(iterations: input.sheets.count) { index in
      let built = parseSheet(input.sheets[index], input: input, namesByKey: namesByKey)
      lock.lock()
      perSheet[index] = built
      lock.unlock()
    }
    return assemble(perSheet, sheetNames: input.sheets.map(\.name))
  }

  private struct BuiltFormula {
    public var coord: FormulaCoord
    public var cells: [FormulaCoord]
    public var ranges: [FormulaRangeRef]
  }

  private static func parseSheet(
    _ sheet: WorkbookGraphInput.Sheet,
    input: WorkbookGraphInput,
    namesByKey: [String: WorkbookGraphInput.Name]
  ) -> [BuiltFormula] {
    var built: [BuiltFormula] = []
    for column in sheet.columns {
      var masterExpr: FormulaExpr?
      var masterRow = 0
      var masterCol = 0
      var lastRow: Int?
      for cell in column {
        let coord = FormulaCoord(sheetID: sheet.sheetID, row: cell.row, col: cell.col)
        var expr: FormulaExpr?
        if let master = masterExpr, let previous = lastRow, cell.row == previous + 1 {
          let rowDelta = cell.row - masterRow
          let colDelta = cell.col - masterCol
          let expected = FormulaRewriter.adjustedFormulaText(
            expr: master,
            rowDelta: rowDelta,
            colDelta: colDelta
          )
          if expected == cell.raw {
            expr = FormulaRewriter.adjustExpression(master, rowDelta: rowDelta, colDelta: colDelta)
          }
        }
        if expr == nil {
          guard let parsed = try? FormulaParser.parse(cell.raw) else {
            masterExpr = nil
            lastRow = cell.row
            continue
          }
          expr = parsed
          masterExpr = parsed
          masterRow = cell.row
          masterCol = cell.col
        }
        lastRow = cell.row
        guard let expr else { continue }
        let precedents = collect(
          expr,
          formulaSheet: sheet.sheetID,
          input: input,
          namesByKey: namesByKey
        )
        built.append(BuiltFormula(coord: coord, cells: precedents.cells, ranges: precedents.ranges))
      }
    }
    return built
  }

  private static func assemble(
    _ perSheet: [[BuiltFormula]],
    sheetNames: [String]
  ) -> WorkbookDependencyGraph {
    var formulaCoords: [FormulaCoord] = []
    var cellPrecedents: [[FormulaCoord]] = []
    var rangePrecedents: [[FormulaRangeRef]] = []
    var cellDependents: [FormulaCoord: [Int]] = [:]
    var rangesBySheet: [Int: [(minRow: Int, maxRow: Int, minCol: Int, maxCol: Int, formula: Int)]] =
      [:]
    for sheetFormulas in perSheet {
      for formula in sheetFormulas {
        let formulaID = formulaCoords.count
        formulaCoords.append(formula.coord)
        cellPrecedents.append(formula.cells)
        rangePrecedents.append(formula.ranges)
        for cell in formula.cells {
          cellDependents[cell, default: []].append(formulaID)
        }
        for range in formula.ranges {
          rangesBySheet[range.sheetID, default: []].append(
            (range.minRow, range.maxRow, range.minCol, range.maxCol, formulaID)
          )
        }
      }
    }
    var rangeIndex: [Int: FormulaRangeIntervalIndex] = [:]
    for (sheetID, ranges) in rangesBySheet {
      rangeIndex[sheetID] = FormulaRangeIntervalIndex(ranges: ranges)
    }
    return WorkbookDependencyGraph(
      sheetNames: sheetNames,
      formulaCoords: formulaCoords,
      cellPrecedents: cellPrecedents,
      rangePrecedents: rangePrecedents,
      cellDependents: cellDependents,
      rangeIndex: rangeIndex
    )
  }

  private static func collect(
    _ expr: FormulaExpr,
    formulaSheet: Int,
    input: WorkbookGraphInput,
    namesByKey: [String: WorkbookGraphInput.Name]
  ) -> (cells: [FormulaCoord], ranges: [FormulaRangeRef]) {
    var cells: [FormulaCoord] = []
    var ranges: [FormulaRangeRef] = []
    collect(
      expr, formulaSheet: formulaSheet, input: input, namesByKey: namesByKey, cells: &cells,
      ranges: &ranges)
    return (cells, ranges)
  }

  private static func collect(
    _ expr: FormulaExpr,
    formulaSheet: Int,
    input: WorkbookGraphInput,
    namesByKey: [String: WorkbookGraphInput.Name],
    cells: inout [FormulaCoord],
    ranges: inout [FormulaRangeRef]
  ) {
    switch expr {
    case .number, .string, .boolean, .error:
      break
    case .namedRange(let name):
      guard let named = namesByKey[name.uppercased()] else { return }
      appendArea(
        sheetID: named.sheetID,
        minRow: named.minRow,
        maxRow: named.maxRow,
        minCol: named.minCol,
        maxCol: named.maxCol,
        cells: &cells,
        ranges: &ranges
      )
    case .cellRef(let ref):
      guard let sheetID = sheetID(for: ref.sheet, formulaSheet: formulaSheet, input: input) else {
        return
      }
      if ref.isRowOpen || ref.isColOpen {
        let extent = extent(for: sheetID, input: input)
        let start = ref
        var end = ref
        if ref.isRowOpen { end.row = extent.maxRow }
        if ref.isColOpen { end.col = extent.maxCol }
        let bounds = A1Reference.resolvedBounds(
          start: start,
          end: end,
          maxRow: extent.maxRow,
          maxCol: extent.maxCol
        )
        appendArea(
          sheetID: sheetID,
          minRow: bounds.minRow,
          maxRow: bounds.maxRow,
          minCol: bounds.minCol,
          maxCol: bounds.maxCol,
          cells: &cells,
          ranges: &ranges
        )
      } else if ref.row >= 0, ref.col >= 0 {
        cells.append(FormulaCoord(sheetID: sheetID, row: ref.row, col: ref.col))
      }
    case .range(let start, let end):
      let sheetName = start.sheet ?? end.sheet
      guard let sheetID = sheetID(for: sheetName, formulaSheet: formulaSheet, input: input) else {
        return
      }
      let extent = extent(for: sheetID, input: input)
      let bounds = A1Reference.resolvedBounds(
        start: start,
        end: end,
        maxRow: extent.maxRow,
        maxCol: extent.maxCol
      )
      appendArea(
        sheetID: sheetID,
        minRow: bounds.minRow,
        maxRow: bounds.maxRow,
        minCol: bounds.minCol,
        maxCol: bounds.maxCol,
        cells: &cells,
        ranges: &ranges
      )
    case .unary(_, let inner):
      collect(
        inner, formulaSheet: formulaSheet, input: input, namesByKey: namesByKey, cells: &cells,
        ranges: &ranges)
    case .binary(_, let lhs, let rhs):
      collect(
        lhs, formulaSheet: formulaSheet, input: input, namesByKey: namesByKey, cells: &cells,
        ranges: &ranges)
      collect(
        rhs, formulaSheet: formulaSheet, input: input, namesByKey: namesByKey, cells: &cells,
        ranges: &ranges)
    case .call(_, let args):
      for arg in args {
        collect(
          arg, formulaSheet: formulaSheet, input: input, namesByKey: namesByKey, cells: &cells,
          ranges: &ranges)
      }
    }
  }

  private static func appendArea(
    sheetID: Int,
    minRow: Int,
    maxRow: Int,
    minCol: Int,
    maxCol: Int,
    cells: inout [FormulaCoord],
    ranges: inout [FormulaRangeRef]
  ) {
    guard minRow >= 0, minCol >= 0, maxRow >= minRow, maxCol >= minCol else { return }
    let rows = maxRow - minRow + 1
    let cols = maxCol - minCol + 1
    if rows == 1 && cols == 1 {
      cells.append(FormulaCoord(sheetID: sheetID, row: minRow, col: minCol))
    } else {
      ranges.append(
        FormulaRangeRef(
          sheetID: sheetID,
          minRow: minRow,
          maxRow: maxRow,
          minCol: minCol,
          maxCol: maxCol
        )
      )
    }
  }

  private static func sheetID(
    for sheetName: String?,
    formulaSheet: Int,
    input: WorkbookGraphInput
  ) -> Int? {
    guard let sheetName else { return formulaSheet }
    return input.sheetIDsByName[sheetName.lowercased()]
  }

  private static func extent(
    for sheetID: Int,
    input: WorkbookGraphInput
  ) -> (maxRow: Int, maxCol: Int) {
    guard input.sheets.indices.contains(sheetID) else {
      return (input.fallbackMaxRow, input.fallbackMaxCol)
    }
    let sheet = input.sheets[sheetID]
    return (sheet.maxRow, sheet.maxCol)
  }
}

extension WorkbookDependencyGraph {
  /// Sheet ids grouped so a formula's cross-sheet precedents are in an earlier group.
  /// Sheets in one group do not read each other. A cycle is left in workbook order, one sheet at a time.
  public func sheetEvaluationWaves() -> [[Int]] {
    let count = sheetNames.count
    guard count > 0 else { return [] }
    var followers: [Set<Int>] = Array(repeating: [], count: count)
    var indegree = Array(repeating: 0, count: count)
    var seenEdges: Set<SheetEdge> = []

    func link(precedent: Int, formulaSheet: Int) {
      guard precedent != formulaSheet else { return }
      guard precedent >= 0, formulaSheet >= 0, precedent < count, formulaSheet < count else {
        return
      }
      let edge = SheetEdge(precedent: precedent, formulaSheet: formulaSheet)
      guard seenEdges.insert(edge).inserted else { return }
      followers[precedent].insert(formulaSheet)
      indegree[formulaSheet] += 1
    }

    for formulaID in formulaCoords.indices {
      guard cellPrecedents.indices.contains(formulaID),
        rangePrecedents.indices.contains(formulaID)
      else { continue }
      let formulaSheet = formulaCoords[formulaID].sheetID
      for cell in cellPrecedents[formulaID] {
        link(precedent: cell.sheetID, formulaSheet: formulaSheet)
      }
      for range in rangePrecedents[formulaID] {
        link(precedent: range.sheetID, formulaSheet: formulaSheet)
      }
    }

    var ready = (0..<count).filter { indegree[$0] == 0 }
    var waves: [[Int]] = []
    var placed = 0
    while !ready.isEmpty {
      let wave = ready.sorted()
      waves.append(wave)
      placed += wave.count
      var next: [Int] = []
      for sheetID in wave {
        for follower in followers[sheetID] {
          indegree[follower] -= 1
          if indegree[follower] == 0 {
            next.append(follower)
          }
        }
      }
      ready = next
    }
    if placed < count {
      for sheetID in 0..<count where indegree[sheetID] > 0 {
        waves.append([sheetID])
      }
    }
    return waves
  }

  private struct SheetEdge: Hashable {
    public var precedent: Int
    public var formulaSheet: Int
  }
}
