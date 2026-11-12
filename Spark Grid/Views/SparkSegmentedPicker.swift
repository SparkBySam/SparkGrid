import AppKit
import SparkGridCore
import SwiftUI

/// A segmented choice drawn in the app's accent. The system segmented control always uses the
/// macOS accent, so with Spark amber chosen it still showed blue.
struct SparkSegmentedPicker<Value: Hashable>: View {
  @Binding var selection: Value
  let options: [(value: Value, title: String)]
  /// Every segment as wide as the widest, as the system control draws them.
  var equalWidths = false

  @Environment(\.isEnabled) private var isEnabled
  @State private var widest: CGFloat = 0

  init(
    selection: Binding<Value>, options: [(value: Value, title: String)], equalWidths: Bool = false
  ) {
    _selection = selection
    self.options = options
    self.equalWidths = equalWidths
  }

  var body: some View {
    let accent = SparkStyle.accent
    HStack(spacing: 2) {
      ForEach(Array(options.enumerated()), id: \.offset) { index, option in
        let selected = option.value == selection
        Button {
          selection = option.value
        } label: {
          Text(option.title)
            .font(.system(size: 12, weight: selected ? .semibold : .regular))
            .lineLimit(1)
            .fixedSize()
            .background(
              GeometryReader { geo in
                Color.clear.preference(key: SegmentWidthKey.self, value: geo.size.width)
              }
            )
            .frame(minWidth: equalWidths ? widest : nil)
            .padding(.horizontal, 10)
            .frame(height: 20)
            .foregroundStyle(selected ? Self.text(on: accent) : SparkStyle.label)
            .background(
              RoundedRectangle(cornerRadius: 5)
                .fill(selected ? accent : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        if index < options.count - 1 {
          Rectangle()
            .fill(SparkStyle.separator)
            .frame(width: 1, height: 12)
            .opacity(selected || options[index + 1].value == selection ? 0 : 1)
        }
      }
    }
    .padding(2)
    .background(RoundedRectangle(cornerRadius: 7).fill(SparkStyle.field))
    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(SparkStyle.chromeBorder))
    .opacity(isEnabled ? 1 : 0.5)
    .onPreferenceChange(SegmentWidthKey.self) { widest = $0 }
    .accessibilityElement(children: .contain)
  }

  /// Dark text on a light accent such as Spark amber, white on a dark one.
  static func text(on accent: Color) -> Color {
    let ns = NSColor(accent).usingColorSpace(.deviceRGB) ?? .controlAccentColor
    let luminance =
      0.2126 * ns.redComponent + 0.7152 * ns.greenComponent + 0.0722 * ns.blueComponent
    return luminance > 0.55 ? Color.black.opacity(0.85) : .white
  }
}

private struct SegmentWidthKey: PreferenceKey {
  static let defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = max(value, nextValue())
  }
}
