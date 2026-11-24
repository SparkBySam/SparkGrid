import Formula
import Foundation
import GridCore
import Model
import NumberFormat

/// The number format a formula typed into a General cell takes, as other apps give it (asked
/// of Excel 16.115 on Nov 18): =DATE(...) shows as a date, =PMT(...) as money, =A1+1 as A1
/// does. Only these cases; anything else stays General.
enum FormulaAutoFormat {
  struct Choice: Equatable {
    var kind: CellFormat.NumberFormat
    var code: String
  }

  static let money = "$#,##0.00_);[Red]($#,##0.00)"

  /// Functions whose result has a format of its own.
  private static let byFunction: [String: Choice] = {
    var table: [String: Choice] = [
      "DATE": Choice(kind: .date, code: "m/d/yy"),
      "TODAY": Choice(kind: .date, code: "m/d/yy"),
      "NOW": Choice(kind: .date, code: "m/d/yy h:mm"),
      "TIME": Choice(kind: .time, code: "h:mm AM/PM"),
      "RATE": Choice(kind: .percent, code: "0%"),
    ]
    for name in ["PMT", "PPMT", "IPMT", "FV", "PV", "NPV", "SLN", "SYD", "DDB", "DB"] {
      table[name] = Choice(kind: .currency, code: money)
    }
    return table
  }()

  /// Functions whose result keeps the format of the cells they read.
  private static let keepsFormat: Set<String> = ["SUM", "ROUND"]

  static func choice(for raw: String, on sheet: Sheet, in workbook: Workbook) -> Choice? {
    guard FormulaSyntax.isFormula(raw), let expr = try? FormulaParser.parse(raw) else { return nil }
    return choice(expr, sheet: sheet, workbook: workbook)
  }

  private static func choice(_ expr: FormulaExpr, sheet: Sheet, workbook: Workbook) -> Choice? {
    switch expr {
    case .call(let name, let args):
      let plain = plainName(name)
      if let fixed = byFunction[plain] { return fixed }
      guard keepsFormat.contains(plain) else { return nil }
      for arg in args {
        if let found = referenceFormats(arg, sheet: sheet, workbook: workbook).first {
          return found
        }
      }
      return nil
    case .cellRef:
      return referenceFormats(expr, sheet: sheet, workbook: workbook).first
    case .binary(let op, _, _) where op == .add || op == .subtract:
      // A date plus or minus days is a date; two dates added or taken apart are not.
      var operands: [FormulaExpr] = []
      collectAddends(expr, into: &operands)
      let formats = operands.compactMap { operand -> Choice? in
        guard case .cellRef = operand else { return nil }
        return referenceFormats(operand, sheet: sheet, workbook: workbook).first
      }
      if formats.filter({ $0.kind == .date }).count >= 2 { return nil }
      return formats.first
    default:
      return nil
    }
  }

  private static func collectAddends(_ expr: FormulaExpr, into out: inout [FormulaExpr]) {
    if case .binary(let op, let lhs, let rhs) = expr, op == .add || op == .subtract {
      collectAddends(lhs, into: &out)
      collectAddends(rhs, into: &out)
    } else {
      out.append(expr)
    }
  }

  /// The formats of the formatted cells a reference names, in order.
  private static func referenceFormats(_ expr: FormulaExpr, sheet: Sheet, workbook: Workbook)
    -> [Choice]
  {
    func target(_ name: String?) -> Sheet? {
      guard let name else { return sheet }
      return workbook.sheets.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }
    func format(of cell: Cell) -> Choice? {
      guard let format = cell.format else { return nil }
      if let code = format.formatCode, !code.isEmpty, code.lowercased() != "general" {
        return Choice(kind: format.numberFormat, code: code)
      }
      guard format.numberFormat != .general else { return nil }
      return Choice(
        kind: format.numberFormat, code: format.viewerFormatCode)
    }
    switch expr {
    case .cellRef(let ref):
      guard let owner = target(ref.sheet), !ref.isRowOpen, !ref.isColOpen else { return [] }
      return format(of: owner.cell(at: ref.address)).map { [$0] } ?? []
    case .range(let start, let end):
      guard let owner = target(start.sheet ?? end.sheet), !start.isRowOpen, !start.isColOpen,
        !end.isRowOpen, !end.isColOpen
      else { return [] }
      let rows = min(start.row, end.row)...max(start.row, end.row)
      let cols = min(start.col, end.col)...max(start.col, end.col)
      guard rows.count * cols.count <= 10_000 else { return [] }
      var found: [Choice] = []
      for row in rows {
        for col in cols {
          if let choice = format(of: owner.cell(at: CellAddress(row: row, col: col))) {
            found.append(choice)
            return found
          }
        }
      }
      return found
    default:
      return []
    }
  }

  private static func plainName(_ name: String) -> String {
    var upper = name.uppercased()
    for prefix in ["_XLFN._XLWS.", "_XLFN."] where upper.hasPrefix(prefix) {
      upper.removeFirst(prefix.count)
    }
    return upper
  }
}
