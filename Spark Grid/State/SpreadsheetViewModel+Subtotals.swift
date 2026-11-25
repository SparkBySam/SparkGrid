import Foundation
import SparkGridCore

/// SUBTOTAL and AGGREGATE leave out the rows a filter hides, as in other apps: SUBTOTAL(109,…)
/// under a filtered list adds only what shows. The filter works on what cells show, so the app
/// works out the hidden rows and hands them to the sheet, then those formulas calculate again.
extension SpreadsheetViewModel {
  func syncFilteredRowsForFormulas() {
    let hidden = hiddenRowsForPrint()
    guard hidden != activeSheet.fileExtras.filteredRows else { return }
    var sheet = activeSheet
    sheet.fileExtras.filteredRows = hidden
    let readers = sheet.cells.compactMap { address, cell -> CellAddress? in
      guard FormulaSyntax.isFormula(cell.raw) else { return nil }
      let upper = cell.raw.uppercased()
      return upper.contains("SUBTOTAL(") || upper.contains("AGGREGATE(") ? address : nil
    }
    replaceActiveSheetForSpill(sheet, changed: readers)
  }
}
