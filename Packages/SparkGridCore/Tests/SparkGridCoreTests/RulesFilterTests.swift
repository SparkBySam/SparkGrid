import FileFormats
import Foundation
import GridCore
import Model
import XCTest

/// Rule filters: contains, greater than, between, top and bottom, saved the way other apps read.
final class RulesFilterTests: XCTestCase {
  private typealias Rule = ColumnFilterRules.Rule

  func testTextRulesIgnoreCase() {
    let none = ColumnFilterRules.Cutoffs()
    XCTAssertTrue(
      ColumnFilterRules(rules: [Rule(kind: .contains, value: "west")]).matches(
        "North West", cutoffs: none))
    XCTAssertFalse(
      ColumnFilterRules(rules: [Rule(kind: .notContains, value: "west")]).matches(
        "Northwest", cutoffs: none))
    XCTAssertTrue(
      ColumnFilterRules(rules: [Rule(kind: .beginsWith, value: "SO-1")]).matches(
        "SO-100001", cutoffs: none))
    XCTAssertTrue(
      ColumnFilterRules(rules: [Rule(kind: .endsWith, value: "b")]).matches(
        "Order 12-B", cutoffs: none))
  }

  func testNumberRulesReadShownNumbers() {
    let none = ColumnFilterRules.Cutoffs()
    let over = ColumnFilterRules(rules: [Rule(kind: .greaterThan, value: "1000")])
    XCTAssertTrue(over.matches("$1,250.50", cutoffs: none))
    XCTAssertFalse(over.matches("(1,250.50)", cutoffs: none))
    XCTAssertFalse(over.matches("North", cutoffs: none))
    let between = ColumnFilterRules(rules: [Rule(kind: .between, value: "10", value2: "5")])
    XCTAssertTrue(between.matches("7", cutoffs: none))
    XCTAssertFalse(between.matches("11", cutoffs: none))
    // A percent compares as shown.
    XCTAssertTrue(
      ColumnFilterRules(rules: [Rule(kind: .greaterThan, value: "10")]).matches(
        "12%", cutoffs: none))
  }

  func testAnyAndAll() {
    let none = ColumnFilterRules.Cutoffs()
    let rules = [Rule(kind: .equals, value: "East"), Rule(kind: .equals, value: "West")]
    XCTAssertTrue(ColumnFilterRules(rules: rules, matchAll: false).matches("West", cutoffs: none))
    XCTAssertFalse(ColumnFilterRules(rules: rules, matchAll: true).matches("West", cutoffs: none))
  }

  func testTopAndBottomHideTheRest() {
    var sheet = Sheet(name: "Data")
    let values = [12, 7, 3, 19, 7, 25]
    sheet.setCell(Cell(raw: "Value"), at: CellAddress(row: 0, col: 0))
    for (i, v) in values.enumerated() {
      sheet.setCell(Cell(raw: String(v)), at: CellAddress(row: i + 1, col: 0))
    }
    var filter = SheetFilterState(
      range: CellRange(start: .origin, end: CellAddress(row: values.count, col: 0)))
    filter.rulesByColumn[0] = ColumnFilterRules(rules: [Rule(kind: .top, value: "2")])
    let shown: (CellAddress) -> String = { sheet.cell(at: $0).raw }
    let cutoffs = filter.cutoffs(sheet: sheet, displayString: shown)
    let visible = (1...values.count).filter {
      !filter.isRowHidden($0, sheet: sheet, displayString: shown, cutoffs: cutoffs)
    }.map { values[$0 - 1] }
    XCTAssertEqual(visible, [19, 25])
  }

  func testRulesSaveAndReopen() throws {
    let cases: [ColumnFilterRules] = [
      ColumnFilterRules(rules: [Rule(kind: .contains, value: "West")]),
      ColumnFilterRules(rules: [Rule(kind: .notContains, value: "a*b")]),
      ColumnFilterRules(rules: [Rule(kind: .beginsWith, value: "SO")]),
      ColumnFilterRules(rules: [Rule(kind: .endsWith, value: "B")]),
      ColumnFilterRules(rules: [
        Rule(kind: .greaterThan, value: "100"), Rule(kind: .lessOrEqual, value: "500"),
      ]),
      ColumnFilterRules(
        rules: [Rule(kind: .equals, value: "East"), Rule(kind: .notEquals, value: "West")],
        matchAll: false),
      ColumnFilterRules(rules: [Rule(kind: .between, value: "10", value2: "20")]),
      ColumnFilterRules(rules: [Rule(kind: .top, value: "10")]),
      ColumnFilterRules(rules: [Rule(kind: .bottom, value: "3")]),
    ]
    for rules in cases {
      var sheet = Sheet(name: "Data")
      sheet.setCell(Cell(raw: "Region"), at: CellAddress(row: 0, col: 1))
      sheet.setCell(Cell(raw: "West"), at: CellAddress(row: 1, col: 1))
      var filter = SheetFilterState(
        range: CellRange(start: CellAddress(row: 0, col: 1), end: CellAddress(row: 5, col: 1)))
      filter.rulesByColumn[1] = rules
      sheet.autoFilter = filter
      let saved = try XLSXCodec.exportWorkbook(Workbook(sheets: [sheet]))
      let reopened = try XLSXCodec.importWorkbook(from: saved)
      XCTAssertEqual(reopened.sheets[0].autoFilter?.rulesByColumn[1], rules, "\(rules)")
    }
  }

  func testRowsAFilterHidesAreNotKeptAsHiddenRows() throws {
    var sheet = Sheet(name: "Data")
    sheet.setCell(Cell(raw: "Region"), at: .origin)
    for (i, region) in ["East", "West", "East"].enumerated() {
      sheet.setCell(Cell(raw: region), at: CellAddress(row: i + 1, col: 0))
    }
    var filter = SheetFilterState(
      range: CellRange(start: .origin, end: CellAddress(row: 3, col: 0)),
      selectedValuesByColumn: [0: ["East"]])
    filter.excludedColumns = []
    sheet.autoFilter = filter
    // As another app saves it: the filtered-out row is marked hidden, and so is one outside.
    sheet.fileExtras.hiddenRows = [2, 6]
    let reopened = try XLSXCodec.importWorkbook(
      from: try XLSXCodec.exportWorkbook(Workbook(sheets: [sheet])))
    XCTAssertEqual(reopened.sheets[0].fileExtras.hiddenRows, [6])
  }

  func testOldFilterDataWithoutRulesStillDecodes() throws {
    let json =
      #"{"range":{"start":{"row":0,"col":0},"end":{"row":3,"col":1}},"selectedValuesByColumn":{}}"#
    let filter = try JSONDecoder().decode(SheetFilterState.self, from: Data(json.utf8))
    XCTAssertTrue(filter.rulesByColumn.isEmpty)
  }
}
