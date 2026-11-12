import AppKit
import Darwin
import SparkGridCore
import SwiftUI

/// AppKit spreadsheet grid with sticky row/column headers, selection, editing, and keyboard navigation.
final class SpreadsheetGridNSView: NSView {
  static let baseHeaderSize: CGFloat = 28
  static let headerSize: CGFloat = 28  // unscaled; prefer instance `headerSize` for layout
  static let defaultColumnWidth = Workbook.defaultColumnWidth
  static let defaultRowHeight = Workbook.defaultRowHeight
  /// Theme colors resolved for this view's appearance and accent. See `theme`.
  private var themeCache: (key: SparkTheme.PaletteKey, palette: SparkTheme.Palette)?
  private struct OutlineCacheKey: Equatable {
    var revision: Int
    var sheet: Int
  }
  private var outlineCache:
    (
      key: OutlineCacheKey, rows: [Int: SpreadsheetViewModel.OutlineGroup],
      columns: [Int: SpreadsheetViewModel.OutlineGroup]
    )?

  var viewModel: SpreadsheetViewModel? {
    didSet {
      guard viewModel !== oldValue else { return }
      oldValue?.onGridInvalidation = nil
      viewModel?.onGridInvalidation = { [weak self] invalidation in
        guard let self else { return }
        switch invalidation {
        case .full:
          self.testingInvalidateReason = "full"
          self.reloadContent(resetScrollPosition: false)
        case .cells(let addresses):
          self.testingInvalidateReason = "cells \(addresses.count)"
          self.invalidateDisplayedCells(addresses)
          self.layoutOnSheetCharts()
        case .charts:
          self.layoutOnSheetCharts()
        case .repaint:
          self.testingInvalidateReason = "repaint"
          self.cellPaintCache.removeAll(keepingCapacity: true)
          if self.scrollTilesPresented {
            self.rerenderPresentedTiles()
          } else {
            // Idle scroll pictures were drawn with the old paint.
            self.needsViewportTileWarm = true
            self.discardScrollTiles()
            self.needsDisplay = true
          }
        }
      }
      chartHostSnapshots.removeAll()
      invalidateLayoutCache()
      needsDisplay = true
      if window != nil {
        layoutOnSheetCharts()
      }
    }
  }

  private var zoomScale: CGFloat {
    if let zoom = tileCapture?.session.zoom { return zoom }
    if let drawZoomScale { return drawZoomScale }
    return max(0.5, min(2.0, viewModel?.zoomScale ?? 1))
  }

  /// Zoom-scaled header band size.
  private var headerSize: CGFloat { Self.baseHeaderSize * zoomScale }

  private var scrollOrigin = CGPoint.zero {
    didSet {
      if scrollOrigin != oldValue { flashScrollIndicators() }
    }
  }
  /// Fading scroll bars drawn over the cells.
  private let scrollIndicators = GridScrollIndicatorView(frame: .zero)
  private let commentCard = CommentHoverCard(frame: .zero)
  /// Until when a scroll frame may draw newly visible tiles itself. Past it they wait for a worker.
  private var visibleTileDrawDeadline: CFAbsoluteTime = 0
  /// Main-thread time a scroll frame may spend drawing tiles that just came on screen.
  private static let visibleTileDrawBudget: CFAbsoluteTime = 0.006
  /// The commented cell the pointer is resting on, and the wait before its card shows.
  private var hoveredCommentAddress: CellAddress?
  private var commentHoverTimer: Timer?
  /// Scroll used while a background tile records drawing commands.
  private var activeScrollOrigin: CGPoint { tileCapture?.scroll ?? scrollOrigin }

  private static let tileCaptureSlot: pthread_key_t = {
    var key = pthread_key_t()
    guard pthread_key_create(&key, nil) == 0 else { return 0 }
    return key
  }()

  private var tileCapture: TileCaptureState? {
    guard let raw = pthread_getspecific(Self.tileCaptureSlot) else { return nil }
    return Unmanaged<TileCaptureState>.fromOpaque(raw).takeUnretainedValue()
  }

  private func setTileCapture(_ state: TileCaptureState?) {
    if let state = state {
      pthread_setspecific(
        Self.tileCaptureSlot, Unmanaged.passUnretained(state).toOpaque())
    } else {
      pthread_setspecific(Self.tileCaptureSlot, nil)
    }
  }
  private var cachedColumnOffsets: [CGFloat]?
  private var cachedRowOffsets: [CGFloat]?
  private var cachedColumnCount = 0
  private var cachedRowCount = 0
  private var cachedColumnLayoutRevision = Int.min
  private var cachedColumnLayoutZoom: CGFloat = -.greatestFiniteMagnitude
  private var cachedRowLayoutRevision = Int.min
  private var cachedRowLayoutZoom: CGFloat = -.greatestFiniteMagnitude
  private var cachedWrappedRowHeights: [Int: CGFloat] = [:]
  private var cachedWrappedRevision = Int.min
  private var cachedWrappedZoom: CGFloat = -.greatestFiniteMagnitude
  private struct CellPaintCacheEntry {
    var paint: ConditionalPaint
    var value: CellValue
    var displayText: String
  }
  private var cellPaintCache: [CellAddress: CellPaintCacheEntry] = [:]
  private var cellPaintCacheRevision = Int.min
  private var cellPaintCacheZoom: CGFloat = -.greatestFiniteMagnitude
  /// One copy of the sheet for the draw in progress. Cell loops read this instead of `activeSheet`.
  private var layoutSheet: Sheet?
  private var drawColumnOffsets: [CGFloat]?
  private var drawRowOffsets: [CGFloat]?
  private var drawFrozenRows: Int?
  private var drawFrozenCols: Int?
  private var drawMergeLookup: MergeLookup?
  /// Zoom for the draw in progress. Reading the observed view model once per cell was
  /// about 8% of a scroll frame on a 15,000-row sheet in a Debug build.
  private var drawZoomScale: CGFloat?
  private var drawLayoutDepth = 0
  private var cachedMergeLookup: MergeLookup?
  private var cachedMergeRevision = Int.min
  private var cachedMergeSheetID: UUID?
  /// How far past the viewport a scroll plane is rasterized, in points.
  /// A tick inside this margin blits the plane; it does not redraw cell text.
  static let liveScrollOverscan: CGFloat = 280
  /// Fixed tile edge. Scrolling moves these layers; it does not redraw cells.
  static let scrollTileSize: CGFloat = 512
  /// How far ahead of the viewport a scroll prefetches, in seconds of travel.
  private static let tilePrefetchHorizon: TimeInterval = 0.5
  /// Furthest a fast flick may prefetch, in points.
  private static let tilePrefetchCap: CGFloat = 4_096
  /// Bitmap cache for tiles that scrolled away and may come back.
  private static let tileCacheByteCap = 96 * 1024 * 1024
  /// Kept tiles per pane. The live viewport plus the next screen in the scroll direction.
  private static let scrollPlaneCacheLimit = 4
  private var contentRectOverride: NSRect?
  private var rasterTarget: RasterTarget?
  private var suppressSelectionWash = false
  private struct ScrollPlane {
    var key: String
    /// Scroll origin whose visible pane was captured with `cacheDisplay`.
    var exactScroll: CGPoint
    var contentOrigin: CGPoint
    var viewRect: NSRect
    var exactCells: NSImage
    var cells: NSImage
    var overflow: NSImage
    var skipGridlines: Bool
    var scrollsX: Bool
    var scrollsY: Bool

    func matchesExact(scroll: CGPoint) -> Bool {
      let dx = scrollsX ? abs(scroll.x - exactScroll.x) : 0
      let dy = scrollsY ? abs(scroll.y - exactScroll.y) : 0
      return dx < 0.01 && dy < 0.01
    }

    func covers(scroll: CGPoint, pane: NSRect) -> Bool {
      let dx = scrollsX ? scroll.x - contentOrigin.x : 0
      let dy = scrollsY ? scroll.y - contentOrigin.y : 0
      let dest = NSRect(
        x: viewRect.origin.x - dx,
        y: viewRect.origin.y - dy,
        width: viewRect.width,
        height: viewRect.height
      )
      return dest.minX <= pane.minX + 0.5
        && dest.minY <= pane.minY + 0.5
        && dest.maxX >= pane.maxX - 0.5
        && dest.maxY >= pane.maxY - 0.5
    }

    func destination(scroll: CGPoint) -> NSRect {
      let dx = scrollsX ? scroll.x - contentOrigin.x : 0
      let dy = scrollsY ? scroll.y - contentOrigin.y : 0
      return NSRect(
        x: viewRect.origin.x - dx,
        y: viewRect.origin.y - dy,
        width: viewRect.width,
        height: viewRect.height
      )
    }
  }
  private enum RasterTarget {
    case bodyCells
    case bodyOverflow
    case bodyComposite
    case frozenCells
    case frozenOverflow
    case frozenComposite
    case columnHeaders
    case rowHeaders
  }
  private var bodyPlanes: [ScrollPlane] = []
  private var frozenTopPlanes: [ScrollPlane] = []
  private var frozenLeftPlanes: [ScrollPlane] = []
  private var frozenCornerPlanes: [ScrollPlane] = []
  private(set) var liveScrollCellVisits = 0
  private(set) var testingGridVisits = 0
  private(set) var testingOverlayVisits = 0
  private(set) var testingGridDraws = 0
  private(set) var testingFrameStores = 0
  private(set) var testingFrameClears = 0
  private var inGridDraw = false
  private var testingSkipDraw = false
  private(set) var liveScrollTextPaints = 0
  /// Debug checks: every string the live grid painted since this was set to an empty set.
  var testingPaintedTexts: Set<String>?
  private(set) var liveScrollPlaneBuilds = 0
  private(set) var liveScrollHeaderDraws = 0
  private(set) var liveScrollMaxRow = -1
  var testingScrollSurfacesPresented: Bool { scrollSurfacesPresented }
  var testingScrollTilesPresented: Bool { scrollTilesPresented }

  /// True when every tile covering the current screen is already rasterized.
  func testingViewportTileCacheReady() -> Bool {
    viewportTilesAreCached()
  }
  var testingLayerNeedsDisplay: Bool { layer?.needsDisplay() == true }

  private func testingSampleBackingPixel() -> String {
    guard let context = NSGraphicsContext.current?.cgContext, let data = context.data else {
      return "none"
    }
    let width = context.width
    let height = context.height
    let bytesPerRow = context.bytesPerRow
    let bytesPerPixel = context.bitsPerPixel / 8
    guard width > 80, height > 80, bytesPerPixel >= 4, bytesPerRow > 80 * bytesPerPixel else {
      return "small"
    }
    let x = 60
    let y = 60
    let offset = y * bytesPerRow + x * bytesPerPixel
    let bytes = data.bindMemory(to: UInt8.self, capacity: bytesPerRow * height)
    return "\(bytes[offset]),\(bytes[offset + 1]),\(bytes[offset + 2]),\(bytes[offset + 3])"
  }

  /// Drops the scroll pictures so the next draw paints every cell itself. A snapshot of the
  /// grid's layer then shows the cells rather than only the headers drawn around the pictures.
  func testingPaintCellsLive() {
    discardScrollTiles()
    needsViewportTileWarm = false
    needsDisplay = true
  }

  /// What the grid last painted for itself, without the views on top of it.
  func testingFrameImage() -> CGImage? { frameBitmap?.makeImage() }

  func testingWriteLayerPNG(to path: String) {
    let width = Int(bounds.width.rounded(.down))
    let height = Int(bounds.height.rounded(.down))
    guard width > 1, height > 1, let layer else { return }
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
    guard
      let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: bitmapInfo
      )
    else { return }
    if let frame = frameBitmap?.makeImage() {
      context.draw(frame, in: CGRect(x: 0, y: 0, width: width, height: height))
    } else {
      context.translateBy(x: 0, y: CGFloat(height))
      context.scaleBy(x: 1, y: -1)
      testingSkipDraw = true
      layer.render(in: context)
      testingSkipDraw = false
    }
    guard let image = context.makeImage() else { return }
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else { return }
    try? data.write(to: URL(fileURLWithPath: path))
  }
  /// Why the last edit repainted. The benchmark reads this.
  private(set) var testingInvalidateReason = ""
  private let editor = CellEditorTextField()
  private let editorClip: EditorClipView = {
    let view = EditorClipView()
    view.wantsLayer = true
    view.clipsToBounds = true
    view.layer?.masksToBounds = true
    view.layer?.zPosition = 23
    return view
  }()
  /// In-cell editor frame. It uses the same row height as selection and hit testing.
  var editorFrame: NSRect {
    guard editor.superview != nil else { return editor.frame }
    return editor.convert(editor.bounds, to: self)
  }
  private var isEditorActive = false
  /// Tab / Shift-Tab already moved the cell for this key event. The grid must
  /// not handle that same key again and grow the selection.
  private var suppressFollowingTabMove = false
  private var lastTabMoveTimestamp: TimeInterval = -1
  /// The open column filter panel, if any.
  private var filterPopover: NSPopover?
  private var isDraggingSelection = false
  /// ⌘-drag that began on a highlighted cell. It unhighlights instead of adding.
  private var isDraggingDeselection = false
  private var isDraggingFill = false
  private enum ImageResizeCorner { case bottomRight }
  private struct ImageDragState {
    enum Mode {
      case move
      case resize(ImageResizeCorner)
    }
    let imageID: UUID
    let mode: Mode
    let startPoint: NSPoint
    let startImage: SheetImage
  }
  private var activeImageDrag: ImageDragState?
  private struct ChartDragState {
    let chartID: UUID
    let handle: OnSheetChartGeometry.ChartFrameHandle
    let startPoint: NSPoint
    let startChart: SheetChart
    let startRect: NSRect
    var hasMoved = false
  }
  private var activeChartDrag: ChartDragState?
  /// A chart from the file being dragged. Its card moves with the pointer; the anchor is
  /// written when the drag ends.
  private var activeImportedChartDrag: ImportedChartDrag?

  private struct ImportedChartDrag {
    var id: Int
    /// `.body` moves the chart; an edge or corner resizes it.
    var handle: OnSheetChartGeometry.ChartFrameHandle = .body
    var startPoint: NSPoint
    var startRect: NSRect
    var startHostFrame: NSRect
    var hasMoved = false
  }
  private let chartHandleThickness: CGFloat = 8
  /// Flipped like the grid. Host frames are viewport coordinates whose
  /// origin is the chart's top-left. An unflipped layer reads that origin
  /// as the bottom-left, so the chart moves up when its anchor moves down
  /// and scrolls against the cells.
  ///
  /// This layer stays the full cell viewport so a chart keeps scrolling with
  /// its anchor. Frozen rows and columns are not clipped out of the chart;
  /// `FrozenPaneOverlayView` paints those cells above this layer.
  private final class ChartLayerView: NSView {
    override var isFlipped: Bool { true }
  }

  /// Paints one frozen pane after the chart layer. The grid's own `draw` runs
  /// before subviews, so a chart would otherwise cover the panes.
  ///
  /// The frame is only that pane. A full-bounds overlay clears the scrollable
  /// body as well, and the layer snapshot keeps those pixels as black, so a
  /// merged fill that scrolled out from under the header disappears.
  private final class FrozenPaneOverlayView: NSView {
    weak var grid: SpreadsheetGridNSView?
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
      guard let grid, bounds.width > 0.5, bounds.height > 0.5 else { return }
      // Scroll ticks move subviews of this overlay. Drawing would wipe the
      // corner that those subviews do not cover and would repaint cell text.
      if grid.scrollSurfacesPresented || grid.isAdjustingScrollSurfaces { return }
      guard let ctx = NSGraphicsContext.current else { return }
      let local = bounds.intersection(dirtyRect)
      guard !local.isNull else { return }
      // Clear only this pane. An opaque base stays in this view's coordinates so a
      // missed redraw cannot leave the last frozen row transparent over the body.
      ctx.cgContext.clear(local)
      grid.theme.canvas.setFill()
      local.fill()
      ctx.saveGraphicsState()
      let origin = convert(CGPoint.zero, to: grid)
      ctx.cgContext.translateBy(x: -origin.x, y: -origin.y)
      NSBezierPath(rect: convert(bounds, to: grid)).addClip()
      grid.drawFrozenPanesCoveringCharts(in: convert(dirtyRect, to: grid))
      ctx.restoreGraphicsState()
    }
  }

  /// Text for a merge that crosses a freeze. Drawn above the bitmap that would
  /// otherwise translate it, and clipped so it does not paint in the frozen pane.
  private final class PinnedMergeTextOverlay: NSView {
    enum Band { case frozenPanes, body }
    weak var grid: SpreadsheetGridNSView?
    var band: Band = .frozenPanes
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
      guard let grid, bounds.width > 0.5, bounds.height > 0.5 else { return }
      guard let ctx = NSGraphicsContext.current else { return }
      let local = bounds.intersection(dirtyRect)
      guard !local.isNull, local.width > 0.5, local.height > 0.5 else { return }
      ctx.cgContext.clear(local)
      grid.drawPinnedCrossFreezeMergeText(in: local, band: band)
    }
  }

  /// Keeps the in-cell editor inside the grid body so typed text passes under the headers.
  private final class EditorClipView: NSView {
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? {
      let hit = super.hitTest(point)
      if hit === self { return nil }
      return hit
    }
  }

  /// Selection outline, wash, formula-reference highlights, and the fill handle.
  /// These sit above the scroll-plane bitmaps so a selection change does not
  /// rasterize cell text again.
  private final class SelectionChromeOverlayView: NSView {
    weak var grid: SpreadsheetGridNSView?
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
      guard let grid, bounds.width > 0.5, bounds.height > 0.5 else { return }
      guard let ctx = NSGraphicsContext.current else { return }
      let local = bounds.intersection(dirtyRect)
      guard !local.isNull, local.width > 0.5, local.height > 0.5 else { return }
      // Same scale correction as the grid draw, so the stroke is not in another space.
      let flattened = grid.flattenHorizontalScaleIfNeeded(ctx)
      defer {
        if flattened { ctx.cgContext.restoreGState() }
      }
      ctx.cgContext.clear(local)
      grid.drawSelectionChrome(in: local)
    }
  }

  /// Clips a pre-rasterized cell or header image. Scrolling moves the image
  /// view; it does not redraw the grid.
  private final class ScrollClipView: NSView {
    let surface = ScrollSurfaceView()
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override init(frame frameRect: NSRect) {
      super.init(frame: frameRect)
      wantsLayer = true
      clipsToBounds = true
      layer?.masksToBounds = true
      surface.wantsLayer = true
      surface.layerContentsRedrawPolicy = .onSetNeedsDisplay
      addSubview(surface)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
  }

  /// Draws its bitmap once. Later frame changes only move the layer.
  private final class ScrollSurfaceView: NSView {
    var image: NSImage?
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { image != nil }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
      guard let image else { return }
      image.draw(
        in: bounds,
        from: NSRect(origin: .zero, size: image.size),
        operation: .sourceOver,
        fraction: 1,
        respectFlipped: true,
        hints: [.interpolation: NSImageInterpolation.none]
      )
    }
  }

  /// One fixed-size piece of a pane. The image is drawn once; scroll only moves it.
  private final class ScrollTileView: NSView {
    var image: NSImage?
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { image != nil }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
      guard let image else { return }
      image.draw(
        in: bounds,
        from: NSRect(origin: .zero, size: image.size),
        operation: .copy,
        fraction: 1,
        respectFlipped: true,
        hints: [.interpolation: NSImageInterpolation.none]
      )
    }
  }

  private let chartLayerView: ChartLayerView = {
    let view = ChartLayerView()
    view.wantsLayer = true
    view.layer?.backgroundColor = NSColor.clear.cgColor
    view.layer?.masksToBounds = true
    view.layer?.zPosition = 5
    view.clipsToBounds = true
    return view
  }()
  /// Above the chart (z 5) and below the cell editor (z 8). One view per pane
  /// rectangle: frozen header, then frozen columns. Neither covers the body.
  private let frozenPaneOverlays: [FrozenPaneOverlayView] = [
    SpreadsheetGridNSView.makeFrozenPaneOverlay(),
    SpreadsheetGridNSView.makeFrozenPaneOverlay(),
  ]

  private static func makeFrozenPaneOverlay() -> FrozenPaneOverlayView {
    let view = FrozenPaneOverlayView()
    view.wantsLayer = true
    view.layer?.backgroundColor = NSColor.clear.cgColor
    view.layer?.zPosition = 6
    view.layer?.isOpaque = false
    view.layer?.contentsFormat = .RGBA8Uint
    view.clipsToBounds = true
    return view
  }

  private let selectionChromeOverlay: SelectionChromeOverlayView = {
    let view = SelectionChromeOverlayView()
    view.wantsLayer = true
    view.layer?.backgroundColor = NSColor.clear.cgColor
    view.layer?.zPosition = 22
    view.layer?.isOpaque = false
    return view
  }()
  /// Merged text that starts in a frozen row or column. It is not part of a
  /// scrolling bitmap, so a scroll cannot slide it under the frozen pane.
  private let pinnedHeaderMergeOverlay: PinnedMergeTextOverlay = {
    let view = PinnedMergeTextOverlay()
    view.band = .frozenPanes
    view.wantsLayer = true
    view.layer?.backgroundColor = NSColor.clear.cgColor
    view.layer?.zPosition = 7
    view.layer?.isOpaque = false
    view.clipsToBounds = true
    return view
  }()
  private let pinnedBodyMergeOverlay: PinnedMergeTextOverlay = {
    let view = PinnedMergeTextOverlay()
    view.band = .body
    view.wantsLayer = true
    view.layer?.backgroundColor = NSColor.clear.cgColor
    view.layer?.zPosition = 2
    view.layer?.isOpaque = false
    view.clipsToBounds = true
    return view
  }()
  private let bodyScrollClip = ScrollClipView(frame: .zero)
  private let columnHeaderScrollClip = ScrollClipView(frame: .zero)
  private let rowHeaderScrollClip = ScrollClipView(frame: .zero)
  private let frozenCornerScrollClip = ScrollClipView(frame: .zero)
  private let frozenTopScrollClip = ScrollClipView(frame: .zero)
  private let frozenLeftScrollClip = ScrollClipView(frame: .zero)
  private var columnHeaderPlanes: [ScrollPlane] = []
  private var rowHeaderPlanes: [ScrollPlane] = []
  private var scrollSurfacesPresented = false
  private var isAdjustingScrollSurfaces = false
  private var scrollPlaneBuildScheduled = false
  /// Direction of the latest scroll, used to prefetch tiles ahead of the viewport.
  private var lastScrollDelta = CGPoint.zero
  private var lastScrollTime: CFAbsoluteTime = 0
  private var scrollVelocity = CGPoint.zero
  private var scrollTiles: [ScrollTileRecord] = []
  private var scrollTilesPresented = false
  /// The open paint and a sheet switch fill the on-screen tiles before the user scrolls.
  private var needsViewportTileWarm = true
  private var isAdjustingScrollTiles = false
  private var gridlinePlaceholderCache: [String: NSImage] = [:]
  private var tileDrawList: TileDrawList?
  private var tileRenderGroup: DispatchGroup?
  private let renderedTileImages = TileImageBox()
  private let scrollTileRenderQueue = DispatchQueue(
    label: "com.sparkbysam.SparkGrid.tile-render",
    qos: .userInitiated,
    attributes: .concurrent
  )
  /// Draws tile bitmaps. Value snapshots stay on `tileValues.queue`.
  private let tileRenderPool = DispatchQueue(
    label: "com.sparkbysam.SparkGrid.tile-pool",
    qos: .userInitiated,
    attributes: .concurrent
  )
  private let tileValueRenderGroup = DispatchGroup()
  private let tileWorkerLock = NSLock()
  private var tileWorkers: [TileValueSession] = []
  private var tileCalcGeneration = 0
  /// Conditional-range numbers shared by tile workers. Cleared with `tileCalcGeneration`.
  private let tileRangeLock = NSLock()
  private var tileSharedRangeValues: [RangeValueKey: [Double]] = [:]
  private var tileSharedRangeFlights: [RangeValueKey: SharedRangeFlight] = [:]
  private var isInstallingTileImages = false
  private let tileValues = TileValueSession()
  private var tileCaptureGeneration = 0
  private var tileFillEpoch: CFAbsoluteTime = 0
  private var tileImageCache: [TileImageKey: TileImageEntry] = [:]
  private var tileCacheBytes = 0
  private var tileCacheClock: UInt64 = 0
  private(set) var testingMaxTileFillSeconds: TimeInterval = 0
  private(set) var testingTileFillCount = 0
  /// Longest stretch the main thread spent installing tiles or applying a jump.
  private(set) var testingMaxMainStallSeconds: TimeInterval = 0
  /// Slowest tile since the fill stats were reset: value lookup, draw list, bitmap.
  private(set) var testingSlowestTileValueSeconds: TimeInterval = 0
  private(set) var testingSlowestTileDrawSeconds: TimeInterval = 0
  private(set) var testingSlowestTileImageSeconds: TimeInterval = 0
  private var testingRecordTilePhases = false

  /// Drawing commands for one tile. Built on the main thread from resolved cell
  /// data, then replayed into a bitmap on a background queue.
  private final class TileDrawList {
    let viewRect: NSRect
    var commands: [() -> Void] = []

    init(viewRect: NSRect) {
      self.viewRect = viewRect
    }

    func renderImage(scale: CGFloat) -> NSImage? {
      let size = viewRect.size
      guard size.width > 1, size.height > 1 else { return nil }
      let pixelsWide = max(1, Int((size.width * scale).rounded(.up)))
      let pixelsHigh = max(1, Int((size.height * scale).rounded(.up)))
      guard
        let rep = NSBitmapImageRep(
          bitmapDataPlanes: nil,
          pixelsWide: pixelsWide,
          pixelsHigh: pixelsHigh,
          bitsPerSample: 8,
          samplesPerPixel: 4,
          hasAlpha: true,
          isPlanar: false,
          colorSpaceName: .deviceRGB,
          bytesPerRow: 0,
          bitsPerPixel: 0
        )
      else { return nil }
      rep.size = size
      NSGraphicsContext.saveGraphicsState()
      defer { NSGraphicsContext.restoreGraphicsState() }
      guard let base = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
      base.imageInterpolation = .none
      let cg = base.cgContext
      cg.translateBy(x: 0, y: size.height)
      cg.scaleBy(x: 1, y: -1)
      cg.translateBy(x: -viewRect.origin.x, y: -viewRect.origin.y)
      let flipped = NSGraphicsContext(cgContext: cg, flipped: true)
      flipped.imageInterpolation = .none
      NSGraphicsContext.current = flipped
      for command in commands {
        command()
      }
      let image = NSImage(size: size)
      image.addRepresentation(rep)
      return image
    }
  }

  private struct RenderedTileImage {
    var pane: ScrollTilePane
    var x: Int
    var y: Int
    var image: NSImage
    var generation: Int
    var requestedAt: CFAbsoluteTime
  }

  private final class TileImageBox {
    let lock = NSLock()
    var images: [RenderedTileImage] = []
  }

  /// Formula results for one sheet. Each tile worker has its own engine.
  /// `queue` publishes the shared geometry the workers copy.
  private final class TileValueSession {
    let queue = DispatchQueue(
      label: "com.sparkbysam.SparkGrid.tile-values",
      qos: .userInitiated
    )
    var engine = FormulaEngine()
    var sheet: Sheet?
    var sheetID: UUID?
    var columnOffsets: [CGFloat] = []
    var rowOffsets: [CGFloat] = []
    var zoom: CGFloat = 1
    var isDarkMode = false
    /// Palette resolved on the main thread. Background tile drawing reads this
    /// and does not call `SparkTheme.palette(for:)`.
    var resolvedPalette: SparkTheme.Palette?
    var windowBackground = NSColor.white
    var gridLine = NSColor.black
    var headerLine = NSColor.black
    var headerFill = NSColor.white
    var headerText = NSColor.gray
    var mergeLookup: MergeLookup?
    var calculatedResults: [String: [CellAddress: CellValue]] = [:]
    var paintCache: [CellAddress: CellPaintCacheEntry] = [:]
    /// Numbers in each conditional range, scanned once per engine.
    var rangeValueCache: [RangeValueKey: [Double]] = [:]
    /// Bumped when the workbook changes so this worker drops its cache.
    var preparedGeneration = -1
    /// The view model's content revision this engine was built from. Its value cache is keyed
    /// by address, so after a sort it held the old rows' answers and tiles drawn while
    /// scrolling showed the sheet unsorted.
    var preparedContentRevision = -1
  }

  /// Normalized bounds of a conditional range. Direction does not change the numbers.
  private struct RangeValueKey: Hashable {
    var minRow: Int
    var maxRow: Int
    var minCol: Int
    var maxCol: Int
  }

  /// One in-flight scan of a conditional range. Other workers wait for it.
  private final class SharedRangeFlight {
    let group = DispatchGroup()
    let owner: pthread_t

    init() {
      group.enter()
      owner = pthread_self()
    }
  }

  /// Draw inputs for the tile being recorded on `TileValueSession.queue`.
  private final class TileCaptureState {
    let session: TileValueSession
    var scroll: CGPoint
    var contentOverride: NSRect?
    var drawList: TileDrawList?

    init(session: TileValueSession, scroll: CGPoint, contentOverride: NSRect?) {
      self.session = session
      self.scroll = scroll
      self.contentOverride = contentOverride
    }
  }

  private var isPropagatingDisplay = false
  private var isApplyingPartialPaint = false
  private var limitPaintTo: Set<CellAddress>?
  /// Cell pixels for the current view size. Partial edits draw into this bitmap,
  /// then the view blits it, so a layer update does not erase the other cells.
  private var frameBitmap: CGContext?
  private var isDrawingFrameBitmap = false
  private var chartHosts: [UUID: OnSheetChartHost] = [:]
  /// Charts from other apps, by their place among the sheet's kept charts.
  private var importedChartHosts: [Int: ImportedChartHost] = [:]
  /// Pointer position for each chart card, so it can name the value under the pointer.
  private var chartHovers: [UUID: ChartHover] = [:]
  private var importedChartHovers: [Int: ChartHover] = [:]
  private var importedChartSnapshots: [Int: ImportedChartSnapshot] = [:]
  private var chartHostSnapshots: [UUID: ChartHostSnapshot] = [:]
  private var isLayingOutCharts = false

  private struct ImportedChartSnapshot: Equatable {
    var placement: SpreadsheetViewModel.ImportedChartPlacement
    var selected: Bool
    var sheetID: UUID
    var contentRevision: Int
    /// Bumps when calculated values arrive from the background, such as another sheet's totals.
    var engineRevision: Int
    var series: [SpreadsheetViewModel.ImportedChartSeriesData]
  }

  private struct ChartHostSnapshot: Equatable {
    var chart: SheetChart
    var contentRevision: Int
    var selected: Bool
  }
  private var fillSourceRange: CellRange?
  private var headerDrag: HeaderDrag?
  private let resizeHandleThickness: CGFloat = 6
  private let fillHandleSize: CGFloat = 9
  private var editorCaretObserver: NSObjectProtocol?
  private var isApplyingFormulaAttributes = false
  private var lastAppliedFormulaHighlightKey = ""

  private enum HeaderDrag {
    case columns(anchor: Int)
    case rows(anchor: Int)
  }

  private enum ResizeTarget {
    case column(Int, startWidth: CGFloat, startX: CGFloat)
    case row(Int, startHeight: CGFloat, startY: CGFloat)
  }

  private var activeResize: ResizeTarget?

  private enum AutoscrollDragKind {
    case selection
    case deselection
    case fill(CellRange)
    case headerColumns(Int)
    case headerRows(Int)
  }

  private var autoscrollTimer: Timer?
  private var autoscrollLastPoint: NSPoint = .zero
  private var autoscrollDragKind: AutoscrollDragKind?
  private var autoscrollTicks = 0
  private let autoscrollMargin: CGFloat = 24
  private let autoscrollStep: CGFloat = 14
  /// Fastest drag-select step. The timer starts at `autoscrollStep` and climbs here.
  private let autoscrollMaxStep: CGFloat = 64

  private enum HeaderHit {
    case corner
    case column(Int)
    case row(Int)
    case content
  }

  override var isFlipped: Bool { true }
  override var acceptsFirstResponder: Bool { true }

  override func setNeedsDisplay(_ invalidRect: NSRect) {
    if isAdjustingScrollTiles {
      return
    }
    if scrollTilesPresented {
      // Header letters are painted on this view. A cell invalidation drops the
      // tiles; a header-only one must not, or the letters stay where they were.
      if rectOverlapsCellArea(invalidRect) {
        discardScrollTiles()
        selectionChromeOverlay.needsDisplay = true
        super.setNeedsDisplay(bounds)
        return
      }
      selectionChromeOverlay.needsDisplay = true
      super.setNeedsDisplay(invalidRect)
      return
    }
    if isApplyingPartialPaint {
      selectionChromeOverlay.needsDisplay = true
      super.setNeedsDisplay(invalidRect)
      return
    }
    var rect = invalidRect
    if !isAdjustingScrollSurfaces, scrollSurfacesPresented, rectOverlapsCellArea(invalidRect) {
      // The scrolling bitmaps were covering a stale parent layer. Repaint the
      // whole view at the current scroll before those bitmaps go away.
      hideScrollSurfaces()
      rect = bounds
    }
    selectionChromeOverlay.needsDisplay = true
    super.setNeedsDisplay(rect)
    if !scrollSurfacesPresented, !isAdjustingScrollSurfaces {
      displayFrozenPaneOverlay()
    }
  }

  private func rectOverlapsCellArea(_ rect: NSRect) -> Bool {
    let hit = rect.intersection(contentRect)
    return !hit.isNull && hit.width > 0.5 && hit.height > 0.5
  }

  private func displayFrozenPaneOverlay() {
    guard !isPropagatingDisplay else { return }
    isPropagatingDisplay = true
    for overlay in frozenPaneOverlays {
      overlay.needsDisplay = true
    }
    isPropagatingDisplay = false
  }

  private var contentRect: NSRect {
    if let override = tileCapture?.contentOverride { return override }
    if let contentRectOverride { return contentRectOverride }
    return NSRect(
      x: headerSize,
      y: headerSize,
      width: max(0, bounds.width - headerSize),
      height: max(0, bounds.height - headerSize)
    )
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    themeCache = nil
    layer?.backgroundColor = theme.canvas.cgColor
    needsDisplay = true
  }

  /// Concrete theme colors. A background tile reads the palette resolved on the main
  /// thread and does not call `palette(for:)` or the view appearance.
  private var theme: SparkTheme.Palette {
    if tileCapture != nil {
      if let palette = tileCapture?.session.resolvedPalette {
        return palette
      }
      if let palette = SparkTheme.adoptedDrawingPalette {
        return palette
      }
      return SparkTheme.fallbackPalette
    }
    return paletteResolvedOnMainThread()
  }

  private func paletteResolvedOnMainThread() -> SparkTheme.Palette {
    let key = SparkTheme.PaletteKey(appearance: effectiveAppearance)
    if let themeCache, themeCache.key == key {
      return themeCache.palette
    }
    let palette = SparkTheme.palette(for: effectiveAppearance)
    themeCache = (key, palette)
    return palette
  }

  /// Accent setting or system accent changed: repaint everything, including cached planes.
  @objc private func themeDidChange(_ notification: Notification) {
    if notification.name == NSColor.systemColorsDidChangeNotification {
      SparkTheme.noteSystemColorsChanged()
    }
    themeCache = nil
    layer?.backgroundColor = theme.canvas.cgColor
    reloadContent(resetScrollPosition: false)
    refreshSelectionDisplay()
  }

  private func gridLineColor() -> NSColor {
    theme.gridLine
  }

  /// Header cells use the same line as cells. The old light-mode value replaced the
  /// separator's alpha with 0.92 and drew near-black.
  private func headerLineColor() -> NSColor {
    theme.gridLine
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layerContentsRedrawPolicy = .onSetNeedsDisplay
    // Until the next draw, a resize keeps the old picture. Pinned, it never stretches the
    // header letters and row numbers sideways; the new area shows the canvas color.
    layerContentsPlacement = .topLeft
    layer?.backgroundColor = theme.canvas.cgColor
    NotificationCenter.default.addObserver(
      self, selector: #selector(themeDidChange(_:)), name: SparkTheme.didChangeNotification,
      object: nil)
    NotificationCenter.default.addObserver(
      self, selector: #selector(themeDidChange(_:)),
      name: NSColor.systemColorsDidChangeNotification, object: nil)
    configureEditor()
    addSubview(chartLayerView, positioned: .below, relativeTo: editorClip)
    for overlay in frozenPaneOverlays {
      overlay.grid = self
      addSubview(overlay, positioned: .above, relativeTo: chartLayerView)
    }
    bodyScrollClip.layer?.zPosition = 1
    columnHeaderScrollClip.layer?.zPosition = 20
    rowHeaderScrollClip.layer?.zPosition = 21
    bodyScrollClip.isHidden = true
    columnHeaderScrollClip.isHidden = true
    rowHeaderScrollClip.isHidden = true
    frozenCornerScrollClip.isHidden = true
    frozenTopScrollClip.isHidden = true
    frozenLeftScrollClip.isHidden = true
    addSubview(bodyScrollClip, positioned: .below, relativeTo: chartLayerView)
    addSubview(columnHeaderScrollClip)
    addSubview(rowHeaderScrollClip)
    selectionChromeOverlay.grid = self
    addSubview(selectionChromeOverlay, positioned: .below, relativeTo: editorClip)
    addSubview(scrollIndicators)
    addSubview(commentCard)
    pinnedHeaderMergeOverlay.grid = self
    pinnedBodyMergeOverlay.grid = self
    pinnedHeaderMergeOverlay.isHidden = true
    pinnedBodyMergeOverlay.isHidden = true
    addSubview(pinnedHeaderMergeOverlay, positioned: .above, relativeTo: chartLayerView)
    addSubview(pinnedBodyMergeOverlay, positioned: .below, relativeTo: chartLayerView)
  }

  override func setFrameSize(_ newSize: NSSize) {
    // A negative proposal is what logs "Invalid view geometry" and retriggers layout.
    let width = newSize.width.isFinite ? max(0, newSize.width) : 0
    let height = newSize.height.isFinite ? max(0, newSize.height) : 0
    let oldSize = frame.size
    super.setFrameSize(NSSize(width: width, height: height))
    _ = alignBoundsWithFrame()
    // The view only redraws when asked. Without this, a wider window showed the old
    // drawing stretched to the new width until something else asked for a draw.
    if frame.size != oldSize {
      needsDisplay = true
    }
  }

  /// A bounds rectangle that is not the frame stretches this view on the way to
  /// the screen and leaves the selection overlay, which is a layer-backed
  /// subview, at the unstretched size. Header letters then sit on the wrong column.
  /// Returns whether the bounds changed, so the current draw can run again on a square scale.
  @discardableResult
  private func alignBoundsWithFrame() -> Bool {
    guard !isAligningBounds else { return false }
    let target = frame.size
    guard target.width.isFinite, target.height.isFinite, target.width > 1, target.height > 1
    else { return false }
    guard abs(bounds.width - target.width) > 0.5 || abs(bounds.height - target.height) > 0.5
    else { return false }
    isAligningBounds = true
    setBoundsSize(target)
    isAligningBounds = false
    return true
  }

  private var isAligningBounds = false
  private var isLayingOut = false
  /// One extra draw after bounds are squared. Stops a mismatch from redrawing forever.
  private var didRequestBoundsRedraw = false

  override func layout() {
    if isLayingOut { return }
    isLayingOut = true
    defer { isLayingOut = false }
    super.layout()
    _ = alignBoundsWithFrame()
    if selectionChromeOverlay.frame != bounds {
      selectionChromeOverlay.frame = bounds
    }
    if scrollIndicators.frame != bounds {
      scrollIndicators.frame = bounds
    }
    if pinnedHeaderMergeOverlay.frame != bounds {
      pinnedHeaderMergeOverlay.frame = bounds
    }
    if pinnedBodyMergeOverlay.frame != bounds {
      pinnedBodyMergeOverlay.frame = bounds
    }
    layoutOnSheetCharts()
    scheduleViewportTileWarm()
    if isEditorActive {
      updateEditorFrame()
    }
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    let hit = super.hitTest(point)
    if isEditorActive, hit === editor || hit?.isDescendant(of: editor) == true {
      return hit
    }
    if let hit, hit === chartLayerView || hit.isDescendant(of: chartLayerView) {
      return self
    }
    return hit
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    for area in trackingAreas {
      removeTrackingArea(area)
    }
    let options: NSTrackingArea.Options = [
      .activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect,
      .enabledDuringMouseDrag,
    ]
    addTrackingArea(NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil))
  }

  override func resetCursorRects() {
    super.resetCursorRects()
    updateCursorRects()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  func resetScrollPosition() {
    scrollOrigin = .zero
    needsDisplay = true
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    layoutOnSheetCharts()
    guard window != nil else {
      claimedInitialFocus = false
      return
    }
    claimInitialFocusIfNeeded()
  }

  private var claimedInitialFocus = false

  func claimInitialFocusIfNeeded() {
    guard !claimedInitialFocus, window != nil else { return }
    claimedInitialFocus = true
    DispatchQueue.main.async { [weak self] in
      DispatchQueue.main.async {
        guard let self, let window = self.window else { return }
        window.makeFirstResponder(self)
      }
    }
  }

  private func configureEditor() {
    editor.isBordered = false
    editor.isBezeled = false
    editor.focusRingType = .none
    editor.drawsBackground = false
    editor.backgroundColor = .clear
    editor.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
    editor.delegate = self
    editor.isHidden = true
    editor.wantsLayer = true
    editorClip.addSubview(editor)
    addSubview(editorClip)

    editorCaretObserver = NotificationCenter.default.addObserver(
      forName: NSTextView.didChangeSelectionNotification,
      object: nil,
      queue: .main
    ) { [weak self] note in
      guard let self, self.isEditorActive, !self.isApplyingFormulaAttributes,
        let textView = note.object as? NSTextView,
        self.editor.currentEditor() === textView
      else { return }
      // Only update which ref is focused for grid borders — do not rewrite
      // attributed text here (that retriggers selection and freezes the app).
      self.viewModel?.updateFormulaHighlightFocus(atUTF16: textView.selectedRange.location)
    }
  }

  // MARK: - Layout helpers

  /// Merges indexed by row so a cell does not walk `mergedRanges`.
  private final class MergeLookup {
    struct Interval {
      var startCol: Int
      var endCol: Int
      var order: Int
      var range: CellRange
    }

    var rows: [Int: [Interval]]

    init(ranges: [CellRange]) {
      var built: [Int: [Interval]] = [:]
      for (order, range) in ranges.enumerated() {
        let n = range.normalized
        guard n.minRow <= n.maxRow, n.minCol <= n.maxCol else { continue }
        let interval = Interval(startCol: n.minCol, endCol: n.maxCol, order: order, range: range)
        for row in n.minRow...n.maxRow {
          built[row, default: []].append(interval)
        }
      }
      for row in built.keys {
        built[row]?.sort { $0.startCol < $1.startCol }
      }
      rows = built
    }

    func containing(_ address: CellAddress) -> Interval? {
      guard let intervals = rows[address.row], !intervals.isEmpty else { return nil }
      var lo = 0
      var hi = intervals.count - 1
      var found = -1
      while lo <= hi {
        let mid = (lo + hi) / 2
        if intervals[mid].startCol <= address.col {
          found = mid
          lo = mid + 1
        } else {
          hi = mid - 1
        }
      }
      guard found >= 0 else { return nil }
      var best: Interval?
      var index = found
      while index >= 0, intervals[index].startCol <= address.col {
        let interval = intervals[index]
        if address.col <= interval.endCol {
          if best == nil || interval.order < (best?.order ?? interval.order) {
            best = interval
          }
        }
        index -= 1
      }
      return best
    }
  }

  private enum MergeRole {
    case none
    case anchor(CellRange)
    case covered
  }

  private func sheetForLayout() -> Sheet? {
    if let sheet = tileCapture?.session.sheet { return sheet }
    if let layoutSheet { return layoutSheet }
    return viewModel?.activeSheet
  }

  private func paintWindowBackground() -> NSColor {
    theme.canvas
  }

  private func paintIsDarkMode() -> Bool {
    if let dark = tileCapture?.session.isDarkMode { return dark }
    return theme.isDark
  }

  /// Nil while a background tile is recording, so that pass does not touch the view model.
  private func rasterViewModel() -> SpreadsheetViewModel? {
    if tileCapture != nil { return nil }
    return viewModel
  }

  private func filterHeaderCell(row: Int, col: Int, viewModel: SpreadsheetViewModel?) -> Bool {
    if tileCapture != nil {
      guard let filter = tileCapture?.session.sheet?.autoFilter else { return false }
      let span = filter.range.normalized
      return row == span.minRow && filter.isColumnActive(col)
    }
    return viewModel?.isFilterHeaderCell(row: row, col: col) ?? false
  }

  private func beginDrawLayout() {
    if tileCapture != nil { return }
    if drawLayoutDepth == 0 {
      drawZoomScale = max(0.5, min(2.0, viewModel?.zoomScale ?? 1))
      layoutSheet = viewModel?.activeSheet
      drawFrozenRows = layoutSheet?.frozenRows ?? 0
      drawFrozenCols = layoutSheet?.frozenColumns ?? 0
      if let sheet = layoutSheet {
        drawMergeLookup = mergeLookup(for: sheet)
      }
      let columns = columnOffsets()
      let rows = rowOffsets()
      drawColumnOffsets = columns
      drawRowOffsets = rows
    }
    drawLayoutDepth += 1
  }

  private func endDrawLayout() {
    if tileCapture != nil { return }
    drawLayoutDepth = max(0, drawLayoutDepth - 1)
    guard drawLayoutDepth == 0 else { return }
    layoutSheet = nil
    drawColumnOffsets = nil
    drawRowOffsets = nil
    drawFrozenRows = nil
    drawFrozenCols = nil
    drawMergeLookup = nil
    drawZoomScale = nil
  }

  private func mergeLookup(for sheet: Sheet) -> MergeLookup {
    if let lookup = tileCapture?.session.mergeLookup { return lookup }
    let revision = viewModel?.structureRevision ?? -1
    if let cachedMergeLookup, cachedMergeRevision == revision, cachedMergeSheetID == sheet.id {
      return cachedMergeLookup
    }
    let built = MergeLookup(ranges: sheet.mergedRanges)
    cachedMergeLookup = built
    cachedMergeRevision = revision
    cachedMergeSheetID = sheet.id
    return built
  }

  private func mergeRole(at address: CellAddress, sheet: Sheet) -> MergeRole {
    let lookup = drawMergeLookup ?? mergeLookup(for: sheet)
    guard let interval = lookup.containing(address) else { return .none }
    let n = interval.range.normalized
    if address.row == n.minRow, address.col == n.minCol {
      return .anchor(interval.range)
    }
    return .covered
  }

  private func columnWidth(at col: Int) -> CGFloat {
    if let capture = tileCapture {
      let offsets = capture.session.columnOffsets
      if col >= 0, col + 1 < offsets.count {
        return offsets[col + 1] - offsets[col]
      }
      return Self.defaultColumnWidth * capture.session.zoom
    }
    if let offsets = drawColumnOffsets, col >= 0, col + 1 < offsets.count {
      return offsets[col + 1] - offsets[col]
    }
    guard let sheet = sheetForLayout() else { return Self.defaultColumnWidth * zoomScale }
    return sheet.columnWidth(for: col, default: Self.defaultColumnWidth) * zoomScale
  }

  func rowHeight(at row: Int) -> CGFloat {
    if let capture = tileCapture {
      let offsets = capture.session.rowOffsets
      if row >= 0, row + 1 < offsets.count {
        return offsets[row + 1] - offsets[row]
      }
      return Self.defaultRowHeight * capture.session.zoom
    }
    if let offsets = drawRowOffsets, row >= 0, row + 1 < offsets.count {
      return offsets[row + 1] - offsets[row]
    }
    if viewModel?.isRowHiddenByFilter(row) == true { return 0 }
    guard let viewModel, let sheet = sheetForLayout() else {
      return Self.defaultRowHeight * zoomScale
    }
    return CellTextLayout.displayRowHeight(
      row: row,
      sheet: sheet,
      defaultRowHeight: Self.defaultRowHeight,
      wrapped: wrappedRowHeights(viewModel: viewModel, sheet: sheet),
      zoom: zoomScale
    ) + filterHeaderExtraHeight(for: row)
  }

  /// Room the filter chip takes out of the header row's text rect. Added only
  /// while that row is the filter header, so clearing the filter restores the row.
  private func filterHeaderExtraHeight(for row: Int) -> CGFloat {
    guard let filter = viewModel?.filterState, row == filter.headerRow else { return 0 }
    let span = filter.range.normalized
    guard span.minCol <= span.maxCol else { return 0 }
    for col in span.minCol...span.maxCol where filter.isColumnActive(col) {
      return 14 * zoomScale
    }
    return 0
  }

  private func wrappedRowHeights(viewModel: SpreadsheetViewModel, sheet: Sheet) -> [Int: CGFloat] {
    if viewModel.structureRevision == cachedWrappedRevision, zoomScale == cachedWrappedZoom {
      return cachedWrappedRowHeights
    }
    let zoom = zoomScale
    let heights = CellTextLayout.wrappedRowHeights(
      sheet: sheet,
      defaultRowHeight: Self.defaultRowHeight,
      defaultColumnWidth: Self.defaultColumnWidth,
      zoom: zoom,
      columnWidth: { sheet.columnWidth(for: $0, default: Self.defaultColumnWidth) },
      displayText: { viewModel.displayString(at: $0) },
      extraWidthInset: { address in
        var extra: CGFloat = 0
        if viewModel.resolvedPaint(at: address).icon != nil {
          extra += 14 * zoom
        }
        if viewModel.isFilterHeaderCell(row: address.row, col: address.col) {
          extra += 14 * zoom
        }
        return extra
      }
    )
    cachedWrappedRowHeights = heights
    cachedWrappedRevision = viewModel.structureRevision
    cachedWrappedZoom = zoomScale
    return heights
  }

  private func cachedCellPaint(
    at address: CellAddress,
    viewModel: SpreadsheetViewModel?,
    sheet: Sheet,
    cell: Cell
  ) -> CellPaintCacheEntry {
    if let capture = tileCapture {
      if let cached = capture.session.paintCache[address] { return cached }
      let paint = resolvedPaintOffMain(
        at: address, sheet: sheet, cell: cell, engine: capture.session.engine)
      let value = capture.session.engine.sheetDisplayValue(at: address, sheet: sheet, cell: cell)
      let displayText = CellFormatRenderer.displayText(
        for: value,
        format: paint.format ?? cell.format,
        fallbackRaw: cell.raw
      )
      let entry = CellPaintCacheEntry(paint: paint, value: value, displayText: displayText)
      capture.session.paintCache[address] = entry
      return entry
    }
    guard let viewModel else {
      return CellPaintCacheEntry(
        paint: ConditionalPaint(format: cell.format), value: .blank, displayText: "")
    }
    if viewModel.structureRevision != cellPaintCacheRevision || zoomScale != cellPaintCacheZoom {
      cellPaintCache.removeAll(keepingCapacity: true)
      cellPaintCacheRevision = viewModel.structureRevision
      cellPaintCacheZoom = zoomScale
    }
    if let cached = cellPaintCache[address] {
      return cached
    }
    let paint = viewModel.resolvedPaint(at: address)
    let value = viewModel.sheetDisplayValue(at: address, cell: cell)
    let displayText = CellFormatRenderer.displayText(
      for: value,
      format: paint.format ?? cell.format,
      fallbackRaw: cell.raw
    )
    let entry = CellPaintCacheEntry(paint: paint, value: value, displayText: displayText)
    cellPaintCache[address] = entry
    return entry
  }

  /// Conditional paint from the tile engine. The view model stays on the main thread.
  private func resolvedPaintOffMain(
    at address: CellAddress,
    sheet: Sheet,
    cell: Cell,
    engine: FormulaEngine
  ) -> ConditionalPaint {
    let rules = sheet.conditionalFormats
    let base = sheet.formatWithTableStyle(at: address)
    guard !rules.isEmpty else { return ConditionalPaint(format: base) }
    let value = engine.sheetDisplayValue(at: address, sheet: sheet, cell: cell)
    let text = engine.displayString(at: address, sheet: sheet, format: cell.format)
    return ConditionalFormatEvaluator.resolvedPaint(
      at: address,
      base: base,
      rules: rules,
      value: value,
      displayString: text,
      numberFormat: cell.format?.numberFormat,
      numericValuesInRange: { range in
        let span = range.normalized
        guard span.minRow <= span.maxRow, span.minCol <= span.maxCol else { return [] }
        let key = RangeValueKey(
          minRow: span.minRow,
          maxRow: span.maxRow,
          minCol: span.minCol,
          maxCol: span.maxCol
        )
        if let cached = tileCapture?.session.rangeValueCache[key] {
          return cached
        }
        let generation = tileCapture?.session.preparedGeneration ?? currentTileCalcGeneration()
        let values = sharedRangeValues(key: key, generation: generation) {
          var scanned: [Double] = []
          for row in span.minRow...span.maxRow {
            for col in span.minCol...span.maxCol {
              let sample = CellAddress(row: row, col: col)
              let number = engine.sheetDisplayValue(
                at: sample, sheet: sheet, cell: sheet.cell(at: sample)
              ).asNumber
              if let number = number { scanned.append(number) }
            }
          }
          return scanned
        }
        tileCapture?.session.rangeValueCache[key] = values
        return values
      },
      evaluateFormula: { raw, sample, origin in
        engine.evaluateConditionalFormula(raw, at: sample, relativeTo: origin, sheet: sheet)
      }
    )
  }

  private func frozenColumnCount() -> Int {
    if let sheet = tileCapture?.session.sheet { return sheet.frozenColumns }
    if let drawFrozenCols { return drawFrozenCols }
    return sheetForLayout()?.frozenColumns ?? 0
  }

  private func frozenRowCount() -> Int {
    if let sheet = tileCapture?.session.sheet { return sheet.frozenRows }
    if let drawFrozenRows { return drawFrozenRows }
    return sheetForLayout()?.frozenRows ?? 0
  }

  private func frozenColumnBoundaryX() -> CGFloat {
    let frozen = frozenColumnCount()
    guard frozen > 0 else { return headerSize }
    return headerSize
      + offset(
        in: columnOffsets(), at: frozen, fallbackStride: Self.defaultColumnWidth * zoomScale)
  }

  func frozenRowBoundaryY() -> CGFloat {
    let frozen = frozenRowCount()
    guard frozen > 0 else { return headerSize }
    return headerSize
      + offset(in: rowOffsets(), at: frozen, fallbackStride: Self.defaultRowHeight * zoomScale)
  }

  private func headerColumnIndices() -> [Int] {
    let frozen = frozenColumnCount()
    var columns: [Int] = []
    if frozen > 0 {
      for col in 0..<frozen where shouldDrawColumnHeader(col) {
        columns.append(col)
      }
    }
    for span in visibleColumnSpans() {
      for col in span where col >= frozen && shouldDrawColumnHeader(col) {
        columns.append(col)
      }
    }
    return columns
  }

  private func headerRowIndices() -> [Int] {
    let frozen = frozenRowCount()
    var rows: [Int] = []
    if frozen > 0 {
      for row in 0..<frozen where shouldDrawRowHeader(row) {
        rows.append(row)
      }
    }
    for span in visibleRowSpans() {
      for row in span where row >= frozen && shouldDrawRowHeader(row) {
        rows.append(row)
      }
    }
    return rows
  }

  private func invalidateLayoutCache() {
    cachedColumnOffsets = nil
    cachedRowOffsets = nil
    cachedColumnCount = 0
    cachedRowCount = 0
    cachedColumnLayoutRevision = Int.min
    cachedColumnLayoutZoom = -.greatestFiniteMagnitude
    cachedRowLayoutRevision = Int.min
    cachedRowLayoutZoom = -.greatestFiniteMagnitude
    cachedWrappedRevision = Int.min
    cachedWrappedZoom = -.greatestFiniteMagnitude
    cellPaintCache.removeAll(keepingCapacity: true)
    cellPaintCacheRevision = Int.min
    cellPaintCacheZoom = -.greatestFiniteMagnitude
    cachedMergeLookup = nil
    cachedMergeRevision = Int.min
    cachedMergeSheetID = nil
    invalidateScrollPlanes()
  }

  private func invalidateScrollPlanes() {
    bodyPlanes.removeAll(keepingCapacity: true)
    frozenTopPlanes.removeAll(keepingCapacity: true)
    frozenLeftPlanes.removeAll(keepingCapacity: true)
    frozenCornerPlanes.removeAll(keepingCapacity: true)
    columnHeaderPlanes.removeAll(keepingCapacity: true)
    rowHeaderPlanes.removeAll(keepingCapacity: true)
    lastScrollDelta = .zero
    lastScrollTime = 0
    scrollVelocity = .zero
    hideScrollSurfaces()
  }

  /// A column or row past the laid-out offsets. Uses the last stride instead of trapping.
  private func offset(in offsets: [CGFloat], at index: Int, fallbackStride: CGFloat) -> CGFloat {
    if index >= 0, index < offsets.count { return offsets[index] }
    if offsets.isEmpty { return CGFloat(max(0, index)) * fallbackStride }
    let lastIndex = offsets.count - 1
    let last = offsets[lastIndex]
    if index <= lastIndex { return last }
    let step = offsets.count >= 2 ? offsets[lastIndex] - offsets[lastIndex - 1] : fallbackStride
    return last + CGFloat(index - lastIndex) * step
  }

  private func columnOffsets() -> [CGFloat] {
    if let capture = tileCapture, !capture.session.columnOffsets.isEmpty {
      return capture.session.columnOffsets
    }
    if let drawColumnOffsets { return drawColumnOffsets }
    let count = columnCount()
    let revision = viewModel?.structureRevision ?? -1
    if let cached = cachedColumnOffsets,
      cachedColumnCount == count,
      cachedColumnLayoutRevision == revision,
      cachedColumnLayoutZoom == zoomScale
    {
      return cached
    }
    var offsets = [CGFloat](repeating: 0, count: count + 1)
    for col in 0..<count {
      offsets[col + 1] = offsets[col] + columnWidth(at: col)
    }
    cachedColumnOffsets = offsets
    cachedColumnCount = count
    cachedColumnLayoutRevision = revision
    cachedColumnLayoutZoom = zoomScale
    return offsets
  }

  private func rowOffsets() -> [CGFloat] {
    if let capture = tileCapture, !capture.session.rowOffsets.isEmpty {
      return capture.session.rowOffsets
    }
    if let drawRowOffsets { return drawRowOffsets }
    let count = rowCount()
    let revision = viewModel?.structureRevision ?? -1
    if let cached = cachedRowOffsets,
      cachedRowCount == count,
      cachedRowLayoutRevision == revision,
      cachedRowLayoutZoom == zoomScale
    {
      return cached
    }
    var offsets = [CGFloat](repeating: 0, count: count + 1)
    for row in 0..<count {
      offsets[row + 1] = offsets[row] + rowHeight(at: row)
    }
    cachedRowOffsets = offsets
    cachedRowCount = count
    cachedRowLayoutRevision = revision
    cachedRowLayoutZoom = zoomScale
    return offsets
  }

  private func indexAtOffset(
    _ offsets: [CGFloat], position: CGFloat, lowerBound: Int, upperBound: Int
  ) -> Int {
    let upper = min(upperBound, offsets.count)
    guard upper > lowerBound else { return lowerBound }
    var lo = lowerBound
    var hi = upper - 1
    while lo < hi {
      let mid = (lo + hi + 1) / 2
      if mid < offsets.count, offsets[mid] <= position {
        lo = mid
      } else {
        hi = mid - 1
      }
    }
    return lo
  }

  private func widthOfColumns(from: Int, to: Int) -> CGFloat {
    guard to > from else { return 0 }
    let offsets = columnOffsets()
    let stride = Self.defaultColumnWidth * zoomScale
    return offset(in: offsets, at: to, fallbackStride: stride)
      - offset(in: offsets, at: from, fallbackStride: stride)
  }

  private func heightOfRows(from: Int, to: Int) -> CGFloat {
    guard to > from else { return 0 }
    let offsets = rowOffsets()
    let stride = Self.defaultRowHeight * zoomScale
    return offset(in: offsets, at: to, fallbackStride: stride)
      - offset(in: offsets, at: from, fallbackStride: stride)
  }

  private func xForColumn(_ col: Int) -> CGFloat {
    let offsets = columnOffsets()
    let modelX = offset(
      in: offsets, at: col, fallbackStride: Self.defaultColumnWidth * zoomScale)
    if col < frozenColumnCount() {
      return headerSize + modelX
    }
    return headerSize + modelX - activeScrollOrigin.x
  }

  private func yForRow(_ row: Int) -> CGFloat {
    let offsets = rowOffsets()
    let modelY = offset(
      in: offsets, at: row, fallbackStride: Self.defaultRowHeight * zoomScale)
    if row < frozenRowCount() {
      return headerSize + modelY
    }
    return headerSize + modelY - activeScrollOrigin.y
  }

  private func rowCount() -> Int {
    if let capture = tileCapture, capture.session.rowOffsets.count > 1 {
      return capture.session.rowOffsets.count - 1
    }
    if let offsets = drawRowOffsets, !offsets.isEmpty {
      return offsets.count - 1
    }
    return sheetForLayout()?.effectiveRowCount ?? Workbook.defaultRowCount
  }

  private func columnCount() -> Int {
    if let capture = tileCapture, capture.session.columnOffsets.count > 1 {
      return capture.session.columnOffsets.count - 1
    }
    if let offsets = drawColumnOffsets, !offsets.isEmpty {
      return offsets.count - 1
    }
    return sheetForLayout()?.effectiveColumnCount ?? Workbook.defaultColumnCount
  }

  private func columnAtContent(x: CGFloat) -> Int {
    let count = columnCount()
    let offsets = columnOffsets()
    let frozen = frozenColumnCount()
    let frozenEndX = frozenColumnBoundaryX()

    if x < frozenEndX {
      let position = max(0, x - headerSize)
      return indexAtOffset(offsets, position: position, lowerBound: 0, upperBound: frozen)
    }

    let position = max(0, x - headerSize + activeScrollOrigin.x)
    return indexAtOffset(offsets, position: position, lowerBound: frozen, upperBound: count)
  }

  func rowAtContent(y: CGFloat) -> Int {
    let count = rowCount()
    let offsets = rowOffsets()
    let frozen = frozenRowCount()
    let frozenEndY = frozenRowBoundaryY()
    let totalHeight = offset(
      in: offsets, at: count, fallbackStride: Self.defaultRowHeight * zoomScale)

    let position: CGFloat
    let lower: Int
    let upper: Int
    if y < frozenEndY {
      position = max(0, y - headerSize)
      lower = 0
      upper = max(frozen, 1)
    } else {
      position = max(0, y - headerSize + activeScrollOrigin.y)
      lower = frozen
      upper = count
    }

    // Clicking in empty space below all laid-out rows used to land on the last
    // zero-height (filter-hidden) index — e.g. row 1000. Clamp to content.
    if totalHeight <= 0 {
      return lower
    }
    if position >= totalHeight {
      return lastVisibleRow(in: lower..<(upper == 0 ? 1 : upper)) ?? max(lower, upper - 1)
    }

    var row = indexAtOffset(
      offsets, position: min(position, totalHeight - 0.001), lowerBound: lower, upperBound: upper)
    if rowHeight(at: row) == 0 {
      row = nearestVisibleRow(from: row, lowerBound: lower, upperBound: upper) ?? row
    }
    return row
  }

  private func lastVisibleRow(in range: Range<Int>) -> Int? {
    for row in stride(from: range.upperBound - 1, through: range.lowerBound, by: -1) {
      if rowHeight(at: row) > 0 { return row }
    }
    return nil
  }

  private func nearestVisibleRow(from row: Int, lowerBound: Int, upperBound: Int) -> Int? {
    if rowHeight(at: row) > 0 { return row }
    var down = row + 1
    var up = row - 1
    while down < upperBound || up >= lowerBound {
      if down < upperBound {
        if rowHeight(at: down) > 0 { return down }
        down += 1
      }
      if up >= lowerBound {
        if rowHeight(at: up) > 0 { return up }
        up -= 1
      }
    }
    return nil
  }

  /// Bottom Y of the laid-out sheet content inside the scrollable area (not the viewport bottom).
  private func contentBottomY() -> CGFloat {
    let offsets = rowOffsets()
    let total = offset(
      in: offsets, at: rowCount(), fallbackStride: Self.defaultRowHeight * zoomScale)
    return headerSize + total - activeScrollOrigin.y
  }

  func rectForCell(row: Int, col: Int) -> NSRect {
    NSRect(
      x: xForColumn(col),
      y: yForRow(row),
      width: columnWidth(at: col),
      height: rowHeight(at: row)
    )
  }

  /// Paint rect for a cell, spanning merges at the anchor. Returns nil for covered (non-anchor) cells.
  private func paintRect(for address: CellAddress, sheet: Sheet) -> NSRect? {
    switch mergeRole(at: address, sheet: sheet) {
    case .covered:
      return nil
    case .anchor(let range):
      return paintRect(for: address, merge: range)
    case .none:
      return paintRect(for: address, merge: nil)
    }
  }

  private func paintRect(for address: CellAddress, merge: CellRange?) -> NSRect? {
    if let merge {
      let n = merge.normalized
      let topLeft = rectForCell(row: n.minRow, col: n.minCol)
      let bottomRight = rectForCell(row: n.maxRow, col: n.maxCol)
      return topLeft.union(bottomRight)
    }
    return rectForCell(row: address.row, col: address.col)
  }

  private func fillHandleRect() -> NSRect? {
    guard let viewModel, !viewModel.isEditing, !isEditorActive else { return nil }
    guard !viewModel.hasMultipleSelectionRanges else { return nil }
    let range = (viewModel.selectionRanges.last ?? viewModel.selectionRange).normalized
    // Filter chip owns the SE corner on header cells — hide the handle so they don't fight.
    if viewModel.isFilterHeaderCell(row: range.maxRow, col: range.maxCol) { return nil }
    guard visibleRowRange().contains(range.maxRow),
      visibleColumnRange().contains(range.maxCol)
    else { return nil }
    let cell = rectForCell(row: range.maxRow, col: range.maxCol)
    guard isCellRectInContentArea(cell) else { return nil }
    let size = fillHandleSize
    return NSRect(
      x: cell.maxX - size / 2,
      y: cell.maxY - size / 2,
      width: size,
      height: size
    )
  }

  private func isPointInFillHandle(_ point: NSPoint) -> Bool {
    guard let rect = fillHandleRect() else { return false }
    return rect.insetBy(dx: -2, dy: -2).contains(point)
  }

  private func isCellRectInContentArea(_ rect: NSRect) -> Bool {
    if let area = tileCapture?.contentOverride ?? contentRectOverride {
      return rect.intersects(area)
    }
    return rect.maxX > headerSize
      && rect.maxY > headerSize
      && rect.minX < bounds.width
      && rect.minY < bounds.height
  }

  /// Extra rows and columns drawn around the viewport. A short scroll is already
  /// in that paint, and the frame does not build a region bitmap to get them.
  private var viewportPaintOverscan = false
  private let viewportPaintOverscanCells = 2

  private func visibleColumnRange() -> ClosedRange<Int> {
    let content = contentRect
    var first = max(0, columnAtContent(x: content.minX))
    var last = min(columnCount() - 1, columnAtContent(x: content.maxX))
    if viewportPaintOverscan {
      first = max(0, first - viewportPaintOverscanCells)
      last = min(columnCount() - 1, last + viewportPaintOverscanCells)
    }
    if first > last {
      let fallback = min(max(0, first), max(0, columnCount() - 1))
      return fallback...fallback
    }
    return first...last
  }

  private func visibleRowRange() -> ClosedRange<Int> {
    let content = contentRect
    var first = max(0, rowAtContent(y: content.minY))
    var last = min(rowCount() - 1, rowAtContent(y: content.maxY))
    if viewportPaintOverscan {
      first = max(0, first - viewportPaintOverscanCells)
      last = min(rowCount() - 1, last + viewportPaintOverscanCells)
    }
    if first > last {
      let fallback = min(max(0, first), max(0, rowCount() - 1))
      return fallback...fallback
    }
    return first...last
  }

  private func boundedRowSpan(_ y0: CGFloat, _ y1: CGFloat, count: Int) -> ClosedRange<Int> {
    var first = max(0, rowAtContent(y: min(y0, y1)))
    var last = min(count - 1, rowAtContent(y: max(y0, y1)))
    if viewportPaintOverscan {
      first = max(0, first - viewportPaintOverscanCells)
      last = min(count - 1, last + viewportPaintOverscanCells)
    }
    if first > last {
      let fallback = min(max(0, first), max(0, count - 1))
      return fallback...fallback
    }
    return first...last
  }

  /// On-screen rows. Frozen rows and the scrolled window are not contiguous
  /// indexes, so the closed range between them is not on screen.
  private func visibleRowSpans() -> [ClosedRange<Int>] {
    let content = contentRect
    let count = rowCount()
    guard count > 0 else { return [0...0] }
    let frozen = frozenRowCount()
    guard frozen > 0 else {
      return [boundedRowSpan(content.minY, content.maxY, count: count)]
    }
    let boundary = frozenRowBoundaryY()
    var spans: [ClosedRange<Int>] = []
    if content.minY < boundary {
      let endY = min(content.maxY, boundary - 0.001)
      if endY >= content.minY {
        let span = boundedRowSpan(content.minY, endY, count: count)
        let upper = min(span.upperBound, max(0, frozen - 1))
        let lower = min(span.lowerBound, upper)
        if lower <= upper {
          spans.append(lower...upper)
        }
      }
    }
    if content.maxY >= boundary {
      let startY = max(content.minY, boundary)
      let span = boundedRowSpan(startY, content.maxY, count: count)
      let lower = max(span.lowerBound, frozen)
      let upper = min(span.upperBound, count - 1)
      if lower <= upper {
        spans.append(lower...upper)
      }
    }
    appendMergeAnchorRows(to: &spans, count: count)
    if spans.isEmpty {
      let fallback = min(max(0, frozen), count - 1)
      return [fallback...fallback]
    }
    return spans
  }

  /// A merge anchored above this window still paints where its rect crosses the tile.
  private func appendMergeAnchorRows(to spans: inout [ClosedRange<Int>], count: Int) {
    guard let sheet = sheetForLayout(), !sheet.mergedRanges.isEmpty else { return }
    for merge in sheet.mergedRanges {
      let anchor = merge.normalized.minRow
      guard anchor >= 0, anchor < count else { continue }
      if spans.contains(where: { $0.contains(anchor) }) { continue }
      let n = merge.normalized
      let overlaps = spans.contains { span in
        n.minRow <= span.upperBound && n.maxRow >= span.lowerBound
      }
      guard overlaps else { continue }
      spans.append(anchor...anchor)
    }
  }

  private func boundedColumnSpan(_ x0: CGFloat, _ x1: CGFloat, count: Int) -> ClosedRange<Int> {
    var first = max(0, columnAtContent(x: min(x0, x1)))
    var last = min(count - 1, columnAtContent(x: max(x0, x1)))
    if viewportPaintOverscan {
      first = max(0, first - viewportPaintOverscanCells)
      last = min(count - 1, last + viewportPaintOverscanCells)
    }
    if first > last {
      let fallback = min(max(0, first), max(0, count - 1))
      return fallback...fallback
    }
    return first...last
  }

  /// On-screen columns. Frozen columns and the scrolled window are not contiguous
  /// indexes, so the closed range between them is not on screen.
  private func visibleColumnSpans() -> [ClosedRange<Int>] {
    let content = contentRect
    let count = columnCount()
    guard count > 0 else { return [0...0] }
    let frozen = frozenColumnCount()
    guard frozen > 0 else {
      return [boundedColumnSpan(content.minX, content.maxX, count: count)]
    }
    let boundary = frozenColumnBoundaryX()
    var spans: [ClosedRange<Int>] = []
    if content.minX < boundary {
      let endX = min(content.maxX, boundary - 0.001)
      if endX >= content.minX {
        let span = boundedColumnSpan(content.minX, endX, count: count)
        let upper = min(span.upperBound, max(0, frozen - 1))
        let lower = min(span.lowerBound, upper)
        if lower <= upper {
          spans.append(lower...upper)
        }
      }
    }
    if content.maxX >= boundary {
      let startX = max(content.minX, boundary)
      let span = boundedColumnSpan(startX, content.maxX, count: count)
      let lower = max(span.lowerBound, frozen)
      let upper = min(span.upperBound, count - 1)
      if lower <= upper {
        spans.append(lower...upper)
      }
    }
    appendMergeAnchorColumns(to: &spans, count: count)
    if spans.isEmpty {
      let fallback = min(max(0, frozen), count - 1)
      return [fallback...fallback]
    }
    return spans
  }

  /// Spans at or after `lower`. Frozen columns stay out of a scrolled pane.
  private func columnSpans(atOrAfter lower: Int) -> [ClosedRange<Int>] {
    var result: [ClosedRange<Int>] = []
    for span in visibleColumnSpans() {
      guard let cols = optionalRange(span, atOrAfter: lower) else { continue }
      result.append(cols)
    }
    return result
  }

  /// A merge anchored to the left of this window still paints where its rect crosses the tile.
  private func appendMergeAnchorColumns(to spans: inout [ClosedRange<Int>], count: Int) {
    guard let sheet = sheetForLayout(), !sheet.mergedRanges.isEmpty else { return }
    for merge in sheet.mergedRanges {
      let anchor = merge.normalized.minCol
      guard anchor >= 0, anchor < count else { continue }
      if spans.contains(where: { $0.contains(anchor) }) { continue }
      let n = merge.normalized
      let overlaps = spans.contains { span in
        n.minCol <= span.upperBound && n.maxCol >= span.lowerBound
      }
      guard overlaps else { continue }
      spans.append(anchor...anchor)
    }
  }

  private func totalContentSize() -> NSSize {
    let colOffsets = columnOffsets()
    let rowOff = rowOffsets()
    return NSSize(
      width: headerSize + colOffsets[columnCount()],
      height: headerSize + rowOff[rowCount()]
    )
  }

  /// Shows the scroll bars at the current position. They fade on their own.
  private func flashScrollIndicators() {
    guard window != nil, tileCapture == nil else { return }
    let frozenWidth = widthOfColumns(from: 0, to: frozenColumnCount())
    let frozenHeight = heightOfRows(from: 0, to: frozenRowCount())
    let area = NSRect(
      x: contentRect.minX + frozenWidth, y: contentRect.minY + frozenHeight,
      width: max(0, contentRect.width - frozenWidth),
      height: max(0, contentRect.height - frozenHeight))
    scrollIndicators.show(
      area: area,
      visible: area.size,
      total: CGSize(
        width: widthOfColumns(from: frozenColumnCount(), to: columnCount()),
        height: heightOfRows(from: frozenRowCount(), to: rowCount())),
      offset: scrollOrigin)
  }

  private func clampScrollOrigin() {
    let frozenCols = frozenColumnCount()
    let frozenRows = frozenRowCount()
    let scrollableWidth = widthOfColumns(from: frozenCols, to: columnCount())
    let scrollableHeight = heightOfRows(from: frozenRows, to: rowCount())
    let visibleScrollableWidth = max(0, contentRect.width - widthOfColumns(from: 0, to: frozenCols))
    let visibleScrollableHeight = max(0, contentRect.height - heightOfRows(from: 0, to: frozenRows))
    let maxX = max(0, scrollableWidth - visibleScrollableWidth)
    let maxY = max(0, scrollableHeight - visibleScrollableHeight)
    // Tiles, grid lines, and the selection stroke share this origin. A fractional
    // point lands between device pixels, and the highlight then sits in the gap.
    scrollOrigin.x = devicePixel(min(max(0, scrollOrigin.x), maxX))
    scrollOrigin.y = devicePixel(min(max(0, scrollOrigin.y), maxY))
  }

  /// The same device pixel the grid lines snap to. Selection edges use it too.
  private func devicePixel(_ value: CGFloat) -> CGFloat {
    let scale = rasterScale
    guard scale > 0, value.isFinite else { return value }
    return (value * scale).rounded() / scale
  }

  private func ensureSelectionVisible() -> Bool {
    guard let viewModel else { return false }
    let before = scrollOrigin
    let anchor = viewModel.selectionAnchor
    let end = viewModel.selectionEnd
    ensureCellVisible(row: anchor.row, col: anchor.col)
    // A merged click expands the selection to the far corner. Scrolling that
    // corner jumps the viewport. The anchor is the visible origin of the merge.
    if !selectionEndIsMergeExpansion(anchor: anchor, end: end, sheet: viewModel.activeSheet) {
      ensureCellVisible(row: end.row, col: end.col)
    }
    return before != scrollOrigin
  }

  /// True when `end` is only the far corner of the merge that contains `anchor`.
  private func selectionEndIsMergeExpansion(anchor: CellAddress, end: CellAddress, sheet: Sheet)
    -> Bool
  {
    guard anchor != end else { return false }
    let expanded = sheet.selectionExpandedForMerges(CellRange(start: anchor, end: anchor))
    let n = expanded.normalized
    return anchor.row == n.minRow
      && anchor.col == n.minCol
      && end.row == n.maxRow
      && end.col == n.maxCol
  }

  private func ensureCellVisible(row: Int, col: Int) {
    let cellRect = rectForCell(row: row, col: col)
    let visible = contentRect
    if cellRect.minX < visible.minX {
      scrollOrigin.x -= visible.minX - cellRect.minX
    } else if cellRect.maxX > visible.maxX {
      scrollOrigin.x += cellRect.maxX - visible.maxX
    }
    if cellRect.minY < visible.minY {
      scrollOrigin.y -= visible.minY - cellRect.minY
    } else if cellRect.maxY > visible.maxY {
      scrollOrigin.y += cellRect.maxY - visible.maxY
    }
    clampScrollOrigin()
  }

  private func addressAtDragPoint(_ point: NSPoint) -> CellAddress {
    let x = max(headerSize, min(point.x, bounds.width - 1))
    let y = max(headerSize, min(point.y, bounds.height - 1))
    return addressAtContent(point: NSPoint(x: x, y: y))
  }

  /// Ticks to reach `autoscrollMaxStep`. At 0.05 s a tick, about two seconds.
  private let autoscrollRampTicks = 40

  /// Grows evenly from the base step to `autoscrollMaxStep` while the pointer stays at the edge.
  private func autoscrollDistance() -> CGFloat {
    let progress = CGFloat(min(autoscrollTicks, autoscrollRampTicks)) / CGFloat(autoscrollRampTicks)
    return autoscrollStep + (autoscrollMaxStep - autoscrollStep) * progress
  }

  private func autoscrollDelta(for point: NSPoint) -> CGPoint {
    let step = autoscrollDistance()
    var delta = CGPoint.zero
    if point.x > contentRect.maxX - autoscrollMargin {
      delta.x = step
    } else if point.x < contentRect.minX + autoscrollMargin {
      delta.x = -step
    }
    if point.y > contentRect.maxY - autoscrollMargin {
      delta.y = step
    } else if point.y < contentRect.minY + autoscrollMargin {
      delta.y = -step
    }
    return delta
  }

  private func updateAutoscrollTimer(at point: NSPoint, kind: AutoscrollDragKind) {
    autoscrollLastPoint = point
    autoscrollDragKind = kind
    let delta = autoscrollDelta(for: point)
    if delta == .zero {
      stopAutoscrollTimer()
      return
    }
    guard autoscrollTimer == nil else { return }
    autoscrollTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
      self?.autoscrollTick()
    }
  }

  private func stopAutoscrollTimer() {
    autoscrollTimer?.invalidate()
    autoscrollTimer = nil
    autoscrollDragKind = nil
    autoscrollTicks = 0
  }

  private func autoscrollTick() {
    guard let kind = autoscrollDragKind else { return }
    let delta = autoscrollDelta(for: autoscrollLastPoint)
    guard delta != .zero else { return }
    scrollOrigin.x += delta.x
    scrollOrigin.y += delta.y
    clampScrollOrigin()
    applyAutoscrollDrag(kind: kind, at: autoscrollLastPoint)
    autoscrollTicks += 1
    updateEditorFrame()
    layoutOnSheetCharts()
    needsDisplay = true
  }

  private func applyAutoscrollDrag(kind: AutoscrollDragKind, at point: NSPoint) {
    guard let viewModel else { return }
    switch kind {
    case .selection:
      viewModel.extendSelection(to: addressAtDragPoint(point))
    case .deselection:
      viewModel.extendCommandDeselect(to: addressAtDragPoint(point))
    case .fill(let source):
      let end = addressAtDragPoint(point)
      let normalized = source.normalized
      let fillEnd = CellAddress(
        row: max(normalized.maxRow, end.row),
        col: max(normalized.maxCol, end.col)
      )
      viewModel.extendSelection(to: fillEnd)
    case .headerColumns(let anchor):
      let col = addressAtDragPoint(point).col
      viewModel.selectColumns(from: anchor, to: col)
    case .headerRows(let anchor):
      let row = addressAtDragPoint(point).row
      viewModel.selectRows(from: anchor, to: row)
    }
  }

  private func headerHit(at point: NSPoint) -> HeaderHit {
    if point.x < headerSize && point.y < headerSize { return .corner }
    if point.y < headerSize && point.x >= headerSize {
      return .column(columnAtContent(x: point.x))
    }
    if point.x < headerSize && point.y >= headerSize {
      return .row(rowAtContent(y: point.y))
    }
    if contentRect.contains(point) { return .content }
    return .content
  }

  private func addressAtContent(point: NSPoint) -> CellAddress {
    CellAddress(
      row: rowAtContent(y: point.y),
      col: columnAtContent(x: point.x)
    )
  }

  private func columnHeaderRect(for col: Int) -> NSRect {
    NSRect(
      x: xForColumn(col),
      y: 0,
      width: columnWidth(at: col),
      height: headerSize
    )
  }

  private func rowHeaderRect(for row: Int) -> NSRect {
    NSRect(
      x: 0,
      y: yForRow(row),
      width: headerSize,
      height: rowHeight(at: row)
    )
  }

  private func shouldDrawColumnHeader(_ col: Int) -> Bool {
    let rect = columnHeaderRect(for: col)
    let leftClip = frozenColumnCount() > 0 ? frozenColumnBoundaryX() : headerSize
    // Keep partially scrolled headers visible (clip draws the visible sliver).
    if col < frozenColumnCount() {
      return rect.maxX > headerSize && rect.minX < bounds.width
    }
    return rect.maxX > leftClip && rect.minX < bounds.width
  }

  private func shouldDrawRowHeader(_ row: Int) -> Bool {
    guard rowHeight(at: row) > 0.5 else { return false }
    let rect = rowHeaderRect(for: row)
    let topClip = frozenRowCount() > 0 ? frozenRowBoundaryY() : headerSize
    if row < frozenRowCount() {
      return rect.maxY > headerSize && rect.minY < bounds.height
    }
    return rect.maxY > topClip && rect.minY < bounds.height
  }

  private func resizeTarget(at point: NSPoint) -> ResizeTarget? {
    // Double-click zone: left edge of column A (against the corner) → auto-fit all columns.
    // Top edge of row 1 (against the corner) → auto-fit all rows.
    if point.y < headerSize, point.x >= headerSize {
      let col = columnAtContent(x: point.x)
      let rect = columnHeaderRect(for: col)

      if col == 0, abs(point.x - headerSize) <= resizeHandleThickness {
        return .column(0, startWidth: columnWidth(at: 0), startX: point.x)
      }

      if col > 0 {
        let leftBorder = rect.minX
        if abs(point.x - leftBorder) <= resizeHandleThickness {
          let previous = col - 1
          return .column(previous, startWidth: columnWidth(at: previous), startX: point.x)
        }
      }

      if abs(point.x - rect.maxX) <= resizeHandleThickness {
        return .column(col, startWidth: rect.width, startX: point.x)
      }
    }

    if point.x < headerSize, point.y >= headerSize {
      let row = rowAtContent(y: point.y)
      let rect = rowHeaderRect(for: row)

      if row == 0, abs(point.y - headerSize) <= resizeHandleThickness {
        return .row(0, startHeight: rowHeight(at: 0), startY: point.y)
      }

      if row > 0 {
        let topBorder = rect.minY
        if abs(point.y - topBorder) <= resizeHandleThickness {
          let previous = row - 1
          return .row(previous, startHeight: rowHeight(at: previous), startY: point.y)
        }
      }

      if abs(point.y - rect.maxY) <= resizeHandleThickness {
        return .row(row, startHeight: rect.height, startY: point.y)
      }
    }

    return nil
  }

  private func updateCursor(for point: NSPoint) {
    if let drag = activeChartDrag {
      if drag.handle == .body {
        NSCursor.closedHand.set()
      } else {
        cursor(for: drag.handle).set()
      }
      return
    }
    if activeImageDrag != nil {
      switch activeImageDrag?.mode {
      case .resize:
        NSCursor.crosshair.set()
      default:
        NSCursor.closedHand.set()
      }
      return
    }
    guard activeResize == nil else { return }
    if let chart = chartHitTest(at: point) {
      let rect = chartRect(for: chart)
      if viewModel?.selectedChartID == chart.id,
        let handle = OnSheetChartGeometry.frameHandle(
          at: point, in: rect, thickness: chartHandleThickness),
        handle != .body
      {
        cursor(for: handle).set()
      } else {
        NSCursor.openHand.set()
      }
      return
    }
    if let placement = importedChartHitTest(at: point) {
      if let drag = activeImportedChartDrag, drag.hasMoved {
        (drag.handle == .body ? NSCursor.closedHand : cursor(for: drag.handle)).set()
      } else if viewModel?.selectedImportedChartID == placement.id,
        let handle = OnSheetChartGeometry.frameHandle(
          at: point, in: importedChartRect(placement), thickness: chartHandleThickness),
        handle != .body
      {
        cursor(for: handle).set()
      } else {
        NSCursor.openHand.set()
      }
      return
    }
    if let imageCursor = imageCursor(at: point) {
      imageCursor.set()
      return
    }
    if isPointInFillHandle(point) {
      NSCursor.crosshair.set()
      return
    }
    switch resizeTarget(at: point) {
    case .column:
      NSCursor.resizeLeftRight.set()
    case .row:
      NSCursor.resizeUpDown.set()
    default:
      NSCursor.arrow.set()
    }
  }

  private func updateCursorRects() {
    discardCursorRects()
    let colRange = visibleColumnRange()
    for col in colRange {
      let rect = columnHeaderRect(for: col)
      let rightHandle = NSRect(
        x: rect.maxX - resizeHandleThickness / 2,
        y: rect.minY,
        width: resizeHandleThickness,
        height: rect.height
      )
      if rightHandle.maxX > headerSize {
        addCursorRect(rightHandle, cursor: .resizeLeftRight)
      }

      if col > 0 {
        let leftHandle = NSRect(
          x: rect.minX - resizeHandleThickness / 2,
          y: rect.minY,
          width: resizeHandleThickness,
          height: rect.height
        )
        if leftHandle.maxX > headerSize {
          addCursorRect(leftHandle, cursor: .resizeLeftRight)
        }
      }
    }

    for span in visibleRowSpans() {
      for row in span {
        let rect = rowHeaderRect(for: row)
        let bottomHandle = NSRect(
          x: rect.minX,
          y: rect.maxY - resizeHandleThickness / 2,
          width: rect.width,
          height: resizeHandleThickness
        )
        if bottomHandle.maxY > headerSize {
          addCursorRect(bottomHandle, cursor: .resizeUpDown)
        }

        if row > 0 {
          let topHandle = NSRect(
            x: rect.minX,
            y: rect.minY - resizeHandleThickness / 2,
            width: rect.width,
            height: resizeHandleThickness
          )
          if topHandle.maxY > headerSize {
            addCursorRect(topHandle, cursor: .resizeUpDown)
          }
        }
      }
    }

    if let sheet = viewModel?.activeSheet {
      let selectedChartID = viewModel?.selectedChartID
      for chart in sheet.charts {
        let rect = chartRect(for: chart)
        guard rect.width >= 8, rect.height >= 8, rect.intersects(bounds) else { continue }
        addScrollableCursorRect(rect, cursor: .openHand)
        guard chart.id == selectedChartID else { continue }
        let thickness = chartHandleThickness
        addScrollableCursorRect(
          NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: thickness),
          cursor: .resizeUpDown
        )
        addScrollableCursorRect(
          NSRect(x: rect.minX, y: rect.maxY - thickness, width: rect.width, height: thickness),
          cursor: .resizeUpDown
        )
        addScrollableCursorRect(
          NSRect(x: rect.minX, y: rect.minY, width: thickness, height: rect.height),
          cursor: .resizeLeftRight
        )
        addScrollableCursorRect(
          NSRect(x: rect.maxX - thickness, y: rect.minY, width: thickness, height: rect.height),
          cursor: .resizeLeftRight
        )
        let corner = thickness + 4
        for origin in [
          NSPoint(x: rect.minX, y: rect.minY),
          NSPoint(x: rect.maxX, y: rect.minY),
          NSPoint(x: rect.minX, y: rect.maxY),
          NSPoint(x: rect.maxX, y: rect.maxY),
        ] {
          addScrollableCursorRect(
            NSRect(
              x: origin.x - corner / 2, y: origin.y - corner / 2, width: corner, height: corner),
            cursor: .crosshair
          )
        }
      }
      let selectedID = viewModel?.selectedImageID
      for image in sheet.images {
        let rect = imageRect(for: image)
        guard rect.intersects(contentRect) else { continue }
        if image.id == selectedID {
          addCursorRect(imageResizeHandleRect(for: rect), cursor: .crosshair)
        }
        addCursorRect(rect, cursor: .openHand)
      }
    }
  }

  // MARK: - Drawing

  private func scrollPlaneKey() -> String {
    let appearance = theme.isDark ? "d" : "l"
    let sheetID = viewModel?.activeSheet.id.uuidString ?? ""
    return
      "\(viewModel?.structureRevision ?? -1)|\(zoomScale)|\(sheetID)|\(appearance)|\(frozenRowCount())|\(frozenColumnCount())|\(rasterScale)"
  }

  private var rasterScale: CGFloat {
    max(1, window?.backingScaleFactor ?? 2)
  }

  private struct PlaneCoverage {
    var origin: CGPoint
    var viewRect: NSRect
  }

  /// Extra rows and columns live in the same image as the viewport so a short
  /// scroll only moves that image.
  private func expandedCoverage(scroll: CGPoint, pane: NSRect, scrollsX: Bool, scrollsY: Bool)
    -> PlaneCoverage
  {
    let overscan = Self.liveScrollOverscan
    var origin = scroll
    var size = pane.size
    if scrollsX {
      let lead = min(overscan, max(0, origin.x))
      origin.x -= lead
      size.width += lead + overscan
    }
    if scrollsY {
      let lead = min(overscan, max(0, origin.y))
      origin.y -= lead
      size.height += lead + overscan
    }
    return PlaneCoverage(origin: origin, viewRect: NSRect(origin: pane.origin, size: size))
  }

  private func contentRect(coveringScrollable rect: NSRect) -> NSRect {
    let frozenW = max(0, rect.minX - headerSize)
    let frozenH = max(0, rect.minY - headerSize)
    return NSRect(
      x: headerSize,
      y: headerSize,
      width: max(1, frozenW + rect.width),
      height: max(1, frozenH + rect.height)
    )
  }

  private func invalidateScrollSurfaces() {
    var rects = [scrollableCellsClipRect()]
    if frozenRowCount() > 0 {
      rects.append(frozenTopStripClipRect())
      if frozenColumnCount() > 0 {
        rects.append(frozenCellsClipRect())
      }
    }
    if frozenColumnCount() > 0 {
      rects.append(frozenLeftStripClipRect())
    }
    rects.append(NSRect(x: 0, y: 0, width: bounds.width, height: headerSize))
    rects.append(NSRect(x: 0, y: 0, width: headerSize, height: bounds.height))
    for rect in rects where rect.width > 0.5 && rect.height > 0.5 {
      setNeedsDisplay(rect.intersection(bounds))
    }
  }

  private func drawRasterStack(_ target: RasterTarget, in dirtyRect: NSRect) {
    beginDrawLayout()
    defer { endDrawLayout() }
    switch target {
    case .bodyCells:
      tileFill(dirtyRect, color: paintWindowBackground())
      tileClip(scrollableCellsClipRect()) {
        self.drawCells(in: dirtyRect)
      }
    case .bodyOverflow:
      if recordingDrawList == nil {
        NSGraphicsContext.current?.cgContext.clear(dirtyRect)
      }
      drawScrollableOverflowText(in: dirtyRect)
    case .bodyComposite:
      tileFill(dirtyRect, color: paintWindowBackground())
      tileClip(scrollableCellsClipRect()) {
        self.drawCells(in: dirtyRect)
        if !self.visibleRegionIsMostlyBordered() {
          self.drawGridLines(in: dirtyRect)
        }
        self.drawScrollableOverflowText(in: dirtyRect)
        self.drawImages(in: dirtyRect)
      }
    case .frozenCells:
      tileFill(dirtyRect, color: paintWindowBackground())
      fillFrozenPaneBackgrounds(in: dirtyRect)
      drawFrozenCells(in: dirtyRect)
    case .frozenOverflow:
      if recordingDrawList == nil {
        NSGraphicsContext.current?.cgContext.clear(dirtyRect)
      }
      drawFrozenOverflowText(in: dirtyRect)
    case .frozenComposite:
      tileFill(dirtyRect, color: paintWindowBackground())
      fillFrozenPaneBackgrounds(in: dirtyRect)
      drawFrozenCells(in: dirtyRect)
      if !visibleRegionIsMostlyBordered() {
        drawFrozenGridLines(in: dirtyRect)
      }
      drawFrozenOverflowText(in: dirtyRect)
      drawImages(in: dirtyRect)
    case .columnHeaders:
      drawScrollingHeaderPlane(columns: true, in: dirtyRect)
    case .rowHeaders:
      drawScrollingHeaderPlane(columns: false, in: dirtyRect)
    }
  }

  private func captureManual(
    viewRect: NSRect,
    scroll: CGPoint,
    contentOverride: NSRect?,
    target: RasterTarget,
    suppressWash: Bool
  ) -> NSImage? {
    let savedScroll = scrollOrigin
    let savedOverride = contentRectOverride
    let savedTarget = rasterTarget
    let savedWash = suppressSelectionWash
    scrollOrigin = scroll
    contentRectOverride = contentOverride
    rasterTarget = target
    suppressSelectionWash = suppressWash
    defer {
      scrollOrigin = savedScroll
      contentRectOverride = savedOverride
      rasterTarget = savedTarget
      suppressSelectionWash = savedWash
    }
    return renderManual(viewRect: viewRect) {
      self.drawRasterStack(target, in: viewRect)
    }
  }

  /// Flipped point-space bitmap so cell drawing matches `isFlipped`.
  private func renderManual(viewRect: NSRect, draw: () -> Void) -> NSImage? {
    let size = viewRect.size
    guard size.width > 1, size.height > 1 else { return nil }
    let scale = rasterScale
    let pixelsWide = max(1, Int((size.width * scale).rounded(.up)))
    let pixelsHigh = max(1, Int((size.height * scale).rounded(.up)))
    guard
      let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelsWide,
        pixelsHigh: pixelsHigh,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
      )
    else { return nil }
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    guard let base = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    base.imageInterpolation = .none
    let cg = base.cgContext
    cg.translateBy(x: 0, y: size.height)
    cg.scaleBy(x: 1, y: -1)
    cg.translateBy(x: -viewRect.origin.x, y: -viewRect.origin.y)
    let flipped = NSGraphicsContext(cgContext: cg, flipped: true)
    flipped.imageInterpolation = .none
    NSGraphicsContext.current = flipped
    draw()
    let image = NSImage(size: size)
    image.addRepresentation(rep)
    return image
  }

  private func ensureBodyPlane(at scroll: CGPoint) -> ScrollPlane? {
    let pane = scrollableCellsClipRect()
    guard pane.width > 1, pane.height > 1, viewModel != nil else { return nil }
    let key = scrollPlaneKey()
    if let existing = takeCoveringPlane(in: bodyPlanes, key: key, scroll: scroll, pane: pane) {
      return existing
    }
    let coverage = expandedCoverage(scroll: scroll, pane: pane, scrollsX: true, scrollsY: true)
    let override = contentRect(coveringScrollable: coverage.viewRect)
    prepareValuesCovering(
      viewRect: coverage.viewRect, scroll: coverage.origin, contentOverride: override)
    guard
      let image = captureManual(
        viewRect: coverage.viewRect,
        scroll: coverage.origin,
        contentOverride: override,
        target: .bodyComposite,
        suppressWash: false
      )
    else { return nil }
    let plane = ScrollPlane(
      key: key,
      exactScroll: scroll,
      contentOrigin: coverage.origin,
      viewRect: coverage.viewRect,
      exactCells: image,
      cells: image,
      overflow: image,
      skipGridlines: true,
      scrollsX: true,
      scrollsY: true
    )
    storePlane(plane, in: &bodyPlanes, pane: pane)
    liveScrollPlaneBuilds += 1
    return plane
  }

  private func ensureFrozenPlane(
    in cache: inout [ScrollPlane],
    pane: NSRect,
    scrollsX: Bool,
    scrollsY: Bool,
    at scroll: CGPoint
  ) -> ScrollPlane? {
    guard pane.width > 1, pane.height > 1, viewModel != nil else { return nil }
    let key = scrollPlaneKey()
    let anchor = CGPoint(
      x: scrollsX ? scroll.x : scrollOrigin.x,
      y: scrollsY ? scroll.y : scrollOrigin.y
    )
    if let existing = takeCoveringPlane(in: cache, key: key, scroll: anchor, pane: pane) {
      return existing
    }
    let coverage = expandedCoverage(
      scroll: anchor, pane: pane, scrollsX: scrollsX, scrollsY: scrollsY)
    let manualScroll = CGPoint(
      x: scrollsX ? coverage.origin.x : scrollOrigin.x,
      y: scrollsY ? coverage.origin.y : scrollOrigin.y
    )
    let override = NSRect(
      x: headerSize,
      y: headerSize,
      width: max(bounds.width - headerSize, coverage.viewRect.maxX - headerSize),
      height: max(bounds.height - headerSize, coverage.viewRect.maxY - headerSize)
    )
    prepareValuesCovering(
      viewRect: coverage.viewRect, scroll: manualScroll, contentOverride: override)
    guard
      let image = captureManual(
        viewRect: coverage.viewRect,
        scroll: manualScroll,
        contentOverride: override,
        target: .frozenComposite,
        suppressWash: false
      )
    else { return nil }
    let plane = ScrollPlane(
      key: key,
      exactScroll: anchor,
      contentOrigin: coverage.origin,
      viewRect: coverage.viewRect,
      exactCells: image,
      cells: image,
      overflow: image,
      skipGridlines: true,
      scrollsX: scrollsX,
      scrollsY: scrollsY
    )
    storePlane(plane, in: &cache, pane: pane)
    liveScrollPlaneBuilds += 1
    return plane
  }

  private func scrollingColumnHeaderPane() -> NSRect {
    let left = frozenColumnCount() > 0 ? frozenColumnBoundaryX() : headerSize
    return NSRect(x: left, y: 0, width: max(0, bounds.width - left), height: headerSize)
  }

  private func scrollingRowHeaderPane() -> NSRect {
    let top = frozenRowCount() > 0 ? frozenRowBoundaryY() : headerSize
    return NSRect(x: 0, y: top, width: headerSize, height: max(0, bounds.height - top))
  }

  private func ensureColumnHeaderPlane(at scroll: CGPoint) -> ScrollPlane? {
    ensureHeaderPlane(
      in: &columnHeaderPlanes,
      pane: scrollingColumnHeaderPane(),
      scrollsX: true,
      scrollsY: false,
      target: .columnHeaders,
      at: scroll
    )
  }

  private func ensureRowHeaderPlane(at scroll: CGPoint) -> ScrollPlane? {
    ensureHeaderPlane(
      in: &rowHeaderPlanes,
      pane: scrollingRowHeaderPane(),
      scrollsX: false,
      scrollsY: true,
      target: .rowHeaders,
      at: scroll
    )
  }

  private func ensureHeaderPlane(
    in cache: inout [ScrollPlane],
    pane: NSRect,
    scrollsX: Bool,
    scrollsY: Bool,
    target: RasterTarget,
    at scroll: CGPoint
  ) -> ScrollPlane? {
    guard pane.width > 1, pane.height > 1, viewModel != nil else { return nil }
    let key = scrollPlaneKey()
    let anchor = CGPoint(
      x: scrollsX ? scroll.x : scrollOrigin.x,
      y: scrollsY ? scroll.y : scrollOrigin.y
    )
    if let existing = takeCoveringPlane(in: cache, key: key, scroll: anchor, pane: pane) {
      return existing
    }
    let coverage = expandedCoverage(
      scroll: anchor, pane: pane, scrollsX: scrollsX, scrollsY: scrollsY)
    let manualScroll = CGPoint(
      x: scrollsX ? coverage.origin.x : scrollOrigin.x,
      y: scrollsY ? coverage.origin.y : scrollOrigin.y
    )
    guard
      let image = captureManual(
        viewRect: coverage.viewRect,
        scroll: manualScroll,
        contentOverride: contentRect(coveringScrollable: coverage.viewRect),
        target: target,
        suppressWash: true
      )
    else { return nil }
    let plane = ScrollPlane(
      key: key,
      exactScroll: anchor,
      contentOrigin: coverage.origin,
      viewRect: coverage.viewRect,
      exactCells: image,
      cells: image,
      overflow: image,
      skipGridlines: true,
      scrollsX: scrollsX,
      scrollsY: scrollsY
    )
    storePlane(plane, in: &cache, pane: pane)
    liveScrollPlaneBuilds += 1
    return plane
  }

  /// Labels for the scrolling header bands. Frozen labels stay in the view's
  /// last paint because they do not move.
  private func drawScrollingHeaderPlane(columns: Bool, in dirtyRect: NSRect) {
    let headerFill = theme.chrome
    let headerText = theme.secondaryLabel
    let gridLine = headerLineColor()
    let attrs: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 11, weight: .medium),
      .foregroundColor: headerText,
    ]
    tileFill(dirtyRect, color: headerFill)
    if columns {
      let frozenCols = frozenColumnCount()
      for span in visibleColumnSpans() {
        guard let cols = optionalRange(span, atOrAfter: frozenCols) else { continue }
        for col in cols {
          let rect = columnHeaderRect(for: col)
          guard dirtyRect.intersects(rect), rect.width > 0.5 else { continue }
          let label = A1Notation.columnLabel(for: col) as NSString
          let size = label.size(withAttributes: attrs)
          let point = NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2)
          let band = rect.intersection(dirtyRect)
          recordHeaderCell(
            band: band,
            label: label,
            point: point,
            attributes: attrs,
            fill: headerFill,
            line: gridLine,
            from: NSPoint(x: rect.maxX, y: rect.minY),
            to: NSPoint(x: rect.maxX, y: rect.maxY)
          )
        }
      }
    } else {
      let frozenRows = frozenRowCount()
      for span in visibleRowSpans() {
        guard let rows = optionalRange(span, atOrAfter: frozenRows) else { continue }
        for row in rows where rowHeight(at: row) > 0.5 {
          let rect = rowHeaderRect(for: row)
          guard dirtyRect.intersects(rect), rect.height > 0.5 else { continue }
          let label = "\(row + 1)" as NSString
          let size = label.size(withAttributes: attrs)
          let point = NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2)
          let band = rect.intersection(dirtyRect)
          recordHeaderCell(
            band: band,
            label: label,
            point: point,
            attributes: attrs,
            fill: headerFill,
            line: gridLine,
            from: NSPoint(x: rect.minX, y: rect.maxY),
            to: NSPoint(x: rect.maxX, y: rect.maxY)
          )
        }
      }
    }
  }

  private func recordHeaderCell(
    band: NSRect,
    label: NSString,
    point: NSPoint,
    attributes: [NSAttributedString.Key: Any],
    fill: NSColor,
    line: NSColor,
    from: NSPoint,
    to: NSPoint
  ) {
    if let tileDrawList = recordingDrawList {
      let paint = resolvedDrawColor(fill)
      let textColor = resolvedDrawColor(
        (attributes[.foregroundColor] as? NSColor) ?? theme.secondaryLabel)
      var recordedAttributes = attributes
      recordedAttributes[.foregroundColor] = textColor
      let stroke = resolvedDrawColor(line)
      tileDrawList.commands.append {
        paint.setFill()
        band.fill()
        label.draw(at: point, withAttributes: recordedAttributes)
        stroke.setStroke()
        NSBezierPath.strokeLine(from: from, to: to)
      }
    } else {
      fill.setFill()
      band.fill()
      label.draw(at: point, withAttributes: attributes)
      line.setStroke()
      NSBezierPath.strokeLine(from: from, to: to)
    }
  }

  private func optionalRange(_ range: ClosedRange<Int>, atOrAfter lower: Int) -> ClosedRange<Int>? {
    let first = max(range.lowerBound, lower)
    guard first <= range.upperBound else { return nil }
    return first...range.upperBound
  }

  private func buildScrollPlanesIfNeeded() {
    buildScrollPlanes(at: scrollOrigin)
  }

  private func buildScrollPlanes(at scroll: CGPoint) {
    _ = ensureBodyPlane(at: scroll)
    _ = ensureColumnHeaderPlane(at: scroll)
    _ = ensureRowHeaderPlane(at: scroll)
    _ = ensureFrozenScrollPlanes(at: scroll)
  }

  @discardableResult
  private func ensureFrozenScrollPlanes(at scroll: CGPoint) -> (
    corner: ScrollPlane?, top: ScrollPlane?, left: ScrollPlane?
  ) {
    let cornerPane = frozenCellsClipRect()
    let topPane = frozenTopStripClipRect()
    let leftPane = frozenLeftStripClipRect()
    let corner =
      frozenRowCount() > 0 && frozenColumnCount() > 0 && cornerPane.width > 1
        && cornerPane.height > 1
      ? ensureFrozenPlane(
        in: &frozenCornerPlanes,
        pane: cornerPane,
        scrollsX: false,
        scrollsY: false,
        at: scroll
      )
      : nil
    let top =
      frozenRowCount() > 0 && topPane.width > 1 && topPane.height > 1
      ? ensureFrozenPlane(
        in: &frozenTopPlanes,
        pane: topPane,
        scrollsX: true,
        scrollsY: false,
        at: scroll
      )
      : nil
    let left =
      frozenColumnCount() > 0 && leftPane.width > 1 && leftPane.height > 1
      ? ensureFrozenPlane(
        in: &frozenLeftPlanes,
        pane: leftPane,
        scrollsX: false,
        scrollsY: true,
        at: scroll
      )
      : nil
    return (corner, top, left)
  }

  /// After a live paint, raster the current screen once the frame has been committed.
  private func scheduleScrollPlanePrefetch() {
    guard !planesCover(scrollOrigin) else { return }
    scheduleOffFrameScrollBuild()
  }

  /// One region per turn, after the scroll frame. The frame itself only blits.
  private func scheduleOffFrameScrollBuild() {
    guard !scrollPlaneBuildScheduled, rasterTarget == nil, window != nil, viewModel != nil else {
      return
    }
    guard scrollRegionNeedingBuild() != nil else { return }
    scrollPlaneBuildScheduled = true
    DispatchQueue.main.async { [weak self] in
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.scrollPlaneBuildScheduled = false
        self.performOffFrameScrollBuild()
      }
    }
  }

  private func performOffFrameScrollBuild() {
    guard rasterTarget == nil, window != nil, viewModel != nil else { return }
    guard let target = scrollRegionNeedingBuild() else { return }
    let presented = scrollSurfacesPresented
    isAdjustingScrollSurfaces = true
    buildScrollPlanes(at: target)
    isAdjustingScrollSurfaces = false
    if presented {
      needsDisplay = false
    }
    guard planesCover(target) else { return }
    guard presented || scrollSurfacesPresented else { return }
    _ = applyScrollSurfaces()
  }

  /// The on-screen region wins. Otherwise the next uncovered step toward one viewport ahead.
  private func scrollRegionNeedingBuild() -> CGPoint? {
    if !planesCover(scrollOrigin) {
      return scrollOrigin
    }
    return nextViewportStep()
  }

  private func nextViewportStep() -> CGPoint? {
    let dx = lastScrollDelta.x
    let dy = lastScrollDelta.y
    guard abs(dx) > 0.5 || abs(dy) > 0.5 else { return nil }
    let pane = scrollableCellsClipRect()
    guard pane.width > 1, pane.height > 1 else { return nil }
    let dirX: CGFloat = abs(dx) > 0.5 ? (dx > 0 ? 1 : -1) : 0
    let dirY: CGFloat = abs(dy) > 0.5 ? (dy > 0 ? 1 : -1) : 0
    let goal = clampedScroll(
      CGPoint(
        x: scrollOrigin.x + dirX * pane.width,
        y: scrollOrigin.y + dirY * pane.height
      ))
    if planesCover(goal) { return nil }
    let step = Self.liveScrollOverscan
    var cursor = scrollOrigin
    for _ in 0..<8 {
      let next = clampedScroll(
        CGPoint(
          x: cursor.x + dirX * step,
          y: cursor.y + dirY * step
        ))
      if abs(next.x - cursor.x) < 0.5, abs(next.y - cursor.y) < 0.5 {
        return nil
      }
      if !planesCover(next) {
        return next
      }
      let passedX = dirX == 0 || (dirX > 0 ? next.x >= goal.x - 0.5 : next.x <= goal.x + 0.5)
      let passedY = dirY == 0 || (dirY > 0 ? next.y >= goal.y - 0.5 : next.y <= goal.y + 0.5)
      if passedX && passedY { return nil }
      cursor = next
    }
    return nil
  }

  private func clampedScroll(_ scroll: CGPoint) -> CGPoint {
    let saved = scrollOrigin
    scrollOrigin = scroll
    clampScrollOrigin()
    let clamped = scrollOrigin
    scrollOrigin = saved
    return clamped
  }

  private func planesCover(_ scroll: CGPoint) -> Bool {
    let key = scrollPlaneKey()
    let bodyPane = scrollableCellsClipRect()
    let columnPane = scrollingColumnHeaderPane()
    let rowPane = scrollingRowHeaderPane()
    guard
      bodyPlanes.contains(where: { $0.key == key && $0.covers(scroll: scroll, pane: bodyPane) }),
      columnHeaderPlanes.contains(where: {
        $0.key == key && $0.covers(scroll: scroll, pane: columnPane)
      }),
      rowHeaderPlanes.contains(where: { $0.key == key && $0.covers(scroll: scroll, pane: rowPane) })
    else { return false }
    let topPane = frozenTopStripClipRect()
    let leftPane = frozenLeftStripClipRect()
    let cornerPane = frozenCellsClipRect()
    if frozenRowCount() > 0, topPane.height > 1,
      !frozenTopPlanes.contains(where: { $0.key == key && $0.covers(scroll: scroll, pane: topPane) }
      )
    {
      return false
    }
    if frozenColumnCount() > 0, leftPane.width > 1,
      !frozenLeftPlanes.contains(where: {
        $0.key == key && $0.covers(scroll: scroll, pane: leftPane)
      })
    {
      return false
    }
    if frozenRowCount() > 0, frozenColumnCount() > 0, cornerPane.width > 1, cornerPane.height > 1,
      !frozenCornerPlanes.contains(where: {
        $0.key == key && $0.covers(scroll: scroll, pane: cornerPane)
      })
    {
      return false
    }
    return true
  }

  private func planeForBlit(
    in cache: [ScrollPlane],
    key: String,
    scroll: CGPoint,
    pane: NSRect
  ) -> ScrollPlane? {
    if let covering = takeCoveringPlane(in: cache, key: key, scroll: scroll, pane: pane) {
      return covering
    }
    return takeNearestPlane(in: cache, key: key, scroll: scroll)
  }

  /// The first covering tile stays on screen until the scroll leaves it.
  private func takeCoveringPlane(
    in cache: [ScrollPlane],
    key: String,
    scroll: CGPoint,
    pane: NSRect
  ) -> ScrollPlane? {
    cache.first { $0.key == key && $0.covers(scroll: scroll, pane: pane) }
  }

  private func takeNearestPlane(
    in cache: [ScrollPlane],
    key: String,
    scroll: CGPoint
  ) -> ScrollPlane? {
    var best: ScrollPlane?
    var bestDistance = CGFloat.greatestFiniteMagnitude
    for plane in cache where plane.key == key {
      let dx = plane.scrollsX ? plane.exactScroll.x - scroll.x : 0
      let dy = plane.scrollsY ? plane.exactScroll.y - scroll.y : 0
      let distance = (dx * dx) + (dy * dy)
      if distance < bestDistance {
        bestDistance = distance
        best = plane
      }
    }
    return best
  }

  private func storePlane(_ plane: ScrollPlane, in cache: inout [ScrollPlane], pane: NSRect) {
    cache.removeAll { $0.key == plane.key && $0.matchesExact(scroll: plane.exactScroll) }
    cache.append(plane)
    let limit = Self.scrollPlaneCacheLimit
    let key = scrollPlaneKey()
    while cache.count > limit {
      let candidates = cache.indices.dropLast()
      if let index = candidates.first(where: { index in
        let candidate = cache[index]
        return candidate.key != key || !candidate.covers(scroll: scrollOrigin, pane: pane)
      }) {
        cache.remove(at: index)
        continue
      }
      guard
        let farthest = candidates.max(by: { lhs, rhs in
          planeDistance(cache[lhs], from: scrollOrigin)
            < planeDistance(cache[rhs], from: scrollOrigin)
        })
      else { break }
      cache.remove(at: farthest)
    }
  }

  private func planeDistance(_ plane: ScrollPlane, from scroll: CGPoint) -> CGFloat {
    let dx = plane.scrollsX ? plane.exactScroll.x - scroll.x : 0
    let dy = plane.scrollsY ? plane.exactScroll.y - scroll.y : 0
    return (dx * dx) + (dy * dy)
  }

  private func hideScrollSurfaces() {
    scrollSurfacesPresented = false
    bodyScrollClip.isHidden = true
    columnHeaderScrollClip.isHidden = true
    rowHeaderScrollClip.isHidden = true
    frozenCornerScrollClip.isHidden = true
    frozenTopScrollClip.isHidden = true
    frozenLeftScrollClip.isHidden = true
    hidePinnedMergeText()
  }

  private enum ScrollTilePane: CaseIterable, Hashable {
    case body
    case columnHeader
    case rowHeader
    case frozenCorner
    case frozenTop
    case frozenLeft
  }

  private struct ScrollTileSpec {
    var rect: NSRect
    var scrollsX: Bool
    var scrollsY: Bool
    var target: RasterTarget
  }

  private struct ScrollTileRecord {
    var pane: ScrollTilePane
    var indexX: Int
    var indexY: Int
    var scrollsX: Bool
    var scrollsY: Bool
    var contentOrigin: CGPoint
    var viewRect: NSRect
    var image: NSImage
    var placeholder: Bool
    var requestedAt: CFAbsoluteTime = 0
    /// When this tile's frame first intersected its clip. Fill time starts here.
    var visibleAt: CFAbsoluteTime = 0
    var fillNoted = false
    var filledDuringFling = false
    var layerReady = false
    let view: ScrollTileView
  }

  private struct TileImageKey: Hashable {
    var pane: ScrollTilePane
    var x: Int
    var y: Int
  }

  private struct TileImageEntry {
    var image: NSImage
    var bytes: Int
    var used: UInt64
  }

  /// Show gridlines for the visible tiles, then fill each one from calculated values.
  func testingPrepareScrollTiles() {
    guard viewModel != nil, bounds.width > 2, bounds.height > 2 else { return }
    warmTileValueEngine()
    updatingScrollTiles {
      self.syncScrollTiles()
    }
    _ = tileValueRenderGroup.wait(timeout: .now() + 30)
    installBackgroundTileImages()
    noteTileVisibility()
    needsDisplay = false
  }

  /// Ignore fills that happened while the first screen was prepared.
  func testingResetTileFillStats() {
    testingMaxTileFillSeconds = 0
    testingTileFillCount = 0
    testingMaxMainStallSeconds = 0
    tileWorkerLock.lock()
    testingSlowestTileValueSeconds = 0
    testingSlowestTileDrawSeconds = 0
    testingSlowestTileImageSeconds = 0
    tileWorkerLock.unlock()
    tileFillEpoch = CFAbsoluteTimeGetCurrent()
    for index in scrollTiles.indices {
      scrollTiles[index].filledDuringFling = false
    }
  }

  /// Let tiles requested by a jump install as they finish. The main thread
  /// pumps the run loop. It does not wait out the draw.
  func testingFinishScrollTileFills() {
    let deadline = Date().addingTimeInterval(30)
    while Date() < deadline {
      if !visiblePlaceholderTilesRemain() { break }
      RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.001))
    }
    let started = CFAbsoluteTimeGetCurrent()
    installBackgroundTileImages()
    noteTileVisibility()
    noteMainStall(CFAbsoluteTimeGetCurrent() - started)
  }

  private func visiblePlaceholderTilesRemain() -> Bool {
    for tile in scrollTiles where tile.placeholder {
      let visible = scrollTileClip(tile.pane).bounds.intersection(tile.view.frame)
      if visible.width >= 0.5 && visible.height >= 0.5 { return true }
    }
    return false
  }

  private func noteMainStall(_ seconds: TimeInterval) {
    if seconds > testingMaxMainStallSeconds {
      testingMaxMainStallSeconds = seconds
    }
  }

  func testingEnableTilePhaseTiming(_ enabled: Bool) {
    testingRecordTilePhases = enabled
  }

  private func noteSlowestTile(value: TimeInterval, draw: TimeInterval, image: TimeInterval) {
    let total = value + draw + image
    tileWorkerLock.lock()
    let previous =
      testingSlowestTileValueSeconds + testingSlowestTileDrawSeconds
      + testingSlowestTileImageSeconds
    if total > previous {
      testingSlowestTileValueSeconds = value
      testingSlowestTileDrawSeconds = draw
      testingSlowestTileImageSeconds = image
    }
    tileWorkerLock.unlock()
  }

  private func advanceTileCalcGeneration() {
    tileRangeLock.lock()
    tileCalcGeneration += 1
    tileSharedRangeValues.removeAll(keepingCapacity: true)
    tileRangeLock.unlock()
  }

  private func currentTileCalcGeneration() -> Int {
    tileRangeLock.lock()
    let generation = tileCalcGeneration
    tileRangeLock.unlock()
    return generation
  }

  /// One scan of a conditional range, shared by the tile workers until the sheet changes.
  /// `scan` runs outside the lock. A worker that already owns this key scans again.
  private func sharedRangeValues(
    key: RangeValueKey,
    generation: Int,
    scan: () -> [Double]
  ) -> [Double] {
    while true {
      tileRangeLock.lock()
      if tileCalcGeneration != generation {
        tileRangeLock.unlock()
        return scan()
      }
      if let cached = tileSharedRangeValues[key] {
        tileRangeLock.unlock()
        return cached
      }
      if let flight = tileSharedRangeFlights[key] {
        if pthread_equal(flight.owner, pthread_self()) != 0 {
          tileRangeLock.unlock()
          return scan()
        }
        tileRangeLock.unlock()
        flight.group.wait()
        continue
      }
      let flight = SharedRangeFlight()
      tileSharedRangeFlights[key] = flight
      tileRangeLock.unlock()
      let values = scan()
      tileRangeLock.lock()
      if tileCalcGeneration == generation {
        tileSharedRangeValues[key] = values
      }
      tileSharedRangeFlights[key] = nil
      tileRangeLock.unlock()
      flight.group.leave()
      return values
    }
  }

  private func resolvedDrawColor(_ color: NSColor) -> NSColor {
    color.usingColorSpace(.deviceRGB) ?? color
  }

  private func tileFill(_ rect: NSRect, color: NSColor) {
    if let tileDrawList = recordingDrawList {
      let paint = resolvedDrawColor(color)
      let area = rect
      tileDrawList.commands.append {
        paint.setFill()
        area.fill()
      }
    } else {
      color.setFill()
      rect.fill()
    }
  }

  private func tileClip(_ rect: NSRect, draw: () -> Void) {
    if let tileDrawList = recordingDrawList {
      let clip = rect
      tileDrawList.commands.append {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: clip).addClip()
      }
      draw()
      tileDrawList.commands.append {
        NSGraphicsContext.restoreGraphicsState()
      }
    } else {
      NSGraphicsContext.saveGraphicsState()
      NSBezierPath(rect: rect).addClip()
      draw()
      NSGraphicsContext.restoreGraphicsState()
    }
  }

  private func tileStroke(_ path: NSBezierPath, color: NSColor) {
    if let tileDrawList = recordingDrawList {
      let paint = resolvedDrawColor(color)
      let recorded = path
      tileDrawList.commands.append {
        paint.setStroke()
        recorded.stroke()
      }
    } else {
      color.setStroke()
      path.stroke()
    }
  }

  private func tileStrokeLine(from start: NSPoint, to end: NSPoint, color: NSColor) {
    if let tileDrawList = recordingDrawList {
      let paint = resolvedDrawColor(color)
      tileDrawList.commands.append {
        paint.setStroke()
        NSBezierPath.strokeLine(from: start, to: end)
      }
    } else {
      color.setStroke()
      NSBezierPath.strokeLine(from: start, to: end)
    }
  }

  private func installBackgroundTileImages() {
    if isInstallingTileImages { return }
    isInstallingTileImages = true
    let started = CFAbsoluteTimeGetCurrent()
    defer {
      isInstallingTileImages = false
      noteMainStall(CFAbsoluteTimeGetCurrent() - started)
    }
    renderedTileImages.lock.lock()
    let images = renderedTileImages.images
    renderedTileImages.images.removeAll(keepingCapacity: true)
    renderedTileImages.lock.unlock()
    guard !images.isEmpty else { return }
    let generation = tileCaptureGeneration
    var kept: [RenderedTileImage] = []
    kept.reserveCapacity(images.count)
    updatingScrollTiles {
      for item in images where item.generation == generation {
        kept.append(item)
        guard
          let index = self.scrollTiles.firstIndex(where: {
            $0.pane == item.pane && $0.indexX == item.x && $0.indexY == item.y
          })
        else { continue }
        self.scrollTiles[index].image = item.image
        self.scrollTiles[index].placeholder = false
        self.finishTileFillIfVisible(index)
        let view = self.scrollTiles[index].view
        view.image = item.image
        view.needsDisplay = true
        view.display()
        self.scrollTiles[index].layerReady = true
      }
    }
    for item in kept {
      rememberTileImage(pane: item.pane, x: item.x, y: item.y, image: item.image)
    }
  }

  private func noteTileFilled(visibleAt: CFAbsoluteTime) {
    guard visibleAt >= tileFillEpoch, visibleAt > 0 else { return }
    testingTileFillCount += 1
    let elapsed = CFAbsoluteTimeGetCurrent() - visibleAt
    if elapsed > testingMaxTileFillSeconds {
      testingMaxTileFillSeconds = elapsed
    }
  }

  /// Start the fill clock when a tile enters the clip. A tile that is already
  /// painted counts as immediate. A placeholder counts until its bitmap arrives.
  private func noteTileVisibility() {
    let now = CFAbsoluteTimeGetCurrent()
    for index in scrollTiles.indices {
      if scrollTiles[index].fillNoted { continue }
      let frame = scrollTiles[index].view.frame
      let clip = scrollTileClip(scrollTiles[index].pane).bounds
      let visible = clip.intersection(frame)
      if visible.width < 0.5 || visible.height < 0.5 { continue }
      if scrollTiles[index].visibleAt == 0 {
        scrollTiles[index].visibleAt = now
      }
      if !scrollTiles[index].placeholder {
        finishTileFillIfVisible(index)
      }
    }
  }

  private func finishTileFillIfVisible(_ index: Int) {
    guard scrollTiles.indices.contains(index) else { return }
    if scrollTiles[index].fillNoted { return }
    let visibleAt = scrollTiles[index].visibleAt
    guard visibleAt > 0 else { return }
    scrollTiles[index].fillNoted = true
    if visibleAt >= tileFillEpoch {
      scrollTiles[index].filledDuringFling = true
    }
    noteTileFilled(visibleAt: visibleAt)
  }

  private var recordingDrawList: TileDrawList? {
    if let list = tileCapture?.drawList { return list }
    return tileDrawList
  }

  private func collectTileDrawList(
    viewRect: NSRect,
    scroll: CGPoint,
    contentOverride: NSRect?,
    target: RasterTarget
  ) -> TileDrawList {
    let list = TileDrawList(viewRect: viewRect)
    if let capture = tileCapture {
      let savedScroll = capture.scroll
      let savedOverride = capture.contentOverride
      let savedList = capture.drawList
      capture.scroll = scroll
      capture.contentOverride = contentOverride
      capture.drawList = list
      drawRasterStack(target, in: viewRect)
      capture.drawList = savedList
      capture.scroll = savedScroll
      capture.contentOverride = savedOverride
      return list
    }
    let savedScroll = scrollOrigin
    let savedOverride = contentRectOverride
    let savedList = tileDrawList
    scrollOrigin = scroll
    contentRectOverride = contentOverride
    tileDrawList = list
    defer {
      tileDrawList = savedList
      scrollOrigin = savedScroll
      contentRectOverride = savedOverride
    }
    drawRasterStack(target, in: viewRect)
    return list
  }

  /// Sampled mismatches between a body tile and a fresh raster of the same rect.
  /// Zero means the tile image matches the cell renderer.
  func testingTilePixelMismatches() -> Int {
    guard scrollTilesPresented else { return -1 }
    let previous = isAdjustingScrollTiles
    isAdjustingScrollTiles = true
    defer { isAdjustingScrollTiles = previous }
    var mismatches = 0
    var checked = 0
    for tile in scrollTiles where tile.pane == .body && !tile.placeholder {
      let visible = scrollTileClip(.body).bounds.intersection(tile.view.frame)
      if visible.width < 0.5 || visible.height < 0.5 { continue }
      let scroll = CGPoint(
        x: tile.scrollsX ? tile.contentOrigin.x : scrollOrigin.x,
        y: tile.scrollsY ? tile.contentOrigin.y : scrollOrigin.y
      )
      guard
        let fresh = captureManual(
          viewRect: tile.viewRect,
          scroll: scroll,
          contentOverride: contentRect(coveringScrollable: tile.viewRect),
          target: .bodyComposite,
          suppressWash: true
        )
      else { return -1 }
      mismatches += bitmapMismatchCount(tile.image, fresh)
      checked += 1
      if checked >= 4 { break }
    }
    if checked == 0 { return -1 }
    return mismatches
  }

  /// Mismatches between a body tile's view and the image it was given.
  /// A high count means the layer is showing different pixels than the raster.
  func testingTileViewMismatches() -> Int {
    guard let tile = scrollTiles.first(where: { $0.pane == .body && !$0.placeholder }) else {
      return -1
    }
    let previous = isAdjustingScrollTiles
    isAdjustingScrollTiles = true
    defer { isAdjustingScrollTiles = previous }
    guard let shown = imageFromTileView(tile.view) else { return -1 }
    return bitmapMismatchCount(tile.image, shown)
  }

  /// Mismatches for body tiles that filled in during the fling.
  func testingLateTilePixelMismatches() -> Int {
    let late = scrollTiles.filter {
      $0.pane == .body && $0.filledDuringFling && !$0.placeholder
    }
    guard !late.isEmpty else { return -1 }
    let previous = isAdjustingScrollTiles
    isAdjustingScrollTiles = true
    defer { isAdjustingScrollTiles = previous }
    var mismatches = 0
    var checked = 0
    for tile in late {
      let scroll = CGPoint(
        x: tile.scrollsX ? tile.contentOrigin.x : scrollOrigin.x,
        y: tile.scrollsY ? tile.contentOrigin.y : scrollOrigin.y
      )
      guard
        let fresh = captureManual(
          viewRect: tile.viewRect,
          scroll: scroll,
          contentOverride: contentRect(coveringScrollable: tile.viewRect),
          target: .bodyComposite,
          suppressWash: true
        )
      else { return -1 }
      mismatches += bitmapMismatchCount(tile.image, fresh)
      checked += 1
      if checked >= 4 { break }
    }
    return mismatches
  }

  private func imageFromTileView(_ view: NSView) -> NSImage? {
    let bounds = view.bounds
    guard bounds.width > 1, bounds.height > 1 else { return nil }
    guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
    view.cacheDisplay(in: bounds, to: rep)
    let image = NSImage(size: bounds.size)
    image.addRepresentation(rep)
    return image
  }

  private func moveScrollTilesForScroll() {
    let started = CFAbsoluteTimeGetCurrent()
    defer { noteMainStall(CFAbsoluteTimeGetCurrent() - started) }
    installBackgroundTileImages()
    updatingScrollTiles {
      self.updateEditorFrame()
      self.layoutOnSheetCharts()
      self.syncScrollTiles()
      self.displaySelectionChrome()
    }
    noteTileVisibility()
    needsDisplay = false
    invalidateStickyHeaders()
  }

  /// Column letters and row numbers live on this view, not on the cell tiles.
  /// Mark just those bands dirty so a scroll does not leave the previous letters in place.
  private func invalidateStickyHeaders() {
    guard bounds.width > 1, bounds.height > 1 else { return }
    let topHeight = min(headerSize, bounds.height)
    let leftWidth = min(headerSize, bounds.width)
    selectionChromeOverlay.needsDisplay = true
    super.setNeedsDisplay(NSRect(x: 0, y: 0, width: bounds.width, height: topHeight))
    super.setNeedsDisplay(NSRect(x: 0, y: 0, width: leftWidth, height: bounds.height))
  }

  private func updatingScrollTiles(_ body: () -> Void) {
    let previous = isAdjustingScrollTiles
    isAdjustingScrollTiles = true
    body()
    isAdjustingScrollTiles = previous
  }

  private func discardScrollTiles() {
    tileCaptureGeneration += 1
    lastScrollTime = 0
    scrollVelocity = .zero
    tileImageCache.removeAll(keepingCapacity: true)
    tileCacheBytes = 0
    let tiles = scrollTiles
    scrollTiles.removeAll(keepingCapacity: true)
    scrollTilesPresented = false
    renderedTileImages.lock.lock()
    renderedTileImages.images.removeAll(keepingCapacity: true)
    renderedTileImages.lock.unlock()
    for tile in tiles {
      tile.view.removeFromSuperview()
    }
    hideScrollSurfaces()
  }

  private struct PendingScrollTile {
    var pane: ScrollTilePane
    var indexX: Int
    var indexY: Int
    var spec: ScrollTileSpec
  }

  private func syncScrollTiles() {
    guard viewModel != nil else { return }
    visibleTileDrawDeadline = CFAbsoluteTimeGetCurrent() + Self.visibleTileDrawBudget
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    defer { CATransaction.commit() }
    var pending: [PendingScrollTile] = []
    let leadX = tilePrefetchLead(delta: lastScrollDelta.x, velocity: scrollVelocity.x)
    let leadY = tilePrefetchLead(delta: lastScrollDelta.y, velocity: scrollVelocity.y)
    for pane in ScrollTilePane.allCases {
      // Live column letters use the sheet's widths. The header tile is a
      // default-width placeholder one tile wide, so the rest of the band stays blank.
      if pane == .columnHeader {
        scrollTileClip(pane).isHidden = true
        continue
      }
      guard let spec = scrollTileSpec(pane) else {
        scrollTileClip(pane).isHidden = true
        continue
      }
      placeScrollTileClip(pane, frame: spec.rect)
      let columns = scrollTileIndices(
        offset: spec.scrollsX ? scrollOrigin.x : 0,
        length: spec.rect.width,
        scrolls: spec.scrollsX,
        lead: spec.scrollsX ? leadX : 0
      )
      let rows = scrollTileIndices(
        offset: spec.scrollsY ? scrollOrigin.y : 0,
        length: spec.rect.height,
        scrolls: spec.scrollsY,
        lead: spec.scrollsY ? leadY : 0
      )
      for indexX in columns {
        for indexY in rows where !scrollTileExists(pane: pane, x: indexX, y: indexY) {
          pending.append(
            PendingScrollTile(pane: pane, indexX: indexX, indexY: indexY, spec: spec))
        }
      }
    }
    let vertical = abs(lastScrollDelta.y) >= abs(lastScrollDelta.x)
    pending.sort { a, b in
      tileComesBefore(a, b, vertical: vertical)
    }
    for item in pending {
      addPlaceholderScrollTile(
        pane: item.pane, indexX: item.indexX, indexY: item.indexY, spec: item.spec)
    }
    for index in scrollTiles.indices {
      let frame = scrollTileFrame(scrollTiles[index])
      let view = scrollTiles[index].view
      if view.frame != frame {
        view.frame = frame
      }
      if scrollTiles[index].layerReady { continue }
      let visible = scrollTileClip(scrollTiles[index].pane).bounds.intersection(frame)
      if visible.width < 0.5 || visible.height < 0.5 { continue }
      view.needsDisplay = true
      view.display()
      scrollTiles[index].layerReady = true
    }
    scrollTilesPresented = !scrollTiles.isEmpty
    if scrollTilesPresented {
      hidePinnedMergeText()
      for overlay in frozenPaneOverlays {
        overlay.isHidden = true
      }
    }
  }

  private func scrollTileSpec(_ pane: ScrollTilePane) -> ScrollTileSpec? {
    let rect: NSRect
    let scrollsX: Bool
    let scrollsY: Bool
    let target: RasterTarget
    switch pane {
    case .body:
      rect = scrollableCellsClipRect()
      scrollsX = true
      scrollsY = true
      target = .bodyComposite
    case .columnHeader:
      rect = scrollingColumnHeaderPane()
      scrollsX = true
      scrollsY = false
      target = .columnHeaders
    case .rowHeader:
      rect = scrollingRowHeaderPane()
      scrollsX = false
      scrollsY = true
      target = .rowHeaders
    case .frozenCorner:
      rect = frozenCellsClipRect()
      scrollsX = false
      scrollsY = false
      target = .frozenComposite
    case .frozenTop:
      rect = frozenTopStripClipRect()
      scrollsX = true
      scrollsY = false
      target = .frozenComposite
    case .frozenLeft:
      rect = frozenLeftStripClipRect()
      scrollsX = false
      scrollsY = true
      target = .frozenComposite
    }
    guard rect.width > 1, rect.height > 1 else { return nil }
    return ScrollTileSpec(rect: rect, scrollsX: scrollsX, scrollsY: scrollsY, target: target)
  }

  private func scrollTileClip(_ pane: ScrollTilePane) -> ScrollClipView {
    switch pane {
    case .body: bodyScrollClip
    case .columnHeader: columnHeaderScrollClip
    case .rowHeader: rowHeaderScrollClip
    case .frozenCorner: frozenCornerScrollClip
    case .frozenTop: frozenTopScrollClip
    case .frozenLeft: frozenLeftScrollClip
    }
  }

  private func scrollTileZPosition(_ pane: ScrollTilePane) -> CGFloat {
    switch pane {
    case .body: 1
    case .frozenCorner, .frozenTop, .frozenLeft: 8
    case .columnHeader: 20
    case .rowHeader: 21
    }
  }

  private func placeScrollTileClip(_ pane: ScrollTilePane, frame: NSRect) {
    let clip = scrollTileClip(pane)
    if clip.superview !== self {
      addSubview(clip, positioned: .below, relativeTo: selectionChromeOverlay)
    }
    if clip.frame != frame {
      clip.frame = frame
    }
    clip.layer?.zPosition = scrollTileZPosition(pane)
    clip.layer?.backgroundColor = theme.canvas.cgColor
    clip.surface.isHidden = true
    clip.isHidden = false
  }

  /// The next band of tiles, then that band's headers, then tiles further ahead.
  private func tileComesBefore(
    _ a: PendingScrollTile,
    _ b: PendingScrollTile,
    vertical: Bool
  ) -> Bool {
    if vertical {
      if a.indexY != b.indexY {
        return lastScrollDelta.y >= 0 ? a.indexY < b.indexY : a.indexY > b.indexY
      }
    } else if a.indexX != b.indexX {
      return lastScrollDelta.x >= 0 ? a.indexX < b.indexX : a.indexX > b.indexX
    }
    let paneOrderA = tilePrefetchPaneOrder(a.pane)
    let paneOrderB = tilePrefetchPaneOrder(b.pane)
    if paneOrderA != paneOrderB { return paneOrderA < paneOrderB }
    if a.indexX != b.indexX { return a.indexX < b.indexX }
    return a.indexY < b.indexY
  }

  private func tilePrefetchPaneOrder(_ pane: ScrollTilePane) -> Int {
    switch pane {
    case .body: 0
    case .rowHeader: 1
    case .frozenLeft: 2
    case .columnHeader: 3
    case .frozenTop: 4
    case .frozenCorner: 5
    }
  }

  private func tilePrefetchLead(delta: CGFloat, velocity: CGFloat) -> CGFloat {
    guard delta != 0 else { return 0 }
    var lead = velocity * CGFloat(Self.tilePrefetchHorizon)
    if lead * delta <= 0 {
      lead = 0
    }
    if abs(lead) > Self.tilePrefetchCap {
      lead = lead > 0 ? Self.tilePrefetchCap : -Self.tilePrefetchCap
    }
    if abs(lead) < Self.scrollTileSize {
      lead = delta > 0 ? Self.scrollTileSize : -Self.scrollTileSize
    }
    return lead
  }

  private func scrollTileIndices(
    offset: CGFloat,
    length: CGFloat,
    scrolls: Bool,
    lead: CGFloat = 0
  ) -> [Int] {
    guard length > 0.5 else { return [] }
    if !scrolls { return [0] }
    guard offset.isFinite, length.isFinite, lead.isFinite else { return [] }
    let size = Self.scrollTileSize
    guard size > 1 else { return [] }
    var start = offset
    var end = offset + length
    if lead > 0 {
      end += lead
    } else if lead < 0 {
      start += lead
    }
    if start < 0 { start = 0 }
    let first = max(0, Int(start / size))
    let last = max(first, Int((end - 0.01) / size))
    let cappedLast = min(last, first + 32)
    var indices: [Int] = []
    indices.reserveCapacity(cappedLast - first + 1)
    var index = first
    while index <= cappedLast {
      indices.append(index)
      index += 1
    }
    return indices
  }

  private func scrollTileExists(pane: ScrollTilePane, x: Int, y: Int) -> Bool {
    scrollTiles.contains { $0.pane == pane && $0.indexX == x && $0.indexY == y }
  }

  private func scrollTileViewRect(_ spec: ScrollTileSpec) -> NSRect {
    let width = spec.scrollsX ? Self.scrollTileSize : spec.rect.width
    let height = spec.scrollsY ? Self.scrollTileSize : spec.rect.height
    return NSRect(x: spec.rect.minX, y: spec.rect.minY, width: width, height: height)
  }

  private func scrollTileContentOrigin(indexX: Int, indexY: Int, spec: ScrollTileSpec) -> CGPoint {
    CGPoint(
      x: spec.scrollsX ? CGFloat(indexX) * Self.scrollTileSize : 0,
      y: spec.scrollsY ? CGFloat(indexY) * Self.scrollTileSize : 0
    )
  }

  private func scrollTileFrame(_ tile: ScrollTileRecord) -> NSRect {
    let dx = tile.scrollsX ? scrollOrigin.x - tile.contentOrigin.x : 0
    let dy = tile.scrollsY ? scrollOrigin.y - tile.contentOrigin.y : 0
    return NSRect(x: -dx, y: -dy, width: tile.viewRect.width, height: tile.viewRect.height)
  }

  /// Raster the tiles that cover the screen. Rows past that screen stay unbuilt.
  /// Setup is cheap and the raster runs off the paint frame, so the open grid
  /// is not waiting and the tiles can be ready before the first scroll.
  private func scheduleViewportTileWarm() {
    guard needsViewportTileWarm, !inGridDraw, rasterTarget == nil, tileCapture == nil,
      viewModel != nil
    else { return }
    // Tile workers would calculate the same uncached formulas as the open pass.
    guard viewModel?.formulaEngine.paintsStoredResultsOnly != true else { return }
    guard bounds.width > 2, bounds.height > 2, window != nil else { return }
    needsViewportTileWarm = false
    enqueueViewportTileWarm()
  }

  private func enqueueViewportTileWarm() {
    guard viewModel != nil, bounds.width > 2, bounds.height > 2 else { return }
    warmTileValueEngine()
    let tiles = viewportTileIndexes()
    let requestedAt = CFAbsoluteTimeGetCurrent()
    for tile in tiles {
      let viewRect = scrollTileViewRect(tile.spec)
      let contentOrigin = scrollTileContentOrigin(
        indexX: tile.x, indexY: tile.y, spec: tile.spec)
      enqueueTileValueRender(
        pane: tile.pane,
        indexX: tile.x,
        indexY: tile.y,
        spec: tile.spec,
        viewRect: viewRect,
        contentOrigin: contentOrigin,
        requestedAt: requestedAt,
        notifyMain: true
      )
    }
  }

  /// Draw the tiles already on screen again after stored values replace `#REF!`.
  private func rerenderPresentedTiles() {
    let requestedAt = CFAbsoluteTimeGetCurrent()
    for index in scrollTiles.indices {
      let tile = scrollTiles[index]
      forgetTileImage(TileImageKey(pane: tile.pane, x: tile.indexX, y: tile.indexY))
      guard let spec = scrollTileSpec(tile.pane) else { continue }
      scrollTiles[index].placeholder = true
      enqueueTileValueRender(
        pane: tile.pane,
        indexX: tile.indexX,
        indexY: tile.indexY,
        spec: spec,
        viewRect: tile.viewRect,
        contentOrigin: tile.contentOrigin,
        requestedAt: requestedAt,
        notifyMain: true
      )
    }
  }

  private struct ViewportTile {
    var pane: ScrollTilePane
    var x: Int
    var y: Int
    var spec: ScrollTileSpec
  }

  /// Tiles that intersect the current screen. Prefetch lead stays at zero.
  private func viewportTileIndexes() -> [ViewportTile] {
    var tiles: [ViewportTile] = []
    for pane in ScrollTilePane.allCases {
      if pane == .columnHeader { continue }
      guard let spec = scrollTileSpec(pane) else { continue }
      let columns = scrollTileIndices(
        offset: spec.scrollsX ? scrollOrigin.x : 0,
        length: spec.rect.width,
        scrolls: spec.scrollsX
      )
      let rows = scrollTileIndices(
        offset: spec.scrollsY ? scrollOrigin.y : 0,
        length: spec.rect.height,
        scrolls: spec.scrollsY
      )
      for x in columns {
        for y in rows {
          tiles.append(ViewportTile(pane: pane, x: x, y: y, spec: spec))
        }
      }
    }
    return tiles
  }

  /// Move tiles only when the screen being shown is already rasterized.
  /// A jump onto unbuilt rows paints cells instead of waiting on new tiles.
  private func useWarmTilesForScroll() -> Bool {
    if scrollTilesPresented {
      moveScrollTilesForScroll()
      return true
    }
    guard presentCachedViewportTiles() else { return false }
    moveScrollTilesForScroll()
    return true
  }

  private func viewportTilesAreCached() -> Bool {
    let tiles = viewportTileIndexes()
    guard !tiles.isEmpty else { return false }
    for tile in tiles where cachedTileImage(pane: tile.pane, x: tile.x, y: tile.y) == nil {
      return false
    }
    return true
  }

  /// Install tiles that are already rasterized. A miss keeps the live cell paint.
  private func presentCachedViewportTiles() -> Bool {
    guard viewportTilesAreCached() else { return false }
    let savedDelta = lastScrollDelta
    let savedVelocity = scrollVelocity
    lastScrollDelta = .zero
    scrollVelocity = .zero
    updatingScrollTiles {
      self.syncScrollTiles()
    }
    lastScrollDelta = savedDelta
    scrollVelocity = savedVelocity
    return scrollTilesPresented
  }

  /// Offsets for `sheet`, not for whatever sheet last filled the cache.
  private func columnOffsetsCovering(_ sheet: Sheet, existing: [CGFloat], zoom: CGFloat)
    -> [CGFloat]
  {
    let needed = sheet.effectiveColumnCount + 1
    if existing.count >= needed { return existing }
    var offsets = [CGFloat](repeating: 0, count: max(needed, 1))
    let columns = max(0, offsets.count - 1)
    for col in 0..<columns {
      offsets[col + 1] =
        offsets[col] + sheet.columnWidth(for: col, default: Self.defaultColumnWidth) * zoom
    }
    return offsets
  }

  private func rowOffsetsCovering(_ sheet: Sheet, existing: [CGFloat], zoom: CGFloat) -> [CGFloat] {
    let needed = sheet.effectiveRowCount + 1
    if existing.count >= needed { return existing }
    var offsets = [CGFloat](repeating: 0, count: max(needed, 1))
    let rows = max(0, offsets.count - 1)
    for row in 0..<rows {
      offsets[row + 1] =
        offsets[row] + sheet.rowHeight(for: row, default: Self.defaultRowHeight) * zoom
    }
    return offsets
  }

  private func warmTileValueEngine() {
    guard let viewModel else { return }
    let workbook = viewModel.workbook
    let sheet = workbook.activeSheet
    if columnCount() < sheet.effectiveColumnCount {
      drawColumnOffsets = nil
      cachedColumnOffsets = nil
      cachedColumnCount = 0
    }
    if rowCount() < sheet.effectiveRowCount {
      drawRowOffsets = nil
      cachedRowOffsets = nil
      cachedRowCount = 0
    }
    let columns = columnOffsetsCovering(sheet, existing: columnOffsets(), zoom: zoomScale)
    let rows = rowOffsetsCovering(sheet, existing: rowOffsets(), zoom: zoomScale)
    let zoom = zoomScale
    let palette = paletteResolvedOnMainThread()
    let dark = palette.isDark
    let background = resolvedDrawColor(palette.canvas)
    let grid = resolvedDrawColor(palette.gridLine)
    let headerLine = grid
    let headerFill = resolvedDrawColor(palette.chrome)
    let headerText = resolvedDrawColor(palette.secondaryLabel)
    let merges = MergeLookup(ranges: sheet.mergedRanges)
    let sheetID = sheet.id
    let contentRevision = viewModel.contentRevision
    advanceTileCalcGeneration()
    tileValues.queue.sync {
      if self.tileValues.preparedContentRevision != contentRevision {
        self.tileValues.engine = FormulaEngine()
        self.tileValues.engine.activateSheet(workbook)
        self.tileValues.paintCache.removeAll(keepingCapacity: true)
        self.tileValues.rangeValueCache.removeAll(keepingCapacity: true)
        self.tileValues.sheetID = sheetID
        self.tileValues.preparedContentRevision = contentRevision
      } else if self.tileValues.sheetID != sheetID {
        self.tileValues.engine.activateSheet(workbook)
        self.tileValues.paintCache.removeAll(keepingCapacity: true)
        self.tileValues.rangeValueCache.removeAll(keepingCapacity: true)
        self.tileValues.sheetID = sheetID
      }
      self.tileValues.sheet = sheet
      self.tileValues.columnOffsets = columns
      self.tileValues.rowOffsets = rows
      self.tileValues.zoom = zoom
      self.tileValues.isDarkMode = dark
      self.tileValues.resolvedPalette = palette
      self.tileValues.windowBackground = background
      self.tileValues.gridLine = grid
      self.tileValues.headerLine = headerLine
      self.tileValues.headerFill = headerFill
      self.tileValues.headerText = headerText
      self.tileValues.mergeLookup = merges
      self.tileValues.calculatedResults = viewModel.formulaEngine.snapshotCalculatedResults()
    }
  }

  private func enqueueTileValueRender(
    pane: ScrollTilePane,
    indexX: Int,
    indexY: Int,
    spec: ScrollTileSpec,
    viewRect: NSRect,
    contentOrigin: CGPoint,
    requestedAt: CFAbsoluteTime,
    notifyMain: Bool = false
  ) {
    let scroll = CGPoint(
      x: spec.scrollsX ? contentOrigin.x : scrollOrigin.x,
      y: spec.scrollsY ? contentOrigin.y : scrollOrigin.y
    )
    let override = contentRect(coveringScrollable: viewRect)
    let generation = tileCaptureGeneration
    let scale = rasterScale
    let target = spec.target
    let workbook = viewModel?.workbook
    let contentRevision = viewModel?.contentRevision ?? -1
    let group = tileValueRenderGroup
    group.enter()
    // Snapshot after any workbook update already queued on this same queue.
    tileValues.queue.async { [weak self] in
      guard let self, let sheet = self.tileValues.sheet else {
        group.leave()
        return
      }
      let columns = self.tileValues.columnOffsets
      let rowList = self.tileValues.rowOffsets
      let zoom = self.tileValues.zoom
      let dark = self.tileValues.isDarkMode
      let palette = self.tileValues.resolvedPalette
      let background = self.tileValues.windowBackground
      let grid = self.tileValues.gridLine
      let headerLine = self.tileValues.headerLine
      let headerFill = self.tileValues.headerFill
      let headerText = self.tileValues.headerText
      let merges = self.tileValues.mergeLookup
      let calculatedResults = self.tileValues.calculatedResults
      let calcGeneration = self.currentTileCalcGeneration()
      self.tileRenderPool.async {
        defer { group.leave() }
        let worker = self.borrowTileWorker()
        defer { self.returnTileWorker(worker) }
        self.prepareTileWorker(
          worker,
          sheet: sheet,
          columns: columns,
          rows: rowList,
          zoom: zoom,
          dark: dark,
          palette: palette,
          background: background,
          grid: grid,
          headerLine: headerLine,
          headerFill: headerFill,
          headerText: headerText,
          merges: merges,
          calculatedResults: calculatedResults,
          generation: calcGeneration,
          contentRevision: contentRevision,
          workbook: workbook
        )
        self.renderTileFromValues(
          session: worker,
          pane: pane,
          indexX: indexX,
          indexY: indexY,
          viewRect: viewRect,
          scroll: scroll,
          contentOverride: override,
          target: target,
          scale: scale,
          generation: generation,
          requestedAt: requestedAt,
          notifyMain: notifyMain
        )
      }
    }
  }

  private func borrowTileWorker() -> TileValueSession {
    tileWorkerLock.lock()
    if let worker = tileWorkers.popLast() {
      tileWorkerLock.unlock()
      return worker
    }
    tileWorkerLock.unlock()
    return TileValueSession()
  }

  private func returnTileWorker(_ worker: TileValueSession) {
    tileWorkerLock.lock()
    tileWorkers.append(worker)
    tileWorkerLock.unlock()
  }

  private func prepareTileWorker(
    _ worker: TileValueSession,
    sheet: Sheet,
    columns: [CGFloat],
    rows: [CGFloat],
    zoom: CGFloat,
    dark: Bool,
    palette: SparkTheme.Palette?,
    background: NSColor,
    grid: NSColor,
    headerLine: NSColor,
    headerFill: NSColor,
    headerText: NSColor,
    merges: MergeLookup?,
    calculatedResults: [String: [CellAddress: CellValue]],
    generation: Int,
    contentRevision: Int,
    workbook: Workbook?
  ) {
    if worker.preparedGeneration != generation {
      worker.paintCache.removeAll(keepingCapacity: true)
      worker.rangeValueCache.removeAll(keepingCapacity: true)
      if let workbook {
        if worker.preparedContentRevision != contentRevision {
          worker.engine = FormulaEngine()
          worker.preparedContentRevision = contentRevision
        }
        worker.engine.activateSheet(workbook)
      }
      worker.preparedGeneration = generation
    }
    worker.sheet = sheet
    worker.sheetID = sheet.id
    worker.columnOffsets = columnOffsetsCovering(sheet, existing: columns, zoom: zoom)
    worker.rowOffsets = rowOffsetsCovering(sheet, existing: rows, zoom: zoom)
    worker.zoom = zoom
    worker.isDarkMode = dark
    worker.resolvedPalette = palette
    worker.windowBackground = background
    worker.gridLine = grid
    worker.headerLine = headerLine
    worker.headerFill = headerFill
    worker.headerText = headerText
    worker.mergeLookup = merges
    if !calculatedResults.isEmpty {
      worker.engine.installCalculatedResults(calculatedResults)
    }
  }

  private func renderTileFromValues(
    session: TileValueSession,
    pane: ScrollTilePane,
    indexX: Int,
    indexY: Int,
    viewRect: NSRect,
    scroll: CGPoint,
    contentOverride: NSRect?,
    target: RasterTarget,
    scale: CGFloat,
    generation: Int,
    requestedAt: CFAbsoluteTime,
    notifyMain: Bool = false
  ) {
    guard session.sheet != nil else { return }
    let drawingPalette = session.resolvedPalette ?? SparkTheme.fallbackPalette
    SparkTheme.adoptResolvedPalette(drawingPalette)
    defer { SparkTheme.adoptResolvedPalette(nil) }
    let state = TileCaptureState(
      session: session, scroll: scroll, contentOverride: contentOverride)
    setTileCapture(state)
    defer { setTileCapture(nil) }
    let recordPhases = testingRecordTilePhases
    let valueStarted = recordPhases ? CFAbsoluteTimeGetCurrent() : 0
    prepareCapturedTileValues()
    let valueSeconds = recordPhases ? CFAbsoluteTimeGetCurrent() - valueStarted : 0
    let drawStarted = recordPhases ? CFAbsoluteTimeGetCurrent() : 0
    let list = collectTileDrawList(
      viewRect: viewRect,
      scroll: scroll,
      contentOverride: contentOverride,
      target: target
    )
    let drawSeconds = recordPhases ? CFAbsoluteTimeGetCurrent() - drawStarted : 0
    let imageStarted = recordPhases ? CFAbsoluteTimeGetCurrent() : 0
    guard let image = list.renderImage(scale: scale) else { return }
    if recordPhases {
      noteSlowestTile(
        value: valueSeconds,
        draw: drawSeconds,
        image: CFAbsoluteTimeGetCurrent() - imageStarted
      )
    }
    let rendered = RenderedTileImage(
      pane: pane,
      x: indexX,
      y: indexY,
      image: image,
      generation: generation,
      requestedAt: requestedAt
    )
    renderedTileImages.lock.lock()
    renderedTileImages.images.append(rendered)
    renderedTileImages.lock.unlock()
    guard notifyMain else { return }
    DispatchQueue.main.async { [weak self] in
      self?.installBackgroundTileImages()
    }
  }

  /// Calculate the cells this tile will draw, before the draw commands are recorded.
  private func prepareCapturedTileValues() {
    guard let sheet = sheetForLayout() else { return }
    for rows in visibleRowSpans() {
      for cols in visibleColumnSpans() {
        for row in rows {
          for col in cols {
            let address = CellAddress(row: row, col: col)
            let role = mergeRole(at: address, sheet: sheet)
            if case .covered = role { continue }
            let hasCell = sheet.cells[address] != nil
            if !hasCell, case .none = role, !sheet.tableContains(address) { continue }
            let cell = sheet.cell(at: address)
            _ = cachedCellPaint(at: address, viewModel: nil, sheet: sheet, cell: cell)
          }
        }
      }
    }
  }

  private func addRasterScrollTile(
    pane: ScrollTilePane,
    indexX: Int,
    indexY: Int,
    spec: ScrollTileSpec
  ) {
    let viewRect = scrollTileViewRect(spec)
    guard viewRect.width > 1, viewRect.height > 1 else { return }
    let contentOrigin = scrollTileContentOrigin(indexX: indexX, indexY: indexY, spec: spec)
    let scroll = CGPoint(
      x: spec.scrollsX ? contentOrigin.x : scrollOrigin.x,
      y: spec.scrollsY ? contentOrigin.y : scrollOrigin.y
    )
    let override = contentRect(coveringScrollable: viewRect)
    prepareValuesCovering(viewRect: viewRect, scroll: scroll, contentOverride: override)
    let list = collectTileDrawList(
      viewRect: viewRect,
      scroll: scroll,
      contentOverride: override,
      target: spec.target
    )
    guard let placeholder = gridlinePlaceholder(size: viewRect.size) else { return }
    appendScrollTile(
      pane: pane,
      indexX: indexX,
      indexY: indexY,
      spec: spec,
      image: placeholder,
      viewRect: viewRect,
      contentOrigin: contentOrigin,
      placeholder: true
    )
    let scale = rasterScale
    let box = renderedTileImages
    let group = tileRenderGroup
    let drawingPalette = paletteResolvedOnMainThread()
    group?.enter()
    scrollTileRenderQueue.async {
      SparkTheme.adoptResolvedPalette(drawingPalette)
      defer { SparkTheme.adoptResolvedPalette(nil) }
      let image = list.renderImage(scale: scale)
      if let image {
        box.lock.lock()
        box.images.append(
          RenderedTileImage(
            pane: pane, x: indexX, y: indexY, image: image, generation: 0, requestedAt: 0))
        box.lock.unlock()
      }
      group?.leave()
    }
  }

  private func addPlaceholderScrollTile(
    pane: ScrollTilePane,
    indexX: Int,
    indexY: Int,
    spec: ScrollTileSpec
  ) {
    let viewRect = scrollTileViewRect(spec)
    guard viewRect.width > 1, viewRect.height > 1 else { return }
    let contentOrigin = scrollTileContentOrigin(indexX: indexX, indexY: indexY, spec: spec)
    if let cached = cachedTileImage(pane: pane, x: indexX, y: indexY) {
      appendScrollTile(
        pane: pane,
        indexX: indexX,
        indexY: indexY,
        spec: spec,
        image: cached,
        viewRect: viewRect,
        contentOrigin: contentOrigin,
        placeholder: false
      )
      return
    }
    // A tile already on screen is drawn now from the values this view has. A gridline
    // placeholder there filled in a beat later, block by block, while the sheet scrolled.
    if let image = drawVisibleTileNow(
      pane: pane, spec: spec, viewRect: viewRect, contentOrigin: contentOrigin)
    {
      appendScrollTile(
        pane: pane,
        indexX: indexX,
        indexY: indexY,
        spec: spec,
        image: image,
        viewRect: viewRect,
        contentOrigin: contentOrigin,
        placeholder: false
      )
      rememberTileImage(pane: pane, x: indexX, y: indexY, image: image)
      return
    }
    guard let image = gridlinePlaceholder(size: viewRect.size) else { return }
    let requestedAt = CFAbsoluteTimeGetCurrent()
    appendScrollTile(
      pane: pane,
      indexX: indexX,
      indexY: indexY,
      spec: spec,
      image: image,
      viewRect: viewRect,
      contentOrigin: contentOrigin,
      placeholder: true,
      requestedAt: requestedAt
    )
    enqueueTileValueRender(
      pane: pane,
      indexX: indexX,
      indexY: indexY,
      spec: spec,
      viewRect: viewRect,
      contentOrigin: contentOrigin,
      requestedAt: requestedAt,
      notifyMain: true
    )
  }

  /// The tile's image when it is on screen and this frame still has drawing time; otherwise nil.
  private func drawVisibleTileNow(
    pane: ScrollTilePane,
    spec: ScrollTileSpec,
    viewRect: NSRect,
    contentOrigin: CGPoint
  ) -> NSImage? {
    guard tileCapture == nil, rasterTarget == nil,
      viewModel?.formulaEngine.paintsStoredResultsOnly != true,
      CFAbsoluteTimeGetCurrent() < visibleTileDrawDeadline
    else { return nil }
    let frame = NSRect(
      x: spec.scrollsX ? contentOrigin.x - scrollOrigin.x : 0,
      y: spec.scrollsY ? contentOrigin.y - scrollOrigin.y : 0,
      width: viewRect.width,
      height: viewRect.height
    )
    let visible = scrollTileClip(pane).bounds.intersection(frame)
    guard visible.width >= 0.5, visible.height >= 0.5 else { return nil }
    let scroll = CGPoint(
      x: spec.scrollsX ? contentOrigin.x : scrollOrigin.x,
      y: spec.scrollsY ? contentOrigin.y : scrollOrigin.y
    )
    let override = contentRect(coveringScrollable: viewRect)
    prepareValuesCovering(viewRect: viewRect, scroll: scroll, contentOverride: override)
    let list = collectTileDrawList(
      viewRect: viewRect,
      scroll: scroll,
      contentOverride: override,
      target: spec.target
    )
    return list.renderImage(scale: rasterScale)
  }

  private func appendScrollTile(
    pane: ScrollTilePane,
    indexX: Int,
    indexY: Int,
    spec: ScrollTileSpec,
    image: NSImage,
    viewRect: NSRect,
    contentOrigin: CGPoint,
    placeholder: Bool,
    requestedAt: CFAbsoluteTime = 0
  ) {
    let view = ScrollTileView(frame: .zero)
    view.wantsLayer = true
    view.layerContentsRedrawPolicy = .onSetNeedsDisplay
    view.image = image
    var record = ScrollTileRecord(
      pane: pane,
      indexX: indexX,
      indexY: indexY,
      scrollsX: spec.scrollsX,
      scrollsY: spec.scrollsY,
      contentOrigin: contentOrigin,
      viewRect: viewRect,
      image: image,
      placeholder: placeholder,
      requestedAt: requestedAt,
      view: view
    )
    view.frame = scrollTileFrame(record)
    scrollTileClip(pane).addSubview(view)
    let visible = scrollTileClip(pane).bounds.intersection(view.frame)
    if visible.width >= 0.5, visible.height >= 0.5 {
      view.needsDisplay = true
      view.display()
      record.layerReady = true
    }
    scrollTiles.append(record)
  }

  private func noteScrollVelocity(_ delta: CGPoint) {
    lastScrollDelta = delta
    let now = CFAbsoluteTimeGetCurrent()
    let previous = lastScrollTime
    lastScrollTime = now
    guard previous > 0 else { return }
    let dt = now - previous
    guard dt > 0.0001, dt < 0.5 else {
      scrollVelocity = .zero
      return
    }
    scrollVelocity = CGPoint(x: delta.x / dt, y: delta.y / dt)
  }

  private func cachedTileImage(pane: ScrollTilePane, x: Int, y: Int) -> NSImage? {
    let key = TileImageKey(pane: pane, x: x, y: y)
    guard let entry = tileImageCache[key] else { return nil }
    tileCacheClock &+= 1
    var updated = entry
    updated.used = tileCacheClock
    tileImageCache[key] = updated
    return entry.image
  }

  private func rememberTileImage(pane: ScrollTilePane, x: Int, y: Int, image: NSImage) {
    let key = TileImageKey(pane: pane, x: x, y: y)
    let bytes = tileImageBytes(image)
    if let existing = tileImageCache[key] {
      tileCacheBytes = tileCacheBytes > existing.bytes ? tileCacheBytes - existing.bytes : 0
    }
    tileCacheClock &+= 1
    tileImageCache[key] = TileImageEntry(image: image, bytes: bytes, used: tileCacheClock)
    if tileCacheBytes > Int.max - bytes {
      tileCacheBytes = Int.max
    } else {
      tileCacheBytes += bytes
    }
    evictTileImages()
  }

  private func tileImageBytes(_ image: NSImage) -> Int {
    var bytes = 0
    for rep in image.representations {
      guard let bitmap = rep as? NSBitmapImageRep else { continue }
      let rows = bitmap.pixelsHigh
      let rowBytes = bitmap.bytesPerRow
      guard rows > 0, rowBytes > 0, rowBytes <= Int.max / rows else { continue }
      let area = rowBytes * rows
      if bytes > Int.max - area { return Int.max }
      bytes += area
    }
    if bytes > 0 { return bytes }
    let width = max(1, Int((image.size.width * 2).rounded(.up)))
    let height = max(1, Int((image.size.height * 2).rounded(.up)))
    guard width <= Int.max / height else { return Self.tileCacheByteCap }
    let pixels = width * height
    guard pixels <= Int.max / 4 else { return Self.tileCacheByteCap }
    return pixels * 4
  }

  private func evictTileImages() {
    while tileCacheBytes > Self.tileCacheByteCap {
      var oldestKey: TileImageKey?
      var oldestUsed = UInt64.max
      for (key, entry) in tileImageCache {
        if scrollTileIsVisible(pane: key.pane, x: key.x, y: key.y) { continue }
        if entry.used < oldestUsed {
          oldestUsed = entry.used
          oldestKey = key
        }
      }
      guard let key = oldestKey, let entry = tileImageCache.removeValue(forKey: key) else {
        return
      }
      tileCacheBytes = tileCacheBytes > entry.bytes ? tileCacheBytes - entry.bytes : 0
      removeScrollTileView(pane: key.pane, x: key.x, y: key.y)
    }
  }

  private func scrollTileIsVisible(pane: ScrollTilePane, x: Int, y: Int) -> Bool {
    guard
      let tile = scrollTiles.first(where: {
        $0.pane == pane && $0.indexX == x && $0.indexY == y
      })
    else { return false }
    let visible = scrollTileClip(pane).bounds.intersection(tile.view.frame)
    return visible.width >= 0.5 && visible.height >= 0.5
  }

  private func removeScrollTileView(pane: ScrollTilePane, x: Int, y: Int) {
    guard
      let index = scrollTiles.firstIndex(where: {
        $0.pane == pane && $0.indexX == x && $0.indexY == y
      })
    else { return }
    if scrollTileIsVisible(pane: pane, x: x, y: y) { return }
    scrollTiles[index].view.removeFromSuperview()
    scrollTiles.remove(at: index)
  }

  private func gridlinePlaceholder(size: NSSize) -> NSImage? {
    let key = "\(Int(size.width.rounded()))x\(Int(size.height.rounded()))"
    if let cached = gridlinePlaceholderCache[key] { return cached }
    let image = renderManual(viewRect: NSRect(origin: .zero, size: size)) {
      theme.canvas.setFill()
      NSRect(origin: .zero, size: size).fill()
      self.gridLineColor().setStroke()
      let rowPitch = Self.defaultRowHeight
      let columnPitch = Self.defaultColumnWidth
      var y = rowPitch
      while y < size.height {
        NSBezierPath.strokeLine(from: NSPoint(x: 0, y: y), to: NSPoint(x: size.width, y: y))
        y += rowPitch
      }
      var x = columnPitch
      while x < size.width {
        NSBezierPath.strokeLine(from: NSPoint(x: x, y: 0), to: NSPoint(x: x, y: size.height))
        x += columnPitch
      }
    }
    guard let placeholder = image else { return nil }
    gridlinePlaceholderCache[key] = placeholder
    return placeholder
  }

  private func bitmapMismatchCount(_ lhs: NSImage, _ rhs: NSImage) -> Int {
    guard abs(lhs.size.width - rhs.size.width) < 0.5,
      abs(lhs.size.height - rhs.size.height) < 0.5
    else { return 1_000_000 }
    guard let left = drawnBitmap(lhs), let right = drawnBitmap(rhs) else { return 1_000_000 }
    guard left.pixelsWide == right.pixelsWide, left.pixelsHigh == right.pixelsHigh,
      left.samplesPerPixel >= 4, right.samplesPerPixel >= 4,
      let leftBytes = left.bitmapData, let rightBytes = right.bitmapData
    else { return 1_000_000 }
    let width = left.pixelsWide
    let height = left.pixelsHigh
    guard width > 0, height > 0 else { return 1_000_000 }
    let leftPixel = left.bitsPerPixel / 8
    let rightPixel = right.bitsPerPixel / 8
    guard leftPixel >= 4, rightPixel >= 4 else { return 1_000_000 }
    var mismatches = 0
    var y = 0
    while y < height {
      var x = 0
      while x < width {
        let leftOffset = y * left.bytesPerRow + x * leftPixel
        let rightOffset = y * right.bytesPerRow + x * rightPixel
        let leftLimit = left.bytesPerRow * height
        let rightLimit = right.bytesPerRow * height
        if leftOffset < 0 || rightOffset < 0 || leftOffset + 3 >= leftLimit
          || rightOffset + 3 >= rightLimit
        {
          x += 16
          continue
        }
        var channel = 0
        while channel < 4 {
          let leftSample = Int(leftBytes[leftOffset + channel])
          let rightSample = Int(rightBytes[rightOffset + channel])
          if abs(leftSample - rightSample) > 8 {
            mismatches += 1
            break
          }
          channel += 1
        }
        x += 16
      }
      y += 16
    }
    return mismatches
  }

  private func drawnBitmap(_ image: NSImage) -> NSBitmapImageRep? {
    let size = image.size
    let pixelsWide = max(1, Int(size.width.rounded(.up)))
    let pixelsHigh = max(1, Int(size.height.rounded(.up)))
    guard
      let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelsWide,
        pixelsHigh: pixelsHigh,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
      )
    else { return nil }
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    context.imageInterpolation = .none
    NSGraphicsContext.current = context
    image.draw(
      in: NSRect(origin: .zero, size: size),
      from: NSRect(origin: .zero, size: image.size),
      operation: .copy,
      fraction: 1,
      respectFlipped: false,
      hints: [.interpolation: NSImageInterpolation.none]
    )
    return rep
  }

  /// Move already-rasterized panes. A miss blits the nearest tile and builds the
  /// real region after this frame. Returns false only when there is no tile yet.
  private func applyScrollSurfaces() -> Bool {
    guard viewModel != nil, bounds.width > 2, bounds.height > 2 else { return false }
    isAdjustingScrollSurfaces = true
    defer { isAdjustingScrollSurfaces = false }

    let key = scrollPlaneKey()
    let bodyPaneRect = scrollableCellsClipRect()
    let columnPane = scrollingColumnHeaderPane()
    let rowPane = scrollingRowHeaderPane()
    guard
      let body = planeForBlit(in: bodyPlanes, key: key, scroll: scrollOrigin, pane: bodyPaneRect),
      let columns = planeForBlit(
        in: columnHeaderPlanes, key: key, scroll: scrollOrigin, pane: columnPane),
      let rows = planeForBlit(in: rowHeaderPlanes, key: key, scroll: scrollOrigin, pane: rowPane)
    else {
      hideScrollSurfaces()
      return false
    }
    let topPane = frozenTopStripClipRect()
    let leftPane = frozenLeftStripClipRect()
    let cornerPane = frozenCellsClipRect()
    let corner =
      frozenRowCount() > 0 && frozenColumnCount() > 0 && cornerPane.width > 1
      ? planeForBlit(in: frozenCornerPlanes, key: key, scroll: scrollOrigin, pane: cornerPane)
      : nil
    let top =
      frozenRowCount() > 0 && topPane.height > 1
      ? planeForBlit(in: frozenTopPlanes, key: key, scroll: scrollOrigin, pane: topPane)
      : nil
    let left =
      frozenColumnCount() > 0 && leftPane.width > 1
      ? planeForBlit(in: frozenLeftPlanes, key: key, scroll: scrollOrigin, pane: leftPane)
      : nil
    if frozenRowCount() > 0, topPane.height > 1, top == nil {
      hideScrollSurfaces()
      return false
    }
    if frozenColumnCount() > 0, leftPane.width > 1, left == nil {
      hideScrollSurfaces()
      return false
    }
    if frozenRowCount() > 0, frozenColumnCount() > 0, cornerPane.width > 1, corner == nil {
      hideScrollSurfaces()
      return false
    }

    installScrollClip(bodyScrollClip, plane: body, frame: bodyPaneRect, superview: self)
    installScrollClip(columnHeaderScrollClip, plane: columns, frame: columnPane, superview: self)
    installScrollClip(rowHeaderScrollClip, plane: rows, frame: rowPane, superview: self)
    installFrozenScrollClips((corner: corner, top: top, left: left))
    scrollSurfacesPresented = true
    needsDisplay = false
    displayPinnedMergeText()
    displaySelectionChrome()
    scheduleOffFrameScrollBuild()
    return true
  }

  private func installScrollClip(
    _ clip: ScrollClipView,
    plane: ScrollPlane,
    frame: NSRect,
    superview: NSView
  ) {
    if clip.superview !== superview {
      superview.addSubview(clip)
    }
    if clip.frame != frame {
      clip.frame = frame
    }
    if superview !== self {
      superview.clipsToBounds = true
    }
    clip.layer?.backgroundColor = theme.canvas.cgColor
    placeScrollSurface(clip, plane: plane)
    showScrollImage(clip, image: plane.cells)
  }

  private func installFrozenScrollClips(
    _ frozen: (corner: ScrollPlane?, top: ScrollPlane?, left: ScrollPlane?)
  ) {
    frozenCornerScrollClip.isHidden = true
    frozenTopScrollClip.isHidden = true
    frozenLeftScrollClip.isHidden = true
    guard frozenRowCount() > 0 || frozenColumnCount() > 0 else { return }
    layoutOnSheetCharts()
    if frozenRowCount() > 0, let overlay = frozenPaneOverlays.first, !overlay.isHidden,
      overlay.bounds.height > 1
    {
      let cornerW = frozenColumnCount() > 0 ? max(0, frozenColumnBoundaryX() - contentRect.minX) : 0
      if let corner = frozen.corner, cornerW > 1 {
        installScrollClip(
          frozenCornerScrollClip,
          plane: corner,
          frame: NSRect(x: 0, y: 0, width: cornerW, height: overlay.bounds.height),
          superview: overlay
        )
      }
      if let top = frozen.top {
        installScrollClip(
          frozenTopScrollClip,
          plane: top,
          frame: NSRect(
            x: cornerW,
            y: 0,
            width: max(0, overlay.bounds.width - cornerW),
            height: overlay.bounds.height
          ),
          superview: overlay
        )
      }
    }
    if frozenColumnCount() > 0, let left = frozen.left {
      let index = frozenRowCount() > 0 ? 1 : 0
      let overlay = frozenPaneOverlays[index]
      guard !overlay.isHidden, overlay.bounds.width > 1, overlay.bounds.height > 1 else { return }
      installScrollClip(
        frozenLeftScrollClip, plane: left, frame: overlay.bounds, superview: overlay)
    }
  }

  private func showScrollImage(_ clip: ScrollClipView, image: NSImage) {
    clip.isHidden = false
    guard clip.surface.image !== image else { return }
    clip.surface.image = image
    clip.surface.needsDisplay = true
    clip.surface.display()
  }

  private func placeScrollSurface(_ clip: ScrollClipView, plane: ScrollPlane) {
    let paneInGrid = clip.convert(clip.bounds, to: self)
    let dest = plane.destination(scroll: scrollOrigin)
    let local = NSRect(
      x: dest.minX - paneInGrid.minX,
      y: dest.minY - paneInGrid.minY,
      width: plane.viewRect.width,
      height: plane.viewRect.height
    )
    if clip.surface.frame != local {
      clip.surface.frame = local
    }
  }

  override func display() {
    if limitPaintTo == nil {
      prepareViewportValues()
    }
    super.display()
    // An offscreen window can skip drawing. Seed the frame bitmap so the next
    // edit does not have to repaint every visible cell.
    if frameBitmap == nil, limitPaintTo == nil, bounds.width > 1, bounds.height > 1 {
      draw(bounds)
    }
    scheduleViewportTileWarm()
  }

  override func display(_ rect: NSRect) {
    testingInvalidateReason += " displayRect"
    if limitPaintTo == nil {
      prepareViewportValues()
    }
    super.display(rect)
  }

  override func displayIfNeeded() {
    // A layer-backed subview, such as a chart, can mark this layer dirty without
    // the view needing to repaint cells. Drawing then would walk every visible cell.
    if !needsDisplay, limitPaintTo == nil {
      for subview in subviews where subview.needsDisplay {
        subview.displayIfNeeded()
      }
      return
    }
    if limitPaintTo == nil {
      prepareViewportValues()
    }
    super.displayIfNeeded()
    limitPaintTo = nil
  }

  /// Calculate the cells this paint will show. Drawing then reads that cache.
  private func prepareViewportValues() {
    guard !isPreparingPaintValues, rasterTarget == nil, let viewModel else { return }
    isPreparingPaintValues = true
    viewportPaintOverscan = true
    beginDrawLayout()
    defer {
      endDrawLayout()
      viewportPaintOverscan = false
      isPreparingPaintValues = false
    }
    guard let sheet = layoutSheet else { return }
    let clip = contentRect.union(bounds)
    for rows in visibleRowSpans() {
      for cols in visibleColumnSpans() {
        for row in rows {
          for col in cols {
            let address = CellAddress(row: row, col: col)
            let role = mergeRole(at: address, sheet: sheet)
            if case .covered = role { continue }
            let hasCell = sheet.cells[address] != nil
            if !hasCell, case .none = role, !sheet.tableContains(address) { continue }
            let merge = mergeRange(from: role)
            guard let rect = paintRect(for: address, merge: merge), clip.intersects(rect) else {
              continue
            }
            let cell = sheet.cell(at: address)
            _ = cachedCellPaint(at: address, viewModel: viewModel, sheet: sheet, cell: cell)
          }
        }
      }
    }
  }

  private func mergeRange(from role: MergeRole) -> CellRange? {
    if case .anchor(let range) = role { return range }
    return nil
  }

  private func prepareValuesCovering(viewRect: NSRect, scroll: CGPoint, contentOverride: NSRect?) {
    let savedScroll = scrollOrigin
    let savedOverride = contentRectOverride
    scrollOrigin = scroll
    contentRectOverride = contentOverride
    defer {
      scrollOrigin = savedScroll
      contentRectOverride = savedOverride
    }
    prepareViewportValues()
  }

  private var isPreparingPaintValues = false

  /// A view context whose x scale is larger than its y scale paints columns on
  /// the wrong header and leaves the selection overlay, drawn in its own context,
  /// on the model column. Text keeps the font's height, so the letter looks
  /// normal while its cell is twice as wide. Square the scale for this draw.
  private func flattenHorizontalScaleIfNeeded(_ context: NSGraphicsContext?) -> Bool {
    guard let cg = context?.cgContext else { return false }
    let sx = abs(cg.ctm.a)
    let sy = abs(cg.ctm.d)
    guard sx > 0.01, sy > 0.01, sx > sy * 1.5 else { return false }
    cg.saveGState()
    cg.scaleBy(x: sy / sx, y: 1)
    return true
  }

  override func draw(_ dirtyRect: NSRect) {
    if testingSkipDraw { return }
    if alignBoundsWithFrame() {
      if !didRequestBoundsRedraw {
        didRequestBoundsRedraw = true
        needsDisplay = true
        return
      }
    } else {
      didRequestBoundsRedraw = false
    }
    let viewGraphicsContext = NSGraphicsContext.current
    let flattenedScale = flattenHorizontalScaleIfNeeded(viewGraphicsContext)
    defer {
      if flattenedScale {
        viewGraphicsContext?.cgContext.restoreGState()
      }
    }
    // Tiles already show the cells. Painting them again here walks every
    // conditional range on the main thread while a jump is waiting to install.
    if scrollTilesPresented, rasterTarget == nil, limitPaintTo == nil {
      let started = CFAbsoluteTimeGetCurrent()
      inGridDraw = true
      testingGridDraws += 1
      beginDrawLayout()
      theme.canvas.setFill()
      dirtyRect.fill()
      drawStickyHeaders(in: dirtyRect)
      drawFreezeDividers(in: dirtyRect)
      drawHeaderCorner(in: dirtyRect)
      endDrawLayout()
      inGridDraw = false
      noteMainStall(CFAbsoluteTimeGetCurrent() - started)
      return
    }
    inGridDraw = true
    testingGridDraws += 1
    testingInvalidateReason +=
      " draw \(Int(dirtyRect.width))x\(Int(dirtyRect.height)) needs \(needsDisplay)"
    defer { inGridDraw = false }
    // The offscreen frame is copied to the screen scaled to the view. After a resize the old
    // one stretched every letter and line sideways, so a frame of the wrong size is dropped
    // and this draw paints everything into a new one.
    if let bitmap = frameBitmap, !frameBitmapFitsBounds(bitmap) {
      frameBitmap = nil
      limitPaintTo = nil
    }
    if let limited = limitPaintTo {
      if frameBitmap == nil {
        _ = ensureFrameBitmap()
      }
      if let bitmap = frameBitmap {
        testingInvalidateReason += " bitmap true"
        let viewContext = NSGraphicsContext.current
        let nested = isDrawingFrameBitmap
        if !nested {
          isDrawingFrameBitmap = true
          NSGraphicsContext.current = NSGraphicsContext(cgContext: bitmap, flipped: true)
        }
        beginDrawLayout()
        drawLimitedCells(limited, in: bounds)
        endDrawLayout()
        if !nested {
          isDrawingFrameBitmap = false
          NSGraphicsContext.current = viewContext
          blitFrameBitmap(to: viewContext)
        }
        return
      }
      testingInvalidateReason += " bitmap false"
    }
    let viewContext = NSGraphicsContext.current
    if frameBitmap == nil, rasterTarget == nil {
      _ = ensureFrameBitmap()
    }
    let drawIntoBitmap = rasterTarget == nil && frameBitmap != nil && !isDrawingFrameBitmap
    if drawIntoBitmap, let bitmap = frameBitmap {
      isDrawingFrameBitmap = true
      NSGraphicsContext.current = NSGraphicsContext(cgContext: bitmap, flipped: true)
    }
    beginDrawLayout()
    viewportPaintOverscan = rasterTarget == nil
    defer {
      viewportPaintOverscan = false
      endDrawLayout()
      if drawIntoBitmap {
        isDrawingFrameBitmap = false
        NSGraphicsContext.current = viewContext
        blitFrameBitmap(to: viewContext)
      }
    }
    if let target = rasterTarget {
      drawRasterStack(target, in: dirtyRect)
      return
    }

    if scrollSurfacesPresented, !rectOverlapsCellArea(dirtyRect) {
      theme.chrome.setFill()
      dirtyRect.fill()
      drawStickyHeaders(in: dirtyRect)
      drawHeaderCorner(in: dirtyRect)
      return
    }

    theme.canvas.setFill()
    dirtyRect.fill()

    // The visible rows and columns, plus a small overscan, from the cell store.
    // A scroll frame takes this path and does not wait on a region bitmap.
    let skipGridlines = visibleRegionIsMostlyBordered()
    if let ctx = NSGraphicsContext.current {
      ctx.saveGraphicsState()
      NSBezierPath(rect: contentRect).addClip()
      drawCells(in: dirtyRect)
      if !skipGridlines {
        drawGridLines(in: dirtyRect)
      }
      drawScrollableOverflowText(in: dirtyRect)
      ctx.restoreGraphicsState()
    }

    // Frozen panes sit above scrolled cells. Subviews paint after this, so the
    // chart layer still covers these cells. Pane-sized overlays paint them again
    // above the chart — not a full-grid clear.
    if frozenRowCount() > 0 || frozenColumnCount() > 0, let ctx = NSGraphicsContext.current {
      ctx.saveGraphicsState()
      NSBezierPath(rect: contentRect).addClip()
      fillFrozenPaneBackgrounds(in: dirtyRect)
      drawFrozenCells(in: dirtyRect)
      if !skipGridlines {
        drawFrozenGridLines(in: dirtyRect)
      }
      drawFrozenOverflowText(in: dirtyRect)
      ctx.restoreGraphicsState()
    }

    // Pictures float above cell fills and gridlines (scrollable + frozen).
    if let ctx = NSGraphicsContext.current {
      ctx.saveGraphicsState()
      NSBezierPath(rect: contentRect).addClip()
      drawImages(in: dirtyRect)
      ctx.restoreGraphicsState()
    }

    // Opaque header gutters so scrolled cells cannot bleed into labels.
    theme.chrome.setFill()
    if dirtyRect.intersects(NSRect(x: 0, y: 0, width: bounds.width, height: headerSize)) {
      NSRect(x: 0, y: 0, width: bounds.width, height: headerSize).fill()
    }
    if dirtyRect.intersects(NSRect(x: 0, y: 0, width: headerSize, height: bounds.height)) {
      NSRect(x: 0, y: 0, width: headerSize, height: bounds.height).fill()
    }

    drawStickyHeaders(in: dirtyRect)
    drawFreezeDividers(in: dirtyRect)
    drawHeaderCorner(in: dirtyRect)
  }

  private func frameBitmapFitsBounds(_ bitmap: CGContext) -> Bool {
    let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    return bitmap.width == max(1, Int((bounds.width * scale).rounded(.up)))
      && bitmap.height == max(1, Int((bounds.height * scale).rounded(.up)))
  }

  private func ensureFrameBitmap() -> CGContext? {
    let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    let width = max(1, Int((bounds.width * scale).rounded(.up)))
    let height = max(1, Int((bounds.height * scale).rounded(.up)))
    if let frameBitmap, frameBitmap.width == width, frameBitmap.height == height {
      return frameBitmap
    }
    guard
      let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
          | CGBitmapInfo.byteOrder32Little.rawValue
      )
    else { return nil }
    context.scaleBy(x: scale, y: scale)
    frameBitmap = context
    testingFrameStores += 1
    return context
  }

  private func blitFrameBitmap(to context: NSGraphicsContext?) {
    guard let frameBitmap, let image = frameBitmap.makeImage(), let context else { return }
    let cg = context.cgContext
    cg.saveGState()
    cg.interpolationQuality = .none
    cg.draw(image, in: bounds)
    cg.restoreGState()
  }

  private enum GridLineRegion {
    case scrollable
    case frozenCorner
    case frozenTop
    case frozenLeft
  }

  private func columnIncludedInGridLines(_ col: Int, region: GridLineRegion, frozenCols: Int)
    -> Bool
  {
    switch region {
    case .scrollable: col >= frozenCols
    case .frozenCorner, .frozenLeft: col < frozenCols
    case .frozenTop: col >= frozenCols
    }
  }

  private func rowIncludedInGridLines(_ row: Int, region: GridLineRegion, frozenRows: Int) -> Bool {
    switch region {
    case .scrollable: row >= frozenRows
    case .frozenCorner, .frozenTop: row < frozenRows
    case .frozenLeft: row >= frozenRows
    }
  }

  private func scrollableCellsClipRect() -> NSRect {
    let frozenRows = frozenRowCount()
    let frozenCols = frozenColumnCount()
    let top = frozenRows > 0 ? frozenRowBoundaryY() : contentRect.minY
    let left = frozenCols > 0 ? frozenColumnBoundaryX() : contentRect.minX
    return NSRect(
      x: max(contentRect.minX, left),
      y: max(contentRect.minY, top),
      width: max(0, contentRect.maxX - max(contentRect.minX, left)),
      height: max(0, contentRect.maxY - max(contentRect.minY, top))
    )
  }

  private func frozenCellsClipRect() -> NSRect {
    let frozenRows = frozenRowCount()
    let frozenCols = frozenColumnCount()
    guard frozenRows > 0, frozenCols > 0 else { return .zero }
    return NSRect(
      x: contentRect.minX,
      y: contentRect.minY,
      width: max(0, frozenColumnBoundaryX() - contentRect.minX),
      height: max(0, frozenRowBoundaryY() - contentRect.minY)
    )
  }

  private func frozenTopStripClipRect() -> NSRect {
    let frozenRows = frozenRowCount()
    guard frozenRows > 0 else { return .zero }
    let left = frozenColumnCount() > 0 ? frozenColumnBoundaryX() : contentRect.minX
    return NSRect(
      x: max(contentRect.minX, left),
      y: contentRect.minY,
      width: max(0, contentRect.maxX - max(contentRect.minX, left)),
      height: max(0, frozenRowBoundaryY() - contentRect.minY)
    )
  }

  /// Opaque sheet background for the dirty slice of each frozen pane. Scrolled
  /// cells are clipped below the boundary; this still covers strokes and text
  /// that antialias across the last frozen row or column.
  private func fillFrozenPaneBackgrounds(in dirtyRect: NSRect) {
    guard frozenRowCount() > 0 || frozenColumnCount() > 0 else { return }
    for rect in [frozenCellsClipRect(), frozenTopStripClipRect(), frozenLeftStripClipRect()] {
      guard rect.width > 0.5, rect.height > 0.5 else { continue }
      let hit = rect.intersection(dirtyRect)
      guard !hit.isNull, hit.width > 0.5, hit.height > 0.5 else { continue }
      tileFill(hit, color: paintWindowBackground())
    }
  }

  /// Where a selection or formula highlight may paint. A range that only scrolls
  /// stays out of the frozen panes, even when its cell rect starts underneath them.
  private func paneClipRect(for range: CellRange) -> NSRect {
    var clip = contentRect
    let n = range.normalized
    let frozenRows = frozenRowCount()
    let frozenCols = frozenColumnCount()
    if frozenRows > 0 {
      if n.minRow >= frozenRows {
        let top = max(clip.minY, frozenRowBoundaryY())
        clip = NSRect(x: clip.minX, y: top, width: clip.width, height: max(0, clip.maxY - top))
      } else if n.maxRow < frozenRows {
        let bottom = min(clip.maxY, frozenRowBoundaryY())
        clip = NSRect(
          x: clip.minX, y: clip.minY, width: clip.width, height: max(0, bottom - clip.minY))
      }
    }
    if frozenCols > 0, clip.width > 0.5, clip.height > 0.5 {
      if n.minCol >= frozenCols {
        let left = max(clip.minX, frozenColumnBoundaryX())
        clip = NSRect(x: left, y: clip.minY, width: max(0, clip.maxX - left), height: clip.height)
      } else if n.maxCol < frozenCols {
        let right = min(clip.maxX, frozenColumnBoundaryX())
        clip = NSRect(
          x: clip.minX, y: clip.minY, width: max(0, right - clip.minX), height: clip.height)
      }
    }
    return clip
  }

  private func frozenLeftStripClipRect() -> NSRect {
    let frozenCols = frozenColumnCount()
    guard frozenCols > 0 else { return .zero }
    let top = frozenRowCount() > 0 ? frozenRowBoundaryY() : contentRect.minY
    return NSRect(
      x: contentRect.minX,
      y: max(contentRect.minY, top),
      width: max(0, frozenColumnBoundaryX() - contentRect.minX),
      height: max(0, contentRect.maxY - max(contentRect.minY, top))
    )
  }

  /// Header titles use the 11 pt medium system font. The glyph is that font's
  /// size, centered in the header cell. A non-uniform context scale must not
  /// stretch it to the cell bounds.
  private func drawHeaderLabel(
    _ label: NSString,
    centeredIn rect: NSRect,
    clip: NSRect,
    color: NSColor
  ) {
    let attrs: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 11, weight: .medium),
      .foregroundColor: color,
    ]
    let size = label.size(withAttributes: attrs)
    let point = NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2)
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(rect: clip).addClip()
    if let cg = NSGraphicsContext.current?.cgContext {
      let sx = abs(cg.ctm.a)
      let sy = abs(cg.ctm.d)
      if sx > 0.01, sy > 0.01, sx > sy * 1.5 {
        cg.saveGState()
        cg.translateBy(x: point.x, y: point.y)
        cg.scaleBy(x: sy / sx, y: 1)
        label.draw(at: .zero, withAttributes: attrs)
        cg.restoreGState()
        NSGraphicsContext.restoreGraphicsState()
        return
      }
    }
    label.draw(at: point, withAttributes: attrs)
    NSGraphicsContext.restoreGraphicsState()
  }

  private func drawStickyHeaders(in dirtyRect: NSRect) {
    if rasterTarget == nil {
      liveScrollHeaderDraws += 1
    }
    let headerFill = theme.chrome
    let headerText = theme.secondaryLabel
    let gridLine = headerLineColor()

    // Opaque header bands (cover any scrolled cell text underneath).
    let topBand = NSRect(x: 0, y: 0, width: bounds.width, height: headerSize)
    if dirtyRect.intersects(topBand) {
      headerFill.setFill()
      topBand.fill()
    }
    let leftBand = NSRect(x: 0, y: 0, width: headerSize, height: bounds.height)
    if dirtyRect.intersects(leftBand) {
      headerFill.setFill()
      leftBand.fill()
    }

    // Column headers (fixed vertically, scroll horizontally).
    NSGraphicsContext.saveGraphicsState()
    let columnHeaderClip = NSRect(
      x: headerSize,
      y: 0,
      width: max(0, bounds.width - headerSize),
      height: headerSize
    )
    NSBezierPath(rect: columnHeaderClip).addClip()
    if frozenColumnCount() > 0 {
      let frozenHeaderBand = NSRect(
        x: headerSize,
        y: 0,
        width: max(0, frozenColumnBoundaryX() - headerSize),
        height: headerSize
      )
      headerFill.setFill()
      frozenHeaderBand.fill()
      let scrollableHeaderBand = NSRect(
        x: frozenColumnBoundaryX(),
        y: 0,
        width: max(0, bounds.width - frozenColumnBoundaryX()),
        height: headerSize
      )
      scrollableHeaderBand.fill()
    }
    let frozenCols = frozenColumnCount()
    let columnBoundaryX = frozenCols > 0 ? frozenColumnBoundaryX() : columnHeaderClip.minX
    let scrollingColumnClip = NSRect(
      x: columnBoundaryX,
      y: columnHeaderClip.minY,
      width: max(0, columnHeaderClip.maxX - columnBoundaryX),
      height: columnHeaderClip.height
    )
    let frozenColumnClip = NSRect(
      x: headerSize,
      y: 0,
      width: max(0, columnBoundaryX - headerSize),
      height: headerSize
    )
    func drawColumnHeaders(_ columns: [Int], clip passClip: NSRect) {
      guard passClip.width > 0.5, passClip.height > 0.5 else { return }
      NSGraphicsContext.saveGraphicsState()
      NSBezierPath(rect: passClip).addClip()
      for col in columns {
        let rect = columnHeaderRect(for: col)
        let onScreen = rect.intersection(columnHeaderClip)
        let visible = onScreen.intersection(passClip)
        guard !visible.isNull, !visible.isEmpty, dirtyRect.intersects(visible) else { continue }
        headerFill.setFill()
        visible.fill()
        // Under the label, so the number or letter stays readable.
        drawHiddenRunChevrons(hiddenRunChevrons(column: col, rect: rect))
        drawOutlineButtons(outlineButtons(column: col, rect: rect))
        drawHeaderLabel(
          A1Notation.columnLabel(for: col) as NSString,
          centeredIn: onScreen,
          clip: visible,
          color: headerText
        )
        gridLine.setStroke()
        if abs(rect.maxX - columnBoundaryX) > 0.5 {
          NSBezierPath.strokeLine(
            from: NSPoint(x: rect.maxX, y: 0), to: NSPoint(x: rect.maxX, y: headerSize))
        }
      }
      NSGraphicsContext.restoreGraphicsState()
    }
    // Scrolling headers first. Frozen headers are painted again afterward so a
    // column that straddles the boundary cannot cover the last frozen column.
    drawColumnHeaders(headerColumnIndices().filter { $0 >= frozenCols }, clip: scrollingColumnClip)
    if frozenCols > 0 {
      headerFill.setFill()
      frozenColumnClip.fill()
      drawColumnHeaders(
        (0..<frozenCols).filter { shouldDrawColumnHeader($0) }, clip: frozenColumnClip)
      gridLine.setStroke()
      NSBezierPath.strokeLine(
        from: NSPoint(x: columnBoundaryX, y: 0),
        to: NSPoint(x: columnBoundaryX, y: headerSize)
      )
    }
    NSGraphicsContext.restoreGraphicsState()

    // Row headers (fixed horizontally, scroll vertically).
    NSGraphicsContext.saveGraphicsState()
    let rowHeaderClip = NSRect(
      x: 0,
      y: headerSize,
      width: headerSize,
      height: max(0, bounds.height - headerSize)
    )
    NSBezierPath(rect: rowHeaderClip).addClip()
    if frozenRowCount() > 0 {
      let frozenHeaderBand = NSRect(
        x: 0,
        y: headerSize,
        width: headerSize,
        height: max(0, frozenRowBoundaryY() - headerSize)
      )
      headerFill.setFill()
      frozenHeaderBand.fill()
      let scrollableHeaderBand = NSRect(
        x: 0,
        y: frozenRowBoundaryY(),
        width: headerSize,
        height: max(0, bounds.height - frozenRowBoundaryY())
      )
      scrollableHeaderBand.fill()
    }
    let frozenRows = frozenRowCount()
    let rowBoundaryY = frozenRows > 0 ? frozenRowBoundaryY() : rowHeaderClip.minY
    let scrollingRowClip = NSRect(
      x: rowHeaderClip.minX,
      y: rowBoundaryY,
      width: rowHeaderClip.width,
      height: max(0, rowHeaderClip.maxY - rowBoundaryY)
    )
    let frozenRowClip = NSRect(
      x: 0,
      y: headerSize,
      width: headerSize,
      height: max(0, rowBoundaryY - headerSize)
    )
    func drawRowHeaders(_ rows: [Int], clip passClip: NSRect) {
      guard passClip.width > 0.5, passClip.height > 0.5 else { return }
      NSGraphicsContext.saveGraphicsState()
      NSBezierPath(rect: passClip).addClip()
      for row in rows {
        let rect = rowHeaderRect(for: row)
        let onScreen = rect.intersection(rowHeaderClip)
        let visible = onScreen.intersection(passClip)
        guard !visible.isNull, !visible.isEmpty, dirtyRect.intersects(visible) else { continue }
        headerFill.setFill()
        visible.fill()
        // The accent marks every row of a filtered list.
        // Under the label, so the number or letter stays readable.
        drawHiddenRunChevrons(hiddenRunChevrons(row: row, rect: rect))
        let rowButtons = outlineButtons(row: row, rect: rect)
        drawOutlineButtons(rowButtons)
        var labelRect = onScreen
        if !rowButtons.isEmpty {
          labelRect.origin.x += 10
          labelRect.size.width = max(0, labelRect.width - 10)
        }
        drawHeaderLabel(
          "\(row + 1)" as NSString,
          centeredIn: labelRect,
          clip: visible,
          color: viewModel?.isShownByActiveFilter(row) == true ? theme.accent : headerText
        )
        gridLine.setStroke()
        if abs(rect.maxY - rowBoundaryY) > 0.5 {
          NSBezierPath.strokeLine(
            from: NSPoint(x: 0, y: rect.maxY), to: NSPoint(x: headerSize, y: rect.maxY))
        }
      }
      NSGraphicsContext.restoreGraphicsState()
    }
    // Same order as columns: scrolling labels cannot remain on the last frozen row.
    drawRowHeaders(headerRowIndices().filter { $0 >= frozenRows }, clip: scrollingRowClip)
    if frozenRows > 0 {
      headerFill.setFill()
      frozenRowClip.fill()
      drawRowHeaders((0..<frozenRows).filter { shouldDrawRowHeader($0) }, clip: frozenRowClip)
      gridLine.setStroke()
      NSBezierPath.strokeLine(
        from: NSPoint(x: 0, y: rowBoundaryY),
        to: NSPoint(x: headerSize, y: rowBoundaryY)
      )
    }
    NSGraphicsContext.restoreGraphicsState()
  }

  /// A small chevron in a header beside rows or columns the sheet hides, pointing at them.
  /// Clicking it shows them again.
  private struct HiddenRunChevron {
    enum Direction { case up, down, left, right }
    var rect: NSRect
    var direction: Direction
    var axis: SpreadsheetViewModel.HideAxis
    var hiddenIndex: Int
  }

  private func hiddenRunChevrons(row: Int, rect: NSRect) -> [HiddenRunChevron] {
    guard let sheet = viewModel?.activeSheet, !sheet.fileExtras.hiddenRows.isEmpty,
      rect.height >= 12
    else { return [] }
    var marks: [HiddenRunChevron] = []
    // At the header's left edge: row numbers are centered and long ones reached the right edge.
    let x = rect.minX + 3
    if sheet.isRowHidden(row + 1), !startsGroupWithButton(.rows, at: row + 1) {
      marks.append(
        HiddenRunChevron(
          rect: NSRect(x: x, y: rect.maxY - 8, width: 9, height: 5), direction: .down,
          axis: .rows, hiddenIndex: row + 1))
    }
    if row > 0, sheet.isRowHidden(row - 1), outlineButtonMap(.rows)[row] == nil {
      marks.append(
        HiddenRunChevron(
          rect: NSRect(x: x, y: rect.minY + 3, width: 9, height: 5), direction: .up,
          axis: .rows, hiddenIndex: row - 1))
    }
    return marks
  }

  private func hiddenRunChevrons(column col: Int, rect: NSRect) -> [HiddenRunChevron] {
    guard let sheet = viewModel?.activeSheet, !sheet.fileExtras.hiddenColumns.isEmpty,
      rect.width >= 16
    else { return [] }
    var marks: [HiddenRunChevron] = []
    let y = rect.midY - 4.5
    if sheet.isColumnHidden(col + 1), !startsGroupWithButton(.columns, at: col + 1) {
      marks.append(
        HiddenRunChevron(
          rect: NSRect(x: rect.maxX - 8, y: y, width: 5, height: 9), direction: .right,
          axis: .columns, hiddenIndex: col + 1))
    }
    if col > 0, sheet.isColumnHidden(col - 1), outlineButtonMap(.columns)[col] == nil {
      marks.append(
        HiddenRunChevron(
          rect: NSRect(x: rect.minX + 3, y: y, width: 5, height: 9), direction: .left,
          axis: .columns, hiddenIndex: col - 1))
    }
    return marks
  }

  /// In a translucent accent, drawn before the header's number or letter so that sits on top.
  private func drawHiddenRunChevrons(_ marks: [HiddenRunChevron]) {
    guard !marks.isEmpty else { return }
    for mark in marks {
      let r = mark.rect
      let path = NSBezierPath()
      path.lineWidth = 1.75
      path.lineCapStyle = .round
      path.lineJoinStyle = .round
      switch mark.direction {
      case .down:
        path.move(to: NSPoint(x: r.minX, y: r.minY))
        path.line(to: NSPoint(x: r.midX, y: r.maxY))
        path.line(to: NSPoint(x: r.maxX, y: r.minY))
      case .up:
        path.move(to: NSPoint(x: r.minX, y: r.maxY))
        path.line(to: NSPoint(x: r.midX, y: r.minY))
        path.line(to: NSPoint(x: r.maxX, y: r.maxY))
      case .right:
        path.move(to: NSPoint(x: r.minX, y: r.minY))
        path.line(to: NSPoint(x: r.maxX, y: r.midY))
        path.line(to: NSPoint(x: r.minX, y: r.maxY))
      case .left:
        path.move(to: NSPoint(x: r.maxX, y: r.minY))
        path.line(to: NSPoint(x: r.minX, y: r.midY))
        path.line(to: NSPoint(x: r.maxX, y: r.maxY))
      }
      theme.accent.withAlphaComponent(0.55).setStroke()
      path.stroke()
    }
  }

  // MARK: - Group (outline) buttons

  /// A +/− box in the header just past a group of rows or columns. Clicking folds the group.
  private struct OutlineButton {
    var rect: NSRect
    var axis: SpreadsheetViewModel.HideAxis
    var group: SpreadsheetViewModel.OutlineGroup
    var collapsed: Bool
  }

  /// The view model's buttons, worked out once per content change rather than per header.
  private func outlineButtonMap(_ axis: SpreadsheetViewModel.HideAxis)
    -> [Int: SpreadsheetViewModel.OutlineGroup]
  {
    guard let viewModel else { return [:] }
    let key = OutlineCacheKey(
      revision: viewModel.contentRevision, sheet: viewModel.workbook.activeSheetIndex)
    if outlineCache?.key != key {
      outlineCache = (key, viewModel.outlineButtons(.rows), viewModel.outlineButtons(.columns))
    }
    return axis == .rows ? outlineCache?.rows ?? [:] : outlineCache?.columns ?? [:]
  }

  /// True when `index` starts a group whose +/− button already marks the fold.
  private func startsGroupWithButton(_ axis: SpreadsheetViewModel.HideAxis, at index: Int) -> Bool {
    outlineButtonMap(axis).values.contains { $0.start == index }
  }

  private func outlineButtons(row: Int, rect: NSRect) -> [OutlineButton] {
    guard let viewModel, viewModel.hasOutline.rows, rect.height >= 12,
      let group = outlineButtonMap(.rows)[row]
    else { return [] }
    // At the left edge; the row number moves right to make room.
    let box = NSRect(x: rect.minX + 3, y: rect.midY - 4.5, width: 9, height: 9)
    return [
      OutlineButton(
        rect: box, axis: .rows, group: group,
        collapsed: viewModel.isOutlineGroupCollapsed(group, .rows))
    ]
  }

  private func outlineButtons(column col: Int, rect: NSRect) -> [OutlineButton] {
    guard let viewModel, viewModel.hasOutline.columns, rect.width >= 30,
      let group = outlineButtonMap(.columns)[col]
    else { return [] }
    let box = NSRect(x: rect.maxX - 22, y: rect.midY - 5, width: 10, height: 10)
    return [
      OutlineButton(
        rect: box, axis: .columns, group: group,
        collapsed: viewModel.isOutlineGroupCollapsed(group, .columns))
    ]
  }

  private func drawOutlineButtons(_ buttons: [OutlineButton]) {
    for button in buttons {
      let r = button.rect.insetBy(dx: 0.5, dy: 0.5)
      let color = theme.accent.withAlphaComponent(0.8)
      color.setStroke()
      let box = NSBezierPath(roundedRect: r, xRadius: 2, yRadius: 2)
      box.lineWidth = 1
      box.stroke()
      let sign = NSBezierPath()
      sign.lineWidth = 1.25
      sign.lineCapStyle = .round
      sign.move(to: NSPoint(x: r.minX + 2.5, y: r.midY))
      sign.line(to: NSPoint(x: r.maxX - 2.5, y: r.midY))
      if button.collapsed {
        sign.move(to: NSPoint(x: r.midX, y: r.minY + 2.5))
        sign.line(to: NSPoint(x: r.midX, y: r.maxY - 2.5))
      }
      sign.stroke()
    }
  }

  private func outlineButton(at point: NSPoint) -> OutlineButton? {
    let candidates: [OutlineButton]
    switch headerHit(at: point) {
    case .row(let row):
      candidates = outlineButtons(row: row, rect: rowHeaderRect(for: row))
    case .column(let col):
      candidates = outlineButtons(column: col, rect: columnHeaderRect(for: col))
    default:
      return nil
    }
    return candidates.first { $0.rect.insetBy(dx: -3, dy: -3).contains(point) }
  }

  /// The chevron under `point` in a header, with a little slack around it.
  private func hiddenRunChevron(at point: NSPoint) -> HiddenRunChevron? {
    let candidates: [HiddenRunChevron]
    switch headerHit(at: point) {
    case .row(let row):
      candidates = (max(0, row - 1)...(row + 1)).flatMap {
        hiddenRunChevrons(row: $0, rect: rowHeaderRect(for: $0))
      }
    case .column(let col):
      candidates = (max(0, col - 1)...(col + 1)).flatMap {
        hiddenRunChevrons(column: $0, rect: columnHeaderRect(for: $0))
      }
    default:
      return nil
    }
    return candidates.first { $0.rect.insetBy(dx: -4, dy: -4).contains(point) }
  }

  private func drawHeaderCorner(in dirtyRect: NSRect) {
    let headerFill = theme.chrome
    let gridLine = headerLineColor()

    let corner = NSRect(x: 0, y: 0, width: headerSize, height: headerSize)
    guard dirtyRect.intersects(corner) else { return }
    headerFill.setFill()
    corner.fill()
    gridLine.setStroke()
    NSBezierPath.strokeLine(
      from: NSPoint(x: corner.maxX, y: 0), to: NSPoint(x: corner.maxX, y: corner.maxY))
    NSBezierPath.strokeLine(
      from: NSPoint(x: 0, y: corner.maxY), to: NSPoint(x: corner.maxX, y: corner.maxY))
  }

  private func drawGridLinesInClip(
    dirtyRect: NSRect,
    region: GridLineRegion,
    clipRect: NSRect
  ) {
    guard !clipRect.isEmpty else { return }

    let frozenRows = frozenRowCount()
    let frozenCols = frozenColumnCount()
    let frozenBoundaryX = frozenColumnBoundaryX()
    let frozenBoundaryY = frozenRowBoundaryY()

    let content = contentRect
    // Don't extend gridlines into empty viewport below the last laid-out row
    // (important when filter-hidden rows collapse height).
    let sheetBottom = min(content.maxY, max(content.minY, contentBottomY()))
    let gridBounds = NSRect(
      x: content.minX,
      y: content.minY,
      width: content.width,
      height: max(0, sheetBottom - content.minY)
    )
    guard gridBounds.height > 0.5 else { return }

    let gridClip = clipRect.intersection(gridBounds)
    tileClip(gridClip) {
      self.strokeRecordedGridLines(
        gridBounds: gridBounds,
        region: region,
        frozenCols: frozenCols,
        frozenRows: frozenRows,
        frozenBoundaryX: frozenBoundaryX,
        frozenBoundaryY: frozenBoundaryY
      )
    }
  }

  private func strokeRecordedGridLines(
    gridBounds: NSRect,
    region: GridLineRegion,
    frozenCols: Int,
    frozenRows: Int,
    frozenBoundaryX: CGFloat,
    frozenBoundaryY: CGFloat
  ) {
    let path = NSBezierPath()
    path.lineWidth = 0.5

    // Fast full-span lines — one stroke per unique grid line (avoid painting shared edges twice).
    // A merge is one cell: drop interior segments, keep the border around the outside.
    let cuts = mergeGridLineCuts(region: region)
    for colSpan in visibleColumnSpans() {
      for col in colSpan {
        guard columnIncludedInGridLines(col, region: region, frozenCols: frozenCols) else {
          continue
        }
        let x = xForColumn(col)
        let maxX = x + columnWidth(at: col)
        if region == .scrollable, x < frozenBoundaryX - 0.5 { continue }
        if region == .frozenCorner || region == .frozenLeft, maxX > frozenBoundaryX + 0.5 {
          continue
        }
        appendGridLine(
          path,
          axis: x,
          from: gridBounds.minY,
          to: gridBounds.maxY,
          horizontal: false,
          gaps: verticalMergeGaps(boundaryColumn: col, cuts: cuts)
        )
        if col == colSpan.upperBound {
          appendGridLine(
            path,
            axis: maxX,
            from: gridBounds.minY,
            to: gridBounds.maxY,
            horizontal: false,
            gaps: verticalMergeGaps(boundaryColumn: col + 1, cuts: cuts)
          )
        }
      }
    }

    for rowSpan in visibleRowSpans() {
      for row in rowSpan {
        guard rowIncludedInGridLines(row, region: region, frozenRows: frozenRows) else { continue }
        let height = rowHeight(at: row)
        guard height > 0.5 else { continue }
        let y = yForRow(row)
        let maxY = y + height
        if region == .scrollable, y < frozenBoundaryY - 0.5 { continue }
        if region == .frozenCorner || region == .frozenTop, maxY > frozenBoundaryY + 0.5 {
          continue
        }
        if maxY < gridBounds.minY || y > gridBounds.maxY { continue }
        appendGridLine(
          path,
          axis: y,
          from: gridBounds.minX,
          to: gridBounds.maxX,
          horizontal: true,
          gaps: horizontalMergeGaps(boundaryRow: row, cuts: cuts)
        )
        if row == rowSpan.upperBound {
          appendGridLine(
            path,
            axis: maxY,
            from: gridBounds.minX,
            to: gridBounds.maxX,
            horizontal: true,
            gaps: horizontalMergeGaps(boundaryRow: row + 1, cuts: cuts)
          )
        }
      }
    }
    tileStroke(path, color: gridLineColor())
  }

  /// View-space hole where a merge crosses this region. Row and column indexes stay
  /// the full merge so a line is interior even when the other axis is clipped to the
  /// frozen or scrolling side. The x/y span is only the part this region paints, so a
  /// scrolled merge does not use frozen coordinates (and the reverse).
  private struct MergeGridLineCut {
    var minRow: Int
    var maxRow: Int
    var minCol: Int
    var maxCol: Int
    var minX: CGFloat
    var maxX: CGFloat
    var minY: CGFloat
    var maxY: CGFloat
  }

  private func mergeGridLineCuts(region: GridLineRegion) -> [MergeGridLineCut] {
    guard let merges = sheetForLayout()?.mergedRanges, !merges.isEmpty else { return [] }
    let frozenRows = frozenRowCount()
    let frozenCols = frozenColumnCount()
    let rowLimit = rowCount()
    let colLimit = columnCount()
    let rowLower: Int
    let rowUpper: Int
    let colLower: Int
    let colUpper: Int
    switch region {
    case .scrollable:
      rowLower = frozenRows
      rowUpper = rowLimit
      colLower = frozenCols
      colUpper = colLimit
    case .frozenCorner:
      rowLower = 0
      rowUpper = frozenRows
      colLower = 0
      colUpper = frozenCols
    case .frozenTop:
      rowLower = 0
      rowUpper = frozenRows
      colLower = frozenCols
      colUpper = colLimit
    case .frozenLeft:
      rowLower = frozenRows
      rowUpper = rowLimit
      colLower = 0
      colUpper = frozenCols
    }
    guard rowUpper > rowLower, colUpper > colLower else { return [] }

    var cuts: [MergeGridLineCut] = []
    cuts.reserveCapacity(merges.count)
    for merge in merges {
      let n = merge.normalized
      guard n.maxRow > n.minRow || n.maxCol > n.minCol else { continue }
      let row0 = max(n.minRow, rowLower)
      let row1 = min(n.maxRow, rowUpper - 1)
      let col0 = max(n.minCol, colLower)
      let col1 = min(n.maxCol, colUpper - 1)
      guard row0 <= row1, col0 <= col1 else { continue }
      let minY = yForRow(row0)
      let maxY = yForRow(row1) + rowHeight(at: row1)
      let minX = xForColumn(col0)
      let maxX = xForColumn(col1) + columnWidth(at: col1)
      guard maxY - minY > 0.5, maxX - minX > 0.5 else { continue }
      cuts.append(
        MergeGridLineCut(
          minRow: n.minRow,
          maxRow: n.maxRow,
          minCol: n.minCol,
          maxCol: n.maxCol,
          minX: minX,
          maxX: maxX,
          minY: minY,
          maxY: maxY
        ))
    }
    return cuts
  }

  /// Left edge of `col` is interior when the merge contains the columns on both sides.
  private func verticalMergeGaps(boundaryColumn col: Int, cuts: [MergeGridLineCut]) -> [(
    CGFloat, CGFloat
  )] {
    guard !cuts.isEmpty else { return [] }
    var gaps: [(CGFloat, CGFloat)] = []
    gaps.reserveCapacity(cuts.count)
    for cut in cuts where cut.minCol < col && col <= cut.maxCol {
      gaps.append((cut.minY, cut.maxY))
    }
    return gaps
  }

  /// Top edge of `row` is interior when the merge contains the rows on both sides.
  private func horizontalMergeGaps(boundaryRow row: Int, cuts: [MergeGridLineCut]) -> [(
    CGFloat, CGFloat
  )] {
    guard !cuts.isEmpty else { return [] }
    var gaps: [(CGFloat, CGFloat)] = []
    gaps.reserveCapacity(cuts.count)
    for cut in cuts where cut.minRow < row && row <= cut.maxRow {
      gaps.append((cut.minX, cut.maxX))
    }
    return gaps
  }

  private func appendGridLine(
    _ path: NSBezierPath,
    axis: CGFloat,
    from: CGFloat,
    to: CGFloat,
    horizontal: Bool,
    gaps: [(CGFloat, CGFloat)]
  ) {
    let start = min(from, to)
    let end = max(from, to)
    guard end - start > 0.5 else { return }
    if gaps.isEmpty {
      addGridSegment(path, axis: axis, from: start, to: end, horizontal: horizontal)
      return
    }
    var cuts: [(CGFloat, CGFloat)] = []
    cuts.reserveCapacity(gaps.count)
    for gap in gaps {
      let low = max(start, min(gap.0, gap.1))
      let high = min(end, max(gap.0, gap.1))
      if high - low > 0.25 {
        cuts.append((low, high))
      }
    }
    guard !cuts.isEmpty else {
      addGridSegment(path, axis: axis, from: start, to: end, horizontal: horizontal)
      return
    }
    cuts.sort { $0.0 < $1.0 }
    var merged: [(CGFloat, CGFloat)] = []
    merged.reserveCapacity(cuts.count)
    for cut in cuts {
      if let last = merged.last, cut.0 <= last.1 + 0.25 {
        merged[merged.count - 1] = (last.0, max(last.1, cut.1))
      } else {
        merged.append(cut)
      }
    }
    var cursor = start
    for cut in merged {
      if cut.0 - cursor > 0.5 {
        addGridSegment(path, axis: axis, from: cursor, to: cut.0, horizontal: horizontal)
      }
      cursor = max(cursor, cut.1)
    }
    if end - cursor > 0.5 {
      addGridSegment(path, axis: axis, from: cursor, to: end, horizontal: horizontal)
    }
  }

  private func addGridSegment(
    _ path: NSBezierPath,
    axis: CGFloat,
    from: CGFloat,
    to: CGFloat,
    horizontal: Bool
  ) {
    let aligned = devicePixel(axis)
    if horizontal {
      path.move(to: NSPoint(x: from, y: aligned))
      path.line(to: NSPoint(x: to, y: aligned))
    } else {
      path.move(to: NSPoint(x: aligned, y: from))
      path.line(to: NSPoint(x: aligned, y: to))
    }
  }

  private func drawGridLines(in dirtyRect: NSRect) {
    drawGridLinesInClip(
      dirtyRect: dirtyRect,
      region: .scrollable,
      clipRect: scrollableCellsClipRect()
    )
  }

  private func drawFrozenGridLines(in dirtyRect: NSRect) {
    let frozenRows = frozenRowCount()
    let frozenCols = frozenColumnCount()
    guard frozenRows > 0 || frozenCols > 0 else { return }

    if frozenRows > 0 && frozenCols > 0 {
      drawGridLinesInClip(
        dirtyRect: dirtyRect, region: .frozenCorner, clipRect: frozenCellsClipRect())
    }
    if frozenRows > 0 {
      drawGridLinesInClip(
        dirtyRect: dirtyRect, region: .frozenTop, clipRect: frozenTopStripClipRect())
    }
    if frozenCols > 0 {
      drawGridLinesInClip(
        dirtyRect: dirtyRect, region: .frozenLeft, clipRect: frozenLeftStripClipRect())
    }
  }

  /// When most on-screen cells already have custom borders, default gridlines are pure overdraw.
  private func visibleRegionIsMostlyBordered() -> Bool {
    guard let sheet = sheetForLayout() else { return false }
    var bordered = 0
    var populated = 0
    // Sample up to ~200 cells so this stays cheap on huge views.
    var sampled = 0
    rowLoop: for rows in visibleRowSpans() {
      for cols in visibleColumnSpans() {
        for row in rows {
          for col in cols {
            guard let cell = sheet.cells[CellAddress(row: row, col: col)] else { continue }
            populated += 1
            if cell.format?.borders.hasAny == true { bordered += 1 }
            sampled += 1
            if sampled >= 200 { break rowLoop }
          }
        }
      }
    }
    guard populated > 0 else { return false }
    return bordered * 2 >= populated
  }

  private func drawCell(
    _ cell: Cell,
    at address: CellAddress,
    in dirtyRect: NSRect,
    viewModel: SpreadsheetViewModel,
    drawBorders: Bool = true
  ) {
    let rect = rectForCell(row: address.row, col: address.col)
    guard isCellRectInContentArea(rect), dirtyRect.intersects(rect) else { return }
    let paintFormat = viewModel.resolvedFormat(at: address)
    let hasBorders = paintFormat?.borders.hasAny == true || cell.format?.borders.hasAny == true
    let hasFill = paintFormat?.fillColor != nil
    if !cell.hasContent && !hasFill && !hasBorders { return }
    if viewModel.isEditing && address == viewModel.selectionAnchor && isEditorActive {
      if drawBorders, let borders = paintFormat?.borders ?? cell.format?.borders, borders.hasAny {
        CellFormatRenderer.drawBorders(borders, in: rect, scale: zoomScale)
      }
      return
    }

    if let fill = CellFormatRenderer.fillColor(for: paintFormat) {
      fill.setFill()
      rect.fill()
    }

    if cell.hasContent {
      let value = viewModel.displayValue(at: address)
      let text = viewModel.displayString(at: address)
      let insetX = 4 * zoomScale
      let insetY = 2 * zoomScale
      let textRect = rect.insetBy(dx: insetX, dy: insetY)
      if textRect.width > 1, textRect.height > 1 {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: rect).addClip()
        var drawFormat = paintFormat ?? CellFormat()
        let baseSize = drawFormat.fontSize ?? CellFormatRenderer.defaultFontSize
        drawFormat.fontSize = baseSize * zoomScale
        if value.isError {
          drawFormat.textColor = CellFormatRenderer.codableColor(from: theme.errorText)
          CellFormatRenderer.drawText(text, in: textRect, format: drawFormat)
        } else {
          if paintIsDarkMode(), CellFormatRenderer.fillColor(for: paintFormat) == nil,
            drawFormat.textColor == SpreadsheetViewModel.linkTextColor
          {
            drawFormat.textColor = Self.darkModeLinkColor
          }
          CellFormatRenderer.drawText(text, in: textRect, format: drawFormat)
        }
        NSGraphicsContext.restoreGraphicsState()
      }
    }

    if drawBorders, let borders = paintFormat?.borders, borders.hasAny {
      CellFormatRenderer.drawBorders(borders, in: rect, scale: zoomScale)
    }
  }

  /// The filter button in a header cell: a funnel, drawn in the accent while its column hides rows.
  private func drawFilterAffordance(in rect: NSRect, over background: NSColor?, column: Int) {
    let isFiltering = viewModel?.filterState?.isFiltering(column: column) == true
    let size = 10 * zoomScale
    let gap = 5 * zoomScale
    let boxWidth = size + 2 * zoomScale
    let boxHeight = size
    let box = NSRect(
      x: rect.maxX - boxWidth - gap,
      y: rect.maxY - boxHeight - gap,
      width: boxWidth,
      height: boxHeight
    )

    let base =
      (background ?? theme.canvas)
      .usingColorSpace(.deviceRGB) ?? background ?? theme.canvas
    let luminance =
      0.2126 * base.redComponent
      + 0.7152 * base.greenComponent
      + 0.0722 * base.blueComponent
    let onLight = luminance > 0.55
    let chipFill =
      onLight
      ? NSColor.black.withAlphaComponent(0.12)
      : NSColor.white.withAlphaComponent(0.22)
    let glyphFill =
      onLight
      ? NSColor.black.withAlphaComponent(0.72)
      : NSColor.white.withAlphaComponent(0.92)

    let chipPath = NSBezierPath(roundedRect: box, xRadius: 2 * zoomScale, yRadius: 2 * zoomScale)
    tileFillPath(chipPath, color: isFiltering ? theme.accent.withAlphaComponent(0.28) : chipFill)

    // A funnel: a wide top narrowing to a short stem. The view is flipped, so y grows down.
    let top = box.minY + size * 0.18
    let neck = box.minY + size * 0.55
    let bottom = box.minY + size * 0.88
    let left = box.midX - size * 0.42
    let right = box.midX + size * 0.42
    let stem = size * 0.11
    let funnel = NSBezierPath()
    funnel.move(to: NSPoint(x: left, y: top))
    funnel.line(to: NSPoint(x: right, y: top))
    funnel.line(to: NSPoint(x: box.midX + stem, y: neck))
    funnel.line(to: NSPoint(x: box.midX + stem, y: bottom))
    funnel.line(to: NSPoint(x: box.midX - stem, y: bottom - size * 0.12))
    funnel.line(to: NSPoint(x: box.midX - stem, y: neck))
    funnel.close()
    tileFillPath(funnel, color: isFiltering ? theme.accent : glyphFill)
  }

  private func tileFillPath(_ path: NSBezierPath, color: NSColor) {
    if let tileDrawList = recordingDrawList {
      let paint = resolvedDrawColor(color)
      let recorded = path
      tileDrawList.commands.append {
        paint.setFill()
        recorded.fill()
      }
    } else {
      color.setFill()
      path.fill()
    }
  }

  /// Effective background after the selection wash that will be drawn under text.
  private static func selectedCellBackground(
    over fill: NSColor?, theme: SparkTheme.Palette
  ) -> NSColor {
    let base = (fill ?? theme.canvas).usingColorSpace(.deviceRGB) ?? fill ?? theme.canvas
    return blendedColor(
      base,
      overlay: theme.selectionWash.withAlphaComponent(1),
      overlayFraction: theme.selectionWash.alphaComponent
    )
  }

  private static func selectedCellTextColor(
    over fill: NSColor?, theme: SparkTheme.Palette
  ) -> NSColor {
    let washed = selectedCellBackground(over: fill, theme: theme)
    // Pick contrast against the washed fill — not labelColor (white in dark mode on white fills).
    return luminance(of: washed) < 0.58 ? .white : .black
  }

  private static func luminance(of color: NSColor) -> CGFloat {
    let c = color.usingColorSpace(.deviceRGB) ?? color
    return 0.2126 * c.redComponent
      + 0.7152 * c.greenComponent
      + 0.0722 * c.blueComponent
  }

  private static func blendedColor(
    _ base: NSColor,
    overlay: NSColor,
    overlayFraction: CGFloat
  ) -> NSColor {
    let b = base.usingColorSpace(.deviceRGB) ?? base
    let o = overlay.usingColorSpace(.deviceRGB) ?? overlay
    let t = min(max(overlayFraction, 0), 1)
    return NSColor(
      red: o.redComponent * t + b.redComponent * (1 - t),
      green: o.greenComponent * t + b.greenComponent * (1 - t),
      blue: o.blueComponent * t + b.blueComponent * (1 - t),
      alpha: 1
    )
  }

  private func filterAffordanceRect(forCell rect: NSRect) -> NSRect {
    let size = 10 * zoomScale
    let gap = 5 * zoomScale
    let boxWidth = size + 2 * zoomScale
    let boxHeight = size
    // Slightly larger hit target than the drawn chip.
    return NSRect(
      x: rect.maxX - boxWidth - gap - 2 * zoomScale,
      y: rect.maxY - boxHeight - gap - 2 * zoomScale,
      width: boxWidth + 4 * zoomScale,
      height: boxHeight + 4 * zoomScale
    )
  }

  private func drawImages(in dirtyRect: NSRect) {
    let model = rasterViewModel()
    guard let sheet = sheetForLayout() ?? model?.activeSheet, !sheet.images.isEmpty else { return }
    let selectedID = model?.selectedImageID
    for image in sheet.images {
      guard let nsImage = NSImage(data: image.imageData) else { continue }
      let rect = imageRect(for: image)
      guard dirtyRect.intersects(rect), isCellRectInContentArea(rect) else { continue }
      if let tileDrawList = recordingDrawList {
        let recorded = nsImage
        let recordedRect = rect
        tileDrawList.commands.append {
          recorded.draw(
            in: recordedRect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: nil
          )
        }
      } else {
        nsImage.draw(
          in: rect,
          from: .zero,
          operation: .sourceOver,
          fraction: 1,
          respectFlipped: true,
          hints: nil
        )
      }
      if image.id == selectedID, recordingDrawList == nil {
        drawImageSelectionChrome(in: rect)
      }
    }
  }

  private func imageRect(for image: SheetImage) -> NSRect {
    let x = xForColumn(image.anchorCol) + SheetImage.points(fromEMU: image.colOffsetEMU)
    let y = yForRow(image.anchorRow) + SheetImage.points(fromEMU: image.rowOffsetEMU)
    let width = SheetImage.points(fromEMU: image.widthEMU)
    let height = SheetImage.points(fromEMU: image.heightEMU)
    return NSRect(x: x, y: y, width: width, height: height)
  }

  func layoutOnSheetCharts() {
    guard !isLayingOutCharts else { return }
    isLayingOutCharts = true
    defer { isLayingOutCharts = false }
    // Full cell viewport, not the scrollable inset. Host frames then move
    // with the anchor cells, including the part that slides under a freeze.
    chartLayerView.frame = contentRect
    let panes = frozenPaneCoverRects()
    for (index, overlay) in frozenPaneOverlays.enumerated() {
      let rect = index < panes.count ? panes[index] : .zero
      let hide = scrollTilesPresented || rect.width < 0.5 || rect.height < 0.5
      if hide {
        overlay.isHidden = true
        if overlay.frame != .zero {
          overlay.frame = .zero
        }
      } else {
        overlay.isHidden = false
        if overlay.frame != rect {
          overlay.frame = rect
        }
      }
    }
    guard let viewModel else {
      removeChartHosts()
      return
    }
    let charts = viewModel.activeSheet.charts
    let live = Set(charts.map(\.id))
    for id in Array(chartHosts.keys) where !live.contains(id) {
      removeChartHost(id: id)
    }
    for chart in charts {
      let rect = chartRect(for: chart)
      let top = rect.minY
      let bottom = rect.minY + rect.height
      guard rect.width >= 1,
        let height = OnSheetChartGeometry.placedHeight(top: top, bottom: bottom)
      else {
        removeChartHost(id: chart.id)
        continue
      }
      let local = OnSheetChartGeometry.hostFrame(
        chartRect: NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: height),
        layerFrame: chartLayerView.frame
      )
      guard local.width.isFinite, local.height.isFinite, local.width >= 1, local.height >= 1,
        local.origin.x.isFinite, local.origin.y.isFinite
      else {
        removeChartHost(id: chart.id)
        continue
      }
      let snapshot = ChartHostSnapshot(
        chart: chart,
        contentRevision: viewModel.contentRevision,
        selected: viewModel.selectedChartID == chart.id
      )
      let host: OnSheetChartHost
      if let existing = chartHosts[chart.id] {
        host = existing
      } else {
        let created = OnSheetChartHost(
          rootView: OnSheetChartCard(
            chart: chart, viewModel: viewModel, hover: chartHover(for: chart.id)))
        created.sizingOptions = []
        created.safeAreaRegions = []
        created.translatesAutoresizingMaskIntoConstraints = true
        created.focusRingType = .none
        // Set a positive frame before the host joins the window. A zero
        // bounds lays the card out immediately and the inset height goes negative.
        created.frame = local
        chartLayerView.addSubview(created)
        chartHosts[chart.id] = created
        host = created
      }
      if chartHostSnapshots[chart.id] != snapshot {
        host.rootView = OnSheetChartCard(
          chart: chart, viewModel: viewModel, hover: chartHover(for: chart.id))
        chartHostSnapshots[chart.id] = snapshot
      }
      host.isHidden = false
      let sizeChanged =
        abs(host.frame.width - local.width) > 0.5
        || abs(host.frame.height - local.height) > 0.5
      if host.frame != local {
        host.frame = local
      }
      if sizeChanged {
        host.needsLayout = true
      }
    }
    layoutImportedCharts(viewModel)
  }

  /// Places charts from other apps where the file put them. They draw from the cells they name.
  private func layoutImportedCharts(_ viewModel: SpreadsheetViewModel) {
    let placements = viewModel.importedChartPlacements
    let live = Set(placements.map(\.id))
    for id in Array(importedChartHosts.keys) where !live.contains(id) {
      removeImportedChartHost(id: id)
    }
    let sheetID = viewModel.activeSheet.id
    for placement in placements {
      let rect = importedChartRect(placement)
      let local = OnSheetChartGeometry.hostFrame(chartRect: rect, layerFrame: chartLayerView.frame)
      guard rect.width >= 1, rect.height >= 1, local.width.isFinite, local.height.isFinite,
        local.width >= 1, local.height >= 1, local.origin.x.isFinite, local.origin.y.isFinite
      else {
        removeImportedChartHost(id: placement.id)
        continue
      }
      let series = viewModel.importedChartSeries(placement.chart)
      let snapshot = ImportedChartSnapshot(
        placement: placement, selected: viewModel.selectedImportedChartID == placement.id,
        sheetID: sheetID, contentRevision: viewModel.contentRevision,
        engineRevision: viewModel.formulaEngine.cacheRevision, series: series)
      let host: ImportedChartHost
      if let existing = importedChartHosts[placement.id] {
        host = existing
      } else {
        let created = ImportedChartHost(
          rootView: ImportedChartCard(
            placement: placement, series: series, viewModel: viewModel,
            hover: importedChartHover(for: placement.id)))
        created.sizingOptions = []
        created.safeAreaRegions = []
        created.translatesAutoresizingMaskIntoConstraints = true
        created.focusRingType = .none
        created.frame = local
        chartLayerView.addSubview(created)
        importedChartHosts[placement.id] = created
        host = created
      }
      if importedChartSnapshots[placement.id] != snapshot {
        host.rootView = ImportedChartCard(
          placement: placement, series: series, viewModel: viewModel,
          hover: importedChartHover(for: placement.id))
        importedChartSnapshots[placement.id] = snapshot
      }
      host.isHidden = false
      if host.frame != local {
        host.frame = local
        host.needsLayout = true
      }
    }
  }

  private func removeImportedChartHost(id: Int) {
    importedChartHosts[id]?.removeFromSuperview()
    importedChartHosts.removeValue(forKey: id)
    importedChartSnapshots.removeValue(forKey: id)
    importedChartHovers.removeValue(forKey: id)
  }

  private func chartHover(for id: UUID) -> ChartHover {
    if let hover = chartHovers[id] { return hover }
    let hover = ChartHover()
    chartHovers[id] = hover
    return hover
  }

  private func importedChartHover(for id: Int) -> ChartHover {
    if let hover = importedChartHovers[id] { return hover }
    let hover = ChartHover()
    importedChartHovers[id] = hover
    return hover
  }

  /// Hands the pointer to the chart under it and clears every other chart's.
  private func updateChartHover(at point: NSPoint?) {
    func place(_ hover: ChartHover?, in host: NSView) {
      guard let hover else { return }
      var location: CGPoint?
      if let point, !host.isHidden {
        let local = host.convert(point, from: self)
        if host.bounds.contains(local) { location = local }
      }
      if hover.location != location { hover.location = location }
    }
    for (id, host) in chartHosts { place(chartHovers[id], in: host) }
    for (id, host) in importedChartHosts { place(importedChartHovers[id], in: host) }
  }

  /// A drawing anchor's cells and offsets (12,700 EMU to a point) in grid coordinates.
  private func importedChartRect(_ placement: SpreadsheetViewModel.ImportedChartPlacement) -> NSRect
  {
    let scale = zoomScale
    func point(_ marker: DrawingMarker) -> NSPoint {
      NSPoint(
        x: xForColumn(marker.col) + CGFloat(marker.colOffset) / 12_700 * scale,
        y: yForRow(marker.row) + CGFloat(marker.rowOffset) / 12_700 * scale)
    }
    let origin = point(placement.from)
    let end: NSPoint
    if let to = placement.to {
      end = point(to)
    } else {
      let size = placement.size ?? CGSize(width: 480, height: 288)
      end = NSPoint(x: origin.x + size.width * scale, y: origin.y + size.height * scale)
    }
    return NSRect(
      x: origin.x, y: origin.y, width: max(0, end.x - origin.x), height: max(0, end.y - origin.y))
  }

  func scrollChartIntoView(id: UUID) {
    guard let chart = viewModel?.activeSheet.charts.first(where: { $0.id == id }) else { return }
    scrollIntoView(chartRect(for: chart))
  }

  func scrollImportedChartIntoView(id: Int) {
    guard let placement = viewModel?.importedChartPlacements.first(where: { $0.id == id })
    else { return }
    scrollIntoView(importedChartRect(placement))
  }

  private func scrollIntoView(_ rect: NSRect) {
    let visible = contentRect
    if rect.width > visible.width {
      scrollOrigin.x -= visible.minX - rect.minX
    } else if rect.minX < visible.minX {
      scrollOrigin.x -= visible.minX - rect.minX
    } else if rect.maxX > visible.maxX {
      scrollOrigin.x += rect.maxX - visible.maxX
    }
    if rect.height > visible.height {
      scrollOrigin.y -= visible.minY - rect.minY
    } else if rect.minY < visible.minY {
      scrollOrigin.y -= visible.minY - rect.minY
    } else if rect.maxY > visible.maxY {
      scrollOrigin.y += rect.maxY - visible.maxY
    }
    clampScrollOrigin()
    layoutOnSheetCharts()
    needsDisplay = true
  }

  private func removeChartHosts() {
    for host in chartHosts.values {
      host.removeFromSuperview()
    }
    chartHosts.removeAll()
    chartHostSnapshots.removeAll()
    for id in Array(importedChartHosts.keys) {
      removeImportedChartHost(id: id)
    }
  }

  private func removeChartHost(id: UUID) {
    chartHosts[id]?.removeFromSuperview()
    chartHosts.removeValue(forKey: id)
    chartHostSnapshots.removeValue(forKey: id)
    chartHovers.removeValue(forKey: id)
  }

  private func chartRect(for chart: SheetChart) -> NSRect {
    let scale = zoomScale
    return OnSheetChartGeometry.frame(
      anchorRow: chart.anchorRow,
      anchorCol: chart.anchorCol,
      rowSpan: chart.rowSpan,
      colSpan: chart.colSpan,
      rowCount: rowCount(),
      columnCount: columnCount(),
      originXOffset: chart.originXOffset * scale,
      originYOffset: chart.originYOffset * scale,
      endXOffset: chart.endXOffset * scale,
      endYOffset: chart.endYOffset * scale,
      xForColumn: { self.xForColumn($0) },
      yForRow: { self.yForRow($0) },
      columnWidth: { self.columnWidth(at: $0) },
      rowHeight: { self.rowHeight(at: $0) }
    )
  }

  private func cursor(for handle: OnSheetChartGeometry.ChartFrameHandle) -> NSCursor {
    switch handle {
    case .body:
      return .openHand
    case .left, .right:
      return .resizeLeftRight
    case .top, .bottom:
      return .resizeUpDown
    case .topLeft, .topRight, .bottomLeft, .bottomRight:
      return .crosshair
    }
  }

  /// The chart from the file under `point`, topmost first.
  private func importedChartHitTest(at point: NSPoint)
    -> SpreadsheetViewModel.ImportedChartPlacement?
  {
    guard contentRect.contains(point), !pointIsCoveredByFrozenPane(point),
      let placements = viewModel?.importedChartPlacements
    else { return nil }
    let selected = viewModel?.selectedImportedChartID
    return placements.reversed().first { placement in
      var rect = importedChartRect(placement)
      guard rect.width >= 8, rect.height >= 8 else { return false }
      // A selected chart's handles sit on its border, half outside it. Grab all of each one.
      if placement.id == selected {
        rect = rect.insetBy(dx: -chartHandleThickness / 2, dy: -chartHandleThickness / 2)
      }
      return rect.contains(point)
    }
  }

  /// The frame a drag gives a chart from the file: moved by the body, or resized by an edge
  /// or corner. Its top-left stays inside the sheet and it keeps a readable size.
  private static func importedChartFrame(
    _ drag: ImportedChartDrag, dx: CGFloat, dy: CGFloat, headerSize: CGFloat
  ) -> NSRect {
    let start = drag.startRect
    let minWidth: CGFloat = 120
    let minHeight: CGFloat = 80
    var minX = start.minX
    var minY = start.minY
    var maxX = start.maxX
    var maxY = start.maxY
    switch drag.handle {
    case .body:
      minX = max(headerSize, start.minX + dx)
      minY = max(headerSize, start.minY + dy)
      return NSRect(x: minX, y: minY, width: start.width, height: start.height)
    case .left, .topLeft, .bottomLeft:
      minX = min(max(headerSize, start.minX + dx), maxX - minWidth)
    case .right, .topRight, .bottomRight:
      maxX = max(start.maxX + dx, minX + minWidth)
    case .top, .bottom:
      break
    }
    switch drag.handle {
    case .top, .topLeft, .topRight:
      minY = min(max(headerSize, start.minY + dy), maxY - minHeight)
    case .bottom, .bottomLeft, .bottomRight:
      maxY = max(start.maxY + dy, minY + minHeight)
    default:
      break
    }
    return NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
  }

  /// Writes the moved or resized chart's anchor cells. Offsets are stored in EMU at 100% zoom.
  private func commitImportedChartDrag(_ drag: ImportedChartDrag, dx: CGFloat, dy: CGFloat) {
    guard let viewModel,
      let placement = viewModel.importedChartPlacements.first(where: { $0.id == drag.id })
    else { return }
    let scale = zoomScale
    func marker(at point: NSPoint) -> DrawingMarker {
      let col = max(0, columnAtContent(x: point.x))
      let row = max(0, rowAtContent(y: point.y))
      return DrawingMarker(
        col: col, colOffset: Int(max(0, (point.x - xForColumn(col)) / scale * 12_700)),
        row: row, rowOffset: Int(max(0, (point.y - yForRow(row)) / scale * 12_700)))
    }
    let rect = Self.importedChartFrame(drag, dx: dx, dy: dy, headerSize: headerSize)
    let from = marker(at: NSPoint(x: rect.minX, y: rect.minY))
    let to = placement.to == nil ? nil : marker(at: NSPoint(x: rect.maxX, y: rect.maxY))
    if drag.handle == .body {
      viewModel.moveImportedChart(placement.id, from: from, to: to)
    } else {
      viewModel.resizeImportedChart(
        placement.id, from: from, to: to,
        size: CGSize(width: rect.width / scale, height: rect.height / scale))
    }
  }

  private func chartHitTest(at point: NSPoint) -> SheetChart? {
    guard contentRect.contains(point), !pointIsCoveredByFrozenPane(point),
      let charts = viewModel?.activeSheet.charts
    else { return nil }
    for chart in charts.reversed() {
      let rect = chartRect(for: chart)
      if rect.width < 8 || rect.height < 8 { continue }
      if rect.contains(point) { return chart }
    }
    return nil
  }

  /// Frozen rows and columns stay above the chart, so a click there selects
  /// the cell. The scrollable part of the chart still hits.
  private func pointIsCoveredByFrozenPane(_ point: NSPoint) -> Bool {
    OnSheetChartGeometry.frozenPaneCovers(
      point,
      contentRect: contentRect,
      frozenColumnBoundaryX: frozenColumnBoundaryX(),
      frozenRowBoundaryY: frozenRowBoundaryY(),
      frozenColumns: frozenColumnCount(),
      frozenRows: frozenRowCount()
    )
  }

  private func frozenPaneCoverRects() -> [NSRect] {
    OnSheetChartGeometry.frozenPaneCoverRects(
      contentRect: contentRect,
      frozenColumnBoundaryX: frozenColumnBoundaryX(),
      frozenRowBoundaryY: frozenRowBoundaryY(),
      frozenColumns: frozenColumnCount(),
      frozenRows: frozenRowCount()
    )
  }

  /// Chart cursors stop at the freeze. The pane owns those cells.
  private func addScrollableCursorRect(_ rect: NSRect, cursor: NSCursor) {
    let visible = rect.intersection(scrollableCellsClipRect())
    guard !visible.isNull, visible.width >= 1, visible.height >= 1 else { return }
    addCursorRect(visible, cursor: cursor)
  }

  /// Sheet background, frozen cells, pictures, and the freeze divider, in the
  /// overlay's context. The chart layer is underneath, so where a chart has
  /// scrolled under the header or the frozen columns, these cells cover it.
  fileprivate func drawFrozenPanesCoveringCharts(in dirtyRect: NSRect) {
    let panes = frozenPaneCoverRects()
    guard !panes.isEmpty, let ctx = NSGraphicsContext.current else { return }

    ctx.saveGraphicsState()
    let cover = NSBezierPath()
    for rect in panes {
      cover.appendRect(rect)
    }
    cover.addClip()

    theme.canvas.setFill()
    for rect in panes {
      let hit = rect.intersection(dirtyRect)
      guard !hit.isNull, hit.width > 0.5, hit.height > 0.5 else { continue }
      hit.fill()
    }
    let skipGridlines = visibleRegionIsMostlyBordered()
    drawFrozenCells(in: dirtyRect)
    if !skipGridlines {
      drawFrozenGridLines(in: dirtyRect)
    }
    drawFrozenOverflowText(in: dirtyRect)
    // Pictures stay above frozen cells, including the strip that covers a chart.
    drawImages(in: dirtyRect)
    ctx.restoreGraphicsState()

    drawFreezeDividers(in: dirtyRect)
  }

  private func drawImageSelectionChrome(in rect: NSRect) {
    let accent = theme.accent
    accent.setStroke()
    let border = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
    border.lineWidth = 2
    border.stroke()
    let handle = imageResizeHandleRect(for: rect)
    theme.canvas.setFill()
    handle.fill()
    accent.setStroke()
    let handleBorder = NSBezierPath(rect: handle.insetBy(dx: 0.5, dy: 0.5))
    handleBorder.lineWidth = 1
    handleBorder.stroke()
  }

  private func imageResizeHandleRect(for imageRect: NSRect) -> NSRect {
    NSRect(x: imageRect.maxX - 7, y: imageRect.maxY - 7, width: 14, height: 14)
  }

  private func imageCursor(at point: NSPoint) -> NSCursor? {
    guard let viewModel else { return nil }
    if let selected = viewModel.selectedImageID.flatMap({ viewModel.image(with: $0) }) {
      if imageResizeHandleRect(for: imageRect(for: selected)).contains(point) {
        return .crosshair
      }
      if imageRect(for: selected).contains(point) {
        return activeImageDrag != nil ? .closedHand : .openHand
      }
    }
    if let hit = imageHitTest(at: point) {
      return activeImageDrag?.imageID == hit.id ? .closedHand : .openHand
    }
    return nil
  }

  private func imageHitTest(at point: NSPoint) -> SheetImage? {
    guard let sheet = viewModel?.activeSheet else { return nil }
    for image in sheet.images.reversed() {
      if imageRect(for: image).contains(point) { return image }
    }
    return nil
  }

  private func imageResizeHandleHit(at point: NSPoint, image: SheetImage) -> ImageResizeCorner? {
    let rect = imageRect(for: image)
    return imageResizeHandleRect(for: rect).contains(point) ? .bottomRight : nil
  }

  private func normalizeImagePlacement(
    row: Int,
    col: Int,
    rowOffsetEMU: Int,
    colOffsetEMU: Int
  ) -> (row: Int, col: Int, rowOffsetEMU: Int, colOffsetEMU: Int) {
    var r = max(0, row)
    var c = max(0, col)
    var rowPts = SheetImage.points(fromEMU: rowOffsetEMU)
    var colPts = SheetImage.points(fromEMU: colOffsetEMU)
    while colPts < -0.5, c > 0 {
      c -= 1
      colPts += columnWidth(at: c)
    }
    let maxCol = columnCount() - 1
    while colPts >= columnWidth(at: c) - 0.5, c < maxCol {
      colPts -= columnWidth(at: c)
      c += 1
    }
    while rowPts < -0.5, r > 0 {
      r -= 1
      rowPts += rowHeight(at: r)
    }
    let maxRow = rowCount() - 1
    while rowPts >= rowHeight(at: r) - 0.5, r < maxRow {
      rowPts -= rowHeight(at: r)
      r += 1
    }
    return (
      r,
      c,
      SheetImage.emu(fromPoints: max(0, rowPts)),
      SheetImage.emu(fromPoints: max(0, colPts))
    )
  }

  private func placementForImageTopLeft(x: CGFloat, y: CGFloat) -> (
    row: Int, col: Int, rowOffsetEMU: Int, colOffsetEMU: Int
  ) {
    let col = columnAtContent(x: max(headerSize, min(x, bounds.width - 1)))
    let row = rowAtContent(y: max(headerSize, min(y, bounds.height - 1)))
    let colPts = x - xForColumn(col)
    let rowPts = y - yForRow(row)
    return normalizeImagePlacement(
      row: row,
      col: col,
      rowOffsetEMU: SheetImage.emu(fromPoints: rowPts),
      colOffsetEMU: SheetImage.emu(fromPoints: colPts)
    )
  }

  @discardableResult
  private func handleImageMouseDown(at point: NSPoint, event: NSEvent) -> Bool {
    guard let viewModel else { return false }
    if let selectedID = viewModel.selectedImageID,
      let selected = viewModel.image(with: selectedID),
      imageResizeHandleHit(at: point, image: selected) != nil
    {
      viewModel.selectImage(id: selectedID, bringToFront: true)
      activeImageDrag = ImageDragState(
        imageID: selectedID,
        mode: .resize(.bottomRight),
        startPoint: point,
        startImage: selected
      )
      isDraggingSelection = false
      return true
    }
    if let hit = imageHitTest(at: point) {
      viewModel.selectImage(id: hit.id, bringToFront: true)
      activeImageDrag = ImageDragState(
        imageID: hit.id,
        mode: .move,
        startPoint: point,
        startImage: hit
      )
      isDraggingSelection = false
      return true
    }
    return false
  }

  private func applyImageDrag(to point: NSPoint) {
    guard let drag = activeImageDrag, let viewModel else { return }
    let deltaX = point.x - drag.startPoint.x
    let deltaY = point.y - drag.startPoint.y
    let startRect = imageRect(for: drag.startImage)
    switch drag.mode {
    case .move:
      let placement = placementForImageTopLeft(
        x: startRect.minX + deltaX,
        y: startRect.minY + deltaY
      )
      viewModel.setImagePlacement(
        id: drag.imageID,
        anchorRow: placement.row,
        anchorCol: placement.col,
        rowOffsetEMU: placement.rowOffsetEMU,
        colOffsetEMU: placement.colOffsetEMU
      )
    case .resize(.bottomRight):
      let startAspect = startRect.height / max(startRect.width, 1)
      var newWidth = max(12, startRect.width + deltaX)
      var newHeight = max(12, startRect.height + deltaY)
      if !NSEvent.modifierFlags.contains(.shift) {
        newHeight = max(12, newWidth * startAspect)
      }
      viewModel.setImagePlacement(
        id: drag.imageID,
        anchorRow: drag.startImage.anchorRow,
        anchorCol: drag.startImage.anchorCol,
        rowOffsetEMU: drag.startImage.rowOffsetEMU,
        colOffsetEMU: drag.startImage.colOffsetEMU,
        widthEMU: SheetImage.emu(fromPoints: newWidth),
        heightEMU: SheetImage.emu(fromPoints: newHeight)
      )
    }
    needsDisplay = true
  }

  /// Pointer delta in the flipped grid. Positive `dy` is downward.
  /// The chart layer is flipped the same way, so this is not negated:
  /// negating it raises the anchor when the pointer moves down.
  static func chartDragTranslation(dx: CGFloat, dy: CGFloat) -> CGSize {
    CGSize(width: dx, height: dy)
  }

  /// Command keeps the dragged edge on the pointer. Releasing it snaps to cell borders.
  static func chartDragUsesFreePlacement(modifierFlags: NSEvent.ModifierFlags) -> Bool {
    modifierFlags.contains(.command)
  }

  private func applyChartDrag(to point: NSPoint, freePlacement: Bool) {
    guard let drag = activeChartDrag, let viewModel else { return }
    let translation = Self.chartDragTranslation(
      dx: point.x - drag.startPoint.x,
      dy: point.y - drag.startPoint.y
    )
    let start = OnSheetChartGeometry.ChartFrameAnchor(
      anchorRow: drag.startChart.anchorRow,
      anchorCol: drag.startChart.anchorCol,
      rowSpan: drag.startChart.rowSpan,
      colSpan: drag.startChart.colSpan
    )
    // Column positions are viewport points, zoom included. Stored offsets are
    // sheet points so they still line up with the cell after the zoom changes.
    let scale = zoomScale
    let next = OnSheetChartGeometry.anchorAfterDrag(
      start: start,
      handle: drag.handle,
      startRect: drag.startRect,
      translation: translation,
      minimumSpan: SheetChart.minimumSpan,
      rowLimit: rowCount(),
      columnLimit: columnCount(),
      columnAt: { self.columnAtContent(x: $0) },
      rowAt: { self.rowAtContent(y: $0) },
      freePlacement: freePlacement,
      xForColumn: { self.xForColumn($0) },
      yForRow: { self.yForRow($0) },
      columnWidth: { self.columnWidth(at: $0) },
      rowHeight: { self.rowHeight(at: $0) }
    )
    viewModel.setChartFrame(
      id: drag.chartID,
      anchorRow: next.anchorRow,
      anchorCol: next.anchorCol,
      rowSpan: next.rowSpan,
      colSpan: next.colSpan,
      originXOffset: next.originXOffset / scale,
      originYOffset: next.originYOffset / scale,
      endXOffset: next.endXOffset / scale,
      endYOffset: next.endYOffset / scale,
      preservingCustomFrom: drag.startChart
    )
    layoutOnSheetCharts()
    needsDisplay = true
  }

  private func finishChartDragIfNeeded() {
    guard let drag = activeChartDrag, let viewModel else {
      activeChartDrag = nil
      return
    }
    let actionName = drag.handle == .body ? "Move Chart" : "Resize Chart"
    viewModel.commitChartFrame(id: drag.chartID, before: drag.startChart, actionName: actionName)
    activeChartDrag = nil
    window?.invalidateCursorRects(for: self)
  }

  private func finishImageDragIfNeeded() {
    guard let drag = activeImageDrag, let viewModel else {
      activeImageDrag = nil
      return
    }
    viewModel.commitImagePlacement(id: drag.imageID, before: drag.startImage)
    activeImageDrag = nil
  }

  /// Paints the anchor fill for the slice of each merge that this pane shows.
  /// Covered cells are not drawn on their own, and the anchor's paint rect is
  /// clipped to whichever pane contains the anchor. A frozen header, a frozen
  /// column, or a scroll that moves the anchor off screen would otherwise leave
  /// the rest of the merge on the sheet background. Indexes stay inside this
  /// region so frozen and scrolled coordinates are not joined into one rect.
  private func drawMergedCellFills(
    in dirtyRect: NSRect,
    region: GridLineRegion,
    viewModel: SpreadsheetViewModel?,
    sheet: Sheet
  ) {
    guard !sheet.mergedRanges.isEmpty else { return }
    let frozenRows = frozenRowCount()
    let frozenCols = frozenColumnCount()
    let rowLimit = rowCount()
    let colLimit = columnCount()
    let rowLower: Int
    let rowUpper: Int
    let colLower: Int
    let colUpper: Int
    switch region {
    case .scrollable:
      rowLower = frozenRows
      rowUpper = rowLimit
      colLower = frozenCols
      colUpper = colLimit
    case .frozenCorner:
      rowLower = 0
      rowUpper = frozenRows
      colLower = 0
      colUpper = frozenCols
    case .frozenTop:
      rowLower = 0
      rowUpper = frozenRows
      colLower = frozenCols
      colUpper = colLimit
    case .frozenLeft:
      rowLower = frozenRows
      rowUpper = rowLimit
      colLower = 0
      colUpper = frozenCols
    }
    guard rowUpper > rowLower, colUpper > colLower else { return }

    for merge in sheet.mergedRanges {
      let n = merge.normalized
      guard n.maxRow > n.minRow || n.maxCol > n.minCol else { continue }
      let row0 = max(n.minRow, rowLower)
      let row1 = min(n.maxRow, rowUpper - 1)
      let col0 = max(n.minCol, colLower)
      let col1 = min(n.maxCol, colUpper - 1)
      guard row0 <= row1, col0 <= col1 else { continue }
      let anchor = CellAddress(row: n.minRow, col: n.minCol)
      if rasterTarget == nil, let viewModel, viewModel.isEditing, isEditorActive,
        viewModel.selectionAnchor == anchor
      {
        continue
      }
      let paint: ConditionalPaint
      if let viewModel {
        paint = viewModel.resolvedPaint(at: anchor)
      } else {
        let anchorCell = sheet.cell(at: anchor)
        paint = cachedCellPaint(at: anchor, viewModel: nil, sheet: sheet, cell: anchorCell).paint
      }
      guard let fill = CellFormatRenderer.fillColor(for: paint.format) else { continue }
      let minX = xForColumn(col0)
      let maxX = xForColumn(col1) + columnWidth(at: col1)
      let minY = yForRow(row0)
      let maxY = yForRow(row1) + rowHeight(at: row1)
      guard maxX - minX > 0.5, maxY - minY > 0.5 else { continue }
      let rect = NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
      guard dirtyRect.intersects(rect) else { continue }
      tileFill(rect, color: fill)
    }
  }

  private func drawCells(in dirtyRect: NSRect) {
    let viewModel = rasterViewModel()
    guard viewModel != nil || tileCapture != nil else { return }
    guard let sheet = sheetForLayout() ?? viewModel?.activeSheet else { return }
    tileClip(scrollableCellsClipRect()) {
      self.drawMergedCellFills(
        in: dirtyRect,
        region: .scrollable,
        viewModel: viewModel,
        sheet: sheet
      )
      for rowSpan in self.visibleRowSpans() {
        for colSpan in self.visibleColumnSpans() {
          self.drawScrollableCellBodies(
            in: dirtyRect,
            viewModel: viewModel,
            sheet: sheet,
            rowRange: rowSpan,
            colRange: colSpan
          )
        }
      }
    }
  }

  private func drawScrollableCellBodies(
    in dirtyRect: NSRect,
    viewModel: SpreadsheetViewModel?,
    sheet: Sheet,
    rowRange: ClosedRange<Int>,
    colRange: ClosedRange<Int>
  ) {
    let frozenRows = frozenRowCount()
    let frozenCols = frozenColumnCount()
    var borderItems: [(CellBorders, NSRect)] = []
    borderItems.reserveCapacity(256)
    var mergeBordersDrawn = Set<CellAddress>()
    let paneRowLower = max(rowRange.lowerBound, frozenRows)
    let paneColLower = max(colRange.lowerBound, frozenCols)
    let paneRows = paneRowLower <= rowRange.upperBound ? paneRowLower...rowRange.upperBound : nil
    let paneCols = paneColLower <= colRange.upperBound ? paneColLower...colRange.upperBound : nil
    for row in rowRange where row >= frozenRows {
      for col in colRange where col >= frozenCols {
        let address = CellAddress(row: row, col: col)
        let role = mergeRole(at: address, sheet: sheet)
        if case .covered = role {
          appendOffPaneMergeBorders(
            at: address,
            sheet: sheet,
            viewModel: viewModel,
            paneRows: paneRows,
            paneCols: paneCols,
            seen: &mergeBordersDrawn,
            borderItems: &borderItems
          )
          continue
        }
        let hasCell = sheet.cells[address] != nil
        if !hasCell, case .none = role, !sheet.tableContains(address) { continue }
        let cell = sheet.cell(at: address)
        guard let rect = paintRect(for: address, merge: mergeRange(from: role)) else { continue }
        guard isCellRectInContentArea(rect), dirtyRect.intersects(rect) else { continue }
        let cached = cachedCellPaint(at: address, viewModel: viewModel, sheet: sheet, cell: cell)
        drawCellContent(
          cell,
          at: address,
          rect: rect,
          viewModel: viewModel,
          paint: cached.paint,
          value: cached.value,
          displayText: cached.displayText
        )
        if let borders = cached.paint.format?.borders ?? cell.format?.borders,
          borders.hasAny
        {
          borderItems.append((borders, rect))
        }
      }
    }
    tileDrawBorders(borderItems)
  }

  private func tileDrawBorders(_ items: [(CellBorders, NSRect)]) {
    if let tileDrawList = recordingDrawList {
      let recorded = items
      let scale = zoomScale
      tileDrawList.commands.append {
        CellFormatRenderer.drawBordersBatch(recorded, scale: scale)
      }
    } else {
      CellFormatRenderer.drawBordersBatch(items, scale: zoomScale)
    }
  }

  private func drawFrozenRegionCells(
    in dirtyRect: NSRect,
    rowRange: ClosedRange<Int>,
    colRange: ClosedRange<Int>,
    clipRect: NSRect,
    viewModel: SpreadsheetViewModel?,
    sheet: Sheet,
    region: GridLineRegion,
    paintCells: Bool = true
  ) {
    guard !clipRect.isEmpty else { return }

    tileClip(clipRect) {
      self.drawMergedCellFills(in: dirtyRect, region: region, viewModel: viewModel, sheet: sheet)
      guard paintCells, !rowRange.isEmpty, !colRange.isEmpty else { return }
      self.drawFrozenRegionBodies(
        in: dirtyRect,
        rowRange: rowRange,
        colRange: colRange,
        viewModel: viewModel,
        sheet: sheet
      )
    }
  }

  private func drawFrozenRegionBodies(
    in dirtyRect: NSRect,
    rowRange: ClosedRange<Int>,
    colRange: ClosedRange<Int>,
    viewModel: SpreadsheetViewModel?,
    sheet: Sheet
  ) {
    var borderItems: [(CellBorders, NSRect)] = []
    borderItems.reserveCapacity(64)
    var mergeBordersDrawn = Set<CellAddress>()
    for row in rowRange {
      for col in colRange {
        let address = CellAddress(row: row, col: col)
        let role = mergeRole(at: address, sheet: sheet)
        if case .covered = role {
          appendOffPaneMergeBorders(
            at: address,
            sheet: sheet,
            viewModel: viewModel,
            paneRows: rowRange,
            paneCols: colRange,
            seen: &mergeBordersDrawn,
            borderItems: &borderItems
          )
          continue
        }
        let hasCell = sheet.cells[address] != nil
        if !hasCell, case .none = role, !sheet.tableContains(address) { continue }
        let cell = sheet.cell(at: address)
        guard let rect = paintRect(for: address, merge: mergeRange(from: role)) else { continue }
        guard dirtyRect.intersects(rect) else { continue }
        let cached = cachedCellPaint(at: address, viewModel: viewModel, sheet: sheet, cell: cell)
        drawCellContent(
          cell,
          at: address,
          rect: rect,
          viewModel: viewModel,
          paint: cached.paint,
          value: cached.value,
          displayText: cached.displayText
        )
        if let borders = cached.paint.format?.borders ?? cell.format?.borders,
          borders.hasAny
        {
          borderItems.append((borders, rect))
        }
      }
    }
    tileDrawBorders(borderItems)
  }

  /// Selection fill for every cell in the range — not only cells still stored after clearing text.
  private func drawSelectionWash(
    in dirtyRect: NSRect,
    rowRange: ClosedRange<Int>,
    colRange: ClosedRange<Int>,
    viewModel: SpreadsheetViewModel,
    sheet: Sheet
  ) {
    guard !suppressSelectionWash else { return }
    guard !rowRange.isEmpty, !colRange.isEmpty else { return }
    theme.selectionWash.setFill()

    for range in viewModel.selectionRanges {
      let n = range.normalized
      let rowLower = max(n.minRow, rowRange.lowerBound)
      let rowUpper = min(n.maxRow, rowRange.upperBound)
      let colLower = max(n.minCol, colRange.lowerBound)
      let colUpper = min(n.maxCol, colRange.upperBound)
      guard rowLower <= rowUpper, colLower <= colUpper else { continue }
      for row in rowLower...rowUpper {
        for col in colLower...colUpper {
          let address = CellAddress(row: row, col: col)
          if viewModel.isEditing, isEditorActive, address == viewModel.selectionAnchor { continue }
          // Every cell of a merge is washed, not only its top-left one, so a selected merge is
          // tinted across its whole width even when part of it is scrolled away.
          let rect = rectForCell(row: row, col: col)
          guard isCellRectInContentArea(rect), dirtyRect.intersects(rect) else { continue }
          rect.fill()
        }
      }
    }
  }

  /// Fill + text only. Borders are painted in a later coalesced pass.
  private func drawCellContent(
    _ cell: Cell,
    at address: CellAddress,
    rect: NSRect,
    viewModel: SpreadsheetViewModel?,
    paint: ConditionalPaint,
    value: CellValue,
    displayText: String
  ) {
    // A row a filter hides, or a hidden column, has no size. Its data bar or icon would still
    // paint a sliver at the edge of the cell beside it.
    guard rect.height >= 1, rect.width >= 1 else { return }
    if rasterTarget == nil, let viewModel,
      viewModel.isEditing && address == viewModel.selectionAnchor && isEditorActive
    {
      return
    }
    if tileCapture == nil {
      liveScrollCellVisits += 1
      if inGridDraw {
        testingGridVisits += 1
      } else {
        testingOverlayVisits += 1
      }
      if address.row > liveScrollMaxRow { liveScrollMaxRow = address.row }
    }
    let paintFormat = paint.format
    let fillColor = CellFormatRenderer.fillColor(for: paintFormat)
    if let fill = fillColor {
      tileFill(rect, color: fill)
    }

    // Selection color lives in the chrome overlay. Baking it into the plane
    // would keep the previous cell's text color after the selection moves.
    let isSelected = false
    let isDarkMode = paintIsDarkMode()

    if let fraction = paint.dataBarFraction, let color = paint.dataBarColor {
      drawDataBar(fraction: fraction, color: color, in: rect)
    }
    if let icon = paint.icon {
      drawIconSetGlyph(icon, in: rect)
    }

    let isFilterHeader = filterHeaderCell(row: address.row, col: address.col, viewModel: viewModel)
    let hideValue = paint.dataBarFraction != nil && paint.dataBarShowValue == false
    let drawFormat = paintFormat ?? cell.format ?? CellFormat()
    if !hideValue, cell.hasContent, !drawFormat.overflowsUnclipped {
      if !displayText.isEmpty {
        let textRect = textDrawingRect(
          in: rect, hasIcon: paint.icon != nil, isFilterHeader: isFilterHeader)
        drawPreparedText(
          displayText,
          value: value,
          format: drawFormat,
          textRect: textRect,
          clipRect: rect,
          fillColor: fillColor,
          isSelected: isSelected,
          isDarkMode: isDarkMode
        )
      }
    }

    if isFilterHeader {
      drawFilterAffordance(in: rect, over: fillColor, column: address.col)
    }
  }

  private func textDrawingRect(in cellRect: NSRect, hasIcon: Bool, isFilterHeader: Bool) -> NSRect {
    let insetX = 4 * zoomScale
    let insetY = 2 * zoomScale
    var textRect = cellRect.insetBy(dx: insetX, dy: insetY)
    if hasIcon {
      textRect.origin.x += 14 * zoomScale
      textRect.size.width = max(0, textRect.width - 14 * zoomScale)
    }
    if isFilterHeader {
      // Keep wrapped text clear of the bottom-right filter chip.
      textRect.size.width = max(0, textRect.width - 14 * zoomScale)
      textRect.size.height = max(0, textRect.height - 14 * zoomScale)
    }
    return textRect
  }

  /// Link blue as shown on the dark grid.
  static let darkModeLinkColor = CodableColor(
    red: 88.0 / 255, green: 166.0 / 255, blue: 255.0 / 255, alpha: 1)

  private func drawPreparedText(
    _ text: String,
    value: CellValue,
    format: CellFormat,
    textRect: NSRect,
    clipRect: NSRect,
    fillColor: NSColor?,
    isSelected: Bool,
    isDarkMode: Bool
  ) {
    guard !text.isEmpty, textRect.width > 1, textRect.height > 1, clipRect.width > 0.5,
      clipRect.height > 0.5
    else {
      return
    }
    if tileCapture == nil { liveScrollTextPaints += 1 }
    if tileCapture == nil { testingPaintedTexts?.insert(text) }
    var drawFormat = format
    let baseSize = drawFormat.fontSize ?? CellFormatRenderer.defaultFontSize
    drawFormat.fontSize = baseSize * zoomScale
    if value.isError {
      drawFormat.textColor = CellFormatRenderer.codableColor(from: theme.errorText)
    } else if isSelected {
      drawFormat.textColor = CellFormatRenderer.codableColor(
        from: Self.selectedCellTextColor(over: fillColor, theme: theme)
      )
    } else if isDarkMode, fillColor == nil,
      drawFormat.textColor == SpreadsheetViewModel.linkTextColor
    {
      // Link blue is dim on the dark grid; the file keeps it, the screen shows it lighter.
      drawFormat.textColor = Self.darkModeLinkColor
    } else if isDarkMode, drawFormat.textColor == nil, let fillColor {
      // Automatic text is white in dark mode. On a file's light fill, such as a totals row,
      // it was nearly invisible; it now follows the fill, as conditional fills already do.
      drawFormat.textColor = CodableColor.contrastingText(
        on: CellFormatRenderer.codableColor(from: fillColor))
    }
    let recordedText = text
    let recordedRect = textRect
    let recordedClip = clipRect
    let recordedFormat = drawFormat
    if let tileDrawList = recordingDrawList {
      tileDrawList.commands.append {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: recordedClip).addClip()
        CellFormatRenderer.drawText(recordedText, in: recordedRect, format: recordedFormat)
        NSGraphicsContext.restoreGraphicsState()
      }
      return
    }
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(rect: clipRect).addClip()
    CellFormatRenderer.drawText(text, in: textRect, format: drawFormat)
    NSGraphicsContext.restoreGraphicsState()
  }

  /// `onlyRows` limits the pass to those rows, for a repaint of a few cells.
  private func drawScrollableOverflowText(in dirtyRect: NSRect, onlyRows: Set<Int>? = nil) {
    let viewModel = rasterViewModel()
    guard viewModel != nil || tileCapture != nil else { return }
    guard let sheet = sheetForLayout() ?? viewModel?.activeSheet else { return }
    let frozenRows = frozenRowCount()
    let frozenCols = frozenColumnCount()
    let lastColumn = columnCount() - 1
    guard frozenCols <= lastColumn else { return }
    let clip = scrollableCellsClipRect()
    let pad = overflowColumnPad()
    let paneColumns = frozenCols...lastColumn
    // Each visible run of rows, or each of `onlyRows` that is on screen.
    var rowRuns: [ClosedRange<Int>] = []
    for rows in visibleRowSpans() {
      let rowLower = max(rows.lowerBound, frozenRows)
      guard rowLower <= rows.upperBound else { continue }
      if let onlyRows {
        rowRuns += onlyRows.filter { $0 >= rowLower && $0 <= rows.upperBound }.sorted().map {
          $0...$0
        }
      } else {
        rowRuns.append(rowLower...rows.upperBound)
      }
    }
    for cols in columnSpans(atOrAfter: frozenCols) {
      for rows in rowRuns {
        drawOverflowText(
          in: dirtyRect,
          rowRange: rows,
          visibleColumns: cols,
          paneColumns: paneColumns,
          clipRect: clip,
          viewModel: viewModel,
          sheet: sheet,
          columnPad: pad
        )
      }
    }
    // A title in the frozen columns keeps going through empty cells on this side of the freeze.
    if frozenCols > 0 {
      for rows in rowRuns {
        drawOverflowText(
          in: dirtyRect,
          rowRange: rows,
          visibleColumns: 0...(frozenCols - 1),
          paneColumns: 0...lastColumn,
          clipRect: clip,
          viewModel: viewModel,
          sheet: sheet,
          skipMerges: true,
          columnPad: 0
        )
      }
    }
  }

  private func drawFrozenOverflowText(in dirtyRect: NSRect) {
    let viewModel = rasterViewModel()
    guard viewModel != nil || tileCapture != nil else { return }
    guard let sheet = sheetForLayout() ?? viewModel?.activeSheet else { return }
    let frozenRows = frozenRowCount()
    let frozenCols = frozenColumnCount()
    let lastColumn = columnCount() - 1

    if frozenRows > 0 && frozenCols > 0 {
      drawOverflowText(
        in: dirtyRect,
        rowRange: 0...(frozenRows - 1),
        visibleColumns: 0...(frozenCols - 1),
        paneColumns: 0...(frozenCols - 1),
        clipRect: frozenCellsClipRect(),
        viewModel: viewModel,
        sheet: sheet,
        columnPad: overflowColumnPad()
      )
    }
    if frozenRows > 0, frozenCols <= lastColumn {
      let clip = frozenTopStripClipRect()
      let pad = overflowColumnPad()
      let paneColumns = frozenCols...lastColumn
      for cols in columnSpans(atOrAfter: frozenCols) {
        drawOverflowText(
          in: dirtyRect,
          rowRange: 0...(frozenRows - 1),
          visibleColumns: cols,
          paneColumns: paneColumns,
          clipRect: clip,
          viewModel: viewModel,
          sheet: sheet,
          columnPad: pad
        )
      }
    }
    if frozenCols > 0 {
      let clip = frozenLeftStripClipRect()
      let pad = overflowColumnPad()
      for rows in visibleRowSpans() {
        let rowLower = max(rows.lowerBound, frozenRows)
        guard rowLower <= rows.upperBound else { continue }
        drawOverflowText(
          in: dirtyRect,
          rowRange: rowLower...rows.upperBound,
          visibleColumns: 0...(frozenCols - 1),
          paneColumns: 0...(frozenCols - 1),
          clipRect: clip,
          viewModel: viewModel,
          sheet: sheet,
          columnPad: pad
        )
      }
    }
  }

  /// How far past this paint spill text is allowed to start. One screen, and
  /// never more than the old whole-sheet search. A tile therefore does not
  /// measure every column on the sheet.
  private func overflowColumnPad() -> CGFloat {
    let span = contentRect.width
    if span >= 4_000 { return 4_000 }
    if span >= 512 { return span }
    return 512
  }

  private func drawOverflowText(
    in dirtyRect: NSRect,
    rowRange: ClosedRange<Int>,
    visibleColumns: ClosedRange<Int>,
    paneColumns: ClosedRange<Int>,
    clipRect: NSRect,
    viewModel: SpreadsheetViewModel?,
    sheet: Sheet,
    skipMerges: Bool = false,
    columnPad: CGFloat = 4000
  ) {
    guard !clipRect.isEmpty, !rowRange.isEmpty, !visibleColumns.isEmpty, !paneColumns.isEmpty else {
      return
    }
    let isDarkMode = paintIsDarkMode()

    let paneScrollsY = frozenRowCount() > 0 && rowRange.lowerBound >= frozenRowCount()
    tileClip(clipRect) {
      self.paintOverflowCells(
        in: dirtyRect,
        rowRange: rowRange,
        visibleColumns: visibleColumns,
        paneColumns: paneColumns,
        columnPad: columnPad,
        paneScrollsY: paneScrollsY,
        viewModel: viewModel,
        sheet: sheet,
        isDarkMode: isDarkMode,
        skipMerges: skipMerges
      )
    }
  }

  private func paintOverflowCells(
    in dirtyRect: NSRect,
    rowRange: ClosedRange<Int>,
    visibleColumns: ClosedRange<Int>,
    paneColumns: ClosedRange<Int>,
    columnPad: CGFloat,
    paneScrollsY: Bool,
    viewModel: SpreadsheetViewModel?,
    sheet: Sheet,
    isDarkMode: Bool,
    skipMerges: Bool
  ) {
    var painted = Set<CellAddress>()
    for row in rowRange {
      let columns = overflowColumnSpan(
        row: row,
        visible: visibleColumns,
        pane: paneColumns,
        pad: columnPad,
        sheet: sheet
      )
      for col in columns {
        let address = CellAddress(row: row, col: col)
        switch mergeRole(at: address, sheet: sheet) {
        case .covered:
          if skipMerges { continue }
          guard let merge = sheet.mergeContaining(address) else { continue }
          let span = merge.normalized
          paintOverflowCell(
            address: CellAddress(row: span.minRow, col: span.minCol),
            merge: merge,
            painted: &painted,
            dirtyRect: dirtyRect,
            paneColumns: paneColumns,
            paneScrollsY: paneScrollsY,
            viewModel: viewModel,
            sheet: sheet,
            isDarkMode: isDarkMode
          )
        case .anchor(let merge):
          if skipMerges { continue }
          paintOverflowCell(
            address: address,
            merge: merge,
            painted: &painted,
            dirtyRect: dirtyRect,
            paneColumns: paneColumns,
            paneScrollsY: paneScrollsY,
            viewModel: viewModel,
            sheet: sheet,
            isDarkMode: isDarkMode
          )
        case .none:
          paintOverflowCell(
            address: address,
            merge: nil,
            painted: &painted,
            dirtyRect: dirtyRect,
            paneColumns: paneColumns,
            paneScrollsY: paneScrollsY,
            viewModel: viewModel,
            sheet: sheet,
            isDarkMode: isDarkMode
          )
        }
      }
    }
  }

  /// One cell's overflow text. A merge is drawn from its anchor in every pane the
  /// merge crosses, clipped to that pane, so a frozen column does not end the sentence.
  /// A merge that starts inside the frozen pane is left out of a scrolling bitmap;
  /// `drawPinnedCrossFreezeMergeText` keeps that text fixed and clipped at the boundary.
  private func paintOverflowCell(
    address: CellAddress,
    merge: CellRange?,
    painted: inout Set<CellAddress>,
    dirtyRect: NSRect,
    paneColumns: ClosedRange<Int>,
    paneScrollsY: Bool,
    viewModel: SpreadsheetViewModel?,
    sheet: Sheet,
    isDarkMode: Bool
  ) {
    let recordingTile = tileCapture != nil || rasterTarget != nil
    if recordingTile, let merge,
      crossFreezeMergeMovesWithPane(merge, paneColumns: paneColumns, paneScrollsY: paneScrollsY)
    {
      return
    }
    if !painted.insert(address).inserted { return }
    let cell = sheet.cell(at: address)
    guard cell.hasContent else { return }
    if rasterTarget == nil, let viewModel,
      viewModel.isEditing && address == viewModel.selectionAnchor && isEditorActive
    {
      return
    }
    let cached = cachedCellPaint(at: address, viewModel: viewModel, sheet: sheet, cell: cell)
    let paint = cached.paint
    let format = paint.format ?? cell.format ?? CellFormat()
    guard format.overflowsUnclipped else { return }
    if paint.dataBarFraction != nil && paint.dataBarShowValue == false { return }
    let text = cached.displayText
    guard !text.isEmpty else { return }
    guard let cellRect = paintRect(for: address, merge: merge) else { return }
    let isFilterHeader = filterHeaderCell(row: address.row, col: address.col, viewModel: viewModel)
    let textRect = textDrawingRect(
      in: cellRect, hasIcon: paint.icon != nil, isFilterHeader: isFilterHeader)
    guard textRect.width > 1, textRect.height > 1 else { return }

    let sourceColumns: ClosedRange<Int>
    if let merge {
      let span = merge.normalized
      sourceColumns = span.minCol...span.maxCol
    } else {
      sourceColumns = address.col...address.col
    }
    var measureFormat = format
    let baseSize = measureFormat.fontSize ?? CellFormatRenderer.defaultFontSize
    measureFormat.fontSize = baseSize * zoomScale
    if tileCapture == nil { liveScrollTextPaints += 1 }
    if tileCapture == nil { testingPaintedTexts?.insert(text) }
    let textWidth = CellFormatRenderer.overflowWidth(for: text, format: measureFormat)
    let row = address.row
    // Full size. A merge that is narrower than the sentence continues through empty cells
    // to its right. Those cells are only covered while drawing; the sheet is not changed.
    let horizontal = CellTextLayout.overflowClip(
      cellMinX: textRect.minX,
      cellMaxX: textRect.maxX,
      textWidth: textWidth,
      alignment: format.horizontalAlign,
      insetX: 4,
      sourceColumns: sourceColumns,
      paneColumns: paneColumns,
      columnOrigin: { self.xForColumn($0) },
      columnWidth: { self.columnWidth(at: $0) },
      blocks: { column in
        guard column >= 0, row >= 0 else { return true }
        if sourceColumns.contains(column) { return false }
        let neighborAddress = CellAddress(row: row, col: column)
        let neighborRole = self.mergeRole(at: neighborAddress, sheet: sheet)
        if case .none = neighborRole {
          let neighbor = sheet.cell(at: neighborAddress)
          guard neighbor.hasContent else { return false }
          return !self.cachedCellPaint(
            at: neighborAddress,
            viewModel: viewModel,
            sheet: sheet,
            cell: neighbor
          ).displayText.isEmpty
        }
        return true
      }
    )
    let spill = NSRect(
      x: horizontal.minX, y: cellRect.minY, width: horizontal.width, height: cellRect.height)
    guard spill.width > 0.5, dirtyRect.intersects(spill) else { return }
    let fillColor = CellFormatRenderer.fillColor(for: paint.format)
    let spillsPastCell =
      horizontal.minX < cellRect.minX - 0.5 || horizontal.maxX > cellRect.maxX + 0.5
    if spillsPastCell || merge != nil {
      // Cover borders and fills that would otherwise stroke through the glyphs.
      let background = fillColor ?? theme.canvas
      let cover = spillsPastCell ? spill : cellRect.insetBy(dx: 1, dy: 1)
      if cover.width > 0.5, cover.height > 0.5 {
        tileFill(cover, color: background)
      }
    }
    drawPreparedText(
      text,
      value: cached.value,
      format: format,
      textRect: textRect,
      clipRect: spill,
      fillColor: fillColor,
      isSelected: false,
      isDarkMode: isDarkMode
    )
    if isFilterHeader {
      drawFilterAffordance(in: cellRect, over: fillColor, column: address.col)
    }
  }

  /// The anchor lives in another pane. This pane still draws the merge's outer borders.
  private func appendOffPaneMergeBorders(
    at address: CellAddress,
    sheet: Sheet,
    viewModel: SpreadsheetViewModel?,
    paneRows: ClosedRange<Int>?,
    paneCols: ClosedRange<Int>?,
    seen: inout Set<CellAddress>,
    borderItems: inout [(CellBorders, NSRect)]
  ) {
    guard let merge = sheet.mergeContaining(address) else { return }
    let span = merge.normalized
    let anchor = CellAddress(row: span.minRow, col: span.minCol)
    guard let paneRows, let paneCols else { return }
    guard !paneRows.contains(anchor.row) || !paneCols.contains(anchor.col) else { return }
    guard seen.insert(anchor).inserted else { return }
    guard let rect = paintRect(for: anchor, merge: merge) else { return }
    let anchorCell = sheet.cell(at: anchor)
    let cached = cachedCellPaint(at: anchor, viewModel: viewModel, sheet: sheet, cell: anchorCell)
    if let borders = cached.paint.format?.borders ?? anchorCell.format?.borders, borders.hasAny {
      borderItems.append((borders, rect))
    }
  }

  /// Columns whose text can still reach this row's visible cells.
  /// Spill stops at the next non-empty cell, so a point pad does not have to
  /// format every narrow column in that distance.
  private func overflowColumnSpan(
    row: Int,
    visible: ClosedRange<Int>,
    pane: ClosedRange<Int>,
    pad: CGFloat,
    sheet: Sheet
  ) -> ClosedRange<Int> {
    var lower = visible.lowerBound
    var used: CGFloat = 0
    while lower > pane.lowerBound && used < pad {
      let next = lower - 1
      used += columnWidth(at: next)
      lower = next
      if overflowSourceBlocks(row: row, col: next, sheet: sheet) { break }
    }
    var upper = visible.upperBound
    used = 0
    while upper < pane.upperBound && used < pad {
      let next = upper + 1
      used += columnWidth(at: next)
      upper = next
      if overflowSourceBlocks(row: row, col: next, sheet: sheet) { break }
    }
    return lower...upper
  }

  /// A non-empty cell or a merge ends the spill, same as the clip walk.
  private func overflowSourceBlocks(row: Int, col: Int, sheet: Sheet) -> Bool {
    guard row >= 0, col >= 0 else { return true }
    let address = CellAddress(row: row, col: col)
    switch mergeRole(at: address, sheet: sheet) {
    case .anchor, .covered:
      return true
    case .none:
      return sheet.cell(at: address).hasContent
    }
  }

  /// Include columns just outside the viewport so spill from an off-screen cell can still paint.
  private func extendedColumnRange(
    around visible: ClosedRange<Int>, within pane: ClosedRange<Int>, pad: CGFloat = 4000
  ) -> ClosedRange<Int> {
    var lower = max(pane.lowerBound, visible.lowerBound)
    var width: CGFloat = 0
    while lower > pane.lowerBound && width < pad {
      lower -= 1
      width += columnWidth(at: lower)
    }
    var upper = min(pane.upperBound, visible.upperBound)
    width = 0
    while upper < pane.upperBound && width < pad {
      upper += 1
      width += columnWidth(at: upper)
    }
    return lower...upper
  }

  private func drawDataBar(fraction: Double, color: CodableColor, in rect: NSRect) {
    let pad = 2 * zoomScale
    let height = max(4 * zoomScale, rect.height - pad * 2)
    let maxWidth = max(0, rect.width - pad * 2)
    let width = maxWidth * CGFloat(min(1, max(0, fraction)))
    guard width > 0.5 else { return }
    let bar = NSRect(
      x: rect.minX + pad,
      y: rect.midY - height / 2,
      width: width,
      height: height
    )
    let paint = NSColor(
      calibratedRed: color.red,
      green: color.green,
      blue: color.blue,
      alpha: 0.72
    )
    let radius = 2 * zoomScale
    let path = NSBezierPath(roundedRect: bar, xRadius: radius, yRadius: radius)
    if let tileDrawList = recordingDrawList {
      let recorded = resolvedDrawColor(paint)
      tileDrawList.commands.append {
        recorded.setFill()
        path.fill()
      }
    } else {
      paint.setFill()
      path.fill()
    }
  }

  private func drawIconSetGlyph(_ glyph: IconSetGlyph, in rect: NSRect) {
    let size = min(12 * zoomScale, rect.height - 4 * zoomScale)
    guard size > 4 else { return }
    let origin = NSPoint(x: rect.minX + 3 * zoomScale, y: rect.midY - size / 2)
    let box = NSRect(origin: origin, size: NSSize(width: size, height: size))
    switch glyph {
    case .greenCircle, .yellowCircle, .redCircle:
      let color: NSColor = {
        switch glyph {
        case .greenCircle: return .systemGreen
        case .yellowCircle: return .systemYellow
        default: return .systemRed
        }
      }()
      tileFillPath(NSBezierPath(ovalIn: box.insetBy(dx: 1, dy: 1)), color: color)
    case .greenArrow, .yellowArrow, .redArrow:
      let color: NSColor = {
        switch glyph {
        case .greenArrow: return .systemGreen
        case .yellowArrow: return .systemYellow
        default: return .systemRed
        }
      }()
      let path = NSBezierPath()
      if glyph == .yellowArrow {
        path.move(to: NSPoint(x: box.minX, y: box.midY))
        path.line(to: NSPoint(x: box.maxX, y: box.midY))
        path.line(to: NSPoint(x: box.maxX - size * 0.25, y: box.midY - size * 0.25))
        path.move(to: NSPoint(x: box.maxX, y: box.midY))
        path.line(to: NSPoint(x: box.maxX - size * 0.25, y: box.midY + size * 0.25))
        path.lineWidth = 1.5 * zoomScale
        tileStroke(path, color: color)
      } else if glyph == .greenArrow {
        // Flipped grid: the green arrow's tip is at the top, the red arrow's at the bottom.
        path.move(to: NSPoint(x: box.midX, y: box.minY))
        path.line(to: NSPoint(x: box.minX + 1, y: box.maxY - size * 0.35))
        path.line(to: NSPoint(x: box.maxX - 1, y: box.maxY - size * 0.35))
        path.close()
        tileFillPath(path, color: color)
      } else {
        path.move(to: NSPoint(x: box.midX, y: box.maxY))
        path.line(to: NSPoint(x: box.minX + 1, y: box.minY + size * 0.35))
        path.line(to: NSPoint(x: box.maxX - 1, y: box.minY + size * 0.35))
        path.close()
        tileFillPath(path, color: color)
      }
    case .greenCheck, .yellowDash, .redX:
      let color: NSColor = {
        switch glyph {
        case .greenCheck: return .systemGreen
        case .yellowDash: return .systemYellow
        default: return .systemRed
        }
      }()
      let path = NSBezierPath()
      path.lineWidth = 1.6 * zoomScale
      path.lineCapStyle = .round
      switch glyph {
      case .greenCheck:
        // The grid is flipped: larger y is lower. The tick dips down, then rises to the right.
        path.move(to: NSPoint(x: box.minX + size * 0.15, y: box.midY))
        path.line(to: NSPoint(x: box.midX - size * 0.05, y: box.maxY - size * 0.2))
        path.line(to: NSPoint(x: box.maxX - size * 0.1, y: box.minY + size * 0.15))
      case .yellowDash:
        path.move(to: NSPoint(x: box.minX + size * 0.15, y: box.midY))
        path.line(to: NSPoint(x: box.maxX - size * 0.15, y: box.midY))
      default:
        path.move(to: NSPoint(x: box.minX + size * 0.2, y: box.minY + size * 0.2))
        path.line(to: NSPoint(x: box.maxX - size * 0.2, y: box.maxY - size * 0.2))
        path.move(to: NSPoint(x: box.maxX - size * 0.2, y: box.minY + size * 0.2))
        path.line(to: NSPoint(x: box.minX + size * 0.2, y: box.maxY - size * 0.2))
      }
      tileStroke(path, color: color)
    }
  }

  private func drawFrozenCells(in dirtyRect: NSRect) {
    let viewModel = rasterViewModel()
    guard viewModel != nil || tileCapture != nil else { return }
    guard let sheet = sheetForLayout() ?? viewModel?.activeSheet else { return }
    let frozenRows = frozenRowCount()
    let frozenCols = frozenColumnCount()

    if frozenRows > 0 && frozenCols > 0 {
      drawFrozenRegionCells(
        in: dirtyRect,
        rowRange: 0...(frozenRows - 1),
        colRange: 0...(frozenCols - 1),
        clipRect: frozenCellsClipRect(),
        viewModel: viewModel,
        sheet: sheet,
        region: .frozenCorner
      )
    }
    if frozenRows > 0 {
      let spans = columnSpans(atOrAfter: frozenCols)
      let clip = frozenTopStripClipRect()
      if spans.isEmpty {
        drawFrozenRegionCells(
          in: dirtyRect,
          rowRange: 0...(frozenRows - 1),
          colRange: 0...0,
          clipRect: clip,
          viewModel: viewModel,
          sheet: sheet,
          region: .frozenTop,
          paintCells: false
        )
      } else {
        for cols in spans {
          drawFrozenRegionCells(
            in: dirtyRect,
            rowRange: 0...(frozenRows - 1),
            colRange: cols,
            clipRect: clip,
            viewModel: viewModel,
            sheet: sheet,
            region: .frozenTop
          )
        }
      }
    }
    if frozenCols > 0 {
      let clip = frozenLeftStripClipRect()
      for rows in visibleRowSpans() {
        let rowLower = max(rows.lowerBound, frozenRows)
        guard rowLower <= rows.upperBound else { continue }
        drawFrozenRegionCells(
          in: dirtyRect,
          rowRange: rowLower...rows.upperBound,
          colRange: 0...(frozenCols - 1),
          clipRect: clip,
          viewModel: viewModel,
          sheet: sheet,
          region: .frozenLeft
        )
      }
    }
  }

  /// Selection, formula highlights, and the fill handle. Drawn above scroll planes.
  fileprivate func drawSelectionChrome(in dirtyRect: NSRect) {
    guard viewModel != nil else { return }
    beginDrawLayout()
    defer { endDrawLayout() }
    guard let viewModel, let sheet = layoutSheet else { return }
    // Clip each pane's wash to that pane. A cell scrolled part-way under the
    // headers or a frozen pane must not show through the corner or across the freeze.
    let shaded = viewModel.duplicateHighlightCells
    let shade = (viewModel.duplicateHighlight?.unique == true ? NSColor.systemGreen : .systemRed)
      .withAlphaComponent(0.28)
    for (rows, cols, clip) in onScreenSelectionRegions() {
      guard clip.width > 0.5, clip.height > 0.5, dirtyRect.intersects(clip) else { continue }
      NSGraphicsContext.saveGraphicsState()
      NSBezierPath(rect: clip).addClip()
      if !shaded.isEmpty {
        drawDuplicateShading(shaded, color: shade, rows: rows, cols: cols, in: dirtyRect)
      }
      drawSelectionWash(
        in: dirtyRect,
        rowRange: rows,
        colRange: cols,
        viewModel: viewModel,
        sheet: sheet
      )
      NSGraphicsContext.restoreGraphicsState()
    }
    drawFormulaReferenceHighlights(in: dirtyRect)
    drawCommentMarks(in: dirtyRect, sheet: sheet)
    drawPageBreaks(in: dirtyRect, sheet: sheet)
    drawDropdownHints(in: dirtyRect, sheet: sheet)
    drawSelection(in: dirtyRect)
    drawDropdownButton(in: dirtyRect)
    drawHeaderSelectionChrome(in: dirtyRect)
  }

  /// The temporary Duplicates highlight, over the cells it marks in one pane.
  private func drawDuplicateShading(
    _ cells: Set<CellAddress>, color: NSColor, rows: ClosedRange<Int>, cols: ClosedRange<Int>,
    in dirtyRect: NSRect
  ) {
    color.setFill()
    for row in rows where rowHeight(at: row) > 0 {
      for col in cols where cells.contains(CellAddress(row: row, col: col)) {
        let rect = cellBorderRect(minRow: row, minCol: col, maxRow: row, maxCol: col)
        if rect.intersects(dirtyRect) { rect.fill() }
      }
    }
  }

  /// A small corner triangle on each cell that has a comment, as other spreadsheet apps draw it.
  /// A small speech bubble in the top-right corner of each cell with a comment. A red corner
  /// triangle read as an error, or as part of a dropdown.
  /// Manual page breaks: a dashed line above the row or left of the column that starts a page.
  private func drawPageBreaks(in dirtyRect: NSRect, sheet: Sheet) {
    let extras = sheet.fileExtras
    guard !extras.rowBreaks.isEmpty || !extras.columnBreaks.isEmpty else { return }
    let frozenRows = frozenRowCount()
    let frozenCols = frozenColumnCount()
    // Scrolled rows and columns pass under the frozen ones.
    let scrolledTop =
      frozenRows > 0 ? yForRow(frozenRows - 1) + rowHeight(at: frozenRows - 1) : headerSize
    let scrolledLeft =
      frozenCols > 0 ? xForColumn(frozenCols - 1) + columnWidth(at: frozenCols - 1) : headerSize
    let path = NSBezierPath()
    path.lineWidth = max(1, zoomScale)
    path.setLineDash([4 * zoomScale, 3 * zoomScale], count: 2, phase: 0)
    for row in extras.rowBreaks {
      let y = yForRow(row).rounded() + 0.5
      let top = row < frozenRows ? headerSize : scrolledTop
      guard y > top, y >= dirtyRect.minY - 1, y <= dirtyRect.maxY + 1 else { continue }
      path.move(to: NSPoint(x: headerSize, y: y))
      path.line(to: NSPoint(x: bounds.maxX, y: y))
    }
    for col in extras.columnBreaks {
      let x = xForColumn(col).rounded() + 0.5
      let left = col < frozenCols ? headerSize : scrolledLeft
      guard x > left, x >= dirtyRect.minX - 1, x <= dirtyRect.maxX + 1 else { continue }
      path.move(to: NSPoint(x: x, y: headerSize))
      path.line(to: NSPoint(x: x, y: bounds.maxY))
    }
    guard !path.isEmpty else { return }
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(
      rect: NSRect(
        x: headerSize, y: headerSize, width: max(0, bounds.width - headerSize),
        height: max(0, bounds.height - headerSize))
    ).addClip()
    NSColor.secondaryLabelColor.setStroke()
    path.stroke()
    NSGraphicsContext.restoreGraphicsState()
  }

  private func drawCommentMarks(in dirtyRect: NSRect, sheet: Sheet) {
    let comments = sheet.fileExtras.comments
    guard !comments.isEmpty else { return }
    let width = 8 * zoomScale
    let height = 6.5 * zoomScale
    let inset = 1.5 * zoomScale
    for comment in comments {
      let address = sheet.mergeAnchor(for: comment.address)
      let span = sheet.mergeContaining(address) ?? CellRange(start: address, end: address)
      let n = span.normalized
      let rect = cellBorderRect(
        minRow: n.minRow, minCol: n.minCol, maxRow: n.maxRow, maxCol: n.maxCol)
      guard rect.width > width * 2, rect.height > height + inset * 2, dirtyRect.intersects(rect),
        isCellRectInContentArea(rect)
      else { continue }
      let clip = paneClipRect(for: span)
      guard clip.width > 0.5, clip.height > 0.5 else { continue }
      NSGraphicsContext.saveGraphicsState()
      NSBezierPath(rect: clip).addClip()
      // Flipped: y grows down, so the tail hangs below the bubble's left side.
      let tail = 2 * zoomScale
      let body = NSRect(
        x: rect.maxX - inset - width, y: rect.minY + inset, width: width, height: height - tail)
      let bubble = NSBezierPath(roundedRect: body, xRadius: 2 * zoomScale, yRadius: 2 * zoomScale)
      bubble.move(to: NSPoint(x: body.minX + 2 * zoomScale, y: body.maxY - 0.5))
      bubble.line(to: NSPoint(x: body.minX + 2 * zoomScale, y: body.maxY + tail))
      bubble.line(to: NSPoint(x: body.minX + 5 * zoomScale, y: body.maxY - 0.5))
      bubble.close()
      NSColor.systemYellow.setFill()
      bubble.fill()
      NSColor.systemOrange.setStroke()
      bubble.lineWidth = max(0.75, 0.75 * zoomScale)
      bubble.stroke()
      NSGraphicsContext.restoreGraphicsState()
    }
  }

  /// A faint chevron at the right of every visible cell with a dropdown list, so the lists can
  /// be seen without selecting each cell. The selected cell draws its full button instead.
  private func drawDropdownHints(in dirtyRect: NSRect, sheet: Sheet) {
    let rules = sheet.fileExtras.dataValidations.filter(\.isList)
    guard !rules.isEmpty, let viewModel else { return }
    let selected = viewModel.selectionAnchor
    let w = 6 * zoomScale
    let h = 3.5 * zoomScale
    let color = theme.accent.withAlphaComponent(0.75)
    for (rows, cols, clip) in onScreenSelectionRegions() {
      guard dirtyRect.intersects(clip) else { continue }
      NSGraphicsContext.saveGraphicsState()
      NSBezierPath(rect: clip).addClip()
      for rule in rules {
        for range in rule.ranges {
          let n = range.normalized
          let rowLow = max(n.minRow, rows.lowerBound)
          let rowHigh = min(n.maxRow, rows.upperBound)
          let colLow = max(n.minCol, cols.lowerBound)
          let colHigh = min(n.maxCol, cols.upperBound)
          guard rowLow <= rowHigh, colLow <= colHigh else { continue }
          for row in rowLow...rowHigh {
            for col in colLow...colHigh {
              let address = CellAddress(row: row, col: col)
              if address == selected { continue }
              let cell = rectForCell(row: row, col: col)
              guard cell.height > h * 2, cell.width > w * 3, dirtyRect.intersects(cell) else {
                continue
              }
              let midY = cell.midY
              let right = cell.maxX - 5 * zoomScale
              let chevron = NSBezierPath()
              chevron.move(to: NSPoint(x: right - w, y: midY - h / 2))
              chevron.line(to: NSPoint(x: right - w / 2, y: midY + h / 2))
              chevron.line(to: NSPoint(x: right, y: midY - h / 2))
              chevron.lineWidth = 1.2 * zoomScale
              chevron.lineCapStyle = .round
              chevron.lineJoinStyle = .round
              color.setStroke()
              chevron.stroke()
            }
          }
        }
      }
      NSGraphicsContext.restoreGraphicsState()
    }
  }

  /// Where the dropdown button of the selected cell is, when it has a dropdown list.
  private func dropdownButtonRect() -> NSRect? {
    guard let viewModel, viewModel.selectionRanges.count <= 1, !viewModel.isEditing else {
      return nil
    }
    let address = viewModel.selectionAnchor
    guard viewModel.hasDropdown(at: address) else { return nil }
    let range =
      viewModel.activeSheet.mergeContaining(address)
      ?? CellRange(start: address, end: address)
    let n = range.normalized
    let cell = cellBorderRect(
      minRow: n.minRow, minCol: n.minCol, maxRow: n.maxRow, maxCol: n.maxCol)
    guard cell.height > 1, isCellRectInContentArea(cell) else { return nil }
    // Ends short of the fill handle, which sits half inside the cell's bottom-right corner,
    // so the two never overlap and each is easy to hit.
    let handleClearance = fillHandleSize / 2 + 1
    let width = min(18 * zoomScale, cell.height)
    return NSRect(
      x: cell.maxX - width - handleClearance, y: cell.minY + 1, width: width,
      height: max(1, cell.height - 2))
  }

  private func drawDropdownButton(in dirtyRect: NSRect) {
    guard let box = dropdownButtonRect(), dirtyRect.intersects(box) else { return }
    let chip = NSBezierPath(roundedRect: box, xRadius: 2 * zoomScale, yRadius: 2 * zoomScale)
    theme.accent.withAlphaComponent(0.9).setFill()
    chip.fill()
    let w = 7 * zoomScale
    let h = 4 * zoomScale
    let chevron = NSBezierPath()
    chevron.move(to: NSPoint(x: box.midX - w / 2, y: box.midY - h / 2))
    chevron.line(to: NSPoint(x: box.midX, y: box.midY + h / 2))
    chevron.line(to: NSPoint(x: box.midX + w / 2, y: box.midY - h / 2))
    chevron.lineWidth = 1.5 * zoomScale
    chevron.lineCapStyle = .round
    chevron.lineJoinStyle = .round
    NSColor.white.setStroke()
    chevron.stroke()
  }

  /// The selected cell's dropdown list, as a menu under the cell.
  func presentDropdownMenu() {
    guard let viewModel, let box = dropdownButtonRect() else { return }
    let address = viewModel.selectionAnchor
    guard let items = viewModel.dropdownItems(at: address) else { return }
    let menu = NSMenu()
    // What the cell shows, so a formula such as `=Reps!$B$2` ticks the name it gives.
    let current = viewModel.displayString(at: address)
    if items.isEmpty {
      let empty = menu.addItem(withTitle: "No choices", action: nil, keyEquivalent: "")
      empty.isEnabled = false
    }
    for item in items {
      let entry = menu.addItem(
        withTitle: item, action: #selector(handleDropdownChoice(_:)), keyEquivalent: "")
      entry.target = self
      entry.representedObject = item
      entry.state = item == current ? .on : .off
    }
    let n =
      (viewModel.activeSheet.mergeContaining(address) ?? CellRange(start: address, end: address))
      .normalized
    let cell = cellBorderRect(
      minRow: n.minRow, minCol: n.minCol, maxRow: n.maxRow, maxCol: n.maxCol)
    menu.minimumWidth = cell.width + box.width
    menu.popUp(positioning: nil, at: NSPoint(x: cell.minX, y: cell.maxY + 2), in: self)
  }

  @objc private func handleDropdownChoice(_ sender: NSMenuItem) {
    guard let viewModel, let item = sender.representedObject as? String else { return }
    viewModel.chooseDropdownItem(item, at: viewModel.selectionAnchor)
    needsDisplay = true
  }

  @objc private func handleMenuComment(_ sender: NSMenuItem) {
    guard let viewModel else { return }
    CellNotePresenter.presentComment(from: viewModel, in: window)
  }

  @objc private func handleMenuDeleteComment(_ sender: NSMenuItem) {
    viewModel?.deleteComment()
    needsDisplay = true
  }

  @objc private func handleMenuDropdown(_ sender: NSMenuItem) {
    guard let viewModel else { return }
    CellNotePresenter.presentDropdown(from: viewModel, in: window)
  }

  @objc private func handleMenuOpenLink(_ sender: NSMenuItem) {
    guard let viewModel, let link = viewModel.followableLink(at: viewModel.selectionAnchor) else {
      return
    }
    viewModel.openHyperlink(link)
    needsDisplay = true
  }

  @objc private func handleMenuLink(_ sender: NSMenuItem) {
    guard let viewModel else { return }
    LinkPresenter.present(from: viewModel, in: window)
  }

  @objc private func handleMenuRemoveLink(_ sender: NSMenuItem) {
    viewModel?.removeLink()
    needsDisplay = true
  }

  /// Rows and columns actually on screen, split so a frozen pane is not joined
  /// to the scrolled body, with the rectangle each pane draws in. The viewport's
  /// min and max row indexes are not a contiguous run when rows are frozen.
  private func onScreenSelectionRegions() -> [(ClosedRange<Int>, ClosedRange<Int>, NSRect)] {
    let frozenRows = frozenRowCount()
    let frozenCols = frozenColumnCount()
    let rows = rowCount()
    let cols = columnCount()
    guard rows > 0, cols > 0 else { return [] }

    func rowSpan(_ clip: NSRect, limit: Range<Int>) -> ClosedRange<Int>? {
      guard clip.width > 0.5, clip.height > 0.5, limit.upperBound > limit.lowerBound else {
        return nil
      }
      let first = min(max(rowAtContent(y: clip.minY + 0.5), limit.lowerBound), limit.upperBound - 1)
      let last = min(max(rowAtContent(y: clip.maxY - 0.5), limit.lowerBound), limit.upperBound - 1)
      guard first <= last else { return nil }
      return first...last
    }
    func colSpan(_ clip: NSRect, limit: Range<Int>) -> ClosedRange<Int>? {
      guard clip.width > 0.5, clip.height > 0.5, limit.upperBound > limit.lowerBound else {
        return nil
      }
      let first = min(
        max(columnAtContent(x: clip.minX + 0.5), limit.lowerBound), limit.upperBound - 1)
      let last = min(
        max(columnAtContent(x: clip.maxX - 0.5), limit.lowerBound), limit.upperBound - 1)
      guard first <= last else { return nil }
      return first...last
    }

    var regions: [(ClosedRange<Int>, ClosedRange<Int>, NSRect)] = []
    let body = scrollableCellsClipRect()
    let scrolledRows = rowSpan(body, limit: frozenRows..<rows)
    let scrolledCols = colSpan(body, limit: frozenCols..<cols)
    if let scrolledRows, let scrolledCols {
      regions.append((scrolledRows, scrolledCols, body))
    }
    if frozenRows > 0,
      let frozenRowSpan = rowSpan(
        NSRect(
          x: contentRect.minX, y: contentRect.minY, width: contentRect.width,
          height: max(0, frozenRowBoundaryY() - contentRect.minY)), limit: 0..<frozenRows)
    {
      let corner = frozenCellsClipRect()
      if frozenCols > 0, let frozenColSpan = colSpan(corner, limit: 0..<frozenCols) {
        regions.append((frozenRowSpan, frozenColSpan, corner))
      }
      let topStrip = frozenTopStripClipRect()
      if let scrolledCols, let topRows = rowSpan(topStrip, limit: 0..<frozenRows) {
        regions.append((topRows, scrolledCols, topStrip))
      }
    }
    let leftStrip = frozenLeftStripClipRect()
    if frozenCols > 0, let leftCols = colSpan(leftStrip, limit: 0..<frozenCols),
      let scrolledRows
    {
      regions.append((scrolledRows, leftCols, leftStrip))
    }
    return regions
  }

  /// True when this pane's bitmap will translate a merge whose anchor stays in the frozen pane.
  private func crossFreezeMergeMovesWithPane(
    _ merge: CellRange,
    paneColumns: ClosedRange<Int>,
    paneScrollsY: Bool
  ) -> Bool {
    let span = merge.normalized
    let frozenCols = frozenColumnCount()
    let frozenRows = frozenRowCount()
    let pinnedX = frozenCols > 0 && span.minCol < frozenCols && span.maxCol >= frozenCols
    let pinnedY = frozenRows > 0 && span.minRow < frozenRows && span.maxRow >= frozenRows
    let paneScrollsX = frozenCols > 0 && paneColumns.lowerBound >= frozenCols
    if pinnedX && paneScrollsX { return true }
    if pinnedY && paneScrollsY { return true }
    return false
  }

  private func hidePinnedMergeText() {
    pinnedHeaderMergeOverlay.isHidden = true
    pinnedBodyMergeOverlay.isHidden = true
  }

  /// Redraw merge text that must stay with the frozen pane while the cell bitmaps scroll.
  private func displayPinnedMergeText() {
    let show = scrollSurfacesPresented && hasPinnedCrossFreezeMerge()
    pinnedHeaderMergeOverlay.isHidden = !show
    pinnedBodyMergeOverlay.isHidden = !show
    guard show else { return }
    if pinnedHeaderMergeOverlay.frame != bounds {
      pinnedHeaderMergeOverlay.frame = bounds
    }
    if pinnedBodyMergeOverlay.frame != bounds {
      pinnedBodyMergeOverlay.frame = bounds
    }
    pinnedHeaderMergeOverlay.needsDisplay = true
    pinnedBodyMergeOverlay.needsDisplay = true
    guard window != nil else { return }
    pinnedHeaderMergeOverlay.display()
    pinnedBodyMergeOverlay.display()
  }

  private func hasPinnedCrossFreezeMerge() -> Bool {
    guard let sheet = viewModel?.activeSheet else { return false }
    let frozenCols = sheet.frozenColumns
    let frozenRows = sheet.frozenRows
    guard frozenCols > 0 || frozenRows > 0 else { return false }
    for merge in sheet.mergedRanges {
      let span = merge.normalized
      if frozenCols > 0, span.minCol < frozenCols, span.maxCol >= frozenCols { return true }
      if frozenRows > 0, span.minRow < frozenRows, span.maxRow >= frozenRows { return true }
    }
    return false
  }

  private func drawPinnedCrossFreezeMergeText(
    in dirtyRect: NSRect, band: PinnedMergeTextOverlay.Band
  ) {
    guard scrollSurfacesPresented, let viewModel else { return }
    let sheet = layoutSheet ?? viewModel.activeSheet
    guard !sheet.mergedRanges.isEmpty else { return }
    beginDrawLayout()
    defer { endDrawLayout() }
    let isDarkMode = theme.isDark
    let lastColumn = max(0, columnCount() - 1)
    for merge in sheet.mergedRanges {
      for slice in pinnedMergeSlices(merge, band: band) {
        let visible = slice.intersection(dirtyRect)
        guard visible.width > 0.5, visible.height > 0.5 else { continue }
        let span = merge.normalized
        var painted = Set<CellAddress>()
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: visible).addClip()
        paintOverflowCell(
          address: CellAddress(row: span.minRow, col: span.minCol),
          merge: merge,
          painted: &painted,
          dirtyRect: visible,
          paneColumns: 0...lastColumn,
          paneScrollsY: false,
          viewModel: viewModel,
          sheet: sheet,
          isDarkMode: isDarkMode
        )
        NSGraphicsContext.restoreGraphicsState()
      }
    }
  }

  /// The part of a cross-freeze merge whose bitmap would move. The frozen corner is not included.
  private func pinnedMergeSlices(_ merge: CellRange, band: PinnedMergeTextOverlay.Band) -> [NSRect]
  {
    let span = merge.normalized
    let frozenCols = frozenColumnCount()
    let frozenRows = frozenRowCount()
    let pinnedX = frozenCols > 0 && span.minCol < frozenCols && span.maxCol >= frozenCols
    let pinnedY = frozenRows > 0 && span.minRow < frozenRows && span.maxRow >= frozenRows
    guard pinnedX || pinnedY else { return [] }
    guard let rect = paintRect(for: CellAddress(row: span.minRow, col: span.minCol), merge: merge)
    else {
      return []
    }
    switch band {
    case .frozenPanes:
      var slices: [NSRect] = []
      // The header strip is only for a merge that lives in the frozen rows.
      // A merge lower in the sheet scrolls. Once its rect passes over that
      // strip, painting it there covers the frozen headers.
      if pinnedX, span.minRow < frozenRows {
        let strip = frozenTopStripClipRect()
        var top = rect.intersection(strip)
        if top.width > 0.5, top.height > 0.5 {
          top.size.width = max(top.width, strip.maxX - top.minX)
          slices.append(top)
        }
      }
      if pinnedY {
        let left = rect.intersection(frozenLeftStripClipRect())
        if left.width > 0.5, left.height > 0.5 { slices.append(left) }
      }
      return slices
    case .body:
      let bodyClip = scrollableCellsClipRect()
      var body = rect.intersection(bodyClip)
      guard body.width > 0.5, body.height > 0.5 else { return [] }
      body.size.width = max(body.width, bodyClip.maxX - body.minX)
      return [body]
    }
  }

  private func displaySelectionChrome() {
    if selectionChromeOverlay.frame != bounds {
      selectionChromeOverlay.frame = bounds
    }
    selectionChromeOverlay.needsDisplay = true
    guard window != nil else { return }
    selectionChromeOverlay.display()
  }

  /// Column-header band for a selected letter, excluding the corner box.
  private func columnHeaderSelectionStrip(for col: Int) -> NSRect {
    if col < frozenColumnCount() {
      return NSRect(
        x: headerSize,
        y: 0,
        width: max(0, frozenColumnBoundaryX() - headerSize),
        height: headerSize
      )
    }
    return scrollingColumnHeaderPane()
  }

  /// Row-header band for a selected number, excluding the corner box.
  private func rowHeaderSelectionStrip(for row: Int) -> NSRect {
    if row < frozenRowCount() {
      return NSRect(
        x: 0,
        y: headerSize,
        width: headerSize,
        height: max(0, frozenRowBoundaryY() - headerSize)
      )
    }
    return scrollingRowHeaderPane()
  }

  private func drawHeaderSelectionChrome(in dirtyRect: NSRect) {
    guard let viewModel else { return }
    let isSheetSelection = viewModel.selectionAxis == .sheet
    let selectionFill = theme.headerSelected
    let headerFill = theme.chrome
    let accent = theme.accent
    let gridLine = headerLineColor()
    let labelColor = theme.secondaryLabel

    func paintColumn(_ col: Int) {
      guard shouldDrawColumnHeader(col) else { return }
      let rect = columnHeaderRect(for: col)
      let strip = columnHeaderSelectionStrip(for: col)
      let visible = rect.intersection(strip)
      guard visible.width > 0.5, visible.height > 0.5, dirtyRect.intersects(visible) else {
        return
      }
      NSGraphicsContext.saveGraphicsState()
      NSBezierPath(rect: visible).addClip()
      headerFill.setFill()
      visible.fill()
      selectionFill.setFill()
      visible.fill()
      // Under the label, so the number or letter stays readable.
      drawHiddenRunChevrons(hiddenRunChevrons(column: col, rect: rect))
      drawOutlineButtons(outlineButtons(column: col, rect: rect))
      drawHeaderLabel(
        A1Notation.columnLabel(for: col) as NSString,
        centeredIn: visible,
        clip: visible,
        color: labelColor
      )
      accent.setStroke()
      let border = NSBezierPath()
      border.lineWidth = 2
      border.move(to: NSPoint(x: rect.minX + 0.5, y: rect.maxY - 1))
      border.line(to: NSPoint(x: rect.maxX - 0.5, y: rect.maxY - 1))
      border.stroke()
      gridLine.setStroke()
      NSBezierPath.strokeLine(
        from: NSPoint(x: rect.maxX, y: rect.minY), to: NSPoint(x: rect.maxX, y: rect.maxY))
      NSGraphicsContext.restoreGraphicsState()
    }

    func paintRow(_ row: Int) {
      guard shouldDrawRowHeader(row) else { return }
      let rect = rowHeaderRect(for: row)
      let strip = rowHeaderSelectionStrip(for: row)
      let visible = rect.intersection(strip)
      guard visible.width > 0.5, visible.height > 0.5, dirtyRect.intersects(visible) else {
        return
      }
      NSGraphicsContext.saveGraphicsState()
      NSBezierPath(rect: visible).addClip()
      headerFill.setFill()
      visible.fill()
      selectionFill.setFill()
      visible.fill()
      // Under the label, so the number or letter stays readable.
      drawHiddenRunChevrons(hiddenRunChevrons(row: row, rect: rect))
      let rowButtons = outlineButtons(row: row, rect: rect)
      drawOutlineButtons(rowButtons)
      var labelRect = visible
      if !rowButtons.isEmpty {
        labelRect.origin.x += 10
        labelRect.size.width = max(0, labelRect.width - 10)
      }
      drawHeaderLabel(
        "\(row + 1)" as NSString,
        centeredIn: labelRect,
        clip: visible,
        color: labelColor
      )
      accent.setStroke()
      let border = NSBezierPath()
      border.lineWidth = 2
      border.move(to: NSPoint(x: rect.maxX - 1, y: rect.minY + 0.5))
      border.line(to: NSPoint(x: rect.maxX - 1, y: rect.maxY - 0.5))
      border.stroke()
      gridLine.setStroke()
      NSBezierPath.strokeLine(
        from: NSPoint(x: rect.minX, y: rect.maxY), to: NSPoint(x: rect.maxX, y: rect.maxY))
      NSGraphicsContext.restoreGraphicsState()
    }

    if isSheetSelection {
      for col in headerColumnIndices() { paintColumn(col) }
      for row in headerRowIndices() { paintRow(row) }
      let corner = NSRect(x: 0, y: 0, width: headerSize, height: headerSize)
      if dirtyRect.intersects(corner) {
        headerFill.setFill()
        corner.fill()
        selectionFill.setFill()
        corner.fill()
        gridLine.setStroke()
        NSBezierPath.strokeLine(
          from: NSPoint(x: corner.maxX, y: 0), to: NSPoint(x: corner.maxX, y: corner.maxY))
        NSBezierPath.strokeLine(
          from: NSPoint(x: 0, y: corner.maxY), to: NSPoint(x: corner.maxX, y: corner.maxY))
      }
      return
    }
    for col in headerColumnIndices() where viewModel.isColumnInSelection(col) {
      paintColumn(col)
    }
    for row in headerRowIndices() where viewModel.isRowInSelection(row) {
      paintRow(row)
    }
  }

  /// The rectangle whose edges are the grid lines around these cells.
  private func cellBorderRect(minRow: Int, minCol: Int, maxRow: Int, maxCol: Int) -> NSRect {
    let minX = devicePixel(xForColumn(minCol))
    let minY = devicePixel(yForRow(minRow))
    let maxX: CGFloat
    if maxCol + 1 < columnCount() {
      maxX = devicePixel(xForColumn(maxCol + 1))
    } else {
      maxX = devicePixel(xForColumn(maxCol) + columnWidth(at: maxCol))
    }
    let maxY: CGFloat
    if maxRow + 1 < rowCount() {
      maxY = devicePixel(yForRow(maxRow + 1))
    } else {
      maxY = devicePixel(yForRow(maxRow) + rowHeight(at: maxRow))
    }
    return NSRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
  }

  private func drawSelection(in dirtyRect: NSRect) {
    guard let viewModel else { return }
    let ranges = viewModel.selectionRanges
    let isMulti = ranges.count > 1

    for (index, range) in ranges.enumerated() {
      let n = range.normalized
      // The far edge is the next grid line, the same coordinate addGridSegment snaps.
      let fullRect = cellBorderRect(
        minRow: n.minRow, minCol: n.minCol, maxRow: n.maxRow, maxCol: n.maxCol)

      // Full selection outline (Excel-familiar), not an L-anchor on the active cell.
      // Clip to the pane that owns the range so a scrolled cell starting under
      // the freeze cannot stroke across the last frozen row or column.
      let clip = paneClipRect(for: range)
      guard clip.width > 0.5, clip.height > 0.5, dirtyRect.intersects(clip) else { continue }
      if isCellRectInContentArea(fullRect), dirtyRect.intersects(fullRect) {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: clip).addClip()
        theme.accent.setStroke()
        let border = NSBezierPath(rect: fullRect)
        border.lineWidth = index == ranges.count - 1 ? 2 : 1.5
        border.stroke()
        NSGraphicsContext.restoreGraphicsState()
      }
    }

    if !isMulti, let range = ranges.last {
      let clip = paneClipRect(for: range)
      guard clip.width > 0.5, clip.height > 0.5 else { return }
      NSGraphicsContext.saveGraphicsState()
      NSBezierPath(rect: clip).addClip()
      drawFillHandle(in: dirtyRect)
      NSGraphicsContext.restoreGraphicsState()
    }
  }

  private func drawFillHandle(in dirtyRect: NSRect) {
    guard let rect = fillHandleRect(), dirtyRect.intersects(rect) else { return }
    theme.accent.setFill()
    NSBezierPath(rect: rect).fill()
    theme.fillHandleRing.setStroke()
    let border = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
    border.lineWidth = 1.5
    border.stroke()
  }

  private func drawFormulaReferenceHighlights(in dirtyRect: NSRect) {
    guard let viewModel else { return }
    let highlights = viewModel.formulaReferenceHighlights
    guard !highlights.isEmpty else { return }

    let activeSheetName = viewModel.activeSheet.name
    let visibleRows = visibleRowRange()
    let visibleCols = visibleColumnRange()
    let focused = viewModel.focusedFormulaHighlightIndex

    for (index, highlight) in highlights.enumerated() {
      if let sheet = highlight.sheet,
        sheet.caseInsensitiveCompare(activeSheetName) != .orderedSame
      {
        continue
      }
      let n = highlight.cellRange.normalized
      let startRow = max(n.minRow, visibleRows.lowerBound)
      let endRow = min(n.maxRow, visibleRows.upperBound)
      let startCol = max(n.minCol, visibleCols.lowerBound)
      let endCol = min(n.maxCol, visibleCols.upperBound)
      guard startRow <= endRow, startCol <= endCol else { continue }

      let topLeft = rectForCell(row: startRow, col: startCol)
      let bottomRight = rectForCell(row: endRow, col: endCol)
      let fillRect = NSRect(
        x: topLeft.minX,
        y: topLeft.minY,
        width: bottomRight.maxX - topLeft.minX,
        height: bottomRight.maxY - topLeft.minY
      )
      let clip = paneClipRect(for: highlight.cellRange)
      guard clip.width > 0.5, clip.height > 0.5, dirtyRect.intersects(clip) else { continue }
      guard isCellRectInContentArea(fillRect), dirtyRect.intersects(fillRect) else { continue }

      let color = highlight.color
      let isFocused = focused == index || (focused == nil && highlights.count == 1)
      NSGraphicsContext.saveGraphicsState()
      NSBezierPath(rect: clip).addClip()
      color.withAlphaComponent(isFocused ? 0.16 : 0.08).setFill()
      fillRect.fill()

      color.setStroke()
      let border = NSBezierPath(rect: fillRect.insetBy(dx: 0.5, dy: 0.5))
      border.lineWidth = isFocused ? 2 : 1.5
      // Sheets-style dashed range outline
      border.setLineDash([4, 3], count: 2, phase: 0)
      border.stroke()
      NSGraphicsContext.restoreGraphicsState()
    }
  }

  private func drawFreezeDividers(in dirtyRect: NSRect) {
    guard let sheet = viewModel?.activeSheet else { return }
    let frozenCols = sheet.frozenColumns
    let frozenRows = sheet.frozenRows
    guard frozenCols > 0 || frozenRows > 0 else { return }

    let content = contentRect
    theme.freezeDivider.setStroke()
    if frozenCols > 0 {
      let x = frozenColumnBoundaryX()
      strokeDivider(
        horizontal: false,
        axis: x,
        from: content.minY,
        to: content.maxY,
        gaps: mergeSpansCrossingFreeze(
          sheet: sheet, vertical: true, frozenRows: frozenRows, frozenCols: frozenCols)
      )
    }
    if frozenRows > 0 {
      let y = frozenRowBoundaryY()
      strokeDivider(
        horizontal: true,
        axis: y,
        from: content.minX,
        to: content.maxX,
        gaps: mergeSpansCrossingFreeze(
          sheet: sheet, vertical: false, frozenRows: frozenRows, frozenCols: frozenCols)
      )
    }
  }

  /// Merges that cross a freeze line leave a gap so the divider does not cut their text.
  private func mergeSpansCrossingFreeze(
    sheet: Sheet,
    vertical: Bool,
    frozenRows: Int,
    frozenCols: Int
  ) -> [(CGFloat, CGFloat)] {
    var gaps: [(CGFloat, CGFloat)] = []
    for merge in sheet.mergedRanges {
      let span = merge.normalized
      if vertical {
        guard frozenCols > 0, span.minCol < frozenCols, span.maxCol >= frozenCols else { continue }
        let minY = yForRow(span.minRow)
        let maxY = yForRow(span.maxRow) + rowHeight(at: span.maxRow)
        gaps.append((minY, maxY))
      } else {
        guard frozenRows > 0, span.minRow < frozenRows, span.maxRow >= frozenRows else { continue }
        let minX = xForColumn(span.minCol)
        let maxX = xForColumn(span.maxCol) + columnWidth(at: span.maxCol)
        gaps.append((minX, maxX))
      }
    }
    return gaps
  }

  private func strokeDivider(
    horizontal: Bool,
    axis: CGFloat,
    from: CGFloat,
    to: CGFloat,
    gaps: [(CGFloat, CGFloat)]
  ) {
    let start = min(from, to)
    let end = max(from, to)
    var segments: [(CGFloat, CGFloat)] = [(start, end)]
    for gap in gaps {
      let low = min(gap.0, gap.1)
      let high = max(gap.0, gap.1)
      var next: [(CGFloat, CGFloat)] = []
      next.reserveCapacity(segments.count + 1)
      for segment in segments {
        if high <= segment.0 || low >= segment.1 {
          next.append(segment)
          continue
        }
        if low - segment.0 > 0.5 { next.append((segment.0, low)) }
        if segment.1 - high > 0.5 { next.append((high, segment.1)) }
      }
      segments = next
    }
    let line = NSBezierPath()
    // Three points, so frozen rows and columns read as a pane and not as one more grid line.
    line.lineWidth = 3
    for segment in segments where segment.1 - segment.0 > 0.5 {
      if horizontal {
        line.move(to: NSPoint(x: segment.0, y: axis))
        line.line(to: NSPoint(x: segment.1, y: axis))
      } else {
        line.move(to: NSPoint(x: axis, y: segment.0))
        line.line(to: NSPoint(x: axis, y: segment.1))
      }
    }
    line.stroke()
  }

  // MARK: - Editor

  func showEditor(selectAll: Bool = false) {
    hideCommentCard()
    guard let viewModel else { return }
    let rect = rectForCell(row: viewModel.selectionAnchor.row, col: viewModel.selectionAnchor.col)
    guard isCellRectInContentArea(rect) else { return }
    isEditorActive = true
    lastAppliedFormulaHighlightKey = ""
    editor.stringValue = viewModel.editText
    applyEditorFormat(from: viewModel.selectedCell.format)
    styleFieldEditor(for: viewModel.selectedCell.format)
    updateEditorFrame()
    editor.isHidden = false
    window?.makeFirstResponder(editor)
    guard let fieldEditor = editor.currentEditor() else { return }
    if selectAll {
      fieldEditor.selectAll(nil)
    } else {
      let length = editor.stringValue.utf16.count
      fieldEditor.selectedRange = NSRange(location: length, length: 0)
    }
    if let textView = fieldEditor as? NSTextView {
      EditorSpellCheck.apply(to: textView, text: textView.string, refresh: true)
    }
    applyInCellFormulaAttributes(preserveSelection: true)
    if let textView = editor.currentEditor() as? NSTextView {
      viewModel.updateFormulaHighlightFocus(atUTF16: textView.selectedRange.location)
      // Focus update may arrive before highlights exist; refresh once more next turn.
      // Spell checking is set again because the field editor can clear it while starting.
      DispatchQueue.main.async { [weak self] in
        guard let self, self.isEditorActive else { return }
        self.lastAppliedFormulaHighlightKey = ""
        if let textView = self.editor.currentEditor() as? NSTextView {
          EditorSpellCheck.apply(
            to: textView,
            text: textView.string,
            refresh: EditorSpellCheck.shouldCheck(textView.string)
          )
        }
        self.applyInCellFormulaAttributes(preserveSelection: true)
        if let textView = self.editor.currentEditor() as? NSTextView {
          self.viewModel?.updateFormulaHighlightFocus(atUTF16: textView.selectedRange.location)
        }
        self.needsDisplay = true
      }
    }
  }

  private func applyEditorFormat(from format: CellFormat?) {
    var scaledFormat = format ?? CellFormat()
    let baseSize = scaledFormat.fontSize ?? CellFormatRenderer.defaultFontSize
    scaledFormat.fontSize = baseSize * zoomScale
    editor.font = CellFormatRenderer.font(for: scaledFormat)
    let colors = editorColors(for: format)
    editor.textColor = colors.foreground
    let wraps = format?.textDisplay == .wrap
    editor.cell?.wraps = wraps
    editor.cell?.isScrollable = !wraps
    editor.lineBreakMode = wraps ? .byWordWrapping : .byClipping
    if let cell = editor.cell as? NSTextFieldCell {
      cell.usesSingleLineMode = !wraps
    }
    styleFieldEditor(for: format)
  }

  /// Match the in-cell editor surface to the cell fill with readable text/selection colors.
  private func editorColors(for format: CellFormat?) -> (background: NSColor, foreground: NSColor) {
    let background = CellFormatRenderer.fillColor(for: format) ?? theme.canvas
    let bgRGB = background.usingColorSpace(.deviceRGB) ?? background
    if let explicit = CellFormatRenderer.nsColor(format?.textColor) {
      return (background, explicit)
    }
    let fg = Self.luminance(of: bgRGB) > 0.65 ? NSColor.black : theme.label
    return (background, fg)
  }

  private func styleFieldEditor(for format: CellFormat?) {
    guard let textView = editor.currentEditor() as? NSTextView else { return }
    let colors = editorColors(for: format)
    textView.drawsBackground = true
    textView.backgroundColor = colors.background
    textView.textColor = colors.foreground
    textView.insertionPointColor = colors.foreground
    let selectionForeground =
      Self.luminance(of: colors.background.usingColorSpace(.deviceRGB) ?? colors.background) > 0.65
      ? NSColor.black
      : NSColor.white
    textView.selectedTextAttributes = [
      .backgroundColor: NSColor.selectedTextBackgroundColor,
      .foregroundColor: selectionForeground,
    ]
    textView.typingAttributes = [
      .font: editor.font ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
      .foregroundColor: colors.foreground,
      .backgroundColor: NSColor.clear,
    ]
  }

  private func applyInCellFormulaAttributes(preserveSelection: Bool) {
    guard !isApplyingFormulaAttributes else { return }
    guard let viewModel, FormulaSyntax.isFormula(editor.stringValue) else {
      lastAppliedFormulaHighlightKey = ""
      return
    }

    let key =
      "\(editor.stringValue)|\(viewModel.focusedFormulaHighlightIndex ?? -1)|\(viewModel.formulaHighlightRevision)"
    guard key != lastAppliedFormulaHighlightKey else { return }
    lastAppliedFormulaHighlightKey = key

    isApplyingFormulaAttributes = true
    defer { isApplyingFormulaAttributes = false }

    let font = editor.font ?? .monospacedSystemFont(ofSize: 12, weight: .regular)
    let colors = editorColors(for: viewModel.selectedCell.format)
    let attributed = FormulaReferenceScanner.attributedFormula(
      editor.stringValue,
      highlights: viewModel.formulaReferenceHighlights,
      focusedIndex: viewModel.focusedFormulaHighlightIndex,
      baseFont: font,
      baseColor: colors.foreground
    )
    var selected: NSRange?
    if preserveSelection, let textView = editor.currentEditor() as? NSTextView {
      selected = textView.selectedRange
    }
    editor.attributedStringValue = attributed
    if let selected, let textView = editor.currentEditor() as? NSTextView {
      let maxLen = (editor.stringValue as NSString).length
      let loc = min(selected.location, maxLen)
      let len = min(selected.length, max(0, maxLen - loc))
      textView.setSelectedRange(NSRange(location: loc, length: len))
    }
  }

  func hideEditor(commit: Bool, claimGridFocus: Bool = true) {
    guard isEditorActive else { return }
    isEditorActive = false
    if commit, let viewModel {
      viewModel.editText = editor.stringValue
      viewModel.commitEdit()
    } else {
      viewModel?.cancelEdit()
    }
    editor.isHidden = true
    if claimGridFocus {
      window?.makeFirstResponder(self)
    }
    needsDisplay = true
  }

  /// Find is about to take the key window. Commit an open cell and do not
  /// hand focus back to the grid, or the next character edits that cell.
  func endEditingForFind() {
    if isEditorActive {
      hideEditor(commit: true, claimGridFocus: false)
    }
  }

  static func endEditingInKeyWindowForFind() {
    let window = NSApp.keyWindow ?? NSApp.mainWindow
    first(in: window?.contentView)?.endEditingForFind()
  }

  fileprivate func commitEditingForSave() {
    if isEditorActive {
      hideEditor(commit: true)
    } else {
      viewModel?.commitEditIfNeeded()
    }
  }

  fileprivate static func first(in root: NSView?) -> SpreadsheetGridNSView? {
    guard let root else { return nil }
    if let grid = root as? SpreadsheetGridNSView { return grid }
    for subview in root.subviews {
      if let grid = first(in: subview) { return grid }
    }
    return nil
  }

  private func commitEditorAndMove(rowDelta: Int, colDelta: Int, extending: Bool = false) {
    guard let viewModel else { return }
    viewModel.editText = editor.stringValue
    hideEditor(commit: true)
    viewModel.moveSelection(rowDelta: rowDelta, colDelta: colDelta, extending: extending)
    scrollSelectionIntoView()
  }

  /// Commit the edit and move one cell for Tab or Shift-Tab, as a single cell.
  /// Ignores a second delivery of the same key so the range cannot grow afterward.
  private func commitTabMove(colDelta: Int) {
    if let event = NSApp.currentEvent, isTabKeyDown(event) {
      if event.timestamp == lastTabMoveTimestamp { return }
      lastTabMoveTimestamp = event.timestamp
    }
    suppressFollowingTabMove = true
    commitEditorAndMove(rowDelta: 0, colDelta: colDelta, extending: false)
    DispatchQueue.main.async { [weak self] in
      self?.suppressFollowingTabMove = false
    }
  }

  private func isTabKeyDown(_ event: NSEvent?) -> Bool {
    guard let event, event.type == .keyDown else { return false }
    return event.keyCode == 48
  }

  private func updateEditorFrame() {
    guard let viewModel else { return }
    let sheet = viewModel.activeSheet
    let anchor = viewModel.selectionAnchor
    let rect =
      (paintRect(for: anchor, sheet: sheet) ?? rectForCell(row: anchor.row, col: anchor.col))
      .insetBy(dx: 1, dy: 1)
    let body = contentRect
    guard rect.width > 4, rect.height > 4, body.width > 1, body.height > 1 else {
      editor.isHidden = true
      return
    }
    if editorClip.frame != body {
      editorClip.frame = body
    }
    // The field keeps the full cell frame. The clip view hides the part under the headers.
    let local = NSRect(
      x: rect.minX - body.minX,
      y: rect.minY - body.minY,
      width: rect.width,
      height: rect.height
    )
    if editor.frame != local {
      editor.frame = local
    }
  }

  /// Drops changed cells from the paint cache and redraws only those rects.
  /// Wrapped rows in the set are measured again. Merge lookup and row offsets stay
  /// unless a wrapped row actually changes height.
  func invalidateDisplayedCells(_ changed: Set<CellAddress>) {
    guard let viewModel, !changed.isEmpty else { return }
    let neighbors = Self.withOverflowNeighbors(changed, sheet: viewModel.activeSheet)
    // A color scale, data bar, icon set or duplicate rule colors every cell from the whole
    // range, so one edited value can change all of them.
    guard
      let addresses = Self.withRangeRuleCells(
        neighbors, rules: viewModel.activeSheet.conditionalFormats)
    else {
      testingInvalidateReason = "range-rule full"
      advanceTileCalcGeneration()
      reloadContent(resetScrollPosition: false)
      return
    }
    if addresses.count != neighbors.count { advanceTileCalcGeneration() }
    if scrollSurfacesPresented {
      testingInvalidateReason = "scroll-surfaces"
      reloadContent(resetScrollPosition: false)
      return
    }
    let sheet = viewModel.activeSheet
    let rows = wrappedRows(in: addresses, sheet: sheet)
    if remeasureWrappedRows(rows, viewModel: viewModel, sheet: sheet) {
      testingInvalidateReason = "wrapped-height \(rows.count)"
      cachedRowOffsets = nil
      cachedRowLayoutRevision = Int.min
      reloadContent(resetScrollPosition: false)
      return
    }
    testingInvalidateReason = "partial \(addresses.count)"
    for address in addresses {
      cellPaintCache.removeValue(forKey: address)
    }
    if scrollTilesPresented {
      refreshScrollTiles(covering: addresses, sheet: sheet)
      displaySelectionChrome()
      testingInvalidateReason += " tiles"
      return
    }
    // Pictures drawn for scrolling while the grid sat idle still show these cells as they were.
    // The next trackpad scroll shows them, so typed text went blank until a click. Draw them again.
    if !tileImageCache.isEmpty || !scrollTiles.isEmpty {
      refreshScrollTiles(covering: addresses, sheet: sheet)
      needsViewportTileWarm = true
      // After the background queue has the new values, so the warm-up does not wait on it.
      tileValues.queue.async { [weak self] in
        DispatchQueue.main.async { self?.scheduleViewportTileWarm() }
      }
      testingInvalidateReason += " cached-tiles"
    }
    // Frozen rows draw their spilling text in the frozen pass, which a limited repaint skips.
    let frozenRows = frozenRowCount()
    if frozenRows > 0, addresses.contains(where: { $0.row < frozenRows }) {
      testingInvalidateReason += " frozen-rows"
      for address in addresses {
        let rect =
          paintRect(for: address, sheet: sheet) ?? rectForCell(row: address.row, col: address.col)
        if rect.intersects(bounds) { setNeedsDisplay(rect) }
      }
      return
    }
    limitPaintTo = addresses
    isApplyingPartialPaint = true
    var anyOnScreen = false
    for address in addresses {
      let rect =
        paintRect(for: address, sheet: sheet) ?? rectForCell(row: address.row, col: address.col)
      guard rect.intersects(bounds), rect.width > 0.5, rect.height > 0.5 else { continue }
      anyOnScreen = true
      displayCellRect(rect)
    }
    isApplyingPartialPaint = false
    limitPaintTo = nil
    testingInvalidateReason +=
      " partial \(addresses.count) onscreen \(anyOnScreen) dirty \(needsDisplay) layer \(layer?.needsDisplay() == true)"
  }

  /// The cells to repaint once rules that read their whole range are counted: `changed` plus
  /// every cell of such a rule that a changed cell is in. Nil when that is too many to repaint
  /// one by one.
  static func withRangeRuleCells(_ changed: Set<CellAddress>, rules: [ConditionalFormatRule])
    -> Set<CellAddress>?
  {
    var result = changed
    for rule in rules {
      switch rule.predicate {
      case .colorScale, .dataBar, .iconSet, .duplicateValues, .uniqueValues: break
      default: continue
      }
      let range = rule.range.normalized
      guard
        changed.contains(where: {
          $0.row >= range.minRow && $0.row <= range.maxRow && $0.col >= range.minCol
            && $0.col <= range.maxCol
        })
      else { continue }
      let rows = range.maxRow - range.minRow + 1
      let cols = range.maxCol - range.minCol + 1
      guard rows * cols + result.count <= 4_096 else { return nil }
      for row in range.minRow...range.maxRow {
        for col in range.minCol...range.maxCol { result.insert(CellAddress(row: row, col: col)) }
      }
    }
    return result
  }

  /// Text spills over empty cells beside it. When a cell changes, the cells its old or new text
  /// covered, and a neighbor whose text spilled over it, must be painted again too: the empty
  /// cells on both sides, and the first filled cell each way.
  static func withOverflowNeighbors(_ addresses: Set<CellAddress>, sheet: Sheet) -> Set<CellAddress>
  {
    // Past this many changed cells the caller repaints everything anyway.
    guard addresses.count <= 256 else { return addresses }
    let lastColumn = sheet.effectiveColumnCount - 1
    let reach = 64
    var result = addresses
    for address in addresses {
      for step in [-1, 1] {
        var col = address.col + step
        var walked = 0
        while col >= 0, col <= lastColumn, walked < reach {
          let neighbor = CellAddress(row: address.row, col: col)
          result.insert(neighbor)
          if sheet.cell(at: neighbor).hasContent { break }
          col += step
          walked += 1
        }
      }
    }
    return result
  }

  /// Keeps the other tiles. A fresh engine reads the edited workbook, then only the
  /// tiles that contain these cells are painted again. Selection stays on its overlay.
  private func refreshScrollTiles(covering addresses: Set<CellAddress>, sheet: Sheet) {
    queueTileWorkbookUpdate(invalidating: addresses)
    var queued: Set<TileImageKey> = []
    for address in addresses {
      let bounds = changedModelBounds(address: address, sheet: sheet)
      for index in scrollTiles.indices {
        let tile = scrollTiles[index]
        guard tileOverlaps(tile.pane, x: tile.indexX, y: tile.indexY, bounds: bounds) else {
          continue
        }
        let key = TileImageKey(pane: tile.pane, x: tile.indexX, y: tile.indexY)
        if queued.contains(key) { continue }
        queued.insert(key)
        forgetTileImage(key)
        guard let spec = scrollTileSpec(tile.pane) else { continue }
        enqueueTileValueRender(
          pane: tile.pane,
          indexX: tile.indexX,
          indexY: tile.indexY,
          spec: spec,
          viewRect: tile.viewRect,
          contentOrigin: tile.contentOrigin,
          requestedAt: CFAbsoluteTimeGetCurrent(),
          notifyMain: true
        )
      }
      let cached = tileImageCache.keys.filter { key in
        !queued.contains(key) && tileOverlaps(key.pane, x: key.x, y: key.y, bounds: bounds)
      }
      for key in cached {
        forgetTileImage(key)
        queued.insert(key)
      }
    }
  }

  private func queueTileWorkbookUpdate(invalidating addresses: Set<CellAddress>) {
    guard let viewModel else { return }
    let workbook = viewModel.workbook
    let sheet = workbook.activeSheet
    let columns = columnOffsets()
    let rows = rowOffsets()
    let zoom = zoomScale
    let merges = MergeLookup(ranges: sheet.mergedRanges)
    let sheetID = sheet.id
    let dirty = addresses
    let palette = paletteResolvedOnMainThread()
    let contentRevision = viewModel.contentRevision
    advanceTileCalcGeneration()
    tileValues.queue.async {
      let engine = FormulaEngine()
      engine.activateSheet(workbook)
      self.tileValues.engine = engine
      // The warm-up would otherwise build this engine again, on the main thread.
      self.tileValues.preparedContentRevision = contentRevision
      self.tileValues.sheet = sheet
      self.tileValues.sheetID = sheetID
      self.tileValues.rangeValueCache.removeAll(keepingCapacity: true)
      self.tileValues.columnOffsets = columns
      self.tileValues.rowOffsets = rows
      self.tileValues.zoom = zoom
      self.tileValues.mergeLookup = merges
      self.tileValues.resolvedPalette = palette
      self.tileValues.isDarkMode = palette.isDark
      for address in dirty {
        self.tileValues.paintCache.removeValue(forKey: address)
      }
    }
  }

  private func changedModelBounds(address: CellAddress, sheet: Sheet) -> (Int, Int, Int, Int) {
    let lookup = mergeLookup(for: sheet)
    if let interval = lookup.containing(address) {
      let span = interval.range.normalized
      return (span.minCol, span.maxCol, span.minRow, span.maxRow)
    }
    return (address.col, address.col, address.row, address.row)
  }

  private struct TileSpan {
    var x0: CGFloat
    var x1: CGFloat
    var y0: CGFloat
    var y1: CGFloat
  }

  private func tileOverlaps(
    _ pane: ScrollTilePane,
    x: Int,
    y: Int,
    bounds: (Int, Int, Int, Int)
  ) -> Bool {
    guard let cell = paneSpan(pane, bounds: bounds) else { return false }
    return spansOverlap(cell, indexSpan(pane, x: x, y: y))
  }

  private func spansOverlap(_ cell: TileSpan, _ tile: TileSpan) -> Bool {
    cell.x0 < tile.x1 && tile.x0 < cell.x1 && cell.y0 < tile.y1 && tile.y0 < cell.y1
  }

  private func indexSpan(_ pane: ScrollTilePane, x: Int, y: Int) -> TileSpan {
    let size = Self.scrollTileSize
    let scrollsX = pane == .body || pane == .columnHeader || pane == .frozenTop
    let scrollsY = pane == .body || pane == .rowHeader || pane == .frozenLeft
    let x0 = scrollsX ? CGFloat(x) * size : 0
    let y0 = scrollsY ? CGFloat(y) * size : 0
    let x1 = scrollsX ? x0 + size : CGFloat.greatestFiniteMagnitude
    let y1 = scrollsY ? y0 + size : CGFloat.greatestFiniteMagnitude
    return TileSpan(x0: x0, x1: x1, y0: y0, y1: y1)
  }

  private func paneSpan(_ pane: ScrollTilePane, bounds: (Int, Int, Int, Int)) -> TileSpan? {
    let minCol = bounds.0
    let maxCol = bounds.1
    let minRow = bounds.2
    let maxRow = bounds.3
    let cols = columnOffsets()
    let rows = rowOffsets()
    guard minCol >= 0, minRow >= 0, maxCol >= minCol, maxRow >= minRow else { return nil }
    guard maxCol + 1 < cols.count, maxRow + 1 < rows.count else { return nil }
    let frozenCols = frozenColumnCount()
    let frozenRows = frozenRowCount()
    let frozenX = frozenCols < cols.count ? cols[frozenCols] : 0
    let frozenY = frozenRows < rows.count ? rows[frozenRows] : 0
    switch pane {
    case .columnHeader, .rowHeader:
      return nil
    case .body:
      guard maxCol >= frozenCols, maxRow >= frozenRows else { return nil }
      let x0 = max(0, cols[minCol] - frozenX)
      let x1 = cols[maxCol + 1] - frozenX
      let y0 = max(0, rows[minRow] - frozenY)
      let y1 = rows[maxRow + 1] - frozenY
      guard x1 > x0, y1 > y0 else { return nil }
      return TileSpan(x0: x0, x1: x1, y0: y0, y1: y1)
    case .frozenLeft:
      guard minCol < frozenCols, maxRow >= frozenRows else { return nil }
      let y0 = max(0, rows[minRow] - frozenY)
      let y1 = rows[maxRow + 1] - frozenY
      guard y1 > y0 else { return nil }
      return TileSpan(x0: 0, x1: 1, y0: y0, y1: y1)
    case .frozenTop:
      guard minRow < frozenRows, maxCol >= frozenCols else { return nil }
      let x0 = max(0, cols[minCol] - frozenX)
      let x1 = cols[maxCol + 1] - frozenX
      guard x1 > x0 else { return nil }
      return TileSpan(x0: x0, x1: x1, y0: 0, y1: 1)
    case .frozenCorner:
      guard minCol < frozenCols, minRow < frozenRows else { return nil }
      return TileSpan(x0: 0, x1: 1, y0: 0, y1: 1)
    }
  }

  private func forgetTileImage(_ key: TileImageKey) {
    guard let existing = tileImageCache.removeValue(forKey: key) else { return }
    tileCacheBytes = tileCacheBytes > existing.bytes ? tileCacheBytes - existing.bytes : 0
  }

  /// Redraws one cell without marking the rest of the view dirty.
  private func displayCellRect(_ rect: NSRect) {
    if frozenRowCount() > 0 || frozenColumnCount() > 0 {
      layoutSubtreeIfNeeded()
      for overlay in frozenPaneOverlays where !overlay.isHidden && overlay.frame.intersects(rect) {
        let local = overlay.convert(rect, from: self).intersection(overlay.bounds)
        guard local.width > 0.5, local.height > 0.5 else { continue }
        overlay.displayIgnoringOpacity(local)
      }
    }
    let visible = rect.intersection(bounds)
    guard visible.width > 0.5, visible.height > 0.5 else { return }
    setNeedsDisplay(visible)
    super.displayIfNeeded()
  }

  private func wrappedRows(in addresses: Set<CellAddress>, sheet: Sheet) -> Set<Int> {
    var rows: Set<Int> = []
    for address in addresses {
      if sheet.cell(at: address).format?.textDisplay == .wrap {
        rows.insert(address.row)
      }
    }
    return rows
  }

  private func remeasureWrappedRows(
    _ rows: Set<Int>,
    viewModel: SpreadsheetViewModel,
    sheet: Sheet
  ) -> Bool {
    guard !rows.isEmpty else { return false }
    let zoom = zoomScale
    let measured = CellTextLayout.wrappedRowHeights(
      rows: rows,
      sheet: sheet,
      defaultRowHeight: Self.defaultRowHeight,
      defaultColumnWidth: Self.defaultColumnWidth,
      zoom: zoom,
      columnWidth: { sheet.columnWidth(for: $0, default: Self.defaultColumnWidth) },
      displayText: { viewModel.displayString(at: $0) },
      extraWidthInset: { address in
        var extra: CGFloat = 0
        if viewModel.resolvedPaint(at: address).icon != nil {
          extra += 14 * zoom
        }
        if viewModel.isFilterHeaderCell(row: address.row, col: address.col) {
          extra += 14 * zoom
        }
        return extra
      }
    )
    var changed = false
    for row in rows {
      let next = measured[row]
      if cachedWrappedRowHeights[row] != next {
        changed = true
        if let next {
          cachedWrappedRowHeights[row] = next
        } else {
          cachedWrappedRowHeights.removeValue(forKey: row)
        }
      }
    }
    return changed
  }

  private func drawLimitedCells(_ addresses: Set<CellAddress>, in dirtyRect: NSRect) {
    guard let viewModel else { return }
    let sheet = layoutSheet ?? viewModel.activeSheet
    var borderItems: [(CellBorders, NSRect)] = []
    var painted: [NSRect] = []
    var rows = Set<Int>()
    for address in addresses {
      let role = mergeRole(at: address, sheet: sheet)
      if case .covered = role { continue }
      guard let rect = paintRect(for: address, merge: mergeRange(from: role)) else { continue }
      guard rect.intersects(dirtyRect) else { continue }
      painted.append(rect)
      rows.insert(address.row)
      theme.canvas.setFill()
      rect.fill()
      let cell = sheet.cell(at: address)
      let cached = cachedCellPaint(at: address, viewModel: viewModel, sheet: sheet, cell: cell)
      drawCellContent(
        cell,
        at: address,
        rect: rect,
        viewModel: viewModel,
        paint: cached.paint,
        value: cached.value,
        displayText: cached.displayText
      )
      if let borders = cached.paint.format?.borders ?? cell.format?.borders, borders.hasAny {
        borderItems.append((borders, rect))
      }
    }
    // Most text is drawn by the spill pass, not with its cell. Without this, a repainted cell
    // showed blank until the next full redraw. Clipped to the repainted cells, so text in the
    // cells around them is not drawn twice.
    if !painted.isEmpty, let ctx = NSGraphicsContext.current {
      ctx.saveGraphicsState()
      let clip = NSBezierPath()
      for rect in painted { clip.appendRect(rect) }
      clip.addClip()
      let union = painted.dropFirst().reduce(painted[0]) { $0.union($1) }
      // The fills above cover the gridlines on the cells' edges. A full redraw draws them
      // after the fills; without this, a whole row lost its lines after AutoSum until the next
      // full redraw, as AutoSum leaves the selection where it was.
      if !visibleRegionIsMostlyBordered() {
        drawGridLines(in: union)
      }
      drawScrollableOverflowText(in: union, onlyRows: rows)
      ctx.restoreGraphicsState()
    }
    if !borderItems.isEmpty {
      CellFormatRenderer.drawBordersBatch(borderItems, scale: zoomScale)
    }
  }

  func syncDisplay() {
    // Filter visibility depends on cell values — rebuild row heights when content changes.
    if viewModel?.filterState != nil {
      invalidateLayoutCache()
    }
    clampScrollOrigin()
    updateEditorFrame()
    layoutOnSheetCharts()
    window?.invalidateCursorRects(for: self)
    needsDisplay = true
  }

  func applyFreezePanesLayout() {
    invalidateLayoutCache()
    syncDisplay()
  }

  func refreshSelectionDisplay() {
    updateEditorFrame()
    // Chrome sits above the cell planes, so this does not rasterize them.
    displaySelectionChrome()
  }

  func refreshFormulaHighlights() {
    displaySelectionChrome()
    guard isEditorActive else { return }
    applyInCellFormulaAttributes(preserveSelection: true)
  }

  func scrollFocusedFormulaHighlightIntoViewIfNeeded() {
    guard let viewModel,
      let index = viewModel.focusedFormulaHighlightIndex,
      viewModel.formulaReferenceHighlights.indices.contains(index)
    else { return }
    let highlight = viewModel.formulaReferenceHighlights[index]
    if let sheet = highlight.sheet,
      sheet.caseInsensitiveCompare(viewModel.activeSheet.name) != .orderedSame
    {
      return
    }
    let address = highlight.start
    let rect = rectForCell(row: address.row, col: address.col)
    scrollToVisible(rect.insetBy(dx: -40, dy: -40))
  }

  /// Where each sheet in this window was scrolled to, so returning to a tab (or an Undo that
  /// switches back to one) shows the same place rather than the top-left corner.
  private var scrollOriginBySheet: [UUID: CGPoint] = [:]
  private var scrolledSheetID: UUID?

  /// Shows another sheet, or the same sheet after its size or freeze changed.
  func reloadForSheetChange(to sheetID: UUID) {
    hideCommentCard()
    // Switching sheets already saved the typing to the sheet it was typed on. An editor left
    // open saved it again, into the cell selected on the new sheet, when it closed.
    if isEditorActive {
      hideEditor(commit: false, claimGridFocus: false)
    }
    if let previous = scrolledSheetID {
      scrollOriginBySheet[previous] = scrollOrigin
    }
    scrolledSheetID = sheetID
    reloadContent(resetScrollPosition: true)
    if let saved = scrollOriginBySheet[sheetID] {
      scrollOrigin = saved
      clampScrollOrigin()
    }
  }

  func reloadContent(resetScrollPosition shouldReset: Bool = false) {
    if shouldReset { scrollOrigin = .zero }
    needsViewportTileWarm = true
    discardScrollTiles()
    frameBitmap = nil
    testingFrameClears += 1
    invalidateLayoutCache()
    updateEditorFrame()
    layoutOnSheetCharts()
    window?.invalidateCursorRects(for: self)
    needsDisplay = true
    scheduleViewportTileWarm()
  }

  func scrollSelectionIntoView() {
    let didScroll = ensureSelectionVisible()
    updateEditorFrame()
    // Arrow-key navigation relies on selectionRevision → refreshSelectionDisplay().
    // Only force a full redraw when the viewport actually moved.
    if didScroll {
      needsDisplay = true
    }
  }

  /// Scroll one cell into view without following a merge's far corner.
  private func scrollAddressIntoView(_ address: CellAddress) {
    let before = scrollOrigin
    ensureCellVisible(row: address.row, col: address.col)
    updateEditorFrame()
    if before != scrollOrigin {
      needsDisplay = true
    }
  }

  // MARK: - Mouse

  override func mouseMoved(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    updateCursor(for: point)
    updateErrorToolTip(at: point)
    updateCommentCard(at: point)
    updateChartHover(at: point)
  }

  override func mouseExited(with event: NSEvent) {
    super.mouseExited(with: event)
    hideCommentCard()
    updateChartHover(at: nil)
  }

  private func updateErrorToolTip(at point: NSPoint) {
    guard let viewModel, contentRect.contains(point) else {
      toolTip = nil
      return
    }
    let address = addressAtContent(point: point)
    if let error = viewModel.displayValue(at: address).formulaError {
      toolTip = "\(error.displayCode) — \(error.explanation)"
    } else if viewModel.comment(at: address) != nil {
      // The comment card shows it.
      toolTip = nil
    } else {
      toolTip = viewModel.noteToolTip(at: address)
    }
  }

  /// Shows a cell's comment after the pointer rests on it briefly. Moving off hides it.
  private func updateCommentCard(at point: NSPoint) {
    guard let viewModel, !isEditorActive, contentRect.contains(point) else {
      hideCommentCard()
      return
    }
    let address = viewModel.activeSheet.mergeAnchor(for: addressAtContent(point: point))
    guard viewModel.comment(at: address) != nil else {
      hideCommentCard()
      return
    }
    guard address != hoveredCommentAddress else { return }
    hideCommentCard()
    hoveredCommentAddress = address
    commentHoverTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) {
      [weak self] _ in
      self?.showCommentCard(at: address)
    }
  }

  private func showCommentCard(at address: CellAddress) {
    guard let viewModel, !isEditorActive, let comment = viewModel.comment(at: address),
      let cell = paintRect(for: address, sheet: viewModel.activeSheet)
    else { return }
    commentCard.show(
      author: comment.author, text: comment.text, beside: cell, within: contentRect)
  }

  private func hideCommentCard() {
    commentHoverTimer?.invalidate()
    commentHoverTimer = nil
    hoveredCommentAddress = nil
    commentCard.hide()
  }

  override func cursorUpdate(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    updateCursor(for: point)
  }

  override func mouseDown(with event: NSEvent) {
    window?.makeFirstResponder(self)
    let point = convert(event.locationInWindow, from: nil)

    if isEditorActive { hideEditor(commit: true) }

    if isPointInFillHandle(point) {
      fillSourceRange = viewModel?.selectionRange
      isDraggingFill = true
      return
    }

    if let button = outlineButton(at: point) {
      viewModel?.toggleOutlineGroup(button.group, button.axis)
      needsDisplay = true
      return
    }

    // Before resizing: the chevrons sit right at the edge a resize grabs.
    if let chevron = hiddenRunChevron(at: point) {
      viewModel?.unhideRun(chevron.axis, containing: chevron.hiddenIndex)
      needsDisplay = true
      return
    }

    if let target = resizeTarget(at: point) {
      if event.clickCount >= 2 {
        switch target {
        case .column(let col, _, _):
          // Double-click the left edge of column A (against the corner) fits every column.
          if col == 0, abs(point.x - headerSize) <= resizeHandleThickness {
            viewModel?.autoFitAllColumns()
          } else {
            viewModel?.autoFitColumn(col)
          }
        case .row(let row, _, _):
          // Double-click the top edge of row 1 (against the corner) fits every row.
          if row == 0, abs(point.y - headerSize) <= resizeHandleThickness {
            viewModel?.autoFitAllRows()
          } else {
            viewModel?.autoFitRow(row)
          }
        }
        invalidateLayoutCache()
        updateEditorFrame()
        needsDisplay = true
        return
      }
      activeResize = target
      return
    }

    switch headerHit(at: point) {
    case .corner:
      viewModel?.toggleSelectAll()
      window?.makeFirstResponder(self)
      needsDisplay = true
      return
    case .column(let col):
      if event.modifierFlags.contains(.command) {
        viewModel?.commandClickColumn(col)
      } else {
        viewModel?.selectColumn(col)
        headerDrag = .columns(anchor: col)
      }
      needsDisplay = true
      return
    case .row(let row):
      if event.modifierFlags.contains(.command) {
        viewModel?.commandClickRow(row)
      } else {
        viewModel?.selectRow(row)
        headerDrag = .rows(anchor: row)
      }
      needsDisplay = true
      return
    case .content:
      break
    }

    guard contentRect.contains(point) else { return }
    // Ignore clicks in the empty band below collapsed/filter-hidden content.
    if point.y > contentBottomY() + 1 {
      return
    }

    if let chart = chartHitTest(at: point) {
      let rect = chartRect(for: chart)
      let selected = viewModel?.selectedChartID == chart.id
      let hit = OnSheetChartGeometry.frameHandle(
        at: point, in: rect, thickness: chartHandleThickness)
      let handle: OnSheetChartGeometry.ChartFrameHandle
      if selected, let hit, hit != .body {
        handle = hit
      } else {
        handle = .body
      }
      viewModel?.selectChart(id: chart.id, scroll: false)
      if event.clickCount >= 2, handle == .body {
        viewModel?.beginEditChart(id: chart.id)
        needsDisplay = true
        return
      }
      activeChartDrag = ChartDragState(
        chartID: chart.id,
        handle: handle,
        startPoint: point,
        startChart: chart,
        startRect: rect,
        hasMoved: false
      )
      isDraggingSelection = false
      needsDisplay = true
      return
    }
    viewModel?.selectChart(id: nil)

    if let placement = importedChartHitTest(at: point), let host = importedChartHosts[placement.id]
    {
      let rect = importedChartRect(placement)
      let wasSelected = viewModel?.selectedImportedChartID == placement.id
      viewModel?.selectImportedChart(placement.id)
      if event.clickCount >= 2 {
        viewModel?.beginEditImportedChart(placement.id)
        needsDisplay = true
        return
      }
      var handle = OnSheetChartGeometry.ChartFrameHandle.body
      if wasSelected,
        let hit = OnSheetChartGeometry.frameHandle(
          at: point, in: rect, thickness: chartHandleThickness)
      {
        handle = hit
      }
      activeImportedChartDrag = ImportedChartDrag(
        id: placement.id, handle: handle, startPoint: point, startRect: rect,
        startHostFrame: host.frame)
      isDraggingSelection = false
      layoutOnSheetCharts()
      needsDisplay = true
      return
    }
    viewModel?.selectImportedChart(nil)

    if handleImageMouseDown(at: point, event: event) {
      needsDisplay = true
      return
    }
    viewModel?.selectImage(id: nil)

    if let box = dropdownButtonRect(), box.contains(point) {
      presentDropdownMenu()
      return
    }

    let rawAddress = addressAtContent(point: point)
    let address = viewModel?.activeSheet.mergeAnchor(for: rawAddress) ?? rawAddress
    if rowHeight(at: address.row) <= 0 {
      return
    }
    if viewModel?.isFilterHeaderCell(row: address.row, col: address.col) == true,
      isInFilterAffordance(point: point, address: address)
    {
      presentFilterPopover(for: address)
      window?.makeFirstResponder(self)
      return
    }
    // Command-click on a link follows it; on any other cell it adds to the selection.
    if event.modifierFlags.contains(.command), !event.modifierFlags.contains(.shift),
      let viewModel, let link = viewModel.followableLink(at: address)
    {
      viewModel.select(address)
      viewModel.openHyperlink(link)
      needsDisplay = true
      return
    }
    if event.modifierFlags.contains(.command) {
      let alreadySelected = viewModel?.isAddressSelected(address) == true
      viewModel?.commandClickCell(address)
      // A drag from a highlighted cell unhighlights; from any other cell it adds.
      isDraggingSelection = !alreadySelected
      isDraggingDeselection = alreadySelected
      needsDisplay = true
      return
    }

    isDraggingSelection = true
    viewModel?.selectRange(from: address, to: address)

    if event.clickCount >= 2 {
      isDraggingSelection = false
      viewModel?.beginEditing()
      if viewModel?.isEditing == true { showEditor(selectAll: false) }
    } else {
      // Keep the expanded merge selected, but stay on the cell that was clicked.
      scrollAddressIntoView(rawAddress)
    }
  }

  private func isInFilterAffordance(point: NSPoint, address: CellAddress) -> Bool {
    let rect = rectForCell(row: address.row, col: address.col)
    return filterAffordanceRect(forCell: rect).contains(point)
  }

  private func presentFilterPopover(for address: CellAddress) {
    guard let viewModel, viewModel.filterState != nil else { return }
    filterPopover?.close()
    let header = viewModel.displayString(at: address)
    let title = header.isEmpty ? A1Notation.columnLabel(for: address.col) : header
    let popover = NSPopover()
    popover.behavior = .transient
    popover.animates = false
    let relayout: () -> Void = { [weak self] in
      self?.invalidateLayoutCache()
      self?.needsDisplay = true
    }
    let controller = FilterPopoverController(
      rootView: FilterPopoverView(
        viewModel: viewModel,
        column: address.col,
        title: title,
        onChange: relayout,
        onDone: { [weak popover] in popover?.close() }
      )
    )
    controller.sheetUndoManager = viewModel.undoManager
    controller.onUndo = relayout
    popover.contentViewController = controller
    filterPopover = popover
    let anchor = filterAffordanceRect(forCell: rectForCell(row: address.row, col: address.col))
    popover.show(relativeTo: anchor, of: self, preferredEdge: .maxY)
  }

  override func flagsChanged(with event: NSEvent) {
    super.flagsChanged(with: event)
    guard let drag = activeChartDrag, drag.hasMoved else { return }
    let point = convert(event.locationInWindow, from: nil)
    applyChartDrag(
      to: point,
      freePlacement: Self.chartDragUsesFreePlacement(modifierFlags: event.modifierFlags)
    )
  }

  override func mouseDragged(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)

    if let resize = activeResize {
      switch resize {
      case .column(let col, let startWidth, let startX):
        let delta = point.x - startX
        viewModel?.setColumnWidth(col, width: (startWidth + delta) / zoomScale, recordUndo: false)
      case .row(let row, let startHeight, let startY):
        let delta = point.y - startY
        viewModel?.setRowHeight(row, height: (startHeight + delta) / zoomScale, recordUndo: false)
      }
      invalidateLayoutCache()
      window?.invalidateCursorRects(for: self)
      updateEditorFrame()
      layoutOnSheetCharts()
      needsDisplay = true
      return
    }

    if let drag = activeImportedChartDrag {
      // A click that wobbles a point is still a click, not a move.
      if !drag.hasMoved,
        hypot(point.x - drag.startPoint.x, point.y - drag.startPoint.y) < 3
      {
        return
      }
      activeImportedChartDrag?.hasMoved = true
      let rect = Self.importedChartFrame(
        drag, dx: point.x - drag.startPoint.x, dy: point.y - drag.startPoint.y,
        headerSize: headerSize)
      importedChartHosts[drag.id]?.frame = rect.offsetBy(
        dx: drag.startHostFrame.minX - drag.startRect.minX,
        dy: drag.startHostFrame.minY - drag.startRect.minY)
      return
    }

    if let drag = activeChartDrag {
      if point != drag.startPoint {
        activeChartDrag?.hasMoved = true
      }
      if activeChartDrag?.hasMoved == true {
        applyChartDrag(
          to: point,
          freePlacement: Self.chartDragUsesFreePlacement(modifierFlags: event.modifierFlags)
        )
      }
      updateCursor(for: point)
      return
    }

    if activeImageDrag != nil {
      applyImageDrag(to: point)
      updateCursor(for: point)
      return
    }

    if let headerDrag {
      switch headerDrag {
      case .columns(let anchor):
        viewModel?.selectColumns(from: anchor, to: addressAtDragPoint(point).col)
        updateAutoscrollTimer(at: point, kind: .headerColumns(anchor))
        needsDisplay = true
        return
      case .rows(let anchor):
        viewModel?.selectRows(from: anchor, to: addressAtDragPoint(point).row)
        updateAutoscrollTimer(at: point, kind: .headerRows(anchor))
        needsDisplay = true
        return
      }
    }

    if isDraggingFill, let viewModel, let source = fillSourceRange {
      let end = addressAtDragPoint(point)
      let normalized = source.normalized
      let fillEnd = CellAddress(
        row: max(normalized.maxRow, end.row),
        col: max(normalized.maxCol, end.col)
      )
      viewModel.extendSelection(to: fillEnd)
      // Revealing the end cell slides the sheet under a still pointer, so the
      // next drag event lands on the next row and the fill runs away. The
      // autoscroll timer is what moves the sheet at the screen edge.
      updateAutoscrollTimer(at: point, kind: .fill(source))
      return
    }

    if isDraggingDeselection, let viewModel {
      viewModel.extendCommandDeselect(to: addressAtDragPoint(point))
      updateAutoscrollTimer(at: point, kind: .deselection)
      return
    }

    guard isDraggingSelection, let viewModel else { return }
    viewModel.extendSelection(to: addressAtDragPoint(point))
    // The anchor is behind the viewport once the drag has left the screen.
    // Scrolling it back into view jumps past the cell where the pointer stopped.
    updateAutoscrollTimer(at: point, kind: .selection)
  }

  override func mouseUp(with event: NSEvent) {
    stopAutoscrollTimer()

    if let drag = activeImportedChartDrag {
      activeImportedChartDrag = nil
      if drag.hasMoved {
        let point = convert(event.locationInWindow, from: nil)
        commitImportedChartDrag(
          drag, dx: point.x - drag.startPoint.x, dy: point.y - drag.startPoint.y)
      }
      layoutOnSheetCharts()
      needsDisplay = true
      return
    }

    if let drag = activeChartDrag {
      if drag.hasMoved {
        let point = convert(event.locationInWindow, from: nil)
        applyChartDrag(
          to: point,
          freePlacement: Self.chartDragUsesFreePlacement(modifierFlags: event.modifierFlags)
        )
      }
      finishChartDragIfNeeded()
      needsDisplay = true
    }

    if activeImageDrag != nil {
      finishImageDragIfNeeded()
      needsDisplay = true
    }

    if isDraggingFill, let viewModel, let source = fillSourceRange {
      let end = addressAtDragPoint(convert(event.locationInWindow, from: nil))
      let normalized = source.normalized
      if end.row > normalized.maxRow || end.col > normalized.maxCol {
        viewModel.fillSelection(
          from: source, to: end, alternate: event.modifierFlags.contains(.option))
      } else {
        viewModel.selectRange(from: source.start, to: source.end)
      }
      isDraggingFill = false
      fillSourceRange = nil
      syncDisplay()
      return
    }

    if let resize = activeResize {
      switch resize {
      case .column(let col, let startWidth, _):
        viewModel?.commitColumnWidthResize(col: col, from: startWidth / zoomScale)
      case .row(let row, let startHeight, _):
        viewModel?.commitRowHeightResize(row: row, from: startHeight / zoomScale)
      }
      activeResize = nil
      window?.invalidateCursorRects(for: self)
      let point = convert(event.locationInWindow, from: nil)
      updateCursor(for: point)
    }
    headerDrag = nil
    if isDraggingSelection {
      viewModel?.applyFormatPainterIfActive()
    }
    isDraggingSelection = false
    if isDraggingDeselection {
      isDraggingDeselection = false
      viewModel?.endCommandDeselect()
    }
  }

  override func scrollWheel(with event: NSEvent) {
    hideCommentCard()
    updateChartHover(at: nil)
    let invert = AppSettings.shared.invertScrollDirection
    let previousOrigin = scrollOrigin
    scrollOrigin.x += event.scrollingDeltaX
    scrollOrigin.y += event.scrollingDeltaY * (invert ? -1 : 1)
    clampScrollOrigin()
    guard scrollOrigin != previousOrigin else { return }
    noteScrollVelocity(
      CGPoint(x: scrollOrigin.x - previousOrigin.x, y: scrollOrigin.y - previousOrigin.y))
    if useWarmTilesForScroll() {
      return
    }
    updateEditorFrame()
    layoutOnSheetCharts()
    // Paint the viewport from the cell store. Do not blit or raster a body plane.
    if scrollSurfacesPresented {
      hideScrollSurfaces()
    }
    needsDisplay = true
  }

  func testingResetScrollCounters() {
    liveScrollCellVisits = 0
    testingGridVisits = 0
    testingOverlayVisits = 0
    testingGridDraws = 0
    liveScrollTextPaints = 0
    liveScrollPlaneBuilds = 0
    liveScrollHeaderDraws = 0
    liveScrollMaxRow = -1
  }

  /// Rasterize scroll planes without counting the work as a scroll tick.
  func testingWarmScrollPlanes() {
    buildScrollPlanesIfNeeded()
  }

  /// Scroll the grid the way a trackpad tick does. Returns false at the content edge.
  @discardableResult
  func testingApplyScroll(dx: CGFloat, dy: CGFloat) -> Bool {
    let started = CFAbsoluteTimeGetCurrent()
    defer { noteMainStall(CFAbsoluteTimeGetCurrent() - started) }
    testingResetScrollCounters()
    let previousOrigin = scrollOrigin
    scrollOrigin.x += dx
    scrollOrigin.y += dy
    clampScrollOrigin()
    guard scrollOrigin != previousOrigin else { return false }
    noteScrollVelocity(
      CGPoint(x: scrollOrigin.x - previousOrigin.x, y: scrollOrigin.y - previousOrigin.y))
    if useWarmTilesForScroll() {
      return true
    }
    updateEditorFrame()
    layoutOnSheetCharts()
    if scrollSurfacesPresented {
      hideScrollSurfaces()
    }
    display()
    // An offscreen window can return from display() without drawing. A frame on
    // screen would have painted. Draw once so the timed frame includes that paint.
    if testingGridDraws == 0, bounds.width > 1, bounds.height > 1 {
      draw(bounds)
    }
    return true
  }

  override func menu(for event: NSEvent) -> NSMenu? {
    let point = convert(event.locationInWindow, from: nil)

    if let viewModel, contentRect.contains(point), let chart = chartHitTest(at: point) {
      viewModel.selectChart(id: chart.id)
      needsDisplay = true
      return chartContextMenu()
    }

    if let viewModel, contentRect.contains(point),
      let placement = importedChartHitTest(at: point)
    {
      viewModel.selectChart(id: nil)
      viewModel.selectImportedChart(placement.id)
      layoutOnSheetCharts()
      needsDisplay = true
      return importedChartContextMenu()
    }

    if let viewModel, contentRect.contains(point), let hit = imageHitTest(at: point) {
      viewModel.selectImage(id: hit.id, bringToFront: true)
      needsDisplay = true
      return imageContextMenu()
    }

    if let viewModel {
      switch headerHit(at: point) {
      case .row(let row):
        // Keep a multi-row header selection so Insert can offer that many rows.
        if viewModel.selectionAxis == .row, viewModel.isRowInSelection(row) {
          break
        }
        viewModel.selectRow(row)
        needsDisplay = true
      case .column(let col):
        if viewModel.selectionAxis == .column, viewModel.isColumnInSelection(col) {
          break
        }
        viewModel.selectColumn(col)
        needsDisplay = true
      case .content:
        viewModel.selectChart(id: nil)
        viewModel.selectImportedChart(nil)
        viewModel.selectImage(id: nil)
        let address = addressAtContent(point: point)
        if !viewModel.isAddressSelected(address) {
          viewModel.selectRange(from: address, to: address)
          needsDisplay = true
        }
      case .corner:
        break
      }
    }

    let menu = NSMenu()
    if let viewModel, viewModel.followableLink(at: viewModel.selectionAnchor) != nil {
      _ = addMenuItem(menu, "Open Link", #selector(handleMenuOpenLink(_:)))
    }
    if let viewModel, viewModel.selectionAxis == .cells {
      let hasLink = viewModel.selectedHyperlink != nil
      _ = addMenuItem(
        menu, hasLink ? "Edit Link…" : "Add Link…", #selector(handleMenuLink(_:)))
      if hasLink {
        _ = addMenuItem(menu, "Remove Link", #selector(handleMenuRemoveLink(_:)))
      }
      menu.addItem(.separator())
    }
    if let viewModel, viewModel.selectionAxis == .cells {
      let hasComment = viewModel.selectedComment != nil
      _ = addMenuItem(
        menu, hasComment ? "Edit Comment…" : "Add Comment…", #selector(handleMenuComment(_:)))
      if hasComment {
        _ = addMenuItem(menu, "Delete Comment", #selector(handleMenuDeleteComment(_:)))
      }
      _ = addMenuItem(
        menu, viewModel.selectedDropdownSource == nil ? "Dropdown List…" : "Edit Dropdown List…",
        #selector(handleMenuDropdown(_:)))
      menu.addItem(.separator())
    }
    let cut = menu.addItem(
      withTitle: "Cut", action: #selector(handleMenuCut(_:)), keyEquivalent: "")
    cut.target = self
    let copy = menu.addItem(
      withTitle: "Copy", action: #selector(handleMenuCopy(_:)), keyEquivalent: "")
    copy.target = self
    let paste = menu.addItem(
      withTitle: "Paste", action: #selector(handleMenuPaste(_:)), keyEquivalent: "")
    paste.target = self
    menu.addItem(.separator())
    addPrimaryContextActions(to: menu)
    menu.addItem(.separator())
    addStructureSubmenus(to: menu)
    return menu
  }

  private func chartContextMenu() -> NSMenu {
    let menu = NSMenu()
    addMenuItem(menu, "Edit Chart…", #selector(handleMenuEditChart(_:)))
    addMenuItem(menu, "Delete Chart", #selector(handleMenuDeleteChart(_:)))
    return menu
  }

  private func importedChartContextMenu() -> NSMenu {
    let menu = NSMenu()
    addMenuItem(menu, "Edit Chart…", #selector(handleMenuEditImportedChart(_:)))
    addMenuItem(menu, "Duplicate Chart", #selector(handleMenuDuplicateImportedChart(_:)))
    menu.addItem(.separator())
    addMenuItem(menu, "Bring to Front", #selector(handleMenuImportedChartToFront(_:)))
    addMenuItem(menu, "Send to Back", #selector(handleMenuImportedChartToBack(_:)))
    menu.addItem(.separator())
    addMenuItem(menu, "Delete Chart", #selector(handleMenuDeleteImportedChart(_:)))
    return menu
  }

  @objc private func handleMenuEditImportedChart(_ sender: Any?) {
    guard let id = viewModel?.selectedImportedChartID else { return }
    viewModel?.beginEditImportedChart(id)
  }

  @objc private func handleMenuDuplicateImportedChart(_ sender: Any?) {
    guard let id = viewModel?.selectedImportedChartID else { return }
    viewModel?.duplicateImportedChart(id)
    layoutOnSheetCharts()
    needsDisplay = true
  }

  @objc private func handleMenuImportedChartToFront(_ sender: Any?) {
    guard let id = viewModel?.selectedImportedChartID else { return }
    viewModel?.reorderImportedChart(id, toFront: true)
    layoutOnSheetCharts()
  }

  @objc private func handleMenuImportedChartToBack(_ sender: Any?) {
    guard let id = viewModel?.selectedImportedChartID else { return }
    viewModel?.reorderImportedChart(id, toFront: false)
    layoutOnSheetCharts()
  }

  @objc private func handleMenuDeleteImportedChart(_ sender: Any?) {
    guard let id = viewModel?.selectedImportedChartID else { return }
    viewModel?.deleteImportedChart(id)
    layoutOnSheetCharts()
    needsDisplay = true
  }

  @objc private func handleMenuCreateTable(_ sender: Any?) {
    viewModel?.createTable()
    needsDisplay = true
  }

  @objc private func handleMenuRemoveTable(_ sender: Any?) {
    guard let viewModel, let index = viewModel.selectedTableIndex else { return }
    viewModel.removeTable(at: index)
    needsDisplay = true
  }

  @objc private func handleMenuTableStyle(_ sender: NSMenuItem) {
    guard let viewModel, let index = viewModel.selectedTableIndex,
      let name = sender.representedObject as? String
    else { return }
    viewModel.setTableStyle(name, at: index)
    needsDisplay = true
  }

  @objc private func handleMenuEditChart(_ sender: Any?) {
    guard let id = viewModel?.selectedChartID else { return }
    viewModel?.beginEditChart(id: id)
  }

  @objc private func handleMenuDeleteChart(_ sender: Any?) {
    guard let id = viewModel?.selectedChartID else { return }
    viewModel?.removeChart(id: id)
    needsDisplay = true
  }

  private func imageContextMenu() -> NSMenu {
    let menu = NSMenu()
    let cut = menu.addItem(
      withTitle: "Cut", action: #selector(handleMenuCutImage(_:)), keyEquivalent: "")
    cut.target = self
    let copy = menu.addItem(
      withTitle: "Copy", action: #selector(handleMenuCopyImage(_:)), keyEquivalent: "")
    copy.target = self
    let paste = menu.addItem(
      withTitle: "Paste", action: #selector(handleMenuPaste(_:)), keyEquivalent: "")
    paste.target = self
    menu.addItem(.separator())
    addMenuItem(menu, "Bring to Front", #selector(handleMenuBringImageToFront(_:)))
    addMenuItem(menu, "Send to Back", #selector(handleMenuSendImageToBack(_:)))
    menu.addItem(.separator())
    addMenuItem(menu, "Delete Picture", #selector(handleMenuDeleteImage(_:)))
    return menu
  }

  private func addPrimaryContextActions(to menu: NSMenu) {
    guard let viewModel else { return }

    if let table = viewModel.selectedTableIndex {
      let styles = NSMenu(title: "Table Style")
      let current = viewModel.tableStyleName(at: table)
      for style in SpreadsheetViewModel.tableStyles {
        let item = addMenuItem(styles, style.title, #selector(handleMenuTableStyle(_:)))
        item.representedObject = style.name
        item.state = style.name == current ? .on : .off
      }
      let stylesItem = menu.addItem(withTitle: "Table Style", action: nil, keyEquivalent: "")
      stylesItem.submenu = styles
      addMenuItem(menu, "Remove Table", #selector(handleMenuRemoveTable(_:)))
    } else {
      let create = addMenuItem(menu, "Create Table", #selector(handleMenuCreateTable(_:)))
      create.isEnabled = viewModel.newTableRange != nil
    }
    menu.addItem(.separator())

    addMenuItem(menu, "Create a Filter", #selector(handleMenuCreateFilter(_:)))
    let clearFilter = addMenuItem(menu, "Clear Filter", #selector(handleMenuClearFilter(_:)))
    clearFilter.isEnabled = viewModel.filterState != nil
    let clearColumn = addMenuItem(
      menu,
      "Clear Filter for Column",
      #selector(handleMenuClearColumnFilter(_:))
    )
    clearColumn.isEnabled = viewModel.isFilterColumn(viewModel.selectionAnchor.col)

    menu.addItem(.separator())

    let merge = NSMenu(title: "Merge")
    let mergeAll = addMenuItem(merge, "Merge All", #selector(handleMenuMergeAll(_:)))
    mergeAll.isEnabled = viewModel.canMergeSelection
    let mergeAcross = addMenuItem(merge, "Merge Across", #selector(handleMenuMergeAcross(_:)))
    mergeAcross.isEnabled = viewModel.canMergeHorizontally
    let mergeVertical = addMenuItem(
      merge, "Merge Vertically", #selector(handleMenuMergeVertical(_:)))
    mergeVertical.isEnabled = viewModel.canMergeVertically
    merge.addItem(.separator())
    let unmerge = addMenuItem(merge, "Unmerge Cells", #selector(handleMenuUnmerge(_:)))
    unmerge.isEnabled = viewModel.canUnmergeSelection
    let mergeItem = NSMenuItem(title: "Merge", action: nil, keyEquivalent: "")
    mergeItem.submenu = merge
    menu.addItem(mergeItem)
  }

  @objc private func handleMenuHideRows(_ sender: Any?) {
    viewModel?.hideSelected(.rows)
  }

  @objc private func handleMenuUnhideRows(_ sender: Any?) {
    viewModel?.unhideSelected(.rows)
  }

  @objc private func handleMenuHideColumns(_ sender: Any?) {
    viewModel?.hideSelected(.columns)
  }

  @objc private func handleMenuUnhideColumns(_ sender: Any?) {
    viewModel?.unhideSelected(.columns)
  }

  private func addStructureSubmenus(to menu: NSMenu) {
    guard let viewModel else { return }
    let axis = viewModel.selectionAxis
    let showRows = axis != .column
    let showCols = axis != .row

    if showRows || showCols {
      if showRows {
        addMenuItem(
          menu,
          viewModel.insertRowAboveTitle,
          #selector(handleMenuInsertRowAbove(_:)),
          tag: viewModel.rowInsertCount
        )
        addMenuItem(
          menu,
          viewModel.insertRowBelowTitle,
          #selector(handleMenuInsertRowBelow(_:)),
          tag: viewModel.rowInsertCount
        )
        addMenuItem(menu, "Delete Row(s)", #selector(handleMenuDeleteRows(_:)))
        if axis == .row {
          addMenuItem(menu, "Hide Rows", #selector(handleMenuHideRows(_:)))
        }
        if viewModel.canUnhideInSelection.rows {
          addMenuItem(menu, "Unhide Rows", #selector(handleMenuUnhideRows(_:)))
        }
      }
      if showRows && showCols {
        menu.addItem(.separator())
      }
      if showCols {
        addMenuItem(
          menu,
          viewModel.insertColumnLeftTitle,
          #selector(handleMenuInsertColumnLeft(_:)),
          tag: viewModel.columnInsertCount
        )
        addMenuItem(
          menu,
          viewModel.insertColumnRightTitle,
          #selector(handleMenuInsertColumnRight(_:)),
          tag: viewModel.columnInsertCount
        )
        addMenuItem(menu, "Delete Column(s)", #selector(handleMenuDeleteColumns(_:)))
        if axis == .column {
          addMenuItem(menu, "Hide Columns", #selector(handleMenuHideColumns(_:)))
        }
        if viewModel.canUnhideInSelection.columns {
          addMenuItem(menu, "Unhide Columns", #selector(handleMenuUnhideColumns(_:)))
        }
      }
      menu.addItem(.separator())
    }

    let borders = NSMenu(title: "Borders")
    addMenuItem(borders, "All Borders", #selector(handleMenuBorderAll(_:)))
    addMenuItem(borders, "Outside Borders", #selector(handleMenuBorderOutside(_:)))
    addMenuItem(borders, "Bottom Border", #selector(handleMenuBorderBottom(_:)))
    addMenuItem(borders, "No Border", #selector(handleMenuBorderNone(_:)))
    let bordersItem = NSMenuItem(title: "Borders", action: nil, keyEquivalent: "")
    bordersItem.submenu = borders
    menu.addItem(bordersItem)

    let freeze = NSMenu(title: "Freeze")
    addMenuItem(freeze, "Freeze Panes", #selector(handleMenuFreezePanes(_:)))
    addMenuItem(freeze, viewModel.freezeRowsTitle, #selector(handleMenuFreezeRows(_:)))
    addMenuItem(freeze, viewModel.freezeColumnsTitle, #selector(handleMenuFreezeColumns(_:)))
    freeze.addItem(.separator())
    addMenuItem(freeze, "Unfreeze Panes", #selector(handleMenuUnfreezePanes(_:)))
    let freezeItem = NSMenuItem(title: "Freeze", action: nil, keyEquivalent: "")
    freezeItem.submenu = freeze
    menu.addItem(freezeItem)
  }

  @discardableResult
  private func addMenuItem(_ menu: NSMenu, _ title: String, _ action: Selector, tag: Int = 0)
    -> NSMenuItem
  {
    let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
    item.target = self
    item.tag = tag
    return item
  }

  private func menuInsertCount(from sender: Any?) -> Int? {
    guard let item = sender as? NSMenuItem, item.tag > 0 else { return nil }
    return item.tag
  }

  private func addStructureMenuItems(to menu: NSMenu) {
    addStructureSubmenus(to: menu)
  }

  @objc private func handleMenuCut(_ sender: Any?) {
    viewModel?.cutSelection()
    syncDisplay()
  }

  @objc private func handleMenuCopy(_ sender: Any?) {
    viewModel?.copySelectionToPasteboard()
  }

  @objc private func handleMenuPaste(_ sender: Any?) {
    SpreadsheetPaste.perform(on: viewModel)
    syncDisplay()
  }

  @objc private func handleMenuCutImage(_ sender: Any?) {
    viewModel?.cutSelectedImage()
    syncDisplay()
  }

  @objc private func handleMenuCopyImage(_ sender: Any?) {
    viewModel?.copySelectedImageToPasteboard()
  }

  @objc private func handleMenuDeleteImage(_ sender: Any?) {
    viewModel?.deleteSelectedImage()
    syncDisplay()
  }

  @objc private func handleMenuBringImageToFront(_ sender: Any?) {
    viewModel?.bringSelectedImageToFront()
    syncDisplay()
  }

  @objc private func handleMenuSendImageToBack(_ sender: Any?) {
    viewModel?.sendSelectedImageToBack()
    syncDisplay()
  }

  @objc private func handleMenuInsertRowAbove(_ sender: Any?) {
    viewModel?.insertRowsAbove(count: menuInsertCount(from: sender))
    syncDisplay()
  }

  @objc private func handleMenuInsertRowBelow(_ sender: Any?) {
    viewModel?.insertRowsBelow(count: menuInsertCount(from: sender))
    syncDisplay()
  }

  @objc private func handleMenuDeleteRows(_ sender: Any?) {
    viewModel?.deleteSelectedRows()
    syncDisplay()
  }

  @objc private func handleMenuInsertColumnLeft(_ sender: Any?) {
    viewModel?.insertColumnsLeft(count: menuInsertCount(from: sender))
    syncDisplay()
  }

  @objc private func handleMenuInsertColumnRight(_ sender: Any?) {
    viewModel?.insertColumnsRight(count: menuInsertCount(from: sender))
    syncDisplay()
  }

  @objc private func handleMenuDeleteColumns(_ sender: Any?) {
    viewModel?.deleteSelectedColumns()
    syncDisplay()
  }

  @objc private func handleMenuFreezePanes(_ sender: Any?) {
    guard viewModel?.freezePanesAtSelection() == true else {
      Self.presentFreezeRequiresOffsetAlert(axis: .both)
      return
    }
    applyFreezePanesLayout()
  }

  @objc private func handleMenuFreezeRows(_ sender: Any?) {
    guard viewModel?.freezeRowsAtSelection() == true else {
      Self.presentFreezeRequiresOffsetAlert(axis: .rows)
      return
    }
    applyFreezePanesLayout()
  }

  @objc private func handleMenuFreezeColumns(_ sender: Any?) {
    guard viewModel?.freezeColumnsAtSelection() == true else {
      Self.presentFreezeRequiresOffsetAlert(axis: .columns)
      return
    }
    applyFreezePanesLayout()
  }

  @objc private func handleMenuUnfreezePanes(_ sender: Any?) {
    viewModel?.unfreezePanes()
    applyFreezePanesLayout()
  }

  @objc private func handleMenuMergeAll(_ sender: Any?) {
    viewModel?.mergeSelection(axis: .all)
    syncDisplay()
  }

  @objc private func handleMenuMergeAcross(_ sender: Any?) {
    viewModel?.mergeSelection(axis: .horizontal)
    syncDisplay()
  }

  @objc private func handleMenuMergeVertical(_ sender: Any?) {
    viewModel?.mergeSelection(axis: .vertical)
    syncDisplay()
  }

  @objc private func handleMenuUnmerge(_ sender: Any?) {
    viewModel?.unmergeSelection()
    syncDisplay()
  }

  @objc private func handleMenuBorderAll(_ sender: Any?) {
    viewModel?.applyBorderPreset(.all)
    syncDisplay()
  }

  @objc private func handleMenuBorderOutside(_ sender: Any?) {
    viewModel?.applyBorderPreset(.outside)
    syncDisplay()
  }

  @objc private func handleMenuBorderBottom(_ sender: Any?) {
    viewModel?.applyBorderPreset(.bottom)
    syncDisplay()
  }

  @objc private func handleMenuBorderNone(_ sender: Any?) {
    viewModel?.applyBorderPreset(.none)
    syncDisplay()
  }

  @objc private func handleMenuCreateFilter(_ sender: Any?) {
    viewModel?.createFilter()
    syncDisplay()
  }

  @objc private func handleMenuClearFilter(_ sender: Any?) {
    viewModel?.clearFilter()
    syncDisplay()
  }

  @objc private func handleMenuClearColumnFilter(_ sender: Any?) {
    guard let viewModel else { return }
    viewModel.clearColumnFilter(viewModel.selectionAnchor.col)
    syncDisplay()
  }

  enum FreezeAlertAxis {
    case both
    case rows
    case columns
  }

  static func presentFreezeRequiresOffsetAlert(axis: FreezeAlertAxis) {
    let alert = NSAlert()
    alert.messageText = "Can’t Freeze Panes"
    switch axis {
    case .both:
      alert.informativeText =
        "Select the bottom-right cell of the area you want to keep visible, then try again. For example, select B2 to freeze row 1 and column A."
    case .rows:
      alert.informativeText =
        "Select the last row you want to keep frozen. For example, select row 3 to freeze rows 1–3."
    case .columns:
      alert.informativeText =
        "Select the last column you want to keep frozen. For example, select column C to freeze columns A–C."
    }
    alert.alertStyle = .informational
    alert.addButton(withTitle: "OK")
    alert.runModal()
  }

  // MARK: - Keyboard

  @objc override func selectAll(_ sender: Any?) {
    viewModel?.selectAll()
    needsDisplay = true
  }

  override func keyDown(with event: NSEvent) {
    if AppSettings.shared.matches(.save, event: event) {
      if SparkGridSaveShortcut.perform() { return }
    }
    guard let viewModel, !isEditorActive else {
      super.keyDown(with: event)
      return
    }

    switch event.keyCode {
    case 51, 117:
      if let chartID = viewModel.selectedChartID {
        viewModel.removeChart(id: chartID)
        needsDisplay = true
        return
      }
      if let imported = viewModel.selectedImportedChartID {
        viewModel.deleteImportedChart(imported)
        layoutOnSheetCharts()
        needsDisplay = true
        return
      }
      if viewModel.selectedImageID != nil {
        viewModel.deleteSelectedImage()
        needsDisplay = true
        return
      }
      viewModel.clearSelection()
    case 53:
      if viewModel.selectedChartID != nil {
        viewModel.selectChart(id: nil)
        needsDisplay = true
        return
      }
      if viewModel.selectedImportedChartID != nil {
        viewModel.selectImportedChart(nil)
        layoutOnSheetCharts()
        needsDisplay = true
        return
      }
      if viewModel.selectedImageID != nil {
        viewModel.selectImage(id: nil)
        needsDisplay = true
        return
      }
      if viewModel.duplicateHighlight != nil {
        viewModel.clearDuplicateHighlight()
        needsDisplay = true
        return
      }
      if viewModel.formatPainterBlock != nil {
        viewModel.formatPainterBlock = nil
        return
      }
    case 123, 124, 125, 126:
      if let imageID = viewModel.selectedImageID, let image = viewModel.image(with: imageID) {
        let nudge = event.modifierFlags.contains(.shift) ? 8.0 : 1.0
        let deltaX: CGFloat = event.keyCode == 123 ? -nudge : event.keyCode == 124 ? nudge : 0
        let deltaY: CGFloat = event.keyCode == 125 ? -nudge : event.keyCode == 126 ? nudge : 0
        let before = image
        let rect = imageRect(for: image)
        let placement = placementForImageTopLeft(x: rect.minX + deltaX, y: rect.minY + deltaY)
        viewModel.setImagePlacement(
          id: imageID,
          anchorRow: placement.row,
          anchorCol: placement.col,
          rowOffsetEMU: placement.rowOffsetEMU,
          colOffsetEMU: placement.colOffsetEMU
        )
        viewModel.commitImagePlacement(id: imageID, before: before, actionName: "Move Picture")
        needsDisplay = true
        return
      }
      // Option-Down opens the selected cell's dropdown list.
      if event.keyCode == 125, event.modifierFlags.contains(.option),
        viewModel.hasDropdown(at: viewModel.selectionAnchor)
      {
        presentDropdownMenu()
        break
      }
      if event.modifierFlags.contains(.command) {
        let rowStep = event.keyCode == 125 ? 1 : event.keyCode == 126 ? -1 : 0
        let colStep = event.keyCode == 124 ? 1 : event.keyCode == 123 ? -1 : 0
        viewModel.jumpSelection(
          rowStep: rowStep, colStep: colStep, extending: event.modifierFlags.contains(.shift))
        break
      }
      switch event.keyCode {
      case 123:
        viewModel.moveSelection(
          rowDelta: 0, colDelta: -1, extending: event.modifierFlags.contains(.shift))
      case 124:
        viewModel.moveSelection(
          rowDelta: 0, colDelta: 1, extending: event.modifierFlags.contains(.shift))
      case 125:
        viewModel.moveSelection(
          rowDelta: 1, colDelta: 0, extending: event.modifierFlags.contains(.shift))
      case 126:
        viewModel.moveSelection(
          rowDelta: -1, colDelta: 0, extending: event.modifierFlags.contains(.shift))
      default: break
      }
    case 120:
      // F2 edits the selected cell with the caret at the end, as other spreadsheet apps do.
      viewModel.beginEditing()
      if viewModel.isEditing { showEditor(selectAll: false) }
    case 36:
      if viewModel.isFindBarVisible {
        super.keyDown(with: event)
        return
      }
      viewModel.beginEditing()
      if viewModel.isEditing { showEditor(selectAll: false) }
      return
    case 48:
      // While editing, Tab / Shift-Tab already committed and moved one cell.
      // Handling this same key again would extend the range.
      if suppressFollowingTabMove || event.timestamp == lastTabMoveTimestamp {
        break
      }
      viewModel.moveSelection(
        rowDelta: 0,
        colDelta: event.modifierFlags.contains(.shift) ? -1 : 1,
        extending: event.modifierFlags.contains(.shift)
      )
    default:
      // Command and control shortcuts must not type into the selected cell.
      let shortcutMods = event.modifierFlags.intersection([.command, .control])
      if !shortcutMods.isEmpty || viewModel.isFindBarVisible {
        super.keyDown(with: event)
        break
      }
      if let chars = event.characters, chars.count == 1, let scalar = chars.unicodeScalars.first {
        let isPrintable =
          CharacterSet.alphanumerics.contains(scalar)
          || CharacterSet.punctuationCharacters.contains(scalar)
          || CharacterSet.symbols.contains(scalar)
          || scalar == " "
        if isPrintable {
          if viewModel.beginTyping(chars) { showEditor(selectAll: false) }
          return
        }
      }
      super.keyDown(with: event)
    }
    scrollSelectionIntoView()
  }

  /// Text being typed when Command-A is pressed: the formula bar, the in-cell editor, the name
  /// box or the find bar. Command-A selects that text rather than the sheet.
  private func formulaFieldForSelectAll() -> NSText? {
    guard let responder = window?.firstResponder else { return nil }
    if let text = responder as? NSText { return text }
    if responder === editor, isEditorActive { return editor.currentEditor() }
    return nil
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if AppSettings.shared.matches(.save, event: event) {
      return SparkGridSaveShortcut.perform()
    }
    let settings = AppSettings.shared
    let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
    if event.charactersIgnoringModifiers?.lowercased() == "a", mods == .command {
      if let formulaField = formulaFieldForSelectAll() {
        formulaField.selectAll(nil)
        return true
      }
      viewModel?.selectAll()
      needsDisplay = true
      return true
    }
    if settings.matches(.copy, event: event) {
      if viewModel?.selectedImageID != nil {
        viewModel?.copySelectedImageToPasteboard()
        return true
      }
      if viewModel?.copySelectionToPasteboard() == true {
        return true
      }
    }
    if settings.matches(.cut, event: event) {
      if viewModel?.selectedImageID != nil {
        viewModel?.cutSelectedImage()
        syncDisplay()
        return true
      }
      viewModel?.cutSelection()
      syncDisplay()
      return true
    }
    if settings.matches(.paste, event: event) {
      SpreadsheetPaste.perform(on: viewModel)
      syncDisplay()
      return true
    }
    if settings.matches(.copyFormulas, event: event) {
      viewModel?.copyFormulas()
      return true
    }
    if settings.matches(.pasteFormulas, event: event) {
      viewModel?.pasteFormulasFromPasteboard()
      syncDisplay()
      return true
    }
    if settings.matches(.convertToValues, event: event) {
      viewModel?.convertSelectionToValues()
      syncDisplay()
      return true
    }
    if settings.matches(.bold, event: event) {
      viewModel?.toggleBold()
      syncDisplay()
      return true
    }
    if settings.matches(.italic, event: event) {
      viewModel?.toggleItalic()
      syncDisplay()
      return true
    }
    if settings.matches(.underline, event: event) {
      viewModel?.toggleUnderline()
      syncDisplay()
      return true
    }
    return super.performKeyEquivalent(with: event)
  }
}

extension SpreadsheetGridNSView: NSTextFieldDelegate {
  func control(
    _ control: NSControl,
    textView: NSTextView,
    doCommandBy commandSelector: Selector
  ) -> Bool {
    guard isEditorActive else { return false }

    switch commandSelector {
    case #selector(NSResponder.insertNewline(_:)):
      commitEditorAndMove(rowDelta: 1, colDelta: 0)
      return true
    case #selector(NSResponder.cancelOperation(_:)):
      hideEditor(commit: false)
      return true
    case #selector(NSResponder.insertTab(_:)),
      #selector(NSResponder.insertTabIgnoringFieldEditor(_:)):
      if applyFormulaTabCompletion(in: textView) {
        return true
      }
      commitTabMove(colDelta: 1)
      return true
    case #selector(NSResponder.insertBacktab(_:)):
      // Shift-Tab commits and moves one cell left. It must not extend the range.
      commitTabMove(colDelta: -1)
      return true
    case #selector(NSResponder.moveUp(_:)):
      commitEditorAndMove(rowDelta: -1, colDelta: 0)
      return true
    case #selector(NSResponder.moveDown(_:)):
      commitEditorAndMove(rowDelta: 1, colDelta: 0)
      return true
    case #selector(NSResponder.moveLeft(_:)):
      commitEditorAndMove(rowDelta: 0, colDelta: -1)
      return true
    case #selector(NSResponder.moveRight(_:)):
      commitEditorAndMove(rowDelta: 0, colDelta: 1)
      return true
    case #selector(NSResponder.moveUpAndModifySelection(_:)):
      commitEditorAndMove(rowDelta: -1, colDelta: 0, extending: true)
      return true
    case #selector(NSResponder.moveDownAndModifySelection(_:)):
      commitEditorAndMove(rowDelta: 1, colDelta: 0, extending: true)
      return true
    case #selector(NSResponder.moveLeftAndModifySelection(_:)):
      // Some field editors deliver Shift-Tab as a selection-modifying move.
      if isTabKeyDown(NSApp.currentEvent) {
        commitTabMove(colDelta: -1)
      } else {
        commitEditorAndMove(rowDelta: 0, colDelta: -1, extending: true)
      }
      return true
    case #selector(NSResponder.moveRightAndModifySelection(_:)):
      if isTabKeyDown(NSApp.currentEvent) {
        commitTabMove(colDelta: 1)
      } else {
        commitEditorAndMove(rowDelta: 0, colDelta: 1, extending: true)
      }
      return true
    default:
      return false
    }
  }

  private var namedRangeNames: [String] {
    guard let keys = viewModel?.workbook.namedRanges.keys else { return [] }
    return Array(keys)
  }

  @discardableResult
  private func applyFormulaTabCompletion(in textView: NSTextView) -> Bool {
    let cursor = textView.selectedRange.location
    guard
      let result = FormulaAutocomplete.tabComplete(
        text: textView.string,
        utf16Cursor: cursor,
        namedRanges: namedRangeNames
      )
    else { return false }
    textView.string = result.text
    textView.setSelectedRange(NSRange(location: result.cursor, length: 0))
    editor.stringValue = result.text
    viewModel?.editText = result.text
    viewModel?.noteFormulaEditTextChanged()
    return true
  }

  func controlTextDidEndEditing(_ obj: Notification) {
    guard isEditorActive else { return }
    let movement = (obj.userInfo?["NSTextMovement"] as? NSNumber)?.intValue
    if movement == NSTextMovement.cancel.rawValue {
      hideEditor(commit: false)
      return
    }
    // Field editor ended on Tab / Shift-Tab before the command handler moved.
    // Move one cell and do not let the same key extend the selection.
    if movement == NSTextMovement.tab.rawValue {
      commitTabMove(colDelta: 1)
      return
    }
    if movement == NSTextMovement.backtab.rawValue {
      commitTabMove(colDelta: -1)
      return
    }
    hideEditor(commit: true)
  }

  func controlTextDidChange(_ obj: Notification) {
    guard !isApplyingFormulaAttributes else { return }
    viewModel?.editText = editor.stringValue
    viewModel?.noteFormulaEditTextChanged()
    if let fieldEditor = editor.currentEditor() as? NSTextView {
      viewModel?.updateFormulaHighlightFocus(atUTF16: fieldEditor.selectedRange.location)
      EditorSpellCheck.apply(to: fieldEditor, text: fieldEditor.string, refresh: false)
    }
    applyInCellFormulaAttributes(preserveSelection: true)
    maybeOfferFormulaCompletions()
  }

  func control(
    _ control: NSControl,
    textView: NSTextView,
    completions words: [String],
    forPartialWordRange charRange: NSRange,
    indexOfSelectedItem index: UnsafeMutablePointer<Int>
  ) -> [String] {
    guard editor.stringValue.hasPrefix("=") else { return [] }
    guard
      FormulaAutocomplete.shouldOfferPopup(
        in: textView.string,
        utf16Cursor: charRange.location + charRange.length,
        namedRanges: namedRangeNames
      )
    else { return [] }
    let partial = (textView.string as NSString).substring(with: charRange)
    index.pointee = 0
    return FormulaAutocomplete.suggestions(
      matching: partial,
      namedRanges: namedRangeNames
    )
  }

  private func maybeOfferFormulaCompletions() {
    guard let window = window,
      let fieldEditor = window.fieldEditor(false, for: editor) as? NSTextView
    else { return }

    let cursor = fieldEditor.selectedRange.location
    guard
      FormulaAutocomplete.shouldOfferPopup(
        in: fieldEditor.string,
        utf16Cursor: cursor,
        namedRanges: namedRangeNames
      )
    else {
      NSObject.cancelPreviousPerformRequests(
        withTarget: self, selector: #selector(triggerFormulaComplete), object: nil)
      return
    }

    NSObject.cancelPreviousPerformRequests(
      withTarget: self, selector: #selector(triggerFormulaComplete), object: nil)
    perform(#selector(triggerFormulaComplete), with: nil, afterDelay: 0.12)
  }

  @objc private func triggerFormulaComplete() {
    guard isEditorActive,
      !isApplyingFormulaAttributes,
      let window = window,
      let fieldEditor = window.fieldEditor(false, for: editor) as? NSTextView
    else { return }
    fieldEditor.complete(nil)
  }
}

/// In-cell editor. Marked so the window can install a field editor that ignores ⌘S.
final class CellEditorTextField: NSTextField {}

/// Field editor that saves on the Save shortcut instead of inserting the key.
final class CellFieldEditor: NSTextView {
  private var isHandlingTextChange = false
  private var isApplyingSpellPolicy = false

  override func didChangeText() {
    // Applying the policy can notify a text change. Ignore that re-entry so
    // AppKit does not put the defaults back on top of the policy.
    if isApplyingSpellPolicy {
      return
    }
    if isHandlingTextChange {
      super.didChangeText()
      return
    }
    isHandlingTextChange = true
    isAutomaticSpellingCorrectionEnabled = false
    isGrammarCheckingEnabled = false
    super.didChangeText()
    isHandlingTextChange = false
    isApplyingSpellPolicy = true
    EditorSpellCheck.apply(
      to: self,
      text: string,
      refresh: EditorSpellCheck.shouldCheck(string)
    )
    isApplyingSpellPolicy = false
  }

  override func checkText(
    in range: NSRange,
    types checkingTypes: NSTextCheckingTypes,
    options: [NSSpellChecker.OptionKey: Any] = [:]
  ) {
    guard EditorSpellCheck.shouldCheck(string) else { return }
    super.checkText(in: range, types: checkingTypes, options: options)
    guard !isApplyingSpellPolicy else { return }
    isApplyingSpellPolicy = true
    EditorSpellCheck.markSystemSpelling(
      on: self,
      language: EditorSpellCheck.spellingLanguage(in: options)
    )
    isApplyingSpellPolicy = false
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if AppSettings.shared.matches(.save, event: event) {
      return SparkGridSaveShortcut.perform()
    }
    return super.performKeyEquivalent(with: event)
  }

  override func keyDown(with event: NSEvent) {
    if AppSettings.shared.matches(.save, event: event) {
      if SparkGridSaveShortcut.perform() { return }
    }
    super.keyDown(with: event)
  }

  override func insertText(_ insertString: Any, replacementRange: NSRange) {
    if let event = NSApp.currentEvent,
      event.type == .keyDown,
      AppSettings.shared.matches(.save, event: event)
    {
      _ = SparkGridSaveShortcut.perform()
      return
    }
    super.insertText(insertString, replacementRange: replacementRange)
  }

  override func insertCompletion(
    _ word: String,
    forPartialWordRange charRange: NSRange,
    movement: Int,
    isFinal flag: Bool
  ) {
    let partial = Self.partialWord(in: string, range: charRange)
    let before = string
    super.insertCompletion(word, forPartialWordRange: charRange, movement: movement, isFinal: flag)
    // Return on a finished token (`=SUM`) accepts the popup again and never
    // reaches insertNewline. Commit when this key did not change the text.
    let commitOnReturn =
      flag
      && movement == NSTextMovement.`return`.rawValue
      && (before == string
        || FormulaAutocomplete.isExactCompletion(partial: partial, completion: word))
    guard commitOnReturn else { return }
    let editor = self
    DispatchQueue.main.async {
      guard editor.window?.firstResponder === editor else { return }
      editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
    }
  }

  private static func partialWord(in text: String, range: NSRange) -> String {
    let ns = text as NSString
    guard range.location != NSNotFound,
      range.length >= 0,
      NSMaxRange(range) <= ns.length
    else { return "" }
    return ns.substring(with: range)
  }
}

/// Writes the open cell or formula-bar edit into the workbook before Save.
enum SpreadsheetEditorFlush {
  @MainActor
  static func commitForSave() {
    let window = NSApp.keyWindow ?? NSApp.mainWindow
    let grid = window.flatMap { SpreadsheetGridNSView.first(in: $0.contentView) }
    if let window, window.firstResponder is FormulaBarNSTextView {
      if let grid {
        window.makeFirstResponder(grid)
      } else {
        window.makeFirstResponder(nil)
      }
    }
    if let grid {
      grid.commitEditingForSave()
    } else {
      SparkGridAppDelegate.current?.documentStore?.activeViewModel?
        .commitEditIfNeeded()
    }
  }
}
