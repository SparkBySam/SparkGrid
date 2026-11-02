import AppKit
import Calc
import CoreText
import Formula
import Foundation
import GridCore
import Model
import NumberFormat

public enum CellFormatRenderer {
  public static let defaultFontSize: CGFloat = 12
  public static let defaultFontFamily = "Helvetica Neue"

  public static let fontFamilies = [
    "Helvetica Neue",
    "Helvetica",
    "Arial",
    "Times New Roman",
    "Georgia",
    "Courier New",
    "Menlo",
  ]

  public static func displayText(raw: String, format: CellFormat?) -> String {
    guard let format, !raw.isEmpty else { return raw }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let parsed = parseNumber(trimmed) else {
      if let rendered = renderedText(trimmed, format) {
        return rendered
      }
      return raw
    }
    let number = parsed == 0 ? 0 : parsed

    if let rendered = renderedFormat(number, format) {
      return rendered
    }
    let places = format.decimalPlaces ?? decimalPlaces(for: format.numberFormat)
    switch format.numberFormat {
    case .general:
      return raw
    case .number:
      return formatNumber(number, places: places)
    case .currency:
      return formatCurrency(number, places: places)
    case .percent:
      // parseNumber strips `%`; recover Excel fraction semantics when raw was a percent literal.
      let value = trimmed.hasSuffix("%") ? number / 100 : number
      return formatPercent(value, places: places)
    case .scientific:
      return String(format: "%.\(places)e", number)
    case .date, .time:
      return raw
    }
  }

  /// Format an evaluated formula/literal value for display.
  public static func displayText(for value: CellValue, format: CellFormat?, fallbackRaw: String)
    -> String
  {
    switch value {
    case .error:
      return value.displayString
    case .blank:
      return ""
    case .bool:
      return value.displayString
    case .string(let text):
      if let rendered = renderedText(text, format) {
        return rendered
      }
      return value.displayString
    case .number(let signedNumber):
      // Negative zero (a rounding difference, or "-0" cached in a file) shows as zero, as in
      // other spreadsheet apps, not "-$0" or "(0)".
      let number = signedNumber == 0 ? 0 : signedNumber
      let trimmed = fallbackRaw.trimmingCharacters(in: .whitespacesAndNewlines)
      let literalPercent = trimmed.hasSuffix("%") && !trimmed.hasPrefix("=")
      let resolvedFormat: CellFormat? = {
        if let format, format.numberFormat != .general { return format }
        if literalPercent {
          var inferred = format ?? CellFormat()
          inferred.numberFormat = .percent
          return inferred
        }
        return format
      }()
      guard let resolvedFormat else { return value.displayString }
      if let rendered = renderedFormat(number, resolvedFormat) {
        return rendered
      }
      let places = resolvedFormat.decimalPlaces ?? decimalPlaces(for: resolvedFormat.numberFormat)
      switch resolvedFormat.numberFormat {
      case .general:
        return value.displayString
      case .number:
        return formatNumber(number, places: places)
      case .currency:
        return formatCurrency(number, places: places)
      case .percent:
        return formatPercent(number, places: places)
      case .scientific:
        return String(format: "%.\(places)e", number)
      case .date:
        return formatDate(number)
      case .time:
        return formatTime(number)
      }
    }
  }

  public static func lineBreakMode(for format: CellFormat?) -> NSLineBreakMode {
    switch (format ?? CellFormat()).textDisplay {
    case .overflow:
      return .byClipping
    case .wrap, .clip:
      return .byWordWrapping
    }
  }

  /// Clip keeps the previous ellipsis. Overflow and wrap do not.
  public static func showsEllipsis(_ format: CellFormat?) -> Bool {
    (format ?? CellFormat()).textDisplay == .clip
  }

  public static func attributes(for format: CellFormat?, onLightBackground: Bool = false)
    -> [NSAttributedString.Key: Any]
  {
    let resolved = format ?? CellFormat()
    let fallback = onLightBackground ? NSColor.black : SparkTheme.label
    let textColor = nsColor(resolved.textColor) ?? fallback
    var attrs: [NSAttributedString.Key: Any] = [
      .font: font(for: resolved),
      .foregroundColor: textColor,
    ]

    if resolved.underline {
      attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
    }
    if resolved.strikethrough {
      attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
    }

    let paragraph = NSMutableParagraphStyle()
    switch resolved.horizontalAlign {
    case .general, .left: paragraph.alignment = .left
    case .center: paragraph.alignment = .center
    case .right: paragraph.alignment = .right
    }
    paragraph.lineBreakMode = lineBreakMode(for: resolved)
    attrs[.paragraphStyle] = paragraph

    return attrs
  }

  public static func drawSingleLineText(
    _ text: String,
    in rect: NSRect,
    format: CellFormat?,
    onLightBackground: Bool = false
  ) {
    guard !text.isEmpty else { return }
    let resolved = format ?? CellFormat()
    if resolved.isStackedVertically || resolved.textRotation != 0 {
      drawText(text, in: rect, format: format, onLightBackground: onLightBackground)
      return
    }
    var attrs = attributes(for: format, onLightBackground: onLightBackground)
    let paragraph =
      ((attrs[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy()
        as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
    paragraph.lineBreakMode = .byTruncatingTail
    attrs[.paragraphStyle] = paragraph

    let size = (text as NSString).size(withAttributes: attrs)
    var drawRect = rect
    drawRect.size.height = max(size.height, 1)
    drawRect.origin.y += (rect.height - drawRect.height) / 2

    (text as NSString).draw(
      with: drawRect,
      options: [.usesLineFragmentOrigin, .usesFontLeading],
      attributes: attrs
    )
  }

  public static func drawCenteredLabel(
    _ text: String,
    in rect: NSRect,
    font: NSFont,
    color: NSColor
  ) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: color,
      .paragraphStyle: paragraph,
    ]
    (text as NSString).draw(
      with: rect,
      options: [.usesLineFragmentOrigin, .usesFontLeading],
      attributes: attrs
    )
  }

  public static func drawText(
    _ text: String,
    in cellRect: NSRect,
    format: CellFormat?,
    onLightBackground: Bool = false,
    verticalAlign: CellFormat.VerticalAlign? = nil
  ) {
    let resolved = format ?? CellFormat()
    if resolved.textRotation != 0 || resolved.isStackedVertically {
      drawTextUncached(
        text,
        in: cellRect,
        format: format,
        onLightBackground: onLightBackground,
        verticalAlign: verticalAlign
      )
      return
    }
    guard !text.isEmpty else { return }
    let attrs = attributes(for: format, onLightBackground: onLightBackground)
    let inset = cellRect.insetBy(dx: 4, dy: 2)
    guard inset.width > 1, inset.height > 1 else { return }
    let font = attrs[.font] as? NSFont ?? Self.font(for: resolved)
    if resolved.textDisplay == .wrap {
      TextLayoutCache.drawWrapped(
        text,
        attributes: attrs,
        font: font,
        in: inset,
        align: resolved.horizontalAlign
      )
      return
    }
    if Self.showsEllipsis(resolved) {
      TextLayoutCache.drawTruncated(
        text,
        attributes: attrs,
        font: font,
        in: inset,
        align: resolved.horizontalAlign
      )
      return
    }
    let alignment = verticalAlign ?? resolved.verticalAlign
    let lineHeight = font.ascender - font.descender
    let point: NSPoint
    if resolved.horizontalAlign == .general || resolved.horizontalAlign == .left {
      var origin = inset.origin
      switch alignment {
      case .top: break
      case .middle: origin.y = inset.midY - lineHeight / 2
      case .bottom: origin.y = inset.maxY - lineHeight
      }
      point = origin
    } else {
      let width = TextLayoutCache.lineWidth(
        text, attributes: attrs, font: font, align: resolved.horizontalAlign)
      let size = NSSize(width: width, height: lineHeight)
      point = alignedOrigin(
        for: size, in: inset, horizontalAlign: resolved.horizontalAlign, verticalAlign: alignment)
    }
    TextLayoutCache.drawLine(
      text, attributes: attrs, font: font, at: point, align: resolved.horizontalAlign)
  }

  /// The drawing path from before the text-layout cache. Tests compare pixels against it.
  static func drawTextUncached(
    _ text: String,
    in cellRect: NSRect,
    format: CellFormat?,
    onLightBackground: Bool = false,
    verticalAlign: CellFormat.VerticalAlign? = nil
  ) {
    let resolved = format ?? CellFormat()
    let attrs = attributes(for: format, onLightBackground: onLightBackground)
    let inset = cellRect.insetBy(dx: 4, dy: 2)
    guard inset.width > 1, inset.height > 1 else { return }

    // Wrap and clip paint through the text cache. AppKit's rect draw would put a
    // second line in a tall cell, which is not the single-line clip the grid uses.
    if resolved.textDisplay == .wrap {
      let font = attrs[.font] as? NSFont ?? Self.font(for: resolved)
      TextLayoutCache.drawWrapped(
        text, attributes: attrs, font: font, in: inset, align: resolved.horizontalAlign)
      return
    }

    if Self.showsEllipsis(resolved) {
      let font = attrs[.font] as? NSFont ?? Self.font(for: resolved)
      TextLayoutCache.drawTruncated(
        text, attributes: attrs, font: font, in: inset, align: resolved.horizontalAlign)
      return
    }

    let alignment = verticalAlign ?? resolved.verticalAlign
    if resolved.isStackedVertically {
      drawStackedVerticalText(
        text,
        in: inset,
        attributes: attrs,
        horizontalAlign: resolved.horizontalAlign,
        verticalAlign: alignment
      )
      return
    }

    // Fast path: left-aligned, no rotation — skip size measurement.
    if resolved.textRotation == 0,
      resolved.horizontalAlign == .general || resolved.horizontalAlign == .left
    {
      let font = attrs[.font] as? NSFont ?? Self.font(for: resolved)
      let height = font.ascender - font.descender
      var point = inset.origin
      switch alignment {
      case .top: break
      case .middle: point.y = inset.midY - height / 2
      case .bottom: point.y = inset.maxY - height
      }
      (text as NSString).draw(at: point, withAttributes: attrs)
      return
    }

    let measured = (text as NSString).size(withAttributes: attrs)
    let font = attrs[.font] as? NSFont ?? Self.font(for: resolved)
    let size = NSSize(width: measured.width, height: font.ascender - font.descender)
    let point = alignedOrigin(
      for: size, in: inset, horizontalAlign: resolved.horizontalAlign, verticalAlign: alignment)

    if resolved.textRotation != 0 {
      NSGraphicsContext.saveGraphicsState()
      let center = NSPoint(x: inset.midX, y: inset.midY)
      let transform = NSAffineTransform()
      transform.translateX(by: center.x, yBy: center.y)
      transform.rotate(byDegrees: CGFloat(resolved.textRotation))
      transform.translateX(by: -center.x, yBy: -center.y)
      transform.concat()
      (text as NSString).draw(at: point, withAttributes: attrs)
      NSGraphicsContext.restoreGraphicsState()
    } else {
      (text as NSString).draw(at: point, withAttributes: attrs)
    }
  }

  public static func measuredBoundingSize(for text: String, format: CellFormat?) -> NSSize {
    guard !text.isEmpty else { return .zero }
    let resolved = format ?? CellFormat()
    let attrs = attributes(for: format)
    let size = (text as NSString).size(withAttributes: attrs)
    guard !resolved.wrapText else { return size }

    if resolved.isStackedVertically {
      let font = attrs[.font] as? NSFont ?? Self.font(for: resolved)
      let lineHeight = font.ascender - font.descender + 1
      var maxWidth: CGFloat = 0
      for ch in text {
        let width = (String(ch) as NSString).size(withAttributes: attrs).width
        maxWidth = max(maxWidth, width)
      }
      return NSSize(width: maxWidth, height: lineHeight * CGFloat(text.count))
    }

    guard resolved.textRotation != 0 else { return size }

    // Axis-aligned bounds of text rotated within the cell (matches drawText rotation).
    let radians = CGFloat(resolved.textRotation) * .pi / 180
    let cosA = abs(cos(radians))
    let sinA = abs(sin(radians))
    return NSSize(
      width: size.width * cosA + size.height * sinA,
      height: size.width * sinA + size.height * cosA
    )
  }

  public static func measuredWidth(for text: String, format: CellFormat?) -> CGFloat {
    measuredBoundingSize(for: text, format: format).width
  }

  /// Width of one unwrapped line, from glyph advances. Kerning can make the
  /// drawn line slightly narrower, so a spill clip based on this does not cut
  /// off the last glyph. Wrapped, rotated, and stacked text keep the typesetter.
  public static func overflowWidth(for text: String, format: CellFormat?) -> CGFloat {
    guard !text.isEmpty else { return 0 }
    let resolved = format ?? CellFormat()
    if resolved.wrapText || resolved.textRotation != 0 || resolved.isStackedVertically {
      return measuredWidth(for: text, format: format)
    }
    let font = font(for: resolved)
    if let width = GlyphAdvances.shared.width(of: text, font: font) {
      return width
    }
    return measuredWidth(for: text, format: format)
  }

  public static func measuredHeight(for text: String, format: CellFormat?) -> CGFloat {
    measuredBoundingSize(for: text, format: format).height
  }

  private static func drawStackedVerticalText(
    _ text: String,
    in rect: NSRect,
    attributes attrs: [NSAttributedString.Key: Any],
    horizontalAlign: CellFormat.HorizontalAlign,
    verticalAlign: CellFormat.VerticalAlign
  ) {
    let font = attrs[.font] as? NSFont ?? NSFont.systemFont(ofSize: defaultFontSize)
    let characters = Array(text)
    guard !characters.isEmpty else { return }

    let lineHeight = font.ascender - font.descender + 1
    let charWidths = characters.map { (String($0) as NSString).size(withAttributes: attrs).width }
    let blockHeight = lineHeight * CGFloat(characters.count)

    let blockTopY: CGFloat
    switch verticalAlign {
    case .top:
      blockTopY = rect.maxY
    case .middle:
      blockTopY = rect.midY + blockHeight / 2
    case .bottom:
      blockTopY = rect.minY + blockHeight
    }

    for (index, ch) in characters.enumerated() {
      let chWidth = charWidths[index]
      let x: CGFloat
      switch horizontalAlign {
      case .center, .general:
        x = rect.midX - chWidth / 2
      case .left:
        x = rect.minX
      case .right:
        x = rect.maxX - chWidth
      }
      let y = blockTopY - font.ascender - CGFloat(index) * lineHeight
      (String(ch) as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: attrs)
    }
  }

  private static func alignedOrigin(
    for size: NSSize,
    in rect: NSRect,
    horizontalAlign: CellFormat.HorizontalAlign,
    verticalAlign: CellFormat.VerticalAlign
  ) -> NSPoint {
    let x: CGFloat
    switch horizontalAlign {
    case .center:
      x = rect.midX - size.width / 2
    case .right:
      x = rect.maxX - size.width
    default:
      x = rect.minX
    }

    let y: CGFloat
    switch verticalAlign {
    case .top:
      y = rect.minY
    case .middle:
      y = rect.midY - size.height / 2
    case .bottom:
      y = rect.maxY - size.height
    }

    return NSPoint(x: x, y: y)
  }

  private static let fontLock = NSLock()
  private static var fontCache: [String: NSFont] = [:]

  public static func font(for format: CellFormat) -> NSFont {
    let family = format.fontFamily ?? defaultFontFamily
    let size = format.fontSize ?? defaultFontSize
    let key = "\(family)|\(size)|\(format.bold ? 1 : 0)|\(format.italic ? 1 : 0)"
    fontLock.lock()
    if let cached = fontCache[key] {
      fontLock.unlock()
      return cached
    }
    fontLock.unlock()

    var font = NSFont(name: family, size: size) ?? NSFont.systemFont(ofSize: size)
    if format.bold && format.italic {
      font = NSFontManager.shared.convert(font, toHaveTrait: [.boldFontMask, .italicFontMask])
    } else if format.bold {
      font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
    } else if format.italic {
      font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
    }
    fontLock.lock()
    fontCache[key] = font
    fontLock.unlock()
    return font
  }

  public static func fillColor(for format: CellFormat?) -> NSColor? {
    guard let color = format?.fillColor else { return nil }
    return nsColor(color)
  }

  public static func nsColor(_ color: CodableColor?) -> NSColor? {
    guard let color else { return nil }
    return NSColor(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
  }

  public static func codableColor(from color: NSColor) -> CodableColor {
    let rgb = color.usingColorSpace(.sRGB) ?? color
    return CodableColor(
      red: Double(rgb.redComponent),
      green: Double(rgb.greenComponent),
      blue: Double(rgb.blueComponent),
      alpha: Double(rgb.alphaComponent)
    )
  }

  // MARK: - Number helpers

  private static func renderedFormat(_ number: Double, _ format: CellFormat) -> String? {
    guard let code = format.formatCode else { return nil }
    return ExcelFormatCode.formatted(number, code: code, fractionDigits: format.decimalPlaces)
  }

  private static func renderedText(_ text: String, _ format: CellFormat?) -> String? {
    guard let code = format?.formatCode else { return nil }
    return ExcelFormatCode.formattedText(text, code: code)
  }

  private static func parseNumber(_ text: String) -> Double? {
    let stripped =
      text
      .replacingOccurrences(of: "$", with: "")
      .replacingOccurrences(of: "%", with: "")
      .replacingOccurrences(of: ",", with: "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return Double(stripped)
  }

  private static func decimalPlaces(for format: CellFormat.NumberFormat) -> Int {
    switch format {
    case .general: return 0
    case .number, .currency: return 2
    case .percent: return 2
    case .scientific: return 2
    case .date, .time: return 0
    }
  }

  private static func formatNumber(_ value: Double, places: Int) -> String {
    String(format: "%.\(places)f", value)
  }

  private static func formatCurrency(_ value: Double, places: Int) -> String {
    "$" + String(format: "%.\(places)f", value)
  }

  private static func formatPercent(_ value: Double, places: Int) -> String {
    // Excel stores percentages as fractions (0.5 → 50%). Always scale for display.
    String(format: "%.\(places)f%%", value * 100)
  }

  private static let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "M/d/yyyy"
    return formatter
  }()

  private static let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "h:mm:ss a"
    return formatter
  }()

  private static func formatDate(_ serial: Double) -> String {
    guard let date = ExcelDate.date(from: serial) else {
      return String(serial)
    }
    return dateFormatter.string(from: date)
  }

  private static func formatTime(_ serial: Double) -> String {
    // Excel times are day fractions; full datetimes still show the time component.
    let fraction = serial.truncatingRemainder(dividingBy: 1)
    let dayFraction = fraction < 0 ? fraction + 1 : fraction
    guard let date = ExcelDate.date(from: dayFraction) else {
      return String(serial)
    }
    return timeFormatter.string(from: date)
  }
}

extension CellFormatRenderer {
  public static func borderColor(for edge: BorderEdge) -> NSColor {
    if let color = edge.color, let ns = nsColor(color) {
      return ns
    }
    return SparkTheme.cellBorder
  }

  public static func drawBorders(_ borders: CellBorders, in rect: NSRect, scale: CGFloat = 1) {
    drawBordersBatch([(borders, rect)], scale: scale)
  }

  /// Batched border drawing. Shared edges are deduped and collinear runs are merged into
  /// long spans so a dense “all borders” / double-border grid paints like gridlines
  /// (O(rows+cols) strokes) instead of O(cells) short segments.
  public static func drawBordersBatch(_ items: [(CellBorders, NSRect)], scale: CGFloat = 1) {
    guard !items.isEmpty else { return }

    struct LineKey: Hashable {
      var vertical: Bool
      var major: Int
      var style: BorderStyle
      var colorKey: UInt64
    }

    // major → list of [start,end] quanta along the line
    var runs: [LineKey: [(Int, Int)]] = [:]
    runs.reserveCapacity(min(items.count, 512))

    func colorKey(for edge: BorderEdge) -> UInt64 {
      guard let c = edge.color else { return 0 }
      let r = UInt64((c.red * 255).rounded())
      let g = UInt64((c.green * 255).rounded())
      let b = UInt64((c.blue * 255).rounded())
      let a = UInt64((c.alpha * 255).rounded())
      return (r << 24) | (g << 16) | (b << 8) | a
    }

    func quantize(_ value: CGFloat) -> Int {
      Int((value * 2).rounded())
    }

    func dequantize(_ value: Int) -> CGFloat {
      CGFloat(value) * 0.5
    }

    func append(_ edge: BorderEdge?, vertical: Bool, major: CGFloat, from: CGFloat, to: CGFloat) {
      guard let edge else { return }
      let a0 = quantize(from)
      let b0 = quantize(to)
      let a = min(a0, b0)
      let b = max(a0, b0)
      guard b > a else { return }
      let key = LineKey(
        vertical: vertical,
        major: quantize(major),
        style: edge.style,
        colorKey: colorKey(for: edge)
      )
      runs[key, default: []].append((a, b))
    }

    for (borders, rect) in items {
      guard borders.hasAny else { continue }
      append(borders.top, vertical: false, major: rect.minY, from: rect.minX, to: rect.maxX)
      append(borders.bottom, vertical: false, major: rect.maxY, from: rect.minX, to: rect.maxX)
      append(borders.left, vertical: true, major: rect.minX, from: rect.minY, to: rect.maxY)
      append(borders.right, vertical: true, major: rect.maxX, from: rect.minY, to: rect.maxY)
    }

    func mergeIntervals(_ intervals: [(Int, Int)]) -> [(Int, Int)] {
      guard !intervals.isEmpty else { return [] }
      let sorted = intervals.sorted { lhs, rhs in
        if lhs.0 != rhs.0 { return lhs.0 < rhs.0 }
        return lhs.1 < rhs.1
      }
      var merged: [(Int, Int)] = []
      merged.reserveCapacity(sorted.count)
      var current = sorted[0]
      for i in 1..<sorted.count {
        let next = sorted[i]
        // Allow 1-quantum gaps so adjacent cell edges fuse into one span.
        if next.0 <= current.1 + 1 {
          current.1 = max(current.1, next.1)
        } else {
          merged.append(current)
          current = next
        }
      }
      merged.append(current)
      return merged
    }

    func strokeColor(for key: LineKey) -> NSColor {
      if key.colorKey == 0 {
        return SparkTheme.cellBorder
      }
      let r = CGFloat((key.colorKey >> 24) & 0xFF) / 255
      let g = CGFloat((key.colorKey >> 16) & 0xFF) / 255
      let b = CGFloat((key.colorKey >> 8) & 0xFF) / 255
      let a = CGFloat(key.colorKey & 0xFF) / 255
      return NSColor(red: r, green: g, blue: b, alpha: a)
    }

    guard let cg = NSGraphicsContext.current?.cgContext else { return }
    cg.saveGState()
    cg.setShouldAntialias(false)

    for (key, intervals) in runs {
      let merged = mergeIntervals(intervals)
      guard !merged.isEmpty else { continue }
      let color = strokeColor(for: key)
      cg.setStrokeColor(color.cgColor)
      let major = dequantize(key.major)

      switch key.style {
      case .double:
        let inset = 1.5 * scale
        cg.setLineWidth(max(0.5, 1 * scale))
        cg.beginPath()
        for (a, b) in merged {
          let start = dequantize(a)
          let end = dequantize(b)
          if key.vertical {
            cg.move(to: CGPoint(x: major - inset, y: start))
            cg.addLine(to: CGPoint(x: major - inset, y: end))
            cg.move(to: CGPoint(x: major + inset, y: start))
            cg.addLine(to: CGPoint(x: major + inset, y: end))
          } else {
            cg.move(to: CGPoint(x: start, y: major - inset))
            cg.addLine(to: CGPoint(x: end, y: major - inset))
            cg.move(to: CGPoint(x: start, y: major + inset))
            cg.addLine(to: CGPoint(x: end, y: major + inset))
          }
        }
        cg.strokePath()

      case .dashed, .dotted:
        // Dashes still use NSBezierPath (CG dash + many spans is awkward here).
        let path = NSBezierPath()
        let width = max(0.5, key.style.lineWidth * scale)
        path.lineWidth = width
        if key.style == .dashed {
          path.setLineDash([3 * scale, 2 * scale], count: 2, phase: 0)
        } else {
          path.lineCapStyle = .round
          path.setLineDash([0.5 * scale, 2 * scale], count: 2, phase: 0)
        }
        color.setStroke()
        for (a, b) in merged {
          let start = dequantize(a)
          let end = dequantize(b)
          if key.vertical {
            path.move(to: NSPoint(x: major, y: start))
            path.line(to: NSPoint(x: major, y: end))
          } else {
            path.move(to: NSPoint(x: start, y: major))
            path.line(to: NSPoint(x: end, y: major))
          }
        }
        path.stroke()

      case .thin, .medium, .thick:
        let width = max(0.5, key.style.lineWidth * scale)
        cg.setLineWidth(max(width, 1.25 * scale))
        cg.beginPath()
        for (a, b) in merged {
          let start = dequantize(a)
          let end = dequantize(b)
          if key.vertical {
            cg.move(to: CGPoint(x: major, y: start))
            cg.addLine(to: CGPoint(x: major, y: end))
          } else {
            cg.move(to: CGPoint(x: start, y: major))
            cg.addLine(to: CGPoint(x: end, y: major))
          }
        }
        cg.strokePath()
      }
    }

    cg.restoreGState()
  }
}

/// Per-font glyph advances for overflow clips. One table is shared by every tile.
private final class GlyphAdvances {
  static let shared = GlyphAdvances()

  private let lock = NSLock()
  private var tables: [AdvanceKey: AdvanceTable] = [:]

  func width(of text: String, font: NSFont) -> CGFloat? {
    let key = AdvanceKey(font: font)
    lock.lock()
    let table: AdvanceTable
    if let existing = tables[key] {
      table = existing
    } else {
      table = AdvanceTable(font: font)
      tables[key] = table
    }
    let measured = table.width(of: text)
    lock.unlock()
    return measured
  }
}

private struct AdvanceKey: Hashable {
  var name: String
  var sizeMilli: Int
  var bold: Bool
  var italic: Bool

  init(font: NSFont) {
    name = font.fontName
    let scaled = font.pointSize * 1_000
    if scaled >= CGFloat(Int.max) {
      sizeMilli = Int.max
    } else if scaled <= CGFloat(Int.min) {
      sizeMilli = Int.min
    } else {
      sizeMilli = Int(scaled.rounded())
    }
    let traits = font.fontDescriptor.symbolicTraits
    bold = traits.contains(.bold)
    italic = traits.contains(.italic)
  }
}

private final class AdvanceTable {
  let font: CTFont
  var ascii: [CGFloat]
  var more: [UInt16: CGFloat] = [:]

  init(font: NSFont) {
    self.font = CTFontCreateWithFontDescriptor(font.fontDescriptor, font.pointSize, nil)
    ascii = [CGFloat](repeating: -1, count: 128)
  }

  func width(of text: String) -> CGFloat? {
    var total: CGFloat = 0
    for scalar in text.unicodeScalars {
      let value = scalar.value
      if value > 0xFFFF { return nil }
      let unit = UInt16(value)
      let advance: CGFloat
      if unit < 128 {
        let index = Int(unit)
        if ascii[index] < 0 {
          guard let measured = Self.measure(font, unit) else { return nil }
          ascii[index] = measured
        }
        advance = ascii[index]
      } else if let cached = more[unit] {
        advance = cached
      } else {
        guard let measured = Self.measure(font, unit) else { return nil }
        more[unit] = measured
        advance = measured
      }
      total += advance
    }
    return total
  }

  private static func measure(_ font: CTFont, _ unit: UInt16) -> CGFloat? {
    var chars = [UniChar(unit)]
    var glyph = CGGlyph(0)
    guard CTFontGetGlyphsForCharacters(font, &chars, &glyph, 1), glyph != 0 else {
      return nil
    }
    var advance = CGSize.zero
    CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, &advance, 1)
    return advance.width
  }
}
