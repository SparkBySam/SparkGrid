import SparkGridCore
import SwiftUI

struct SpreadsheetPrintPagePreview: View {
  let content: SpreadsheetPrintPreviewContent

  @State private var currentPage = 1
  @State private var zoom: CGFloat = 1.0
  @State private var pinchAnchorZoom: CGFloat?
  @State private var scrollResetToken = 0

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

              if !content.pages.isEmpty {
                // Drawn at the size shown, so text and lines stay sharp at any zoom.
                SpreadsheetPrintPageCanvas(
                  content: content, page: min(max(1, currentPage), pageCount)
                )
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
    .onChange(of: content.renderToken) { _, _ in
      currentPage = 1
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

/// One page of the preview, drawn by the same view that prints it, scaled to the size it is
/// shown. A picture of the page went soft when zoomed in.
struct SpreadsheetPrintPageCanvas: NSViewRepresentable {
  let content: SpreadsheetPrintPreviewContent
  let page: Int

  func makeNSView(context: Context) -> CanvasView { CanvasView() }

  func updateNSView(_ view: CanvasView, context: Context) {
    if view.token != content.renderToken || view.page != page {
      view.content = content
      view.token = content.renderToken
      view.page = page
      view.needsDisplay = true
    }
  }

  final class CanvasView: NSView {
    var content: SpreadsheetPrintPreviewContent?
    var token = ""
    var page = 1

    override var isFlipped: Bool { true }

    override func setFrameSize(_ newSize: NSSize) {
      super.setFrameSize(newSize)
      needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
      NSColor.white.setFill()
      bounds.fill()
      guard let content, let book = SpreadsheetPrintSnapshotRenderer.bookView(for: content),
        book.bounds.width > 0, book.bounds.height > 0
      else { return }
      book.pageIndex = min(max(1, page), book.pageCount)
      NSGraphicsContext.saveGraphicsState()
      bounds.clip()
      let scale = NSAffineTransform()
      scale.scaleX(by: bounds.width / book.bounds.width, yBy: bounds.height / book.bounds.height)
      scale.concat()
      book.draw(book.bounds)
      NSGraphicsContext.restoreGraphicsState()
    }
  }
}
