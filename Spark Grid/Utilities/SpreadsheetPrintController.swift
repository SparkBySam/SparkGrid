import AppKit
import SparkGridCore
import SwiftUI

/// Renders one sheet region for print preview and printing.
final class SpreadsheetPrintNSView: NSView {
  private let sheet: Sheet
  private let formulaEngine: FormulaEngine
  private let showGridlines: Bool
  private let normalized: (minRow: Int, maxRow: Int, minCol: Int, maxCol: Int)
  private let maxRow: Int
  private let columnXs: [CGFloat]
  private let columnWidths: [CGFloat]
  private let rowYs: [CGFloat]
  private let rowHeights: [CGFloat]

  static let headerWidth: CGFloat = 28
  static let headerHeight: CGFloat = 20

  override var isFlipped: Bool { true }

  init(
    sheet: Sheet,
    range: CellRange,
    showGridlines: Bool = true,
    previewRowCap: Int? = nil,
    workbook: Workbook? = nil,
    hiddenRows: Set<Int> = []
  ) {
    self.sheet = sheet
    let engine = FormulaEngine()
    if let workbook {
      var wb = workbook
      if let index = wb.sheets.firstIndex(where: { $0.id == sheet.id }) {
        wb.activeSheetIndex = index
      } else if let index = wb.sheets.firstIndex(where: { $0.name == sheet.name }) {
        wb.activeSheetIndex = index
      }
      // Prefer the concrete sheet snapshot being printed.
      if wb.sheets.indices.contains(wb.activeSheetIndex) {
        wb.sheets[wb.activeSheetIndex] = sheet
      }
      engine.rebuild(workbook: wb, recalculate: true)
    } else {
      engine.rebuild(sheet: sheet)
    }
    self.formulaEngine = engine
    self.showGridlines = showGridlines
    let normalized = range.normalized
    self.normalized = normalized
    let maxRow = previewRowCap.map { min($0, normalized.maxRow) } ?? normalized.maxRow
    self.maxRow = maxRow

    var columnWidths: [CGFloat] = []
    var columnXs: [CGFloat] = []
    var x = Self.headerWidth
    for col in normalized.minCol...normalized.maxCol {
      let width = sheet.columnWidth(for: col, default: Workbook.defaultColumnWidth)
      columnXs.append(x)
      columnWidths.append(width)
      x += width
    }
    self.columnXs = columnXs
    self.columnWidths = columnWidths

    let wrappedHeights = CellTextLayout.wrappedRowHeights(
      sheet: sheet,
      defaultRowHeight: Workbook.defaultRowHeight,
      defaultColumnWidth: Workbook.defaultColumnWidth,
      zoom: 1,
      columnWidth: { sheet.columnWidth(for: $0, default: Workbook.defaultColumnWidth) },
      displayText: { address in
        engine.displayString(at: address, sheet: sheet, format: sheet.cell(at: address).format)
      }
    )
    var rowHeights: [CGFloat] = []
    var rowYs: [CGFloat] = []
    var y = Self.headerHeight
    for row in normalized.minRow...maxRow {
      let height =
        hiddenRows.contains(row)
        ? 0
        : CellTextLayout.displayRowHeight(
          row: row,
          sheet: sheet,
          defaultRowHeight: Workbook.defaultRowHeight,
          wrapped: wrappedHeights
        )
      rowYs.append(y)
      rowHeights.append(height)
      y += height
    }
    self.rowYs = rowYs
    self.rowHeights = rowHeights

    let size = NSSize(
      width: max(x, Self.headerWidth + Workbook.defaultColumnWidth),
      height: max(y, Self.headerHeight + Workbook.defaultRowHeight)
    )
    super.init(frame: NSRect(origin: .zero, size: size))
    appearance = NSAppearance(named: .aqua)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  override var isOpaque: Bool { true }

  override func knowsPageRange(_ range: NSRangePointer) -> Bool {
    range.pointee = NSRange(location: 1, length: 1)
    return true
  }

  override func rectForPage(_ page: Int) -> NSRect {
    bounds
  }

  override func draw(_ dirtyRect: NSRect) {
    NSColor.white.setFill()
    bounds.fill()

    let gridLine = NSColor(calibratedWhite: 0.75, alpha: 1.0)
    let headerFill = NSColor(calibratedWhite: 0.92, alpha: 1.0)
    let headerText = NSColor(calibratedWhite: 0.35, alpha: 1.0)

    // Fast gridlines: one stroke per edge instead of a rect per cell.
    if showGridlines {
      drawGridLines(gridLine: gridLine)
    }

    // Fills and in-cell text first, then overflow so a later fill cannot cover spilled text.
    drawSheetCells(overflowPass: false)
    drawSheetCells(overflowPass: true)

    let corner = NSRect(x: 0, y: 0, width: Self.headerWidth, height: Self.headerHeight)
    headerFill.setFill()
    corner.fill()
    if showGridlines {
      gridLine.setStroke()
      NSBezierPath.strokeLine(
        from: NSPoint(x: corner.maxX, y: 0), to: NSPoint(x: corner.maxX, y: corner.maxY))
      NSBezierPath.strokeLine(
        from: NSPoint(x: 0, y: corner.maxY), to: NSPoint(x: corner.maxX, y: corner.maxY))
    }

    for col in normalized.minCol...normalized.maxCol {
      let colIndex = col - normalized.minCol
      let header = NSRect(
        x: columnXs[colIndex],
        y: 0,
        width: columnWidths[colIndex],
        height: Self.headerHeight
      )
      headerFill.setFill()
      header.fill()
      if showGridlines {
        gridLine.setStroke()
        NSBezierPath(rect: header.insetBy(dx: 0.5, dy: 0.5)).stroke()
      }
      CellFormatRenderer.drawCenteredLabel(
        A1Notation.columnLabel(for: col),
        in: header,
        font: NSFont.systemFont(ofSize: 9, weight: .medium),
        color: headerText
      )
    }

    for row in normalized.minRow...maxRow {
      let rowIndex = row - normalized.minRow
      guard rowHeights[rowIndex] > 0 else { continue }
      let header = NSRect(
        x: 0,
        y: rowYs[rowIndex],
        width: Self.headerWidth,
        height: rowHeights[rowIndex]
      )
      headerFill.setFill()
      header.fill()
      if showGridlines {
        gridLine.setStroke()
        NSBezierPath(rect: header.insetBy(dx: 0.5, dy: 0.5)).stroke()
      }
      CellFormatRenderer.drawCenteredLabel(
        "\(row + 1)",
        in: header,
        font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular),
        color: headerText
      )
    }
  }

  private func drawGridLines(gridLine: NSColor) {
    guard
      let firstColX = columnXs.first,
      let lastColX = columnXs.last,
      let lastColW = columnWidths.last
    else { return }

    let visibleRowYs = zip(rowYs, rowHeights).compactMap { y, h -> CGFloat? in h > 0 ? y : nil }
    var lastVisibleY: CGFloat?
    var lastVisibleH: CGFloat?
    for (y, h) in zip(rowYs, rowHeights) where h > 0 {
      lastVisibleY = y
      lastVisibleH = h
    }
    guard let firstRowY = visibleRowYs.first ?? rowYs.first,
      let lastRowY = lastVisibleY,
      let lastRowH = lastVisibleH
    else { return }

    let gridMinX = firstColX
    let gridMaxX = lastColX + lastColW
    let gridMinY = firstRowY
    let gridMaxY = lastRowY + lastRowH

    gridLine.setStroke()
    let path = NSBezierPath()
    path.lineWidth = 1

    for x in columnXs {
      path.move(to: NSPoint(x: x + 0.5, y: gridMinY))
      path.line(to: NSPoint(x: x + 0.5, y: gridMaxY))
    }
    path.move(to: NSPoint(x: gridMaxX + 0.5, y: gridMinY))
    path.line(to: NSPoint(x: gridMaxX + 0.5, y: gridMaxY))

    for y in visibleRowYs {
      path.move(to: NSPoint(x: gridMinX, y: y + 0.5))
      path.line(to: NSPoint(x: gridMaxX, y: y + 0.5))
    }
    path.move(to: NSPoint(x: gridMinX, y: gridMaxY + 0.5))
    path.line(to: NSPoint(x: gridMaxX, y: gridMaxY + 0.5))
    path.stroke()
  }

  private func drawSheetCells(overflowPass: Bool) {
    for (address, cell) in sheet.cells {
      guard
        address.row >= normalized.minRow,
        address.row <= maxRow,
        address.col >= normalized.minCol,
        address.col <= normalized.maxCol
      else { continue }
      let rowIndex = address.row - normalized.minRow
      guard rowHeights[rowIndex] > 0 else { continue }
      let colIndex = address.col - normalized.minCol
      let rect = NSRect(
        x: columnXs[colIndex],
        y: rowYs[rowIndex],
        width: columnWidths[colIndex],
        height: rowHeights[rowIndex]
      )
      drawCellContent(cell, at: address, in: rect, overflowPass: overflowPass)
    }
  }

  private func drawCellContent(
    _ cell: Cell, at address: CellAddress, in rect: NSRect, overflowPass: Bool
  ) {
    let paintFormat = resolvedFormat(at: address, cell: cell)
    let format = paintFormat ?? CellFormat()
    if !overflowPass, let fill = CellFormatRenderer.fillColor(for: paintFormat) {
      fill.setFill()
      rect.fill()
    }

    if !cell.raw.isEmpty, format.overflowsUnclipped == overflowPass {
      let text = formulaEngine.displayString(at: address, sheet: sheet, format: cell.format)
      let textRect = rect.insetBy(dx: 4, dy: 2)
      if textRect.width > 1, textRect.height > 1, !text.isEmpty {
        let clip =
          overflowPass
          ? overflowClipRect(
            for: address, text: text, format: format, textRect: textRect, cellRect: rect) : rect
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: clip).addClip()
        CellFormatRenderer.drawText(
          text,
          in: textRect,
          format: paintFormat,
          onLightBackground: true
        )
        NSGraphicsContext.restoreGraphicsState()
      }
    }

    if !overflowPass, let borders = paintFormat?.borders, borders.hasAny {
      CellFormatRenderer.drawBorders(borders, in: rect)
    }
  }

  private func overflowClipRect(
    for address: CellAddress,
    text: String,
    format: CellFormat,
    textRect: NSRect,
    cellRect: NSRect
  ) -> NSRect {
    let textWidth = CellFormatRenderer.overflowWidth(for: text, format: format)
    let sourceColumns: ClosedRange<Int>
    if let merge = sheet.mergeContaining(address) {
      let span = merge.normalized
      sourceColumns = span.minCol...span.maxCol
    } else {
      sourceColumns = address.col...address.col
    }
    let pane = normalized.minCol...normalized.maxCol
    let horizontal = CellTextLayout.overflowClip(
      cellMinX: textRect.minX,
      cellMaxX: textRect.maxX,
      textWidth: textWidth,
      alignment: format.horizontalAlign,
      insetX: 4,
      sourceColumns: sourceColumns,
      paneColumns: pane,
      columnOrigin: { self.columnOrigin($0) },
      columnWidth: { self.printedColumnWidth($0) },
      blocks: { column in
        CellTextLayout.blocksOverflow(sheet: self.sheet, row: address.row, column: column) {
          neighbor in
          let neighborCell = self.sheet.cell(at: neighbor)
          return self.formulaEngine.displayString(
            at: neighbor, sheet: self.sheet, format: neighborCell.format)
        }
      }
    )
    return NSRect(
      x: horizontal.minX, y: cellRect.minY, width: horizontal.width, height: cellRect.height)
  }

  private func columnOrigin(_ col: Int) -> CGFloat {
    let index = col - normalized.minCol
    if columnXs.indices.contains(index) { return columnXs[index] }
    if col < normalized.minCol { return columnXs.first ?? Self.headerWidth }
    let lastX = columnXs.last ?? Self.headerWidth
    let lastWidth = columnWidths.last ?? Workbook.defaultColumnWidth
    return lastX + lastWidth
  }

  private func printedColumnWidth(_ col: Int) -> CGFloat {
    let index = col - normalized.minCol
    guard columnWidths.indices.contains(index) else { return Workbook.defaultColumnWidth }
    return columnWidths[index]
  }

  private func resolvedFormat(at address: CellAddress, cell: Cell) -> CellFormat? {
    let rules = sheet.conditionalFormats
    guard !rules.isEmpty else { return cell.format }
    let value = formulaEngine.displayValue(at: address, sheet: sheet)
    let text = formulaEngine.displayString(at: address, sheet: sheet, format: cell.format)
    return ConditionalFormatEvaluator.resolvedFormat(
      at: address,
      base: cell.format,
      rules: rules,
      value: value,
      displayString: text,
      numberFormat: cell.format?.numberFormat,
      numericValuesInRange: { [sheet, formulaEngine] range in
        let n = range.normalized
        var values: [Double] = []
        for row in n.minRow...n.maxRow {
          for col in n.minCol...n.maxCol {
            if let number = formulaEngine.displayValue(
              at: CellAddress(row: row, col: col),
              sheet: sheet
            ).asNumber {
              values.append(number)
            }
          }
        }
        return values
      },
      evaluateFormula: { [formulaEngine, sheet] raw, addr, origin in
        formulaEngine.evaluateConditionalFormula(raw, at: addr, relativeTo: origin, sheet: sheet)
      }
    )
  }

  private func drawCell(_ cell: Cell, at address: CellAddress, in rect: NSRect, gridLine: NSColor) {
    let paintFormat = resolvedFormat(at: address, cell: cell)
    drawCellContent(cell, at: address, in: rect, overflowPass: false)
    drawCellContent(cell, at: address, in: rect, overflowPass: true)
    if showGridlines || !cell.raw.isEmpty || paintFormat?.fillColor != nil {
      gridLine.setStroke()
      NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5)).stroke()
    }
  }

  static func contentSize(
    for sheet: Sheet,
    range: (minRow: Int, maxRow: Int, minCol: Int, maxCol: Int),
    hiddenRows: Set<Int> = []
  ) -> NSSize {
    var width = headerWidth
    for col in range.minCol...range.maxCol {
      width += sheet.columnWidth(for: col, default: Workbook.defaultColumnWidth)
    }
    let engine = FormulaEngine()
    engine.rebuild(sheet: sheet)
    let wrappedHeights = CellTextLayout.wrappedRowHeights(
      sheet: sheet,
      defaultRowHeight: Workbook.defaultRowHeight,
      defaultColumnWidth: Workbook.defaultColumnWidth,
      zoom: 1,
      columnWidth: { sheet.columnWidth(for: $0, default: Workbook.defaultColumnWidth) },
      displayText: { address in
        engine.displayString(at: address, sheet: sheet, format: sheet.cell(at: address).format)
      }
    )
    var height = headerHeight
    for row in range.minRow...range.maxRow {
      if hiddenRows.contains(row) { continue }
      height += CellTextLayout.displayRowHeight(
        row: row,
        sheet: sheet,
        defaultRowHeight: Workbook.defaultRowHeight,
        wrapped: wrappedHeights
      )
    }
    return NSSize(
      width: max(width, Self.headerWidth + Workbook.defaultColumnWidth),
      height: max(height, Self.headerHeight + Workbook.defaultRowHeight)
    )
  }
}

/// Full paper page with the grid drawn according to scale and alignment options.
final class SpreadsheetPrintPaginatedView: NSView {
  private let gridView: SpreadsheetPrintNSView
  private let options: SpreadsheetPrintOptions
  private let sheetName: String
  private let pageIndex: Int
  private let pageCount: Int
  private let fitScale: CGFloat
  private let pageOffset: NSPoint

  override var isFlipped: Bool { true }

  init(
    gridView: SpreadsheetPrintNSView,
    options: SpreadsheetPrintOptions,
    sheetName: String,
    pageIndex: Int = 1,
    pageCount: Int = 1
  ) {
    self.gridView = gridView
    self.options = options
    self.sheetName = sheetName
    self.pageIndex = max(1, pageIndex)
    self.pageCount = max(1, pageCount)
    let naturalSize = gridView.bounds.size
    self.fitScale = options.fitScale(forContent: naturalSize)
    self.pageOffset = Self.pageContentOffset(
      pageIndex: self.pageIndex,
      options: options,
      contentSize: naturalSize,
      scale: self.fitScale
    )

    super.init(frame: NSRect(origin: .zero, size: options.pageSize))
    gridView.frame = NSRect(origin: .zero, size: naturalSize)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  override var isOpaque: Bool { true }

  override func knowsPageRange(_ range: NSRangePointer) -> Bool {
    range.pointee = NSRange(location: 1, length: pageCount)
    return true
  }

  override func rectForPage(_ page: Int) -> NSRect {
    bounds
  }

  private var activePageIndex: Int {
    if let current = NSPrintOperation.current?.currentPage, current >= 1 {
      return min(current, pageCount)
    }
    return pageIndex
  }

  /// Content scroll offset (in unscaled points) for a 1-based page index.
  static func pageContentOffset(
    pageIndex: Int,
    options: SpreadsheetPrintOptions,
    contentSize: NSSize,
    scale: CGFloat
  ) -> NSPoint {
    let margin = options.margins.inset
    let printableWidth = max(1, options.pageSize.width - margin * 2)
    let printableHeight = max(1, options.pageSize.height - margin * 2)
    let scaledWidth = contentSize.width * scale
    let scaledHeight = contentSize.height * scale
    let pagesAcross = max(1, Int(ceil(scaledWidth / printableWidth)))
    let pagesDown = max(1, Int(ceil(scaledHeight / printableHeight)))
    let index = max(0, pageIndex - 1)

    let col: Int
    let row: Int
    switch options.pageOrder {
    case .overThenDown:
      col = index % pagesAcross
      row = index / pagesAcross
    case .downThenOver:
      row = index % pagesDown
      col = index / pagesDown
    }

    return NSPoint(
      x: CGFloat(col) * printableWidth / max(scale, 0.0001),
      y: CGFloat(row) * printableHeight / max(scale, 0.0001)
    )
  }

  override func draw(_ dirtyRect: NSRect) {
    NSColor.white.setFill()
    bounds.fill()

    let naturalSize = gridView.bounds.size
    guard naturalSize.width > 1, naturalSize.height > 1 else { return }
    guard let context = NSGraphicsContext.current?.cgContext else { return }

    let currentPage = activePageIndex
    let offset = Self.pageContentOffset(
      pageIndex: currentPage,
      options: options,
      contentSize: naturalSize,
      scale: fitScale
    )

    let margin = options.margins.inset
    let printable = NSRect(
      x: margin,
      y: margin,
      width: max(0, bounds.width - margin * 2),
      height: max(0, bounds.height - margin * 2)
    )

    // Align within the first page's printable area; later pages are scrolled via offset.
    let baseOrigin = options.contentOrigin(contentSize: naturalSize, scale: fitScale)
    let drawOrigin =
      currentPage == 1
      ? baseOrigin
      : NSPoint(x: margin, y: margin)

    context.saveGState()
    NSBezierPath(rect: printable).addClip()
    context.translateBy(x: drawOrigin.x, y: drawOrigin.y)
    context.scaleBy(x: fitScale, y: fitScale)
    context.translateBy(x: -offset.x, y: -offset.y)
    gridView.draw(NSRect(origin: .zero, size: naturalSize))
    context.restoreGState()

    drawHeadersAndFooters(forPage: currentPage)
  }

  private func drawHeadersAndFooters(forPage currentPage: Int) {
    guard options.headersFooters.hasAny else { return }
    let lines = options.headerFooterLines(
      sheetName: sheetName,
      pageIndex: currentPage,
      pageCount: pageCount
    )
    let attrs: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 9),
      .foregroundColor: NSColor(calibratedWhite: 0.35, alpha: 1),
    ]
    let margin = options.margins.inset
    if !lines.header.isEmpty {
      let rect = NSRect(
        x: margin, y: max(8, margin - 18), width: bounds.width - margin * 2, height: 14)
      (lines.header as NSString).draw(in: rect, withAttributes: attrs)
    }
    if !lines.footer.isEmpty {
      let paragraph = NSMutableParagraphStyle()
      paragraph.alignment = .right
      var footerAttrs = attrs
      footerAttrs[.paragraphStyle] = paragraph
      let rect = NSRect(
        x: margin,
        y: bounds.height - max(22, margin - 4),
        width: bounds.width - margin * 2,
        height: 14
      )
      (lines.footer as NSString).draw(in: rect, withAttributes: footerAttrs)
    }
  }
}

/// Stacks one or more sheet regions for workbook printing.
final class SpreadsheetPrintStackNSView: NSView {
  private let sectionViews: [SpreadsheetPrintNSView]
  private let sectionTitles: [String?]

  override var isFlipped: Bool { true }

  init(pages: [SpreadsheetPrintPage], showGridlines: Bool, workbook: Workbook? = nil) {
    var views: [SpreadsheetPrintNSView] = []
    var titles: [String?] = []
    var y: CGFloat = 0
    var maxWidth: CGFloat = 0
    let titleGap: CGFloat = 28

    for page in pages {
      if let title = page.title {
        y += titleGap
      }
      let view = SpreadsheetPrintNSView(
        sheet: page.sheet,
        range: page.range,
        showGridlines: showGridlines,
        workbook: workbook,
        hiddenRows: page.hiddenRows
      )
      views.append(view)
      titles.append(page.title)
      maxWidth = max(maxWidth, view.bounds.width)
      y += view.bounds.height + 32
    }

    self.sectionViews = views
    self.sectionTitles = titles
    super.init(frame: NSRect(x: 0, y: 0, width: maxWidth, height: max(y, 1)))

    y = 0
    for (index, view) in views.enumerated() {
      if sectionTitles[index] != nil {
        y += titleGap
      }
      view.frame.origin = NSPoint(x: 0, y: y)
      addSubview(view)
      y += view.bounds.height + 32
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  override var isOpaque: Bool { true }

  override func draw(_ dirtyRect: NSRect) {
    NSColor.white.setFill()
    dirtyRect.fill()

    for (index, title) in sectionTitles.enumerated() {
      guard let title else { continue }
      let view = sectionViews[index]
      let titleRect = NSRect(x: 0, y: view.frame.minY - 22, width: bounds.width, height: 18)
      guard dirtyRect.intersects(titleRect) else { continue }
      let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
        .foregroundColor: NSColor(calibratedWhite: 0.25, alpha: 1),
      ]
      (title as NSString).draw(in: titleRect, withAttributes: attrs)
    }
  }
}

enum SpreadsheetPrintController {
  private final class SetupWindowController: NSObject, NSWindowDelegate {
    var window: NSWindow?

    func close() {
      window?.close()
      window = nil
    }
  }

  private static var setupController = SetupWindowController()

  @MainActor
  static func presentPrintSetup(from viewModel: SpreadsheetViewModel, in window: NSWindow?) {
    viewModel.commitEditIfNeeded()
    let documentTitle =
      window?.title
      .replacingOccurrences(of: " — Edited", with: "")
      .replacingOccurrences(of: ".csv", with: "")
      ?? "Untitled"
    let options = SpreadsheetPrintOptions.default(for: viewModel, documentTitle: documentTitle)
    let rootView = SpreadsheetPrintSetupView(
      viewModel: viewModel,
      options: options,
      onCancel: {
        setupController.close()
      },
      onPrint: { finalOptions in
        setupController.close()
        runSystemPrint(options: finalOptions, viewModel: viewModel, in: window)
      }
    )

    let hosting = NSHostingController(rootView: rootView)
    let setupWindow = NSWindow(contentViewController: hosting)
    setupWindow.title = "Print"
    setupWindow.styleMask = [.titled, .closable]
    setupWindow.setContentSize(NSSize(width: 980, height: 660))
    setupWindow.minSize = NSSize(width: 820, height: 520)
    setupWindow.center()
    setupController.window = setupWindow
    setupWindow.delegate = setupController

    if let parent = window ?? NSApp.keyWindow ?? NSApp.mainWindow {
      parent.beginSheet(setupWindow) { _ in
        setupController.close()
      }
    } else {
      setupWindow.makeKeyAndOrderFront(nil)
    }
  }

  @MainActor
  static func printActiveSheet(from viewModel: SpreadsheetViewModel, in window: NSWindow?) {
    presentPrintSetup(from: viewModel, in: window)
  }

  @MainActor
  private static func runSystemPrint(
    options: SpreadsheetPrintOptions,
    viewModel: SpreadsheetViewModel,
    in window: NSWindow?
  ) {
    viewModel.commitEditIfNeeded()
    let pages = options.pages(for: viewModel)
    guard !pages.isEmpty else {
      let alert = NSAlert()
      alert.messageText = "Nothing to Print"
      alert.informativeText = "There is no content in the selected print range."
      alert.alertStyle = .informational
      alert.addButton(withTitle: "OK")
      alert.runModal()
      return
    }

    let printInfo = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
    options.apply(to: printInfo)

    let pageCount = max(
      1,
      SpreadsheetPrintSnapshotRenderer.estimatedPageCount(
        for: SpreadsheetPrintPreviewContent(
          contentRevision: viewModel.contentRevision,
          options: options,
          pages: pages,
          workbook: viewModel.workbook
        )
      ))

    let paginatedView: NSView
    if pages.count == 1, pages[0].title == nil {
      let page = pages[0]
      let gridView = SpreadsheetPrintNSView(
        sheet: page.sheet,
        range: page.range,
        showGridlines: options.showGridlines,
        workbook: viewModel.workbook,
        hiddenRows: page.hiddenRows
      )
      paginatedView = SpreadsheetPrintPaginatedView(
        gridView: gridView,
        options: options,
        sheetName: page.sheet.name,
        pageIndex: 1,
        pageCount: pageCount
      )
    } else {
      paginatedView = SpreadsheetPrintStackNSView(
        pages: pages,
        showGridlines: options.showGridlines,
        workbook: viewModel.workbook
      )
    }

    paginatedView.frame = paginatedView.bounds
    paginatedView.layoutSubtreeIfNeeded()
    paginatedView.setNeedsDisplay(paginatedView.bounds)

    let printWindow = NSWindow(
      contentRect: paginatedView.bounds,
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    printWindow.isReleasedWhenClosed = false
    printWindow.alphaValue = 0
    printWindow.setFrameOrigin(
      NSPoint(x: -paginatedView.bounds.width - 200, y: -paginatedView.bounds.height - 200))
    printWindow.contentView = paginatedView
    printWindow.orderBack(nil)

    defer {
      printWindow.orderOut(nil)
      printWindow.close()
    }

    let operation = NSPrintOperation(view: paginatedView, printInfo: printInfo)
    operation.showsPrintPanel = true
    operation.showsProgressPanel = true
    operation.jobTitle = jobTitle(for: options, viewModel: viewModel)
    operation.canSpawnSeparateThread = false

    let parentWindow = window ?? NSApp.keyWindow ?? NSApp.mainWindow
    if let parentWindow {
      parentWindow.makeKeyAndOrderFront(nil)
      operation.runModal(for: parentWindow, delegate: nil, didRun: nil, contextInfo: nil)
    } else {
      _ = operation.run()
    }
  }

  private static func jobTitle(
    for options: SpreadsheetPrintOptions, viewModel: SpreadsheetViewModel
  ) -> String {
    switch options.scope {
    case .workbook:
      return viewModel.workbook.activeSheet.name + " and more"
    default:
      return viewModel.activeSheet.name
    }
  }
}
