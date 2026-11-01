import AppKit
import Darwin
import Foundation
import SparkGridCore

/// Release timings for the seven paths the app actually runs.
///
/// Launch with `SPARK_GRID_BENCHMARK=1`. Sheet names are not built in: the scroll
/// sheet is `SPARK_GRID_BENCHMARK_SCROLL_SHEET` when that sheet exists, otherwise
/// the sheet with the most populated rows.
enum PerformanceBenchmark {
  private static let firstScreenRows = 60
  private static let firstScreenColumns = 25

  static func run() -> Never {
    let env = ProcessInfo.processInfo.environment
    let reference = env["SPARK_GRID_BENCHMARK_REFERENCE"] ?? ""
    let root = env["SPARK_GRID_BENCHMARK_ROOT"] ?? FileManager.default.currentDirectoryPath
    let answersDirectory =
      env["SPARK_GRID_BENCHMARK_ANSWERS"]
      ?? FileManager.default.temporaryDirectory
      .appendingPathComponent("spark-grid-benchmark-answers", isDirectory: true).path
    let logPath = env["SPARK_GRID_BENCHMARK_LOG"] ?? "/tmp/spark-grid-phase0-baseline.txt"
    var lines: [String] = []
    func emit(_ line: String) {
      print(line)
      fflush(stdout)
      lines.append(line)
      let text = lines.joined(separator: "\n") + "\n"
      try? Data(text.utf8).write(to: URL(fileURLWithPath: logPath), options: .atomic)
    }

    do {
      try FileManager.default.createDirectory(
        atPath: answersDirectory, withIntermediateDirectories: true)
      try verifyCachedFormulaRoundTrip(emit: emit)
      if env["SPARK_GRID_BENCHMARK_COMPARE_IMPORT"] == "1" {
        try compareImporters(env: env, root: root, emit: emit)
        emit("import-compare done")
        exit(0)
      }
      guard !reference.isEmpty, FileManager.default.fileExists(atPath: reference) else {
        emit("benchmark failed: SPARK_GRID_BENCHMARK_REFERENCE is missing")
        exit(1)
      }
      let editOnly = env["SPARK_GRID_BENCHMARK_EDIT_ONLY"] == "1"
      let flingOnly = env["SPARK_GRID_BENCHMARK_FLING"] == "1"
      let openScrollOnly = env["SPARK_GRID_BENCHMARK_OPEN_SCROLL"] == "1"
      let otherPath =
        (editOnly && !flingOnly) || openScrollOnly
        ? "" : try resolveLedgerPath(env: env, root: root, emit: emit)
      emit("benchmark reference \(reference)")
      if !otherPath.isEmpty {
        emit("benchmark ledger \(otherPath)")
      }
      _ = NSApplication.shared
      if openScrollOnly {
        try measureOpenAndFirstScroll(
          url: URL(fileURLWithPath: reference), label: "reference", emit: emit)
      } else if flingOnly {
        try measureFling(
          url: URL(fileURLWithPath: reference), label: "reference", env: env, emit: emit)
        if !otherPath.isEmpty {
          try measureFling(
            url: URL(fileURLWithPath: otherPath), label: "ledger", env: env, emit: emit)
        }
      } else {
        try measure(
          url: URL(fileURLWithPath: reference), label: "reference", env: env,
          answersDirectory: answersDirectory, emit: emit)
        if !editOnly {
          try measure(
            url: URL(fileURLWithPath: otherPath), label: "ledger", env: env,
            answersDirectory: answersDirectory, emit: emit)
        }
      }
      emit("benchmark done")
      exit(0)
    } catch {
      emit("benchmark failed: \(error)")
      exit(1)
    }
  }

  private static func resolveLedgerPath(
    env: [String: String],
    root: String,
    emit: (String) -> Void
  ) throws -> String {
    if let given = env["SPARK_GRID_BENCHMARK_OTHER"], !given.isEmpty {
      return given
    }
    let script = (root as NSString).appendingPathComponent("scripts/generate_ledger_workbook.py")
    let output = "/tmp/spark-grid-phase0-ledger.xlsx"
    guard FileManager.default.fileExists(atPath: script) else {
      throw BenchmarkFailure("ledger generator missing at \(script)")
    }
    emit("generating ledger with \(script)")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    process.arguments = [script, "-o", output]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    process.waitUntilExit()
    let outputText =
      String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    emit(outputText.trimmingCharacters(in: .whitespacesAndNewlines))
    guard process.terminationStatus == 0 else {
      throw BenchmarkFailure("ledger generator exited \(process.terminationStatus)")
    }
    return output
  }

  /// Open through the first painted grid, then one scroll of that sheet.
  /// Skips the ledger, the fling, and the other workbook paths.
  private static func measureOpenAndFirstScroll(
    url: URL,
    label: String,
    emit: @escaping (String) -> Void
  ) throws {
    emit("---- \(label) ----")
    let store = SpreadsheetDocumentStore()
    let baselineURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("spark-grid-open-scroll-empty-\(label).xlsx")
    try store.save(to: baselineURL)
    let openCopy = FileManager.default.temporaryDirectory
      .appendingPathComponent("spark-grid-open-scroll-\(label)-\(UUID().uuidString).xlsx")
    try FileManager.default.copyItem(at: url, to: openCopy)
    defer { try? FileManager.default.removeItem(at: openCopy) }
    let autosaveDuringOpen = AppSettings.shared.autosaveEnabled
    AppSettings.shared.autosaveEnabled = false
    defer { AppSettings.shared.autosaveEnabled = autosaveDuringOpen }

    let painted = OpenScrollPaint()
    let openStarted = CFAbsoluteTimeGetCurrent()
    store.onActiveSheetReady = { workbook in
      let viewModel = SpreadsheetViewModel(workbook: workbook)
      let frame = viewportFrame(for: viewModel.activeSheet)
      let grid = BenchmarkGrid(viewModel: viewModel, frame: frame)
      grid.grid.needsDisplay = true
      grid.grid.display()
      painted.viewModel = viewModel
      painted.grid = grid
      painted.frame = frame
      painted.openSeconds = CFAbsoluteTimeGetCurrent() - openStarted
    }
    try store.load(from: openCopy)
    store.onActiveSheetReady = nil
    store.fileURL = nil
    while store.isLoadingRemainder {
      drainMain()
    }
    defer { painted.grid?.close() }
    guard let viewModel = painted.viewModel, let grid = painted.grid else {
      throw BenchmarkFailure("open did not paint a sheet")
    }
    emit(String(format: "open %.3f s", painted.openSeconds))
    emit("opened-sheet\t\(viewModel.activeSheet.name)")
    let loaded = store.document.workbook
    var formulas = 0
    var cached = 0
    for sheet in loaded.sheets {
      for cell in sheet.cells.values where FormulaSyntax.isFormula(cell.raw) {
        formulas += 1
        if cell.cachedFormulaValue != nil { cached += 1 }
      }
    }
    emit("formula-caches \(cached) of \(formulas)")
    var refShown = 0
    for (address, cell) in viewModel.activeSheet.cells where FormulaSyntax.isFormula(cell.raw) {
      let shown = viewModel.sheetDisplayValue(at: address, cell: cell)
      if case .error(.ref) = shown, cell.cachedFormulaValue != .error(.ref) {
        refShown += 1
      }
    }
    emit("open-ref \(refShown)")

    drainMain()
    emit("viewport-tiles-ready\t\(grid.grid.testingViewportTileCacheReady())")
    let header = SpreadsheetGridNSView.baseHeaderSize
    let body = max(1, painted.frame.height - header)
    let scrollStarted = CFAbsoluteTimeGetCurrent()
    let moved = grid.grid.testingApplyScroll(dx: 0, dy: body)
    let scrollSeconds = CFAbsoluteTimeGetCurrent() - scrollStarted
    emit(
      "first-scroll\t\(viewModel.activeSheet.name)\t\(formatSeconds(scrollSeconds))\tmoved \(moved)"
    )
    emit("first-scroll-draws\t\(grid.grid.testingGridDraws)")
    emit("first-scroll-tiles\t\(grid.grid.testingScrollTilesPresented)")

    viewModel.withoutRecordingEdit {
      viewModel.workbook = loaded
    }
    let heavy = scrollSheetIndex(in: viewModel.workbook, preferredName: nil)
    if heavy != viewModel.workbook.activeSheetIndex {
      let switchStarted = CFAbsoluteTimeGetCurrent()
      viewModel.selectSheet(at: heavy)
      grid.resize(to: viewportFrame(for: viewModel.activeSheet))
      grid.grid.reloadContent(resetScrollPosition: true)
      grid.grid.needsDisplay = true
      grid.grid.display()
      let switchSeconds = CFAbsoluteTimeGetCurrent() - switchStarted
      emit("sheet-switch\t\(viewModel.activeSheet.name)\t\(formatSeconds(switchSeconds))")
      drainMain()
      let heavyFrame = grid.grid.bounds
      let heavyBody = max(1, heavyFrame.height - header)
      let heavyStarted = CFAbsoluteTimeGetCurrent()
      let heavyMoved = grid.grid.testingApplyScroll(dx: 0, dy: heavyBody)
      let heavySeconds = CFAbsoluteTimeGetCurrent() - heavyStarted
      emit(
        "heavy-first-scroll\t\(viewModel.activeSheet.name)\t\(formatSeconds(heavySeconds))\tmoved \(heavyMoved)"
      )
    }
  }

  private final class OpenScrollPaint {
    var viewModel: SpreadsheetViewModel?
    var grid: BenchmarkGrid?
    var frame = NSRect.zero
    var openSeconds: TimeInterval = 0
  }

  private static func measure(
    url: URL,
    label: String,
    env: [String: String],
    answersDirectory: String,
    emit: @escaping (String) -> Void
  ) throws {
    emit("---- \(label) ----")
    let editOnly = env["SPARK_GRID_BENCHMARK_EDIT_ONLY"] == "1"
    let beforeResident = residentBytes()
    let importStarted = CFAbsoluteTimeGetCurrent()
    let imported = try XLSXCodec.importWorkbook(from: url)
    let importSeconds = CFAbsoluteTimeGetCurrent() - importStarted
    let afterResident = residentBytes()
    emit(String(format: "importWorkbook %.3f s", importSeconds))
    emit(
      String(
        format: "resident-after-import %.2f MB delta %.2f MB", Double(afterResident) / 1_048_576,
        Double(afterResident &- beforeResident) / 1_048_576))
    if label == "ledger" {
      try validateLedger(imported)
      emit("ledger shape ok")
    }

    let fingerprintSeconds: TimeInterval
    if editOnly {
      fingerprintSeconds = 0
    } else {
      let fingerprintStarted = CFAbsoluteTimeGetCurrent()
      _ = WorkbookFingerprint.data(for: imported)
      fingerprintSeconds = CFAbsoluteTimeGetCurrent() - fingerprintStarted
      emit(String(format: "WorkbookFingerprint %.3f s", fingerprintSeconds))
    }

    let exportSeconds: TimeInterval
    if editOnly {
      exportSeconds = 0
    } else {
      let exportStarted = CFAbsoluteTimeGetCurrent()
      _ = try XLSXCodec.exportWorkbook(imported)
      exportSeconds = CFAbsoluteTimeGetCurrent() - exportStarted
      emit(String(format: "exportWorkbook %.3f s", exportSeconds))
    }

    if !editOnly {
      let autosaveURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("spark-grid-phase1-autosave-\(label)-\(UUID().uuidString).xlsx")
      defer { try? FileManager.default.removeItem(at: autosaveURL) }
      let autosaveStore = SpreadsheetDocumentStore()
      autosaveStore.document.workbook = imported
      autosaveStore.fileURL = autosaveURL
      autosaveStore.noteEdit()
      let autosaveWasEnabled = AppSettings.shared.autosaveEnabled
      AppSettings.shared.autosaveEnabled = true
      let autosaveStarted = CFAbsoluteTimeGetCurrent()
      autosaveStore.autosaveIfNeeded()
      let autosaveMainSeconds = CFAbsoluteTimeGetCurrent() - autosaveStarted
      emit(String(format: "autosave-main %.3f s", autosaveMainSeconds))
      let autosaveDeadline = Date().addingTimeInterval(180)
      while autosaveStore.isAutosaving, Date() < autosaveDeadline {
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
      }
      AppSettings.shared.autosaveEnabled = autosaveWasEnabled
      emit(
        "autosave-finished\t\(autosaveStore.isAutosaving ? "busy" : "idle")\t\(FileManager.default.fileExists(atPath: autosaveURL.path))"
      )
    }

    let store = SpreadsheetDocumentStore()
    // Sheet ids are random, so a new store's saved fingerprint does not match its
    // empty document and the first load would ask to save. Write that empty
    // workbook first so `load` takes the clean-document path.
    let baselineURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("spark-grid-phase0-empty-\(label).xlsx")
    try store.save(to: baselineURL)
    // Load a copy. An edit during the timing must not write the caller's file.
    let openCopy = FileManager.default.temporaryDirectory
      .appendingPathComponent("spark-grid-bench-open-\(label)-\(UUID().uuidString).xlsx")
    try FileManager.default.copyItem(at: url, to: openCopy)
    defer { try? FileManager.default.removeItem(at: openCopy) }
    let autosaveDuringOpen = AppSettings.shared.autosaveEnabled
    AppSettings.shared.autosaveEnabled = false
    defer { AppSettings.shared.autosaveEnabled = autosaveDuringOpen }
    let openStarted = CFAbsoluteTimeGetCurrent()
    try store.load(from: openCopy, finishesInBackground: false)
    store.fileURL = nil
    drainMain()
    let viewModel = SpreadsheetViewModel(workbook: store.document.workbook)
    let grid = BenchmarkGrid(viewModel: viewModel, frame: viewportFrame(for: viewModel.activeSheet))
    grid.grid.needsDisplay = true
    grid.grid.display()
    let openSeconds = CFAbsoluteTimeGetCurrent() - openStarted
    emit(String(format: "open %.3f s", openSeconds))

    let unsavedStarted = CFAbsoluteTimeGetCurrent()
    store.documentDidChange()
    let unsavedSeconds = CFAbsoluteTimeGetCurrent() - unsavedStarted
    emit(String(format: "unsaved-check %.3f s", unsavedSeconds))

    var firstScreens: [(String, TimeInterval)] = []
    var scroll = (worst: 0.0, ticks: 0, sheet: "")
    var selectSeconds = 0.0
    var selectSyncSeconds = 0.0
    if !editOnly {
      for index in viewModel.workbook.sheets.indices {
        if viewModel.workbook.activeSheetIndex != index {
          viewModel.selectSheet(at: index)
        }
        let frame = viewportFrame(for: viewModel.activeSheet)
        grid.resize(to: frame)
        grid.grid.reloadContent(resetScrollPosition: true)
        let paintStarted = CFAbsoluteTimeGetCurrent()
        grid.grid.needsDisplay = true
        grid.grid.display()
        let paintSeconds = CFAbsoluteTimeGetCurrent() - paintStarted
        let name = viewModel.activeSheet.name
        firstScreens.append((name, paintSeconds))
        emit("first-screen\t\(name)\t\(formatSeconds(paintSeconds))")
      }

      let scrollIndex = scrollSheetIndex(
        in: viewModel.workbook, preferredName: env["SPARK_GRID_BENCHMARK_SCROLL_SHEET"])
      scroll = timeWorstScroll(grid: grid, viewModel: viewModel, sheetIndex: scrollIndex)
      emit("scroll-worst\t\(scroll.sheet)\t\(formatSeconds(scroll.worst))\tticks \(scroll.ticks)")

      // Same sheet ids as the open document. A second import compares unequal at the
      // first sheet id and hides the workbook-sized sync the window actually runs.
      let switchViewModel = SpreadsheetViewModel(workbook: store.document.workbook)
      store.activeViewModel = switchViewModel
      store.documentDidChange()
      let switchStarted = CFAbsoluteTimeGetCurrent()
      switchViewModel.selectSheet(at: min(1, switchViewModel.workbook.sheets.count - 1))
      selectSeconds = CFAbsoluteTimeGetCurrent() - switchStarted
      let selectSyncStarted = CFAbsoluteTimeGetCurrent()
      syncOnChange(store: store, viewModel: switchViewModel)
      selectSyncSeconds = CFAbsoluteTimeGetCurrent() - selectSyncStarted
      emit(String(format: "selectSheet %.3f s", selectSeconds))
      emit(String(format: "selectSheet-onchange %.3f s", selectSyncSeconds))
      emit(String(format: "tab-switch %.3f s", selectSeconds + selectSyncSeconds))
      emit("tab-switch-dirty\t\(store.isDirty)")
    }
    grid.close()

    let loaded = store.document.workbook

    let editViewModel = SpreadsheetViewModel(workbook: loaded)
    if let preferred = env["SPARK_GRID_BENCHMARK_EDIT_SHEET"],
      let index = editViewModel.workbook.sheets.firstIndex(where: { $0.name == preferred })
    {
      editViewModel.selectSheet(at: index)
    }
    store.activeViewModel = editViewModel
    store.documentDidChange()
    let editGrid = BenchmarkGrid(
      viewModel: editViewModel, frame: viewportFrame(for: editViewModel.activeSheet))
    editGrid.grid.needsDisplay = true
    editGrid.grid.display()
    let layerAfterWarm = editGrid.grid.testingLayerNeedsDisplay
    let editAddress = firstNumericLiteral(in: editViewModel.activeSheet) ?? .origin
    let oldRaw = editViewModel.activeSheet.cell(at: editAddress).raw
    let newRaw = oldRaw == "0" ? "1" : "0"
    editViewModel.select(editAddress)
    editViewModel.beginEditing()
    editViewModel.editText = newRaw
    editGrid.grid.scrollSelectionIntoView()
    editGrid.grid.needsDisplay = true
    editGrid.grid.display()
    let graphBuildsBeforeEdit = editViewModel.formulaEngine.dependencyGraphBuildCount
    editGrid.grid.testingResetScrollCounters()
    let dirtyBefore = editGrid.grid.needsDisplay
    let commitStarted = CFAbsoluteTimeGetCurrent()
    editViewModel.commitEdit()
    let commitSeconds = CFAbsoluteTimeGetCurrent() - commitStarted
    editGrid.grid.displayIfNeeded()
    let pixelsSeconds = CFAbsoluteTimeGetCurrent() - commitStarted
    if env["SPARK_GRID_BENCHMARK_SNAPSHOT"] == "1" {
      editGrid.grid.testingWriteLayerPNG(to: "/tmp/spark-grid-phase-b-edit.png")
    }
    let paintedCells = editGrid.grid.liveScrollCellVisits
    let changedCells = editViewModel.lastPublishedCellCount
    let graphBuildsAfterEdit = editViewModel.formulaEngine.dependencyGraphBuildCount
    emit("dependency-graph-builds-edit\t\(graphBuildsAfterEdit - graphBuildsBeforeEdit)")
    let editSyncStarted = CFAbsoluteTimeGetCurrent()
    syncOnChange(store: store, viewModel: editViewModel)
    let editSyncSeconds = CFAbsoluteTimeGetCurrent() - editSyncStarted
    editGrid.close()
    emit(
      "commitEdit\t\(editViewModel.activeSheet.name)!\(editAddress.a1)\t\(formatSeconds(commitSeconds))"
    )
    emit(
      "edit-to-pixels\t\(editViewModel.activeSheet.name)!\(editAddress.a1)\t\(formatSeconds(pixelsSeconds))\tpainted \(paintedCells)\tchanged \(changedCells)\tdirty-before \(dirtyBefore)\tlayer-after-warm \(layerAfterWarm)\tstores \(editGrid.grid.testingFrameStores) clears \(editGrid.grid.testingFrameClears)\tgrid \(editGrid.grid.testingGridVisits) overlay \(editGrid.grid.testingOverlayVisits) draws \(editGrid.grid.testingGridDraws)\t\(editGrid.grid.testingInvalidateReason)"
    )
    emit(String(format: "edit-onchange %.3f s", editSyncSeconds))
    emit(String(format: "edit %.3f s", commitSeconds + editSyncSeconds))
    emit("edit-dirty\t\(store.isDirty)")
    let graphBuildsBeforeSave = editViewModel.formulaEngine.dependencyGraphBuildCount
    let saveURL = FileManager.default.temporaryDirectory.appendingPathComponent(
      "spark-grid-bench-save-\(label)-\(UUID().uuidString).xlsx")
    store.fileURL = saveURL
    try store.save(to: saveURL)
    let graphBuildsAfterSave = editViewModel.formulaEngine.dependencyGraphBuildCount
    emit("dependency-graph-builds-save\t\(graphBuildsAfterSave - graphBuildsBeforeSave)")
    try? FileManager.default.removeItem(at: saveURL)

    let slowest = firstScreens.max(by: { $0.1 < $1.1 })
    emit("first-screen-slowest\t\(slowest?.0 ?? "")\t\(formatSeconds(slowest?.1 ?? 0))")
    emit(
      summaryLine(
        label: label,
        open: openSeconds,
        unsaved: unsavedSeconds,
        firstScreen: slowest?.1 ?? 0,
        firstScreenName: slowest?.0 ?? "",
        edit: commitSeconds + editSyncSeconds,
        commit: commitSeconds,
        pixels: pixelsSeconds,
        paintedCells: paintedCells,
        tab: selectSeconds + selectSyncSeconds,
        export: exportSeconds,
        scroll: scroll.worst,
        scrollSheet: scroll.sheet,
        importSeconds: importSeconds,
        fingerprint: fingerprintSeconds,
        residentMB: Double(afterResident) / 1_048_576
      ))

    if !editOnly, env["SPARK_GRID_BENCHMARK_SKIP_SCALAR"] != "1" {
      try checkAnswers(
        workbook: imported, label: label, answersDirectory: answersDirectory, emit: emit)
    }
  }

  private static func checkAnswers(
    workbook: Workbook,
    label: String,
    answersDirectory: String,
    emit: @escaping (String) -> Void
  ) throws {
    emit("answer-check \(label) scalar evaluate")
    let stripped = withoutImportedResults(workbook)
    let scalar = ScalarFormulaAnswers.evaluate(workbook: stripped) { count in
      emit("answer-check \(label) scalar \(count)")
    }
    var byKey: [AnswerKey: CellValue] = [:]
    byKey.reserveCapacity(scalar.count)
    for answer in scalar {
      byKey[AnswerKey(sheet: answer.sheetIndex, address: answer.address)] = answer.value
    }
    emit("answer-check \(label) path under test")
    let viewModel = SpreadsheetViewModel(workbook: stripped)
    var mismatches: [(String, CellValue, CellValue)] = []
    var checked = 0
    for sheetIndex in stripped.sheets.indices {
      viewModel.selectSheet(at: sheetIndex)
      let sheet = viewModel.activeSheet
      let addresses = sheet.cells.keys.filter { FormulaSyntax.isFormula(sheet.cell(at: $0).raw) }
        .sorted()
      for address in addresses {
        let actual = viewModel.displayValue(at: address)
        let expected = byKey[AnswerKey(sheet: sheetIndex, address: address)] ?? .error(.error)
        checked += 1
        if !ScalarFormulaAnswers.same(actual, expected) {
          mismatches.append(("\(sheet.name)!\(address.a1)", expected, actual))
        }
        if checked % 5000 == 0 {
          emit("answer-check \(label) path \(checked)")
        }
      }
    }
    emit("answer-check \(label) formulas \(checked) mismatches \(mismatches.count)")
    for mismatch in mismatches.prefix(15) {
      emit(
        "mismatch \(mismatch.0) scalar \(ScalarFormulaAnswers.encode(mismatch.1)) path \(ScalarFormulaAnswers.encode(mismatch.2))"
      )
    }
    let url = URL(fileURLWithPath: answersDirectory).appendingPathComponent("\(label)-answers.txt")
    try ScalarFormulaAnswers.write(scalar, label: label, mismatches: mismatches.count, to: url)
    emit("answers \(url.path)")
  }

  private struct AnswerKey: Hashable {
    var sheet: Int
    var address: CellAddress
  }

  private static func summaryLine(
    label: String,
    open: TimeInterval,
    unsaved: TimeInterval,
    firstScreen: TimeInterval,
    firstScreenName: String,
    edit: TimeInterval,
    commit: TimeInterval,
    pixels: TimeInterval,
    paintedCells: Int,
    tab: TimeInterval,
    export: TimeInterval,
    scroll: TimeInterval,
    scrollSheet: String,
    importSeconds: TimeInterval,
    fingerprint: TimeInterval,
    residentMB: Double
  ) -> String {
    "SUMMARY\t\(label)\topen \(formatSeconds(open))\tunsaved \(formatSeconds(unsaved))\tfirst \(formatSeconds(firstScreen)) (\(firstScreenName))\tedit \(formatSeconds(edit))\tcommitEdit \(formatSeconds(commit))\tedit-to-pixels \(formatSeconds(pixels)) painted \(paintedCells)\ttab \(formatSeconds(tab))\texport \(formatSeconds(export))\tscroll \(formatSeconds(scroll)) (\(scrollSheet))\timport \(formatSeconds(importSeconds))\tfingerprint \(formatSeconds(fingerprint))\tresident \(String(format: "%.0f", residentMB))MB"
  }

  private static func formatSeconds(_ seconds: TimeInterval) -> String {
    String(format: "%.3f s", seconds)
  }

  /// A scripted trackpad fling. One sample is the main-thread cost of one 120 Hz frame.
  private static let flingHertz = 120.0
  private static let flingFrameBudget = 1.0 / flingHertz
  private static let flingLateThreshold = 0.016
  private static let flingInitialVelocity: CGFloat = 4_000
  /// Normal UIScrollView deceleration, applied per millisecond.
  private static let flingDecelerationPerMillisecond = 0.998
  private static let flingStopVelocity: CGFloat = 40
  private static let flingFrameCap = 300
  private static let flingWallCap: TimeInterval = 90
  /// Same size as the window's default content size.
  private static let flingViewport = NSRect(x: 0, y: 0, width: 1280, height: 800)

  private struct FlingStats {
    var sheet: String
    var frames: Int
    var p50: TimeInterval
    var p95: TimeInterval
    var max: TimeInterval
    var dropped: Int
    var over16: Int
    var capped: Bool
    var draws: Int
    var cellVisits: Int
    var pixels: Int
    var viewPixels: Int
    var fill: TimeInterval
    var fillCount: Int
    var latePixels: Int
  }

  private static func measureFling(
    url: URL,
    label: String,
    env: [String: String],
    emit: (String) -> Void
  ) throws {
    emit("---- \(label) fling ----")
    let names = flingSheetNames(env)
    guard !names.isEmpty else {
      emit("fling skipped: SPARK_GRID_BENCHMARK_FLING_SHEETS is empty")
      return
    }
    let store = SpreadsheetDocumentStore()
    let baselineURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("spark-grid-fling-empty-\(label).xlsx")
    try store.save(to: baselineURL)
    let openCopy = FileManager.default.temporaryDirectory
      .appendingPathComponent("spark-grid-fling-open-\(label)-\(UUID().uuidString).xlsx")
    try FileManager.default.copyItem(at: url, to: openCopy)
    defer { try? FileManager.default.removeItem(at: openCopy) }
    let autosaveDuringOpen = AppSettings.shared.autosaveEnabled
    AppSettings.shared.autosaveEnabled = false
    defer { AppSettings.shared.autosaveEnabled = autosaveDuringOpen }
    try store.load(from: openCopy, finishesInBackground: false)
    store.fileURL = nil
    drainMain()
    let viewModel = SpreadsheetViewModel(workbook: store.document.workbook)
    let grid = BenchmarkGrid(viewModel: viewModel, frame: flingViewport)
    defer { grid.close() }
    grid.grid.needsDisplay = true
    grid.grid.display()
    for name in names {
      guard
        let index = viewModel.workbook.sheets.firstIndex(where: {
          $0.name.caseInsensitiveCompare(name) == .orderedSame
        })
      else {
        emit("fling\t\(label)\t\(name)\tmissing")
        continue
      }
      let stats = timeMomentumFling(grid: grid, viewModel: viewModel, sheetIndex: index)
      emit(flingLine(label: label, stats: stats))
    }
  }

  private static func flingSheetNames(_ env: [String: String]) -> [String] {
    let raw = env["SPARK_GRID_BENCHMARK_FLING_SHEETS"] ?? ""
    return raw.split(separator: ",").map {
      $0.trimmingCharacters(in: .whitespacesAndNewlines)
    }.filter { !$0.isEmpty }
  }

  private static func timeMomentumFling(
    grid: BenchmarkGrid,
    viewModel: SpreadsheetViewModel,
    sheetIndex: Int
  ) -> FlingStats {
    viewModel.selectSheet(at: sheetIndex)
    grid.resize(to: flingViewport)
    grid.grid.reloadContent(resetScrollPosition: true)
    grid.grid.needsDisplay = true
    grid.grid.display()
    grid.grid.testingPrepareScrollTiles()
    let pixels = grid.grid.testingTilePixelMismatches()
    let viewPixels = grid.grid.testingTileViewMismatches()
    grid.grid.testingResetTileFillStats()
    var velocity = flingInitialVelocity
    var samples: [TimeInterval] = []
    var dropped = 0
    var over16 = 0
    var draws = 0
    var cellVisits = 0
    let wallStart = CFAbsoluteTimeGetCurrent()
    var capped = false
    while samples.count < flingFrameCap {
      if CFAbsoluteTimeGetCurrent() - wallStart > flingWallCap {
        capped = true
        break
      }
      let dy = velocity * CGFloat(flingFrameBudget)
      if abs(dy) < 0.5 || abs(velocity) < flingStopVelocity { break }
      let started = CFAbsoluteTimeGetCurrent()
      let moved = grid.grid.testingApplyScroll(dx: 0, dy: dy)
      let elapsed = CFAbsoluteTimeGetCurrent() - started
      if !moved { break }
      draws += grid.grid.testingGridDraws
      cellVisits += grid.grid.liveScrollCellVisits
      samples.append(elapsed)
      if elapsed > flingLateThreshold { over16 += 1 }
      let slots = Int((elapsed / flingFrameBudget).rounded(.up))
      if slots > 1 { dropped += slots - 1 }
      // Wait out the rest of this 120 Hz frame so prefetch can finish.
      // The wait is outside the sample.
      let remain = flingFrameBudget - elapsed
      if remain > 0 {
        Thread.sleep(forTimeInterval: remain)
      }
      velocity *= CGFloat(pow(flingDecelerationPerMillisecond, flingFrameBudget * 1_000))
    }
    grid.grid.testingFinishScrollTileFills()
    let sorted = samples.sorted()
    return FlingStats(
      sheet: viewModel.activeSheet.name,
      frames: samples.count,
      p50: percentile(sorted, 0.50),
      p95: percentile(sorted, 0.95),
      max: sorted.last ?? 0,
      dropped: dropped,
      over16: over16,
      capped: capped,
      draws: draws,
      cellVisits: cellVisits,
      pixels: pixels,
      viewPixels: viewPixels,
      fill: grid.grid.testingMaxTileFillSeconds,
      fillCount: grid.grid.testingTileFillCount,
      latePixels: grid.grid.testingLateTilePixelMismatches()
    )
  }

  private static func percentile(_ sorted: [TimeInterval], _ p: Double) -> TimeInterval {
    guard !sorted.isEmpty else { return 0 }
    if sorted.count == 1 { return sorted[0] }
    let rank = p * Double(sorted.count - 1)
    let lower = Int(rank)
    let upper = min(lower + 1, sorted.count - 1)
    let fraction = rank - Double(lower)
    return sorted[lower] * (1 - fraction) + sorted[upper] * fraction
  }

  private static func flingLine(label: String, stats: FlingStats) -> String {
    let cap = stats.capped ? " capped" : ""
    let head =
      "fling\t\(label)\t\(stats.sheet)\tframes \(stats.frames)\tp50 \(formatMilliseconds(stats.p50))"
    let middle =
      "p95 \(formatMilliseconds(stats.p95))\tmax \(formatMilliseconds(stats.max))\tdropped \(stats.dropped)"
    let tail =
      "over16 \(stats.over16)\tdraws \(stats.draws)\tcells \(stats.cellVisits)\tpixels \(stats.pixels)\tview \(stats.viewPixels)\(cap)"
    let fill =
      "fill \(formatMilliseconds(stats.fill)) n \(stats.fillCount) late \(stats.latePixels)"
    return "\(head)\t\(middle)\t\(tail)\t\(fill)"
  }

  private static func formatMilliseconds(_ seconds: TimeInterval) -> String {
    String(format: "%.3f ms", seconds * 1_000)
  }

  private static func timeWorstScroll(
    grid: BenchmarkGrid,
    viewModel: SpreadsheetViewModel,
    sheetIndex: Int
  ) -> (worst: TimeInterval, ticks: Int, sheet: String) {
    viewModel.selectSheet(at: sheetIndex)
    let sheet = viewModel.activeSheet
    let frame = viewportFrame(for: sheet)
    grid.resize(to: frame)
    grid.grid.reloadContent(resetScrollPosition: true)
    grid.grid.needsDisplay = true
    grid.grid.display()
    grid.grid.testingWarmScrollPlanes()
    let header = SpreadsheetGridNSView.baseHeaderSize
    let body = max(1, frame.height - header)
    let dataRows = max(1, sheet.maxPopulatedRow + 1)
    let screens = max(1, (dataRows + firstScreenRows - 1) / firstScreenRows)
    let landings = sampleLandings(screens: screens)
    var cursor = 0
    var worst = 0.0
    for landing in landings {
      let before = landing - 1
      if cursor < before {
        grid.grid.testingApplyScroll(dx: 0, dy: body * CGFloat(before - cursor))
        cursor = before
      }
      let started = CFAbsoluteTimeGetCurrent()
      grid.grid.testingApplyScroll(dx: 0, dy: body)
      worst = max(worst, CFAbsoluteTimeGetCurrent() - started)
      cursor = landing
    }
    return (worst, landings.count, sheet.name)
  }

  /// 1-based screen index each timed tick lands on.
  private static func sampleLandings(screens: Int) -> [Int] {
    if screens <= 36 {
      return Array(1...max(1, screens))
    }
    let raw = [
      1, 2, 3, max(1, screens / 4), max(1, screens / 2), max(1, (screens * 3) / 4), screens,
    ]
    return Array(Set(raw.filter { $0 >= 1 && $0 <= screens })).sorted()
  }

  private static func scrollSheetIndex(in workbook: Workbook, preferredName: String?) -> Int {
    if let preferredName,
      !preferredName.isEmpty,
      let index = workbook.sheets.firstIndex(where: {
        $0.name.caseInsensitiveCompare(preferredName) == .orderedSame
      })
    {
      return index
    }
    return workbook.sheets.indices.max { lhs, rhs in
      workbook.sheets[lhs].maxPopulatedRow < workbook.sheets[rhs].maxPopulatedRow
    } ?? 0
  }

  private static func viewportFrame(for sheet: Sheet) -> NSRect {
    let header = SpreadsheetGridNSView.baseHeaderSize
    var width = header
    let columns = min(firstScreenColumns, max(1, sheet.effectiveColumnCount))
    for column in 0..<columns {
      width += sheet.columnWidth(for: column, default: Workbook.defaultColumnWidth)
    }
    var height = header
    let rows = min(firstScreenRows, max(1, sheet.effectiveRowCount))
    for row in 0..<rows {
      height += sheet.rowHeight(for: row, default: Workbook.defaultRowHeight)
    }
    return NSRect(x: 0, y: 0, width: width + 2, height: height + 2)
  }

  private static func syncOnChange(store: SpreadsheetDocumentStore, viewModel: SpreadsheetViewModel)
  {
    store.document.workbook = viewModel.workbook
    store.documentDidChange()
  }

  private static func firstNumericLiteral(in sheet: Sheet) -> CellAddress? {
    for address in sheet.cells.keys.sorted() {
      let raw = sheet.cell(at: address).raw
      guard !FormulaSyntax.isFormula(raw) else { continue }
      if case .number = CellValue.fromLiteralRaw(raw) {
        return address
      }
    }
    return nil
  }

  private static func withoutImportedResults(_ workbook: Workbook) -> Workbook {
    var copy = workbook
    for index in copy.sheets.indices {
      var sheet = copy.sheets[index]
      let addresses = sheet.cells.compactMap { address, cell -> CellAddress? in
        cell.importedFormulaResult == nil ? nil : address
      }
      guard !addresses.isEmpty else { continue }
      for address in addresses {
        var cell = sheet.cell(at: address)
        cell.importedFormulaResult = nil
        cell.importedFormulaValueType = nil
        sheet.setCell(cell, at: address)
      }
      copy.sheets[index] = sheet
    }
    return copy
  }

  private static func validateLedger(_ workbook: Workbook) throws {
    guard let tallest = workbook.sheets.max(by: { $0.maxPopulatedRow < $1.maxPopulatedRow }),
      tallest.maxPopulatedRow + 1 >= 50_000
    else { throw BenchmarkFailure("ledger does not have 50000 rows") }

    var sawVLookup = false
    var sawIndexMatch = false
    var sawSumIfs = false
    var longestFormulaColumn = 0
    for sheet in workbook.sheets {
      var perColumn: [Int: Int] = [:]
      for (address, cell) in sheet.cells where FormulaSyntax.isFormula(cell.raw) {
        let upper = cell.raw.uppercased()
        if upper.contains("VLOOKUP") { sawVLookup = true }
        if upper.contains("INDEX"), upper.contains("MATCH") { sawIndexMatch = true }
        if upper.contains("SUMIFS") { sawSumIfs = true }
        perColumn[address.col, default: 0] += 1
      }
      longestFormulaColumn = max(longestFormulaColumn, perColumn.values.max() ?? 0)
    }
    guard sawVLookup else { throw BenchmarkFailure("ledger has no VLOOKUP") }
    guard sawIndexMatch else { throw BenchmarkFailure("ledger has no INDEX/MATCH") }
    guard sawSumIfs else { throw BenchmarkFailure("ledger has no SUMIFS") }
    guard longestFormulaColumn >= 400 else {
      throw BenchmarkFailure("dependency chain is shorter than 400 formulas")
    }

    let tallName = tallest.name
    let tallRefsOut = tallest.cells.values.contains { cell in
      FormulaSyntax.isFormula(cell.raw) && cell.raw.contains("!")
    }
    let othersRefTall = workbook.sheets.contains { sheet in
      guard sheet.name != tallName else { return false }
      return sheet.cells.values.contains { cell in
        FormulaSyntax.isFormula(cell.raw) && cell.raw.localizedCaseInsensitiveContains(tallName)
      }
    }
    guard tallRefsOut, othersRefTall else {
      throw BenchmarkFailure("cross-sheet references do not run both ways")
    }

    let wideConditionalFormat = workbook.sheets.contains { sheet in
      sheet.conditionalFormats.contains { rule in
        let bounds = rule.range.normalized
        return bounds.maxRow - bounds.minRow >= 10_000
      }
    }
    guard wideConditionalFormat else {
      throw BenchmarkFailure("conditional formatting does not cover a large range")
    }
    let wrapped = workbook.sheets.contains { sheet in
      sheet.cells.values.contains { $0.format?.textDisplay == .wrap }
    }
    guard wrapped else { throw BenchmarkFailure("wrapped text is missing") }
  }

  private static func drainMain() {
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
  }

  private static func residentBytes() -> UInt64 {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(
      MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<natural_t>.size)
    let result: kern_return_t = withUnsafeMutablePointer(to: &info) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
      }
    }
    guard result == KERN_SUCCESS else { return 0 }
    return info.resident_size
  }

  /// Export then import, with calculation left off. A wrong cached number proves we did not recalc.
  private static func compareImporters(
    env: [String: String],
    root: String,
    emit: (String) -> Void
  ) throws {
    var files: [String] = []
    let reference = env["SPARK_GRID_BENCHMARK_REFERENCE"] ?? ""
    if !reference.isEmpty, FileManager.default.fileExists(atPath: reference) {
      files.append(reference)
    }
    let ledger = env["SPARK_GRID_BENCHMARK_OTHER"] ?? "/tmp/spark-grid-phase0-ledger.xlsx"
    if FileManager.default.fileExists(atPath: ledger) {
      files.append(ledger)
    }
    let fixtures = (root as NSString).appendingPathComponent("Fixtures")
    for name in ["shared_formula_many_cells.xlsx", "Q3-Enterprise-Pipeline.xlsx"] {
      let path = (fixtures as NSString).appendingPathComponent(name)
      if FileManager.default.fileExists(atPath: path) {
        files.append(path)
      }
    }
    guard !files.isEmpty else {
      throw BenchmarkFailure("import compare has no workbooks")
    }
    for path in files {
      emit("import-compare \(path)")
      let data = try Data(contentsOf: URL(fileURLWithPath: path))
      let legacy = try XLSXCodec.importWorkbookLegacy(from: data)
      let streamed = try XLSXCodec.importWorkbook(from: data)
      emit(XLSXImportParity.summary(legacy: legacy, streamed: streamed))
    }
  }

  private static func verifyCachedFormulaRoundTrip(emit: (String) -> Void) throws {
    var sheet = Sheet(name: "Cache")
    func put(col: Int, raw: String, result: String?, type: ImportedFormulaValueType?) {
      var cell = Cell(raw: raw)
      cell.importedFormulaResult = result
      cell.importedFormulaValueType = type
      sheet.setCell(cell, at: CellAddress(row: 0, col: col))
    }
    put(col: 0, raw: "=1+2", result: "99", type: .number)
    put(col: 1, raw: "=1+2", result: "a&b<c", type: .string)
    put(col: 2, raw: "=1+2", result: "1", type: .boolean)
    put(col: 3, raw: "=1+2", result: "0", type: .boolean)
    put(col: 4, raw: "=1+2", result: "#DIV/0!", type: .error)
    put(col: 5, raw: "=1+2", result: "#N/A", type: .error)
    put(col: 6, raw: "=1+2", result: "40", type: nil)
    put(col: 7, raw: "=1+2", result: "TRUE", type: nil)
    put(col: 8, raw: "=1+2", result: nil, type: nil)
    sheet.setCell(Cell(raw: "10"), at: CellAddress(row: 1, col: 0))
    sheet.setCell(Cell(raw: "hello"), at: CellAddress(row: 1, col: 1))

    let data = try XLSXCodec.exportWorkbook(Workbook(sheets: [sheet]))
    let url = URL(fileURLWithPath: "/tmp/spark-grid-cached-formula-roundtrip.xlsx")
    try data.write(to: url, options: .atomic)
    let imported = try XLSXCodec.importWorkbook(from: data)
    let engine = FormulaEngine()
    engine.rebuild(workbook: imported, recalculate: false)
    let importedSheet = imported.sheets[0]

    func expect(
      col: Int,
      raw: String,
      result: String?,
      type: ImportedFormulaValueType?,
      value: CellValue
    ) throws {
      let address = CellAddress(row: 0, col: col)
      let cell = importedSheet.cell(at: address)
      guard cell.raw == raw else {
        throw BenchmarkFailure("raw \(address.a1) is \(cell.raw)")
      }
      guard cell.importedFormulaResult == result else {
        throw BenchmarkFailure("cache \(address.a1) is \(cell.importedFormulaResult ?? "nil")")
      }
      guard cell.importedFormulaValueType == type else {
        throw BenchmarkFailure(
          "type \(address.a1) is \(String(describing: cell.importedFormulaValueType))")
      }
      let shown = engine.displayValue(at: address, sheet: importedSheet)
      guard shown == value else {
        throw BenchmarkFailure("value \(address.a1) is \(shown)")
      }
    }

    try expect(col: 0, raw: "=1+2", result: "99", type: .number, value: .number(99))
    try expect(col: 1, raw: "=1+2", result: "a&b<c", type: .string, value: .string("a&b<c"))
    try expect(col: 2, raw: "=1+2", result: "1", type: .boolean, value: .bool(true))
    try expect(col: 3, raw: "=1+2", result: "0", type: .boolean, value: .bool(false))
    try expect(col: 4, raw: "=1+2", result: "#DIV/0!", type: .error, value: .error(.divZero))
    try expect(col: 5, raw: "=1+2", result: "#N/A", type: .error, value: .error(.na))
    try expect(col: 6, raw: "=1+2", result: "40", type: .number, value: .number(40))
    try expect(col: 7, raw: "=1+2", result: "1", type: .boolean, value: .bool(true))

    let uncached = importedSheet.cell(at: CellAddress(row: 0, col: 8))
    guard uncached.raw == "=1+2", uncached.importedFormulaResult == nil else {
      throw BenchmarkFailure("formula without a cache gained a result")
    }
    let literalNumber = importedSheet.cell(at: CellAddress(row: 1, col: 0))
    guard literalNumber.raw == "10", literalNumber.importedFormulaResult == nil else {
      throw BenchmarkFailure("literal number changed")
    }
    let literalText = importedSheet.cell(at: CellAddress(row: 1, col: 1))
    guard literalText.raw == "hello", literalText.importedFormulaResult == nil else {
      throw BenchmarkFailure("literal text changed")
    }
    emit("cached-formula-roundtrip ok \(url.path)")
  }

  private struct BenchmarkFailure: Error, CustomStringConvertible {
    var description: String
    init(_ description: String) { self.description = description }
  }
}

@MainActor
private final class BenchmarkGrid {
  let window: NSWindow
  let grid: SpreadsheetGridNSView

  init(viewModel: SpreadsheetViewModel, frame: NSRect) {
    grid = SpreadsheetGridNSView(frame: frame)
    window = NSWindow(
      contentRect: frame,
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    window.isReleasedWhenClosed = false
    window.contentView = grid
    window.setFrameOrigin(NSPoint(x: -8000, y: -8000))
    window.orderFrontRegardless()
    window.setContentSize(frame.size)
    grid.frame = frame
    grid.viewModel = viewModel
    grid.layoutSubtreeIfNeeded()
  }

  func resize(to frame: NSRect) {
    window.setContentSize(frame.size)
    grid.frame = frame
    grid.layoutSubtreeIfNeeded()
  }

  func close() {
    window.orderOut(nil)
    window.close()
  }
}
