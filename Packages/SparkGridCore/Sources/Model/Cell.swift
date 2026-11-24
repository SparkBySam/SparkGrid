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
  /// Text that reads like a number or TRUE/FALSE but is text: a ZIP code such as 02134, a code
  /// such as 007, a file's text cell, or something typed after an apostrophe ('007). Without
  /// it, 02134 read back as the number 2134 and was saved as one, losing the zero for good
  /// (found Nov 18). Nil for everything else.
  public var isText: Bool?
  /// A formula from a file that did not mark it as an array formula, with a range in it.
  /// Other apps read such a formula as one value, as files saved before results could spill
  /// meant it, so it does not spill (`=B1:B8*2`, `=LEN(D1:D8)`). Typing the formula again
  /// clears it. Nil for everything else.
  public var opensAsOneValue: Bool?

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
    if isText == true, !raw.isEmpty { return .string(raw) }
    return CellValue.fromLiteralRaw(raw)
  }

  /// Marks `raw` as text when it would otherwise read as a number or TRUE/FALSE.
  public mutating func markTextIfNeeded() {
    guard !raw.isEmpty, !raw.hasPrefix("=") else {
      isText = nil
      return
    }
    if case .string = CellValue.fromLiteralRaw(raw) {
      isText = nil
    } else {
      isText = true
    }
  }

  public var isEmpty: Bool {
    raw.isEmpty && importedFormulaResult == nil && (format == nil || format == CellFormat())
  }
}
