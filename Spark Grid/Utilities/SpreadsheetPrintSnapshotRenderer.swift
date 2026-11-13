import AppKit
import Foundation
import SparkGridCore

enum SpreadsheetPrintRenderStyle {
  case print
  case preview
}

struct SpreadsheetPrintPreviewContent: Equatable {
  let contentRevision: Int
  let options: SpreadsheetPrintOptions
  let pages: [SpreadsheetPrintPage]
  var workbook: Workbook = .empty

  var paperSize: NSSize { options.pageSize }

  var renderToken: String {
    guard let page = pages.first else { return "empty-\(contentRevision)" }
    let range = page.range.normalized
    let sections = pages.map { "\($0.sheet.id)" }.joined(separator: ",")
    let hf = options.headersFooters
    return [
      String(contentRevision),
      options.scope.rawValue,
      options.showGridlines ? "1" : "0",
      options.showHeadings ? "1" : "0",
      options.paper.rawValue,
      options.isLandscape ? "L" : "P",
      options.scale.rawValue,
      options.margins.rawValue,
      options.pageOrder.rawValue,
      options.horizontalAlign.rawValue,
      options.verticalAlign.rawValue,
      hf.pageNumbers ? "1" : "0",
      hf.workbookTitle ? "1" : "0",
      hf.sheetName ? "1" : "0",
      hf.currentDate ? "1" : "0",
      hf.currentTime ? "1" : "0",
      options.repeatFrozenRows ? "1" : "0",
      options.repeatFrozenColumns ? "1" : "0",
      "\(range.minRow)-\(range.maxRow)-\(range.minCol)-\(range.maxCol)",
      String(page.sheet.cells.count),
      sections,
      String(page.hiddenRows.count),
      page.sheet.fileExtras.rowBreaks.sorted().map(String.init).joined(separator: ","),
      page.sheet.fileExtras.columnBreaks.sorted().map(String.init).joined(separator: ","),
      "\(page.sheet.frozenRows)x\(page.sheet.frozenColumns)",
    ].joined(separator: "|")
  }
}

enum SpreadsheetPrintSnapshotRenderer {
  /// The last laid-out preview. Building it computes every row's height and the formulas, and
  /// the preview asks for the page count on every redraw.
  private static var cached: (token: String, view: SpreadsheetPrintBookView)?

  private static func bookView(for content: SpreadsheetPrintPreviewContent)
    -> SpreadsheetPrintBookView?
  {
    guard !content.pages.isEmpty else { return nil }
    let token = content.renderToken
    if let cached, cached.token == token { return cached.view }
    let view = SpreadsheetPrintBookView(
      pages: content.pages, options: content.options, workbook: content.workbook)
    cached = (token, view)
    return view
  }

  static func renderPageImage(
    content: SpreadsheetPrintPreviewContent,
    pageIndex: Int
  ) -> NSImage? {
    guard let view = bookView(for: content) else { return nil }
    view.pageIndex = min(max(1, pageIndex), view.pageCount)
    return snapshot(of: view)
  }

  static func renderPageImage(content: SpreadsheetPrintPreviewContent) -> NSImage? {
    renderPageImage(content: content, pageIndex: 1)
  }

  static func estimatedPageCount(for content: SpreadsheetPrintPreviewContent) -> Int {
    bookView(for: content)?.pageCount ?? 0
  }

  /// Draws now, at twice the paper size. A lazily drawn image would draw whatever page the
  /// shared view shows when the image is next displayed.
  private static func snapshot(of view: NSView) -> NSImage? {
    let bounds = view.bounds
    guard bounds.width > 1, bounds.height > 1,
      let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * 2),
        pixelsHigh: Int(bounds.height * 2),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
      let context = NSGraphicsContext(bitmapImageRep: rep)
    else { return nil }
    rep.size = bounds.size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let cg = context.cgContext
    cg.scaleBy(x: 2, y: 2)
    // The page views are flipped; the bitmap is not.
    cg.translateBy(x: 0, y: bounds.height)
    cg.scaleBy(x: 1, y: -1)
    let flipped = NSGraphicsContext(cgContext: cg, flipped: true)
    NSGraphicsContext.current = flipped
    view.draw(bounds)
    NSGraphicsContext.restoreGraphicsState()
    let image = NSImage(size: bounds.size)
    image.addRepresentation(rep)
    return image
  }
}
