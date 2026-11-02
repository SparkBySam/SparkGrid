import AppKit

/// The comment on a cell, shown beside it while the pointer rests there, like the note card in
/// other spreadsheet apps. Reading a comment no longer needs Edit Comment. Clicks pass through.
final class CommentHoverCard: NSView {
  private let label = NSTextField(wrappingLabelWithString: "")

  private let maxTextWidth: CGFloat = 240
  private let padding: CGFloat = 8
  /// Gap between the cell's right edge and the card.
  private let gap: CGFloat = 4

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.cornerRadius = 6
    layer?.borderWidth = 1
    layer?.zPosition = 40
    layer?.shadowOpacity = 0.25
    layer?.shadowRadius = 6
    layer?.shadowOffset = CGSize(width: 0, height: -2)
    label.isSelectable = false
    label.drawsBackground = false
    label.maximumNumberOfLines = 12
    label.lineBreakMode = .byWordWrapping
    addSubview(label)
    isHidden = true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  override var isFlipped: Bool { true }

  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    applyColors()
  }

  /// Shows `author` and `text` next to `cellRect`, kept inside `bounds` of the grid.
  func show(author: String, text: String, beside cellRect: NSRect, within area: NSRect) {
    let body = NSMutableAttributedString()
    if !author.isEmpty {
      body.append(
        NSAttributedString(
          string: author + "\n",
          attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
          ]))
    }
    body.append(
      NSAttributedString(
        string: text,
        attributes: [
          .font: NSFont.systemFont(ofSize: 12),
          .foregroundColor: NSColor.labelColor,
        ]))
    label.attributedStringValue = body
    label.preferredMaxLayoutWidth = maxTextWidth
    let fitted = label.sizeThatFits(NSSize(width: maxTextWidth, height: .greatestFiniteMagnitude))
    let textSize = NSSize(width: min(ceil(fitted.width), maxTextWidth), height: ceil(fitted.height))
    let size = NSSize(width: textSize.width + padding * 2, height: textSize.height + padding * 2)

    // Right of the cell, top-aligned; flipped to the left or pulled up when it would leave the grid.
    var origin = NSPoint(x: cellRect.maxX + gap, y: cellRect.minY)
    if origin.x + size.width > area.maxX {
      origin.x = max(area.minX, cellRect.minX - gap - size.width)
    }
    if origin.y + size.height > area.maxY {
      origin.y = max(area.minY, area.maxY - size.height)
    }
    frame = NSRect(origin: origin, size: size)
    label.frame = NSRect(x: padding, y: padding, width: textSize.width, height: textSize.height)
    applyColors()
    isHidden = false
  }

  func hide() {
    isHidden = true
  }

  private func applyColors() {
    effectiveAppearance.performAsCurrentDrawingAppearance {
      layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
      layer?.borderColor = NSColor.separatorColor.cgColor
    }
  }
}
