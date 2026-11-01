import FileFormats
import Foundation
import GridCore
import Model
import XCTest

@testable import Engine

@MainActor
final class LedgerAnswerCheck: XCTestCase {
  func testLedgerGroundTruth() throws {
    guard ProcessInfo.processInfo.environment["SPARK_GRID_LEDGER_CHECK"] == "1" else {
      throw XCTSkip(
        "Ledger ground truth runs from scripts/check-ledger.sh (SPARK_GRID_LEDGER_CHECK=1)."
      )
    }
    let paths = try ledgerPaths()
    let workbook = try XLSXCodec.importWorkbook(from: paths.xlsx)
    let expected = try loadAnswers(paths.answers)
    let cleared = AnswerComparison.clearingFormulaCaches(workbook)
    let actual = AnswerComparison.calculatedFormulaResults(in: cleared)
    let result = AnswerComparison.mismatches(expected: expected, actual: actual)
    print(
      "ledger answer check: checked \(result.checked) mismatches \(result.mismatches.count)"
    )
    if !result.mismatches.isEmpty {
      let sample = result.mismatches.prefix(15).map {
        "\($0.key) expected \($0.expected) actual \($0.actual)"
      }
      XCTFail(
        "ledger answer check: checked \(result.checked) mismatches \(result.mismatches.count). \(sample.joined(separator: "; "))"
      )
    }
    XCTAssertGreaterThan(result.checked, 0)
  }

  private struct Paths {
    var xlsx: URL
    var answers: URL
  }

  private func ledgerPaths() throws -> Paths {
    let env = ProcessInfo.processInfo.environment
    if let xlsx = env["SPARK_GRID_LEDGER_XLSX"], let answers = env["SPARK_GRID_LEDGER_ANSWERS"],
      !xlsx.isEmpty, !answers.isEmpty
    {
      return Paths(xlsx: URL(fileURLWithPath: xlsx), answers: URL(fileURLWithPath: answers))
    }
    let root = repoRoot()
    let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(
      "spark-grid-ledger-\(ProcessInfo.processInfo.processIdentifier)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let xlsx = directory.appendingPathComponent("ledger.xlsx")
    let answers = directory.appendingPathComponent("answers.txt")
    let script = root.appendingPathComponent("scripts/generate_ledger_workbook.py")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    process.arguments = [script.path, "-o", xlsx.path, "--answers", answers.path]
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      XCTFail("ledger generator exited \(process.terminationStatus)")
      return Paths(xlsx: xlsx, answers: answers)
    }
    return Paths(xlsx: xlsx, answers: answers)
  }

  private func loadAnswers(_ url: URL) throws -> [String: CellValue] {
    let text = try String(contentsOf: url, encoding: .utf8)
    var expected: [String: CellValue] = [:]
    for raw in text.split(separator: "\n") {
      let line = String(raw)
      if line.hasPrefix("#") || line.isEmpty { continue }
      let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
      guard parts.count == 2, let value = AnswerValues.parseToken(parts[1]) else {
        XCTFail("unreadable ledger answer line")
        continue
      }
      expected[parts[0]] = value
    }
    return expected
  }

  private func repoRoot() -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }
}
