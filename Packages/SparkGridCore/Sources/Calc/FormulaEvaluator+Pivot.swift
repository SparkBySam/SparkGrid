import Formula
import Foundation
import GridCore
import Model

/// GETPIVOTDATA(data_field, pivot_table, [field1, item1], …) for pivot tables made in Spark
/// Grid. It reads the drawn table: the header row names the row fields and value columns, the
/// rows below hold the items, and the last row is the grand total.
extension FormulaEvaluator {
  func evalGetPivotData(_ args: [FormulaExpr]) -> CellValue {
    guard args.count >= 2, args.count % 2 == 0 else { return .error(.value) }
    let dataField = evaluate(args[0])
    if case .error = dataField { return dataField }
    let ref: FormulaRef
    switch resolvedExpr(args[1]) {
    case .cellRef(let cell): ref = cell
    case .range(let start, _): ref = start
    default: return .error(.ref)
    }
    guard let sheetName = ref.sheet ?? formulaSheetName,
      let pivot = pivotLookup(sheetName, ref.address),
      pivot.drawnRows >= 2, pivot.drawnColumns >= 1
    else { return .error(.ref) }

    var pairs: [(field: String, item: CellValue)] = []
    var index = 2
    while index + 1 < args.count {
      let field = evaluate(args[index])
      let item = evaluate(args[index + 1])
      if case .error = field { return field }
      if case .error = item { return item }
      pairs.append((Self.pivotKey(field), item))
      index += 2
    }

    let definition = pivot.definition
    let names = pivot.fieldNames
    func name(_ field: Int) -> String { field < names.count ? names[field] : "" }
    // Which value field: "Sum of Amount", or "Amount" when only one value reads it.
    let wanted = Self.pivotKey(dataField)
    let valueNames = pivot.valueNames.map { $0.lowercased() }
    var valueIndex = valueNames.firstIndex(of: wanted)
    if valueIndex == nil {
      let matches = definition.values.indices.filter {
        name(definition.values[$0].field).lowercased() == wanted
      }
      if matches.count == 1 { valueIndex = matches[0] }
    }
    guard let valueIndex else { return .error(.ref) }

    let rowFieldNames = definition.rows.map { name($0).lowercased() }
    let columnFieldNames = definition.columns.map { name($0).lowercased() }
    var rowItems: [Int: CellValue] = [:]
    var columnItems: [Int: CellValue] = [:]
    for pair in pairs {
      if let i = rowFieldNames.firstIndex(of: pair.field) {
        rowItems[i] = pair.item
      } else if let i = columnFieldNames.firstIndex(of: pair.field) {
        columnItems[i] = pair.item
      } else {
        return .error(.ref)
      }
    }
    // The drawn table has no subtotals: name every row field, or none for the grand total.
    guard rowItems.isEmpty || rowItems.count == rowFieldNames.count,
      columnItems.isEmpty || columnItems.count == columnFieldNames.count
    else { return .error(.ref) }

    let anchor = pivot.anchor
    func cell(_ row: Int, _ col: Int) -> CellValue {
      lookup(
        FormulaRef(
          sheet: sheetName, row: anchor.row + row, col: anchor.col + col, absRow: false,
          absCol: false))
    }
    func same(_ a: CellValue, _ b: CellValue) -> Bool {
      if let x = a.asNumber, let y = b.asNumber, case .number = a, case .number = b {
        return x == y
      }
      return Self.pivotKey(a) == Self.pivotKey(b)
    }

    let rowFieldCount = rowFieldNames.count
    let valueCount = definition.values.count
    let lastRow = pivot.drawnRows - 1
    // Row: the grand total row, or the row whose labels match every row item.
    var row: Int?
    if rowItems.isEmpty {
      row = lastRow
    } else {
      for r in 1..<lastRow
      where (0..<rowFieldCount).allSatisfy({ same(cell(r, $0), rowItems[$0] ?? .blank) }) {
        row = r
        break
      }
    }
    // Column: the value column, the column item's column, or that value's grand total column.
    var col: Int?
    if columnFieldNames.isEmpty {
      col = rowFieldCount + valueIndex
    } else if columnItems.isEmpty {
      col = pivot.drawnColumns - valueCount + valueIndex
    } else {
      let label = (0..<columnFieldNames.count).map { Self.pivotLabel(columnItems[$0] ?? .blank) }
        .joined(separator: " / ")
      let header =
        valueCount > 1 ? "\(label) – \(pivot.valueNames[valueIndex])" : label
      for c in rowFieldCount..<(pivot.drawnColumns - valueCount)
      where Self.pivotKey(cell(0, c)) == header.lowercased() {
        col = c
        break
      }
    }
    guard let row, let col else { return .error(.ref) }
    let value = cell(row, col)
    if case .blank = value { return .error(.ref) }
    return value
  }

  /// How a pivot shows an item: blanks as "(blank)", text trimmed.
  static func pivotLabel(_ value: CellValue) -> String {
    switch value {
    case .blank: return "(blank)"
    case .string(let text):
      let trimmed = text.trimmingCharacters(in: .whitespaces)
      return trimmed.isEmpty ? "(blank)" : trimmed
    default: return value.displayString
    }
  }

  static func pivotKey(_ value: CellValue) -> String {
    pivotLabel(value).lowercased()
  }
}
