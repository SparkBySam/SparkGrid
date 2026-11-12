import AppKit
import SparkGridCore
import SwiftUI
import UniformTypeIdentifiers

/// Renders one sheet region for print preview and printing.
final class SpreadsheetPrintNSView: NSView {
  let sheet: Sheet
  private let formulaEngine: FormulaEngine
  private let showGridlines: Bool
  let normalized: (minRow: Int, maxRow: Int, minCol: Int, maxCol: Int)
  let maxRow: Int
  /// Positions and sizes in the view, one per printed column or row. Hidden ones are zero wide.
  let columnXs: [CGFloat]
  let columnWidths: [CGFloat]
  let rowYs: [CGFloat]
  let rowHeights: [CGFloat]

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
    let hiddenColumns = sheet.fileExtras.hiddenColumns
    for col in normalized.minCol...normalized.maxCol {
      let width =
        hiddenColumns.contains(col)
        ? 0 : sheet.columnWidth(for: col, default: Workbook.defaultColumnWidth)
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

  /// The part being drawn. Page strips draw one part each; anything outside it is left out so a
  /// PDF holds each cell's text once.
  private var drawRect = NSRect.infinite

  override func draw(_ dirtyRect: NSRect) {
    drawRect = dirtyRect
    defer { drawRect = .infinite }
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
    drawSheetCells(overflowPass: false, in: dirtyRect)
    drawSheetCells(overflowPass: true, in: dirtyRect)

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
      guard columnWidths[colIndex] > 0 else { continue }
      let header = NSRect(
        x: columnXs[colIndex],
        y: 0,
        width: columnWidths[colIndex],
        height: Self.headerHeight
      )
      guard header.intersects(dirtyRect) else { continue }
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
      guard header.intersects(dirtyRect) else { continue }
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

  private func drawSheetCells(overflowPass: Bool, in dirtyRect: NSRect) {
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
      guard columnWidths[colIndex] > 0 else { continue }
      let rect = NSRect(
        x: columnXs[colIndex],
        y: rowYs[rowIndex],
        width: columnWidths[colIndex],
        height: rowHeights[rowIndex]
      )
      // Overflowing text can reach other columns, so only rows are culled on that pass.
      if overflowPass {
        guard rect.maxY > dirtyRect.minY, rect.minY < dirtyRect.maxY else { continue }
      } else if !rect.intersects(dirtyRect) {
        continue
      }
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

    if cell.hasContent, format.overflowsUnclipped == overflowPass {
      let text = formulaEngine.displayString(at: address, sheet: sheet, format: cell.format)
      let textRect = rect.insetBy(dx: 4, dy: 2)
      if textRect.width > 1, textRect.height > 1, !text.isEmpty {
        let clip =
          overflowPass
          ? overflowClipRect(
            for: address, text: text, format: format, textRect: textRect, cellRect: rect) : rect
        guard clip.intersects(drawRect) else { return }
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
    if showGridlines || cell.hasContent || paintFormat?.fillColor != nil {
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

/// Full paper pages of one grid region, split on row and column edges by `SpreadsheetPrintLayout`.
final class SpreadsheetPrintPaginatedView: NSView {
  private let gridView: SpreadsheetPrintNSView
  private let options: SpreadsheetPrintOptions
  private let sheetName: String
  /// The page drawn outside a print operation, for the preview.
  var pageIndex: Int
  let layout: SpreadsheetPrintLayout

  var pageCount: Int { max(1, layout.pages.count) }

  override var isFlipped: Bool { true }

  init(
    gridView: SpreadsheetPrintNSView,
    options: SpreadsheetPrintOptions,
    sheetName: String,
    pageIndex: Int = 1
  ) {
    self.gridView = gridView
    self.options = options
    self.sheetName = sheetName
    self.layout = SpreadsheetPrintLayout(
      gridView: gridView, sheet: gridView.sheet, options: options)
    self.pageIndex = max(1, pageIndex)
    super.init(frame: NSRect(origin: .zero, size: options.pageSize))
    gridView.frame = NSRect(origin: .zero, size: gridView.bounds.size)
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

  /// Set by `SpreadsheetPrintBookView`, which knows the page across every sheet printed.
  private var activePageIndex: Int { min(max(1, pageIndex), pageCount) }

  override func draw(_ dirtyRect: NSRect) {
    NSColor.white.setFill()
    bounds.fill()

    guard gridView.bounds.width > 1, gridView.bounds.height > 1,
      let context = NSGraphicsContext.current?.cgContext
    else { return }
    let currentPage = activePageIndex
    if layout.pages.indices.contains(currentPage - 1) {
      SpreadsheetPrintLayout.draw(
        page: layout.pages[currentPage - 1], of: gridView, scale: layout.scale, options: options,
        in: context)
    }
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

/// Every printed region's pages in one run: one sheet, or each sheet in turn when printing the
/// workbook. Print, preview and PDF export all page through this.
final class SpreadsheetPrintBookView: NSView {
  let sections: [SpreadsheetPrintPaginatedView]
  /// The page drawn outside a print operation, counted across all sections.
  var pageIndex = 1

  var pageCount: Int { max(1, sections.reduce(0) { $0 + $1.pageCount }) }

  override var isFlipped: Bool { true }
  override var isOpaque: Bool { true }

  init(pages: [SpreadsheetPrintPage], options: SpreadsheetPrintOptions, workbook: Workbook) {
    sections = pages.map { page in
      let grid = SpreadsheetPrintNSView(
        sheet: page.sheet,
        range: page.range,
        showGridlines: options.showGridlines,
        workbook: workbook,
        hiddenRows: page.hiddenRows
      )
      return SpreadsheetPrintPaginatedView(
        gridView: grid, options: options, sheetName: page.sheet.name)
    }
    super.init(frame: NSRect(origin: .zero, size: options.pageSize))
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  override func knowsPageRange(_ range: NSRangePointer) -> Bool {
    range.pointee = NSRange(location: 1, length: pageCount)
    return true
  }

  override func rectForPage(_ page: Int) -> NSRect { bounds }

  /// The section and its own page number for a page counted across the book.
  func locate(_ page: Int) -> (SpreadsheetPrintPaginatedView, Int)? {
    var remaining = page
    for section in sections {
      if remaining <= section.pageCount { return (section, remaining) }
      remaining -= section.pageCount
    }
    return nil
  }

  override func draw(_ dirtyRect: NSRect) {
    let current = NSPrintOperation.current?.currentPage ?? pageIndex
    guard let (section, index) = locate(min(max(1, current), pageCount)) else {
      NSColor.white.setFill()
      bounds.fill()
      return
    }
    section.pageIndex = index
    section.draw(bounds)
  }
}

enum SpreadsheetPrintController {
  private final class SetupWindowController: NSObject, NSWindowDelegate {
    var window: NSWindow?

    /// Ends the sheet on its document window, so a save panel or print panel can take its place.
    func close() {
      // Cleared first: ending the sheet calls back into close().
      guard let window else { return }
      self.window = nil
      window.sheetParent?.endSheet(window)
      window.close()
    }
  }

  private static var setupController = SetupWindowController()

  @MainActor
  static func presentPrintSetup(
    from viewModel: SpreadsheetViewModel, in window: NSWindow?, exportsPDF: Bool = false
  ) {
    viewModel.commitEditIfNeeded()
    // Found now: once this window is up it is the key window, and after it closes there may be none.
    let window = window ?? NSApp.keyWindow ?? NSApp.mainWindow
    let documentTitle =
      window.map {
        ($0.title.replacingOccurrences(of: " — Edited", with: "") as NSString)
          .deletingPathExtension
      } ?? "Untitled"
    let options = SpreadsheetPrintOptions.default(for: viewModel, documentTitle: documentTitle)
    let rootView = SpreadsheetPrintSetupView(
      viewModel: viewModel,
      options: options,
      exportsPDF: exportsPDF,
      onCancel: {
        setupController.close()
      },
      onPrint: { finalOptions in
        setupController.close()
        runSystemPrint(options: finalOptions, viewModel: viewModel, in: window)
      },
      onSavePDF: { finalOptions in
        setupController.close()
        savePDF(options: finalOptions, viewModel: viewModel, in: window)
      }
    )

    let hosting = NSHostingController(rootView: rootView)
    let setupWindow = NSWindow(contentViewController: hosting)
    setupWindow.title = exportsPDF ? "Export as PDF" : "Print"
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

    let paginatedView = SpreadsheetPrintBookView(
      pages: pages, options: options, workbook: viewModel.workbook)
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

  /// Asks where to save, then writes every page of the chosen range as a PDF.
  @MainActor
  private static func savePDF(
    options: SpreadsheetPrintOptions, viewModel: SpreadsheetViewModel, in window: NSWindow?
  ) {
    viewModel.commitEditIfNeeded()
    let pages = options.pages(for: viewModel)
    let panel = NSSavePanel()
    panel.title = "Export as PDF"
    panel.allowedContentTypes = [.pdf]
    panel.canCreateDirectories = true
    panel.nameFieldStringValue = options.documentTitle + ".pdf"
    let write = { (url: URL) in
      do {
        let result = try SpreadsheetPDFExporter.pdfData(
          pages: pages, options: options, workbook: viewModel.workbook)
        try result.data.write(to: url, options: .atomic)
      } catch {
        let alert = NSAlert()
        alert.messageText = "Can’t Export PDF"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
      }
    }
    if let parent = window ?? NSApp.keyWindow ?? NSApp.mainWindow {
      panel.beginSheetModal(for: parent) { response in
        guard response == .OK, let url = panel.url else { return }
        write(url)
      }
    } else if panel.runModal() == .OK, let url = panel.url {
      write(url)
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
