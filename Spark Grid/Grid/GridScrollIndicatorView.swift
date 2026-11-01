import AppKit

/// Overlay scroll bars for the grid, like the system's: thin thumbs that appear while the
/// sheet scrolls and fade out shortly after. They show where you are; clicks pass through.
final class GridScrollIndicatorView: NSView {
  private let vertical = CALayer()
  private let horizontal = CALayer()
  private var fadeTimer: Timer?

  /// How long the thumbs stay after the last scroll.
  private let holdSeconds: TimeInterval = 0.9
  private let thickness: CGFloat = 7
  private let inset: CGFloat = 2
  private let minimumLength: CGFloat = 28

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.backgroundColor = NSColor.clear.cgColor
    layer?.zPosition = 30
    for thumb in [vertical, horizontal] {
      thumb.cornerRadius = thickness / 2
      thumb.opacity = 0
      layer?.addSublayer(thumb)
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  override var isFlipped: Bool { true }

  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    applyColor()
  }

  /// Places the thumbs for the scrolled `area`, then shows them and starts the fade.
  /// `visible` and `total` are the scrollable lengths on each axis; `offset` is the scroll.
  func show(area: NSRect, visible: CGSize, total: CGSize, offset: CGPoint) {
    applyColor()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    place(
      vertical, isVertical: true, area: area, visible: visible.height, total: total.height,
      offset: offset.y)
    place(
      horizontal, isVertical: false, area: area, visible: visible.width, total: total.width,
      offset: offset.x)
    CATransaction.commit()

    fadeTimer?.invalidate()
    fadeTimer = Timer.scheduledTimer(withTimeInterval: holdSeconds, repeats: false) {
      [weak self] _ in
      self?.fadeOut()
    }
  }

  private func place(
    _ thumb: CALayer, isVertical: Bool, area: NSRect, visible: CGFloat, total: CGFloat,
    offset: CGFloat
  ) {
    let track = (isVertical ? area.height : area.width) - 2 * inset - thickness
    guard total > visible + 0.5, visible > 0, track > minimumLength else {
      thumb.opacity = 0
      return
    }
    let length = max(minimumLength, track * visible / total)
    let travel = max(0, total - visible)
    let position = travel > 0 ? (track - length) * min(1, max(0, offset / travel)) : 0
    if isVertical {
      thumb.frame = NSRect(
        x: area.maxX - inset - thickness, y: area.minY + inset + position,
        width: thickness, height: length)
    } else {
      thumb.frame = NSRect(
        x: area.minX + inset + position, y: area.maxY - inset - thickness,
        width: length, height: thickness)
    }
    thumb.removeAnimation(forKey: "fade")
    thumb.opacity = 1
  }

  private func fadeOut() {
    for thumb in [vertical, horizontal] where thumb.opacity > 0 {
      let fade = CABasicAnimation(keyPath: "opacity")
      fade.fromValue = thumb.opacity
      fade.toValue = 0
      fade.duration = 0.35
      thumb.opacity = 0
      thumb.add(fade, forKey: "fade")
    }
  }

  private func applyColor() {
    let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    let color =
      isDark ? NSColor.white.withAlphaComponent(0.42) : NSColor.black.withAlphaComponent(0.38)
    vertical.backgroundColor = color.cgColor
    horizontal.backgroundColor = color.cgColor
  }
}
