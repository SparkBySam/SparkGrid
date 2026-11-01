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
    let hf = options.headersFooters
    return [
      String(contentRevision),
      options.scope.rawValue,
      options.showGridlines ? "1" : "0",
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
      String(page.hiddenRows.count),
    ].joined(separator: "|")
  }
}

enum SpreadsheetPrintSnapshotRenderer {
  @MainActor
  static func renderPageImage(
    content: SpreadsheetPrintPreviewContent,
    pageIndex: Int
  ) -> NSImage? {
    guard let page = content.pages.first else { return nil }

    let options = content.options
    let pageCount = estimatedPageCount(for: content)
    let index = min(max(1, pageIndex), max(1, pageCount))

    // Full range — page offsets depend on true content size (no row cap).
    let gridView = SpreadsheetPrintNSView(
      sheet: page.sheet,
      range: page.range,
      showGridlines: options.showGridlines,
      workbook: content.workbook,
      hiddenRows: page.hiddenRows
    )

    let pageView = SpreadsheetPrintPaginatedView(
      gridView: gridView,
      options: options,
      sheetName: page.sheet.name,
      pageIndex: index,
      pageCount: pageCount
    )

    return snapshot(of: pageView)
  }

  @MainActor
  static func renderPageImage(content: SpreadsheetPrintPreviewContent) -> NSImage? {
    renderPageImage(content: content, pageIndex: 1)
  }

  static func estimatedPageCount(for content: SpreadsheetPrintPreviewContent) -> Int {
    guard let page = content.pages.first else { return 0 }

    let options = content.options
    let margin = options.margins.inset
    let printableHeight = options.pageSize.height - margin * 2
    let printableWidth = options.pageSize.width - margin * 2

    let normalized = page.range.normalized
    let naturalSize = SpreadsheetPrintNSView.contentSize(
      for: page.sheet,
      range: normalized,
      hiddenRows: page.hiddenRows
    )
    let fitScale = options.fitScale(forContent: naturalSize)
    let scaledWidth = naturalSize.width * fitScale
    let scaledHeight = naturalSize.height * fitScale

    let pagesAcross = max(1, Int(ceil(scaledWidth / max(printableWidth, 1))))
    let pagesDown = max(1, Int(ceil(scaledHeight / max(printableHeight, 1))))
    return max(1, pagesAcross * pagesDown)
  }

  @MainActor
  private static func snapshot(of view: NSView) -> NSImage? {
    let bounds = view.bounds
    guard bounds.width > 1, bounds.height > 1 else { return nil }

    let image = NSImage(size: bounds.size, flipped: true) { rect in
      view.draw(rect)
      return true
    }
    return image
  }
}
