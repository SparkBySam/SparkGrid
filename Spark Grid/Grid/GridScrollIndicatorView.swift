import AppKit

/// Overlay scroll bars for the grid, like the system's: thin thumbs that appear while the
/// sheet scrolls and fade out shortly after. Moving the pointer to the edge brings a bar back,
/// wider and with its track; there the thumb can be dragged and the track clicked. The grid
/// does the clicking: this view only draws and answers where things are.
final class GridScrollIndicatorView: NSView {
  enum Axis {
    case vertical
    case horizontal
  }

  /// Where a point is on a bar: on the thumb, or in the track before or after it.
  enum Hit: Equatable {
    case thumb(Axis)
    case trackBefore(Axis)
    case trackAfter(Axis)

    var axis: Axis {
      switch self {
      case .thumb(let axis), .trackBefore(let axis), .trackAfter(let axis): axis
      }
    }
  }

  private let vertical = CALayer()
  private let horizontal = CALayer()
  private let verticalTrack = CALayer()
  private let horizontalTrack = CALayer()
  private var fadeTimer: Timer?

  /// How long the thumbs stay after the last scroll.
  private let holdSeconds: TimeInterval = 0.9
  private let thinThickness: CGFloat = 7
  private let wideThickness: CGFloat = 11
  private let inset: CGFloat = 2
  private let minimumLength: CGFloat = 28
  /// How far in from the edge the pointer brings a bar back.
  private let edgeBand: CGFloat = 15

  /// The last placement, so the grid can ask where the thumbs are and map a drag back.
  private var area = NSRect.zero
  private var visible = CGSize.zero
  private var total = CGSize.zero
  private var offset = CGPoint.zero
  /// The bar the pointer is over or dragging: shown wide, and kept until it leaves.
  private(set) var heldAxis: Axis?
  /// Classic scroll bars: always on screen, wide, with their tracks.
  var alwaysShown = false {
    didSet {
      guard alwaysShown != oldValue else { return }
      placeBoth()
      if alwaysShown { fadeTimer?.invalidate() } else { scheduleFade() }
    }
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.backgroundColor = NSColor.clear.cgColor
    layer?.zPosition = 30
    for track in [verticalTrack, horizontalTrack] {
      track.opacity = 0
      layer?.addSublayer(track)
    }
    for thumb in [vertical, horizontal] {
      thumb.opacity = 0
      layer?.addSublayer(thumb)
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  override var isFlipped: Bool { true }

  /// Clicks go to the grid, which asks `hit(at:)`.
  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    applyColor()
  }

  /// Places the thumbs for the scrolled `area`, then shows them and starts the fade.
  /// `visible` and `total` are the scrollable lengths on each axis; `offset` is the scroll.
  func show(area: NSRect, visible: CGSize, total: CGSize, offset: CGPoint) {
    self.area = area
    self.visible = visible
    self.total = total
    self.offset = offset
    applyColor()
    placeBoth()
    scheduleFade()
  }

  /// Keeps `axis`'s bar shown wide, or with nil lets the bars fade again.
  func hold(_ axis: Axis?) {
    guard axis != heldAxis else { return }
    heldAxis = axis
    placeBoth()
    scheduleFade()
  }

  // MARK: Geometry

  private func lengths(_ axis: Axis) -> (visible: CGFloat, total: CGFloat, offset: CGFloat) {
    axis == .vertical
      ? (visible.height, total.height, offset.y) : (visible.width, total.width, offset.x)
  }

  private func thickness(_ axis: Axis) -> CGFloat {
    heldAxis == axis || alwaysShown ? wideThickness : thinThickness
  }

  /// The track's length along `axis`, and the thumb's length and start within it. Nil when
  /// the axis has nothing to scroll.
  private func metrics(_ axis: Axis) -> (track: CGFloat, thumb: CGFloat, start: CGFloat)? {
    let l = lengths(axis)
    let track = (axis == .vertical ? area.height : area.width) - 2 * inset - wideThickness
    guard l.total > l.visible + 0.5, l.visible > 0, track > minimumLength else { return nil }
    let thumb = max(minimumLength, track * l.visible / l.total)
    let travel = max(0, l.total - l.visible)
    let start = travel > 0 ? (track - thumb) * min(1, max(0, l.offset / travel)) : 0
    return (track, thumb, start)
  }

  private func trackRect(_ axis: Axis) -> NSRect? {
    guard let m = metrics(axis) else { return nil }
    let t = thickness(axis)
    return axis == .vertical
      ? NSRect(x: area.maxX - inset - t, y: area.minY + inset, width: t, height: m.track)
      : NSRect(x: area.minX + inset, y: area.maxY - inset - t, width: m.track, height: t)
  }

  func thumbRect(_ axis: Axis) -> NSRect? {
    guard let m = metrics(axis), let track = trackRect(axis) else { return nil }
    return axis == .vertical
      ? NSRect(x: track.minX, y: track.minY + m.start, width: track.width, height: m.thumb)
      : NSRect(x: track.minX + m.start, y: track.minY, width: m.thumb, height: track.height)
  }

  /// The band along the edge where a bar answers the pointer.
  private func edgeRect(_ axis: Axis) -> NSRect? {
    guard metrics(axis) != nil else { return nil }
    return axis == .vertical
      ? NSRect(x: area.maxX - edgeBand, y: area.minY, width: edgeBand, height: area.height)
      : NSRect(x: area.minX, y: area.maxY - edgeBand, width: area.width, height: edgeBand)
  }

  /// The bar whose edge band `point` is in. The vertical bar wins the corner.
  func edgeAxis(at point: NSPoint) -> Axis? {
    if edgeRect(.vertical)?.contains(point) == true { return .vertical }
    if edgeRect(.horizontal)?.contains(point) == true { return .horizontal }
    return nil
  }

  /// What a click at `point` would press. Only a bar that is showing answers.
  func hit(at point: NSPoint) -> Hit? {
    guard let axis = edgeAxis(at: point), isShowing(axis), let thumb = thumbRect(axis) else {
      return nil
    }
    let along = axis == .vertical ? point.y : point.x
    let (start, end) = axis == .vertical ? (thumb.minY, thumb.maxY) : (thumb.minX, thumb.maxX)
    if along < start { return .trackBefore(axis) }
    if along > end { return .trackAfter(axis) }
    return .thumb(axis)
  }

  /// Where `axis`'s thumb is drawn now, if it is showing.
  func drawnThumbFrame(_ axis: Axis) -> NSRect? {
    let thumb = axis == .vertical ? vertical : horizontal
    return thumb.opacity > 0 ? thumb.frame : nil
  }

  func isShowing(_ axis: Axis) -> Bool {
    (axis == .vertical ? vertical : horizontal).opacity > 0
  }

  /// The thumb's start along the track now.
  func thumbStart(_ axis: Axis) -> CGFloat { metrics(axis)?.start ?? 0 }

  /// The scroll offset that puts the thumb's start at `start` along the track.
  func offset(forThumbStart start: CGFloat, _ axis: Axis) -> CGFloat {
    let l = lengths(axis)
    guard let m = metrics(axis), m.track > m.thumb else { return l.offset }
    let travel = max(0, l.total - l.visible)
    return min(travel, max(0, start / (m.track - m.thumb) * travel))
  }

  /// The scroll offset that centers the thumb on `point`, for a click that jumps to the spot.
  func offset(centeringThumbOn point: NSPoint, _ axis: Axis) -> CGFloat {
    guard let m = metrics(axis), let track = trackRect(axis) else { return lengths(axis).offset }
    let along = axis == .vertical ? point.y - track.minY : point.x - track.minX
    return offset(forThumbStart: along - m.thumb / 2, axis)
  }

  // MARK: Drawing

  private func placeBoth() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    place(.vertical)
    place(.horizontal)
    CATransaction.commit()
  }

  private func place(_ axis: Axis) {
    let thumb = axis == .vertical ? vertical : horizontal
    let track = axis == .vertical ? verticalTrack : horizontalTrack
    guard let thumbFrame = thumbRect(axis), let trackFrame = trackRect(axis) else {
      thumb.opacity = 0
      track.opacity = 0
      return
    }
    let t = thickness(axis)
    thumb.frame = thumbFrame
    thumb.cornerRadius = t / 2
    track.frame = trackFrame.insetBy(dx: -1, dy: -1)
    track.cornerRadius = t / 2 + 1
    thumb.removeAnimation(forKey: "fade")
    track.removeAnimation(forKey: "fade")
    thumb.opacity = 1
    track.opacity = heldAxis == axis || alwaysShown ? 1 : 0
  }

  private func scheduleFade() {
    fadeTimer?.invalidate()
    fadeTimer = nil
    guard heldAxis == nil, !alwaysShown else { return }
    fadeTimer = Timer.scheduledTimer(withTimeInterval: holdSeconds, repeats: false) {
      [weak self] _ in
      self?.fadeOut()
    }
  }

  private func fadeOut() {
    guard heldAxis == nil, !alwaysShown else { return }
    for layer in [vertical, horizontal, verticalTrack, horizontalTrack] where layer.opacity > 0 {
      let fade = CABasicAnimation(keyPath: "opacity")
      fade.fromValue = layer.opacity
      fade.toValue = 0
      fade.duration = 0.35
      layer.opacity = 0
      layer.add(fade, forKey: "fade")
    }
  }

  private func applyColor() {
    let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    let color =
      isDark ? NSColor.white.withAlphaComponent(0.42) : NSColor.black.withAlphaComponent(0.38)
    let trackColor =
      isDark ? NSColor.white.withAlphaComponent(0.08) : NSColor.black.withAlphaComponent(0.06)
    vertical.backgroundColor = color.cgColor
    horizontal.backgroundColor = color.cgColor
    verticalTrack.backgroundColor = trackColor.cgColor
    horizontalTrack.backgroundColor = trackColor.cgColor
  }
}
