import Calc
import Foundation
import GridCore
import Model

extension FormulaEngine {
  public func displayString(at address: CellAddress, sheet: Sheet, format: CellFormat?) -> String {
    let cell = sheet.cell(at: address)
    let value = sheetDisplayValue(at: address, sheet: sheet, cell: cell)
    return CellFormatRenderer.displayText(for: value, format: format, fallbackRaw: cell.raw)
  }
}
