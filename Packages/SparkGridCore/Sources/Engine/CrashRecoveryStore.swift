import FileFormats
import Foundation
import Model

/// Crash-safe copy of an open workbook. A clean quit removes the session marker.
public nonisolated enum CrashRecoveryStore {
  public static let sessionMarkerName = "session-open"
  public static let snapshotName = "recovery.xlsx"
  private static let metaName = "recovery.json"

  public struct Meta: Codable, Equatable, Sendable {
    public var documentPath: String?
    public var savedAt: Date
  }

  public static func defaultDirectory() -> URL {
    let base =
      FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSTemporaryDirectory())
    return base.appendingPathComponent("Spark Grid/CrashRecovery", isDirectory: true)
  }

  public static func beginSession(in directory: URL = defaultDirectory()) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let marker = directory.appendingPathComponent(sessionMarkerName)
    if !FileManager.default.fileExists(atPath: marker.path) {
      try Data().write(to: marker, options: .atomic)
    }
  }

  public static func noteCleanExit(in directory: URL = defaultDirectory()) {
    clear(in: directory)
  }

  public static func needsRestore(in directory: URL = defaultDirectory()) -> Bool {
    let marker = directory.appendingPathComponent(sessionMarkerName)
    let snapshot = directory.appendingPathComponent(snapshotName)
    return FileManager.default.fileExists(atPath: marker.path)
      && FileManager.default.fileExists(atPath: snapshot.path)
  }

  public static func write(
    workbook: Workbook,
    documentPath: String?,
    in directory: URL = defaultDirectory()
  ) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let data = try XLSXCodec.exportWorkbook(workbook, includeFormulaCaches: true)
    let snapshot = directory.appendingPathComponent(snapshotName)
    let temporary = directory.appendingPathComponent("recovery.xlsx.tmp")
    try data.write(to: temporary, options: .atomic)
    if FileManager.default.fileExists(atPath: snapshot.path) {
      _ = try FileManager.default.replaceItemAt(snapshot, withItemAt: temporary)
    } else {
      try FileManager.default.moveItem(at: temporary, to: snapshot)
    }
    let meta = Meta(documentPath: documentPath, savedAt: Date())
    let encoded = try JSONEncoder().encode(meta)
    try encoded.write(to: directory.appendingPathComponent(metaName), options: .atomic)
    try beginSession(in: directory)
  }

  public static func load(in directory: URL = defaultDirectory()) throws -> (
    workbook: Workbook, documentPath: String?
  ) {
    let data = try Data(contentsOf: directory.appendingPathComponent(snapshotName))
    let workbook = try XLSXCodec.importWorkbook(from: data)
    let metaURL = directory.appendingPathComponent(metaName)
    let path = (try? Data(contentsOf: metaURL)).flatMap { data in
      try? JSONDecoder().decode(Meta.self, from: data).documentPath
    }
    return (workbook, path)
  }

  public static func clear(in directory: URL = defaultDirectory()) {
    let names = [sessionMarkerName, snapshotName, metaName, "recovery.xlsx.tmp"]
    for name in names {
      let url = directory.appendingPathComponent(name)
      try? FileManager.default.removeItem(at: url)
    }
  }
}

public nonisolated enum BackgroundWriteError: Error, Equatable {
  case refusingMainThread
}

public nonisolated enum BackgroundWriteGuard {
  public static func requireBackgroundThread() throws {
    if Thread.isMainThread {
      throw BackgroundWriteError.refusingMainThread
    }
  }
}
