import SwiftUI

/// A small "i" that shows a sentence or two about the thing beside it, in a popover. Used on
/// templates, chart kinds, trendlines, sparkline kinds, alert styles and other choices whose
/// names alone don't say what they do (Sam, Nov 20: "can we get some i's").
struct SparkInfoButton: View {
  let title: String
  let text: String
  var size: CGFloat = 13
  @State private var showing = false

  var body: some View {
    Button {
      showing.toggle()
    } label: {
      Image(systemName: "info.circle")
        .font(.system(size: size))
        .foregroundStyle(showing ? SparkStyle.accent : SparkStyle.secondaryLabel)
    }
    .buttonStyle(.plain)
    .help(text)
    .accessibilityLabel("About \(title)")
    .popover(isPresented: $showing, arrowEdge: .bottom) {
      VStack(alignment: .leading, spacing: 6) {
        Text(title)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(SparkStyle.label)
        Text(text)
          .font(.system(size: 12))
          .foregroundStyle(SparkStyle.secondaryLabel)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(12)
      .frame(width: 260, alignment: .leading)
    }
  }
}
