import AppKit
import SparkGridCore
import StoreKit
import SwiftUI

/// Shared geometry for the strip above the grid so spacer and chrome stay in sync.
enum SpreadsheetChrome {
  static let formulaBarLineHeight: CGFloat = 18
  static let formulaBarVerticalPadding: CGFloat = 10
  static let formulaBarMaxLines = 4
  static let findBarHeight: CGFloat = 36
  static let formulaErrorBannerHeight: CGFloat = 40
  static let formulaArgumentHintHeight: CGFloat = 22
  static let dividerHeight: CGFloat = 1

  /// Rules between the toolbar, formula bar, find bar and grid (`SparkTheme.chromeDivider`).
  static var chromeDividerColor: Color {
    SparkStyle.chromeDivider
  }

  static var chromeBorderColor: Color {
    SparkStyle.chromeBorder
  }

  static func toolbarHeight(showLabels: Bool) -> CGFloat {
    58
  }

  static func formulaBarLineCount(for text: String) -> Int {
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false).count
    return min(formulaBarMaxLines, max(1, lines))
  }

  static func formulaBarContentLineCount(for text: String) -> Int {
    max(1, text.split(separator: "\n", omittingEmptySubsequences: false).count)
  }

  /// Collapsed = one visible row (scroll for overflow); expanded = up to `formulaBarMaxLines`.
  static func formulaBarViewportLineCount(contentLines: Int, expanded: Bool) -> Int {
    if expanded {
      return min(formulaBarMaxLines, max(1, contentLines))
    }
    return 1
  }

  static func formulaBarHeight(lineCount: Int) -> CGFloat {
    CGFloat(lineCount) * formulaBarLineHeight + formulaBarVerticalPadding
  }

  static func formulaFieldHeight(lineCount: Int) -> CGFloat {
    CGFloat(lineCount) * formulaBarLineHeight
  }

  static func topHeight(
    showLabels: Bool,
    showingFormulaError: Bool,
    showingFindBar: Bool,
    formulaBarLineCount: Int = 1,
    showingFormulaArgumentHint: Bool = false
  ) -> CGFloat {
    var height =
      toolbarHeight(showLabels: showLabels)
      + dividerHeight
      + formulaBarHeight(lineCount: formulaBarLineCount)
      + dividerHeight
    if showingFormulaArgumentHint {
      height += formulaArgumentHintHeight
    }
    if showingFindBar {
      height += findBarHeight + dividerHeight
    }
    if showingFormulaError {
      height += formulaErrorBannerHeight
    }
    return height
  }
}

/// Chrome hairline — a touch stronger than stock `Divider()`.
struct ChromeDivider: View {
  var body: some View {
    Rectangle()
      .fill(SpreadsheetChrome.chromeDividerColor)
      .frame(height: SpreadsheetChrome.dividerHeight)
      .frame(maxWidth: .infinity)
  }
}

struct SpreadsheetWindowView: View {
  @Bindable var store: SpreadsheetDocumentStore
  @Environment(\.undoManager) private var undoManager
  @Environment(\.sparkGridAppDelegate) private var appDelegate
  @Environment(\.requestReview) private var requestReview
  @Bindable private var settings = AppSettings.shared

  @State private var isChartsPanelCollapsed = false
  @State private var isFormulaBarExpanded = false

  private var document: Binding<SpreadsheetDocument> {
    $store.document
  }

  init(
    store: SpreadsheetDocumentStore,
    onDocumentChanged: @escaping () -> Void = {}
  ) {
    self.store = store
    self.onDocumentChanged = onDocumentChanged
  }

  var onDocumentChanged: () -> Void = {}

  var body: some View {
    @Bindable var viewModel = store.attachedViewModel()
    // The file token can already have changed before this view exists, so
    // `onChange` never sees the partial workbook. Sync the flag from its
    // current value before any cell is read.
    let _ = viewModel.setAwaitingRemainder(store.isLoadingRemainder)
    let showingFormulaError = viewModel.selectedFormulaErrorExplanation != nil
    let formulaContentLines = SpreadsheetChrome.formulaBarContentLineCount(
      for: viewModel.formulaBarText)
    let formulaViewportLines = SpreadsheetChrome.formulaBarViewportLineCount(
      contentLines: formulaContentLines,
      expanded: isFormulaBarExpanded
    )
    let hasCharts = !viewModel.activeSheet.charts.isEmpty
    let chromeHeight = SpreadsheetChrome.topHeight(
      showLabels: settings.showToolbarLabels,
      showingFormulaError: showingFormulaError,
      showingFindBar: viewModel.isFindBarVisible,
      formulaBarLineCount: formulaViewportLines,
      showingFormulaArgumentHint: viewModel.showsFormulaArgumentHint
    )
    GeometryReader { proxy in
      let width = max(0, proxy.size.width)
      let height = max(0, proxy.size.height)
      let tabStrip = 24 + SpreadsheetChrome.dividerHeight
      // The grid's slot must stay non-negative. A negative proposal is what
      // logs "Invalid view geometry" and keeps layout — and ⌘W — spinning.
      let spacer = min(chromeHeight, max(0, height - tabStrip))
      let chartsIdeal: CGFloat =
        isChartsPanelCollapsed
        ? SpreadsheetChartsPanel.collapsedWidth
        : SpreadsheetChartsPanel.expandedWidth
      let chartsWidth = hasCharts ? min(chartsIdeal, width) : 0
      let divider = hasCharts ? SpreadsheetChrome.dividerHeight : 0
      let gridWidth = max(0, width - chartsWidth - divider)
      ZStack(alignment: .top) {
        VStack(spacing: 0) {
          Color.clear.frame(height: spacer)
          HStack(spacing: 0) {
            SpreadsheetGridView(viewModel: viewModel)
              .frame(width: gridWidth)
              .frame(maxHeight: .infinity)
            if hasCharts {
              Rectangle()
                .fill(SpreadsheetChrome.chromeDividerColor)
                .frame(width: SpreadsheetChrome.dividerHeight)
              SpreadsheetChartsPanel(viewModel: viewModel, isCollapsed: $isChartsPanelCollapsed)
                .frame(width: chartsWidth)
            }
          }
          ChromeDivider()
          SheetTabsView(viewModel: viewModel)
        }

        VStack(spacing: 0) {
          FormattingToolbar(viewModel: viewModel, store: store, undoManager: undoManager)
          ChromeDivider()
          FormulaBarView(
            viewModel: viewModel,
            isExpanded: $isFormulaBarExpanded
          )
          ChromeDivider()
          if viewModel.isFindBarVisible {
            FindReplaceBar(viewModel: viewModel)
            ChromeDivider()
          }
        }
        .frame(maxWidth: .infinity)
        .background(SparkStyle.chrome)
      }
    }
    .onChange(of: viewModel.activeSheet.charts.count) { oldCount, newCount in
      if oldCount == 0, newCount > 0 {
        isChartsPanelCollapsed = false
      }
    }
    .sheet(
      isPresented: $viewModel.isInsertChartPresented,
      onDismiss: {
        viewModel.editingChartID = nil
      }
    ) {
      InsertChartSheet(viewModel: viewModel)
    }
    .focusedValue(\.spreadsheetViewModel, viewModel)
    .onAppear {
      viewModel.undoManager = undoManager
      viewModel.restoreFilterFromActiveSheet()
      registerWithAppDelegate(viewModel)
    }
    .onChange(of: viewModel.editStamp) { _, _ in
      if store.isLoadingRemainder { return }
      store.document.workbook = viewModel.workbook
      onDocumentChanged()
    }
    .onChange(of: viewModel.workbook.activeSheetIndex) { _, index in
      guard index != store.document.workbook.activeSheetIndex else { return }
      store.document.workbook = viewModel.workbook
      onDocumentChanged()
    }
    .onChange(of: store.externalWorkbookToken) { _, _ in
      if !store.isLoadingRemainder, store.fileURL != nil {
        considerRatingPrompt()
      }
      viewModel.setAwaitingRemainder(store.isLoadingRemainder)
      viewModel.withoutRecordingEdit {
        viewModel.workbook = store.document.workbook
      }
      viewModel.isEditing = false
      viewModel.syncEditTextFromSelection()
      viewModel.restoreFilterFromActiveSheet()
      // File/load sync only — don't mark dirty.
    }
    .onDisappear {
      appDelegate?.unregisterSpreadsheetViewModel(viewModel, store: store)
    }
    // Opening a file can hand this view a new view model after `onAppear` has run.
    // Without this, that model had no undo manager and nothing could be undone.
    .task(id: ObjectIdentifier(viewModel)) {
      viewModel.undoManager = undoManager
      registerWithAppDelegate(viewModel)
    }
    .onChange(of: undoManager) { _, newValue in
      viewModel.undoManager = newValue
    }
  }

  /// Counts an opened file and, once Spark Grid has been used on a few days, asks the system
  /// for its rating prompt, once per version. The system decides whether it appears.
  private func considerRatingPrompt() {
    guard ProcessInfo.processInfo.environment["SPARK_GRID_BENCHMARK"] == nil else { return }
    RatingPrompt.recordOpen()
    let version = RatingPrompt.currentVersion
    guard RatingPrompt.shouldAsk(version: version) else { return }
    RatingPrompt.markAsked(version: version)
    Task { @MainActor in
      // After the file is on screen, not over it while it opens.
      try? await Task.sleep(for: .seconds(3))
      requestReview()
    }
  }

  private func registerWithAppDelegate(_ viewModel: SpreadsheetViewModel) {
    appDelegate?.registerSpreadsheetViewModel(viewModel, store: store)
  }
}

enum WindowTitleUpdater {
  static func apply(title: String) {
    DispatchQueue.main.async {
      NSApp.keyWindow?.title = title
    }
  }
}

#Preview {
  SpreadsheetWindowView(store: SpreadsheetDocumentStore())
}
