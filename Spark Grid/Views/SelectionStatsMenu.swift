import SparkGridCore
import SwiftUI

/// Bottom right of the window: the sum of the selected numbers, or the statistic picked from
/// its menu, which lists every one of them.
struct SelectionStatsMenu: View {
  var viewModel: SpreadsheetViewModel
  @AppStorage("selectionStat") private var chosen = SpreadsheetViewModel.SelectionStat.sum.rawValue

  var body: some View {
    if let stats = viewModel.selectionStats, stats.count > 0 {
      let stat = SpreadsheetViewModel.SelectionStat(rawValue: chosen) ?? .sum
      let shown = statLine(stat, stats) ?? statLine(.count, stats) ?? ""
      Menu {
        ForEach(SpreadsheetViewModel.SelectionStat.allCases) { item in
          if let line = statLine(item, stats) {
            Button {
              chosen = item.rawValue
            } label: {
              if item == stat {
                Label(line, systemImage: "checkmark")
              } else {
                Text(line)
              }
            }
          }
        }
      } label: {
        Text(shown)
          .font(.system(size: 11))
          .monospacedDigit()
      }
      .menuStyle(.borderlessButton)
      .fixedSize()
      .padding(.horizontal, 10)
      .help("Statistics for the selected cells")
    }
  }

  private func statLine(
    _ stat: SpreadsheetViewModel.SelectionStat, _ stats: SpreadsheetViewModel.SelectionStats
  ) -> String? {
    viewModel.selectionStatText(stat, in: stats).map { "\(stat.title): \($0)" }
  }
}
