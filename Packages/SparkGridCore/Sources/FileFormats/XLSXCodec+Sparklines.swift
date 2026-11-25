import Formula
import Foundation
import GridCore
import Model

/// Sparklines, kept in a worksheet's extension list as `<x14:sparklineGroups>`, the way other
/// spreadsheet apps save them.
extension XLSXCodec {
  static let sparklineExtensionURI = "{05C60535-1F16-4fd2-B633-F4F36F0B64E0}"

  /// The groups in a `<x14:sparklineGroups>` element. Data on `sheetName` reads as this sheet.
  static func sparklineGroups(in xml: String, sheetName: String) -> [SparklineGroup] {
    // Drop prefixes, so `x14:` and `xm:` read the same as bare names.
    let plain = xml.replacingOccurrences(
      of: #"<(/?)[A-Za-z0-9]+:"#, with: "<$1", options: .regularExpression)
    var groups: [SparklineGroup] = []
    for block in captures(#"<sparklineGroup\b([^>]*)>([\s\S]*?)</sparklineGroup>"#, in: plain) {
      let attributes = block[0]
      let body = block[1]
      func flag(_ name: String) -> Bool {
        let value = attribute(name, in: attributes)
        return value == "1" || value == "true"
      }
      var lines: [SparklineGroup.Sparkline] = []
      for line in captures(#"<sparkline>([\s\S]*?)</sparkline>"#, in: body) {
        guard
          let formula = captures(#"<f>([\s\S]*?)</f>"#, in: line[0]).first?.first,
          let sqref = captures(#"<sqref>([\s\S]*?)</sqref>"#, in: line[0]).first?.first,
          let location = parseCellRange(sqref.trimmingCharacters(in: .whitespaces))?.start
        else { continue }
        let text = unescapedXML(formula).trimmingCharacters(in: .whitespacesAndNewlines)
        var dataSheet: String?
        let data: CellRange
        if let (start, end) = A1Reference.parseFormulaRange(text) {
          dataSheet = start.sheet ?? end.sheet
          data = CellRange(start: start.address, end: end.address)
        } else if let ref = A1Reference.parseFormulaRef(text) {
          dataSheet = ref.sheet
          data = CellRange(start: ref.address, end: ref.address)
        } else {
          continue
        }
        if dataSheet == sheetName { dataSheet = nil }
        lines.append(.init(location: location, dataSheet: dataSheet, data: data))
      }
      guard !lines.isEmpty else { continue }
      groups.append(
        SparklineGroup(
          kind: .init(fileType: attribute("type", in: attributes)),
          colorHex: color("colorSeries", in: body) ?? SparklineGroup.defaultColor,
          negativeColorHex: color("colorNegative", in: body) ?? SparklineGroup.defaultNegativeColor,
          showsMarkers: flag("markers"),
          showsHighLow: flag("high") || flag("low"),
          showsNegative: flag("negative"),
          sparklines: lines))
    }
    return groups
  }

  /// The worksheet's `<extLst>` holding its sparklines, or nothing when it has none.
  static func sparklinesExtensionXML(_ groups: [SparklineGroup], sheetName: String) -> String {
    let groups = groups.filter { !$0.sparklines.isEmpty }
    guard !groups.isEmpty else { return "" }
    let ownSheet = "'\(sheetName.replacingOccurrences(of: "'", with: "''"))'"
    var xml =
      #"<extLst><ext uri="\#(sparklineExtensionURI)" "#
      + #"xmlns:x14="http://schemas.microsoft.com/office/spreadsheetml/2009/9/main">"#
      + #"<x14:sparklineGroups xmlns:xm="http://schemas.microsoft.com/office/excel/2006/main">"#
    for group in groups {
      var attributes = #" displayEmptyCellsAs="gap""#
      if let type = group.kind.fileType { attributes += #" type="\#(type)""# }
      if group.showsMarkers, group.kind == .line { attributes += #" markers="1""# }
      if group.showsHighLow { attributes += #" high="1" low="1""# }
      if group.showsNegative { attributes += #" negative="1""# }
      let series = argb(group.colorHex)
      let negative = argb(group.negativeColorHex)
      xml += "<x14:sparklineGroup\(attributes)>"
      xml += #"<x14:colorSeries rgb="\#(series)"/><x14:colorNegative rgb="\#(negative)"/>"#
      xml += #"<x14:colorAxis rgb="FF000000"/><x14:colorMarkers rgb="\#(series)"/>"#
      xml += #"<x14:colorFirst rgb="\#(series)"/><x14:colorLast rgb="\#(series)"/>"#
      xml += #"<x14:colorHigh rgb="\#(negative)"/><x14:colorLow rgb="\#(negative)"/>"#
      xml += "<x14:sparklines>"
      for line in group.sparklines {
        let sheet =
          line.dataSheet.map { "'\($0.replacingOccurrences(of: "'", with: "''"))'" } ?? ownSheet
        let n = line.data.normalized
        let first = CellAddress(row: n.minRow, col: n.minCol).a1
        let last = CellAddress(row: n.maxRow, col: n.maxCol).a1
        let ref = first == last ? first : "\(first):\(last)"
        xml += "<x14:sparkline><xm:f>\(escapeXML(sheet + "!" + ref))</xm:f>"
        xml += "<xm:sqref>\(line.location.a1)</xm:sqref></x14:sparkline>"
      }
      xml += "</x14:sparklines></x14:sparklineGroup>"
    }
    return xml + "</x14:sparklineGroups></ext></extLst>"
  }

  private static func argb(_ hex: String) -> String {
    let digits = hex.uppercased().filter(\.isHexDigit)
    return digits.count == 6 ? "FF" + digits : "FF376092"
  }

  /// `RRGGBB` from `<name rgb="AARRGGBB"/>`; nil for a theme color.
  private static func color(_ name: String, in body: String) -> String? {
    guard let tag = captures(#"<\#(name)\b([^>]*)/?>"#, in: body).first?.first,
      let rgb = attribute("rgb", in: tag)
    else { return nil }
    let digits = rgb.uppercased().filter(\.isHexDigit)
    return digits.count >= 6 ? String(digits.suffix(6)) : nil
  }

  private static func attribute(_ name: String, in attributes: String) -> String? {
    captures(#"\b\#(name)\s*=\s*"([^"]*)""#, in: attributes).first?.first
  }

  private static func captures(_ pattern: String, in text: String) -> [[String]] {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    let ns = text as NSString
    return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { match in
      (1..<match.numberOfRanges).map { index in
        let range = match.range(at: index)
        return range.location == NSNotFound ? "" : ns.substring(with: range)
      }
    }
  }

  private static func unescapedXML(_ text: String) -> String {
    text.replacingOccurrences(of: "&apos;", with: "'")
      .replacingOccurrences(of: "&quot;", with: "\"")
      .replacingOccurrences(of: "&lt;", with: "<")
      .replacingOccurrences(of: "&gt;", with: ">")
      .replacingOccurrences(of: "&amp;", with: "&")
  }
}
