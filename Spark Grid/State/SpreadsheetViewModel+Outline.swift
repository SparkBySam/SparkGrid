import Foundation
import SparkGridCore

/// Sheet ▸ Group and Ungroup for rows and columns, and folding a group from the +/− button in the
/// header just past it. Levels and hidden rows are the file's own outline, so a save keeps them.
extension SpreadsheetViewModel {
  /// One group: a run of rows or columns at `level` or deeper. Its button sits on `summary`,
  /// the row below or the column to the right, as other spreadsheet apps place it.
  struct OutlineGroup: Equatable {
    var start: Int
    var end: Int
    var level: Int
    var summary: Int { end + 1 }
  }

  static let maxOutlineLevel = 7

  private func outlineLevels(_ axis: HideAxis) -> [Int: Int] {
    axis == .rows
      ? activeSheet.fileExtras.rowOutlineLevels : activeSheet.fileExtras.columnOutlineLevels
  }

  private func hiddenSet(_ axis: HideAxis) -> Set<Int> {
    axis == .rows ? activeSheet.fileExtras.hiddenRows : activeSheet.fileExtras.hiddenColumns
  }

  /// Every group, outermost first.
  func outlineGroups(_ axis: HideAxis) -> [OutlineGroup] {
    let levels = outlineLevels(axis)
    guard !levels.isEmpty else { return [] }
    let indexes = levels.keys.sorted()
    var groups: [OutlineGroup] = []
    for level in 1...Self.maxOutlineLevel {
      var start: Int?
      var previous = -2
      for index in indexes where (levels[index] ?? 0) >= level {
        if let s = start, index != previous + 1 {
          groups.append(OutlineGroup(start: s, end: previous, level: level))
          start = index
        } else if start == nil {
          start = index
        }
        previous = index
      }
      if let s = start { groups.append(OutlineGroup(start: s, end: previous, level: level)) }
    }
    return groups
  }

  /// The innermost group whose button is on `index`, keyed by that index.
  func outlineButtons(_ axis: HideAxis) -> [Int: OutlineGroup] {
    var buttons: [Int: OutlineGroup] = [:]
    for group in outlineGroups(axis) {
      if let existing = buttons[group.summary], existing.level > group.level { continue }
      buttons[group.summary] = group
    }
    return buttons
  }

  func isOutlineGroupCollapsed(_ group: OutlineGroup, _ axis: HideAxis) -> Bool {
    let hidden = hiddenSet(axis)
    guard !hidden.isEmpty else { return false }
    return (group.start...group.end).allSatisfy { hidden.contains($0) }
  }

  /// The deepest group level on an axis; 0 with no groups.
  func outlineDepth(_ axis: HideAxis) -> Int {
    outlineLevels(axis).values.max() ?? 0
  }

  /// Level button `level`, as other apps number them: 1 shows only the outermost rows,
  /// the highest shows everything.
  func showOutlineLevelButton(_ level: Int, _ axis: HideAxis) {
    let depth = outlineDepth(axis)
    guard depth > 0 else { return }
    showOutlineLevel(level > depth ? nil : level - 1, axis)
  }

  var hasOutline: (rows: Bool, columns: Bool) {
    (
      !activeSheet.fileExtras.rowOutlineLevels.isEmpty,
      !activeSheet.fileExtras.columnOutlineLevels.isEmpty
    )
  }

  private func selectedOutlineRange(_ axis: HideAxis) -> ClosedRange<Int>? {
    let n = selectionRange.normalized
    let low = axis == .rows ? n.minRow : n.minCol
    let high = axis == .rows ? n.maxRow : n.maxCol
    guard high >= low, high - low < 100_000 else { return nil }
    return low...high
  }

  /// Rows when whole rows or plain cells are selected, columns when whole columns are.
  var outlineAxisForSelection: HideAxis {
    selectionAxis == .column ? .columns : .rows
  }

  /// Puts the selected rows or columns one level deeper.
  func groupSelection(_ axis: HideAxis) {
    guard protectionAllows([], structural: true) else { return }
    guard let span = selectedOutlineRange(axis) else { return }
    let levels = outlineLevels(axis)
    guard span.contains(where: { (levels[$0] ?? 0) < Self.maxOutlineLevel }) else { return }
    updateFileExtras(actionName: axis == .rows ? "Group Rows" : "Group Columns") { extras in
      for index in span {
        if axis == .rows {
          extras.rowOutlineLevels[index] = min((levels[index] ?? 0) + 1, Self.maxOutlineLevel)
        } else {
          extras.columnOutlineLevels[index] = min((levels[index] ?? 0) + 1, Self.maxOutlineLevel)
        }
      }
    }
  }

  /// Takes the selected rows or columns one level out. Rows that leave every group show again.
  func ungroupSelection(_ axis: HideAxis) {
    guard protectionAllows([], structural: true) else { return }
    guard let span = selectedOutlineRange(axis) else { return }
    let levels = outlineLevels(axis)
    guard span.contains(where: { levels[$0] != nil }) else { return }
    updateFileExtras(actionName: axis == .rows ? "Ungroup Rows" : "Ungroup Columns") { extras in
      for index in span {
        guard let level = levels[index] else { continue }
        let next = level > 1 ? level - 1 : nil
        if axis == .rows {
          extras.rowOutlineLevels[index] = next
          if next == nil { extras.hiddenRows.remove(index) }
        } else {
          extras.columnOutlineLevels[index] = next
          if next == nil { extras.hiddenColumns.remove(index) }
        }
      }
      // A button whose group is gone no longer marks a fold.
      if axis == .rows {
        extras.collapsedRows = extras.collapsedRows.filter {
          extras.rowOutlineLevels[$0 - 1] != nil
        }
      } else {
        extras.collapsedColumns = extras.collapsedColumns.filter {
          extras.columnOutlineLevels[$0 - 1] != nil
        }
      }
    }
  }

  /// Folds or unfolds one group. Unfolding keeps groups inside it that were folded on their own.
  func toggleOutlineGroup(_ group: OutlineGroup, _ axis: HideAxis) {
    let collapse = !isOutlineGroupCollapsed(group, axis)
    let nestedFolded = collapse ? [] : foldedGroups(inside: group, axis)
    updateFileExtras(actionName: collapse ? "Collapse Group" : "Expand Group") { extras in
      var hidden = axis == .rows ? extras.hiddenRows : extras.hiddenColumns
      var collapsed = axis == .rows ? extras.collapsedRows : extras.collapsedColumns
      if collapse {
        hidden.formUnion(group.start...group.end)
        collapsed.insert(group.summary)
      } else {
        hidden.subtract(group.start...group.end)
        for inner in nestedFolded { hidden.formUnion(inner.start...inner.end) }
        collapsed.remove(group.summary)
      }
      if axis == .rows {
        extras.hiddenRows = hidden
        extras.collapsedRows = collapsed
      } else {
        extras.hiddenColumns = hidden
        extras.collapsedColumns = collapsed
      }
    }
  }

  private func foldedGroups(inside group: OutlineGroup, _ axis: HideAxis) -> [OutlineGroup] {
    let collapsed =
      axis == .rows
      ? activeSheet.fileExtras.collapsedRows : activeSheet.fileExtras.collapsedColumns
    return outlineGroups(axis).filter {
      $0.level > group.level && $0.start >= group.start && $0.end <= group.end
        && $0.summary <= group.end && collapsed.contains($0.summary)
        && isOutlineGroupCollapsed($0, axis)
    }
  }

  /// Folds or unfolds the group at the selection: the innermost one holding the active cell, or
  /// whose button is on it.
  func toggleOutlineGroupAtSelection(_ axis: HideAxis) {
    let index = axis == .rows ? selectionAnchor.row : selectionAnchor.col
    let groups = outlineGroups(axis).filter {
      ($0.start...$0.summary).contains(index)
    }
    guard let group = groups.max(by: { $0.level < $1.level }) else { return }
    toggleOutlineGroup(group, axis)
  }

  /// Shows every grouped row or column (`level` nil), or folds everything deeper than `level`.
  func showOutlineLevel(_ level: Int?, _ axis: HideAxis) {
    let levels = outlineLevels(axis)
    guard !levels.isEmpty else { return }
    let groups = outlineGroups(axis)
    updateFileExtras(actionName: level == nil ? "Expand All Groups" : "Collapse Groups") {
      extras in
      var hidden = axis == .rows ? extras.hiddenRows : extras.hiddenColumns
      var collapsed = Set<Int>()
      for (index, depth) in levels {
        if let level, depth > level {
          hidden.insert(index)
        } else {
          hidden.remove(index)
        }
      }
      if let level {
        for group in groups where group.level == level + 1 { collapsed.insert(group.summary) }
      }
      if axis == .rows {
        extras.hiddenRows = hidden
        extras.collapsedRows = collapsed
      } else {
        extras.hiddenColumns = hidden
        extras.collapsedColumns = collapsed
      }
    }
  }
}
