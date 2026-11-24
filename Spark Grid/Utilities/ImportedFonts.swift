import AppKit
import CoreText
import SparkGridCore
import UniformTypeIdentifiers

/// Fonts people add to Spark Grid (Format › Add Fonts…): copied into Spark Grid's own folder and
/// loaded for Spark Grid each time it opens, so they show in the font menu without installing
/// them for the whole Mac (asked for by Sam, Nov 19). A file that uses one shows the Mac's
/// standard font on a Mac that does not have it.
@MainActor
enum ImportedFonts {
  static var folder: URL? {
    guard
      let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        .first
    else { return nil }
    return base.appendingPathComponent("Fonts", isDirectory: true)
  }

  static let fileExtensions: Set<String> = ["ttf", "otf", "ttc", "otc"]

  /// Loads every font added earlier. Called once at launch.
  static func registerSaved() {
    guard let folder,
      let files = try? FileManager.default.contentsOfDirectory(
        at: folder, includingPropertiesForKeys: nil)
    else { return }
    let fonts = files.filter { fileExtensions.contains($0.pathExtension.lowercased()) }
    guard !fonts.isEmpty else { return }
    CTFontManagerRegisterFontURLs(fonts as CFArray, .process, true, nil)
    CellFormatRenderer.reloadInstalledFontFamilies()
  }

  /// Asks for font files, copies and loads them, and says which families were added.
  static func chooseAndAdd(in window: NSWindow?, then done: @escaping ([String]) -> Void) {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = true
    panel.canChooseDirectories = false
    panel.allowedContentTypes = [.font]
    panel.message = "Choose font files (.ttf, .otf or .ttc) to use in Spark Grid."
    panel.prompt = "Add Fonts"
    let handle: (NSApplication.ModalResponse) -> Void = { response in
      guard response == .OK else { return }
      done(add(panel.urls))
    }
    if let window {
      panel.beginSheetModal(for: window, completionHandler: handle)
    } else {
      handle(panel.runModal())
    }
  }

  static func add(_ urls: [URL]) -> [String] {
    guard let folder else { return [] }
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    var families: [String] = []
    for url in urls where fileExtensions.contains(url.pathExtension.lowercased()) {
      let copy = folder.appendingPathComponent(url.lastPathComponent)
      if FileManager.default.fileExists(atPath: copy.path) {
        CTFontManagerUnregisterFontsForURL(copy as CFURL, .process, nil)
        try? FileManager.default.removeItem(at: copy)
      }
      guard (try? FileManager.default.copyItem(at: url, to: copy)) != nil else { continue }
      guard CTFontManagerRegisterFontsForURL(copy as CFURL, .process, nil) else {
        try? FileManager.default.removeItem(at: copy)
        continue
      }
      let descriptors =
        CTFontManagerCreateFontDescriptorsFromURL(copy as CFURL) as? [CTFontDescriptor] ?? []
      for descriptor in descriptors {
        if let family = CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute)
          as? String, !families.contains(family)
        {
          families.append(family)
        }
      }
    }
    CellFormatRenderer.reloadInstalledFontFamilies()
    return families
  }
}
