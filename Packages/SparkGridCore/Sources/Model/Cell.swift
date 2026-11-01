import Formula
import Foundation
import GridCore
import NumberFormat

public nonisolated struct Cell: Codable, Equatable, Sendable {
  public var raw: String = ""
  public var format: CellFormat?
  /// Excel's last calculated `<v>` for a formula cell; seeds the engine until recalc.
  public var importedFormulaResult: String?
  /// Type of `importedFormulaResult`. Nil means the text has not been classified yet.
  public var importedFormulaValueType: ImportedFormulaValueType?

  public init(
    raw: String = "",
    format: CellFormat? = nil,
    importedFormulaResult: String? = nil,
    importedFormulaValueType: ImportedFormulaValueType? = nil
  ) {
    self.raw = raw
    self.format = format
    self.importedFormulaResult = importedFormulaResult
    self.importedFormulaValueType = importedFormulaValueType
  }

  /// Cached formula result, without calculating. Nil when the cell has no cache.
  public var cachedFormulaValue: CellValue? {
    guard let importedFormulaResult else { return nil }
    return CellValue.fromImportedCache(importedFormulaResult, type: importedFormulaValueType)
  }

  public var displayText: String { raw }

  public var isEmpty: Bool {
    raw.isEmpty && (format == nil || format == CellFormat())
  }
}
