import Foundation
import GridCore
import Model
import NumberFormat

/// Opens a Numbers document: every table becomes a sheet with its values. Text, numbers, dates,
/// durations and true/false come in; a formula comes in as the result Numbers last calculated.
///
/// Numbers keeps a document as protobuf objects (see `NumbersArchive`). The ones read here:
/// the document (type 1) lists sheets, a sheet (2) names itself and lists its drawables, a
/// table (6000) points at its model (6001), whose data store holds the tiles of cells (6002) and
/// the lists (6005) cells point into for text.
public nonisolated enum NumbersImporter {
  public enum ImportError: LocalizedError {
    case notNumbers
    case damaged
    case noTables

    public var errorDescription: String? {
      switch self {
      case .notNumbers: return "This isn't a Numbers document."
      case .damaged: return "This Numbers document is damaged and can't be read."
      case .noTables: return "This Numbers document has no tables to open."
      }
    }
  }

  /// A `.numbers` file: one zip, or a package folder with its parts in `Index.zip` or `Index/`.
  public static func importWorkbook(from url: URL) throws -> Workbook {
    var isDirectory: ObjCBool = false
    if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    {
      let indexZip = url.appendingPathComponent("Index.zip")
      if FileManager.default.fileExists(atPath: indexZip.path) {
        return try importWorkbook(fromArchiveData: Data(contentsOf: indexZip))
      }
      let index = url.appendingPathComponent("Index")
      var parts: [String: Data] = [:]
      let found = FileManager.default.enumerator(at: index, includingPropertiesForKeys: nil)
      while let file = found?.nextObject() as? URL {
        guard file.pathExtension == "iwa" else { continue }
        let relative = file.path.replacingOccurrences(of: index.path + "/", with: "")
        parts["Index/" + relative] = try Data(contentsOf: file)
      }
      return try importWorkbook(parts: parts)
    }
    return try importWorkbook(fromArchiveData: Data(contentsOf: url))
  }

  public static func importWorkbook(fromArchiveData data: Data) throws -> Workbook {
    let package: ZipPackage
    do {
      package = try ZipPackage(archiveData: data)
    } catch XLSXCodec.CodecError.tooLarge {
      throw XLSXCodec.CodecError.tooLarge
    } catch {
      throw ImportError.notNumbers
    }
    var parts: [String: Data] = [:]
    for path in package.entryPaths {
      parts[path] = package.data(for: path)
    }
    return try importWorkbook(parts: parts)
  }

  static func importWorkbook(parts: [String: Data]) throws -> Workbook {
    let archive: NumbersArchive
    do {
      archive = try NumbersArchive(parts: parts)
    } catch NumbersArchive.ReadError.notNumbers {
      throw ImportError.notNumbers
    } catch {
      throw ImportError.damaged
    }
    guard let documentID = archive.ids(ofType: Types.document).first,
      let document = archive.message(documentID)
    else { throw ImportError.damaged }

    // Every table first, with its sheet name, so a formula can name a table read later.
    var tables: [(name: String, model: ProtoMessage, owner: UInt64?)] = []
    for (index, sheetID) in document.references(1).enumerated() {
      guard let sheetMessage = archive.message(sheetID) else { continue }
      let sheetName = sheetMessage.string(1) ?? "Sheet \(index + 1)"
      let tableIDs = sheetMessage.references(2).filter {
        archive.object($0)?.type == Types.tableInfo
      }
      for tableID in tableIDs {
        guard let info = archive.message(tableID), let modelID = info.reference(2),
          let model = archive.message(modelID)
        else { continue }
        let tableName = model.string(8) ?? "Table"
        let name = tableIDs.count == 1 ? sheetName : "\(sheetName) - \(tableName)"
        // The table's formula owners share the upper half of its identifier (field 7).
        tables.append(
          (uniqueName(name, taken: tables.map(\.name)), model, info.message(7)?.varint(2)))
      }
    }
    guard !tables.isEmpty else { throw ImportError.noTables }
    var sheetNamesByTable: [String: NumbersFormula.Table] = [:]
    for table in tables {
      if let uid = table.model.message(39).map(tableUID) {
        sheetNamesByTable[uid] = NumbersFormula.Table(table.name, model: table.model)
      }
    }
    let merges = mergedRanges(archive)
    var sheets: [Sheet] = []
    for table in tables {
      var sheet = Sheet(name: table.name)
      if let owner = table.owner { sheet.mergedRanges = merges[owner] ?? [] }
      readCells(
        of: table.model, archive: archive,
        this: NumbersFormula.Table(table.name, model: table.model),
        tables: sheetNamesByTable, into: &sheet)
      sheet.frozenRows = Int(table.model.varint(9) ?? 0)
      sheet.frozenColumns = Int(table.model.varint(10) ?? 0)
      sheet.recomputePopulatedExtents()
      sheet.rebuildFormulaIngestIndex()
      sheets.append(sheet)
    }
    return Workbook(sheets: sheets)
  }

  /// Merged cells, by the table owning them. The calculation engine keeps them: a formula owner
  /// (`TSCE.FormulaOwnerDependenciesArchive`, 4008) of kind (3) 5 points (15) at a list (4010)
  /// of ranges, each a top-left cell (column 2, row 3) and a size (columns 1, rows 2).
  static func mergedRanges(_ archive: NumbersArchive) -> [UInt64: [CellRange]] {
    var out: [UInt64: [CellRange]] = [:]
    for id in archive.ids(ofType: 4008) {
      guard let owner = archive.message(id), owner.varint(3) == 5,
        let table = owner.message(1)?.varint(2), let listID = owner.message(15)?.reference(1),
        let list = archive.message(listID)
      else { continue }
      for entry in list.messages(2) {
        guard let region = entry.message(2) else { continue }
        let origin = region.message(1)
        let size = region.message(2)
        let col = Int(origin?.varint(2) ?? 0)
        let row = Int(origin?.varint(3) ?? 0)
        let cols = max(Int(size?.varint(1) ?? 1), 1)
        let rows = max(Int(size?.varint(2) ?? 1), 1)
        guard cols > 1 || rows > 1 else { continue }
        out[table, default: []].append(
          CellRange(
            start: CellAddress(row: row, col: col),
            end: CellAddress(row: row + rows - 1, col: col + cols - 1)))
      }
    }
    return out
  }

  enum Types {
    static let document: UInt32 = 1
    static let tableInfo: UInt32 = 6000
  }

  /// A sheet name that other apps accept: at most 31 characters, none of `[]:*?/\`, and not one
  /// already taken (compared without regard to case).
  static func uniqueName(_ name: String, taken: [String]) -> String {
    let banned = Set("[]:*?/\\")
    var base = String(name.filter { !banned.contains($0) }.prefix(31))
      .trimmingCharacters(in: .whitespaces)
    if base.isEmpty { base = "Sheet" }
    let lowered = Set(taken.map { $0.lowercased() })
    guard lowered.contains(base.lowercased()) else { return base }
    var n = 2
    while true {
      let suffix = " (\(n))"
      let candidate = String(base.prefix(31 - suffix.count)) + suffix
      if !lowered.contains(candidate.lowercased()) { return candidate }
      n += 1
    }
  }

  // MARK: Cells

  /// A table as formulas name it. Numbers gives a table a block of identifiers that differ only in
  /// their first part (a formula's is the model's field 39 less 3), so the last three parts, which
  /// are random, name the table.
  static func tableUID(_ message: ProtoMessage) -> String {
    (3...5).map { String(message.varint($0) ?? 0) }.joined(separator: "-")
  }

  /// The table model's data store (field 4): tiles (3), text (4), formulas (6), rich text (17)
  /// and formats (22).
  private static func readCells(
    of model: ProtoMessage, archive: NumbersArchive, this: NumbersFormula.Table,
    tables: [String: NumbersFormula.Table], into sheet: inout Sheet
  ) {
    guard let store = model.message(4) else { return }
    var formulas: [UInt32: [ProtoMessage]] = [:]
    if let id = store.reference(6), let list = archive.message(id) {
      for entry in list.messages(3) {
        guard let key = entry.varint(1), let nodes = entry.message(5)?.message(1) else { continue }
        formulas[UInt32(truncatingIfNeeded: key)] = nodes.messages(1)
      }
    }
    let strings = listStrings(store.reference(4), archive: archive)
    let richText = richStrings(store.reference(17), archive: archive)
    let formats = listFormats(store.reference(22), archive: archive)
    let styles = NumbersStyles(model: model, store: store, archive: archive)
    // Sizes first: in rows Numbers gave a height, its defaults (top, wrapped) show.
    NumbersStyles.applySizes(model: model, store: store, archive: archive, to: &sheet)
    let defaultHeight = CGFloat(model.double(16) ?? 20)
    let tallRows = Set(sheet.rowHeights.filter { $0.value > defaultHeight + 4 }.keys)
    let rowCount = Int(model.varint(6) ?? 0)
    let columnCount = Int(model.varint(7) ?? 0)
    guard let tiles = store.message(3) else { return }
    let tileSize = Int(tiles.varint(2) ?? 256)
    var cells: [CellAddress: Cell] = [:]
    for entry in tiles.messages(1) {
      let tileIndex = Int(entry.varint(1) ?? 0)
      guard let tileID = entry.reference(2), let tile = archive.message(tileID) else { continue }
      for rowInfo in tile.messages(5) {
        let row = tileIndex * tileSize + Int(rowInfo.varint(1) ?? 0)
        guard row < max(rowCount, 1) + tileSize else { continue }
        // Version 5 storage; older files keep a copy in fields 3 and 4 that is not read.
        guard let buffer = rowInfo.data(6), let offsets = rowInfo.data(7) else { continue }
        let wide = (rowInfo.varint(8) ?? 0) != 0
        let bytes = [UInt8](buffer)
        let offsetBytes = [UInt8](offsets)
        var col = 0
        var k = 0
        while k + 1 < offsetBytes.count {
          let raw = Int(offsetBytes[k]) | Int(offsetBytes[k + 1]) << 8
          if raw != 0xFFFF, columnCount == 0 || col < columnCount {
            let start = wide ? raw * 4 : raw
            let address = CellAddress(row: row, col: col)
            let value =
              start < bytes.count
              ? cell(
                bytes, at: start, strings: strings, richText: richText, formats: formats,
                styles: styles, tallRow: tallRows.contains(row))
              : nil
            if let id = formulaID(bytes, at: start), let nodes = formulas[id],
              let text = NumbersFormula.text(nodes, host: address, table: this, tables: tables)
            {
              cells[address] = formulaCell(
                "=" + text, result: value, errorType: bytes[start + 1] == 8)
            } else if let value {
              cells[address] = value
            }
          }
          col += 1
          k += 2
        }
      }
    }
    // Header rows and columns keep Numbers' bold and fill across the table, filled cells or not.
    let headerRows = Int(model.varint(9) ?? 0)
    let headerColumns = Int(model.varint(10) ?? 0)
    func header(_ row: Int, _ col: Int) -> CellFormat? {
      row < headerRows ? styles.headerRow : col < headerColumns ? styles.headerColumn : nil
    }
    if styles.headerRow != nil || styles.headerColumn != nil {
      for row in 0..<min(max(rowCount, 1), 100_000) {
        let lastColumn = row < headerRows ? max(columnCount, 1) : min(headerColumns, columnCount)
        for col in 0..<lastColumn {
          guard let look = header(row, col) else { continue }
          let address = CellAddress(row: row, col: col)
          var cell = cells[address] ?? Cell()
          cell.format = mergedHeader(look, under: cell.format)
          cells[address] = cell
        }
      }
    }
    NumbersStyles.applyBorders(model: model, archive: archive, to: &cells)
    sheet.replaceCells(cells)
    // Numbers grows a row to fit large text by itself and saves no height for it.
    var largest: [Int: CGFloat] = [:]
    for (address, cell) in cells where !cell.raw.isEmpty {
      if let size = cell.format?.fontSize, size > 12 {
        largest[address.row] = max(largest[address.row] ?? 0, size)
      }
    }
    for (row, size) in largest where sheet.rowHeights[row] == nil {
      sheet.rowHeights[row] = max(22, (size * 1.4).rounded(.up))
    }
  }

  /// A header cell's look under what the cell sets itself: the cell's own fill, color and
  /// alignment win; bold comes from either.
  static func mergedHeader(_ header: CellFormat, under own: CellFormat?) -> CellFormat {
    guard let own else { return header }
    var merged = own
    if merged.fillColor == nil { merged.fillColor = header.fillColor }
    if merged.textColor == nil { merged.textColor = header.textColor }
    merged.bold = merged.bold || header.bold
    merged.italic = merged.italic || header.italic
    return merged
  }

  /// A formula with the result Numbers saved, so it shows without calculating. An error keeps no
  /// result: Numbers does not say which error, so Spark Grid works it out on open.
  static func formulaCell(_ formula: String, result: Cell?, errorType: Bool) -> Cell {
    var cell = Cell(raw: formula, format: result?.format)
    guard !errorType, let result, !result.raw.isEmpty else { return cell }
    cell.importedFormulaResult = result.raw
    switch result.raw {
    case "TRUE", "FALSE": cell.importedFormulaValueType = .boolean
    default: cell.importedFormulaValueType = Double(result.raw) != nil ? .number : .string
    }
    return cell
  }

  /// The formula id of a cell that has one (flag 0x200), after the fields before it.
  static func formulaID(_ bytes: [UInt8], at start: Int) -> UInt32? {
    guard start >= 0, start + 12 <= bytes.count, bytes[start] == 5 else { return nil }
    let flags = uint32(bytes, start + 8)
    guard flags & 0x200 != 0 else { return nil }
    var offset = start + 12
    if flags & 0x1 != 0 { offset += 16 }
    if flags & 0x2 != 0 { offset += 8 }
    if flags & 0x4 != 0 { offset += 8 }
    var bit: UInt32 = 0x8
    while bit < 0x200 {
      if flags & bit != 0 { offset += 4 }
      bit <<= 1
    }
    guard offset + 4 <= bytes.count else { return nil }
    return uint32(bytes, offset)
  }

  /// One cell of version 5 storage: version, type, two reserved bytes, four more, then flags
  /// saying which fields follow, in flag order.
  static func cell(
    _ bytes: [UInt8], at start: Int, strings: [UInt32: String], richText: [UInt32: String],
    formats: [UInt32: ProtoMessage] = [:], styles: NumbersStyles? = nil, tallRow: Bool = false
  ) -> Cell? {
    guard
      let value = valueCell(
        bytes, at: start, strings: strings, richText: richText, formats: formats)
    else {
      // A cell with no value can still be filled or styled.
      guard let styles, let ids = styleIDs(bytes, at: start) else { return nil }
      var look = CellFormat()
      styles.apply(cellStyle: ids.cell, textStyle: ids.text, to: &look)
      // An empty cell needs no wrapping or alignment, only what shows: fill and the like.
      look.wrapText = false
      look.verticalAlign = .bottom
      return look == CellFormat() ? nil : Cell(raw: "", format: look)
    }
    guard let styles else { return value }
    let ids = styleIDs(bytes, at: start)
    guard ids != nil || tallRow else { return value }
    var cell = value
    var look = cell.format ?? CellFormat()
    styles.apply(cellStyle: ids?.cell, textStyle: ids?.text, to: &look, tallRow: tallRow)
    cell.format = look == CellFormat() ? nil : look
    return cell
  }

  /// The cell style (flag 0x20) and text style (0x40) ids, after the fields before them.
  static func styleIDs(_ bytes: [UInt8], at start: Int) -> (cell: UInt32?, text: UInt32?)? {
    guard start >= 0, start + 12 <= bytes.count, bytes[start] == 5 else { return nil }
    let flags = uint32(bytes, start + 8)
    guard flags & 0x60 != 0 else { return nil }
    var offset = start + 12
    if flags & 0x1 != 0 { offset += 16 }
    if flags & 0x2 != 0 { offset += 8 }
    if flags & 0x4 != 0 { offset += 8 }
    if flags & 0x8 != 0 { offset += 4 }
    if flags & 0x10 != 0 { offset += 4 }
    var cell: UInt32?
    var text: UInt32?
    if flags & 0x20 != 0, offset + 4 <= bytes.count {
      cell = uint32(bytes, offset)
      offset += 4
    }
    if flags & 0x40 != 0, offset + 4 <= bytes.count { text = uint32(bytes, offset) }
    return (cell, text)
  }

  /// The cell's value and number format, without its style.
  static func valueCell(
    _ bytes: [UInt8], at start: Int, strings: [UInt32: String], richText: [UInt32: String],
    formats: [UInt32: ProtoMessage]
  ) -> Cell? {
    guard start + 12 <= bytes.count, bytes[start] == 5 else { return nil }
    let type = bytes[start + 1]
    let flags = uint32(bytes, start + 8)
    var offset = start + 12
    var decimal: Decimal?
    var double: Double?
    var seconds: Double?
    var stringID: UInt32?
    var richID: UInt32?
    if flags & 0x1 != 0 {
      guard offset + 16 <= bytes.count else { return nil }
      decimal = decimal128(bytes, offset)
      offset += 16
    }
    if flags & 0x2 != 0 {
      guard offset + 8 <= bytes.count else { return nil }
      double = Double(bitPattern: uint64(bytes, offset))
      offset += 8
    }
    if flags & 0x4 != 0 {
      guard offset + 8 <= bytes.count else { return nil }
      seconds = Double(bitPattern: uint64(bytes, offset))
      offset += 8
    }
    if flags & 0x8 != 0, offset + 4 <= bytes.count {
      stringID = uint32(bytes, offset)
      offset += 4
    }
    if flags & 0x10 != 0, offset + 4 <= bytes.count {
      richID = uint32(bytes, offset)
      offset += 4
    }
    // Then a 4-byte id for each of these that is set, in this order: styles, formula, control,
    // suggestion, and the number, currency, date, duration, text and true/false formats.
    var ids: [UInt32: UInt32] = [:]
    var bit: UInt32 = 0x20
    while bit <= 0x40000 {
      if flags & bit != 0 {
        guard offset + 4 <= bytes.count else { break }
        ids[bit] = uint32(bytes, offset)
        offset += 4
      }
      bit <<= 1
    }
    func format(_ flag: UInt32) -> ProtoMessage? { ids[flag].flatMap { formats[$0] } }

    func number() -> Double? {
      if let decimal { return NSDecimalNumber(decimal: decimal).doubleValue }
      return double
    }

    switch type {
    case 2:  // number
      guard let value = number() else { return nil }
      return Cell(raw: text(value), format: numberFormat(format(0x2000), value: value))
    case 10:  // currency, a number with its own type since Numbers 10
      guard let value = number() else { return nil }
      return Cell(
        raw: text(value),
        format: numberFormat(format(0x4000), value: value) ?? CellFormat(numberFormat: .currency))
    case 3:  // text
      guard let stringID, let value = strings[stringID], !value.isEmpty else { return nil }
      return Cell(raw: value)
    case 5:  // date: seconds since 2001-01-01
      guard let seconds else { return nil }
      let serial = seconds / 86_400 + 36_892
      let whole = serial == serial.rounded(.down)
      let pattern = format(0x8000)?.string(14).map(excelDateCode)
      return Cell(
        raw: text(serial),
        format: CellFormat(
          numberFormat: .date,
          formatCode: pattern ?? (whole ? "mmm d, yyyy" : "mmm d, yyyy h:mm AM/PM")))
    case 6:  // true or false
      guard let value = number() else { return nil }
      return Cell(raw: value != 0 ? "TRUE" : "FALSE")
    case 7:  // duration in seconds, shown as hours and minutes
      guard let value = number() else { return nil }
      return Cell(
        raw: text(value / 86_400), format: CellFormat(numberFormat: .time, formatCode: "[h]:mm:ss"))
    case 8:  // a formula's error
      return Cell(raw: "#VALUE!")
    case 9:  // rich text
      guard let richID, let value = richText[richID], !value.isEmpty else { return nil }
      return Cell(raw: value)
    default:
      return nil
    }
  }

  /// A number's format (`TSK.FormatStructArchive`): its type (1), decimal places (2, 253 for
  /// as many as needed), currency code (3) and thousands separator (5). Nil for plain numbers.
  static func numberFormat(_ format: ProtoMessage?, value: Double) -> CellFormat? {
    guard let format, let type = format.varint(1) else { return nil }
    let decimals = format.varint(2).flatMap { $0 == 253 ? nil : Int($0) }
    let thousands = (format.varint(5) ?? 0) != 0
    func places(_ count: Int?) -> String {
      guard let count, count > 0 else { return "" }
      return "." + String(repeating: "0", count: count)
    }
    switch type {
    case 256:  // number
      guard decimals != nil || thousands else { return nil }
      let code = (thousands ? "#,##0" : "0") + places(decimals)
      return CellFormat(numberFormat: .number, formatCode: code, decimalPlaces: decimals)
    case 257:  // currency
      let symbol: String
      switch format.string(3) ?? "USD" {
      case "USD", "CAD", "AUD", "NZD", "MXN": symbol = "$"
      case "EUR": symbol = "€"
      case "GBP": symbol = "£"
      case "JPY", "CNY": symbol = "¥"
      case let code: symbol = code + " "
      }
      let code = "\"\(symbol)\"#,##0" + places(decimals ?? 2)
      return CellFormat(numberFormat: .currency, formatCode: code, decimalPlaces: decimals ?? 2)
    case 258:  // percent
      // As many places as the value needs, when the format says "auto".
      let needed = decimals ?? max(0, min(4, significantPlaces(value * 100)))
      return CellFormat(
        numberFormat: .percent, formatCode: "0" + places(needed) + "%", decimalPlaces: needed)
    case 259:  // scientific
      return CellFormat(numberFormat: .scientific, decimalPlaces: decimals ?? 2)
    default:
      return nil
    }
  }

  private static func significantPlaces(_ value: Double) -> Int {
    var places = 0
    var scaled = abs(value)
    while places < 10, abs(scaled - scaled.rounded()) > 1e-9 {
      scaled *= 10
      places += 1
    }
    return places
  }

  /// Numbers' date patterns (Unicode style, such as `M/d/yyyy h:mm a`) as an Excel format code.
  static func excelDateCode(_ pattern: String) -> String {
    var out = ""
    let chars = Array(pattern)
    var i = 0
    var inQuote = false
    while i < chars.count {
      let c = chars[i]
      if c == "'" {
        inQuote.toggle()
        i += 1
        continue
      }
      if inQuote {
        out += "\\" + String(c)
        i += 1
        continue
      }
      var run = 1
      while i + run < chars.count, chars[i + run] == c { run += 1 }
      switch c {
      case "y": out += run == 2 ? "yy" : "yyyy"
      case "M", "L": out += String(repeating: "m", count: min(run, 4))
      case "d": out += String(repeating: "d", count: min(run, 2))
      case "E": out += run >= 4 ? "dddd" : "ddd"
      case "h", "K": out += String(repeating: "h", count: min(run, 2))
      case "H", "k": out += String(repeating: "h", count: min(run, 2))
      case "m": out += String(repeating: "m", count: min(run, 2))
      case "s": out += String(repeating: "s", count: min(run, 2))
      case "a": out += "AM/PM"
      default: out += String(repeating: String(c), count: run)
      }
      i += run
    }
    return out
  }

  /// A number as the cell's raw text: whole numbers without `.0`.
  static func text(_ value: Double) -> String {
    if value == value.rounded(), abs(value) < 1e15 { return String(Int64(value)) }
    return "\(value)"
  }

  /// IEEE 754 decimal128 in binary integer form: sign, a 14-bit exponent biased by 6176, and a
  /// 113-bit coefficient. Numbers' coefficients fit the plain form.
  static func decimal128(_ bytes: [UInt8], _ offset: Int) -> Decimal {
    let low = uint64(bytes, offset)
    let high = uint64(bytes, offset + 8)
    let negative = high >> 63 == 1
    let exponent = Int((high >> 49) & 0x3FFF) - 6176
    let highCoefficient = high & 0x0001_FFFF_FFFF_FFFF
    var coefficient = Decimal(low)
    if highCoefficient != 0 {
      let twoTo64 = Decimal(UInt64.max) + 1
      coefficient += Decimal(highCoefficient) * twoTo64
    }
    return Decimal(sign: negative ? .minus : .plus, exponent: exponent, significand: coefficient)
  }

  private static func uint32(_ bytes: [UInt8], _ i: Int) -> UInt32 {
    UInt32(bytes[i]) | UInt32(bytes[i + 1]) << 8 | UInt32(bytes[i + 2]) << 16 | UInt32(bytes[i + 3])
      << 24
  }

  private static func uint64(_ bytes: [UInt8], _ i: Int) -> UInt64 {
    UInt64(uint32(bytes, i)) | UInt64(uint32(bytes, i + 4)) << 32
  }

  // MARK: Lists

  /// A format list (6005): entries (3) of a key (1) and a format (6).
  private static func listFormats(_ id: UInt64?, archive: NumbersArchive) -> [UInt32: ProtoMessage]
  {
    guard let id, let list = archive.message(id) else { return [:] }
    var out: [UInt32: ProtoMessage] = [:]
    for entry in list.messages(3) {
      if let key = entry.varint(1), let format = entry.message(6) {
        out[UInt32(truncatingIfNeeded: key)] = format
      }
    }
    return out
  }

  /// A table data list (6005): entries (3) of a key (1) and text (3).
  private static func listStrings(_ id: UInt64?, archive: NumbersArchive) -> [UInt32: String] {
    guard let id, let list = archive.message(id) else { return [:] }
    var out: [UInt32: String] = [:]
    for entry in list.messages(3) {
      if let key = entry.varint(1), let text = entry.string(3) {
        out[UInt32(truncatingIfNeeded: key)] = text
      }
    }
    return out
  }

  /// A rich text list: each entry (3) keys (1) a text storage (4) whose text is field 3.
  private static func richStrings(_ id: UInt64?, archive: NumbersArchive) -> [UInt32: String] {
    guard let id, let list = archive.message(id) else { return [:] }
    var out: [UInt32: String] = [:]
    for entry in list.messages(3) {
      guard let key = entry.varint(1), let storageID = entry.reference(4),
        let storage = archive.message(storageID)
      else { continue }
      let text = (storage.fields[3] ?? []).compactMap { value -> String? in
        if case .bytes(let d) = value { return String(decoding: d, as: UTF8.self) }
        return nil
      }.joined()
      out[UInt32(truncatingIfNeeded: key)] = text.trimmingCharacters(in: .newlines)
    }
    return out
  }
}
