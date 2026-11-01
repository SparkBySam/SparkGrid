import Formula
import Foundation
import GridCore
import Model

/// What the engine has calculated since the file was opened.
/// A save writes these values and keeps every other imported cache.
public nonisolated struct FormulaSaveStamp: Sendable {
  /// Lowercased sheet name to formula addresses whose results are current.
  public var freshValues: [String: [CellAddress: CellValue]]
  /// Cross-sheet update still running. The writer finishes it before the file is written.
  public var pendingCrossSheet: CrossSheetBackground.Request?
  /// A structural edit moved or replaced formulas. Imported caches from before that edit are stale.
  public var recalculateAllFormulas: Bool

  public init(
    freshValues: [String: [CellAddress: CellValue]] = [:],
    pendingCrossSheet: CrossSheetBackground.Request? = nil,
    recalculateAllFormulas: Bool = false
  ) {
    self.freshValues = freshValues
    self.pendingCrossSheet = pendingCrossSheet
    self.recalculateAllFormulas = recalculateAllFormulas
  }

  public static let empty = FormulaSaveStamp()
}

/// Puts the engine's current formula results on cells so export can write `<v>`.
/// Cells the engine has not recalculated keep the cache they were opened with.
public nonisolated enum FormulaCacheWriter {
  public static func prepare(_ workbook: Workbook, stamp: FormulaSaveStamp = .empty) -> Workbook {
    if stamp.recalculateAllFormulas {
      // A sort or other structural edit made every stored result stale. Recalculating the whole
      // workbook here took 17 s in Release and over 20 min in Debug on a 114k-formula file, and
      // Quit waited on it. The stale results are dropped instead: Excel recalculates a file
      // with no results when it opens it, and so does Spark Grid.
      return withoutFormulaResults(workbook)
    }
    if stamp.freshValues.isEmpty, stamp.pendingCrossSheet == nil,
      !hasMissingFormulaCache(workbook)
    {
      return workbook
    }
    var book = workbook
    // The edited sheet's engine values are applied last so they win over a second calculation.
    // Older results on other sheets are applied first, then the cross-sheet pass replaces them.
    var olderFresh = stamp.freshValues
    var editedSheetFresh: [String: [CellAddress: CellValue]] = [:]
    if let pending = stamp.pendingCrossSheet {
      let editedKey = pending.editedSheetName.lowercased()
      if let current = olderFresh.removeValue(forKey: editedKey) {
        editedSheetFresh[editedKey] = current
      }
    }
    write(olderFresh, into: &book)
    if var request = stamp.pendingCrossSheet {
      request.onlySheetName = nil
      request.workbook = workbook
      if let index = workbook.sheets.firstIndex(where: {
        $0.name.caseInsensitiveCompare(request.editedSheetName) == .orderedSame
      }) {
        request.editedSheet = workbook.sheets[index]
      }
      let outcome = CrossSheetBackground.compute(request)
      write(outcome.valuesBySheet, into: &book)
    }
    write(editedSheetFresh, into: &book)
    if hasMissingFormulaCache(book) {
      let missing = CrossSheetBackground.calculateFormulasWithoutCaches(in: book)
      write(missing.valuesBySheet, into: &book)
    }
    return book
  }

  /// The workbook with every stored formula result removed. Opening it calculates them.
  public static func withoutFormulaResults(_ workbook: Workbook) -> Workbook {
    var book = workbook
    clearFormulaCaches(&book)
    return book
  }

  private static func hasMissingFormulaCache(_ workbook: Workbook) -> Bool {
    for sheet in workbook.sheets {
      for cell in sheet.cells.values where FormulaSyntax.isFormula(cell.raw) {
        if cell.importedFormulaResult == nil { return true }
      }
    }
    return false
  }

  private static func clearFormulaCaches(_ workbook: inout Workbook) {
    for index in workbook.sheets.indices {
      var sheet = workbook.sheets[index]
      let formulas = sheet.cells.filter { FormulaSyntax.isFormula($0.value.raw) }
      var changed = false
      for (address, cell) in formulas {
        guard cell.importedFormulaResult != nil || cell.importedFormulaValueType != nil else {
          continue
        }
        var next = cell
        next.importedFormulaResult = nil
        next.importedFormulaValueType = nil
        sheet.setCell(next, at: address)
        changed = true
      }
      if changed {
        workbook.sheets[index] = sheet
      }
    }
  }

  private static func write(
    _ valuesBySheet: [String: [CellAddress: CellValue]],
    into workbook: inout Workbook
  ) {
    guard !valuesBySheet.isEmpty else { return }
    for (key, values) in valuesBySheet {
      guard
        let index = workbook.sheets.firstIndex(where: {
          $0.name.caseInsensitiveCompare(key) == .orderedSame
        })
      else { continue }
      var sheet = workbook.sheets[index]
      var changed = false
      for (address, value) in values {
        var cell = sheet.cell(at: address)
        let raw = cell.raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard FormulaSyntax.isFormula(raw) else { continue }
        if case .string(let text) = value,
          text.trimmingCharacters(in: .whitespacesAndNewlines) == raw
        {
          if cell.importedFormulaResult != nil || cell.importedFormulaValueType != nil {
            cell.importedFormulaResult = nil
            cell.importedFormulaValueType = nil
            sheet.setCell(cell, at: address)
            changed = true
          }
          continue
        }
        let stored = value.importedCacheStorage
        if cell.importedFormulaResult == stored.text, cell.importedFormulaValueType == stored.type {
          continue
        }
        cell.importedFormulaResult = stored.text
        cell.importedFormulaValueType = stored.type
        sheet.setCell(cell, at: address)
        changed = true
      }
      if changed {
        workbook.sheets[index] = sheet
      }
    }
  }
}
