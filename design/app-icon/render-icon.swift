// Renders the Spark Grid app icon on Apple's macOS grid: 1024 canvas, 824 shape at 100,
// continuous corners (radius 185.4), drop shadow 0/10 blur 10 at 30% black (Nov 23).
// swift render-icon.swift glyph-1024.png out.png
import AppKit
import SwiftUI

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data((message + "\n").utf8))
  exit(1)
}

let args = CommandLine.arguments
guard args.count == 3 else { fail("usage: render-icon glyph.png out.png") }
guard
  let glyph = NSImage(contentsOfFile: args[1])?
    .cgImage(forProposedRect: nil, context: nil, hints: nil)
else { fail("can't read \(args[1])") }
let size = 1024
guard
  let space = CGColorSpace(name: CGColorSpace.sRGB),
  let ctx = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
else { fail("can't make the drawing context") }
ctx.interpolationQuality = .high
let shape = CGRect(x: 100, y: 100, width: 824, height: 824)
let path = RoundedRectangle(cornerRadius: 185.4, style: .continuous).path(in: shape).cgPath
// CG's origin is bottom-left, so a shadow below the icon is a negative y offset.
ctx.saveGState()
ctx.setShadow(
  offset: CGSize(width: 0, height: -10), blur: 10,
  color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.3))
ctx.addPath(path)
ctx.setFillColor(CGColor(srgbRed: 16 / 255, green: 16 / 255, blue: 18 / 255, alpha: 1))
ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(path)
ctx.clip()
ctx.draw(glyph, in: shape)
ctx.restoreGState()
guard
  let image = ctx.makeImage(),
  let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
else { fail("can't encode the PNG") }
do {
  try png.write(to: URL(fileURLWithPath: args[2]))
} catch {
  fail("can't write \(args[2]): \(error)")
}
