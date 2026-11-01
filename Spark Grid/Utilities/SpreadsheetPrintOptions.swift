import AppKit
import Foundation
import SparkGridCore

enum SpreadsheetPrintScope: String, CaseIterable, Identifiable {
  case selectedCells = "Selected cells"
  case populatedCells = "Current sheet"
  case wholeSheet = "Whole sheet"
  case workbook = "Workbook"

  var id: String { rawValue }
}

enum SpreadsheetPrintMarginPreset: String, CaseIterable, Identifiable {
  case normal = "Normal"
  case narrow = "Narrow"
  case wide = "Wide"

  var id: String { rawValue }

  var inset: CGFloat {
    switch self {
    case .normal: 36
    case .narrow: 18
    case .wide: 72
    }
  }
}

enum SpreadsheetPrintPaper: String, CaseIterable, Identifiable {
  case letter = "Letter (8.5\" × 11\")"
  case a4 = "A4"

  var id: String { rawValue }

  var size: NSSize {
    switch self {
    case .letter: NSSize(width: 612, height: 792)
    case .a4: NSSize(width: 595, height: 842)
    }
  }
}

enum SpreadsheetPrintScale: String, CaseIterable, Identifiable {
  case fitToWidth = "Fit to width"
  case fitToPage = "Fit to page"
  case normal = "Normal (100%)"

  var id: String { rawValue }
}

enum SpreadsheetPrintPageOrder: String, CaseIterable, Identifiable {
  case overThenDown = "Over, then down"
  case downThenOver = "Down, then over"

  var id: String { rawValue }
}

enum SpreadsheetPrintHorizontalAlign: String, CaseIterable, Identifiable {
  case left = "Left"
  case center = "Center"
  case right = "Right"

  var id: String { rawValue }
}

enum SpreadsheetPrintVerticalAlign: String, CaseIterable, Identifiable {
  case top = "Top"
  case middle = "Middle"
  case bottom = "Bottom"

  var id: String { rawValue }
}

struct SpreadsheetPrintHeadersFooters: Equatable {
  var pageNumbers = false
  var workbookTitle = false
  var sheetName = false
  var currentDate = false
  var currentTime = false

  var hasAny: Bool {
    pageNumbers || workbookTitle || sheetName || currentDate || currentTime
  }
}

struct SpreadsheetPrintPage: Equatable {
  let sheet: Sheet
  let range: CellRange
  var title: String?
  /// Filter-hidden rows to collapse when printing (matches on-screen view).
  var hiddenRows: Set<Int> = []
}

struct SpreadsheetPrintOptions: Equatable {
  var scope: SpreadsheetPrintScope
  var paper: SpreadsheetPrintPaper
  var isLandscape: Bool
  var scale: SpreadsheetPrintScale
  var margins: SpreadsheetPrintMarginPreset
  var showGridlines: Bool
  var pageOrder: SpreadsheetPrintPageOrder
  var horizontalAlign: SpreadsheetPrintHorizontalAlign
  var verticalAlign: SpreadsheetPrintVerticalAlign
  var headersFooters: SpreadsheetPrintHeadersFooters
  var repeatFrozenRows: Bool
  var repeatFrozenColumns: Bool

  /// Document title used for headers/footers (file name without extension when available).
  var documentTitle: String = "Untitled"

  static func `default`(for viewModel: SpreadsheetViewModel, documentTitle: String = "Untitled")
    -> SpreadsheetPrintOptions
  {
    SpreadsheetPrintOptions(
      scope: .populatedCells,
      paper: .letter,
      isLandscape: false,
      scale: .fitToWidth,
      margins: .normal,
      showGridlines: true,
      pageOrder: .overThenDown,
      horizontalAlign: .left,
      verticalAlign: .top,
      headersFooters: SpreadsheetPrintHeadersFooters(),
      repeatFrozenRows: viewModel.activeSheet.frozenRows > 0,
      repeatFrozenColumns: viewModel.activeSheet.frozenColumns > 0,
      documentTitle: documentTitle
    )
  }

  func pages(for viewModel: SpreadsheetViewModel) -> [SpreadsheetPrintPage] {
    let activeHidden = viewModel.hiddenRowsForPrint()
    switch scope {
    case .selectedCells:
      return [
        SpreadsheetPrintPage(
          sheet: viewModel.activeSheet,
          range: viewModel.selectionRange,
          hiddenRows: activeHidden
        )
      ]
    case .populatedCells:
      let sheet = viewModel.activeSheet
      let range = sheet.populatedBounds ?? sheet.populatedRangeFromOrigin
      return [SpreadsheetPrintPage(sheet: sheet, range: range, hiddenRows: activeHidden)]
    case .wholeSheet:
      let sheet = viewModel.activeSheet
      return [
        SpreadsheetPrintPage(sheet: sheet, range: sheet.wholeSheetRange(), hiddenRows: activeHidden)
      ]
    case .workbook:
      return viewModel.workbook.sheets.compactMap { sheet in
        guard let bounds = sheet.populatedBounds else { return nil }
        let hidden = sheet.id == viewModel.activeSheet.id ? activeHidden : []
        return SpreadsheetPrintPage(
          sheet: sheet, range: bounds, title: sheet.name, hiddenRows: hidden)
      }
    }
  }

  func canUseScope(_ scope: SpreadsheetPrintScope, viewModel: SpreadsheetViewModel) -> Bool {
    switch scope {
    case .selectedCells, .populatedCells, .wholeSheet:
      return true
    case .workbook:
      return viewModel.workbook.sheets.contains { $0.populatedBounds != nil }
    }
  }

  var pageSize: NSSize {
    let size = paper.size
    return isLandscape ? NSSize(width: size.height, height: size.width) : size
  }

  func fitScale(forContent contentSize: NSSize) -> CGFloat {
    let inset = margins.inset
    let printableWidth = max(1, pageSize.width - inset * 2)
    let printableHeight = max(1, pageSize.height - inset * 2)
    switch scale {
    case .normal:
      return 1.0
    case .fitToWidth:
      return min(1.0, printableWidth / max(contentSize.width, 1))
    case .fitToPage:
      return min(
        1.0,
        printableWidth / max(contentSize.width, 1),
        printableHeight / max(contentSize.height, 1)
      )
    }
  }

  func contentOrigin(contentSize: NSSize, scale: CGFloat) -> NSPoint {
    let inset = margins.inset
    let printableWidth = pageSize.width - inset * 2
    let printableHeight = pageSize.height - inset * 2
    let scaledWidth = contentSize.width * scale
    let scaledHeight = contentSize.height * scale

    let x: CGFloat
    switch horizontalAlign {
    case .left: x = inset
    case .center: x = inset + max(0, (printableWidth - scaledWidth) / 2)
    case .right: x = inset + max(0, printableWidth - scaledWidth)
    }

    let y: CGFloat
    switch verticalAlign {
    case .top: y = inset
    case .middle: y = inset + max(0, (printableHeight - scaledHeight) / 2)
    case .bottom: y = inset + max(0, printableHeight - scaledHeight)
    }

    return NSPoint(x: x, y: y)
  }

  func headerFooterLines(sheetName: String, pageIndex: Int, pageCount: Int) -> (
    header: String, footer: String
  ) {
    var left: [String] = []
    var right: [String] = []

    if headersFooters.workbookTitle { left.append(documentTitle) }
    if headersFooters.sheetName { left.append(sheetName) }

    let formatter = DateFormatter()
    if headersFooters.currentDate {
      formatter.dateStyle = .medium
      formatter.timeStyle = .none
      right.append(formatter.string(from: Date()))
    }
    if headersFooters.currentTime {
      formatter.dateStyle = .none
      formatter.timeStyle = .short
      right.append(formatter.string(from: Date()))
    }
    if headersFooters.pageNumbers {
      right.append("Page \(pageIndex) of \(pageCount)")
    }

    let header = left.joined(separator: "  ·  ")
    let footer = right.joined(separator: "  ·  ")
    return (header, footer)
  }

  func apply(to printInfo: NSPrintInfo) {
    let size = pageSize
    printInfo.paperSize = size
    printInfo.orientation = isLandscape ? .landscape : .portrait
    // Margins are drawn by SpreadsheetPrintPaginatedView.
    printInfo.topMargin = 0
    printInfo.bottomMargin = 0
    printInfo.leftMargin = 0
    printInfo.rightMargin = 0
    printInfo.horizontalPagination = .automatic
    printInfo.verticalPagination = .automatic
    printInfo.isHorizontallyCentered = false
    printInfo.isVerticallyCentered = false
  }
}
