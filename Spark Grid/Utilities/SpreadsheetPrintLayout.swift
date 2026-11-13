import AppKit
import SparkGridCore

/// Where each printed page starts and ends. Pages end on row and column edges, start again at
/// manual page breaks, and repeat the column letters and row numbers. With "Repeat frozen rows"
/// on, the frozen rows print at the top of every page after the first; frozen columns likewise.
struct SpreadsheetPrintLayout {
  /// A strip of the grid view in its own coordinates, along one axis.
  struct Band: Equatable {
    var origin: CGFloat
    var length: CGFloat
  }

  struct Page: Equatable {
    var rows: ClosedRange<Int>
    var columns: ClosedRange<Int>
    /// Top to bottom: headers, repeated rows, then this page's rows.
    var yBands: [Band]
    /// Left to right: headers, repeated columns, then this page's columns.
    var xBands: [Band]

    var contentSize: NSSize {
      NSSize(
        width: xBands.reduce(0) { $0 + $1.length }, height: yBands.reduce(0) { $0 + $1.length })
    }
  }

  let scale: CGFloat
  let pages: [Page]

  init(gridView: SpreadsheetPrintNSView, sheet: Sheet, options: SpreadsheetPrintOptions) {
    let natural = gridView.bounds.size
    let scale = options.fitScale(forContent: natural)
    self.scale = scale
    let n = gridView.normalized
    let rows = n.minRow...gridView.maxRow
    let columns = n.minCol...n.maxCol
    let margin = options.margins.inset
    let printableWidth = max(1, options.pageSize.width - margin * 2) / max(scale, 0.0001)
    let printableHeight = max(1, options.pageSize.height - margin * 2) / max(scale, 0.0001)

    func rowY(_ row: Int) -> CGFloat { gridView.rowYs[row - n.minRow] }
    func rowHeight(_ row: Int) -> CGFloat { gridView.rowHeights[row - n.minRow] }
    func colX(_ col: Int) -> CGFloat { gridView.columnXs[col - n.minCol] }
    func colWidth(_ col: Int) -> CGFloat { gridView.columnWidths[col - n.minCol] }

    // Frozen rows and columns inside the printed range repeat when asked.
    let titleRows: ClosedRange<Int>? = {
      guard options.repeatFrozenRows, sheet.frozenRows > 0, rows.lowerBound < sheet.frozenRows
      else { return nil }
      return rows.lowerBound...min(sheet.frozenRows - 1, rows.upperBound)
    }()
    let titleColumns: ClosedRange<Int>? = {
      guard options.repeatFrozenColumns, sheet.frozenColumns > 0,
        columns.lowerBound < sheet.frozenColumns
      else { return nil }
      return columns.lowerBound...min(sheet.frozenColumns - 1, columns.upperBound)
    }()
    let titleHeight = titleRows.map { r in r.reduce(CGFloat(0)) { $0 + rowHeight($1) } } ?? 0
    let titleWidth = titleColumns.map { c in c.reduce(CGFloat(0)) { $0 + colWidth($1) } } ?? 0
    let headerHeight = gridView.headerHeight
    let headerWidth = gridView.headerWidth

    // Fit to page puts everything on one page; fit to width puts every column on each page.
    let extras = sheet.fileExtras
    let rowRuns: [ClosedRange<Int>]
    if options.scale == .fitToPage {
      rowRuns = [rows]
    } else {
      rowRuns = PrintPagination.split(
        first: rows.lowerBound,
        sizes: rows.map { Double(rowHeight($0)) },
        available: Double(printableHeight - headerHeight - titleHeight),
        breaks: extras.rowBreaks)
    }
    let columnRuns: [ClosedRange<Int>]
    if options.scale != .normal {
      columnRuns = [columns]
    } else {
      columnRuns = PrintPagination.split(
        first: columns.lowerBound,
        sizes: columns.map { Double(colWidth($0)) },
        available: Double(printableWidth - headerWidth - titleWidth),
        breaks: extras.columnBreaks)
    }

    let tiles = PrintPagination.pages(
      rows: rowRuns, columns: columnRuns, overThenDown: options.pageOrder == .overThenDown)
    pages = tiles.map { tile in
      var yBands = [Band(origin: 0, length: headerHeight)]
      if let titleRows, tile.rows.lowerBound > titleRows.upperBound {
        yBands.append(Band(origin: rowY(titleRows.lowerBound), length: titleHeight))
      }
      let top = rowY(tile.rows.lowerBound)
      yBands.append(
        Band(
          origin: top, length: rowY(tile.rows.upperBound) + rowHeight(tile.rows.upperBound) - top))
      var xBands = [Band(origin: 0, length: headerWidth)]
      if let titleColumns, tile.columns.lowerBound > titleColumns.upperBound {
        xBands.append(Band(origin: colX(titleColumns.lowerBound), length: titleWidth))
      }
      let left = colX(tile.columns.lowerBound)
      xBands.append(
        Band(
          origin: left,
          length: colX(tile.columns.upperBound) + colWidth(tile.columns.upperBound) - left))
      return Page(rows: tile.rows, columns: tile.columns, yBands: yBands, xBands: xBands)
    }
  }

  /// Draws `page` of the grid on paper, scaled and placed by the alignment options.
  static func draw(
    page: Page, of gridView: SpreadsheetPrintNSView, scale: CGFloat,
    options: SpreadsheetPrintOptions, in context: CGContext
  ) {
    let origin = options.contentOrigin(contentSize: page.contentSize, scale: scale)
    var y = origin.y
    for yBand in page.yBands where yBand.length > 0 {
      var x = origin.x
      for xBand in page.xBands where xBand.length > 0 {
        let source = NSRect(
          x: xBand.origin, y: yBand.origin, width: xBand.length, height: yBand.length)
        context.saveGState()
        context.translateBy(x: x, y: y)
        context.scaleBy(x: scale, y: scale)
        context.clip(to: CGRect(origin: .zero, size: source.size))
        context.translateBy(x: -source.minX, y: -source.minY)
        gridView.draw(source)
        context.restoreGState()
        x += xBand.length * scale
      }
      y += yBand.length * scale
    }
  }
}
