import Calc
import Engine
import FileFormats
import Formula
import Foundation
import GridCore
import Model

@main
struct SparkGridCLI {
  static func main() {
    let status = SparkGridCommandLine.run(Array(CommandLine.arguments.dropFirst()))
    exit(status)
  }
}

enum SparkGridCommandLine {
  static let usage = """
    spark-grid-cli eval '<formula>'
    spark-grid-cli cat <file> --sheet S --range A1:F20
    spark-grid-cli recalc <file>
    spark-grid-cli check <file>
    spark-grid-cli bench <file>
    spark-grid-cli run <file> --cmd '<command json>' --out <file>

    check compares saved formula results. It does not print cell values.
    bench times import, fingerprint, recalc, and export. Painted-grid timings stay on the app:
    SPARK_GRID_BENCHMARK=1.
    """

  static func run(_ args: [String]) -> Int32 {
    guard let name = args.first else {
      FileHandle.standardError.write(Data(usage.utf8))
      return 2
    }
    let rest = Array(args.dropFirst())
    switch name {
    case "-h", "--help", "help":
      print(usage)
      return 0
    case "eval":
      return eval(rest)
    case "cat":
      return cat(rest)
    case "recalc":
      return recalc(rest)
    case "check":
      return check(rest)
    case "calccheck":
      return calcCheck(rest)
    case "bench":
      return bench(rest)
    case "run":
      return runCommand(rest)
    default:
      fputs("unknown command \(name)\n\(usage)\n", stderr)
      return 2
    }
  }

  private static func eval(_ args: [String]) -> Int32 {
    let source = args.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !source.isEmpty else {
      fputs("eval needs a formula\n", stderr)
      return 2
    }
    let raw = source.hasPrefix("=") ? source : "=" + source
    var sheet = Sheet(name: "Sheet1")
    sheet.setCell(Cell(raw: raw), at: .origin)
    let workbook = Workbook(sheets: [sheet])
    let engine = FormulaEngine()
    engine.rebuild(workbook: workbook, recalculate: true)
    let value = engine.displayValue(at: .origin, sheet: workbook.sheets[0])
    print(value.displayString)
    return 0
  }

  private static func cat(_ args: [String]) -> Int32 {
    let parsed = ParsedArguments(args)
    guard let path = parsed.positional.first else {
      fputs("cat needs a file\n", stderr)
      return 2
    }
    guard let rangeText = parsed.options["range"] else {
      fputs("cat needs --range A1:F20\n", stderr)
      return 2
    }
    guard let range = parseRange(rangeText) else {
      fputs("cat could not read the range\n", stderr)
      return 2
    }
    let bounds = range.normalized
    let rowCount = bounds.maxRow - bounds.minRow + 1
    let colCount = bounds.maxCol - bounds.minCol + 1
    guard rowCount <= 200, colCount <= 40,
      InputBounds.materializedCount(rows: rowCount, cols: colCount) != nil
    else {
      fputs("cat range is too large\n", stderr)
      return 2
    }
    guard let workbook = loadWorkbook(at: path) else { return 1 }
    let sheet: Sheet
    if let name = parsed.options["sheet"] {
      guard
        let found = workbook.sheets.first(where: {
          $0.name.caseInsensitiveCompare(name) == .orderedSame
        })
      else {
        fputs("cat sheet was not found\n", stderr)
        return 1
      }
      sheet = found
    } else {
      sheet = workbook.activeSheet
    }
    let shown = displayGrid(workbook: workbook, sheet: sheet, range: range)
    print(shown)
    return 0
  }

  private static func recalc(_ args: [String]) -> Int32 {
    guard let path = args.first, !path.hasPrefix("-") else {
      fputs("recalc needs a file\n", stderr)
      return 2
    }
    guard let workbook = loadWorkbook(at: path) else { return 1 }
    let cleared = AnswerComparison.clearingFormulaCaches(workbook)
    let started = CFAbsoluteTimeGetCurrent()
    let results = AnswerComparison.calculatedFormulaResults(in: cleared)
    let elapsed = CFAbsoluteTimeGetCurrent() - started
    let errors = results.values.filter(\.isError).count
    print(
      "recalc \(String(format: "%.3f", elapsed))s formulas \(results.count) errors \(errors)"
    )
    return 0
  }

  /// Saved results against the whole-workbook pass and the open pass, with mismatches by sheet.
  private static func calcCheck(_ args: [String]) -> Int32 {
    guard let path = args.first, !path.hasPrefix("-") else {
      fputs("calccheck needs a file\n", stderr)
      return 2
    }
    guard let workbook = loadWorkbook(at: path) else { return 1 }
    let exempt = exemptions(for: URL(fileURLWithPath: path).lastPathComponent)
    var failed = false
    for result in AnswerComparison.compareCalculationPaths(in: workbook, exempt: exempt) {
      print("\(result.name) checked \(result.checked) mismatches \(result.mismatches.count)")
      var bySheet: [String: Int] = [:]
      for mismatch in result.mismatches {
        let sheet = mismatch.key.split(separator: "!").first.map(String.init) ?? "?"
        bySheet[sheet, default: 0] += 1
      }
      for (sheet, count) in bySheet.sorted(by: { $0.value > $1.value }) {
        print("  \(sheet): \(count)")
      }
      for mismatch in result.mismatches.prefix(12) {
        print("  \(mismatch.key) expected \(mismatch.expected) got \(mismatch.actual)")
      }
      if !result.mismatches.isEmpty { failed = true }
    }
    return failed ? 1 : 0
  }

  private static func check(_ args: [String]) -> Int32 {
    guard let path = args.first, !path.hasPrefix("-") else {
      fputs("check needs a file\n", stderr)
      return 2
    }
    guard let workbook = loadWorkbook(at: path) else { return 1 }
    let fileName = URL(fileURLWithPath: path).lastPathComponent
    let exempt = exemptions(for: fileName)
    let editSheets = ["June", "January"]
    let paths = AnswerComparison.comparePaths(
      in: workbook,
      editSheetNames: editSheets,
      exempt: exempt
    )
    var failed = false
    for path in paths {
      let seedNote = path.name == "shuffled" ? " seed \(AnswerComparison.displayShuffleSeed)" : ""
      print(
        "\(path.name)\(seedNote) checked \(path.checked) mismatches \(path.mismatches.count) exempt \(exempt.count)"
      )
      if path.checked == 0 {
        fputs("\(path.name) checked 0 formulas\n", stderr)
        failed = true
      }
      if !path.mismatches.isEmpty {
        let sample = path.mismatches.prefix(15).map(\.key).joined(separator: ", ")
        print("\(path.name) mismatch cells \(sample)")
        failed = true
      }
    }
    if let edits = paths.first(where: { $0.name == "edits" }), edits.editedSheets == 0 {
      fputs("edits did not run on \(editSheets.joined(separator: ", "))\n", stderr)
      failed = true
    }
    return failed ? 1 : 0
  }

  private static func bench(_ args: [String]) -> Int32 {
    guard let path = args.first, !path.hasPrefix("-") else {
      fputs("bench needs a file\n", stderr)
      return 2
    }
    let url = URL(fileURLWithPath: path)
    guard let data = try? Data(contentsOf: url) else {
      fputs("bench could not read the file\n", stderr)
      return 1
    }
    let importStart = CFAbsoluteTimeGetCurrent()
    guard let workbook = importData(data, path: path) else {
      fputs("bench could not import the file\n", stderr)
      return 1
    }
    let importElapsed = CFAbsoluteTimeGetCurrent() - importStart
    let fingerprintStart = CFAbsoluteTimeGetCurrent()
    _ = WorkbookFingerprint.data(for: workbook)
    let fingerprintElapsed = CFAbsoluteTimeGetCurrent() - fingerprintStart
    let recalcStart = CFAbsoluteTimeGetCurrent()
    let results = AnswerComparison.calculatedFormulaResults(
      in: AnswerComparison.clearingFormulaCaches(workbook)
    )
    let recalcElapsed = CFAbsoluteTimeGetCurrent() - recalcStart
    let exportStart = CFAbsoluteTimeGetCurrent()
    do {
      _ = try XLSXCodec.exportWorkbook(workbook, includeFormulaCaches: true)
    } catch {
      fputs("bench could not export\n", stderr)
      return 1
    }
    let exportElapsed = CFAbsoluteTimeGetCurrent() - exportStart
    let errors = results.values.filter(\.isError).count
    let lines = [
      "import \(String(format: "%.3f", importElapsed))s",
      "fingerprint \(String(format: "%.3f", fingerprintElapsed))s",
      "recalc \(String(format: "%.3f", recalcElapsed))s",
      "export \(String(format: "%.3f", exportElapsed))s",
      "formulas \(results.count)",
      "errors \(errors)",
      "painted-grid timings stay on the app: SPARK_GRID_BENCHMARK=1",
    ]
    let report = lines.joined(separator: "\n")
    print(report)
    if let log = ProcessInfo.processInfo.environment["SPARK_GRID_BENCHMARK_LOG"],
      log.hasPrefix("/tmp/")
    {
      try? report.appending("\n").write(
        to: URL(fileURLWithPath: log), atomically: true, encoding: .utf8)
    }
    return 0
  }

  private static func runCommand(_ args: [String]) -> Int32 {
    let parsed = ParsedArguments(args)
    guard let path = parsed.positional.first else {
      fputs("run needs a file\n", stderr)
      return 2
    }
    guard let commandJSON = parsed.options["cmd"] else {
      fputs("run needs --cmd '<command json>'\n", stderr)
      return 2
    }
    guard let out = parsed.options["out"] else {
      fputs("run needs --out <file>\n", stderr)
      return 2
    }
    guard let commands = parseCommands(commandJSON) else {
      fputs("run could not read the command json\n", stderr)
      return 2
    }
    guard var workbook = loadWorkbook(at: path) else { return 1 }
    let session = WorkbookSession(workbook: workbook)
    for command in commands {
      let outcome = session.run(id: command.id, arguments: command.arguments)
      if !outcome.ok {
        fputs("\(command.id): \(outcome.message)\n", stderr)
        return 1
      }
    }
    workbook = session.workbook
    do {
      let data = try XLSXCodec.exportWorkbook(workbook, includeFormulaCaches: true)
      try data.write(to: URL(fileURLWithPath: out), options: .atomic)
    } catch {
      fputs("run could not write the output\n", stderr)
      return 1
    }
    print("wrote \(out)")
    return 0
  }

  private struct ParsedCommand {
    var id: String
    var arguments: [String: String]
  }

  private static func parseCommands(_ text: String) -> [ParsedCommand]? {
    guard let data = text.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data)
    else { return nil }
    if let list = object as? [Any] {
      let commands = list.compactMap(parseCommandObject)
      return commands.count == list.count ? commands : nil
    }
    if let one = parseCommandObject(object) { return [one] }
    return nil
  }

  private static func parseCommandObject(_ object: Any) -> ParsedCommand? {
    guard let fields = object as? [String: Any], let id = fields["id"] as? String, !id.isEmpty
    else { return nil }
    let raw = (fields["arguments"] as? [String: Any]) ?? (fields["args"] as? [String: Any]) ?? [:]
    var arguments: [String: String] = [:]
    for (key, value) in raw {
      guard let text = stringify(value) else { continue }
      arguments[key] = text
    }
    return ParsedCommand(id: id, arguments: arguments)
  }

  private static func stringify(_ value: Any) -> String? {
    if let text = value as? String { return text }
    if let flag = value as? Bool { return flag ? "true" : "false" }
    if let number = value as? NSNumber {
      if CFGetTypeID(number) == CFBooleanGetTypeID() {
        return number.boolValue ? "true" : "false"
      }
      return number.stringValue
    }
    return nil
  }

  private static func loadWorkbook(at path: String) -> Workbook? {
    let url = URL(fileURLWithPath: path)
    guard let data = try? Data(contentsOf: url) else {
      fputs("could not read \(url.lastPathComponent)\n", stderr)
      return nil
    }
    return importData(data, path: path)
  }

  private static func importData(_ data: Data, path: String) -> Workbook? {
    let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
    if ext == "csv" || ext == "tsv" || ext == "txt" {
      guard let text = String(data: data, encoding: .utf8) else {
        fputs("could not read text\n", stderr)
        return nil
      }
      let cells = CSVCodec.importCSV(text)
      return Workbook(sheets: [Sheet(name: "Sheet1", cells: cells)])
    }
    do {
      return try XLSXCodec.importWorkbook(from: data)
    } catch {
      fputs("could not import the workbook\n", stderr)
      return nil
    }
  }

  private static func displayGrid(workbook: Workbook, sheet: Sheet, range: CellRange) -> String {
    let engine = FormulaEngine()
    engine.recalculateEntireWorkbook(workbook)
    let stored = engine.formulaResults(on: sheet)
    let bounds = range.normalized
    var rows: [[String]] = []
    var widths = Array(repeating: 0, count: bounds.maxCol - bounds.minCol + 1)
    for row in bounds.minRow...bounds.maxRow {
      var fields: [String] = []
      for col in bounds.minCol...bounds.maxCol {
        let address = CellAddress(row: row, col: col)
        let cell = sheet.cell(at: address)
        let text: String
        if FormulaSyntax.isFormula(cell.raw) {
          text = (stored[address] ?? .blank).displayString
        } else {
          text = CellValue.fromLiteralRaw(cell.raw).displayString
        }
        let clipped = text.count > 40 ? String(text.prefix(40)) : text
        fields.append(clipped)
        let index = col - bounds.minCol
        if clipped.count > widths[index] { widths[index] = clipped.count }
      }
      rows.append(fields)
    }
    return rows.map { fields in
      fields.enumerated().map { index, field in
        field.padding(toLength: widths[index], withPad: " ", startingAt: 0)
      }.joined(separator: "  ")
    }.joined(separator: "\n")
  }

  private static func parseRange(_ text: String) -> CellRange? {
    let parts = text.split(separator: ":").map(String.init)
    func address(_ token: String) -> CellAddress? {
      guard let parsed = A1Reference.parseAddress(token) else { return nil }
      return CellAddress(row: parsed.row, col: parsed.col)
    }
    if parts.count == 1, let only = address(parts[0]) {
      return CellRange(start: only, end: only)
    }
    guard parts.count == 2, let start = address(parts[0]), let end = address(parts[1]) else {
      return nil
    }
    return CellRange(start: start, end: end)
  }

  private static func exemptions(for fileName: String) -> Set<String> {
    var directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let marker = "corpus/known-differences.md"
    for _ in 0..<6 {
      let candidate = directory.appendingPathComponent(marker)
      if let text = try? String(contentsOf: candidate, encoding: .utf8) {
        return exemptionKeys(in: text, fileName: fileName)
      }
      directory.deleteLastPathComponent()
    }
    return []
  }

  private static func exemptionKeys(in markdown: String, fileName: String) -> Set<String> {
    let needle = fileName.lowercased()
    var keys: Set<String> = []
    for raw in markdown.split(separator: "\n") {
      let line = String(raw)
      guard line.lowercased().contains(needle) else { continue }
      guard
        let range = line.range(
          of: #"([A-Za-z0-9][^!|\n]*![A-Z]+[0-9]+)"#,
          options: .regularExpression
        )
      else { continue }
      keys.insert(line[range].lowercased())
    }
    return keys
  }
}

private struct ParsedArguments {
  var positional: [String] = []
  var options: [String: String] = [:]

  init(_ args: [String]) {
    var index = 0
    while index < args.count {
      let token = args[index]
      if token == "--", index + 1 < args.count {
        positional.append(contentsOf: args[(index + 1)...])
        break
      }
      if token.hasPrefix("--"), let eq = token.firstIndex(of: "=") {
        let key = String(token[token.index(token.startIndex, offsetBy: 2)..<eq])
        options[key] = String(token[token.index(after: eq)...])
      } else if token.hasPrefix("--") {
        let key = String(token.dropFirst(2))
        let next = index + 1
        if next < args.count, !args[next].hasPrefix("--") {
          options[key] = args[next]
          index += 1
        } else {
          options[key] = ""
        }
      } else {
        positional.append(token)
      }
      index += 1
    }
  }
}
