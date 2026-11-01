import Formula
import Foundation
import GridCore
import Model
import NumberFormat

/// Office theme color scheme (ECMA-376 clrScheme).
public struct ThemeColorScheme: Sendable {
  public var colorsByName: [String: CodableColor] = [:]

  public init(colorsByName: [String: CodableColor] = [:]) {
    self.colorsByName = colorsByName
  }

  /// SpreadsheetML `theme` attribute indices (ThemeColorValues).
  public func color(themeIndex: Int, tint: Double = 0) -> CodableColor? {
    let names = [
      "dk1", "lt1", "dk2", "lt2",
      "accent1", "accent2", "accent3", "accent4", "accent5", "accent6",
      "hlink", "folHlink",
    ]
    guard themeIndex >= 0, themeIndex < names.count else { return nil }
    let name = names[themeIndex]
    guard
      var base = colorsByName[name]
        ?? colorsByName[name == "dk1" ? "tx1" : name]
        ?? colorsByName[name == "lt1" ? "bg1" : name]
        ?? colorsByName[name == "dk2" ? "tx2" : name]
        ?? colorsByName[name == "lt2" ? "bg2" : name]
    else { return nil }
    if tint != 0 {
      base = Self.applyTint(base, tint: tint)
    }
    return base
  }

  /// Excel tint: positive lightens toward white, negative darkens toward black.
  public static func applyTint(_ color: CodableColor, tint: Double) -> CodableColor {
    let t = min(1, max(-1, tint))
    if t > 0 {
      return CodableColor(
        red: color.red * (1 - t) + t,
        green: color.green * (1 - t) + t,
        blue: color.blue * (1 - t) + t,
        alpha: color.alpha
      )
    }
    if t < 0 {
      let f = 1 + t
      return CodableColor(
        red: color.red * f,
        green: color.green * f,
        blue: color.blue * f,
        alpha: color.alpha
      )
    }
    return color
  }

  public static func parse(themeXML: String) -> ThemeColorScheme {
    var scheme = ThemeColorScheme()
    let names = [
      "lt1", "dk1", "lt2", "dk2",
      "accent1", "accent2", "accent3", "accent4", "accent5", "accent6",
      "hlink", "folHlink", "bg1", "tx1", "bg2", "tx2",
    ]
    for name in names {
      let pattern = #"<a:\#(name)\b[^>]*>([\s\S]*?)</a:\#(name)>"#
      guard let regex = try? NSRegularExpression(pattern: pattern),
        let match = regex.firstMatch(
          in: themeXML,
          range: NSRange(location: 0, length: (themeXML as NSString).length)
        )
      else { continue }
      let body = (themeXML as NSString).substring(with: match.range(at: 1))
      if let color = parseColorElement(in: body) {
        scheme.colorsByName[name] = color
      }
    }
    if scheme.colorsByName["lt1"] == nil { scheme.colorsByName["lt1"] = scheme.colorsByName["bg1"] }
    if scheme.colorsByName["dk1"] == nil { scheme.colorsByName["dk1"] = scheme.colorsByName["tx1"] }
    if scheme.colorsByName["lt2"] == nil { scheme.colorsByName["lt2"] = scheme.colorsByName["bg2"] }
    if scheme.colorsByName["dk2"] == nil { scheme.colorsByName["dk2"] = scheme.colorsByName["tx2"] }
    return scheme
  }

  private static func parseColorElement(in body: String) -> CodableColor? {
    if let range = body.range(of: #"val="[A-Fa-f0-9]{6}""#, options: .regularExpression) {
      return colorFromQuotedHex(String(body[range]))
    }
    if let range = body.range(of: #"lastClr="[A-Fa-f0-9]{6}""#, options: .regularExpression) {
      return colorFromQuotedHex(String(body[range]))
    }
    return nil
  }

  private static func colorFromQuotedHex(_ token: String) -> CodableColor? {
    guard let q1 = token.firstIndex(of: "\""),
      let q2 = token.lastIndex(of: "\""),
      q1 < q2
    else { return nil }
    let hex = String(token[token.index(after: q1)..<q2])
    guard let value = UInt32(hex, radix: 16) else { return nil }
    return CodableColor(
      red: Double((value >> 16) & 0xFF) / 255,
      green: Double((value >> 8) & 0xFF) / 255,
      blue: Double(value & 0xFF) / 255,
      alpha: 1
    )
  }
}

/// Theme-resolved fill/font colors keyed by styles.xml indices.
public struct ThemeResolvedStyleColors: Sendable {
  public var fontColorsById: [Int: CodableColor] = [:]
  public var fillColorsById: [Int: CodableColor] = [:]
  /// Resolved through cellXfs → fontId/fillId (most reliable for per-cell paint).
  public var fontColorsByCellXfId: [Int: CodableColor] = [:]
  public var fillColorsByCellXfId: [Int: CodableColor] = [:]
}

public enum ThemeColorLookup {
  public static func resolve(fromAttributes attrs: String, scheme: ThemeColorScheme)
    -> CodableColor?
  {
    guard let themeStr = attribute(attrs, "theme"), let theme = Int(themeStr) else { return nil }
    let tint = attribute(attrs, "tint").flatMap(Double.init) ?? 0
    return scheme.color(themeIndex: theme, tint: tint)
  }

  public static func parseStyleColors(stylesXML: String, scheme: ThemeColorScheme)
    -> ThemeResolvedStyleColors
  {
    var result = ThemeResolvedStyleColors()
    if let fontsRange = stylesXML.range(
      of: #"<fonts\b[^>]*>[\s\S]*?</fonts>"#, options: .regularExpression)
    {
      let fontsXML = String(stylesXML[fontsRange])
      let pattern = #"<font>(.*?)</font>"#
      if let regex = try? NSRegularExpression(
        pattern: pattern, options: [.dotMatchesLineSeparators])
      {
        let ns = fontsXML as NSString
        for (index, match) in regex.matches(
          in: fontsXML,
          range: NSRange(location: 0, length: ns.length)
        ).enumerated() {
          let body = ns.substring(with: match.range(at: 1))
          if let color = firstThemeOrRGBColor(in: body, scheme: scheme) {
            result.fontColorsById[index] = color
          }
        }
      }
    }
    if let fillsRange = stylesXML.range(
      of: #"<fills\b[^>]*>[\s\S]*?</fills>"#, options: .regularExpression)
    {
      let fillsXML = String(stylesXML[fillsRange])
      let pattern = #"<fill>(.*?)</fill>"#
      if let regex = try? NSRegularExpression(
        pattern: pattern, options: [.dotMatchesLineSeparators])
      {
        let ns = fillsXML as NSString
        for (index, match) in regex.matches(
          in: fillsXML,
          range: NSRange(location: 0, length: ns.length)
        ).enumerated() {
          let body = ns.substring(with: match.range(at: 1))
          if body.contains(#"patternType="none""#) { continue }
          if let color = firstThemeOrRGBColor(in: body, scheme: scheme) {
            result.fillColorsById[index] = color
          }
        }
      }
    }
    if let xfsRange = stylesXML.range(
      of: #"<cellXfs\b[^>]*>[\s\S]*?</cellXfs>"#, options: .regularExpression)
    {
      let xfsXML = String(stylesXML[xfsRange])
      let xfPattern = #"<xf\b([^>/]*)(?:/>|>)"#
      if let regex = try? NSRegularExpression(pattern: xfPattern) {
        let ns = xfsXML as NSString
        for (index, match) in regex.matches(
          in: xfsXML,
          range: NSRange(location: 0, length: ns.length)
        ).enumerated() {
          let attrs = ns.substring(with: match.range(at: 1))
          if let fontId = attribute(attrs, "fontId").flatMap(Int.init),
            let color = result.fontColorsById[fontId]
          {
            result.fontColorsByCellXfId[index] = color
          }
          if let fillId = attribute(attrs, "fillId").flatMap(Int.init),
            let color = result.fillColorsById[fillId]
          {
            result.fillColorsByCellXfId[index] = color
          }
        }
      }
    }
    return result
  }

  private static func firstThemeOrRGBColor(in xml: String, scheme: ThemeColorScheme)
    -> CodableColor?
  {
    let colorPattern = #"<[^>]*?(?:fgColor|bgColor|color)\b([^>/]*)/?\s*>"#
    guard let regex = try? NSRegularExpression(pattern: colorPattern) else { return nil }
    let ns = xml as NSString
    for match in regex.matches(in: xml, range: NSRange(location: 0, length: ns.length)) {
      let attrs = ns.substring(with: match.range(at: 1))
      if let themed = resolve(fromAttributes: attrs, scheme: scheme) {
        return themed
      }
      if let rgb = attribute(attrs, "rgb") {
        let hex = rgb.count == 8 ? String(rgb.suffix(6)) : rgb
        guard let value = UInt32(hex, radix: 16) else { continue }
        return CodableColor(
          red: Double((value >> 16) & 0xFF) / 255,
          green: Double((value >> 8) & 0xFF) / 255,
          blue: Double(value & 0xFF) / 255,
          alpha: 1
        )
      }
    }
    return nil
  }

  private static func attribute(_ attrs: String, _ name: String) -> String? {
    guard let range = attrs.range(of: #"\#(name)="[^"]*""#, options: .regularExpression) else {
      return nil
    }
    let token = String(attrs[range])
    guard let q1 = token.firstIndex(of: "\""),
      let q2 = token.lastIndex(of: "\""),
      q1 < q2
    else { return nil }
    return String(token[token.index(after: q1)..<q2])
  }
}
