import Calc
import FileFormats
import Formula
import Foundation
import Functions
import GridCore
import Model
import NumberFormat

/// Builds plottable series from an explicit chart configuration (category + value / count).
public enum ChartPreviewSeries {
  /// Soft cap for sidebar readability; full count is still reported.
  public static let maxPreviewPoints = 40

  public struct Point: Identifiable, Equatable {
    public let id: Int
    public let label: String
    public let value: Double
  }

  public struct ColumnOption: Identifiable, Equatable {
    public let column: Int
    public let header: String
    public let numericCount: Int
    public let textCount: Int

    public var id: Int { column }

    public var displayName: String {
      let letter = CellAddress(row: 0, col: column).a1.filter(\.isLetter)
      if header.isEmpty { return "Column \(letter)" }
      return "\(letter) — \(header)"
    }

    public var isMostlyNumeric: Bool { numericCount > textCount && numericCount > 0 }
    public var isMostlyText: Bool { textCount >= numericCount && textCount > 0 }
  }

  public struct Suggestion: Equatable {
    public var categoryColumn: Int
    public var valueColumn: Int
    public var hasHeaderRow: Bool
    public var valueMode: SheetChart.ValueMode
  }

  public static func points(
    for chart: SheetChart,
    labelFor: (CellAddress) -> String,
    numberFor: (CellAddress) -> Double?
  ) -> (points: [Point], totalCount: Int) {
    let resolved = resolve(chart: chart, labelFor: labelFor, numberFor: numberFor)
    let uncapped = buildPoints(
      range: chart.dataRange,
      categoryColumn: resolved.categoryColumn,
      valueColumn: resolved.valueColumn,
      hasHeaderRow: resolved.hasHeaderRow,
      valueMode: resolved.valueMode,
      labelFor: labelFor,
      numberFor: numberFor
    )
    return (capped(uncapped), uncapped.count)
  }

  /// Legacy entry used by older tests — infers columns from the range.
  public static func points(
    in range: CellRange,
    labelFor: (CellAddress) -> String,
    numberFor: (CellAddress) -> Double?
  ) -> [Point] {
    let suggestion = suggest(in: range, labelFor: labelFor, numberFor: numberFor)
    let chart = SheetChart(
      dataRange: range,
      categoryColumn: suggestion.categoryColumn,
      valueColumn: suggestion.valueColumn,
      hasHeaderRow: suggestion.hasHeaderRow,
      valueMode: suggestion.valueMode,
      anchorRow: 0,
      anchorCol: 0
    )
    return points(for: chart, labelFor: labelFor, numberFor: numberFor).points
  }

  public static func columnOptions(
    in range: CellRange,
    labelFor: (CellAddress) -> String,
    numberFor: (CellAddress) -> Double?
  ) -> [ColumnOption] {
    let n = range.normalized
    let headerRow = n.minRow
    let dataRows = Array((n.minRow + 1)...n.maxRow)
    let sampleRows = dataRows.isEmpty ? [n.minRow] : dataRows
    return (n.minCol...n.maxCol).map { col in
      let header = labelFor(CellAddress(row: headerRow, col: col)).trimmingCharacters(
        in: .whitespacesAndNewlines)
      var numeric = 0
      var text = 0
      for row in sampleRows {
        let address = CellAddress(row: row, col: col)
        let label = labelFor(address).trimmingCharacters(in: .whitespacesAndNewlines)
        if numberFor(address) != nil {
          numeric += 1
        } else if !label.isEmpty {
          text += 1
        }
      }
      return ColumnOption(column: col, header: header, numericCount: numeric, textCount: text)
    }
  }

  public static func suggest(
    in range: CellRange,
    labelFor: (CellAddress) -> String,
    numberFor: (CellAddress) -> Double?
  ) -> Suggestion {
    let n = range.normalized
    let options = columnOptions(in: range, labelFor: labelFor, numberFor: numberFor)
    let hasHeader = detectHeaderRow(
      in: range, options: options, labelFor: labelFor, numberFor: numberFor)

    let textCols = options.filter(\.isMostlyText)
    let numericCols = options.filter(\.isMostlyNumeric)

    let category =
      textCols.first?.column
      ?? options.first(where: { !$0.isMostlyNumeric })?.column
      ?? n.minCol

    if let value = numericCols.first(where: { $0.column != category })?.column
      ?? numericCols.first?.column
    {
      return Suggestion(
        categoryColumn: category,
        valueColumn: value,
        hasHeaderRow: hasHeader,
        valueMode: .values
      )
    }

    // No numeric column — default to counting rows per category (CRM-style tables).
    let fallbackValue = options.first(where: { $0.column != category })?.column ?? category
    return Suggestion(
      categoryColumn: category,
      valueColumn: fallbackValue,
      hasHeaderRow: hasHeader,
      valueMode: .count
    )
  }

  public static func seriesDescription(
    for chart: SheetChart, categoryHeader: String, valueHeader: String
  ) -> String {
    let cat = categoryHeader.isEmpty ? "categories" : categoryHeader
    switch chart.valueMode {
    case .count:
      return "Count by \(cat)"
    case .values:
      let val = valueHeader.isEmpty ? "values" : valueHeader
      return "\(val) by \(cat)"
    }
  }

  // MARK: - Private

  private struct Resolved {
    public var categoryColumn: Int
    public var valueColumn: Int
    public var hasHeaderRow: Bool
    public var valueMode: SheetChart.ValueMode
  }

  private static func resolve(
    chart: SheetChart,
    labelFor: (CellAddress) -> String,
    numberFor: (CellAddress) -> Double?
  ) -> Resolved {
    let n = chart.dataRange.normalized
    if let category = chart.categoryColumn, let value = chart.valueColumn {
      return Resolved(
        categoryColumn: category,
        valueColumn: value,
        hasHeaderRow: chart.hasHeaderRow,
        valueMode: chart.valueMode
      )
    }
    let suggestion = suggest(in: chart.dataRange, labelFor: labelFor, numberFor: numberFor)
    return Resolved(
      categoryColumn: chart.categoryColumn ?? suggestion.categoryColumn,
      valueColumn: chart.valueColumn ?? suggestion.valueColumn,
      hasHeaderRow: chart.categoryColumn == nil ? suggestion.hasHeaderRow : chart.hasHeaderRow,
      valueMode: chart.categoryColumn == nil ? suggestion.valueMode : chart.valueMode
    )
  }

  private static func buildPoints(
    range: CellRange,
    categoryColumn: Int,
    valueColumn: Int,
    hasHeaderRow: Bool,
    valueMode: SheetChart.ValueMode,
    labelFor: (CellAddress) -> String,
    numberFor: (CellAddress) -> Double?
  ) -> [Point] {
    let n = range.normalized
    let startRow = hasHeaderRow && n.maxRow > n.minRow ? n.minRow + 1 : n.minRow
    guard startRow <= n.maxRow else { return [] }

    switch valueMode {
    case .values:
      var result: [Point] = []
      var index = 0
      for row in startRow...n.maxRow {
        guard let value = numberFor(CellAddress(row: row, col: valueColumn)), value.isFinite else {
          continue
        }
        let raw = labelFor(CellAddress(row: row, col: categoryColumn))
          .trimmingCharacters(in: .whitespacesAndNewlines)
        let label = raw.isEmpty ? "\(index + 1)" : raw
        result.append(Point(id: index, label: label, value: value))
        index += 1
      }
      return result

    case .count:
      var counts: [String: Double] = [:]
      var order: [String] = []
      for row in startRow...n.maxRow {
        let raw = labelFor(CellAddress(row: row, col: categoryColumn))
          .trimmingCharacters(in: .whitespacesAndNewlines)
        let label = raw.isEmpty ? "(blank)" : raw
        if counts[label] == nil {
          order.append(label)
          counts[label] = 0
        }
        counts[label, default: 0] += 1
      }
      return order.enumerated().map {
        Point(id: $0.offset, label: $0.element, value: counts[$0.element] ?? 0)
      }
    }
  }

  private static func capped(_ points: [Point]) -> [Point] {
    guard points.count > maxPreviewPoints else { return points }
    return Array(points.prefix(maxPreviewPoints))
  }

  private static func detectHeaderRow(
    in range: CellRange,
    options: [ColumnOption],
    labelFor: (CellAddress) -> String,
    numberFor: (CellAddress) -> Double?
  ) -> Bool {
    let n = range.normalized
    guard n.maxRow > n.minRow else { return false }
    // Header-like if first row is mostly non-numeric text across columns.
    var textish = 0
    var numeric = 0
    for col in n.minCol...n.maxCol {
      let address = CellAddress(row: n.minRow, col: col)
      let text = labelFor(address).trimmingCharacters(in: .whitespacesAndNewlines)
      if numberFor(address) != nil {
        numeric += 1
      } else if !text.isEmpty {
        textish += 1
      }
    }
    return textish > numeric && textish > 0
  }
}
