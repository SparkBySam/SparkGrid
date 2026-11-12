import AppKit
import SparkGridCore

/// File ▸ Export as PDF. Writes the same pages printing makes, one PDF page each, with text kept
/// as text. Printing every sheet gives each sheet its own pages.
enum SpreadsheetPDFExporter {
  enum ExportError: LocalizedError {
    case nothingToExport
    case cannotCreateFile

    var errorDescription: String? {
      switch self {
      case .nothingToExport: "There is nothing to export in the chosen range."
      case .cannotCreateFile: "The PDF file could not be created."
      }
    }
  }

  /// PDF data for every page. Returns the page count with it.
  static func pdfData(
    pages: [SpreadsheetPrintPage], options: SpreadsheetPrintOptions, workbook: Workbook
  ) throws -> (data: Data, pageCount: Int) {
    guard !pages.isEmpty else { throw ExportError.nothingToExport }
    let book = SpreadsheetPrintBookView(pages: pages, options: options, workbook: workbook)
    let data = NSMutableData()
    var mediaBox = CGRect(origin: .zero, size: options.pageSize)
    guard let consumer = CGDataConsumer(data: data as CFMutableData),
      let pdf = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
    else { throw ExportError.cannotCreateFile }
    var count = 0
    for index in 1...book.pageCount {
      book.pageIndex = index
      pdf.beginPDFPage(nil)
      // PDF pages count up from the bottom; the print views count down from the top.
      pdf.translateBy(x: 0, y: mediaBox.height)
      pdf.scaleBy(x: 1, y: -1)
      NSGraphicsContext.saveGraphicsState()
      NSGraphicsContext.current = NSGraphicsContext(cgContext: pdf, flipped: true)
      book.draw(book.bounds)
      NSGraphicsContext.restoreGraphicsState()
      pdf.endPDFPage()
      count += 1
    }
    pdf.closePDF()
    return (data as Data, count)
  }
}
