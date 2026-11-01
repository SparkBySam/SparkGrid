import Formula
import Foundation
import GridCore
import Model
import NumberFormat

extension XLSXCodec {
  // MARK: - Import

  public static func importSheetImages(
    into sheet: inout Sheet,
    archiveData: Data,
    worksheetPath: String
  ) {
    let worksheetFile = (worksheetPath as NSString).lastPathComponent
    let worksheetDir = (worksheetPath as NSString).deletingLastPathComponent
    let relsPath = "\(worksheetDir)/_rels/\(worksheetFile).rels"
    guard let relsXML = zipEntryString(archiveData: archiveData, entryPath: relsPath),
      let drawingTarget = relationshipTarget(
        in: relsXML,
        relationshipType: "officeDocument/2006/relationships/drawing"
      )
    else { return }

    let drawingPath = resolveZipPath(basePath: worksheetPath, relativeTarget: drawingTarget)
    guard let drawingXML = zipEntryString(archiveData: archiveData, entryPath: drawingPath) else {
      return
    }

    let drawingName = (drawingPath as NSString).lastPathComponent
    let drawingRelsPath = "xl/drawings/_rels/\(drawingName).rels"
    let drawingRelsXML = zipEntryString(archiveData: archiveData, entryPath: drawingRelsPath) ?? ""

    sheet.images = parseDrawingImages(
      drawingXML: drawingXML,
      drawingRelsXML: drawingRelsXML,
      drawingPath: drawingPath,
      archiveData: archiveData
    )
  }

  private static func parseDrawingImages(
    drawingXML: String,
    drawingRelsXML: String,
    drawingPath: String,
    archiveData: Data
  ) -> [SheetImage] {
    let anchorPattern = #"<xdr:(?:oneCell|twoCell)Anchor[\s\S]*?</xdr:(?:oneCell|twoCell)Anchor>"#
    guard let regex = try? NSRegularExpression(pattern: anchorPattern, options: []) else {
      return []
    }
    let ns = drawingXML as NSString
    var images: [SheetImage] = []

    for match in regex.matches(
      in: drawingXML, options: [], range: NSRange(location: 0, length: ns.length))
    {
      let anchor = ns.substring(with: match.range)
      guard anchor.contains("<xdr:pic") || anchor.contains(":pic>") else { continue }
      guard let embedId = firstXMLAttribute(in: anchor, names: ["r:embed", "embed"]) else {
        continue
      }
      guard let mediaTarget = relationshipTarget(in: drawingRelsXML, relationshipId: embedId) else {
        continue
      }
      let mediaPath = resolveZipPath(basePath: drawingPath, relativeTarget: mediaTarget)
      guard let imageData = zipEntryData(archiveData: archiveData, entryPath: mediaPath) else {
        continue
      }

      let row =
        intXMLTagValue(in: anchor, tag: "xdr:row") ?? intXMLTagValue(in: anchor, tag: "row") ?? 0
      let col =
        intXMLTagValue(in: anchor, tag: "xdr:col") ?? intXMLTagValue(in: anchor, tag: "col") ?? 0
      let rowOff =
        intXMLTagValue(in: anchor, tag: "xdr:rowOff") ?? intXMLTagValue(in: anchor, tag: "rowOff")
        ?? 0
      let colOff =
        intXMLTagValue(in: anchor, tag: "xdr:colOff") ?? intXMLTagValue(in: anchor, tag: "colOff")
        ?? 0

      let (widthEMU, heightEMU): (Int, Int)
      if let cx = intXMLAttribute(in: anchor, name: "cx"),
        let cy = intXMLAttribute(in: anchor, name: "cy"),
        anchor.contains("<xdr:ext")
      {
        widthEMU = cx
        heightEMU = cy
      } else if let toRow = intXMLTagValue(in: anchor, tag: "xdr:row", occurrence: 2),
        let toCol = intXMLTagValue(in: anchor, tag: "xdr:col", occurrence: 2)
      {
        // twoCellAnchor without ext — approximate size from default cell dimensions.
        let colSpan = max(1, toCol - col)
        let rowSpan = max(1, toRow - row)
        widthEMU = Int(CGFloat(colSpan) * Workbook.defaultColumnWidth * SheetImage.emuPerPoint)
        heightEMU = Int(CGFloat(rowSpan) * Workbook.defaultRowHeight * SheetImage.emuPerPoint)
      } else {
        widthEMU = Int(Workbook.defaultColumnWidth * SheetImage.emuPerPoint)
        heightEMU = Int(Workbook.defaultRowHeight * SheetImage.emuPerPoint)
      }

      let ext = (mediaPath as NSString).pathExtension.lowercased()
      let contentType: String
      switch ext {
      case "jpg", "jpeg": contentType = "image/jpeg"
      case "gif": contentType = "image/gif"
      default: contentType = "image/png"
      }

      images.append(
        SheetImage(
          anchorRow: row,
          anchorCol: col,
          rowOffsetEMU: rowOff,
          colOffsetEMU: colOff,
          widthEMU: widthEMU,
          heightEMU: heightEMU,
          imageData: imageData,
          contentType: contentType
        )
      )
    }
    return images
  }

  // MARK: - Export helpers (used by XLSXCodec+Charts)

  public static func oneCellAnchorImageXML(image: SheetImage, relId: String, pictureId: Int)
    -> String
  {
    """
    <xdr:oneCellAnchor editAs="oneCell">
      <xdr:from>
        <xdr:col>\(image.anchorCol)</xdr:col><xdr:colOff>\(image.colOffsetEMU)</xdr:colOff>
        <xdr:row>\(image.anchorRow)</xdr:row><xdr:rowOff>\(image.rowOffsetEMU)</xdr:rowOff>
      </xdr:from>
      <xdr:ext cx="\(image.widthEMU)" cy="\(image.heightEMU)"/>
      <xdr:pic>
        <xdr:nvPicPr>
          <xdr:cNvPr id="\(pictureId)" name="Picture \(pictureId)"/>
          <xdr:cNvPicPr><a:picLocks noChangeAspect="1"/></xdr:cNvPicPr>
        </xdr:nvPicPr>
        <xdr:blipFill>
          <a:blip r:embed="\(relId)" cstate="print"/>
          <a:stretch><a:fillRect/></a:stretch>
        </xdr:blipFill>
        <xdr:spPr>
          <a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/></a:xfrm>
          <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
        </xdr:spPr>
      </xdr:pic>
      <xdr:clientData/>
    </xdr:oneCellAnchor>
    """
  }

  public static func imageContentTypeDefaults(workbook: Workbook) -> String {
    let hasPNG = workbook.sheets.contains { $0.images.contains { $0.contentType == "image/png" } }
    let hasJPEG = workbook.sheets.contains {
      $0.images.contains { $0.contentType == "image/jpeg" }
    }
    var defaults = ""
    if hasPNG {
      defaults += #"<Default Extension="png" ContentType="image/png"/>"#
    }
    if hasJPEG {
      defaults += #"<Default Extension="jpeg" ContentType="image/jpeg"/>"#
    }
    return defaults
  }

  public static func mediaFileName(for image: SheetImage, index: Int) -> String {
    switch image.contentType {
    case "image/jpeg": return "image\(index).jpeg"
    case "image/gif": return "image\(index).gif"
    default: return "image\(index).png"
    }
  }

  // MARK: - XML helpers

  public static func resolveZipPath(basePath: String, relativeTarget: String) -> String {
    let baseDir = (basePath as NSString).deletingLastPathComponent
    var parts = (baseDir as NSString).pathComponents
    for component in (relativeTarget as NSString).pathComponents {
      if component == ".." {
        if !parts.isEmpty { parts.removeLast() }
      } else if component != "." {
        parts.append(component)
      }
    }
    return parts.joined(separator: "/")
  }

  private static func relationshipTarget(
    in relsXML: String,
    relationshipType: String
  ) -> String? {
    let pattern =
      #"<Relationship\b[^>]*Type="[^"]*/\#(NSRegularExpression.escapedPattern(for: relationshipType))"[^>]*Target="([^"]+)""#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
    let ns = relsXML as NSString
    guard
      let match = regex.firstMatch(
        in: relsXML, options: [], range: NSRange(location: 0, length: ns.length))
    else { return nil }
    return ns.substring(with: match.range(at: 1))
  }

  private static func relationshipTarget(in relsXML: String, relationshipId: String) -> String? {
    let escaped = NSRegularExpression.escapedPattern(for: relationshipId)
    let pattern = #"<Relationship\b[^>]*Id="\#(escaped)"[^>]*Target="([^"]+)""#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
    let ns = relsXML as NSString
    guard
      let match = regex.firstMatch(
        in: relsXML, options: [], range: NSRange(location: 0, length: ns.length))
    else { return nil }
    return ns.substring(with: match.range(at: 1))
  }

  private static func intXMLTagValue(in xml: String, tag: String, occurrence: Int = 1) -> Int? {
    let pattern = "<\(tag)>([0-9]+)</\(tag)>"
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
    let ns = xml as NSString
    let matches = regex.matches(
      in: xml, options: [], range: NSRange(location: 0, length: ns.length))
    guard occurrence > 0, occurrence <= matches.count else { return nil }
    return Int(ns.substring(with: matches[occurrence - 1].range(at: 1)))
  }

  private static func intXMLAttribute(in xml: String, name: String) -> Int? {
    let escaped = NSRegularExpression.escapedPattern(for: name)
    let pattern = #"\#(escaped)="([0-9]+)""#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
    let ns = xml as NSString
    guard
      let match = regex.firstMatch(
        in: xml, options: [], range: NSRange(location: 0, length: ns.length))
    else { return nil }
    return Int(ns.substring(with: match.range(at: 1)))
  }

  private static func firstXMLAttribute(in xml: String, names: [String]) -> String? {
    for name in names {
      let escaped = NSRegularExpression.escapedPattern(for: name)
      let pattern = #"\#(escaped)="([^"]+)""#
      guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
      let ns = xml as NSString
      if let match = regex.firstMatch(
        in: xml, options: [], range: NSRange(location: 0, length: ns.length))
      {
        return ns.substring(with: match.range(at: 1))
      }
    }
    return nil
  }
}
