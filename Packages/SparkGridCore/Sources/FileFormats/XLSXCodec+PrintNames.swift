import Formula
import Foundation
import GridCore
import Model

/// Names a file scopes to one sheet with the `_xlnm.` prefix: the print area, print titles and a
/// filter's range. They belong to their sheet, not to the workbook's name list, and a save writes
/// them back with `localSheetId` so each sheet keeps its own.
extension XLSXCodec {
  static let printAreaName = "_xlnm.Print_Area"

  /// True for a name that belongs on its sheet rather than in the workbook's name list.
  static func isSheetBuiltInName(_ name: String, localSheetId: String?) -> Bool {
    localSheetId != nil && name.lowercased().hasPrefix("_xlnm.")
  }

  /// Moves `_xlnm.` names scoped to a sheet onto that sheet.
  static func importSheetBuiltInNames(archiveData: Data, into sheets: inout [Sheet]) {
    guard let xml = zipEntryString(archiveData: archiveData, entryPath: "xl/workbook.xml"),
      let blockStart = xml.range(of: "<definedNames"),
      let blockEnd = xml.range(of: "</definedNames>", range: blockStart.upperBound..<xml.endIndex),
      let regex = try? NSRegularExpression(
        pattern: #"<(?:[\w]+:)?definedName\b([^>]*)>([\s\S]*?)</(?:[\w]+:)?definedName>"#)
    else { return }
    let section = xml[blockStart.lowerBound..<blockEnd.upperBound] as Substring
    let text = String(section) as NSString
    for match in regex.matches(
      in: String(section), range: NSRange(location: 0, length: text.length))
    {
      let attrs = text.substring(with: match.range(at: 1))
      let body = decodeXMLEntities(text.substring(with: match.range(at: 2)))
        .trimmingCharacters(in: .whitespacesAndNewlines)
      guard let name = xmlAttribute(attrs, named: "name"),
        let local = xmlAttribute(attrs, named: "localSheetId"),
        isSheetBuiltInName(name, localSheetId: local),
        let index = Int(local), sheets.indices.contains(index), !body.isEmpty
      else { continue }
      if name.caseInsensitiveCompare(printAreaName) == .orderedSame,
        let range = singleRange(body, sheetName: sheets[index].name)
      {
        sheets[index].fileExtras.printArea = range
      } else {
        sheets[index].fileExtras.builtInNames[name] = body
      }
    }
  }

  /// One rectangle on `sheetName`, or nil for several areas, another sheet, or a formula.
  static func singleRange(_ formula: String, sheetName: String) -> CellRange? {
    var text = formula
    if text.hasPrefix("=") { text.removeFirst() }
    guard !text.contains(",") else { return nil }
    let ends: (FormulaRef, FormulaRef)
    if let pair = A1Reference.parseFormulaRange(text) {
      ends = pair
    } else if let ref = A1Reference.parseFormulaRef(text) {
      ends = (ref, ref)
    } else {
      return nil
    }
    if let sheet = ends.0.sheet, sheet.caseInsensitiveCompare(sheetName) != .orderedSame {
      return nil
    }
    func address(_ ref: FormulaRef, last: Bool) -> CellAddress {
      CellAddress(
        row: ref.isRowOpen ? (last ? maxRowIndex : 0) : ref.row,
        col: ref.isColOpen ? (last ? maxColumnIndex : 0) : ref.col)
    }
    return CellRange(start: address(ends.0, last: false), end: address(ends.1, last: true))
  }

  static let maxRowIndex = 1_048_575
  static let maxColumnIndex = 16_383

  /// `'Sheet'!$A$1:$D$20`, the form a print area is written in.
  static func absoluteReference(sheetName: String, range: CellRange) -> String {
    let n = range.normalized
    let quoted = "'" + sheetName.replacingOccurrences(of: "'", with: "''") + "'"
    func cell(_ row: Int, _ col: Int) -> String {
      "$" + A1Notation.columnLabel(for: col) + "$" + String(row + 1)
    }
    return "\(quoted)!\(cell(n.minRow, n.minCol)):\(cell(n.maxRow, n.maxCol))"
  }

  /// `<definedName>` elements for every sheet's print area and other `_xlnm.` names.
  static func sheetBuiltInNamesXML(_ sheets: [Sheet]) -> String {
    var out = ""
    for (index, sheet) in sheets.enumerated() {
      var names = sheet.fileExtras.builtInNames
      if let area = sheet.fileExtras.printArea {
        names[printAreaName] = absoluteReference(sheetName: sheet.name, range: area)
      }
      for (name, formula) in names.sorted(by: { $0.key < $1.key }) {
        out +=
          #"<definedName name="\#(escapeXML(name))" localSheetId="\#(index)">"#
          + escapeXML(formula) + "</definedName>"
      }
    }
    return out
  }
}
