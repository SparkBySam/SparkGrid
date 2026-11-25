import SparkGridCore
import SwiftUI

/// The alert a data validation rule asks for when an entry breaks it, in the app's dialog
/// layout: Stop refuses the entry, Warning asks whether to keep it, Information tells and keeps
/// it unless Cancel is chosen. The rule's own title and message when it has them.
struct ValidationAlertSheet: View {
  let parts: DataValidationRule.Parts
  let entry: String
  let cell: String
  let onAnswer: (Bool) -> Void

  var body: some View {
    SparkDialog(
      title: title,
      subtitle: "\(shownEntry) in \(cell)",
      primaryTitle: parts.alertStyle == .warning ? "Keep" : "OK",
      cancelTitle: cancelTitle,
      onCancel: { onAnswer(false) },
      onPrimary: { onAnswer(parts.alertStyle != .stop) },
      leading: { EmptyView() },
      content: {
        Label {
          Text(message)
            .font(.system(size: 13))
            .foregroundStyle(SparkStyle.label)
            .fixedSize(horizontal: false, vertical: true)
        } icon: {
          Image(systemName: symbol).foregroundStyle(symbolColor)
        }
      }
    )
  }

  private var title: String {
    if !parts.errorTitle.isEmpty { return parts.errorTitle }
    switch parts.alertStyle {
    case .stop: return "That entry isn't allowed here"
    case .warning: return "Keep this entry?"
    case .information: return "That entry doesn't match the rule"
    }
  }

  private var message: String {
    let rule =
      parts.error.isEmpty
      ? "It doesn't match the rule for this cell (Data › Data Validation)." : parts.error
    switch parts.alertStyle {
    case .stop: return rule
    case .warning: return parts.errorTitle.isEmpty ? rule : rule + " Keep it anyway?"
    case .information: return rule + " It's kept unless you cancel."
    }
  }

  private var cancelTitle: String? {
    switch parts.alertStyle {
    case .stop: return nil
    case .warning: return "Don't Keep"
    case .information: return "Cancel"
    }
  }

  private var symbol: String {
    switch parts.alertStyle {
    case .stop: return "xmark.octagon.fill"
    case .warning: return "exclamationmark.triangle.fill"
    case .information: return "info.circle.fill"
    }
  }

  private var symbolColor: Color {
    switch parts.alertStyle {
    case .stop: return Color(nsColor: .systemRed)
    case .warning: return SparkStyle.accent
    case .information: return SparkStyle.secondaryLabel
    }
  }

  /// The typed text, cut short when long.
  private var shownEntry: String {
    let text = entry.trimmingCharacters(in: .whitespaces)
    return text.count > 30 ? "\u{201C}" + text.prefix(29) + "…\u{201D}" : "\u{201C}\(text)\u{201D}"
  }
}
