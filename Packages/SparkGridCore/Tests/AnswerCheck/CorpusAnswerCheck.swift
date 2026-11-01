import CryptoKit
import FileFormats
import Foundation
import Model
import XCTest

@testable import Engine

/// Saved-result check for files named in `corpus/manifest.json`.
/// Cell values are not printed: the corpus can hold customer workbooks.
@MainActor
final class CorpusAnswerCheck: XCTestCase {
  func testCorpusSavedResults() throws {
    let env = ProcessInfo.processInfo.environment
    if env["CI"] != nil || env["SPARK_GRID_CI"] != nil {
      throw XCTSkip("private corpus is not used on hosted CI")
    }
    guard let corpus = env["SPARK_GRID_CORPUS"], !corpus.isEmpty else {
      throw XCTSkip("SPARK_GRID_CORPUS is not set")
    }
    let root = repoRoot()
    let manifestURL = root.appendingPathComponent("corpus/manifest.json")
    let differencesURL = root.appendingPathComponent("corpus/known-differences.md")
    let manifest = try loadManifest(manifestURL)
    let differences = try String(contentsOf: differencesURL, encoding: .utf8)
    XCTAssertFalse(manifest.isEmpty)
    for entry in manifest {
      let fileURL = URL(fileURLWithPath: corpus, isDirectory: true).appendingPathComponent(
        entry.name)
      guard FileManager.default.fileExists(atPath: fileURL.path) else {
        XCTFail("corpus file missing: \(entry.name)")
        continue
      }
      let data = try Data(contentsOf: fileURL)
      let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
      guard digest == entry.sha256.lowercased() else {
        XCTFail("checksum mismatch for \(entry.name)")
        continue
      }
      let workbook = try XLSXCodec.importWorkbook(from: data)
      let exempt = exemptions(in: differences, fileName: entry.name)
      let editSheets = ["June", "January"]
      let paths = AnswerComparison.comparePaths(
        in: workbook, editSheetNames: editSheets, exempt: exempt)
      let exempted = exempt.count
      var failures: [String] = []
      for path in paths {
        let seedNote = path.name == "shuffled" ? " seed \(AnswerComparison.displayShuffleSeed)" : ""
        print(
          "corpus answer check: file \(entry.name) \(path.name)\(seedNote) checked \(path.checked) mismatches \(path.mismatches.count) exempt \(exempted)"
        )
        if !path.mismatches.isEmpty {
          let sample = path.mismatches.prefix(15).map(\.key).joined(separator: ", ")
          failures.append(
            "\(path.name) checked \(path.checked) mismatches \(path.mismatches.count). cells \(sample)"
          )
        }
      }
      if let edits = paths.first(where: { $0.name == "edits" }), edits.editedSheets == 0 {
        failures.append("edits did not run on \(editSheets.joined(separator: ", "))")
      }
      if !failures.isEmpty {
        XCTFail("corpus answer check: \(entry.name) \(failures.joined(separator: " | "))")
      }
    }
  }

  private struct ManifestEntry {
    var name: String
    var sha256: String
  }

  private func loadManifest(_ url: URL) throws -> [ManifestEntry] {
    let data = try Data(contentsOf: url)
    let object = try JSONSerialization.jsonObject(with: data)
    guard let root = object as? [String: Any], let files = root["files"] as? [[String: Any]] else {
      XCTFail("corpus manifest is unreadable")
      return []
    }
    return files.compactMap { item in
      guard let name = item["name"] as? String, let sha256 = item["sha256"] as? String else {
        return nil
      }
      return ManifestEntry(name: name, sha256: sha256)
    }
  }

  private func exemptions(in markdown: String, fileName: String) -> Set<String> {
    let needle = fileName.lowercased()
    var keys: Set<String> = []
    for raw in markdown.split(separator: "\n") {
      let line = String(raw)
      guard line.lowercased().contains(needle) else { continue }
      guard
        let range = line.range(
          of: #"([A-Za-z0-9][^!|\n]*![A-Z]+[0-9]+)"#, options: .regularExpression)
      else { continue }
      keys.insert(line[range].lowercased())
    }
    return keys
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
