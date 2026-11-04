import FileFormats
import Foundation
import Model
import XCTest

/// Sheet tab colors, read from and written to the sheet's own properties.
final class TabColorTests: XCTestCase {
  private func extras(_ xml: String?) -> SheetFileExtras {
    var extras = SheetFileExtras()
    extras.sheetPropertiesXML = xml
    return extras
  }

  func testReadsRGBThemeAndIndexedColors() {
    XCTAssertEqual(extras(#"<sheetPr><tabColor rgb="FFFF8800"/></sheetPr>"#).tabColorHex, "FF8800")
    XCTAssertEqual(
      extras(#"<sheetPr><tabColor theme="5" tint="0.4"/></sheetPr>"#).tabColorHex, "ED7D31")
    XCTAssertEqual(extras(#"<sheetPr><tabColor indexed="10"/></sheetPr>"#).tabColorHex, "FF0000")
    XCTAssertNil(extras(#"<sheetPr filterMode="1"/>"#).tabColorHex)
    XCTAssertNil(extras(nil).tabColorHex)
  }

  func testSettingKeepsTheOtherProperties() {
    var a = extras(nil)
    a.tabColorHex = "34a853"
    XCTAssertEqual(a.sheetPropertiesXML, #"<sheetPr><tabColor rgb="FF34A853"/></sheetPr>"#)

    var b = extras(#"<sheetPr filterMode="1"/>"#)
    b.tabColorHex = "FF0000"
    XCTAssertEqual(
      b.sheetPropertiesXML, #"<sheetPr filterMode="1"><tabColor rgb="FFFF0000"/></sheetPr>"#)

    var c = extras(#"<sheetPr><tabColor theme="4"/><outlinePr summaryBelow="0"/></sheetPr>"#)
    c.tabColorHex = "000000"
    XCTAssertEqual(
      c.sheetPropertiesXML,
      #"<sheetPr><tabColor rgb="FF000000"/><outlinePr summaryBelow="0"/></sheetPr>"#)
    c.tabColorHex = nil
    XCTAssertEqual(c.sheetPropertiesXML, #"<sheetPr><outlinePr summaryBelow="0"/></sheetPr>"#)

    var d = extras(#"<sheetPr><tabColor rgb="FF123456"/></sheetPr>"#)
    d.tabColorHex = nil
    XCTAssertNil(d.sheetPropertiesXML, "an empty sheetPr is dropped")
  }

  func testTabColorSurvivesSaveAndReopen() throws {
    var sheet = Sheet(name: "Colored")
    sheet.fileExtras.tabColorHex = "4472C4"
    let saved = try XLSXCodec.exportWorkbook(Workbook(sheets: [sheet, Sheet(name: "Plain")]))
    let reopened = try XLSXCodec.importWorkbook(from: saved)
    XCTAssertEqual(reopened.sheets[0].fileExtras.tabColorHex, "4472C4")
    XCTAssertNil(reopened.sheets[1].fileExtras.tabColorHex)
  }
}
