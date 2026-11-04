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
            sheetTab(
              name: sheet.name, color: sheet.fileExtras.tabColorHex,
              isActive: index == viewModel.workbook.activeSheetIndex
            ) {
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
              Menu("Tab Color") {
                ForEach(Self.tabColors, id: \.hex) { choice in
                  Button {
                    viewModel.setTabColor(choice.hex, at: index)
                  } label: {
                    Label {
                      Text(choice.name)
                    } icon: {
                      Image(nsImage: Self.swatch(choice.hex))
                    }
                  }
                }
                Divider()
                Button("No Color") { viewModel.setTabColor(nil, at: index) }
                  .disabled(sheet.fileExtras.tabColorHex == nil)
              }
              Button("Hide") {
                viewModel.setSheetHidden(true, at: index)
              }
              .disabled(visibleSheets.count <= 1)
              let hiddenSheets = viewModel.unhideableSheets
              if !hiddenSheets.isEmpty {
                Menu("Unhide") {
                  ForEach(hiddenSheets, id: \.index) { hidden in
                    Button(hidden.name) {
                      viewModel.setSheetHidden(false, at: hidden.index)
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

      if let summary = viewModel.duplicateHighlightSummary {
        HStack(spacing: 6) {
          Circle()
            .fill(viewModel.duplicateHighlight?.unique == true ? Color.green : Color.red)
            .frame(width: 7, height: 7)
          Text(summary)
            .font(.system(size: 11))
            .foregroundStyle(SparkStyle.label)
            .monospacedDigit()
          Button {
            viewModel.isDuplicatesSheetPresented = true
          } label: {
            Text("Remove…")
          }
          .buttonStyle(.link)
          .font(.system(size: 11))
          .opacity(viewModel.duplicateHighlight?.unique == true ? 0 : 1)
          Button {
            viewModel.clearDuplicateHighlight()
          } label: {
            Image(systemName: "xmark.circle.fill")
              .foregroundStyle(SparkStyle.secondaryLabel)
          }
          .buttonStyle(.plain)
          .help("Clear the highlight (Esc)")
        }
        .padding(.horizontal, 8)
      }

      SelectionStatsMenu(viewModel: viewModel)

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

  static let tabColors: [(name: String, hex: String)] = [
    ("Red", "E5484D"), ("Orange", "F08A24"), ("Yellow", "F2C94C"), ("Green", "34A853"),
    ("Teal", "14B8A6"), ("Blue", "4472C4"), ("Purple", "8B5CF6"), ("Pink", "EC4899"),
    ("Gray", "8E8E93"),
  ]

  /// A small round chip for the menu. Menus draw images, not SwiftUI shapes.
  static func swatch(_ hex: String) -> NSImage {
    let image = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
      (Self.nsColor(hex) ?? .gray).setFill()
      NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
      return true
    }
    image.isTemplate = false
    return image
  }

  static func nsColor(_ hex: String) -> NSColor? {
    guard hex.count == 6, let value = Int(hex, radix: 16) else { return nil }
    return NSColor(
      srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
      blue: CGFloat(value & 0xFF) / 255, alpha: 1)
  }

  private func sheetTab(
    name: String, color: String?, isActive: Bool, action: @escaping () -> Void
  ) -> some View {
    let tint = color.flatMap(Self.nsColor).map(Color.init(nsColor:))
    return Button(action: action) {
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
        .background {
          // A colored tab is tinted, as other spreadsheet apps show it.
          if let tint, !isActive { tint.opacity(0.18) }
        }
        .overlay(alignment: .bottom) {
          Rectangle()
            .fill(tint ?? (isActive ? SparkStyle.accent : Color.clear))
            .frame(height: isActive ? 3 : 2)
        }
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}
