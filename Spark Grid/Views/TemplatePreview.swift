import AppKit
import SparkGridCore
import SwiftUI

/// The first screenful of a template as it opens: its calculated values, fills and bold text,
/// laid out by its column widths and row heights. Made once per template and drawn small.
struct TemplatePreview {
  struct Item {
    var rect: CGRect
    var text: String
    var fontSize: CGFloat
    var bold: Bool
    var alignment: CellFormat.HorizontalAlign
    var fill: CodableColor?
    var textColor: CodableColor?
  }

  /// The part of the sheet shown, in sheet points.
  static let area = CGSize(width: 600, height: 300)
  static let defaultColumnWidth: CGFloat = 80
  static let defaultRowHeight: CGFloat = 22

  var columnEdges: [CGFloat] = []
  var rowEdges: [CGFloat] = []
  var items: [Item] = []

  @MainActor private static var cache: [WorkbookTemplate: TemplatePreview] = [:]

  @MainActor
  static func preview(for template: WorkbookTemplate) -> TemplatePreview {
    if let cached = cache[template] { return cached }
    let made = make(template.makeWorkbook())
    cache[template] = made
    return made
  }

  /// An empty sheet, for Blank Workbook.
  static let blank = TemplatePreview.layout(of: Sheet(name: "Sheet1"))

  @MainActor
  static func make(_ workbook: Workbook) -> TemplatePreview {
    let sheet = workbook.sheets[0]
    let engine = FormulaEngine()
    engine.recalculateEntireWorkbook(workbook, profile: false)
    let results = engine.formulaResults(on: sheet)
    var preview = layout(of: sheet)
    for (address, cell) in sheet.cells {
      guard address.col < preview.columnEdges.count - 1, address.row < preview.rowEdges.count - 1
      else { continue }
      let format = cell.format
      var text: String
      var isNumber = false
      if FormulaSyntax.isFormula(cell.raw) {
        let value = results[address] ?? .blank
        if case .number = value { isNumber = true }
        text = CellFormatRenderer.displayText(for: value, format: format, fallbackRaw: cell.raw)
      } else {
        isNumber = Double(cell.raw) != nil
        text = CellFormatRenderer.displayText(raw: cell.raw, format: format)
      }
      if text.isEmpty && format?.fillColor == nil { continue }
      let rect = CGRect(
        x: preview.columnEdges[address.col], y: preview.rowEdges[address.row],
        width: preview.columnEdges[address.col + 1] - preview.columnEdges[address.col],
        height: preview.rowEdges[address.row + 1] - preview.rowEdges[address.row])
      var alignment = format?.horizontalAlign ?? .general
      if alignment == .general { alignment = isNumber ? .right : .left }
      preview.items.append(
        Item(
          rect: rect, text: text, fontSize: format?.fontSize ?? 12, bold: format?.bold ?? false,
          alignment: alignment, fill: format?.fillColor, textColor: format?.textColor))
    }
    // Fills first, so text that runs into the next cell is drawn over them.
    preview.items.sort { ($0.fill != nil ? 0 : 1) < ($1.fill != nil ? 0 : 1) }
    return preview
  }

  private static func layout(of sheet: Sheet) -> TemplatePreview {
    var preview = TemplatePreview()
    var x: CGFloat = 0
    var col = 0
    preview.columnEdges = [0]
    while x < area.width {
      x += sheet.columnWidths[col] ?? defaultColumnWidth
      preview.columnEdges.append(x)
      col += 1
    }
    var y: CGFloat = 0
    var row = 0
    preview.rowEdges = [0]
    while y < area.height {
      y += sheet.rowHeights[row] ?? defaultRowHeight
      preview.rowEdges.append(y)
      row += 1
    }
    return preview
  }
}

/// Draws a `TemplatePreview` to fit its frame's width, in the window's light or dark look.
struct TemplatePreviewCanvas: View {
  let preview: TemplatePreview
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    Canvas { context, size in
      let scale = size.width / TemplatePreview.area.width
      context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(SparkStyle.canvas))
      context.scaleBy(x: scale, y: scale)
      let gridLine = Color(nsColor: SparkTheme.gridLine).opacity(0.6)
      let lineWidth = 1 / scale
      for x in preview.columnEdges.dropFirst() {
        context.fill(
          Path(CGRect(x: x, y: 0, width: lineWidth, height: TemplatePreview.area.height + 40)),
          with: .color(gridLine))
      }
      for y in preview.rowEdges.dropFirst() {
        context.fill(
          Path(CGRect(x: 0, y: y, width: TemplatePreview.area.width + 80, height: lineWidth)),
          with: .color(gridLine))
      }
      for item in preview.items {
        if let fill = item.fill {
          context.fill(Path(item.rect), with: .color(color(fill)))
        }
      }
      for item in preview.items where !item.text.isEmpty {
        let font = Font.custom("Helvetica Neue", size: item.fontSize)
          .weight(item.bold ? .bold : .regular)
        let text = Text(item.text).font(font).foregroundStyle(textColor(item))
        let inset: CGFloat = 4
        let point: CGPoint
        let anchor: UnitPoint
        switch item.alignment {
        case .right:
          point = CGPoint(x: item.rect.maxX - inset, y: item.rect.midY)
          anchor = .trailing
        case .center:
          point = CGPoint(x: item.rect.midX, y: item.rect.midY)
          anchor = .center
        default:
          point = CGPoint(x: item.rect.minX + inset, y: item.rect.midY)
          anchor = .leading
        }
        context.draw(text, at: point, anchor: anchor)
      }
    }
  }

  private func color(_ c: CodableColor) -> Color {
    Color(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: c.alpha)
  }

  /// As the grid draws it: the cell's own color, else black on a light fill in dark mode, else
  /// the theme's text color.
  private func textColor(_ item: TemplatePreview.Item) -> Color {
    if let text = item.textColor { return color(text) }
    if let fill = item.fill, colorScheme == .dark, fill.relativeLuminance > 0.5 {
      return .black
    }
    return SparkStyle.label
  }
}
