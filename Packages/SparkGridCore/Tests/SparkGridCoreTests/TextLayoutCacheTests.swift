import AppKit
import Model
import XCTest

@testable import Rendering

/// Cached Core Text drawing has to match the AppKit text the grid used before the cache.
final class TextLayoutCacheTests: XCTestCase {
  func testCachedLinesMatchUncachedPixels() {
    let cell = NSRect(x: 0, y: 0, width: 120, height: 44)
    var centered = CellFormat()
    centered.horizontalAlign = .center
    var right = CellFormat()
    right.horizontalAlign = .right
    var wrapped = CellFormat()
    wrapped.wrapText = true
    var clipped = CellFormat()
    clipped.clipText = true
    var bold = CellFormat()
    bold.bold = true
    var colored = CellFormat()
    colored.textColor = CodableColor(red: 0.1, green: 0.25, blue: 0.7, alpha: 1)

    let samples: [(String, CellFormat)] = [
      ("Revenue", CellFormat()),
      ("1,234.50", centered),
      ("Total", right),
      ("A longer label that wraps inside the cell", wrapped),
      ("Clipped label that does not fit this cell", clipped),
      ("Bold", bold),
      ("Blue", colored),
    ]
    for sample in samples {
      let before = render(cell) {
        CellFormatRenderer.drawTextUncached(sample.0, in: cell, format: sample.1)
      }
      let after = render(cell) {
        CellFormatRenderer.drawText(sample.0, in: cell, format: sample.1)
      }
      let again = render(cell) {
        CellFormatRenderer.drawText(sample.0, in: cell, format: sample.1)
      }
      XCTAssertNotNil(before, sample.0)
      XCTAssertNotNil(after, sample.0)
      guard let before, let after, let again else { continue }
      XCTAssertEqual(mismatchCount(before, after), 0, sample.0)
      XCTAssertEqual(mismatchCount(after, again), 0, sample.0)
    }
  }

  private func render(_ rect: NSRect, draw: () -> Void) -> NSBitmapImageRep? {
    guard
      let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(rect.width),
        pixelsHigh: Int(rect.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
      )
    else { return nil }
    rep.size = rect.size
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    guard let base = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    let cg = base.cgContext
    cg.translateBy(x: 0, y: rect.height)
    cg.scaleBy(x: 1, y: -1)
    let flipped = NSGraphicsContext(cgContext: cg, flipped: true)
    flipped.imageInterpolation = .none
    NSGraphicsContext.current = flipped
    NSColor.white.setFill()
    rect.fill()
    draw()
    return rep
  }

  func testOverflowWidthCoversTheDrawnLine() {
    let samples = [
      "1,234.56",
      "June",
      "Total Revenue",
      "-$4,200.00",
      "100%",
      "Operating expenses and allocations",
    ]
    var bold = CellFormat()
    bold.bold = true
    let formats = [CellFormat(), bold]
    for format in formats {
      for text in samples {
        let exact = CellFormatRenderer.measuredWidth(for: text, format: format)
        let fast = CellFormatRenderer.overflowWidth(for: text, format: format)
        XCTAssertGreaterThanOrEqual(fast, exact - 0.5, text)
        XCTAssertLessThanOrEqual(fast, exact + 3, text)
      }
    }
    var wrapped = CellFormat()
    wrapped.wrapText = true
    let wrappedText = "A longer label that wraps inside the cell"
    XCTAssertEqual(
      CellFormatRenderer.overflowWidth(for: wrappedText, format: wrapped),
      CellFormatRenderer.measuredWidth(for: wrappedText, format: wrapped)
    )
  }

  private func mismatchCount(_ left: NSBitmapImageRep, _ right: NSBitmapImageRep) -> Int {
    guard let leftData = left.bitmapData, let rightData = right.bitmapData else { return -1 }
    guard left.pixelsWide == right.pixelsWide, left.pixelsHigh == right.pixelsHigh else {
      return -1
    }
    var mismatches = 0
    for y in 0..<left.pixelsHigh {
      for x in 0..<left.pixelsWide {
        let leftOffset = y * left.bytesPerRow + x * 4
        let rightOffset = y * right.bytesPerRow + x * 4
        var different = false
        for channel in 0..<4 {
          let leftByte = Int(leftData[leftOffset + channel])
          let rightByte = Int(rightData[rightOffset + channel])
          let delta = abs(leftByte - rightByte)
          if delta > 8 {
            different = true
            break
          }
        }
        if different { mismatches += 1 }
      }
    }
    return mismatches
  }
}
