import FileFormats
import Model
import XCTest

/// Excel's theme color numbers put light before dark for the first four colors.
final class ThemeColorIndexTests: XCTestCase {
  private let scheme = ThemeColorScheme.parse(
    themeXML: """
      <a:clrScheme name="Office"><a:dk1><a:sysClr val="windowText" lastClr="000000"/></a:dk1>\
      <a:lt1><a:sysClr val="window" lastClr="FFFFFF"/></a:lt1><a:dk2><a:srgbClr val="44546A"/>\
      </a:dk2><a:lt2><a:srgbClr val="E7E6E6"/></a:lt2><a:accent1><a:srgbClr val="4472C4"/>\
      </a:accent1></a:clrScheme>
      """)

  /// The default font is `theme="1"`. It is black text, not white.
  func testThemeOneIsDarkText() {
    let white = CodableColor(red: 1, green: 1, blue: 1, alpha: 1)
    let black = CodableColor(red: 0, green: 0, blue: 0, alpha: 1)
    XCTAssertEqual(scheme.color(themeIndex: 0), white)
    XCTAssertEqual(scheme.color(themeIndex: 1), black)
    XCTAssertEqual(scheme.color(themeIndex: 2)?.red ?? 0, 0xE7 / 255.0, accuracy: 1e-9)
    XCTAssertEqual(scheme.color(themeIndex: 3)?.red ?? 0, 0x44 / 255.0, accuracy: 1e-9)
    XCTAssertEqual(scheme.color(themeIndex: 4)?.blue ?? 0, 0xC4 / 255.0, accuracy: 1e-9)
  }

  /// Excel's default text color stays automatic, so it is dark in light mode and light in
  /// dark mode, and is not saved back as a fixed color. Other text colors are kept.
  func testDefaultTextColorStaysAutomatic() {
    let styles = """
      <styleSheet><fonts count="4"><font><sz val="11"/><color theme="1"/></font>\
      <font><color theme="1" tint="0.5"/></font><font><color rgb="FFFF0000"/></font>\
      <font><color auto="1"/></font></fonts>\
      <cellXfs count="4"><xf fontId="0"/><xf fontId="1"/><xf fontId="2"/><xf fontId="3"/>\
      </cellXfs></styleSheet>
      """
    let colors = ThemeColorLookup.parseStyleColors(stylesXML: styles, scheme: scheme)
    XCTAssertNil(colors.fontColorsByCellXfId[0])
    XCTAssertEqual(colors.fontColorsByCellXfId[1]?.red ?? 0, 0.5, accuracy: 1e-9)
    XCTAssertEqual(
      colors.fontColorsByCellXfId[2], CodableColor(red: 1, green: 0, blue: 0, alpha: 1))
    XCTAssertNil(colors.fontColorsByCellXfId[3])
  }
}
