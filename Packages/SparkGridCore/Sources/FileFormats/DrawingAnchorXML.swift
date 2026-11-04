import CoreGraphics
import Foundation
import Model

/// Small edits to a kept drawing anchor (`<xdr:twoCellAnchor>` and friends) without parsing it.
public nonisolated enum DrawingAnchorXML {
  /// The anchor with its first `ext`, the frame's size for a one-cell anchor, set to `size`
  /// points. 12,700 EMU make a point.
  public static func withSize(_ anchorXML: String, _ size: CGSize) -> String {
    guard
      let range = anchorXML.range(
        of: #"<(?:\w+:)?ext\s+cx="\d+"\s+cy="\d+""#, options: .regularExpression)
    else { return anchorXML }
    let tag = anchorXML[range]
    let name = tag.prefix { $0 != " " && $0 != "\t" && $0 != "\n" }
    let cx = Int((max(1, size.width) * 12_700).rounded())
    let cy = Int((max(1, size.height) * 12_700).rounded())
    return anchorXML.replacingCharacters(in: range, with: #"\#(name) cx="\#(cx)" cy="\#(cy)""#)
  }

  /// `<xdr:cNvPr id="4" …>`: the object's number in its drawing.
  public static func objectID(_ anchorXML: String) -> Int? {
    guard let range = cNvPrIDRange(anchorXML) else { return nil }
    return Int(anchorXML[range].filter(\.isNumber))
  }

  public static func withObjectID(_ anchorXML: String, _ id: Int) -> String {
    guard let range = cNvPrIDRange(anchorXML) else { return anchorXML }
    return anchorXML.replacingCharacters(in: range, with: #"id="\#(id)""#)
  }

  /// A copy `rows` rows lower, for Duplicate Chart.
  public static func shifted(_ chart: ForeignChart, rows: Int) -> ForeignChart {
    var copy = chart
    func moved(_ marker: DrawingMarker?) -> DrawingMarker? {
      marker.map {
        DrawingMarker(
          col: $0.col, colOffset: $0.colOffset, row: $0.row + rows, rowOffset: $0.rowOffset)
      }
    }
    copy.from = moved(chart.from)
    copy.to = moved(chart.to)
    return copy
  }

  /// The `id="…"` inside the first `cNvPr` tag.
  private static func cNvPrIDRange(_ anchorXML: String) -> Range<String.Index>? {
    guard
      let tag = anchorXML.range(of: #"<(?:\w+:)?cNvPr\b[^>]*>"#, options: .regularExpression)
    else { return nil }
    return anchorXML.range(of: #"\bid="\d+""#, options: .regularExpression, range: tag)
  }
}
