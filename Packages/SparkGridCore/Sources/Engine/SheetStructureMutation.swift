import Calc
import FileFormats
import Formula
import Foundation
import Functions
import GridCore
import Model
import NumberFormat

public enum SheetStructureMutation {
  public static func insertRows(into sheet: inout Sheet, at index: Int, count: Int = 1) {
    guard count > 0, index >= 0 else { return }
    // Spilled values do not move with the cells: their formulas fill them in again after.
    SpillLayout.clearSpills(in: &sheet)

    var newCells: [CellAddress: Cell] = [:]
    newCells.reserveCapacity(sheet.cells.count)
    for (address, cell) in sheet.cells {
      if address.row >= index {
        newCells[CellAddress(row: address.row + count, col: address.col)] = cell
      } else {
        newCells[address] = cell
      }
    }
    sheet.cells = newCells
    sheet.recomputePopulatedExtents()
    sheet.rebuildFormulaIngestIndex()
    sheet.rowHeights = shiftKeyedValues(sheet.rowHeights, threshold: index, delta: count)
    if sheet.frozenRows > index {
      sheet.frozenRows += count
    }
    ensureRowCapacity(&sheet, through: index + count - 1)
    shiftSheetAnnotations(&sheet, axis: .row, index: index, delta: count)
  }

  public static func deleteRows(in sheet: inout Sheet, at index: Int, count: Int = 1) {
    guard count > 0, index >= 0 else { return }
    // Spilled values do not move with the cells: their formulas fill them in again after.
    SpillLayout.clearSpills(in: &sheet)

    var newCells: [CellAddress: Cell] = [:]
    for (address, cell) in sheet.cells {
      if address.row >= index && address.row < index + count {
        continue
      }
      if address.row >= index + count {
        newCells[CellAddress(row: address.row - count, col: address.col)] = cell
      } else {
        newCells[address] = cell
      }
    }
    sheet.cells = newCells
    sheet.recomputePopulatedExtents()
    sheet.rebuildFormulaIngestIndex()
    sheet.rowHeights = deleteKeyedValues(sheet.rowHeights, range: index..<(index + count))
    sheet.rowHeights = shiftKeyedValues(sheet.rowHeights, threshold: index + count, delta: -count)
    sheet.frozenRows = max(0, min(sheet.frozenRows, index))
    shiftSheetAnnotations(&sheet, axis: .row, index: index, delta: -count, deleteCount: count)
  }

  public static func insertColumns(into sheet: inout Sheet, at index: Int, count: Int = 1) {
    guard count > 0, index >= 0 else { return }
    // Spilled values do not move with the cells: their formulas fill them in again after.
    SpillLayout.clearSpills(in: &sheet)

    var newCells: [CellAddress: Cell] = [:]
    newCells.reserveCapacity(sheet.cells.count)
    for (address, cell) in sheet.cells {
      if address.col >= index {
        newCells[CellAddress(row: address.row, col: address.col + count)] = cell
      } else {
        newCells[address] = cell
      }
    }
    sheet.cells = newCells
    sheet.recomputePopulatedExtents()
    sheet.rebuildFormulaIngestIndex()
    sheet.columnWidths = shiftKeyedValues(sheet.columnWidths, threshold: index, delta: count)
    if sheet.frozenColumns > index {
      sheet.frozenColumns += count
    }
    ensureColumnCapacity(&sheet, through: index + count - 1)
    shiftSheetAnnotations(&sheet, axis: .column, index: index, delta: count)
  }

  public static func deleteColumns(in sheet: inout Sheet, at index: Int, count: Int = 1) {
    guard count > 0, index >= 0 else { return }
    // Spilled values do not move with the cells: their formulas fill them in again after.
    SpillLayout.clearSpills(in: &sheet)

    var newCells: [CellAddress: Cell] = [:]
    for (address, cell) in sheet.cells {
      if address.col >= index && address.col < index + count {
        continue
      }
      if address.col >= index + count {
        newCells[CellAddress(row: address.row, col: address.col - count)] = cell
      } else {
        newCells[address] = cell
      }
    }
    sheet.cells = newCells
    sheet.recomputePopulatedExtents()
    sheet.rebuildFormulaIngestIndex()
    sheet.columnWidths = deleteKeyedValues(sheet.columnWidths, range: index..<(index + count))
    sheet.columnWidths = shiftKeyedValues(
      sheet.columnWidths, threshold: index + count, delta: -count)
    sheet.frozenColumns = max(0, min(sheet.frozenColumns, index))
    shiftSheetAnnotations(&sheet, axis: .column, index: index, delta: -count, deleteCount: count)
  }

  private enum Axis { case row, column }

  private static func shiftSheetAnnotations(
    _ sheet: inout Sheet,
    axis: Axis,
    index: Int,
    delta: Int,
    deleteCount: Int = 0
  ) {
    sheet.mergedRanges = sheet.mergedRanges.compactMap {
      shiftRange($0, axis: axis, index: index, delta: delta, deleteCount: deleteCount)
    }
    sheet.conditionalFormats = sheet.conditionalFormats.compactMap { rule in
      guard
        let range = shiftRange(
          rule.range, axis: axis, index: index, delta: delta, deleteCount: deleteCount)
      else { return nil }
      var next = rule
      next.range = range
      return next
    }
    if var filter = sheet.autoFilter {
      if let range = shiftRange(
        filter.range, axis: axis, index: index, delta: delta, deleteCount: deleteCount)
      {
        filter.range = range
        if axis == .column {
          var shiftedRules: [Int: ColumnFilterRules] = [:]
          for (col, rules) in filter.rulesByColumn {
            if let next = shiftIndex(col, index: index, delta: delta, deleteCount: deleteCount) {
              shiftedRules[next] = rules
            }
          }
          filter.rulesByColumn = shiftedRules
          filter.selectedValuesByColumn = shiftColumnMap(
            filter.selectedValuesByColumn,
            index: index,
            delta: delta,
            deleteCount: deleteCount
          )
          filter.excludedColumns = Set(
            filter.excludedColumns.compactMap { col -> Int? in
              shiftIndex(col, index: index, delta: delta, deleteCount: deleteCount)
            }
          )
        }
        sheet.autoFilter = filter
      } else {
        sheet.autoFilter = nil
      }
    }
    sheet.charts = sheet.charts.compactMap { chart in
      guard
        let range = shiftRange(
          chart.dataRange, axis: axis, index: index, delta: delta, deleteCount: deleteCount)
      else { return nil }
      var next = chart
      next.dataRange = range
      switch axis {
      case .row:
        if let anchor = shiftIndex(
          chart.anchorRow, index: index, delta: delta, deleteCount: deleteCount)
        {
          next.anchorRow = anchor
        } else {
          return nil
        }
      case .column:
        if let anchor = shiftIndex(
          chart.anchorCol, index: index, delta: delta, deleteCount: deleteCount)
        {
          next.anchorCol = anchor
        } else {
          return nil
        }
      }
      return next
    }
    let headers = shiftFileExtras(
      &sheet.fileExtras, axis: axis, index: index, delta: delta, deleteCount: deleteCount)
    for (address, name) in headers where sheet.cell(at: address).raw.isEmpty {
      var cell = sheet.cell(at: address)
      cell.raw = name
      sheet.setCell(cell, at: address)
    }
    sheet.images = sheet.images.compactMap { image in
      var next = image
      switch axis {
      case .row:
        guard
          let anchor = shiftIndex(
            image.anchorRow, index: index, delta: delta, deleteCount: deleteCount)
        else {
          return nil
        }
        next.anchorRow = anchor
      case .column:
        guard
          let anchor = shiftIndex(
            image.anchorCol, index: index, delta: delta, deleteCount: deleteCount)
        else {
          return nil
        }
        next.anchorCol = anchor
      }
      return next
    }
  }

  /// Moves hidden and grouped rows or columns, dropdown rules, links, comments, tables and kept
  /// charts with the cells they belong to.
  /// Returns header cells for columns a table gained, so the sheet shows their names.
  private static func shiftFileExtras(
    _ extras: inout SheetFileExtras,
    axis: Axis,
    index: Int,
    delta: Int,
    deleteCount: Int
  ) -> [(CellAddress, String)] {
    guard !extras.isEmpty else { return [] }
    var newTableHeaders: [(CellAddress, String)] = []
    func shift(_ value: Int) -> Int? {
      shiftIndex(value, index: index, delta: delta, deleteCount: deleteCount)
    }
    func shiftSet(_ values: Set<Int>) -> Set<Int> { Set(values.compactMap(shift)) }
    func shiftLevels(_ levels: [Int: Int]) -> [Int: Int] {
      var result: [Int: Int] = [:]
      for (key, level) in levels {
        if let next = shift(key) { result[next] = level }
      }
      return result
    }
    func keep(_ range: CellRange) -> CellRange? {
      shiftRangeKeepingSurvivors(
        range, axis: axis, index: index, delta: delta, deleteCount: deleteCount)
    }
    if let area = extras.printArea { extras.printArea = keep(area) }
    // A pivot table drawn here moves with its cells; one whose corner is deleted goes.
    extras.sparkPivots = extras.sparkPivots.compactMap { pivot in
      var next = pivot
      switch axis {
      case .row:
        guard let row = shift(pivot.anchor.row) else { return nil }
        next.anchor = CellAddress(row: row, col: pivot.anchor.col)
      case .column:
        guard let col = shift(pivot.anchor.col) else { return nil }
        next.anchor = CellAddress(row: pivot.anchor.row, col: col)
      }
      return next
    }
    switch axis {
    case .row:
      extras.rowBreaks = shiftSet(extras.rowBreaks).filter { $0 > 0 }
      extras.hiddenRows = shiftSet(extras.hiddenRows)
      extras.rowOutlineLevels = shiftLevels(extras.rowOutlineLevels)
      extras.collapsedRows = shiftSet(extras.collapsedRows)
    case .column:
      extras.columnBreaks = shiftSet(extras.columnBreaks).filter { $0 > 0 }
      extras.hiddenColumns = shiftSet(extras.hiddenColumns)
      extras.columnOutlineLevels = shiftLevels(extras.columnOutlineLevels)
      extras.collapsedColumns = shiftSet(extras.collapsedColumns)
    }
    extras.dataValidations = extras.dataValidations.compactMap { rule in
      var next = rule
      next.ranges = rule.ranges.compactMap(keep)
      return next.ranges.isEmpty ? nil : next
    }
    extras.hyperlinks = extras.hyperlinks.compactMap { link in
      guard let range = keep(link.range) else { return nil }
      var next = link
      next.range = range
      return next
    }
    extras.comments = extras.comments.compactMap { comment in
      let moved: Int?
      var next = comment
      switch axis {
      case .row:
        moved = shift(comment.address.row)
        next.address = CellAddress(row: moved ?? 0, col: comment.address.col)
      case .column:
        moved = shift(comment.address.col)
        next.address = CellAddress(row: comment.address.row, col: moved ?? 0)
      }
      return moved == nil ? nil : next
    }
    extras.tables = extras.tables.compactMap { table in
      guard let range = keep(table.range) else { return nil }
      var next = table
      next.range = range
      // Columns added or removed inside a table join or leave its column list.
      guard axis == .column else { return next }
      let n = table.range.normalized
      if delta > 0, index > n.minCol, index <= n.maxCol {
        var used = Set(XLSXCodec.tableColumnNames(table.xml).map { $0.uppercased() })
        var names: [String] = []
        var number = 1
        while names.count < delta {
          let name = "Column\(number)"
          number += 1
          if used.insert(name.uppercased()).inserted { names.append(name) }
        }
        next.xml = XLSXCodec.tableXML(
          table.xml, insertingColumns: delta, atOffset: index - n.minCol, names: names)
        if XLSXCodec.tableHasHeaderRow(table.xml) {
          newTableHeaders.append(
            contentsOf: names.enumerated().map { offset, name in
              (CellAddress(row: range.normalized.minRow, col: index + offset), name)
            })
        }
      } else if delta < 0, index <= n.maxCol, index + deleteCount > n.minCol {
        guard
          let xml = XLSXCodec.tableXML(
            table.xml, removingColumns: deleteCount, atOffset: index - n.minCol)
        else { return nil }
        next.xml = xml
      }
      return next
    }
    extras.foreignCharts = extras.foreignCharts.compactMap { chart in
      guard var from = chart.from else { return chart }
      var next = chart
      switch axis {
      case .row:
        guard let row = shift(from.row) else { return nil }
        from.row = row
        if var to = chart.to {
          to.row = max(row, shift(to.row) ?? row)
          next.to = to
        }
      case .column:
        guard let col = shift(from.col) else { return nil }
        from.col = col
        if var to = chart.to {
          to.col = max(col, shift(to.col) ?? col)
          next.to = to
        }
      }
      next.from = from
      return next
    }
    return newTableHeaders
  }

  /// Like `shiftRange`, but a range that loses only some of its rows or columns keeps the rest.
  private static func shiftRangeKeepingSurvivors(
    _ range: CellRange,
    axis: Axis,
    index: Int,
    delta: Int,
    deleteCount: Int
  ) -> CellRange? {
    guard delta < 0 else {
      return shiftRange(range, axis: axis, index: index, delta: delta, deleteCount: deleteCount)
    }
    let n = range.normalized
    let low = axis == .row ? n.minRow : n.minCol
    let high = axis == .row ? n.maxRow : n.maxCol
    let deletedEnd = index + deleteCount
    let survivorsBefore = max(0, min(high, index - 1) - low + 1)
    let survivorsAfter = max(0, high - max(low, deletedEnd) + 1)
    let survivors = survivorsBefore + survivorsAfter
    guard survivors > 0 else { return nil }
    let newLow = low < index ? low : max(index, low - deleteCount)
    let newHigh = newLow + survivors - 1
    switch axis {
    case .row:
      return CellRange(
        start: CellAddress(row: newLow, col: n.minCol),
        end: CellAddress(row: newHigh, col: n.maxCol))
    case .column:
      return CellRange(
        start: CellAddress(row: n.minRow, col: newLow),
        end: CellAddress(row: n.maxRow, col: newHigh))
    }
  }

  private static func shiftRange(
    _ range: CellRange,
    axis: Axis,
    index: Int,
    delta: Int,
    deleteCount: Int
  ) -> CellRange? {
    let n = range.normalized
    switch axis {
    case .row:
      guard let minRow = shiftIndex(n.minRow, index: index, delta: delta, deleteCount: deleteCount),
        let maxRow = shiftIndex(n.maxRow, index: index, delta: delta, deleteCount: deleteCount)
      else { return nil }
      return CellRange(
        start: CellAddress(row: minRow, col: n.minCol),
        end: CellAddress(row: maxRow, col: n.maxCol)
      )
    case .column:
      guard let minCol = shiftIndex(n.minCol, index: index, delta: delta, deleteCount: deleteCount),
        let maxCol = shiftIndex(n.maxCol, index: index, delta: delta, deleteCount: deleteCount)
      else { return nil }
      return CellRange(
        start: CellAddress(row: n.minRow, col: minCol),
        end: CellAddress(row: n.maxRow, col: maxCol)
      )
    }
  }

  private static func shiftIndex(_ value: Int, index: Int, delta: Int, deleteCount: Int) -> Int? {
    if delta < 0 {
      let end = index + deleteCount
      if value >= index && value < end { return nil }
      if value >= end { return value + delta }
      return value
    }
    if value >= index { return value + delta }
    return value
  }

  private static func shiftColumnMap(
    _ map: [Int: Set<String>],
    index: Int,
    delta: Int,
    deleteCount: Int
  ) -> [Int: Set<String>] {
    var result: [Int: Set<String>] = [:]
    for (key, value) in map {
      if let next = shiftIndex(key, index: index, delta: delta, deleteCount: deleteCount) {
        result[next] = value
      }
    }
    return result
  }

  private static func shiftKeyedValues(_ values: [Int: CGFloat], threshold: Int, delta: Int)
    -> [Int: CGFloat]
  {
    var result: [Int: CGFloat] = [:]
    for (key, value) in values {
      if key >= threshold {
        result[key + delta] = value
      } else {
        result[key] = value
      }
    }
    return result
  }

  private static func deleteKeyedValues(_ values: [Int: CGFloat], range: Range<Int>) -> [Int:
    CGFloat]
  {
    values.filter { !range.contains($0.key) }
  }

  private static func ensureColumnCapacity(_ sheet: inout Sheet, through lastColumn: Int) {
    let needed = lastColumn + 1
    guard needed > sheet.effectiveColumnCount else { return }
    sheet.gridColumnCount = needed
  }

  private static func ensureRowCapacity(_ sheet: inout Sheet, through lastRow: Int) {
    let needed = lastRow + 1
    guard needed > sheet.effectiveRowCount else { return }
    sheet.gridRowCount = needed
  }
}
