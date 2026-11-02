import AppKit
import Foundation

/// Spark Grid's colors, shared with sparkgridapp.com.
///
/// Light mode keeps the macOS system colors. Dark mode uses the website's warm graphite.
/// Selection, the fill handle, the active sheet tab and toolbar toggles use Spark amber
/// unless the user turns on Settings > Use macOS accent color. Values and their contrast
/// ratios are listed in the Spark Grid design system.
public nonisolated enum SparkTheme {
  /// Posted on the main thread after `usesSystemAccent` changes.
  public static let didChangeNotification = Notification.Name("SparkThemeDidChange")

  /// UserDefaults key that Settings writes for the accent choice.
  public static let systemAccentDefaultsKey = "useSystemAccentColor"

  /// Written on the main thread only; drawing code reads it.
  nonisolated(unsafe) private static var systemAccentFlag = UserDefaults.standard.bool(
    forKey: systemAccentDefaultsKey)

  /// True when the accent follows macOS instead of Spark amber.
  public static var usesSystemAccent: Bool {
    get { systemAccentFlag }
    set { systemAccentFlag = newValue }
  }

  public static func isDark(_ appearance: NSAppearance) -> Bool {
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
  }

  // MARK: - Brand values from sparkgridapp.com

  /// Spark amber on light grounds. Deep enough for a 3:1 outline on white (3.7:1).
  public static let amberOnLight = rgb(0xB8_78_1F)
  /// Spark amber on dark grounds, the website's `--amber` (7.8:1 on `graphiteRaised`).
  public static let amber = rgb(0xE0_A2_4A)
  /// The website's page ground, `--bg`.
  public static let graphite = rgb(0x0F_12_14)
  /// The website's raised ground, `--bg-elevated`.
  public static let graphiteRaised = rgb(0x17_1B_1F)
  /// The website's text, `--ink`.
  public static let warmInk = rgb(0xF2_EF_E8)
  /// The website's secondary text, `--muted`.
  public static let warmMuted = rgb(0x9A_A3_AB)

  // MARK: - Surfaces

  /// Window ground: the sheet-tab bar and anything outside the toolbar, formula bar and grid.
  public static let window = dynamic("SparkWindow", light: .windowBackgroundColor, dark: graphite)
  /// The grid canvas behind cells.
  public static let canvas = dynamic(
    "SparkCanvas", light: .windowBackgroundColor, dark: graphiteRaised)
  /// Toolbar, formula bar, row and column headers, and the active sheet tab.
  public static let chrome = dynamic(
    "SparkChrome", light: .controlBackgroundColor, dark: graphiteRaised)
  /// Text fields in the window chrome, such as the Find bar.
  public static let field = dynamic(
    "SparkField", light: .textBackgroundColor, dark: graphiteRaised)

  // MARK: - Text

  /// Body text: cells, the formula bar, toolbar glyphs and captions.
  private static let dynamicLabel = dynamic("SparkLabel", light: .labelColor, dark: warmInk)
  /// Concrete when a background tile has adopted a palette resolved on the main thread.
  public static var label: NSColor { adoptedDrawingPalette?.label ?? dynamicLabel }
  /// Header labels, the name box, inactive tabs. 5.7:1 on white, 6.8:1 on `graphiteRaised`.
  public static let secondaryLabel = dynamic(
    "SparkSecondaryLabel", light: rgb(0x00_00_00, alpha: 0.60), dark: warmMuted)
  /// Placeholders and disabled text only.
  public static let tertiaryLabel = dynamic(
    "SparkTertiaryLabel", light: .tertiaryLabelColor, dark: rgb(0xF2_EF_E8, alpha: 0.35))
  /// Formula error values in cells. 5.4:1 on white, 5.0:1 on `graphiteRaised`.
  public static let errorText = dynamic("SparkErrorText", light: rgb(0xD7_00_15), dark: .systemRed)

  // MARK: - Lines

  public static let separator = dynamic(
    "SparkSeparator", light: .separatorColor, dark: rgb(0xF2_EF_E8, alpha: 0.12))
  /// Rules between the toolbar, formula bar, find bar and grid.
  public static let chromeDivider = dynamic(
    "SparkChromeDivider", light: rgb(0x00_00_00, alpha: 0.07),
    dark: rgb(0xF2_EF_E8, alpha: 0.12))
  /// Hairline outlines around chrome controls.
  public static let chromeBorder = dynamic(
    "SparkChromeBorder", light: rgb(0x00_00_00, alpha: 0.056),
    dark: rgb(0xF2_EF_E8, alpha: 0.09))
  /// Lines between cells, and between header cells.
  public static let gridLine = dynamic(
    "SparkGridLine", light: rgb(0x00_00_00, alpha: 0.24), dark: rgb(0xF2_EF_E8, alpha: 0.16))
  /// The freeze-pane boundary: plainly heavier than a grid line, never near-black.
  public static let freezeDivider = dynamic(
    "SparkFreezeDivider", light: rgb(0x00_00_00, alpha: 0.6),
    dark: rgb(0xF2_EF_E8, alpha: 0.55))
  /// Cell borders the user applies without picking a color.
  private static let dynamicCellBorder = dynamic(
    "SparkCellBorder", light: rgb(0x00_00_00, alpha: 0.85),
    dark: rgb(0xF2_EF_E8, alpha: 0.85))
  /// Concrete when a background tile has adopted a palette resolved on the main thread.
  public static var cellBorder: NSColor { adoptedDrawingPalette?.cellBorder ?? dynamicCellBorder }

  // MARK: - Accent and selection

  /// Spark amber in both appearances, whatever the accent setting.
  public static let sparkAmber = dynamic("SparkAmber", light: amberOnLight, dark: amber)

  /// Selection outline, fill handle, active sheet-tab underline.
  public static let accent = NSColor(name: "SparkAccent") { appearance in
    accentBase(for: appearance)
  }
  /// Background of an active toolbar toggle.
  public static let accentSubtle = NSColor(name: "SparkAccentSubtle") { appearance in
    accentBase(for: appearance).withAlphaComponent(0.22)
  }
  /// Fill behind selected ranges.
  public static let selectionWash = NSColor(name: "SparkSelectionWash") { appearance in
    let dark = isDark(appearance)
    if usesSystemAccent {
      return NSColor.selectedContentBackgroundColor.withAlphaComponent(dark ? 0.40 : 0.12)
    }
    return (dark ? amber : amberOnLight).withAlphaComponent(dark ? 0.24 : 0.12)
  }
  /// Row and column header cells inside the selection.
  public static let headerSelected = NSColor(name: "SparkHeaderSelected") { appearance in
    let dark = isDark(appearance)
    if usesSystemAccent {
      return NSColor.selectedContentBackgroundColor.withAlphaComponent(0.12)
    }
    return (dark ? amber : amberOnLight).withAlphaComponent(dark ? 0.16 : 0.12)
  }
  /// Ring around the fill handle.
  public static let fillHandleRing = NSColor.white

  /// Formula reference colors, in order. Light mode darkens the four system colors that fall
  /// under 3:1 on white (orange, green, teal, yellow).
  public static let referencePalette: [NSColor] = [
    dynamic("SparkRefBlue", light: .systemBlue, dark: .systemBlue),
    dynamic("SparkRefOrange", light: rgb(0xC1_5B_00), dark: .systemOrange),
    dynamic("SparkRefPurple", light: .systemPurple, dark: .systemPurple),
    dynamic("SparkRefGreen", light: rgb(0x24_8A_3D), dark: .systemGreen),
    dynamic("SparkRefPink", light: .systemPink, dark: .systemPink),
    dynamic("SparkRefTeal", light: rgb(0x0A_7F_8A), dark: .systemTeal),
    dynamic("SparkRefYellow", light: rgb(0x94_6C_00), dark: .systemYellow),
    dynamic("SparkRefIndigo", light: .systemIndigo, dark: .systemIndigo),
  ]

  // MARK: - Resolved palette for drawing

  /// Concrete colors for one appearance and accent choice. Resolve once per draw pass;
  /// the dynamic colors above re-run their provider every time they are set.
  public struct Palette {
    public let isDark: Bool
    public let window: NSColor
    public let canvas: NSColor
    public let chrome: NSColor
    public let field: NSColor
    public let label: NSColor
    public let secondaryLabel: NSColor
    public let errorText: NSColor
    public let gridLine: NSColor
    public let freezeDivider: NSColor
    public let cellBorder: NSColor
    public let accent: NSColor
    public let selectionWash: NSColor
    public let headerSelected: NSColor
    public let fillHandleRing: NSColor
  }

  /// Identifies a resolved palette, so views can cache one.
  public struct PaletteKey: Equatable {
    public let isDark: Bool
    public let usesSystemAccent: Bool
    public let systemAccentGeneration: Int

    public init(appearance: NSAppearance) {
      isDark = SparkTheme.isDark(appearance)
      usesSystemAccent = SparkTheme.usesSystemAccent
      systemAccentGeneration = SparkTheme.systemAccentGeneration
    }
  }

  /// Bumped when macOS system colors change (the user picks another accent).
  nonisolated(unsafe) public private(set) static var systemAccentGeneration = 0

  /// Call from `NSColor.systemColorsDidChangeNotification`.
  public static func noteSystemColorsChanged() {
    systemAccentGeneration &+= 1
  }

  /// Concrete light colors for a draw that has no resolved palette. Background tile
  /// rendering uses `adoptResolvedPalette` instead of calling `palette(for:)`.
  public static let fallbackPalette = Palette(
    isDark: false,
    window: rgb(0xFF_FF_FF),
    canvas: rgb(0xFF_FF_FF),
    chrome: rgb(0xFF_FF_FF),
    field: rgb(0xFF_FF_FF),
    label: rgb(0x00_00_00),
    secondaryLabel: rgb(0x00_00_00, alpha: 0.60),
    errorText: rgb(0xD7_00_15),
    gridLine: rgb(0x00_00_00, alpha: 0.24),
    freezeDivider: rgb(0x00_00_00, alpha: 0.6),
    cellBorder: rgb(0x00_00_00, alpha: 0.85),
    accent: amberOnLight,
    selectionWash: amberOnLight.withAlphaComponent(0.12),
    headerSelected: amberOnLight.withAlphaComponent(0.12),
    fillHandleRing: .white
  )

  private static let drawingPaletteKey = "SparkTheme.drawingPalette"

  private final class DrawingPaletteBox: NSObject {
    let palette: Palette
    init(_ palette: Palette) { self.palette = palette }
  }

  /// Palette installed for this thread by `adoptResolvedPalette`.
  public static var adoptedDrawingPalette: Palette? {
    (Thread.current.threadDictionary[drawingPaletteKey] as? DrawingPaletteBox)?.palette
  }

  /// Install a palette that was resolved on the main thread. Background tile rendering
  /// calls this before it draws, so `label` and `cellBorder` stay concrete colors.
  public static func adoptResolvedPalette(_ palette: Palette?) {
    if let palette {
      Thread.current.threadDictionary[drawingPaletteKey] = DrawingPaletteBox(palette)
    } else {
      Thread.current.threadDictionary.removeObject(forKey: drawingPaletteKey)
    }
  }

  public static func palette(for appearance: NSAppearance) -> Palette {
    func pick(_ color: NSColor) -> NSColor { resolved(color, for: appearance) }
    return Palette(
      isDark: isDark(appearance),
      window: pick(window),
      canvas: pick(canvas),
      chrome: pick(chrome),
      field: pick(field),
      label: pick(label),
      secondaryLabel: pick(secondaryLabel),
      errorText: pick(errorText),
      gridLine: pick(gridLine),
      freezeDivider: pick(freezeDivider),
      cellBorder: pick(cellBorder),
      accent: pick(accent),
      selectionWash: pick(selectionWash),
      headerSelected: pick(headerSelected),
      fillHandleRing: fillHandleRing
    )
  }

  // MARK: - Helpers

  /// `color` as concrete sRGB for `appearance`. Costs an appearance switch and a color
  /// conversion, so resolve once per draw pass (see `palette(for:)`), never per cell.
  public static func resolved(_ color: NSColor, for appearance: NSAppearance) -> NSColor {
    var result = color
    appearance.performAsCurrentDrawingAppearance {
      // Copy the components out. `usingColorSpace` can hand back another dynamic
      // color, and Core Text then draws different pixels than AppKit.
      guard let source = color.usingColorSpace(.sRGB) else { return }
      result = NSColor(
        srgbRed: source.redComponent,
        green: source.greenComponent,
        blue: source.blueComponent,
        alpha: source.alphaComponent
      )
    }
    return result
  }

  private static func accentBase(for appearance: NSAppearance) -> NSColor {
    if usesSystemAccent {
      return .controlAccentColor
    }
    return isDark(appearance) ? amber : amberOnLight
  }

  /// AppKit resolves a system color returned here in the drawing appearance it is already
  /// using, so the provider only picks a side.
  private static func dynamic(_ name: String, light: NSColor, dark: NSColor) -> NSColor {
    NSColor(name: NSColor.Name(name)) { appearance in
      isDark(appearance) ? dark : light
    }
  }

  private static func rgb(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(
      srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
      green: CGFloat((hex >> 8) & 0xFF) / 255,
      blue: CGFloat(hex & 0xFF) / 255,
      alpha: alpha
    )
  }
}
