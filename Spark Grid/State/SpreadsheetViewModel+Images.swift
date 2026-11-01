import AppKit
import Foundation
import SparkGridCore

extension SpreadsheetViewModel {
  func insertImageFromFile(url: URL) {
    guard let data = try? Data(contentsOf: url) else { return }
    let contentType = Self.contentType(forPathExtension: url.pathExtension)
    insertImage(data: data, contentType: contentType)
  }

  @discardableResult
  func pasteImageFromPasteboard() -> Bool {
    let pasteboard = NSPasteboard.general
    if let png = pasteboard.data(forType: .png) {
      insertImage(data: png, contentType: "image/png")
      return true
    }
    if let jpeg = pasteboard.data(forType: NSPasteboard.PasteboardType("public.jpeg")) {
      insertImage(data: jpeg, contentType: "image/jpeg")
      return true
    }
    if let tiff = pasteboard.data(forType: .tiff),
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:])
    {
      insertImage(data: png, contentType: "image/png")
      return true
    }
    return false
  }

  func insertImage(data: Data, contentType: String, at anchor: CellAddress? = nil) {
    commitEditIfNeeded()
    let placement = anchor ?? selectionAnchor
    let (widthEMU, heightEMU) = Self.defaultImageEMUSize(for: data)
    let image = SheetImage(
      anchorRow: placement.row,
      anchorCol: placement.col,
      widthEMU: widthEMU,
      heightEMU: heightEMU,
      imageData: data,
      contentType: contentType
    )
    var sheet = activeSheet
    let before = sheet.images
    sheet.images.append(image)
    applyImages(sheet.images, undoBefore: before, actionName: "Insert Picture")
    selectedImageID = image.id
  }

  private static func defaultImageEMUSize(for data: Data) -> (Int, Int) {
    let defaultWidth = Workbook.defaultColumnWidth * 4
    let defaultHeight = Workbook.defaultRowHeight * 3
    guard let image = NSImage(data: data), image.size.width > 1, image.size.height > 1 else {
      return (
        SheetImage.emu(fromPoints: defaultWidth),
        SheetImage.emu(fromPoints: defaultHeight)
      )
    }
    let aspect = image.size.height / image.size.width
    let width = defaultWidth
    let height = max(Workbook.defaultRowHeight, width * aspect)
    return (SheetImage.emu(fromPoints: width), SheetImage.emu(fromPoints: height))
  }

  private static func contentType(forPathExtension ext: String) -> String {
    switch ext.lowercased() {
    case "jpg", "jpeg": return "image/jpeg"
    case "gif": return "image/gif"
    default: return "image/png"
    }
  }

  func selectImage(id: UUID?, bringToFront: Bool = false) {
    let clearedChart = id != nil && selectedChartID != nil
    if id != nil { selectedChartID = nil }
    if let id, bringToFront {
      reorderImage(id: id, toFront: true, recordUndo: false)
    }
    guard selectedImageID != id else {
      if clearedChart { notifyGridRefresh() }
      return
    }
    selectedImageID = id
    notifyGridRefresh()
  }

  func bringSelectedImageToFront() {
    guard let id = selectedImageID else { return }
    reorderImage(id: id, toFront: true, recordUndo: true, actionName: "Bring Picture to Front")
  }

  func sendSelectedImageToBack() {
    guard let id = selectedImageID else { return }
    reorderImage(id: id, toFront: false, recordUndo: true, actionName: "Send Picture to Back")
  }

  private func reorderImage(
    id: UUID, toFront: Bool, recordUndo: Bool, actionName: String = "Reorder Picture"
  ) {
    var sheet = activeSheet
    guard let index = sheet.images.firstIndex(where: { $0.id == id }) else { return }
    let before = sheet.images
    let image = sheet.images.remove(at: index)
    if toFront {
      sheet.images.append(image)
    } else {
      sheet.images.insert(image, at: 0)
    }
    if recordUndo {
      applyImages(sheet.images, undoBefore: before, actionName: actionName)
    } else {
      setActiveSheetPreservingFormulas(sheet)
      notifyGridRefresh()
    }
  }

  func image(with id: UUID) -> SheetImage? {
    activeSheet.images.first { $0.id == id }
  }

  /// Updates placement during a drag (no undo). Call `commitImagePlacement` on mouse up.
  func setImagePlacement(
    id: UUID,
    anchorRow: Int,
    anchorCol: Int,
    rowOffsetEMU: Int,
    colOffsetEMU: Int,
    widthEMU: Int? = nil,
    heightEMU: Int? = nil
  ) {
    guard let index = activeSheet.images.firstIndex(where: { $0.id == id }) else { return }
    var sheet = activeSheet
    sheet.images[index].anchorRow = max(0, anchorRow)
    sheet.images[index].anchorCol = max(0, anchorCol)
    sheet.images[index].rowOffsetEMU = max(0, rowOffsetEMU)
    sheet.images[index].colOffsetEMU = max(0, colOffsetEMU)
    if let widthEMU { sheet.images[index].widthEMU = max(SheetImage.emu(fromPoints: 12), widthEMU) }
    if let heightEMU {
      sheet.images[index].heightEMU = max(SheetImage.emu(fromPoints: 12), heightEMU)
    }
    setActiveSheetPreservingFormulas(sheet)
    notifyGridRefresh()
  }

  func commitImagePlacement(
    id: UUID,
    before: SheetImage,
    actionName: String = "Move Picture"
  ) {
    guard let after = image(with: id), before != after else { return }
    let undoBefore = replaceImage(before, in: activeSheet.images)
    applyImages(activeSheet.images, undoBefore: undoBefore, actionName: actionName)
  }

  func deleteSelectedImage() {
    guard let id = selectedImageID else { return }
    deleteImage(id: id)
  }

  @discardableResult
  func copySelectedImageToPasteboard() -> Bool {
    guard let id = selectedImageID, let image = image(with: id) else { return false }
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    let type = NSPasteboard.PasteboardType(image.contentType)
    return pasteboard.setData(image.imageData, forType: type)
  }

  func cutSelectedImage() {
    guard copySelectedImageToPasteboard() else { return }
    deleteSelectedImage()
  }

  func deleteImage(id: UUID) {
    commitEditIfNeeded()
    let before = activeSheet.images
    var sheet = activeSheet
    sheet.images.removeAll { $0.id == id }
    if selectedImageID == id { selectedImageID = nil }
    setActiveSheetPreservingFormulas(sheet)
    undoManager?.registerUndo(withTarget: self) { target in
      target.applyImages(before, undoBefore: sheet.images, actionName: "Delete Picture")
    }
    undoManager?.setActionName("Delete Picture")
    notifyGridRefresh()
  }

  private func replaceImage(_ image: SheetImage, in images: [SheetImage]) -> [SheetImage] {
    guard let index = images.firstIndex(where: { $0.id == image.id }) else { return images }
    var next = images
    next[index] = image
    return next
  }

  private func applyImages(_ images: [SheetImage], undoBefore: [SheetImage], actionName: String) {
    var sheet = activeSheet
    sheet.images = images
    setActiveSheetPreservingFormulas(sheet)
    undoManager?.registerUndo(withTarget: self) { target in
      target.applyImages(undoBefore, undoBefore: images, actionName: actionName)
    }
    undoManager?.setActionName(actionName)
    notifyGridRefresh()
  }
}
