import AppKit
import Foundation
import Observation
import SparkGridCore
import SwiftUI

/// When the grid's scroll bars show.
enum ScrollBarVisibility: String, CaseIterable, Identifiable {
  /// As System Settings › Appearance › Show scroll bars says.
  case automatic
  /// Always on screen, with their tracks, as classic scroll bars are.
  case always
  /// Only while scrolling, or with the pointer at the edge.
  case whenScrolling

  var id: String { rawValue }

  var title: String {
    switch self {
    case .automatic: return "Automatic"
    case .always: return "Always"
    case .whenScrolling: return "When scrolling"
    }
  }
}

/// How much of the sheet the scroll bars stand for.
enum ScrollBarLength: String, CaseIterable, Identifiable {
  /// The rows and columns in use and half a screen more, as other spreadsheet apps do.
  case rowsInUse
  /// The whole grid, 1,000 rows and more.
  case wholeGrid

  var id: String { rawValue }

  var title: String {
    switch self {
    case .rowsInUse: return "Rows in use"
    case .wholeGrid: return "Whole grid"
    }
  }
}

enum AppearanceMode: String, CaseIterable, Identifiable, Codable {
  case system
  case light
  case dark

  var id: String { rawValue }

  var title: String {
    switch self {
    case .system: return "System"
    case .light: return "Light"
    case .dark: return "Dark"
    }
  }

  var colorScheme: ColorScheme? {
    switch self {
    case .system: return nil
    case .light: return .light
    case .dark: return .dark
    }
  }
}

enum HotkeyAction: String, CaseIterable, Identifiable, Codable {
  case copy
  case cut
  case paste
  case copyFormulas
  case pasteFormulas
  case pasteValues
  case fillDown
  case fillRight
  case convertToValues
  case undo
  case redo
  case save
  case bold
  case italic
  case underline
  case autoSum
  case clearFormats
  case newWorkbook
  case newFromTemplate
  case open
  case saveAs
  case print
  case find
  case findAndReplace
  case findNext
  case findPrevious
  case goTo
  case selectAll
  case editCell
  case openDropdown
  case insertLink
  case formulaHelp
  case groupRowsOrColumns
  case ungroupRowsOrColumns
  case zoomIn
  case zoomOut
  case actualSize
  case help

  var id: String { rawValue }

  /// Where the action sits in Settings.
  enum Group: String, CaseIterable, Identifiable {
    case file = "File"
    case edit = "Edit"
    case cells = "Cells"
    case find = "Find"
    case formulas = "Formulas"
    case format = "Format"
    case insert = "Insert and Sheet"
    case view = "View and Help"
    var id: String { rawValue }
  }

  var group: Group {
    switch self {
    case .newWorkbook, .newFromTemplate, .open, .save, .saveAs, .print: return .file
    case .copy, .cut, .paste, .undo, .redo, .fillDown, .fillRight, .selectAll: return .edit
    case .editCell, .openDropdown, .goTo: return .cells
    case .find, .findAndReplace, .findNext, .findPrevious: return .find
    case .copyFormulas, .pasteFormulas, .pasteValues, .convertToValues, .autoSum, .formulaHelp:
      return .formulas
    case .bold, .italic, .underline, .clearFormats: return .format
    case .insertLink, .groupRowsOrColumns, .ungroupRowsOrColumns: return .insert
    case .zoomIn, .zoomOut, .actualSize, .help: return .view
    }
  }

  var detail: String {
    switch self {
    case .copyFormulas: return "Copies the formulas, not their results"
    case .pasteFormulas: return "Pastes formulas and adjusts their references"
    case .pasteValues: return "Pastes results only, without formulas or formats"
    case .fillDown: return "Copies the top row down the selection"
    case .fillRight: return "Copies the left column across the selection"
    case .convertToValues: return "Replaces the selected formulas with their results"
    case .autoSum: return "Adds the numbers above or to the left"
    case .clearFormats: return "Takes fonts, colors, borders and number formats off the selection"
    case .goTo: return "Puts the cursor in the name box: type a cell, range or name"
    case .editCell: return "Edits the selected cell with the cursor at the end"
    case .openDropdown: return "Opens a cell's dropdown list"
    case .formulaHelp: return "Writes or explains a formula with Apple Intelligence"
    case .groupRowsOrColumns: return "Groups the selected rows or columns"
    case .ungroupRowsOrColumns: return "Ungroups the selected rows or columns"
    default: return ""
    }
  }

  var displayName: String {
    switch self {
    case .copy: return "Copy"
    case .cut: return "Cut"
    case .paste: return "Paste"
    case .copyFormulas: return "Copy Formulas"
    case .pasteFormulas: return "Paste Formulas"
    case .pasteValues: return "Paste Values"
    case .fillDown: return "Fill Down"
    case .fillRight: return "Fill Right"
    case .convertToValues: return "Convert to Values"
    case .undo: return "Undo"
    case .redo: return "Redo"
    case .save: return "Save"
    case .bold: return "Bold"
    case .italic: return "Italic"
    case .underline: return "Underline"
    case .autoSum: return "AutoSum"
    case .clearFormats: return "Clear Formats"
    case .newWorkbook: return "New Spreadsheet"
    case .newFromTemplate: return "New from Template"
    case .open: return "Open"
    case .saveAs: return "Save As"
    case .print: return "Print"
    case .find: return "Find"
    case .findAndReplace: return "Find and Replace"
    case .findNext: return "Find Next"
    case .findPrevious: return "Find Previous"
    case .goTo: return "Go To"
    case .selectAll: return "Select All"
    case .editCell: return "Edit Cell"
    case .openDropdown: return "Open Dropdown List"
    case .insertLink: return "Insert Link"
    case .formulaHelp: return "Formula Help"
    case .groupRowsOrColumns: return "Group"
    case .ungroupRowsOrColumns: return "Ungroup"
    case .zoomIn: return "Zoom In"
    case .zoomOut: return "Zoom Out"
    case .actualSize: return "Actual Size"
    case .help: return "Spark Grid Help"
    }
  }
}

struct StoredShortcut: Codable, Equatable, Hashable {
  var key: String
  var modifiers: UInt

  static let `default` = StoredShortcut(key: "", modifiers: 0)

  var displayString: String {
    guard !key.isEmpty else { return "—" }
    var parts: [String] = []
    let flags = NSEvent.ModifierFlags(rawValue: modifiers)
    if flags.contains(.control) { parts.append("⌃") }
    if flags.contains(.option) { parts.append("⌥") }
    if flags.contains(.shift) { parts.append("⇧") }
    if flags.contains(.command) { parts.append("⌘") }
    parts.append(Self.keyName(key))
    return parts.joined()
  }

  /// F1 to F12, arrows and the rest, which have no printable character of their own.
  static let specialKeys: [String: String] = {
    var names: [String: String] = [
      "\u{F700}": "↑", "\u{F701}": "↓", "\u{F702}": "←", "\u{F703}": "→",
      "\u{F728}": "⌦", "\u{F729}": "↖", "\u{F72B}": "↘", "\u{F72C}": "⇞", "\u{F72D}": "⇟",
      "\r": "↩", "\t": "⇥", " ": "Space", "\u{7F}": "⌫", "\u{1B}": "⎋",
    ]
    for n in 1...20 {
      if let scalar = UnicodeScalar(0xF703 + n) { names[String(Character(scalar))] = "F\(n)" }
    }
    return names
  }()

  static func keyName(_ key: String) -> String {
    specialKeys[key] ?? key.uppercased()
  }

  /// F1 to F20: these work without ⌘, ⌥ or ⌃, as F2 does.
  var isFunctionKey: Bool {
    guard let scalar = key.unicodeScalars.first, key.unicodeScalars.count == 1 else {
      return false
    }
    return (0xF704...0xF717).contains(scalar.value)
  }

  func matches(_ event: NSEvent) -> Bool {
    guard let chars = event.charactersIgnoringModifiers?.lowercased(), !chars.isEmpty else {
      return false
    }
    let first = String(chars.prefix(1))
    guard first == key.lowercased() else { return false }
    let relevant: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
    return event.modifierFlags.intersection(relevant)
      == NSEvent.ModifierFlags(rawValue: modifiers).intersection(relevant)
  }
}

@Observable
@MainActor
final class AppSettings {
  static let shared = AppSettings()

  private let defaults = UserDefaults.standard
  private let invertScrollKey = "invertScrollDirection"
  private let toolbarLabelsKey = "showToolbarLabels"
  private let appearanceModeKey = "appearanceMode"
  private let autosaveEnabledKey = "autosaveEnabled"
  private let warnsUncalculatedKey = "warnsUncalculatedFormulas"
  private let keepVersionsKey = "keepVersions"
  private let appleIntelligenceKey = "usesAppleIntelligence"
  private let autosaveIntervalKey = "autosaveIntervalSeconds"
  private let startScreenKey = "showStartScreen"
  private let shortcutsKey = "keyboardShortcuts"
  private let scrollBarVisibilityKey = "scrollBarVisibility"
  private let scrollBarLengthKey = "scrollBarLength"

  /// Posted when a scroll bar setting changes, for the grids to redraw their bars.
  static let scrollBarsChanged = Notification.Name("SparkGridScrollBarsChanged")

  static let autosaveIntervalOptions = [10, 30, 60, 120, 300]

  var invertScrollDirection: Bool {
    didSet { defaults.set(invertScrollDirection, forKey: invertScrollKey) }
  }

  var scrollBarVisibility: ScrollBarVisibility {
    didSet {
      defaults.set(scrollBarVisibility.rawValue, forKey: scrollBarVisibilityKey)
      NotificationCenter.default.post(name: Self.scrollBarsChanged, object: nil)
    }
  }

  var scrollBarLength: ScrollBarLength {
    didSet {
      defaults.set(scrollBarLength.rawValue, forKey: scrollBarLengthKey)
      NotificationCenter.default.post(name: Self.scrollBarsChanged, object: nil)
    }
  }

  /// Whether the bars stay on screen: the setting, or with Automatic, the system's.
  var scrollBarsAlwaysShown: Bool {
    switch scrollBarVisibility {
    case .always: return true
    case .whenScrolling: return false
    case .automatic: return NSScroller.preferredScrollerStyle == .legacy
    }
  }

  var showToolbarLabels: Bool {
    didSet { defaults.set(showToolbarLabels, forKey: toolbarLabelsKey) }
  }

  var appearanceMode: AppearanceMode {
    didSet { defaults.set(appearanceMode.rawValue, forKey: appearanceModeKey) }
  }

  var autosaveEnabled: Bool {
    didSet { defaults.set(autosaveEnabled, forKey: autosaveEnabledKey) }
  }

  /// Say so when an opened file has formulas Spark Grid cannot calculate (a Reddit comment,
  /// Nov 20: "Worst thing for a spreadsheet user is breaking it without knowing"). On by default.
  var warnsAboutUncalculatedFormulas: Bool {
    didSet { defaults.set(warnsAboutUncalculatedFormulas, forKey: warnsUncalculatedKey) }
  }

  /// Keep earlier versions of saved workbooks (File › Browse Versions). On unless turned off:
  /// people with very large files may not want the space it takes (Sam, Nov 20).
  var keepVersions: Bool {
    didSet { defaults.set(keepVersions, forKey: keepVersionsKey) }
  }

  /// Formula Help and chart suggestions, with the model built into the Mac. On unless turned
  /// off in Settings › AI; off, they leave the menus and dialogs (Sam, Nov 20).
  var usesAppleIntelligence: Bool {
    didSet { defaults.set(usesAppleIntelligence, forKey: appleIntelligenceKey) }
  }

  var autosaveIntervalSeconds: Int {
    didSet { defaults.set(autosaveIntervalSeconds, forKey: autosaveIntervalKey) }
  }

  /// On (the default): Spark Grid opens to the start screen when it opens with no file.
  var showStartScreen: Bool {
    didSet { defaults.set(showStartScreen, forKey: startScreenKey) }
  }

  /// Off (the default): selection, the fill handle and toggles use Spark amber.
  /// On: they follow the accent color chosen in macOS System Settings.
  var useSystemAccent: Bool {
    didSet {
      defaults.set(useSystemAccent, forKey: SparkTheme.systemAccentDefaultsKey)
      SparkTheme.usesSystemAccent = useSystemAccent
      NotificationCenter.default.post(name: SparkTheme.didChangeNotification, object: nil)
    }
  }

  /// On (the default): text with no color of its own turns light or dark to be read on a
  /// cell's fill, and on a conditional fill. Off: text keeps its color, as other apps show it.
  var readableTextOnFills: Bool {
    didSet {
      defaults.set(readableTextOnFills, forKey: SparkTheme.readableTextDefaultsKey)
      SparkTheme.readableTextOnFills = readableTextOnFills
      NotificationCenter.default.post(name: SparkTheme.didChangeNotification, object: nil)
    }
  }

  private var shortcuts: [HotkeyAction: StoredShortcut]

  private init() {
    invertScrollDirection = defaults.bool(forKey: invertScrollKey)
    scrollBarVisibility =
      defaults.string(forKey: scrollBarVisibilityKey).flatMap(ScrollBarVisibility.init(rawValue:))
      ?? .automatic
    scrollBarLength =
      defaults.string(forKey: scrollBarLengthKey).flatMap(ScrollBarLength.init(rawValue:))
      ?? .rowsInUse
    showToolbarLabels = defaults.bool(forKey: toolbarLabelsKey)
    if let raw = defaults.string(forKey: appearanceModeKey),
      let mode = AppearanceMode(rawValue: raw)
    {
      appearanceMode = mode
    } else {
      appearanceMode = .system
    }
    if defaults.object(forKey: autosaveEnabledKey) != nil {
      autosaveEnabled = defaults.bool(forKey: autosaveEnabledKey)
    } else {
      autosaveEnabled = true
    }
    warnsAboutUncalculatedFormulas =
      defaults.object(forKey: warnsUncalculatedKey) as? Bool ?? true
    keepVersions =
      defaults.object(forKey: keepVersionsKey) == nil
      ? true : defaults.bool(forKey: keepVersionsKey)
    showStartScreen =
      defaults.object(forKey: startScreenKey) == nil ? true : defaults.bool(forKey: startScreenKey)
    usesAppleIntelligence = defaults.object(forKey: appleIntelligenceKey) as? Bool ?? true
    let storedInterval = defaults.integer(forKey: autosaveIntervalKey)
    autosaveIntervalSeconds =
      Self.autosaveIntervalOptions.contains(storedInterval) ? storedInterval : 30
    let readableText =
      defaults.object(forKey: SparkTheme.readableTextDefaultsKey) as? Bool ?? true
    readableTextOnFills = readableText
    SparkTheme.readableTextOnFills = readableText
    let systemAccent = defaults.bool(forKey: SparkTheme.systemAccentDefaultsKey)
    useSystemAccent = systemAccent
    SparkTheme.usesSystemAccent = systemAccent
    if let data = defaults.data(forKey: shortcutsKey),
      let decoded = try? JSONDecoder().decode([HotkeyAction: StoredShortcut].self, from: data)
    {
      shortcuts = decoded
    } else {
      shortcuts = Self.defaultShortcuts
    }
    mergeMissingDefaults()
  }

  func shortcut(for action: HotkeyAction) -> StoredShortcut {
    shortcuts[action] ?? Self.defaultShortcuts[action] ?? .default
  }

  func setShortcut(_ shortcut: StoredShortcut, for action: HotkeyAction) {
    shortcuts[action] = shortcut
    persistShortcuts()
  }

  func defaultShortcut(for action: HotkeyAction) -> StoredShortcut {
    Self.defaultShortcuts[action] ?? .default
  }

  func resetShortcut(for action: HotkeyAction) {
    setShortcut(defaultShortcut(for: action), for: action)
  }

  /// The other action already using `shortcut`, if any.
  func action(using shortcut: StoredShortcut, except action: HotkeyAction) -> HotkeyAction? {
    HotkeyAction.allCases.first { $0 != action && self.shortcut(for: $0) == shortcut }
  }

  /// The system's own commands, which every Mac app shares and can't be reassigned. Every
  /// command of Spark Grid's own can (Sam, Nov 20).
  static let reservedShortcuts: [StoredShortcut: String] = {
    let command = NSEvent.ModifierFlags.command.rawValue
    let pairs: [(String, String)] = [
      ("q", "Quit"), ("w", "Close"), ("h", "Hide"), ("m", "Minimize"), (",", "Settings"),
    ]
    return Dictionary(
      uniqueKeysWithValues: pairs.map { (StoredShortcut(key: $0.0, modifiers: command), $0.1) })
  }()

  func resetShortcutsToDefaults() {
    shortcuts = Self.defaultShortcuts
    persistShortcuts()
  }

  func keyEquivalent(for action: HotkeyAction) -> KeyEquivalent {
    let key = shortcut(for: action).key
    guard let first = key.first else { return KeyEquivalent("a") }
    return KeyEquivalent(first)
  }

  func eventModifiers(for action: HotkeyAction) -> EventModifiers {
    let flags = NSEvent.ModifierFlags(rawValue: shortcut(for: action).modifiers)
    var mods = EventModifiers()
    if flags.contains(.command) { mods.insert(.command) }
    if flags.contains(.shift) { mods.insert(.shift) }
    if flags.contains(.option) { mods.insert(.option) }
    if flags.contains(.control) { mods.insert(.control) }
    return mods
  }

  func matches(_ action: HotkeyAction, event: NSEvent) -> Bool {
    shortcut(for: action).matches(event)
  }

  static func label(forInterval seconds: Int) -> String {
    switch seconds {
    case 10: return "Every 10 seconds"
    case 30: return "Every 30 seconds"
    case 60: return "Every minute"
    case 120: return "Every 2 minutes"
    case 300: return "Every 5 minutes"
    default: return "Every \(seconds) seconds"
    }
  }

  private func persistShortcuts() {
    guard let data = try? JSONEncoder().encode(shortcuts) else { return }
    defaults.set(data, forKey: shortcutsKey)
  }

  private func mergeMissingDefaults() {
    for (action, shortcut) in Self.defaultShortcuts where shortcuts[action] == nil {
      shortcuts[action] = shortcut
    }
  }

  private static let defaultShortcuts: [HotkeyAction: StoredShortcut] = [
    .copy: StoredShortcut(key: "c", modifiers: NSEvent.ModifierFlags.command.rawValue),
    .cut: StoredShortcut(key: "x", modifiers: NSEvent.ModifierFlags.command.rawValue),
    .paste: StoredShortcut(key: "v", modifiers: NSEvent.ModifierFlags.command.rawValue),
    .copyFormulas: StoredShortcut(
      key: "c",
      modifiers: NSEvent.ModifierFlags.command.union(.shift).rawValue
    ),
    .pasteFormulas: StoredShortcut(
      key: "v",
      modifiers: NSEvent.ModifierFlags.command.union(.shift).rawValue
    ),
    .pasteValues: StoredShortcut(
      key: "v",
      modifiers: NSEvent.ModifierFlags.command.union(.shift).union(.option).rawValue
    ),
    .fillDown: StoredShortcut(key: "d", modifiers: NSEvent.ModifierFlags.command.rawValue),
    .fillRight: StoredShortcut(key: "r", modifiers: NSEvent.ModifierFlags.command.rawValue),
    .convertToValues: StoredShortcut(
      key: "e",
      modifiers: NSEvent.ModifierFlags.command.union(.shift).rawValue
    ),
    .undo: StoredShortcut(key: "z", modifiers: NSEvent.ModifierFlags.command.rawValue),
    .redo: StoredShortcut(
      key: "z", modifiers: NSEvent.ModifierFlags.command.union(.shift).rawValue),
    .save: StoredShortcut(key: "s", modifiers: NSEvent.ModifierFlags.command.rawValue),
    .bold: StoredShortcut(key: "b", modifiers: NSEvent.ModifierFlags.command.rawValue),
    .italic: StoredShortcut(key: "i", modifiers: NSEvent.ModifierFlags.command.rawValue),
    .underline: StoredShortcut(key: "u", modifiers: NSEvent.ModifierFlags.command.rawValue),
    .autoSum: StoredShortcut(
      key: "t", modifiers: NSEvent.ModifierFlags.command.union(.shift).rawValue),
    // ⌘\ as in other spreadsheet apps.
    .clearFormats: StoredShortcut(key: "\\", modifiers: NSEvent.ModifierFlags.command.rawValue),
    .newWorkbook: StoredShortcut(key: "n", modifiers: NSEvent.ModifierFlags.command.rawValue),
    .newFromTemplate: StoredShortcut(
      key: "n", modifiers: NSEvent.ModifierFlags.command.union(.shift).rawValue),
    .open: StoredShortcut(key: "o", modifiers: NSEvent.ModifierFlags.command.rawValue),
    .saveAs: StoredShortcut(
      key: "s", modifiers: NSEvent.ModifierFlags.command.union(.shift).rawValue),
    .print: StoredShortcut(key: "p", modifiers: NSEvent.ModifierFlags.command.rawValue),
    .find: StoredShortcut(key: "f", modifiers: NSEvent.ModifierFlags.command.rawValue),
    .findAndReplace: StoredShortcut(
      key: "f", modifiers: NSEvent.ModifierFlags.command.union(.option).rawValue),
    .findNext: StoredShortcut(key: "g", modifiers: NSEvent.ModifierFlags.command.rawValue),
    .findPrevious: StoredShortcut(
      key: "g", modifiers: NSEvent.ModifierFlags.command.union(.shift).rawValue),
    .goTo: StoredShortcut(key: "g", modifiers: NSEvent.ModifierFlags.control.rawValue),
    .selectAll: StoredShortcut(key: "a", modifiers: NSEvent.ModifierFlags.command.rawValue),
    .editCell: StoredShortcut(key: "\u{F705}", modifiers: 0),
    .openDropdown: StoredShortcut(
      key: "\u{F701}", modifiers: NSEvent.ModifierFlags.option.rawValue),
    .insertLink: StoredShortcut(key: "k", modifiers: NSEvent.ModifierFlags.command.rawValue),
    .formulaHelp: StoredShortcut(
      key: "h", modifiers: NSEvent.ModifierFlags.command.union(.control).rawValue),
    .groupRowsOrColumns: StoredShortcut(
      key: "k", modifiers: NSEvent.ModifierFlags.command.union(.shift).rawValue),
    .ungroupRowsOrColumns: StoredShortcut(
      key: "j", modifiers: NSEvent.ModifierFlags.command.union(.shift).rawValue),
    .zoomIn: StoredShortcut(key: "+", modifiers: NSEvent.ModifierFlags.command.rawValue),
    .zoomOut: StoredShortcut(key: "-", modifiers: NSEvent.ModifierFlags.command.rawValue),
    .actualSize: StoredShortcut(key: "0", modifiers: NSEvent.ModifierFlags.command.rawValue),
    .help: StoredShortcut(
      key: "?", modifiers: NSEvent.ModifierFlags.command.rawValue),
  ]
}

extension StoredShortcut {
  static func from(event: NSEvent) -> StoredShortcut? {
    guard let chars = event.charactersIgnoringModifiers?.lowercased(), let first = chars.first
    else { return nil }
    let relevant: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
    let mods = event.modifierFlags.intersection(relevant).rawValue
    let shortcut = StoredShortcut(key: String(first), modifiers: mods)
    guard mods != 0 || shortcut.isFunctionKey else { return nil }
    return shortcut
  }
}

extension View {
  /// The shortcut Settings › Shortcuts gives `action`.
  func hotkey(_ action: HotkeyAction, _ settings: AppSettings) -> some View {
    keyboardShortcut(
      settings.keyEquivalent(for: action), modifiers: settings.eventModifiers(for: action))
  }
}
