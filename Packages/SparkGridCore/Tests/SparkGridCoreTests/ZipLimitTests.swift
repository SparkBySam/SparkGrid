import Foundation
import GridCore
import Model
import XCTest

@testable import FileFormats

/// Spark Grid opens files up to 2 GB unpacked, with no part over 200 MB (Sam, Nov 13 2026).
/// Bytes are counted as they unpack, so a small file that unpacks to far more stops early.
final class ZipLimitTests: XCTestCase {
  private func workbookFile(adding parts: [String: Data] = [:]) throws -> Data {
    var sheet = Sheet(name: "S")
    sheet.setCell(Cell(raw: "x"), at: .origin)
    let plain = try XLSXCodec.exportWorkbook(Workbook(sheets: [sheet]))
    guard !parts.isEmpty else { return plain }
    return try XCTUnwrap(XLSXCodec.replacingZipEntries(plain, entries: parts))
  }

  private let small = ZipPackage.Limits(totalBytes: 1_500_000, partBytes: 1_000_000)

  private func assertTooLarge(_ data: Data, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertThrowsError(try ZipPackage(archiveData: data, limits: small), file: file, line: line) {
      error in
      guard case XLSXCodec.CodecError.tooLarge = error else {
        return XCTFail("\(error)", file: file, line: line)
      }
    }
  }

  func testWithinTheLimitsOpens() throws {
    let data = try workbookFile(adding: ["xl/media/a.bin": Data(repeating: 1, count: 900_000)])
    let package = try ZipPackage(archiveData: data, limits: small)
    XCTAssertEqual(package.data(for: "xl/media/a.bin")?.count, 900_000)
    XCTAssertEqual(try XLSXCodec.importWorkbook(from: data).activeSheet.cell(at: .origin).raw, "x")
  }

  func testOnePartOverTheLimitStops() throws {
    assertTooLarge(try workbookFile(adding: ["xl/media/a.bin": Data(count: 1_000_001)]))
  }

  func testAllPartsTogetherOverTheLimitStops() throws {
    assertTooLarge(
      try workbookFile(adding: [
        "xl/media/a.bin": Data(count: 800_000), "xl/media/b.bin": Data(count: 800_000),
      ]))
  }

  /// A part that packs very small but unpacks large is caught by what unpacks.
  func testSmallFileThatUnpacksLargeStops() throws {
    let data = try workbookFile(adding: ["xl/media/zeros.bin": Data(count: 5_000_000)])
    XCTAssertLessThan(data.count, 500_000, "the zeros should pack small")
    assertTooLarge(data)
  }

  func testTooLargeSaysWhatTheLimitIs() {
    let message = XLSXCodec.CodecError.tooLarge.errorDescription ?? ""
    XCTAssertTrue(message.contains("2 GB"), message)
    XCTAssertTrue(message.contains("200 MB"), message)
  }
}
