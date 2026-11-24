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

  static func bookView(for content: SpreadsheetPrintPreviewContent)
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

  static func estimatedPageCount(for content: SpreadsheetPrintPreviewContent) -> Int {
    bookView(for: content)?.pageCount ?? 0
  }
}
