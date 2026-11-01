import AppKit
import SparkGridCore
import SwiftUI

private enum AppMetadata {
  static var versionString: String {
    let info = Bundle.main.infoDictionary
    let version = info?["CFBundleShortVersionString"] as? String ?? "—"
    let build = info?["CFBundleVersion"] as? String ?? "—"
    if build.isEmpty || build == version {
      return "Version \(version)"
    }
    return "Version \(version) (\(build))"
  }

  static var copyrightString: String {
    Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String ?? ""
  }

  static var appIcon: NSImage? {
    if let icon = NSApplication.shared.applicationIconImage, icon.size.width > 0 {
      return icon
    }
    return NSImage(named: NSImage.applicationIconName)
  }
}

struct AboutView: View {
  var onClose: () -> Void

  /// Matches the website's cards.
  private let cornerRadius: CGFloat = 14

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Spacer()
        Button(action: onClose) {
          Image(systemName: "xmark")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .help("Close")
      }
      .padding(.bottom, 6)

      VStack(spacing: 16) {
        appIconView

        Text("Spark Grid")
          .font(.sparkDisplay(size: 30))
          .tracking(-1.2)
          .foregroundStyle(SparkStyle.label)

        Text(AppMetadata.versionString)
          .font(.sparkBody(size: 13, weight: 500))
          .foregroundStyle(SparkStyle.secondaryLabel)

        if !AppMetadata.copyrightString.isEmpty {
          Text(AppMetadata.copyrightString)
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
        }

        Text("A native spreadsheet for opening, editing, and saving Excel workbooks and CSV files.")
          .font(.sparkBody(size: 12))
          .foregroundStyle(SparkStyle.secondaryLabel)
          .multilineTextAlignment(.center)
          .lineSpacing(2)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.horizontal, 4)

        Button(action: LegalLinks.openFeedback) {
          Label("Email support", systemImage: "envelope")
            .font(.sparkBody(size: 12, weight: 500))
            .foregroundStyle(SparkStyle.accent)
        }
        .buttonStyle(.plain)

        Button(action: LegalLinks.openSupport) {
          Label("Support page", systemImage: "questionmark.circle")
            .font(.sparkBody(size: 12, weight: 500))
            .foregroundStyle(SparkStyle.accent)
        }
        .buttonStyle(.plain)

        Button(action: LegalLinks.openTermsOfUse) {
          Label("Terms of Use & licenses", systemImage: "doc.text")
            .font(.sparkBody(size: 12, weight: 500))
            .foregroundStyle(SparkStyle.accent)
        }
        .buttonStyle(.plain)

        Button(action: LegalLinks.openPrivacy) {
          Label("Privacy Policy", systemImage: "hand.raised")
            .font(.sparkBody(size: 12, weight: 500))
            .foregroundStyle(SparkStyle.accent)
        }
        .buttonStyle(.plain)

        Text(
          "Uses ZIPFoundation and CoreXLSX (open-source licenses). "
            + "Set in Bricolage Grotesque and Figtree (SIL Open Font License)."
        )
        .font(.sparkBody(size: 10))
        .foregroundStyle(SparkStyle.secondaryLabel)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 2)

        Text("Built by Sam Parker")
          .font(.sparkBody(size: 12))
          .foregroundStyle(SparkStyle.secondaryLabel)
          .padding(.top, 4)

        Button(action: LegalLinks.openSparkSuite) {
          Text("Part of the Spark Suite")
            .font(.sparkBody(size: 10, weight: 500))
            .foregroundStyle(SparkStyle.accent)
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
      }
      .frame(maxWidth: .infinity)
    }
    .padding(22)
    .frame(width: 300)
    .background {
      RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .fill(SparkStyle.chrome)
        .shadow(color: .black.opacity(0.35), radius: 20, y: 8)
    }
    .overlay(
      RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .strokeBorder(SparkStyle.separator, lineWidth: 1)
    )
    .onExitCommand(perform: onClose)
  }

  @ViewBuilder
  private var appIconView: some View {
    if let icon = AppMetadata.appIcon {
      Image(nsImage: icon)
        .resizable()
        .interpolation(.high)
        .aspectRatio(contentMode: .fit)
        .frame(width: 88, height: 88)
        .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
    }
  }
}

struct AboutPanelOverlay: ViewModifier {
  @Binding var isPresented: Bool

  func body(content: Content) -> some View {
    ZStack {
      content

      if isPresented {
        Color.black.opacity(0.45)
          .contentShape(Rectangle())
          .onTapGesture {
            isPresented = false
          }

        AboutView {
          isPresented = false
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
      }
    }
    .animation(.easeOut(duration: 0.18), value: isPresented)
  }
}

extension View {
  func aboutPanel(isPresented: Binding<Bool>) -> some View {
    modifier(AboutPanelOverlay(isPresented: isPresented))
  }
}

#Preview {
  AboutView(onClose: {})
    .padding()
    .background(Color.black.opacity(0.5))
}
