import AppKit
import SparkGridCore

/// Places category names on a chart so a label stays inside the chart
/// when its bar is still on screen.
///
/// Centered axis labels hang off the trailing edge. On a Weekly Calls sheet
/// the last bar is drawn and the last name is clipped. These placements pull
/// that name inward until its full text sits inside the chart width.
enum ChartCategoryLabelLayout {
  struct Item: Equatable {
    var index: Int
    var text: String
  }

  struct Placement: Equatable {
    var index: Int
    var text: String
    var minX: CGFloat
    var width: CGFloat

    var maxX: CGFloat { minX + width }
  }

  /// Indexes drawn under the axis. The last category is always included.
  static func labelIndexes(count: Int, desired: Int = 6) -> [Int] {
    guard count > 0 else { return [] }
    let limit = min(max(1, desired), count)
    if count <= limit { return Array(0..<count) }
    var indexes: [Int] = []
    let span = Double(limit - 1)
    for i in 0..<limit {
      let index = Int((Double(i) * Double(count - 1) / span).rounded())
      if indexes.last != index {
        indexes.append(index)
      }
    }
    if indexes.last != count - 1 {
      indexes.append(count - 1)
    }
    return indexes
  }

  /// Bar center for a plot whose domain is `-0.5 ... (count - 1) + 0.5`.
  static func barCenterX(index: Int, count: Int, plotMinX: CGFloat, plotWidth: CGFloat) -> CGFloat {
    guard count > 0 else { return plotMinX }
    let t = (CGFloat(index) + 0.5) / CGFloat(count)
    return plotMinX + plotWidth * t
  }

  static func measure(_ text: String, fontSize: CGFloat) -> CGFloat {
    let font = NSFont.systemFont(ofSize: fontSize)
    let width = (text as NSString).size(withAttributes: [.font: font]).width
    return ceil(width) + 4
  }

  /// Right-to-left so the last name keeps its place when earlier names would overlap it.
  static func placements(
    items: [Item],
    chartWidth: CGFloat,
    barCenterX: (Int) -> CGFloat,
    labelWidth: (String) -> CGFloat,
    gap: CGFloat = 4
  ) -> [Placement] {
    guard chartWidth > 1 else { return [] }
    let ordered = items.sorted { $0.index < $1.index }
    var placed: [Placement] = []
    var rightLimit = max(1, chartWidth - 1)
    for item in ordered.reversed() {
      let natural = max(1, labelWidth(item.text))
      let width = min(natural, chartWidth)
      let preferred = barCenterX(item.index) - width / 2
      var minX = min(preferred, rightLimit - width)
      if minX < 0 { minX = 0 }
      guard minX + width <= rightLimit + 0.01 else { continue }
      placed.append(Placement(index: item.index, text: item.text, minX: minX, width: width))
      rightLimit = minX - gap
      if rightLimit <= 1 { break }
    }
    return placed.sorted { $0.index < $1.index }
  }
}
