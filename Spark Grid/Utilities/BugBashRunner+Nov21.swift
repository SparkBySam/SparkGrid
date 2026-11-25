import AppKit
import Foundation
import SparkGridCore

#if DEBUG
  /// Checks for what changed after Sam's hand test of the 1.7 stress workbook (Nov 20–21).
  extension BugBashRunner {
    @MainActor
    static func nov21Checks() -> [Result] {
      [
        removeTableRestoresFilledHeaders(),
        everyCommandHasAShortcutToChange(),
        clearFormatsKeepsValues(),
        webPageAndTabTextExports(),
        lambdaAndCriteriaArraysInTheGrid(),
      ]
    }

    /// Making a table over blank header cells fills them ("Column 2"…); removing it puts them
    /// back, except one someone changed in between.
    @MainActor
    private static func removeTableRestoresFilledHeaders() -> Result {
      let name = "remove table restores filled headers"
      var sheet = Sheet(name: "T")
      sheet.setCell(Cell(raw: "Title"), at: .origin)
      for row in 1...3 {
        for col in 0...2 {
          sheet.setCell(Cell(raw: "\(row * 10 + col)"), at: CellAddress(row: row, col: col))
        }
      }
      let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
      vm.selectRange(from: .origin, to: CellAddress(row: 3, col: 2))
      vm.createTable()
      let b1 = CellAddress(row: 0, col: 1)
      let c1 = CellAddress(row: 0, col: 2)
      guard vm.selectedTableIndex != nil, vm.activeSheet.cell(at: b1).raw == "Column 2",
        vm.activeSheet.cell(at: c1).raw == "Column 3"
      else {
        return Result(
          name: name, passed: false,
          detail: "table not made or headers not filled: \(vm.activeSheet.cell(at: b1).raw)")
      }
      vm.setCellValue("Amount", at: c1)
      guard let index = vm.selectedTableIndex else {
        return Result(name: name, passed: false, detail: "table lost")
      }
      vm.removeTable(at: index)
      let restored = vm.activeSheet.cell(at: b1).raw
      let kept = vm.activeSheet.cell(at: c1).raw
      let title = vm.activeSheet.cell(at: .origin).raw
      let ok =
        vm.activeSheet.fileExtras.tables.isEmpty && restored.isEmpty && kept == "Amount"
        && title == "Title"
      return Result(
        name: name, passed: ok,
        detail: ok
          ? "Column 2 cleared, Amount kept, Title untouched"
          : "B1 \(restored), C1 \(kept), A1 \(title)")
    }

    /// Every action in Settings › Shortcuts has a default, none of Spark Grid's own commands is
    /// reserved, defaults don't clash, and a change and its reset work.
    @MainActor
    private static func everyCommandHasAShortcutToChange() -> Result {
      let name = "every command's shortcut can change"
      let settings = AppSettings.shared
      var seen: [StoredShortcut: HotkeyAction] = [:]
      for action in HotkeyAction.allCases {
        let shortcut = settings.defaultShortcut(for: action)
        guard !shortcut.key.isEmpty else {
          return Result(name: name, passed: false, detail: "\(action) has no default")
        }
        if let other = seen[shortcut] {
          return Result(
            name: name, passed: false,
            detail: "\(action) and \(other) share \(shortcut.displayString)")
        }
        seen[shortcut] = action
        if AppSettings.reservedShortcuts[shortcut] != nil {
          return Result(name: name, passed: false, detail: "\(action) is reserved")
        }
      }
      let before = settings.shortcut(for: .find)
      let changed = StoredShortcut(
        key: "f", modifiers: NSEvent.ModifierFlags.command.union(.control).rawValue)
      settings.setShortcut(changed, for: .find)
      let took = settings.shortcut(for: .find) == changed
      settings.resetShortcut(for: .find)
      let reset = settings.shortcut(for: .find) == settings.defaultShortcut(for: .find)
      settings.setShortcut(before, for: .find)
      let f2 = settings.defaultShortcut(for: .editCell)
      let ok =
        took && reset && f2.isFunctionKey && f2.displayString == "F2"
        && HotkeyAction.allCases.count >= 38
      return Result(
        name: name, passed: ok,
        detail: ok
          ? "\(HotkeyAction.allCases.count) actions, no clashes, change and reset work, F2 shown"
          : "took \(took), reset \(reset), F2 \(f2.displayString)")
    }

    @MainActor
    private static func clearFormatsKeepsValues() -> Result {
      let name = "clear formats keeps values"
      var format = CellFormat()
      format.bold = true
      format.fillColor = CodableColor(red: 1, green: 0, blue: 0, alpha: 1)
      var sheet = Sheet(name: "F")
      sheet.setCell(Cell(raw: "42", format: format), at: .origin)
      let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
      vm.selectRange(from: .origin, to: .origin)
      vm.clearFormats()
      let cell = vm.activeSheet.cell(at: .origin)
      let ok = cell.raw == "42" && (cell.format == nil || cell.format == CellFormat())
      return Result(
        name: name, passed: ok,
        detail: ok ? "42 kept, formats gone" : "\(cell.raw), \(String(describing: cell.format))")
    }

    private static func webPageAndTabTextExports() -> Result {
      let name = "save as web page and tab text"
      var sheet = Sheet(name: "Sales")
      sheet.setCell(Cell(raw: "Region"), at: .origin)
      sheet.setCell(Cell(raw: "a\tb"), at: CellAddress(row: 1, col: 0))
      sheet.setCell(Cell(raw: "=1+1"), at: CellAddress(row: 1, col: 1))
      let tsv = CSVCodec.exportTSV(from: sheet)
      let html = HTMLExporter.export(Workbook(sheets: [sheet]), title: "Sales")
      let ok =
        tsv == "Region\t\n\"a\tb\"\t=1+1" && html.contains("<table>")
        && html.contains("<td style=\"text-align:right\">2</td>") && !html.contains("=1+1")
      return Result(
        name: name, passed: ok, detail: ok ? "tsv quoted, html shows the result 2" : tsv)
    }

    /// The engine fixes from the stress workbook, through the grid's own model.
    @MainActor
    private static func lambdaAndCriteriaArraysInTheGrid() -> Result {
      let name = "lambda in place and criteria arrays"
      var sheet = Sheet(name: "L")
      let regions = ["East", "West", "East"]
      for (row, region) in regions.enumerated() {
        sheet.setCell(Cell(raw: region), at: CellAddress(row: row, col: 0))
        sheet.setCell(Cell(raw: "\((row + 1) * 10)"), at: CellAddress(row: row, col: 1))
      }
      let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
      // Typed in, as a person would.
      vm.setCellValue("=LAMBDA(x,x*3)(7)", at: CellAddress(row: 5, col: 0))
      vm.setCellValue("=SUM(SUMIFS(B1:B3,A1:A3,A1:A3))", at: CellAddress(row: 6, col: 0))
      vm.setCellValue("=SUMIF(Nope!A1:A3,1)", at: CellAddress(row: 7, col: 0))
      let lambda = vm.displayValue(at: CellAddress(row: 5, col: 0))
      let sums = vm.displayValue(at: CellAddress(row: 6, col: 0))
      let missing = vm.displayValue(at: CellAddress(row: 7, col: 0))
      // East 40 + West 20 + East 40.
      let ok = lambda == .number(21) && sums == .number(100) && missing == .error(.ref)
      return Result(
        name: name, passed: ok,
        detail: ok
          ? "21, 100, #REF!"
          : "\(lambda.displayString), \(sums.displayString), \(missing.displayString)")
    }
  }
#endif
