import AppKit
import SparkGridCore
import SwiftUI

struct SpreadsheetFormatCommands: Commands {
  @Bindable private var settings = AppSettings.shared
  @FocusedValue(\.spreadsheetViewModel) private var viewModel: SpreadsheetViewModel?

  var body: some Commands {
    CommandMenu("Format") {
      Button("Bold") { viewModel?.toggleBold() }
        .keyboardShortcut(
          settings.keyEquivalent(for: .bold), modifiers: settings.eventModifiers(for: .bold)
        )
        .disabled(viewModel == nil)
      Button("Italic") { viewModel?.toggleItalic() }
        .keyboardShortcut(
          settings.keyEquivalent(for: .italic), modifiers: settings.eventModifiers(for: .italic)
        )
        .disabled(viewModel == nil)
      Button("Underline") { viewModel?.toggleUnderline() }
        .keyboardShortcut(
          settings.keyEquivalent(for: .underline),
          modifiers: settings.eventModifiers(for: .underline)
        )
        .disabled(viewModel == nil)
      Button("Strikethrough") { viewModel?.toggleStrikethrough() }
        .disabled(viewModel == nil)

      Divider()

      Menu("Align") {
        Button("Align Left") { viewModel?.setHorizontalAlign(.left) }
        Button("Align Center") { viewModel?.setHorizontalAlign(.center) }
        Button("Align Right") { viewModel?.setHorizontalAlign(.right) }
        Divider()
        Button("Align Top") { viewModel?.setVerticalAlign(.top) }
        Button("Align Middle") { viewModel?.setVerticalAlign(.middle) }
        Button("Align Bottom") { viewModel?.setVerticalAlign(.bottom) }
      }
      .disabled(viewModel == nil)

      Menu("Text") {
        Button("Overflow") { viewModel?.setTextDisplay(.overflow) }
        Button("Wrap") { viewModel?.setTextDisplay(.wrap) }
        Button("Clip") { viewModel?.setTextDisplay(.clip) }
      }
      .disabled(viewModel == nil)

      Menu("Number") {
        Button("General") { viewModel?.setNumberFormat(.general) }
        Button("Number") { viewModel?.setNumberFormat(.number) }
        Button("Currency") { viewModel?.setNumberFormat(.currency) }
        Button("Percent") { viewModel?.setNumberFormat(.percent) }
        Button("Scientific") { viewModel?.setNumberFormat(.scientific) }
        Button("Date") { viewModel?.setNumberFormat(.date) }
        Button("Time") { viewModel?.setNumberFormat(.time) }
      }
      .disabled(viewModel == nil)

      Button("Cell Format…") {
        guard let viewModel else { return }
        CellFormatViewerPresenter.present(from: viewModel)
      }
      .disabled(viewModel == nil)

      Menu("Borders") {
        ForEach(BorderPreset.allCases, id: \.self) { preset in
          Button(preset.title) { viewModel?.applyBorderPreset(preset) }
        }
      }
      .disabled(viewModel == nil)

      Menu("Fill") {
        Button("No Fill") { viewModel?.setFillColor(nil) }
        Divider()
        Button("Light Red") { viewModel?.setFillColor(Self.fill(.systemRed, alpha: 0.35)) }
        Button("Light Yellow") { viewModel?.setFillColor(Self.fill(.systemYellow, alpha: 0.45)) }
        Button("Light Green") { viewModel?.setFillColor(Self.fill(.systemGreen, alpha: 0.35)) }
        Button("Light Blue") { viewModel?.setFillColor(Self.fill(.systemBlue, alpha: 0.3)) }
        Button("Light Orange") { viewModel?.setFillColor(Self.fill(.systemOrange, alpha: 0.35)) }
        Button("Light Purple") { viewModel?.setFillColor(Self.fill(.systemPurple, alpha: 0.3)) }
        Button("Light Gray") { viewModel?.setFillColor(Self.fill(.systemGray, alpha: 0.3)) }
        Divider()
        Menu("Alternating Row Colors") {
          Button("Light Blue (with header)") {
            viewModel?.applyAlternatingRowColors(
              bandColor: Self.fill(.systemBlue, alpha: 0.22),
              hasHeader: true
            )
          }
          Button("Light Blue (no header)") {
            viewModel?.applyAlternatingRowColors(
              bandColor: Self.fill(.systemBlue, alpha: 0.22),
              hasHeader: false
            )
          }
          Button("Light Gray (with header)") {
            viewModel?.applyAlternatingRowColors(
              bandColor: Self.fill(.systemGray, alpha: 0.22),
              hasHeader: true
            )
          }
          Button("Light Gray (no header)") {
            viewModel?.applyAlternatingRowColors(
              bandColor: Self.fill(.systemGray, alpha: 0.22),
              hasHeader: false
            )
          }
        }
      }
      .disabled(viewModel == nil)

      Divider()

      Button("Conditional Formatting…") {
        guard let viewModel else { return }
        ConditionalFormattingPresenter.present(from: viewModel)
      }
      .disabled(viewModel == nil)

      Button("Clear Rules from Selection") {
        guard let viewModel else { return }
        viewModel.clearConditionalFormats(intersecting: viewModel.selectionRange)
      }
      .disabled(viewModel == nil || viewModel?.activeSheet.conditionalFormats.isEmpty == true)
    }
  }

  private static func fill(_ color: NSColor, alpha: CGFloat) -> CodableColor {
    CellFormatRenderer.codableColor(from: color.withAlphaComponent(alpha))
  }
}
