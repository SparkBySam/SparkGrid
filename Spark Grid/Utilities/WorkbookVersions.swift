import AppKit
import Foundation

/// Earlier versions of a saved workbook, kept in the Mac's own version store as other document
/// apps keep theirs (Sam, Nov 20: "version history"). Each Save keeps one, an autosave at most
/// one every ten minutes, and the first save after opening also keeps the file as it was opened.
enum WorkbookVersions {
  /// Ten minutes between versions kept by autosave.
  static let autosaveInterval: TimeInterval = 600

  /// Keeps the file at `url` as it is now. Off the main thread, inside the file's access.
  nonisolated static func keep(_ url: URL, unlessAlreadyKept: Bool = false) {
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    if unlessAlreadyKept, newestVersionMatchesFile(url) { return }
    _ = try? NSFileVersion.addOfItem(at: url, withContentsOf: url, options: [])
  }

  /// Earlier versions of the file at `url`, newest first.
  static func versions(of url: URL) -> [NSFileVersion] {
    let accessing = url.startAccessingSecurityScopedResource()
    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
    return (NSFileVersion.otherVersionsOfItem(at: url) ?? [])
      .sorted { ($0.modificationDate ?? .distantPast) > ($1.modificationDate ?? .distantPast) }
  }

  /// The version written to a temporary file the app may read later, with the workbook's
  /// extension so it opens the same way.
  static func temporaryCopy(of version: NSFileVersion, from file: URL?) -> URL? {
    let accessing = file?.startAccessingSecurityScopedResource() ?? false
    defer { if accessing { file?.stopAccessingSecurityScopedResource() } }
    let ext = file.map(\.pathExtension).flatMap { $0.isEmpty ? nil : $0 } ?? "xlsx"
    let destination = FileManager.default.temporaryDirectory
      .appendingPathComponent("Version-\(UUID().uuidString)").appendingPathExtension(ext)
    do {
      try FileManager.default.copyItem(at: version.url, to: destination)
      return destination
    } catch {
      return nil
    }
  }

  /// Whether the newest kept version already holds the file as it is on disk.
  nonisolated static func newestVersionMatchesFile(_ url: URL) -> Bool {
    guard
      let newest = (NSFileVersion.otherVersionsOfItem(at: url) ?? []).compactMap(\.modificationDate)
        .max(),
      let fileDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
        .contentModificationDate
    else { return false }
    return newest >= fileDate.addingTimeInterval(-1)
  }

  static func title(of version: NSFileVersion) -> String {
    guard let date = version.modificationDate else { return "Earlier version" }
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .medium
    formatter.doesRelativeDateFormatting = true
    return formatter.string(from: date)
  }
}
