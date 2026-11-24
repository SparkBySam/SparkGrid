import Foundation
import Model

/// Spark Grid's note of what it saved in its own parts (`xl/sparkGrid/`), kept as a custom
/// document property. Other apps drop parts they do not know when they save, but keep custom
/// properties, so a file reopened after another app saved it can say what was lost.
extension XLSXCodec {
  static let sparkGridNoteName = "SparkGridExtras"
  static let customPropertiesPath = "docProps/custom.xml"
  static let customPropertiesRelationship =
    #"<Relationship Id="rIdCustom" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/custom-properties" Target="docProps/custom.xml"/>"#
  static let customPropertiesContentType =
    #"<Override PartName="/docProps/custom.xml" ContentType="application/vnd.openxmlformats-officedocument.custom-properties+xml"/>"#

  /// A zip of these parts, as the export writes one; for tests that rebuild a file.
  static func zipArchive(files: [String: Data]) -> Data? {
    MinimalZip.archive(files: files)
  }

  /// The note's text, such as `pivots=2;locks=1`, or nil when Spark Grid saved none.
  static func sparkGridNote(for workbook: Workbook) -> String? {
    let parts = SparkGridExtra.allCases.compactMap { kind -> String? in
      let count = kind.count(in: workbook)
      return count > 0 ? "\(kind.rawValue)=\(count)" : nil
    }
    return parts.isEmpty ? nil : parts.joined(separator: ";")
  }

  /// `docProps/custom.xml` to write: the file's own custom properties, with Spark Grid's note in
  /// place of an earlier one. Nil when there is nothing to write.
  static func customPropertiesPart(for workbook: Workbook) -> Data? {
    var properties = customProperties(in: workbook.xlsxCustomPropertiesData)
      .filter { $0.name != sparkGridNoteName }
      .map(\.xml)
    if let note = sparkGridNote(for: workbook) {
      properties.append(
        #"<property fmtid="{D5CDD505-2E9C-101B-9397-08002B2CF9AE}" pid="0" name="\#(sparkGridNoteName)"><vt:lpwstr>\#(escapeXML(note))</vt:lpwstr></property>"#
      )
    }
    guard !properties.isEmpty else { return nil }
    // Property ids start at 2 and run in order.
    let numbered = properties.enumerated().map { index, xml in
      xml.replacingOccurrences(
        of: #"pid="[0-9]+""#, with: #"pid="\#(index + 2)""#, options: .regularExpression)
    }
    let xml =
      #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"# + "\n"
      + #"<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/custom-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">"#
      + numbered.joined() + "</Properties>"
    return Data(xml.utf8)
  }

  /// Each `<property>` in a custom properties part: its name and its element as written.
  static func customProperties(in data: Data?) -> [(name: String, xml: String)] {
    guard let data, let xml = String(data: data, encoding: .utf8),
      let pattern = try? NSRegularExpression(
        pattern: #"<property\b[^>]*>.*?</property>"#, options: [.dotMatchesLineSeparators])
    else { return [] }
    let range = NSRange(xml.startIndex..., in: xml)
    return pattern.matches(in: xml, range: range).compactMap { match in
      guard let r = Range(match.range, in: xml) else { return nil }
      let element = String(xml[r])
      let name = tagAttributes(in: element, localName: "property").first?["name"] ?? ""
      return (name, element)
    }
  }

  /// Spark Grid's note in a file, as counts of each extra.
  static func sparkGridNote(in data: Data?) -> [SparkGridExtra: Int] {
    guard let note = customProperties(in: data).first(where: { $0.name == sparkGridNoteName }),
      let open = note.xml.range(of: "<vt:lpwstr>"),
      let close = note.xml.range(of: "</vt:lpwstr>", range: open.upperBound..<note.xml.endIndex)
    else { return [:] }
    var counts: [SparkGridExtra: Int] = [:]
    for item in note.xml[open.upperBound..<close.lowerBound].split(separator: ";") {
      let pair = item.split(separator: "=")
      if pair.count == 2, let kind = SparkGridExtra(rawValue: String(pair[0])),
        let count = Int(pair[1])
      {
        counts[kind] = count
      }
    }
    return counts
  }

  /// On open: keep the file's custom properties, and note any extras the file says Spark Grid
  /// saved that are not in it now.
  static func importCustomProperties(into workbook: inout Workbook, package: (String) -> Data?) {
    let data = package(customPropertiesPath)
    workbook.xlsxCustomPropertiesData = data
    let saved = sparkGridNote(in: data)
    workbook.removedSparkGridExtras = SparkGridExtra.allCases.filter { kind in
      (saved[kind] ?? 0) > 0 && kind.count(in: workbook) == 0
    }
  }
}
