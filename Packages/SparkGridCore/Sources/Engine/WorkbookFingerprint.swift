import Calc
import CryptoKit
import FileFormats
import Formula
import Foundation
import Functions
import GridCore
import Model
import NumberFormat

/// Stable dirty-state fingerprint without JSON-encoding every cell (large workbooks
/// can hold hundreds of thousands of cells and spike memory on open).
public enum WorkbookFingerprint {
  public static func data(for workbook: Workbook) -> Data {
    var hasher = SHA256()
    update(hasher: &hasher, workbook: workbook)
    return Data(hasher.finalize())
  }

  private static func update(hasher: inout SHA256, workbook: Workbook) {
    hashInt(hasher: &hasher, value: workbook.activeSheetIndex)
    hashNamedRanges(hasher: &hasher, ranges: workbook.namedRanges)
    for sheet in workbook.sheets {
      hashSheet(hasher: &hasher, sheet: sheet)
    }
  }

  private static func hashSheet(hasher: inout SHA256, sheet: Sheet) {
    hashString(hasher: &hasher, value: sheet.id.uuidString)
    hashString(hasher: &hasher, value: sheet.name)
    hashInt(hasher: &hasher, value: sheet.frozenRows)
    hashInt(hasher: &hasher, value: sheet.frozenColumns)
    hashOptionalInt(hasher: &hasher, value: sheet.gridRowCount)
    hashOptionalInt(hasher: &hasher, value: sheet.gridColumnCount)

    for key in sheet.columnWidths.keys.sorted() {
      hashInt(hasher: &hasher, value: key)
      hashCGFloat(hasher: &hasher, value: sheet.columnWidths[key] ?? 0)
    }
    for key in sheet.rowHeights.keys.sorted() {
      hashInt(hasher: &hasher, value: key)
      hashCGFloat(hasher: &hasher, value: sheet.rowHeights[key] ?? 0)
    }

    for merge in sheet.mergedRanges {
      hashCellAddress(hasher: &hasher, address: merge.start)
      hashCellAddress(hasher: &hasher, address: merge.end)
    }

    hashConditionalFormats(hasher: &hasher, rules: sheet.conditionalFormats)
    hashAutoFilter(hasher: &hasher, filter: sheet.autoFilter)
    hashCharts(hasher: &hasher, charts: sheet.charts)
    hashImages(hasher: &hasher, images: sheet.images)

    for address in sheet.cells.keys.sorted() {
      hashCell(hasher: &hasher, address: address, cell: sheet.cells[address] ?? Cell())
    }
  }

  private static func hashCell(hasher: inout SHA256, address: CellAddress, cell: Cell) {
    hashCellAddress(hasher: &hasher, address: address)
    hashString(hasher: &hasher, value: cell.raw)
    if let format = cell.format {
      hashCellFormat(hasher: &hasher, format: format)
    } else {
      hasher.update(data: Data([0]))
    }
  }

  private static func hashCellFormat(hasher: inout SHA256, format: CellFormat) {
    // Reuse JSON for format blobs — small compared to full-workbook encoding.
    if let encoded = try? JSONEncoder().encode(format) {
      hasher.update(data: encoded)
    }
  }

  private static func hashNamedRanges(hasher: inout SHA256, ranges: [String: NamedRange]) {
    for key in ranges.keys.sorted() {
      hashString(hasher: &hasher, value: key)
      if let encoded = try? JSONEncoder().encode(ranges[key]) {
        hasher.update(data: encoded)
      }
    }
  }

  private static func hashConditionalFormats(hasher: inout SHA256, rules: [ConditionalFormatRule]) {
    for rule in rules {
      if let encoded = try? JSONEncoder().encode(rule) {
        hasher.update(data: encoded)
      }
    }
  }

  private static func hashAutoFilter(hasher: inout SHA256, filter: SheetFilterState?) {
    guard let filter else {
      hasher.update(data: Data([0]))
      return
    }
    hasher.update(data: Data([1]))
    if let encoded = try? JSONEncoder().encode(filter) {
      hasher.update(data: encoded)
    }
  }

  private static func hashCharts(hasher: inout SHA256, charts: [SheetChart]) {
    for chart in charts {
      if let encoded = try? JSONEncoder().encode(chart) {
        hasher.update(data: encoded)
      }
    }
  }

  private static func hashImages(hasher: inout SHA256, images: [SheetImage]) {
    for image in images {
      hashInt(hasher: &hasher, value: image.anchorRow)
      hashInt(hasher: &hasher, value: image.anchorCol)
      hashInt(hasher: &hasher, value: image.widthEMU)
      hashInt(hasher: &hasher, value: image.heightEMU)
      hasher.update(data: image.imageData)
    }
  }

  private static func hashCellAddress(hasher: inout SHA256, address: CellAddress) {
    hashInt(hasher: &hasher, value: address.row)
    hashInt(hasher: &hasher, value: address.col)
  }

  private static func hashString(hasher: inout SHA256, value: String) {
    var length = UInt32(value.utf8.count).littleEndian
    withUnsafeBytes(of: length) { hasher.update(data: Data($0)) }
    hasher.update(data: Data(value.utf8))
  }

  private static func hashInt(hasher: inout SHA256, value: Int) {
    var little = Int64(value).littleEndian
    withUnsafeBytes(of: little) { hasher.update(data: Data($0)) }
  }

  private static func hashOptionalInt(hasher: inout SHA256, value: Int?) {
    guard let value else {
      hasher.update(data: Data([0]))
      return
    }
    hasher.update(data: Data([1]))
    hashInt(hasher: &hasher, value: value)
  }

  private static func hashCGFloat(hasher: inout SHA256, value: CGFloat) {
    var bits = Double(value).bitPattern.littleEndian
    withUnsafeBytes(of: bits) { hasher.update(data: Data($0)) }
  }
}
