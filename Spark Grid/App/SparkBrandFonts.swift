import AppKit
import CoreText
import SwiftUI

/// The website's typefaces, bundled for brand moments only: the About window and the
/// Opening panel. The toolbar, menus and cells stay on system fonts and Helvetica Neue.
///
/// Bricolage Grotesque (Mathieu Triay) and Figtree (Erik Kennedy) are SIL Open Font
/// License fonts. Their licenses ship beside them in `Fonts/`.
enum SparkBrandFonts {
  static let displayFamily = "Bricolage Grotesque"
  static let bodyFamily = "Figtree"

  private static let fontFiles = ["BricolageGrotesque-Variable", "Figtree-Variable"]
  private static let weightAxis = 0x7767_6874  // 'wght'
  private static let opticalSizeAxis = 0x6F70_737A  // 'opsz'

  /// Registers the bundled fonts for this process once.
  private static let registration: Void = {
    for name in fontFiles {
      guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
      CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
  }()

  /// Headings, set like the website: Bricolage Grotesque with optical size matched to
  /// the point size. Falls back to the system font if the file is missing.
  static func display(size: CGFloat, weight: Int = 700) -> NSFont {
    font(family: displayFamily, size: size, weight: weight, opticalSize: size)
      ?? .systemFont(ofSize: size, weight: weight >= 600 ? .bold : .medium)
  }

  /// Body copy in brand moments: Figtree.
  static func body(size: CGFloat, weight: Int = 400) -> NSFont {
    font(family: bodyFamily, size: size, weight: weight, opticalSize: nil)
      ?? .systemFont(ofSize: size, weight: weight >= 500 ? .medium : .regular)
  }

  private static func font(
    family: String, size: CGFloat, weight: Int, opticalSize: CGFloat?
  ) -> NSFont? {
    _ = registration
    var variation: [Int: CGFloat] = [weightAxis: CGFloat(weight)]
    if let opticalSize {
      variation[opticalSizeAxis] = min(max(opticalSize, 12), 96)
    }
    let descriptor = NSFontDescriptor(fontAttributes: [
      .family: family,
      NSFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): variation,
    ])
    guard let font = NSFont(descriptor: descriptor, size: size), font.familyName == family else {
      return nil
    }
    return font
  }
}

extension Font {
  /// Bricolage Grotesque for brand headings.
  static func sparkDisplay(size: CGFloat, weight: Int = 700) -> Font {
    Font(SparkBrandFonts.display(size: size, weight: weight) as CTFont)
  }

  /// Figtree for brand body copy.
  static func sparkBody(size: CGFloat, weight: Int = 400) -> Font {
    Font(SparkBrandFonts.body(size: size, weight: weight) as CTFont)
  }
}
