import CoreText
import Foundation
import GridCore
import Model

/// A Numbers table's look: each cell's own styles, the table's header rows and columns, and its
/// column widths and row heights. Cell styles (`TST.CellStyleArchive`, 6004) hold the fill; text
/// styles (`TSWP.ParagraphStyleArchive`, 2022) hold the font, size, color and alignment. Both are
/// in the table's style list (data store field 5), named by the ids cells carry.
nonisolated struct NumbersStyles {
  private var styles: [UInt32: (type: UInt32, message: ProtoMessage)] = [:]
  /// Header cells' look: Numbers draws header rows and columns bold on a gray fill.
  private(set) var headerRow: CellFormat?
  private(set) var headerColumn: CellFormat?

  static let cellStyle: UInt32 = 6004
  static let textStyle: UInt32 = 2022

  init(model: ProtoMessage, store: ProtoMessage, archive: NumbersArchive) {
    if let id = store.reference(5), let list = archive.message(id) {
      for entry in list.messages(3) {
        guard let key = entry.varint(1), let ref = entry.reference(4),
          let object = archive.object(ref)
        else { continue }
        styles[UInt32(truncatingIfNeeded: key)] = (object.type, ProtoMessage(object.payload))
      }
    }
    // The table's own styles: header row cells (19) and text (25), header column (20, 26).
    func region(_ cellField: Int, _ textField: Int) -> CellFormat? {
      var format = CellFormat()
      if let id = model.reference(cellField), let style = archive.message(id) {
        Self.applyCellStyle(style, to: &format)
      }
      if let id = model.reference(textField), let style = archive.message(id) {
        Self.applyTextStyle(style, to: &format, keepDefaultFont: true)
      }
      // The header's look only: wrapping and alignment follow the row, as for other cells.
      format.wrapText = false
      format.verticalAlign = .bottom
      return format == CellFormat() ? nil : format
    }
    headerRow = region(19, 25)
    headerColumn = region(20, 26)
  }

  /// The cell's own look, from its cell style and text style ids.
  /// `tallRow`: the cell is in a row Numbers gave a height. There Numbers' own defaults, text at
  /// the top and wrapped, show, so they come too unless the cell's style says otherwise.
  func apply(
    cellStyle: UInt32?, textStyle: UInt32?, to format: inout CellFormat, tallRow: Bool = false
  ) {
    var setsWrap = false
    var setsVertical = false
    if let cellStyle, let style = styles[cellStyle], style.type == Self.cellStyle {
      Self.applyCellStyle(style.message, to: &format)
      setsWrap = style.message.message(11)?.has(3) ?? false
      setsVertical = style.message.message(11)?.has(8) ?? false
    }
    if tallRow {
      if !setsVertical { format.verticalAlign = .top }
      if !setsWrap { format.wrapText = true }
    }
    if let textStyle, let style = styles[textStyle], style.type == Self.textStyle {
      Self.applyTextStyle(style.message, to: &format, keepDefaultFont: false)
    }
  }

  /// A cell style's properties (11): the fill (1, a color at 1 > 1, in sRGB), text wrapping (3)
  /// and vertical alignment (8: 0 top, 1 middle, 2 bottom).
  static func applyCellStyle(_ style: ProtoMessage, to format: inout CellFormat) {
    guard let properties = style.message(11) else { return }
    if let fill = properties.message(1)?.message(1), let color = color(fill) {
      format.fillColor = color
    }
    if let wrap = properties.varint(3) { format.wrapText = wrap != 0 }
    switch properties.varint(8) {
    case 0?: format.verticalAlign = .top
    case 1?: format.verticalAlign = .middle
    case 2?: format.verticalAlign = .bottom
    default: break
    }
  }

  /// A text style's character properties (11): bold (1), italic (2), size (3), font (5) and
  /// color (7); and paragraph properties (12): alignment (1).
  static func applyTextStyle(
    _ style: ProtoMessage, to format: inout CellFormat, keepDefaultFont: Bool
  ) {
    if let character = style.message(11) {
      if let name = character.string(5), !name.isEmpty {
        let font = CTFontCreateWithName(name as CFString, 12, nil)
        let traits = CTFontGetSymbolicTraits(font)
        if traits.contains(.traitBold) { format.bold = true }
        if traits.contains(.traitItalic) { format.italic = true }
        let family = CTFontCopyFamilyName(font) as String
        // Helvetica Neue is Spark Grid's own cell font, as it is Numbers'. A font this Mac does
        // not have comes back as another one, and is not set.
        let found = CTFontCopyPostScriptName(font) as String == name
        if !keepDefaultFont, found, family != "Helvetica Neue" {
          format.fontFamily = family
        }
      }
      if let bold = character.varint(1) { format.bold = format.bold || bold != 0 }
      if let italic = character.varint(2) { format.italic = format.italic || italic != 0 }
      if !keepDefaultFont, let size = character.float(3), size > 0 {
        format.fontSize = CGFloat(size)
      }
      if let colorMessage = character.message(7), let color = color(colorMessage),
        !(keepDefaultFont && color == CodableColor(red: 0, green: 0, blue: 0, alpha: 1))
      {
        format.textColor = color
      }
    }
    if let paragraph = style.message(12), let alignment = paragraph.varint(1) {
      switch alignment {
      case 0: format.horizontalAlign = .left
      case 1: format.horizontalAlign = .right
      case 2: format.horizontalAlign = .center
      default: break  // justified and "natural" read as general
      }
    }
  }

  /// A color (`TSP.Color`): model (1) 1 for RGB, then red (3), green (4), blue (5), alpha (6),
  /// in sRGB as Numbers' own Excel export writes them.
  static func color(_ message: ProtoMessage) -> CodableColor? {
    guard (message.varint(1) ?? 1) == 1, let r = message.float(3), let g = message.float(4),
      let b = message.float(5)
    else { return nil }
    // Rounded down to whole 0-255 steps, as Numbers' own export does.
    func clamp(_ v: Float) -> Double { (Double(min(max(v, 0), 1)) * 255).rounded(.down) / 255 }
    return CodableColor(
      red: clamp(r), green: clamp(g), blue: clamp(b), alpha: Double(message.float(6) ?? 1))
  }

  // MARK: Borders

  /// The table's own strokes, from its stroke sidecar (`TST.StrokeSidecarArchive`, model field
  /// 49): layers of top (4), bottom (5), left (6) and right (7) cell edges. Each layer is one row
  /// or column (1) with runs (2) of an origin (1), a length (2), a stroke (3) and an order (4);
  /// a later order draws over an earlier one. Gridlines are not strokes, so they do not come.
  static func applyBorders(
    model: ProtoMessage, archive: NumbersArchive, to cells: inout [CellAddress: Cell]
  ) {
    guard let id = model.reference(49), let sidecar = archive.message(id) else { return }
    enum Side { case top, bottom, left, right }
    var runs: [(order: UInt64, side: Side, cells: [CellAddress], edge: BorderEdge?)] = []
    for (field, side) in [(4, Side.top), (5, .bottom), (6, .left), (7, .right)] {
      for layerID in sidecar.references(field) {
        guard let layer = archive.message(layerID), let line = layer.varint(1) else { continue }
        for run in layer.messages(2) {
          let origin = Int(run.varint(1) ?? 0)
          let length = min(Int(run.varint(2) ?? 0), 100_000)
          guard length > 0, let stroke = run.message(3) else { continue }
          let addresses = (origin..<origin + length).map { index in
            side == .top || side == .bottom
              ? CellAddress(row: Int(line), col: index) : CellAddress(row: index, col: Int(line))
          }
          runs.append((run.varint(4) ?? 0, side, addresses, edge(stroke)))
        }
      }
    }
    for run in runs.sorted(by: { $0.order < $1.order }) {
      for address in run.cells {
        var cell = cells[address] ?? Cell()
        var format = cell.format ?? CellFormat()
        switch run.side {
        case .top: format.borders.top = run.edge
        case .bottom: format.borders.bottom = run.edge
        case .left: format.borders.left = run.edge
        case .right: format.borders.right = run.edge
        }
        cell.format = format == CellFormat() ? nil : format
        cells[address] = cell
      }
    }
  }

  /// A stroke (`TSD.StrokeArchive`): color (1), width (2) and pattern (6, type 1 for a solid
  /// line, 0 for none, with dash lengths in 4). Nil for no line.
  static func edge(_ stroke: ProtoMessage) -> BorderEdge? {
    let width = stroke.float(2) ?? 1
    let pattern = stroke.message(6)
    guard width > 0, (pattern?.varint(1) ?? 1) != 0 else { return nil }
    var style: BorderStyle = width > 2 ? .thick : width > 1 ? .medium : .thin
    if let dashes = pattern?.floats(4), let first = dashes.first, first > 0 {
      style = first < 1 ? .dotted : .dashed
    }
    let color = stroke.message(1).flatMap(color)
    return BorderEdge(style: style, color: color)
  }

  // MARK: Sizes

  /// Column widths and row heights in points, and hidden rows and columns, from the table's
  /// header buckets (`TST.HeaderStorageBucket`, 6006): each header has its index (1), size (2, 0
  /// for the table's default), hidden state (3) and cell count (4).
  static func applySizes(
    model: ProtoMessage, store: ProtoMessage, archive: NumbersArchive, to sheet: inout Sheet
  ) {
    let columns = Int(model.varint(7) ?? 0)
    let defaultWidth = model.double(17).map { CGFloat($0) }
    func headers(_ ids: [UInt64]) -> [(index: Int, size: Float, hidden: Bool)] {
      ids.compactMap { archive.message($0) }.flatMap { bucket in
        bucket.messages(2).compactMap { header in
          guard let index = header.varint(1) else { return nil }
          return (Int(index), header.float(2) ?? 0, (header.varint(3) ?? 0) != 0)
        }
      }
    }
    // Every column of the table gets Numbers' width, so it lays out as it did there.
    if let defaultWidth, defaultWidth > 0 {
      for col in 0..<min(columns, 1_000) { sheet.columnWidths[col] = defaultWidth }
    }
    var columnIDs: [UInt64] = []
    if let id = store.reference(2) { columnIDs.append(id) }
    for header in headers(columnIDs) {
      if header.size > 0 { sheet.columnWidths[header.index] = CGFloat(header.size) }
      if header.hidden { sheet.fileExtras.hiddenColumns.insert(header.index) }
    }
    let rowIDs = store.message(1)?.references(2) ?? []
    for header in headers(rowIDs) {
      if header.size > 0 { sheet.rowHeights[header.index] = CGFloat(header.size) }
      if header.hidden { sheet.fileExtras.hiddenRows.insert(header.index) }
    }
  }
}
