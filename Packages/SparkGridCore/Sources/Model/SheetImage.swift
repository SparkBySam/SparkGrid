import CoreGraphics
import Formula
import Foundation
import GridCore
import NumberFormat

/// Embedded picture anchored on a sheet (Excel drawing / oneCellAnchor).
public nonisolated struct SheetImage: Identifiable, Codable, Equatable, Sendable {
  public var id: UUID
  /// Top-left anchor cell (0-based row/column).
  public var anchorRow: Int
  public var anchorCol: Int
  /// Offset from anchor cell top-left, in EMU (English Metric Units).
  public var rowOffsetEMU: Int
  public var colOffsetEMU: Int
  public var widthEMU: Int
  public var heightEMU: Int
  public var imageData: Data
  /// MIME type for export (`image/png`, `image/jpeg`).
  public var contentType: String

  public init(
    id: UUID = UUID(),
    anchorRow: Int,
    anchorCol: Int,
    rowOffsetEMU: Int = 0,
    colOffsetEMU: Int = 0,
    widthEMU: Int,
    heightEMU: Int,
    imageData: Data,
    contentType: String = "image/png"
  ) {
    self.id = id
    self.anchorRow = anchorRow
    self.anchorCol = anchorCol
    self.rowOffsetEMU = rowOffsetEMU
    self.colOffsetEMU = colOffsetEMU
    self.widthEMU = widthEMU
    self.heightEMU = heightEMU
    self.imageData = imageData
    self.contentType = contentType
  }

  /// EMU per typographic point (914400 EMU per inch, 72 pt per inch).
  public static let emuPerPoint: CGFloat = 914_400 / 72

  public static func points(fromEMU emu: Int) -> CGFloat {
    CGFloat(emu) / emuPerPoint
  }

  public static func emu(fromPoints points: CGFloat) -> Int {
    Int((points * emuPerPoint).rounded())
  }
}
