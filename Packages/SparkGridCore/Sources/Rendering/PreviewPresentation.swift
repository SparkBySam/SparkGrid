import Calc
import Formula
import Foundation
import GridCore
import Model

/// What a cell shows in the Finder preview, and how it looks: the grid's text, alignment and
/// colors without the grid. Formulas the file saved no result for are calculated here when the
/// workbook is small enough to do so quickly.
public nonisolated struct PreviewPresentation: Sendable {
  public struct Style: Equatable, Sendable {
    public var alignment: CellFormat.HorizontalAlign
    public var bold: Bool
    public var italic: Bool
    public var fontSize: Double
    public var fill: CodableColor?
    /// Nil: the theme's text color.
    public var textColor: CodableColor?
    public var isError: Bool
  }

  /// Uncalculated formulas past this many are left blank; the preview says so.
  public static let maxFormulasToCalculate = 60_000

  public let workbook: Workbook
  /// Results for formulas the file has no result for, by sheet index.
  private let calculated: [Int: [CellAddress: CellValue]]
  /// True when some formulas had no saved result and were not calculated.
  public let hasUncalculatedFormulas: Bool

  public init(workbook: Workbook, results: [Int: [CellAddress: CellValue]], skipped: Bool) {
    self.workbook = workbook
    calculated = results
    hasUncalculatedFormulas = skipped
  }

  /// Calculates what the file left out. Runs on any thread, as the parallel recalculation's
  /// workers do; Quick Look calls it in the background.
  public static func make(_ workbook: Workbook) -> PreviewPresentation {
    var missing = 0
    var total = 0
    for sheet in workbook.sheets {
      for cell in sheet.cells.values where FormulaSyntax.isFormula(cell.raw) {
        total += 1
        if cell.cachedFormulaValue == nil { missing += 1 }
      }
    }
    guard missing > 0 else {
      return PreviewPresentation(workbook: workbook, results: [:], skipped: false)
    }
    guard total <= maxFormulasToCalculate else {
      return PreviewPresentation(workbook: workbook, results: [:], skipped: true)
    }
    let engine = FormulaEngine()
    engine.recalculateEntireWorkbook(workbook, profile: false)
    var results: [Int: [CellAddress: CellValue]] = [:]
    for (index, sheet) in workbook.sheets.enumerated() {
      results[index] = engine.formulaResults(on: sheet)
    }
    return PreviewPresentation(workbook: workbook, results: results, skipped: false)
  }

  /// The value a cell shows: its saved result, else the one calculated here.
  public func value(sheet index: Int, at address: CellAddress) -> CellValue? {
    let cell = workbook.sheets[index].cell(at: address)
    guard FormulaSyntax.isFormula(cell.raw) else { return nil }
    return cell.cachedFormulaValue ?? calculated[index]?[address]
  }

  public func text(sheet index: Int, at address: CellAddress) -> String {
    let cell = workbook.sheets[index].cell(at: address)
    if FormulaSyntax.isFormula(cell.raw) {
      let value = value(sheet: index, at: address) ?? .blank
      return CellFormatRenderer.displayText(for: value, format: cell.format, fallbackRaw: "")
    }
    return CellFormatRenderer.displayText(raw: cell.raw, format: cell.format)
  }

  /// As the grid draws the cell: general alignment puts numbers on the right, error values use
  /// the error color, and in dark mode automatic text on a fill follows the fill.
  public func style(sheet index: Int, at address: CellAddress, darkMode: Bool) -> Style {
    let cell = workbook.sheets[index].cell(at: address)
    let format = cell.format
    var isNumber = false
    var isError = false
    if FormulaSyntax.isFormula(cell.raw) {
      switch value(sheet: index, at: address) {
      case .number?: isNumber = true
      case .error?: isError = true
      default: break
      }
    } else {
      let trimmed = cell.raw.trimmingCharacters(in: .whitespaces)
      isNumber = !trimmed.isEmpty && Double(trimmed) != nil
    }
    var alignment = format?.horizontalAlign ?? .general
    if alignment == .general {
      alignment = isNumber || isError ? (isError ? .center : .right) : .left
    }
    var textColor = format?.textColor
    if darkMode, SparkTheme.readableTextOnFills, textColor == nil, let fill = format?.fillColor {
      textColor = CodableColor.contrastingText(on: fill)
    }
    return Style(
      alignment: alignment, bold: format?.bold ?? false, italic: format?.italic ?? false,
      fontSize: Double(format?.fontSize ?? 12), fill: format?.fillColor, textColor: textColor,
      isError: isError)
  }

  /// Column widths in points, as the sheet sets them.
  public func columnWidth(sheet index: Int, column: Int, default defaultWidth: Double) -> Double {
    Double(workbook.sheets[index].columnWidth(for: column, default: CGFloat(defaultWidth)))
  }
}
