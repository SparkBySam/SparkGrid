import Foundation
import SparkGridCore

/// Making, styling and removing tables. A table is saved as its own part, as other apps keep it,
/// and drawn with its style under the cells' own formats.
extension SpreadsheetViewModel {
  struct TableStyleChoice: Identifiable {
    let name: String
    let title: String
    var id: String { name }
  }

  static let tableStyles: [TableStyleChoice] = [
    TableStyleChoice(name: "TableStyleMedium2", title: "Blue"),
    TableStyleChoice(name: "TableStyleMedium3", title: "Orange"),
    TableStyleChoice(name: "TableStyleMedium7", title: "Green"),
    TableStyleChoice(name: "TableStyleMedium5", title: "Gold"),
    TableStyleChoice(name: "TableStyleMedium1", title: "Gray"),
    TableStyleChoice(name: "TableStyleLight9", title: "Light Blue"),
    TableStyleChoice(name: "TableStyleDark1", title: "Dark"),
  ]

  /// The table on the active sheet that holds `address`.
  func tableIndex(containing address: CellAddress) -> Int? {
    activeSheet.fileExtras.tables.firstIndex { $0.range.contains(address) }
  }

  var selectedTableIndex: Int? { tableIndex(containing: selectionAnchor) }

  /// The block a new table would cover: the selection, or the filled block around one cell.
  var newTableRange: CellRange? {
    let range =
      selectionRange.isSingleCell ? contiguousRegion(around: selectionAnchor) : selectionRange
    guard let range else { return nil }
    let n = range.normalized
    guard n.maxRow > n.minRow else { return nil }
    let overlaps = activeSheet.fileExtras.tables.contains { table in
      let t = table.range.normalized
      return t.minRow <= n.maxRow && n.minRow <= t.maxRow && t.minCol <= n.maxCol
        && n.minCol <= t.maxCol
    }
    return overlaps ? nil : range
  }

  /// Turns the selection into a table, with its first row as the header.
  func createTable() {
    commitEditIfNeeded()
    guard let range = newTableRange else { return }
    let n = range.normalized
    undoManager?.beginUndoGrouping()
    defer {
      undoManager?.endUndoGrouping()
      undoManager?.setActionName("Create Table")
    }
    // Every header needs a name, and other apps reject a table whose names repeat.
    var names: [String] = []
    var used = Set<String>()
    for col in n.minCol...n.maxCol {
      let address = CellAddress(row: n.minRow, col: col)
      var name = displayString(at: address).trimmingCharacters(in: .whitespacesAndNewlines)
      let blank = name.isEmpty
      if blank { name = "Column \(col - n.minCol + 1)" }
      var unique = name
      var suffix = 2
      while used.contains(unique.lowercased()) {
        unique = "\(name)\(suffix)"
        suffix += 1
      }
      used.insert(unique.lowercased())
      names.append(unique)
      if blank || unique != name { setCellValue(unique, at: address) }
    }
    let (id, tableName) = nextTableIdentity()
    let ref = range.a1Label
    let columns = names.enumerated().map { index, name in
      #"<tableColumn id="\#(index + 1)" name="\#(Self.xmlEscaped(name))"/>"#
    }.joined()
    let xml =
      #"<table xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" id="\#(id)" name="\#(tableName)" displayName="\#(tableName)" ref="\#(ref)" totalsRowShown="0"><autoFilter ref="\#(ref)"/><tableColumns count="\#(names.count)">\#(columns)</tableColumns><tableStyleInfo name="TableStyleMedium2" showFirstColumn="0" showLastColumn="0" showRowStripes="1" showColumnStripes="0"/></table>"#
    updateFileExtras(actionName: "Create Table") { extras in
      extras.tables.append(SheetTable(range: range, xml: xml))
    }
    notifyGridRefresh()
  }

  /// Keeps the cells and their values; only the table goes.
  func removeTable(at index: Int) {
    guard activeSheet.fileExtras.tables.indices.contains(index) else { return }
    updateFileExtras(actionName: "Remove Table") { extras in
      extras.tables.remove(at: index)
    }
    notifyGridRefresh()
  }

  func tableStyleName(at index: Int) -> String? {
    guard activeSheet.fileExtras.tables.indices.contains(index) else { return nil }
    let xml = activeSheet.fileExtras.tables[index].xml
    guard
      let range = xml.range(
        of: #"<(\w+:)?tableStyleInfo\b[^>]*\bname="[^"]*""#, options: .regularExpression)
    else { return nil }
    return xml[range].split(separator: "\"").last.map(String.init)
  }

  func setTableStyle(_ name: String, at index: Int) {
    guard activeSheet.fileExtras.tables.indices.contains(index) else { return }
    var xml = activeSheet.fileExtras.tables[index].xml
    let info =
      #"<tableStyleInfo name="\#(name)" showFirstColumn="0" showLastColumn="0" showRowStripes="1" showColumnStripes="0"/>"#
    if let existing = xml.range(
      of: #"<(\w+:)?tableStyleInfo\b[^>]*?(/>|>\s*</(\w+:)?tableStyleInfo>)"#,
      options: .regularExpression)
    {
      xml.replaceSubrange(existing, with: info)
    } else if let close = xml.range(
      of: #"</(\w+:)?table>"#, options: [.regularExpression, .backwards])
    {
      xml.insert(contentsOf: info, at: close.lowerBound)
    } else {
      return
    }
    updateFileExtras(actionName: "Table Style") { extras in
      extras.tables[index].xml = xml
    }
    notifyGridRefresh()
  }

  /// An id and `TableN` name no table in the workbook has.
  private func nextTableIdentity() -> (Int, String) {
    var ids = Set<Int>()
    var names = Set<String>()
    for sheet in workbook.sheets {
      for table in sheet.fileExtras.tables {
        if let id = Self.attribute("id", in: table.xml).flatMap(Int.init) { ids.insert(id) }
        for key in ["name", "displayName"] {
          if let name = Self.attribute(key, in: table.xml) { names.insert(name.lowercased()) }
        }
      }
    }
    let id = (ids.max() ?? 0) + 1
    var number = 1
    while names.contains("table\(number)") { number += 1 }
    return (id, "Table\(number)")
  }

  /// An attribute on the `<table>` tag itself.
  private static func attribute(_ name: String, in xml: String) -> String? {
    guard let tag = xml.range(of: #"<(\w+:)?table\b[^>]*>"#, options: .regularExpression),
      let range = xml.range(of: #"\s\#(name)="[^"]*""#, options: .regularExpression, range: tag)
    else { return nil }
    return xml[range].split(separator: "\"").dropFirst().first.map(String.init)
  }

  private static func xmlEscaped(_ text: String) -> String {
    text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
  }
}
