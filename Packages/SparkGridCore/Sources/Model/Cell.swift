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

  /// A cell an array formula above or to the left spills into: nothing typed, a calculated value.
  /// Other apps save these cells the same way, as a value with no formula.
  public var isSpilled: Bool { raw.isEmpty && importedFormulaResult != nil }

  /// Something shows in the cell: typed text or a formula, or a value spilled into it.
  public var hasContent: Bool { !raw.isEmpty || importedFormulaResult != nil }

  /// The cell's value when it holds no formula: what was typed, or the value spilled into it.
  public var literalValue: CellValue {
    if raw.isEmpty, let spilled = cachedFormulaValue { return spilled }
    return CellValue.fromLiteralRaw(raw)
  }

  public var isEmpty: Bool {
    raw.isEmpty && importedFormulaResult == nil && (format == nil || format == CellFormat())
  }
}
