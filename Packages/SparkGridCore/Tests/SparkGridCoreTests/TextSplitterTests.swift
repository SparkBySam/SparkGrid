import Engine
import XCTest

final class TextSplitterTests: XCTestCase {
  private func split(_ text: String, _ delimiters: Set<Character>, merge: Bool = false) -> [String]
  {
    TextSplitter.split(text, options: .init(delimiters: delimiters, mergeRepeats: merge))
  }

  func testCommasAndEmptyFields() {
    XCTAssertEqual(split("a,b,,c", [","]), ["a", "b", "", "c"])
    XCTAssertEqual(split("a,", [","]), ["a", ""])
    XCTAssertEqual(split("plain", [","]), ["plain"])
  }

  func testRepeatedSpacesCountOnce() {
    XCTAssertEqual(split("Ada  Lovelace", [" "], merge: true), ["Ada", "Lovelace"])
    XCTAssertEqual(split("Ada  Lovelace", [" "]), ["Ada", "", "Lovelace"])
  }

  func testQuotedFieldsKeepTheirDelimiters() {
    XCTAssertEqual(split("\"Smith, Jo\",42", [","]), ["Smith, Jo", "42"])
    XCTAssertEqual(split("\"say \"\"hi\"\"\",x", [","]), ["say \"hi\"", "x"])
    XCTAssertEqual(split("5\" pipe,2", [","]), ["5\" pipe", "2"])
  }

  func testSeveralDelimiters() {
    XCTAssertEqual(split("a;b\tc", [";", "\t"]), ["a", "b", "c"])
  }
}

final class FixedWidthSplitTests: XCTestCase {
  func testCutsAtBreaksAndTrims() {
    let options = TextSplitter.Options.fixedWidth([6, 12])
    XCTAssertEqual(TextSplitter.split("Alex  Smith 42", options: options), ["Alex", "Smith", "42"])
    XCTAssertEqual(TextSplitter.split("Bo", options: options), ["Bo", "", ""])
    XCTAssertEqual(TextSplitter.split("a,b c", options: options), ["a,b c", "", ""])
  }

  func testSuggestsBreaksBetweenLinedUpColumns() {
    let lines = [
      "Alex   Smith   42",
      "Bo     Jones   7",
      "Cyrus  Lee     100",
    ]
    XCTAssertEqual(TextSplitter.suggestedBreaks(lines), [7, 15])
    XCTAssertEqual(
      TextSplitter.split(lines[2], options: .fixedWidth([7, 15])), ["Cyrus", "Lee", "100"])
  }
}
