import AppKit
import SparkGridCore
import SwiftUI

/// SwiftUI colors for the Spark Grid theme (`SparkTheme`): macOS system colors in light
/// mode, the website's warm graphite in dark mode, and Spark amber as the accent.
@MainActor
enum SparkStyle {
  static let window = Color(nsColor: SparkTheme.window)
  static let canvas = Color(nsColor: SparkTheme.canvas)
  static let chrome = Color(nsColor: SparkTheme.chrome)
  static let field = Color(nsColor: SparkTheme.field)
  static let label = Color(nsColor: SparkTheme.label)
  static let secondaryLabel = Color(nsColor: SparkTheme.secondaryLabel)
  static let separator = Color(nsColor: SparkTheme.separator)
  static let chromeDivider = Color(nsColor: SparkTheme.chromeDivider)
  static let chromeBorder = Color(nsColor: SparkTheme.chromeBorder)
  static let error = Color(nsColor: SparkTheme.errorText)

  /// Spark amber, or the macOS accent when Settings says so. Reading this inside `body`
  /// ties the view to that setting, so it redraws when the setting changes.
  static var accent: Color {
    AppSettings.shared.useSystemAccent
      ? Color(nsColor: .controlAccentColor)
      : Color(nsColor: SparkTheme.sparkAmber)
  }
}
