import AppKit
import CoreXLSX
import Foundation
import PDFKit
import SparkGridCore
import SwiftUI

typealias Workbook = SparkGridCore.Workbook
typealias Cell = SparkGridCore.Cell

#if DEBUG
  enum BugBashRunner {
    struct Result: Sendable {
      let name: String
      let passed: Bool
      let detail: String
    }

    static func runIfRequested() -> Bool {
      guard ProcessInfo.processInfo.environment["SPARK_GRID_BUG_BASH"] == "1" else { return false }
      let results = runAll()
      let failed = results.filter { !$0.passed }
      for result in results {
        let mark = result.passed ? "PASS" : "FAIL"
        print("[BugBash] \(mark): \(result.name) — \(result.detail)")
      }
      print("[BugBash] \(results.count - failed.count)/\(results.count) passed")
      if failed.isEmpty {
        print("[BugBash] ALL PASSED")
        exit(0)
      }
      fputs("[BugBash] FAILED\n", stderr)
      exit(1)
    }

    static func runAll() -> [Result] {
      var results: [Result] = []
      results.append(importSmoke(fixture: .formulas, label: "formulas"))
      results.append(importSmoke(fixture: .conditionalFormat, label: "CF bash"))
      results.append(importSmoke(fixture: .enterpriseThemed, label: "enterprise themed"))
      results.append(percentConditionalCompare())
      results.append(mergeRoundTrip())
      results.append(filterCriteriaRoundTrip())
      results.append(emptyFilterRoundTrip())
      results.append(chartRoundTrip())
      results.append(colorScaleRoundTrip())
      results.append(themeSchemeParse())
      results.append(mergeSelectionSnap())
      results.append(sharedFormulaRoundTrip())
      results.append(sharedFormulaExpansionManyCells())
      results.append(kpiWorkbookSharedFormulaImport())
      results.append(conditionalFormatImport())
      results.append(highlightRoundTrip())
      results.append(cfDxfExcelCompat())
      results.append(dataBarRoundTrip())
      results.append(excelChartParts())
      results.append(imageImport())
      results.append(chartPreviewSeries())
      results.append(MainActor.assumeIsolated { insertPictureModel() })
      results.append(worksheetElementOrder())
      results.append(enterpriseFilterImport())
      results.append(MainActor.assumeIsolated { findScopePersistsAfterJump() })
      results.append(MainActor.assumeIsolated { largeEmptyFormatApply() })
      results.append(cfParseNumber())
      results.append(MainActor.assumeIsolated { sortRemapsMerge() })
      results.append(MainActor.assumeIsolated { sortUndoKeepsFormulas() })
      results.append(MainActor.assumeIsolated { textToColumnsSplitsAndUndoes() })
      results.append(MainActor.assumeIsolated { rowGroupsFoldAndSave() })
      results.append(MainActor.assumeIsolated { sheetProtectionGuardsLockedCells() })
      results.append(MainActor.assumeIsolated { printAreaAndPageBreaks() })
      results.append(MainActor.assumeIsolated { pdfExportKeepsPages() })
      results.append(MainActor.assumeIsolated { scrollWhileEditingKeepsColumnText() })
      results.append(MainActor.assumeIsolated { typingOverAValueHidesTheOldText() })
      results.append(MainActor.assumeIsolated { fillSkipsFilteredRows() })
      results.append(MainActor.assumeIsolated { printWithoutHeadings() })
      results.append(MainActor.assumeIsolated { editThenTileScrollShowsEdit() })
      results.append(MainActor.assumeIsolated { linksInsertFollowRemove() })
      results.append(MainActor.assumeIsolated { pivotCreateDrawRefreshUndo() })
      results.append(MainActor.assumeIsolated { pivotGroupsDatesByMonth() })
      results.append(MainActor.assumeIsolated { filePivotRefreshes() })
      results.append(MainActor.assumeIsolated { arrayFormulasSpill() })
      results.append(MainActor.assumeIsolated { insertRowUndoRedoAlternates() })
      results.append(MainActor.assumeIsolated { undoRedoAlternatesForEveryStep() })
      results.append(MainActor.assumeIsolated { spillsSurviveMovingCells() })
      results.append(MainActor.assumeIsolated { spillReferencesFollowTheSpill() })
      results.append(MainActor.assumeIsolated { mergeLeavesNoSavedResult() })
      results.append(MainActor.assumeIsolated { filterPopoverModel() })
      results.append(MainActor.assumeIsolated { commandArrowJumps() })
      results.append(MainActor.assumeIsolated { sheetTabMove() })
      results.append(MainActor.assumeIsolated { insertColumnPastLastColumn() })
      results.append(MainActor.assumeIsolated { selectionSizedInsert() })
      results.append(MainActor.assumeIsolated { freezeThroughSelection() })
      results.append(MainActor.assumeIsolated { insertChartEmptySelection() })
      results.append(formulaExactTokenSkipsAutocomplete())
      results.append(MainActor.assumeIsolated { editExistingChart() })
      results.append(onSheetChartFrame())
      results.append(chartPlotPaddingBounded())
      results.append(chartScaleDomainHolds())
      results.append(weeklyCallsLastLabel())
      results.append(chartValueColors())
      results.append(chartFrameDrag())
      results.append(chartCommandFreePlacement())
      results.append(chartSlidesUnderFrozenPanes())
      results.append(MainActor.assumeIsolated { frozenPanesCoverChartPixels() })
      results.append(MainActor.assumeIsolated { scrolledCellsStayBelowFrozenPanes() })
      results.append(MainActor.assumeIsolated { mergedCellsHideInteriorGridLines() })
      results.append(MainActor.assumeIsolated { chartMoveResizeAndColorRoundTrip() })
      results.append(legacyChartLandsUnderData())
      results.append(cfFillTextContrast())
      results.append(formulaEvalRegressionGate())
      results.append(everydayFormulas())
      results.append(sumproductBooleanFastPathSelfCheck())
      results.append(kpiJuneStyleCountifs())
      results.append(countifsSkipsErrorRows())
      results.append(countifsRangeDependencyBudget())
      results.append(syntheticWorkbookAggregateRecalcBudget())
      results.append(syntheticWorkbookAggregateEditBudget())
      results.append(kpiWorkbookFullRecalcBudget())
      results.append(kpiWorkbookAggregateEditBudget())
      results.append(nowAndTodayUseLocalTime())
      results.append(lookupFormulas())
      results.append(formulaFunctionPicker())
      results.append(excelFormatCodes())
      results.append(MainActor.assumeIsolated { cellFormatApplyCloses() })
      results.append(MainActor.assumeIsolated { customFormatPasteStaysInField() })
      results.append(definedNamesResolve())
      results.append(MainActor.assumeIsolated { nameManagerEditsSheet() })
      results.append(MainActor.assumeIsolated { cellFormatCodeEditsSheet() })
      results.append(MainActor.assumeIsolated { conditionalFormatRuleEdit() })
      results.append(MainActor.assumeIsolated { conditionalBoldUncheckPersists() })
      results.append(cellTextOverflowAndClip())
      results.append(MainActor.assumeIsolated { cellTextWrapLayout() })
      results.append(MainActor.assumeIsolated { textDisplayToolbarLabel() })
      results.append(MainActor.assumeIsolated { unsavedPromptOnce() })
      results.append(largeWorkbookOpenBaseline())
      results.append(MainActor.assumeIsolated { wideFreezeMergeLayoutOpen() })
      results.append(MainActor.assumeIsolated { bdcKpiWorkbookOpenPath() })
      results.append(MainActor.assumeIsolated { largeSyntheticWorkbookColdViewportScroll() })
      results.append(MainActor.assumeIsolated { largeSheetScrollRegionBudgets() })
      results.append(MainActor.assumeIsolated { liveScrollTickMovesCellsWithoutPainting() })
      results.append(MainActor.assumeIsolated { kpiWorkbookMultiSheetScroll() })
      results.append(MainActor.assumeIsolated { conditionalFormatPaste() })
      results.append(editorSpellChecking())
      return results
    }

    /// Optional local xlsx samples for import/round-trip checks.
    /// Set `SPARK_GRID_FIXTURES` to a directory of generic filenames, or override a single
    /// file with the matching `SPARK_GRID_FIXTURE_*` env var (absolute path).
    private enum Fixture: String {
      case formulas
      case conditionalFormat = "conditional_format"
      case enterpriseThemed = "enterprise_themed"
      case enterpriseImages = "enterprise_images"

      var envKey: String {
        switch self {
        case .formulas: return "SPARK_GRID_FIXTURE_FORMULAS"
        case .conditionalFormat: return "SPARK_GRID_FIXTURE_CF"
        case .enterpriseThemed: return "SPARK_GRID_FIXTURE_ENTERPRISE"
        case .enterpriseImages: return "SPARK_GRID_FIXTURE_ENTERPRISE_IMAGES"
        }
      }

      var fileName: String { "\(rawValue).xlsx" }
    }

    private static func fixturePath(_ fixture: Fixture) -> String? {
      let env = ProcessInfo.processInfo.environment
      if let explicit = env[fixture.envKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
        !explicit.isEmpty,
        FileManager.default.fileExists(atPath: explicit)
      {
        return explicit
      }
      if let dir = env["SPARK_GRID_FIXTURES"]?.trimmingCharacters(in: .whitespacesAndNewlines),
        !dir.isEmpty
      {
        let path = (dir as NSString).appendingPathComponent(fixture.fileName)
        if FileManager.default.fileExists(atPath: path) { return path }
      }
      return nil
    }

    /// Regression for KPI-scale worksheets: whole-sheet `<c>…</c>` regex used to hang in `expandSharedFormulas`.
    private static func sharedFormulaExpansionManyCells() -> Result {
      let name = "shared formula expansion many cells"
      do {
        // Built here: the sandbox cannot read Fixtures/shared_formula_many_cells.xlsx. Same
        // shape: 3,500 value cells in one row, then a shared formula and its follower.
        var cells = ""
        for n in 1...3500 { cells += #"<c r="Z\#(n)"><v>\#(n)</v></c>"# }
        cells += #"<c r="AA1"><f t="shared" ref="AA1:AA2" si="5">Z1+1</f></c>"#
        cells += #"<c r="AA2"><f t="shared" si="5"/></c>"#
        let sheetXML = """
          <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
          <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">\
          <sheetData><row r="1">\(cells)</row></sheetData></worksheet>
          """
        var base = Sheet(name: "Sheet1")
        base.setCell(Cell(raw: "1"), at: .origin)
        let exported = try XLSXCodec.exportWorkbook(Workbook(sheets: [base]))
        guard
          let data = XLSXCodec.replacingZipEntry(
            archiveData: exported, entryPath: "xl/worksheets/sheet1.xml",
            with: Data(sheetXML.utf8))
        else {
          return Result(name: name, passed: false, detail: "could not build the workbook")
        }
        let start = CFAbsoluteTimeGetCurrent()
        let workbook = try XLSXCodec.importWorkbook(from: data)
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        guard elapsed < 15 else {
          return Result(
            name: name,
            passed: false,
            detail: String(format: "import took %.1fs", elapsed)
          )
        }
        let follower = workbook.activeSheet.cell(at: CellAddress(row: 1, col: 26))
        guard FormulaSyntax.isFormula(follower.raw) else {
          return Result(
            name: name, passed: false, detail: "follower AA2 not a formula: \(follower.raw)")
        }
        return Result(
          name: name,
          passed: true,
          detail: String(format: "3500 cells + shared follower in %.2fs", elapsed)
        )
      } catch {
        return Result(name: name, passed: false, detail: error.localizedDescription)
      }
    }

    /// Optional full KPI workbook; import must finish (shared-formula expansion used to hang).
    private static func kpiWorkbookSharedFormulaImport() -> Result {
      let name = "KPI workbook shared formula import"
      let env = ProcessInfo.processInfo.environment
      let envPath =
        env["SPARK_GRID_FIXTURE_BDC_KPI"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let fixturesDir =
        env["SPARK_GRID_FIXTURES"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let fixturesPath = (fixturesDir as NSString).appendingPathComponent(
        "BDC-Digital-KPI-2026.xlsx")
      let hasSource =
        (!envPath.isEmpty && FileManager.default.fileExists(atPath: envPath))
        || (!fixturesDir.isEmpty && FileManager.default.fileExists(atPath: fixturesPath))
      guard hasSource else {
        return Result(name: name, passed: true, detail: "skipped (no KPI fixture source)")
      }
      do {
        let url = try sandboxReadableWorkbookURL(
          cacheFileName: "BDC-Digital-KPI-2026.xlsx",
          envKeys: ["SPARK_GRID_FIXTURE_BDC_KPI"],
          fixturesFileName: "BDC-Digital-KPI-2026.xlsx"
        )
        let start = CFAbsoluteTimeGetCurrent()
        let workbook = try XLSXCodec.importWorkbook(from: url)
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        let cellCount = workbook.sheets.reduce(0) { $0 + $1.cells.count }
        let formulaCount = workbook.sheets.reduce(0) { partial, sheet in
          partial + sheet.cells.values.filter { FormulaSyntax.isFormula($0.raw) }.count
        }
        guard elapsed < 300 else {
          return Result(
            name: name,
            passed: false,
            detail: String(format: "import took %.1fs for %d cells", elapsed, cellCount)
          )
        }
        guard formulaCount >= 48_000 else {
          return Result(
            name: name,
            passed: false,
            detail: "expected ~48191 formulas after shared expansion, got \(formulaCount)"
          )
        }
        return Result(
          name: name,
          passed: true,
          detail: String(
            format: "%d cells, %d formulas imported in %.1fs", cellCount, formulaCount, elapsed)
        )
      } catch {
        return Result(name: name, passed: false, detail: error.localizedDescription)
      }
    }

    private static func sharedFormulaRoundTrip() -> Result {
      guard let path = fixturePath(.formulas) else {
        return Result(
          name: "shared formula round-trip", passed: true, detail: "skipped (no fixture)")
      }
      do {
        let original = try XLSXCodec.importWorkbook(from: URL(fileURLWithPath: path))
        let formulaCount = original.activeSheet.cells.values.filter {
          FormulaSyntax.isFormula($0.raw)
        }.count
        guard formulaCount > 0 else {
          return Result(
            name: "shared formula round-trip", passed: false, detail: "no formulas in source")
        }
        let data = try XLSXCodec.exportWorkbook(original)
        let roundTripped = try XLSXCodec.importWorkbook(from: data)
        let rtCount = roundTripped.activeSheet.cells.values.filter {
          FormulaSyntax.isFormula($0.raw)
        }.count
        guard rtCount >= formulaCount else {
          return Result(
            name: "shared formula round-trip",
            passed: false,
            detail: "formulas \(formulaCount) -> \(rtCount)"
          )
        }
        return Result(
          name: "shared formula round-trip", passed: true, detail: "\(rtCount) formulas")
      } catch {
        return Result(
          name: "shared formula round-trip", passed: false, detail: error.localizedDescription)
      }
    }

    private static func conditionalFormatImport() -> Result {
      guard let path = fixturePath(.conditionalFormat) else {
        return Result(name: "CF import", passed: true, detail: "skipped (no fixture)")
      }
      do {
        let wb = try XLSXCodec.importWorkbook(from: URL(fileURLWithPath: path))
        let count = wb.activeSheet.conditionalFormats.count
        guard count > 0 else {
          return Result(name: "CF import", passed: false, detail: "no rules imported")
        }
        return Result(name: "CF import", passed: true, detail: "\(count) rule(s)")
      } catch {
        return Result(name: "CF import", passed: false, detail: error.localizedDescription)
      }
    }

    private static func highlightRoundTrip() -> Result {
      var sheet = Sheet(name: "Test")
      sheet.setCell(Cell(raw: "5"), at: CellAddress(row: 0, col: 0))
      sheet.setCell(Cell(raw: "15"), at: CellAddress(row: 1, col: 0))
      sheet.conditionalFormats = [
        ConditionalFormatRule(
          range: CellRange(start: .origin, end: CellAddress(row: 9, col: 0)),
          predicate: .greaterThan(10),
          style: .redFill
        )
      ]
      do {
        let data = try XLSXCodec.exportWorkbook(Workbook(sheets: [sheet]))
        let xml =
          XLSXCodec.zipEntryString(archiveData: data, entryPath: "xl/worksheets/sheet1.xml") ?? ""
        let styles = XLSXCodec.zipEntryString(archiveData: data, entryPath: "xl/styles.xml") ?? ""
        guard xml.contains("type=\"cellIs\""), xml.contains("conditionalFormatting") else {
          return Result(name: "highlight export", passed: false, detail: "missing cellIs CF in XML")
        }
        // One copy of each rule: a second copy in an extension block hid them in other apps.
        guard !xml.contains("x14:conditionalFormatting"), styles.contains("<cellStyles") else {
          return Result(
            name: "highlight export", passed: false, detail: "extra x14 CF or missing cellStyles")
        }
        let imported = try XLSXCodec.importWorkbook(from: data)
        guard imported.activeSheet.conditionalFormats.count == 1,
          case .greaterThan(10) = imported.activeSheet.conditionalFormats[0].predicate
        else {
          return Result(
            name: "highlight round-trip", passed: false,
            detail: "\(imported.activeSheet.conditionalFormats)")
        }
        return Result(name: "highlight round-trip", passed: true, detail: "ok")
      } catch {
        return Result(
          name: "highlight round-trip", passed: false, detail: error.localizedDescription)
      }
    }

    private static func cfDxfExcelCompat() -> Result {
      var sheet = Sheet(name: "Test")
      sheet.conditionalFormats = [
        ConditionalFormatRule(
          range: CellRange(start: .origin, end: CellAddress(row: 9, col: 0)),
          predicate: .greaterThan(10),
          style: .redFill
        )
      ]
      do {
        let data = try XLSXCodec.exportWorkbook(Workbook(sheets: [sheet]))
        let styles = XLSXCodec.zipEntryString(archiveData: data, entryPath: "xl/styles.xml") ?? ""
        guard styles.contains("<dxf>"), styles.contains("bgColor") else {
          return Result(name: "CF dxf excel compat", passed: false, detail: "missing dxf bgColor")
        }
        guard !styles.contains(#"bgColor indexed="64""#) else {
          return Result(
            name: "CF dxf excel compat", passed: false, detail: "dxf still has bgColor indexed=64")
        }
        return Result(name: "CF dxf excel compat", passed: true, detail: "bgColor solid fill")
      } catch {
        return Result(
          name: "CF dxf excel compat", passed: false, detail: error.localizedDescription)
      }
    }

    private static func imageImport() -> Result {
      let pngData: Data
      if let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: 8,
        pixelsHigh: 8,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
      ),
        let encoded = rep.representation(using: .png, properties: [:])
      {
        pngData = encoded
      } else {
        return Result(name: "image round-trip", passed: false, detail: "couldn't build PNG")
      }

      var sheet = Sheet(name: "Images")
      sheet.images = [
        SheetImage(
          anchorRow: 1,
          anchorCol: 0,
          widthEMU: 1_016_000,
          heightEMU: 381_000,
          imageData: pngData
        )
      ]
      do {
        let data = try XLSXCodec.exportWorkbook(Workbook(sheets: [sheet]))
        guard XLSXCodec.zipEntryData(archiveData: data, entryPath: "xl/media/image1.png") != nil,
          XLSXCodec.zipEntryString(archiveData: data, entryPath: "xl/drawings/drawing1.xml")?
            .contains("oneCellAnchor") == true
        else {
          return Result(name: "image export", passed: false, detail: "missing drawing/media parts")
        }
        let imported = try XLSXCodec.importWorkbook(from: data)
        guard imported.activeSheet.images.count == 1,
          imported.activeSheet.images[0].imageData == pngData
        else {
          return Result(name: "image round-trip", passed: false, detail: "import mismatch")
        }
      } catch {
        return Result(name: "image round-trip", passed: false, detail: error.localizedDescription)
      }

      guard let samplePath = fixturePath(.enterpriseImages) else {
        return Result(
          name: "image round-trip", passed: true, detail: "synthetic ok; sample fixture skipped")
      }
      do {
        let wb = try XLSXCodec.importWorkbook(from: URL(fileURLWithPath: samplePath))
        let imageCount = wb.sheets.reduce(0) { $0 + $1.images.count }
        guard imageCount > 0 else {
          return Result(
            name: "image sample import", passed: false, detail: "no images in sample fixture")
        }
        return Result(
          name: "image round-trip", passed: true,
          detail: "synthetic + \(imageCount) sample image(s)")
      } catch {
        return Result(
          name: "image round-trip", passed: true,
          detail: "synthetic ok; sample: \(error.localizedDescription)")
      }
    }

    private static func chartPreviewSeries() -> Result {
      // Count-by-category (CRM-style): dates in col 0, junk ids in col 1.
      let range = CellRange(
        start: CellAddress(row: 0, col: 0),
        end: CellAddress(row: 3, col: 1)
      )
      let labels = ["Lead Date", "8/1/26", "8/1/26", "8/2/26"]
      let ids = ["Lead ID", "100", "200", "300"]
      let chart = SheetChart(
        kind: .bar,
        title: "Count by Lead Date",
        dataRange: range,
        categoryColumn: 0,
        valueColumn: 1,
        hasHeaderRow: true,
        valueMode: .count,
        anchorRow: 5,
        anchorCol: 0
      )
      let series = ChartPreviewSeries.points(
        for: chart,
        labelFor: { address in
          address.col == 0 ? labels[address.row] : ids[address.row]
        },
        numberFor: { address in
          address.col == 1 ? Double(ids[address.row]) : nil
        }
      )
      guard series.points.count == 2,
        series.points[0].label == "8/1/26",
        series.points[0].value == 2,
        series.points[1].label == "8/2/26",
        series.points[1].value == 1
      else {
        return Result(name: "chart preview series", passed: false, detail: "\(series.points)")
      }

      let suggestion = ChartPreviewSeries.suggest(
        in: range,
        labelFor: { address in
          address.col == 0 ? labels[address.row] : ids[address.row]
        },
        numberFor: { address in
          // Treat Lead ID as non-chart numeric noise: only pure small ints from a metrics col.
          nil
        }
      )
      guard suggestion.valueMode == .count, suggestion.categoryColumn == 0 else {
        return Result(
          name: "chart preview series", passed: false, detail: "bad suggestion \(suggestion)")
      }
      return Result(name: "chart preview series", passed: true, detail: "count-by-category ok")
    }

    @MainActor
    private static func insertPictureModel() -> Result {
      let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [Sheet(name: "Test")]))
      vm.selectRange(from: CellAddress(row: 2, col: 2), to: CellAddress(row: 2, col: 2))
      guard
        let rep = NSBitmapImageRep(
          bitmapDataPlanes: nil,
          pixelsWide: 4,
          pixelsHigh: 4,
          bitsPerSample: 8,
          samplesPerPixel: 4,
          hasAlpha: true,
          isPlanar: false,
          colorSpaceName: .deviceRGB,
          bytesPerRow: 0,
          bitsPerPixel: 0
        ),
        let png = rep.representation(using: .png, properties: [:])
      else {
        return Result(name: "insert picture", passed: false, detail: "png setup failed")
      }
      vm.insertImage(data: png, contentType: "image/png")
      guard vm.activeSheet.images.count == 1,
        vm.activeSheet.images[0].anchorRow == 2,
        vm.activeSheet.images[0].anchorCol == 2,
        vm.selectedImageID == vm.activeSheet.images[0].id
      else {
        return Result(
          name: "insert picture", passed: false, detail: "image not placed at selection")
      }
      return Result(name: "insert picture", passed: true, detail: "anchored at selection")
    }

    private static func dataBarRoundTrip() -> Result {
      var sheet = Sheet(name: "Test")
      sheet.setCell(Cell(raw: "10"), at: CellAddress(row: 0, col: 0))
      sheet.setCell(Cell(raw: "90"), at: CellAddress(row: 1, col: 0))
      sheet.conditionalFormats = [
        ConditionalFormatRule(
          range: CellRange(start: .origin, end: CellAddress(row: 1, col: 0)),
          predicate: .dataBar(.blue),
          style: ConditionalFormatStyle()
        ),
        ConditionalFormatRule(
          range: CellRange(start: .origin, end: CellAddress(row: 1, col: 0)),
          predicate: .iconSet(.threeTrafficLights),
          style: ConditionalFormatStyle()
        ),
      ]
      do {
        let data = try XLSXCodec.exportWorkbook(Workbook(sheets: [sheet]))
        let xml =
          XLSXCodec.zipEntryString(archiveData: data, entryPath: "xl/worksheets/sheet1.xml") ?? ""
        guard xml.contains("type=\"dataBar\""), xml.contains("type=\"iconSet\"") else {
          return Result(
            name: "data bar / icon export", passed: false, detail: "missing CF types in XML")
        }
        let imported = try XLSXCodec.importWorkbook(from: data)
        let preds = imported.activeSheet.conditionalFormats.map(\.predicate)
        let hasBar = preds.contains {
          if case .dataBar = $0 { return true }
          return false
        }
        let hasIcon = preds.contains {
          if case .iconSet = $0 { return true }
          return false
        }
        guard hasBar, hasIcon else {
          return Result(name: "data bar / icon round-trip", passed: false, detail: "\(preds)")
        }
        return Result(name: "data bar / icon round-trip", passed: true, detail: "ok")
      } catch {
        return Result(
          name: "data bar / icon round-trip", passed: false, detail: error.localizedDescription)
      }
    }

    private static func excelChartParts() -> Result {
      var sheet = Sheet(name: "Sales")
      sheet.setCell(Cell(raw: "A"), at: CellAddress(row: 0, col: 0))
      sheet.setCell(Cell(raw: "10"), at: CellAddress(row: 1, col: 0))
      sheet.setCell(Cell(raw: "20"), at: CellAddress(row: 2, col: 0))
      sheet.charts = [
        SheetChart(
          kind: .bar,
          title: "Sales",
          dataRange: CellRange(start: .origin, end: CellAddress(row: 2, col: 0)),
          anchorRow: 4,
          anchorCol: 2
        )
      ]
      do {
        let data = try XLSXCodec.exportWorkbook(Workbook(sheets: [sheet]))
        for path in [
          "xl/charts/chart1.xml",
          "xl/drawings/drawing1.xml",
          "xl/worksheets/_rels/sheet1.xml.rels",
        ] {
          guard XLSXCodec.zipEntryString(archiveData: data, entryPath: path) != nil else {
            return Result(name: "excel chart parts", passed: false, detail: "missing \(path)")
          }
        }
        let sheetXML =
          XLSXCodec.zipEntryString(archiveData: data, entryPath: "xl/worksheets/sheet1.xml") ?? ""
        guard sheetXML.contains("<drawing") else {
          return Result(
            name: "excel chart parts", passed: false, detail: "worksheet missing drawing ref")
        }
        return Result(name: "excel chart parts", passed: true, detail: "drawing+chart+rels")
      } catch {
        return Result(name: "excel chart parts", passed: false, detail: error.localizedDescription)
      }
    }

    private static func worksheetElementOrder() -> Result {
      var sheet = Sheet(name: "Test")
      sheet.setCell(Cell(raw: "A"), at: .origin)
      sheet.setCell(Cell(raw: "B"), at: CellAddress(row: 0, col: 1))
      sheet.mergedRanges = [
        CellRange(start: .origin, end: CellAddress(row: 0, col: 1))
      ]
      sheet.autoFilter = SheetFilterState(
        range: CellRange(start: .origin, end: CellAddress(row: 2, col: 1)),
        selectedValuesByColumn: [:]
      )
      do {
        let data = try XLSXCodec.exportWorkbook(Workbook(sheets: [sheet]))
        let xml =
          XLSXCodec.zipEntryString(archiveData: data, entryPath: "xl/worksheets/sheet1.xml") ?? ""
        guard let filterIdx = xml.range(of: "<autoFilter")?.lowerBound,
          let mergeIdx = xml.range(of: "<mergeCells")?.lowerBound
        else {
          return Result(
            name: "worksheet element order", passed: false,
            detail: "missing autoFilter or mergeCells")
        }
        guard filterIdx < mergeIdx else {
          return Result(
            name: "worksheet element order", passed: false,
            detail: "mergeCells before autoFilter (Excel rejects)")
        }
        return Result(
          name: "worksheet element order", passed: true, detail: "autoFilter before mergeCells")
      } catch {
        return Result(
          name: "worksheet element order", passed: false, detail: error.localizedDescription)
      }
    }

    private static func enterpriseFilterImport() -> Result {
      guard let path = fixturePath(.enterpriseThemed) else {
        return Result(
          name: "enterprise filter import", passed: true, detail: "skipped (no fixture)")
      }
      do {
        let wb = try XLSXCodec.importWorkbook(from: URL(fileURLWithPath: path))
        let withFilters = wb.sheets.filter { $0.autoFilter != nil }
        guard withFilters.count >= 2 else {
          return Result(
            name: "enterprise filter import",
            passed: false,
            detail: "expected ≥2 sheets with autoFilter, got \(withFilters.count)"
          )
        }
        let reportFilters = withFilters.prefix(2)
        for sheet in reportFilters {
          guard let filter = sheet.autoFilter else { continue }
          let n = filter.range.normalized
          guard n.minRow == 4 else {
            return Result(
              name: "enterprise filter import",
              passed: false,
              detail: "\(sheet.name) header row \(n.minRow + 1), expected 5"
            )
          }
        }
        return Result(
          name: "enterprise filter import",
          passed: true,
          detail: "\(withFilters.count) sheets filtered; Report headers on row 5"
        )
      } catch {
        return Result(
          name: "enterprise filter import", passed: false, detail: error.localizedDescription)
      }
    }

    private static func importSmoke(fixture: Fixture, label: String) -> Result {
      guard let path = fixturePath(fixture) else {
        return Result(name: "import \(label)", passed: true, detail: "skipped (no fixture)")
      }
      let url = URL(fileURLWithPath: path)
      do {
        let wb = try XLSXCodec.importWorkbook(from: url)
        guard !wb.sheets.isEmpty else {
          return Result(name: "import \(label)", passed: false, detail: "empty workbook")
        }
        return Result(
          name: "import \(label)",
          passed: true,
          detail: "\(wb.sheets.count) sheet(s), \(wb.activeSheet.cells.count) cells"
        )
      } catch {
        return Result(name: "import \(label)", passed: false, detail: error.localizedDescription)
      }
    }

    private static func percentConditionalCompare() -> Result {
      let matches = ConditionalFormatEvaluator.matches(
        .greaterThan(50),
        value: .number(1.0),
        displayString: "100%",
        numberFormat: .percent,
        address: .origin,
        origin: .origin,
        evaluateFormula: { _, _, _ in .blank }
      )
      let noMatch = ConditionalFormatEvaluator.matches(
        .greaterThan(50),
        value: .number(0.4),
        displayString: "40%",
        numberFormat: .percent,
        address: .origin,
        origin: .origin,
        evaluateFormula: { _, _, _ in .blank }
      )
      guard matches, !noMatch else {
        return Result(
          name: "percent CF compare", passed: false,
          detail: "100% > 50 expected true, 40% > 50 false")
      }
      return Result(name: "percent CF compare", passed: true, detail: "ok")
    }

    private static func mergeRoundTrip() -> Result {
      var sheet = Sheet(name: "Test")
      sheet.setCell(Cell(raw: "Title"), at: CellAddress(row: 0, col: 0))
      sheet.mergedRanges = [
        CellRange(
          start: CellAddress(row: 0, col: 0),
          end: CellAddress(row: 0, col: 2)
        )
      ]
      let wb = Workbook(sheets: [sheet])
      do {
        let data = try XLSXCodec.exportWorkbook(wb)
        let imported = try XLSXCodec.importWorkbook(from: data)
        guard imported.activeSheet.mergedRanges.count == 1 else {
          return Result(
            name: "merge round-trip", passed: false,
            detail: "expected 1 merge, got \(imported.activeSheet.mergedRanges.count)")
        }
        let m = imported.activeSheet.mergedRanges[0].normalized
        guard m.minRow == 0, m.maxRow == 0, m.minCol == 0, m.maxCol == 2 else {
          return Result(name: "merge round-trip", passed: false, detail: "wrong bounds \(m)")
        }
        return Result(name: "merge round-trip", passed: true, detail: "ok")
      } catch {
        return Result(name: "merge round-trip", passed: false, detail: error.localizedDescription)
      }
    }

    private static func emptyFilterRoundTrip() -> Result {
      var sheet = Sheet(name: "Test")
      sheet.setCell(Cell(raw: "H"), at: CellAddress(row: 4, col: 0))
      sheet.setCell(Cell(raw: "1"), at: CellAddress(row: 5, col: 0))
      sheet.autoFilter = SheetFilterState(
        range: CellRange(
          start: CellAddress(row: 4, col: 0),
          end: CellAddress(row: 5, col: 2)
        ),
        selectedValuesByColumn: [:]
      )
      do {
        let data = try XLSXCodec.exportWorkbook(Workbook(sheets: [sheet]))
        let xml =
          XLSXCodec.zipEntryString(archiveData: data, entryPath: "xl/worksheets/sheet1.xml") ?? ""
        guard xml.contains(#"<autoFilter ref="A5:C6"/>"#) || xml.contains(#"ref="A5:C6""#) else {
          return Result(
            name: "empty filter export", passed: false, detail: "missing autoFilter ref A5:C6")
        }
        let imported = try XLSXCodec.importWorkbook(from: data)
        guard let filter = imported.activeSheet.autoFilter else {
          return Result(
            name: "empty filter round-trip", passed: false, detail: "no autofilter after import")
        }
        let n = filter.range.normalized
        guard n.minRow == 4, n.maxRow == 5, n.minCol == 0, n.maxCol == 2 else {
          return Result(name: "empty filter round-trip", passed: false, detail: "wrong range \(n)")
        }
        guard filter.selectedValuesByColumn.isEmpty else {
          return Result(
            name: "empty filter round-trip", passed: false, detail: "expected no criteria")
        }
        return Result(name: "empty filter round-trip", passed: true, detail: "A5:C6 preserved")
      } catch {
        return Result(
          name: "empty filter round-trip", passed: false, detail: error.localizedDescription)
      }
    }

    private static func filterCriteriaRoundTrip() -> Result {
      var sheet = Sheet(name: "Test")
      for row in 0...3 {
        sheet.setCell(Cell(raw: row == 0 ? "Name" : "A"), at: CellAddress(row: row, col: 0))
        sheet.setCell(
          Cell(raw: row == 0 ? "Val" : (row == 1 ? "X" : "Y")), at: CellAddress(row: row, col: 1))
      }
      let range = CellRange(
        start: CellAddress(row: 0, col: 0),
        end: CellAddress(row: 3, col: 1)
      )
      sheet.autoFilter = SheetFilterState(
        range: range,
        selectedValuesByColumn: [1: ["X"]]
      )
      let wb = Workbook(sheets: [sheet])
      do {
        let data = try XLSXCodec.exportWorkbook(wb)
        let xml =
          XLSXCodec.zipEntryString(archiveData: data, entryPath: "xl/worksheets/sheet1.xml") ?? ""
        guard xml.contains("filterColumn"), xml.contains("filter val=\"X\"") else {
          return Result(
            name: "filter criteria export", passed: false, detail: "missing filterColumn XML")
        }
        let imported = try XLSXCodec.importWorkbook(from: data)
        guard let filter = imported.activeSheet.autoFilter else {
          return Result(
            name: "filter criteria round-trip", passed: false, detail: "no autofilter after import")
        }
        guard filter.selectedValuesByColumn[1] == ["X"] else {
          return Result(
            name: "filter criteria round-trip",
            passed: false,
            detail: "col 1 values: \(String(describing: filter.selectedValuesByColumn[1]))"
          )
        }
        return Result(name: "filter criteria round-trip", passed: true, detail: "ok")
      } catch {
        return Result(
          name: "filter criteria round-trip", passed: false, detail: error.localizedDescription)
      }
    }

    private static func chartRoundTrip() -> Result {
      var sheet = Sheet(name: "Test")
      sheet.setCell(Cell(raw: "A"), at: CellAddress(row: 0, col: 0))
      sheet.setCell(Cell(raw: "10"), at: CellAddress(row: 1, col: 0))
      sheet.setCell(Cell(raw: "20"), at: CellAddress(row: 2, col: 0))
      let chart = SheetChart(
        kind: .bar,
        title: "Test",
        dataRange: CellRange(start: CellAddress(row: 0, col: 0), end: CellAddress(row: 2, col: 0)),
        anchorRow: 4,
        anchorCol: 0
      )
      sheet.charts = [chart]
      let wb = Workbook(sheets: [sheet])
      do {
        let data = try XLSXCodec.exportWorkbook(wb)
        guard
          XLSXCodec.zipEntryString(archiveData: data, entryPath: "xl/sparkGrid/charts1.json") != nil
        else {
          return Result(name: "chart round-trip", passed: false, detail: "missing charts json part")
        }
        let imported = try XLSXCodec.importWorkbook(from: data)
        let saved = imported.activeSheet.charts
        guard saved.count == 1,
          saved[0].title == "Test",
          saved[0].anchorRow == 4,
          saved[0].anchorCol == 0
        else {
          return Result(name: "chart round-trip", passed: false, detail: "charts: \(saved)")
        }
        return Result(name: "chart round-trip", passed: true, detail: "ok")
      } catch {
        return Result(name: "chart round-trip", passed: false, detail: error.localizedDescription)
      }
    }

    private static func colorScaleRoundTrip() -> Result {
      let stops = [
        ColorScaleStop(
          type: .min, value: nil, color: CodableColor(red: 1, green: 0.8, blue: 0.8, alpha: 1)),
        ColorScaleStop(
          type: .max, value: nil, color: CodableColor(red: 0.8, green: 1, blue: 0.8, alpha: 1)),
      ]
      var sheet = Sheet(name: "Test")
      sheet.setCell(Cell(raw: "10"), at: CellAddress(row: 0, col: 0))
      sheet.setCell(Cell(raw: "90"), at: CellAddress(row: 1, col: 0))
      sheet.conditionalFormats = [
        ConditionalFormatRule(
          range: CellRange(start: .origin, end: CellAddress(row: 1, col: 0)),
          predicate: .colorScale(stops),
          style: ConditionalFormatStyle()
        )
      ]
      let wb = Workbook(sheets: [sheet])
      do {
        let data = try XLSXCodec.exportWorkbook(wb)
        let xml =
          XLSXCodec.zipEntryString(archiveData: data, entryPath: "xl/worksheets/sheet1.xml") ?? ""
        guard xml.contains("type=\"colorScale\"") else {
          return Result(
            name: "color scale export", passed: false, detail: "missing colorScale in XML")
        }
        let imported = try XLSXCodec.importWorkbook(from: data)
        guard let rule = imported.activeSheet.conditionalFormats.first,
          case .colorScale(let importedStops) = rule.predicate,
          importedStops.count == 2
        else {
          return Result(
            name: "color scale round-trip", passed: false,
            detail: "rules: \(imported.activeSheet.conditionalFormats)")
        }
        return Result(name: "color scale round-trip", passed: true, detail: "ok")
      } catch {
        return Result(
          name: "color scale round-trip", passed: false, detail: error.localizedDescription)
      }
    }

    private static func themeSchemeParse() -> Result {
      guard let path = fixturePath(.enterpriseThemed),
        let data = try? Data(contentsOf: URL(fileURLWithPath: path))
      else {
        return Result(name: "theme parse", passed: true, detail: "skipped (no fixture)")
      }
      // File may have been re-saved without a theme part (e.g. after Excel repair).
      guard XLSXCodec.zipEntryString(archiveData: data, entryPath: "xl/theme/theme1.xml") != nil
      else {
        return Result(name: "theme parse", passed: true, detail: "skipped (no theme part in file)")
      }
      let scheme = XLSXCodec.importThemeScheme(archiveData: data)
      guard scheme.colorsByName["accent1"] != nil else {
        return Result(
          name: "theme parse", passed: false,
          detail: "accent1 missing (\(scheme.colorsByName.keys.sorted()))")
      }
      let resolved = scheme.color(themeIndex: 4, tint: 0)
      guard resolved != nil else {
        return Result(name: "theme resolve", passed: false, detail: "theme index 4 unresolved")
      }
      return Result(name: "theme parse", passed: true, detail: "accent1 + theme[4] ok")
    }

    private static func mergeSelectionSnap() -> Result {
      var sheet = Sheet(name: "Test")
      sheet.mergedRanges = [
        CellRange(
          start: CellAddress(row: 0, col: 0),
          end: CellAddress(row: 0, col: 2)
        )
      ]
      let expanded = sheet.selectionExpandedForMerges(
        CellRange(start: CellAddress(row: 0, col: 1), end: CellAddress(row: 0, col: 1))
      )
      let n = expanded.normalized
      guard n.minCol == 0, n.maxCol == 2 else {
        return Result(
          name: "merge selection expand", passed: false, detail: "got cols \(n.minCol)-\(n.maxCol)")
      }
      guard sheet.isCoveredByMerge(CellAddress(row: 0, col: 1)) else {
        return Result(name: "merge covered cell", passed: false, detail: "B1 should be covered")
      }
      guard sheet.mergeAnchor(for: CellAddress(row: 0, col: 1)) == CellAddress(row: 0, col: 0)
      else {
        return Result(name: "merge anchor snap", passed: false, detail: "B1 anchor should be A1")
      }
      return Result(name: "merge selection expand", passed: true, detail: "ok")
    }

    // MARK: - Focused regression tests

    @MainActor
    private static func findScopePersistsAfterJump() -> Result {
      var sheet = Sheet(name: "Find")
      sheet.setCell(Cell(raw: "alpha"), at: CellAddress(row: 0, col: 0))
      sheet.setCell(Cell(raw: "alpha"), at: CellAddress(row: 1, col: 1))
      sheet.setCell(Cell(raw: "alpha"), at: CellAddress(row: 2, col: 2))
      let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
      vm.selectRange(from: .origin, to: CellAddress(row: 2, col: 2))
      vm.findScope = .selection
      vm.findQuery = "alpha"
      vm.showFindBar(replace: false)
      let initialCount = vm.findMatches.count
      guard initialCount == 3 else {
        return Result(
          name: "find scope capture", passed: false,
          detail: "expected 3 matches, got \(initialCount)")
      }
      guard let scope = vm.findScopeRange else {
        return Result(name: "find scope capture", passed: false, detail: "findScopeRange not set")
      }
      let sn = scope.normalized
      guard sn.minRow == 0, sn.maxRow == 2, sn.minCol == 0, sn.maxCol == 2 else {
        return Result(name: "find scope capture", passed: false, detail: "bad scope \(sn)")
      }
      // Jump shrinks live selection to one cell; captured scope must remain.
      vm.select(CellAddress(row: 1, col: 1))
      vm.refreshFindMatches()
      guard vm.findMatches.count == 3 else {
        return Result(
          name: "find scope after jump",
          passed: false,
          detail: "expected 3 matches after select shrink, got \(vm.findMatches.count)"
        )
      }
      return Result(name: "find scope after jump", passed: true, detail: "scope held 3 matches")
    }

    @MainActor
    private static func largeEmptyFormatApply() -> Result {
      let sheet = Sheet(name: "Format")
      let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
      // 100×26 = 2600 > large-apply threshold; previously only existing cells were formatted.
      let end = CellAddress(row: 99, col: Workbook.defaultColumnCount - 1)
      vm.selectRange(from: .origin, to: end)
      let fill = CodableColor(red: 1, green: 0, blue: 0, alpha: 1)
      vm.setFillColor(fill)
      let sampleEmpty = CellAddress(row: 50, col: 12)
      guard vm.activeSheet.cell(at: sampleEmpty).format?.fillColor == fill,
        vm.activeSheet.cell(at: end).format?.fillColor == fill,
        vm.activeSheet.cell(at: .origin).format?.fillColor == fill
      else {
        let mid = vm.activeSheet.cell(at: sampleEmpty).format?.fillColor
        let far = vm.activeSheet.cell(at: end).format?.fillColor
        let origin = vm.activeSheet.cell(at: .origin).format?.fillColor
        return Result(
          name: "large empty format",
          passed: false,
          detail:
            "missing fill mid=\(String(describing: mid)) end=\(String(describing: far)) origin=\(String(describing: origin))"
        )
      }
      return Result(name: "large empty format", passed: true, detail: "2600 cells filled")
    }

    private static func cfParseNumber() -> Result {
      let cases: [(String, Double?)] = [
        (" 1,234.5 ", 1234.5),
        ("$50", 50),
        ("25%", 0.25),
        ("  12% ", 0.12),
        ("", nil),
        ("abc", nil),
      ]
      for (input, expected) in cases {
        let parsed = ConditionalFormattingSheet.parseNumber(input)
        switch (parsed, expected) {
        case (nil, nil):
          continue
        case (let value?, let exp?):
          guard abs(value - exp) < 0.000_001 else {
            return Result(
              name: "CF parseNumber", passed: false, detail: "\(input) -> \(value), expected \(exp)"
            )
          }
        default:
          return Result(
            name: "CF parseNumber",
            passed: false,
            detail:
              "\(input) -> \(String(describing: parsed)), expected \(String(describing: expected))"
          )
        }
      }
      return Result(name: "CF parseNumber", passed: true, detail: "ok")
    }

    @MainActor
    /// Dragging a tab moves the sheet, keeps the active sheet, leaves formulas pointing at
    /// sheets by name, and undoes back to the old order.
    private static func sheetTabMove() -> Result {
      let name = "sheet tab move"
      let a1 = CellAddress(row: 0, col: 0)
      var data = Sheet(name: "Data")
      data.setCell(Cell(raw: "7"), at: a1)
      var summary = Sheet(name: "Summary")
      summary.setCell(Cell(raw: "=Data!A1*2"), at: a1)
      let vm = SpreadsheetViewModel(
        workbook: Workbook(sheets: [data, Sheet(name: "Notes"), summary]))
      let undo = UndoManager()
      undo.groupsByEvent = false
      vm.undoManager = undo
      vm.selectSheet(at: 2)
      undo.beginUndoGrouping()
      vm.moveSheet(from: 2, to: 0)
      undo.endUndoGrouping()
      let order = vm.workbook.sheets.map(\.name)
      guard order == ["Summary", "Data", "Notes"], vm.activeSheet.name == "Summary" else {
        return Result(
          name: name, passed: false, detail: "order \(order), active \(vm.activeSheet.name)")
      }
      guard vm.displayString(at: a1) == "14" else {
        return Result(name: name, passed: false, detail: "formula gave \(vm.displayString(at: a1))")
      }
      undo.undo()
      let restored = vm.workbook.sheets.map(\.name)
      guard restored == ["Data", "Notes", "Summary"], vm.activeSheet.name == "Summary" else {
        return Result(name: name, passed: false, detail: "undo left \(restored)")
      }
      return Result(name: name, passed: true, detail: "move, formula by name, undo")
    }

    /// ⌘-arrow lands where Excel's Ctrl-arrow does: the end of a filled run, the next filled
    /// cell across a gap, and the end of the data rather than the sheet's last row.
    private static func commandArrowJumps() -> Result {
      let name = "command-arrow jumps"
      var sheet = Sheet(name: "Jump")
      // Column A: rows 0-3 filled, 4-6 empty, 7-9 filled. Nothing below row 9.
      for row in [0, 1, 2, 3, 7, 8, 9] {
        sheet.setCell(Cell(raw: "x"), at: CellAddress(row: row, col: 0))
      }
      sheet.setCell(Cell(raw: "x"), at: CellAddress(row: 0, col: 4))
      let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
      var landed: [String] = []
      func jump(_ rowStep: Int, _ colStep: Int) {
        vm.jumpSelection(rowStep: rowStep, colStep: colStep)
        landed.append(vm.selectionAnchor.a1)
      }
      vm.select(.origin)
      jump(1, 0)  // end of the first run: A4
      jump(1, 0)  // across the gap: A8
      jump(1, 0)  // end of the second run: A10
      jump(1, 0)  // nothing below: stays at the end of the data, A10
      jump(-1, 0)  // back up the run: A8
      vm.select(.origin)
      jump(0, 1)  // across the empty columns to E1
      vm.select(.origin)
      vm.jumpSelection(rowStep: 1, colStep: 0, extending: true)
      let extended = vm.selectionRange.normalized
      let expected = ["A4", "A8", "A10", "A10", "A8", "E1"]
      guard landed == expected, extended.maxRow == 3, extended.minRow == 0 else {
        return Result(
          name: name, passed: false,
          detail: "landed \(landed), shift reached row \(extended.maxRow)")
      }
      return Result(name: name, passed: true, detail: "runs, gaps, data end, shift-extend")
    }

    /// The filter popover's model: undoable criteria, row counts, the gap marker, and a sort
    /// that a second click undoes, even after a sort the other way.
    private static func filterPopoverModel() -> Result {
      let name = "filter popover model"
      var sheet = Sheet(name: "Filter")
      sheet.setCell(Cell(raw: "Stage"), at: CellAddress(row: 0, col: 0))
      sheet.setCell(Cell(raw: "Rank"), at: CellAddress(row: 0, col: 1))
      for (offset, stage) in ["b", "a", "c", "a", "b"].enumerated() {
        sheet.setCell(Cell(raw: stage), at: CellAddress(row: offset + 1, col: 0))
        sheet.setCell(Cell(raw: "\(offset + 1)"), at: CellAddress(row: offset + 1, col: 1))
      }
      let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
      let undo = UndoManager()
      undo.groupsByEvent = false
      vm.undoManager = undo
      func step(_ body: () -> Void) {
        undo.beginUndoGrouping()
        body()
        undo.endUndoGrouping()
      }
      func column(_ col: Int) -> [String] {
        (1...5).map { vm.activeSheet.cell(at: CellAddress(row: $0, col: col)).raw }
      }

      vm.selectRange(from: .origin, to: CellAddress(row: 5, col: 1))
      step { vm.createFilter() }
      step { vm.setFilterValues(column: 0, values: ["a"]) }
      guard let counts = vm.filterRowCounts, counts.shown == 2, counts.total == 5 else {
        return Result(
          name: name, passed: false,
          detail: "row counts \(String(describing: vm.filterRowCounts))")
      }
      // Rows 2 and 4 hold "a"; rows 1, 3 and 5 are hidden.
      guard vm.isShownByActiveFilter(2), vm.isShownByActiveFilter(4),
        !vm.isShownByActiveFilter(1), !vm.isShownByActiveFilter(0)
      else {
        return Result(name: name, passed: false, detail: "filtered row marker on the wrong rows")
      }
      undo.undo()
      guard vm.filterState != nil, vm.filterRowCounts == nil else {
        return Result(name: name, passed: false, detail: "undo did not restore the criteria")
      }
      let listed = vm.filterValueCounts(column: 0).map { "\($0.value)\($0.count)" }
      guard listed == ["a2", "b2", "c1"] else {
        return Result(name: name, passed: false, detail: "value counts \(listed)")
      }

      step { vm.filterSort(column: 0, ascending: true) }
      guard column(0) == ["a", "a", "b", "b", "c"], vm.isFilterSorted(column: 0, ascending: true)
      else {
        return Result(name: name, passed: false, detail: "A to Z gave \(column(0))")
      }
      step { vm.filterSort(column: 0, ascending: true) }
      guard column(1) == ["1", "2", "3", "4", "5"], !vm.isFilterSorted(column: 0, ascending: true)
      else {
        return Result(name: name, passed: false, detail: "second click left \(column(1))")
      }

      step { vm.filterSort(column: 0, ascending: true) }
      step { vm.filterSort(column: 0, ascending: false) }
      step { vm.filterSort(column: 0, ascending: false) }
      guard column(1) == ["1", "2", "3", "4", "5"] else {
        return Result(name: name, passed: false, detail: "unsort after two sorts left \(column(1))")
      }

      // Undo puts the rows back from the stored order; redo sorts them again.
      step { vm.filterSort(column: 0, ascending: true) }
      undo.undo()
      guard column(1) == ["1", "2", "3", "4", "5"] else {
        return Result(name: name, passed: false, detail: "undo of a sort left \(column(1))")
      }
      undo.redo()
      guard column(0) == ["a", "a", "b", "b", "c"] else {
        return Result(name: name, passed: false, detail: "redo of a sort left \(column(0))")
      }
      undo.undo()

      // Copy and Delete leave out rows the filter hides, as in Excel.
      step { vm.setFilterValues(column: 0, values: ["a"]) }
      let stageColumn = CellRange(
        start: CellAddress(row: 1, col: 0), end: CellAddress(row: 5, col: 0))
      let copied = SpreadsheetClipboard.copyText(
        from: vm.activeSheet, range: stageColumn, skippingRow: vm.isRowHiddenByFilter)
      guard copied == "a\na" else {
        return Result(name: name, passed: false, detail: "filtered copy gave \(copied)")
      }
      vm.selectRange(from: CellAddress(row: 1, col: 0), to: CellAddress(row: 5, col: 1))
      step { vm.clearSelection() }
      guard column(0) == ["b", "", "c", "", "b"] else {
        return Result(name: name, passed: false, detail: "filtered delete left \(column(0))")
      }
      return Result(
        name: name, passed: true,
        detail: "undo, counts, gap, sort, unsort, filtered copy and delete")
    }

    private static func sortRemapsMerge() -> Result {
      var sheet = Sheet(name: "Sort")
      // Header + three data rows; merge spans two data rows in col A.
      sheet.setCell(Cell(raw: "Name"), at: CellAddress(row: 0, col: 0))
      sheet.setCell(Cell(raw: "Val"), at: CellAddress(row: 0, col: 1))
      sheet.setCell(Cell(raw: "C"), at: CellAddress(row: 1, col: 0))
      sheet.setCell(Cell(raw: "3"), at: CellAddress(row: 1, col: 1))
      sheet.setCell(Cell(raw: "A"), at: CellAddress(row: 2, col: 0))
      sheet.setCell(Cell(raw: "1"), at: CellAddress(row: 2, col: 1))
      sheet.setCell(Cell(raw: "B"), at: CellAddress(row: 3, col: 0))
      sheet.setCell(Cell(raw: "2"), at: CellAddress(row: 3, col: 1))
      // Single-row merge in data (safe rectangular remap).
      sheet.mergedRanges = [
        CellRange(start: CellAddress(row: 2, col: 0), end: CellAddress(row: 2, col: 1))
      ]
      sheet.conditionalFormats = [
        ConditionalFormatRule(
          range: CellRange(start: CellAddress(row: 1, col: 1), end: CellAddress(row: 3, col: 1)),
          predicate: .greaterThan(0),
          style: .redFill
        )
      ]
      sheet.charts = [
        SheetChart(
          kind: .bar,
          title: "Vals",
          dataRange: CellRange(
            start: CellAddress(row: 1, col: 1), end: CellAddress(row: 3, col: 1)),
          anchorRow: 5,
          anchorCol: 3
        )
      ]
      let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
      vm.selectRange(from: .origin, to: CellAddress(row: 3, col: 1))
      vm.sortRange(column: 1, direction: .ascending, hasHeader: true)
      // Ascending by Val: row2(A/1) → first data, row3(B/2) → second, row1(C/3) → third.
      // Merge was on old row 2 → new row 1 (firstDataRow=1).
      let merges = vm.activeSheet.mergedRanges
      guard merges.count == 1 else {
        return Result(
          name: "sort remap merge", passed: false, detail: "merge count \(merges.count)")
      }
      let mn = merges[0].normalized
      guard mn.minRow == 1, mn.maxRow == 1, mn.minCol == 0, mn.maxCol == 1 else {
        return Result(name: "sort remap merge", passed: false, detail: "merge at \(mn)")
      }
      let cf = vm.activeSheet.conditionalFormats.first?.range.normalized
      guard let cf, cf.minRow == 1, cf.maxRow == 3, cf.minCol == 1, cf.maxCol == 1 else {
        return Result(
          name: "sort remap CF", passed: false, detail: "CF range \(String(describing: cf))")
      }
      let chartRange = vm.activeSheet.charts.first?.dataRange.normalized
      guard let chartRange, chartRange.minRow == 1, chartRange.maxRow == 3 else {
        return Result(
          name: "sort remap chart", passed: false, detail: "chart \(String(describing: chartRange))"
        )
      }
      return Result(name: "sort remap merge/CF/chart", passed: true, detail: "rows remapped")
    }

    /// A sort that pushes a SUM off the top of the sheet, then Undo: the formulas come back
    /// as they were. Quick sort leaves the total row under the table.
    @MainActor
    private static func sortUndoKeepsFormulas() -> Result {
      let name = "sort undo keeps formulas"
      var sheet = Sheet(name: "Pipeline")
      sheet.setCell(Cell(raw: "Account"), at: CellAddress(row: 0, col: 0))
      sheet.setCell(Cell(raw: "Close"), at: CellAddress(row: 0, col: 1))
      let closes = ["0.9", "0.8", "0.7", "0.6", "0.5", "0.4", "0.3", "0.2"]
      for (i, close) in closes.enumerated() {
        sheet.setCell(Cell(raw: "Deal \(i)"), at: CellAddress(row: i + 1, col: 0))
        sheet.setCell(Cell(raw: close), at: CellAddress(row: i + 1, col: 1))
      }
      let total = CellAddress(row: 9, col: 1)
      sheet.setCell(Cell(raw: "Total"), at: CellAddress(row: 9, col: 0))
      sheet.setCell(Cell(raw: "=SUM(B2:B9)"), at: total)
      let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
      let undo = UndoManager()
      undo.groupsByEvent = false
      vm.undoManager = undo

      // Quick sort from a cell in the table leaves the total row where it is.
      vm.select(CellAddress(row: 3, col: 1))
      undo.beginUndoGrouping()
      vm.quickSort(ascending: true)
      undo.endUndoGrouping()
      guard vm.activeSheet.cell(at: total).raw == "=SUM(B2:B9)",
        vm.activeSheet.cell(at: CellAddress(row: 1, col: 1)).raw == "0.2"
      else {
        return Result(
          name: name, passed: false,
          detail: "quick sort moved the total: \(vm.activeSheet.cell(at: total).raw)")
      }
      undo.undo()

      // Sorting the whole block moves the total to the top, off the sheet; Undo restores it.
      undo.beginUndoGrouping()
      vm.sortRange(
        column: 1, direction: .ascending, hasHeader: true,
        range: CellRange(start: .origin, end: total))
      undo.endUndoGrouping()
      undo.undo()
      let back = vm.activeSheet.cell(at: total).raw
      guard back == "=SUM(B2:B9)",
        vm.activeSheet.cell(at: CellAddress(row: 1, col: 1)).raw == "0.9"
      else {
        return Result(name: name, passed: false, detail: "after undo the total reads \(back)")
      }
      undo.redo()
      undo.undo()
      guard vm.activeSheet.cell(at: total).raw == "=SUM(B2:B9)" else {
        return Result(name: name, passed: false, detail: "redo then undo lost the total")
      }
      return Result(name: name, passed: true, detail: "total row kept and restored")
    }

    /// Text to Columns splits "Last, First, Age" into three columns, keeps a formula row, and
    /// one Undo puts the column and the cells beside it back.
    @MainActor
    private static func textToColumnsSplitsAndUndoes() -> Result {
      let name = "text to columns"
      var sheet = Sheet(name: "Names")
      sheet.setCell(Cell(raw: "Lovelace,Ada,36"), at: CellAddress(row: 0, col: 0))
      sheet.setCell(Cell(raw: "\"Hopper, Jr\",Grace,85"), at: CellAddress(row: 1, col: 0))
      sheet.setCell(Cell(raw: "=1+1"), at: CellAddress(row: 2, col: 0))
      sheet.setCell(Cell(raw: "keep"), at: CellAddress(row: 2, col: 1))
      sheet.setCell(Cell(raw: "old"), at: CellAddress(row: 0, col: 2))
      let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
      let undo = UndoManager()
      undo.groupsByEvent = false
      vm.undoManager = undo
      vm.select(.origin)
      guard let source = vm.textToColumnsSource(), source.normalized.maxRow == 2 else {
        return Result(name: name, passed: false, detail: "source range not found")
      }
      undo.beginUndoGrouping()
      vm.applyTextToColumns(source, options: .init(delimiters: [","]))
      undo.endUndoGrouping()
      func raw(_ r: Int, _ c: Int) -> String {
        vm.activeSheet.cell(at: CellAddress(row: r, col: c)).raw
      }
      let got = [raw(0, 0), raw(0, 1), raw(0, 2), raw(1, 0), raw(1, 2), raw(2, 0), raw(2, 1)]
      guard got == ["Lovelace", "Ada", "36", "Hopper, Jr", "85", "=1+1", "keep"] else {
        return Result(name: name, passed: false, detail: "split \(got)")
      }
      undo.undo()
      guard raw(0, 0) == "Lovelace,Ada,36", raw(0, 1).isEmpty, raw(0, 2) == "old",
        raw(2, 1) == "keep"
      else {
        return Result(name: name, passed: false, detail: "undo left \(raw(0, 0)) \(raw(0, 2))")
      }
      // Fixed width: lined-up text splits at the suggested breaks.
      var fixed = Sheet(name: "Fixed")
      let lines = ["Alex   Smith   42", "Bo     Jones   7"]
      for (row, line) in lines.enumerated() {
        fixed.setCell(Cell(raw: line), at: CellAddress(row: row, col: 0))
      }
      let fixedModel = SpreadsheetViewModel(workbook: Workbook(sheets: [fixed]))
      fixedModel.undoManager = UndoManager()
      let breaks = TextSplitter.suggestedBreaks(lines)
      fixedModel.applyTextToColumns(
        CellRange(start: .origin, end: CellAddress(row: 1, col: 0)),
        options: .fixedWidth(breaks))
      let pieces = (0..<3).map {
        fixedModel.activeSheet.cell(at: CellAddress(row: 1, col: $0)).raw
      }
      guard breaks == [7, 15], pieces == ["Bo", "Jones", "7"] else {
        return Result(name: name, passed: false, detail: "fixed width \(breaks) \(pieces)")
      }
      return Result(
        name: name, passed: true, detail: "split, formula row kept, undone, fixed width")
    }

    /// Rows 2-5 grouped with 3-4 inside: fold the inner group, fold and unfold the outer one,
    /// and the inner stays folded. The levels survive a save. Ungroup shows the rows again.
    @MainActor
    private static func rowGroupsFoldAndSave() -> Result {
      let name = "row groups fold and save"
      var sheet = Sheet(name: "Outline")
      for row in 0..<8 { sheet.setCell(Cell(raw: "\(row + 1)"), at: CellAddress(row: row, col: 0)) }
      let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
      let undo = UndoManager()
      undo.groupsByEvent = false
      vm.undoManager = undo
      func step(_ body: () -> Void) {
        undo.beginUndoGrouping()
        body()
        undo.endUndoGrouping()
      }
      vm.selectRange(from: CellAddress(row: 1, col: 0), to: CellAddress(row: 4, col: 0))
      step { vm.groupSelection(.rows) }
      vm.selectRange(from: CellAddress(row: 2, col: 0), to: CellAddress(row: 3, col: 0))
      step { vm.groupSelection(.rows) }
      let groups = vm.outlineGroups(.rows)
      guard
        groups == [
          .init(start: 1, end: 4, level: 1), .init(start: 2, end: 3, level: 2),
        ]
      else { return Result(name: name, passed: false, detail: "groups \(groups)") }
      step { vm.toggleOutlineGroup(groups[1], .rows) }
      step { vm.toggleOutlineGroup(groups[0], .rows) }
      guard vm.activeSheet.fileExtras.hiddenRows == [1, 2, 3, 4] else {
        return Result(
          name: name, passed: false,
          detail: "outer fold hid \(vm.activeSheet.fileExtras.hiddenRows.sorted())")
      }
      step { vm.toggleOutlineGroup(groups[0], .rows) }
      guard vm.activeSheet.fileExtras.hiddenRows == [2, 3] else {
        return Result(
          name: name, passed: false,
          detail: "unfold left \(vm.activeSheet.fileExtras.hiddenRows.sorted()) hidden")
      }
      do {
        let data = try XLSXCodec.exportWorkbook(vm.workbook)
        let back = try XLSXCodec.importWorkbook(from: data).activeSheet.fileExtras
        guard back.rowOutlineLevels == [1: 1, 2: 2, 3: 2, 4: 1], back.hiddenRows == [2, 3] else {
          return Result(name: name, passed: false, detail: "saved levels \(back.rowOutlineLevels)")
        }
      } catch {
        return Result(name: name, passed: false, detail: error.localizedDescription)
      }
      vm.selectRange(from: CellAddress(row: 1, col: 0), to: CellAddress(row: 4, col: 0))
      step { vm.ungroupSelection(.rows) }
      step { vm.ungroupSelection(.rows) }
      guard vm.activeSheet.fileExtras.rowOutlineLevels.isEmpty,
        vm.activeSheet.fileExtras.hiddenRows.isEmpty
      else {
        return Result(name: name, passed: false, detail: "ungroup left levels or hidden rows")
      }
      undo.undo()
      guard vm.activeSheet.fileExtras.rowOutlineLevels == [2: 1, 3: 1] else {
        return Result(
          name: name, passed: false,
          detail: "undo ungroup gave \(vm.activeSheet.fileExtras.rowOutlineLevels)")
      }
      // Level buttons: 1 folds every group, the last shows everything.
      step { vm.showOutlineLevelButton(1, .rows) }
      let foldedAtOne = vm.activeSheet.fileExtras.hiddenRows
      step { vm.showOutlineLevelButton(2, .rows) }
      guard vm.outlineDepth(.rows) == 1, foldedAtOne == [2, 3],
        vm.activeSheet.fileExtras.hiddenRows.isEmpty
      else {
        return Result(
          name: name, passed: false,
          detail: "level 1 hid \(foldedAtOne), level 2 left \(vm.activeSheet.fileExtras.hiddenRows)"
        )
      }
      return Result(
        name: name, passed: true, detail: "nested fold kept, saved, ungrouped, levels shown")
    }

    /// B1 unlocked, sheet protected with a password: A1 and formatting are refused, B1 takes
    /// typing, the wrong password fails, and protection plus the unlocked cell survive a save.
    @MainActor
    private static func sheetProtectionGuardsLockedCells() -> Result {
      let name = "sheet protection"
      var sheet = Sheet(name: "Inputs")
      sheet.setCell(Cell(raw: "fixed"), at: CellAddress(row: 0, col: 0))
      let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
      vm.undoManager = UndoManager()
      let a1 = CellAddress(row: 0, col: 0)
      let b1 = CellAddress(row: 0, col: 1)
      vm.select(b1)
      vm.setSelectionLocked(false)
      vm.protectSheet(password: "secret")
      guard vm.isSheetProtected, vm.sheetProtectionHasPassword else {
        return Result(name: name, passed: false, detail: "protection not on")
      }
      vm.setCellValue("changed", at: a1)
      guard vm.activeSheet.cell(at: a1).raw == "fixed", vm.protectionNotice != nil else {
        return Result(name: name, passed: false, detail: "locked A1 changed")
      }
      vm.protectionNotice = nil
      vm.setCellValue("typed", at: b1)
      guard vm.activeSheet.cell(at: b1).raw == "typed", vm.protectionNotice == nil else {
        return Result(name: name, passed: false, detail: "unlocked B1 refused")
      }
      // Typing on a locked cell starts no edit; a refused commit drops the text, same sheet.
      vm.protectionNotice = nil
      vm.select(a1)
      let sheetBefore = vm.workbook.activeSheetIndex
      guard !vm.beginTyping("x"), !vm.isEditing, vm.protectionNotice != nil else {
        return Result(name: name, passed: false, detail: "typing on locked A1 began an edit")
      }
      vm.protectionNotice = nil
      vm.editText = "x"
      vm.isEditing = true
      vm.commitEdit()
      guard !vm.isEditing, vm.editText == "fixed", vm.activeSheet.cell(at: a1).raw == "fixed",
        vm.workbook.activeSheetIndex == sheetBefore, vm.protectionNotice != nil
      else {
        return Result(name: name, passed: false, detail: "refused commit kept text \(vm.editText)")
      }
      vm.protectionNotice = nil
      vm.select(b1)
      guard vm.beginTyping("y"), vm.isEditing else {
        return Result(name: name, passed: false, detail: "typing on unlocked B1 refused")
      }
      vm.cancelEdit()
      vm.select(a1)
      vm.toggleBold()
      vm.insertRowsAbove()
      guard vm.activeSheet.cell(at: a1).format?.bold != true,
        vm.activeSheet.cell(at: a1).raw == "fixed"
      else {
        return Result(name: name, passed: false, detail: "format or insert went through")
      }
      do {
        let back = try XLSXCodec.importWorkbook(from: XLSXCodec.exportWorkbook(vm.workbook))
          .activeSheet
        guard SheetProtection.isOn(back.fileExtras.protectionXML),
          SheetProtection.verify("secret", against: back.fileExtras.protectionXML),
          back.cell(at: b1).format?.locked == false, back.cell(at: a1).format?.locked != false
        else {
          return Result(name: name, passed: false, detail: "protection lost in save")
        }
      } catch {
        return Result(name: name, passed: false, detail: error.localizedDescription)
      }
      guard !vm.unprotectSheet(password: "nope"), vm.unprotectSheet(password: "secret"),
        !vm.isSheetProtected
      else {
        return Result(name: name, passed: false, detail: "password check wrong")
      }
      vm.setCellValue("changed", at: a1)
      guard vm.activeSheet.cell(at: a1).raw == "changed" else {
        return Result(name: name, passed: false, detail: "A1 still refused after unprotect")
      }
      // Allowed actions go through on a protected sheet; the rest stay refused.
      vm.protectSheet(password: nil, allowing: [.formatCells, .insertRows])
      vm.select(a1)
      vm.toggleBold()
      let rowsBefore = vm.activeSheet.cell(at: a1).raw
      vm.insertRowsAbove()
      let moved = vm.activeSheet.cell(at: CellAddress(row: 1, col: 0)).raw == rowsBefore
      vm.protectionNotice = nil
      vm.select(CellAddress(row: 1, col: 0))
      vm.hideSelected(.rows)
      guard vm.activeSheet.cell(at: CellAddress(row: 1, col: 0)).format?.bold == true, moved,
        vm.activeSheet.fileExtras.hiddenRows.isEmpty, vm.protectionNotice != nil
      else {
        return Result(
          name: name, passed: false,
          detail:
            "allowed: bold \(vm.activeSheet.cell(at: CellAddress(row: 1, col: 0)).format?.bold == true) insert \(moved); hide refused \(vm.protectionNotice != nil)"
        )
      }
      return Result(
        name: name, passed: true, detail: "locked refused, unlocked typed, saved, allow flags kept")
    }

    /// Typing in a cell, then scrolling before pressing Return, left other cells in that
    /// column blank until the edit ended (reported on 1.3, Nov 10).
    /// Print setup can leave out the column letters and row numbers (Sam, Nov 13).
    @MainActor
    private static func printWithoutHeadings() -> Result {
      let name = "print without headings"
      var sheet = Sheet(name: "Report")
      var red = CellFormat()
      red.fillColor = CodableColor(red: 1, green: 0.23, blue: 0.25, alpha: 1)
      for row in 0..<60 {
        for col in 0..<3 {
          var cell = Cell(raw: "r\(row) c\(col)")
          cell.format = red
          sheet.setCell(cell, at: CellAddress(row: row, col: col))
        }
      }
      let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
      var options = SpreadsheetPrintOptions.default(for: vm)
      options.scale = .normal
      guard options.showHeadings, let page = options.pages(for: vm).first else {
        return Result(name: name, passed: false, detail: "headings should start on")
      }
      let with = SpreadsheetPrintNSView(sheet: page.sheet, range: page.range)
      options.showHeadings = false
      let without = SpreadsheetPrintNSView(
        sheet: page.sheet, range: page.range, showHeadings: options.showHeadings)
      let widthSaved = with.bounds.width - without.bounds.width
      let heightSaved = with.bounds.height - without.bounds.height
      guard widthSaved == SpreadsheetPrintNSView.headerWidth,
        heightSaved == SpreadsheetPrintNSView.headerHeight, without.columnXs.first == 0,
        without.rowYs.first == 0
      else {
        return Result(
          name: name, passed: false, detail: "size saved \(widthSaved) x \(heightSaved)")
      }
      // Pages reserve no heading strip, so more rows fit on each.
      let pagesWith = SpreadsheetPrintLayout(gridView: with, sheet: page.sheet, options: options)
      let pagesWithout = SpreadsheetPrintLayout(
        gridView: without, sheet: page.sheet, options: options)
      guard pagesWithout.pages.allSatisfy({ $0.yBands.first?.length == 0 }),
        pagesWithout.pages.allSatisfy({ $0.xBands.first?.length == 0 }),
        (pagesWithout.pages.first?.rows.count ?? 0) >= (pagesWith.pages.first?.rows.count ?? 0)
      else {
        return Result(name: name, passed: false, detail: "pages still keep a heading strip")
      }
      // The top-left corner shows the first cell's fill, not the gray heading corner.
      guard let drawn = without.bitmapImageRepForCachingDisplay(in: without.bounds) else {
        return Result(name: name, passed: false, detail: "no drawing")
      }
      without.cacheDisplay(in: without.bounds, to: drawn)
      let scale = CGFloat(drawn.pixelsWide) / without.bounds.width
      let corner = drawn.colorAt(x: Int(10 * scale), y: Int(8 * scale))?.usingColorSpace(.deviceRGB)
      guard let corner, corner.redComponent > 0.8, corner.greenComponent < 0.45 else {
        return Result(
          name: name, passed: false,
          detail: "top-left is not the cell: \(String(describing: corner))")
      }
      return Result(
        name: name, passed: true,
        detail: "no letters or numbers; \(pagesWithout.pages.first?.rows.count ?? 0) rows on page 1"
      )
    }

    /// Coloring filtered rows (Sam, 1.3) also colored the rows the filter hid.
    @MainActor
    private static func fillSkipsFilteredRows() -> Result {
      let name = "fill skips filtered rows"
      var sheet = Sheet(name: "Leads")
      sheet.setCell(Cell(raw: "Status"), at: .origin)
      for (offset, status) in ["close", "open", "close", "open", "close"].enumerated() {
        sheet.setCell(Cell(raw: status), at: CellAddress(row: offset + 1, col: 0))
        sheet.setCell(Cell(raw: "note \(offset + 1)"), at: CellAddress(row: offset + 1, col: 1))
      }
      let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
      let undo = UndoManager()
      undo.groupsByEvent = false
      vm.undoManager = undo
      func step(_ body: () -> Void) {
        undo.beginUndoGrouping()
        body()
        undo.endUndoGrouping()
      }
      let red = CodableColor(red: 1, green: 0.23, blue: 0.25, alpha: 1)
      func filled() -> [Int] {
        (1...5).filter { row in
          (0...1).allSatisfy {
            vm.activeSheet.cell(at: CellAddress(row: row, col: $0)).format?.fillColor == red
          }
        }
      }
      vm.selectRange(from: .origin, to: CellAddress(row: 5, col: 1))
      step { vm.createFilter() }
      step { vm.setFilterValues(column: 0, values: ["close"]) }
      // Select the shown rows' cells, as dragging over them does, and fill.
      vm.selectRange(from: CellAddress(row: 1, col: 0), to: CellAddress(row: 5, col: 1))
      step { vm.setFillColor(red) }
      guard filled() == [1, 3, 5] else {
        return Result(name: name, passed: false, detail: "filled rows \(filled()), want [1, 3, 5]")
      }
      step { vm.setFilterValues(column: 0, values: nil) }
      guard filled() == [1, 3, 5] else {
        return Result(name: name, passed: false, detail: "after showing all: \(filled())")
      }
      undo.undo()
      undo.undo()
      guard filled().isEmpty else {
        return Result(name: name, passed: false, detail: "undo left \(filled())")
      }
      return Result(name: name, passed: true, detail: "only the shown rows take the fill")
    }

    /// Typing over a cell's value (Sam, 1.3) showed the typed letter over another word: macOS's predicted end of the
    /// word, drawn off the typed letters. Predictions are off, and nothing under the clear editor
    /// (the frame, or the scroll pictures) still shows the old value.
    @MainActor
    private static func typingOverAValueHidesTheOldText() -> Result {
      let name = "typing over a value hides the old text"
      var sheet = Sheet(name: "Activity")
      var red = CellFormat()
      red.fillColor = CodableColor(red: 1, green: 0.23, blue: 0.25, alpha: 1)
      for row in 0..<60 {
        // Only the cell typed over has text, so no other text can be mistaken for it.
        var cell = Cell(raw: row == 12 ? "Placeholder Name" : "")
        cell.format = red
        sheet.setCell(cell, at: CellAddress(row: row, col: 1))
      }
      let frame = NSRect(x: 0, y: 0, width: 820, height: 520)
      let grid = SpreadsheetGridNSView(frame: frame)
      let window = NSWindow(
        contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.contentView = grid
      window.setFrameOrigin(NSPoint(x: -4000, y: -4000))
      window.orderFrontRegardless()
      defer {
        window.orderOut(nil)
        window.close()
      }
      let viewModel = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
      grid.viewModel = viewModel
      grid.layoutSubtreeIfNeeded()
      grid.display()
      RunLoop.current.run(until: Date().addingTimeInterval(0.25))
      let target = CellAddress(row: 12, col: 1)
      viewModel.selection = target
      grid.display()
      // As in Sam's screenshot: a scroll first, so the scroll pictures of the cells are showing.
      let deadline = Date().addingTimeInterval(10)
      while !grid.testingViewportTileCacheReady(), Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
      }
      grid.testingApplyScroll(dx: 0, dy: 2)
      grid.testingFinishScrollTileFills()
      RunLoop.current.run(until: Date().addingTimeInterval(0.1))
      let picturesBeforeTyping = grid.testingScrollTilesPresented
      guard viewModel.beginTyping("S") else {
        return Result(name: name, passed: false, detail: "typing refused")
      }
      grid.showEditor(selectAll: false)
      window.displayIfNeeded()
      RunLoop.current.run(until: Date().addingTimeInterval(0.15))
      window.displayIfNeeded()
      // macOS's predicted end of the word drew over the typed letters (Sam's 1.3 report).
      guard let typing = window.firstResponder as? NSTextView else {
        return Result(name: name, passed: false, detail: "no text view while typing")
      }
      guard typing.inlinePredictionType == .no, !typing.isAutomaticTextCompletionEnabled else {
        return Result(name: name, passed: false, detail: "word predictions are on in the cell")
      }
      // The pictures hold the old value; the editor is clear. They must be gone once typing starts.
      if grid.testingScrollTilesPresented || grid.testingScrollSurfacesPresented {
        return Result(
          name: name, passed: false,
          detail: "scroll pictures with the old value still show under the editor")
      }
      guard let image = grid.testingFrameImage() else {
        return Result(name: name, passed: false, detail: "no frame")
      }
      // The cell's right part, past the typed "S", must be its plain fill in the grid's frame.
      let rect = grid.rectForCell(row: target.row, col: target.col)
      let scale = CGFloat(image.width) / grid.bounds.width
      let rep = NSBitmapImageRep(cgImage: image)
      func textPixels(flippedY: Bool) -> (text: Int, fill: Int) {
        var text = 0
        var fill = 0
        let x0 = Int((rect.minX + 30) * scale)
        let x1 = Int((rect.maxX - 4) * scale)
        let y0 = Int((rect.minY + 4) * scale)
        let y1 = Int((rect.maxY - 4) * scale)
        guard x1 > x0, y1 > y0 else { return (0, 0) }
        for y in stride(from: y0, to: y1, by: 1) {
          let py = flippedY ? image.height - 1 - y : y
          for x in stride(from: x0, to: x1, by: 2) {
            guard let c = rep.colorAt(x: x, y: py)?.usingColorSpace(.deviceRGB) else { continue }
            if c.redComponent > 0.8, c.greenComponent < 0.45 { fill += 1 } else { text += 1 }
          }
        }
        return (text, fill)
      }
      // Only the cell typed over has text, so either way up, text over red is the old value.
      let readings = [textPixels(flippedY: false), textPixels(flippedY: true)]
        .filter { $0.fill > 0 }
      let found = (text: readings.map(\.text).max() ?? 0, fill: readings.map(\.fill).max() ?? 0)
      guard found.fill > 0 else {
        return Result(name: name, passed: false, detail: "cell fill not found in the frame")
      }
      guard found.text == 0 else {
        return Result(
          name: name, passed: false,
          detail: "old text still drawn under the editor: \(found.text) text pixels")
      }
      return Result(
        name: name, passed: true,
        detail:
          "only the fill under the editor (pictures showing before typing: \(picturesBeforeTyping))"
      )
    }

    @MainActor
    private static func scrollWhileEditingKeepsColumnText() -> Result {
      let name = "scroll while editing keeps column text"
      var sheet = Sheet(name: "Activity")
      for row in 0..<120 {
        sheet.setCell(Cell(raw: "Name \(row + 1)"), at: CellAddress(row: row, col: 0))
        if row % 3 != 1 {
          sheet.setCell(Cell(raw: "note \(row + 1)"), at: CellAddress(row: row, col: 3))
        }
      }
      let frame = NSRect(x: 0, y: 0, width: 820, height: 520)
      let grid = SpreadsheetGridNSView(frame: frame)
      let window = NSWindow(
        contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.contentView = grid
      window.setFrameOrigin(NSPoint(x: -4000, y: -4000))
      window.orderFrontRegardless()
      defer {
        window.orderOut(nil)
        window.close()
      }
      let viewModel = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
      grid.viewModel = viewModel
      grid.layoutSubtreeIfNeeded()
      grid.display()
      RunLoop.current.run(until: Date().addingTimeInterval(0.25))
      viewModel.selection = CellAddress(row: 10, col: 3)
      viewModel.beginEditing()
      grid.showEditor(selectAll: true)
      viewModel.editText = "old lead"
      grid.display()
      var missing: [String] = []
      for tick in 1...6 {
        grid.testingPaintedTexts = []
        grid.testingApplyScroll(dx: 0, dy: 23)
        grid.display()
        let painted = grid.testingPaintedTexts ?? []
        grid.testingPaintedTexts = nil
        // Every note on screen apart from the cell being edited must be painted.
        let top = grid.rowAtContent(y: grid.bounds.minY + 60)
        let bottom = grid.rowAtContent(y: grid.bounds.maxY - 30)
        for row in top...bottom where row % 3 != 1 && row != 10 {
          let note = "note \(row + 1)"
          if !painted.contains(note) { missing.append("tick \(tick) \(note)") }
        }
        if !missing.isEmpty { break }
      }
      grid.hideEditor(commit: false)
      guard missing.isEmpty else {
        return Result(name: name, passed: false, detail: "blank: \(missing.prefix(6))")
      }
      return Result(name: name, passed: true, detail: "column text painted on every scroll tick")
    }

    /// The grid draws pictures of the cells while idle and scrolls with them. A cell typed after
    /// that showed its old (blank) value on the next trackpad scroll, until a click (1.3, Nov 10).
    @MainActor
    private static func editThenTileScrollShowsEdit() -> Result {
      let name = "edit then tile scroll shows edit"
      var sheet = Sheet(name: "Activity")
      for row in 0..<200 {
        sheet.setCell(Cell(raw: "Name \(row + 1)"), at: CellAddress(row: row, col: 0))
      }
      let frame = NSRect(x: 0, y: 0, width: 820, height: 520)
      let grid = SpreadsheetGridNSView(frame: frame)
      let window = NSWindow(
        contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.contentView = grid
      window.setFrameOrigin(NSPoint(x: -4000, y: -4000))
      window.orderFrontRegardless()
      defer {
        window.orderOut(nil)
        window.close()
      }
      let viewModel = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
      grid.viewModel = viewModel
      grid.layoutSubtreeIfNeeded()
      grid.display()
      // The idle warm-up fills the picture cache in the background.
      let deadline = Date().addingTimeInterval(10)
      while !grid.testingViewportTileCacheReady(), Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
      }
      guard grid.testingViewportTileCacheReady() else {
        return Result(name: name, passed: false, detail: "tiles never warmed")
      }
      guard !grid.testingScrollTilesPresented else {
        return Result(name: name, passed: false, detail: "tiles already showing")
      }
      // Fill several cells in column D, as when notes are typed down a column.
      for row in 2..<12 {
        viewModel.setCellValue("typed \(row + 1)", at: CellAddress(row: row, col: 3))
      }
      grid.display()
      // Pictures redrawn after the edit arrive in the background; the scroll waits for them so
      // it uses them rather than the live cells.
      let redrawn = Date().addingTimeInterval(10)
      while !grid.testingViewportTileCacheReady(), Date() < redrawn {
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
      }
      let readyAfterEdit = grid.testingViewportTileCacheReady()
      grid.testingApplyScroll(dx: 0, dy: 2)
      grid.testingFinishScrollTileFills()
      let deadline2 = Date().addingTimeInterval(5)
      while Date() < deadline2 {
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        if grid.testingTilePixelMismatches() == 0 { break }
      }
      let mismatches = grid.testingTilePixelMismatches()
      guard grid.testingScrollTilesPresented else {
        return Result(
          name: name, passed: false,
          detail: "scroll did not use the tiles; cache ready after edit \(readyAfterEdit)")
      }
      guard mismatches == 0 else {
        return Result(
          name: name, passed: false,
          detail: "scroll pictures differ from the cells by \(mismatches) samples")
      }
      return Result(name: name, passed: true, detail: "typed cells show in the scroll pictures")
    }

    /// FILTER, SORT and UNIQUE fill the cells below them; typing in the way shows #SPILL!.
    @MainActor
    private static func arrayFormulasSpill() -> Result {
      let name = "array formulas spill"
      var sheet = Sheet(name: "Deals")
      let rows: [[String]] = [
        ["Rep", "Amount"], ["Ann", "100"], ["Bo", "5"], ["Cy", "40"], ["Di", "70"], ["Ann", "20"],
      ]
      for (r, row) in rows.enumerated() {
        for (c, value) in row.enumerated() {
          sheet.setCell(Cell(raw: value), at: CellAddress(row: r, col: c))
        }
      }
      let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
      let undo = UndoManager()
      undo.groupsByEvent = false
      vm.undoManager = undo
      func step(_ body: () -> Void) {
        undo.beginUndoGrouping()
        body()
        undo.endUndoGrouping()
      }
      func text(_ a1: String) -> String {
        guard let (address, _) = A1Reference.parseRange(a1 + ":" + a1) else { return "?" }
        return vm.displayString(at: address)
      }
      let d1 = CellAddress(row: 0, col: 3)
      step { vm.setCellValue("=FILTER(A2:A6,B2:B6>10)", at: d1) }
      step { vm.setCellValue("=SORT(UNIQUE(A2:A6))", at: CellAddress(row: 0, col: 4)) }
      step { vm.setCellValue("=COUNTA(D1:D10)", at: CellAddress(row: 0, col: 5)) }
      let filtered = ["D1", "D2", "D3", "D4", "D5"].map(text)
      guard filtered == ["Ann", "Cy", "Di", "Ann", ""], text("F1") == "4",
        ["E1", "E2", "E3", "E4", "E5"].map(text) == ["Ann", "Bo", "Cy", "Di", ""]
      else {
        return Result(
          name: name, passed: false,
          detail: "D \(filtered) E \(["E1", "E2", "E3", "E4"].map(text)) F1 \(text("F1"))")
      }
      // The data changes: Bo passes the filter, so it grows by one.
      step { vm.setCellValue("50", at: CellAddress(row: 2, col: 1)) }
      guard text("D2") == "Bo", text("D5") == "Ann", text("F1") == "5" else {
        return Result(
          name: name, passed: false, detail: "after edit D2 \(text("D2")) F1 \(text("F1"))")
      }
      // Typing in the way blocks it; clearing that cell lets it spill again.
      step { vm.setCellValue("x", at: CellAddress(row: 2, col: 3)) }
      guard text("D1") == "#SPILL!", text("D2").isEmpty, text("D3") == "x" else {
        return Result(
          name: name, passed: false, detail: "blocked D1 \(text("D1")) D2 \(text("D2"))")
      }
      undo.undo()
      guard text("D1") == "Ann", text("D3") == "Cy" else {
        return Result(name: name, passed: false, detail: "undo D1 \(text("D1")) D3 \(text("D3"))")
      }
      return Result(name: name, passed: true, detail: "spilled, grew, counted, blocked, undone")
    }

    /// Insert a row, then Undo and Redo in turn. Each Redo must leave an Undo behind, so the
    /// next Undo takes the row out again instead of skipping to an older step.
    @MainActor
    private static func insertRowUndoRedoAlternates() -> Result {
      let name = "insert row undo redo alternates"
      var sheet = Sheet(name: "Rows")
      for (r, value) in ["a", "b", "c"].enumerated() {
        sheet.setCell(Cell(raw: value), at: CellAddress(row: r, col: 0))
      }
      let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
      let undo = UndoManager()
      undo.groupsByEvent = false
      vm.undoManager = undo
      func step(_ body: () -> Void) {
        undo.beginUndoGrouping()
        body()
        undo.endUndoGrouping()
      }
      func column() -> [String] {
        (0..<4).map { vm.displayString(at: CellAddress(row: $0, col: 0)) }
      }
      // An older step that the Undo after a Redo must not reach.
      step { vm.setCellValue("x", at: CellAddress(row: 0, col: 1)) }
      let before = ["a", "b", "c", ""]
      let inserted = ["a", "", "b", "c"]
      vm.select(CellAddress(row: 1, col: 0))
      step { vm.insertRowsAbove(count: 1) }
      guard column() == inserted else {
        return Result(name: name, passed: false, detail: "insert \(column())")
      }
      let script: [(String, () -> Void, [String])] = [
        ("undo 1", { undo.undo() }, before),
        ("redo 1", { undo.redo() }, inserted),
        ("undo 2", { undo.undo() }, before),
        ("redo 2", { undo.redo() }, inserted),
        ("undo 3", { undo.undo() }, before),
      ]
      for (label, action, expected) in script {
        action()
        let olderEdit = vm.displayString(at: CellAddress(row: 0, col: 1))
        guard column() == expected, olderEdit == "x" else {
          return Result(
            name: name, passed: false, detail: "\(label): A \(column()) B1 \(olderEdit)")
        }
      }
      guard undo.canRedo else {
        return Result(name: name, passed: false, detail: "nothing left to redo")
      }
      return Result(name: name, passed: true, detail: "insert, then undo and redo three times")
    }

    /// Cell edits, sizes, freeze panes, hidden sheets and names: after each, Undo and Redo in
    /// turn. Every Redo must leave an Undo behind, and no Undo may reach the older edit.
    @MainActor
    private static func undoRedoAlternatesForEveryStep() -> Result {
      let name = "undo redo alternates for every step"
      typealias Case = (
        label: String, prepare: (SpreadsheetViewModel) -> Void,
        act: (SpreadsheetViewModel) -> Void, probe: (SpreadsheetViewModel) -> String
      )
      func widths(_ vm: SpreadsheetViewModel) -> String {
        vm.activeSheet.columnWidths.sorted { $0.key < $1.key }
          .map { "\($0.key):\(Int($0.value))" }.joined(separator: ",")
      }
      let cases: [Case] = [
        (
          "edit cell", { _ in }, { $0.setCellValue("new", at: CellAddress(row: 1, col: 0)) },
          { $0.activeSheet.cell(at: CellAddress(row: 1, col: 0)).raw }
        ),
        (
          "resize column", { _ in }, { $0.setColumnWidth(2, width: 200) },
          { "\(Int($0.columnWidth(for: 2)))" }
        ),
        (
          "resize row", { _ in }, { $0.setRowHeight(3, height: 60) },
          { "\(Int($0.rowHeight(for: 3)))" }
        ),
        ("auto fit columns", { _ in }, { $0.autoFitAllColumns() }, widths),
        (
          "freeze panes", { $0.select(CellAddress(row: 2, col: 1)) },
          { _ = $0.freezePanesAtSelection() },
          { "\($0.activeSheet.frozenRows),\($0.activeSheet.frozenColumns)" }
        ),
        (
          "hide sheet", { _ in }, { $0.setSheetHidden(true, at: 1) },
          { $0.workbook.sheets.map { $0.isHidden ? "hidden" : "shown" }.joined(separator: ",") }
        ),
        (
          "define named range", { $0.select(CellAddress(row: 0, col: 0)) },
          { $0.defineNamedRange(name: "Start") },
          { $0.workbook.namedRanges.keys.sorted().joined(separator: ",") }
        ),
        (
          "add defined name", { _ in },
          { _ = $0.upsertDefinedName(originalName: nil, name: "Rate", refersTo: "=Data!$A$1") },
          { $0.workbook.namedRanges.keys.sorted().joined(separator: ",") }
        ),
      ]
      var passed: [String] = []
      for item in cases {
        var data = Sheet(name: "Data")
        for (r, value) in ["a", "b", "a much longer piece of text than the column is wide"]
          .enumerated()
        {
          data.setCell(Cell(raw: value), at: CellAddress(row: r, col: 0))
        }
        let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [data, Sheet(name: "Other")]))
        let undo = UndoManager()
        undo.groupsByEvent = false
        vm.undoManager = undo
        func step(_ body: () -> Void) {
          undo.beginUndoGrouping()
          body()
          undo.endUndoGrouping()
        }
        let older = CellAddress(row: 0, col: 1)
        step { vm.setCellValue("x", at: older) }
        item.prepare(vm)
        let before = item.probe(vm)
        step { item.act(vm) }
        let after = item.probe(vm)
        guard before != after else {
          return Result(name: name, passed: false, detail: "\(item.label): no change (\(before))")
        }
        let script: [(String, Bool, String)] = [
          ("undo 1", true, before), ("redo 1", false, after), ("undo 2", true, before),
          ("redo 2", false, after), ("undo 3", true, before),
        ]
        for (label, isUndo, expected) in script {
          if isUndo { undo.undo() } else { undo.redo() }
          let now = item.probe(vm)
          let olderNow = vm.workbook.sheets.first?.cell(at: older).raw ?? "?"
          guard now == expected, olderNow == "x" else {
            return Result(
              name: name, passed: false,
              detail: "\(item.label) \(label): \(now), expected \(expected); B1 \(olderNow)")
          }
        }
        passed.append(item.label)
      }
      return Result(name: name, passed: true, detail: passed.joined(separator: ", "))
    }

    /// `C1#` reads every cell C1's results spill into. Typing in the data, growing the spill,
    /// and blocking it must each update the formulas that read it, without a full recalculation.
    @MainActor
    private static func spillReferencesFollowTheSpill() -> Result {
      let name = "spill references follow the spill"
      var sheet = Sheet(name: "Data")
      for (r, value) in ["30", "10", "20"].enumerated() {
        sheet.setCell(Cell(raw: value), at: CellAddress(row: r, col: 0))
      }
      let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
      let undo = UndoManager()
      undo.groupsByEvent = false
      vm.undoManager = undo
      func step(_ body: () -> Void) {
        undo.beginUndoGrouping()
        body()
        undo.endUndoGrouping()
      }
      func address(_ a1: String) -> CellAddress {
        A1Reference.parseRange(a1 + ":" + a1)?.0 ?? .origin
      }
      /// Waits for the background update that finishes an edit, as the app shows it a moment later.
      func text(_ labels: [String]) -> [String] {
        vm.formulaEngine.finishPendingCrossSheet()
        return labels.map { vm.displayString(at: address($0)) }
      }
      let watched = ["E1", "E2", "E3", "G1", "G2", "G3", "G4"]
      func fail(_ what: String) -> Result {
        Result(name: name, passed: false, detail: "\(what): \(watched) = \(text(watched))")
      }
      step { vm.setCellValue("=SORT(A1:A3)", at: address("C1")) }
      step { vm.setCellValue("=SUM(C1#)", at: address("E1")) }
      step { vm.setCellValue("=ROWS(C1#)", at: address("E2")) }
      step { vm.setCellValue("=INDEX(C1#,1)", at: address("E3")) }
      step { vm.setCellValue("=C1#*2", at: address("G1")) }
      guard text(watched) == ["60", "3", "10", "20", "40", "60", ""] else { return fail("start") }

      // New data: the sorted results change, and so does everything reading them.
      step { vm.setCellValue("5", at: address("A2")) }
      guard text(watched) == ["55", "3", "5", "10", "40", "60", ""] else {
        return fail("typed in the data")
      }

      // The spill grows by a row.
      step { vm.setCellValue("1", at: address("A4")) }
      step { vm.setCellValue("=SORT(A1:A4)", at: address("C1")) }
      guard text(watched) == ["56", "4", "1", "2", "10", "40", "60"] else {
        return fail("spill grew")
      }

      // Something typed in its way blocks it: nothing to read.
      step { vm.setCellValue("in the way", at: address("C3")) }
      guard text(["E1", "E2"]) == ["#REF!", "#REF!"] else { return fail("spill blocked") }
      undo.undo()
      guard text(watched) == ["56", "4", "1", "2", "10", "40", "60"] else {
        return fail("undo block")
      }
      return Result(name: name, passed: true, detail: "C1# follows typing, growth and a block")
    }

    /// Inserting or deleting rows and columns, and sorting, move cells. Spilled results must
    /// follow their formula: none may stay behind as a value no formula owns.
    @MainActor
    private static func spillsSurviveMovingCells() -> Result {
      let name = "spills survive moving cells"
      var sheet = Sheet(name: "Deals")
      let rows: [[String]] = [
        ["Rep", "Amount"], ["Cy", "40"], ["Ann", "100"], ["Bo", "5"], ["Di", "70"], ["Ann", "20"],
      ]
      for (r, row) in rows.enumerated() {
        for (c, value) in row.enumerated() {
          sheet.setCell(Cell(raw: value), at: CellAddress(row: r, col: c))
        }
      }
      let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
      let undo = UndoManager()
      undo.groupsByEvent = false
      vm.undoManager = undo
      func step(_ body: () -> Void) {
        undo.beginUndoGrouping()
        body()
        undo.endUndoGrouping()
      }
      func address(_ a1: String) -> CellAddress {
        A1Reference.parseRange(a1 + ":" + a1)?.0 ?? .origin
      }
      func text(_ labels: [String]) -> [String] {
        labels.map { vm.displayString(at: address($0)) }
      }
      /// Spilled values that no formula's results cover. There must never be any.
      func stranded() -> [String] {
        let sheet = vm.activeSheet
        var covered = Set<CellAddress>()
        for (anchor, range) in sheet.fileExtras.spills {
          for cell in range.allAddresses() where cell != anchor { covered.insert(cell) }
        }
        return sheet.cells.filter { $0.value.isSpilled && !covered.contains($0.key) }
          .map { "\($0.key.a1)=\($0.value.importedFormulaResult ?? "")" }.sorted()
      }
      func fail(_ what: String, _ labels: [String]) -> Result {
        Result(
          name: name, passed: false,
          detail:
            "\(what): \(text(labels)) stray \(stranded()) G1 \(vm.activeSheet.cell(at: address("G1")).raw)=\(text(["G1"])) G2 \(vm.activeSheet.cell(at: address("G2")).raw)=\(text(["G2"]))"
        )
      }
      let column = ["D1", "D2", "D3", "D4", "D5", "D6"]
      step { vm.setCellValue("=FILTER(A2:A6,B2:B6>10)", at: address("D1")) }
      step { vm.setCellValue("=COUNTA(D1:D20)", at: address("G2")) }
      let start = ["Cy", "Ann", "Di", "Ann", "", ""]
      guard text(column) == start, text(["G2"]) == ["4"], stranded().isEmpty else {
        return fail("start", column)
      }

      // A row inserted through the results. They stay four cells long under the formula.
      vm.select(address("A3"))
      step { vm.insertRowsAbove(count: 1) }
      guard text(column) == start, text(["G2"]) == ["4"], stranded().isEmpty,
        vm.activeSheet.cell(at: address("D1")).raw == "=FILTER(A2:A7,B2:B7>10)",
        vm.activeSheet.fileExtras.spills[address("D1")]?.a1Label == "D1:D4"
      else { return fail("insert row", column) }
      undo.undo()
      guard text(column) == start, text(["G2"]) == ["4"], stranded().isEmpty else {
        return fail("undo insert row", column)
      }

      // The formula's own row deleted. Nothing of its results is left.
      vm.select(address("A1"))
      step { vm.deleteSelectedRows() }
      guard text(column) == ["", "", "", "", "", ""], stranded().isEmpty,
        !vm.activeSheet.cells.contains(where: { $0.value.isSpilled })
      else { return fail("delete formula row", column) }
      undo.undo()
      guard text(column) == start, text(["G2"]) == ["4"], stranded().isEmpty else {
        return fail("undo delete row", column)
      }

      // A sort over rows the results lie in. They are the formula's again afterwards, in the
      // order of the sorted data.
      step {
        vm.sortRange(
          column: 0, direction: .ascending, hasHeader: true,
          range: CellRange(start: address("A1"), end: address("D6")))
      }
      let sorted = ["Ann", "Ann", "Cy", "Di", "", ""]
      guard text(["A2", "A3", "A4", "A5", "A6"]) == ["Ann", "Ann", "Bo", "Cy", "Di"],
        text(column) == sorted, text(["G2"]) == ["4"], stranded().isEmpty
      else { return fail("sort", column) }
      undo.undo()
      guard text(["A2", "A3", "A4"]) == ["Cy", "Ann", "Bo"], text(column) == start,
        stranded().isEmpty
      else { return fail("undo sort", column) }

      // A column inserted left of the formula. It and its results move over together.
      vm.select(address("D1"))
      step { vm.insertColumnsLeft(count: 1) }
      let moved = ["E1", "E2", "E3", "E4", "E5", "E6"]
      guard text(moved) == start, text(column) == ["", "", "", "", "", ""], stranded().isEmpty,
        text(["H2"]) == ["4"]
      else { return fail("insert column", moved) }
      undo.undo()
      guard text(column) == start, stranded().isEmpty else {
        return fail("undo insert column", column)
      }

      // The column of the results deleted.
      vm.selectColumns(from: 3, to: 3)
      step { vm.deleteSelectedColumns() }
      guard !vm.activeSheet.cells.contains(where: { $0.value.isSpilled }), stranded().isEmpty
      else { return fail("delete column", column) }
      undo.undo()
      guard text(column) == start, text(["G2"]) == ["4"], stranded().isEmpty else {
        return fail("undo delete column", column)
      }
      return Result(
        name: name, passed: true,
        detail: "rows, columns and a sort moved cells; results followed their formula each time")
    }

    /// Merging clears the cells under the merge. A formula there with a result saved in the
    /// file must not leave that result behind as a value.
    @MainActor
    private static func mergeLeavesNoSavedResult() -> Result {
      let name = "merge leaves no saved result"
      var sheet = Sheet(name: "S")
      let a1 = CellAddress(row: 0, col: 0)
      let b1 = CellAddress(row: 0, col: 1)
      let d1 = CellAddress(row: 0, col: 3)
      sheet.setCell(Cell(raw: "1"), at: a1)
      // As a file opens it: the formula with the result the file saved.
      sheet.setCell(
        Cell(raw: "=A1*2", importedFormulaResult: "2", importedFormulaValueType: .number), at: b1)
      sheet.setCell(
        Cell(raw: "=B1+10", importedFormulaResult: "12", importedFormulaValueType: .number),
        at: d1)
      let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
      vm.undoManager = UndoManager()
      guard vm.displayString(at: b1) == "2", vm.displayString(at: d1) == "12" else {
        return Result(
          name: name, passed: false,
          detail: "start B1 \(vm.displayString(at: b1)) D1 \(vm.displayString(at: d1))")
      }
      vm.selectRange(from: a1, to: b1)
      guard vm.mergeSelection(axis: .all, confirmDiscard: false) == .merged(count: 1) else {
        return Result(name: name, passed: false, detail: "did not merge")
      }
      let covered = vm.activeSheet.cell(at: b1)
      guard !covered.hasContent, !covered.isSpilled, covered.importedFormulaResult == nil else {
        return Result(
          name: name, passed: false,
          detail: "B1 kept \(covered.importedFormulaResult ?? "nil") under the merge")
      }
      return Result(
        name: name, passed: true,
        detail: "B1 empty under the merge; D1 shows \(vm.displayString(at: d1))")
    }

    /// A pivot table another app saved: Refresh draws it from the data in Spark Grid, keeps the
    /// file's table and asks it to rebuild when the file opens there.
    @MainActor
    private static func filePivotRefreshes() -> Result {
      let name = "file pivot refresh"
      var data = Sheet(name: "Sales Data")
      let rows: [[String]] = [
        ["Region", "Rep", "Product", "Amount"], ["West", "Ann", "Bike", "100"],
        ["East", "Bo", "Helmet", "40"], ["West", "Ann", "Helmet", "30"],
        ["East", "Cy", "Bike", "120"], ["North", "Ed", "Bike", "5"],
      ]
      for (r, row) in rows.enumerated() {
        for (c, value) in row.enumerated() {
          data.setCell(Cell(raw: value), at: CellAddress(row: r, col: c))
        }
      }
      // What the other app drew, in its own layout, before the data changed.
      var pivotSheet = Sheet(name: "Pivot")
      let drawn: [[String]] = [
        ["Sum of Amount", "Column Labels"], ["Row Labels", "Bike", "Helmet", "Grand Total"],
        ["East", "120", "40", "160"], ["West", "100", "30", "130"],
        ["Grand Total", "220", "70", "290"],
      ]
      for (r, row) in drawn.enumerated() {
        for (c, value) in row.enumerated() {
          pivotSheet.setCell(Cell(raw: value), at: CellAddress(row: 2 + r, col: c))
        }
      }
      let pivotXML = #"""
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?><pivotTableDefinition xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" name="PivotTable1" cacheId="3" dataCaption="Values"><location ref="A3:D7" firstHeaderRow="1" firstDataRow="2" firstDataCol="1"/><pivotFields count="4"><pivotField axis="axisRow" showAll="0"><items count="4"><item x="1"/><item x="2" h="1"/><item x="0"/><item t="default"/></items></pivotField><pivotField showAll="0"/><pivotField axis="axisCol" showAll="0"><items count="3"><item x="0"/><item x="1"/><item t="default"/></items></pivotField><pivotField dataField="1" showAll="0"/></pivotFields><rowFields count="1"><field x="0"/></rowFields><colFields count="1"><field x="2"/></colFields><dataFields count="1"><dataField name="Sum of Amount" fld="3" baseField="0" baseItem="0"/></dataFields></pivotTableDefinition>
        """#
      let cacheXML = #"""
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?><pivotCacheDefinition xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" recordCount="5"><cacheSource type="worksheet"><worksheetSource ref="A1:D6" sheet="Sales Data"/></cacheSource><cacheFields count="4"><cacheField name="Region" numFmtId="0"><sharedItems count="3"><s v="West"/><s v="East"/><s v="North"/></sharedItems></cacheField><cacheField name="Rep" numFmtId="0"><sharedItems/></cacheField><cacheField name="Product" numFmtId="0"><sharedItems count="2"><s v="Bike"/><s v="Helmet"/></sharedItems></cacheField><cacheField name="Amount" numFmtId="0"><sharedItems containsNumber="1"/></cacheField></cacheFields></pivotCacheDefinition>
        """#
      pivotSheet.fileExtras.pivotTables = [PivotTablePart(xml: Data(pivotXML.utf8), cacheID: 3)]
      var original = Workbook(sheets: [data, pivotSheet])
      original.pivotCaches = [
        PivotCachePart(cacheID: 3, definitionXML: Data(cacheXML.utf8), recordsXML: nil)
      ]
      do {
        // Through a save and reopen, as a real file arrives.
        let opened = try XLSXCodec.importWorkbook(from: XLSXCodec.exportWorkbook(original))
        let vm = SpreadsheetViewModel(workbook: opened)
        let undo = UndoManager()
        undo.groupsByEvent = false
        vm.undoManager = undo
        // The data changed since the file was saved.
        vm.selectSheet(at: 0)
        undo.beginUndoGrouping()
        vm.setCellValue("150", at: CellAddress(row: 1, col: 3))
        undo.endUndoGrouping()
        vm.selectSheet(at: 1)
        guard vm.hasPivots else {
          return Result(name: name, passed: false, detail: "file pivot not seen")
        }
        undo.beginUndoGrouping()
        vm.refreshPivots()
        undo.endUndoGrouping()
        func text(_ row: Int, _ col: Int) -> String {
          vm.displayString(at: CellAddress(row: 2 + row, col: col))
        }
        // North stays hidden, as the file's table hid it. West is now 150 + 30.
        let table = (0...3).map { r in (0...3).map { text(r, $0) } }
        guard
          table == [
            ["Region", "Bike", "Helmet", "Grand Total"], ["East", "120", "40", "160"],
            ["West", "150", "30", "180"], ["Grand Total", "270", "70", "340"],
          ], text(4, 0).isEmpty, vm.pivotNotice == nil
        else {
          return Result(
            name: name, passed: false, detail: "drawn \(table) notice \(vm.pivotNotice ?? "")")
        }
        let part = String(decoding: vm.activeSheet.fileExtras.pivotTables[0].xml, as: UTF8.self)
        let cache = String(decoding: vm.workbook.pivotCaches[0].definitionXML, as: UTF8.self)
        guard part.contains(#"ref="A3:D7""#), cache.contains(#"refreshOnLoad="1""#),
          vm.activeSheet.fileExtras.sparkPivots.first?.linkedFilePivot == "PivotTable1"
        else {
          return Result(name: name, passed: false, detail: "file pivot not kept in step")
        }
        // Saved and reopened, the link holds and the file still has its pivot table.
        let again = try XLSXCodec.importWorkbook(from: XLSXCodec.exportWorkbook(vm.workbook))
        guard again.sheets[1].fileExtras.pivotTables.count == 1,
          again.sheets[1].fileExtras.sparkPivots.count == 1
        else {
          return Result(name: name, passed: false, detail: "lost in save")
        }
        undo.undo()
        guard text(0, 0) == "Sum of Amount", vm.activeSheet.fileExtras.sparkPivots.isEmpty,
          !String(decoding: vm.workbook.pivotCaches[0].definitionXML, as: UTF8.self).contains(
            "refreshOnLoad")
        else {
          return Result(name: name, passed: false, detail: "undo left \(text(0, 0))")
        }
      } catch {
        return Result(name: name, passed: false, detail: error.localizedDescription)
      }
      return Result(
        name: name, passed: true, detail: "redrawn, hidden item kept, file pivot kept, undone")
    }

    @MainActor
    private static func pivotGroupsDatesByMonth() -> Result {
      let name = "pivot date grouping"
      var data = Sheet(name: "Orders")
      data.setCell(Cell(raw: "Date"), at: .origin)
      data.setCell(Cell(raw: "Qty"), at: CellAddress(row: 0, col: 1))
      let serials = [46023, 46030, 46113, 45658]
      var dateFormat = CellFormat()
      dateFormat.numberFormat = .date
      for (i, serial) in serials.enumerated() {
        var cell = Cell(raw: String(serial))
        cell.format = dateFormat
        data.setCell(cell, at: CellAddress(row: i + 1, col: 0))
        data.setCell(Cell(raw: String(i + 1)), at: CellAddress(row: i + 1, col: 1))
      }
      let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [data]))
      vm.undoManager = UndoManager()
      vm.select(.origin)
      guard let pivot = vm.createPivot() else {
        return Result(name: name, passed: false, detail: "pivot not made")
      }
      guard vm.pivotFieldIsDate(pivot, field: 0), !vm.pivotFieldIsDate(pivot, field: 1) else {
        return Result(name: name, passed: false, detail: "date column not recognised")
      }
      vm.applyPivot(
        pivot.id,
        definition: PivotDefinition(
          rows: [0], values: [.init(field: 1, aggregate: .sum)], dateGroups: [0: .month]))
      let labels = (1...4).map { vm.displayString(at: CellAddress(row: 2 + $0, col: 0)) }
      let jan = vm.displayString(at: CellAddress(row: 4, col: 1))
      guard labels == ["Jan 2025", "Jan 2026", "Apr 2026", "Grand Total"], jan == "3",
        vm.pivotItems(pivot, field: 0, group: .quarter) == ["Q1 2025", "Q1 2026", "Q2 2026"]
      else {
        return Result(name: name, passed: false, detail: "rows \(labels) Jan 2026 \(jan)")
      }
      return Result(name: name, passed: true, detail: "months grouped and in date order")
    }

    @MainActor
    private static func pivotCreateDrawRefreshUndo() -> Result {
      let name = "pivot table"
      var data = Sheet(name: "Sales")
      let rows: [[String]] = [
        ["Region", "Rep", "Amount"], ["West", "Ann", "100"], ["East", "Bo", "40"],
        ["West", "Cy", "30"], ["East", "Di", "120"],
      ]
      for (r, row) in rows.enumerated() {
        for (c, value) in row.enumerated() {
          data.setCell(Cell(raw: value), at: CellAddress(row: r, col: c))
        }
      }
      let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [data]))
      let undo = UndoManager()
      undo.groupsByEvent = false
      vm.undoManager = undo
      func step(_ body: () -> Void) {
        undo.beginUndoGrouping()
        body()
        undo.endUndoGrouping()
      }
      vm.select(CellAddress(row: 1, col: 1))
      var made: SheetPivot?
      step { made = vm.createPivot() }
      guard let pivot = made, vm.activeSheet.name == "Pivot 1", vm.workbook.sheets.count == 2,
        pivot.sourceRange.normalized.maxRow == 4, pivot.sourceRange.normalized.maxCol == 2
      else {
        return Result(name: name, passed: false, detail: "pivot sheet not made")
      }
      func text(_ row: Int, _ col: Int) -> String {
        vm.displayString(at: CellAddress(row: 2 + row, col: col))
      }
      var definition = PivotDefinition(rows: [0], values: [.init(field: 2, aggregate: .sum)])
      step { vm.applyPivot(pivot.id, definition: definition) }
      guard text(0, 0) == "Region", text(0, 1) == "Sum of Amount", text(1, 0) == "East",
        text(1, 1) == "160", text(3, 0) == "Grand Total", text(3, 1) == "290",
        vm.activeSheet.cell(at: CellAddress(row: 2, col: 0)).format?.bold == true,
        vm.activeSheet.cell(at: .origin).raw.isEmpty
      else {
        return Result(
          name: name, passed: false,
          detail: "drawn \(text(0, 0)) \(text(1, 0)) \(text(1, 1)) \(text(3, 1))")
      }
      // A pivot chart covers the header and item rows, not the grand total.
      guard vm.canMakePivotChart,
        let chartRange = SpreadsheetViewModel.pivotChartRange(
          anchor: pivot.anchor, rows: 4, columns: 2, definition: definition),
        chartRange.normalized.maxRow == 4, chartRange.normalized.maxCol == 1
      else {
        return Result(name: name, passed: false, detail: "pivot chart range wrong")
      }
      step {
        vm.insertChart(
          SheetChart(
            title: "Pivot", dataRange: chartRange, categoryColumn: 0, valueColumn: 1,
            anchorRow: 10, anchorCol: 0))
      }
      // GETPIVOTDATA reads the table and follows it through a refresh.
      let lookupCell = CellAddress(row: 0, col: 6)
      step {
        vm.setCellValue(#"=GETPIVOTDATA("Sum of Amount",A3,"Region","West")"#, at: lookupCell)
      }
      guard vm.displayString(at: lookupCell) == "130" else {
        return Result(
          name: name, passed: false, detail: "GETPIVOTDATA \(vm.displayString(at: lookupCell))")
      }
      // A change in the source shows after Refresh.
      vm.selectSheet(at: 0)
      step { vm.setCellValue("200", at: CellAddress(row: 1, col: 2)) }
      vm.selectSheet(at: 1)
      step { vm.refreshPivots() }
      guard text(2, 1) == "230", text(3, 1) == "390" else {
        return Result(name: name, passed: false, detail: "refresh West \(text(2, 1))")
      }
      guard vm.displayString(at: lookupCell) == "230" else {
        return Result(
          name: name, passed: false,
          detail: "GETPIVOTDATA after refresh \(vm.displayString(at: lookupCell))")
      }
      // A third region makes the table one row taller; the chart follows.
      vm.selectSheet(at: 0)
      step { vm.setCellValue("North", at: CellAddress(row: 4, col: 0)) }
      vm.selectSheet(at: 1)
      step { vm.refreshPivots() }
      guard vm.activeSheet.charts.first?.dataRange.normalized.maxRow == 5 else {
        return Result(
          name: name, passed: false,
          detail:
            "chart did not follow: \(String(describing: vm.activeSheet.charts.first?.dataRange))")
      }
      undo.undo()
      undo.undo()
      vm.selectSheet(at: 1)
      // A smaller table clears what the larger one drew.
      definition = PivotDefinition(values: [.init(field: 2, aggregate: .count)])
      step { vm.applyPivot(pivot.id, definition: definition) }
      guard text(0, 0) == "Count of Amount", text(1, 0) == "4", text(2, 0).isEmpty,
        text(3, 0).isEmpty, text(1, 1).isEmpty
      else {
        return Result(name: name, passed: false, detail: "old cells left: \(text(2, 0))")
      }
      undo.undo()
      guard text(3, 0) == "Grand Total" else {
        return Result(name: name, passed: false, detail: "undo did not restore the table")
      }
      while vm.workbook.sheets.count > 1, undo.canUndo { undo.undo() }
      guard vm.workbook.sheets.count == 1, vm.activeSheet.name == "Sales" else {
        return Result(
          name: name, passed: false, detail: "undo left \(vm.workbook.sheets.map(\.name))")
      }
      return Result(name: name, passed: true, detail: "made, drawn, refreshed, shrunk, undone")
    }

    @MainActor
    private static func linksInsertFollowRemove() -> Result {
      let name = "links"
      var data = Sheet(name: "Data")
      data.setCell(Cell(raw: "Total"), at: CellAddress(row: 0, col: 0))
      data.setCell(
        Cell(raw: "=HYPERLINK(\"https://example.com/\"&B2,\"Docs\")"),
        at: CellAddress(row: 3, col: 0))
      data.setCell(Cell(raw: "help"), at: CellAddress(row: 1, col: 1))
      data.setCell(
        Cell(raw: "=HYPERLINK(\"#'Q1 Sales'!C3\",\"Jump\")"), at: CellAddress(row: 4, col: 0))
      let sales = Sheet(name: "Q1 Sales")
      var workbook = Workbook(sheets: [data, sales])
      workbook.namedRanges["TOTALS"] = NamedRange(
        name: "Totals", sheetName: "Q1 Sales",
        range: CellRange(start: CellAddress(row: 9, col: 1), end: CellAddress(row: 9, col: 3)))
      let vm = SpreadsheetViewModel(workbook: workbook)
      let undo = UndoManager()
      undo.groupsByEvent = false
      vm.undoManager = undo
      func step(_ body: () -> Void) {
        undo.beginUndoGrouping()
        body()
        undo.endUndoGrouping()
      }
      let b1 = CellAddress(row: 0, col: 1)
      vm.select(b1)
      step { vm.setLink(text: "", destination: .web("pat@example.com")) }
      guard let mail = vm.hyperlink(at: b1), mail.target == "mailto:pat@example.com",
        vm.activeSheet.cell(at: b1).raw == "pat@example.com",
        vm.activeSheet.cell(at: b1).format?.underline == true
      else {
        return Result(name: name, passed: false, detail: "mail link not made")
      }
      vm.select(.origin)
      step { vm.setLink(text: "", destination: .place("Totals")) }
      guard vm.activeSheet.cell(at: .origin).raw == "Total",
        let place = vm.followableLink(at: .origin)
      else {
        return Result(name: name, passed: false, detail: "place link not made")
      }
      vm.openHyperlink(place)
      guard vm.activeSheet.name == "Q1 Sales", vm.selectionRange.normalized.minRow == 9,
        vm.selectionRange.normalized.maxCol == 3
      else {
        return Result(name: name, passed: false, detail: "did not go to Totals")
      }
      vm.selectSheet(at: 0)
      guard
        vm.followableLink(at: CellAddress(row: 3, col: 0))?.target
          == "https://example.com/help"
      else {
        return Result(
          name: name, passed: false,
          detail:
            "HYPERLINK target \(String(describing: vm.hyperlinkFormulaTarget(at: CellAddress(row: 3, col: 0))))"
        )
      }
      if let jump = vm.followableLink(at: CellAddress(row: 4, col: 0)) {
        vm.openHyperlink(jump)
      }
      guard vm.activeSheet.name == "Q1 Sales", vm.selectionAnchor == CellAddress(row: 2, col: 2)
      else {
        return Result(name: name, passed: false, detail: "HYPERLINK # place not followed")
      }
      vm.selectSheet(at: 0)
      do {
        let back = try XLSXCodec.importWorkbook(from: XLSXCodec.exportWorkbook(vm.workbook))
        let links = back.sheets[0].fileExtras.hyperlinks
        guard links.contains(where: { $0.target == "mailto:pat@example.com" }),
          links.contains(where: { $0.location == "Totals" })
        else {
          return Result(name: name, passed: false, detail: "links lost in save")
        }
      } catch {
        return Result(name: name, passed: false, detail: error.localizedDescription)
      }
      vm.select(b1)
      step { vm.removeLink() }
      guard vm.hyperlink(at: b1) == nil, vm.activeSheet.cell(at: b1).format?.underline != true,
        vm.activeSheet.cell(at: b1).raw == "pat@example.com"
      else {
        return Result(name: name, passed: false, detail: "remove left the link or its style")
      }
      undo.undo()
      guard vm.hyperlink(at: b1) != nil else {
        return Result(name: name, passed: false, detail: "undo did not bring the link back")
      }
      return Result(name: name, passed: true, detail: "mail, name, HYPERLINK, save, remove, undo")
    }

    @MainActor
    private static func pdfExportKeepsPages() -> Result {
      let name = "pdf export"
      var report = Sheet(name: "Report")
      for row in 0..<30 {
        report.setCell(Cell(raw: "Item \(row + 1)"), at: CellAddress(row: row, col: 0))
      }
      report.fileExtras.rowBreaks = [10]
      var notes = Sheet(name: "Notes")
      notes.setCell(Cell(raw: "Second sheet"), at: CellAddress(row: 0, col: 0))
      let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [report, notes]))
      var options = SpreadsheetPrintOptions.default(for: vm)
      options.scope = .workbook
      do {
        let result = try SpreadsheetPDFExporter.pdfData(
          pages: options.pages(for: vm), options: options, workbook: vm.workbook)
        if ProcessInfo.processInfo.environment["SPARK_GRID_PDF_DUMP"] != nil {
          try? result.data.write(
            to: FileManager.default.temporaryDirectory.appendingPathComponent("bugbash-export.pdf"))
        }
        guard let pdf = PDFDocument(data: result.data), pdf.pageCount == 3, result.pageCount == 3
        else {
          return Result(name: name, passed: false, detail: "expected 3 pages")
        }
        let first = pdf.page(at: 0)?.string ?? ""
        let second = pdf.page(at: 1)?.string ?? ""
        let third = pdf.page(at: 2)?.string ?? ""
        guard first.contains("Item 10"), !first.contains("Item 11"), second.contains("Item 11"),
          third.contains("Second sheet")
        else {
          let sample = [first, second, third].map {
            $0.replacingOccurrences(of: "\n", with: " ").prefix(80)
          }
          return Result(name: name, passed: false, detail: "page text: \(sample)")
        }
      } catch {
        return Result(name: name, passed: false, detail: error.localizedDescription)
      }
      return Result(name: name, passed: true, detail: "break and sheets became 3 text pages")
    }

    @MainActor
    private static func printAreaAndPageBreaks() -> Result {
      let name = "print area and page breaks"
      var sheet = Sheet(name: "Report")
      for row in 0..<60 {
        sheet.setCell(Cell(raw: "Row \(row + 1)"), at: CellAddress(row: row, col: 0))
        sheet.setCell(Cell(raw: "\(row)"), at: CellAddress(row: row, col: 1))
      }
      sheet.frozenRows = 1
      let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
      let undo = UndoManager()
      undo.groupsByEvent = false
      vm.undoManager = undo
      func step(_ body: () -> Void) {
        undo.beginUndoGrouping()
        body()
        undo.endUndoGrouping()
      }
      vm.selectRange(from: CellAddress(row: 0, col: 0), to: CellAddress(row: 39, col: 1))
      step { vm.setPrintArea() }
      vm.select(CellAddress(row: 20, col: 0))
      step { vm.insertPageBreak() }
      guard vm.printArea?.normalized.maxRow == 39, vm.activeSheet.fileExtras.rowBreaks == [20],
        vm.activeSheet.fileExtras.columnBreaks.isEmpty
      else {
        return Result(name: name, passed: false, detail: "area or break not set")
      }
      var options = SpreadsheetPrintOptions.default(for: vm)
      options.scale = .normal
      guard options.scope == .printArea, let page = options.pages(for: vm).first,
        page.range.normalized.maxRow == 39
      else {
        return Result(name: name, passed: false, detail: "print scope is not the print area")
      }
      let grid = SpreadsheetPrintNSView(sheet: page.sheet, range: page.range)
      let layout = SpreadsheetPrintLayout(gridView: grid, sheet: page.sheet, options: options)
      let rows = layout.pages.map(\.rows)
      // Rows 1-20 fit one page; the break starts row 21's page; the frozen row repeats there.
      guard rows == [0...19, 20...39], layout.pages[1].yBands.count == 3 else {
        return Result(name: name, passed: false, detail: "pages \(rows)")
      }
      do {
        let back = try XLSXCodec.importWorkbook(from: XLSXCodec.exportWorkbook(vm.workbook))
          .activeSheet
        guard back.fileExtras.printArea?.normalized.maxRow == 39,
          back.fileExtras.rowBreaks == [20]
        else {
          return Result(name: name, passed: false, detail: "lost in save")
        }
      } catch {
        return Result(name: name, passed: false, detail: error.localizedDescription)
      }
      undo.undo()
      guard vm.activeSheet.fileExtras.rowBreaks.isEmpty, vm.printArea != nil else {
        return Result(name: name, passed: false, detail: "undo did not take the break back")
      }
      step { vm.clearPrintArea() }
      guard vm.activeSheet.fileExtras.rowBreaks.isEmpty, vm.printArea == nil else {
        return Result(name: name, passed: false, detail: "undo or clear failed")
      }
      return Result(name: name, passed: true, detail: "area printed, break paged, saved, undone")
    }

    @MainActor
    private static func insertColumnPastLastColumn() -> Result {
      var sheet = Sheet(name: "Insert")
      let lastCol = Workbook.defaultColumnCount - 1
      sheet.setCell(Cell(raw: "Last"), at: CellAddress(row: 0, col: lastCol))
      let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
      vm.selectColumn(lastCol)
      let beforeCount = vm.activeSheet.effectiveColumnCount
      vm.insertColumnsRight()
      let afterCount = vm.activeSheet.effectiveColumnCount
      guard afterCount == beforeCount + 1 else {
        return Result(
          name: "insert column right edge",
          passed: false,
          detail: "columns \(beforeCount) -> \(afterCount)"
        )
      }
      let selected = vm.selectionRange.normalized
      guard selected.minCol == lastCol + 1, selected.maxCol == lastCol + 1 else {
        return Result(
          name: "insert column right edge",
          passed: false,
          detail: "selection cols \(selected.minCol)-\(selected.maxCol)"
        )
      }
      return Result(name: "insert column right edge", passed: true, detail: "column \(lastCol + 1)")
    }

    @MainActor
    private static func insertChartEmptySelection() -> Result {
      let name = "insert chart empty selection"
      var sheet = Sheet(name: "Charts")
      sheet.setCell(Cell(raw: "Name"), at: .origin)
      sheet.setCell(Cell(raw: "Ada"), at: CellAddress(row: 1, col: 0))
      sheet.setCell(Cell(raw: "10"), at: CellAddress(row: 1, col: 1))
      let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
      guard vm.selectionRange.isSingleCell else {
        return Result(name: name, passed: false, detail: "expected a single-cell selection")
      }
      guard vm.chartSelectionRange == nil else {
        return Result(name: name, passed: false, detail: "invented a range from nearby cells")
      }
      vm.beginInsertChart(preferredKind: .line)
      guard vm.isInsertChartPresented, vm.pendingChartKind == .line else {
        return Result(name: name, passed: false, detail: "chart menu did not open")
      }
      guard vm.activeSheet.charts.isEmpty else {
        return Result(name: name, passed: false, detail: "chart created before a range was chosen")
      }
      let refused = vm.insertChart(
        SheetChart(kind: .bar, dataRange: .singleOrigin, anchorRow: 0, anchorCol: 0)
      )
      guard !refused, vm.activeSheet.charts.isEmpty, vm.isInsertChartPresented else {
        return Result(name: name, passed: false, detail: "single-cell insert was accepted")
      }
      guard ChartDataRangeParser.parse("") == nil,
        ChartDataRangeParser.parse("A1") == nil,
        ChartDataRangeParser.parse("A1:A1") == nil,
        ChartDataRangeParser.parse("A:A") == nil,
        ChartDataRangeParser.parse("Sheet1!A1:B2") == nil
      else {
        return Result(name: name, passed: false, detail: "parser accepted an empty selection")
      }
      guard let parsed = ChartDataRangeParser.parse("A1:B2"), !parsed.isSingleCell else {
        return Result(name: name, passed: false, detail: "parser rejected A1:B2")
      }
      let inserted = vm.insertChart(
        SheetChart(
          kind: .line,
          title: "Picked",
          dataRange: parsed,
          categoryColumn: 0,
          valueColumn: 1,
          anchorRow: 4,
          anchorCol: 0
        )
      )
      guard inserted, vm.activeSheet.charts.count == 1, vm.activeSheet.charts[0].dataRange == parsed
      else {
        return Result(name: name, passed: false, detail: "explicit range was not inserted")
      }
      guard !vm.isInsertChartPresented else {
        return Result(name: name, passed: false, detail: "menu stayed open after insert")
      }

      let ranged = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
      ranged.selectRange(from: .origin, to: CellAddress(row: 1, col: 1))
      guard let chosen = ranged.chartSelectionRange, !chosen.isSingleCell else {
        return Result(name: name, passed: false, detail: "multi-cell selection was dropped")
      }
      ranged.beginInsertChart()
      guard ranged.isInsertChartPresented, ranged.activeSheet.charts.isEmpty else {
        return Result(name: name, passed: false, detail: "ranged insert opened wrong")
      }
      return Result(name: name, passed: true, detail: "menu opens; chart waits for a range")
    }

    /// `=SU` still offers SUM. After that token is `=SUM`, the popup must stay
    /// closed so Return commits the cell instead of accepting SUM again.
    private static func formulaExactTokenSkipsAutocomplete() -> Result {
      let named: [String] = []
      let offersPartial = FormulaAutocomplete.shouldOfferPopup(
        in: "=SU", utf16Cursor: 3, namedRanges: named)
      let offersExact = FormulaAutocomplete.shouldOfferPopup(
        in: "=SUM", utf16Cursor: 4, namedRanges: named)
      let offersLower = FormulaAutocomplete.shouldOfferPopup(
        in: "=sum", utf16Cursor: 4, namedRanges: named)
      guard offersPartial, !offersExact, !offersLower else {
        return Result(
          name: "formula exact token",
          passed: false,
          detail: "popup SU=\(offersPartial) SUM=\(offersExact) sum=\(offersLower)"
        )
      }
      guard FormulaAutocomplete.isExactCompletion(partial: "SUM", completion: "SUM"),
        !FormulaAutocomplete.isExactCompletion(partial: "SU", completion: "SUM")
      else {
        return Result(
          name: "formula exact token", passed: false, detail: "exact-match check failed")
      }
      let matches = FormulaAutocomplete.suggestions(matching: "SUM", namedRanges: named)
      guard matches == ["SUM"] else {
        return Result(name: "formula exact token", passed: false, detail: "SUM matches \(matches)")
      }
      return Result(
        name: "formula exact token", passed: true, detail: "=SU offers popup; =SUM does not")
    }

    @MainActor
    private static func editExistingChart() -> Result {
      let name = "edit existing chart"
      var sheet = Sheet(name: "Weekly Calls")
      sheet.setCell(Cell(raw: "Week"), at: .origin)
      sheet.setCell(Cell(raw: "Calls"), at: CellAddress(row: 0, col: 1))
      for index in 1...4 {
        sheet.setCell(Cell(raw: "Week \(index)"), at: CellAddress(row: index, col: 0))
        sheet.setCell(Cell(raw: "\(index * 3)"), at: CellAddress(row: index, col: 1))
      }
      let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
      let range = CellRange(start: .origin, end: CellAddress(row: 4, col: 1))
      let inserted = vm.insertChart(
        SheetChart(
          kind: .bar,
          title: "Calls by Week",
          dataRange: range,
          categoryColumn: 0,
          valueColumn: 1,
          hasHeaderRow: true,
          valueMode: .values,
          anchorRow: 7,
          anchorCol: 0,
          rowSpan: 12,
          colSpan: 8
        )
      )
      guard inserted, vm.activeSheet.charts.count == 1 else {
        return Result(name: name, passed: false, detail: "chart was not inserted")
      }
      let original = vm.activeSheet.charts[0]
      guard vm.selectedChartID == original.id else {
        return Result(
          name: name, passed: false, detail: "inserted chart was not selected on the sheet")
      }
      vm.beginEditChart(id: original.id)
      guard vm.isInsertChartPresented, vm.editingChartID == original.id,
        vm.activeSheet.charts.count == 1
      else {
        return Result(name: name, passed: false, detail: "edit did not reopen the existing chart")
      }
      var edited = original
      edited.kind = .line
      edited.categoryColumn = 1
      edited.valueColumn = 0
      edited.valueMode = .count
      edited.title = "Calls by Week"
      guard vm.updateChart(edited) else {
        return Result(name: name, passed: false, detail: "update was refused")
      }
      guard vm.activeSheet.charts.count == 1 else {
        return Result(name: name, passed: false, detail: "update inserted a second chart")
      }
      let saved = vm.activeSheet.charts[0]
      guard saved.id == original.id,
        saved.kind == .line,
        saved.categoryColumn == 1,
        saved.valueColumn == 0,
        saved.valueMode == .count,
        saved.dataRange == range,
        saved.anchorRow == 7,
        saved.anchorCol == 0,
        saved.rowSpan == 12,
        saved.colSpan == 8,
        !vm.isInsertChartPresented,
        vm.editingChartID == nil
      else {
        return Result(
          name: name, passed: false,
          detail: "saved \(saved.kind) anchor \(saved.anchorRow),\(saved.anchorCol)")
      }
      var rejected = saved
      rejected.dataRange = .singleOrigin
      guard !vm.updateChart(rejected), vm.activeSheet.charts[0].dataRange == range else {
        return Result(name: name, passed: false, detail: "single-cell edit was accepted")
      }
      vm.selection = .origin
      vm.beginInsertChart(preferredKind: .bar)
      guard vm.editingChartID == nil, vm.isInsertChartPresented, vm.chartSelectionRange == nil
      else {
        return Result(name: name, passed: false, detail: "empty selection started an edit")
      }
      guard vm.activeSheet.charts.count == 1 else {
        return Result(name: name, passed: false, detail: "empty selection created a chart")
      }
      return Result(
        name: name, passed: true, detail: "type, range, and series update; anchor stays")
    }

    private static func onSheetChartFrame() -> Result {
      let name = "on-sheet chart frame"
      let frame = OnSheetChartGeometry.frame(
        anchorRow: 7,
        anchorCol: 0,
        rowSpan: 12,
        colSpan: 8,
        rowCount: 1_000,
        columnCount: 26,
        xForColumn: { 28 + CGFloat($0) * 80 },
        yForRow: { 28 + CGFloat($0) * 22 },
        columnWidth: { _ in 80 },
        rowHeight: { _ in 22 }
      )
      guard frame.width == 640, frame.height == 264, frame.minX == 28, frame.minY == 28 + 7 * 22
      else {
        return Result(name: name, passed: false, detail: "\(frame)")
      }
      let dataBottom: CGFloat = 28 + 5 * 22
      guard frame.minY >= dataBottom else {
        return Result(name: name, passed: false, detail: "chart covers the data rows")
      }
      guard OnSheetChartGeometry.placedHeight(top: frame.minY, bottom: frame.maxY) == frame.height
      else {
        return Result(
          name: name, passed: false,
          detail:
            "placed height \(String(describing: OnSheetChartGeometry.placedHeight(top: frame.minY, bottom: frame.maxY)))"
        )
      }
      // bottom - top is negative when the lower edge sits above the upper edge.
      guard OnSheetChartGeometry.placedHeight(top: 400, bottom: 120) == nil else {
        return Result(
          name: name, passed: false, detail: "reversed edges were treated as a view height")
      }
      guard OnSheetChartGeometry.placedHeight(top: 10, bottom: 10.5) == nil else {
        return Result(name: name, passed: false, detail: "sub-point height was placed")
      }
      let collapsed = OnSheetChartGeometry.frame(
        anchorRow: 0,
        anchorCol: 0,
        rowSpan: 12,
        colSpan: 4,
        rowCount: 100,
        columnCount: 8,
        xForColumn: { CGFloat($0) * 80 },
        yForRow: { 400 - CGFloat($0) * 30 },
        columnWidth: { _ in 80 },
        rowHeight: { _ in -10 }
      )
      guard collapsed == .zero else {
        return Result(name: name, passed: false, detail: "negative row span produced \(collapsed)")
      }
      let scrolled = OnSheetChartGeometry.frame(
        anchorRow: 0,
        anchorCol: 0,
        rowSpan: 12,
        colSpan: 4,
        rowCount: 100,
        columnCount: 8,
        xForColumn: { CGFloat($0) * 80 },
        yForRow: { row in
          row < 2 ? CGFloat(row) * 22 : CGFloat(row) * 22 - 800
        },
        columnWidth: { _ in 80 },
        rowHeight: { _ in 22 }
      )
      guard scrolled.height >= 1, scrolled.height == 12 * 22 else {
        return Result(name: name, passed: false, detail: "scrolled span \(scrolled.height)")
      }
      return Result(
        name: name, passed: true, detail: "\(Int(frame.width))×\(Int(frame.height)) at row 7")
    }

    /// `SheetChartView` hands `.chartPlotStyle { plot.padding(.bottom, _) }` a
    /// value that must stay under whatever height the chart is actually given;
    /// otherwise Charts computes a negative plot height in
    /// `PositionScaleRange.plotFrame` and traps. A normal multi-cell chart
    /// (plenty of height) must still get the full 20pt inset for category
    /// labels — this only has to shrink once the proposed height is small
    /// (side panel mid-resize, first layout, or a squeezed on-sheet card).
    private static func chartPlotPaddingBounded() -> Result {
      let name = "chart plot padding bounded"
      let ideal = SheetChartView.plotBottomInset
      let minimum = SheetChartView.minimumPlotHeight
      // A normal 8×12 chart card has well over `minimum` to spare: full padding.
      let roomy = SheetChartView.clampedBottomPadding(idealPadding: ideal, availableHeight: 236)
      guard roomy == ideal else {
        return Result(name: name, passed: false, detail: "roomy chart lost its padding: \(roomy)")
      }
      // Exactly `ideal + minimum` is the last height that still affords full padding.
      let boundary = SheetChartView.clampedBottomPadding(
        idealPadding: ideal, availableHeight: ideal + minimum)
      guard boundary == ideal else {
        return Result(
          name: name, passed: false, detail: "boundary height lost its padding: \(boundary)")
      }
      // Below that, padding must shrink by exactly the shortfall — plot height
      // stays pinned at `minimum`, never negative.
      for availableHeight: CGFloat in [minimum, minimum + 8, ideal + minimum - 1, 10, 1] {
        let padding = SheetChartView.clampedBottomPadding(
          idealPadding: ideal, availableHeight: availableHeight)
        guard padding >= 0, padding <= availableHeight,
          availableHeight - padding >= min(minimum, availableHeight)
        else {
          return Result(
            name: name, passed: false,
            detail: "height \(availableHeight) padding \(padding) went negative")
        }
      }
      // A degenerate or reversed proposal must never produce negative padding.
      for availableHeight: CGFloat in [0, -5] {
        let padding = SheetChartView.clampedBottomPadding(
          idealPadding: ideal, availableHeight: availableHeight)
        guard padding == 0 else {
          return Result(
            name: name, passed: false,
            detail: "non-positive height \(availableHeight) kept padding \(padding)")
        }
      }
      return Result(
        name: name, passed: true, detail: "padding stays within the proposed height at every size")
    }

    /// Insert Chart on Weekly Calls must hand Charts a finite domain with
    /// `lower < upper`. An empty, NaN, or reversed domain hits the same
    /// `PositionScaleRange.plotFrame` trap as a negative plot height.
    private static func chartScaleDomainHolds() -> Result {
      let name = "chart scale domain"
      func holds(_ domain: ClosedRange<Double>?) -> Bool {
        guard let domain else { return false }
        return domain.lowerBound.isFinite
          && domain.upperBound.isFinite
          && domain.lowerBound < domain.upperBound
      }
      let weeklyValues = [3.0, 6, 9, 12]
      guard let weekly = SheetChartView.plotValueDomain(values: weeklyValues),
        holds(weekly),
        weekly.lowerBound <= 0,
        weekly.upperBound > 12
      else {
        return Result(
          name: name, passed: false,
          detail:
            "weekly \(String(describing: SheetChartView.plotValueDomain(values: weeklyValues)))")
      }
      guard holds(SheetChartView.plotValueDomain(values: [5, 5, 5])),
        holds(SheetChartView.plotValueDomain(values: [0, 0])),
        let negatives = SheetChartView.plotValueDomain(values: [-4, -4]),
        holds(negatives),
        negatives.lowerBound <= -4
      else {
        return Result(name: name, passed: false, detail: "flat series domain collapsed")
      }
      guard SheetChartView.plotValueDomain(values: []) == nil,
        SheetChartView.plotValueDomain(values: [.nan, .infinity]) == nil,
        let mixed = SheetChartView.plotValueDomain(values: [.nan, 4]),
        holds(mixed),
        mixed.upperBound > 4
      else {
        return Result(
          name: name, passed: false, detail: "non-finite values still produced a domain")
      }
      guard SheetChartView.plotCategoryDomain(count: 0) == nil,
        SheetChartView.plotCategoryDomain(count: 1) == -0.5...0.5,
        SheetChartView.plotCategoryDomain(count: 4) == -0.5...3.5
      else {
        return Result(
          name: name, passed: false,
          detail:
            "category domain \(String(describing: SheetChartView.plotCategoryDomain(count: 4)))")
      }

      let range = CellRange(start: .origin, end: CellAddress(row: 2, col: 1))
      let chart = SheetChart(
        kind: .bar,
        dataRange: range,
        categoryColumn: 0,
        valueColumn: 1,
        hasHeaderRow: false,
        valueMode: .values,
        anchorRow: 0,
        anchorCol: 0
      )
      let series = ChartPreviewSeries.points(
        for: chart,
        labelFor: { _ in "Week" },
        numberFor: { address in
          address.row == 1 ? .nan : Double(address.row + 1)
        }
      )
      guard series.points.count == 2, series.points.allSatisfy({ $0.value.isFinite }) else {
        return Result(name: name, passed: false, detail: "NaN point was plotted \(series.points)")
      }
      return Result(
        name: name, passed: true, detail: "weekly \(weekly.lowerBound)...\(weekly.upperBound)")
    }

    private static func weeklyCallsLastLabel() -> Result {
      let name = "weekly calls last label"
      let names = [
        "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun",
        "Mon 2", "Tue 2", "Wed 2", "Thu 2", "Fri 2", "Sat 2", "Closing Call",
      ]
      let count = names.count
      let indexes = ChartCategoryLabelLayout.labelIndexes(count: count)
      guard indexes.last == count - 1 else {
        return Result(name: name, passed: false, detail: "last category was dropped from the axis")
      }
      let chartWidth: CGFloat = 280
      let plotMinX: CGFloat = 36
      let plotWidth = chartWidth - plotMinX
      let items = indexes.map { ChartCategoryLabelLayout.Item(index: $0, text: names[$0]) }
      let placements = ChartCategoryLabelLayout.placements(
        items: items,
        chartWidth: chartWidth,
        barCenterX: { index in
          ChartCategoryLabelLayout.barCenterX(
            index: index,
            count: count,
            plotMinX: plotMinX,
            plotWidth: plotWidth
          )
        },
        labelWidth: { ChartCategoryLabelLayout.measure($0, fontSize: 8) }
      )
      guard let last = placements.first(where: { $0.index == count - 1 }) else {
        return Result(name: name, passed: false, detail: "last label was not placed")
      }
      let center = ChartCategoryLabelLayout.barCenterX(
        index: count - 1,
        count: count,
        plotMinX: plotMinX,
        plotWidth: plotWidth
      )
      let labelWidth = ChartCategoryLabelLayout.measure(names[count - 1], fontSize: 8)
      let centeredMaxX = center + labelWidth / 2
      guard center > plotMinX, center < chartWidth else {
        return Result(
          name: name, passed: false, detail: "last bar center \(center) is off the chart")
      }
      guard centeredMaxX > chartWidth + 1 else {
        return Result(
          name: name,
          passed: false,
          detail:
            "fixture does not clip a centered label (center \(center), width \(labelWidth), chart \(chartWidth))"
        )
      }
      guard last.text == "Closing Call", last.minX >= -0.01, last.maxX <= chartWidth + 0.01 else {
        return Result(
          name: name, passed: false, detail: "last label \(last.text) \(last.minX)...\(last.maxX)")
      }
      let outside = placements.filter { $0.minX < -0.01 || $0.maxX > chartWidth + 0.01 }
      guard outside.isEmpty else {
        return Result(name: name, passed: false, detail: "label outside the chart")
      }
      return Result(
        name: name, passed: true,
        detail: "Closing Call fits; centered max \(Int(centeredMaxX.rounded()))")
    }

    private static func chartValueColors() -> Result {
      let name = "chart value colors"
      let colors = (0..<8).map { ChartMarkPalette.swatch(at: $0) }
      guard Set(colors).count == colors.count else {
        return Result(name: name, passed: false, detail: "first 8 swatches are not distinct")
      }
      let swatch = ChartMarkPalette.swatch(at: 0)
      let fallback = SheetChart.defaultSeriesColor(for: .bar)
      guard abs(swatch.red - fallback.red) < 0.001,
        abs(swatch.green - fallback.green) < 0.001,
        abs(swatch.blue - fallback.blue) < 0.001
      else {
        return Result(
          name: name, passed: false, detail: "series default drifted from the first swatch")
      }
      var chart = SheetChart(
        kind: .bar,
        dataRange: CellRange(start: .origin, end: CellAddress(row: 3, col: 1)),
        anchorRow: 6,
        anchorCol: 0
      )
      guard chart.resolvedColor(forPoint: 0) == chart.resolvedColor(forPoint: 2),
        chart.resolvedColor(forPoint: 0) == chart.resolvedSeriesColor
      else {
        return Result(name: name, passed: false, detail: "points did not share the series color")
      }
      let point = CodableColor(red: 0.9, green: 0.2, blue: 0.1, alpha: 1)
      chart.setPointColor(point, at: 1)
      guard chart.resolvedColor(forPoint: 1) == point,
        chart.resolvedColor(forPoint: 0) == chart.resolvedSeriesColor
      else {
        return Result(name: name, passed: false, detail: "point override did not stick")
      }
      chart.setPointColor(nil, at: 1)
      guard chart.pointColors[1] == nil,
        chart.resolvedColor(forPoint: 1) == chart.resolvedSeriesColor
      else {
        return Result(
          name: name, passed: false, detail: "clearing a point did not return to the series color")
      }
      let series = CodableColor(red: 0.1, green: 0.6, blue: 0.3, alpha: 1)
      chart.seriesColor = series
      chart.setPointColor(point, at: 2)
      guard chart.resolvedColor(forPoint: 0) == series, chart.resolvedColor(forPoint: 2) == point
      else {
        return Result(name: name, passed: false, detail: "series color did not replace the default")
      }
      return Result(name: name, passed: true, detail: "series color, point override, and clear")
    }

    private static func chartFrameDrag() -> Result {
      let name = "chart frame drag"
      func columnAt(_ x: CGFloat) -> Int { min(25, max(0, Int(floor(x / 80)))) }
      func rowAt(_ y: CGFloat) -> Int { min(99, max(0, Int(floor(y / 22)))) }
      let start = OnSheetChartGeometry.ChartFrameAnchor(
        anchorRow: 4, anchorCol: 0, rowSpan: 12, colSpan: 8)
      let rect = CGRect(x: 0, y: 88, width: 640, height: 264)
      let moved = OnSheetChartGeometry.anchorAfterDrag(
        start: start,
        handle: .body,
        startRect: rect,
        translation: CGSize(width: 100, height: 30),
        minimumSpan: SheetChart.minimumSpan,
        rowLimit: 100,
        columnLimit: 26,
        columnAt: columnAt,
        rowAt: rowAt
      )
      guard moved.anchorCol == 1, moved.anchorRow == 5, moved.colSpan == 8, moved.rowSpan == 12
      else {
        return Result(name: name, passed: false, detail: "move \(moved)")
      }
      let downward = SpreadsheetGridNSView.chartDragTranslation(dx: 100, dy: 30)
      guard downward.width == 100, downward.height == 30 else {
        return Result(name: name, passed: false, detail: "downward sign \(downward)")
      }
      let followed = OnSheetChartGeometry.anchorAfterDrag(
        start: start,
        handle: .body,
        startRect: rect,
        translation: downward,
        minimumSpan: SheetChart.minimumSpan,
        rowLimit: 100,
        columnLimit: 26,
        columnAt: columnAt,
        rowAt: rowAt
      )
      guard followed.anchorCol == 1, followed.anchorRow == 5, followed.rowSpan == 12 else {
        return Result(name: name, passed: false, detail: "pointer down \(followed)")
      }
      let grown = OnSheetChartGeometry.anchorAfterDrag(
        start: start,
        handle: .bottom,
        startRect: rect,
        translation: downward,
        minimumSpan: SheetChart.minimumSpan,
        rowLimit: 100,
        columnLimit: 26,
        columnAt: columnAt,
        rowAt: rowAt
      )
      guard grown.anchorRow == 4, grown.anchorCol == 0, grown.rowSpan == 14 else {
        return Result(name: name, passed: false, detail: "bottom follows \(grown)")
      }
      let loweredTop = OnSheetChartGeometry.anchorAfterDrag(
        start: start,
        handle: .top,
        startRect: rect,
        translation: downward,
        minimumSpan: SheetChart.minimumSpan,
        rowLimit: 100,
        columnLimit: 26,
        columnAt: columnAt,
        rowAt: rowAt
      )
      guard loweredTop.anchorRow == 5, loweredTop.rowSpan == 11, loweredTop.anchorCol == 0 else {
        return Result(name: name, passed: false, detail: "top follows \(loweredTop)")
      }
      let layer = CGRect(x: 28, y: 28, width: 800, height: 600)
      let atRest = CGRect(x: 100, y: 200, width: 320, height: 180)
      let scrolled = atRest.offsetBy(dx: 0, dy: -40)
      let hostAtRest = OnSheetChartGeometry.hostFrame(chartRect: atRest, layerFrame: layer)
      let hostScrolled = OnSheetChartGeometry.hostFrame(chartRect: scrolled, layerFrame: layer)
      guard hostAtRest.minY == 172, hostScrolled.minY == 132,
        hostAtRest.minY - hostScrolled.minY == 40,
        hostScrolled.minX == hostAtRest.minX
      else {
        return Result(
          name: name, passed: false, detail: "scroll host \(hostAtRest) \(hostScrolled)")
      }
      let nudged = OnSheetChartGeometry.anchorAfterDrag(
        start: start,
        handle: .body,
        startRect: rect,
        translation: CGSize(width: 40, height: 10),
        minimumSpan: SheetChart.minimumSpan,
        rowLimit: 100,
        columnLimit: 26,
        columnAt: columnAt,
        rowAt: rowAt
      )
      guard nudged == start else {
        return Result(name: name, passed: false, detail: "sub-cell move changed \(nudged)")
      }
      let wider = OnSheetChartGeometry.anchorAfterDrag(
        start: start,
        handle: .right,
        startRect: rect,
        translation: CGSize(width: 80, height: 0),
        minimumSpan: SheetChart.minimumSpan,
        rowLimit: 100,
        columnLimit: 26,
        columnAt: columnAt,
        rowAt: rowAt
      )
      guard wider.anchorCol == 0, wider.colSpan == 9, wider.rowSpan == 12 else {
        return Result(name: name, passed: false, detail: "resize right \(wider)")
      }
      let inset = OnSheetChartGeometry.anchorAfterDrag(
        start: start,
        handle: .left,
        startRect: rect,
        translation: CGSize(width: 480, height: 0),
        minimumSpan: SheetChart.minimumSpan,
        rowLimit: 100,
        columnLimit: 26,
        columnAt: columnAt,
        rowAt: rowAt
      )
      guard inset.anchorCol == 4, inset.colSpan == 4, inset.anchorRow == 4 else {
        return Result(name: name, passed: false, detail: "resize left min span \(inset)")
      }
      guard
        OnSheetChartGeometry.frameHandle(at: CGPoint(x: 320, y: 200), in: rect, thickness: 8)
          == .body,
        OnSheetChartGeometry.frameHandle(at: CGPoint(x: 2, y: 200), in: rect, thickness: 8)
          == .left,
        OnSheetChartGeometry.frameHandle(at: CGPoint(x: 638, y: 90), in: rect, thickness: 8)
          == .topRight,
        OnSheetChartGeometry.frameHandle(at: CGPoint(x: -40, y: -40), in: rect, thickness: 8) == nil
      else {
        return Result(name: name, passed: false, detail: "handle hit test")
      }
      let wide = OnSheetChartGeometry.previewHeight(colSpan: 16, rowSpan: 4, width: 320)
      let tall = OnSheetChartGeometry.previewHeight(colSpan: 4, rowSpan: 16, width: 320)
      guard tall > wide else {
        return Result(name: name, passed: false, detail: "preview tall \(tall) wide \(wide)")
      }
      return Result(name: name, passed: true, detail: "move, resize, handles, preview size")
    }

    /// Command during a drag or resize leaves the edge on the pointer. Without
    /// it, the same gesture snaps to the cell border. The chart still scrolls
    /// with its anchor, and dragging down still moves it down.
    private static func chartCommandFreePlacement() -> Result {
      let name = "chart command free placement"
      guard SpreadsheetGridNSView.chartDragUsesFreePlacement(modifierFlags: .command),
        SpreadsheetGridNSView.chartDragUsesFreePlacement(modifierFlags: [.command, .shift]),
        !SpreadsheetGridNSView.chartDragUsesFreePlacement(modifierFlags: []),
        !SpreadsheetGridNSView.chartDragUsesFreePlacement(modifierFlags: .shift),
        !SpreadsheetGridNSView.chartDragUsesFreePlacement(modifierFlags: .option),
        !SpreadsheetGridNSView.chartDragUsesFreePlacement(modifierFlags: .control)
      else {
        return Result(name: name, passed: false, detail: "modifier was not command")
      }
      func columnAt(_ x: CGFloat) -> Int { min(25, max(0, Int(floor(x / 80)))) }
      func rowAt(_ y: CGFloat) -> Int { min(99, max(0, Int(floor(y / 22)))) }
      func xForColumn(_ col: Int) -> CGFloat { CGFloat(col) * 80 }
      func yForRow(_ row: Int) -> CGFloat { CGFloat(row) * 22 }
      let start = OnSheetChartGeometry.ChartFrameAnchor(
        anchorRow: 4, anchorCol: 0, rowSpan: 12, colSpan: 8)
      let rect = CGRect(x: 0, y: 88, width: 640, height: 264)
      func drag(
        _ handle: OnSheetChartGeometry.ChartFrameHandle,
        _ translation: CGSize,
        free: Bool
      ) -> OnSheetChartGeometry.ChartFrameAnchor {
        OnSheetChartGeometry.anchorAfterDrag(
          start: start,
          handle: handle,
          startRect: rect,
          translation: translation,
          minimumSpan: SheetChart.minimumSpan,
          rowLimit: 100,
          columnLimit: 26,
          columnAt: columnAt,
          rowAt: rowAt,
          freePlacement: free,
          xForColumn: xForColumn,
          yForRow: yForRow,
          columnWidth: { _ in 80 },
          rowHeight: { _ in 22 }
        )
      }
      func placed(_ anchor: OnSheetChartGeometry.ChartFrameAnchor) -> CGRect {
        OnSheetChartGeometry.frame(
          anchorRow: anchor.anchorRow,
          anchorCol: anchor.anchorCol,
          rowSpan: anchor.rowSpan,
          colSpan: anchor.colSpan,
          rowCount: 100,
          columnCount: 26,
          originXOffset: anchor.originXOffset,
          originYOffset: anchor.originYOffset,
          endXOffset: anchor.endXOffset,
          endYOffset: anchor.endYOffset,
          xForColumn: xForColumn,
          yForRow: yForRow,
          columnWidth: { _ in 80 },
          rowHeight: { _ in 22 }
        )
      }
      let nudge = CGSize(width: 40, height: 10)
      let snappedNudge = drag(.body, nudge, free: false)
      let freedNudge = drag(.body, nudge, free: true)
      guard snappedNudge == start, placed(snappedNudge).minX == 0, placed(snappedNudge).minY == 88
      else {
        return Result(
          name: name, passed: false, detail: "sub-cell snap \(snappedNudge) \(placed(snappedNudge))"
        )
      }
      let freedRect = placed(freedNudge)
      guard freedNudge.anchorCol == 0, freedNudge.anchorRow == 4,
        freedNudge.colSpan == 8, freedNudge.rowSpan == 12,
        freedNudge.originXOffset == 40, freedNudge.originYOffset == 10,
        freedNudge.endXOffset == 40, freedNudge.endYOffset == 10,
        freedRect.minX == 40, freedRect.minY == 98,
        freedRect.width == 640, freedRect.height == 264
      else {
        return Result(name: name, passed: false, detail: "free nudge \(freedNudge) \(freedRect)")
      }
      let downward = SpreadsheetGridNSView.chartDragTranslation(dx: 100, dy: 30)
      guard downward.height > 0 else {
        return Result(name: name, passed: false, detail: "downward sign \(downward)")
      }
      let snappedMove = drag(.body, downward, free: false)
      let freedMove = drag(.body, downward, free: true)
      guard snappedMove.anchorCol == 1, snappedMove.anchorRow == 5,
        snappedMove.originXOffset == 0, snappedMove.originYOffset == 0,
        placed(snappedMove).minX == 80, placed(snappedMove).minY == 110
      else {
        return Result(
          name: name, passed: false, detail: "snap move \(snappedMove) \(placed(snappedMove))")
      }
      let freedMoveRect = placed(freedMove)
      guard freedMove.anchorCol == 1, freedMove.anchorRow == 5,
        freedMove.originXOffset == 20, freedMove.originYOffset == 8,
        freedMoveRect.minX == 100, freedMoveRect.minY == 118,
        freedMoveRect.width == 640, freedMoveRect.height == 264
      else {
        return Result(name: name, passed: false, detail: "free move \(freedMove) \(freedMoveRect)")
      }
      let snapRight = drag(.right, CGSize(width: 30, height: 0), free: false)
      let freeRight = drag(.right, CGSize(width: 30, height: 0), free: true)
      guard snapRight.colSpan == 9, snapRight.endXOffset == 0, placed(snapRight).width == 720 else {
        return Result(
          name: name, passed: false, detail: "snap resize \(snapRight) \(placed(snapRight))")
      }
      guard freeRight.anchorCol == 0, freeRight.colSpan == 8, freeRight.endXOffset == 30,
        freeRight.rowSpan == 12, placed(freeRight).width == 670, placed(freeRight).minX == 0
      else {
        return Result(
          name: name, passed: false, detail: "free resize \(freeRight) \(placed(freeRight))")
      }
      let downEdge = SpreadsheetGridNSView.chartDragTranslation(dx: 0, dy: 10)
      let freeBottom = drag(.bottom, downEdge, free: true)
      guard freeBottom.anchorRow == 4, freeBottom.rowSpan == 12, freeBottom.endYOffset == 10,
        placed(freeBottom).minY == 88, placed(freeBottom).height == 274
      else {
        return Result(
          name: name, passed: false, detail: "bottom down \(freeBottom) \(placed(freeBottom))")
      }
      let freeCorner = drag(.topLeft, CGSize(width: 50, height: 10), free: true)
      guard freeCorner.originXOffset == 50, freeCorner.originYOffset == 10,
        freeCorner.colSpan == 8, freeCorner.rowSpan == 12,
        placed(freeCorner).minX == 50, placed(freeCorner).minY == 98
      else {
        return Result(
          name: name, passed: false, detail: "corner \(freeCorner) \(placed(freeCorner))")
      }
      func widthAt(_ col: Int) -> CGFloat { col == 0 ? 50 : (col == 1 ? 100 : 80) }
      func xOf(_ col: Int) -> CGFloat {
        var x: CGFloat = 0
        for index in 0..<max(0, col) { x += widthAt(index) }
        return x
      }
      func colAt(_ x: CGFloat) -> Int {
        var index = 0
        var cursor: CGFloat = 0
        while index < 25 {
          let width = widthAt(index)
          if x < cursor + width { return index }
          cursor += width
          index += 1
        }
        return 25
      }
      let variableRect = CGRect(x: 0, y: 88, width: xOf(8), height: 264)
      let variableFree = OnSheetChartGeometry.anchorAfterDrag(
        start: start,
        handle: .body,
        startRect: variableRect,
        translation: CGSize(width: 60, height: 0),
        minimumSpan: SheetChart.minimumSpan,
        rowLimit: 100,
        columnLimit: 26,
        columnAt: colAt,
        rowAt: rowAt,
        freePlacement: true,
        xForColumn: xOf,
        yForRow: yForRow,
        columnWidth: widthAt,
        rowHeight: { _ in 22 }
      )
      let variableSnap = OnSheetChartGeometry.anchorAfterDrag(
        start: start,
        handle: .body,
        startRect: variableRect,
        translation: CGSize(width: 60, height: 0),
        minimumSpan: SheetChart.minimumSpan,
        rowLimit: 100,
        columnLimit: 26,
        columnAt: colAt,
        rowAt: rowAt,
        freePlacement: false,
        xForColumn: xOf,
        yForRow: yForRow,
        columnWidth: widthAt,
        rowHeight: { _ in 22 }
      )
      let variablePlaced = OnSheetChartGeometry.frame(
        anchorRow: variableFree.anchorRow,
        anchorCol: variableFree.anchorCol,
        rowSpan: variableFree.rowSpan,
        colSpan: variableFree.colSpan,
        rowCount: 100,
        columnCount: 26,
        originXOffset: variableFree.originXOffset,
        originYOffset: variableFree.originYOffset,
        endXOffset: variableFree.endXOffset,
        endYOffset: variableFree.endYOffset,
        xForColumn: xOf,
        yForRow: yForRow,
        columnWidth: widthAt,
        rowHeight: { _ in 22 }
      )
      guard variableFree.anchorCol == 1, variableFree.originXOffset == 10,
        variablePlaced.minX == 60, variablePlaced.width == variableRect.width,
        variableSnap.anchorCol == 1, variableSnap.originXOffset == 0
      else {
        return Result(
          name: name, passed: false,
          detail: "variable \(variableFree) snap \(variableSnap) \(variablePlaced)")
      }

      let header: CGFloat = 28
      let rowH: CGFloat = 22
      let colW: CGFloat = 80
      let frozenRows = 7
      let frozenCols = 2
      let content = CGRect(x: header, y: header, width: 960, height: 640)
      let boundaryX = header + CGFloat(frozenCols) * colW
      let boundaryY = header + CGFloat(frozenRows) * rowH
      func scrolledY(_ row: Int, scrollY: CGFloat) -> CGFloat {
        let model = CGFloat(row) * rowH
        if row < frozenRows { return header + model }
        return header + model - scrollY
      }
      func scrolledX(_ col: Int, scrollX: CGFloat) -> CGFloat {
        let model = CGFloat(col) * colW
        if col < frozenCols { return header + model }
        return header + model - scrollX
      }
      func offsetChart(scrollX: CGFloat, scrollY: CGFloat) -> CGRect {
        OnSheetChartGeometry.frame(
          anchorRow: 10,
          anchorCol: 3,
          rowSpan: 14,
          colSpan: 8,
          rowCount: 200,
          columnCount: 26,
          originXOffset: 5,
          originYOffset: 6,
          endXOffset: 5,
          endYOffset: 6,
          xForColumn: { scrolledX($0, scrollX: scrollX) },
          yForRow: { scrolledY($0, scrollY: scrollY) },
          columnWidth: { _ in colW },
          rowHeight: { _ in rowH }
        )
      }
      let rested = offsetChart(scrollX: 0, scrollY: 0)
      let scrolled = offsetChart(scrollX: 200, scrollY: 120)
      guard rested.minY == header + 10 * rowH + 6, rested.minX == header + 3 * colW + 5,
        rested.height == 14 * rowH, rested.width == 8 * colW,
        rested.minY - scrolled.minY == 120, rested.minX - scrolled.minX == 200
      else {
        return Result(name: name, passed: false, detail: "offset scroll \(rested) \(scrolled)")
      }
      let hostRest = OnSheetChartGeometry.hostFrame(chartRect: rested, layerFrame: content)
      let hostScroll = OnSheetChartGeometry.hostFrame(chartRect: scrolled, layerFrame: content)
      guard hostRest.minY - hostScroll.minY == 120, hostRest.minX - hostScroll.minX == 200 else {
        return Result(name: name, passed: false, detail: "host scroll \(hostRest) \(hostScroll)")
      }
      let underHeader = CGPoint(x: scrolled.midX, y: boundaryY - 4)
      guard scrolled.minY < boundaryY, scrolled.contains(underHeader),
        OnSheetChartGeometry.frozenPaneCovers(
          underHeader,
          contentRect: content,
          frozenColumnBoundaryX: boundaryX,
          frozenRowBoundaryY: boundaryY,
          frozenColumns: frozenCols,
          frozenRows: frozenRows
        )
      else {
        return Result(name: name, passed: false, detail: "frozen cover \(scrolled)")
      }

      var sheet = Sheet(name: "Weekly Calls")
      sheet.setCell(Cell(raw: "Week"), at: .origin)
      sheet.setCell(Cell(raw: "Calls"), at: CellAddress(row: 0, col: 1))
      var chart = SheetChart(
        kind: .bar,
        title: "Calls by Week",
        dataRange: CellRange(start: .origin, end: CellAddress(row: 4, col: 1)),
        anchorRow: 7,
        anchorCol: 0
      )
      chart.originXOffset = 12
      chart.originYOffset = 6
      chart.endXOffset = 3
      chart.endYOffset = 9
      sheet.charts = [chart]
      do {
        let data = try XLSXCodec.exportWorkbook(Workbook(sheets: [sheet]))
        let drawing =
          XLSXCodec.zipEntryString(archiveData: data, entryPath: "xl/drawings/drawing1.xml") ?? ""
        func emu(_ points: CGFloat) -> String { "\(SheetImage.emu(fromPoints: points))" }
        guard drawing.contains("<xdr:colOff>\(emu(12))</xdr:colOff>"),
          drawing.contains("<xdr:rowOff>\(emu(6))</xdr:rowOff>"),
          drawing.contains("<xdr:colOff>\(emu(3))</xdr:colOff>"),
          drawing.contains("<xdr:rowOff>\(emu(9))</xdr:rowOff>")
        else {
          return Result(name: name, passed: false, detail: "drawing offsets missing")
        }
        let imported = try XLSXCodec.importWorkbook(from: data)
        let saved = imported.sheets[0].charts.first
        guard saved?.originXOffset == 12, saved?.originYOffset == 6,
          saved?.endXOffset == 3, saved?.endYOffset == 9,
          saved?.anchorRow == 7, saved?.colSpan == 8
        else {
          return Result(
            name: name, passed: false,
            detail: "reopen offsets \(String(describing: saved?.originXOffset))")
        }
      } catch {
        return Result(name: name, passed: false, detail: error.localizedDescription)
      }
      let legacyJSON = """
        {"id":"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE","kind":"bar","title":"Old","dataRange":{"start":{"row":0,"col":0},"end":{"row":3,"col":1}},"anchorRow":1,"anchorCol":2,"rowSpan":10,"colSpan":6}
        """
      guard let legacy = try? JSONDecoder().decode(SheetChart.self, from: Data(legacyJSON.utf8)),
        legacy.originXOffset == 0, legacy.originYOffset == 0,
        legacy.endXOffset == 0, legacy.endYOffset == 0
      else {
        return Result(name: name, passed: false, detail: "legacy chart kept a free offset")
      }

      let placedSheet = sheet
      let model = MainActor.assumeIsolated { () -> Result? in
        let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [placedSheet]))
        guard let original = vm.activeSheet.charts.first else {
          return Result(name: name, passed: false, detail: "chart missing on the sheet")
        }
        let undo = UndoManager()
        vm.undoManager = undo
        vm.setChartFrame(
          id: original.id,
          anchorRow: 5,
          anchorCol: 1,
          rowSpan: 12,
          colSpan: 8,
          originXOffset: 20,
          originYOffset: 8,
          endXOffset: 20,
          endYOffset: 8,
          preservingCustomFrom: original
        )
        guard let live = vm.chart(with: original.id),
          live.anchorRow == 5, live.anchorCol == 1,
          live.originXOffset == 20, live.originYOffset == 8,
          live.endXOffset == 20, live.endYOffset == 8,
          live.frameIsCustom
        else {
          return Result(name: name, passed: false, detail: "live frame dropped the offset")
        }
        vm.commitChartFrame(id: original.id, before: original, actionName: "Move Chart")
        guard undo.canUndo else {
          return Result(name: name, passed: false, detail: "free move was not undoable")
        }
        undo.undo()
        guard vm.chart(with: original.id)?.originXOffset == 12 else {
          return Result(name: name, passed: false, detail: "undo did not restore the offset")
        }
        undo.redo()
        vm.setChartFrame(
          id: original.id,
          anchorRow: 5,
          anchorCol: 1,
          rowSpan: 12,
          colSpan: 8,
          preservingCustomFrom: original
        )
        guard let snapped = vm.chart(with: original.id),
          snapped.originXOffset == 0, snapped.endXOffset == 0,
          snapped.endYOffset == 0, snapped.anchorCol == 1
        else {
          return Result(name: name, passed: false, detail: "releasing the offset did not snap")
        }
        return nil
      }
      if let model { return model }
      return Result(
        name: name, passed: true, detail: "command frees move and resize; release snaps")
    }

    /// Weekly Calls: "Calls by Rep" scrolls with its anchor and slides under
    /// the frozen header and frozen columns. Those panes cover the chart; the
    /// chart frame itself is not clipped, so the scroll delta stays intact.
    private static func chartSlidesUnderFrozenPanes() -> Result {
      let name = "chart under frozen panes"
      let header: CGFloat = 28
      let rowH: CGFloat = 22
      let colW: CGFloat = 80
      let frozenRows = 7
      let frozenCols = 2
      let content = CGRect(x: header, y: header, width: 960, height: 640)
      let boundaryX = header + CGFloat(frozenCols) * colW
      let boundaryY = header + CGFloat(frozenRows) * rowH
      func yForRow(_ row: Int, scrollY: CGFloat) -> CGFloat {
        let model = CGFloat(row) * rowH
        if row < frozenRows { return header + model }
        return header + model - scrollY
      }
      func xForColumn(_ col: Int, scrollX: CGFloat) -> CGFloat {
        let model = CGFloat(col) * colW
        if col < frozenCols { return header + model }
        return header + model - scrollX
      }
      func chart(scrollX: CGFloat, scrollY: CGFloat) -> CGRect {
        OnSheetChartGeometry.frame(
          anchorRow: 10,
          anchorCol: 3,
          rowSpan: 14,
          colSpan: 8,
          rowCount: 200,
          columnCount: 26,
          xForColumn: { xForColumn($0, scrollX: scrollX) },
          yForRow: { yForRow($0, scrollY: scrollY) },
          columnWidth: { _ in colW },
          rowHeight: { _ in rowH }
        )
      }
      func covers(_ point: CGPoint, columns: Int = frozenCols, rows: Int = frozenRows) -> Bool {
        OnSheetChartGeometry.frozenPaneCovers(
          point,
          contentRect: content,
          frozenColumnBoundaryX: columns > 0 ? boundaryX : content.minX,
          frozenRowBoundaryY: rows > 0 ? boundaryY : content.minY,
          frozenColumns: columns,
          frozenRows: rows
        )
      }
      let rested = chart(scrollX: 0, scrollY: 0)
      guard rested.minY > boundaryY, rested.minX > boundaryX, rested.height == 14 * rowH else {
        return Result(name: name, passed: false, detail: "rest frame \(rested)")
      }
      let scrolled = chart(scrollX: 0, scrollY: 120)
      guard scrolled.minY < boundaryY, scrolled.height == rested.height else {
        return Result(name: name, passed: false, detail: "scroll under header \(scrolled)")
      }
      let layer = content
      let hostRest = OnSheetChartGeometry.hostFrame(chartRect: rested, layerFrame: layer)
      let hostScroll = OnSheetChartGeometry.hostFrame(chartRect: scrolled, layerFrame: layer)
      guard hostRest.minY - hostScroll.minY == 120, hostScroll.minX == hostRest.minX else {
        return Result(name: name, passed: false, detail: "anchor scroll \(hostRest) \(hostScroll)")
      }
      let underHeader = CGPoint(x: scrolled.midX, y: boundaryY - 4)
      let inBody = CGPoint(x: scrolled.midX, y: boundaryY + 8)
      guard scrolled.contains(underHeader), covers(underHeader),
        scrolled.contains(inBody), !covers(inBody)
      else {
        return Result(name: name, passed: false, detail: "header cover \(underHeader) \(inBody)")
      }
      let slidLeft = chart(scrollX: 200, scrollY: 0)
      let underCols = CGPoint(x: boundaryX - 4, y: slidLeft.midY)
      let rightOfCols = CGPoint(x: boundaryX + 8, y: slidLeft.midY)
      guard slidLeft.minX < boundaryX, slidLeft.height == rested.height,
        slidLeft.contains(underCols), covers(underCols),
        slidLeft.contains(rightOfCols), !covers(rightOfCols)
      else {
        return Result(name: name, passed: false, detail: "column cover \(slidLeft)")
      }
      let onDivider = CGPoint(x: scrolled.midX, y: boundaryY)
      guard covers(onDivider) else {
        return Result(name: name, passed: false, detail: "divider was left to the chart")
      }
      let panes = OnSheetChartGeometry.frozenPaneCoverRects(
        contentRect: content,
        frozenColumnBoundaryX: boundaryX,
        frozenRowBoundaryY: boundaryY,
        frozenColumns: frozenCols,
        frozenRows: frozenRows
      )
      guard panes.count == 2,
        panes[0] == CGRect(x: header, y: header, width: 960, height: boundaryY - header),
        panes[1]
          == CGRect(
            x: header, y: boundaryY, width: boundaryX - header, height: content.maxY - boundaryY)
      else {
        return Result(name: name, passed: false, detail: "cover rects \(panes)")
      }
      guard
        OnSheetChartGeometry.frozenPaneCoverRects(
          contentRect: content,
          frozenColumnBoundaryX: content.minX,
          frozenRowBoundaryY: content.minY,
          frozenColumns: 0,
          frozenRows: 0
        ).isEmpty, !covers(underHeader, columns: 0, rows: 0)
      else {
        return Result(name: name, passed: false, detail: "unfrozen sheet still covered the chart")
      }
      return Result(name: name, passed: true, detail: "header and columns cover the scrolled chart")
    }

    /// Draws Weekly Calls with "Calls by Rep" sitting on top of the frozen header
    /// and frozen columns. Those cells stay the fill color; the same cells without
    /// a freeze are covered by the chart.
    @MainActor
    private static func frozenPanesCoverChartPixels() -> Result {
      let name = "frozen panes cover chart"
      let red = CodableColor(red: 1, green: 0, blue: 0, alpha: 1)
      let green = CodableColor(red: 0, green: 1, blue: 0, alpha: 1)
      let blue = CodableColor(red: 0, green: 0, blue: 1, alpha: 1)
      func painted(_ color: CodableColor) -> Cell {
        var format = CellFormat()
        format.fillColor = color
        return Cell(raw: "", format: format)
      }
      func makeSheet(frozen: Bool) -> Sheet {
        var sheet = Sheet(
          name: "Weekly Calls",
          frozenRows: frozen ? 2 : 0,
          frozenColumns: frozen ? 1 : 0
        )
        sheet.setCell(painted(red), at: CellAddress(row: 0, col: 2))
        sheet.setCell(painted(green), at: CellAddress(row: 4, col: 0))
        sheet.setCell(painted(blue), at: CellAddress(row: 4, col: 2))
        sheet.charts = [
          SheetChart(
            kind: .bar,
            title: "Calls by Rep",
            dataRange: CellRange(start: .origin, end: CellAddress(row: 4, col: 1)),
            anchorRow: 0,
            anchorCol: 0,
            rowSpan: 12,
            colSpan: 8
          )
        ]
        return sheet
      }
      let header: CGFloat = SpreadsheetGridNSView.baseHeaderSize
      let rowH = Workbook.defaultRowHeight
      let colW = Workbook.defaultColumnWidth
      let redPoint = NSPoint(x: header + 2 * colW + colW / 2, y: header + rowH / 2)
      let greenPoint = NSPoint(x: header + colW / 2, y: header + 4 * rowH + rowH / 2)
      let bluePoint = NSPoint(x: header + 2 * colW + colW / 2, y: header + 4 * rowH + rowH / 2)

      func isRed(_ color: NSColor) -> Bool {
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return false }
        return rgb.redComponent > 0.85 && rgb.greenComponent < 0.2 && rgb.blueComponent < 0.2
      }
      func isGreen(_ color: NSColor) -> Bool {
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return false }
        return rgb.greenComponent > 0.85 && rgb.redComponent < 0.2 && rgb.blueComponent < 0.2
      }
      func isBlue(_ color: NSColor) -> Bool {
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return false }
        return rgb.blueComponent > 0.85 && rgb.redComponent < 0.2 && rgb.greenComponent < 0.2
      }
      func describe(_ color: NSColor?) -> String {
        guard let rgb = color?.usingColorSpace(.deviceRGB) else { return "nil" }
        return String(
          format: "%.2f,%.2f,%.2f", rgb.redComponent, rgb.greenComponent, rgb.blueComponent)
      }

      guard let open = snapshotGrid(sheet: makeSheet(frozen: false)),
        let frozen = snapshotGrid(sheet: makeSheet(frozen: true))
      else {
        return Result(name: name, passed: false, detail: "grid snapshot failed")
      }
      let fromTop = [true, false].first { fromTop in
        !isRed(open.color(at: redPoint, fromTop: fromTop))
          && !isGreen(open.color(at: greenPoint, fromTop: fromTop))
          && !isBlue(open.color(at: bluePoint, fromTop: fromTop))
      }
      guard let fromTop else {
        return Result(
          name: name,
          passed: false,
          detail:
            "chart did not cover the cells top \(describe(open.color(at: redPoint, fromTop: true))) \(describe(open.color(at: greenPoint, fromTop: true))) \(describe(open.color(at: bluePoint, fromTop: true))) bottom \(describe(open.color(at: redPoint, fromTop: false))) \(describe(open.color(at: greenPoint, fromTop: false))) \(describe(open.color(at: bluePoint, fromTop: false)))"
        )
      }
      let frozenRed = frozen.color(at: redPoint, fromTop: fromTop)
      let frozenGreen = frozen.color(at: greenPoint, fromTop: fromTop)
      let frozenBlue = frozen.color(at: bluePoint, fromTop: fromTop)
      guard isRed(frozenRed), isGreen(frozenGreen), !isBlue(frozenBlue) else {
        return Result(
          name: name,
          passed: false,
          detail:
            "panes red \(describe(frozenRed)) green \(describe(frozenGreen)) body \(describe(frozenBlue))"
        )
      }
      let chartAboveOverlay = frozen.chartAboveFrozenPane
      guard !chartAboveOverlay else {
        return Result(name: name, passed: false, detail: "chart layer is above the frozen pane")
      }
      return Result(
        name: name, passed: true, detail: "frozen header and columns cover Calls by Rep")
    }

    /// A scrolled row and column that start underneath the freeze must not paint
    /// over the last frozen row or the last frozen column. The cells just outside
    /// the panes stay their own color, so the pane overlay did not clear the body.
    @MainActor
    private static func scrolledCellsStayBelowFrozenPanes() -> Result {
      let name = "scrolled cells stay below frozen panes"
      let header = SpreadsheetGridNSView.baseHeaderSize
      let rowH = Workbook.defaultRowHeight
      let colW = Workbook.defaultColumnWidth
      // snapshotGrid's frame. Scroll matches ensureCellVisible against that size.
      let viewWidth: CGFloat = 900
      let viewHeight: CGFloat = 560
      let frozenRows = 2
      let frozenCols = 1
      let boundaryY = header + CGFloat(frozenRows) * rowH
      let boundaryX = header + CGFloat(frozenCols) * colW
      // Bottom-aligning row 39 / column O leaves row 18 and column F straddling.
      let scrollRow = 39
      let scrollCol = 14
      let scrollY = header + CGFloat(scrollRow + 1) * rowH - viewHeight
      let scrollX = header + CGFloat(scrollCol + 1) * colW - viewWidth
      let straddlingRow = 17
      let straddlingCol = 5
      let rowBelow = 20

      func viewY(_ row: Int) -> CGFloat {
        if row < frozenRows { return header + CGFloat(row) * rowH }
        return header + CGFloat(row) * rowH - scrollY
      }
      func viewX(_ col: Int) -> CGFloat {
        if col < frozenCols { return header + CGFloat(col) * colW }
        return header + CGFloat(col) * colW - scrollX
      }
      func paint(_ sheet: inout Sheet, row: Int, col: Int, rgb: (CGFloat, CGFloat, CGFloat)) {
        var format = CellFormat()
        format.fillColor = CodableColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        sheet.setCell(Cell(raw: "", format: format), at: CellAddress(row: row, col: col))
      }

      var sheet = Sheet(name: "Frozen edge", frozenRows: frozenRows, frozenColumns: frozenCols)
      for row in 0..<frozenRows {
        for col in 0...8 {
          paint(&sheet, row: row, col: col, rgb: (1, 0, 0))
        }
      }
      for col in 0...8 {
        paint(&sheet, row: straddlingRow, col: col, rgb: (0, 0, 1))
      }
      let rowJustBelow = straddlingRow + 1
      for col in 0...8 {
        paint(&sheet, row: rowJustBelow, col: col, rgb: (0, 0, 1))
      }
      paint(&sheet, row: rowBelow, col: 0, rgb: (0, 1, 0))
      paint(&sheet, row: rowBelow, col: straddlingCol, rgb: (0, 0, 1))

      let stableRed = NSPoint(x: viewX(6) + colW / 2, y: viewY(0) + rowH / 2)
      let lastFrozenRow = NSPoint(x: viewX(6) + colW / 2, y: boundaryY - 6)
      // Mid-cell of the first row fully below the freeze, clear of the divider.
      let scrolledBelow = NSPoint(x: viewX(6) + colW / 2, y: viewY(rowJustBelow) + rowH / 2)
      let cornerOverlap = NSPoint(x: boundaryX - 4, y: boundaryY - 6)
      let lastFrozenColumn = NSPoint(x: boundaryX - 4, y: viewY(rowBelow) + rowH / 2)
      let scrolledBeside = NSPoint(
        x: viewX(straddlingCol) + colW / 2, y: viewY(rowBelow) + rowH / 2)

      func isRed(_ color: NSColor) -> Bool {
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return false }
        return rgb.redComponent > 0.85 && rgb.greenComponent < 0.2 && rgb.blueComponent < 0.2
      }
      func isGreen(_ color: NSColor) -> Bool {
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return false }
        return rgb.greenComponent > 0.85 && rgb.redComponent < 0.2 && rgb.blueComponent < 0.2
      }
      func isBlue(_ color: NSColor) -> Bool {
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return false }
        return rgb.blueComponent > 0.85 && rgb.redComponent < 0.2 && rgb.greenComponent < 0.2
      }
      func describe(_ color: NSColor) -> String {
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return "nil" }
        return String(
          format: "%.2f,%.2f,%.2f", rgb.redComponent, rgb.greenComponent, rgb.blueComponent)
      }

      guard
        let snap = snapshotGrid(
          sheet: sheet,
          prepare: { grid in
            grid.viewModel?.select(CellAddress(row: scrollRow, col: scrollCol))
            grid.scrollSelectionIntoView()
          })
      else {
        return Result(name: name, passed: false, detail: "grid snapshot failed")
      }
      let fromTop = [true, false].first { isRed(snap.color(at: stableRed, fromTop: $0)) }
      guard let fromTop else {
        return Result(name: name, passed: false, detail: "frozen row 1 was not red")
      }
      let rowColor = snap.color(at: lastFrozenRow, fromTop: fromTop)
      let belowColor = snap.color(at: scrolledBelow, fromTop: fromTop)
      let cornerColor = snap.color(at: cornerOverlap, fromTop: fromTop)
      let columnColor = snap.color(at: lastFrozenColumn, fromTop: fromTop)
      let besideColor = snap.color(at: scrolledBeside, fromTop: fromTop)
      guard isRed(rowColor), isRed(cornerColor), isGreen(columnColor), isBlue(belowColor),
        isBlue(besideColor)
      else {
        return Result(
          name: name,
          passed: false,
          detail:
            "row \(describe(rowColor)) corner \(describe(cornerColor)) column \(describe(columnColor)) below \(describe(belowColor)) beside \(describe(besideColor))"
        )
      }
      return Result(
        name: name, passed: true, detail: "last frozen row and column stay above the scrolled cells"
      )
    }

    /// A merged range paints as one cell. Interior grid lines disappear, the border
    /// around the outside stays, and unmerge draws those interior lines again.
    /// The same rule holds while the merge is selected, crosses a freeze, or scrolls.
    @MainActor
    private static func mergedCellsHideInteriorGridLines() -> Result {
      let name = "merged cells hide interior grid"
      let header = SpreadsheetGridNSView.baseHeaderSize
      let rowH = Workbook.defaultRowHeight
      let colW = Workbook.defaultColumnWidth
      // snapshotGrid's frame. Scroll math below matches ensureCellVisible against it.
      let viewHeight: CGFloat = 560
      let vertical = CGPoint(x: 1, y: 0)
      let horizontal = CGPoint(x: 0, y: 1)

      func fail(_ detail: String) -> Result {
        Result(name: name, passed: false, detail: detail)
      }
      func paintRed(sheet: inout Sheet, rows: ClosedRange<Int>, cols: ClosedRange<Int>) {
        var format = CellFormat()
        format.fillColor = CodableColor(red: 1, green: 0, blue: 0, alpha: 1)
        let cell = Cell(raw: "", format: format)
        for row in rows {
          for col in cols {
            sheet.setCell(cell, at: CellAddress(row: row, col: col))
          }
        }
      }
      func isRed(_ color: NSColor) -> Bool {
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return false }
        return rgb.redComponent > 0.85 && rgb.greenComponent < 0.2 && rgb.blueComponent < 0.2
      }
      func channelDelta(_ a: NSColor, _ b: NSColor) -> CGFloat {
        guard let lhs = a.usingColorSpace(.deviceRGB), let rhs = b.usingColorSpace(.deviceRGB)
        else {
          return 1
        }
        return abs(lhs.redComponent - rhs.redComponent)
          + abs(lhs.greenComponent - rhs.greenComponent)
          + abs(lhs.blueComponent - rhs.blueComponent)
      }
      func viewY(_ row: Int, scroll: CGFloat, frozenRows: Int) -> CGFloat {
        if row < frozenRows { return header + CGFloat(row) * rowH }
        return header + CGFloat(row) * rowH - scroll
      }
      func viewX(_ col: Int, scroll: CGFloat, frozenCols: Int) -> CGFloat {
        if col < frozenCols { return header + CGFloat(col) * colW }
        return header + CGFloat(col) * colW - scroll
      }
      func boundaryX(_ col: Int, scroll: CGFloat = 0, frozenCols: Int = 0) -> CGFloat {
        viewX(col, scroll: scroll, frozenCols: frozenCols)
      }
      func boundaryY(_ row: Int, scroll: CGFloat = 0, frozenRows: Int = 0) -> CGFloat {
        viewY(row, scroll: scroll, frozenRows: frozenRows)
      }
      func midX(_ col: Int, scroll: CGFloat = 0, frozenCols: Int = 0) -> CGFloat {
        viewX(col, scroll: scroll, frozenCols: frozenCols) + colW / 2
      }
      func midY(_ row: Int, scroll: CGFloat = 0, frozenRows: Int = 0) -> CGFloat {
        viewY(row, scroll: scroll, frozenRows: frozenRows) + rowH / 2
      }

      /// How strongly a hairline shows across `point`, compared with the cell 8pt to the side.
      /// `wantsRed` fails closed when the sample landed on the wrong surface.
      func lineStrength(
        _ snap: GridSnapshot,
        at point: NSPoint,
        perpendicular: CGPoint,
        fromTop: Bool,
        wantsRed: Bool = true
      ) -> CGFloat? {
        let fillPoint = NSPoint(
          x: point.x + perpendicular.x * 8,
          y: point.y + perpendicular.y * 8
        )
        let fill = snap.color(at: fillPoint, fromTop: fromTop)
        guard isRed(fill) == wantsRed else { return nil }
        var strongest: CGFloat = 0
        for step in stride(from: CGFloat(-1), through: CGFloat(1), by: CGFloat(0.5)) {
          let sample = snap.color(
            at: NSPoint(x: point.x + perpendicular.x * step, y: point.y + perpendicular.y * step),
            fromTop: fromTop
          )
          strongest = max(strongest, channelDelta(fill, sample))
        }
        return strongest
      }

      func orientation(of snap: GridSnapshot, redAt point: NSPoint) -> Bool? {
        [true, false].first { isRed(snap.color(at: point, fromTop: $0)) }
      }
      func hidesLine(_ strength: CGFloat, comparedTo control: CGFloat) -> Bool {
        strength < 0.03 || (strength < control * 0.4 && control - strength > 0.02)
      }
      func showsLine(_ strength: CGFloat, comparedTo control: CGFloat) -> Bool {
        strength > 0.04 && strength > control * 0.5
      }

      // Rows 1...6 and cols 1...5 are red. Only rows 2...5, cols 2...4 are merged,
      // so the outside border has the same fill on both sides as an interior line.
      var block = Sheet(name: "Merge")
      paintRed(sheet: &block, rows: 1...6, cols: 1...5)
      block.mergedRanges = [
        CellRange(
          start: CellAddress(row: 2, col: 2),
          end: CellAddress(row: 5, col: 4)
        )
      ]
      let interiorVertical = NSPoint(x: boundaryX(4), y: midY(4))
      let interiorHorizontal = NSPoint(x: midX(3), y: boundaryY(4))
      let outsideVertical = NSPoint(x: boundaryX(4), y: midY(1))
      let outerLeft = NSPoint(x: boundaryX(2), y: midY(4))
      let outerBottom = NSPoint(x: midX(3), y: boundaryY(6))
      let fillProbe = NSPoint(x: midX(3), y: midY(4))

      guard let mergedSnap = snapshotGrid(sheet: block),
        let fromTop = orientation(of: mergedSnap, redAt: fillProbe)
      else {
        return fail("grid snapshot failed or the merged fill was not red")
      }
      guard
        let control = lineStrength(
          mergedSnap, at: outsideVertical, perpendicular: vertical, fromTop: fromTop),
        let interiorV = lineStrength(
          mergedSnap, at: interiorVertical, perpendicular: vertical, fromTop: fromTop),
        let interiorH = lineStrength(
          mergedSnap, at: interiorHorizontal, perpendicular: horizontal, fromTop: fromTop),
        let leftBorder = lineStrength(
          mergedSnap, at: outerLeft, perpendicular: vertical, fromTop: fromTop),
        let bottomBorder = lineStrength(
          mergedSnap, at: outerBottom, perpendicular: horizontal, fromTop: fromTop)
      else {
        return fail("merged fill missed a sample point")
      }
      guard control > 0.04 else {
        return fail(String(format: "control grid line was not visible (%.3f)", control))
      }
      guard hidesLine(interiorV, comparedTo: control), hidesLine(interiorH, comparedTo: control)
      else {
        return fail(
          String(
            format: "interior lines stayed vertical %.3f horizontal %.3f control %.3f", interiorV,
            interiorH, control))
      }
      guard showsLine(leftBorder, comparedTo: control), showsLine(bottomBorder, comparedTo: control)
      else {
        return fail(
          String(
            format: "outer border dropped left %.3f bottom %.3f control %.3f", leftBorder,
            bottomBorder, control))
      }

      let unmergeModel = SpreadsheetViewModel(workbook: Workbook(sheets: [block]))
      unmergeModel.select(CellAddress(row: 2, col: 2))
      let selectedSpan = unmergeModel.selectionRange.normalized
      guard selectedSpan.minRow == 2, selectedSpan.maxRow == 5, selectedSpan.minCol == 2,
        selectedSpan.maxCol == 4
      else {
        return fail("selection did not cover the merge")
      }
      guard
        let selectedSnap = snapshotGrid(
          sheet: block,
          prepare: { grid in
            grid.viewModel?.select(CellAddress(row: 2, col: 2))
          }), let selectedTop = orientation(of: selectedSnap, redAt: fillProbe)
      else {
        return fail("selected merge snapshot failed")
      }
      guard
        let selectedInteriorV = lineStrength(
          selectedSnap, at: interiorVertical, perpendicular: vertical, fromTop: selectedTop),
        let selectedInteriorH = lineStrength(
          selectedSnap, at: interiorHorizontal, perpendicular: horizontal, fromTop: selectedTop)
      else {
        return fail("selection changed the merged fill")
      }
      guard hidesLine(selectedInteriorV, comparedTo: control),
        hidesLine(selectedInteriorH, comparedTo: control)
      else {
        return fail(
          String(
            format: "selection redrew interior lines vertical %.3f horizontal %.3f",
            selectedInteriorV, selectedInteriorH))
      }

      unmergeModel.unmergeSelection()
      guard unmergeModel.activeSheet.mergedRanges.isEmpty else {
        return fail("unmerge left a range")
      }
      guard let openSnap = snapshotGrid(sheet: unmergeModel.activeSheet),
        let openTop = orientation(of: openSnap, redAt: fillProbe),
        let opened = lineStrength(
          openSnap, at: interiorVertical, perpendicular: vertical, fromTop: openTop),
        let openedRow = lineStrength(
          openSnap, at: interiorHorizontal, perpendicular: horizontal, fromTop: openTop)
      else {
        return fail("unmerged snapshot failed")
      }
      guard showsLine(opened, comparedTo: control), showsLine(openedRow, comparedTo: control) else {
        return fail(
          String(
            format: "unmerge did not restore lines vertical %.3f horizontal %.3f", opened, openedRow
          ))
      }

      // Frozen band keeps its own red merge. A second merge crosses the freeze into
      // the body; its anchor has no fill, so both panes stay the sheet background.
      // A third sits below the fold so scrolling moves the holes with the cells.
      // The red merges have to keep that fill in the frozen header and after scroll.
      var frozenSheet = Sheet(name: "Frozen merge", frozenRows: 2, frozenColumns: 1)
      paintRed(sheet: &frozenSheet, rows: 0...1, cols: 3...7)
      paintRed(sheet: &frozenSheet, rows: 21...25, cols: 2...6)
      frozenSheet.mergedRanges = [
        CellRange(start: CellAddress(row: 0, col: 0), end: CellAddress(row: 5, col: 2)),
        CellRange(start: CellAddress(row: 0, col: 4), end: CellAddress(row: 1, col: 6)),
        CellRange(start: CellAddress(row: 22, col: 3), end: CellAddress(row: 25, col: 5)),
      ]
      let scrollRow = 26
      let scroll = (header + CGFloat(scrollRow + 1) * rowH) - viewHeight
      let frozenFill = NSPoint(x: midX(5), y: midY(0, frozenRows: 2))
      let frozenInteriorV = NSPoint(x: boundaryX(6), y: midY(0, frozenRows: 2))
      let frozenInteriorH = NSPoint(x: midX(5), y: boundaryY(1, frozenRows: 2))
      let frozenOuter = NSPoint(x: boundaryX(4), y: midY(0, frozenRows: 2))
      let crossFrozen = NSPoint(x: boundaryX(2), y: midY(0, frozenRows: 2))
      let crossFrozenRow = NSPoint(x: midX(1), y: boundaryY(1, frozenRows: 2))
      let crossControl = NSPoint(x: boundaryX(9), y: midY(0, frozenRows: 2))
      let crossBody = NSPoint(x: boundaryX(2), y: midY(5, scroll: scroll, frozenRows: 2))
      let crossBodyLine = NSPoint(x: boundaryX(2), y: midY(7, scroll: scroll, frozenRows: 2))
      let scrolledInteriorV = NSPoint(x: boundaryX(5), y: midY(23, scroll: scroll, frozenRows: 2))
      let scrolledInteriorH = NSPoint(x: midX(4), y: boundaryY(24, scroll: scroll, frozenRows: 2))
      let scrolledOutside = NSPoint(x: boundaryX(5), y: midY(21, scroll: scroll, frozenRows: 2))

      guard
        let frozenSnap = snapshotGrid(
          sheet: frozenSheet,
          prepare: { grid in
            grid.viewModel?.select(CellAddress(row: scrollRow, col: 8))
            grid.scrollSelectionIntoView()
          })
      else {
        return fail("frozen snapshot failed")
      }
      // Same bitmap axis as the unfrozen snapshot. Re-detecting it from the frozen
      // header is ambiguous: the flipped pixel sits in the scrolled red merge.
      guard isRed(frozenSnap.color(at: frozenFill, fromTop: fromTop)) else {
        return fail("frozen merge fill was not red")
      }
      var missedFill: [String] = []
      func take(
        _ name: String,
        _ point: NSPoint,
        _ perpendicular: CGPoint,
        wantsRed: Bool = true
      ) -> CGFloat? {
        let strength = lineStrength(
          frozenSnap,
          at: point,
          perpendicular: perpendicular,
          fromTop: fromTop,
          wantsRed: wantsRed
        )
        if strength == nil {
          let fillPoint = NSPoint(
            x: point.x + perpendicular.x * 8,
            y: point.y + perpendicular.y * 8
          )
          let color = frozenSnap.color(at: fillPoint, fromTop: fromTop)
          let rgb = color.usingColorSpace(.deviceRGB)
          let detail =
            rgb.map {
              String(format: "%.2f,%.2f,%.2f", $0.redComponent, $0.greenComponent, $0.blueComponent)
            } ?? "nil"
          missedFill.append("\(name) \(detail)")
        }
        return strength
      }
      let frozenV = take("frozen vertical", frozenInteriorV, vertical)
      let frozenH = take("frozen horizontal", frozenInteriorH, horizontal)
      let frozenEdge = take("frozen edge", frozenOuter, vertical)
      let crossV = take("cross vertical", crossFrozen, vertical, wantsRed: false)
      let crossH = take("cross horizontal", crossFrozenRow, horizontal, wantsRed: false)
      let crossLine = take("cross line", crossControl, vertical, wantsRed: false)
      let crossScrolled = take("cross scrolled", crossBody, vertical, wantsRed: false)
      let crossScrolledLine = take("cross scrolled line", crossBodyLine, vertical, wantsRed: false)
      let scrolledV = take("scrolled vertical", scrolledInteriorV, vertical)
      let scrolledH = take("scrolled horizontal", scrolledInteriorH, horizontal)
      let scrolledLine = take("scrolled line", scrolledOutside, vertical)
      guard let frozenV, let frozenH, let frozenEdge,
        let crossV, let crossH, let crossLine,
        let crossScrolled, let crossScrolledLine,
        let scrolledV, let scrolledH, let scrolledLine
      else {
        return fail(
          "frozen or scrolled sample missed its fill (\(missedFill.joined(separator: "; ")))")
      }
      guard showsLine(crossLine, comparedTo: crossLine),
        showsLine(crossScrolledLine, comparedTo: crossScrolledLine),
        showsLine(scrolledLine, comparedTo: scrolledLine),
        showsLine(frozenEdge, comparedTo: frozenEdge)
      else {
        return fail(
          String(
            format:
              "line outside a merge was not visible frozen %.3f body %.3f scroll %.3f edge %.3f",
            crossLine, crossScrolledLine, scrolledLine, frozenEdge))
      }
      guard hidesLine(frozenV, comparedTo: frozenEdge), hidesLine(frozenH, comparedTo: frozenEdge),
        hidesLine(crossV, comparedTo: crossLine), hidesLine(crossH, comparedTo: crossLine),
        hidesLine(crossScrolled, comparedTo: crossScrolledLine),
        hidesLine(scrolledV, comparedTo: scrolledLine),
        hidesLine(scrolledH, comparedTo: scrolledLine)
      else {
        return fail(
          String(
            format:
              "freeze/scroll interior stayed band %.3f %.3f cross %.3f %.3f %.3f scrolled %.3f %.3f",
            frozenV, frozenH, crossV, crossH, crossScrolled, scrolledV, scrolledH))
      }
      return Result(
        name: name, passed: true,
        detail: "interior lines drop out; the outside border and unmerge put them back")
    }

    private struct GridSnapshot {
      var image: NSBitmapImageRep
      var pointScale: CGFloat
      var chartAboveFrozenPane: Bool

      func color(at point: NSPoint, fromTop: Bool) -> NSColor {
        let x = Int((point.x * pointScale).rounded(.down))
        let yFromTop = Int((point.y * pointScale).rounded(.down))
        let y = fromTop ? yFromTop : image.pixelsHigh - 1 - yFromTop
        let px = min(image.pixelsWide - 1, max(0, x))
        let py = min(image.pixelsHigh - 1, max(0, y))
        return image.colorAt(x: px, y: py) ?? .clear
      }
    }

    @MainActor
    private static func snapshotGrid(
      sheet: Sheet,
      prepare: ((SpreadsheetGridNSView) -> Void)? = nil
    ) -> GridSnapshot? {
      let frame = NSRect(x: 0, y: 0, width: 900, height: 560)
      let grid = SpreadsheetGridNSView(frame: frame)
      let window = NSWindow(
        contentRect: frame,
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
      )
      window.isReleasedWhenClosed = false
      window.contentView = grid
      window.setFrameOrigin(NSPoint(x: -4000, y: -4000))
      window.orderFrontRegardless()
      window.setContentSize(frame.size)
      grid.frame = frame
      grid.viewModel = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
      grid.layoutSubtreeIfNeeded()
      prepare?(grid)
      grid.needsDisplay = true
      window.displayIfNeeded()
      RunLoop.current.run(until: Date().addingTimeInterval(0.15))
      grid.layoutSubtreeIfNeeded()
      // A focus update during the run above can redraw a slice of a frozen pane.
      // Capture a full draw so that slice is not the bitmap we score. Idle scroll pictures are
      // dropped first: while they show, the grid's own layer has only the headers.
      grid.testingPaintCellsLive()
      grid.needsDisplay = true
      grid.display()

      let scale = max(1, window.backingScaleFactor)
      let pixelsWide = Int((grid.bounds.width * scale).rounded())
      let pixelsHigh = Int((grid.bounds.height * scale).rounded())
      guard
        let rep = NSBitmapImageRep(
          bitmapDataPlanes: nil,
          pixelsWide: pixelsWide,
          pixelsHigh: pixelsHigh,
          bitsPerSample: 8,
          samplesPerPixel: 4,
          hasAlpha: true,
          isPlanar: false,
          colorSpaceName: .deviceRGB,
          bytesPerRow: 0,
          bitsPerPixel: 0
        ), let gfx = NSGraphicsContext(bitmapImageRep: rep)
      else {
        window.orderOut(nil)
        window.close()
        return nil
      }
      rep.size = grid.bounds.size
      NSGraphicsContext.saveGraphicsState()
      NSGraphicsContext.current = gfx
      let cg = gfx.cgContext
      cg.translateBy(x: 0, y: CGFloat(pixelsHigh))
      cg.scaleBy(x: scale, y: -scale)
      // The grid paints into its own frame and copies it to the screen; render(in:) does not
      // see that copy off screen and clears what is under the grid. Render the layers, then
      // put the grid's frame where its own layer drew nothing.
      grid.layer?.render(in: cg)
      if let frame = grid.testingFrameImage() {
        cg.setBlendMode(.destinationOver)
        cg.draw(frame, in: CGRect(origin: .zero, size: grid.bounds.size))
        cg.setBlendMode(.normal)
        // Charts (z 5) and the frozen-pane overlay (z 6) are views of their own that
        // render(in:) misses; draw them above the frame in layer order. Other views, such as
        // the selection, already came through render(in:).
        let views = grid.subviews
          .filter { [5, 6].contains($0.layer?.zPosition ?? -1) }
          .filter { !$0.isHidden && $0.frame.width > 1 && $0.frame.height > 1 }
          .sorted { ($0.layer?.zPosition ?? 0) < ($1.layer?.zPosition ?? 0) }
        for view in views {
          guard let drawn = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            continue
          }
          view.cacheDisplay(in: view.bounds, to: drawn)
          guard let image = drawn.cgImage else { continue }
          cg.saveGState()
          cg.translateBy(x: view.frame.minX, y: view.frame.maxY)
          cg.scaleBy(x: 1, y: -1)
          cg.draw(image, in: CGRect(origin: .zero, size: view.frame.size))
          cg.restoreGState()
        }
      }
      NSGraphicsContext.restoreGraphicsState()
      let image = rep
      let chartLayer = grid.subviews.first { ($0.layer?.zPosition ?? -1) == 5 }
      let pane = grid.subviews.first { ($0.layer?.zPosition ?? -1) == 6 }
      let chartAbove =
        pane == nil || pane?.isHidden == true
        || (chartLayer?.layer?.zPosition ?? 0) > (pane?.layer?.zPosition ?? 0)
      window.orderOut(nil)
      window.close()
      return GridSnapshot(image: image, pointScale: scale, chartAboveFrozenPane: chartAbove)
    }

    @MainActor
    private static func chartMoveResizeAndColorRoundTrip() -> Result {
      let name = "chart move color round-trip"
      var sheet = Sheet(name: "Weekly Calls")
      sheet.setCell(Cell(raw: "Week"), at: .origin)
      sheet.setCell(Cell(raw: "Calls"), at: CellAddress(row: 0, col: 1))
      for index in 1...4 {
        sheet.setCell(Cell(raw: "Week \(index)"), at: CellAddress(row: index, col: 0))
        sheet.setCell(Cell(raw: "\(index * 3)"), at: CellAddress(row: index, col: 1))
      }
      let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
      let range = CellRange(start: .origin, end: CellAddress(row: 4, col: 1))
      let inserted = vm.insertChart(
        SheetChart(
          kind: .bar,
          title: "Calls by Week",
          dataRange: range,
          categoryColumn: 0,
          valueColumn: 1,
          anchorRow: 7,
          anchorCol: 0
        )
      )
      guard inserted, let original = vm.activeSheet.charts.first else {
        return Result(name: name, passed: false, detail: "chart was not inserted")
      }
      vm.setChartFrame(
        id: original.id,
        anchorRow: 0,
        anchorCol: 0,
        rowSpan: 6,
        colSpan: 5,
        preservingCustomFrom: original
      )
      vm.commitChartFrame(id: original.id, before: original, actionName: "Move Chart")
      let series = CodableColor(red: 0.12, green: 0.55, blue: 0.32, alpha: 1)
      let point = CodableColor(red: 0.86, green: 0.24, blue: 0.18, alpha: 1)
      vm.updateChartContent(id: original.id, actionName: "Chart Color") {
        $0.seriesColor = series
        $0.setPointColor(point, at: 1)
        $0.showsLegend = true
        $0.showsGridlines = false
        $0.categoryAxisTitle = "Week"
        $0.valueAxisTitle = "Calls"
        $0.title = "Pipeline"
      }
      guard let live = vm.chart(with: original.id) else {
        return Result(name: name, passed: false, detail: "chart disappeared")
      }
      guard live.anchorRow == 0, live.anchorCol == 0, live.rowSpan == 6, live.colSpan == 5,
        live.frameIsCustom
      else {
        return Result(
          name: name, passed: false,
          detail: "frame \(live.anchorRow),\(live.anchorCol) \(live.colSpan)×\(live.rowSpan)")
      }
      guard live.placementDescription == "At A1 · 5×6" else {
        return Result(name: name, passed: false, detail: live.placementDescription)
      }
      guard live.seriesColor == series,
        live.resolvedColor(forPoint: 1) == point,
        live.resolvedColor(forPoint: 0) == series,
        live.showsLegend, !live.showsGridlines,
        live.categoryAxisTitle == "Week",
        live.valueAxisTitle == "Calls",
        live.title == "Pipeline"
      else {
        return Result(name: name, passed: false, detail: "format did not apply")
      }
      vm.updateChartContent(id: original.id, actionName: "Chart Color") {
        $0.setPointColor(nil, at: 1)
      }
      guard vm.chart(with: original.id)?.resolvedColor(forPoint: 1) == series else {
        return Result(name: name, passed: false, detail: "cleared point kept its color")
      }
      vm.updateChartContent(id: original.id, actionName: "Chart Color") {
        $0.setPointColor(point, at: 1)
      }
      do {
        let data = try XLSXCodec.exportWorkbook(vm.workbook)
        let chartXML =
          XLSXCodec.zipEntryString(archiveData: data, entryPath: "xl/charts/chart1.xml") ?? ""
        guard chartXML.contains("srgbClr val=\"\(XLSXCodec.rgbHex(series))\""),
          chartXML.contains("srgbClr val=\"\(XLSXCodec.rgbHex(point))\""),
          chartXML.contains("<c:dPt>"),
          chartXML.contains("legendPos val=\"b\""),
          chartXML.contains(">Week<"),
          chartXML.contains(">Calls<"),
          chartXML.contains(">Pipeline<"),
          !chartXML.contains("<c:majorGridlines")
        else {
          return Result(name: name, passed: false, detail: "excel chart xml missed format")
        }
        let imported = try XLSXCodec.importWorkbook(from: data)
        let saved = imported.sheets[0].charts.first
        guard let saved else {
          return Result(name: name, passed: false, detail: "import dropped the chart")
        }
        guard saved.anchorRow == 0, saved.anchorCol == 0, saved.rowSpan == 6, saved.colSpan == 5,
          saved.frameIsCustom, saved.seriesColor == series, saved.pointColors[1] == point,
          saved.showsLegend, !saved.showsGridlines,
          saved.categoryAxisTitle == "Week", saved.valueAxisTitle == "Calls",
          saved.title == "Pipeline"
        else {
          return Result(
            name: name, passed: false,
            detail: "reopen \(saved.anchorRow),\(saved.anchorCol) legend \(saved.showsLegend)")
        }
        let kept = saved.positionedUnderData()
        guard kept.anchorRow == 0, kept.anchorCol == 0 else {
          return Result(name: name, passed: false, detail: "custom frame was moved under the data")
        }
      } catch {
        return Result(name: name, passed: false, detail: error.localizedDescription)
      }
      let legacyJSON = """
        {"id":"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE","kind":"line","title":"Old","dataRange":{"start":{"row":0,"col":0},"end":{"row":3,"col":1}},"anchorRow":1,"anchorCol":2,"rowSpan":10,"colSpan":6}
        """
      guard let decoded = try? JSONDecoder().decode(SheetChart.self, from: Data(legacyJSON.utf8))
      else {
        return Result(name: name, passed: false, detail: "legacy chart json did not decode")
      }
      guard decoded.seriesColor == nil, decoded.pointColors.isEmpty, !decoded.showsLegend,
        decoded.showsGridlines, decoded.categoryAxisTitle.isEmpty, !decoded.frameIsCustom,
        decoded.anchorRow == 1, decoded.rowSpan == 10
      else {
        return Result(
          name: name, passed: false,
          detail: "legacy defaults \(decoded.showsGridlines) custom \(decoded.frameIsCustom)")
      }
      return Result(
        name: name, passed: true, detail: "frame and colors reopen; legacy json still decodes")
    }

    @MainActor
    private static func selectionSizedInsert() -> Result {
      let name = "selection sized insert"

      guard
        SpreadsheetViewModel.structureInsertTitle(
          count: 1, singular: "Column", plural: "Columns", placement: "Left")
          == "Insert Column Left",
        SpreadsheetViewModel.structureInsertTitle(
          count: 3, singular: "Column", plural: "Columns", placement: "Right")
          == "Insert 3 Columns Right",
        SpreadsheetViewModel.structureInsertTitle(
          count: 3, singular: "Row", plural: "Rows", placement: "Above")
          == "Insert 3 Rows Above",
        SpreadsheetViewModel.structureInsertTitle(
          count: 4, singular: "Row", plural: "Rows", placement: "Below")
          == "Insert 4 Rows Below"
      else {
        return Result(name: name, passed: false, detail: "menu title wording")
      }

      func raw(_ vm: SpreadsheetViewModel, _ row: Int, _ col: Int) -> String {
        vm.activeSheet.cell(at: CellAddress(row: row, col: col)).raw
      }

      do {
        var sheet = Sheet(name: "Cols")
        sheet.setCell(Cell(raw: "left"), at: CellAddress(row: 0, col: 1))
        sheet.setCell(Cell(raw: "sel"), at: CellAddress(row: 0, col: 2))
        sheet.setCell(Cell(raw: "right"), at: CellAddress(row: 0, col: 5))
        let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
        vm.selectColumns(from: 2, to: 4)
        guard vm.columnInsertCount == 3, vm.rowInsertCount == 1 else {
          return Result(
            name: name, passed: false,
            detail: "header columns count \(vm.columnInsertCount) rows \(vm.rowInsertCount)")
        }
        guard vm.insertColumnLeftTitle == "Insert 3 Columns Left",
          vm.insertColumnRightTitle == "Insert 3 Columns Right",
          vm.insertRowAboveTitle == "Insert Row Above"
        else {
          return Result(name: name, passed: false, detail: "header column menu titles")
        }
        vm.insertColumnsLeft()
        guard raw(vm, 0, 1) == "left", raw(vm, 0, 2).isEmpty, raw(vm, 0, 5) == "sel",
          raw(vm, 0, 8) == "right"
        else {
          return Result(
            name: name, passed: false, detail: "insert 3 columns left shifted \(raw(vm, 0, 5))")
        }
      }

      do {
        var sheet = Sheet(name: "ColsRight")
        sheet.setCell(Cell(raw: "sel"), at: CellAddress(row: 0, col: 4))
        sheet.setCell(Cell(raw: "after"), at: CellAddress(row: 0, col: 7))
        let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
        vm.selectColumns(from: 4, to: 6)
        vm.insertColumnsRight()
        let selected = vm.selectionRange.normalized
        guard raw(vm, 0, 4) == "sel", raw(vm, 0, 7).isEmpty, raw(vm, 0, 10) == "after" else {
          return Result(
            name: name, passed: false, detail: "insert 3 columns right did not open a gap of 3")
        }
        guard selected.minCol == 7, selected.maxCol == 9, vm.selectionAxis == .column else {
          return Result(
            name: name, passed: false,
            detail: "insert right selection \(selected.minCol)-\(selected.maxCol)")
        }
      }

      do {
        var sheet = Sheet(name: "Rows")
        sheet.setCell(Cell(raw: "above"), at: CellAddress(row: 1, col: 0))
        sheet.setCell(Cell(raw: "sel"), at: CellAddress(row: 2, col: 0))
        sheet.setCell(Cell(raw: "below"), at: CellAddress(row: 5, col: 0))
        let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
        vm.selectRows(from: 2, to: 4)
        guard vm.rowInsertCount == 3, vm.columnInsertCount == 1,
          vm.insertRowAboveTitle == "Insert 3 Rows Above",
          vm.insertRowBelowTitle == "Insert 3 Rows Below",
          vm.insertColumnLeftTitle == "Insert Column Left"
        else {
          return Result(name: name, passed: false, detail: "header row counts/titles")
        }
        vm.insertRowsAbove()
        guard raw(vm, 1, 0) == "above", raw(vm, 2, 0).isEmpty, raw(vm, 5, 0) == "sel",
          raw(vm, 8, 0) == "below"
        else {
          return Result(name: name, passed: false, detail: "insert 3 rows above")
        }
      }

      do {
        var sheet = Sheet(name: "RowsBelow")
        sheet.setCell(Cell(raw: "sel"), at: CellAddress(row: 2, col: 0))
        sheet.setCell(Cell(raw: "after"), at: CellAddress(row: 5, col: 0))
        let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
        vm.selectRows(from: 2, to: 4)
        vm.insertRowsBelow()
        guard raw(vm, 2, 0) == "sel", raw(vm, 5, 0).isEmpty, raw(vm, 8, 0) == "after" else {
          return Result(name: name, passed: false, detail: "insert 3 rows below")
        }
        let selected = vm.selectionRange.normalized
        guard selected.minRow == 2, selected.maxRow == 4 else {
          return Result(name: name, passed: false, detail: "row below selection moved")
        }
      }

      do {
        var sheet = Sheet(name: "Rect")
        sheet.setCell(Cell(raw: "keep"), at: CellAddress(row: 0, col: 1))
        sheet.setCell(Cell(raw: "body"), at: CellAddress(row: 1, col: 2))
        let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
        vm.selectRange(from: CellAddress(row: 1, col: 2), to: CellAddress(row: 4, col: 4))
        guard vm.selectionAxis == .cells, vm.rowInsertCount == 4, vm.columnInsertCount == 3 else {
          return Result(
            name: name, passed: false,
            detail: "rectangle counts rows \(vm.rowInsertCount) cols \(vm.columnInsertCount)")
        }
        guard vm.insertRowAboveTitle == "Insert 4 Rows Above",
          vm.insertColumnLeftTitle == "Insert 3 Columns Left"
        else {
          return Result(name: name, passed: false, detail: "rectangle menu titles")
        }
        vm.insertRowsAbove()
        guard raw(vm, 0, 1) == "keep", raw(vm, 5, 2) == "body", raw(vm, 1, 2).isEmpty else {
          return Result(
            name: name, passed: false, detail: "rectangle row insert used \(raw(vm, 5, 2))")
        }
      }

      do {
        var sheet = Sheet(name: "RectCols")
        sheet.setCell(Cell(raw: "keep"), at: CellAddress(row: 1, col: 1))
        sheet.setCell(Cell(raw: "body"), at: CellAddress(row: 1, col: 2))
        let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
        vm.selectRange(from: CellAddress(row: 1, col: 2), to: CellAddress(row: 4, col: 4))
        vm.insertColumnsLeft()
        guard raw(vm, 1, 1) == "keep", raw(vm, 1, 5) == "body", raw(vm, 1, 2).isEmpty else {
          return Result(name: name, passed: false, detail: "rectangle column insert")
        }
        vm.selectRange(from: CellAddress(row: 1, col: 2), to: CellAddress(row: 4, col: 4))
        vm.insertColumnsRight()
        let selected = vm.selectionRange.normalized
        guard selected.minRow == 1, selected.maxRow == 4, selected.minCol == 5, selected.maxCol == 7
        else {
          return Result(name: name, passed: false, detail: "rectangle insert right selection")
        }
      }

      do {
        var sheet = Sheet(name: "One")
        sheet.setCell(Cell(raw: "only"), at: CellAddress(row: 3, col: 3))
        let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
        vm.select(CellAddress(row: 3, col: 3))
        guard vm.rowInsertCount == 1, vm.columnInsertCount == 1,
          vm.insertRowAboveTitle == "Insert Row Above",
          vm.insertColumnRightTitle == "Insert Column Right"
        else {
          return Result(name: name, passed: false, detail: "single cell labels")
        }
        vm.insertColumnsLeft()
        guard raw(vm, 3, 4) == "only", raw(vm, 3, 3).isEmpty else {
          return Result(
            name: name, passed: false, detail: "single cell inserted more than one column")
        }
      }

      do {
        var sheet = Sheet(name: "Gaps")
        sheet.setCell(Cell(raw: "b"), at: CellAddress(row: 0, col: 1))
        sheet.setCell(Cell(raw: "gap"), at: CellAddress(row: 0, col: 2))
        sheet.setCell(Cell(raw: "d"), at: CellAddress(row: 0, col: 3))
        let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
        vm.selectColumn(1)
        vm.commandClickColumn(3)
        vm.commandClickColumn(5)
        guard vm.columnInsertCount == 3, vm.insertColumnLeftTitle == "Insert 3 Columns Left" else {
          return Result(
            name: name, passed: false, detail: "disjoint columns counted \(vm.columnInsertCount)")
        }
        vm.insertColumnsLeft()
        guard raw(vm, 0, 1).isEmpty, raw(vm, 0, 4) == "b", raw(vm, 0, 5) == "gap",
          raw(vm, 0, 6) == "d"
        else {
          return Result(name: name, passed: false, detail: "disjoint insert count was not 3")
        }
      }

      do {
        let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [Sheet(name: "Command")]))
        let a1 = CellAddress(row: 0, col: 0)
        let b2 = CellAddress(row: 1, col: 1)
        let c3 = CellAddress(row: 2, col: 2)
        vm.selectRange(from: a1, to: c3)
        vm.commandClickCell(b2)
        guard !vm.isAddressSelected(b2), vm.isAddressSelected(a1), vm.isAddressSelected(c3) else {
          return Result(
            name: name, passed: false,
            detail: "command-click did not unhighlight a cell in a block")
        }
        let d4 = CellAddress(row: 3, col: 3)
        vm.selectRange(from: a1, to: d4)
        vm.commandClickCell(b2)
        vm.extendCommandDeselect(to: c3)
        vm.endCommandDeselect()
        guard !vm.isAddressSelected(b2), !vm.isAddressSelected(c3),
          !vm.isAddressSelected(CellAddress(row: 1, col: 2)), vm.isAddressSelected(a1),
          vm.isAddressSelected(d4)
        else {
          return Result(
            name: name, passed: false, detail: "command-drag did not unhighlight the block")
        }
        vm.select(a1)
        vm.commandClickCell(a1)
        vm.extendCommandDeselect(to: b2)
        vm.endCommandDeselect()
        guard vm.isAddressSelected(a1) else {
          return Result(
            name: name, passed: false, detail: "command-click emptied the selection")
        }
        vm.selectColumns(from: 1, to: 3)
        vm.commandClickColumn(2)
        guard !vm.isColumnInSelection(2), vm.isColumnInSelection(1), vm.isColumnInSelection(3)
        else {
          return Result(
            name: name, passed: false, detail: "command-click did not drop a column in a block")
        }
        vm.selectRange(from: a1, to: d4)
        vm.commandClickRow(1)
        guard !vm.isRowInSelection(1), vm.isRowInSelection(0), vm.isRowInSelection(2) else {
          return Result(
            name: name, passed: false, detail: "command-click did not drop a row from a block")
        }
        vm.selectColumn(1)
        vm.commandClickColumn(1)
        guard vm.isColumnInSelection(1) else {
          return Result(
            name: name, passed: false, detail: "command-click emptied the column selection")
        }
      }

      do {
        var sheet = Sheet(name: "Edge")
        let last = Workbook.defaultColumnCount - 1
        sheet.setCell(Cell(raw: "end"), at: CellAddress(row: 0, col: last - 1))
        let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
        vm.selectColumns(from: last - 1, to: last)
        let before = vm.activeSheet.effectiveColumnCount
        guard vm.columnInsertCount == 2 else {
          return Result(
            name: name, passed: false, detail: "edge selection count \(vm.columnInsertCount)")
        }
        vm.insertColumnsRight()
        guard vm.activeSheet.effectiveColumnCount == before + 2 else {
          return Result(
            name: name, passed: false,
            detail: "edge insert grew by \(vm.activeSheet.effectiveColumnCount - before)")
        }
        guard raw(vm, 0, last - 1) == "end" else {
          return Result(name: name, passed: false, detail: "edge insert moved the selected column")
        }
      }

      return Result(name: name, passed: true, detail: "rows and columns match the selection")
    }

    /// Freeze keeps every row or column through the far edge of the selection.
    @MainActor
    private static func freezeThroughSelection() -> Result {
      let name = "freeze through selection"

      do {
        let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [Sheet(name: "Rows")]))
        vm.selectRows(from: 0, to: 2)
        guard vm.freezeRowsTitle == "Freeze up to row 3",
          vm.freezeColumnsTitle == "Freeze up to column A"
        else {
          return Result(
            name: name, passed: false,
            detail: "rows 1–3 titles \(vm.freezeRowsTitle) / \(vm.freezeColumnsTitle)")
        }
        guard vm.freezeRowsAtSelection(),
          vm.activeSheet.frozenRows == 3,
          vm.activeSheet.frozenColumns == 0
        else {
          return Result(
            name: name, passed: false, detail: "rows 1–3 froze \(vm.activeSheet.frozenRows)")
        }
        guard vm.freezeColumnsAtSelection(),
          vm.activeSheet.frozenColumns == 1,
          vm.activeSheet.frozenRows == 3
        else {
          return Result(
            name: name, passed: false,
            detail: "row selection columns froze \(vm.activeSheet.frozenColumns)")
        }
      }

      do {
        let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [Sheet(name: "Cols")]))
        vm.selectColumns(from: 0, to: 2)
        guard vm.freezeColumnsTitle == "Freeze up to column C",
          vm.freezeRowsTitle == "Freeze up to row 1"
        else {
          return Result(
            name: name, passed: false,
            detail: "columns A–C titles \(vm.freezeColumnsTitle) / \(vm.freezeRowsTitle)")
        }
        guard vm.freezeColumnsAtSelection(),
          vm.activeSheet.frozenColumns == 3,
          vm.activeSheet.frozenRows == 0
        else {
          return Result(
            name: name, passed: false, detail: "columns A–C froze \(vm.activeSheet.frozenColumns)")
        }
        guard vm.freezeRowsAtSelection(),
          vm.activeSheet.frozenRows == 1,
          vm.activeSheet.frozenColumns == 3
        else {
          return Result(
            name: name, passed: false,
            detail: "column selection rows froze \(vm.activeSheet.frozenRows)")
        }
      }

      do {
        let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [Sheet(name: "Below")]))
        vm.selectRows(from: 4, to: 6)
        guard vm.freezeRowsTitle == "Freeze up to row 7" else {
          return Result(name: name, passed: false, detail: "rows 5–7 title \(vm.freezeRowsTitle)")
        }
        guard vm.freezeRowsAtSelection(), vm.activeSheet.frozenRows == 7 else {
          return Result(
            name: name, passed: false, detail: "rows 5–7 froze \(vm.activeSheet.frozenRows)")
        }
      }

      do {
        let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [Sheet(name: "Right")]))
        vm.selectColumns(from: 2, to: 4)
        guard vm.freezeColumnsTitle == "Freeze up to column E" else {
          return Result(
            name: name, passed: false, detail: "columns C–E title \(vm.freezeColumnsTitle)")
        }
        guard vm.freezeColumnsAtSelection(), vm.activeSheet.frozenColumns == 5 else {
          return Result(
            name: name, passed: false, detail: "columns C–E froze \(vm.activeSheet.frozenColumns)")
        }
      }

      do {
        let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [Sheet(name: "Block")]))
        vm.selectRange(from: CellAddress(row: 4, col: 1), to: CellAddress(row: 7, col: 3))
        guard vm.freezeRowsTitle == "Freeze up to row 8",
          vm.freezeColumnsTitle == "Freeze up to column D"
        else {
          return Result(
            name: name, passed: false,
            detail: "block titles \(vm.freezeRowsTitle) / \(vm.freezeColumnsTitle)")
        }
        guard vm.freezeRowsAtSelection(),
          vm.activeSheet.frozenRows == 8,
          vm.activeSheet.frozenColumns == 0
        else {
          return Result(
            name: name, passed: false, detail: "block rows froze \(vm.activeSheet.frozenRows)")
        }
        guard vm.freezeColumnsAtSelection(),
          vm.activeSheet.frozenColumns == 4,
          vm.activeSheet.frozenRows == 8
        else {
          return Result(
            name: name, passed: false,
            detail:
              "block columns froze \(vm.activeSheet.frozenColumns) rows \(vm.activeSheet.frozenRows)"
          )
        }
      }

      do {
        let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [Sheet(name: "Reverse")]))
        vm.selectRange(from: CellAddress(row: 7, col: 3), to: CellAddress(row: 4, col: 1))
        guard vm.freezeRowsTitle == "Freeze up to row 8",
          vm.freezeColumnsTitle == "Freeze up to column D"
        else {
          return Result(
            name: name, passed: false,
            detail: "reverse titles \(vm.freezeRowsTitle) / \(vm.freezeColumnsTitle)")
        }
        vm.selectRows(from: 2, to: 0)
        guard vm.freezeRowsTitle == "Freeze up to row 3" else {
          return Result(
            name: name, passed: false, detail: "upward rows title \(vm.freezeRowsTitle)")
        }
        vm.selectColumns(from: 2, to: 0)
        guard vm.freezeColumnsTitle == "Freeze up to column C" else {
          return Result(
            name: name, passed: false, detail: "leftward columns title \(vm.freezeColumnsTitle)")
        }
      }

      return Result(
        name: name, passed: true, detail: "freeze follows the bottom row and right column")
    }

    private static func legacyChartLandsUnderData() -> Result {
      let name = "legacy chart lands under data"
      let range = CellRange(
        start: CellAddress(row: 2, col: 0),
        end: CellAddress(row: 8, col: 5)
      )
      let covering = SheetChart(
        kind: .bar,
        title: "Calls by Rep",
        dataRange: range,
        categoryColumn: 0,
        valueColumn: 1,
        hasHeaderRow: true,
        valueMode: .values,
        anchorRow: 0,
        anchorCol: 0
      )
      let placed = covering.positionedUnderData()
      guard placed.anchorRow == 10, placed.anchorCol == 0, placed.id == covering.id else {
        return Result(
          name: name, passed: false, detail: "moved to \(placed.anchorRow),\(placed.anchorCol)")
      }
      let already = SheetChart(
        id: covering.id,
        kind: .bar,
        title: "Calls by Rep",
        dataRange: range,
        categoryColumn: 0,
        valueColumn: 1,
        anchorRow: 10,
        anchorCol: 0,
        rowSpan: 12,
        colSpan: 8
      )
      let kept = already.positionedUnderData()
      guard kept == already else {
        return Result(
          name: name, passed: false,
          detail: "anchored chart moved to \(kept.anchorRow),\(kept.anchorCol)")
      }
      var sheet = Sheet(name: "Weekly Calls")
      sheet.charts = [covering]
      do {
        let data = try XLSXCodec.exportWorkbook(Workbook(sheets: [sheet]))
        let imported = try XLSXCodec.importWorkbook(from: data)
        let chart = imported.sheets[0].charts.first
        guard chart?.anchorRow == 10, chart?.anchorCol == 0, chart?.title == "Calls by Rep" else {
          return Result(
            name: name, passed: false, detail: "import kept \(String(describing: chart?.anchorRow))"
          )
        }
      } catch {
        return Result(name: name, passed: false, detail: error.localizedDescription)
      }
      return Result(name: name, passed: true, detail: "covering chart opens under A3:F9")
    }

    private static func cfFillTextContrast() -> Result {
      let name = "cf fill text contrast"
      let yellow = CodableColor(red: 1, green: 0.953, blue: 0.804, alpha: 1)
      let dark = CodableColor(red: 0.12, green: 0.18, blue: 0.42, alpha: 1)
      guard CodableColor.contrastingText(on: yellow).relativeLuminance < 0.2,
        CodableColor.contrastingText(on: dark).relativeLuminance > 0.8
      else {
        return Result(name: name, passed: false, detail: "luminance threshold missed the palette")
      }

      let stops = [
        ColorScaleStop(
          type: .min, value: nil,
          color: CodableColor(red: 0.992, green: 0.886, blue: 0.882, alpha: 1)),
        ColorScaleStop(type: .percentile, value: 50, color: yellow),
        ColorScaleStop(
          type: .max, value: nil,
          color: CodableColor(red: 0.847, green: 0.953, blue: 0.863, alpha: 1)),
      ]
      let scale = ConditionalFormatRule(
        range: CellRange(start: CellAddress(row: 3, col: 4), end: CellAddress(row: 8, col: 4)),
        predicate: .colorScale(stops),
        style: ConditionalFormatStyle()
      )
      let values = [0.41, 0.37, 0.44, 0.29, 0.38, 0.33]
      let lightPaint = ConditionalFormatEvaluator.resolvedPaint(
        at: CellAddress(row: 3, col: 4),
        base: nil,
        rules: [scale],
        value: .number(0.41),
        displayString: "0.41",
        numberFormat: nil,
        numericValuesInRange: { _ in values },
        evaluateFormula: { _, _, _ in .blank }
      )
      guard let lightText = lightPaint.format?.textColor, lightText.relativeLuminance < 0.25 else {
        return Result(
          name: name, passed: false,
          detail: "scale text \(String(describing: lightPaint.format?.textColor))")
      }

      var whiteBase = CellFormat()
      whiteBase.textColor = CodableColor(red: 1, green: 1, blue: 1, alpha: 1)
      let darkRule = ConditionalFormatRule(
        range: CellRange(start: .origin, end: .origin),
        predicate: .greaterThan(0),
        style: ConditionalFormatStyle(fillColor: dark)
      )
      let darkPaint = ConditionalFormatEvaluator.resolvedPaint(
        at: .origin,
        base: whiteBase,
        rules: [darkRule],
        value: .number(5),
        displayString: "5",
        numberFormat: nil,
        numericValuesInRange: { _ in [] },
        evaluateFormula: { _, _, _ in .blank }
      )
      guard let darkText = darkPaint.format?.textColor, darkText.relativeLuminance > 0.8 else {
        return Result(
          name: name, passed: false,
          detail: "dark fill text \(String(describing: darkPaint.format?.textColor))")
      }

      let chosen = CodableColor(red: 0.45, green: 0.12, blue: 0.12, alpha: 1)
      let keptRule = ConditionalFormatRule(
        range: CellRange(start: .origin, end: .origin),
        predicate: .greaterThan(0),
        style: ConditionalFormatStyle(textColor: chosen, fillColor: yellow)
      )
      let keptPaint = ConditionalFormatEvaluator.resolvedPaint(
        at: .origin,
        base: nil,
        rules: [keptRule],
        value: .number(5),
        displayString: "5",
        numberFormat: nil,
        numericValuesInRange: { _ in [] },
        evaluateFormula: { _, _, _ in .blank }
      )
      guard let keptText = keptPaint.format?.textColor, abs(keptText.red - chosen.red) < 0.01 else {
        return Result(
          name: name, passed: false,
          detail: "rule text was replaced \(String(describing: keptPaint.format?.textColor))")
      }
      return Result(name: name, passed: true, detail: "dark on light scale, light on dark fill")
    }

    private static func formulaFunctionPicker() -> Result {
      let name = "formula function picker"
      let groups = FormulaFunctionCatalog.groups(matching: "")
      let listed = groups.flatMap { $0.entries.map(\.name) }
      let implemented = Set(FormulaFunctions.all)
      let listedSet = Set(listed)
      if listedSet != implemented || listed.count != implemented.count {
        let missing = implemented.subtracting(listedSet).sorted()
        let extra = listedSet.subtracting(implemented).sorted()
        return Result(
          name: name,
          passed: false,
          detail:
            "catalog missing \(missing.joined(separator: ", ")) extra \(extra.joined(separator: ", "))"
        )
      }
      let titles = groups.map(\.kind.title)
      if titles != ["Math", "Statistical", "Logical", "Text", "Lookup", "Date & Time", "Financial"]
      {
        return Result(name: name, passed: false, detail: "groups \(titles.joined(separator: ", "))")
      }

      for group in groups {
        for entry in group.entries {
          if entry.kind != group.kind {
            return Result(name: name, passed: false, detail: "\(entry.name) kind")
          }
          guard let insertion = FormulaFunctionCatalog.insertion(for: entry.name) else {
            return Result(name: name, passed: false, detail: "no insertion for \(entry.name)")
          }
          if insertion.text != "=\(entry.name)()" || insertion.signatureLine != entry.signatureLine
          {
            return Result(
              name: name, passed: false, detail: "\(entry.name) insertion \(insertion.text)")
          }
          if insertion.signatureLine.isEmpty || insertion.signatureLine.contains("\n") {
            return Result(name: name, passed: false, detail: "\(entry.name) argument line")
          }
          let ns = insertion.text as NSString
          let caret = insertion.caretUTF16
          if caret <= 0 || caret >= ns.length
            || ns.character(at: caret - 1) != UInt16(UnicodeScalar("(").value)
            || ns.character(at: caret) != UInt16(UnicodeScalar(")").value)
          {
            return Result(
              name: name, passed: false, detail: "\(entry.name) caret \(caret) in \(insertion.text)"
            )
          }
          let value = evalFormula(insertion.text, cells: [:])
          if case .error(.name) = value {
            return Result(name: name, passed: false, detail: "\(entry.name) does not calculate")
          }
          if case .error(.error) = value {
            return Result(name: name, passed: false, detail: "\(entry.name) did not parse")
          }
        }
      }

      let sumNames = Set(
        FormulaFunctionCatalog.groups(matching: "sum").flatMap { $0.entries.map(\.name) })
      if sumNames != ["SUM", "SUMIF", "SUMIFS", "SUMPRODUCT", "SUMSQ"] {
        return Result(name: name, passed: false, detail: "sum search \(sumNames.sorted())")
      }
      let lookup = Set(
        FormulaFunctionCatalog.groups(matching: "xLoOkUp").flatMap { $0.entries.map(\.name) })
      if lookup != ["XLOOKUP"] {
        return Result(name: name, passed: false, detail: "lookup search \(lookup.sorted())")
      }
      if !FormulaFunctionCatalog.groups(matching: "notafunction").isEmpty {
        return Result(name: name, passed: false, detail: "unknown query returned functions")
      }
      if FormulaFunctionCatalog.insertion(for: "SUMIFZ") != nil {
        return Result(name: name, passed: false, detail: "inserted an unknown function")
      }
      if !FormulaFunctionListKeys.shouldClose(
        keyCode: FormulaFunctionListKeys.escapeKeyCode, modifierFlags: [])
        || FormulaFunctionListKeys.shouldClose(keyCode: 36, modifierFlags: [])
        || FormulaFunctionListKeys.shouldClose(
          keyCode: FormulaFunctionListKeys.escapeKeyCode, modifierFlags: .command)
      {
        return Result(name: name, passed: false, detail: "escape check failed")
      }

      let placed = MainActor.assumeIsolated { () -> String in
        let viewModel = SpreadsheetViewModel(workbook: Workbook(sheets: [Sheet(name: "Sheet1")]))
        viewModel.setCellValue("12", at: .origin)
        viewModel.insertFormulaFunction("ROUND")
        guard viewModel.isEditing, viewModel.formulaBarText == "=ROUND()",
          viewModel.editText == "=ROUND()"
        else {
          return "bar \(viewModel.formulaBarText) editing \(viewModel.isEditing)"
        }
        guard viewModel.formulaCaretUTF16 == 7, viewModel.formulaCaretToken == 1 else {
          return "caret \(viewModel.formulaCaretUTF16) token \(viewModel.formulaCaretToken)"
        }
        guard viewModel.formulaArgumentHint == "ROUND(number, [num_digits])" else {
          return "hint \(viewModel.formulaArgumentHint ?? "")"
        }
        viewModel.insertFormulaFunction("NOPE")
        guard viewModel.formulaBarText == "=ROUND()", viewModel.formulaCaretToken == 1 else {
          return "unknown function changed the bar"
        }
        viewModel.commitEdit()
        guard !viewModel.isEditing,
          viewModel.formulaArgumentHint == nil,
          viewModel.activeSheet.cell(at: .origin).raw == "=ROUND()"
        else {
          return "commit \(viewModel.activeSheet.cell(at: .origin).raw)"
        }
        viewModel.insertFormulaFunction("abs")
        guard viewModel.formulaBarText == "=ABS()",
          viewModel.formulaCaretUTF16 == 5,
          viewModel.formulaArgumentHint == "ABS(number)"
        else {
          return "abs \(viewModel.formulaBarText) \(viewModel.formulaArgumentHint ?? "")"
        }
        return ""
      }
      if !placed.isEmpty {
        return Result(name: name, passed: false, detail: placed)
      }
      return Result(
        name: name,
        passed: true,
        detail: "\(listed.count) functions, grouped, caret inside parentheses"
      )
    }

    /// Guards SUMIF, VLOOKUP, COUNTIFS UNIQUE, spell-check formula display, and SUMPRODUCT boolean hits.
    private static func formulaEvalRegressionGate() -> Result {
      let name = "formula eval regression gate"
      let aggregateCells: [CellAddress: String] = [
        CellAddress(row: 0, col: 0): "10",
        CellAddress(row: 1, col: 0): "20",
        CellAddress(row: 2, col: 0): "30",
      ]
      let sumif = evalFormula("=SUMIF(A1:A3,\">15\")", cells: aggregateCells)
      guard case .number(let sumifTotal) = sumif, abs(sumifTotal - 50) < 0.000_001 else {
        return Result(
          name: name,
          passed: false,
          detail: "SUMIF got \(sumif.displayString) expected 50"
        )
      }

      let lookupCells: [CellAddress: String] = [
        CellAddress(row: 0, col: 0): "10",
        CellAddress(row: 1, col: 0): "20",
        CellAddress(row: 2, col: 0): "30",
        CellAddress(row: 0, col: 1): "a",
        CellAddress(row: 1, col: 1): "b",
        CellAddress(row: 2, col: 1): "c",
      ]
      let vlookup = evalFormula("=VLOOKUP(20,A1:B3,2,FALSE)", cells: lookupCells)
      guard case .string(let hit) = vlookup, hit == "b" else {
        return Result(
          name: name,
          passed: false,
          detail: "VLOOKUP got \(vlookup.displayString) expected b"
        )
      }

      var countifsCells: [CellAddress: String] = [:]
      countifsCells[CellAddress(row: 5, col: 0)] = "k"
      for row in 10..<30 {
        countifsCells[CellAddress(row: row, col: 0)] = row < 15 ? "k" : "z"
        if row < 15 {
          countifsCells[CellAddress(row: row, col: 2)] = "k"
        } else {
          countifsCells[CellAddress(row: row, col: 2)] = "=1/0"
        }
        countifsCells[CellAddress(row: row, col: 11)] = "UNIQUE"
      }
      let countifs = evalFormula(
        "=COUNTIFS($C$11:$C$29,$A6,$L$11:$L$29,\"UNIQUE\")",
        cells: countifsCells
      )
      guard case .number(let uniqueCount) = countifs, uniqueCount == 5 else {
        return Result(
          name: name,
          passed: false,
          detail: "COUNTIFS UNIQUE got \(countifs.displayString) expected 5"
        )
      }

      var spellSheet = Sheet(name: "Sheet1")
      spellSheet.setCell(Cell(raw: "recieve"), at: .origin)
      spellSheet.setCell(Cell(raw: "=A1"), at: CellAddress(row: 0, col: 1))
      let spellEngine = FormulaEngine()
      spellEngine.rebuild(workbook: Workbook(sheets: [spellSheet]), recalculate: true)
      let displayed = spellEngine.displayString(
        at: CellAddress(row: 0, col: 1),
        sheet: spellSheet,
        format: nil
      )
      guard displayed == "recieve" else {
        return Result(name: name, passed: false, detail: "spell formula result \(displayed)")
      }

      var january = Sheet(name: "January")
      for row in 110...115 {
        january.setCell(Cell(raw: "agent-1"), at: CellAddress(row: row, col: 2))
        january.setCell(Cell(raw: "Yes"), at: CellAddress(row: row, col: 17))
        january.setCell(Cell(raw: "3"), at: CellAddress(row: row, col: 18))
        january.setCell(Cell(raw: "1"), at: CellAddress(row: row, col: 1))
      }
      var ytd = Sheet(name: "YTD Summary")
      ytd.setCell(Cell(raw: "agent-1"), at: CellAddress(row: 4, col: 0))
      let kpiSumProduct = """
        =SUMPRODUCT((January!$C$110:$C$115=$A5)*(January!$R$110:$R$115="Yes")*(January!$S$110:$S$115<>"")*((January!$S$110:$S$115-January!$B$110:$B$115)>=0)*((January!$S$110:$S$115-January!$B$110:$B$115)<=60))
        """
      let multiArg = """
        =SUMPRODUCT(--(January!$C$110:$C$115=$A5),--(January!$R$110:$R$115="Yes"),--(January!$S$110:$S$115<>""),--((January!$S$110:$S$115-January!$B$110:$B$115)>=0))
        """
      ytd.setCell(Cell(raw: kpiSumProduct), at: CellAddress(row: 4, col: 4))
      ytd.setCell(Cell(raw: multiArg), at: CellAddress(row: 5, col: 4))
      let gateEngine = FormulaEngine()
      gateEngine.rebuild(
        workbook: Workbook(sheets: [january, ytd], activeSheetIndex: 1), recalculate: false)
      _ = gateEngine.recalculateEntireWorkbookInSheetWaves(
        Workbook(sheets: [january, ytd], activeSheetIndex: 1),
        profile: true
      )
      let hits = gateEngine.lastWorkbookRecalcProfile?.sumproductBooleanHits ?? 0
      guard hits >= 2 else {
        return Result(
          name: name, passed: false, detail: "sumproductBooleanHits \(hits) expected >= 2")
      }

      var config = Sheet(name: "Config")
      config.setCell(Cell(raw: "agent-1"), at: CellAddress(row: 0, col: 0))
      config.setCell(Cell(raw: "Agent One"), at: CellAddress(row: 0, col: 1))
      var jan = Sheet(name: "January")
      jan.setCell(Cell(raw: ""), at: CellAddress(row: 109, col: 2))
      jan.setCell(Cell(raw: "agent-1"), at: CellAddress(row: 110, col: 2))
      jan.setCell(
        Cell(raw: "=IF(C110=\"\",\"\",IFERROR(VLOOKUP(C110,Config!$A:$B,2,0),\"?\"))"),
        at: CellAddress(row: 109, col: 5)
      )
      jan.setCell(
        Cell(raw: "=IF(C111=\"\",\"\",IFERROR(VLOOKUP(C111,Config!$A:$B,2,0),\"?\"))"),
        at: CellAddress(row: 110, col: 5)
      )
      let ifWorkbook = Workbook(sheets: [config, jan], activeSheetIndex: 1)
      let ifEngine = FormulaEngine()
      ifEngine.rebuild(workbook: ifWorkbook, recalculate: false)
      _ = ifEngine.recalculateEntireWorkbookInSheetWaves(ifWorkbook, profile: true)
      let blankDisplay = ifEngine.displayString(
        at: CellAddress(row: 109, col: 5),
        sheet: jan,
        format: nil
      )
      let filledDisplay = ifEngine.displayString(
        at: CellAddress(row: 110, col: 5),
        sheet: jan,
        format: nil
      )
      guard blankDisplay.isEmpty, filledDisplay == "Agent One" else {
        return Result(
          name: name,
          passed: false,
          detail: "IF blank guard blank=\(blankDisplay) filled=\(filledDisplay)"
        )
      }
      let ifBlankHits = ifEngine.lastWorkbookRecalcProfile?.ifBlankEqualityFastHits ?? 0
      guard ifBlankHits >= 2 else {
        return Result(
          name: name, passed: false, detail: "ifBlankEqualityFastHits \(ifBlankHits) expected >= 2")
      }

      var idxCells: [CellAddress: String] = [:]
      idxCells[CellAddress(row: 5, col: 0)] = "k"
      for row in 10..<20 {
        idxCells[CellAddress(row: row, col: 0)] = "k"
        idxCells[CellAddress(row: row, col: 2)] = "k"
      }
      let idxFormula = "=COUNTIFS($C$11:$C$19,$A6,$C$11:$C$19,\"k\")"
      idxCells[CellAddress(row: 5, col: 1)] = idxFormula
      idxCells[CellAddress(row: 5, col: 2)] = idxFormula
      var idxSheet = Sheet(name: "Sheet1")
      for (address, raw) in idxCells {
        idxSheet.setCell(Cell(raw: raw), at: address)
      }
      let idxWorkbook = Workbook(sheets: [idxSheet])
      let idxEngine = FormulaEngine()
      idxEngine.rebuild(workbook: idxWorkbook, recalculate: false)
      _ = idxEngine.recalculateEntireWorkbookInSheetWaves(idxWorkbook, profile: true)
      guard let idxProfile = idxEngine.lastWorkbookRecalcProfile else {
        return Result(name: name, passed: false, detail: "COUNTIFS index profile missing")
      }
      guard idxProfile.countifsHistogramIndexBuilds >= 1, idxProfile.countifsHistogramIndexHits >= 1
      else {
        return Result(
          name: name,
          passed: false,
          detail: String(
            format: "COUNTIFS idxBuild %d idxHit %d",
            idxProfile.countifsHistogramIndexBuilds,
            idxProfile.countifsHistogramIndexHits
          )
        )
      }

      let iferr = evalFormula(
        "=IFERROR(VLOOKUP(\"missing\",Config!$A:$B,2,FALSE),\"?\")",
        cells: [
          CellAddress(row: 0, col: 0): "ok",
          CellAddress(row: 0, col: 1): "hit",
        ]
      )
      guard case .string(let iferrText) = iferr, iferrText == "?" else {
        return Result(
          name: name, passed: false, detail: "IFERROR VLOOKUP fast got \(iferr.displayString)")
      }

      return Result(
        name: name, passed: true,
        detail: "SUMIF VLOOKUP COUNTIFS spell SUMPRODUCT boolean IFblank idxHit")
    }

    /// KPI-style `SUMPRODUCT(--(Month!C=$A5),--(R="Yes"),…)` must increment `sumproductBooleanHits`.
    private static func sumproductBooleanFastPathSelfCheck() -> Result {
      let name = "SUMPRODUCT boolean fast-path counters"
      var january = Sheet(name: "January")
      for row in 110...115 {
        january.setCell(Cell(raw: "agent-1"), at: CellAddress(row: row, col: 2))
        january.setCell(Cell(raw: "Yes"), at: CellAddress(row: row, col: 17))
        january.setCell(Cell(raw: "3"), at: CellAddress(row: row, col: 18))
        january.setCell(Cell(raw: "1"), at: CellAddress(row: row, col: 1))
      }
      var ytd = Sheet(name: "YTD Summary")
      ytd.setCell(Cell(raw: "agent-1"), at: CellAddress(row: 4, col: 0))
      let multiArg = """
        =SUMPRODUCT(--(January!$C$110:$C$115=$A5),--(January!$R$110:$R$115="Yes"),--(January!$S$110:$S$115<>""),--((January!$S$110:$S$115-January!$B$110:$B$115)>=0))
        """
      let kpiJanuary = """
        =SUMPRODUCT((January!$C$110:$C$115=$A5)*(January!$R$110:$R$115="Yes")*(January!$S$110:$S$115<>"")*((January!$S$110:$S$115-January!$B$110:$B$115)>=0)*((January!$S$110:$S$115-January!$B$110:$B$115)<=60))
        """
      ytd.setCell(Cell(raw: multiArg), at: CellAddress(row: 4, col: 4))
      ytd.setCell(Cell(raw: kpiJanuary), at: CellAddress(row: 5, col: 4))
      let workbook = Workbook(sheets: [january, ytd], activeSheetIndex: 1)
      let engine = FormulaEngine()
      engine.rebuild(workbook: workbook, recalculate: false)
      _ = engine.recalculateEntireWorkbookInSheetWaves(workbook, profile: true)
      guard let profile = engine.lastWorkbookRecalcProfile else {
        return Result(name: name, passed: false, detail: "missing recalc profile")
      }
      guard profile.sumproductBooleanHits >= 2 else {
        return Result(
          name: name,
          passed: false,
          detail: String(
            format: "sumproductBooleanHits %d sumproductBooleanFallbacks %d",
            profile.sumproductBooleanHits,
            profile.sumproductBooleanFallbacks
          )
        )
      }
      return Result(
        name: name,
        passed: true,
        detail: String(
          format: "sumproductBooleanHits %d sumproductBooleanFallbacks %d",
          profile.sumproductBooleanHits,
          profile.sumproductBooleanFallbacks
        )
      )
    }

    private static func kpiJuneStyleCountifs() -> Result {
      let name = "KPI June COUNTIFS COLUMN CHAR"
      var cells: [CellAddress: String] = [:]
      let keyRow = 29
      cells[CellAddress(row: keyRow, col: 0)] = "agent-1"
      for offset in 0..<120 {
        let row = 109 + offset
        cells[CellAddress(row: row, col: 0)] = offset.isMultiple(of: 3) ? "agent-1" : "other"
        cells[CellAddress(row: row, col: 2)] = offset.isMultiple(of: 3) ? "agent-1" : "other"
        cells[CellAddress(row: row, col: 11)] = offset.isMultiple(of: 2) ? "UNIQUE" : "ORIGINAL"
      }
      let summaryAddr = CellAddress(row: 5, col: 4)
      let columnAddr = CellAddress(row: 5, col: 4)
      let cases: [(String, CellAddress, CellValue)] = [
        (
          "=COUNTIFS($C$110:$C$229,$A30,$L$110:$L$229,\"UNIQUE\")+COUNTIFS($C$110:$C$229,$A30,$L$110:$L$229,\"ORIGINAL\")",
          summaryAddr,
          .number(40)
        ),
        ("=COLUMN()", columnAddr, .number(5)),
        ("=CHAR(10)", CellAddress(row: 6, col: 4), .string("\n")),
        ("=TRUE()", CellAddress(row: 7, col: 4), .bool(true)),
      ]
      for (formula, address, expected) in cases {
        var merged = cells
        merged[address] = formula
        let value = evalFormula(formula, cells: merged, at: address)
        if !sameCellValue(value, expected) {
          return Result(
            name: name,
            passed: false,
            detail:
              "\(formula) at \(address.a1) got \(value.displayString) expected \(expected.displayString)"
          )
        }
        if case .error = value {
          return Result(name: name, passed: false, detail: "\(formula) errored at \(address.a1)")
        }
      }
      return Result(name: name, passed: true, detail: "June-style COUNTIFS + COLUMN/CHAR/TRUE")
    }

    /// COUNTIFS must not fail when individual data rows evaluate to #DIV/0! (KPI daily columns).
    private static func countifsSkipsErrorRows() -> Result {
      let name = "COUNTIFS skips error rows"
      var cells: [CellAddress: String] = [:]
      cells[CellAddress(row: 5, col: 0)] = "k"
      for row in 10..<30 {
        cells[CellAddress(row: row, col: 0)] = row < 15 ? "k" : "z"
        if row < 15 {
          cells[CellAddress(row: row, col: 2)] = "k"
        } else {
          cells[CellAddress(row: row, col: 2)] = "=1/0"
        }
        cells[CellAddress(row: row, col: 11)] = "UNIQUE"
      }
      let formula = "=COUNTIFS($C$11:$C$29,$A6,$L$11:$L$29,\"UNIQUE\")"
      let value = evalFormula(formula, cells: cells)
      guard case .number(let count) = value, count == 5 else {
        return Result(
          name: name,
          passed: false,
          detail: "\(formula) got \(value.displayString)"
        )
      }
      return Result(name: name, passed: true, detail: "counted matching rows with errors skipped")
    }

    /// Regression: multi-cell range refs must not fan into the dependency graph (KPI June lag).
    private static func countifsRangeDependencyBudget() -> Result {
      let name = "COUNTIFS range dependency budget"
      var cells: [CellAddress: String] = [:]
      cells[CellAddress(row: 5, col: 0)] = "k"
      for row in 10..<810 {
        cells[CellAddress(row: row, col: 0)] = "k"
        cells[CellAddress(row: row, col: 1)] = "k"
        cells[CellAddress(row: row, col: 2)] = "UNIQUE"
        cells[CellAddress(row: row, col: 3)] = "=SUM($A$1:$A$50)"
      }
      for row in 0..<50 where row != 5 {
        cells[CellAddress(row: row, col: 0)] = "1"
      }
      let formula = "=COUNTIFS($B$11:$B$809,$A6,$C$11:$C$809,\"UNIQUE\")"
      let resultAddr = CellAddress(row: 5, col: 4)
      cells[resultAddr] = formula
      var sheet = Sheet(name: "Sheet1")
      for (address, raw) in cells {
        sheet.setCell(Cell(raw: raw), at: address)
      }
      let engine = FormulaEngine()
      let workbook = Workbook(sheets: [sheet])
      engine.rebuild(workbook: workbook, recalculate: false)
      let start = CFAbsoluteTimeGetCurrent()
      let value = engine.displayValue(at: resultAddr, sheet: sheet)
      let elapsed = CFAbsoluteTimeGetCurrent() - start
      guard case .number(let count) = value, count == 799 else {
        return Result(
          name: name,
          passed: false,
          detail: "value \(value.displayString) in \(String(format: "%.2fs", elapsed))"
        )
      }
      guard elapsed < 0.35 else {
        return Result(
          name: name,
          passed: false,
          detail: String(format: "displayValue took %.2fs (range deps fan-in)", elapsed)
        )
      }
      return Result(
        name: name,
        passed: true,
        detail: String(format: "799 matches in %.2fs", elapsed)
      )
    }

    private static func syntheticCountifsHeavySheet(
      name: String,
      summaryRows: Int,
      dataStartRow: Int,
      dataRows: Int
    ) -> Sheet {
      var sheet = Sheet(name: name)
      let lastDataRow = dataStartRow + dataRows - 1
      let bStart = dataStartRow + 1
      let bEnd = lastDataRow + 1
      for row in 0..<summaryRows {
        sheet.setCell(Cell(raw: "k\(row % 5)"), at: CellAddress(row: row, col: 0))
      }
      for row in dataStartRow...lastDataRow {
        sheet.setCell(Cell(raw: "k\(row % 5)"), at: CellAddress(row: row, col: 1))
        sheet.setCell(
          Cell(raw: row.isMultiple(of: 2) ? "UNIQUE" : "ORIGINAL"),
          at: CellAddress(row: row, col: 2))
        sheet.setCell(Cell(raw: "1"), at: CellAddress(row: row, col: 3))
      }
      for row in 0..<summaryRows {
        let formula =
          "=COUNTIFS($B$\(bStart):$B$\(bEnd),$A\(row + 1),$C$\(bStart):$C$\(bEnd),\"UNIQUE\")"
        sheet.setCell(Cell(raw: formula), at: CellAddress(row: row, col: 4))
      }
      return sheet
    }

    private static func syntheticAggregateWorkbook() -> Workbook {
      let sheets = (0..<5).map { index in
        syntheticCountifsHeavySheet(
          name: "Month\(index)",
          summaryRows: 1_200,
          dataStartRow: 10,
          dataRows: 1_200
        )
      }
      return Workbook(sheets: sheets, activeSheetIndex: 0)
    }

    /// Multi-sheet COUNTIFS workbook: full recalc must stay under ~1s (grouped range scans).
    private static func syntheticWorkbookAggregateRecalcBudget() -> Result {
      let name = "synthetic workbook aggregate recalc budget"
      let workbook = syntheticAggregateWorkbook()
      let formulaCount = workbook.sheets.reduce(0) { partial, sheet in
        partial + sheet.cells.values.count(where: { FormulaSyntax.isFormula($0.raw) })
      }
      let engine = FormulaEngine()
      engine.rebuild(workbook: workbook, recalculate: false)
      let recalc = engine.recalculateEntireWorkbook(workbook)
      guard recalc < 1.0 else {
        return Result(
          name: name,
          passed: false,
          detail: String(format: "%d formulas full recalc %.2fs", formulaCount, recalc)
        )
      }
      let sample = engine.displayValue(at: CellAddress(row: 0, col: 4), sheet: workbook.sheets[0])
      guard case .number(let count) = sample, count > 0 else {
        return Result(name: name, passed: false, detail: "sample COUNTIFS empty after recalc")
      }
      return Result(
        name: name,
        passed: true,
        detail: String(
          format: "%d formulas across %d sheets in %.2fs", formulaCount, workbook.sheets.count,
          recalc)
      )
    }

    /// One edited source cell in a COUNTIFS data column: dependent summary recalc ~50ms.
    private static func syntheticWorkbookAggregateEditBudget() -> Result {
      let name = "synthetic workbook aggregate edit budget"
      let workbook = syntheticAggregateWorkbook()
      var sheet = workbook.sheets[0]
      let engine = FormulaEngine()
      engine.rebuild(workbook: workbook, recalculate: false)
      _ = engine.recalculateEntireWorkbook(workbook)
      let dataCell = CellAddress(row: 50, col: 1)
      sheet.setCell(Cell(raw: "k9"), at: dataCell)
      let start = CFAbsoluteTimeGetCurrent()
      engine.cellsDidChange([dataCell], sheet: sheet)
      let summary = CellAddress(row: 0, col: 4)
      _ = engine.displayValue(at: summary, sheet: sheet)
      let elapsed = CFAbsoluteTimeGetCurrent() - start
      guard elapsed < 0.05 else {
        return Result(
          name: name,
          passed: false,
          detail: String(format: "edit+summary %.2fs", elapsed)
        )
      }
      return Result(name: name, passed: true, detail: String(format: "edit path %.2fs", elapsed))
    }

    private static func kpiWorkbookFixtureURL() throws -> URL? {
      let env = ProcessInfo.processInfo.environment
      let envPath =
        env["SPARK_GRID_FIXTURE_BDC_KPI"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      if !envPath.isEmpty, FileManager.default.fileExists(atPath: envPath) {
        return URL(fileURLWithPath: envPath)
      }
      let fixturesDir =
        env["SPARK_GRID_FIXTURES"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      if !fixturesDir.isEmpty {
        let fixturesPath = (fixturesDir as NSString).appendingPathComponent(
          "BDC-Digital-KPI-2026.xlsx")
        if FileManager.default.fileExists(atPath: fixturesPath) {
          return URL(fileURLWithPath: fixturesPath)
        }
      }
      return nil
    }

    /// Emits KPI full-recalc profile before the rest of Bug Bash (flushed for early Mac kill).
    private static func emitKPIRecalcProfileLine(_ line: String) {
      let text = "KPI full recalc profile | \(line)\n"
      fputs(text, stderr)
      fflush(stderr)
    }

    /// Optional KPI workbook: full grouped recalc under ~1s; June E/F still match Excel cache.
    private static func kpiWorkbookFullRecalcBudget() -> Result {
      let name = "KPI workbook full recalc budget"
      guard (try? kpiWorkbookFixtureURL()) != nil else {
        return Result(name: name, passed: true, detail: "skipped (no KPI fixture source)")
      }
      do {
        let url = try sandboxReadableWorkbookURL(
          cacheFileName: "BDC-Digital-KPI-2026.xlsx",
          envKeys: ["SPARK_GRID_FIXTURE_BDC_KPI"],
          fixturesFileName: "BDC-Digital-KPI-2026.xlsx"
        )
        let imported = try XLSXCodec.importWorkbook(from: url)
        let formulaCount = imported.sheets.reduce(0) { partial, sheet in
          partial + sheet.cells.values.count(where: { FormulaSyntax.isFormula($0.raw) })
        }
        let engine = FormulaEngine()
        let openStart = CFAbsoluteTimeGetCurrent()
        engine.rebuild(workbook: imported, recalculate: false)
        let openElapsed = CFAbsoluteTimeGetCurrent() - openStart
        guard openElapsed < 2.5 else {
          return Result(
            name: name,
            passed: false,
            detail: String(format: "open blocked %.2fs", openElapsed)
          )
        }
        let recalc = engine.recalculateEntireWorkbook(imported, profile: true)
        let phaseDetail =
          engine.lastWorkbookRecalcProfile?.detailSummary(totalSeconds: recalc)
          ?? String(format: "%.2fs", recalc)
        emitKPIRecalcProfileLine(String(format: "%d formulas | %@", formulaCount, phaseDetail))
        guard recalc < 1.0 else {
          return Result(
            name: name,
            passed: false,
            detail: String(format: "%d formulas | %@", formulaCount, phaseDetail)
          )
        }
        guard
          let juneIndex = imported.sheets.firstIndex(where: {
            $0.name.caseInsensitiveCompare("June") == .orderedSame
          })
        else {
          return Result(name: name, passed: false, detail: "June sheet missing")
        }
        let june = imported.sheets[juneIndex]
        var juneErrors = 0
        for row in 5...61 {
          for col in 4...5 {
            let addr = CellAddress(row: row, col: col)
            guard FormulaSyntax.isFormula(june.cell(at: addr).raw) else { continue }
            guard let cached = excelCachedNumericValue(url: url, sheetName: "June", address: addr)
            else {
              continue
            }
            let value = engine.displayValue(at: addr, sheet: june)
            if case .error = value { juneErrors += 1 }
            if case .number(let actual) = value, abs(actual - cached) >= 0.000_001 {
              return Result(
                name: name,
                passed: false,
                detail: "\(addr.a1) got \(actual) cached \(cached) after recalc"
              )
            }
          }
        }
        guard juneErrors == 0 else {
          return Result(
            name: name, passed: false, detail: "\(juneErrors) June E/F errors after recalc")
        }
        return Result(
          name: name,
          passed: true,
          detail: String(
            format: "%d formulas open %.2fs | %@",
            formulaCount,
            openElapsed,
            phaseDetail
          )
        )
      } catch {
        return Result(name: name, passed: false, detail: error.localizedDescription)
      }
    }

    /// Optional KPI workbook: one daily data edit recalculates dependents in ~50ms.
    private static func kpiWorkbookAggregateEditBudget() -> Result {
      let name = "KPI workbook aggregate edit budget"
      guard (try? kpiWorkbookFixtureURL()) != nil else {
        return Result(name: name, passed: true, detail: "skipped (no KPI fixture source)")
      }
      do {
        let url = try sandboxReadableWorkbookURL(
          cacheFileName: "BDC-Digital-KPI-2026.xlsx",
          envKeys: ["SPARK_GRID_FIXTURE_BDC_KPI"],
          fixturesFileName: "BDC-Digital-KPI-2026.xlsx"
        )
        var imported = try XLSXCodec.importWorkbook(from: url)
        guard
          let juneIndex = imported.sheets.firstIndex(where: {
            $0.name.caseInsensitiveCompare("June") == .orderedSame
          })
        else {
          return Result(name: name, passed: false, detail: "June sheet missing")
        }
        imported.activeSheetIndex = juneIndex
        let engine = FormulaEngine()
        engine.rebuild(workbook: imported, recalculate: false)
        _ = engine.recalculateEntireWorkbook(imported)
        var june = imported.sheets[juneIndex]
        let dataCell = CellAddress(row: 120, col: 2)
        guard june.cells[dataCell] != nil else {
          return Result(name: name, passed: false, detail: "June daily cell missing")
        }
        june.setCell(Cell(raw: "EDIT-\(june.cell(at: dataCell).raw)"), at: dataCell)
        imported.sheets[juneIndex] = june
        let summary = CellAddress(row: 5, col: 4)
        let start = CFAbsoluteTimeGetCurrent()
        engine.cellsDidChange([dataCell], sheet: june)
        _ = engine.displayValue(at: summary, sheet: june)
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        guard elapsed < 0.05 else {
          return Result(
            name: name,
            passed: false,
            detail: String(format: "June edit+summary %.2fs", elapsed)
          )
        }
        return Result(
          name: name, passed: true, detail: String(format: "June edit path %.2fs", elapsed))
      } catch {
        return Result(name: name, passed: false, detail: error.localizedDescription)
      }
    }

    private static func everydayFormulas() -> Result {
      let name = "everyday formulas"
      let wanted = [
        "SUMIF", "AVERAGEIF", "COUNTIF", "SUMIFS", "COUNTIFS", "AVERAGEIFS",
        "COUNTBLANK", "SUMPRODUCT", "IFNA", "IFS", "NOT", "UPPER", "LOWER",
        "MID", "SUBSTITUTE", "TEXTJOIN", "ROUNDUP", "ROUNDDOWN", "NOW",
        "CHAR", "COLUMN", "TRUE",
      ]
      let missing = wanted.filter { !FormulaFunctions.all.contains($0) }
      if !missing.isEmpty {
        return Result(
          name: name, passed: false, detail: "catalog missing \(missing.joined(separator: ", "))")
      }

      let cells: [CellAddress: String] = [
        CellAddress(row: 0, col: 0): "10",
        CellAddress(row: 1, col: 0): "20",
        CellAddress(row: 2, col: 0): "30",
        CellAddress(row: 0, col: 1): "1",
        CellAddress(row: 1, col: 1): "2",
        CellAddress(row: 2, col: 1): "3",
        CellAddress(row: 0, col: 2): "east",
        CellAddress(row: 1, col: 2): "west",
        CellAddress(row: 2, col: 2): "eastern",
        CellAddress(row: 0, col: 3): "5",
        CellAddress(row: 1, col: 3): "7",
        CellAddress(row: 2, col: 3): "9",
        CellAddress(row: 4, col: 0): "apple",
        CellAddress(row: 6, col: 0): "Apple",
        CellAddress(row: 0, col: 4): "FALSE",
        CellAddress(row: 1, col: 4): "0",
        CellAddress(row: 1, col: 5): "star*",
        CellAddress(row: 2, col: 5): "starX",
      ]
      let cases: [(String, CellValue)] = [
        ("=SUMIF(A1:A3,\">15\")", .number(50)),
        ("=SUMIF(A1:A3,\">15\",B1:B3)", .number(5)),
        ("=SUMIF(A1:A3,\">15\",B1)", .number(5)),
        ("=SUMIF(C1:C3,\"*east*\",D1:D3)", .number(14)),
        ("=COUNTIF(C1:C3,\"*east*\")", .number(2)),
        ("=COUNTIF(C1:C3,\"?est\")", .number(1)),
        ("=COUNTIF(A1:A3,\">=20\")", .number(2)),
        ("=COUNTIF(A5:A7,\"apple\")", .number(2)),
        ("=COUNTIF(F1:F3,\"star~*\")", .number(1)),
        ("=COUNTIF(F1:F3,\"*\")", .number(2)),
        ("=AVERAGEIF(A1:A3,\">15\")", .number(25)),
        ("=AVERAGEIF(A1:A3,\">100\")", .error(.divZero)),
        ("=SUMIFS(B1:B3,A1:A3,\">10\",A1:A3,\"<30\")", .number(2)),
        ("=COUNTIFS(A1:A3,\">15\",B1:B3,\"<3\")", .number(1)),
        ("=AVERAGEIFS(B1:B3,A1:A3,\">=20\")", .number(2.5)),
        ("=AVERAGEIFS(B1:B3,A1:A3,\">100\")", .error(.divZero)),
        ("=SUMIFS(B1:B2,A1:A3,\">0\")", .error(.value)),
        ("=COUNTBLANK(A1:A4)", .number(1)),
        ("=COUNTBLANK(E1:E3)", .number(1)),
        ("=SUMPRODUCT(A1:A3,B1:B3)", .number(140)),
        ("=SUMPRODUCT(A1:A3,B1:B2)", .error(.value)),
        ("=SUMPRODUCT((A1:A3>15)*(B1:B3))", .number(5)),
        ("=IFNA(1,2)", .number(1)),
        ("=IFNA(VLOOKUP(\"z\",A1:B3,2,FALSE),9)", .number(9)),
        ("=IFNA(1/0,9)", .error(.divZero)),
        ("=IFS(FALSE,1,TRUE,2)", .number(2)),
        ("=IFS(FALSE,1)", .error(.na)),
        ("=IFS(1,\"yes\")", .string("yes")),
        ("=NOT(FALSE)", .bool(true)),
        ("=NOT(1)", .bool(false)),
        ("=NOT(0)", .bool(true)),
        ("=UPPER(\"Ab\")", .string("AB")),
        ("=LOWER(\"Ab\")", .string("ab")),
        ("=UPPER(12)", .string("12")),
        ("=MID(\"spark\",2,3)", .string("par")),
        ("=MID(\"spark\",0,1)", .error(.value)),
        ("=SUBSTITUTE(\"a-a-a\",\"a\",\"b\")", .string("b-b-b")),
        ("=SUBSTITUTE(\"a-a-a\",\"a\",\"b\",2)", .string("a-b-a")),
        ("=SUBSTITUTE(\"Apple\",\"p\",\"X\")", .string("AXXle")),
        ("=SUBSTITUTE(\"Apple\",\"P\",\"X\")", .string("Apple")),
        ("=TEXTJOIN(\", \",TRUE,C1:C3)", .string("east, west, eastern")),
        ("=TEXTJOIN(\",\",FALSE,C1,C4,C3)", .string("east,,eastern")),
        ("=ROUNDUP(1.1,0)", .number(2)),
        ("=ROUNDUP(-1.2,0)", .number(-2)),
        ("=ROUNDDOWN(1.9,0)", .number(1)),
        ("=ROUNDDOWN(-1.9,0)", .number(-1)),
        ("=ROUNDUP(1.234,2)", .number(1.24)),
        ("=ROUNDDOWN(1.239,2)", .number(1.23)),
        ("=ROUNDUP(1234,-2)", .number(1300)),
        ("=ROUNDDOWN(1234,-2)", .number(1200)),
      ]
      for (formula, expected) in cases {
        let value = evalFormula(formula, cells: cells)
        if !sameCellValue(value, expected) {
          return Result(
            name: name,
            passed: false,
            detail: "\(formula) got \(value.displayString) expected \(expected.displayString)"
          )
        }
      }

      let before = ExcelDate.localSerialWithTime(from: Date())
      let now = evalFormula("=NOW()", cells: [:])
      let after = ExcelDate.localSerialWithTime(from: Date())
      guard case .number(let serial) = now, serial >= before - 0.00001, serial <= after + 0.00001
      else {
        return Result(name: name, passed: false, detail: "NOW got \(now.displayString)")
      }
      return Result(name: name, passed: true, detail: "criteria, wildcards, text, and rounding")
    }

    /// `NOW`/`TODAY` must show the Mac wall clock. Cell formats read serials in UTC,
    /// so 2026-10-09 00:52:30 UTC is 10/8/2026 17:52:30 in Pacific time, not the UTC string.
    private static func nowAndTodayUseLocalTime() -> Result {
      let name = "NOW and TODAY use local time"
      func fail(_ detail: String) -> Result {
        Result(name: name, passed: false, detail: detail)
      }
      func shown(_ serial: Double, code: String) -> String {
        ExcelFormatCode.formatted(serial, code: code, fractionDigits: nil) ?? ""
      }

      guard let losAngeles = TimeZone(identifier: "America/Los_Angeles"),
        let tokyo = TimeZone(identifier: "Asia/Tokyo")
      else {
        return fail("missing time zone identifier")
      }
      guard
        let utcEvening = utcDate(year: 2026, month: 10, day: 9, hour: 0, minute: 52, second: 30),
        let utcMorning = utcDate(year: 2026, month: 10, day: 9, hour: 7, minute: 30, second: 0)
      else {
        return fail("could not build UTC instants")
      }

      let probed = ExcelDate.wallClock()
      if abs(probed.date.timeIntervalSinceNow) > 2 {
        return fail("wall clock is not the Mac clock")
      }
      if probed.timeZone.secondsFromGMT(for: probed.date)
        != TimeZone.current.secondsFromGMT(for: probed.date)
      {
        return fail("wall clock zone \(probed.timeZone.identifier) is not the Mac zone")
      }

      let losAngelesNow = ExcelDate.localSerialWithTime(from: utcEvening, timeZone: losAngeles)
      let tokyoNow = ExcelDate.localSerialWithTime(from: utcEvening, timeZone: tokyo)
      let utcNow = ExcelDate.serialWithTime(from: utcEvening)
      if shown(losAngelesNow, code: "m/d/yyyy hh:mm:ss") != "10/8/2026 17:52:30" {
        return fail("Los Angeles \(shown(losAngelesNow, code: "m/d/yyyy hh:mm:ss"))")
      }
      if shown(tokyoNow, code: "m/d/yyyy hh:mm:ss") != "10/9/2026 09:52:30" {
        return fail("Tokyo \(shown(tokyoNow, code: "m/d/yyyy hh:mm:ss"))")
      }
      if shown(utcNow, code: "m/d/yyyy hh:mm:ss") != "10/9/2026 00:52:30" {
        return fail("UTC serial display changed to \(shown(utcNow, code: "m/d/yyyy hh:mm:ss"))")
      }
      if abs(losAngelesNow - utcNow) < 1e-8 {
        return fail("Los Angeles serial matched UTC")
      }
      let losAngelesToday = ExcelDate.localSerial(from: utcEvening, timeZone: losAngeles)
      if shown(losAngelesToday, code: "m/d/yyyy") != "10/8/2026" {
        return fail("TODAY Los Angeles \(shown(losAngelesToday, code: "m/d/yyyy"))")
      }

      let originalClock = ExcelDate.wallClock
      let previousTZ = getenv("TZ").map { String(cString: $0) }
      defer {
        ExcelDate.wallClock = originalClock
        if let previousTZ {
          setenv("TZ", previousTZ, 1)
        } else {
          unsetenv("TZ")
        }
        NSTimeZone.resetSystemTimeZone()
      }

      ExcelDate.wallClock = {
        (date: utcEvening, timeZone: losAngeles)
      }
      guard case .number(let nowSerial) = evalFormula("=NOW()", cells: [:]) else {
        return fail("NOW did not return a number")
      }
      guard case .number(let todaySerial) = evalFormula("=TODAY()", cells: [:]) else {
        return fail("TODAY did not return a number")
      }
      if shown(nowSerial, code: "m/d/yyyy hh:mm:ss") != "10/8/2026 17:52:30" {
        return fail("NOW displayed \(shown(nowSerial, code: "m/d/yyyy hh:mm:ss"))")
      }
      if shown(todaySerial, code: "m/d/yyyy") != "10/8/2026" {
        return fail("TODAY displayed \(shown(todaySerial, code: "m/d/yyyy"))")
      }

      setenv("TZ", "America/Los_Angeles", 1)
      NSTimeZone.resetSystemTimeZone()
      let switched = TimeZone.current.secondsFromGMT(for: utcEvening)
      if switched != losAngeles.secondsFromGMT(for: utcEvening) {
        return fail(
          "process zone \(TimeZone.current.identifier) did not switch to America/Los_Angeles")
      }
      if shown(utcNow, code: "m/d/yyyy hh:mm:ss") != "10/9/2026 00:52:30" {
        return fail("date formats followed the Mac zone")
      }

      ExcelDate.wallClock = {
        (date: utcMorning, timeZone: losAngeles)
      }
      guard case .number(let year) = evalFormula("=YEAR(NOW())", cells: [:]),
        case .number(let month) = evalFormula("=MONTH(NOW())", cells: [:]),
        case .number(let day) = evalFormula("=DAY(NOW())", cells: [:]),
        case .string(let text) = evalFormula("=TEXT(NOW(),\"M/D/YYYY\")", cells: [:])
      else {
        return fail("date parts did not evaluate")
      }
      if year != 2026 || month != 10 || day != 9 || text != "10/9/2026" {
        return fail("local morning parts \(year)-\(month)-\(day) text \(text)")
      }
      return Result(name: name, passed: true, detail: "Mac wall clock, not UTC")
    }

    private static func lookupFormulas() -> Result {
      let name = "lookup formulas"
      let missing = ["HLOOKUP", "XMATCH", "XLOOKUP", "VLOOKUP"].filter {
        !FormulaFunctions.all.contains($0)
      }
      if !missing.isEmpty {
        return Result(
          name: name, passed: false, detail: "catalog missing \(missing.joined(separator: ", "))")
      }

      let cells: [CellAddress: String] = [
        CellAddress(row: 0, col: 0): "10",
        CellAddress(row: 1, col: 0): "20",
        CellAddress(row: 2, col: 0): "30",
        CellAddress(row: 3, col: 0): "15",
        CellAddress(row: 4, col: 0): "20",
        CellAddress(row: 0, col: 1): "a",
        CellAddress(row: 1, col: 1): "b",
        CellAddress(row: 2, col: 1): "c",
        CellAddress(row: 3, col: 1): "d",
        CellAddress(row: 4, col: 1): "later",
        CellAddress(row: 0, col: 2): "east",
        CellAddress(row: 1, col: 2): "west",
        CellAddress(row: 2, col: 2): "eastern",
        CellAddress(row: 0, col: 3): "5",
        CellAddress(row: 1, col: 3): "7",
        CellAddress(row: 2, col: 3): "9",
        CellAddress(row: 0, col: 4): "apple",
        CellAddress(row: 1, col: 4): "banana",
        CellAddress(row: 2, col: 4): "cherry",
        CellAddress(row: 0, col: 5): "1",
        CellAddress(row: 1, col: 5): "2",
        CellAddress(row: 2, col: 5): "3",
        CellAddress(row: 1, col: 6): "star*",
        CellAddress(row: 2, col: 6): "starX",
        CellAddress(row: 1, col: 7): "11",
        CellAddress(row: 2, col: 7): "22",
        CellAddress(row: 5, col: 0): "10",
        CellAddress(row: 5, col: 1): "20",
        CellAddress(row: 5, col: 2): "30",
        CellAddress(row: 6, col: 0): "a",
        CellAddress(row: 6, col: 1): "b",
        CellAddress(row: 6, col: 2): "c",
        CellAddress(row: 8, col: 0): "30",
        CellAddress(row: 8, col: 1): "10",
        CellAddress(row: 8, col: 2): "20",
        CellAddress(row: 9, col: 0): "x",
        CellAddress(row: 9, col: 1): "y",
        CellAddress(row: 9, col: 2): "z",
        CellAddress(row: 11, col: 0): "east",
        CellAddress(row: 11, col: 1): "west",
        CellAddress(row: 11, col: 2): "eastern",
        CellAddress(row: 12, col: 0): "5",
        CellAddress(row: 12, col: 1): "7",
        CellAddress(row: 12, col: 2): "9",
        CellAddress(row: 14, col: 0): "10",
        CellAddress(row: 14, col: 1): "20",
        CellAddress(row: 14, col: 2): "20",
        CellAddress(row: 15, col: 0): "p",
        CellAddress(row: 15, col: 1): "q",
        CellAddress(row: 15, col: 2): "r",
        CellAddress(row: 19, col: 0): "10",
        CellAddress(row: 20, col: 0): "20",
        CellAddress(row: 21, col: 0): "20",
        CellAddress(row: 19, col: 1): "p",
        CellAddress(row: 20, col: 1): "q",
        CellAddress(row: 21, col: 1): "r",
      ]
      let cases: [(String, CellValue)] = [
        ("=VLOOKUP(20,A1:B3,2,FALSE)", .string("b")),
        ("=VLOOKUP(25,A1:B3,2)", .string("b")),
        ("=VLOOKUP(25,A1:B3,2,TRUE)", .string("b")),
        ("=VLOOKUP(20,A20:B22,2)", .string("r")),
        ("=VLOOKUP(20,A20:B22,2,FALSE)", .string("q")),
        ("=VLOOKUP(5,A1:B3,2)", .error(.na)),
        ("=VLOOKUP(20,A1:B3,3,FALSE)", .error(.ref)),
        ("=VLOOKUP(\"z\",A1:B3,2,FALSE)", .error(.na)),
        ("=HLOOKUP(20,A6:C7,2,FALSE)", .string("b")),
        ("=HLOOKUP(25,A6:C7,2)", .string("b")),
        ("=HLOOKUP(25,A6:C7,2,TRUE)", .string("b")),
        ("=hlookup(20,A6:C7,1,FALSE)", .number(20)),
        ("=HLOOKUP(25,A6:C7,2,FALSE)", .error(.na)),
        ("=HLOOKUP(5,A6:C7,2)", .error(.na)),
        ("=HLOOKUP(20,A6:C7,3,FALSE)", .error(.ref)),
        ("=HLOOKUP(10,A6:C7,0,FALSE)", .error(.ref)),
        ("=HLOOKUP(10,A6:C7,\"x\",FALSE)", .error(.value)),
        ("=HLOOKUP(10,A6:C7)", .error(.value)),
        ("=HLOOKUP(25,A9:C10,2)", .string("z")),
        ("=HLOOKUP(10,A9:C10,2,FALSE)", .string("y")),
        ("=HLOOKUP(\"WEST\",A12:C13,2,FALSE)", .number(7)),
        ("=HLOOKUP(\"nope\",A12:C13,2,FALSE)", .error(.na)),
        ("=HLOOKUP(20,A15:C16,2)", .string("r")),
        ("=HLOOKUP(20,A15:C16,2,FALSE)", .string("q")),
        ("=XLOOKUP(20,A1:A3,B1:B3)", .string("b")),
        ("=XLOOKUP(20,A1:A3,B1:B3,\"missing\")", .string("b")),
        ("=XLOOKUP(\"z\",A1:A3,B1:B3,9)", .number(9)),
        ("=XLOOKUP(25,A1:A3,B1:B3,\"missing\")", .string("missing")),
        ("=XLOOKUP(\"*east*\",C1:C3,D1:D3,\"no\")", .string("no")),
        ("=XLOOKUP(20,A6:C6,A7:C7)", .string("b")),
        ("=XLOOKUP(\"APPLE\",E1:E3,F1:F3)", .number(1)),
        ("=XLOOKUP(20,A1:A3,B1:B3,\"no\",0)", .string("b")),
        ("=XLOOKUP(25,A1:A5,B1:B5,\"missing\",-1)", .string("b")),
        ("=XLOOKUP(25,A1:A5,B1:B5,\"missing\",1)", .string("c")),
        ("=XLOOKUP(5,A1:A4,B1:B4,\"missing\",-1)", .string("missing")),
        ("=XLOOKUP(40,A1:A4,B1:B4,\"missing\",1)", .string("missing")),
        ("=XLOOKUP(20,A1:A5,B1:B5,\"missing\",-1)", .string("b")),
        ("=XLOOKUP(\"blueberry\",E1:E3,F1:F3,\"missing\",-1)", .number(2)),
        ("=XLOOKUP(\"blueberry\",E1:E3,F1:F3,\"missing\",1)", .number(3)),
        ("=XLOOKUP(\"aardvark\",E1:E3,F1:F3,\"missing\",-1)", .string("missing")),
        ("=XLOOKUP(\"date\",E1:E3,F1:F3,\"missing\",1)", .string("missing")),
        ("=XLOOKUP(25,A6:C6,A7:C7,\"missing\",-1)", .string("b")),
        ("=XLOOKUP(25,A6:C6,A7:C7,\"missing\",1)", .string("c")),
        ("=XLOOKUP(\"*east*\",C1:C3,D1:D3,\"no\",2)", .number(5)),
        ("=XLOOKUP(\"w*\",C1:C3,D1:D3,\"no\",2)", .number(7)),
        ("=XLOOKUP(\"*ern\",C1:C3,D1:D3,\"no\",2)", .number(9)),
        ("=XLOOKUP(\"2*\",A1:A3,B1:B3,\"no\",2)", .string("b")),
        ("=XLOOKUP(\"star~*\",G2:G3,H2:H3,\"no\",2)", .number(11)),
        ("=XLOOKUP(\"nope*\",C1:C3,D1:D3,\"no\",2)", .string("no")),
        ("=XLOOKUP(20,A1:A3,B1:B3,\"no\",3)", .error(.value)),
        ("=XLOOKUP(20,A1:A3,B1:B3,\"no\",0,1)", .error(.value)),
        ("=XLOOKUP(10,A1:A3)", .error(.value)),
        ("=XMATCH(20,A1:A3)", .number(2)),
        ("=XMATCH(\"z\",A1:A3)", .error(.na)),
        ("=XMATCH(25,A1:A4,-1)", .number(2)),
        ("=XMATCH(25,A1:A4,1)", .number(3)),
        ("=XMATCH(5,A1:A4,-1)", .error(.na)),
        ("=XMATCH(\"blueberry\",E1:E3,-1)", .number(2)),
        ("=XMATCH(\"blueberry\",E1:E3,1)", .number(3)),
        ("=XMATCH(\"w*\",C1:C3,2)", .number(2)),
        ("=XMATCH(\"*ern\",C1:C3,2)", .number(3)),
        ("=XMATCH(\"star~*\",G2:G3,2)", .number(1)),
        ("=XMATCH(30,A6:C6)", .number(3)),
        ("=XMATCH(25,A6:C6,-1)", .number(2)),
        ("=XMATCH(25,A6:C6,1)", .number(3)),
        ("=xmatch(20,A1:A3,0)", .number(2)),
        ("=XMATCH(20,A1:A3,4)", .error(.value)),
        ("=XMATCH(10)", .error(.value)),
      ]
      for (formula, expected) in cases {
        let value = evalFormula(formula, cells: cells)
        if !sameCellValue(value, expected) {
          return Result(
            name: name,
            passed: false,
            detail: "\(formula) got \(value.displayString) expected \(expected.displayString)"
          )
        }
      }
      return Result(name: name, passed: true, detail: "HLOOKUP, XMATCH, and XLOOKUP match modes")
    }

    private static func sameCellValue(_ lhs: CellValue, _ rhs: CellValue) -> Bool {
      if case .number(let left) = lhs, case .number(let right) = rhs {
        return abs(left - right) < 0.000_000_1
      }
      return lhs == rhs
    }

    private static func evalFormula(
      _ formula: String,
      cells: [CellAddress: String],
      at result: CellAddress = CellAddress(row: 40, col: 0)
    ) -> CellValue {
      var sheet = Sheet(name: "Sheet1")
      for (address, raw) in cells {
        sheet.setCell(Cell(raw: raw), at: address)
      }
      sheet.setCell(Cell(raw: formula), at: result)
      let engine = FormulaEngine()
      let workbook = Workbook(sheets: [sheet])
      engine.rebuild(workbook: workbook, recalculate: true)
      return engine.displayValue(at: result, sheet: workbook.activeSheet)
    }

    private static func excelFormatCodes() -> Result {
      let name = "excel format codes"
      func shown(_ number: Double, code: String, places: Int? = nil) -> String {
        var format = CellFormat()
        format.formatCode = code
        format.decimalPlaces = places
        return CellFormatRenderer.displayText(for: .number(number), format: format, fallbackRaw: "")
      }

      func shownText(_ text: String, code: String) -> String {
        var format = CellFormat()
        format.formatCode = code
        return CellFormatRenderer.displayText(for: .string(text), format: format, fallbackRaw: text)
      }

      let sections = "#,##0.00;(#,##0.00);\"zero\";\"id \"@"
      let checks: [(String, String)] = [
        (shown(1234.5, code: "€#,##0.00"), "€1,234.50"),
        (shown(-1234.5, code: "€#,##0.00"), "-€1,234.50"),
        (shown(1234.5, code: "[$£-809]#,##0.00"), "£1,234.50"),
        (shown(1234.5, code: "\"$\"#,##0.00"), "$1,234.50"),
        (shown(1234.5, code: "#,##0.00"), "1,234.50"),
        (shown(1234.4, code: "#,##0"), "1,234"),
        (shown(1234.5, code: "#,##0.00 \"kg\""), "1,234.50 kg"),
        (shown(1234.5, code: "\"Qty \"#,##0.00"), "Qty 1,234.50"),
        (shown(5, code: "\"say \"\"hi\"\" \"0"), "say \"hi\" 5"),
        (shown(1, code: "\"a;b\""), "a;b"),
        (shown(5, code: "0\\;0"), "5;0"),
        (shown(0.5, code: "0%"), "50%"),
        (shown(0.256, code: "0.00%"), "25.60%"),
        (shown(-0.256, code: "0.00%"), "-25.60%"),
        (shown(0.256, code: "0.00\"%\""), "0.26%"),
        (shown(-1234.5, code: "$#,##0.00_);($#,##0.00)"), "($1,234.50)"),
        (shown(1234.5, code: sections), "1,234.50"),
        (shown(-1234.5, code: sections), "(1,234.50)"),
        (shown(0, code: sections), "zero"),
        (shown(0, code: "0;-0;;"), ""),
        (shown(1234, code: "\"n/a\""), "n/a"),
        (shown(1234, code: "0.00E+00"), "1.23E+03"),
        (shown(1234.5, code: "#,##0.00", places: 0), "1,235"),
        (shownText("Hello", code: sections), "id Hello"),
        (shownText("Hello", code: "0;0;0;@\" and \"@"), "Hello and Hello"),
        (shownText("Hello", code: "0;0;0;\"@\"@"), "@Hello"),
        (shownText("Hello", code: "0;0;0;[Red]@"), "Hello"),
        (shownText("Hello", code: "0;0;0;\"n/a\""), "n/a"),
        (shownText("Hello", code: "0;0;0;\"a;b \"@"), "a;b Hello"),
        (shownText("Hello", code: "0.00"), "Hello"),
      ]
      for (actual, expected) in checks where actual != expected {
        return Result(name: name, passed: false, detail: "\(actual) expected \(expected)")
      }

      var plainCurrency = CellFormat()
      plainCurrency.numberFormat = .currency
      let forced = CellFormatRenderer.displayText(
        for: .number(1234.5), format: plainCurrency, fallbackRaw: "1234.5")
      if forced != "$1234.50" {
        return Result(name: name, passed: false, detail: "toolbar currency \(forced)")
      }

      guard let noon = octoberEighth2026() else {
        return Result(name: name, passed: false, detail: "date components")
      }
      guard let afternoon = utcDate(year: 2026, month: 10, day: 8, hour: 17, minute: 52, second: 0)
      else {
        return Result(name: name, passed: false, detail: "date components")
      }
      let serial = ExcelDate.serial(from: noon)
      let afternoonSerial = ExcelDate.serialWithTime(from: afternoon)
      let dates: [(String, String)] = [
        (shown(serial, code: "dd/mm/yyyy"), "08/10/2026"),
        (shown(serial, code: "d-mmm-yy"), "8-Oct-26"),
        (shown(serial, code: "m/d/yyyy"), "10/8/2026"),
        (shown(serial, code: "yyyy-mm-dd"), "2026-10-08"),
        (shown(serial, code: "d \"of\" mmm yyyy"), "8 of Oct 2026"),
        (shown(0.75, code: "h:mm"), "18:00"),
        (shown(0.75, code: "h:mm AM/PM"), "6:00 PM"),
        (shown(afternoonSerial, code: "h:mm AM/PM"), "5:52 PM"),
        (shown(afternoonSerial, code: "h:mm"), "17:52"),
        (shown(afternoonSerial, code: "m/d/yyyy h:mm AM/PM"), "10/8/2026 5:52 PM"),
        (shown(0.75, code: "h:mm \"AM\""), "18:00 AM"),
        (shown(0.75, code: "h\"h\" mm\"m\""), "18h 00m"),
        (shown(1.5, code: "[h]:mm:ss"), "36:00:00"),
        (shown(1.5, code: "[h]:mm \"sec\""), "36:00"),
      ]
      for (actual, expected) in dates where actual != expected {
        return Result(name: name, passed: false, detail: "\(actual) expected \(expected)")
      }

      do {
        var sheet = Sheet(name: "Formats")
        var euro = CellFormat()
        euro.numberFormat = .currency
        euro.formatCode = "€#,##0.00"
        sheet.setCell(Cell(raw: "1234.5", format: euro), at: CellAddress(row: 0, col: 0))
        var toolbar = CellFormat()
        toolbar.numberFormat = .currency
        sheet.setCell(Cell(raw: "1234.5", format: toolbar), at: CellAddress(row: 1, col: 0))
        var dated = CellFormat()
        dated.numberFormat = .date
        sheet.setCell(Cell(raw: String(serial), format: dated), at: CellAddress(row: 2, col: 0))
        var custom = CellFormat()
        custom.formatCode = sections
        custom.numberFormat = .number
        sheet.setCell(Cell(raw: "1234.5", format: custom), at: CellAddress(row: 3, col: 0))
        sheet.setCell(Cell(raw: "Hello", format: custom), at: CellAddress(row: 4, col: 0))

        let data = try XLSXCodec.exportWorkbook(Workbook(sheets: [sheet]))
        let imported = try XLSXCodec.importWorkbook(from: data)
        let euroCell = imported.sheets[0].cell(at: CellAddress(row: 0, col: 0))
        let euroShown = CellFormatRenderer.displayText(
          for: .number(1234.5),
          format: euroCell.format,
          fallbackRaw: euroCell.raw
        )
        if euroCell.format?.formatCode != "€#,##0.00" || euroShown != "€1,234.50" {
          return Result(
            name: name, passed: false,
            detail: "euro reimport \(euroCell.format?.formatCode ?? "") \(euroShown)")
        }
        let dollar = imported.sheets[0].cell(at: CellAddress(row: 1, col: 0))
        let dollarShown = CellFormatRenderer.displayText(
          for: .number(1234.5),
          format: dollar.format,
          fallbackRaw: dollar.raw
        )
        if dollar.format?.formatCode != "$#,##0.00" || dollarShown != "$1,234.50" {
          return Result(
            name: name, passed: false,
            detail: "currency reimport \(dollar.format?.formatCode ?? "") \(dollarShown)")
        }
        if imported.sheets[0].cell(at: CellAddress(row: 2, col: 0)).format?.formatCode != "m/d/yyyy"
        {
          return Result(name: name, passed: false, detail: "builtin 14 code missing")
        }

        guard var styles = XLSXCodec.zipEntryString(archiveData: data, entryPath: "xl/styles.xml")
        else {
          return Result(name: name, passed: false, detail: "styles.xml missing")
        }
        guard styles.contains("numFmtId=\"14\"") else {
          return Result(name: name, passed: false, detail: "date did not export as builtin 14")
        }
        styles = styles.replacingOccurrences(of: "numFmtId=\"14\"", with: "numFmtId=\"15\"")
        guard
          let patched = XLSXCodec.replacingZipEntries(
            data, entries: ["xl/styles.xml": Data(styles.utf8)])
        else {
          return Result(name: name, passed: false, detail: "could not patch styles")
        }
        let builtin = try XLSXCodec.importWorkbook(from: patched)
        let dateCell = builtin.sheets[0].cell(at: CellAddress(row: 2, col: 0))
        let dateShown = CellFormatRenderer.displayText(
          for: .number(serial), format: dateCell.format, fallbackRaw: dateCell.raw)
        if dateCell.format?.formatCode != "d-mmm-yy" || dateShown != "8-Oct-26" {
          return Result(
            name: name, passed: false,
            detail: "builtin 15 \(dateCell.format?.formatCode ?? "") \(dateShown)")
        }
        let customNumber = imported.sheets[0].cell(at: CellAddress(row: 3, col: 0))
        let customShown = CellFormatRenderer.displayText(
          for: .number(1234.5),
          format: customNumber.format,
          fallbackRaw: customNumber.raw
        )
        if customNumber.format?.formatCode != sections || customShown != "1,234.50" {
          return Result(
            name: name, passed: false,
            detail: "custom reimport \(customNumber.format?.formatCode ?? "") \(customShown)")
        }
        let customText = imported.sheets[0].cell(at: CellAddress(row: 4, col: 0))
        let textShown = CellFormatRenderer.displayText(
          for: .string("Hello"), format: customText.format, fallbackRaw: "Hello")
        let rawShown = CellFormatRenderer.displayText(raw: "Hello", format: customText.format)
        if customText.format?.formatCode != sections || textShown != "id Hello"
          || rawShown != "id Hello"
        {
          return Result(
            name: name, passed: false,
            detail: "text reimport \(customText.format?.formatCode ?? "") \(textShown) \(rawShown)")
        }
      } catch {
        return Result(name: name, passed: false, detail: error.localizedDescription)
      }
      return Result(name: name, passed: true, detail: "sections, quotes, symbol, and date pattern")
    }

    private static func definedNamesResolve() -> Result {
      let name = "defined names resolve"
      var sheet = Sheet(name: "Q3 Sales")
      sheet.setCell(Cell(raw: "10"), at: CellAddress(row: 0, col: 0))
      sheet.setCell(Cell(raw: "20"), at: CellAddress(row: 1, col: 0))
      sheet.setCell(Cell(raw: "4"), at: CellAddress(row: 0, col: 1))
      sheet.setCell(Cell(raw: "=SUM(Sales)"), at: CellAddress(row: 0, col: 2))
      sheet.setCell(Cell(raw: "=Rate"), at: CellAddress(row: 1, col: 2))
      var workbook = Workbook(sheets: [sheet])
      workbook.setNamedRange(
        NamedRange(
          name: "Sales",
          sheetName: "Q3 Sales",
          range: CellRange(start: CellAddress(row: 0, col: 0), end: CellAddress(row: 1, col: 0))
        )
      )
      do {
        let data = try XLSXCodec.exportWorkbook(workbook)
        let roundTrip = try XLSXCodec.importWorkbook(from: data)
        let engine = FormulaEngine()
        engine.rebuild(workbook: roundTrip, recalculate: true)
        let summed = engine.displayValue(
          at: CellAddress(row: 0, col: 2), sheet: roundTrip.activeSheet)
        if summed != .number(30) || roundTrip.namedRange(named: "Sales") == nil {
          return Result(
            name: name, passed: false, detail: "exported Sales resolved to \(summed.displayString)")
        }

        guard var xml = XLSXCodec.zipEntryString(archiveData: data, entryPath: "xl/workbook.xml"),
          let start = xml.range(of: "<definedNames"),
          let end = xml.range(of: "</definedNames>")
        else {
          return Result(name: name, passed: false, detail: "workbook.xml has no definedNames")
        }
        let excelNames = """
          <definedNames>\
          <definedName name="Sales">'Q3 Sales'!$A$1:$A$2</definedName>\
          <definedName name="Rate">'q3 sales'!$B$1</definedName>\
          <definedName name="Broken">OFFSET('Q3 Sales'!$A$1,0,0)</definedName>\
          </definedNames>
          """
        xml.replaceSubrange(start.lowerBound..<end.upperBound, with: excelNames)
        guard
          let patched = XLSXCodec.replacingZipEntries(
            data, entries: ["xl/workbook.xml": Data(xml.utf8)])
        else {
          return Result(name: name, passed: false, detail: "could not patch workbook.xml")
        }
        let imported = try XLSXCodec.importWorkbook(from: patched)
        guard let broken = imported.namedRange(named: "Broken"),
          broken.resolvesToRange == false,
          broken.refersTo?.contains("OFFSET") == true
        else {
          return Result(name: name, passed: false, detail: "OFFSET name was dropped or resolved")
        }
        guard let sales = imported.namedRange(named: "Sales"),
          sales.resolvesToRange,
          sales.sheetName == "Q3 Sales",
          sales.startRow == 0, sales.endRow == 1, sales.startCol == 0,
          let rate = imported.namedRange(named: "Rate"),
          rate.resolvesToRange,
          rate.sheetName == "Q3 Sales",
          rate.startRow == 0, rate.startCol == 1, rate.endRow == 0, rate.endCol == 1
        else {
          return Result(name: name, passed: false, detail: "Sales or Rate did not parse")
        }
        var withFormula = imported
        var formulaSheet = withFormula.activeSheet
        formulaSheet.setCell(Cell(raw: "=Broken"), at: CellAddress(row: 3, col: 0))
        withFormula.activeSheet = formulaSheet
        let patchedEngine = FormulaEngine()
        patchedEngine.rebuild(workbook: withFormula, recalculate: true)
        let total = patchedEngine.displayValue(
          at: CellAddress(row: 0, col: 2), sheet: withFormula.activeSheet)
        let rateValue = patchedEngine.displayValue(
          at: CellAddress(row: 1, col: 2), sheet: withFormula.activeSheet)
        let offsetValue = patchedEngine.displayValue(
          at: CellAddress(row: 3, col: 0), sheet: withFormula.activeSheet)
        if total != .number(30) || rateValue != .number(4) || offsetValue != .error(.name) {
          return Result(
            name: name,
            passed: false,
            detail:
              "SUM(Sales)=\(total.displayString) Rate=\(rateValue.displayString) OFFSET=\(offsetValue.displayString)"
          )
        }
        let again = try XLSXCodec.exportWorkbook(imported)
        let workbookXML =
          XLSXCodec.zipEntryString(archiveData: again, entryPath: "xl/workbook.xml") ?? ""
        if !workbookXML.contains("name=\"Broken\"") || !workbookXML.contains("OFFSET") {
          return Result(name: name, passed: false, detail: "export replaced OFFSET with a range")
        }
      } catch {
        return Result(name: name, passed: false, detail: error.localizedDescription)
      }
      return Result(
        name: name, passed: true, detail: "Sales and Rate resolve; OFFSET stays unresolved")
    }

    private static func nameManagerEditsSheet() -> Result {
      let name = "name manager edits"
      var sheet = Sheet(name: "Sheet1")
      sheet.setCell(Cell(raw: "10"), at: CellAddress(row: 0, col: 0))
      sheet.setCell(Cell(raw: "20"), at: CellAddress(row: 1, col: 0))
      sheet.setCell(Cell(raw: "=SUM(Sales)"), at: CellAddress(row: 2, col: 0))
      let viewModel = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
      if let error = viewModel.upsertDefinedName(
        originalName: nil, name: "Sales", refersTo: "Sheet1!$A$1:$A$2")
      {
        return Result(name: name, passed: false, detail: error)
      }
      if viewModel.displayValue(at: CellAddress(row: 2, col: 0)) != .number(30) {
        return Result(name: name, passed: false, detail: "add did not sum Sales")
      }
      if let error = viewModel.upsertDefinedName(
        originalName: "Sales", name: "Sales", refersTo: "Sheet1!$A$1")
      {
        return Result(name: name, passed: false, detail: error)
      }
      if viewModel.displayValue(at: CellAddress(row: 2, col: 0)) != .number(10) {
        return Result(name: name, passed: false, detail: "reference change did not update SUM")
      }
      if let error = viewModel.upsertDefinedName(
        originalName: "Sales", name: "Revenue", refersTo: "Sheet1!$A$1")
      {
        return Result(name: name, passed: false, detail: error)
      }
      if viewModel.activeSheet.cell(at: CellAddress(row: 2, col: 0)).raw != "=SUM(Revenue)" {
        return Result(
          name: name,
          passed: false,
          detail: "rename left \(viewModel.activeSheet.cell(at: CellAddress(row: 2, col: 0)).raw)"
        )
      }
      if let error = viewModel.upsertDefinedName(
        originalName: nil,
        name: "Grow",
        refersTo: "OFFSET(Sheet1!$A$1,0,0,2,1)"
      ) {
        return Result(name: name, passed: false, detail: error)
      }
      guard let grow = viewModel.workbook.namedRange(named: "Grow"), grow.resolvesToRange == false
      else {
        return Result(name: name, passed: false, detail: "OFFSET was stored as a range")
      }
      viewModel.setCellValue("=Grow", at: CellAddress(row: 3, col: 0))
      if viewModel.displayValue(at: CellAddress(row: 3, col: 0)) != .error(.name) {
        return Result(name: name, passed: false, detail: "OFFSET name resolved")
      }
      viewModel.deleteDefinedName(named: "Revenue")
      if viewModel.workbook.namedRange(named: "Revenue") != nil
        || viewModel.displayValue(at: CellAddress(row: 2, col: 0)) != .error(.name)
      {
        return Result(name: name, passed: false, detail: "delete left Revenue in use")
      }
      return Result(
        name: name, passed: true, detail: "add, retarget, rename, unresolved formula, delete")
    }

    private static func cellFormatApplyCloses() -> Result {
      let name = "cell format apply closes"
      let apply = CellFormatPanel.result(for: .apply)
      if !apply.storesDraft || !apply.closes {
        return Result(
          name: name, passed: false,
          detail: "apply stores \(apply.storesDraft) closes \(apply.closes)")
      }
      let close = CellFormatPanel.result(for: .close)
      if close.storesDraft || !close.closes {
        return Result(
          name: name, passed: false,
          detail: "close stores \(close.storesDraft) closes \(close.closes)")
      }
      let away = CellFormatPanel.result(for: .clickAway)
      if away.storesDraft || away.closes {
        return Result(
          name: name, passed: false,
          detail: "click away stores \(away.storesDraft) closes \(away.closes)")
      }

      var sheet = Sheet(name: "Sheet1")
      sheet.setCell(Cell(raw: "1.5"), at: .origin)
      let viewModel = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
      viewModel.selection = .origin
      var closed = false
      CellFormatPanel.perform(
        .apply,
        store: {
          viewModel.setFormatCode("[h]:mm:ss")
        },
        close: {
          closed = true
        })
      let cell = viewModel.activeSheet.cell(at: .origin)
      if !closed || cell.raw != "1.5" || cell.format?.formatCode != "[h]:mm:ss" {
        return Result(name: name, passed: false, detail: "apply raw \(cell.raw) closed \(closed)")
      }
      if viewModel.displayString(at: .origin) != "36:00:00" {
        return Result(
          name: name, passed: false, detail: "elapsed \(viewModel.displayString(at: .origin))")
      }

      var storedOnClose = false
      var closedWithoutStore = false
      CellFormatPanel.perform(
        .close, store: { storedOnClose = true }, close: { closedWithoutStore = true })
      if storedOnClose || !closedWithoutStore {
        return Result(
          name: name, passed: false,
          detail: "close stored \(storedOnClose) closed \(closedWithoutStore)")
      }
      var storedOnClick = false
      var closedOnClick = false
      CellFormatPanel.perform(
        .clickAway, store: { storedOnClick = true }, close: { closedOnClick = true })
      if storedOnClick || closedOnClick {
        return Result(
          name: name, passed: false,
          detail: "click away stored \(storedOnClick) closed \(closedOnClick)")
      }
      return Result(
        name: name, passed: true,
        detail: "apply stores and closes; close and click-away do not store")
    }

    /// ⌘V while the format field is editing inserts into the field. The cell keeps its value.
    private static func customFormatPasteStaysInField() -> Result {
      let name = "custom format paste stays in field"
      let field = CellFormatCodeTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
      field.stringValue = ""
      let window = SpellCheckWindow(
        contentRect: field.frame,
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
      )
      window.isReleasedWhenClosed = false
      window.contentView = field
      window.setFrameOrigin(NSPoint(x: -4200, y: -4200))
      window.makeKeyAndOrderFront(nil)
      defer {
        window.makeFirstResponder(nil)
        window.contentView = nil
        window.orderOut(nil)
        window.close()
      }

      let board = NSPasteboard.general
      let previous = board.string(forType: .string)
      defer {
        board.clearContents()
        if let previous {
          board.setString(previous, forType: .string)
        }
      }

      guard window.makeFirstResponder(field) else {
        return Result(name: name, passed: false, detail: "format field did not focus")
      }
      if field.currentEditor() == nil {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
      }
      guard field.isInterceptingPaste, CellFormatCodePaste.editingField === field else {
        return Result(name: name, passed: false, detail: "paste shortcut was not captured")
      }
      guard let editor = field.currentEditor() as? NSTextView else {
        return Result(name: name, passed: false, detail: "format field has no editor")
      }
      let typedColor = NSColor(srgbRed: 0.93, green: 0.94, blue: 0.96, alpha: 1)
      var typing = editor.typingAttributes
      typing[.foregroundColor] = typedColor
      editor.typingAttributes = typing
      let blackPaste = NSAttributedString(
        string: "[h]:mm:ss",
        attributes: [
          .foregroundColor: NSColor.black,
          .font: NSFont.systemFont(ofSize: 16),
        ]
      )
      board.clearContents()
      guard board.writeObjects([blackPaste]) else {
        return Result(name: name, passed: false, detail: "could not write colored pasteboard")
      }

      var sheet = Sheet(name: "Sheet1")
      sheet.setCell(Cell(raw: "1.5"), at: .origin)
      let viewModel = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
      viewModel.selection = .origin

      guard let event = commandVEvent(window: window) else {
        return Result(name: name, passed: false, detail: "could not build paste event")
      }
      if CellFormatCodePaste.handleKeyDown(event) != nil || field.liveText != "[h]:mm:ss" {
        return Result(name: name, passed: false, detail: "field text \(field.liveText)")
      }
      if let mismatch = pastedForegroundMismatch(in: field, expected: typedColor) {
        return Result(name: name, passed: false, detail: mismatch)
      }
      if viewModel.activeSheet.cell(at: .origin).raw != "1.5" {
        return Result(
          name: name, passed: false,
          detail: "paste wrote \(viewModel.activeSheet.cell(at: .origin).raw)")
      }
      viewModel.setFormatCode("[h]:mm:ss")
      if viewModel.displayString(at: .origin) != "36:00:00"
        || viewModel.activeSheet.cell(at: .origin).raw != "1.5"
      {
        return Result(
          name: name,
          passed: false,
          detail:
            "elapsed \(viewModel.displayString(at: .origin)) raw \(viewModel.activeSheet.cell(at: .origin).raw)"
        )
      }
      SpreadsheetPaste.perform(on: viewModel)
      if viewModel.activeSheet.cell(at: .origin).raw != "1.5" {
        return Result(name: name, passed: false, detail: "menu paste wrote the cell")
      }

      window.makeFirstResponder(nil)
      if field.isInterceptingPaste || CellFormatCodePaste.editingField != nil {
        return Result(
          name: name, passed: false, detail: "paste stayed captured after the field resigned")
      }
      if CellFormatCodePaste.handleKeyDown(event) == nil {
        return Result(
          name: name, passed: false, detail: "paste shortcut was swallowed after resign")
      }
      SpreadsheetPaste.perform(on: viewModel)
      if viewModel.activeSheet.cell(at: .origin).raw != "[h]:mm:ss" {
        return Result(
          name: name, passed: false,
          detail: "grid paste \(viewModel.activeSheet.cell(at: .origin).raw)")
      }
      return Result(
        name: name, passed: true,
        detail:
          "focused paste stays in the field, in the typed color; grid paste still writes the cell")
    }

    /// Pasted runs must use the field's typing color, not the pasteboard's black foreground.
    private static func pastedForegroundMismatch(
      in field: CellFormatCodeTextField, expected: NSColor
    ) -> String? {
      guard let editor = field.currentEditor() as? NSTextView, let storage = editor.textStorage,
        storage.length > 0
      else {
        return "pasted text has no color run"
      }
      var index = 0
      while index < storage.length {
        var run = NSRange(location: 0, length: 0)
        let color = storage.attribute(.foregroundColor, at: index, effectiveRange: &run) as? NSColor
        if !sameForeground(color, expected) {
          return "paste color \(color.map { "\($0)" } ?? "nil") expected typed color"
        }
        let next = max(NSMaxRange(run), index + 1)
        index = next
      }
      return nil
    }

    private static func sameForeground(_ lhs: NSColor?, _ rhs: NSColor) -> Bool {
      guard let left = lhs?.usingColorSpace(.sRGB), let right = rhs.usingColorSpace(.sRGB) else {
        return false
      }
      let slop = 0.02
      return abs(left.redComponent - right.redComponent) < slop
        && abs(left.greenComponent - right.greenComponent) < slop
        && abs(left.blueComponent - right.blueComponent) < slop
        && abs(left.alphaComponent - right.alphaComponent) < slop
    }

    private static func commandVEvent(window: NSWindow) -> NSEvent? {
      NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: .command,
        timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: window.windowNumber,
        context: nil,
        characters: "v",
        charactersIgnoringModifiers: "v",
        isARepeat: false,
        keyCode: 9
      )
    }

    private static func cellFormatCodeEditsSheet() -> Result {
      let name = "cell format code edits"
      var sheet = Sheet(name: "Sheet1")
      sheet.setCell(Cell(raw: "1234.5"), at: .origin)
      let viewModel = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
      viewModel.selection = .origin
      viewModel.setFormatCode("#,##0.00")
      let grouped = viewModel.displayString(at: .origin)
      if grouped != "1,234.50" || viewModel.selectedFormat.formatCode != "#,##0.00" {
        return Result(name: name, passed: false, detail: "thousands \(grouped)")
      }
      viewModel.setFormatCode("$#,##0.00")
      let currency = viewModel.displayString(at: .origin)
      if currency != "$1,234.50" || viewModel.selectedFormat.numberFormat != .currency {
        return Result(name: name, passed: false, detail: "currency \(currency)")
      }
      guard let noon = octoberEighth2026() else {
        return Result(name: name, passed: false, detail: "date components")
      }
      let serial = ExcelDate.serial(from: noon)
      viewModel.setCellValue(String(serial), at: .origin)
      viewModel.setFormatCode("d-mmm-yy")
      let dated = viewModel.displayString(at: .origin)
      if dated != "8-Oct-26" || viewModel.selectedFormat.numberFormat != .date {
        return Result(name: name, passed: false, detail: "date \(dated)")
      }
      viewModel.setCellValue("0.75", at: .origin)
      viewModel.setFormatCode("h:mm AM/PM")
      let timed = viewModel.displayString(at: .origin)
      if timed != "6:00 PM" || viewModel.selectedFormat.numberFormat != .time {
        return Result(name: name, passed: false, detail: "time \(timed)")
      }
      viewModel.setCellValue("1234.5", at: .origin)
      viewModel.setFormatCode(nil)
      let cleared = viewModel.displayString(at: .origin)
      if cleared != "1234.5" || viewModel.selectedFormat.formatCode != nil
        || viewModel.selectedFormat.numberFormat != .general
      {
        return Result(name: name, passed: false, detail: "clear \(cleared)")
      }

      let sections = "#,##0.00;(#,##0.00);\"zero\";\"id \"@"
      viewModel.setFormatCode(sections)
      if viewModel.displayString(at: .origin) != "1,234.50"
        || viewModel.selectedFormat.formatCode != sections
      {
        return Result(
          name: name, passed: false, detail: "apply \(viewModel.displayString(at: .origin))")
      }
      viewModel.setCellValue("-8", at: .origin)
      if viewModel.displayString(at: .origin) != "(8.00)" {
        return Result(
          name: name, passed: false,
          detail: "negative section \(viewModel.displayString(at: .origin))")
      }
      viewModel.setCellValue("0", at: .origin)
      if viewModel.displayString(at: .origin) != "zero" {
        return Result(
          name: name, passed: false, detail: "zero section \(viewModel.displayString(at: .origin))")
      }
      viewModel.setCellValue("Hello", at: .origin)
      if viewModel.displayString(at: .origin) != "id Hello" {
        return Result(
          name: name, passed: false, detail: "text section \(viewModel.displayString(at: .origin))")
      }

      viewModel.setCellValue("1234.5", at: .origin)
      viewModel.setFormatCode("#,##0.00")
      viewModel.setNumberFormat(.number)
      if viewModel.selectedFormat.formatCode != nil
        || viewModel.displayString(at: .origin) != "1234.50"
      {
        return Result(
          name: name, passed: false,
          detail:
            "number preset left \(viewModel.selectedFormat.formatCode ?? "nil") \(viewModel.displayString(at: .origin))"
        )
      }
      viewModel.setFormatCode("€#,##0.00")
      viewModel.setNumberFormat(.currency)
      if viewModel.selectedFormat.formatCode != nil
        || viewModel.displayString(at: .origin) != "$1234.50"
      {
        return Result(
          name: name, passed: false,
          detail:
            "currency preset left \(viewModel.selectedFormat.formatCode ?? "nil") \(viewModel.displayString(at: .origin))"
        )
      }
      viewModel.setFormatCode("0.00%")
      viewModel.setNumberFormat(.general)
      if viewModel.selectedFormat.formatCode != nil
        || viewModel.displayString(at: .origin) != "1234.5"
      {
        return Result(
          name: name, passed: false,
          detail:
            "general preset left \(viewModel.selectedFormat.formatCode ?? "nil") \(viewModel.displayString(at: .origin))"
        )
      }
      viewModel.setCellValue("0.5", at: .origin)
      viewModel.setFormatCode("0%")
      viewModel.setNumberFormat(.percent)
      if viewModel.selectedFormat.formatCode != nil
        || viewModel.displayString(at: .origin) != "50.00%"
      {
        return Result(
          name: name, passed: false,
          detail:
            "percent preset left \(viewModel.selectedFormat.formatCode ?? "nil") \(viewModel.displayString(at: .origin))"
        )
      }
      viewModel.setCellValue("1234", at: .origin)
      viewModel.setFormatCode("0.00E+00")
      viewModel.setNumberFormat(.scientific)
      if viewModel.selectedFormat.formatCode != nil
        || viewModel.displayString(at: .origin) != "1.23e+03"
      {
        return Result(
          name: name, passed: false,
          detail:
            "scientific preset left \(viewModel.selectedFormat.formatCode ?? "nil") \(viewModel.displayString(at: .origin))"
        )
      }
      guard let presetNoon = octoberEighth2026() else {
        return Result(name: name, passed: false, detail: "date components")
      }
      viewModel.setCellValue(String(ExcelDate.serial(from: presetNoon)), at: .origin)
      viewModel.setFormatCode("d-mmm-yy")
      viewModel.setNumberFormat(.date)
      if viewModel.selectedFormat.formatCode != nil
        || viewModel.displayString(at: .origin) != "10/8/2026"
      {
        return Result(
          name: name, passed: false,
          detail:
            "date preset left \(viewModel.selectedFormat.formatCode ?? "nil") \(viewModel.displayString(at: .origin))"
        )
      }
      viewModel.setCellValue("0.75", at: .origin)
      viewModel.setFormatCode("h:mm")
      viewModel.setNumberFormat(.time)
      if viewModel.selectedFormat.formatCode != nil
        || viewModel.displayString(at: .origin) != "6:00:00 PM"
      {
        return Result(
          name: name, passed: false,
          detail:
            "time preset left \(viewModel.selectedFormat.formatCode ?? "nil") \(viewModel.displayString(at: .origin))"
        )
      }
      viewModel.setCellValue("1234.5", at: .origin)

      viewModel.setFormatCode(sections)
      do {
        let data = try XLSXCodec.exportWorkbook(viewModel.workbook)
        let imported = try XLSXCodec.importWorkbook(from: data)
        let cell = imported.sheets[0].cell(at: .origin)
        let shown = CellFormatRenderer.displayText(
          for: .number(1234.5), format: cell.format, fallbackRaw: cell.raw)
        if cell.format?.formatCode != sections || cell.raw != "1234.5" || shown != "1,234.50" {
          return Result(
            name: name, passed: false, detail: "reopen \(cell.format?.formatCode ?? "") \(shown)")
        }
      } catch {
        return Result(name: name, passed: false, detail: error.localizedDescription)
      }
      return Result(name: name, passed: true, detail: "custom code, text section, preset clears it")
    }

    private static func conditionalBoldUncheckPersists() -> Result {
      let name = "conditional bold uncheck"
      func byteColor(_ red: Int, _ green: Int, _ blue: Int) -> CodableColor {
        CodableColor(
          red: Double(red) / 255,
          green: Double(green) / 255,
          blue: Double(blue) / 255,
          alpha: 1
        )
      }
      func sameColor(_ lhs: CodableColor?, _ rhs: CodableColor?) -> Bool {
        guard let lhs, let rhs else { return lhs == nil && rhs == nil }
        func byte(_ value: Double) -> Int { Int((value * 255).rounded()) }
        return byte(lhs.red) == byte(rhs.red)
          && byte(lhs.green) == byte(rhs.green)
          && byte(lhs.blue) == byte(rhs.blue)
          && byte(lhs.alpha) == byte(rhs.alpha)
      }
      func fail(_ detail: String) -> Result {
        Result(name: name, passed: false, detail: detail)
      }
      // A bold element ends at `b`: `<b/>`, `<b val="0"/>`, `<x14:b/>`.
      // `<bgColor` and `<x14:bgColor` share the prefix `<b` / `<x14:b` and are fill.
      func writesBoldTag(_ xml: String) -> Bool {
        xml.range(of: #"<(?:x14:)?b(?:\s|/|>)"#, options: .regularExpression) != nil
      }

      let fill = byteColor(245, 199, 199)
      let text = byteColor(153, 0, 16)
      let otherFill = byteColor(216, 243, 220)
      let onStyle = ConditionalFormatStyle(
        bold: true, italic: true, textColor: text, fillColor: fill)

      if ConditionalFormatStyle.preservedCheckbox(isOn: false, previous: false) != false
        || ConditionalFormatStyle.preservedCheckbox(isOn: true, previous: false) != true
        || ConditionalFormatStyle.preservedCheckbox(isOn: false, previous: true) != nil
        || ConditionalFormatStyle.preservedCheckbox(isOn: false, previous: nil) != nil
      {
        return fail("italic off was not kept when bold was saved")
      }

      var italicOff = onStyle
      italicOff.italic = false
      let boldCleared = italicOff.withBoldCheckbox(isOn: false, previous: true, touched: true)
      if boldCleared.bold != false || boldCleared.italic != false
        || !sameColor(boldCleared.textColor, text) || !sameColor(boldCleared.fillColor, fill)
      {
        return fail("unchecking bold cleared italic off or another field")
      }

      let unchecked = onStyle.withBoldCheckbox(isOn: false, previous: true, touched: false)
      if unchecked.bold != false || unchecked.italic != true
        || !sameColor(unchecked.textColor, text) || !sameColor(unchecked.fillColor, fill)
      {
        return fail(
          "uncheck stored \(String(describing: unchecked.bold)) and dropped another field")
      }
      if unchecked.bold == true {
        return fail("reselect still shows bold on")
      }

      let checkedAgain = unchecked.withBoldCheckbox(
        isOn: true, previous: unchecked.bold, touched: true)
      if checkedAgain.bold != true || checkedAgain.italic != true
        || !sameColor(checkedAgain.textColor, text) || !sameColor(checkedAgain.fillColor, fill)
      {
        return fail("checking bold did not save, or cleared another field")
      }

      let unspecified = ConditionalFormatStyle(italic: true, textColor: text, fillColor: fill)
      let untouched = unspecified.withBoldCheckbox(isOn: false, previous: nil, touched: false)
      if untouched.bold != nil || untouched.italic != true || !sameColor(untouched.fillColor, fill)
      {
        return fail(
          "an edit that leaves Bold alone forced bold \(String(describing: untouched.bold))")
      }

      var boldCell = CellFormat()
      boldCell.bold = true
      if unchecked.applying(to: boldCell).bold != false
        || unchecked.applying(to: boldCell).italic != true
      {
        return fail("explicit bold off did not clear a bold cell")
      }
      if unspecified.applying(to: boldCell).bold != true {
        return fail("unspecified bold cleared a bold cell")
      }

      let scheme = ThemeColorScheme()
      let excelOff = """
        <font><b val="0"/><i/><color rgb="FF990010"/></font><fill><patternFill patternType="solid"><bgColor rgb="FFF5C7C7"/></patternFill></fill>
        """
      let parsedOff = XLSXCodec.parseDxfBody(excelOff, themeScheme: scheme)
      if parsedOff.bold != false || parsedOff.italic != true
        || !sameColor(parsedOff.textColor, text) || !sameColor(parsedOff.fillColor, fill)
      {
        return fail(
          "Excel val=0 imported as \(String(describing: parsedOff.bold)) text=\(parsedOff.textColor != nil) fill=\(parsedOff.fillColor != nil) italic=\(String(describing: parsedOff.italic))"
        )
      }
      let parsedOn = XLSXCodec.parseDxfBody(
        "<font><b/></font><fill><patternFill><bgColor rgb=\"FFF5C7C7\"/></patternFill></fill>",
        themeScheme: scheme)
      if parsedOn.bold != true || !sameColor(parsedOn.fillColor, fill) {
        return fail("bare <b/> should stay on with its fill")
      }
      let parsedValOn = XLSXCodec.parseDxfBody(#"<font><b val="1"/></font>"#, themeScheme: scheme)
      if parsedValOn.bold != true {
        return fail("val=1 should be bold")
      }
      let parsedFalse = XLSXCodec.parseDxfBody(
        #"<font><i val="0"/></font><fill><patternFill><bgColor rgb="FFF5C7C7"/></patternFill></fill>"#,
        themeScheme: scheme)
      if parsedFalse.italic != false || parsedFalse.bold != nil
        || !sameColor(parsedFalse.fillColor, fill)
      {
        return fail("italic val=0 changed bold or fill")
      }
      let x14Off = XLSXCodec.parseDxfBody(
        #"<x14:font><x14:b val="0"/><x14:color rgb="FF990010"/></x14:font><x14:fill><x14:patternFill patternType="solid"><x14:bgColor rgb="FFF5C7C7"/></x14:patternFill></x14:fill>"#,
        themeScheme: scheme
      )
      if x14Off.bold != false || !sameColor(x14Off.textColor, text)
        || !sameColor(x14Off.fillColor, fill)
      {
        return fail(
          "x14 val=0 imported as \(String(describing: x14Off.bold)) text=\(x14Off.textColor != nil) fill=\(x14Off.fillColor != nil)"
        )
      }
      let fillOnly = XLSXCodec.parseDxfBody(
        #"<fill><patternFill><bgColor rgb="FFF5C7C7"/></patternFill></fill>"#, themeScheme: scheme)
      if fillOnly.bold != nil || !sameColor(fillOnly.fillColor, fill) {
        return fail("bgColor was read as bold")
      }

      let offRule = ConditionalFormatRule(
        range: CellRange(start: .origin, end: CellAddress(row: 3, col: 0)),
        predicate: .greaterThan(10),
        style: unchecked
      )
      let onRule = ConditionalFormatRule(
        range: CellRange(start: CellAddress(row: 0, col: 1), end: CellAddress(row: 1, col: 1)),
        predicate: .lessThan(5),
        style: ConditionalFormatStyle(bold: true, textColor: text, fillColor: otherFill)
      )
      var sheet = Sheet(name: "Rules")
      sheet.conditionalFormats = [offRule, onRule]
      do {
        let data = try XLSXCodec.exportWorkbook(Workbook(sheets: [sheet]))
        let styles = XLSXCodec.zipEntryString(archiveData: data, entryPath: "xl/styles.xml") ?? ""
        let worksheet =
          XLSXCodec.zipEntryString(archiveData: data, entryPath: "xl/worksheets/sheet1.xml") ?? ""
        // Rules are saved once, in the sheet (Nov 4): no extension copy for Excel to ignore and
        // Google Sheets to trip on. Bold off lives in the rule's style as val="0".
        if !styles.contains(#"<b val="0"/>"#) || worksheet.contains("x14:cfRule") {
          return fail("explicit bold off was not written as val=0, or a rule was saved twice")
        }
        if !styles.contains("<b/>") && !styles.contains("<b val=\"1\"/>") {
          return fail("checked bold was not written")
        }
        let imported = try XLSXCodec.importWorkbook(from: data)
        let rules = imported.activeSheet.conditionalFormats
        guard let off = rules.first(where: { $0.predicate == .greaterThan(10) }),
          let on = rules.first(where: { $0.predicate == .lessThan(5) })
        else {
          return fail("reopen lost a rule \(rules.map(\.predicate))")
        }
        if off.style.bold != false || off.range.a1Label != "A1:A4" || off.style.italic != true
          || !sameColor(off.style.textColor, text) || !sameColor(off.style.fillColor, fill)
        {
          return fail(
            "reopen bold=\(String(describing: off.style.bold)) range=\(off.range.a1Label) italic=\(String(describing: off.style.italic))"
          )
        }
        if on.style.bold != true || !sameColor(on.style.fillColor, otherFill)
          || !sameColor(on.style.textColor, text)
        {
          return fail(
            "checked rule did not survive reopen bold=\(String(describing: on.style.bold))")
        }
      } catch {
        return fail(error.localizedDescription)
      }

      var plain = Sheet(name: "Plain")
      plain.conditionalFormats = [
        ConditionalFormatRule(
          range: CellRange(start: .origin, end: .origin),
          predicate: .greaterThan(1),
          style: unspecified
        )
      ]
      do {
        let data = try XLSXCodec.exportWorkbook(Workbook(sheets: [plain]))
        let styles = XLSXCodec.zipEntryString(archiveData: data, entryPath: "xl/styles.xml") ?? ""
        let worksheet =
          XLSXCodec.zipEntryString(archiveData: data, entryPath: "xl/worksheets/sheet1.xml") ?? ""
        if !writesBoldTag("<b/>")
          || !writesBoldTag(#"<b val="0"/>"#)
          || !writesBoldTag("<x14:b/>")
          || !writesBoldTag(#"<x14:b val="0"/>"#)
          || writesBoldTag(#"<x14:bgColor rgb="FF"/>"#)
          || writesBoldTag(#"<bgColor rgb="FF"/>"#)
        {
          return fail("bold tag scan missed an explicit bold element")
        }
        if writesBoldTag(styles) || writesBoldTag(worksheet) {
          return fail("unspecified bold was written into the dxf")
        }
        // The fill is in the rule's style; the rule is not copied into an extension (Nov 4).
        if !styles.contains("<bgColor") || worksheet.contains("x14:cfRule") {
          return fail("fill was removed from the dxf")
        }
        let imported = try XLSXCodec.importWorkbook(from: data)
        guard let style = imported.activeSheet.conditionalFormats.first?.style else {
          return fail("unspecified rule missing after reopen")
        }
        if style.bold != nil || style.italic != true || !sameColor(style.fillColor, fill)
          || !sameColor(style.textColor, text)
        {
          return fail("unspecified bold round-trip changed \(style)")
        }
      } catch {
        return fail(error.localizedDescription)
      }

      do {
        let encoded = try JSONEncoder().encode(unchecked)
        let decoded = try JSONDecoder().decode(ConditionalFormatStyle.self, from: encoded)
        if decoded.bold != false || decoded.italic != true
          || !sameColor(decoded.textColor, text) || !sameColor(decoded.fillColor, fill)
        {
          return fail("document encoding dropped bold off")
        }
      } catch {
        return fail(error.localizedDescription)
      }

      var editSheet = Sheet(name: "Edit")
      let original = ConditionalFormatRule(
        range: CellRange(start: .origin, end: CellAddress(row: 3, col: 0)),
        predicate: .greaterThan(10),
        style: onStyle
      )
      editSheet.conditionalFormats = [original]
      let viewModel = SpreadsheetViewModel(workbook: Workbook(sheets: [editSheet]))
      guard let current = viewModel.activeSheet.conditionalFormats.first,
        var edited = current.edited(rangeText: "A1:A4", primary: "10", secondary: "")
      else {
        return fail("could not load the rule for edit")
      }
      edited.style = current.style.withBoldCheckbox(
        isOn: false, previous: current.style.bold, touched: true)
      viewModel.replaceConditionalFormatRule(edited)
      guard let stored = viewModel.activeSheet.conditionalFormats.first else {
        return fail("rule disappeared after uncheck")
      }
      if stored.style.bold != false || stored.style.italic != true
        || !sameColor(stored.style.textColor, text) || !sameColor(stored.style.fillColor, fill)
        || stored.predicate != .greaterThan(10) || stored.range.a1Label != "A1:A4"
      {
        return fail("sheet kept bold \(String(describing: stored.style.bold)) after uncheck")
      }
      guard
        let reselected = viewModel.activeSheet.conditionalFormats.first(where: {
          $0.id == stored.id
        })
      else {
        return fail("reselect missed the rule")
      }
      if reselected.style.bold == true {
        return fail("reselect shows bold on")
      }
      var turnedOn = reselected
      turnedOn.style = reselected.style.withBoldCheckbox(
        isOn: true, previous: reselected.style.bold, touched: true)
      viewModel.replaceConditionalFormatRule(turnedOn)
      guard let afterCheck = viewModel.activeSheet.conditionalFormats.first else {
        return fail("rule disappeared after check")
      }
      if afterCheck.style.bold != true || afterCheck.style.italic != true
        || !sameColor(afterCheck.style.fillColor, fill)
        || !sameColor(afterCheck.style.textColor, text)
      {
        return fail("checking bold on the stored rule did not save")
      }
      return Result(
        name: name, passed: true,
        detail: "bold off stays off; bold on still saves; fill, italic, and text stay")
    }

    private static func conditionalFormatRuleEdit() -> Result {
      let name = "conditional format rule edit"
      var sheet = Sheet(name: "Sheet1")
      let original = ConditionalFormatRule(
        range: CellRange(start: .origin, end: CellAddress(row: 9, col: 0)),
        predicate: .greaterThan(10),
        style: .redFill
      )
      sheet.conditionalFormats = [original]
      let viewModel = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
      guard
        let edited = viewModel.activeSheet.conditionalFormats[0].edited(
          rangeText: "B2:B4",
          primary: "12",
          secondary: ""
        )
      else {
        return Result(name: name, passed: false, detail: "edit helper rejected a valid rule")
      }
      viewModel.replaceConditionalFormatRule(edited)
      guard let stored = viewModel.activeSheet.conditionalFormats.first,
        stored.range.a1Label == "B2:B4",
        stored.predicate == .greaterThan(12)
      else {
        return Result(name: name, passed: false, detail: "rule was not updated on the sheet")
      }
      let untouched = ConditionalFormatRule(
        range: original.range,
        predicate: .colorScale([
          ColorScaleStop(
            type: .min, value: nil, color: CodableColor(red: 1, green: 0, blue: 0, alpha: 1)),
          ColorScaleStop(
            type: .max, value: nil, color: CodableColor(red: 0, green: 1, blue: 0, alpha: 1)),
        ]),
        style: ConditionalFormatStyle()
      )
      guard let kept = untouched.edited(rangeText: "C1:C3", primary: "", secondary: ""),
        kept.range.a1Label == "C1:C3",
        kept.predicate == untouched.predicate
      else {
        return Result(name: name, passed: false, detail: "color scale range edit changed the rule")
      }
      return Result(name: name, passed: true, detail: "stored rule range and value")
    }

    private static func cellTextOverflowAndClip() -> Result {
      let name = "cell text overflow"
      if CellFormat().textDisplay != .overflow || CellFormatRenderer.showsEllipsis(CellFormat()) {
        return Result(name: name, passed: false, detail: "default should overflow without ellipsis")
      }
      var clipFormat = CellFormat()
      clipFormat.textDisplay = .clip
      var wrapFormat = CellFormat()
      wrapFormat.textDisplay = .wrap
      if !CellFormatRenderer.showsEllipsis(clipFormat)
        || CellFormatRenderer.showsEllipsis(wrapFormat)
        || CellFormatRenderer.lineBreakMode(for: CellFormat()) != .byClipping
        || CellFormatRenderer.lineBreakMode(for: wrapFormat) != .byWordWrapping
        || CellFormatRenderer.lineBreakMode(for: clipFormat) != .byWordWrapping
      {
        return Result(
          name: name, passed: false, detail: "clip/wrap/overflow drawing modes diverged")
      }

      let origin: (Int) -> CGFloat = { CGFloat($0) * 80 }
      let width: (Int) -> CGFloat = { _ in 80 }
      let spill = CellTextLayout.overflowClip(
        cellMinX: 0,
        cellMaxX: 80,
        textWidth: 200,
        alignment: .left,
        insetX: 4,
        sourceColumns: 0...0,
        paneColumns: 0...5,
        columnOrigin: origin,
        columnWidth: width,
        blocks: { $0 == 2 }
      )
      if spill.maxX != 160 || spill.minX != 0 || spill.maxX <= 80 {
        return Result(name: name, passed: false, detail: "left overflow clip \(spill)")
      }

      let open = CellTextLayout.overflowClip(
        cellMinX: 0,
        cellMaxX: 80,
        textWidth: 200,
        alignment: .general,
        insetX: 4,
        sourceColumns: 0...0,
        paneColumns: 0...5,
        columnOrigin: origin,
        columnWidth: width,
        blocks: { _ in false }
      )
      if open.maxX <= 80 || open.maxX != 204 {
        return Result(name: name, passed: false, detail: "open overflow clip \(open)")
      }

      let blocked = CellTextLayout.overflowClip(
        cellMinX: 0,
        cellMaxX: 80,
        textWidth: 200,
        alignment: .left,
        insetX: 4,
        sourceColumns: 0...0,
        paneColumns: 0...5,
        columnOrigin: origin,
        columnWidth: width,
        blocks: { $0 == 1 }
      )
      if blocked.maxX != 80 {
        return Result(
          name: name, passed: false,
          detail: "adjacent content should stop at the border, got \(blocked)")
      }

      let right = CellTextLayout.overflowClip(
        cellMinX: 160,
        cellMaxX: 240,
        textWidth: 200,
        alignment: .right,
        insetX: 4,
        sourceColumns: 2...2,
        paneColumns: 0...5,
        columnOrigin: origin,
        columnWidth: width,
        blocks: { $0 == 0 }
      )
      if right.minX != 80 || right.maxX != 240 {
        return Result(name: name, passed: false, detail: "right overflow clip \(right)")
      }

      let center = CellTextLayout.overflowClip(
        cellMinX: 80,
        cellMaxX: 160,
        textWidth: 200,
        alignment: .center,
        insetX: 4,
        sourceColumns: 1...1,
        paneColumns: 0...5,
        columnOrigin: origin,
        columnWidth: width,
        blocks: { $0 == 0 }
      )
      if center.minX != 80 || center.maxX <= 160 {
        return Result(name: name, passed: false, detail: "center overflow clip \(center)")
      }

      var sheet = Sheet(name: "Spill")
      var fill = Cell(raw: "")
      var fillFormat = CellFormat()
      fillFormat.fillColor = CodableColor(red: 1, green: 0.2, blue: 0.2, alpha: 1)
      fill.format = fillFormat
      sheet.setCell(fill, at: CellAddress(row: 0, col: 1))
      sheet.setCell(Cell(raw: "busy"), at: CellAddress(row: 0, col: 2))
      let display: (CellAddress) -> String = { address in
        address.col == 2 ? "busy" : ""
      }
      if CellTextLayout.blocksOverflow(sheet: sheet, row: 0, column: 1, displayText: display) {
        return Result(name: name, passed: false, detail: "fill without text blocked overflow")
      }
      if !CellTextLayout.blocksOverflow(sheet: sheet, row: 0, column: 2, displayText: display) {
        return Result(name: name, passed: false, detail: "text neighbor did not block overflow")
      }

      let long = String(repeating: "alpha ", count: 30)
      var clipCell = Cell(raw: long)
      clipCell.format = clipFormat
      var overflowCell = Cell(raw: long)
      var bold = CellFormat()
      bold.bold = true
      overflowCell.format = bold
      var plain = Sheet(name: "Modes")
      plain.setCell(clipCell, at: CellAddress(row: 0, col: 0))
      plain.setCell(overflowCell, at: CellAddress(row: 1, col: 0))
      let idle: (CellAddress) -> String = { $0.row == 0 || $0.row == 1 ? long : "" }
      let columnWidth: (Int) -> CGFloat = { _ in 60 }
      let wrappedOnly = CellTextLayout.wrappedRowHeights(
        sheet: plain,
        defaultRowHeight: Workbook.defaultRowHeight,
        defaultColumnWidth: Workbook.defaultColumnWidth,
        columnWidth: columnWidth,
        displayText: idle
      )
      if wrappedOnly[0] != nil || wrappedOnly[1] != nil {
        return Result(
          name: name, passed: false, detail: "clip/overflow changed row height \(wrappedOnly)")
      }

      var wrapShort = CellFormat()
      wrapShort.textDisplay = .wrap
      var wrapLong = CellFormat()
      wrapLong.textDisplay = .wrap
      let shortText = "Hello"
      let shortHeight = CellTextLayout.preferredWrappedRowHeight(
        text: shortText,
        format: wrapShort,
        columnWidth: 60
      )
      let longHeight = CellTextLayout.preferredWrappedRowHeight(
        text: long,
        format: wrapLong,
        columnWidth: 60
      )
      if longHeight <= shortHeight || longHeight <= Workbook.defaultRowHeight {
        return Result(
          name: name, passed: false, detail: "wrap height short=\(shortHeight) long=\(longHeight)")
      }
      var wrapSheet = Sheet(name: "Wrap")
      var shortCell = Cell(raw: shortText)
      shortCell.format = wrapShort
      var longCell = Cell(raw: long)
      longCell.format = wrapLong
      wrapSheet.setCell(shortCell, at: CellAddress(row: 0, col: 0))
      wrapSheet.setCell(longCell, at: CellAddress(row: 0, col: 1))
      wrapSheet.columnWidths[0] = 60
      wrapSheet.columnWidths[1] = 60
      let heights = CellTextLayout.wrappedRowHeights(
        sheet: wrapSheet,
        defaultRowHeight: Workbook.defaultRowHeight,
        defaultColumnWidth: Workbook.defaultColumnWidth,
        columnWidth: { wrapSheet.columnWidth(for: $0, default: Workbook.defaultColumnWidth) },
        displayText: { address in wrapSheet.cell(at: address).raw }
      )
      let rowHeight = CellTextLayout.displayRowHeight(
        row: 0,
        sheet: wrapSheet,
        defaultRowHeight: Workbook.defaultRowHeight,
        wrapped: heights
      )
      if abs(rowHeight - longHeight) > 0.6 {
        return Result(
          name: name, passed: false, detail: "row used \(rowHeight), tallest is \(longHeight)")
      }

      var saved = wrapSheet
      var clipSaved = Cell(raw: "clip me")
      var clipSavedFormat = CellFormat()
      clipSavedFormat.italic = true
      clipSavedFormat.textDisplay = .clip
      clipSaved.format = clipSavedFormat
      saved.setCell(clipSaved, at: CellAddress(row: 2, col: 0))
      var overflowSaved = Cell(raw: "spill me")
      var overflowSavedFormat = CellFormat()
      overflowSavedFormat.bold = true
      overflowSaved.format = overflowSavedFormat
      saved.setCell(overflowSaved, at: CellAddress(row: 3, col: 0))
      do {
        let data = try XLSXCodec.exportWorkbook(Workbook(sheets: [saved]))
        let styles = XLSXCodec.zipEntryString(archiveData: data, entryPath: "xl/styles.xml") ?? ""
        if !styles.contains("wrapText=\"1\"") || !styles.contains("sg:textDisplay=\"clip\"")
          || !styles.contains("mc:Ignorable=\"sg\"")
        {
          return Result(name: name, passed: false, detail: "styles missing wrap or clip marker")
        }
        let imported = try XLSXCodec.importWorkbook(from: data)
        let sheet = imported.activeSheet
        let wrapCell = sheet.cell(at: CellAddress(row: 0, col: 0))
        let tallCell = sheet.cell(at: CellAddress(row: 0, col: 1))
        let clipRoundTrip = sheet.cell(at: CellAddress(row: 2, col: 0))
        let overflowRoundTrip = sheet.cell(at: CellAddress(row: 3, col: 0))
        guard wrapCell.format?.textDisplay == .wrap,
          tallCell.format?.textDisplay == .wrap,
          clipRoundTrip.format?.textDisplay == .clip,
          clipRoundTrip.format?.italic == true,
          overflowRoundTrip.format?.textDisplay == .overflow,
          overflowRoundTrip.format?.bold == true
        else {
          return Result(
            name: name,
            passed: false,
            detail:
              "round-trip wrap=\(wrapCell.format?.textDisplay == .wrap) clip=\(clipRoundTrip.format?.textDisplay == .clip) overflow=\(overflowRoundTrip.format?.textDisplay == .overflow) italic=\(clipRoundTrip.format?.italic == true) bold=\(overflowRoundTrip.format?.bold == true)"
          )
        }
      } catch {
        return Result(name: name, passed: false, detail: error.localizedDescription)
      }
      return Result(
        name: name, passed: true,
        detail: "overflow stops at content; wrap is tallest; clip keeps ellipsis")
    }

    @MainActor
    private static func cellTextWrapLayout() -> Result {
      let name = "cell text wrap layout"
      let long = String(repeating: "alpha ", count: 30)
      var sheet = Sheet(name: "Layout")
      sheet.frozenRows = 1
      sheet.columnWidths[0] = 60
      sheet.columnWidths[1] = 60
      var wrap = CellFormat()
      wrap.textDisplay = .wrap
      var tall = Cell(raw: long)
      tall.format = wrap
      var shorter = Cell(raw: "Hello")
      shorter.format = wrap
      sheet.setCell(tall, at: CellAddress(row: 0, col: 0))
      sheet.setCell(shorter, at: CellAddress(row: 0, col: 1))
      let viewModel = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
      let grid = SpreadsheetGridNSView(frame: NSRect(x: 0, y: 0, width: 1200, height: 900))
      grid.viewModel = viewModel

      let heights = CellTextLayout.wrappedRowHeights(
        sheet: viewModel.activeSheet,
        defaultRowHeight: Workbook.defaultRowHeight,
        defaultColumnWidth: Workbook.defaultColumnWidth,
        columnWidth: {
          viewModel.activeSheet.columnWidth(for: $0, default: Workbook.defaultColumnWidth)
        },
        displayText: { viewModel.displayString(at: $0) }
      )
      let expected = CellTextLayout.displayRowHeight(
        row: 0,
        sheet: viewModel.activeSheet,
        defaultRowHeight: Workbook.defaultRowHeight,
        wrapped: heights
      )
      let rowHeight = grid.rowHeight(at: 0)
      if expected <= Workbook.defaultRowHeight + 4 || abs(rowHeight - expected) > 0.6 {
        return Result(name: name, passed: false, detail: "grid row \(rowHeight) layout \(expected)")
      }

      let header = SpreadsheetGridNSView.baseHeaderSize
      let inside = header + Workbook.defaultRowHeight + 4
      if grid.rowAtContent(y: inside) != 0 {
        return Result(
          name: name, passed: false,
          detail: "hit test in the grown row returned \(grid.rowAtContent(y: inside))")
      }
      let below = header + rowHeight + 1
      if grid.rowAtContent(y: below) != 1 {
        return Result(
          name: name, passed: false,
          detail: "hit test below the grown row returned \(grid.rowAtContent(y: below))")
      }

      let selected = grid.rectForCell(row: 0, col: 0)
      let next = grid.rectForCell(row: 1, col: 0)
      if abs(selected.height - rowHeight) > 0.6 || abs(next.minY - selected.maxY) > 0.6 {
        return Result(name: name, passed: false, detail: "selection rects \(selected) \(next)")
      }
      if abs(grid.frozenRowBoundaryY() - (header + rowHeight)) > 0.6 {
        return Result(
          name: name, passed: false,
          detail: "frozen boundary \(grid.frozenRowBoundaryY()) expected \(header + rowHeight)")
      }

      grid.showEditor()
      if abs(grid.editorFrame.height - (rowHeight - 2)) > 1 {
        return Result(
          name: name, passed: false,
          detail: "editor height \(grid.editorFrame.height) row \(rowHeight)")
      }
      return Result(
        name: name, passed: true,
        detail: "hit testing, selection, freeze, and editor share \(Int(rowHeight))pt")
    }

    @MainActor
    private static func textDisplayToolbarLabel() -> Result {
      let name = "text display toolbar label"
      let overflowTitle = CellFormat.TextDisplay.overflow.toolbarTitle
      let wrapTitle = CellFormat.TextDisplay.wrap.toolbarTitle
      let clipTitle = CellFormat.TextDisplay.clip.toolbarTitle
      let mixedTitle = CellFormat.TextDisplay.mixedToolbarTitle
      let modeTitles = [overflowTitle, wrapTitle, clipTitle]
      if modeTitles != ["Overflow", "Wrap", "Clip"] || modeTitles.contains(mixedTitle) {
        return Result(
          name: name, passed: false, detail: "menu titles \(modeTitles) mixed \(mixedTitle)")
      }

      var sheet = Sheet(name: "Label")
      var wrap = CellFormat()
      wrap.textDisplay = .wrap
      var clip = CellFormat()
      clip.textDisplay = .clip
      sheet.setCell(Cell(raw: "wrap", format: wrap), at: CellAddress(row: 0, col: 0))
      sheet.setCell(Cell(raw: "clip", format: clip), at: CellAddress(row: 0, col: 1))
      sheet.setCell(Cell(raw: "plain"), at: CellAddress(row: 0, col: 2))
      var mergedWrap = CellFormat()
      mergedWrap.textDisplay = .wrap
      sheet.setCell(Cell(raw: "merged", format: mergedWrap), at: CellAddress(row: 1, col: 0))
      sheet.mergedRanges = [
        CellRange(start: CellAddress(row: 1, col: 0), end: CellAddress(row: 1, col: 1))
      ]
      let viewModel = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))

      func label(_ expected: String, detail: String) -> Result? {
        if viewModel.textDisplayToolbarTitle != expected {
          return Result(
            name: name,
            passed: false,
            detail: "\(detail) label \(viewModel.textDisplayToolbarTitle)"
          )
        }
        return nil
      }

      if let failed = label(wrapTitle, detail: "wrap cell") { return failed }
      if viewModel.uniformTextDisplay != .wrap {
        return Result(
          name: name, passed: false,
          detail: "wrap cell claimed \(String(describing: viewModel.uniformTextDisplay))")
      }

      viewModel.select(CellAddress(row: 0, col: 1))
      if let failed = label(clipTitle, detail: "clip cell") { return failed }

      viewModel.select(CellAddress(row: 0, col: 2))
      if let failed = label(overflowTitle, detail: "overflow cell") { return failed }

      viewModel.selectRange(from: CellAddress(row: 0, col: 2), to: CellAddress(row: 0, col: 3))
      if let failed = label(overflowTitle, detail: "empty neighbors") { return failed }

      viewModel.selectRange(from: CellAddress(row: 0, col: 0), to: CellAddress(row: 0, col: 1))
      if viewModel.uniformTextDisplay != nil
        || modeTitles.contains(viewModel.textDisplayToolbarTitle)
      {
        return Result(
          name: name,
          passed: false,
          detail: "mixed range claimed \(viewModel.textDisplayToolbarTitle)"
        )
      }
      if let failed = label(mixedTitle, detail: "mixed range") { return failed }

      viewModel.select(CellAddress(row: 0, col: 0))
      viewModel.commandClickCell(CellAddress(row: 0, col: 2))
      if viewModel.uniformTextDisplay != nil || viewModel.textDisplayToolbarTitle != mixedTitle {
        return Result(
          name: name,
          passed: false,
          detail: "split selection claimed \(viewModel.textDisplayToolbarTitle)"
        )
      }

      viewModel.setTextDisplay(.clip)
      if let failed = label(clipTitle, detail: "after applying clip") { return failed }
      if viewModel.activeSheet.cell(at: CellAddress(row: 0, col: 0)).format?.textDisplay != .clip
        || viewModel.activeSheet.cell(at: CellAddress(row: 0, col: 2)).format?.textDisplay != .clip
      {
        return Result(
          name: name, passed: false, detail: "clip did not apply to both selected cells")
      }

      viewModel.selectRange(from: CellAddress(row: 1, col: 0), to: CellAddress(row: 1, col: 1))
      if let failed = label(wrapTitle, detail: "merged wrap") { return failed }

      return Result(
        name: name, passed: true, detail: "label follows the selection; mixed does not name a mode")
    }

    /// Quit calls attemptClose from both the app and the window. That must show one prompt.
    @MainActor
    private static func unsavedPromptOnce() -> Result {
      let name = "unsaved prompt once"

      let cancelled = dirtyStore()
      cancelled.unsavedPromptTestAnswer = .cancel
      let delegate = SparkGridAppDelegate()
      delegate.documentStore = cancelled
      let reply = delegate.applicationShouldTerminate(NSApp)
      // Only the spreadsheet window asks to save; Settings and other windows just close.
      let documentWindow = NSWindow(
        contentRect: .zero,
        styleMask: [.titled],
        backing: .buffered,
        defer: true
      )
      documentWindow.identifier = NSUserInterfaceItemIdentifier("main-check")
      let windowClosed = delegate.windowShouldClose(documentWindow)
      if reply != .terminateCancel || windowClosed || cancelled.unsavedPromptCount != 1 {
        return Result(
          name: name,
          passed: false,
          detail:
            "cancel reply \(reply.rawValue) window \(windowClosed) prompts \(cancelled.unsavedPromptCount)"
        )
      }
      drainMainQueue()
      if cancelled.attemptClose() != false || cancelled.unsavedPromptCount != 2 {
        return Result(
          name: name, passed: false, detail: "later quit prompts \(cancelled.unsavedPromptCount)")
      }

      let discarded = dirtyStore()
      discarded.unsavedPromptTestAnswer = .discard
      if discarded.attemptClose() != true || discarded.attemptClose() != true
        || discarded.unsavedPromptCount != 1
      {
        return Result(
          name: name, passed: false, detail: "don't save prompts \(discarded.unsavedPromptCount)")
      }

      let savedURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("spark-grid-close-\(UUID().uuidString).xlsx")
      defer { try? FileManager.default.removeItem(at: savedURL) }
      let saved = dirtyStore()
      saved.fileURL = savedURL
      saved.unsavedPromptTestAnswer = .save
      if saved.attemptClose() != true {
        return Result(name: name, passed: false, detail: "save did not close")
      }
      var sheet = saved.document.workbook.activeSheet
      sheet.setCell(Cell(raw: "2"), at: CellAddress(row: 1, col: 0))
      saved.document.workbook.activeSheet = sheet
      saved.noteEdit()
      saved.documentDidChange()
      if saved.attemptClose() != true || saved.unsavedPromptCount != 1 {
        return Result(name: name, passed: false, detail: "save prompts \(saved.unsavedPromptCount)")
      }
      let deadline = Date().addingTimeInterval(30)
      var writtenRaw = ""
      var readError = ""
      while Date() < deadline {
        do {
          let written = try XLSXCodec.importWorkbook(from: savedURL)
          writtenRaw = written.activeSheet.cell(at: .origin).raw
          if writtenRaw == "1" { break }
        } catch {
          readError = error.localizedDescription
        }
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
      }
      if writtenRaw != "1" {
        let detail = readError.isEmpty ? "saved raw \(writtenRaw)" : readError
        return Result(name: name, passed: false, detail: detail)
      }

      let replaced = dirtyStore()
      replaced.unsavedPromptTestAnswer = .cancel
      replaced.newDocument()
      if replaced.unsavedPromptCount != 1
        || replaced.document.workbook.activeSheet.cell(at: .origin).raw != "1"
      {
        return Result(
          name: name, passed: false, detail: "new prompts \(replaced.unsavedPromptCount)")
      }

      let opened = dirtyStore()
      opened.unsavedPromptTestAnswer = .cancel
      let openURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("spark-grid-open-\(UUID().uuidString).xlsx")
      defer { try? FileManager.default.removeItem(at: openURL) }
      do {
        try XLSXCodec.exportWorkbook(Workbook()).write(to: openURL)
        try opened.load(from: openURL, finishesInBackground: false)
      } catch {
        return Result(name: name, passed: false, detail: error.localizedDescription)
      }
      if opened.unsavedPromptCount != 1 || opened.fileURL != nil
        || opened.document.workbook.activeSheet.cell(at: .origin).raw != "1"
      {
        return Result(
          name: name, passed: false, detail: "open prompts \(opened.unsavedPromptCount)")
      }

      return Result(name: name, passed: true, detail: "quit, New, and Open each ask once")
    }

    @MainActor
    private static func dirtyStore() -> SpreadsheetDocumentStore {
      let store = SpreadsheetDocumentStore()
      var sheet = store.document.workbook.activeSheet
      sheet.setCell(Cell(raw: "1"), at: .origin)
      store.document.workbook.activeSheet = sheet
      store.noteEdit()
      store.documentDidChange()
      return store
    }

    private static func drainMainQueue() {
      var fired = false
      DispatchQueue.main.async { fired = true }
      let deadline = Date().addingTimeInterval(1)
      while !fired, Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
      }
    }

    /// Copy carries conditional formatting onto another sheet, and onto a new range on the same sheet.
    @MainActor
    private static func conditionalFormatPaste() -> Result {
      let name = "conditional format paste"
      func fail(_ detail: String) -> Result {
        Result(name: name, passed: false, detail: detail)
      }

      var source = Sheet(name: "Source")
      source.setCell(Cell(raw: "5"), at: CellAddress(row: 0, col: 0))
      source.setCell(Cell(raw: "15"), at: CellAddress(row: 1, col: 0))
      source.setCell(Cell(raw: "8"), at: CellAddress(row: 2, col: 0))
      let block = CellRange(start: .origin, end: CellAddress(row: 2, col: 0))
      source.conditionalFormats = [
        ConditionalFormatRule(range: block, predicate: .greaterThan(10), style: .redFill),
        ConditionalFormatRule(
          range: block,
          stopIfTrue: false,
          predicate: .formula("=A1>B1"),
          style: .greenFill
        ),
        ConditionalFormatRule(range: block, predicate: .formula("=$A$1>10"), style: .yellowFill),
        ConditionalFormatRule(
          range: CellRange(start: CellAddress(row: 0, col: 2), end: CellAddress(row: 0, col: 2)),
          predicate: .greaterThan(99),
          style: .blueFill
        ),
      ]
      let testSheet = Sheet(name: "Test")
      let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [source, testSheet]))
      let originals = vm.activeSheet.conditionalFormats
      guard originals.count == 4 else {
        return fail("setup rules \(originals.count)")
      }

      vm.selectRange(from: .origin, to: CellAddress(row: 2, col: 0))
      guard vm.copySelectionToPasteboard() else { return fail("copy failed") }

      vm.selectSheet(at: 1)
      vm.selectRange(from: CellAddress(row: 4, col: 2), to: CellAddress(row: 4, col: 2))
      vm.pasteFromPasteboard()
      guard vm.activeSheet.name == "Test" else {
        return fail("paste landed on \(vm.activeSheet.name)")
      }
      guard vm.activeSheet.cell(at: CellAddress(row: 4, col: 2)).raw == "5",
        vm.activeSheet.cell(at: CellAddress(row: 5, col: 2)).raw == "15",
        vm.activeSheet.cell(at: CellAddress(row: 6, col: 2)).raw == "8"
      else { return fail("cross-sheet values missing") }
      guard vm.activeSheet.conditionalFormats.count == 3 else {
        return fail("cross-sheet rules \(describe(vm.activeSheet.conditionalFormats))")
      }
      guard
        let highlight = rule(
          vm.activeSheet.conditionalFormats, range: "C5:C7", predicate: .greaterThan(10)),
        highlight.style == .redFill
      else {
        return fail("highlight not retargeted \(describe(vm.activeSheet.conditionalFormats))")
      }
      guard
        let shifted = rule(
          vm.activeSheet.conditionalFormats, range: "C5:C7", predicate: .formula("=C5>D5")),
        shifted.style == .greenFill,
        shifted.stopIfTrue == false
      else { return fail("relative formula \(describe(vm.activeSheet.conditionalFormats))") }
      guard
        rule(vm.activeSheet.conditionalFormats, range: "C5:C7", predicate: .formula("=$A$1>10"))
          != nil
      else {
        return fail("absolute formula \(describe(vm.activeSheet.conditionalFormats))")
      }
      guard vm.activeSheet.conditionalFormats.allSatisfy({ $0.predicate != .greaterThan(99) })
      else {
        return fail("copied a rule outside the selection")
      }
      let painted = vm.resolvedPaint(at: CellAddress(row: 5, col: 2))
      guard painted.format?.fillColor == ConditionalFormatStyle.redFill.fillColor else {
        return fail("pasted 15 did not pick up the highlight")
      }

      vm.selectSheet(at: 0)
      guard sourceRulesIntact(vm.activeSheet.conditionalFormats, originals: originals) else {
        return fail(
          "source rules changed after cross-sheet paste \(describe(vm.activeSheet.conditionalFormats))"
        )
      }

      vm.selectRange(from: CellAddress(row: 0, col: 6), to: CellAddress(row: 0, col: 6))
      vm.pasteFromPasteboard()
      guard vm.activeSheet.cell(at: CellAddress(row: 0, col: 6)).raw == "5",
        vm.activeSheet.cell(at: CellAddress(row: 1, col: 6)).raw == "15",
        vm.activeSheet.cell(at: CellAddress(row: 2, col: 6)).raw == "8",
        vm.activeSheet.cell(at: .origin).raw == "5"
      else { return fail("same-sheet values") }
      guard
        rule(vm.activeSheet.conditionalFormats, range: "G1:G3", predicate: .formula("=G1>H1"))
          != nil,
        rule(vm.activeSheet.conditionalFormats, range: "G1:G3", predicate: .formula("=$A$1>10"))
          != nil,
        rule(vm.activeSheet.conditionalFormats, range: "G1:G3", predicate: .greaterThan(10)) != nil
      else { return fail("same-sheet retarget \(describe(vm.activeSheet.conditionalFormats))") }
      guard sourceRulesIntact(vm.activeSheet.conditionalFormats, originals: originals) else {
        return fail("same-sheet paste moved the original rules")
      }
      guard
        vm.resolvedPaint(at: CellAddress(row: 1, col: 0)).format?.fillColor
          == ConditionalFormatStyle.redFill.fillColor
      else { return fail("original highlight stopped matching") }

      vm.selectRange(from: CellAddress(row: 1, col: 0), to: CellAddress(row: 1, col: 0))
      guard vm.copySelectionToPasteboard() else { return fail("partial copy failed") }
      vm.selectRange(from: CellAddress(row: 0, col: 4), to: CellAddress(row: 0, col: 4))
      vm.pasteFromPasteboard()
      guard vm.activeSheet.cell(at: CellAddress(row: 0, col: 4)).raw == "15" else {
        return fail("partial paste value")
      }
      guard
        rule(vm.activeSheet.conditionalFormats, range: "E1", predicate: .formula("=E1>F1")) != nil,
        rule(vm.activeSheet.conditionalFormats, range: "E1", predicate: .formula("=$A$1>10"))
          != nil,
        rule(vm.activeSheet.conditionalFormats, range: "E1", predicate: .greaterThan(10)) != nil
      else { return fail("partial retarget \(describe(vm.activeSheet.conditionalFormats))") }
      guard sourceRulesIntact(vm.activeSheet.conditionalFormats, originals: originals) else {
        return fail("partial paste changed the original block")
      }

      vm.selectRange(from: .origin, to: CellAddress(row: 2, col: 0))
      vm.copyFormulas()
      vm.selectSheet(at: 1)
      vm.selectRange(from: CellAddress(row: 10, col: 0), to: CellAddress(row: 10, col: 0))
      vm.pasteFormulasFromPasteboard()
      guard vm.activeSheet.cell(at: CellAddress(row: 10, col: 0)).raw == "5",
        vm.activeSheet.cell(at: CellAddress(row: 12, col: 0)).raw == "8"
      else { return fail("paste formulas values") }
      guard
        rule(vm.activeSheet.conditionalFormats, range: "A11:A13", predicate: .formula("=A11>B11"))
          != nil,
        rule(vm.activeSheet.conditionalFormats, range: "A11:A13", predicate: .formula("=$A$1>10"))
          != nil,
        rule(vm.activeSheet.conditionalFormats, range: "C5:C7", predicate: .formula("=C5>D5"))
          != nil
      else { return fail("paste formulas rules \(describe(vm.activeSheet.conditionalFormats))") }

      vm.selectSheet(at: 0)
      vm.setCellValue("=B1", at: CellAddress(row: 0, col: 3))
      vm.selectRange(from: CellAddress(row: 0, col: 3), to: CellAddress(row: 0, col: 3))
      guard vm.copySelectionToPasteboard() else { return fail("formula cell copy failed") }
      vm.selectSheet(at: 1)
      let rulesBeforePlainPaste = vm.activeSheet.conditionalFormats.count
      vm.selectRange(from: CellAddress(row: 4, col: 5), to: CellAddress(row: 4, col: 5))
      vm.pasteFromPasteboard()
      guard vm.activeSheet.cell(at: CellAddress(row: 4, col: 5)).raw == "=B1" else {
        return fail(
          "cell formula changed to \(vm.activeSheet.cell(at: CellAddress(row: 4, col: 5)).raw)")
      }
      guard vm.activeSheet.conditionalFormats.count == rulesBeforePlainPaste else {
        return fail("copy without rules still pasted conditional formatting")
      }

      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString("99", forType: .string)
      vm.selectRange(from: CellAddress(row: 0, col: 5), to: CellAddress(row: 0, col: 5))
      vm.pasteFromPasteboard()
      guard vm.activeSheet.cell(at: CellAddress(row: 0, col: 5)).raw == "99",
        vm.activeSheet.conditionalFormats.count == rulesBeforePlainPaste
      else { return fail("external paste changed conditional formatting") }

      return Result(name: name, passed: true, detail: "cross-sheet, same-sheet, and formula shift")
    }

    private static func rule(
      _ rules: [ConditionalFormatRule],
      range: String,
      predicate: ConditionalFormatPredicate
    ) -> ConditionalFormatRule? {
      rules.first { $0.range.a1Label == range && $0.predicate == predicate }
    }

    private static func sourceRulesIntact(
      _ rules: [ConditionalFormatRule],
      originals: [ConditionalFormatRule]
    ) -> Bool {
      originals.allSatisfy { original in
        guard let match = rules.first(where: { $0.id == original.id }) else { return false }
        return match.range.a1Label == original.range.a1Label
          && match.predicate == original.predicate
          && match.style == original.style
          && match.stopIfTrue == original.stopIfTrue
      }
    }

    private static func describe(_ rules: [ConditionalFormatRule]) -> String {
      rules.map { "\($0.range.a1Label) \($0.predicate.title)" }.joined(separator: "; ")
    }

    /// Prose in the cell editor and formula bar uses the Mac spell checker.
    /// A formula (`=`) and a number are not checked. A formula result is not the edit text.
    private static func editorSpellChecking() -> Result {
      let name = "editor spell check"
      let decisions: [(String, Bool)] = [
        ("recieve", true),
        ("Hello", true),
        ("", true),
        ("Hello 2", true),
        ("=SUM(A1)", false),
        ("=sum(A1)", false),
        ("  =A1", false),
        ("42", false),
        ("1,234.50", false),
        ("50%", false),
        ("$12", false),
        ("1e2", false),
      ]
      for (text, expected) in decisions where EditorSpellCheck.shouldCheck(text) != expected {
        return Result(
          name: name, passed: false, detail: "decision \(text.debugDescription) != \(expected)")
      }

      let word = "recieve"
      let wordRange = NSRange(location: 0, length: (word as NSString).length)
      let miss = NSSpellChecker.shared.checkSpelling(
        of: word,
        startingAt: 0,
        language: "en",
        wrap: false,
        inSpellDocumentWithTag: 0,
        wordCount: nil
      )
      let guesses =
        NSSpellChecker.shared.guesses(
          forWordRange: wordRange,
          in: word,
          language: "en",
          inSpellDocumentWithTag: 0
        ) ?? []
      let suggested = guesses.contains { $0.caseInsensitiveCompare("receive") == .orderedSame }
      guard miss.length > 0, suggested else {
        return Result(
          name: name,
          passed: false,
          detail: "system guesses \(guesses) range \(miss.location):\(miss.length)"
        )
      }

      if let detail = formulaResultSkipsSpellCheck() {
        return Result(name: name, passed: false, detail: detail)
      }
      if let detail = formulaBarKeepsSpellingMarks() {
        return Result(name: name, passed: false, detail: detail)
      }
      if let detail = cellEditorSpellChecksProseOnly() {
        return Result(name: name, passed: false, detail: detail)
      }
      return Result(
        name: name,
        passed: true,
        detail: "prose uses the system checker; formulas and numbers do not"
      )
    }

    /// Editing `=A1` checks the formula, not the word the cell displays.
    private static func formulaResultSkipsSpellCheck() -> String? {
      var sheet = Sheet(name: "Sheet1")
      sheet.setCell(Cell(raw: "recieve"), at: .origin)
      sheet.setCell(Cell(raw: "=A1"), at: CellAddress(row: 0, col: 1))
      let viewModel = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
      // A formula with no saved result shows once the background calculation lands.
      var displayed = viewModel.displayString(at: CellAddress(row: 0, col: 1))
      let deadline = Date().addingTimeInterval(10)
      while displayed != "recieve", Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
        displayed = viewModel.displayString(at: CellAddress(row: 0, col: 1))
      }
      guard displayed == "recieve" else { return "formula result \(displayed)" }
      viewModel.selection = CellAddress(row: 0, col: 1)
      viewModel.beginEditing()
      guard viewModel.editText == "=A1", !EditorSpellCheck.shouldCheck(viewModel.editText) else {
        return "edit text \(viewModel.editText)"
      }
      guard EditorSpellCheck.shouldCheck(displayed) else {
        return "result was treated as edit text"
      }
      return nil
    }

    /// Formula-bar attribute updates must not wipe the system underline, and `=` turns checking off.
    private static func formulaBarKeepsSpellingMarks() -> String? {
      let box = SpellCheckTextBox("recieve")
      let field = FormulaBarTextField(
        text: Binding(get: { box.text }, set: { box.text = $0 }),
        liveText: box.text,
        namedRanges: [],
        highlights: [],
        focusedHighlightIndex: nil,
        onSubmit: { _ in },
        onTextChange: {},
        onBeginEditing: {},
        onCaretMoved: { _ in }
      )
      let coordinator = field.makeCoordinator()
      let textView = FormulaBarNSTextView(frame: NSRect(x: 0, y: 0, width: 280, height: 40))
      textView.font = .systemFont(ofSize: 16)
      coordinator.textView = textView
      textView.delegate = coordinator
      let window = SpellCheckWindow(
        contentRect: textView.frame, styleMask: [.borderless], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.contentView = textView
      window.setFrameOrigin(NSPoint(x: -4200, y: -4200))
      window.makeKeyAndOrderFront(nil)
      defer {
        window.orderOut(nil)
        window.close()
      }

      textView.string = "recieve"
      guard textView.isContinuousSpellCheckingEnabled,
        !textView.isAutomaticSpellingCorrectionEnabled
      else {
        return
          "formula bar prose check=\(textView.isContinuousSpellCheckingEnabled) correction=\(textView.isAutomaticSpellingCorrectionEnabled)"
      }
      if let detail = waitForSpellingUnderline(on: textView, label: "formula bar") {
        return detail
      }
      coordinator.applyAttributes(force: false)
      guard spellingMarkLength(textView) > 0 else {
        return "formula bar attribute update cleared the underline"
      }
      if let detail = spellingContextMenuFailure(on: textView, label: "formula bar") {
        return detail
      }

      textView.string = "=SUM(A1)"
      guard textView.string == "=SUM(A1)", !textView.isContinuousSpellCheckingEnabled else {
        return
          "formula bar formula check=\(textView.isContinuousSpellCheckingEnabled) text=\(textView.string)"
      }
      textView.string = "42"
      guard !textView.isContinuousSpellCheckingEnabled else {
        return "formula bar number was checked"
      }
      textView.string = "recieve"
      guard textView.isContinuousSpellCheckingEnabled else {
        return "formula bar prose stayed unchecked"
      }
      return nil
    }

    /// The in-cell field editor checks the typed text, then the standard menu offers a fix, Ignore, and Learn.
    private static func cellEditorSpellChecksProseOnly() -> String? {
      let frame = NSRect(x: 0, y: 0, width: 900, height: 560)
      let grid = SpreadsheetGridNSView(frame: frame)
      let host = SpellFieldEditorHost()
      let window = SpellCheckWindow(
        contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.delegate = host
      window.contentView = grid
      window.setFrameOrigin(NSPoint(x: -4200, y: -4200))
      window.makeKeyAndOrderFront(nil)
      defer {
        grid.hideEditor(commit: false)
        window.contentView = nil
        window.delegate = nil
        window.orderOut(nil)
        window.close()
      }

      var sheet = Sheet(name: "Sheet1")
      sheet.setCell(Cell(raw: "recieve"), at: .origin)
      sheet.setCell(Cell(raw: "=A1"), at: CellAddress(row: 0, col: 1))
      sheet.setCell(Cell(raw: "42"), at: CellAddress(row: 0, col: 2))
      let viewModel = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
      grid.viewModel = viewModel
      grid.layoutSubtreeIfNeeded()
      window.displayIfNeeded()
      // The grid takes first responder once, on the next turns. Edit after that.
      RunLoop.current.run(until: Date().addingTimeInterval(0.25))

      func open(_ address: CellAddress) -> NSTextView? {
        grid.hideEditor(commit: false)
        viewModel.selection = address
        viewModel.beginEditing()
        grid.showEditor(selectAll: true)
        if let textView = window.firstResponder as? NSTextView { return textView }
        if let field = window.firstResponder as? NSTextField {
          return field.currentEditor() as? NSTextView
        }
        return nil
      }

      guard let prose = open(.origin) else { return "cell editor did not focus" }
      guard prose is CellFieldEditor else { return "cell editor is not the field editor" }
      guard prose.string == "recieve",
        prose.isContinuousSpellCheckingEnabled,
        !prose.isAutomaticSpellingCorrectionEnabled,
        !prose.isGrammarCheckingEnabled
      else {
        return "cell prose \(prose.string) check=\(prose.isContinuousSpellCheckingEnabled)"
      }
      if let detail = waitForSpellingUnderline(on: prose, label: "cell") { return detail }
      if let detail = spellingContextMenuFailure(on: prose, label: "cell") { return detail }

      guard let formula = open(CellAddress(row: 0, col: 1)) else {
        return "formula editor did not focus"
      }
      let displayed = viewModel.displayString(at: CellAddress(row: 0, col: 1))
      guard displayed == "recieve", formula.string == "=A1",
        !formula.isContinuousSpellCheckingEnabled
      else {
        return
          "cell formula edit=\(formula.string) result=\(displayed) check=\(formula.isContinuousSpellCheckingEnabled)"
      }

      guard let number = open(CellAddress(row: 0, col: 2)) else {
        return "number editor did not focus"
      }
      guard number.string == "42", !number.isContinuousSpellCheckingEnabled else {
        return "cell number \(number.string) check=\(number.isContinuousSpellCheckingEnabled)"
      }
      return nil
    }

    /// English orthography is only so this check has a known misspelling. Editing uses the system language.
    private static func waitForSpellingUnderline(on textView: NSTextView, label: String) -> String?
    {
      let length = (textView.string as NSString).length
      guard length > 0 else { return "\(label) empty" }
      let orthography = NSOrthography(dominantScript: "Latn", languageMap: ["Latn": ["en"]])
      textView.checkText(
        in: NSRange(location: 0, length: length),
        types: NSTextCheckingResult.CheckingType.spelling.rawValue,
        options: [.orthography: orthography]
      )
      let deadline = Date().addingTimeInterval(2)
      while Date() < deadline && spellingMarkLength(textView) == 0 {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
      }
      guard spellingMarkLength(textView) > 0 else {
        return "\(label) no system underline language=\(NSSpellChecker.shared.language())"
      }
      return nil
    }

    private static func spellingContextMenuFailure(on textView: NSTextView, label: String)
      -> String?
    {
      guard let window = textView.window else { return "\(label) has no window" }
      textView.layoutSubtreeIfNeeded()
      guard let container = textView.textContainer, let layout = textView.layoutManager else {
        return "\(label) no layout"
      }
      layout.ensureLayout(for: container)
      let length = (textView.string as NSString).length
      let word = NSRange(location: 0, length: length)
      let glyphs = layout.glyphRange(forCharacterRange: word, actualCharacterRange: nil)
      var rect = layout.boundingRect(forGlyphRange: glyphs, in: container)
      guard rect.width > 1, rect.height > 1 else { return "\(label) glyph rect \(rect)" }
      rect.origin.x += textView.textContainerOrigin.x
      rect.origin.y += textView.textContainerOrigin.y
      let windowPoint = textView.convert(NSPoint(x: rect.midX, y: rect.midY), to: nil)
      window.makeFirstResponder(textView)
      textView.setSelectedRange(word)
      guard
        let event = NSEvent.mouseEvent(
          with: .rightMouseDown,
          location: windowPoint,
          modifierFlags: [],
          timestamp: ProcessInfo.processInfo.systemUptime,
          windowNumber: window.windowNumber,
          context: nil,
          eventNumber: 1,
          clickCount: 1,
          pressure: 1
        )
      else {
        return "\(label) no click"
      }
      let items = menuItems(in: textView.menu(for: event))
      let titles = items.map(\.title)
      let lower = titles.map { $0.lowercased() }
      let actions = items.compactMap { item -> String? in
        guard let action = item.action else { return nil }
        return NSStringFromSelector(action)
      }
      let represented = items.compactMap { $0.representedObject as? String }.map { $0.lowercased() }
      let suggestion = lower.contains("receive") || represented.contains("receive")
      let ignore =
        lower.contains("ignore spelling") || lower.contains("ignore")
        || actions.contains("ignoreSpelling:")
      let learn =
        lower.contains("learn spelling") || lower.contains("learn")
        || actions.contains { $0.lowercased().contains("learn") }
      guard suggestion, ignore, learn else {
        let shown = titles.prefix(16).joined(separator: " | ")
        return "\(label) menu suggestion=\(suggestion) ignore=\(ignore) learn=\(learn) [\(shown)]"
      }
      return nil
    }

    private static func spellingMarkLength(_ textView: NSTextView) -> Int {
      guard let layout = textView.layoutManager else { return 0 }
      let length = (textView.string as NSString).length
      guard length > 0 else { return 0 }
      var marked = 0
      var index = 0
      while index < length {
        var range = NSRange(location: NSNotFound, length: 0)
        let value = layout.temporaryAttribute(
          .spellingState,
          atCharacterIndex: index,
          effectiveRange: &range
        )
        let state = (value as? NSNumber)?.intValue ?? (value as? Int) ?? 0
        let runEnd: Int
        if range.location != NSNotFound, range.length > 0 {
          runEnd = min(length, range.location + range.length)
        } else {
          runEnd = index + 1
        }
        if state != 0 {
          let runStart = range.location == NSNotFound ? index : max(index, range.location)
          marked += max(0, runEnd - runStart)
        }
        index = runEnd > index ? runEnd : index + 1
      }
      return marked
    }

    private static func menuItems(in menu: NSMenu?) -> [NSMenuItem] {
      guard let menu else { return [] }
      var items: [NSMenuItem] = []
      for item in menu.items {
        items.append(item)
        items.append(contentsOf: menuItems(in: item.submenu))
      }
      return items
    }

    private final class SpellCheckWindow: NSWindow {
      override var canBecomeKey: Bool { true }
      override var canBecomeMain: Bool { true }
    }

    private final class SpellFieldEditorHost: NSObject, NSWindowDelegate {
      let fieldEditor: CellFieldEditor = {
        let editor = CellFieldEditor()
        editor.isFieldEditor = true
        return editor
      }()

      func windowWillReturnFieldEditor(_ sender: NSWindow, to client: Any?) -> Any? {
        guard client is CellEditorTextField else { return nil }
        return fieldEditor
      }
    }

    private final class SpellCheckTextBox {
      var text: String
      init(_ text: String) { self.text = text }
    }

    /// Copies a workbook into the app sandbox temp dir so `SpreadsheetDocumentStore.load` can read it.
    private static func sandboxReadableWorkbookURL(
      cacheFileName: String,
      envKeys: [String] = [],
      fixturesFileName: String? = nil,
      bundleResourceName: String? = nil
    ) throws -> URL {
      let fm = FileManager.default
      let dest = fm.temporaryDirectory.appendingPathComponent("spark-grid-bugbash-\(cacheFileName)")
      if fm.fileExists(atPath: dest.path), fm.isReadableFile(atPath: dest.path) {
        return dest
      }

      func materialize(from source: URL) throws -> URL {
        if source.path.hasPrefix(fm.temporaryDirectory.path), fm.isReadableFile(atPath: source.path)
        {
          return source
        }
        let data = try Data(contentsOf: source)
        try data.write(to: dest, options: .atomic)
        return dest
      }

      var candidates: [URL] = []
      let env = ProcessInfo.processInfo.environment
      for key in envKeys {
        if let raw = env[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
          !raw.isEmpty,
          fm.fileExists(atPath: raw)
        {
          candidates.append(URL(fileURLWithPath: raw))
        }
      }
      if let fixturesFileName,
        let dir = env["SPARK_GRID_FIXTURES"]?.trimmingCharacters(in: .whitespacesAndNewlines),
        !dir.isEmpty
      {
        let path = (dir as NSString).appendingPathComponent(fixturesFileName)
        if fm.fileExists(atPath: path) {
          candidates.append(URL(fileURLWithPath: path))
        }
      }
      if let bundleResourceName {
        if let bundleURL = Bundle.main.url(
          forResource: bundleResourceName,
          withExtension: "xlsx",
          subdirectory: "BugBashFixtures"
        ) ?? Bundle.main.url(forResource: bundleResourceName, withExtension: "xlsx") {
          candidates.append(bundleURL)
        }
      }
      if let fixturesFileName, let repoPath = bundledFixturePath(fixturesFileName) {
        candidates.append(URL(fileURLWithPath: repoPath))
      }

      var lastError: Error?
      for source in candidates {
        do {
          return try materialize(from: source)
        } catch {
          lastError = error
        }
      }
      throw lastError
        ?? NSError(
          domain: "BugBashRunner",
          code: 1,
          userInfo: [NSLocalizedDescriptionKey: "no readable fixture for \(cacheFileName)"]
        )
    }

    /// Generated sample under `Fixtures/` (repo checkout).
    private static func bundledFixturePath(_ fileName: String) -> String? {
      let env = ProcessInfo.processInfo.environment
      let relative = "Fixtures/\(fileName)"
      if let root = env["SPARK_GRID_REPO_ROOT"]?.trimmingCharacters(in: .whitespacesAndNewlines),
        !root.isEmpty
      {
        let path = (root as NSString).appendingPathComponent(relative)
        if FileManager.default.fileExists(atPath: path) { return path }
      }
      let fromSource = URL(fileURLWithPath: #file)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/\(fileName)")
        .path
      if FileManager.default.fileExists(atPath: fromSource) { return fromSource }
      let cwd = (FileManager.default.currentDirectoryPath as NSString).appendingPathComponent(
        relative)
      if FileManager.default.fileExists(atPath: cwd) { return cwd }
      return nil
    }

    private static func syntheticLargeWorkbook() -> Workbook {
      var cells: [CellAddress: Cell] = [:]
      for row in 0..<800 {
        for col in 0..<200 {
          cells[CellAddress(row: row, col: col)] = Cell(raw: "1")
        }
      }
      var summary = Sheet(
        name: "YTD Summary",
        cells: cells,
        frozenRows: 4,
        frozenColumns: 3,
        mergedRanges: [
          CellRange(start: .origin, end: CellAddress(row: 0, col: 24)),
          CellRange(start: CellAddress(row: 1, col: 0), end: CellAddress(row: 1, col: 24)),
        ]
      )
      summary.setCell(
        Cell(raw: "=IFERROR(COUNTIFS(Config!$C:$C,\"x\"),0)"), at: CellAddress(row: 9, col: 5))
      var config = Sheet(name: "Config")
      config.setCell(Cell(raw: "x"), at: CellAddress(row: 0, col: 2))
      return Workbook(sheets: [summary, config], activeSheetIndex: 0)
    }

    /// BDC KPI-scale workbooks used to JSON-encode the entire model twice on open for dirty
    /// baselines, spiking memory and jetsam-ing the Mac app. Streaming fingerprint must finish.
    private static func largeWorkbookOpenBaseline() -> Result {
      let name = "large workbook open baseline"
      let workbook = syntheticLargeWorkbook()
      let cellCount = workbook.sheets.reduce(0) { $0 + $1.cells.count }
      let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("spark-grid-large-open-\(UUID().uuidString).xlsx")
      defer { try? FileManager.default.removeItem(at: url) }
      do {
        try XLSXCodec.exportWorkbook(workbook).write(to: url)
      } catch {
        return Result(name: name, passed: false, detail: error.localizedDescription)
      }
      let fingerprintStart = CFAbsoluteTimeGetCurrent()
      let fp = WorkbookFingerprint.data(for: workbook)
      let fingerprintElapsed = CFAbsoluteTimeGetCurrent() - fingerprintStart
      guard fp.count == 32 else {
        return Result(name: name, passed: false, detail: "fingerprint length \(fp.count)")
      }
      guard fingerprintElapsed < 20 else {
        return Result(
          name: name,
          passed: false,
          detail: String(
            format: "fingerprint took %.1fs for %d cells", fingerprintElapsed, cellCount)
        )
      }
      return MainActor.assumeIsolated {
        let store = SpreadsheetDocumentStore()
        do {
          try store.load(from: url, finishesInBackground: false)
        } catch {
          return Result(name: name, passed: false, detail: error.localizedDescription)
        }
        drainMainQueue()
        guard !store.isDirty else {
          return Result(name: name, passed: false, detail: "clean open marked edited")
        }
        // Formula rebuild and first draw are not part of the open fingerprint regression.
        let vm = SpreadsheetViewModel(workbook: store.document.workbook)
        guard snapshotGrid(sheet: vm.activeSheet) != nil else {
          return Result(name: name, passed: false, detail: "grid snapshot failed")
        }
        return Result(
          name: name,
          passed: true,
          detail: "\(cellCount) cells fingerprinted and opened"
        )
      }
    }

    /// Freeze, a wide merge, and a cross-sheet formula. Built in the test so no customer workbook is committed.
    @MainActor
    private static func wideFreezeMergeLayoutOpen() -> Result {
      let name = "wide freeze and merge layout open"
      let summary = Sheet(
        name: "Summary",
        cells: [CellAddress(row: 4, col: 0): Cell(raw: "=Data!A1")],
        frozenRows: 4,
        frozenColumns: 3,
        mergedRanges: [
          CellRange(start: .origin, end: CellAddress(row: 0, col: 24))
        ]
      )
      let data = Sheet(name: "Data", cells: [.origin: Cell(raw: "1")])
      let built = Workbook(sheets: [summary, data])
      let url = FileManager.default.temporaryDirectory.appendingPathComponent(
        "spark-grid-layout-\(UUID().uuidString).xlsx"
      )
      defer { try? FileManager.default.removeItem(at: url) }
      do {
        try XLSXCodec.exportWorkbook(built).write(to: url)
        let workbook = try XLSXCodec.importWorkbook(from: url)
        let sheet = workbook.activeSheet
        guard sheet.frozenRows == 4, sheet.frozenColumns == 3 else {
          return Result(
            name: name,
            passed: false,
            detail: "freeze expected 4×3 got \(sheet.frozenRows)×\(sheet.frozenColumns)"
          )
        }
        guard
          sheet.mergedRanges.contains(where: {
            let n = $0.normalized
            return n.minRow == 0 && n.minCol == 0 && n.maxCol == 24
          })
        else {
          return Result(name: name, passed: false, detail: "missing A1:Y1 merge")
        }
        let vm = SpreadsheetViewModel(workbook: workbook)
        guard snapshotGrid(sheet: vm.activeSheet) != nil else {
          return Result(name: name, passed: false, detail: "grid snapshot failed")
        }
        return Result(name: name, passed: true, detail: "import, VM, and first draw ok")
      } catch {
        return Result(name: name, passed: false, detail: error.localizedDescription)
      }
    }

    private static func excelCachedNumericValue(
      url: URL,
      sheetName: String,
      address: CellAddress
    ) -> Double? {
      guard let data = try? Data(contentsOf: url),
        let file = try? XLSXFile(data: data),
        let workbook = try? file.parseWorkbooks().first,
        let paths = try? file.parseWorksheetPathsAndNames(workbook: workbook),
        let worksheetPath = paths.first(where: {
          ($0.0 ?? "").caseInsensitiveCompare(sheetName) == .orderedSame
        })?.1,
        let worksheet = try? file.parseWorksheet(at: worksheetPath),
        let rows = worksheet.data?.rows
      else { return nil }
      let target = address.a1
      for row in rows {
        for cell in row.cells where cell.reference.description == target {
          guard let raw = cell.value else { return nil }
          return Double(raw)
        }
      }
      return nil
    }

    private static func syntheticLargeFormulaSheet(
      name: String,
      seedImportedSnapshots: Bool
    ) -> Sheet {
      var sheet = Sheet(name: name)
      for row in 0..<40 {
        sheet.setCell(Cell(raw: "1"), at: CellAddress(row: row, col: 0))
      }
      for row in 0..<900 {
        for col in 0..<16 {
          var cell = Cell(raw: "=SUM($A$1:$A$40)")
          if seedImportedSnapshots {
            cell.importedFormulaResult = "40"
          }
          sheet.setCell(cell, at: CellAddress(row: row, col: col))
        }
      }
      return sheet
    }

    /// Simulates one grid paint pass (conditional paint + displayed value) for a viewport.
    @MainActor
    private static func simulateViewportPaint(
      vm: SpreadsheetViewModel,
      minRow: Int,
      maxRow: Int,
      minCol: Int,
      maxCol: Int
    ) -> TimeInterval {
      let start = CFAbsoluteTimeGetCurrent()
      let sheet = vm.activeSheet
      for row in minRow...maxRow {
        for col in minCol...maxCol {
          let address = CellAddress(row: row, col: col)
          if sheet.cells[address] == nil { continue }
          if sheet.isCoveredByMerge(address), sheet.mergeAnchor(for: address) != address {
            continue
          }
          let cell = sheet.cell(at: address)
          guard !cell.raw.isEmpty else { continue }
          let paint = vm.resolvedPaint(at: address)
          let value = vm.displayValue(at: address)
          _ = CellFormatRenderer.displayText(
            for: value,
            format: paint.format ?? cell.format,
            fallbackRaw: cell.raw
          )
        }
      }
      return CFAbsoluteTimeGetCurrent() - start
    }

    /// Large in-memory workbook: cold scroll regions must stay fast when imported snapshots exist.
    @MainActor
    private static func largeSyntheticWorkbookColdViewportScroll() -> Result {
      let name = "large synthetic cold viewport scroll"
      let workbook = Workbook(sheets: [
        syntheticLargeFormulaSheet(name: "Data", seedImportedSnapshots: true)
      ])
      let vm = SpreadsheetViewModel(workbook: workbook)
      let regionA = simulateViewportPaint(vm: vm, minRow: 0, maxRow: 35, minCol: 0, maxCol: 11)
      let regionB = simulateViewportPaint(vm: vm, minRow: 420, maxRow: 455, minCol: 0, maxCol: 11)
      guard regionA < 0.2, regionB < 0.2 else {
        return Result(
          name: name,
          passed: false,
          detail: String(format: "with snapshots A %.2fs B %.2fs", regionA, regionB)
        )
      }

      var formulaCells = 0
      var missingSnapshots = 0
      let snapSheet = workbook.activeSheet
      for row in 420...455 {
        for col in 0...11 {
          let address = CellAddress(row: row, col: col)
          guard FormulaSyntax.isFormula(snapSheet.cell(at: address).raw) else { continue }
          formulaCells += 1
          if snapSheet.cell(at: address).importedFormulaResult == nil {
            missingSnapshots += 1
          }
        }
      }
      guard formulaCells > 0, missingSnapshots == 0 else {
        return Result(
          name: name,
          passed: false,
          detail: "snapshots missing \(missingSnapshots)/\(formulaCells) in cold band"
        )
      }

      let slowWorkbook = Workbook(sheets: [
        syntheticLargeFormulaSheet(name: "Data", seedImportedSnapshots: false)
      ])
      let slowVM = SpreadsheetViewModel(workbook: slowWorkbook)
      let slowRegion = simulateViewportPaint(
        vm: slowVM,
        minRow: 420,
        maxRow: 455,
        minCol: 0,
        maxCol: 11
      )
      guard slowRegion < 0.2 else {
        return Result(
          name: name,
          passed: false,
          detail: String(format: "without snapshots cold region %.2fs", slowRegion)
        )
      }
      guard slowRegion + 0.000_5 >= regionB else {
        return Result(
          name: name,
          passed: false,
          detail: String(
            format: "snapshots path faster than no-snapshot (%.2fs vs %.2fs)", regionB, slowRegion)
        )
      }
      return Result(
        name: name,
        passed: true,
        detail: String(
          format: "snapshots A %.2fs B %.2fs; no-snapshot %.2fs", regionA, regionB, slowRegion)
      )
    }

    /// A trackpad tick paints the visible cells from the store. It does not
    /// rasterize a region bitmap.
    @MainActor
    private static func liveScrollTickMovesCellsWithoutPainting() -> Result {
      let name = "live scroll tick moves cells without painting"
      let header = SpreadsheetGridNSView.baseHeaderSize
      let rowH = Workbook.defaultRowHeight
      let colW = Workbook.defaultColumnWidth
      func painted(_ color: CodableColor) -> Cell {
        var format = CellFormat()
        format.fillColor = color
        return Cell(raw: "", format: format)
      }
      var sheet = Sheet(name: "Scroll", frozenRows: 2, frozenColumns: 1)
      for row in 0..<36 {
        for col in 0..<8 {
          sheet.setCell(Cell(raw: "r\(row)c\(col)"), at: CellAddress(row: row, col: col))
        }
      }
      let red = CodableColor(red: 0.95, green: 0.05, blue: 0.05, alpha: 1)
      let green = CodableColor(red: 0.05, green: 0.85, blue: 0.1, alpha: 1)
      let blue = CodableColor(red: 0.05, green: 0.15, blue: 0.95, alpha: 1)
      sheet.setCell(painted(green), at: CellAddress(row: 0, col: 3))
      sheet.setCell(painted(blue), at: CellAddress(row: 6, col: 0))
      sheet.setCell(painted(red), at: CellAddress(row: 6, col: 3))

      let frame = NSRect(x: 0, y: 0, width: 820, height: 520)
      let grid = SpreadsheetGridNSView(frame: frame)
      let window = NSWindow(
        contentRect: frame,
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
      )
      window.isReleasedWhenClosed = false
      window.contentView = grid
      window.setFrameOrigin(NSPoint(x: -4000, y: -4000))
      window.orderFrontRegardless()
      window.setContentSize(frame.size)
      grid.frame = frame
      grid.viewModel = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
      grid.layoutSubtreeIfNeeded()
      grid.needsDisplay = true
      grid.display()
      grid.testingResetScrollCounters()
      let scrollX: CGFloat = 40
      let scrollY: CGFloat = rowH
      grid.testingApplyScroll(dx: scrollX, dy: scrollY)

      func point(row: Int, col: Int) -> NSPoint {
        let x = header + CGFloat(col) * colW + colW / 2 - (col < 1 ? 0 : scrollX)
        let y = header + CGFloat(row) * rowH + rowH / 2 - (row < 2 ? 0 : scrollY)
        return NSPoint(x: x, y: y)
      }
      let redNow = point(row: 6, col: 3)
      let redBefore = NSPoint(x: redNow.x + scrollX, y: redNow.y + scrollY)
      let greenNow = point(row: 0, col: 3)
      let blueNow = point(row: 6, col: 0)

      guard grid.liveScrollPlaneBuilds == 0 else {
        window.orderOut(nil)
        window.close()
        return Result(
          name: name,
          passed: false,
          detail:
            "surfaces \(grid.testingScrollSurfacesPresented) visits \(grid.liveScrollCellVisits) text \(grid.liveScrollTextPaints) builds \(grid.liveScrollPlaneBuilds) headers \(grid.liveScrollHeaderDraws)"
        )
      }

      guard let snap = bitmapOfGrid(grid) else {
        window.orderOut(nil)
        window.close()
        return Result(name: name, passed: false, detail: "snapshot failed")
      }
      window.orderOut(nil)
      window.close()

      func isRed(_ color: NSColor) -> Bool {
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return false }
        return rgb.redComponent > 0.7 && rgb.greenComponent < 0.25 && rgb.blueComponent < 0.25
      }
      func isGreen(_ color: NSColor) -> Bool {
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return false }
        return rgb.greenComponent > 0.55 && rgb.redComponent < 0.25 && rgb.blueComponent < 0.3
      }
      func isBlue(_ color: NSColor) -> Bool {
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return false }
        return rgb.blueComponent > 0.7 && rgb.redComponent < 0.25 && rgb.greenComponent < 0.35
      }
      func describe(_ color: NSColor) -> String {
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return "nil" }
        return String(
          format: "%.2f,%.2f,%.2f", rgb.redComponent, rgb.greenComponent, rgb.blueComponent)
      }
      let fromTop = [true, false].first { isRed(snap.color(at: redNow, fromTop: $0)) }
      guard let fromTop else {
        return Result(
          name: name,
          passed: false,
          detail:
            "red did not move top \(describe(snap.color(at: redNow, fromTop: true))) bottom \(describe(snap.color(at: redNow, fromTop: false)))"
        )
      }
      guard !isRed(snap.color(at: redBefore, fromTop: fromTop)) else {
        return Result(name: name, passed: false, detail: "red stayed at the pre-scroll point")
      }
      guard isGreen(snap.color(at: greenNow, fromTop: fromTop)) else {
        return Result(
          name: name,
          passed: false,
          detail: "frozen header fill \(describe(snap.color(at: greenNow, fromTop: fromTop)))"
        )
      }
      guard isBlue(snap.color(at: blueNow, fromTop: fromTop)) else {
        return Result(
          name: name,
          passed: false,
          detail: "frozen column fill \(describe(snap.color(at: blueNow, fromTop: fromTop)))"
        )
      }
      return Result(name: name, passed: true, detail: "tick painted the viewport builds 0")
    }

    @MainActor
    private static func bitmapOfGrid(_ grid: SpreadsheetGridNSView) -> GridSnapshot? {
      let scale = max(1, grid.window?.backingScaleFactor ?? 2)
      let pixelsWide = Int((grid.bounds.width * scale).rounded())
      let pixelsHigh = Int((grid.bounds.height * scale).rounded())
      guard
        let rep = NSBitmapImageRep(
          bitmapDataPlanes: nil,
          pixelsWide: pixelsWide,
          pixelsHigh: pixelsHigh,
          bitsPerSample: 8,
          samplesPerPixel: 4,
          hasAlpha: true,
          isPlanar: false,
          colorSpaceName: .deviceRGB,
          bytesPerRow: 0,
          bitsPerPixel: 0
        ), let gfx = NSGraphicsContext(bitmapImageRep: rep)
      else { return nil }
      rep.size = grid.bounds.size
      NSGraphicsContext.saveGraphicsState()
      NSGraphicsContext.current = gfx
      let cg = gfx.cgContext
      cg.translateBy(x: 0, y: CGFloat(pixelsHigh))
      cg.scaleBy(x: scale, y: -scale)
      // The grid paints into its own frame and copies it to the screen; render(in:) does not
      // see that copy off screen and clears what is under the grid. Render the layers, then
      // put the grid's frame where its own layer drew nothing.
      grid.layer?.render(in: cg)
      if let frame = grid.testingFrameImage() {
        cg.setBlendMode(.destinationOver)
        cg.draw(frame, in: CGRect(origin: .zero, size: grid.bounds.size))
        cg.setBlendMode(.normal)
        // Charts (z 5) and the frozen-pane overlay (z 6) are views of their own that
        // render(in:) misses; draw them above the frame in layer order. Other views, such as
        // the selection, already came through render(in:).
        let views = grid.subviews
          .filter { [5, 6].contains($0.layer?.zPosition ?? -1) }
          .filter { !$0.isHidden && $0.frame.width > 1 && $0.frame.height > 1 }
          .sorted { ($0.layer?.zPosition ?? 0) < ($1.layer?.zPosition ?? 0) }
        for view in views {
          guard let drawn = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            continue
          }
          view.cacheDisplay(in: view.bounds, to: drawn)
          guard let image = drawn.cgImage else { continue }
          cg.saveGState()
          cg.translateBy(x: view.frame.minX, y: view.frame.maxY)
          cg.scaleBy(x: 1, y: -1)
          cg.draw(image, in: CGRect(origin: .zero, size: view.frame.size))
          cg.restoreGState()
        }
      }
      NSGraphicsContext.restoreGraphicsState()
      return GridSnapshot(image: rep, pointScale: scale, chartAboveFrozenPane: false)
    }

    /// Synthetic large sheet: scroll strip ~50ms, cold region ~200ms (not a warm repeat).
    @MainActor
    private static func largeSheetScrollRegionBudgets() -> Result {
      let name = "large sheet scroll region budgets"
      let sheet = syntheticLargeFormulaSheet(name: "Data", seedImportedSnapshots: true)
      let workbook = Workbook(sheets: [sheet])
      let warmVM = SpreadsheetViewModel(workbook: workbook)
      _ = simulateViewportPaint(vm: warmVM, minRow: 0, maxRow: 35, minCol: 0, maxCol: 11)
      let tick = simulateViewportPaint(vm: warmVM, minRow: 36, maxRow: 38, minCol: 0, maxCol: 11)
      guard tick < 0.05 else {
        return Result(name: name, passed: false, detail: String(format: "scroll strip %.2fs", tick))
      }
      let coldVM = SpreadsheetViewModel(workbook: workbook)
      let region = simulateViewportPaint(
        vm: coldVM, minRow: 420, maxRow: 455, minCol: 0, maxCol: 11)
      guard region < 0.2 else {
        return Result(
          name: name, passed: false, detail: String(format: "cold region %.2fs", region))
      }
      return Result(
        name: name,
        passed: true,
        detail: String(format: "tick %.2fs region %.2fs", tick, region)
      )
    }

    /// Optional KPI workbook: multiple sheets, disjoint cold viewports, June E/F vs Excel cache.
    @MainActor
    private static func kpiWorkbookMultiSheetScroll() -> Result {
      let name = "KPI workbook multi-sheet scroll"
      let env = ProcessInfo.processInfo.environment
      let envPath =
        env["SPARK_GRID_FIXTURE_BDC_KPI"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let fixturesDir =
        env["SPARK_GRID_FIXTURES"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let fixturesPath = (fixturesDir as NSString).appendingPathComponent(
        "BDC-Digital-KPI-2026.xlsx")
      let hasSource =
        (!envPath.isEmpty && FileManager.default.fileExists(atPath: envPath))
        || (!fixturesDir.isEmpty && FileManager.default.fileExists(atPath: fixturesPath))
      guard hasSource else {
        return Result(name: name, passed: true, detail: "skipped (no KPI fixture source)")
      }
      do {
        let url = try sandboxReadableWorkbookURL(
          cacheFileName: "BDC-Digital-KPI-2026.xlsx",
          envKeys: ["SPARK_GRID_FIXTURE_BDC_KPI"],
          fixturesFileName: "BDC-Digital-KPI-2026.xlsx"
        )
        var imported = try XLSXCodec.importWorkbook(from: url)
        guard let ytdIndex = imported.sheets.firstIndex(where: { $0.name == "YTD Summary" }) else {
          return Result(name: name, passed: false, detail: "YTD Summary missing")
        }
        imported.activeSheetIndex = ytdIndex
        var vm = SpreadsheetViewModel(workbook: imported)
        drainMainQueue()

        let ytdTop = simulateViewportPaint(vm: vm, minRow: 0, maxRow: 39, minCol: 0, maxCol: 11)
        let ytdDeep = simulateViewportPaint(vm: vm, minRow: 500, maxRow: 539, minCol: 0, maxCol: 11)
        guard ytdTop < 0.2 else {
          return Result(name: name, passed: false, detail: String(format: "YTD top %.2fs", ytdTop))
        }
        let ytdTick = simulateViewportPaint(vm: vm, minRow: 40, maxRow: 42, minCol: 0, maxCol: 11)
        guard ytdTick < 0.05 else {
          return Result(
            name: name, passed: false, detail: String(format: "YTD scroll strip %.2fs", ytdTick))
        }
        guard ytdDeep < 0.2 else {
          return Result(
            name: name, passed: false, detail: String(format: "YTD deep %.2fs", ytdDeep))
        }

        guard let marchIndex = imported.sheets.firstIndex(where: { $0.name == "March" }) else {
          return Result(name: name, passed: false, detail: "March sheet missing")
        }
        vm.selectSheet(at: marchIndex)
        drainMainQueue()
        let marchCold = simulateViewportPaint(
          vm: vm, minRow: 120, maxRow: 159, minCol: 0, maxCol: 11)
        guard marchCold < 0.2 else {
          return Result(
            name: name, passed: false, detail: String(format: "March cold %.2fs", marchCold))
        }

        guard
          let juneIndex = imported.sheets.firstIndex(where: {
            $0.name.caseInsensitiveCompare("June") == .orderedSame
          })
        else {
          return Result(name: name, passed: false, detail: "June sheet missing")
        }
        vm.selectSheet(at: juneIndex)
        drainMainQueue()
        let juneScroll = simulateViewportPaint(
          vm: vm, minRow: 200, maxRow: 239, minCol: 0, maxCol: 11)
        guard juneScroll < 0.2 else {
          return Result(
            name: name, passed: false, detail: String(format: "June scroll %.2fs", juneScroll))
        }

        var juneErrors = 0
        for row in 5...61 {
          for col in 4...5 {
            let addr = CellAddress(row: row, col: col)
            guard FormulaSyntax.isFormula(vm.activeSheet.cell(at: addr).raw) else { continue }
            guard let cached = excelCachedNumericValue(url: url, sheetName: "June", address: addr)
            else {
              continue
            }
            let value = vm.displayValue(at: addr)
            if case .error = value { juneErrors += 1 }
            if case .number(let actual) = value, abs(actual - cached) >= 0.000_001 {
              return Result(
                name: name,
                passed: false,
                detail: "\(addr.a1) got \(actual) cached \(cached)"
              )
            }
          }
        }
        guard juneErrors == 0 else {
          return Result(name: name, passed: false, detail: "\(juneErrors) June E/F errors")
        }

        guard snapshotGrid(sheet: vm.activeSheet) != nil else {
          return Result(name: name, passed: false, detail: "grid snapshot failed")
        }
        return Result(
          name: name,
          passed: true,
          detail: String(
            format: "YTD %.2f/%.2fs March %.2fs June %.2fs",
            ytdTop,
            ytdDeep,
            marchCold,
            juneScroll
          )
        )
      } catch {
        return Result(name: name, passed: false, detail: error.localizedDescription)
      }
    }

    /// Optional full BDC KPI workbook (set `SPARK_GRID_FIXTURE_BDC_KPI`); not committed to git.
    @MainActor
    private static func bdcKpiWorkbookOpenPath() -> Result {
      let name = "BDC KPI workbook open path"
      let env = ProcessInfo.processInfo.environment
      let envPath =
        env["SPARK_GRID_FIXTURE_BDC_KPI"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let fixturesDir =
        env["SPARK_GRID_FIXTURES"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let fixturesPath = (fixturesDir as NSString).appendingPathComponent(
        "BDC-Digital-KPI-2026.xlsx")
      let hasSource =
        (!envPath.isEmpty && FileManager.default.fileExists(atPath: envPath))
        || (!fixturesDir.isEmpty && FileManager.default.fileExists(atPath: fixturesPath))
      guard hasSource else {
        return Result(name: name, passed: true, detail: "skipped (no KPI fixture source)")
      }
      do {
        let url = try sandboxReadableWorkbookURL(
          cacheFileName: "BDC-Digital-KPI-2026.xlsx",
          envKeys: ["SPARK_GRID_FIXTURE_BDC_KPI"],
          fixturesFileName: "BDC-Digital-KPI-2026.xlsx"
        )
        let imported = try XLSXCodec.importWorkbook(from: url)
        let cellCount = imported.sheets.reduce(0) { $0 + $1.cells.count }
        let fpStart = CFAbsoluteTimeGetCurrent()
        let fp = WorkbookFingerprint.data(for: imported)
        let fpElapsed = CFAbsoluteTimeGetCurrent() - fpStart
        guard fp.count == 32, fpElapsed < 60 else {
          return Result(
            name: name,
            passed: false,
            detail: String(format: "fingerprint %.1fs", fpElapsed)
          )
        }
        let store = SpreadsheetDocumentStore()
        try store.load(from: url, finishesInBackground: false)
        drainMainQueue()
        guard !store.isDirty else {
          return Result(name: name, passed: false, detail: "full workbook open marked edited")
        }
        let vm = SpreadsheetViewModel(workbook: store.document.workbook)
        guard snapshotGrid(sheet: vm.activeSheet) != nil else {
          return Result(name: name, passed: false, detail: "grid snapshot failed")
        }
        return Result(name: name, passed: true, detail: "\(cellCount) cells opened")
      } catch {
        return Result(name: name, passed: false, detail: error.localizedDescription)
      }
    }

    private static func octoberEighth2026() -> Date? {
      utcDate(year: 2026, month: 10, day: 8, hour: 12, minute: 0, second: 0)
    }

    private static func utcDate(
      year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int
    ) -> Date? {
      var components = DateComponents()
      components.calendar = Calendar(identifier: .gregorian)
      components.timeZone = TimeZone(secondsFromGMT: 0)
      components.year = year
      components.month = month
      components.day = day
      components.hour = hour
      components.minute = minute
      components.second = second
      return components.date
    }
  }
#endif
