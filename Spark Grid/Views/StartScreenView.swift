import AppKit
import SparkGridCore
import SwiftUI

/// What Spark Grid shows when it opens with no file, and from File > New from Template: the
/// templates and recent files. A template opens as a new Untitled workbook.
struct StartScreenView: View {
  @Bindable var store: SpreadsheetDocumentStore
  /// Shown over an open workbook from the File menu, with Cancel to go back to it.
  var isSheet = false
  @Bindable private var settings = AppSettings.shared

  @State private var search = ""
  @State private var category: WorkbookTemplate.Category?
  @State private var choice: Choice = .blank
  @State private var recentSelection: URL?
  @State private var recents: [RecentFile] = []

  enum Choice: Hashable {
    case blank
    case template(WorkbookTemplate)
    case recent(URL)
  }

  private var matchingTemplates: [WorkbookTemplate] {
    WorkbookTemplate.allCases.filter { template in
      (category == nil || template.category == category) && matches(template.name)
    }
  }

  private var showsBlank: Bool { category == nil && matches("Blank Workbook") }

  private var matchingRecents: [RecentFile] {
    recents.filter { matches($0.name) }
  }

  private func matches(_ name: String) -> Bool {
    let term = search.trimmingCharacters(in: .whitespaces)
    return term.isEmpty || name.localizedCaseInsensitiveContains(term)
  }

  var body: some View {
    VStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 22) {
        header
        templates
        recentFiles
      }
      .padding(.horizontal, 40)
      .padding(.top, 28)
      .padding(.bottom, 16)
      Divider()
      bottomBar
    }
    .background(SparkStyle.window)
    .onAppear { recents = RecentFile.load() }
    .onChange(of: recentSelection) { _, url in
      if let url { choice = .recent(url) }
    }
  }

  // MARK: Parts

  private var header: some View {
    HStack(alignment: .bottom, spacing: 16) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Start a workbook")
          .font(.sparkDisplay(size: 30, weight: 600))
        Text("Pick a template, or open something you worked on recently.")
          .font(.system(size: 13))
          .foregroundStyle(SparkStyle.secondaryLabel)
      }
      Spacer(minLength: 0)
      HStack(spacing: 6) {
        Image(systemName: "magnifyingglass")
          .foregroundStyle(SparkStyle.secondaryLabel)
        TextField("Search templates and recent files", text: $search)
          .textFieldStyle(.plain)
      }
      .padding(.horizontal, 8)
      .frame(width: 260, height: 28)
      .background(
        RoundedRectangle(cornerRadius: 6).fill(SparkStyle.field)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 6).strokeBorder(SparkStyle.separator)
      )
    }
  }

  private var templates: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 12) {
        Text("Templates").font(.system(size: 13, weight: .semibold))
        SparkSegmentedPicker(
          selection: $category,
          options: [(WorkbookTemplate.Category?.none, "All")]
            + WorkbookTemplate.Category.allCases.map { (Optional($0), $0.rawValue) }
        )
        .fixedSize()
        .accessibilityLabel("Template category")
      }
      LazyVGrid(
        columns: Array(repeating: GridItem(.flexible(), spacing: 18, alignment: .top), count: 6),
        alignment: .leading, spacing: 14
      ) {
        if showsBlank {
          TemplateTile(
            name: "Blank Workbook", summary: nil, preview: .blank, isSelected: choice == .blank
          ) {
            select(.blank)
          } open: {
            create(.blank)
          }
        }
        ForEach(matchingTemplates) { template in
          TemplateTile(
            name: template.name, summary: template.summary,
            preview: TemplatePreview.preview(for: template),
            isSelected: choice == .template(template)
          ) {
            select(.template(template))
          } open: {
            create(.template(template))
          }
        }
      }
      if !showsBlank && matchingTemplates.isEmpty {
        Text("No templates match.")
          .font(.system(size: 12))
          .foregroundStyle(SparkStyle.secondaryLabel)
      }
    }
  }

  private var recentFiles: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Recent").font(.system(size: 13, weight: .semibold))
      if recents.isEmpty {
        Text("Files you open show here.")
          .font(.system(size: 12))
          .foregroundStyle(SparkStyle.secondaryLabel)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      } else {
        Table(matchingRecents, selection: $recentSelection) {
          TableColumn("Name") { file in
            Label {
              Text(file.name).lineLimit(1).truncationMode(.middle)
            } icon: {
              Image(systemName: "tablecells").foregroundStyle(SparkStyle.accent)
            }
          }
          .width(min: 180, ideal: 300)
          TableColumn("Where") { file in
            Text(file.location).lineLimit(1).truncationMode(.head)
              .foregroundStyle(SparkStyle.secondaryLabel)
          }
          .width(min: 140, ideal: 260)
          TableColumn("Modified") { file in
            Text(file.modifiedText).foregroundStyle(SparkStyle.secondaryLabel)
          }
          .width(min: 90, ideal: 130)
          TableColumn("Size") { file in
            Text(file.sizeText)
              .monospacedDigit()
              .foregroundStyle(SparkStyle.secondaryLabel)
              .frame(maxWidth: .infinity, alignment: .trailing)
          }
          .width(min: 60, ideal: 80)
        }
        .contextMenu(forSelectionType: URL.self) { _ in
        } primaryAction: { urls in
          if let url = urls.first { create(.recent(url)) }
        }
      }
    }
    .frame(maxHeight: .infinity)
  }

  private var bottomBar: some View {
    HStack(spacing: 10) {
      Toggle("Show this when Spark Grid opens", isOn: $settings.showStartScreen)
        .toggleStyle(SparkCheckboxToggleStyle())
      Spacer(minLength: 0)
      if isSheet {
        Button("Cancel") { store.dismissStartScreen() }
          .keyboardShortcut(.cancelAction)
      } else {
        // Escape gives the blank workbook Spark Grid opened with.
        Button("") { store.dismissStartScreen() }
          .keyboardShortcut(.cancelAction)
          .frame(width: 0, height: 0)
          .opacity(0)
          .accessibilityHidden(true)
      }
      Button("Open…") { SpreadsheetOpenPanel.run(store: store) }
      Button("Blank Workbook") { create(.blank) }
      Button(primaryTitle) { create(choice) }
        .keyboardShortcut(.defaultAction)
        .disabled(!choiceIsShown)
        .buttonStyle(.borderedProminent)
        .tint(SparkStyle.accent)
    }
    .padding(.horizontal, 40)
    .frame(height: 56)
    .background(SparkStyle.chrome)
  }

  /// Create acts only on a tile or file that the search and category still show.
  private var choiceIsShown: Bool {
    switch choice {
    case .blank: return showsBlank
    case .template(let template): return matchingTemplates.contains(template)
    case .recent(let url): return matchingRecents.contains { $0.url == url }
    }
  }

  private var primaryTitle: String {
    if case .recent = choice { return "Open" }
    return "Create"
  }

  // MARK: Actions

  private func select(_ new: Choice) {
    choice = new
    recentSelection = nil
  }

  private func create(_ choice: Choice) {
    switch choice {
    case .blank:
      store.newDocument()
    case .template(let template):
      store.newDocument(from: template)
    case .recent(let url):
      do {
        try store.load(from: url)
      } catch {
        let alert = NSAlert()
        alert.messageText = "Couldn't Open \u{201C}\(url.lastPathComponent)\u{201D}"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
      }
    }
  }
}

/// A template's real first screenful, its name, and an info button with what it is for.
private struct TemplateTile: View {
  let name: String
  let summary: String?
  let preview: TemplatePreview
  let isSelected: Bool
  let select: () -> Void
  let open: () -> Void
  @State private var showsInfo = false

  var body: some View {
    Button(action: select) {
      tile
    }
    .buttonStyle(.plain)
    .simultaneousGesture(TapGesture(count: 2).onEnded(open))
    .accessibilityLabel("\(name) template")
    .accessibilityHint(summary ?? "")
    .accessibilityAddTraits(isSelected ? .isSelected : [])
    .accessibilityAction(named: "Create", open)
    .overlay(alignment: .topTrailing) {
      if let summary {
        Button {
          showsInfo.toggle()
        } label: {
          Image(systemName: "info.circle.fill")
            .font(.system(size: 13))
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, Color.black.opacity(0.45))
        }
        .buttonStyle(.plain)
        .padding(5)
        .help("About this template")
        .accessibilityLabel("About \(name)")
        .popover(isPresented: $showsInfo, arrowEdge: .bottom) {
          VStack(alignment: .leading, spacing: 6) {
            Text(name).font(.system(size: 13, weight: .semibold))
            Text(summary)
              .font(.system(size: 12))
              .foregroundStyle(SparkStyle.secondaryLabel)
              .fixedSize(horizontal: false, vertical: true)
          }
          .padding(12)
          .frame(width: 240, alignment: .leading)
        }
      }
    }
  }

  private var tile: some View {
    VStack(alignment: .leading, spacing: 7) {
      TemplatePreviewCanvas(preview: preview)
        .frame(height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
          RoundedRectangle(cornerRadius: 6)
            .strokeBorder(
              isSelected ? SparkStyle.accent : SparkStyle.separator, lineWidth: isSelected ? 2 : 1)
        )
        .background(
          RoundedRectangle(cornerRadius: 8)
            .stroke(SparkStyle.accent.opacity(isSelected ? 0.3 : 0), lineWidth: 3)
            .padding(-2)
        )
      Text(name)
        .font(.system(size: 12, weight: .medium))
        .lineLimit(1)
        .padding(.leading, 2)
    }
    .contentShape(Rectangle())
  }
}

/// A checkbox in the app's accent (Spark amber unless Settings says the macOS accent). The
/// system checkbox always takes the macOS accent.
struct SparkCheckboxToggleStyle: ToggleStyle {
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    Button {
      configuration.isOn.toggle()
    } label: {
      HStack(spacing: 6) {
        ZStack {
          RoundedRectangle(cornerRadius: 3.5)
            .fill(configuration.isOn ? SparkStyle.accent : SparkStyle.field)
          RoundedRectangle(cornerRadius: 3.5)
            .strokeBorder(configuration.isOn ? Color.clear : SparkStyle.secondaryLabel.opacity(0.6))
          if configuration.isOn {
            Image(systemName: "checkmark")
              .font(.system(size: 9, weight: .bold))
              .foregroundStyle(.white)
          }
        }
        .frame(width: 14, height: 14)
        configuration.label
      }
      .contentShape(Rectangle())
      .opacity(isEnabled ? 1 : 0.5)
    }
    .buttonStyle(.plain)
    .accessibilityRepresentation {
      Toggle(isOn: configuration.$isOn) { configuration.label }
    }
  }
}

/// A file from Open Recent: its name, where it is, when it changed and its size.
struct RecentFile: Identifiable, Hashable {
  let url: URL
  let name: String
  let location: String
  let modified: Date?
  let size: Int?

  var id: URL { url }

  var modifiedText: String {
    guard let modified else { return "" }
    if Calendar.current.isDateInToday(modified) {
      return "Today, " + modified.formatted(date: .omitted, time: .shortened)
    }
    if Calendar.current.isDateInYesterday(modified) { return "Yesterday" }
    return modified.formatted(.dateTime.month(.abbreviated).day().year())
  }

  var sizeText: String {
    guard let size else { return "" }
    return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
  }

  static func load() -> [RecentFile] {
    NSDocumentController.shared.recentDocumentURLs.map { url in
      let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
      return RecentFile(
        url: url, name: url.lastPathComponent, location: location(of: url),
        modified: values?.contentModificationDate, size: values?.fileSize)
    }
  }

  /// The folder, from the home folder down: "Documents › Sales".
  static func location(of url: URL) -> String {
    var parts = url.deletingLastPathComponent().pathComponents
    if parts.count >= 3, parts[1] == "Users" {
      parts.removeFirst(3)
    } else if parts.first == "/" {
      parts.removeFirst()
    }
    if parts.starts(with: ["Library", "Mobile Documents", "com~apple~CloudDocs"]) {
      parts = ["iCloud Drive"] + parts.dropFirst(3)
    }
    return parts.isEmpty ? "Home" : parts.joined(separator: " \u{203A} ")
  }
}
