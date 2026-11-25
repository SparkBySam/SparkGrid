import AppKit
import SparkGridCore

/// Draws the sparklines of the cells in view, over the grid and under charts. It takes no
/// clicks; they reach the cells under it.
final class SparklineLayerView: NSView {
  struct Item: Equatable {
    var rect: NSRect
    var values: [Double?]
    var kind: SparklineGroup.Kind
    var colorHex: String
    var negativeColorHex: String
    var showsMarkers: Bool
    var showsHighLow: Bool
    var showsNegative: Bool
  }

  var items: [Item] = [] {
    didSet { if items != oldValue { needsDisplay = true } }
  }
  var scale: CGFloat = 1

  override var isFlipped: Bool { true }
  override var isOpaque: Bool { false }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  override func draw(_ dirtyRect: NSRect) {
    for item in items where item.rect.intersects(dirtyRect) {
      Self.draw(item, scale: scale)
    }
  }

  static func color(_ hex: String) -> NSColor {
    let digits = hex.filter(\.isHexDigit)
    guard digits.count == 6, let value = Int(digits, radix: 16) else { return .systemBlue }
    return NSColor(
      srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
      blue: CGFloat(value & 0xFF) / 255, alpha: 1)
  }

  /// One sparkline inside its cell, with a little room at the edges.
  static func draw(_ item: Item, scale: CGFloat) {
    let box = item.rect.insetBy(dx: 3 * scale, dy: 3 * scale)
    let points = item.values.enumerated().compactMap { index, value in
      value.map { (index, $0) }
    }
    guard box.width > 2, box.height > 2, !points.isEmpty else { return }
    let series = color(item.colorHex)
    let negative = color(item.negativeColorHex)
    let count = item.values.count
    let numbers = points.map(\.1)
    let high = numbers.max() ?? 0
    let low = numbers.min() ?? 0

    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(rect: item.rect).addClip()
    defer { NSGraphicsContext.restoreGraphicsState() }

    switch item.kind {
    case .line:
      let span = high - low
      func y(_ value: Double) -> CGFloat {
        span == 0 ? box.midY : box.maxY - CGFloat((value - low) / span) * box.height
      }
      func x(_ index: Int) -> CGFloat {
        count <= 1 ? box.midX : box.minX + CGFloat(index) / CGFloat(count - 1) * box.width
      }
      let path = NSBezierPath()
      path.lineWidth = max(1, 1.25 * scale)
      path.lineJoinStyle = .round
      var previous: Int?
      for (index, value) in points {
        let point = NSPoint(x: x(index), y: y(value))
        // A blank cell leaves a gap in the line.
        if let previous, previous == index - 1 {
          path.line(to: point)
        } else {
          path.move(to: point)
        }
        previous = index
      }
      series.setStroke()
      path.stroke()
      let radius = max(1.5, 1.6 * scale)
      func dot(_ index: Int, _ value: Double, _ paint: NSColor) {
        paint.setFill()
        NSBezierPath(
          ovalIn: NSRect(
            x: x(index) - radius, y: y(value) - radius, width: radius * 2, height: radius * 2)
        ).fill()
      }
      if item.showsMarkers {
        for (index, value) in points { dot(index, value, series) }
      }
      if item.showsHighLow, high != low {
        if let top = points.first(where: { $0.1 == high }) { dot(top.0, top.1, negative) }
        if let bottom = points.first(where: { $0.1 == low }) { dot(bottom.0, bottom.1, negative) }
      }
    case .column, .winLoss:
      let slot = box.width / CGFloat(max(1, count))
      let barWidth = max(1, slot * 0.75)
      // Columns rise from zero, or from the lowest value when every value is above zero.
      let top = item.kind == .winLoss ? 1 : max(high, 0)
      let bottom = item.kind == .winLoss ? -1 : min(low, 0)
      let span = top - bottom
      func y(_ value: Double) -> CGFloat {
        span == 0 ? box.midY : box.maxY - CGFloat((value - bottom) / span) * box.height
      }
      for (index, raw) in points {
        let value = item.kind == .winLoss ? (raw > 0 ? 1 : raw < 0 ? -1 : 0) : raw
        guard value != 0 || item.kind == .column else { continue }
        let zero = y(0)
        let end = y(value)
        let left = box.minX + CGFloat(index) * slot + (slot - barWidth) / 2
        var paint = series
        if value < 0, item.showsNegative || item.kind == .winLoss { paint = negative }
        if item.showsHighLow, high != low, raw == high || raw == low { paint = negative }
        paint.setFill()
        let height = max(abs(zero - end), value == 0 ? 0 : 1)
        NSRect(x: left, y: min(zero, end), width: barWidth, height: height).fill()
      }
    }
  }
}
