import AppKit
import SparkGridCore
import SwiftUI

/// The welcome screen the first time Spark Grid opens, and What's New the first time a new
/// version opens (Sam, Nov 20). Each shows once; Help › Welcome and Help › What's New show them
/// again.
enum LaunchIntro {
  enum Screen: String {
    case welcome, whatsNew

    var windowID: String { self == .welcome ? "welcome" : "whatsnew" }
  }

  private static let lastVersionKey = "launchIntro.lastVersion"
  private static var decided = false

  static var currentVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
  }

  /// The screen to show at this launch, asked for once; nil when none is due. Records this
  /// version, so it is not shown again.
  static func screenForThisLaunch(defaults: UserDefaults = .standard) -> Screen? {
    guard !decided else { return nil }
    decided = true
    let environment = ProcessInfo.processInfo.environment
    #if DEBUG
      // SPARK_GRID_RESET_INTRO=1 forgets which version was seen, to try the screens again.
      if environment["SPARK_GRID_RESET_INTRO"] == "1" {
        defaults.removeObject(forKey: lastVersionKey)
        return nil
      }
    #endif
    guard environment["SPARK_GRID_BUG_BASH"] != "1", environment["SPARK_GRID_BENCHMARK"] != "1",
      environment["XCTestConfigurationFilePath"] == nil
    else { return nil }
    let version = currentVersion
    defer { defaults.set(version, forKey: lastVersionKey) }
    if let last = defaults.string(forKey: lastVersionKey) {
      guard last != version, ReleaseNotes.notes(for: version) != nil else { return nil }
      return .whatsNew
    }
    // Before 1.7 nothing recorded the version. Someone who has opened files has used it before.
    let usedBefore =
      defaults.object(forKey: "ratingPrompt.firstOpen") != nil
      || !NSDocumentController.shared.recentDocumentURLs.isEmpty
    if usedBefore { return ReleaseNotes.notes(for: version) == nil ? nil : .whatsNew }
    return .welcome
  }
}

/// What each version brings, for What's New. Shown for the version that is running.
enum ReleaseNotes {
  struct Item: Identifiable {
    let symbol: String
    let title: String
    let detail: String
    var id: String { title }
  }

  static func notes(for version: String) -> [Item]? {
    let major = version.split(separator: ".").prefix(2).joined(separator: ".")
    return all[major]
  }

  static let all: [String: [Item]] = [
    "1.7": [
      Item(
        symbol: "function", title: "Over 200 new functions",
        detail:
          "SUBTOTAL, AGGREGATE, LAMBDA, MAP, GROUPBY, PIVOTBY, LINEST, the statistics tests and "
          + "distributions, bonds, CONVERT, complex numbers and more, each checked against "
          + "another app's answers."),
      Item(
        symbol: "sparkles", title: "Formula Help",
        detail:
          "Insert › Formula Help writes a formula from a sentence or explains one, and Insert › "
          + "Chart makes a chart from a description, with Apple Intelligence on your Mac."),
      Item(
        symbol: "chart.bar.xaxis", title: "New charts and trendlines",
        detail:
          "Horizontal, stacked and doughnut charts, and trendlines with their equation and R²."),
      Item(
        symbol: "chart.xyaxis.line", title: "Sparklines",
        detail: "Insert › Sparklines puts a small line, column or win/loss chart in a cell."),
      Item(
        symbol: "scope", title: "Goal Seek",
        detail: "Data › Goal Seek finds the input that gives a formula the result you want."),
      Item(
        symbol: "square.and.arrow.down", title: "More ways to save",
        detail:
          "Save as OpenDocument (.ods) with every sheet, formula and format, as tab-separated "
          + "text, or as a web page."),
      Item(
        symbol: "keyboard", title: "Your own shortcuts",
        detail: "Every command's shortcut can be changed in Settings › Shortcuts."),
      Item(
        symbol: "exclamationmark.triangle", title: "No surprises with unknown functions",
        detail:
          "A file with functions Spark Grid can't calculate says which when it opens, and can "
          + "keep a copy of the original."),
      Item(
        symbol: "clock.arrow.circlepath", title: "Version history",
        detail:
          "File › Browse Versions shows earlier versions of a workbook to open or restore."),
      Item(
        symbol: "checkmark.shield", title: "Data validation",
        detail:
          "Data › Data Validation limits what cells may hold, with a warning or a stop."),
      Item(
        symbol: "rectangle.on.rectangle", title: "Formulas across sheets",
        detail:
          "While writing a formula, click another sheet's tab and its cells to use them."),
      Item(
        symbol: "calendar", title: "Smarter typing",
        detail: "3/4 and 15-Mar are dates, 1 1/2 is a fraction, #N/A is the error."),
      Item(
        symbol: "externaldrive", title: "Big workbooks",
        detail:
          "Large files keep their results after a sort, and the window says when it is still "
          + "saving."),
      Item(
        symbol: "text.magnifyingglass", title: "Regular expressions in formulas",
        detail:
          "REGEXTEST, REGEXEXTRACT and REGEXREPLACE find, pull out and replace text by pattern."),
      Item(
        symbol: "textformat", title: "Your choice of text color on fills",
        detail:
          "Settings › General › Readable text on filled cells turns off the automatic change "
          + "of text color on colored cells."),
    ]
  ]
}

/// "Thanks for downloading": what Spark Grid does, in one screen.
struct WelcomeView: View {
  @Environment(\.dismissWindow) private var dismissWindow
  @Environment(\.openWindow) private var openWindow

  private var features: [ReleaseNotes.Item] {
    [
      ReleaseNotes.Item(
        symbol: "doc.on.doc", title: "Opens what you have",
        detail: ".xlsx, .csv, Numbers and .ods files open as they are; save as .xlsx or .csv."),
      ReleaseNotes.Item(
        symbol: "function", title: "\(FormulaFunctions.all.count) functions",
        detail: "Formulas work as you expect, with suggestions as you type and click-to-point."),
      ReleaseNotes.Item(
        symbol: "chart.bar", title: "Charts and pivot tables",
        detail: "Select data and choose Insert › Chart, or Data › PivotTable."),
      ReleaseNotes.Item(
        symbol: "sparkles", title: "Help with formulas",
        detail: "Insert › Formula Help writes and explains formulas with Apple Intelligence."),
      ReleaseNotes.Item(
        symbol: "lock", title: "Private by design",
        detail: "No account, no ads, no tracking. Your files never leave your Mac."),
      ReleaseNotes.Item(
        symbol: "questionmark.circle", title: "Help when you need it",
        detail: "Help › Spark Grid Help explains every part, and works offline."),
    ]
  }

  var body: some View {
    VStack(spacing: 18) {
      Image(nsImage: NSApp.applicationIconImage)
        .resizable()
        .frame(width: 84, height: 84)
        .accessibilityHidden(true)
      VStack(spacing: 6) {
        Text("Thanks for downloading Spark Grid")
          .font(.system(size: 22, weight: .semibold))
        Text("A fast, native spreadsheet for your Mac. Here's what it can do.")
          .font(.system(size: 13))
          .foregroundStyle(.secondary)
      }
      LazyVGrid(
        columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)],
        alignment: .leading, spacing: 16
      ) {
        ForEach(features) { IntroRow(item: $0) }
      }
      HStack {
        Button("Open Help") {
          openWindow(id: "help")
          dismissWindow(id: "welcome")
        }
        Spacer()
        Button("Get Started") { dismissWindow(id: "welcome") }
          .keyboardShortcut(.defaultAction)
          .buttonStyle(.borderedProminent)
          .tint(SparkStyle.accent)
      }
    }
    .padding(28)
    .frame(width: 600)
  }
}

/// What's New in this version.
struct WhatsNewView: View {
  @Environment(\.dismissWindow) private var dismissWindow

  private var items: [ReleaseNotes.Item] {
    ReleaseNotes.notes(for: LaunchIntro.currentVersion) ?? []
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(spacing: 14) {
        Image(nsImage: NSApp.applicationIconImage)
          .resizable()
          .frame(width: 56, height: 56)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 2) {
          Text("What's New in Spark Grid \(LaunchIntro.currentVersion)")
            .font(.system(size: 20, weight: .semibold))
          Text("Thanks for updating.")
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
        }
      }
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          ForEach(items) { IntroRow(item: $0) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(maxHeight: 380)
      HStack {
        Spacer()
        Button("Continue") { dismissWindow(id: "whatsnew") }
          .keyboardShortcut(.defaultAction)
          .buttonStyle(.borderedProminent)
          .tint(SparkStyle.accent)
      }
    }
    .padding(28)
    .frame(width: 520)
  }
}

private struct IntroRow: View {
  let item: ReleaseNotes.Item

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: item.symbol)
        .font(.system(size: 18))
        .foregroundStyle(SparkStyle.accent)
        .frame(width: 26)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text(item.title).font(.system(size: 13, weight: .semibold))
        Text(item.detail)
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .accessibilityElement(children: .combine)
  }
}
