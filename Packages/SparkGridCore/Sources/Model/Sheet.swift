import CoreGraphics
import Formula
import Foundation
import GridCore
import NumberFormat

public nonisolated struct Sheet: Identifiable, Codable, Equatable, Sendable {
  public var id: UUID
  public var name: String
  public var cells: [CellAddress: Cell]
  public var columnWidths: [Int: CGFloat]
  public var rowHeights: [Int: CGFloat]
  public var frozenRows: Int
  public var frozenColumns: Int
  public var conditionalFormats: [ConditionalFormatRule]
  /// Persisted AutoFilter including selected values when present.
  public var autoFilter: SheetFilterState?
  /// Merged cell ranges (inclusive). Top-left is the anchor.
  public var mergedRanges: [CellRange]
  /// Embedded charts (Spark-native; also stored in a custom xlsx part).
  public var charts: [SheetChart]
  /// Embedded pictures (Excel drawing anchors).
  public var images: [SheetImage]
  /// Explicit grid width when it exceeds populated data (e.g. after insert past the last column).
  public var gridColumnCount: Int?
  /// Explicit grid height when it exceeds populated data (e.g. after insert past the last row).
  public var gridRowCount: Int?
  /// Hidden rows and columns, tab state, and parts kept from the file for the next save.
  public var fileExtras = SheetFileExtras()

  /// Cached max populated indices for O(1) `effectiveRowCount` / `effectiveColumnCount`.
  /// Not persisted — recomputed after decode and bulk cell replacement.
  private var cachedMaxPopulatedRow: Int = -1
  private var cachedMaxPopulatedColumn: Int = -1
  private var populatedExtentsValid: Bool = false

  /// Formula cells grouped by column, sorted by row — built at import / cell bulk replace, not each recalc.
  public var formulaIngestByColumn: [Int: [(CellAddress, String)]] = [:]

  public init(
    id: UUID = UUID(),
    name: String,
    cells: [CellAddress: Cell] = [:],
    columnWidths: [Int: CGFloat] = [:],
    rowHeights: [Int: CGFloat] = [:],
    frozenRows: Int = 0,
    frozenColumns: Int = 0,
    conditionalFormats: [ConditionalFormatRule] = [],
    autoFilter: SheetFilterState? = nil,
    mergedRanges: [CellRange] = [],
    charts: [SheetChart] = [],
    images: [SheetImage] = [],
    gridColumnCount: Int? = nil,
    gridRowCount: Int? = nil
  ) {
    self.id = id
    self.name = name
    self.cells = cells
    self.columnWidths = columnWidths
    self.rowHeights = rowHeights
    self.frozenRows = frozenRows
    self.frozenColumns = frozenColumns
    self.conditionalFormats = conditionalFormats
    self.autoFilter = autoFilter
    self.mergedRanges = mergedRanges
    self.charts = charts
    self.images = images
    self.gridColumnCount = gridColumnCount
    self.gridRowCount = gridRowCount
    recomputePopulatedExtents()
    rebuildFormulaIngestIndex()
  }

  public enum CodingKeys: String, CodingKey {
    case id, name, cells, columnWidths, rowHeights
    case frozenRows, frozenColumns, conditionalFormats, autoFilter
    case mergedRanges, charts, images, gridColumnCount, gridRowCount
    case fileExtras
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(UUID.self, forKey: .id)
    name = try c.decode(String.self, forKey: .name)
    cells = try c.decodeIfPresent([CellAddress: Cell].self, forKey: .cells) ?? [:]
    columnWidths = try c.decodeIfPresent([Int: CGFloat].self, forKey: .columnWidths) ?? [:]
    rowHeights = try c.decodeIfPresent([Int: CGFloat].self, forKey: .rowHeights) ?? [:]
    frozenRows = try c.decodeIfPresent(Int.self, forKey: .frozenRows) ?? 0
    frozenColumns = try c.decodeIfPresent(Int.self, forKey: .frozenColumns) ?? 0
    conditionalFormats =
      try c.decodeIfPresent([ConditionalFormatRule].self, forKey: .conditionalFormats) ?? []
    autoFilter = try c.decodeIfPresent(SheetFilterState.self, forKey: .autoFilter)
    mergedRanges = try c.decodeIfPresent([CellRange].self, forKey: .mergedRanges) ?? []
    charts = try c.decodeIfPresent([SheetChart].self, forKey: .charts) ?? []
    images = try c.decodeIfPresent([SheetImage].self, forKey: .images) ?? []
    gridColumnCount = try c.decodeIfPresent(Int.self, forKey: .gridColumnCount)
    gridRowCount = try c.decodeIfPresent(Int.self, forKey: .gridRowCount)
    fileExtras =
      try c.decodeIfPresent(SheetFileExtras.self, forKey: .fileExtras) ?? SheetFileExtras()
    recomputePopulatedExtents()
    rebuildFormulaIngestIndex()
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(id, forKey: .id)
    try c.encode(name, forKey: .name)
    try c.encode(cells, forKey: .cells)
    try c.encode(columnWidths, forKey: .columnWidths)
    try c.encode(rowHeights, forKey: .rowHeights)
    try c.encode(frozenRows, forKey: .frozenRows)
    try c.encode(frozenColumns, forKey: .frozenColumns)
    try c.encode(conditionalFormats, forKey: .conditionalFormats)
    try c.encodeIfPresent(autoFilter, forKey: .autoFilter)
    try c.encode(mergedRanges, forKey: .mergedRanges)
    try c.encode(charts, forKey: .charts)
    try c.encode(images, forKey: .images)
    try c.encodeIfPresent(gridColumnCount, forKey: .gridColumnCount)
    try c.encodeIfPresent(gridRowCount, forKey: .gridRowCount)
    if !fileExtras.isEmpty {
      try c.encode(fileExtras, forKey: .fileExtras)
    }
  }

  public static func == (lhs: Sheet, rhs: Sheet) -> Bool {
    lhs.id == rhs.id
      && lhs.name == rhs.name
      && lhs.cells == rhs.cells
      && lhs.columnWidths == rhs.columnWidths
      && lhs.rowHeights == rhs.rowHeights
      && lhs.frozenRows == rhs.frozenRows
      && lhs.frozenColumns == rhs.frozenColumns
      && lhs.conditionalFormats == rhs.conditionalFormats
      && lhs.autoFilter == rhs.autoFilter
      && lhs.mergedRanges == rhs.mergedRanges
      && lhs.charts == rhs.charts
      && lhs.images == rhs.images
      && lhs.gridColumnCount == rhs.gridColumnCount
      && lhs.gridRowCount == rhs.gridRowCount
      && lhs.fileExtras == rhs.fileExtras
  }

  public func cell(at address: CellAddress) -> Cell {
    cells[address] ?? Cell()
  }

  public mutating func setCell(_ cell: Cell, at address: CellAddress) {
    if cell.isEmpty {
      guard let removed = cells.removeValue(forKey: address) else { return }
      removeFormulaIngestEntry(address: address, raw: removed.raw)
      if populatedExtentsValid,
        address.row == cachedMaxPopulatedRow || address.col == cachedMaxPopulatedColumn
      {
        recomputePopulatedExtents()
      }
    } else {
      let previous = cells[address]
      cells[address] = cell
      updateFormulaIngestIndex(address: address, previousRaw: previous?.raw, newRaw: cell.raw)
      if populatedExtentsValid {
        cachedMaxPopulatedRow = max(cachedMaxPopulatedRow, address.row)
        cachedMaxPopulatedColumn = max(cachedMaxPopulatedColumn, address.col)
      } else {
        recomputePopulatedExtents()
      }
    }
  }

  /// Bulk-replace the cell map and refresh populated-extent caches once.
  public mutating func replaceCells(_ newCells: [CellAddress: Cell]) {
    cells = newCells
    recomputePopulatedExtents()
    rebuildFormulaIngestIndex()
  }

  /// Same formula detection / trim as `FormulaEngine.bulkIngestFormulas` (fast `=` prefix, else `FormulaSyntax`).
  public static func bulkIngestTrimmedFormulaRaw(_ raw: String) -> String? {
    guard let first = raw.unicodeScalars.first else { return nil }
    if first == "=" { return raw }
    guard FormulaSyntax.isFormula(raw) else { return nil }
    return raw.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Rebuild `formulaIngestByColumn` from `cells` (import, decode, bulk replace — not each full recalc).
  public mutating func rebuildFormulaIngestIndex() {
    var buckets: [Int: [(CellAddress, String)]] = [:]
    for (address, cell) in cells {
      guard let trimmed = Self.bulkIngestTrimmedFormulaRaw(cell.raw) else { continue }
      buckets[address.col, default: []].append((address, trimmed))
    }
    for col in buckets.keys {
      buckets[col]?.sort { $0.0.row < $1.0.row }
    }
    formulaIngestByColumn = buckets
  }

  private mutating func removeFormulaIngestEntry(address: CellAddress, raw: String) {
    guard Self.bulkIngestTrimmedFormulaRaw(raw) != nil else { return }
    guard var column = formulaIngestByColumn[address.col] else { return }
    if let idx = column.firstIndex(where: { $0.0 == address }) {
      column.remove(at: idx)
      if column.isEmpty {
        formulaIngestByColumn.removeValue(forKey: address.col)
      } else {
        formulaIngestByColumn[address.col] = column
      }
    }
  }

  private mutating func updateFormulaIngestIndex(
    address: CellAddress, previousRaw: String?, newRaw: String
  ) {
    let oldTrimmed = previousRaw.flatMap { Self.bulkIngestTrimmedFormulaRaw($0) }
    let newTrimmed = Self.bulkIngestTrimmedFormulaRaw(newRaw)
    if oldTrimmed == newTrimmed { return }
    if oldTrimmed != nil {
      removeFormulaIngestEntry(address: address, raw: previousRaw ?? "")
    }
    guard let trimmed = newTrimmed else { return }
    var column = formulaIngestByColumn[address.col, default: []]
    let insertIndex = column.firstIndex { $0.0.row >= address.row } ?? column.endIndex
    column.insert((address, trimmed), at: insertIndex)
    formulaIngestByColumn[address.col] = column
  }

  /// Call after direct `cells` dictionary surgery that may change extents.
  public mutating func recomputePopulatedExtents() {
    var maxRow = -1
    var maxCol = -1
    for address in cells.keys {
      if address.row > maxRow { maxRow = address.row }
      if address.col > maxCol { maxCol = address.col }
    }
    cachedMaxPopulatedRow = maxRow
    cachedMaxPopulatedColumn = maxCol
    populatedExtentsValid = true
  }

  /// Zero for a hidden column.
  public func columnWidth(for col: Int, default defaultWidth: CGFloat) -> CGFloat {
    if !fileExtras.hiddenColumns.isEmpty, fileExtras.hiddenColumns.contains(col) { return 0 }
    return columnWidths[col] ?? defaultWidth
  }

  /// Zero for a hidden row.
  public func rowHeight(for row: Int, default defaultHeight: CGFloat) -> CGFloat {
    if !fileExtras.hiddenRows.isEmpty, fileExtras.hiddenRows.contains(row) { return 0 }
    return rowHeights[row] ?? defaultHeight
  }

  public func isRowHidden(_ row: Int) -> Bool {
    !fileExtras.hiddenRows.isEmpty && fileExtras.hiddenRows.contains(row)
  }

  public func isColumnHidden(_ col: Int) -> Bool {
    !fileExtras.hiddenColumns.isEmpty && fileExtras.hiddenColumns.contains(col)
  }

  public var isHidden: Bool { fileExtras.visibility != .visible }

  /// Highest row index that contains data (for CSV export).
  public var maxPopulatedRow: Int {
    if populatedExtentsValid { return cachedMaxPopulatedRow }
    return cells.keys.map(\.row).max() ?? -1
  }

  /// Highest column index that contains data (for CSV export).
  public var maxPopulatedColumn: Int {
    if populatedExtentsValid { return cachedMaxPopulatedColumn }
    return cells.keys.map(\.col).max() ?? -1
  }

  /// Tight bounds around every non-empty cell, if any.
  public var populatedBounds: CellRange? {
    guard !cells.isEmpty else { return nil }
    if populatedExtentsValid {
      // Still need min for bounds — scan once is rare (export / print paths).
      let rows = cells.keys.map(\.row)
      let cols = cells.keys.map(\.col)
      return CellRange(
        start: CellAddress(row: rows.min() ?? 0, col: cols.min() ?? 0),
        end: CellAddress(row: cachedMaxPopulatedRow, col: cachedMaxPopulatedColumn)
      )
    }
    let rows = cells.keys.map(\.row)
    let cols = cells.keys.map(\.col)
    return CellRange(
      start: CellAddress(row: rows.min() ?? 0, col: cols.min() ?? 0),
      end: CellAddress(row: rows.max() ?? 0, col: cols.max() ?? 0)
    )
  }

  /// Full used range from A1 through the last populated row/column.
  public var populatedRangeFromOrigin: CellRange {
    if maxPopulatedRow < 0 || maxPopulatedColumn < 0 {
      return .singleOrigin
    }
    return CellRange(
      start: .origin,
      end: CellAddress(row: maxPopulatedRow, col: maxPopulatedColumn)
    )
  }

  public func wholeSheetRange() -> CellRange {
    CellRange(
      start: .origin,
      end: CellAddress(row: effectiveRowCount - 1, col: effectiveColumnCount - 1)
    )
  }

  /// Grid row count — at least the default, expands when data exceeds it.
  public var effectiveRowCount: Int {
    let fromData = maxPopulatedRow + 1
    let fromHeights = (rowHeights.keys.max() ?? -1) + 1
    let explicit = gridRowCount ?? Workbook.defaultRowCount
    return max(Workbook.defaultRowCount, fromData, fromHeights, explicit)
  }

  /// Grid column count — at least the default, expands when data exceeds it.
  public var effectiveColumnCount: Int {
    let fromData = maxPopulatedColumn + 1
    let fromWidths = (columnWidths.keys.max() ?? -1) + 1
    let explicit = gridColumnCount ?? Workbook.defaultColumnCount
    return max(Workbook.defaultColumnCount, fromData, fromWidths, explicit)
  }

  // MARK: - Merges

  public func mergeContaining(_ address: CellAddress) -> CellRange? {
    mergedRanges.first { $0.contains(address) }
  }

  public func isMergeAnchor(_ address: CellAddress) -> Bool {
    guard let merge = mergeContaining(address) else { return true }
    let n = merge.normalized
    return address.row == n.minRow && address.col == n.minCol
  }

  /// Top-left anchor for selection/editing when `address` sits inside a merge.
  public func mergeAnchor(for address: CellAddress) -> CellAddress {
    guard let merge = mergeContaining(address) else { return address }
    let n = merge.normalized
    return CellAddress(row: n.minRow, col: n.minCol)
  }

  /// Non-anchor cells covered by a merge (should not paint content).
  public func isCoveredByMerge(_ address: CellAddress) -> Bool {
    guard let merge = mergeContaining(address) else { return false }
    let n = merge.normalized
    return !(address.row == n.minRow && address.col == n.minCol)
  }

  /// Expands a single cell (or range) to include any intersecting merges.
  public func selectionExpandedForMerges(_ range: CellRange) -> CellRange {
    var n = range.normalized
    var changed = true
    while changed {
      changed = false
      for merge in mergedRanges {
        let m = merge.normalized
        let intersects =
          n.minRow <= m.maxRow && n.maxRow >= m.minRow
          && n.minCol <= m.maxCol && n.maxCol >= m.minCol
        guard intersects else { continue }
        let next = (
          minRow: min(n.minRow, m.minRow),
          maxRow: max(n.maxRow, m.maxRow),
          minCol: min(n.minCol, m.minCol),
          maxCol: max(n.maxCol, m.maxCol)
        )
        if next != n {
          n = next
          changed = true
        }
      }
    }
    return CellRange(
      start: CellAddress(row: n.minRow, col: n.minCol),
      end: CellAddress(row: n.maxRow, col: n.maxCol)
    )
  }
}
