import CoreGraphics
import CoreXLSX
import Formula
import Foundation
import GridCore
import Model
import NumberFormat
import ZIPFoundation

private typealias Workbook = Model.Workbook
private typealias Cell = Model.Cell

public nonisolated enum XLSXCodec {
  public enum CodecError: LocalizedError {
    case unreadable
    case emptyWorkbook
    case writeFailed
    /// Unpacked, the file is larger than Spark Grid opens (see `ZipPackage.Limits`).
    case tooLarge

    public var errorDescription: String? {
      switch self {
      case .unreadable: return "Couldn't read the Excel workbook."
      case .emptyWorkbook: return "The Excel workbook has no sheets."
      case .writeFailed: return "Couldn't write the Excel workbook."
      case .tooLarge:
        return
          "This workbook is too large to open. Spark Grid opens workbooks up to 2 GB once "
          + "unpacked, with no single part over 200 MB."
      }
    }
  }

  // MARK: - Import

  public static func importWorkbook(from data: Data) throws -> Model.Workbook {
    try importWorkbookStreaming(from: data)
  }

  /// CoreXLSX worksheet DOM plus the old sheet-wide scans. The streaming importer is checked against this.
  public static func importWorkbookLegacy(from data: Data) throws -> Model.Workbook {
    let file = try XLSXFile(data: data)
    return try importWorkbookLegacy(from: file, archiveData: data)
  }

  public static func importWorkbook(from url: URL) throws -> Model.Workbook {
    let data = try Data(contentsOf: url)
    return try importWorkbook(from: data)
  }

  private static func importWorkbookLegacy(from file: XLSXFile, archiveData: Data) throws
    -> Workbook
  {
    let sharedStrings = try? file.parseSharedStrings()
    let styles = parseStylesLeniently(file: file, archiveData: archiveData)
    let themeScheme = importThemeScheme(archiveData: archiveData)
    let themeStyleColors = importThemeStyleColors(archiveData: archiveData, scheme: themeScheme)
    let dxfs = importDifferentialFormats(archiveData: archiveData, themeScheme: themeScheme)
    let underlinedFonts = underlinedFontIndices(archiveData: archiveData)
    let textRotationsByStyleIndex = importTextRotationsByStyleIndex(archiveData: archiveData)
    let clipTextStyleIndexes = importClipTextStyleIndexes(archiveData: archiveData)
    let unlockedStyleIndexes = importUnlockedStyleIndexes(archiveData: archiveData)
    var sheets: [Sheet] = []
    let paths = try worksheetPathsForImport(file: file, archiveData: archiveData)

    for (name, path) in paths {
      let worksheet = try file.parseWorksheet(at: path)
      var sheet = Sheet(name: name ?? "Sheet\(sheets.count + 1)")
      importCells(
        from: worksheet,
        into: &sheet,
        sharedStrings: sharedStrings,
        styles: styles,
        underlinedFontIds: underlinedFonts,
        themeStyleColors: themeStyleColors,
        textRotationsByStyleIndex: textRotationsByStyleIndex,
        clipTextStyleIndexes: clipTextStyleIndexes,
        unlockedStyleIndexes: unlockedStyleIndexes
      )
      expandSharedFormulas(into: &sheet, archiveData: archiveData, worksheetPath: path)
      importFormulaCachedValues(
        into: &sheet,
        archiveData: archiveData,
        worksheetPath: path,
        sharedStrings: sharedStrings
      )
      importColumnWidths(from: worksheet, into: &sheet)
      importRowHeights(from: worksheet, into: &sheet)
      importFreezePanes(from: worksheet, into: &sheet)
      importMergeCells(from: worksheet, into: &sheet)
      importAutoFilter(into: &sheet, archiveData: archiveData, worksheetPath: path)
      importConditionalFormatting(
        into: &sheet,
        archiveData: archiveData,
        worksheetPath: path,
        dxfs: dxfs,
        themeScheme: themeScheme
      )
      importSparkCharts(into: &sheet, archiveData: archiveData, sheetIndex: sheets.count)
      importSparkPivots(into: &sheet, archiveData: archiveData, sheetIndex: sheets.count)
      importSheetImages(
        into: &sheet,
        archiveData: archiveData,
        worksheetPath: path
      )
      sheets.append(sheet)
    }

    guard !sheets.isEmpty else { throw CodecError.emptyWorkbook }
    importSheetBuiltInNames(archiveData: archiveData, into: &sheets)
    return Workbook(
      sheets: sheets,
      activeSheetIndex: 0,
      namedRanges: importDefinedNames(archiveData: archiveData, sheets: sheets),
      xlsxThemeData: zipEntryData(archiveData: archiveData, entryPath: "xl/theme/theme1.xml")
    )
  }

  private static func importWorkbookStreaming(from data: Data) throws -> Workbook {
    let importer = try Importer(data: data)
    let partial = try importer.importActiveSheet()
    return try importer.importRemaining(after: partial)
  }

  /// Reads the active sheet first so the window can paint stored values, then the rest.
  public final class Importer {
    private let data: Data
    private let package: ZipPackage
    private var paths: [(name: String?, path: String)] = []
    private var sharedTexts: [String?] = []
    private var formats: [CellFormat?] = []
    private var dxfs: [ConditionalFormatStyle] = []
    private var themeScheme = ThemeColorScheme()
    private var prepared = false

    public init(data: Data) throws {
      self.data = data
      package = try ZipPackage(archiveData: data)
    }

    /// The first sheet, with shared formulas expanded and cached results kept.
    public func importActiveSheet() throws -> Model.Workbook {
      try ZipPackage.use(package) {
        try prepareIfNeeded()
        return assemble(sheets: [try makeSheet(at: 0)])
      }
    }

    /// Sheets after the active one. The active sheet is the copy already shown.
    public func importRemaining(after partial: Model.Workbook) throws -> Model.Workbook {
      try ZipPackage.use(package) {
        try prepareIfNeeded()
        if paths.count <= 1 {
          return assemble(sheets: partial.sheets)
        }
        var built = [Sheet?](repeating: nil, count: paths.count)
        if let first = partial.sheets.first {
          built[0] = first
        } else {
          built[0] = try makeSheet(at: 0)
        }
        let lock = NSLock()
        var failure: Error?
        let indexes = Array(paths.indices.dropFirst())
        DispatchQueue.concurrentPerform(iterations: indexes.count) { offset in
          guard indexes.indices.contains(offset) else { return }
          let index = indexes[offset]
          do {
            let sheet = try self.makeSheet(at: index)
            lock.lock()
            built[index] = sheet
            lock.unlock()
          } catch {
            lock.lock()
            if failure == nil { failure = error }
            lock.unlock()
          }
        }
        if let failure { throw failure }
        let sheets = built.compactMap { $0 }
        guard sheets.count == paths.count else { throw CodecError.unreadable }
        return assemble(sheets: sheets)
      }
    }

    private func prepareIfNeeded() throws {
      if prepared { return }
      let file = try XLSXFile(data: data)
      let sharedStrings = try? file.parseSharedStrings()
      let styles = XLSXCodec.parseStylesLeniently(file: file, archiveData: data)
      let scheme = importThemeScheme(archiveData: data)
      let themeStyleColors = importThemeStyleColors(archiveData: data, scheme: scheme)
      let underlinedFonts = underlinedFontIndices(archiveData: data)
      let textRotationsByStyleIndex = importTextRotationsByStyleIndex(archiveData: data)
      let clipTextStyleIndexes = importClipTextStyleIndexes(archiveData: data)
      let unlockedStyleIndexes = importUnlockedStyleIndexes(archiveData: data)
      themeScheme = scheme
      dxfs = importDifferentialFormats(archiveData: data, themeScheme: scheme)
      formats = cellFormatsByStyleIndex(
        styles: styles,
        underlinedFontIds: underlinedFonts,
        themeStyleColors: themeStyleColors,
        textRotationsByStyleIndex: textRotationsByStyleIndex,
        clipTextStyleIndexes: clipTextStyleIndexes,
        unlockedStyleIndexes: unlockedStyleIndexes
      )
      sharedTexts = sharedStrings?.items.map(\.text) ?? []
      paths = try worksheetPathsForImport(file: file, archiveData: data)
      guard !paths.isEmpty else { throw CodecError.emptyWorkbook }
      prepared = true
    }

    private func makeSheet(at index: Int) throws -> Sheet {
      guard paths.indices.contains(index) else { throw CodecError.unreadable }
      let (name, path) = paths[index]
      guard let sheetData = package.data(for: path) else { throw CodecError.unreadable }
      var sheet = Sheet(name: name ?? "Sheet\(index + 1)")
      let (conditionalFormatting, kept, arrays) = StreamingWorksheet.fill(
        &sheet,
        data: sheetData,
        sharedTexts: sharedTexts,
        formats: formats
      )
      if !conditionalFormatting.isEmpty {
        importConditionalFormatting(
          into: &sheet,
          worksheetXML: conditionalFormatting,
          dxfs: dxfs,
          themeScheme: themeScheme
        )
      }
      importSparkCharts(into: &sheet, archiveData: data, sheetIndex: index)
      importSheetImages(into: &sheet, archiveData: data, worksheetPath: path)
      let package = self.package
      importFileExtras(
        into: &sheet, kept: kept, package: { package.data(for: $0) }, worksheetPath: path)
      XLSXCodec.adoptSpills(arrays, into: &sheet)
      importSparkPivots(into: &sheet, archiveData: data, sheetIndex: index)
      return sheet
    }

    private func assemble(sheets: [Sheet]) -> Model.Workbook {
      var sheets = sheets
      importSheetBuiltInNames(archiveData: data, into: &sheets)
      var workbook = Workbook(
        sheets: sheets,
        activeSheetIndex: 0,
        namedRanges: importDefinedNames(archiveData: data, sheets: sheets),
        xlsxThemeData: zipEntryData(archiveData: data, entryPath: "xl/theme/theme1.xml")
      )
      let package = self.package
      importWorkbookExtras(into: &workbook, package: { package.data(for: $0) })
      return workbook
    }
  }

  /// Tab order is the `<sheet>` sequence in workbook.xml. Relationship order is not tab order.
  private static func worksheetPathsForImport(
    file: XLSXFile,
    archiveData: Data
  ) throws -> [(name: String?, path: String)] {
    let ordered = worksheetPathsInWorkbookOrder(archiveData: archiveData)
    if !ordered.isEmpty { return ordered }
    var fallback: [(name: String?, path: String)] = []
    for workbook in try file.parseWorkbooks() {
      for (name, path) in try file.parseWorksheetPathsAndNames(workbook: workbook) {
        fallback.append((name, path))
      }
    }
    return fallback
  }

  /// Walk `<sheet>` elements in document order and resolve each `r:id` to its worksheet part.
  private static func worksheetPathsInWorkbookOrder(archiveData: Data) -> [(
    name: String?, path: String
  )] {
    guard let workbookXML = zipEntryString(archiveData: archiveData, entryPath: "xl/workbook.xml"),
      let relsXML = zipEntryString(
        archiveData: archiveData, entryPath: "xl/_rels/workbook.xml.rels")
    else { return [] }
    let targets = worksheetRelationshipTargets(in: relsXML)
    guard !targets.isEmpty else { return [] }
    guard let sheetsXML = xmlElementBody(in: workbookXML, localName: "sheets") else { return [] }

    var ordered: [(name: String?, path: String)] = []
    for attributes in xmlElementAttributes(in: sheetsXML, localName: "sheet") {
      guard let relationship = xmlRelationshipId(in: attributes),
        let target = targets[relationship]
      else { return [] }
      let rawName = xmlAttribute(attributes, named: "name")?
        .trimmingCharacters(in: .whitespacesAndNewlines)
      let name = (rawName?.isEmpty == false) ? rawName : nil
      ordered.append((name, worksheetArchivePath(target)))
    }
    return ordered
  }

  private static func worksheetRelationshipTargets(in relsXML: String) -> [String: String] {
    var targets: [String: String] = [:]
    for attributes in xmlElementAttributes(in: relsXML, localName: "Relationship") {
      guard let id = xmlAttribute(attributes, named: "Id") ?? xmlAttribute(attributes, named: "id"),
        let type = xmlAttribute(attributes, named: "Type")
          ?? xmlAttribute(attributes, named: "type"),
        let target = xmlAttribute(attributes, named: "Target")
          ?? xmlAttribute(attributes, named: "target"),
        relationshipTypeIsWorksheet(type)
      else { continue }
      targets[id] = target
    }
    return targets
  }

  private static func relationshipTypeIsWorksheet(_ type: String) -> Bool {
    let trimmed = type.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let slash = trimmed.range(of: "/", options: .backwards) else { return false }
    return trimmed[slash.upperBound...].caseInsensitiveCompare("worksheet") == .orderedSame
  }

  static func xmlRelationshipId(in attributes: String) -> String? {
    if let id = xmlAttribute(attributes, named: "r:id"), !id.isEmpty { return id }
    let pattern = #":id\s*=\s*(?:"([^"]*)"|'([^']*)')"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
      let match = regex.firstMatch(
        in: attributes,
        range: NSRange(location: 0, length: (attributes as NSString).length)
      )
    else { return nil }
    let ns = attributes as NSString
    if match.range(at: 1).location != NSNotFound, match.range(at: 1).length > 0 {
      return decodeXMLEntities(ns.substring(with: match.range(at: 1)))
    }
    if match.numberOfRanges > 2, match.range(at: 2).location != NSNotFound {
      return decodeXMLEntities(ns.substring(with: match.range(at: 2)))
    }
    return nil
  }

  private static func worksheetArchivePath(_ target: String) -> String {
    let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.hasPrefix("/") {
      return String(trimmed.dropFirst())
    }
    return resolveZipPath(basePath: "xl/workbook.xml", relativeTarget: trimmed)
  }

  /// Inner XML of the first element with this local name. Self-closing elements yield an empty body.
  static func xmlElementBody(in xml: String, localName: String) -> String? {
    var index = xml.startIndex
    while index < xml.endIndex {
      guard let open = xml.range(of: "<", range: index..<xml.endIndex) else { return nil }
      let after = open.upperBound
      if after < xml.endIndex, xml[after] == "/" || xml[after] == "!" || xml[after] == "?" {
        index = after
        continue
      }
      guard
        let nameEnd = xml[after...].firstIndex(where: {
          $0 == " " || $0 == ">" || $0 == "/" || $0 == "\t" || $0 == "\n" || $0 == "\r"
        })
      else { return nil }
      let rawName = xml[after..<nameEnd]
      let local = rawName.split(separator: ":").last.map(String.init) ?? String(rawName)
      guard let tagEnd = xml.range(of: ">", range: nameEnd..<xml.endIndex) else { return nil }
      let tag = xml[open.lowerBound..<tagEnd.upperBound]
      if local != localName {
        index = tagEnd.upperBound
        continue
      }
      if tag.hasSuffix("/>") { return "" }
      let closeMarks = ["</\(rawName)>", "</\(local)>"]
      let bodyStart = tagEnd.upperBound
      for mark in closeMarks {
        if let close = xml.range(of: mark, range: bodyStart..<xml.endIndex) {
          return String(xml[bodyStart..<close.lowerBound])
        }
      }
      return nil
    }
    return nil
  }

  static func xmlElementAttributes(in xml: String, localName: String) -> [String] {
    var found: [String] = []
    var index = xml.startIndex
    while index < xml.endIndex {
      guard let open = xml.range(of: "<", range: index..<xml.endIndex) else { break }
      let after = open.upperBound
      if after < xml.endIndex, xml[after] == "/" || xml[after] == "!" || xml[after] == "?" {
        index = after
        continue
      }
      guard
        let nameEnd = xml[after...].firstIndex(where: {
          $0 == " " || $0 == ">" || $0 == "/" || $0 == "\t" || $0 == "\n" || $0 == "\r"
        })
      else { break }
      let rawName = xml[after..<nameEnd]
      let local = rawName.split(separator: ":").last.map(String.init) ?? String(rawName)
      guard let tagEnd = xml.range(of: ">", range: nameEnd..<xml.endIndex) else { break }
      if local == localName {
        found.append(String(xml[nameEnd..<tagEnd.lowerBound]))
      }
      index = tagEnd.upperBound
    }
    return found
  }

  /// CoreXLSX does not expose `definedNames`. Read them from workbook XML the same way shared formulas are read from sheet XML.
  private static func importDefinedNames(archiveData: Data, sheets: [Sheet]) -> [String: NamedRange]
  {
    guard let xml = zipEntryString(archiveData: archiveData, entryPath: "xl/workbook.xml"),
      let blockStart = xml.range(of: "<definedNames"),
      let blockEnd = xml.range(of: "</definedNames>", range: blockStart.upperBound..<xml.endIndex)
    else { return [:] }
    let section = String(xml[blockStart.lowerBound..<blockEnd.upperBound])
    guard
      let regex = try? NSRegularExpression(
        pattern: #"<(?:[\w]+:)?definedName\b([^>]*)>([\s\S]*?)</(?:[\w]+:)?definedName>"#
      )
    else { return [:] }

    struct RawName {
      var name: String
      var formula: String
      var localSheet: String?
    }

    let nsSection = section as NSString
    var globals: [RawName] = []
    var locals: [RawName] = []
    for match in regex.matches(in: section, range: NSRange(location: 0, length: nsSection.length)) {
      guard match.numberOfRanges > 2 else { continue }
      let attrs = nsSection.substring(with: match.range(at: 1))
      let body = decodeXMLEntities(nsSection.substring(with: match.range(at: 2)))
      guard
        let rawName = xmlAttribute(attrs, named: "name")?.trimmingCharacters(
          in: .whitespacesAndNewlines),
        !rawName.isEmpty
      else { continue }
      if isSheetBuiltInName(rawName, localSheetId: xmlAttribute(attrs, named: "localSheetId")) {
        continue
      }
      let localSheet: String?
      if let local = xmlAttribute(attrs, named: "localSheetId"), let index = Int(local),
        sheets.indices.contains(index)
      {
        localSheet = sheets[index].name
      } else {
        localSheet = nil
      }
      let raw = RawName(name: rawName, formula: body, localSheet: localSheet)
      if localSheet == nil {
        globals.append(raw)
      } else {
        locals.append(raw)
      }
    }

    var named: [String: NamedRange] = [:]
    for raw in globals + locals {
      let key = raw.name.uppercased()
      if raw.localSheet != nil, named[key] != nil { continue }
      let formula = raw.formula.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !formula.isEmpty else { continue }
      named[key] = DefinedNameFormula.make(
        name: raw.name,
        formula: formula,
        sheets: sheets,
        localSheet: raw.localSheet
      )
    }
    return named
  }

  static func xmlAttribute(_ attributes: String, named name: String) -> String? {
    let patterns = [
      #"\#(name)="([^"]*)""#,
      #"\#(name)='([^']*)'"#,
    ]
    for pattern in patterns {
      guard let regex = try? NSRegularExpression(pattern: pattern),
        let match = regex.firstMatch(
          in: attributes,
          range: NSRange(location: 0, length: (attributes as NSString).length)
        ),
        match.numberOfRanges > 1
      else { continue }
      return decodeXMLEntities((attributes as NSString).substring(with: match.range(at: 1)))
    }
    return nil
  }

  /// CoreXLSX drops shared-formula followers (`<f t="shared" si="…"/>`). Expand them from sheet XML.
  private static func expandSharedFormulas(
    into sheet: inout Sheet,
    archiveData: Data,
    worksheetPath: String
  ) {
    guard let xml = zipEntryString(archiveData: archiveData, entryPath: worksheetPath) else {
      return
    }

    struct SharedMaster {
      var address: CellAddress
      var formula: String
    }

    var masters: [Int: SharedMaster] = [:]
    var followers: [(CellAddress, Int)] = []

    forEachCellElement(in: xml) { attrs, body in
      guard
        let ref = xmlAttribute(attrs, named: "r")?.trimmingCharacters(in: .whitespacesAndNewlines),
        !ref.isEmpty,
        let address = address(fromA1: ref)
      else { return }

      guard let fTag = sharedFormulaTag(in: body) else { return }
      guard fTag.contains(#"t="shared""#) || fTag.contains("t='shared'") else { return }

      var si: Int?
      if let siMatch = fTag.range(of: #"si="\d+""#, options: .regularExpression) {
        si = Int(String(fTag[siMatch]).filter(\.isNumber))
      } else if let siMatch = fTag.range(of: #"si='\d+'"#, options: .regularExpression) {
        si = Int(String(fTag[siMatch]).filter(\.isNumber))
      }
      guard let sharedIndex = si else { return }

      if let open = fTag.range(of: ">"), fTag.contains("</f>") {
        let after = fTag[open.upperBound...]
        if let close = after.range(of: "</f>") {
          let formula = decodeXMLEntities(
            String(after[..<close.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
          )
          if !formula.isEmpty {
            masters[sharedIndex] = SharedMaster(address: address, formula: formula)
            let raw = formula.hasPrefix("=") ? formula : "=\(formula)"
            var cell = sheet.cell(at: address)
            cell.raw = raw
            sheet.setCell(cell, at: address)
            return
          }
        }
      }
      followers.append((address, sharedIndex))
    }

    for (address, sharedIndex) in followers {
      guard let master = masters[sharedIndex] else { continue }
      let rowDelta = address.row - master.address.row
      let colDelta = address.col - master.address.col
      let base = master.formula.hasPrefix("=") ? master.formula : "=\(master.formula)"
      let adjusted = FormulaRewriter.adjust(base, rowDelta: rowDelta, colDelta: colDelta)
      var cell = sheet.cell(at: address)
      cell.raw = adjusted
      sheet.setCell(cell, at: address)
    }
  }

  /// Linear scan for `<c …>` / `</c>` pairs. Regex over the whole worksheet XML backtracks catastrophically on large sheets.
  private static func forEachCellElement(in xml: String, body: (String, String) -> Void) {
    var searchStart = xml.startIndex
    while searchStart < xml.endIndex {
      guard let open = xml.range(of: "<c", range: searchStart..<xml.endIndex) else { break }
      let afterTagName = open.upperBound
      guard afterTagName < xml.endIndex else { break }
      let boundary = xml[afterTagName]
      guard boundary == " " || boundary == ">" || boundary == "/" else {
        searchStart = open.upperBound
        continue
      }
      guard let openEnd = xml.range(of: ">", range: afterTagName..<xml.endIndex) else { break }
      let attrs = String(xml[open.upperBound..<openEnd.lowerBound])
      let openTag = String(xml[open.lowerBound..<openEnd.upperBound])
      if openTag.hasSuffix("/>") {
        body(attrs, "")
        searchStart = openEnd.upperBound
        continue
      }
      guard let close = xml.range(of: "</c>", range: openEnd.upperBound..<xml.endIndex) else {
        break
      }
      let cellBody = String(xml[openEnd.upperBound..<close.lowerBound])
      body(attrs, cellBody)
      searchStart = close.upperBound
    }
  }

  /// CoreXLSX often omits cached `<v>` on formula cells; read it from sheet XML (same scan as shared formulas).
  private static func importFormulaCachedValues(
    into sheet: inout Sheet,
    archiveData: Data,
    worksheetPath: String,
    sharedStrings: SharedStrings?
  ) {
    guard let xml = zipEntryString(archiveData: archiveData, entryPath: worksheetPath) else {
      return
    }
    forEachCellElement(in: xml) { attrs, body in
      guard body.contains("<f") else { return }
      guard
        let ref = xmlAttribute(attrs, named: "r")?.trimmingCharacters(in: .whitespacesAndNewlines),
        !ref.isEmpty,
        let address = address(fromA1: ref)
      else { return }
      guard
        let cached = formulaCachedValueFromCellXML(
          attrs: attrs,
          body: body,
          sharedStrings: sharedStrings
        )
      else { return }
      var cell = sheet.cell(at: address)
      guard FormulaSyntax.isFormula(cell.raw) else { return }
      cell.importedFormulaResult = cached.text
      cell.importedFormulaValueType = cached.type
      sheet.setCell(cell, at: address)
    }
  }

  private struct FormulaCache {
    public var text: String
    public var type: ImportedFormulaValueType
  }

  private static func formulaCachedValueFromCellXML(
    attrs: String,
    body: String,
    sharedStrings: SharedStrings?
  ) -> FormulaCache? {
    let cellTypeEarly = xmlAttribute(attrs, named: "t")?.trimmingCharacters(
      in: .whitespacesAndNewlines)
    if body.contains("<v/>") || body.contains("<v />") {
      return emptyStringFormulaCache(cellType: cellTypeEarly)
    }
    guard let vOpen = body.range(of: "<v>"),
      let vClose = body.range(of: "</v>", range: vOpen.upperBound..<body.endIndex)
    else { return nil }
    let raw = decodeXMLEntities(String(body[vOpen.upperBound..<vClose.lowerBound]))
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let cellType = xmlAttribute(attrs, named: "t")?.trimmingCharacters(in: .whitespacesAndNewlines)
    if raw.isEmpty {
      return emptyStringFormulaCache(cellType: cellType)
    }
    if cellType == "s" || cellType == "sharedString" {
      if let index = Int(raw), let text = sharedString(at: index, in: sharedStrings) {
        return FormulaCache(text: text, type: .string)
      }
      return nil
    }
    return FormulaCache(text: raw, type: formulaValueType(forOOXML: cellType))
  }

  /// Excel stores a blank formula result as `t="str"` and an empty `<v/>`. A missing `<v>` is not a cache.
  private static func emptyStringFormulaCache(cellType: String?) -> FormulaCache? {
    guard cellType == "str" || cellType == "inlineStr" else { return nil }
    return FormulaCache(text: "", type: .string)
  }

  private static func formulaValueType(forOOXML cellType: String?) -> ImportedFormulaValueType {
    switch cellType {
    case "b": return .boolean
    case "e": return .error
    case "str", "inlineStr", "s", "d": return .string
    default: return .number
    }
  }

  private static func sharedString(at index: Int, in table: SharedStrings?) -> String? {
    guard let table, index >= 0, index < table.items.count else { return nil }
    return table.items[index].text
  }

  private static func sharedFormulaTag(in cellBody: String) -> String? {
    var search = cellBody.startIndex
    while search < cellBody.endIndex {
      guard let fStart = cellBody.range(of: "<f", range: search..<cellBody.endIndex) else { break }
      let tail = cellBody[fStart.lowerBound...]
      let head = String(tail.prefix(240))
      guard head.contains(#"t="shared""#) || head.contains("t='shared'") else {
        search = fStart.upperBound
        continue
      }
      if let selfClose = tail.range(of: "/>") {
        return String(tail[..<selfClose.upperBound])
      }
      if let close = tail.range(of: "</f>") {
        return String(tail[..<close.upperBound])
      }
      return nil
    }
    return nil
  }

  /// CoreXLSX reads `<dxf>` (conditional-format styles) as cell formats and requires a
  /// `numFmtId` that Excel and Spark Grid leave out, and rejects a `<patternFill>` with no
  /// `patternType`. Either one failed the whole parse, and every cell opened unformatted.
  /// On failure this parses a copy of `styles.xml` without `<dxfs>` (read separately by
  /// `importDifferentialFormats`) and with `patternType="none"` filled in.
  static func parseStylesLeniently(file: XLSXFile, archiveData: Data) -> Styles? {
    if let styles = try? file.parseStyles() {
      return styles
    }
    guard let xml = zipEntryString(archiveData: archiveData, entryPath: "xl/styles.xml") else {
      return nil
    }
    var cleaned = xml.replacingOccurrences(
      of: #"<dxfs\b[^>]*/>|<dxfs\b[^>]*>[\s\S]*?</dxfs>"#, with: "", options: .regularExpression)
    cleaned = cleaned.replacingOccurrences(
      of: #"<patternFill(?![^>]*\bpatternType=)(\s[^>]*)?(/?)>"#,
      with: #"<patternFill patternType="none"$1$2>"#,
      options: .regularExpression)
    guard cleaned != xml,
      let patched = replacingZipEntry(
        archiveData: archiveData, entryPath: "xl/styles.xml", with: Data(cleaned.utf8)),
      let patchedFile = try? XLSXFile(data: patched)
    else { return nil }
    return try? patchedFile.parseStyles()
  }

  /// A copy of the archive with one entry's contents replaced.
  public static func replacingZipEntry(archiveData: Data, entryPath: String, with contents: Data)
    -> Data?
  {
    guard let archive = try? Archive(data: archiveData, accessMode: .update, pathEncoding: nil),
      let entry = archive[entryPath]
    else { return nil }
    do {
      try archive.remove(entry)
      try archive.addEntry(
        with: entryPath, type: .file, uncompressedSize: Int64(contents.count),
        compressionMethod: .deflate
      ) { position, size in
        contents.subdata(in: Int(position)..<Int(position) + size)
      }
    } catch {
      return nil
    }
    return archive.data
  }

  public static func zipEntryString(archiveData: Data, entryPath: String) -> String? {
    guard let data = zipEntryData(archiveData: archiveData, entryPath: entryPath) else {
      return nil
    }
    return String(data: data, encoding: .utf8)
  }

  /// Swap stored parts, then rebuild with the same stored-zip writer import already reads.
  public static func replacingZipEntries(_ archiveData: Data, entries: [String: Data]) -> Data? {
    guard let archive = try? Archive(data: archiveData, accessMode: .read, pathEncoding: nil) else {
      return nil
    }
    var files: [String: Data] = [:]
    for entry in archive {
      let path = entry.path
      if path.hasSuffix("/") { continue }
      var total = 0
      guard let data = try? ZipPackage.extract(entry, from: archive, total: &total) else {
        return nil
      }
      files[path] = data
    }
    for (path, data) in entries {
      files[path] = data
    }
    return MinimalZip.archive(files: files)
  }

  /// Every part's path in a package, for checks that walk the whole file.
  public static func zipEntryNames(archiveData: Data) -> [String]? {
    guard let archive = try? Archive(data: archiveData, accessMode: .read, pathEncoding: nil) else {
      return nil
    }
    return archive.map(\.path)
  }

  public static func zipEntryData(archiveData: Data, entryPath: String) -> Data? {
    // An import in progress holds this archive's parts in memory. Only this archive's: another
    // file loading at the same time must never answer for it.
    let cached = ZipPackage.cachedEntry(in: archiveData, at: entryPath)
    if cached.0 { return cached.1 }
    let normalized = entryPath.hasPrefix("/") ? String(entryPath.dropFirst()) : entryPath
    guard let archive = try? Archive(data: archiveData, accessMode: .read, pathEncoding: nil) else {
      return nil
    }
    let candidates = [normalized, normalized.hasPrefix("xl/") ? normalized : "xl/\(normalized)"]
    for path in candidates {
      guard let entry = archive[path] else { continue }
      var total = 0
      guard let data = try? ZipPackage.extract(entry, from: archive, total: &total),
        !data.isEmpty
      else { continue }
      return data
    }
    return nil
  }

  public static func decodeXMLEntities(_ string: String) -> String {
    string
      .replacingOccurrences(of: "&amp;", with: "&")
      .replacingOccurrences(of: "&lt;", with: "<")
      .replacingOccurrences(of: "&gt;", with: ">")
      .replacingOccurrences(of: "&quot;", with: "\"")
      .replacingOccurrences(of: "&apos;", with: "'")
  }

  private static func address(fromA1 ref: String) -> CellAddress? {
    guard let parsed = A1Reference.parseAddress(ref) else { return nil }
    return CellAddress(row: parsed.row, col: parsed.col)
  }

  private static func importCells(
    from worksheet: Worksheet,
    into sheet: inout Sheet,
    sharedStrings: SharedStrings?,
    styles: Styles?,
    underlinedFontIds: Set<Int>,
    themeStyleColors: ThemeResolvedStyleColors,
    textRotationsByStyleIndex: [Int: Int],
    clipTextStyleIndexes: Set<Int>,
    unlockedStyleIndexes: Set<Int> = []
  ) {
    for row in worksheet.data?.rows ?? [] {
      for cell in row.cells {
        guard let address = address(from: cell.reference) else { continue }
        let raw = cellRawValue(cell, sharedStrings: sharedStrings)
        guard !raw.isEmpty || cell.styleIndex != nil else { continue }
        var model = Cell(raw: raw)
        if let cached = importedFormulaCache(from: cell, sharedStrings: sharedStrings) {
          model.importedFormulaResult = cached.text
          model.importedFormulaValueType = cached.type
        }
        if let styles,
          let format = cellFormat(
            styleIndex: cell.styleIndex,
            styles: styles,
            underlinedFontIds: underlinedFontIds,
            themeStyleColors: themeStyleColors,
            textRotationsByStyleIndex: textRotationsByStyleIndex,
            clipTextStyleIndexes: clipTextStyleIndexes,
            unlockedStyleIndexes: unlockedStyleIndexes
          )
        {
          model.format = format
        }
        sheet.setCell(model, at: address)
      }
    }
  }

  /// CoreXLSX omits `textRotation` on alignment — parse it from styles.xml cellXfs.
  public static func importTextRotationsByStyleIndex(archiveData: Data) -> [Int: Int] {
    guard let xml = zipEntryString(archiveData: archiveData, entryPath: "xl/styles.xml") else {
      return [:]
    }
    guard let start = xml.range(of: "<cellXfs"),
      let end = xml.range(of: "</cellXfs>", range: start.upperBound..<xml.endIndex)
    else { return [:] }

    let section = String(xml[start.lowerBound..<end.upperBound])
    guard
      let xfRegex = try? NSRegularExpression(
        pattern: #"<xf\b[^>]*>(.*?)</xf>|<xf\b[^>]*/>"#,
        options: [.dotMatchesLineSeparators]
      ),
      let rotationRegex = try? NSRegularExpression(pattern: #"textRotation="(-?\d+)""#)
    else { return [:] }

    let nsSection = section as NSString
    var rotations: [Int: Int] = [:]
    for (index, match) in xfRegex.matches(
      in: section,
      options: [],
      range: NSRange(location: 0, length: nsSection.length)
    ).enumerated() {
      let chunk = nsSection.substring(with: match.range)
      let nsChunk = chunk as NSString
      guard
        let rotMatch = rotationRegex.firstMatch(
          in: chunk,
          options: [],
          range: NSRange(location: 0, length: nsChunk.length)
        ), rotMatch.numberOfRanges > 1,
        let rotation = Int(nsChunk.substring(with: rotMatch.range(at: 1)))
      else { continue }
      rotations[index] = rotation
    }
    return rotations
  }

  /// Cells whose style says `<protection locked="0"/>`: the ones a protected sheet lets people edit.
  public static func importUnlockedStyleIndexes(archiveData: Data) -> Set<Int> {
    guard let xml = zipEntryString(archiveData: archiveData, entryPath: "xl/styles.xml"),
      xml.contains("locked=\"0\""),
      let start = xml.range(of: "<cellXfs"),
      let end = xml.range(of: "</cellXfs>", range: start.upperBound..<xml.endIndex),
      let xfRegex = try? NSRegularExpression(
        pattern: #"<xf\b[^>]*>(.*?)</xf>|<xf\b[^>]*/>"#, options: [.dotMatchesLineSeparators])
    else { return [] }
    let section = String(xml[start.lowerBound..<end.upperBound]) as NSString
    var indexes = Set<Int>()
    for (index, match) in xfRegex.matches(
      in: section as String, range: NSRange(location: 0, length: section.length)
    ).enumerated() where section.substring(with: match.range).contains("locked=\"0\"") {
      indexes.insert(index)
    }
    return indexes
  }

  /// Clip is not an OOXML alignment flag. Spark Grid stores it beside wrapText so a round trip keeps it.
  public static func importClipTextStyleIndexes(archiveData: Data) -> Set<Int> {
    guard let xml = zipEntryString(archiveData: archiveData, entryPath: "xl/styles.xml") else {
      return []
    }
    guard let start = xml.range(of: "<cellXfs"),
      let end = xml.range(of: "</cellXfs>", range: start.upperBound..<xml.endIndex)
    else { return [] }

    let section = String(xml[start.lowerBound..<end.upperBound])
    guard
      let xfRegex = try? NSRegularExpression(
        pattern: #"<xf\b[^>]*>(.*?)</xf>|<xf\b[^>]*/>"#,
        options: [.dotMatchesLineSeparators]
      ),
      // 1.4 and later write sg:textDisplay in an ignorable namespace; earlier builds wrote
      // sparkTextDisplay on the alignment element itself.
      let clipRegex = try? NSRegularExpression(
        pattern: #"(?:\bsparkTextDisplay|\b[A-Za-z_][\w.-]*:textDisplay)="clip""#)
    else { return [] }

    let nsSection = section as NSString
    var indexes = Set<Int>()
    for (index, match) in xfRegex.matches(
      in: section,
      options: [],
      range: NSRange(location: 0, length: nsSection.length)
    ).enumerated() {
      let chunk = nsSection.substring(with: match.range)
      let nsChunk = chunk as NSString
      if clipRegex.firstMatch(
        in: chunk,
        options: [],
        range: NSRange(location: 0, length: nsChunk.length)
      ) != nil {
        indexes.insert(index)
      }
    }
    return indexes
  }

  private static func importedFormulaCache(
    from cell: CoreXLSX.Cell,
    sharedStrings: SharedStrings?
  ) -> FormulaCache? {
    guard let formula = cell.formula?.value, !formula.isEmpty else { return nil }
    if cell.type == .sharedString, let sharedStrings, let text = cell.stringValue(sharedStrings) {
      return FormulaCache(text: text, type: .string)
    }
    if let inline = cell.inlineString?.text, !inline.isEmpty {
      return FormulaCache(text: inline, type: .string)
    }
    if let value = cell.value, !value.isEmpty {
      return FormulaCache(text: value, type: formulaValueType(cell.type))
    }
    return nil
  }

  private static func formulaValueType(_ type: CellType?) -> ImportedFormulaValueType {
    switch type {
    case .bool: return .boolean
    case .error: return .error
    case .string, .inlineStr, .sharedString, .date: return .string
    case .number, nil: return .number
    }
  }

  private static func cellRawValue(_ cell: CoreXLSX.Cell, sharedStrings: SharedStrings?) -> String {
    if let formula = cell.formula?.value, !formula.isEmpty {
      return formula.hasPrefix("=") ? formula : "=\(formula)"
    }
    if cell.type == .bool, let value = cell.value {
      return value == "1" ? "TRUE" : "FALSE"
    }
    if let sharedStrings, let text = cell.stringValue(sharedStrings) {
      return text
    }
    if let inline = cell.inlineString?.text, !inline.isEmpty {
      return inline
    }
    return cell.value ?? ""
  }

  private static func cellFormat(
    styleIndex: Int?,
    styles: Styles,
    underlinedFontIds: Set<Int>,
    themeStyleColors: ThemeResolvedStyleColors,
    textRotationsByStyleIndex: [Int: Int],
    clipTextStyleIndexes: Set<Int>,
    unlockedStyleIndexes: Set<Int> = []
  ) -> CellFormat? {
    guard let styleIndex else { return nil }
    let xf = styleFormat(at: styleIndex, styles: styles)
    var format = CellFormat()
    var changed = false

    if let font = styleFont(xf, styles: styles) {
      if font.bold != nil {
        format.bold = true
        changed = true
      }
      if font.italic != nil {
        format.italic = true
        changed = true
      }
      if font.strike != nil {
        format.strikethrough = true
        changed = true
      }
      if let size = font.size?.value {
        format.fontSize = CGFloat(size)
        changed = true
      }
      if let name = font.name?.value, !name.isEmpty {
        format.fontFamily = name
        changed = true
      }
      if let color = codableColor(from: font.color) {
        format.textColor = color
        changed = true
      }
    }

    if let fontId = xf?.fontId {
      if underlinedFontIds.contains(fontId) {
        format.underline = true
        changed = true
      }
      if format.textColor == nil, let themed = themeStyleColors.fontColorsById[fontId] {
        format.textColor = themed
        changed = true
      }
    }

    if let fillId = xf?.fillId,
      let fills = styles.fills?.items,
      fillId >= 0,
      fillId < fills.count
    {
      let pattern = fills[fillId].patternFill
      if pattern.patternType != "none" {
        if let color = codableColor(from: pattern.foregroundColor ?? pattern.backgroundColor) {
          format.fillColor = color
          changed = true
        } else if let themed = themeStyleColors.fillColorsById[fillId] {
          format.fillColor = themed
          changed = true
        }
      }
    }

    if let xf {
      if let mapped = importedNumberFormat(for: xf.numberFormatId, styles: styles) {
        // Prefer explicit number formats even when applyNumberFormat is omitted (common in Excel exports).
        format.numberFormat = mapped.kind
        format.formatCode = mapped.code
        changed = true
      }

      if let borderId = xf.borderId,
        let borders = styles.borders?.items,
        borderId >= 0,
        borderId < borders.count
      {
        let imported = cellBorders(from: borders[borderId])
        if imported.hasAny {
          format.borders = imported
          changed = true
        }
      }

      if let alignment = xf.alignment {
        if let horizontal = horizontalAlign(from: alignment.horizontal) {
          format.horizontalAlign = horizontal
          changed = true
        }
        if let vertical = verticalAlign(from: alignment.vertical) {
          format.verticalAlign = vertical
          changed = true
        }
        if alignment.wrapText == true {
          format.wrapText = true
          changed = true
        }
      }
    }

    if format.textColor == nil, let themed = themeStyleColors.fontColorsByCellXfId[styleIndex] {
      format.textColor = themed
      changed = true
    }
    if format.fillColor == nil, let themed = themeStyleColors.fillColorsByCellXfId[styleIndex] {
      format.fillColor = themed
      changed = true
    }
    if let rotation = textRotationsByStyleIndex[styleIndex] {
      format.textRotation = rotation
      changed = true
    }
    if unlockedStyleIndexes.contains(styleIndex) {
      format.locked = false
      changed = true
    }
    if clipTextStyleIndexes.contains(styleIndex), !format.wrapText {
      format.textDisplay = .clip
      changed = true
    }

    return changed ? format : nil
  }

  /// One `CellFormat` per style index. Import copies these instead of rebuilding them per cell.
  private static func cellFormatsByStyleIndex(
    styles: Styles?,
    underlinedFontIds: Set<Int>,
    themeStyleColors: ThemeResolvedStyleColors,
    textRotationsByStyleIndex: [Int: Int],
    clipTextStyleIndexes: Set<Int>,
    unlockedStyleIndexes: Set<Int> = []
  ) -> [CellFormat?] {
    guard let styles, let items = styles.cellFormats?.items, !items.isEmpty else { return [] }
    var formats: [CellFormat?] = []
    formats.reserveCapacity(items.count)
    for index in items.indices {
      formats.append(
        cellFormat(
          styleIndex: index,
          styles: styles,
          underlinedFontIds: underlinedFontIds,
          themeStyleColors: themeStyleColors,
          textRotationsByStyleIndex: textRotationsByStyleIndex,
          clipTextStyleIndexes: clipTextStyleIndexes,
          unlockedStyleIndexes: unlockedStyleIndexes
        )
      )
    }
    return formats
  }

  private static func styleFormat(at styleIndex: Int, styles: Styles) -> CoreXLSX.Format? {
    guard let items = styles.cellFormats?.items, items.indices.contains(styleIndex) else {
      return nil
    }
    return items[styleIndex]
  }

  private static func styleFont(_ xf: CoreXLSX.Format?, styles: Styles) -> CoreXLSX.Font? {
    guard let fontID = xf?.fontId,
      let fonts = styles.fonts?.items,
      fonts.indices.contains(fontID)
    else { return nil }
    return fonts[fontID]
  }

  private static func cellBorders(from border: Border) -> CellBorders {
    CellBorders(
      top: borderEdge(from: border.top),
      bottom: borderEdge(from: border.bottom),
      left: borderEdge(from: border.left),
      right: borderEdge(from: border.right)
    )
  }

  private static func borderEdge(from value: Border.Value?) -> BorderEdge? {
    guard let value, let style = borderStyle(from: value.style) else { return nil }
    return BorderEdge(style: style, color: codableColor(from: value.color))
  }

  private static func borderStyle(from raw: String?) -> BorderStyle? {
    guard let raw, !raw.isEmpty else { return nil }
    switch raw {
    case "thin": return .thin
    case "medium": return .medium
    case "thick": return .thick
    case "dashed", "mediumDashed", "dashDot", "mediumDashDot",
      "dashDotDot", "mediumDashDotDot", "slantDashDot":
      return .dashed
    case "dotted", "hair": return .dotted
    case "double": return .double
    default: return .thin
    }
  }

  private static func horizontalAlign(from raw: String?) -> CellFormat.HorizontalAlign? {
    switch raw {
    case "left": return .left
    case "center", "centerContinuous": return .center
    case "right": return .right
    case "general": return .general
    default: return nil
    }
  }

  private static func verticalAlign(from raw: String?) -> CellFormat.VerticalAlign? {
    switch raw {
    case "top": return .top
    case "center": return .middle
    case "bottom": return .bottom
    default: return nil
    }
  }

  private struct ImportedNumberFormat {
    public var kind: CellFormat.NumberFormat
    public var code: String
  }

  /// Built-in ECMA-376 format ids. The code is what the cell actually displays.
  private static let builtinNumberFormatCodes: [Int: String] = [
    1: "0",
    2: "0.00",
    3: "#,##0",
    4: "#,##0.00",
    5: "$#,##0_);($#,##0)",
    6: "$#,##0_);[Red]($#,##0)",
    7: "$#,##0.00_);($#,##0.00)",
    8: "$#,##0.00_);[Red]($#,##0.00)",
    9: "0%",
    10: "0.00%",
    11: "0.00E+00",
    14: "m/d/yyyy",
    15: "d-mmm-yy",
    16: "d-mmm",
    17: "mmm-yy",
    18: "h:mm AM/PM",
    19: "h:mm:ss AM/PM",
    20: "h:mm",
    21: "h:mm:ss",
    22: "m/d/yyyy h:mm",
    37: "#,##0_);(#,##0)",
    38: "#,##0_);[Red](#,##0)",
    39: "#,##0.00_);(#,##0.00)",
    40: "#,##0.00_);[Red](#,##0.00)",
    45: "mm:ss",
    46: "[h]:mm:ss",
    48: "##0.0E+0",
    49: "@",
  ]

  private static func builtinNumberFormatID(matching code: String) -> Int? {
    let target = code.trimmingCharacters(in: .whitespacesAndNewlines)
    return builtinNumberFormatCodes.first {
      $0.value.caseInsensitiveCompare(target) == .orderedSame
    }?.key
  }

  private static func importedNumberFormat(for id: Int, styles: Styles) -> ImportedNumberFormat? {
    if let raw = styles.numberFormats?.items.first(where: { $0.id == id })?.formatCode {
      let code = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      if code.isEmpty || code.caseInsensitiveCompare("General") == .orderedSame { return nil }
      return ImportedNumberFormat(kind: classifyNumberFormat(code), code: code)
    }
    guard let code = builtinNumberFormatCodes[id] else { return nil }
    return ImportedNumberFormat(kind: classifyNumberFormat(code), code: code)
  }

  private static func classifyNumberFormat(_ code: String) -> CellFormat.NumberFormat {
    ExcelFormatCode.numberFormatKind(for: code)
  }

  private static func codableColor(from color: Color?) -> CodableColor? {
    if let rgb = color?.rgb, rgb.count >= 6 {
      let hex = rgb.count == 8 ? String(rgb.suffix(6)) : rgb
      guard let value = UInt32(hex, radix: 16) else { return nil }
      let r = Double((value >> 16) & 0xFF) / 255
      let g = Double((value >> 8) & 0xFF) / 255
      let b = Double(value & 0xFF) / 255
      return CodableColor(red: r, green: g, blue: b, alpha: 1)
    }
    if let indexed = color?.indexed, let rgb = indexedColorRGB(indexed) {
      return CodableColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
    }
    return nil
  }

  /// Standard ECMA-376 indexed color palette (subset; unknown indexes fall back to black/white).
  private static func indexedColorRGB(_ index: Int) -> (Double, Double, Double)? {
    let palette: [(Double, Double, Double)] = [
      (0, 0, 0), (1, 1, 1), (1, 0, 0), (0, 1, 0), (0, 0, 1), (1, 1, 0), (1, 0, 1), (0, 1, 1),
      (0, 0, 0), (1, 1, 1), (1, 0, 0), (0, 1, 0), (0, 0, 1), (1, 1, 0), (1, 0, 1), (0, 1, 1),
      (0.5, 0, 0), (0, 0.5, 0), (0, 0, 0.5), (0.5, 0.5, 0), (0.5, 0, 0.5), (0, 0.5, 0.5),
      (0.75, 0.75, 0.75), (0.5, 0.5, 0.5),
      (0.6, 0.8, 1), (0.6, 0.6, 1), (0.8, 0.6, 1), (1, 0.6, 1), (1, 0.6, 0.8), (1, 0.6, 0.6),
      (1, 0.8, 0.6), (1, 1, 0.6), (0.8, 1, 0.6), (0.6, 1, 0.6), (0.6, 1, 0.8), (0.6, 1, 1),
      (0, 0, 0.5), (0.4, 0, 0.6), (0.6, 0, 0.6), (0.6, 0, 0.4), (0.6, 0, 0), (0.6, 0.4, 0),
      (0.4, 0.6, 0), (0, 0.6, 0), (0, 0.6, 0.4), (0, 0.6, 0.6), (0, 0.4, 0.6), (0, 0, 0.6),
      (0.2, 0.2, 0.4), (0.4, 0.2, 0.6), (0.6, 0.2, 0.6), (0.6, 0.2, 0.4), (0.6, 0.2, 0.2),
      (0.6, 0.4, 0.2), (0.4, 0.6, 0.2), (0.2, 0.6, 0.2), (0.2, 0.6, 0.4), (0.2, 0.6, 0.6),
      (0.2, 0.4, 0.6), (0.2, 0.2, 0.6), (0.4, 0.4, 0.6), (0.6, 0.4, 0.6), (0.6, 0.4, 0.4),
    ]
    if index == 64 || index == 65 { return (0, 0, 0) }
    guard index >= 0, index < palette.count else { return nil }
    return palette[index]
  }

  private static func importColumnWidths(from worksheet: Worksheet, into sheet: inout Sheet) {
    for column in worksheet.columns?.items ?? [] {
      // Excel character widths ≈ pixels / 7 for default fonts.
      let width = CGFloat(column.width) * 7
      // The default width is written for grouped or hidden columns; it is not a set width.
      guard width > 0, abs(width - Workbook.defaultColumnWidth) > 0.5 else { continue }
      for col in column.min...column.max {
        sheet.columnWidths[col - 1] = width
      }
    }
  }

  private static func importRowHeights(from worksheet: Worksheet, into sheet: inout Sheet) {
    for row in worksheet.data?.rows ?? [] {
      guard let height = row.height, height > 0 else { continue }
      sheet.rowHeights[Int(row.reference) - 1] = CGFloat(height)
    }
  }

  private static func address(from reference: CellReference) -> CellAddress? {
    guard let col = A1Notation.columnIndex(from: reference.column.value) else { return nil }
    let row = Int(reference.row) - 1
    guard row >= 0, col >= 0 else { return nil }
    return CellAddress(row: row, col: col)
  }

  // MARK: - Export

  public static func exportWorkbook(_ workbook: Model.Workbook, includeFormulaCaches: Bool = true)
    throws -> Data
  {
    // Spark Grid's pivot tables go in as real pivot tables, so other apps can refresh them.
    let workbook = ExcelPivotWriter.addingParts(to: workbook)
    let sheetCount = workbook.sheets.count
    let collected = ExportSlots<SheetExportDraft>(count: sheetCount)
    if sheetCount > 0 {
      DispatchQueue.concurrentPerform(iterations: sheetCount) { index in
        collected.set(index, collectSheetExport(workbook.sheets[index]))
      }
    }
    let drafts = collected.snapshot()

    var sharedStrings: [String] = []
    var sharedIndex: [String: Int] = [:]
    var styleCatalog: [StyleKey: Int] = [.default: 0]
    var styleList: [StyleKey] = [.default]
    var formatToStyle: [CellFormat: Int] = [CellFormat(): 0]
    for draft in drafts {
      guard let draft else { throw CodecError.writeFailed }
      for text in draft.strings where sharedIndex[text] == nil {
        sharedIndex[text] = sharedStrings.count
        sharedStrings.append(text)
      }
      for format in draft.formats where formatToStyle[format] == nil {
        let key = StyleKey(format: format)
        if let existing = styleCatalog[key] {
          formatToStyle[format] = existing
        } else {
          let index = styleList.count
          styleList.append(key)
          styleCatalog[key] = index
          formatToStyle[format] = index
        }
      }
    }

    var dxfCatalog: [ConditionalFormatStyle: Int] = [:]
    var dxfList: [ConditionalFormatStyle] = []
    func recordDxf(_ style: ConditionalFormatStyle) -> Int {
      if let existing = dxfCatalog[style] { return existing }
      let index = dxfList.count
      dxfList.append(style)
      dxfCatalog[style] = index
      return index
    }
    for sheet in workbook.sheets {
      _ = conditionalFormattingXML(sheet.conditionalFormats, dxfIndex: recordDxf)
    }

    var files: [String: Data] = [:]
    var sheetsWithDrawings = Set<Int>()
    var globalImageIndex = 0
    for (index, sheet) in workbook.sheets.enumerated() {
      if appendSheetDrawingParts(
        for: sheet,
        sheetIndex: index,
        globalImageIndex: &globalImageIndex,
        into: &files
      ) {
        sheetsWithDrawings.insert(index)
      }
    }

    let frozenStrings = FrozenMap(sharedIndex)
    let frozenFormats = FrozenMap(formatToStyle)
    let frozenDxfs = FrozenMap(dxfCatalog)
    let drawings = sheetsWithDrawings
    let sheetXML = ExportSlots<Data>(count: sheetCount)
    if sheetCount > 0 {
      DispatchQueue.concurrentPerform(iterations: sheetCount) { index in
        let addresses: [CellAddress]
        if drafts.indices.contains(index), let draft = drafts[index] {
          addresses = draft.addresses
        } else {
          addresses = []
        }
        sheetXML.set(
          index,
          worksheetXML(
            workbook.sheets[index],
            addresses: addresses,
            stringIndex: frozenStrings,
            formatIndex: frozenFormats,
            dxfCatalog: frozenDxfs,
            includeDrawing: drawings.contains(index),
            includeFormulaCaches: includeFormulaCaches
          )
        )
      }
    }

    let numbers = keptPartNumbers(workbook)
    // Workbook relationships: sheets, then styles, shared strings and theme, then pivot caches.
    let pivotCaches = appendPivotCacheParts(
      workbook, numbers: numbers, firstID: sheetCount + 4, into: &files)
    files["_rels/.rels"] = rootRelsXML
    files["xl/workbook.xml"] = workbookXML(
      workbook, resultsWritten: includeFormulaCaches, pivotCaches: pivotCaches.element)
    var extraRelationships = pivotCaches.rels
    if workbook.sheets.contains(where: savesDynamicArrays) {
      files["xl/metadata.xml"] = dynamicArrayMetadataXML
      extraRelationships +=
        #"<Relationship Id="rIdMetadata" Type="\#(sheetMetadataRelationshipType)" "#
        + #"Target="metadata.xml"/>"#
    }
    files["xl/_rels/workbook.xml.rels"] = workbookRelsXML(
      sheetCount: sheetCount,
      includeTheme: workbook.xlsxThemeData != nil,
      extraRelationships: extraRelationships
    )

    let writtenSheets = sheetXML.snapshot()
    for index in 0..<sheetCount {
      guard writtenSheets.indices.contains(index), let xml = writtenSheets[index] else {
        throw CodecError.writeFailed
      }
      let hasDrawing = sheetsWithDrawings.contains(index)
      files["xl/worksheets/sheet\(index + 1).xml"] = xml
      if let rels = worksheetRelsXML(
        workbook.sheets[index], sheetIndex: index, hasDrawing: hasDrawing, numbers: numbers,
        into: &files)
      {
        files["xl/worksheets/_rels/sheet\(index + 1).xml.rels"] = rels
      }
      if let chartsData = sparkChartsJSON(workbook.sheets[index].charts) {
        files["xl/sparkGrid/charts\(index + 1).json"] = chartsData
      }
      if let pivotsData = sparkPivotsJSON(workbook.sheets[index].fileExtras.sparkPivots) {
        files["xl/sparkGrid/pivots\(index + 1).json"] = pivotsData
      }
    }

    files["xl/sharedStrings.xml"] = sharedStringsXML(sharedStrings)
    files["xl/styles.xml"] = stylesXML(styleList, dxfs: dxfList)
    if let themeData = workbook.xlsxThemeData {
      files["xl/theme/theme1.xml"] = themeData
    }
    files["[Content_Types].xml"] = contentTypesXML(
      sheetCount: sheetCount,
      drawingOverrides: drawingContentTypeOverrides(workbook: workbook)
        + keptPartContentTypes(files),
      imageDefaults: imageContentTypeDefaults(workbook: workbook),
      includeTheme: workbook.xlsxThemeData != nil,
      includeVML: files.keys.contains { $0.hasSuffix(".vml") }
    )

    guard let data = MinimalZip.archive(files: files) else {
      throw CodecError.writeFailed
    }
    return data
  }

  // MARK: - Export XML builders

  private static func contentTypesXML(
    sheetCount: Int,
    drawingOverrides: String = "",
    imageDefaults: String = "",
    includeTheme: Bool = false,
    includeVML: Bool = false
  ) -> Data {
    var overrides = """
      <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
      <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
      <Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>
      """
    if includeTheme {
      overrides += """
        <Override PartName="/xl/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>
        """
    }
    for i in 1...sheetCount {
      overrides += """
        <Override PartName="/xl/worksheets/sheet\(i).xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
        """
    }
    overrides += drawingOverrides
    let xml = """
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
      \(imageDefaults)
      <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
      <Default Extension="xml" ContentType="application/xml"/>
      <Default Extension="json" ContentType="application/json"/>
      \(includeVML ? #"<Default Extension="vml" ContentType="application/vnd.openxmlformats-officedocument.vmlDrawing"/>"# : "")
      \(overrides)
      </Types>
      """
    return Data(xml.utf8)
  }

  private static let rootRelsXML = Data(
    """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
    </Relationships>
    """.utf8)

  private static func workbookXML(
    _ workbook: Workbook, resultsWritten: Bool, pivotCaches: String = ""
  ) -> Data {
    var sheetsXML = ""
    // At least one sheet must stay visible, and the tab shown on open must be visible.
    let firstVisible = workbook.sheets.firstIndex { !$0.isHidden } ?? 0
    // Tab order is this element order, the order Excel reads. Do not sort it.
    for (index, sheet) in workbook.sheets.enumerated() {
      let name = escapeXML(sheet.name)
      var state = ""
      if index != firstVisible {
        switch sheet.fileExtras.visibility {
        case .visible: break
        case .hidden: state = #" state="hidden""#
        case .veryHidden: state = #" state="veryHidden""#
        }
      }
      sheetsXML +=
        #"<sheet name="\#(name)" sheetId="\#(index + 1)"\#(state) r:id="rId\#(index + 1)"/>"#
    }
    let bookViews =
      firstVisible == 0
      ? ""
      : #"<bookViews><workbookView firstSheet="\#(firstVisible)" activeTab="\#(firstVisible)"/></bookViews>"#
    var definedNames = ""
    // A `_xlnm.` name read by an older build has lost its sheet; each sheet writes its own.
    let items = workbook.namedRanges.values
      .filter { !$0.name.lowercased().hasPrefix("_xlnm.") }
      .sorted { $0.name.uppercased() < $1.name.uppercased() }
    let body =
      items.map { named -> String in
        let formula = named.referenceText
        return
          #"<definedName name="\#(escapeXML(named.name))">\#(escapeXML(formula))</definedName>"#
      }.joined() + sheetBuiltInNamesXML(workbook.sheets)
    if !body.isEmpty {
      definedNames = "<definedNames>\(body)</definedNames>"
    }
    // A formula saved without its result (after a sort, say) would open blank in a reader that
    // trusts stored results. Ask for a full calculation on open only then.
    let missingResult = workbook.sheets.contains { sheet in
      sheet.cells.values.contains {
        FormulaSyntax.isFormula($0.raw) && (!resultsWritten || $0.importedFormulaResult == nil)
      }
    }
    let calcPr = missingResult ? #"<calcPr fullCalcOnLoad="1"/>"# : ""
    let xml = """
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
      \(bookViews)
      <sheets>\(sheetsXML)</sheets>
      \(definedNames)
      \(calcPr)
      \(pivotCaches)
      </workbook>
      """
    return Data(xml.utf8)
  }

  private static func workbookRelsXML(
    sheetCount: Int, includeTheme: Bool = false, extraRelationships: String = ""
  ) -> Data {
    var rels = ""
    for i in 1...sheetCount {
      rels += """
        <Relationship Id="rId\(i)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet\(i).xml"/>
        """
    }
    let stylesId = sheetCount + 1
    let sharedId = sheetCount + 2
    let themeId = sheetCount + 3
    rels += """
      <Relationship Id="rId\(stylesId)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
      <Relationship Id="rId\(sharedId)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/>
      """
    if includeTheme {
      rels += """
        <Relationship Id="rId\(themeId)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="theme/theme1.xml"/>
        """
    }
    rels += extraRelationships
    let xml = """
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      \(rels)
      </Relationships>
      """
    return Data(xml.utf8)
  }

  private static func worksheetXML(
    _ sheet: Sheet,
    addresses: [CellAddress],
    stringIndex: FrozenMap<String, Int>,
    formatIndex: FrozenMap<CellFormat, Int>,
    dxfCatalog: FrozenMap<ConditionalFormatStyle, Int>,
    includeDrawing: Bool = false,
    includeFormulaCaches: Bool = true
  ) -> Data {
    var xml = XMLBytes()
    xml.reserve(512 + addresses.count * 48)
    xml.append(
      utf8:
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\">"
    )
    let extras = sheet.fileExtras
    if let properties = extras.sheetPropertiesXML {
      xml.append(utf8: properties)
    }
    xml.append(
      utf8: sheetViewsXML(frozenRows: sheet.frozenRows, frozenColumns: sheet.frozenColumns))
    // Other apps draw the outline bar only when the sheet says how deep its groups go.
    let rowDepth = extras.rowOutlineLevels.values.max() ?? 0
    let columnDepth = extras.columnOutlineLevels.values.max() ?? 0
    if rowDepth > 0 || columnDepth > 0 {
      var format = #"<sheetFormatPr defaultRowHeight="15""#
      if rowDepth > 0 { format += #" outlineLevelRow="\#(rowDepth)""# }
      if columnDepth > 0 { format += #" outlineLevelCol="\#(columnDepth)""# }
      xml.append(utf8: format + "/>")
    }
    xml.append(utf8: columnsXML(sheet))
    xml.append(ascii: "<sheetData>")
    appendRows(
      of: sheet,
      addresses: addresses,
      stringIndex: stringIndex,
      formatIndex: formatIndex,
      includeFormulaCaches: includeFormulaCaches,
      into: &xml
    )
    xml.append(ascii: "</sheetData>")
    // ECMA-376 order: sheetData → sheetProtection → autoFilter → mergeCells → conditionalFormatting
    // → dataValidations → hyperlinks → page setup → drawing → legacyDrawing → tableParts → extLst
    if let protection = extras.protectionXML {
      xml.append(utf8: protection)
    }
    xml.append(utf8: autoFilterXML(sheet.autoFilter))
    xml.append(utf8: mergeCellsXML(sheet.mergedRanges))
    xml.append(
      utf8: conditionalFormattingXML(sheet.conditionalFormats) { dxfCatalog.get($0) ?? 0 }
    )
    xml.append(utf8: dataValidationsXML(extras.dataValidations))
    let rels = worksheetRelationshipIDs(sheet, hasDrawing: includeDrawing)
    xml.append(utf8: hyperlinksXML(extras.hyperlinks, firstExternalID: rels.firstHyperlink))
    if let layout = extras.pageLayoutXML {
      xml.append(utf8: layout)
    }
    xml.append(utf8: extras.pageBreaksXML)
    if includeDrawing {
      xml.append(utf8: sheetDrawingRelationshipXML(sheetIndex: 0))
    }
    if let comments = rels.comments {
      xml.append(utf8: #"<legacyDrawing r:id="rId\#(comments + 1)"/>"#)
    }
    if !rels.tables.isEmpty {
      let parts = rels.tables.map { #"<tablePart r:id="rId\#($0)"/>"# }.joined()
      xml.append(utf8: #"<tableParts count="\#(rels.tables.count)">\#(parts)</tableParts>"#)
    }
    xml.append(ascii: "</worksheet>")
    return xml.data
  }

  /// Rows are already in address order. A resized row with no cells still gets a height.
  private static func appendRows(
    of sheet: Sheet,
    addresses: [CellAddress],
    stringIndex: FrozenMap<String, Int>,
    formatIndex: FrozenMap<CellFormat, Int>,
    includeFormulaCaches: Bool,
    into xml: inout XMLBytes
  ) {
    var seenRows = Set<Int>()
    var rows: [Int] = []
    for address in addresses where seenRows.insert(address.row).inserted {
      rows.append(address.row)
    }
    for row in sheet.rowHeights.keys where seenRows.insert(row).inserted {
      rows.append(row)
    }
    let attributedRows = rowsWithFileAttributes(sheet)
    for row in attributedRows where row >= 0 && seenRows.insert(row).inserted {
      rows.append(row)
    }
    rows.sort()

    let spills = sheet.fileExtras.spills
    var cursor = 0
    for row in rows {
      while cursor < addresses.count {
        let address = addresses[cursor]
        if address.row >= row { break }
        cursor += 1
      }
      let start = cursor
      while cursor < addresses.count, addresses[cursor].row == row {
        cursor += 1
      }
      xml.append(ascii: "<row r=\"")
      xml.append(positive: row + 1)
      xml.append(ascii: "\"")
      if let height = sheet.rowHeights[row] {
        xml.append(utf8: #" ht="\#(height)" customHeight="1""#)
      }
      if !attributedRows.isEmpty, attributedRows.contains(row) {
        xml.append(utf8: rowAttributesXML(sheet, row: row))
      }
      if start == cursor {
        xml.append(ascii: "/>")
        continue
      }
      xml.append(ascii: ">")
      for address in addresses[start..<cursor] {
        appendCell(
          sheet.cell(at: address),
          at: address,
          spill: spills.isEmpty ? nil : spills[address],
          stringIndex: stringIndex,
          formatIndex: formatIndex,
          includeFormulaCaches: includeFormulaCaches,
          into: &xml
        )
      }
      xml.append(ascii: "</row>")
    }
  }

  private static func appendCell(
    _ cell: Cell,
    at address: CellAddress,
    spill: CellRange? = nil,
    stringIndex: FrozenMap<String, Int>,
    formatIndex: FrozenMap<CellFormat, Int>,
    includeFormulaCaches: Bool,
    into xml: inout XMLBytes
  ) {
    let kind = exportCellKind(cell)
    guard kind != .skip else { return }
    let style = cell.format.flatMap { formatIndex.get($0) } ?? 0
    xml.append(ascii: "<c")
    xml.appendCellRef(address)
    if style > 0 {
      xml.append(ascii: " s=\"")
      xml.append(positive: style)
      xml.append(ascii: "\"")
    }
    switch kind {
    case .formula:
      let formula = ExcelFutureFunctions.prefixed(
        ExcelFutureFunctions.anchorArrays(
          String(cell.raw.drop(while: { $0 == "=" || $0.isWhitespace }))))
      let cache =
        includeFormulaCaches
        ? formulaCacheMarkup(cell)
        : (typeAttribute: "", valueElement: "")
      xml.append(utf8: cache.typeAttribute)
      // A formula that can spill is saved as one even when it fills one cell or is blocked;
      // saved as a plain formula, other apps would read it the pre-spill way.
      if let range = spill ?? (spills(cell.raw) ? CellRange(start: address, end: address) : nil) {
        // Marks the formula as spilling (metadata.xml) and gives the cells its results fill.
        xml.append(ascii: " cm=\"1\"><f t=\"array\" ref=\"")
        xml.append(utf8: range.a1Label)
        xml.append(ascii: "\">")
      } else {
        xml.append(ascii: "><f>")
      }
      xml.append(escaped: formula)
      xml.append(ascii: "</f>")
      xml.append(utf8: cache.valueElement)
      xml.append(ascii: "</c>")
    case .number:
      xml.append(ascii: "><v>")
      xml.append(escaped: cell.raw)
      xml.append(ascii: "</v></c>")
    case .boolean:
      xml.append(ascii: " t=\"b\"><v>")
      xml.append(ascii: cell.raw.uppercased() == "TRUE" ? "1" : "0")
      xml.append(ascii: "</v></c>")
    case .sharedString:
      if let index = stringIndex.get(cell.raw) {
        xml.append(ascii: " t=\"s\"><v>")
        xml.append(positive: index)
        xml.append(ascii: "</v></c>")
      } else {
        xml.append(ascii: " t=\"inlineStr\"><is><t>")
        xml.append(escaped: cell.raw)
        xml.append(ascii: "</t></is></c>")
      }
    case .spilled:
      // A spilled result is saved as the value it shows.
      let markup = formulaCacheMarkup(cell)
      if markup.typeAttribute == #" t="str""# {
        let text = cell.importedFormulaResult ?? ""
        xml.append(ascii: " t=\"inlineStr\"><is><t xml:space=\"preserve\">")
        xml.append(escaped: text)
        xml.append(ascii: "</t></is></c>")
      } else if markup.valueElement.isEmpty {
        xml.append(ascii: "/>")
      } else {
        xml.append(utf8: markup.typeAttribute)
        xml.append(ascii: ">")
        xml.append(utf8: markup.valueElement)
        xml.append(ascii: "</c>")
      }
    case .emptyFormatted:
      xml.append(ascii: "/>")
    case .skip:
      break
    }
  }

  /// ECMA-376 error codes, the only ones a saved result may use. Newer errors such as #SPILL!
  /// and #CALC! are written as text: saved as errors, Excel reports the file as damaged.
  private static let ooxmlErrorCodes: Set<String> = [
    "#NULL!", "#DIV/0!", "#VALUE!", "#REF!", "#NAME?", "#NUM!", "#N/A", "#GETTING_DATA",
  ]

  /// Whether any formula on `sheet` is saved as a dynamic array, which needs `xl/metadata.xml`.
  static func savesDynamicArrays(_ sheet: Sheet) -> Bool {
    if !sheet.fileExtras.spills.isEmpty { return true }
    return sheet.cells.values.contains { FormulaSyntax.isFormula($0.raw) && spills($0.raw) }
  }

  private static func formulaCacheMarkup(_ cell: Cell) -> (
    typeAttribute: String, valueElement: String
  ) {
    guard let raw = cell.importedFormulaResult else { return ("", "") }
    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.isEmpty {
      guard cell.importedFormulaValueType == .string else { return ("", "") }
      return (#" t="str""#, "<v/>")
    }
    let type = cell.importedFormulaValueType ?? inferredFormulaValueType(text)
    switch type {
    case .number:
      return ("", "<v>\(escapeXML(text))</v>")
    case .string:
      return (#" t="str""#, "<v>\(escapeXML(text))</v>")
    case .boolean:
      return (#" t="b""#, "<v>\(booleanCacheBit(text))</v>")
    case .error:
      if ooxmlErrorCodes.contains(text) {
        return (#" t="e""#, "<v>\(escapeXML(text))</v>")
      }
      return (#" t="str""#, "<v>\(escapeXML(text))</v>")
    }
  }

  private static func inferredFormulaValueType(_ text: String) -> ImportedFormulaValueType {
    if ooxmlErrorCodes.contains(text) || FormulaError(displayCode: text) != nil {
      return .error
    }
    switch text.uppercased() {
    case "TRUE", "FALSE": return .boolean
    default: break
    }
    if Double(text) != nil, !text.contains(where: \.isLetter) {
      return .number
    }
    return .string
  }

  private static func booleanCacheBit(_ text: String) -> String {
    switch text.uppercased() {
    case "1", "TRUE": return "1"
    default: return "0"
    }
  }

  private static func sharedStringsXML(_ strings: [String]) -> Data {
    var xml = XMLBytes()
    var capacity = 160
    for text in strings {
      capacity += text.utf8.count + 17
    }
    xml.reserve(capacity)
    xml.append(
      utf8:
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><sst xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" count=\""
    )
    xml.append(positive: strings.count)
    xml.append(ascii: "\" uniqueCount=\"")
    xml.append(positive: strings.count)
    xml.append(ascii: "\">")
    for text in strings {
      xml.append(ascii: "<si><t>")
      xml.append(escaped: text)
      xml.append(ascii: "</t></si>")
    }
    xml.append(ascii: "</sst>")
    return xml.data
  }

  private static func stylesXML(_ styles: [StyleKey], dxfs: [ConditionalFormatStyle] = []) -> Data {
    var customFormats: [String: Int] = [:]
    var nextCustomID = 164
    var fonts = ""
    var fills =
      #"<fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill>"#
    var bordersXML = #"<border><left/><right/><top/><bottom/><diagonal/></border>"#
    var cellXfs = ""
    var fillCount = 2
    var borderCount = 1
    var borderIndexByKey: [StyleBorderKey: Int] = [.none: 0]

    for (fontId, style) in styles.enumerated() {
      let bold = style.bold ? "<b/>" : ""
      let italic = style.italic ? "<i/>" : ""
      let underline = style.underline ? #"<u val="single"/>"# : ""
      let strike = style.strikethrough ? "<strike/>" : ""
      let size = style.fontSize.map { #"<sz val="\#($0)"/>"# } ?? #"<sz val="12"/>"#
      let name = #"<name val="\#(escapeXML(style.fontFamily ?? "Helvetica Neue"))"/>"#
      let color = style.textRGB.map { #"<color rgb="FF\#($0)"/>"# } ?? ""
      fonts += "<font>\(bold)\(italic)\(underline)\(strike)\(size)\(color)\(name)</font>"

      var fillId = 0
      if let fillRGB = style.fillRGB {
        fills +=
          #"<fill><patternFill patternType="solid"><fgColor rgb="FF\#(fillRGB)"/><bgColor indexed="64"/></patternFill></fill>"#
        fillId = fillCount
        fillCount += 1
      }

      let borderId: Int
      if let existing = borderIndexByKey[style.borders] {
        borderId = existing
      } else {
        bordersXML += style.borders.xml
        borderId = borderCount
        borderIndexByKey[style.borders] = borderId
        borderCount += 1
      }

      let numFmtId = numberFormatID(
        for: style, customFormats: &customFormats, nextCustomID: &nextCustomID)

      let alignmentXML = style.alignmentXML
      let applyBorder = borderId == 0 ? "0" : "1"
      let applyAlignment = alignmentXML.isEmpty ? "0" : "1"
      let protection = style.locked ? "" : #"<protection locked="0"/>"#
      let applyProtection = style.locked ? "" : #" applyProtection="1""#
      cellXfs +=
        #"<xf numFmtId="\#(numFmtId)" fontId="\#(fontId)" fillId="\#(fillId)" borderId="\#(borderId)" xfId="0" applyFont="1" applyFill="1" applyBorder="\#(applyBorder)" applyAlignment="\#(applyAlignment)" applyNumberFormat="1"\#(applyProtection)>\#(alignmentXML)\#(protection)</xf>"#
    }

    let numFmts =
      customFormats
      .sorted { $0.value < $1.value }
      .map { #" <numFmt numFmtId="\#($0.value)" formatCode="\#(escapeXML($0.key))"/>"# }
      .joined()
    let styleSheetExtraNamespaces =
      styles.contains(where: \.clipText)
      ? #" xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006""#
        + #" xmlns:\#(StyleKey.sparkPrefix)="\#(StyleKey.sparkNamespace)""#
        + #" mc:Ignorable="\#(StyleKey.sparkPrefix)""#
      : ""
    let xml = """
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"\(styleSheetExtraNamespaces)>
      <numFmts count="\(customFormats.count)">\(numFmts)</numFmts>
      <fonts count="\(styles.count)">\(fonts)</fonts>
      <fills count="\(fillCount)">\(fills)</fills>
      <borders count="\(borderCount)">\(bordersXML)</borders>
      <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
      <cellXfs count="\(styles.count)">\(cellXfs)</cellXfs>
      <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
      \(dxfsXML(dxfs))
      <tableStyles count="0" defaultTableStyle="TableStyleMedium9" defaultPivotStyle="PivotStyleLight16"/>
      </styleSheet>
      """
    return Data(xml.utf8)
  }

  private static func numberFormatID(
    for style: StyleKey,
    customFormats: inout [String: Int],
    nextCustomID: inout Int
  ) -> Int {
    if let code = style.formatCode?.trimmingCharacters(in: .whitespacesAndNewlines),
      !code.isEmpty,
      code.caseInsensitiveCompare("General") != .orderedSame
    {
      if let builtin = builtinNumberFormatID(matching: code) { return builtin }
      if let existing = customFormats[code] { return existing }
      let id = nextCustomID
      nextCustomID += 1
      customFormats[code] = id
      return id
    }
    switch style.numberFormat {
    case .general: return 0
    case .number: return 2
    case .currency:
      let code = "$#,##0.00"
      if let existing = customFormats[code] { return existing }
      let id = nextCustomID
      nextCustomID += 1
      customFormats[code] = id
      return id
    case .percent: return 10
    case .scientific: return 11
    case .date: return 14
    case .time: return 21
    }
  }

  private static func collectSheetExport(_ sheet: Sheet) -> SheetExportDraft {
    var strings: [String] = []
    var seenStrings = Set<String>()
    var formats: [CellFormat] = []
    var seenFormats = Set<CellFormat>()
    let addresses = sheet.cells.keys.sorted()
    for address in addresses {
      let cell = sheet.cell(at: address)
      if let format = cell.format, seenFormats.insert(format).inserted {
        formats.append(format)
      }
      if exportCellKind(cell) == .sharedString, seenStrings.insert(cell.raw).inserted {
        strings.append(cell.raw)
      }
    }
    return SheetExportDraft(addresses: addresses, strings: strings, formats: formats)
  }

  private static func exportCellKind(_ cell: Cell) -> ExportCellKind {
    if FormulaSyntax.isFormula(cell.raw) { return .formula }
    // A typed TRUE or FALSE is a boolean, saved as one so other apps read it the same way.
    let upper = cell.raw.uppercased()
    if upper == "TRUE" || upper == "FALSE" { return .boolean }
    if Double(cell.raw) != nil, !cell.raw.contains(where: \.isLetter) { return .number }
    if !cell.raw.isEmpty { return .sharedString }
    if cell.importedFormulaResult != nil { return .spilled }
    if cell.format != nil { return .emptyFormatted }
    return .skip
  }

  public static func escapeXML(_ string: String) -> String {
    string
      .replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
      .replacingOccurrences(of: "'", with: "&apos;")
  }
}

// MARK: - Parallel export

private nonisolated enum ExportCellKind {
  case formula
  case number
  case boolean
  case sharedString
  case spilled
  case emptyFormatted
  case skip
}

private nonisolated struct SheetExportDraft: Sendable {
  var addresses: [CellAddress]
  var strings: [String]
  var formats: [CellFormat]
}

/// Read-only map shared by sheet writers. The dictionary is not mutated.
private nonisolated final class FrozenMap<Key: Hashable, Value>: @unchecked Sendable {
  private let values: [Key: Value]

  init(_ values: [Key: Value]) {
    self.values = values
  }

  func get(_ key: Key) -> Value? {
    values[key]
  }
}

/// Slots filled from a concurrent sheet walk, then read on the calling thread.
private nonisolated final class ExportSlots<Element>: @unchecked Sendable {
  private let lock = NSLock()
  private var values: [Element?]

  init(count: Int) {
    values = Array(repeating: nil, count: count)
  }

  func set(_ index: Int, _ value: Element) {
    lock.lock()
    defer { lock.unlock() }
    guard values.indices.contains(index) else { return }
    values[index] = value
  }

  func snapshot() -> [Element?] {
    lock.lock()
    defer { lock.unlock() }
    return values
  }
}

private nonisolated struct XMLBytes {
  private var storage: [UInt8] = []

  var data: Data { Data(storage) }

  mutating func reserve(_ capacity: Int) {
    if capacity > storage.capacity {
      storage.reserveCapacity(capacity)
    }
  }

  mutating func append(ascii literal: StaticString) {
    literal.withUTF8Buffer { buffer in
      storage.append(contentsOf: buffer)
    }
  }

  mutating func append(utf8 text: String) {
    storage.append(contentsOf: text.utf8)
  }

  mutating func append(escaped text: String) {
    for byte in text.utf8 {
      switch byte {
      case UInt8(ascii: "&"):
        append(ascii: "&amp;")
      case UInt8(ascii: "<"):
        append(ascii: "&lt;")
      case UInt8(ascii: ">"):
        append(ascii: "&gt;")
      case UInt8(ascii: "\""):
        append(ascii: "&quot;")
      case UInt8(ascii: "'"):
        append(ascii: "&apos;")
      default:
        storage.append(byte)
      }
    }
  }

  mutating func append(positive value: Int) {
    guard value > 0 else {
      storage.append(UInt8(ascii: "0"))
      return
    }
    var digits: [UInt8] = []
    var n = value
    while n > 0 {
      let remainder = n % 10
      digits.append(UInt8(ascii: "0") + UInt8(remainder))
      n /= 10
    }
    for byte in digits.reversed() {
      storage.append(byte)
    }
  }

  mutating func appendCellRef(_ address: CellAddress) {
    append(ascii: " r=\"")
    appendColumn(address.col)
    append(positive: address.row + 1)
    append(ascii: "\"")
  }

  private mutating func appendColumn(_ index: Int) {
    guard index >= 0 else { return }
    var n = index + 1
    var letters: [UInt8] = []
    while n > 0 {
      n -= 1
      let remainder = n % 26
      letters.append(UInt8(ascii: "A") + UInt8(remainder))
      n /= 26
    }
    for byte in letters.reversed() {
      storage.append(byte)
    }
  }
}

// MARK: - Style key

private nonisolated struct StyleBorderEdgeKey: Hashable {
  var style: String
  var rgb: String?

  init?(_ edge: BorderEdge?) {
    guard let edge else { return nil }
    style = edge.style.rawValue
    rgb = edge.color.map(StyleKey.rgbHex)
  }
}

private nonisolated struct StyleBorderKey: Hashable {
  var top: StyleBorderEdgeKey?
  var bottom: StyleBorderEdgeKey?
  var left: StyleBorderEdgeKey?
  var right: StyleBorderEdgeKey?

  static let none = StyleBorderKey()

  init(_ borders: CellBorders = .none) {
    top = StyleBorderEdgeKey(borders.top)
    bottom = StyleBorderEdgeKey(borders.bottom)
    left = StyleBorderEdgeKey(borders.left)
    right = StyleBorderEdgeKey(borders.right)
  }

  var xml: String {
    func side(_ name: String, _ edge: StyleBorderEdgeKey?) -> String {
      guard let edge else { return "<\(name)/>" }
      if let rgb = edge.rgb {
        return #"<\#(name) style="\#(edge.style)"><color rgb="FF\#(rgb)"/></\#(name)>"#
      }
      return #"<\#(name) style="\#(edge.style)"/>"#
    }
    return
      "<border>\(side("left", left))\(side("right", right))\(side("top", top))\(side("bottom", bottom))<diagonal/></border>"
  }
}

private nonisolated struct StyleKey: Hashable {
  /// Spark Grid's own style settings live in this namespace, which the style sheet marks
  /// mc:Ignorable so other apps skip them instead of reporting the file as damaged.
  static let sparkPrefix = "sg"
  static let sparkNamespace = "urn:sparkgrid:xlsx:2026"

  var bold = false
  var italic = false
  var underline = false
  var strikethrough = false
  var fontFamily: String?
  var fontSize: Double?
  var textRGB: String?
  var fillRGB: String?
  var numberFormat: CellFormat.NumberFormat = .general
  var formatCode: String?
  var borders = StyleBorderKey.none
  var horizontalAlign: CellFormat.HorizontalAlign = .general
  var verticalAlign: CellFormat.VerticalAlign = .bottom
  var wrapText = false
  var clipText = false
  var textRotation = 0
  var locked = true

  static let `default` = StyleKey()

  init(format: CellFormat? = nil) {
    guard let format else { return }
    bold = format.bold
    italic = format.italic
    underline = format.underline
    strikethrough = format.strikethrough
    fontFamily = format.fontFamily
    fontSize = format.fontSize.map(Double.init)
    textRGB = format.textColor.map(Self.rgbHex)
    fillRGB = format.fillColor.map(Self.rgbHex)
    numberFormat = format.numberFormat
    formatCode = format.formatCode
    borders = StyleBorderKey(format.borders)
    horizontalAlign = format.horizontalAlign
    verticalAlign = format.verticalAlign
    wrapText = format.wrapText
    clipText = format.textDisplay == .clip
    textRotation = format.textRotation
    locked = format.locked
  }

  var alignmentXML: String {
    var attrs: [String] = []
    switch horizontalAlign {
    case .general: break
    case .left: attrs.append(#"horizontal="left""#)
    case .center: attrs.append(#"horizontal="center""#)
    case .right: attrs.append(#"horizontal="right""#)
    }
    switch verticalAlign {
    case .bottom: break
    case .top: attrs.append(#"vertical="top""#)
    case .middle: attrs.append(#"vertical="center""#)
    }
    if wrapText { attrs.append(#"wrapText="1""#) }
    if clipText { attrs.append(#"\#(Self.sparkPrefix):textDisplay="clip""#) }
    if textRotation != 0 { attrs.append(#"textRotation="\#(textRotation)""#) }
    guard !attrs.isEmpty else { return "" }
    return "<alignment \(attrs.joined(separator: " "))/>"
  }

  static func rgbHex(_ color: CodableColor) -> String {
    let r = Int((color.red * 255).rounded())
    let g = Int((color.green * 255).rounded())
    let b = Int((color.blue * 255).rounded())
    return String(format: "%02X%02X%02X", r, g, b)
  }
}

// MARK: - ZIP (deflate, zlib CRC-32)

private nonisolated struct PreparedZipEntry: Sendable {
  var body: Data
  var method: UInt16
  var crc: UInt32
  var uncompressed: UInt32
}

private nonisolated enum MinimalZip {
  static func archive(files: [String: Data]) -> Data? {
    let paths = files.keys.sorted()
    guard let entryCount = UInt16(exactly: paths.count) else { return nil }
    var payloads: [Data] = []
    payloads.reserveCapacity(paths.count)
    for path in paths {
      guard let payload = files[path], UInt32(exactly: payload.count) != nil else { return nil }
      payloads.append(payload)
    }

    let prepared = ExportSlots<PreparedZipEntry>(count: paths.count)
    if !paths.isEmpty {
      DispatchQueue.concurrentPerform(iterations: paths.count) { index in
        guard payloads.indices.contains(index) else { return }
        prepared.set(index, prepare(payloads[index]))
      }
    }
    let entries = prepared.snapshot()

    var central = Data()
    var local = Data()
    var offset: UInt32 = 0

    for (index, path) in paths.enumerated() {
      guard entries.indices.contains(index), let entry = entries[index] else { return nil }
      let nameData = Data(path.utf8)
      guard let nameLength = UInt16(exactly: nameData.count),
        let compressedSize = UInt32(exactly: entry.body.count)
      else { return nil }

      var localHeader = Data()
      localHeader.appendUInt32(0x0403_4b50)
      localHeader.appendUInt16(20)
      localHeader.appendUInt16(0)
      localHeader.appendUInt16(entry.method)
      localHeader.appendUInt16(0)
      localHeader.appendUInt16(0)
      localHeader.appendUInt32(entry.crc)
      localHeader.appendUInt32(compressedSize)
      localHeader.appendUInt32(entry.uncompressed)
      localHeader.appendUInt16(nameLength)
      localHeader.appendUInt16(0)
      localHeader.append(nameData)
      localHeader.append(entry.body)

      var centralHeader = Data()
      centralHeader.appendUInt32(0x0201_4b50)
      centralHeader.appendUInt16(20)
      centralHeader.appendUInt16(20)
      centralHeader.appendUInt16(0)
      centralHeader.appendUInt16(entry.method)
      centralHeader.appendUInt16(0)
      centralHeader.appendUInt16(0)
      centralHeader.appendUInt32(entry.crc)
      centralHeader.appendUInt32(compressedSize)
      centralHeader.appendUInt32(entry.uncompressed)
      centralHeader.appendUInt16(nameLength)
      centralHeader.appendUInt16(0)
      centralHeader.appendUInt16(0)
      centralHeader.appendUInt16(0)
      centralHeader.appendUInt16(0)
      centralHeader.appendUInt32(0)
      centralHeader.appendUInt32(offset)
      centralHeader.append(nameData)

      guard let headerSize = UInt32(exactly: localHeader.count) else { return nil }
      let (nextOffset, overflowed) = offset.addingReportingOverflow(headerSize)
      if overflowed { return nil }
      local.append(localHeader)
      central.append(centralHeader)
      offset = nextOffset
    }

    guard let centralSize = UInt32(exactly: central.count),
      let localSize = UInt32(exactly: local.count)
    else { return nil }

    var end = Data()
    end.appendUInt32(0x0605_4b50)
    end.appendUInt16(0)
    end.appendUInt16(0)
    end.appendUInt16(entryCount)
    end.appendUInt16(entryCount)
    end.appendUInt32(centralSize)
    end.appendUInt32(localSize)
    end.appendUInt16(0)

    return local + central + end
  }

  /// Deflate when it shrinks the entry. The checksum is zlib's CRC-32 of the original bytes.
  private static func prepare(_ payload: Data) -> PreparedZipEntry {
    let crc = payload.crc32(checksum: 0)
    let uncompressed = UInt32(exactly: payload.count) ?? 0
    if payload.isEmpty {
      return PreparedZipEntry(body: payload, method: 0, crc: crc, uncompressed: uncompressed)
    }
    if let compressed = deflate(payload),
      compressed.count < payload.count,
      UInt32(exactly: compressed.count) != nil
    {
      return PreparedZipEntry(body: compressed, method: 8, crc: crc, uncompressed: uncompressed)
    }
    return PreparedZipEntry(body: payload, method: 0, crc: crc, uncompressed: uncompressed)
  }

  private static func deflate(_ payload: Data) -> Data? {
    var output = Data()
    output.reserveCapacity(payload.count / 4)
    do {
      _ = try Data.compress(
        size: Int64(payload.count),
        bufferSize: payload.count + 1,
        provider: { position, _ in
          let start = Int(position)
          guard start >= 0, start < payload.count else { return Data() }
          return payload.subdata(in: start..<payload.count)
        },
        consumer: { chunk in
          output.append(chunk)
        }
      )
    } catch {
      return nil
    }
    return output
  }
}

extension Data {
  fileprivate mutating func appendUInt16(_ value: UInt16) {
    var le = value.littleEndian
    Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
  }

  fileprivate mutating func appendUInt32(_ value: UInt32) {
    var le = value.littleEndian
    Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
  }
}
