import AppKit
import Calc
import Formula
import Foundation
import GridCore
import Model
import NumberFormat

/// Overflow, wrap, and clip geometry shared by the grid, printing, and tests.
public enum CellTextLayout {
  /// Safety cap so one wrapped cell cannot stretch a row without bound.
  public static let maxWrappedRowHeight: CGFloat = 4096

  /// Caller inset (scaled) plus the extra inset inside `CellFormatRenderer.drawText`.
  public static func horizontalInset(zoom: CGFloat) -> CGFloat {
    4 * zoom + 4
  }

  public static func verticalInset(zoom: CGFloat) -> CGFloat {
    2 * zoom + 2
  }

  public struct OverflowClip: Equatable {
    public var minX: CGFloat
    public var maxX: CGFloat

    public var width: CGFloat { max(0, maxX - minX) }
  }

  /// A neighbor blocks spill when it has visible text or belongs to a merge.
  /// A fill with no text does not.
  public static func blocksOverflow(
    sheet: Sheet,
    row: Int,
    column: Int,
    displayText: (CellAddress) -> String
  ) -> Bool {
    guard column >= 0, row >= 0 else { return true }
    let address = CellAddress(row: row, col: column)
    if sheet.isCoveredByMerge(address) || sheet.mergeContaining(address) != nil {
      return true
    }
    return !displayText(address).isEmpty
  }

  /// Horizontal clip for one cell. Text may cross empty neighbors and stops at the next border that has content.
  public static func overflowClip(
    cellMinX: CGFloat,
    cellMaxX: CGFloat,
    textWidth: CGFloat,
    alignment: CellFormat.HorizontalAlign,
    insetX: CGFloat,
    sourceColumns: ClosedRange<Int>,
    paneColumns: ClosedRange<Int>,
    columnOrigin: (Int) -> CGFloat,
    columnWidth: (Int) -> CGFloat,
    blocks: (Int) -> Bool
  ) -> OverflowClip {
    let available = max(0, cellMaxX - cellMinX - insetX * 2)
    let spills = textWidth > available + 0.5

    let textStart: CGFloat
    let textEnd: CGFloat
    switch alignment {
    case .right:
      textEnd = cellMaxX - insetX
      textStart = textEnd - textWidth
    case .center:
      let mid = (cellMinX + cellMaxX) / 2
      textStart = mid - textWidth / 2
      textEnd = mid + textWidth / 2
    case .left, .general:
      textStart = cellMinX + insetX
      textEnd = textStart + textWidth
    }

    var minX = cellMinX
    var maxX = cellMaxX
    if spills {
      minX = min(minX, textStart)
      maxX = max(maxX, textEnd)
      let spillsLeft = alignment == .right || alignment == .center
      let spillsRight = alignment != .right
      if spillsRight,
        let boundary = blockBoundary(
          from: sourceColumns,
          towardHigherColumns: true,
          paneColumns: paneColumns,
          columnOrigin: columnOrigin,
          columnWidth: columnWidth,
          blocks: blocks
        )
      {
        maxX = min(maxX, boundary)
      }
      if spillsLeft,
        let boundary = blockBoundary(
          from: sourceColumns,
          towardHigherColumns: false,
          paneColumns: paneColumns,
          columnOrigin: columnOrigin,
          columnWidth: columnWidth,
          blocks: blocks
        )
      {
        minX = max(minX, boundary)
      }
      let leftLimit = columnOrigin(paneColumns.lowerBound)
      let rightColumn = paneColumns.upperBound
      let rightLimit = columnOrigin(rightColumn) + columnWidth(rightColumn)
      minX = max(minX, leftLimit)
      maxX = min(maxX, rightLimit)
    }
    if maxX < minX { maxX = minX }
    return OverflowClip(minX: minX, maxX: maxX)
  }

  /// Height of wrapped text plus the padding `drawText` uses. Zero when the cell is not wrapping.
  public static func preferredWrappedRowHeight(
    text: String,
    format: CellFormat,
    columnWidth: CGFloat,
    zoom: CGFloat = 1,
    extraWidthInset: CGFloat = 0
  ) -> CGFloat {
    guard format.textDisplay == .wrap, !text.isEmpty else { return 0 }
    var scaled = format
    let base = scaled.fontSize ?? CellFormatRenderer.defaultFontSize
    scaled.fontSize = base * zoom
    let contentWidth = max(
      1, columnWidth * zoom - horizontalInset(zoom: zoom) * 2 - extraWidthInset)
    let bounds = (text as NSString).boundingRect(
      with: NSSize(width: contentWidth, height: 10_000),
      options: [.usesLineFragmentOrigin, .usesFontLeading],
      attributes: CellFormatRenderer.attributes(for: scaled)
    )
    let height = ceil(bounds.height) + verticalInset(zoom: zoom) * 2 + 1
    return min(maxWrappedRowHeight, max(0, height))
  }

  /// Wrapped height for a single row (scaled). Zero when the row has no wrap cells.
  public static func wrappedRowHeight(
    row: Int,
    sheet: Sheet,
    defaultRowHeight: CGFloat,
    defaultColumnWidth: CGFloat,
    zoom: CGFloat = 1,
    columnWidth: (Int) -> CGFloat,
    displayText: (CellAddress) -> String,
    extraWidthInset: (CellAddress) -> CGFloat = { _ in 0 }
  ) -> CGFloat {
    var required: CGFloat = 0
    for (address, cell) in sheet.cells where address.row == row {
      guard let format = cell.format, format.textDisplay == .wrap else { continue }
      if sheet.isCoveredByMerge(address) { continue }
      let text = displayText(address)
      guard !text.isEmpty else { continue }
      let width = columnSpanWidth(
        for: address,
        sheet: sheet,
        columnWidth: columnWidth,
        defaultColumnWidth: defaultColumnWidth
      )
      let needed = preferredWrappedRowHeight(
        text: text,
        format: format,
        columnWidth: width,
        zoom: zoom,
        extraWidthInset: extraWidthInset(address)
      )
      guard needed > 0 else { continue }
      if let merge = sheet.mergeContaining(address) {
        let rows = merge.normalized
        if rows.minRow == rows.maxRow {
          required = max(required, needed)
        } else {
          var others: CGFloat = 0
          if rows.minRow < rows.maxRow {
            for mergeRow in (rows.minRow + 1)...rows.maxRow {
              others += sheet.rowHeight(for: mergeRow, default: defaultRowHeight) * zoom
            }
          }
          let anchorNeed = max(0, needed - others)
          required = max(required, anchorNeed)
        }
      } else {
        required = max(required, needed)
      }
    }
    return required
  }

  /// Minimum row heights (already scaled by `zoom`) required by wrapped cells. The tallest cell on a row wins.
  public static func wrappedRowHeights(
    sheet: Sheet,
    defaultRowHeight: CGFloat,
    defaultColumnWidth: CGFloat,
    zoom: CGFloat = 1,
    columnWidth: (Int) -> CGFloat,
    displayText: (CellAddress) -> String,
    extraWidthInset: (CellAddress) -> CGFloat = { _ in 0 }
  ) -> [Int: CGFloat] {
    var required: [Int: CGFloat] = [:]
    for (address, cell) in sheet.cells {
      guard let format = cell.format, format.textDisplay == .wrap else { continue }
      if sheet.isCoveredByMerge(address) { continue }
      let text = displayText(address)
      guard !text.isEmpty else { continue }
      let width = columnSpanWidth(
        for: address,
        sheet: sheet,
        columnWidth: columnWidth,
        defaultColumnWidth: defaultColumnWidth
      )
      let needed = preferredWrappedRowHeight(
        text: text,
        format: format,
        columnWidth: width,
        zoom: zoom,
        extraWidthInset: extraWidthInset(address)
      )
      guard needed > 0 else { continue }
      if let merge = sheet.mergeContaining(address) {
        let rows = merge.normalized
        if rows.minRow == rows.maxRow {
          required[rows.minRow] = max(required[rows.minRow] ?? 0, needed)
        } else {
          var others: CGFloat = 0
          if rows.minRow < rows.maxRow {
            for row in (rows.minRow + 1)...rows.maxRow {
              others += sheet.rowHeight(for: row, default: defaultRowHeight) * zoom
            }
          }
          let anchorNeed = max(0, needed - others)
          required[rows.minRow] = max(required[rows.minRow] ?? 0, anchorNeed)
        }
      } else {
        required[address.row] = max(required[address.row] ?? 0, needed)
      }
    }
    return required
  }

  /// Wrapped height for `rows` only. Other rows are left out of the result.
  public static func wrappedRowHeights(
    rows: Set<Int>,
    sheet: Sheet,
    defaultRowHeight: CGFloat,
    defaultColumnWidth: CGFloat,
    zoom: CGFloat = 1,
    columnWidth: (Int) -> CGFloat,
    displayText: (CellAddress) -> String,
    extraWidthInset: (CellAddress) -> CGFloat = { _ in 0 }
  ) -> [Int: CGFloat] {
    guard !rows.isEmpty else { return [:] }
    var required: [Int: CGFloat] = [:]
    for (address, cell) in sheet.cells {
      guard let format = cell.format, format.textDisplay == .wrap else { continue }
      if sheet.isCoveredByMerge(address) { continue }
      let targetRow = sheet.mergeContaining(address)?.normalized.minRow ?? address.row
      guard rows.contains(targetRow) else { continue }
      let text = displayText(address)
      guard !text.isEmpty else { continue }
      let width = columnSpanWidth(
        for: address,
        sheet: sheet,
        columnWidth: columnWidth,
        defaultColumnWidth: defaultColumnWidth
      )
      let needed = preferredWrappedRowHeight(
        text: text,
        format: format,
        columnWidth: width,
        zoom: zoom,
        extraWidthInset: extraWidthInset(address)
      )
      guard needed > 0 else { continue }
      if let merge = sheet.mergeContaining(address) {
        let span = merge.normalized
        if span.minRow == span.maxRow {
          required[span.minRow] = max(required[span.minRow] ?? 0, needed)
        } else {
          var others: CGFloat = 0
          if span.minRow < span.maxRow {
            for row in (span.minRow + 1)...span.maxRow {
              others += sheet.rowHeight(for: row, default: defaultRowHeight) * zoom
            }
          }
          let anchorNeed = max(0, needed - others)
          required[span.minRow] = max(required[span.minRow] ?? 0, anchorNeed)
        }
      } else {
        required[address.row] = max(required[address.row] ?? 0, needed)
      }
    }
    return required
  }

  public static func displayRowHeight(
    row: Int,
    sheet: Sheet,
    defaultRowHeight: CGFloat,
    wrapped: [Int: CGFloat],
    zoom: CGFloat = 1
  ) -> CGFloat {
    if sheet.isRowHidden(row) { return 0 }
    let stored = sheet.rowHeight(for: row, default: defaultRowHeight) * zoom
    return max(stored, wrapped[row] ?? 0)
  }

  private static func columnSpanWidth(
    for address: CellAddress,
    sheet: Sheet,
    columnWidth: (Int) -> CGFloat,
    defaultColumnWidth: CGFloat
  ) -> CGFloat {
    if let merge = sheet.mergeContaining(address) {
      let columns = merge.normalized
      var total: CGFloat = 0
      for col in columns.minCol...columns.maxCol {
        total += columnWidth(col)
      }
      return total > 0 ? total : defaultColumnWidth
    }
    return columnWidth(address.col)
  }

  private static func blockBoundary(
    from sourceColumns: ClosedRange<Int>,
    towardHigherColumns: Bool,
    paneColumns: ClosedRange<Int>,
    columnOrigin: (Int) -> CGFloat,
    columnWidth: (Int) -> CGFloat,
    blocks: (Int) -> Bool
  ) -> CGFloat? {
    if towardHigherColumns {
      var column = sourceColumns.upperBound + 1
      while column <= paneColumns.upperBound {
        if blocks(column) { return columnOrigin(column) }
        column += 1
      }
      return nil
    }
    var column = sourceColumns.lowerBound - 1
    while column >= paneColumns.lowerBound {
      if blocks(column) { return columnOrigin(column) + columnWidth(column) }
      column -= 1
    }
    return nil
  }
}
