import AppKit
import SparkGridCore
import SwiftUI

struct SheetTabsView: View {
  @Bindable var viewModel: SpreadsheetViewModel
  @State private var sheetToRename: Int?
  @State private var renameText = ""
  /// The tab a dragged tab is hovering over. It takes that tab's place when dropped.
  @State private var dropTargetIndex: Int?

  var body: some View {
    HStack(spacing: 0) {
      Button(action: viewModel.addSheet) {
        Image(systemName: "plus")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(.secondary)
          .frame(width: 24, height: 24)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help("Add sheet")

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 1) {
          ForEach(visibleSheets, id: \.element.id) { index, sheet in
            sheetTab(name: sheet.name, isActive: index == viewModel.workbook.activeSheetIndex) {
              viewModel.selectSheet(at: index)
            }
            .background {
              if dropTargetIndex == index {
                SparkStyle.accent.opacity(0.22)
              }
            }
            .draggable(Self.dragPrefix + sheet.id.uuidString) {
              Text(sheet.name)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            }
            .dropDestination(for: String.self) { items, _ in
              dropTargetIndex = nil
              return moveDraggedSheet(items, to: index)
            } isTargeted: { targeted in
              if targeted {
                dropTargetIndex = index
              } else if dropTargetIndex == index {
                dropTargetIndex = nil
              }
            }
            .contextMenu {
              Button("Rename…") {
                sheetToRename = index
                renameText = sheet.name
              }
              Button("Hide") {
                viewModel.setSheetHidden(true, at: index)
              }
              .disabled(visibleSheets.count <= 1)
              if !hiddenSheets.isEmpty {
                Menu("Unhide") {
                  ForEach(hiddenSheets, id: \.element.id) { hiddenIndex, hidden in
                    Button(hidden.name) {
                      viewModel.setSheetHidden(false, at: hiddenIndex)
                    }
                  }
                }
              }
              Divider()
              Button("Delete", role: .destructive) {
                viewModel.deleteSheet(at: index)
              }
              .disabled(visibleSheets.count <= 1)
            }
          }
        }
      }

      Spacer(minLength: 0)

      if let counts = viewModel.filterRowCounts {
        HStack(spacing: 6) {
          Image(systemName: "line.3.horizontal.decrease")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(SparkStyle.accent)
          Text("Showing \(counts.shown) of \(counts.total) rows")
            .font(.system(size: 11))
            .foregroundStyle(SparkStyle.label)
            .monospacedDigit()
          Button("Clear Filters", action: viewModel.clearAllFilterCriteria)
            .buttonStyle(.link)
            .font(.system(size: 11))
            .tint(SparkStyle.accent)
        }
        .padding(.horizontal, 10)
        .fixedSize()
      }
    }
    .frame(height: 24)
    .background(SparkStyle.window)
    .overlay(alignment: .top) { ChromeDivider() }
    .alert("Rename Sheet", isPresented: renameAlertBinding) {
      TextField("Sheet name", text: $renameText)
      Button("Rename") {
        if let index = sheetToRename {
          viewModel.renameSheet(at: index, to: renameText)
        }
        sheetToRename = nil
      }
      Button("Cancel", role: .cancel) {
        sheetToRename = nil
      }
    }
  }

  /// Tabs shown. A file can hide sheets; those stay out of the tab bar until unhidden.
  private var visibleSheets: [(offset: Int, element: Sheet)] {
    viewModel.workbook.sheets.enumerated().filter { !$0.element.isHidden }
  }

  /// Hidden sheets a person may show again. Sheets the file marks very hidden are not listed.
  private var hiddenSheets: [(offset: Int, element: Sheet)] {
    viewModel.workbook.sheets.enumerated().filter {
      $0.element.fileExtras.visibility == .hidden
    }
  }

  /// Marks a dragged tab, so text dropped from elsewhere is not read as a sheet.
  private static let dragPrefix = "spark-grid-sheet:"

  private func moveDraggedSheet(_ items: [String], to index: Int) -> Bool {
    guard let item = items.first, item.hasPrefix(Self.dragPrefix) else { return false }
    let id = String(item.dropFirst(Self.dragPrefix.count))
    guard
      let source = viewModel.workbook.sheets.firstIndex(where: { $0.id.uuidString == id }),
      source != index
    else { return false }
    viewModel.moveSheet(from: source, to: index)
    return true
  }

  private var renameAlertBinding: Binding<Bool> {
    Binding(
      get: { sheetToRename != nil },
      set: { if !$0 { sheetToRename = nil } }
    )
  }

  private func sheetTab(name: String, isActive: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(name)
        .font(.system(size: 11, weight: isActive ? .semibold : .regular))
        .foregroundStyle(isActive ? SparkStyle.label : SparkStyle.secondaryLabel)
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background {
          if isActive {
            SparkStyle.chrome
          }
        }
        .overlay(alignment: .bottom) {
          Rectangle()
            .fill(isActive ? SparkStyle.accent : Color.clear)
            .frame(height: 2)
        }
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}
