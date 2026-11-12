import GridCore
import Model
import XCTest

@testable import FileFormats

final class ExcelPivotReaderTests: XCTestCase {
  static let cacheXML = #"""
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <pivotCacheDefinition xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" r:id="rId1" refreshedBy="Sam" recordCount="5">
    <cacheSource type="worksheet"><worksheetSource ref="A1:D6" sheet="Sales Data"/></cacheSource>
    <cacheFields count="4">
    <cacheField name="Region" numFmtId="0"><sharedItems count="3"><s v="West"/><s v="East"/><s v="North"/></sharedItems></cacheField>
    <cacheField name="Rep" numFmtId="0"><sharedItems/></cacheField>
    <cacheField name="Product" numFmtId="0"><sharedItems count="2"><s v="Bike"/><s v="Helmet"/></sharedItems></cacheField>
    <cacheField name="Amount" numFmtId="0"><sharedItems containsSemiMixedTypes="0" containsString="0" containsNumber="1" containsInteger="1" minValue="5" maxValue="120"/></cacheField>
    </cacheFields></pivotCacheDefinition>
    """#

  static let pivotXML = #"""
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <pivotTableDefinition xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" name="PivotTable1" cacheId="3" applyNumberFormats="0" dataCaption="Values" updatedVersion="8">
    <location ref="A3:D7" firstHeaderRow="1" firstDataRow="2" firstDataCol="1"/>
    <pivotFields count="4">
    <pivotField axis="axisRow" showAll="0"><items count="4"><item x="1"/><item x="2" h="1"/><item x="0"/><item t="default"/></items></pivotField>
    <pivotField showAll="0"/>
    <pivotField axis="axisCol" showAll="0"><items count="3"><item x="0"/><item x="1"/><item t="default"/></items></pivotField>
    <pivotField dataField="1" showAll="0"/>
    </pivotFields>
    <rowFields count="1"><field x="0"/></rowFields>
    <rowItems count="3"><i><x/></i><i><x v="1"/></i><i t="grand"><x/></i></rowItems>
    <colFields count="1"><field x="2"/></colFields>
    <dataFields count="1"><dataField name="Sum of Amount" fld="3" baseField="0" baseItem="0"/></dataFields>
    </pivotTableDefinition>
    """#

  private func workbook() -> Workbook {
    Workbook(sheets: [Sheet(name: "Sales Data"), Sheet(name: "Pivot")])
  }

  func testReadsFieldsSourceAndHiddenItems() throws {
    let result = ExcelPivotReader.read(
      pivotXML: Data(Self.pivotXML.utf8), cacheDefinitionXML: Data(Self.cacheXML.utf8),
      workbook: workbook())
    let pivot = try result.get()
    XCTAssertEqual(pivot.name, "PivotTable1")
    XCTAssertEqual(pivot.location.a1Label, "A3:D7")
    XCTAssertEqual(pivot.sourceSheet, "Sales Data")
    XCTAssertEqual(pivot.sourceRange.a1Label, "A1:D6")
    XCTAssertEqual(pivot.definition.rows, [0])
    XCTAssertEqual(pivot.definition.columns, [2])
    XCTAssertEqual(pivot.definition.values, [.init(field: 3, aggregate: .sum)])
    XCTAssertEqual(pivot.definition.filters, [.init(field: 0, hidden: ["North"])])
  }

  func testPageFieldShowingOneItem() throws {
    let xml = Self.pivotXML.replacingOccurrences(
      of: "</dataFields>",
      with:
        #"</dataFields><pageFields count="1"><pageField fld="2" item="1" hier="-1"/></pageFields>"#)
    let pivot = try ExcelPivotReader.read(
      pivotXML: Data(xml.utf8), cacheDefinitionXML: Data(Self.cacheXML.utf8),
      workbook: workbook()
    ).get()
    XCTAssertTrue(pivot.definition.filters.contains(.init(field: 2, hidden: ["Bike"])))
  }

  func testUnsupportedFeaturesLeaveTheTableAlone() {
    func read(
      pivot: String = ExcelPivotReaderTests.pivotXML, cache: String = ExcelPivotReaderTests.cacheXML
    ) -> ExcelPivotReader.Unsupported? {
      if case .failure(let why) = ExcelPivotReader.read(
        pivotXML: Data(pivot.utf8), cacheDefinitionXML: Data(cache.utf8), workbook: workbook())
      {
        return why
      }
      return nil
    }
    XCTAssertEqual(
      read(
        pivot: Self.pivotXML.replacingOccurrences(
          of: #"baseItem="0""#, with: #"baseItem="0" showDataAs="percentOfTotal""#)),
      .summary("percentOfTotal"))
    XCTAssertEqual(
      read(
        pivot: Self.pivotXML.replacingOccurrences(
          of: #"fld="3""#, with: #"fld="3" subtotal="stdDev""#)),
      .summary("stdDev"))
    XCTAssertEqual(
      read(
        cache: Self.cacheXML.replacingOccurrences(
          of: #"<cacheField name="Rep" numFmtId="0">"#,
          with: #"<cacheField name="Rep" numFmtId="0" formula="Amount*2">"#)),
      .calculatedField)
    XCTAssertEqual(
      read(
        cache: Self.cacheXML.replacingOccurrences(
          of: #"sheet="Sales Data""#, with: #"sheet="Gone""#)),
      .noSource)
  }

  func testWritesWiderLocationAndRefreshOnLoad() {
    let widened = ExcelPivotReader.pivotXML(
      Data(Self.pivotXML.utf8),
      coveringAlso: CellRange(start: CellAddress(row: 2, col: 0), end: CellAddress(row: 9, col: 3)))
    XCTAssertTrue(String(decoding: widened, as: UTF8.self).contains(#"ref="A3:D10""#))
    let cache = String(
      decoding: ExcelPivotReader.cacheDefinitionXML(refreshingOnLoad: Data(Self.cacheXML.utf8)),
      as: UTF8.self)
    XCTAssertTrue(cache.contains(#"recordCount="5" refreshOnLoad="1">"#))
    let again = String(
      decoding: ExcelPivotReader.cacheDefinitionXML(refreshingOnLoad: Data(cache.utf8)),
      as: UTF8.self)
    XCTAssertEqual(again.components(separatedBy: "refreshOnLoad").count, 2)
  }

  func testSharedItemLabels() {
    XCTAssertEqual(ExcelPivotReader.dateSerial("2026-01-01T00:00:00"), 46023)
  }
}
