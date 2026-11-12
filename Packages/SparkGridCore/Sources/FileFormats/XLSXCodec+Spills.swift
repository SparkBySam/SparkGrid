import Formula
import Foundation
import GridCore
import Model

/// Formulas such as FILTER, SORT and UNIQUE whose results fill the cells below and beside them.
/// Other spreadsheet apps save the formula with `<f t="array" ref="…">`, mark it as spilling
/// in `xl/metadata.xml`, and save each result as a plain value in its own cell.
extension XLSXCodec {
  /// Functions whose results spill, as saved formulas name them (with or without a prefix).
  static let spillingFunctionNames = ["FILTER(", "SORT(", "SORTBY(", "UNIQUE(", "SEQUENCE("]

  static func spills(_ raw: String) -> Bool {
    let upper = raw.uppercased()
    return spillingFunctionNames.contains { upper.contains($0) }
  }

  /// Turns the saved values inside each spilling formula's range into spilled results: shown,
  /// but with nothing typed, so the formula fills them again when it recalculates.
  static func adoptSpills(_ arrays: [CellAddress: CellRange], into sheet: inout Sheet) {
    guard !arrays.isEmpty else { return }
    for (anchor, range) in arrays.sorted(by: { ($0.key.row, $0.key.col) < ($1.key.row, $1.key.col) }
    )
    where spills(sheet.cell(at: anchor).raw) {
      let r = range.normalized
      // The formula is the range's top-left cell; anything else is not a spill.
      guard r.minRow == anchor.row, r.minCol == anchor.col else { continue }
      for address in range.allAddresses() where address != anchor {
        var cell = sheet.cell(at: address)
        guard !cell.raw.isEmpty, !FormulaSyntax.isFormula(cell.raw) else { continue }
        let stored = CellValue.fromLiteralRaw(cell.raw).importedCacheStorage
        cell.raw = ""
        cell.importedFormulaResult = stored.text
        cell.importedFormulaValueType = stored.type
        sheet.setCell(cell, at: address)
      }
      sheet.fileExtras.spills[anchor] = range
    }
  }

  static let sheetMetadataContentType =
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheetMetadata+xml"
  static let sheetMetadataRelationshipType =
    "http://schemas.openxmlformats.org/officeDocument/2006/relationships/sheetMetadata"

  /// `xl/metadata.xml` with the one entry spilling formulas point to with `cm="1"`.
  static let dynamicArrayMetadataXML = Data(
    """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <metadata xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" \
    xmlns:xda="http://schemas.microsoft.com/office/spreadsheetml/2017/dynamicarray">\
    <metadataTypes count="1"><metadataType name="XLDAPR" minSupportedVersion="120000" \
    copy="1" pasteAll="1" pasteValues="1" merge="1" splitFirst="1" rowColShift="1" \
    clearFormats="1" clearComments="1" assign="1" coerce="1" cellMeta="1"/></metadataTypes>\
    <futureMetadata name="XLDAPR" count="1"><bk><extLst>\
    <ext uri="{bdbb8cdc-fa1e-496e-a857-3c3f30c029c3}">\
    <xda:dynamicArrayProperties fDynamic="1" fCollapsed="0"/></ext></extLst></bk>\
    </futureMetadata><cellMetadata count="1"><bk><rc t="1" v="0"/></bk></cellMetadata>\
    </metadata>
    """.utf8)
}
