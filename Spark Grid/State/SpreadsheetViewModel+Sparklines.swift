import Foundation
import SparkGridCore

/// Sparklines: small charts drawn inside cells (Insert › Sparklines…).
extension SpreadsheetViewModel {
  /// The numbers a sparkline plots, in order; a blank or text cell is a gap.
  func sparklineValues(_ line: SparklineGroup.Sparkline) -> [Double?] {
    let n = line.data.normalized
    var values: [Double?] = []
    values.reserveCapacity((n.maxRow - n.minRow + 1) * (n.maxCol - n.minCol + 1))
    // At most a few hundred points: a cell is only so wide.
    for row in n.minRow...n.maxRow {
      for col in n.minCol...n.maxCol {
        values.append(chartNumber(sheetName: line.dataSheet, at: CellAddress(row: row, col: col)))
        if values.count >= 500 { return values }
      }
    }
    return values
  }

  /// Puts a sparkline of each row or column of `data` in the cells of `locations`. Returns a
  /// sentence saying what is wrong when the two do not line up.
  @discardableResult
  func insertSparklines(
    kind: SparklineGroup.Kind, data: CellRange, dataSheet: String? = nil, locations: CellRange,
    colorHex: String = SparklineGroup.defaultColor, showsMarkers: Bool = false,
    showsHighLow: Bool = false
  ) -> String? {
    guard let lines = SparklineGroup.layout(data: data, locations: locations) else {
      return
        "Choose one cell for a single row or column of data, or a row or column of cells with one cell for each row or column of data."
    }
    var placed = lines
    if let dataSheet, dataSheet != activeSheet.name {
      placed = lines.map {
        SparklineGroup.Sparkline(location: $0.location, dataSheet: dataSheet, data: $0.data)
      }
    }
    let group = SparklineGroup(
      kind: kind, colorHex: colorHex, showsMarkers: showsMarkers, showsHighLow: showsHighLow,
      sparklines: placed)
    let cells = Set(placed.map(\.location))
    updateFileExtras(actionName: "Insert Sparklines") { extras in
      // A cell holds one sparkline: a new one replaces what was there.
      extras.sparklines = Self.removing(cells, from: extras.sparklines)
      extras.sparklines.append(group)
    }
    return nil
  }

  /// Whether a cell in `range` holds a sparkline.
  func hasSparklines(in range: CellRange) -> Bool {
    let n = range.normalized
    return activeSheet.fileExtras.sparklines.contains { group in
      group.sparklines.contains {
        (n.minRow...n.maxRow).contains($0.location.row)
          && (n.minCol...n.maxCol).contains($0.location.col)
      }
    }
  }

  /// Removes the sparklines in the selected cells.
  func clearSparklines(in range: CellRange) {
    let n = range.normalized
    var cells = Set<CellAddress>()
    for group in activeSheet.fileExtras.sparklines {
      for line in group.sparklines
      where (n.minRow...n.maxRow).contains(line.location.row)
        && (n.minCol...n.maxCol).contains(line.location.col)
      {
        cells.insert(line.location)
      }
    }
    guard !cells.isEmpty else { return }
    updateFileExtras(actionName: "Clear Sparklines") { extras in
      extras.sparklines = Self.removing(cells, from: extras.sparklines)
    }
  }

  private static func removing(_ cells: Set<CellAddress>, from groups: [SparklineGroup])
    -> [SparklineGroup]
  {
    groups.compactMap { group in
      var next = group
      next.sparklines.removeAll { cells.contains($0.location) }
      return next.sparklines.isEmpty ? nil : next
    }
  }
}
