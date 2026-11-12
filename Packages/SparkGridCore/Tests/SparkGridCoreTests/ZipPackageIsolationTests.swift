import GridCore
import Model
import XCTest

@testable import FileFormats

/// Two files can be loading at once, in the app and in Quick Look. Each must read only its own
/// parts: one file's sheet names, styles, charts or images must never come from the other.
final class ZipPackageIsolationTests: XCTestCase {
  /// A workbook whose sheet names and cells all carry `marker`.
  private func workbook(_ marker: String, sheets: Int = 1) -> Workbook {
    Workbook(
      sheets: (1...sheets).map { index in
        var sheet = Sheet(name: "\(marker)-\(index)")
        sheet.setCell(Cell(raw: "\(marker) cell \(index)"), at: CellAddress(row: 0, col: 0))
        return sheet
      })
  }

  private func file(_ marker: String, sheets: Int = 1) throws -> Data {
    try XLSXCodec.exportWorkbook(workbook(marker, sheets: sheets))
  }

  private func workbookXML(_ data: Data) -> String {
    XLSXCodec.zipEntryString(archiveData: data, entryPath: "xl/workbook.xml") ?? ""
  }

  func testOverlappingImportsReadTheirOwnParts() throws {
    let a = try file("Alpha")
    let b = try file("Beta")
    let packageA = try ZipPackage(archiveData: a)
    let packageB = try ZipPackage(archiveData: b)
    let aInside = DispatchSemaphore(value: 0)
    let bInside = DispatchSemaphore(value: 0)
    let aRead = DispatchSemaphore(value: 0)
    let finished = DispatchGroup()
    nonisolated(unsafe) var seenByA = ""
    nonisolated(unsafe) var seenByB = ""

    // A starts, then B starts while A is still going, then each reads its own workbook.xml.
    DispatchQueue.global().async(group: finished) {
      ZipPackage.use(packageA) {
        aInside.signal()
        bInside.wait()
        seenByA = self.workbookXML(a)
        aRead.signal()
      }
    }
    aInside.wait()
    DispatchQueue.global().async(group: finished) {
      ZipPackage.use(packageB) {
        bInside.signal()
        aRead.wait()
        seenByB = self.workbookXML(b)
      }
    }
    XCTAssertEqual(finished.wait(timeout: .now() + 20), .success)

    XCTAssertTrue(seenByA.contains("Alpha-1"), "A read: \(seenByA)")
    XCTAssertFalse(seenByA.contains("Beta"), "A read B's sheet names")
    XCTAssertTrue(seenByB.contains("Beta-1"), "B read: \(seenByB)")
    XCTAssertFalse(seenByB.contains("Alpha"), "B read A's sheet names")
  }

  func testNothingStaysInUseAfterImportsFinishOutOfOrder() throws {
    let a = try file("Alpha")
    let b = try file("Beta")
    let packageA = try ZipPackage(archiveData: a)
    let packageB = try ZipPackage(archiveData: b)
    let aInside = DispatchSemaphore(value: 0)
    let bInside = DispatchSemaphore(value: 0)
    let aLeft = DispatchSemaphore(value: 0)
    let finished = DispatchGroup()

    // A starts, B starts, A finishes, B finishes: not the order a stack would unwind in.
    DispatchQueue.global().async(group: finished) {
      ZipPackage.use(packageA) {
        aInside.signal()
        bInside.wait()
      }
      aLeft.signal()
    }
    aInside.wait()
    DispatchQueue.global().async(group: finished) {
      ZipPackage.use(packageB) {
        bInside.signal()
        aLeft.wait()
        XCTAssertTrue(ZipPackage.cachedEntry(in: b, at: "xl/workbook.xml").0, "B still loading")
        XCTAssertFalse(ZipPackage.cachedEntry(in: a, at: "xl/workbook.xml").0, "A has finished")
      }
    }
    XCTAssertEqual(finished.wait(timeout: .now() + 20), .success)

    XCTAssertFalse(ZipPackage.cachedEntry(in: a, at: "xl/workbook.xml").0)
    XCTAssertFalse(ZipPackage.cachedEntry(in: b, at: "xl/workbook.xml").0)
    // Later reads of either file, and of a third, still get the right file.
    XCTAssertTrue(workbookXML(a).contains("Alpha-1"))
    XCTAssertTrue(workbookXML(b).contains("Beta-1"))
    XCTAssertTrue(workbookXML(try file("Gamma")).contains("Gamma-1"))
  }

  func testAnotherFilesReadDuringAnImportComesFromThatFile() throws {
    let a = try file("Alpha")
    let b = try file("Beta")
    let packageA = try ZipPackage(archiveData: a)
    ZipPackage.use(packageA) {
      // B is not being imported: its read opens B, and must not be answered from A.
      XCTAssertFalse(ZipPackage.cachedEntry(in: b, at: "xl/workbook.xml").0)
      let seen = workbookXML(b)
      XCTAssertTrue(seen.contains("Beta-1"), "read: \(seen)")
      XCTAssertFalse(seen.contains("Alpha"))
      XCTAssertNil(
        XLSXCodec.zipEntryData(archiveData: b, entryPath: "xl/no-such-part.xml"))
    }
  }

  func testReadsDuringAnImportAreServedFromMemory() throws {
    let data = try file("Alpha")
    let package = try ZipPackage(archiveData: data)
    final class Holder {
      let data: Data
      init(_ data: Data) { self.data = data }
    }
    let holder = Holder(data)
    XCTAssertFalse(ZipPackage.cachedEntry(in: data, at: "xl/workbook.xml").0, "before the import")
    ZipPackage.use(package) {
      // The same archive, however the value reached the reader: as a copy, or kept by an object.
      let copy = data
      XCTAssertTrue(ZipPackage.cachedEntry(in: data, at: "xl/workbook.xml").0)
      XCTAssertTrue(ZipPackage.cachedEntry(in: copy, at: "xl/workbook.xml").0)
      XCTAssertTrue(ZipPackage.cachedEntry(in: holder.data, at: "xl/workbook.xml").0)
      XCTAssertNotNil(ZipPackage.cachedEntry(in: data, at: "xl/workbook.xml").1)
      // In use and the part is missing: no part, without opening the archive again.
      let missing = ZipPackage.cachedEntry(in: data, at: "xl/no-such-part.xml")
      XCTAssertTrue(missing.0)
      XCTAssertNil(missing.1)
      // Worker threads of the import see it too.
      DispatchQueue.concurrentPerform(iterations: 4) { _ in
        XCTAssertTrue(ZipPackage.cachedEntry(in: holder.data, at: "xl/workbook.xml").0)
      }
      // One import inside another of the same file keeps it in use until both end.
      ZipPackage.use(package) {}
      XCTAssertTrue(ZipPackage.cachedEntry(in: data, at: "xl/workbook.xml").0)
    }
    XCTAssertFalse(ZipPackage.cachedEntry(in: data, at: "xl/workbook.xml").0, "after the import")
  }

  func testManyWorkbooksImportedAtOnceKeepTheirOwnContents() throws {
    let markers = (0..<8).map { "Book\($0)" }
    let files = try markers.map { try file($0, sheets: 4) }
    for round in 0..<6 {
      nonisolated(unsafe) var results = [Result<Workbook, Error>?](
        repeating: nil, count: files.count)
      let lock = NSLock()
      DispatchQueue.concurrentPerform(iterations: files.count) { index in
        let result = Result { try XLSXCodec.importWorkbook(from: files[index]) }
        lock.lock()
        results[index] = result
        lock.unlock()
      }
      for (index, marker) in markers.enumerated() {
        let imported = try XCTUnwrap(results[index]).get()
        XCTAssertEqual(
          imported.sheets.map(\.name), (1...4).map { "\(marker)-\($0)" }, "round \(round)")
        for (offset, sheet) in imported.sheets.enumerated() {
          XCTAssertEqual(
            sheet.cell(at: CellAddress(row: 0, col: 0)).raw, "\(marker) cell \(offset + 1)",
            "round \(round)")
        }
      }
    }
  }
}
