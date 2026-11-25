import SparkGridCore
import SwiftUI

/// The note a file gets when its formulas call functions Spark Grid can't calculate: each
/// function with how many cells use it and a way to go to the first, what that means for those
/// cells, and a copy of the file as it is (a Reddit comment, Nov 20).
struct UncalculatedFormulasSheet: View {
  enum FileKind {
    /// An .xlsx: the results saved in it show, and its formulas are written back.
    case saved
    /// Opened from another format (.ods, Numbers): saving makes a new file.
    case imported
    /// CSV and other text: no saved results, so the cells show #NAME?.
    case plainText
  }

  let uses: [UnknownFunctions.Use]
  let fileName: String
  let showsSheetNames: Bool
  let kind: FileKind
  let onShow: (UnknownFunctions.Use) -> Void
  let onSaveCopy: () -> Void
  let onDone: (Bool) -> Void

  @State private var dontTellAgain = false

  private static let shownLimit = 6

  var body: some View {
    SparkDialog(
      title: uses.count == 1
        ? "A function Spark Grid can't calculate" : "Functions Spark Grid can't calculate",
      subtitle: fileName,
      primaryTitle: "OK",
      cancelTitle: nil,
      onCancel: { onDone(dontTellAgain) },
      onPrimary: { onDone(dontTellAgain) },
      leading: {
        if kind != .imported {
          Button("Save a Copy…", action: onSaveCopy)
        }
      },
      content: {
        SparkDialogGroup {
          ForEach(Array(uses.prefix(Self.shownLimit).enumerated()), id: \.offset) { index, use in
            if index > 0 { SparkDialogDivider() }
            row(use)
          }
          if uses.count > Self.shownLimit {
            SparkDialogDivider()
            SparkDialogRow(label: "and \(uses.count - Self.shownLimit) more") { EmptyView() }
          }
        }
        Text(explanation)
          .font(.system(size: 12))
          .foregroundStyle(SparkStyle.secondaryLabel)
          .fixedSize(horizontal: false, vertical: true)
        Toggle("Don't tell me about this again", isOn: $dontTellAgain)
          .toggleStyle(.checkbox)
          .font(.system(size: 12))
      }
    )
  }

  private func row(_ use: UnknownFunctions.Use) -> some View {
    SparkDialogRow(label: use.name) {
      Text(place(of: use))
        .font(.system(size: 12))
        .foregroundStyle(SparkStyle.secondaryLabel)
      Button("Show") { onShow(use) }
        .controlSize(.small)
    }
  }

  private func place(of use: UnknownFunctions.Use) -> String {
    let cells = use.cells == 1 ? "1 cell" : "\(use.cells) cells"
    let place = showsSheetNames ? "\(use.sheet)!\(use.address.a1)" : use.address.a1
    return use.cells == 1 ? "\(cells), \(place)" : "\(cells), first \(place)"
  }

  private var explanation: String {
    switch kind {
    case .saved:
      return "These cells show the results saved in the file. They don't update when the cells "
        + "they use change, and neither do formulas that use them. Saving keeps their formulas, "
        + "so the app that made the file calculates them again. To be safe, you can save a copy "
        + "of the file as it is now."
    case .imported:
      return "These cells show the results saved in the file. They don't update when the cells "
        + "they use change, and neither do formulas that use them. The original file isn't "
        + "changed: saving makes a new one."
    case .plainText:
      return "This file keeps formulas as text and no results, so these cells show #NAME?, and "
        + "so do formulas that use them. Saving keeps the formulas as they are. To be safe, you "
        + "can save a copy of the file as it is now."
    }
  }
}
