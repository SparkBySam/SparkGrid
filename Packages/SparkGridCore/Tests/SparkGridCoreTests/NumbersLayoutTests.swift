import Foundation
import GridCore
import Model
import XCTest

@testable import FileFormats

/// Merged cells, text wrapping and vertical alignment from a Numbers document (Numbers 15.4,
/// checked against its own Excel export). In rows Numbers gave a height, its defaults show:
/// text at the top, wrapped.
final class NumbersLayoutTests: XCTestCase {
  private func fixture(_ name: String) throws -> Workbook {
    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("Fixtures/\(name)")
    return try NumbersImporter.importWorkbook(from: url)
  }

  func testMergedCells() throws {
    let sheet = try fixture("numbers-layout.numbers").sheets[0]
    XCTAssertEqual(Set(sheet.mergedRanges.map(\.a1Label)), ["B2:C2", "B4:C6"])
  }

  func testWrappingAndVerticalAlignment() throws {
    let sheet = try fixture("numbers-layout.numbers").sheets[0]
    func format(_ a1: String) -> CellFormat {
      sheet.cell(at: XLSXCodec.parseCellRange(a1)!.start).format ?? CellFormat()
    }
    // E2 wraps (Numbers' default), E3 has wrapping turned off.
    XCTAssertTrue(format("E2").wrapText)
    XCTAssertFalse(format("E3").wrapText)
    XCTAssertEqual(format("F2").verticalAlign, .top)
    XCTAssertEqual(format("F3").verticalAlign, .middle)
    XCTAssertEqual(format("F4").verticalAlign, .bottom)
    XCTAssertEqual(sheet.rowHeights[1], 60)
  }

  /// A file with formula ranges but no merges: those ranges are not merges.
  func testFormulaRangesAreNotMerges() throws {
    for sheet in try fixture("numbers-references.numbers").sheets {
      XCTAssertTrue(sheet.mergedRanges.isEmpty, sheet.name)
    }
  }

  /// Cells in ordinary rows keep Spark Grid's own defaults.
  func testOrdinaryRowsKeepSparkGridDefaults() throws {
    let sheet = try fixture("numbers-values.numbers").sheets[0]
    for a1 in ["A2", "B2"] {
      let format = sheet.cell(at: XLSXCodec.parseCellRange(a1)!.start).format
      XCTAssertFalse(format?.wrapText ?? false, a1)
      XCTAssertEqual(format?.verticalAlign ?? .bottom, .bottom, a1)
    }
    let format = sheet.cell(at: XLSXCodec.parseCellRange("B2")!.start).format
    XCTAssertFalse(format?.wrapText ?? false)
    XCTAssertEqual(format?.verticalAlign ?? .bottom, .bottom)
  }

  /// Borders: a 6 pt black box around B2:C3 and a 0.75 pt box around D2, as Numbers' own Excel
  /// export shows them. Gridlines are not borders.
  func testBorders() throws {
    let sheet = try fixture("numbers-borders.numbers").sheets[0]
    func borders(_ a1: String) -> CellBorders {
      sheet.cell(at: XLSXCodec.parseCellRange(a1)!.start).format?.borders ?? .none
    }
    let black = CodableColor(red: 0, green: 0, blue: 0, alpha: 1)
    let thick = BorderEdge(style: .thick, color: black)
    let thin = BorderEdge(style: .thin, color: black)
    XCTAssertEqual(borders("B2"), CellBorders(top: thick, left: thick))
    XCTAssertEqual(borders("C2"), CellBorders(top: thick, right: thick))
    XCTAssertEqual(borders("B3"), CellBorders(bottom: thick, left: thick))
    XCTAssertEqual(borders("C3"), CellBorders(bottom: thick, right: thick))
    XCTAssertEqual(borders("D2"), CellBorders(top: thin, bottom: thin, left: thin, right: thin))
    XCTAssertFalse(borders("A1").hasAny)
    XCTAssertFalse(borders("E5").hasAny)
  }

  /// A file with no strokes of its own has no borders.
  func testNoBordersWithoutStrokes() throws {
    let sheet = try fixture("numbers-layout.numbers").sheets[0]
    XCTAssertFalse(sheet.cells.values.contains { $0.format?.borders.hasAny ?? false })
  }
}
