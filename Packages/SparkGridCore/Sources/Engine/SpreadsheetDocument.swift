import Calc
import FileFormats
import Formula
import Foundation
import Functions
import GridCore
import Model
import NumberFormat
import UniformTypeIdentifiers

extension UTType {
  /// Excel Open XML workbook (.xlsx).
  public static var spreadsheetML: UTType {
    UTType(importedAs: "org.openxmlformats.spreadsheetml.sheet")
  }

  /// A Numbers document saved as one file.
  public static var numbersDocument: UTType {
    UTType(importedAs: "com.apple.iwork.numbers.sffnumbers")
  }

  /// A Numbers document saved as a package folder, as older Numbers versions save.
  public static var numbersPackage: UTType {
    UTType(importedAs: "com.apple.iwork.numbers.numbers")
  }

  /// An OpenDocument spreadsheet (.ods), as LibreOffice saves it.
  public static var openDocumentSpreadsheet: UTType {
    UTType(importedAs: "org.oasis-open.opendocument.spreadsheet")
  }

  /// The files Spark Grid opens: its own two, Numbers documents and OpenDocument spreadsheets.
  public static var spreadsheetsSparkGridOpens: [UTType] {
    [
      .spreadsheetML, .commaSeparatedText, .numbersDocument, .numbersPackage,
      .openDocumentSpreadsheet,
    ]
  }
}

/// In-memory workbook container for Spark Grid's custom window/store architecture.
///
/// Not a SwiftUI `Document` / `FileDocument`: the app uses `Window` + `SpreadsheetDocumentStore`
/// rather than `DocumentGroup`. FileDocument is deprecated in the macOS 27 SDK in favor of the
/// class-based `Document` protocols, which we do not need until/unless we adopt DocumentGroup.
public struct SpreadsheetDocument {
  public static var readableContentTypes: [UTType] {
    [.spreadsheetML, .commaSeparatedText, .plainText]
  }
  public static var writableContentTypes: [UTType] { [.spreadsheetML, .commaSeparatedText] }

  public var workbook: Workbook

  public init(workbook: Workbook = .empty) {
    self.workbook = workbook
  }

  public static func workbook(from data: Data, sheetName: String, contentType: UTType? = nil) throws
    -> Workbook
  {
    if isXLSX(data: data, contentType: contentType) {
      return try XLSXCodec.importWorkbook(from: data)
    }
    let text = decodeText(from: data)
    var sheet = Sheet(name: sheetName)
    sheet.replaceCells(CSVCodec.importCSV(text))
    return Workbook(sheets: [sheet])
  }

  public static func load(from url: URL) throws -> SpreadsheetDocument {
    let data = try Data(contentsOf: url)
    let name = url.deletingPathExtension().lastPathComponent
    let type = UTType(filenameExtension: url.pathExtension)
    let workbook = try workbook(
      from: data,
      sheetName: name.isEmpty ? "Sheet1" : name,
      contentType: type
    )
    return SpreadsheetDocument(workbook: workbook)
  }

  private static func isXLSX(data: Data, contentType: UTType?) -> Bool {
    if let contentType,
      contentType.conforms(to: .spreadsheetML)
        || contentType.identifier == "org.openxmlformats.spreadsheetml.sheet"
        || contentType.identifier == "com.microsoft.excel.xlsx"
    {
      return true
    }
    // ZIP local file header signature
    return data.starts(with: [0x50, 0x4B, 0x03, 0x04])
      || data.starts(with: [0x50, 0x4B, 0x05, 0x06])
  }

  private static func decodeText(from data: Data) -> String {
    if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
    if let utf16 = String(data: data, encoding: .utf16) { return utf16 }
    if let macRoman = String(data: data, encoding: .macOSRoman) { return macRoman }
    return String(decoding: data, as: UTF8.self)
  }
}

extension String {
  fileprivate var deletingPathExtension: String {
    (self as NSString).deletingPathExtension
  }
}
