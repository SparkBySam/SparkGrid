import SparkGridCore
import SwiftUI

struct SpreadsheetPrintPagePreview: View {
  let content: SpreadsheetPrintPreviewContent

  @State private var currentPage = 1
  @State private var pageImage: NSImage?
  @State private var pageCache: [Int: NSImage] = [:]
  @State private var zoom: CGFloat = 1.0
  @State private var pinchAnchorZoom: CGFloat?
  @State private var isGenerating = false
  @State private var scrollResetToken = 0
  @State private var renderGeneration = 0

  private var pageCount: Int {
    max(1, SpreadsheetPrintSnapshotRenderer.estimatedPageCount(for: content))
  }

  var body: some View {
    GeometryReader { geometry in
      let fit = previewFitScale(in: geometry.size)
      let pageWidth = content.paperSize.width * fit * zoom
      let pageHeight = content.paperSize.height * fit * zoom

      ZStack {
        Color(nsColor: NSColor(calibratedWhite: 0.90, alpha: 1))

        ScrollViewReader { proxy in
          ScrollView([.horizontal, .vertical]) {
            VStack(spacing: 16) {
              Color.clear.frame(height: 0).id("preview-top")

              if isGenerating && pageImage == nil {
                VStack(spacing: 12) {
                  ProgressView()
                  Text("Generating preview…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .frame(width: 280, height: 360)
              } else if let pageImage {
                Image(nsImage: pageImage)
                  .interpolation(.high)
                  .resizable()
                  .frame(width: pageWidth, height: pageHeight)
                  .shadow(color: .black.opacity(0.20), radius: 12, x: 0, y: 4)
              }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 36)
            .padding(.horizontal, 28)
            .padding(.bottom, 72)
          }
          .simultaneousGesture(pinchZoomGesture)
          .onChange(of: scrollResetToken) { _, _ in
            withAnimation(.easeOut(duration: 0.2)) {
              proxy.scrollTo("preview-top", anchor: .top)
            }
          }
        }

        VStack {
          Spacer()
          HStack {
            if pageCount > 1 {
              pageNavigator
            }
            Spacer()
            zoomControls
          }
          .padding(16)
        }
      }
    }
    .overlay(alignment: .topLeading) {
      Text("Total: \(pageCount) \(pageCount == 1 ? "page" : "pages")")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Color.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.95), in: Capsule())
        .overlay {
          Capsule().stroke(Color.secondary.opacity(0.28), lineWidth: 1)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }
    .task(id: content.renderToken) {
      currentPage = 1
      pageCache = [:]
      pageImage = nil
      await renderCurrentPage()
    }
    .onChange(of: currentPage) { _, _ in
      Task { await renderCurrentPage() }
    }
  }

  private var pageNavigator: some View {
    HStack(spacing: 8) {
      Button {
        currentPage = max(1, currentPage - 1)
        scrollResetToken &+= 1
      } label: {
        Image(systemName: "chevron.left")
          .font(.system(size: 13, weight: .bold))
          .foregroundStyle(Color.primary)
          .frame(width: 32, height: 32)
          .background(Color(nsColor: .windowBackgroundColor).opacity(0.95), in: Circle())
          .overlay { Circle().stroke(Color.secondary.opacity(0.35), lineWidth: 1) }
      }
      .buttonStyle(.plain)
      .disabled(currentPage <= 1)
      .opacity(currentPage <= 1 ? 0.45 : 1)

      Text("Page \(currentPage) of \(pageCount)")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Color.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.95), in: Capsule())
        .overlay {
          Capsule().stroke(Color.secondary.opacity(0.28), lineWidth: 1)
        }

      Button {
        currentPage = min(pageCount, currentPage + 1)
        scrollResetToken &+= 1
      } label: {
        Image(systemName: "chevron.right")
          .font(.system(size: 13, weight: .bold))
          .foregroundStyle(Color.primary)
          .frame(width: 32, height: 32)
          .background(Color(nsColor: .windowBackgroundColor).opacity(0.95), in: Circle())
          .overlay { Circle().stroke(Color.secondary.opacity(0.35), lineWidth: 1) }
      }
      .buttonStyle(.plain)
      .disabled(currentPage >= pageCount)
      .opacity(currentPage >= pageCount ? 0.45 : 1)
    }
    .padding(10)
    .background(.ultraThinMaterial, in: Capsule())
  }

  private var zoomControls: some View {
    HStack(spacing: 6) {
      zoomButton(symbol: "minus") {
        zoom = max(0.4, zoom - 0.1)
      }
      Button {
        resetZoomAndRecenter()
      } label: {
        Text("\(Int((zoom * 100).rounded()))%")
          .font(.caption.monospacedDigit().weight(.bold))
          .foregroundStyle(Color.primary)
          .padding(.horizontal, 10)
          .padding(.vertical, 6)
          .background(Color(nsColor: .windowBackgroundColor).opacity(0.95), in: Capsule())
          .overlay {
            Capsule().stroke(Color.secondary.opacity(0.35), lineWidth: 1)
          }
      }
      .buttonStyle(.plain)
      .help("Reset zoom to 100% and recenter")
      zoomButton(symbol: "plus") {
        zoom = min(3.0, zoom + 0.1)
      }
    }
    .padding(12)
    .background(.ultraThinMaterial, in: Capsule())
  }

  @MainActor
  private func renderCurrentPage() async {
    let page = min(max(1, currentPage), pageCount)
    if page != currentPage {
      currentPage = page
    }

    if let cached = pageCache[page] {
      pageImage = cached
      isGenerating = false
      return
    }

    renderGeneration &+= 1
    let generation = renderGeneration
    let token = content.renderToken
    let snapshot = content
    let pageToRender = page

    isGenerating = pageImage == nil
    let image = SpreadsheetPrintSnapshotRenderer.renderPageImage(
      content: snapshot,
      pageIndex: pageToRender
    )
    guard generation == renderGeneration, token == snapshot.renderToken else { return }

    if let image {
      trimCacheIfNeeded()
      pageCache[pageToRender] = image
      pageImage = image
    }
    isGenerating = false

    // Prefetch neighbors so next/prev feels instant.
    prefetchNeighborPages(around: pageToRender, token: token, snapshot: snapshot)
  }

  @MainActor
  private func prefetchNeighborPages(
    around page: Int,
    token: String,
    snapshot: SpreadsheetPrintPreviewContent
  ) {
    let neighbors = [page - 1, page + 1].filter {
      $0 >= 1 && $0 <= pageCount && pageCache[$0] == nil
    }
    for neighbor in neighbors {
      let image = SpreadsheetPrintSnapshotRenderer.renderPageImage(
        content: snapshot,
        pageIndex: neighbor
      )
      guard token == content.renderToken else { return }
      if let image {
        pageCache[neighbor] = image
      }
    }
  }

  private func trimCacheIfNeeded() {
    // Keep a small window around the current page so flipping back feels instant.
    let keep = Set(
      [currentPage - 1, currentPage, currentPage + 1].filter { $0 >= 1 && $0 <= pageCount })
    pageCache = pageCache.filter { keep.contains($0.key) }
  }

  private func resetZoomAndRecenter() {
    zoom = 1.0
    pinchAnchorZoom = nil
    scrollResetToken &+= 1
  }

  private var pinchZoomGesture: some Gesture {
    MagnificationGesture()
      .onChanged { value in
        if pinchAnchorZoom == nil {
          pinchAnchorZoom = zoom
        }
        let next = (pinchAnchorZoom ?? 1.0) * value
        zoom = min(3.0, max(0.4, next))
      }
      .onEnded { _ in
        pinchAnchorZoom = nil
      }
  }

  private func previewFitScale(in size: CGSize) -> CGFloat {
    let padding: CGFloat = 56
    let availableWidth = max(size.width - padding, 120)
    let availableHeight = max(size.height - padding, 160)
    return min(
      availableWidth / content.paperSize.width,
      availableHeight / content.paperSize.height,
      1.0
    )
  }

  private func zoomButton(symbol: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(Color.primary)
        .frame(width: 32, height: 32)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.95), in: Circle())
        .overlay {
          Circle().stroke(Color.secondary.opacity(0.35), lineWidth: 1)
        }
    }
    .buttonStyle(.plain)
  }
}
