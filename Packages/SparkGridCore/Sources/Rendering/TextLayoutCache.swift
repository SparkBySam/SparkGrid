import AppKit
import CoreText
import Foundation
import Model

/// Reuses Core Text lines and frames for the same text, font, color, alignment, and width.
enum TextLayoutCache {
  private static let store = Store()
  private static let cap = 4_096

  static func lineWidth(
    _ text: String,
    attributes: [NSAttributedString.Key: Any],
    font: NSFont,
    align: CellFormat.HorizontalAlign
  ) -> CGFloat {
    store.line(text: text, attributes: attributes, font: font, align: align, width: 0).width
  }

  static func drawLine(
    _ text: String,
    attributes: [NSAttributedString.Key: Any],
    font: NSFont,
    at point: NSPoint,
    align: CellFormat.HorizontalAlign
  ) {
    let entry = store.line(
      text: text, attributes: attributes, font: font, align: align, width: 0)
    draw(entry.line, at: point, ascender: font.ascender)
  }

  static func drawTruncated(
    _ text: String,
    attributes: [NSAttributedString.Key: Any],
    font: NSFont,
    in rect: NSRect,
    align: CellFormat.HorizontalAlign
  ) {
    let entry = store.line(
      text: text, attributes: attributes, font: font, align: align, width: rect.width)
    let used = min(entry.width, rect.width)
    let x: CGFloat
    switch align {
    case .center:
      x = rect.midX - used / 2
    case .right:
      x = rect.maxX - used
    case .general, .left:
      x = rect.minX
    }
    draw(entry.line, at: NSPoint(x: x, y: rect.minY), ascender: font.ascender)
  }

  static func drawWrapped(
    _ text: String,
    attributes: [NSAttributedString.Key: Any],
    font: NSFont,
    in rect: NSRect,
    align: CellFormat.HorizontalAlign
  ) {
    let frame = store.frame(
      text: text,
      attributes: attributes,
      font: font,
      align: align,
      width: rect.width,
      height: rect.height
    )
    guard let context = NSGraphicsContext.current?.cgContext else { return }
    context.saveGState()
    context.textMatrix = .identity
    if NSGraphicsContext.current?.isFlipped == true {
      context.translateBy(x: rect.minX, y: rect.maxY)
      context.scaleBy(x: 1, y: -1)
    } else {
      context.translateBy(x: rect.minX, y: rect.minY)
    }
    CTFrameDraw(frame, context)
    context.restoreGState()
  }

  private static func draw(_ line: CTLine, at point: NSPoint, ascender: CGFloat) {
    guard let context = NSGraphicsContext.current?.cgContext else { return }
    context.saveGState()
    context.textMatrix = .identity
    if NSGraphicsContext.current?.isFlipped == true {
      context.translateBy(x: point.x, y: point.y + ascender)
      context.scaleBy(x: 1, y: -1)
    } else {
      context.translateBy(x: point.x, y: point.y)
    }
    context.textMatrix = .identity
    CTLineDraw(line, context)
    context.restoreGState()
  }

  private struct Key: Hashable {
    var text: String
    var fontName: String
    var sizeMilli: Int
    var underline: Bool
    var strikethrough: Bool
    var red: UInt8
    var green: UInt8
    var blue: UInt8
    var alpha: UInt8
    var align: String
    var widthMilli: Int
    var heightMilli: Int
  }

  private struct LineEntry {
    var line: CTLine
    var width: CGFloat
    var used: UInt64
  }

  private struct FrameEntry {
    var frame: CTFrame
    var used: UInt64
  }

  private final class Store {
    let lock = NSLock()
    var lines: [Key: LineEntry] = [:]
    var frames: [Key: FrameEntry] = [:]
    var clock: UInt64 = 0

    func line(
      text: String,
      attributes: [NSAttributedString.Key: Any],
      font: NSFont,
      align: CellFormat.HorizontalAlign,
      width: CGFloat
    ) -> LineEntry {
      let key = TextLayoutCache.key(
        text: text, attributes: attributes, font: font, align: align, width: width, height: 0)
      lock.lock()
      if let existing = lines[key] {
        clock &+= 1
        var updated = existing
        updated.used = clock
        lines[key] = updated
        lock.unlock()
        return existing
      }
      lock.unlock()
      let created = TextLayoutCache.makeLine(
        text: text, attributes: attributes, font: font, width: width)
      lock.lock()
      clock &+= 1
      var stored = created
      stored.used = clock
      lines[key] = stored
      evictLines()
      lock.unlock()
      return stored
    }

    func frame(
      text: String,
      attributes: [NSAttributedString.Key: Any],
      font: NSFont,
      align: CellFormat.HorizontalAlign,
      width: CGFloat,
      height: CGFloat
    ) -> CTFrame {
      let key = TextLayoutCache.key(
        text: text,
        attributes: attributes,
        font: font,
        align: align,
        width: width,
        height: height
      )
      lock.lock()
      if let existing = frames[key] {
        clock &+= 1
        var updated = existing
        updated.used = clock
        frames[key] = updated
        lock.unlock()
        return existing.frame
      }
      lock.unlock()
      let created = TextLayoutCache.makeFrame(
        text: text, attributes: attributes, font: font, width: width, height: height)
      lock.lock()
      clock &+= 1
      frames[key] = FrameEntry(frame: created, used: clock)
      evictFrames()
      lock.unlock()
      return created
    }

    func evictLines() {
      while lines.count > cap {
        var oldest: Key?
        var used = UInt64.max
        for (key, entry) in lines where entry.used < used {
          used = entry.used
          oldest = key
        }
        guard let oldest else { return }
        lines.removeValue(forKey: oldest)
      }
    }

    func evictFrames() {
      while frames.count > cap {
        var oldest: Key?
        var used = UInt64.max
        for (key, entry) in frames where entry.used < used {
          used = entry.used
          oldest = key
        }
        guard let oldest else { return }
        frames.removeValue(forKey: oldest)
      }
    }
  }

  private static func key(
    text: String,
    attributes: [NSAttributedString.Key: Any],
    font: NSFont,
    align: CellFormat.HorizontalAlign,
    width: CGFloat,
    height: CGFloat
  ) -> Key {
    let color = (attributes[.foregroundColor] as? NSColor) ?? NSColor.labelColor
    let rgb = color.usingColorSpace(.deviceRGB) ?? color
    return Key(
      text: text,
      fontName: font.fontName,
      sizeMilli: milli(font.pointSize),
      underline: attributes[.underlineStyle] != nil,
      strikethrough: attributes[.strikethroughStyle] != nil,
      red: byte(rgb.redComponent),
      green: byte(rgb.greenComponent),
      blue: byte(rgb.blueComponent),
      alpha: byte(rgb.alphaComponent),
      align: align.rawValue,
      widthMilli: milli(width),
      heightMilli: milli(height)
    )
  }

  private static func makeLine(
    text: String,
    attributes: [NSAttributedString.Key: Any],
    font: NSFont,
    width: CGFloat
  ) -> LineEntry {
    let string = attributed(text, attributes: attributes, font: font)
    let full = CTLineCreateWithAttributedString(string)
    let line: CTLine
    if width > 1, let token = ellipsisToken(attributes: attributes, font: font),
      let truncated = CTLineCreateTruncatedLine(full, Double(width), .end, token)
    {
      line = truncated
    } else {
      line = full
    }
    var ascent: CGFloat = 0
    var descent: CGFloat = 0
    var leading: CGFloat = 0
    let measured = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
    return LineEntry(line: line, width: measured, used: 0)
  }

  private static func makeFrame(
    text: String,
    attributes: [NSAttributedString.Key: Any],
    font: NSFont,
    width: CGFloat,
    height: CGFloat
  ) -> CTFrame {
    let string = attributed(text, attributes: attributes, font: font)
    let setter = CTFramesetterCreateWithAttributedString(string)
    let path = CGPath(rect: CGRect(x: 0, y: 0, width: width, height: height), transform: nil)
    return CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), path, nil)
  }

  private static func attributed(
    _ text: String,
    attributes: [NSAttributedString.Key: Any],
    font: NSFont
  ) -> NSAttributedString {
    var copy = attributes
    let ctFont = CTFontCreateWithName(font.fontName as CFString, font.pointSize, nil)
    copy[.font] = font
    copy[kCTFontAttributeName as NSAttributedString.Key] = ctFont
    if let color = copy[.foregroundColor] as? NSColor {
      // A dynamic theme color has no stable cgColor until it is resolved. Core Text
      // then draws different pixels than AppKit. Tile drawing adopts a concrete palette
      // first, so this conversion does not touch the view appearance.
      let concrete = color.usingColorSpace(.deviceRGB) ?? color
      copy[.foregroundColor] = concrete
      copy[kCTForegroundColorAttributeName as NSAttributedString.Key] = concrete.cgColor
    }
    return NSAttributedString(string: text, attributes: copy)
  }

  private static func ellipsisToken(
    attributes: [NSAttributedString.Key: Any],
    font: NSFont
  ) -> CTLine? {
    let string = attributed("…", attributes: attributes, font: font)
    return CTLineCreateWithAttributedString(string)
  }

  private static func milli(_ value: CGFloat) -> Int {
    guard value.isFinite else { return 0 }
    let scaled = value * 1_000
    if scaled >= CGFloat(Int.max) { return Int.max }
    if scaled <= CGFloat(Int.min) { return Int.min }
    return Int(scaled.rounded())
  }

  private static func byte(_ component: CGFloat) -> UInt8 {
    let clamped = min(1, max(0, component))
    return UInt8((clamped * 255).rounded())
  }
}
