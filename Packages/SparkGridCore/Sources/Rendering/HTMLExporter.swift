import Calc
import Formula
import Foundation
import GridCore
import Model

/// Save As › Web Page (.html): every visible sheet as a table of what its cells show, with
/// number formats, bold, italic, colors, alignment, merged cells and column widths, as the
/// Finder preview draws them (Sam, Nov 20: "Add more save as format options"). Formulas are
/// written as their results.
public nonisolated enum HTMLExporter {
  public static func export(_ workbook: Workbook, title: String) -> String {
    let presentation = PreviewPresentation.make(workbook)
    var html = """
      <!doctype html>
      <html lang="en"><head><meta charset="utf-8">
      <meta name="generator" content="Spark Grid">
      <title>\(escape(title))</title>
      <style>
      body{font:13px -apple-system,Helvetica,Arial,sans-serif;margin:24px;color:#1d1d1f}
      h2{font-size:15px;margin:28px 0 8px}
      table{border-collapse:collapse;table-layout:fixed}
      td{border:1px solid #d9d9d9;padding:2px 6px;white-space:nowrap;overflow:hidden;\
      text-overflow:ellipsis;vertical-align:bottom}
      td.e{color:#c0392b}
      </style></head><body>

      """
    let visible = workbook.sheets.enumerated().filter { !$0.element.isHidden }
    for (index, sheet) in visible {
      if visible.count > 1 { html += "<h2>\(escape(sheet.name))</h2>\n" }
      html += table(sheet, index: index, presentation: presentation)
    }
    return html + "</body></html>\n"
  }

  private static func table(_ sheet: Sheet, index: Int, presentation: PreviewPresentation)
    -> String
  {
    let lastRow = sheet.maxPopulatedRow
    let lastCol = sheet.maxPopulatedColumn
    guard lastRow >= 0, lastCol >= 0 else { return "<p>(empty)</p>\n" }
    // Each merged block: its top-left cell spans it; the others are left out.
    var spans: [CellAddress: (rows: Int, cols: Int)] = [:]
    var covered = Set<CellAddress>()
    for range in sheet.mergedRanges {
      let n = range.normalized
      spans[CellAddress(row: n.minRow, col: n.minCol)] =
        (n.maxRow - n.minRow + 1, n.maxCol - n.minCol + 1)
      for row in n.minRow...n.maxRow {
        for col in n.minCol...n.maxCol where !(row == n.minRow && col == n.minCol) {
          covered.insert(CellAddress(row: row, col: col))
        }
      }
    }
    let columns = (0...lastCol).filter { !sheet.isColumnHidden($0) }
    var out = "<table><colgroup>"
    for col in columns {
      let width = presentation.columnWidth(
        sheet: index, column: col, default: Double(Workbook.defaultColumnWidth))
      out += "<col style=\"width:\(Int(width.rounded()))px\">"
    }
    out += "</colgroup>\n"
    for row in 0...lastRow where !sheet.isRowHidden(row) {
      out += "<tr>"
      for col in columns {
        let address = CellAddress(row: row, col: col)
        if covered.contains(address) { continue }
        let style = presentation.style(sheet: index, at: address, darkMode: false)
        var css: [String] = []
        switch style.alignment {
        case .center: css.append("text-align:center")
        case .right: css.append("text-align:right")
        default: break
        }
        if style.bold { css.append("font-weight:bold") }
        if style.italic { css.append("font-style:italic") }
        if style.fontSize != 12 { css.append("font-size:\(Int(style.fontSize))px") }
        if let fill = style.fill { css.append("background:\(hex(fill))") }
        if let text = style.textColor { css.append("color:\(hex(text))") }
        var attributes = ""
        if style.isError { attributes += " class=\"e\"" }
        if let span = spans[address] {
          if span.rows > 1 { attributes += " rowspan=\"\(span.rows)\"" }
          if span.cols > 1 { attributes += " colspan=\"\(span.cols)\"" }
        }
        if !css.isEmpty { attributes += " style=\"\(css.joined(separator: ";"))\"" }
        out += "<td\(attributes)>\(escape(presentation.text(sheet: index, at: address)))</td>"
      }
      out += "</tr>\n"
    }
    return out + "</table>\n"
  }

  static func hex(_ color: CodableColor) -> String {
    func byte(_ v: Double) -> String {
      String(format: "%02x", Int((min(1, max(0, v)) * 255).rounded()))
    }
    return "#" + byte(color.red) + byte(color.green) + byte(color.blue)
  }

  static func escape(_ text: String) -> String {
    text.replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
  }
}
