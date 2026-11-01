import Formula
import Foundation
import GridCore
import NumberFormat

/// Display formatting for a cell.
public nonisolated struct CellFormat: Codable, Equatable, Hashable, Sendable {
  public var bold = false
  public var italic = false
  public var underline = false
  public var strikethrough = false
  public var horizontalAlign: HorizontalAlign = .general
  public var verticalAlign: VerticalAlign = .bottom
  public var textColor: CodableColor?
  public var fillColor: CodableColor?
  public var numberFormat: NumberFormat = .general
  /// Excel format code (`€#,##0.00`, `dd/mm/yyyy`, or a code typed in Cell Format). Nil uses `numberFormat`.
  public var formatCode: String?
  public var fontFamily: String?
  public var fontSize: CGFloat?
  public var decimalPlaces: Int?
  /// Excel wrap. Prefer `textDisplay` — wrap is one of overflow, wrap, and clip.
  public var wrapText = false
  /// Ellipsis clipping. Nil with wrap off is overflow, the default.
  public var clipText: Bool?
  /// Degrees for tilt/rotate, or `stackedTextRotation` (255) for one character per line (Excel OOXML).
  public var textRotation: Int = 0
  public var borders: CellBorders = .none

  public init(
    bold: Bool = false,
    italic: Bool = false,
    underline: Bool = false,
    strikethrough: Bool = false,
    horizontalAlign: HorizontalAlign = .general,
    verticalAlign: VerticalAlign = .bottom,
    textColor: CodableColor? = nil,
    fillColor: CodableColor? = nil,
    numberFormat: NumberFormat = .general,
    formatCode: String? = nil,
    fontFamily: String? = nil,
    fontSize: CGFloat? = nil,
    decimalPlaces: Int? = nil,
    wrapText: Bool = false,
    clipText: Bool? = nil,
    textRotation: Int = 0,
    borders: CellBorders = .none
  ) {
    self.bold = bold
    self.italic = italic
    self.underline = underline
    self.strikethrough = strikethrough
    self.horizontalAlign = horizontalAlign
    self.verticalAlign = verticalAlign
    self.textColor = textColor
    self.fillColor = fillColor
    self.numberFormat = numberFormat
    self.formatCode = formatCode
    self.fontFamily = fontFamily
    self.fontSize = fontSize
    self.decimalPlaces = decimalPlaces
    self.wrapText = wrapText
    self.clipText = clipText
    self.textRotation = textRotation
    self.borders = borders
  }

  /// How text that does not fit the cell is drawn.
  public enum TextDisplay: String, Codable, Sendable {
    case overflow
    case wrap
    case clip

    /// Toolbar and menu label for this mode.
    public var toolbarTitle: String {
      switch self {
      case .overflow: return "Overflow"
      case .wrap: return "Wrap"
      case .clip: return "Clip"
      }
    }

    /// Toolbar label when the selection does not share one mode.
    public static let mixedToolbarTitle = "Mixed"
  }

  public var textDisplay: TextDisplay {
    get {
      if wrapText { return .wrap }
      if clipText == true { return .clip }
      return .overflow
    }
    set {
      switch newValue {
      case .overflow:
        wrapText = false
        clipText = nil
      case .wrap:
        wrapText = true
        clipText = nil
      case .clip:
        wrapText = false
        clipText = true
      }
    }
  }

  /// Single-line text that may paint through empty neighbors. Rotation stays inside the cell.
  public var overflowsUnclipped: Bool {
    textDisplay == .overflow && textRotation == 0 && !isStackedVertically
  }

  /// Excel OOXML `textRotation="255"` — upright characters stacked top-to-bottom.
  public static let stackedTextRotation = 255

  public var isStackedVertically: Bool {
    textRotation == Self.stackedTextRotation
  }

  public enum HorizontalAlign: String, Codable, Hashable, Sendable {
    case general, left, center, right
  }

  public enum VerticalAlign: String, Codable, Hashable, Sendable {
    case top, middle, bottom
  }

  public typealias NumberFormat = NumberFormatKind

  /// Code shown in the cell-format viewer. An imported `formatCode` wins; otherwise the builtin code for `numberFormat`.
  public var viewerFormatCode: String {
    if let formatCode {
      let trimmed = formatCode.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty { return trimmed }
    }
    return Self.builtinFormatCode(for: numberFormat, decimalPlaces: decimalPlaces)
  }

  public static func builtinFormatCode(for format: NumberFormat, decimalPlaces: Int?) -> String {
    let places = decimalPlaces ?? defaultViewerPlaces(for: format)
    switch format {
    case .general:
      return "General"
    case .number:
      return "0" + fractionZeros(places)
    case .currency:
      return "$0" + fractionZeros(places)
    case .percent:
      return "0" + fractionZeros(places) + "%"
    case .scientific:
      return "0" + fractionZeros(max(places, 2)) + "E+00"
    case .date:
      return "m/d/yyyy"
    case .time:
      return "h:mm:ss AM/PM"
    }
  }

  private static func defaultViewerPlaces(for format: NumberFormat) -> Int {
    switch format {
    case .general, .date, .time: return 0
    case .number, .currency, .percent, .scientific: return 2
    }
  }

  private static func fractionZeros(_ places: Int) -> String {
    guard places > 0 else { return "" }
    return "." + String(repeating: "0", count: places)
  }
}

/// Per-side borders for a cell.
public nonisolated struct CellBorders: Codable, Equatable, Hashable, Sendable {
  public var top: BorderEdge?
  public var bottom: BorderEdge?
  public var left: BorderEdge?
  public var right: BorderEdge?

  public init(
    top: BorderEdge? = nil,
    bottom: BorderEdge? = nil,
    left: BorderEdge? = nil,
    right: BorderEdge? = nil
  ) {
    self.top = top
    self.bottom = bottom
    self.left = left
    self.right = right
  }

  public static let none = CellBorders()

  public var hasAny: Bool {
    top != nil || bottom != nil || left != nil || right != nil
  }
}

public nonisolated struct BorderEdge: Codable, Equatable, Hashable, Sendable {
  public var style: BorderStyle = .thin
  public var color: CodableColor?

  public init(style: BorderStyle = .thin, color: CodableColor? = nil) {
    self.style = style
    self.color = color
  }

  public static func thin(_ color: CodableColor? = nil) -> BorderEdge {
    BorderEdge(style: .thin, color: color)
  }

  public static func medium(_ color: CodableColor? = nil) -> BorderEdge {
    BorderEdge(style: .medium, color: color)
  }

  public static func thick(_ color: CodableColor? = nil) -> BorderEdge {
    BorderEdge(style: .thick, color: color)
  }
}

public nonisolated enum BorderStyle: String, Codable, Hashable, Sendable, CaseIterable {
  case thin
  case medium
  case thick
  case dashed
  case dotted
  case double

  public var title: String {
    switch self {
    case .thin: return "Thin"
    case .medium: return "Medium"
    case .thick: return "Thick"
    case .dashed: return "Dashed"
    case .dotted: return "Dotted"
    case .double: return "Double"
    }
  }

  public var lineWidth: CGFloat {
    switch self {
    case .thin, .dashed, .dotted: return 1
    case .medium: return 1.5
    case .thick, .double: return 2.5
    }
  }
}

extension BorderEdge {
  public static func styled(_ style: BorderStyle, color: CodableColor? = nil) -> BorderEdge {
    BorderEdge(style: style, color: color)
  }
}

/// Toolbar / menu presets for applying borders to a selection.
public nonisolated enum BorderPreset: String, CaseIterable, Sendable {
  case none
  case all
  case outside
  case inside
  case top
  case bottom
  case left
  case right
  case thickOutside

  public var title: String {
    switch self {
    case .none: return "No Border"
    case .all: return "All Borders"
    case .outside: return "Outside Borders"
    case .inside: return "Inside Borders"
    case .top: return "Top Border"
    case .bottom: return "Bottom Border"
    case .left: return "Left Border"
    case .right: return "Right Border"
    case .thickOutside: return "Thick Box Border"
    }
  }

  public var systemImage: String {
    switch self {
    case .none: return "xmark.rectangle"
    case .all: return "square.grid.3x3"
    case .outside: return "square"
    case .inside: return "square.split.2x2"
    case .top: return "rectangle.topthird.inset.filled"
    case .bottom: return "rectangle.bottomthird.inset.filled"
    case .left: return "rectangle.lefthalf.inset.filled"
    case .right: return "rectangle.righthalf.inset.filled"
    case .thickOutside: return "rectangle.inset.filled"
    }
  }
}

/// Serializable color for document persistence.
public nonisolated struct CodableColor: Codable, Equatable, Hashable, Sendable {
  public var red: Double
  public var green: Double
  public var blue: Double
  public var alpha: Double

  public init(red: Double, green: Double, blue: Double, alpha: Double) {
    self.red = red
    self.green = green
    self.blue = blue
    self.alpha = alpha
  }

  /// sRGB relative luminance, 0 (black) through 1 (white).
  public var relativeLuminance: Double {
    let r = min(1, max(0, red))
    let g = min(1, max(0, green))
    let b = min(1, max(0, blue))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b
  }

  /// Black on a light fill, white on a dark fill.
  public static func contrastingText(on fill: CodableColor) -> CodableColor {
    if fill.relativeLuminance < 0.58 {
      return CodableColor(red: 1, green: 1, blue: 1, alpha: 1)
    }
    return CodableColor(red: 0, green: 0, blue: 0, alpha: 1)
  }
}

extension CellFormat {
  public var isDefault: Bool { self == CellFormat() }

  /// Merges a conditional-format overlay onto a base format.
  public static func merging(_ base: CellFormat?, overlay: ConditionalFormatStyle) -> CellFormat {
    overlay.applying(to: base ?? CellFormat())
  }
}
