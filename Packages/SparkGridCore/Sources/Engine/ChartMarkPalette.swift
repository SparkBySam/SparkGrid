import Calc
import FileFormats
import Formula
import Foundation
import Functions
import GridCore
import Model
import NumberFormat

/// Preset series colors. A chart paints one series color (its own, or the first
/// swatch) and optional per-point overrides. The swatches stay distinct so the
/// format controls can offer them as a palette.
public enum ChartMarkPalette {
  public struct RGB: Equatable, Hashable {
    public var red: Double
    public var green: Double
    public var blue: Double
  }

  public static let swatches: [RGB] = [
    RGB(red: 0.18, green: 0.45, blue: 0.86),
    RGB(red: 0.90, green: 0.42, blue: 0.18),
    RGB(red: 0.16, green: 0.62, blue: 0.38),
    RGB(red: 0.72, green: 0.28, blue: 0.58),
    RGB(red: 0.52, green: 0.36, blue: 0.82),
    RGB(red: 0.86, green: 0.68, blue: 0.16),
    RGB(red: 0.14, green: 0.62, blue: 0.70),
    RGB(red: 0.82, green: 0.28, blue: 0.28),
    RGB(red: 0.36, green: 0.52, blue: 0.28),
    RGB(red: 0.48, green: 0.32, blue: 0.22),
  ]

  public static func swatch(at index: Int) -> RGB {
    let count = swatches.count
    let wrapped = ((index % count) + count) % count
    return swatches[wrapped]
  }
}
