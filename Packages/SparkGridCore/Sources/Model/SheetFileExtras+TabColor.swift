import Foundation

/// The sheet tab's color, kept in the sheet's own `<sheetPr><tabColor …/></sheetPr>`.
extension SheetFileExtras {
  /// `RRGGBB`, from an `rgb` color or one of the default Office theme colors. A tint is ignored.
  public var tabColorHex: String? {
    get {
      guard let xml = sheetPropertiesXML, let tag = Self.tabColorTag(in: xml) else { return nil }
      let text = String(xml[tag])
      if let rgb = Self.attribute("rgb", in: text), rgb.count >= 6 {
        return String(rgb.suffix(6)).uppercased()
      }
      if let theme = Self.attribute("theme", in: text).flatMap(Int.init),
        Self.officeTheme.indices.contains(theme)
      {
        return Self.officeTheme[theme]
      }
      if let indexed = Self.attribute("indexed", in: text).flatMap(Int.init),
        let hex = Self.indexedColors[indexed]
      {
        return hex
      }
      return nil
    }
    set {
      let tag = newValue.map { #"<tabColor rgb="FF\#($0.uppercased())"/>"# }
      guard var xml = sheetPropertiesXML else {
        if let tag { sheetPropertiesXML = "<sheetPr>\(tag)</sheetPr>" }
        return
      }
      if let existing = Self.tabColorTag(in: xml) {
        xml.replaceSubrange(existing, with: tag ?? "")
      } else if let tag {
        xml = Self.inserting(tag, intoSheetPr: xml)
      }
      // A sheetPr left with nothing in it is dropped.
      let empty = xml.range(
        of: #"^<(\w+:)?sheetPr\s*(/>|></(\w+:)?sheetPr>)$"#, options: .regularExpression)
      sheetPropertiesXML = empty == nil ? xml : nil
    }
  }

  private static func tabColorTag(in xml: String) -> Range<String.Index>? {
    xml.range(
      of: #"<(\w+:)?tabColor\b[^>]*?(/>|>\s*</(\w+:)?tabColor>)"#, options: .regularExpression)
  }

  /// `tabColor` comes first among sheetPr's children.
  private static func inserting(_ tag: String, intoSheetPr xml: String) -> String {
    guard let open = xml.range(of: #"<(\w+:)?sheetPr\b[^>]*>"#, options: .regularExpression)
    else { return xml }
    let openTag = String(xml[open])
    if openTag.hasSuffix("/>") {
      let name = openTag.dropFirst().prefix { !$0.isWhitespace && $0 != "/" && $0 != ">" }
      let opened = String(openTag.dropLast(2)).trimmingCharacters(in: .whitespaces) + ">"
      return xml.replacingCharacters(in: open, with: "\(opened)\(tag)</\(name)>")
    }
    var result = xml
    result.insert(contentsOf: tag, at: open.upperBound)
    return result
  }

  private static func attribute(_ name: String, in tag: String) -> String? {
    guard let range = tag.range(of: #"\b\#(name)="[^"]*""#, options: .regularExpression) else {
      return nil
    }
    return tag[range].split(separator: "\"").dropFirst().first.map(String.init)
  }

  /// The default Office theme: light 1, dark 1, light 2, dark 2, accents 1 to 6, links.
  private static let officeTheme = [
    "FFFFFF", "000000", "E7E6E6", "44546A", "4472C4", "ED7D31", "A5A5A5", "FFC000", "5B9BD5",
    "70AD47", "0563C1", "954F72",
  ]

  private static let indexedColors: [Int: String] = [
    8: "000000", 9: "FFFFFF", 10: "FF0000", 11: "00FF00", 12: "0000FF", 13: "FFFF00",
    14: "FF00FF", 15: "00FFFF",
  ]
}
