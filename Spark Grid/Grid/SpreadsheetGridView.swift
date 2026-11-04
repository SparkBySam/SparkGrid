import AppKit
import SparkGridCore
import SwiftUI

struct SpreadsheetGridView: NSViewRepresentable {
  var viewModel: SpreadsheetViewModel

  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeNSView(context: Context) -> SpreadsheetGridNSView {
    let view = SpreadsheetGridNSView()
    view.viewModel = viewModel
    context.coordinator.lastSheetKey = context.coordinator.sheetKey(for: viewModel)
    context.coordinator.lastStructureRevision = viewModel.structureRevision
    context.coordinator.lastGridRefreshToken = viewModel.gridRefreshToken
    context.coordinator.lastSelectionAnchor = viewModel.selectionAnchor
    context.coordinator.lastSelectionEnd = viewModel.selectionEnd
    context.coordinator.lastSelectionRevision = viewModel.selectionRevision
    context.coordinator.lastFormulaHighlightRevision = viewModel.formulaHighlightRevision
    context.coordinator.lastScrollRequestToken = viewModel.scrollRequestToken
    context.coordinator.lastChartScrollToken = viewModel.chartScrollToken
    context.coordinator.lastZoomScale = viewModel.zoomScale
    context.coordinator.scheduleInitialFocus(for: view)
    return view
  }

  func updateNSView(_ nsView: SpreadsheetGridNSView, context: Context) {
    if nsView.viewModel !== viewModel {
      nsView.viewModel = viewModel
    }
    let sheetKey = context.coordinator.sheetKey(for: viewModel)
    if sheetKey != context.coordinator.lastSheetKey {
      context.coordinator.lastSheetKey = sheetKey
      context.coordinator.lastStructureRevision = viewModel.structureRevision
      nsView.reloadForSheetChange(to: viewModel.activeSheet.id)
    } else if viewModel.structureRevision != context.coordinator.lastStructureRevision {
      context.coordinator.lastStructureRevision = viewModel.structureRevision
      context.coordinator.lastGridRefreshToken = viewModel.gridRefreshToken
      nsView.reloadContent(resetScrollPosition: false)
    } else if viewModel.gridRefreshToken != context.coordinator.lastGridRefreshToken
      || viewModel.zoomScale != context.coordinator.lastZoomScale
    {
      context.coordinator.lastGridRefreshToken = viewModel.gridRefreshToken
      context.coordinator.lastZoomScale = viewModel.zoomScale
      nsView.reloadContent(resetScrollPosition: false)
    } else if viewModel.selectionRevision != context.coordinator.lastSelectionRevision
      || viewModel.selectionAnchor != context.coordinator.lastSelectionAnchor
      || viewModel.selectionEnd != context.coordinator.lastSelectionEnd
    {
      context.coordinator.lastSelectionRevision = viewModel.selectionRevision
      context.coordinator.lastSelectionAnchor = viewModel.selectionAnchor
      context.coordinator.lastSelectionEnd = viewModel.selectionEnd
      context.coordinator.lastFormulaHighlightRevision = viewModel.formulaHighlightRevision
      nsView.refreshSelectionDisplay()
    } else if viewModel.formulaHighlightRevision != context.coordinator.lastFormulaHighlightRevision
    {
      context.coordinator.lastFormulaHighlightRevision = viewModel.formulaHighlightRevision
      nsView.refreshFormulaHighlights()
    }

    if viewModel.scrollRequestToken != context.coordinator.lastScrollRequestToken {
      context.coordinator.lastScrollRequestToken = viewModel.scrollRequestToken
      nsView.scrollSelectionIntoView()
    }

    if viewModel.chartScrollToken != context.coordinator.lastChartScrollToken {
      context.coordinator.lastChartScrollToken = viewModel.chartScrollToken
      if let id = viewModel.chartScrollID {
        nsView.scrollChartIntoView(id: id)
      } else if let id = viewModel.importedChartScrollID {
        nsView.scrollImportedChartIntoView(id: id)
      }
    }
    nsView.layoutOnSheetCharts()
  }

  final class Coordinator {
    var lastSheetKey = ""
    var lastStructureRevision = 0
    var lastGridRefreshToken = 0
    var lastSelectionRevision = 0
    var lastSelectionAnchor = CellAddress.origin
    var lastSelectionEnd = CellAddress.origin
    var lastFormulaHighlightRevision = 0
    var lastScrollRequestToken = 0
    var lastChartScrollToken = 0
    var lastZoomScale: CGFloat = 1
    private var didScheduleInitialFocus = false

    func scheduleInitialFocus(for gridView: SpreadsheetGridNSView) {
      guard !didScheduleInitialFocus else { return }
      didScheduleInitialFocus = true
      DispatchQueue.main.async {
        gridView.claimInitialFocusIfNeeded()
      }
    }

    func sheetKey(for viewModel: SpreadsheetViewModel) -> String {
      let sheet = viewModel.activeSheet
      return
        "\(viewModel.workbook.activeSheetIndex)-\(sheet.id.uuidString)-\(sheet.effectiveRowCount)-\(sheet.effectiveColumnCount)-\(sheet.frozenRows)-\(sheet.frozenColumns)"
    }
  }
}
