import Model
import XCTest

final class SheetProtectionTests: XCTestCase {
  func testLegacyHashMatchesOtherApps() {
    // Values from openpyxl's implementation of the same hash.
    XCTAssertEqual(SheetProtection.legacyHash("test"), "CBEB")
    XCTAssertEqual(SheetProtection.legacyHash("secret"), "DAA7")
    XCTAssertEqual(SheetProtection.legacyHash("password"), "83AF")
    XCTAssertEqual(SheetProtection.legacyHash("Spark Grid 1.4!"), "8DDC")
  }

  func testProtectWithAndWithoutPassword() {
    let open = SheetProtection.element(password: nil)
    XCTAssertTrue(SheetProtection.isOn(open))
    XCTAssertFalse(SheetProtection.hasPassword(open))
    XCTAssertTrue(SheetProtection.verify("", against: open))

    let locked = SheetProtection.element(password: "secret")
    XCTAssertTrue(SheetProtection.hasPassword(locked))
    XCTAssertTrue(SheetProtection.verify("secret", against: locked))
    XCTAssertFalse(SheetProtection.verify("Secret", against: locked))
    XCTAssertFalse(SheetProtection.isOn(nil))
    XCTAssertFalse(SheetProtection.isOn(#"<sheetProtection sheet="0"/>"#))
  }

  func testSHA512PasswordFromNewerFiles() {
    // Worked out separately in Python with the same salt, UTF-16 password and counter.
    let xml =
      #"<sheetProtection algorithmName="SHA-512" hashValue="4IIHILXO1FuzX8tmBs0//tNQC2ok9ew8zGHJKJ/toBoIT6vO7JyvxV2Chzw3wBGuGwClBt0TI//vkVTCTu0n3g==" saltValue="MDEyMzQ1Njc4OWFiY2RlZg==" spinCount="1000" sheet="1"/>"#
    XCTAssertTrue(SheetProtection.verify("Spark", against: xml))
    XCTAssertFalse(SheetProtection.verify("spark", against: xml))
  }
}

final class SheetProtectionPermissionTests: XCTestCase {
  func testExcelAllowFlagsRead() {
    let xml =
      #"<sheetProtection sheet="1" objects="1" scenarios="1" formatCells="0" insertRows="0" sort="0" autoFilter="1"/>"#
    XCTAssertEqual(SheetProtection.permissions(in: xml), [.formatCells, .insertRows, .sort])
    XCTAssertFalse(SheetProtection.allows(.deleteRows, in: xml))
    XCTAssertFalse(SheetProtection.allows(.autoFilter, in: xml))
    XCTAssertTrue(SheetProtection.allows(.deleteRows, in: nil), "no protection allows all")
  }

  func testWrittenFlagsReadBack() {
    let xml = SheetProtection.element(password: "test", allowing: [.sort, .formatColumns])
    XCTAssertTrue(xml.contains(#"password="CBEB""#))
    XCTAssertTrue(xml.contains(#"formatColumns="0""#))
    XCTAssertTrue(xml.contains(#"sort="0""#))
    XCTAssertEqual(SheetProtection.permissions(in: xml), [.sort, .formatColumns])
    XCTAssertEqual(
      SheetProtection.permissions(in: SheetProtection.element(password: nil)), [])
  }
}
