import Formula
import Foundation
import GridCore
import Model
import NumberFormat

extension XLSXCodec {
  /// Writes Excel-readable drawing parts for a sheet's charts and embedded images.
  /// Also keeps the Spark JSON sidecar for faithful round-trip of our chart model.
  public static func appendSheetDrawingParts(
    for sheet: Sheet,
    sheetIndex: Int,
    globalImageIndex: inout Int,
    into files: inout [String: Data]
  ) -> Bool {
    guard hasDrawing(sheet) else { return false }

    let sheetNum = sheetIndex + 1
    var drawingBody = ""
    var drawingRels = ""
    var relId = 1
    // Each object in a drawing needs its own `cNvPr` id; repeats are a file error.
    var objectID = 1

    for (chartIndex, chart) in sheet.charts.enumerated() {
      let chartNum = sheetIndex * 100 + chartIndex + 1
      files["xl/charts/chart\(chartNum).xml"] = Data(
        excelChartXML(chart, sheetName: sheet.name).utf8)
      objectID += 1
      drawingBody += twoCellAnchorXML(chart: chart, chartRelId: "rId\(relId)", objectID: objectID)
      drawingRels += """
        <Relationship Id="rId\(relId)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/chart" Target="../charts/chart\(chartNum).xml"/>
        """
      relId += 1
    }

    for image in sheet.images {
      globalImageIndex += 1
      let mediaName = mediaFileName(for: image, index: globalImageIndex)
      files["xl/media/\(mediaName)"] = image.imageData
      objectID += 1
      drawingBody += oneCellAnchorImageXML(
        image: image, relId: "rId\(relId)", pictureId: objectID)
      drawingRels += """
        <Relationship Id="rId\(relId)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/\(mediaName)"/>
        """
      relId += 1
    }

    for (index, chart) in sheet.fileExtras.foreignCharts.enumerated() {
      let name = keptChartFileName(sheetNumber: sheetNum, index: index)
      files["xl/charts/\(name)"] = chart.chartXML
      objectID += 1
      drawingBody += DrawingAnchorXML.withObjectID(
        foreignChartAnchorXML(chart, relationshipID: "rId\(relId)"), objectID)
      drawingRels += """
        <Relationship Id="rId\(relId)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/chart" Target="../charts/\(name)"/>
        """
      relId += 1
    }

    files["xl/drawings/drawing\(sheetNum).xml"] = Data(drawingXML(body: drawingBody).utf8)
    files["xl/drawings/_rels/drawing\(sheetNum).xml.rels"] = Data(
      """
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      \(drawingRels)
      </Relationships>
      """.utf8)
    return true
  }

  public static func sheetDrawingRelationshipXML(sheetIndex: Int) -> String {
    #"<drawing r:id="rId1"/>"#
  }

  public static func hasDrawing(_ sheet: Sheet) -> Bool {
    !sheet.charts.isEmpty || !sheet.images.isEmpty || !sheet.fileExtras.foreignCharts.isEmpty
  }

  static func keptChartFileName(sheetNumber: Int, index: Int) -> String {
    "chart\(sheetNumber)k\(index + 1).xml"
  }

  public static func drawingContentTypeOverrides(workbook: Workbook) -> String {
    var overrides = ""
    for (sheetIndex, sheet) in workbook.sheets.enumerated() {
      guard hasDrawing(sheet) else { continue }
      let sheetNum = sheetIndex + 1
      overrides += """
        <Override PartName="/xl/drawings/drawing\(sheetNum).xml" ContentType="application/vnd.openxmlformats-officedocument.drawing+xml"/>
        """
      for (chartIndex, _) in sheet.charts.enumerated() {
        let chartNum = sheetIndex * 100 + chartIndex + 1
        overrides += """
          <Override PartName="/xl/charts/chart\(chartNum).xml" ContentType="application/vnd.openxmlformats-officedocument.drawingml.chart+xml"/>
          """
      }
      for index in sheet.fileExtras.foreignCharts.indices {
        let name = keptChartFileName(sheetNumber: sheetNum, index: index)
        overrides += """
          <Override PartName="/xl/charts/\(name)" ContentType="application/vnd.openxmlformats-officedocument.drawingml.chart+xml"/>
          """
      }
    }
    return overrides
  }

  // MARK: - Chart XML builders

  private static func drawingXML(body: String) -> String {
    """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <xdr:wsDr xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
    \(body)
    </xdr:wsDr>
    """
  }

  private static func twoCellAnchorXML(chart: SheetChart, chartRelId: String, objectID: Int)
    -> String
  {
    let endRow = chart.anchorRow + chart.rowSpan
    let endCol = chart.anchorCol + chart.colSpan
    let fromCol = SheetImage.emu(fromPoints: chart.originXOffset)
    let fromRow = SheetImage.emu(fromPoints: chart.originYOffset)
    let toCol = SheetImage.emu(fromPoints: chart.endXOffset)
    let toRow = SheetImage.emu(fromPoints: chart.endYOffset)
    return """
      <xdr:twoCellAnchor>
        <xdr:from><xdr:col>\(chart.anchorCol)</xdr:col><xdr:colOff>\(fromCol)</xdr:colOff><xdr:row>\(chart.anchorRow)</xdr:row><xdr:rowOff>\(fromRow)</xdr:rowOff></xdr:from>
        <xdr:to><xdr:col>\(endCol)</xdr:col><xdr:colOff>\(toCol)</xdr:colOff><xdr:row>\(endRow)</xdr:row><xdr:rowOff>\(toRow)</xdr:rowOff></xdr:to>
        <xdr:graphicFrame macro="">
          <xdr:nvGraphicFramePr>
            <xdr:cNvPr id="\(objectID)" name="\(escapeXML(chart.title))"/>
            <xdr:cNvGraphicFramePr><a:graphicFrameLocks noGrp="1"/></xdr:cNvGraphicFramePr>
          </xdr:nvGraphicFramePr>
          <xdr:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/></xdr:xfrm>
          <a:graphic>
            <a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/chart">
              <c:chart xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" r:id="\(chartRelId)"/>
            </a:graphicData>
          </a:graphic>
        </xdr:graphicFrame>
        <xdr:clientData/>
      </xdr:twoCellAnchor>
      """
  }

  private static func excelChartXML(_ chart: SheetChart, sheetName: String) -> String {
    let n = chart.dataRange.normalized
    let safeSheet = sheetName.replacingOccurrences(of: "'", with: "''")
    let hasHeader = chart.hasHeaderRow && n.maxRow > n.minRow
    let dataStartRow = hasHeader ? n.minRow + 1 : n.minRow
    let catCol = chart.categoryColumn ?? n.minCol
    let valCol = chart.valueColumn ?? min(n.maxCol, n.minCol + (n.minCol == n.maxCol ? 0 : 1))
    let catStart = CellAddress(row: dataStartRow, col: catCol).a1
    let catEnd = CellAddress(row: n.maxRow, col: catCol).a1
    let valStart = CellAddress(row: dataStartRow, col: valCol).a1
    let valEnd = CellAddress(row: n.maxRow, col: valCol).a1
    let catRef = "'\(safeSheet)'!\(catStart):\(catEnd)"
    let valRef = "'\(safeSheet)'!\(valStart):\(valEnd)"

    // Count mode is Spark-native; Excel export still points at the category column
    // as both cats and a placeholder val ref so the part remains valid.
    let exportValRef = chart.valueMode == .count ? catRef : valRef

    var seriesBody = seriesXML(chart, catRef: catRef, valRef: exportValRef)
    // More series read the same rows from their own columns and take their header as a name.
    if chart.valueMode == .values, chart.kind.allowsMoreSeries {
      for (offset, column) in chart.extraValueColumns.enumerated() {
        let ref =
          "'\(safeSheet)'!\(CellAddress(row: dataStartRow, col: column).a1):\(CellAddress(row: n.maxRow, col: column).a1)"
        let nameRef =
          hasHeader ? "'\(safeSheet)'!\(CellAddress(row: n.minRow, col: column).a1)" : nil
        seriesBody += extraSeriesXML(
          chart, index: offset + 1, catRef: catRef, valRef: ref, nameRef: nameRef)
      }
    }
    let seriesInner: String
    var axes = """
      \(axisXML(tag: "c:catAx", id: "1", position: "b", cross: "2", title: chart.categoryAxisTitle, gridlines: chart.showsGridlines))
      \(axisXML(tag: "c:valAx", id: "2", position: "l", cross: "1", title: chart.valueAxisTitle, gridlines: chart.showsGridlines))
      """
    switch chart.kind {
    case .bar:
      seriesInner = """
        <c:barChart>
          <c:barDir val="col"/>
          <c:grouping val="clustered"/>
          \(seriesBody)
          <c:axId val="1"/><c:axId val="2"/>
        </c:barChart>
        """
    case .line:
      seriesInner = """
        <c:lineChart>
          <c:grouping val="standard"/>
          \(seriesBody)
          <c:axId val="1"/><c:axId val="2"/>
        </c:lineChart>
        """
    case .area:
      seriesInner = """
        <c:areaChart>
          <c:grouping val="standard"/>
          \(seriesBody)
          <c:axId val="1"/><c:axId val="2"/>
        </c:areaChart>
        """
    case .pie:
      seriesInner = """
        <c:pieChart>
          <c:varyColors val="1"/>
          \(seriesBody)
          <c:firstSliceAng val="0"/>
        </c:pieChart>
        """
      axes = ""
    case .scatter:
      seriesInner = """
        <c:scatterChart>
          <c:scatterStyle val="lineMarker"/>
          <c:varyColors val="0"/>
          \(seriesBody)
          <c:axId val="1"/><c:axId val="2"/>
        </c:scatterChart>
        """
      axes = """
        \(axisXML(tag: "c:valAx", id: "1", position: "b", cross: "2", title: chart.categoryAxisTitle, gridlines: chart.showsGridlines))
        \(axisXML(tag: "c:valAx", id: "2", position: "l", cross: "1", title: chart.valueAxisTitle, gridlines: chart.showsGridlines))
        """
    }

    return """
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <c:chartSpace xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <c:chart>
          \(titleXML(chart))
          <c:plotArea>
            <c:layout/>
            \(seriesInner)
            \(axes)
          </c:plotArea>
          \(legendXML(chart))
        </c:chart>
      </c:chartSpace>
      """
  }

  private static func seriesXML(_ chart: SheetChart, catRef: String, valRef: String) -> String {
    let seriesName = chart.title.trimmingCharacters(in: .whitespacesAndNewlines)
    let name = seriesName.isEmpty ? chart.kind.title : seriesName
    let color = chart.seriesColor ?? SheetChart.defaultSeriesColor(for: chart.kind)
    let fill = solidFillXML(color)
    let shape: String
    switch chart.kind {
    case .line:
      shape = """
        <c:spPr><a:ln w="19050">\(fill)</a:ln></c:spPr>
        <c:marker><c:symbol val="circle"/><c:size val="5"/><c:spPr>\(fill)</c:spPr></c:marker>
        """
    case .bar, .area, .pie:
      shape = "<c:spPr>\(fill)</c:spPr>"
    case .scatter:
      shape = scatterShapeXML(fill)
    }
    let points = chart.pointColors.keys.sorted().compactMap { index -> String? in
      guard let point = chart.pointColors[index] else { return nil }
      let pointFill = solidFillXML(point)
      return """
        <c:dPt><c:idx val="\(index)"/>\(pointShapeXML(pointFill, kind: chart.kind))</c:dPt>
        """
    }.joined()
    return """
      <c:ser>
        <c:idx val="0"/><c:order val="0"/>
        <c:tx><c:v>\(escapeXML(name))</c:v></c:tx>
        \(shape)
        \(points)
        \(pointsXML(chart.kind, catRef: catRef, valRef: valRef))
      </c:ser>
      """
  }

  /// A further series in its own color from the palette, named by its header cell.
  private static func extraSeriesXML(
    _ chart: SheetChart, index: Int, catRef: String, valRef: String, nameRef: String?
  ) -> String {
    let color = seriesPalette[index % seriesPalette.count]
    let fill = solidFillXML(color)
    let name =
      nameRef.map { "<c:tx><c:strRef><c:f>\(escapeXML($0))</c:f></c:strRef></c:tx>" }
      ?? "<c:tx><c:v>Series \(index + 1)</c:v></c:tx>"
    let shape: String
    switch chart.kind {
    case .line:
      shape = """
        <c:spPr><a:ln w="19050">\(fill)</a:ln></c:spPr>
        <c:marker><c:symbol val="circle"/><c:size val="5"/><c:spPr>\(fill)</c:spPr></c:marker>
        """
    case .scatter:
      shape = scatterShapeXML(fill)
    case .bar, .area, .pie:
      shape = "<c:spPr>\(fill)</c:spPr>"
    }
    return """
      <c:ser>
        <c:idx val="\(index)"/><c:order val="\(index)"/>
        \(name)
        \(shape)
        \(pointsXML(chart.kind, catRef: catRef, valRef: valRef))
      </c:ser>
      """
  }

  /// Category and value references; a scatter chart's are its X and Y numbers.
  private static func pointsXML(_ kind: SheetChart.Kind, catRef: String, valRef: String) -> String {
    if kind == .scatter {
      return """
        <c:xVal><c:numRef><c:f>\(escapeXML(catRef))</c:f></c:numRef></c:xVal>
        <c:yVal><c:numRef><c:f>\(escapeXML(valRef))</c:f></c:numRef></c:yVal>
        <c:smooth val="0"/>
        """
    }
    return """
      <c:cat><c:strRef><c:f>\(escapeXML(catRef))</c:f></c:strRef></c:cat>
      <c:val><c:numRef><c:f>\(escapeXML(valRef))</c:f></c:numRef></c:val>
      """
  }

  /// Markers only: a scatter chart from Spark Grid plots points, not a connecting line.
  private static func scatterShapeXML(_ fill: String) -> String {
    """
    <c:spPr><a:ln><a:noFill/></a:ln></c:spPr>
    <c:marker><c:symbol val="circle"/><c:size val="6"/><c:spPr>\(fill)</c:spPr></c:marker>
    """
  }

  /// Colors for series after the first, which uses the chart's own series color.
  static let seriesPalette: [CodableColor] = [
    CodableColor(red: 0.18, green: 0.45, blue: 0.86, alpha: 1),
    CodableColor(red: 0.93, green: 0.49, blue: 0.19, alpha: 1),
    CodableColor(red: 0.44, green: 0.68, blue: 0.28, alpha: 1),
    CodableColor(red: 1.0, green: 0.75, blue: 0.0, alpha: 1),
    CodableColor(red: 0.6, green: 0.4, blue: 0.75, alpha: 1),
    CodableColor(red: 0.36, green: 0.61, blue: 0.84, alpha: 1),
  ]

  private static func pointShapeXML(_ fill: String, kind: SheetChart.Kind) -> String {
    switch kind {
    case .line:
      return
        "<c:marker><c:symbol val=\"circle\"/><c:spPr>\(fill)</c:spPr></c:marker><c:spPr><a:ln>\(fill)</a:ln></c:spPr>"
    case .bar, .area, .pie:
      return "<c:spPr>\(fill)</c:spPr>"
    case .scatter:
      return "<c:marker><c:symbol val=\"circle\"/><c:spPr>\(fill)</c:spPr></c:marker>"
    }
  }

  private static func solidFillXML(_ color: CodableColor) -> String {
    "<a:solidFill><a:srgbClr val=\"\(rgbHex(color))\"/></a:solidFill>"
  }

  private static func titleXML(_ chart: SheetChart) -> String {
    let title = chart.title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else { return #"<c:autoTitleDeleted val="1"/>"# }
    return """
      <c:title>
        <c:tx><c:rich><a:bodyPr/><a:lstStyle/><a:p><a:pPr><a:defRPr/></a:pPr><a:r><a:t>\(escapeXML(title))</a:t></a:r></a:p></c:rich></c:tx>
        <c:overlay val="0"/>
      </c:title>
      <c:autoTitleDeleted val="0"/>
      """
  }

  private static func legendXML(_ chart: SheetChart) -> String {
    if chart.showsLegend {
      return #"<c:legend><c:legendPos val="b"/><c:overlay val="0"/></c:legend>"#
    }
    return #"<c:legend><c:delete val="1"/></c:legend>"#
  }

  private static func axisXML(
    tag: String,
    id: String,
    position: String,
    cross: String,
    title: String,
    gridlines: Bool
  ) -> String {
    let grid = gridlines ? "<c:majorGridlines/>" : ""
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let titleXML =
      trimmed.isEmpty
      ? ""
      : """
      <c:title>
        <c:tx><c:rich><a:bodyPr/><a:lstStyle/><a:p><a:pPr><a:defRPr/></a:pPr><a:r><a:t>\(escapeXML(trimmed))</a:t></a:r></a:p></c:rich></c:tx>
        <c:overlay val="0"/>
      </c:title>
      """
    return """
      <\(tag)>
        <c:axId val="\(id)"/>
        <c:scaling><c:orientation val="minMax"/></c:scaling>
        <c:axPos val="\(position)"/>
        \(grid)
        \(titleXML)
        <c:crossAx val="\(cross)"/>
      </\(tag)>
      """
  }
}
