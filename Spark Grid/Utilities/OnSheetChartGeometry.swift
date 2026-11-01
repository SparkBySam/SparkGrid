import CoreGraphics
import SparkGridCore

/// Cell-anchored frame for a chart drawn on the sheet grid.
enum OnSheetChartGeometry {
  /// Height for a view that runs from `top` to `bottom`.
  /// `bottom - top` is negative when those edges are reversed (a scrolled or
  /// frozen row, or a row span that adds up below zero). SwiftUI traps on
  /// that value ("Invalid view geometry: height is negative"), so callers
  /// must skip the view instead of passing it through.
  static func placedHeight(top: CGFloat, bottom: CGFloat) -> CGFloat? {
    let height = bottom - top
    guard height.isFinite, height >= 1 else { return nil }
    return height
  }

  static func frame(
    anchorRow: Int,
    anchorCol: Int,
    rowSpan: Int,
    colSpan: Int,
    rowCount: Int,
    columnCount: Int,
    originXOffset: CGFloat = 0,
    originYOffset: CGFloat = 0,
    endXOffset: CGFloat = 0,
    endYOffset: CGFloat = 0,
    xForColumn: (Int) -> CGFloat,
    yForRow: (Int) -> CGFloat,
    columnWidth: (Int) -> CGFloat,
    rowHeight: (Int) -> CGFloat
  ) -> CGRect {
    guard rowCount > 0, columnCount > 0, rowSpan > 0, colSpan > 0 else { return .zero }
    let row = min(max(0, anchorRow), rowCount - 1)
    let col = min(max(0, anchorCol), columnCount - 1)
    let rowEnd = min(rowCount, row + rowSpan)
    let colEnd = min(columnCount, col + colSpan)
    guard rowEnd > row, colEnd > col else { return .zero }
    var width: CGFloat = 0
    for column in col..<colEnd {
      width += columnWidth(column)
    }
    let top = yForRow(row)
    var cellHeight: CGFloat = 0
    for rowIndex in row..<rowEnd {
      cellHeight += rowHeight(rowIndex)
    }
    // Offsets are distances from the cell borders. Zero keeps the edge on the
    // border, so a snapped chart is the same rectangle as before.
    // End offsets sit past the spanned cells, including past the last cell
    // when a free-placed chart hangs off the sheet. Zero adds nothing, so a
    // snapped span that runs past the used range still clips to those cells.
    width += endXOffset
    width -= originXOffset
    var height = cellHeight
    height += endYOffset
    height -= originYOffset
    let y = top + originYOffset
    guard width.isFinite, width >= 1, let placed = placedHeight(top: y, bottom: y + height) else {
      return .zero
    }
    return CGRect(x: xForColumn(col) + originXOffset, y: y, width: width, height: placed)
  }

  /// Chart frame inside a layer that uses the grid's flipped viewport.
  /// `chartRect` is already in viewport coordinates: `yForRow` has applied
  /// scroll once. Subtract only the layer origin. A second scroll shift
  /// would slide the chart with the gesture instead of with its cells.
  static func hostFrame(chartRect: CGRect, layerFrame: CGRect) -> CGRect {
    CGRect(
      x: chartRect.minX - layerFrame.minX,
      y: chartRect.minY - layerFrame.minY,
      width: chartRect.width,
      height: chartRect.height
    )
  }

  /// Viewport rectangles where frozen rows and columns cover a scrolling chart.
  /// The top rect is the frozen header, full content width, including the
  /// corner. The left rect is frozen columns below that header. The chart
  /// keeps the frame from its anchor cells; these rects are only the cover.
  static func frozenPaneCoverRects(
    contentRect: CGRect,
    frozenColumnBoundaryX: CGFloat,
    frozenRowBoundaryY: CGFloat,
    frozenColumns: Int,
    frozenRows: Int
  ) -> [CGRect] {
    guard contentRect.width > 0, contentRect.height > 0 else { return [] }
    guard frozenColumns > 0 || frozenRows > 0 else { return [] }
    var rects: [CGRect] = []
    if frozenRows > 0 {
      let height = min(contentRect.height, max(0, frozenRowBoundaryY - contentRect.minY))
      if height > 0 {
        rects.append(
          CGRect(
            x: contentRect.minX,
            y: contentRect.minY,
            width: contentRect.width,
            height: height
          ))
      }
    }
    if frozenColumns > 0 {
      let width = min(contentRect.width, max(0, frozenColumnBoundaryX - contentRect.minX))
      let y =
        frozenRows > 0
        ? min(contentRect.maxY, max(contentRect.minY, frozenRowBoundaryY))
        : contentRect.minY
      let height = contentRect.maxY - y
      if width > 0, height > 0 {
        rects.append(CGRect(x: contentRect.minX, y: y, width: width, height: height))
      }
    }
    return rects
  }

  /// True when `point` is in a frozen row or frozen column, including the
  /// divider on the boundary. Header bands outside `contentRect` are not panes.
  static func frozenPaneCovers(
    _ point: CGPoint,
    contentRect: CGRect,
    frozenColumnBoundaryX: CGFloat,
    frozenRowBoundaryY: CGFloat,
    frozenColumns: Int,
    frozenRows: Int
  ) -> Bool {
    guard frozenColumns > 0 || frozenRows > 0 else { return false }
    guard point.x >= contentRect.minX, point.x < contentRect.maxX,
      point.y >= contentRect.minY, point.y < contentRect.maxY
    else { return false }
    if frozenRows > 0, point.y <= frozenRowBoundaryY { return true }
    if frozenColumns > 0, point.x <= frozenColumnBoundaryX { return true }
    return false
  }

  /// Edge or corner of a selected chart. `body` is the interior, used to move it.
  enum ChartFrameHandle: Equatable {
    case body
    case left, right, top, bottom
    case topLeft, topRight, bottomLeft, bottomRight
  }

  struct ChartFrameAnchor: Equatable {
    var anchorRow: Int
    var anchorCol: Int
    var rowSpan: Int
    var colSpan: Int
    /// Points from the left edge of `anchorCol`. Zero sits on that border.
    var originXOffset: CGFloat
    /// Points from the top edge of `anchorRow`. Zero sits on that border.
    var originYOffset: CGFloat
    /// Points past the right edge of the spanned columns.
    var endXOffset: CGFloat
    /// Points past the bottom edge of the spanned rows.
    var endYOffset: CGFloat

    init(
      anchorRow: Int,
      anchorCol: Int,
      rowSpan: Int,
      colSpan: Int,
      originXOffset: CGFloat = 0,
      originYOffset: CGFloat = 0,
      endXOffset: CGFloat = 0,
      endYOffset: CGFloat = 0
    ) {
      self.anchorRow = anchorRow
      self.anchorCol = anchorCol
      self.rowSpan = rowSpan
      self.colSpan = colSpan
      self.originXOffset = originXOffset
      self.originYOffset = originYOffset
      self.endXOffset = endXOffset
      self.endYOffset = endYOffset
    }
  }

  /// Which handle `point` lands on. Nil when it misses the frame, including the
  /// thin band just outside the border where a corner handle still counts.
  static func frameHandle(at point: CGPoint, in rect: CGRect, thickness: CGFloat)
    -> ChartFrameHandle?
  {
    guard rect.width >= 1, rect.height >= 1, thickness > 0 else { return nil }
    let hit = rect.insetBy(dx: -thickness / 2, dy: -thickness / 2)
    guard hit.contains(point) else { return nil }
    let nearLeft = abs(point.x - rect.minX) <= thickness
    let nearRight = abs(point.x - rect.maxX) <= thickness
    let nearTop = abs(point.y - rect.minY) <= thickness
    let nearBottom = abs(point.y - rect.maxY) <= thickness
    if nearTop && nearLeft { return .topLeft }
    if nearTop && nearRight { return .topRight }
    if nearBottom && nearLeft { return .bottomLeft }
    if nearBottom && nearRight { return .bottomRight }
    if nearLeft { return .left }
    if nearRight { return .right }
    if nearTop { return .top }
    if nearBottom { return .bottom }
    return rect.contains(point) ? .body : nil
  }

  /// New cell anchor after dragging `handle` by `translation`.
  /// Move keeps the span. Resize moves one edge, or both for a corner, and
  /// never shrinks below `minimumSpan`. Indexes come from the same column/row
  /// lookup the grid uses, so variable column widths still snap on cell borders.
  ///
  /// `freePlacement` leaves every dragged edge on the pointer instead of a
  /// cell border. The result is still a cell anchor plus offsets, so the chart
  /// scrolls with those cells. Positive `translation.height` moves a chart
  /// down, the same direction as a snapped drag.
  static func anchorAfterDrag(
    start: ChartFrameAnchor,
    handle: ChartFrameHandle,
    startRect: CGRect,
    translation: CGSize,
    minimumSpan: Int,
    rowLimit: Int,
    columnLimit: Int,
    columnAt: (CGFloat) -> Int,
    rowAt: (CGFloat) -> Int,
    freePlacement: Bool = false,
    xForColumn: ((Int) -> CGFloat)? = nil,
    yForRow: ((Int) -> CGFloat)? = nil,
    columnWidth: ((Int) -> CGFloat)? = nil,
    rowHeight: ((Int) -> CGFloat)? = nil
  ) -> ChartFrameAnchor {
    if freePlacement,
      let xForColumn,
      let yForRow,
      let columnWidth,
      let rowHeight
    {
      return anchorAfterFreeDrag(
        handle: handle,
        startRect: startRect,
        translation: translation,
        minimumSpan: minimumSpan,
        rowLimit: rowLimit,
        columnLimit: columnLimit,
        columnAt: columnAt,
        rowAt: rowAt,
        xForColumn: xForColumn,
        yForRow: yForRow,
        columnWidth: columnWidth,
        rowHeight: rowHeight
      )
    }
    let span = max(1, minimumSpan)
    if handle == .body {
      let originCol = columnAt(startRect.minX)
      let originRow = rowAt(startRect.minY)
      let nextCol = columnAt(startRect.minX + translation.width)
      let nextRow = rowAt(startRect.minY + translation.height)
      return ChartFrameAnchor(
        anchorRow: clampIndex(start.anchorRow + (nextRow - originRow), count: rowLimit),
        anchorCol: clampIndex(start.anchorCol + (nextCol - originCol), count: columnLimit),
        rowSpan: start.rowSpan,
        colSpan: start.colSpan
      )
    }

    var anchorCol = start.anchorCol
    var anchorRow = start.anchorRow
    var colSpan = start.colSpan
    var rowSpan = start.rowSpan
    let endCol = start.anchorCol + start.colSpan - 1
    let endRow = start.anchorRow + start.rowSpan - 1

    switch handle {
    case .left, .topLeft, .bottomLeft:
      let origin = columnAt(startRect.minX)
      let next = columnAt(startRect.minX + translation.width)
      let proposed = start.anchorCol + (next - origin)
      let maxAnchor = endCol - span + 1
      anchorCol = min(max(0, proposed), max(0, maxAnchor))
      colSpan = endCol - anchorCol + 1
    case .right, .topRight, .bottomRight:
      let edge = max(startRect.minX, startRect.maxX - 1)
      let origin = columnAt(edge)
      let next = columnAt(edge + translation.width)
      let proposedEnd = endCol + (next - origin)
      let minEnd = start.anchorCol + span - 1
      colSpan = max(minEnd, proposedEnd) - start.anchorCol + 1
    case .body, .top, .bottom:
      break
    }

    switch handle {
    case .top, .topLeft, .topRight:
      let origin = rowAt(startRect.minY)
      let next = rowAt(startRect.minY + translation.height)
      let proposed = start.anchorRow + (next - origin)
      let maxAnchor = endRow - span + 1
      anchorRow = min(max(0, proposed), max(0, maxAnchor))
      rowSpan = endRow - anchorRow + 1
    case .bottom, .bottomLeft, .bottomRight:
      let edge = max(startRect.minY, startRect.maxY - 1)
      let origin = rowAt(edge)
      let next = rowAt(edge + translation.height)
      let proposedEnd = endRow + (next - origin)
      let minEnd = start.anchorRow + span - 1
      rowSpan = max(minEnd, proposedEnd) - start.anchorRow + 1
    case .body, .left, .right:
      break
    }

    return ChartFrameAnchor(
      anchorRow: anchorRow,
      anchorCol: anchorCol,
      rowSpan: max(span, rowSpan),
      colSpan: max(span, colSpan)
    )
  }

  /// Pointer-following anchor. Edges keep the pixel delta and only change
  /// cell when they cross into the next one; the remainder is the offset.
  /// Size still cannot shrink below `minimumSpan` cells, and the origin
  /// cannot leave the sheet.
  private static func anchorAfterFreeDrag(
    handle: ChartFrameHandle,
    startRect: CGRect,
    translation: CGSize,
    minimumSpan: Int,
    rowLimit: Int,
    columnLimit: Int,
    columnAt: (CGFloat) -> Int,
    rowAt: (CGFloat) -> Int,
    xForColumn: (Int) -> CGFloat,
    yForRow: (Int) -> CGFloat,
    columnWidth: (Int) -> CGFloat,
    rowHeight: (Int) -> CGFloat
  ) -> ChartFrameAnchor {
    let span = max(1, minimumSpan)
    guard columnLimit > 0, rowLimit > 0, startRect.width >= 1, startRect.height >= 1 else {
      return ChartFrameAnchor(anchorRow: 0, anchorCol: 0, rowSpan: span, colSpan: span)
    }
    var rect = startRect
    if handle == .body {
      rect.origin.x += translation.width
      rect.origin.y += translation.height
      let minX = xForColumn(0)
      let maxX = xForColumn(max(0, columnLimit - 1))
      let minY = yForRow(0)
      let maxY = yForRow(max(0, rowLimit - 1))
      rect.origin.x = min(max(rect.origin.x, minX), maxX)
      rect.origin.y = min(max(rect.origin.y, minY), maxY)
    } else {
      let movesLeft = handle == .left || handle == .topLeft || handle == .bottomLeft
      let movesRight = handle == .right || handle == .topRight || handle == .bottomRight
      let movesTop = handle == .top || handle == .topLeft || handle == .topRight
      let movesBottom = handle == .bottom || handle == .bottomLeft || handle == .bottomRight
      if movesLeft || movesRight {
        let minWidth = minimumExtent(
          fixedEdge: movesLeft ? startRect.maxX : startRect.minX,
          fromStart: !movesLeft,
          span: span,
          limit: columnLimit,
          indexAt: columnAt,
          originAt: xForColumn,
          sizeAt: columnWidth
        )
        if movesLeft {
          let minLeft = xForColumn(0)
          let maxLeft = startRect.maxX - minWidth
          var left = startRect.minX + translation.width
          if maxLeft >= minLeft {
            left = min(max(left, minLeft), maxLeft)
          } else {
            left = min(max(left, minLeft), startRect.maxX - 1)
          }
          rect.origin.x = left
          rect.size.width = max(1, startRect.maxX - left)
        } else {
          let maxRight = xForColumn(columnLimit)
          let minRight = startRect.minX + minWidth
          var right = startRect.maxX + translation.width
          let lower = min(minRight, maxRight)
          right = min(max(right, lower), maxRight)
          right = max(right, startRect.minX + 1)
          rect.size.width = right - startRect.minX
        }
      }
      if movesTop || movesBottom {
        let minHeight = minimumExtent(
          fixedEdge: movesTop ? startRect.maxY : startRect.minY,
          fromStart: !movesTop,
          span: span,
          limit: rowLimit,
          indexAt: rowAt,
          originAt: yForRow,
          sizeAt: rowHeight
        )
        if movesTop {
          let minTop = yForRow(0)
          let maxTop = startRect.maxY - minHeight
          var top = startRect.minY + translation.height
          if maxTop >= minTop {
            top = min(max(top, minTop), maxTop)
          } else {
            top = min(max(top, minTop), startRect.maxY - 1)
          }
          rect.origin.y = top
          rect.size.height = max(1, startRect.maxY - top)
        } else {
          let maxBottom = yForRow(rowLimit)
          let minBottom = startRect.minY + minHeight
          var bottom = startRect.maxY + translation.height
          let lower = min(minBottom, maxBottom)
          bottom = min(max(bottom, lower), maxBottom)
          bottom = max(bottom, startRect.minY + 1)
          rect.size.height = bottom - startRect.minY
        }
      }
    }

    let left = splitEdge(
      position: rect.minX,
      indexAt: columnAt,
      originAt: xForColumn,
      sizeAt: columnWidth,
      limit: columnLimit
    )
    let right = splitEdge(
      position: rect.maxX,
      indexAt: columnAt,
      originAt: xForColumn,
      sizeAt: columnWidth,
      limit: columnLimit
    )
    let top = splitEdge(
      position: rect.minY,
      indexAt: rowAt,
      originAt: yForRow,
      sizeAt: rowHeight,
      limit: rowLimit
    )
    let bottom = splitEdge(
      position: rect.maxY,
      indexAt: rowAt,
      originAt: yForRow,
      sizeAt: rowHeight,
      limit: rowLimit
    )
    let anchorCol = min(max(0, left.index), columnLimit - 1)
    let anchorRow = min(max(0, top.index), rowLimit - 1)
    let endCol = min(max(right.index, anchorCol + 1), columnLimit)
    let endRow = min(max(bottom.index, anchorRow + 1), rowLimit)
    return ChartFrameAnchor(
      anchorRow: anchorRow,
      anchorCol: anchorCol,
      rowSpan: endRow - anchorRow,
      colSpan: endCol - anchorCol,
      originXOffset: left.index == anchorCol ? max(0, left.offset) : 0,
      originYOffset: top.index == anchorRow ? max(0, top.offset) : 0,
      endXOffset: right.index == endCol ? max(0, right.offset) : 0,
      endYOffset: bottom.index == endRow ? max(0, bottom.offset) : 0
    )
  }

  /// Smallest pixel length of `span` cells measured from the fixed edge.
  private static func minimumExtent(
    fixedEdge: CGFloat,
    fromStart: Bool,
    span: Int,
    limit: Int,
    indexAt: (CGFloat) -> Int,
    originAt: (Int) -> CGFloat,
    sizeAt: (Int) -> CGFloat
  ) -> CGFloat {
    let split = splitEdge(
      position: fixedEdge,
      indexAt: indexAt,
      originAt: originAt,
      sizeAt: sizeAt,
      limit: limit
    )
    if fromStart {
      var total: CGFloat = 0
      let start = min(max(0, split.index), max(0, limit - 1))
      for step in 0..<span {
        let index = start + step
        if index >= limit { break }
        total += max(0, sizeAt(index))
      }
      return max(total, 1)
    }
    let base = max(0, split.index - span)
    return max(1, fixedEdge - originAt(base))
  }

  /// Cell index and the point's distance from that cell's origin.
  /// A point past the last cell keeps the leftover distance so the chart
  /// does not shrink when it is released hanging off the sheet.
  private static func splitEdge(
    position: CGFloat,
    indexAt: (CGFloat) -> Int,
    originAt: (Int) -> CGFloat,
    sizeAt: (Int) -> CGFloat,
    limit: Int
  ) -> (index: Int, offset: CGFloat) {
    guard limit > 0, position.isFinite else { return (0, 0) }
    if indexAt(position) >= limit {
      return (limit, 0)
    }
    let index = min(max(0, indexAt(position)), limit - 1)
    let offset = position - originAt(index)
    guard offset.isFinite else { return (index, 0) }
    if offset < 0 {
      return (index, 0)
    }
    let size = sizeAt(index)
    guard size > 0, offset >= size else {
      return (index, offset)
    }
    let next = index + 1
    if next >= limit {
      // Distance past the sheet edge. Dropping it would shrink a chart that
      // was dragged to the last cell and released there.
      let edge = originAt(limit)
      return (limit, max(0, position - edge))
    }
    let nextOrigin = originAt(next)
    let nextSize = max(0, sizeAt(next))
    if position + 0.001 >= nextOrigin, nextSize == 0 || position < nextOrigin + nextSize {
      return (next, max(0, position - nextOrigin))
    }
    return (index, min(offset, size))
  }

  /// Preview height that follows the chart's column and row span.
  /// A wider chart is shorter; a taller chart is taller, inside the clamps.
  static func previewHeight(
    colSpan: Int,
    rowSpan: Int,
    width: CGFloat,
    minHeight: CGFloat = 140,
    maxHeight: CGFloat = 280
  ) -> CGFloat {
    let aspect = (CGFloat(max(1, colSpan)) * 80) / (CGFloat(max(1, rowSpan)) * 22)
    let raw = width / max(aspect, 0.25)
    return min(maxHeight, max(minHeight, raw))
  }

  private static func clampIndex(_ value: Int, count: Int) -> Int {
    guard count > 0 else { return 0 }
    return min(max(0, value), count - 1)
  }
}
