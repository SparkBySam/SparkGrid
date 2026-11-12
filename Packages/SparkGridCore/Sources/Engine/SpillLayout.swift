import Calc
import Formula
import Foundation
import GridCore
import Model

/// Places array formula results in the cells below and beside each formula. The spilled cells
/// hold the values with nothing typed, as other spreadsheet apps save them. A formula whose
/// results would cover a typed cell, or another formula's results, shows #SPILL! instead.
public nonisolated enum SpillLayout {
  /// Cells holding a formula that can spill, in reading order.
  public static func anchors(in sheet: Sheet) -> [CellAddress] {
    var found: [CellAddress] = []
    for (address, raw) in sheet.formulaIngestByColumn.values.joined() {
      let upper = raw.uppercased()
      guard
        FormulaEvaluator.arrayFunctionNames.contains(where: { upper.contains($0 + "(") }),
        let expr = try? FormulaParser.parse(raw), FormulaEvaluator.spills(expr)
      else { continue }
      found.append(address)
    }
    return found.sorted { ($0.row, $0.col) < ($1.row, $1.col) }
  }

  /// Blanks in a spilled result show as 0, as other apps show them.
  static func shown(_ value: CellValue) -> CellValue {
    if case .blank = value { return .number(0) }
    return value
  }

  /// `cell` without a spilled value, or nil when nothing else is in it. A cell that is not
  /// spilled comes back as it is.
  public static func withoutSpilledValue(_ cell: Cell) -> Cell? {
    guard cell.isSpilled else { return cell }
    var bare = cell
    bare.importedFormulaResult = nil
    bare.importedFormulaValueType = nil
    return bare.isEmpty ? nil : bare
  }

  /// Takes every spilled value off the sheet, and the record of where each formula spilled.
  /// The formulas stay, so the next `apply` fills their results in again.
  ///
  /// Run this before cells move: rows or columns inserted or deleted, or a sort. A spilled
  /// value that moved would belong to no formula, and would stay behind as if it were typed.
  /// Returns the cells that held a spilled value.
  @discardableResult
  public static func clearSpills(in sheet: inout Sheet) -> Set<CellAddress> {
    var cleared = Set<CellAddress>()
    for (address, cell) in sheet.cells where cell.isSpilled {
      cleared.insert(address)
    }
    for address in cleared {
      // Straight into the cell map: nothing typed changes, and the extents are found once.
      if let bare = sheet.cells[address].flatMap(withoutSpilledValue) {
        sheet.cells[address] = bare
      } else {
        sheet.cells.removeValue(forKey: address)
      }
    }
    if !cleared.isEmpty { sheet.recomputePopulatedExtents() }
    sheet.fileExtras.spills = [:]
    sheet.fileExtras.blockedSpills = []
    return cleared
  }

  public struct Outcome: Equatable, Sendable {
    /// Spilled cells whose value changed, appeared or went away.
    public var changedCells: Set<CellAddress>
    /// Formula cells that started or stopped showing #SPILL!.
    public var changedAnchors: Set<CellAddress>
  }

  /// Writes each anchor's result into `sheet`. `arrays` holds the result of every formula that
  /// can spill; a missing or single-value result spills nothing.
  @discardableResult
  public static func apply(
    _ arrays: [CellAddress: ArrayResult], to sheet: inout Sheet
  ) -> Outcome {
    let oldSpills = sheet.fileExtras.spills
    let oldBlocked = sheet.fileExtras.blockedSpills
    // The largest sheet other apps open: 1,048,576 rows by 16,384 columns.
    let maxRow = 1_048_575
    let maxCol = 16_383
    var spills: [CellAddress: CellRange] = [:]
    var blocked = Set<CellAddress>()
    var claimed: [CellAddress: CellAddress] = [:]
    var wanted: [CellAddress: CellValue] = [:]

    for anchor in arrays.keys.sorted(by: { ($0.row, $0.col) < ($1.row, $1.col) }) {
      guard let array = arrays[anchor], !array.isSingle, array.rows > 0, array.cols > 0 else {
        continue
      }
      let end = CellAddress(row: anchor.row + array.rows - 1, col: anchor.col + array.cols - 1)
      var free = end.row <= maxRow && end.col <= maxCol
      if free {
        scan: for row in anchor.row...end.row {
          for col in anchor.col...end.col {
            let address = CellAddress(row: row, col: col)
            if address == anchor { continue }
            if claimed[address] != nil || !sheet.cell(at: address).raw.isEmpty {
              free = false
              break scan
            }
          }
        }
      }
      guard free else {
        blocked.insert(anchor)
        continue
      }
      spills[anchor] = CellRange(start: anchor, end: end)
      for row in anchor.row...end.row {
        for col in anchor.col...end.col {
          let address = CellAddress(row: row, col: col)
          claimed[address] = anchor
          if address == anchor { continue }
          wanted[address] = shown(array.value(row: row - anchor.row, col: col - anchor.col))
        }
      }
    }

    // Every cell an old or new spill covers, apart from the formulas themselves.
    var touched = Set(wanted.keys)
    for (anchor, range) in oldSpills {
      for address in range.allAddresses() where address != anchor { touched.insert(address) }
    }
    var changed = Set<CellAddress>()
    for address in touched {
      var cell = sheet.cell(at: address)
      // Something typed since stays; its formula now shows #SPILL!.
      guard cell.raw.isEmpty else { continue }
      let before = cell.cachedFormulaValue
      if let value = wanted[address] {
        let stored = value.importedCacheStorage
        cell.importedFormulaResult = stored.text
        cell.importedFormulaValueType = stored.type
      } else {
        cell.importedFormulaResult = nil
        cell.importedFormulaValueType = nil
      }
      guard cell.cachedFormulaValue != before else { continue }
      changed.insert(address)
      sheet.setCell(cell, at: address)
    }
    sheet.fileExtras.spills = spills
    sheet.fileExtras.blockedSpills = blocked
    return Outcome(
      changedCells: changed, changedAnchors: blocked.symmetricDifference(oldBlocked))
  }
}
