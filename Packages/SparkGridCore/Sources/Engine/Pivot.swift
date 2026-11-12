import Foundation
import GridCore
import Model

/// One cell of a calculated pivot table.
public nonisolated enum PivotCell: Equatable, Sendable {
  case blank
  case text(String)
  case number(Double)
}

/// A calculated pivot table: a grid of cells with the header row first and the grand total last.
public nonisolated struct PivotTable: Equatable, Sendable {
  public var cells: [[PivotCell]]
  /// Rows of `cells` that are headings or totals, drawn in bold.
  public var boldRows: Set<Int>

  public var height: Int { cells.count }
  public var width: Int { cells.map(\.count).max() ?? 0 }

  /// The text a source value is grouped under. Blanks group as "(blank)", as other apps show.
  public static func label(for value: CellValue) -> String {
    switch value {
    case .blank: return "(blank)"
    case .string(let text):
      let trimmed = text.trimmingCharacters(in: .whitespaces)
      return trimmed.isEmpty ? "(blank)" : trimmed
    default: return value.displayString
    }
  }

  /// Sorts numbers by value before text, and text without regard to case.
  static func ordered(_ a: [CellValue], _ b: [CellValue]) -> Bool {
    for (x, y) in zip(a, b) {
      let lx = label(for: x)
      let ly = label(for: y)
      if lx == ly { continue }
      switch (x.asNumberIfNumeric, y.asNumberIfNumeric) {
      case (let nx?, let ny?): if nx != ny { return nx < ny }
      case (.some, nil): return true
      case (nil, .some): return false
      default: break
      }
      // "(blank)" goes last.
      if lx == "(blank)" { return false }
      if ly == "(blank)" { return true }
      let order = lx.localizedCaseInsensitiveCompare(ly)
      if order != .orderedSame { return order == .orderedAscending }
      return lx < ly
    }
    return false
  }

  /// Calculates `definition` over `records`, one array of values per source row, under
  /// `headers`. Returns nil when no value field is chosen and there is nothing to group.
  public static func calculate(
    headers: [String], records: [[CellValue]], definition: PivotDefinition
  ) -> PivotTable? {
    let width = headers.count
    func value(_ record: [CellValue], _ field: Int) -> CellValue {
      field < record.count ? record[field] : .blank
    }
    let valid = { (field: Int) in field >= 0 && field < width }
    let rowFields = definition.rows.filter(valid)
    let colFields = definition.columns.filter(valid)
    let valueFields = definition.values.filter { valid($0.field) }
    guard !rowFields.isEmpty || !colFields.isEmpty || !valueFields.isEmpty else { return nil }

    /// The label a value is grouped under, and the value its group sorts by.
    func item(_ record: [CellValue], _ field: Int) -> (label: String, sort: CellValue) {
      let v = value(record, field)
      if let group = definition.dateGroups[field], case .number(let serial) = v,
        let grouped = dateGroup(serial: serial, by: group)
      {
        return (grouped.label, .number(grouped.start))
      }
      return (label(for: v), v)
    }

    // Filters, and rows that are blank in every column, leave the source.
    let kept = records.filter { record in
      guard record.contains(where: { $0 != .blank }) else { return false }
      for filter in definition.filters where valid(filter.field) {
        if filter.hidden.contains(item(record, filter.field).label) { return false }
      }
      return true
    }

    struct Key: Hashable { var labels: [String] }
    func key(_ record: [CellValue], _ fields: [Int]) -> Key {
      Key(labels: fields.map { item(record, $0).label })
    }
    var rowSamples: [Key: [CellValue]] = [:]
    var colSamples: [Key: [CellValue]] = [:]
    // Values per (row, column, value field); a nil row or column key is that total.
    struct Bucket: Hashable {
      var row: Key?
      var col: Key?
      var value: Int
    }
    var buckets: [Bucket: Accumulator] = [:]
    for record in kept {
      let rk = key(record, rowFields)
      let ck = key(record, colFields)
      if rowSamples[rk] == nil { rowSamples[rk] = rowFields.map { item(record, $0).sort } }
      if colSamples[ck] == nil { colSamples[ck] = colFields.map { item(record, $0).sort } }
      for (index, field) in valueFields.enumerated() {
        let v = value(record, field.field)
        for bucket in [
          Bucket(row: rk, col: ck, value: index), Bucket(row: rk, col: nil, value: index),
          Bucket(row: nil, col: ck, value: index), Bucket(row: nil, col: nil, value: index),
        ] {
          buckets[bucket, default: Accumulator()].add(v)
        }
      }
    }
    let rowKeys = rowSamples.keys.sorted { ordered(rowSamples[$0] ?? [], rowSamples[$1] ?? []) }
    let colKeys = colSamples.keys.sorted { ordered(colSamples[$0] ?? [], colSamples[$1] ?? []) }

    func valueName(_ field: PivotDefinition.ValueField) -> String {
      "\(field.aggregate.label) of \(headers[field.field])"
    }
    func result(_ bucket: Bucket) -> PivotCell {
      guard let acc = buckets[bucket] else { return .blank }
      let aggregate = valueFields[bucket.value].aggregate
      guard let number = acc.result(aggregate) else { return .blank }
      return .number(number)
    }

    var cells: [[PivotCell]] = []
    var bold: Set<Int> = [0]
    // Header: the row field names, then one column per column item and value field.
    var header: [PivotCell] = rowFields.map { .text(headers[$0]) }
    var columnBuckets: [(col: Key?, value: Int)] = []
    if colFields.isEmpty {
      for index in valueFields.indices {
        header.append(.text(valueName(valueFields[index])))
        columnBuckets.append((nil, index))
      }
    } else {
      for ck in colKeys {
        for index in valueFields.indices {
          let name = ck.labels.joined(separator: " / ")
          header.append(
            .text(valueFields.count > 1 ? "\(name) – \(valueName(valueFields[index]))" : name))
          columnBuckets.append((ck, index))
        }
      }
      for index in valueFields.indices {
        header.append(
          .text(valueFields.count > 1 ? "Total \(valueName(valueFields[index]))" : "Grand Total"))
        columnBuckets.append((nil, index))
      }
    }
    if header.isEmpty { header = [.text("Values")] }
    cells.append(header)

    if !rowFields.isEmpty {
      for rk in rowKeys {
        var line: [PivotCell] = rk.labels.map { .text($0) }
        for column in columnBuckets {
          line.append(result(Bucket(row: rk, col: column.col, value: column.value)))
        }
        cells.append(line)
      }
    }
    // Grand total row.
    if !valueFields.isEmpty {
      var total: [PivotCell] = rowFields.isEmpty ? [] : [.text("Grand Total")]
      if rowFields.count > 1 {
        total += Array(repeating: .blank, count: rowFields.count - 1)
      }
      for column in columnBuckets {
        total.append(result(Bucket(row: nil, col: column.col, value: column.value)))
      }
      bold.insert(cells.count)
      cells.append(total)
    }
    return PivotTable(cells: cells, boldRows: bold)
  }

  /// A date serial (days since 30 Dec 1899) as its year, quarter, month or day: the label shown
  /// and the serial the group starts on, for sorting.
  public static func dateGroup(serial: Double, by group: PivotDefinition.DateGroup) -> (
    label: String, start: Double
  )? {
    guard serial.isFinite, serial >= 1, serial < 2_958_466 else { return nil }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
    let epoch = DateComponents(calendar: calendar, year: 1899, month: 12, day: 30).date
    guard let epoch,
      let date = calendar.date(byAdding: .day, value: Int(serial.rounded(.down)), to: epoch)
    else { return nil }
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
    let months = [
      "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    ]
    let label: String
    var start = DateComponents(year: year, month: 1, day: 1)
    switch group {
    case .year:
      label = String(year)
    case .quarter:
      let quarter = (month - 1) / 3 + 1
      label = "Q\(quarter) \(year)"
      start.month = (quarter - 1) * 3 + 1
    case .month:
      label = "\(months[month - 1]) \(year)"
      start.month = month
    case .day:
      label = "\(months[month - 1]) \(day), \(year)"
      start.month = month
      start.day = day
    }
    guard let first = calendar.date(from: start) else { return nil }
    let days = calendar.dateComponents([.day], from: epoch, to: first).day ?? 0
    return (label, Double(days))
  }

  struct Accumulator: Equatable {
    var count = 0
    var numericCount = 0
    var sum = 0.0
    var minimum = Double.infinity
    var maximum = -Double.infinity

    mutating func add(_ value: CellValue) {
      if value == .blank { return }
      if case .string(let text) = value, text.trimmingCharacters(in: .whitespaces).isEmpty {
        return
      }
      count += 1
      guard let number = value.asNumberIfNumeric else { return }
      numericCount += 1
      sum += number
      minimum = Swift.min(minimum, number)
      maximum = Swift.max(maximum, number)
    }

    func result(_ aggregate: PivotDefinition.Aggregate) -> Double? {
      switch aggregate {
      case .count: return count > 0 ? Double(count) : nil
      case .sum: return numericCount > 0 ? sum : (count > 0 ? 0 : nil)
      case .average: return numericCount > 0 ? sum / Double(numericCount) : nil
      case .min: return numericCount > 0 ? minimum : nil
      case .max: return numericCount > 0 ? maximum : nil
      }
    }
  }
}

extension CellValue {
  /// A number, not text that reads as one. Pivot values count only real numbers, as other
  /// spreadsheet apps do.
  fileprivate var asNumberIfNumeric: Double? {
    if case .number(let n) = self { return n }
    return nil
  }
}
