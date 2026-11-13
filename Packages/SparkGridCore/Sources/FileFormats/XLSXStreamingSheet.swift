import CoreGraphics
import Formula
import Foundation
import GridCore
import Model
import NumberFormat
import ZIPFoundation

/// One forward scan of a worksheet's raw bytes. No `String.range` and no regular expressions.
public nonisolated enum StreamingWorksheet {
  /// One parse of the shared master, then a shift per follower. `FormulaRewriter.adjust`
  /// parses the same master again for every cell that uses it.
  static func expandedSharedFormula(
    master: String,
    si: Int,
    rowDelta: Int,
    colDelta: Int,
    parsedMasters: inout [Int: FormulaExpr]
  ) -> String {
    let base = master.hasPrefix("=") ? master : "=\(master)"
    if rowDelta == 0, colDelta == 0 { return base }
    if parsedMasters[si] == nil {
      parsedMasters[si] = try? FormulaParser.parse(base)
    }
    if let expr = parsedMasters[si] {
      let shifted = FormulaRewriter.adjustExpression(
        expr, rowDelta: rowDelta, colDelta: colDelta)
      return "=" + FormulaRewriter.serialize(shifted)
    }
    return FormulaRewriter.adjust(base, rowDelta: rowDelta, colDelta: colDelta)
  }

  /// Hidden or grouped `<col>` spans are kept up to this column (the format's last).
  static let maxKeptColumn = 16_384

  /// Elements kept as written. `sheetPr` holds the tab color; the rest follow `sheetData`.
  static let keptElementNames: [StaticString] = [
    "sheetPr", "sheetProtection", "dataValidations", "hyperlinks", "printOptions", "pageMargins",
    "pageSetup", "headerFooter", "rowBreaks", "colBreaks", "drawing", "legacyDrawing", "tableParts",
  ]

  /// Fills `sheet` and returns the conditional formatting XML and the kept elements.
  public static func fill(
    _ sheet: inout Sheet,
    data: Data,
    sharedTexts: [String?],
    formats: [CellFormat?]
  ) -> (
    conditionalFormatting: String, kept: [String: [String]], arrays: [CellAddress: CellRange]
  ) {
    data.withUnsafeBytes { rawBuffer in
      let raw = rawBuffer.bindMemory(to: UInt8.self)
      guard let base = raw.baseAddress, raw.count > 0 else { return ("", [:], [:]) }
      var scanner = Scanner(
        bytes: base,
        count: raw.count,
        sharedTexts: sharedTexts,
        formats: formats
      )
      let conditionalFormatting = scanner.parse(into: &sheet)
      var kept: [String: [String]] = [:]
      for (name, xml) in scanner.keptElements {
        kept[name.description, default: []].append(xml)
      }
      return (conditionalFormatting, kept, scanner.arrayRefs)
    }
  }

  private struct Master {
    public var row: Int
    public var col: Int
    public var formula: String
  }

  private struct Follower {
    public var address: CellAddress
    public var si: Int
    public var cacheText: String?
    public var cacheType: ImportedFormulaValueType?
  }

  private struct Tag {
    public var start: Int
    public var end: Int
    public var localStart: Int
    public var localLen: Int
    public var isClose: Bool
    public var isSelfClose: Bool
    public var attrStart: Int
    public var attrEnd: Int
  }

  private struct Scanner {
    public let bytes: UnsafePointer<UInt8>
    public let count: Int
    public let sharedTexts: [String?]
    public let formats: [CellFormat?]
    public var index: Int = 0
    var styleKeepsFormat: [Bool] = []
    /// Worksheet elements the app keeps for the next save, by local name, as written.
    var keptElements: [(name: StaticString, xml: String)] = []
    /// Array formulas and the cells their results fill, as `<f t="array" ref="…">` gives them.
    var arrayRefs: [CellAddress: CellRange] = [:]

    /// Names of unprefixed worksheet elements kept for the next save.
    func keptElementName(_ tag: Tag) -> StaticString? {
      // Every kept name is 7 to 15 letters; `<v>`, `<f>` and `<t>` stop here.
      guard tag.localLen >= 7, tag.localLen <= 15 else { return nil }
      for name in StreamingWorksheet.keptElementNames where localIs(tag, name) {
        return name
      }
      return nil
    }

    public mutating func parse(into sheet: inout Sheet) -> String {
      if count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF {
        index = 3
      }

      var cells: [CellAddress: Cell] = [:]
      cells.reserveCapacity(max(1024, count / 48))
      var masters: [Int: Master] = [:]
      var followers: [Follower] = []
      var conditionalFormatting: [String] = []
      var capturedFilter = false
      var sheetViews = 0
      var inFirstSheetView = false
      var tookPane = false
      keptElements = []
      var styleKeepsFormat = [Bool](repeating: false, count: formats.count)
      for index in formats.indices {
        if let format = formats[index], format != CellFormat() {
          styleKeepsFormat[index] = true
        }
      }
      self.styleKeepsFormat = styleKeepsFormat

      while index < count {
        let before = index
        seekTag()
        if index >= count { break }
        if consumeCellFast(into: &cells, masters: &masters, followers: &followers) {
          continue
        }
        let tag = readTag(at: index)
        if tag.localLen == 0 {
          index = max(tag.end, index + 1)
          continue
        }

        if localIs(tag, "conditionalFormatting"), !tag.isClose {
          conditionalFormatting.append(captureElement(tag, name: "conditionalFormatting"))
          continue
        }
        if localIs(tag, "autoFilter"), !tag.isClose {
          if capturedFilter {
            _ = captureElement(tag, name: "autoFilter")
          } else {
            sheet.autoFilter = parseAutoFilter(tag)
            capturedFilter = true
          }
          continue
        }
        if localIs(tag, "sheetView"), !tag.isClose {
          sheetViews += 1
          inFirstSheetView = sheetViews == 1
          index = tag.end
          if tag.isSelfClose { inFirstSheetView = false }
          continue
        }
        if localIs(tag, "sheetView"), tag.isClose {
          inFirstSheetView = false
          index = tag.end
          continue
        }
        if inFirstSheetView, !tookPane, localIs(tag, "pane"), !tag.isClose {
          applyPane(tag, to: &sheet)
          tookPane = true
          index = tag.end
          continue
        }
        if localIs(tag, "col"), !tag.isClose {
          applyColumn(tag, to: &sheet)
          index = tag.end
          continue
        }
        if localIs(tag, "row"), !tag.isClose {
          applyRow(tag, to: &sheet)
          index = tag.end
          continue
        }
        if localIs(tag, "mergeCell"), !tag.isClose {
          if let ref = attribute(tag, "ref"), let range = XLSXCodec.parseCellRange(ref) {
            sheet.mergedRanges.append(range)
          }
          index = tag.end
          continue
        }
        if localIs(tag, "c"), !tag.isClose {
          parseCell(tag, cells: &cells, masters: &masters, followers: &followers)
          continue
        }
        // After the row and cell checks, so the many `<row>` and `<c>` tags never test these names.
        if !tag.isClose, tag.localStart == tag.start + 1, let name = keptElementName(tag) {
          keptElements.append((name, captureElement(tag, name: name)))
          continue
        }
        index = max(tag.end, index + 1)
        if index <= before { index = before + 1 }
      }

      var parsedMasters: [Int: FormulaExpr] = [:]
      for follower in followers {
        guard let master = masters[follower.si] else { continue }
        let adjusted = StreamingWorksheet.expandedSharedFormula(
          master: master.formula,
          si: follower.si,
          rowDelta: follower.address.row - master.row,
          colDelta: follower.address.col - master.col,
          parsedMasters: &parsedMasters
        )
        var cell = cells[follower.address] ?? Cell()
        cell.raw = adjusted
        if let text = follower.cacheText, let type = follower.cacheType {
          cell.importedFormulaResult = text
          cell.importedFormulaValueType = type
        }
        if !cell.isEmpty {
          cells[follower.address] = cell
        }
      }

      sheet.replaceCells(cells)
      return conditionalFormatting.joined()
    }

    /// `<c r="B1" s="2"/>` in one pass. Returns false when the tag is not that shape.
    mutating func consumePlainStyledCell(into cells: inout [CellAddress: Cell]) -> Bool {
      guard index + 8 < count, bytes[index] == 60, bytes[index + 1] == 99, bytes[index + 2] == 32
      else { return false }
      var cursor = index + 3
      while cursor < count, isXMLSpace(bytes[cursor]) { cursor += 1 }
      guard cursor + 3 < count, bytes[cursor] == 114, bytes[cursor + 1] == 61,
        bytes[cursor + 2] == 34
      else { return false }
      cursor += 3
      let refStart = cursor
      while cursor < count, bytes[cursor] != 34 { cursor += 1 }
      let refEnd = cursor
      guard cursor < count else { return false }
      cursor += 1
      while cursor < count, isXMLSpace(bytes[cursor]) { cursor += 1 }
      guard cursor + 3 < count, bytes[cursor] == 115, bytes[cursor + 1] == 61,
        bytes[cursor + 2] == 34
      else { return false }
      cursor += 3
      var style = 0
      var sawDigit = false
      while cursor < count, bytes[cursor] >= 48, bytes[cursor] <= 57 {
        sawDigit = true
        style = style * 10 + Int(bytes[cursor] - 48)
        cursor += 1
      }
      guard sawDigit, cursor < count, bytes[cursor] == 34 else { return false }
      cursor += 1
      while cursor < count, isXMLSpace(bytes[cursor]) { cursor += 1 }
      guard cursor + 1 < count, bytes[cursor] == 47, bytes[cursor + 1] == 62 else { return false }
      if styleKeepsFormat.indices.contains(style), styleKeepsFormat[style],
        formats.indices.contains(style),
        let format = formats[style],
        let address = parseCellRef(refStart, refEnd)
      {
        var cell = Cell()
        cell.format = format
        cells[address] = cell
      }
      index = cursor + 2
      return true
    }

    /// The common `<c>…</c>` shapes: a styled empty cell, a value, or one formula plus a value.
    mutating func consumeCellFast(
      into cells: inout [CellAddress: Cell],
      masters: inout [Int: Master],
      followers: inout [Follower]
    ) -> Bool {
      if consumePlainStyledCell(into: &cells) { return true }
      guard index + 3 < count, bytes[index] == 60, bytes[index + 1] == 99 else { return false }
      let third = bytes[index + 2]
      guard third == 32 || third == 47 || third == 62 else { return false }
      let open = readTag(at: index)
      guard open.localLen == 1, !open.isClose else { return false }
      if open.isSelfClose {
        storeFastCell(
          open: open,
          sawFormula: false,
          formulaBody: "",
          formulaType: nil,
          formulaSI: nil,
          formulaRef: nil,
          valueText: nil,
          valueWasPlain: true,
          inlineText: nil,
          cells: &cells,
          masters: &masters,
          followers: &followers
        )
        index = open.end
        return true
      }

      var cursor = open.end
      while cursor < count, isXMLSpace(bytes[cursor]) { cursor += 1 }
      guard cursor < count, bytes[cursor] == 60 else { return false }

      var sawFormula = false
      var formulaBody = ""
      var formulaType: String?
      var formulaSI: Int?
      var formulaRef: String?
      var valueText: String?
      var valueWasPlain = true

      if cursor + 1 < count, bytes[cursor + 1] == 102 {
        let formula = readTag(at: cursor)
        guard formula.localLen == 1, !formula.isClose else { return false }
        sawFormula = true
        formulaType = attribute(formula, "t")
        formulaSI = attributeRange(formula, "si").flatMap { parseInt($0.0, $0.1) }
        if formulaType == "array" { formulaRef = attribute(formula, "ref") }
        if formula.isSelfClose {
          cursor = formula.end
        } else {
          cursor = formula.end
          let bodyStart = cursor
          var found = false
          while cursor < count {
            if bytes[cursor] == 60 {
              guard let end = closingTagEnd(at: cursor, name: "f") else { return false }
              formulaBody = stringFrom(bodyStart, cursor)
              cursor = end
              found = true
              break
            }
            cursor += 1
          }
          if !found { return false }
        }
        while cursor < count, isXMLSpace(bytes[cursor]) { cursor += 1 }
      }

      if cursor + 1 < count, bytes[cursor] == 60, bytes[cursor + 1] == 118 {
        let value = readTag(at: cursor)
        guard value.localLen == 1, !value.isClose else { return false }
        if value.isSelfClose {
          valueText = ""
          cursor = value.end
        } else {
          valueWasPlain = !hasAttributes(value)
          cursor = value.end
          let bodyStart = cursor
          var found = false
          while cursor < count {
            if bytes[cursor] == 60 {
              guard let end = closingTagEnd(at: cursor, name: "v") else { return false }
              valueText = stringFrom(bodyStart, cursor)
              cursor = end
              found = true
              break
            }
            cursor += 1
          }
          if !found { return false }
        }
        while cursor < count, isXMLSpace(bytes[cursor]) { cursor += 1 }
      }

      guard cursor + 3 < count, bytes[cursor] == 60, bytes[cursor + 1] == 47,
        bytes[cursor + 2] == 99
      else { return false }
      let close = readTag(at: cursor)
      guard close.isClose, close.localLen == 1 else { return false }

      storeFastCell(
        open: open,
        sawFormula: sawFormula,
        formulaBody: formulaBody,
        formulaType: formulaType,
        formulaSI: formulaSI,
        formulaRef: formulaRef,
        valueText: valueText,
        valueWasPlain: valueWasPlain,
        inlineText: nil,
        cells: &cells,
        masters: &masters,
        followers: &followers
      )
      index = close.end
      return true
    }

    mutating func storeFastCell(
      open: Tag,
      sawFormula: Bool,
      formulaBody: String,
      formulaType: String?,
      formulaSI: Int?,
      formulaRef: String?,
      valueText: String?,
      valueWasPlain: Bool,
      inlineText: String?,
      cells: inout [CellAddress: Cell],
      masters: inout [Int: Master],
      followers: inout [Follower]
    ) {
      guard let ref = attributeRange(open, "r"), let address = parseCellRef(ref.0, ref.1) else {
        return
      }
      let styleIndex = attributeRange(open, "s").flatMap { parseInt($0.0, $0.1) }
      let cellType = attribute(open, "t")
      let format = styleIndex.flatMap { formats.indices.contains($0) ? formats[$0] : nil }
      let isShared = formulaType == "shared" && formulaSI != nil
      var formulaRaw: String?
      var isFollower = false
      if sawFormula {
        if isShared, let si = formulaSI {
          let trimmed = formulaBody.trimmingCharacters(in: .whitespacesAndNewlines)
          let decoded = trimmed.contains("&") ? XLSXCodec.decodeXMLEntities(trimmed) : trimmed
          if decoded.isEmpty {
            isFollower = true
          } else {
            masters[si] = Master(row: address.row, col: address.col, formula: decoded)
            formulaRaw = decoded.hasPrefix("=") ? decoded : "=\(decoded)"
          }
        } else if !formulaBody.isEmpty {
          let decoded = decodeXMLContent(formulaBody)
          if !decoded.isEmpty {
            formulaRaw = decoded.hasPrefix("=") ? decoded : "=\(decoded)"
          }
        }
      }
      var cell = Cell()
      cell.format = format
      if let formulaRaw {
        cell.raw = formulaRaw
        if let formulaRef, let range = XLSXCodec.parseCellRange(formulaRef),
          range.start != range.end
        {
          arrayRefs[address] = range
        }
        if let cache = formulaCache(
          cellType: cellType,
          valueText: valueText,
          valueWasPlain: valueWasPlain,
          inlineText: inlineText
        ) {
          cell.importedFormulaResult = cache.text
          cell.importedFormulaValueType = cache.type
        }
        cells[address] = cell
      } else {
        cell.raw = literalRaw(cellType: cellType, valueText: valueText, inlineText: inlineText)
        let keepsFormat =
          styleIndex.map { styleKeepsFormat.indices.contains($0) && styleKeepsFormat[$0] } ?? false
        if !cell.raw.isEmpty || keepsFormat {
          cells[address] = cell
        }
      }
      if isFollower, let si = formulaSI {
        let cache = formulaCache(
          cellType: cellType,
          valueText: valueText,
          valueWasPlain: valueWasPlain,
          inlineText: inlineText
        )
        followers.append(
          Follower(address: address, si: si, cacheText: cache?.text, cacheType: cache?.type)
        )
      }
    }

    public mutating func parseCell(
      _ tag: Tag,
      cells: inout [CellAddress: Cell],
      masters: inout [Int: Master],
      followers: inout [Follower]
    ) {
      let address = attributeRange(tag, "r").flatMap { parseCellRef($0.0, $0.1) }
      let styleIndex = attributeRange(tag, "s").flatMap { parseInt($0.0, $0.1) }
      let cellType = attribute(tag, "t")
      index = tag.end

      var sawFormula = false
      var formulaBody = ""
      var formulaType: String?
      var formulaSI: Int?
      var formulaRef: String?
      var valueText: String?
      var valueWasPlain = true
      var inlineText: String?

      if !tag.isSelfClose {
        while index < count {
          let before = index
          seekTag()
          if index >= count { break }
          let inner = readTag(at: index)
          if inner.localLen == 0 {
            index = max(inner.end, index + 1)
            continue
          }
          if localIs(inner, "c"), inner.isClose {
            index = max(inner.end, index + 1)
            break
          }
          if localIs(inner, "f"), !inner.isClose {
            sawFormula = true
            formulaType = attribute(inner, "t")
            formulaSI = attributeRange(inner, "si").flatMap { parseInt($0.0, $0.1) }
            if formulaType == "array" { formulaRef = attribute(inner, "ref") }
            if inner.isSelfClose {
              formulaBody = ""
              index = inner.end
            } else {
              index = inner.end
              formulaBody = consumeSimpleText("f")
            }
            continue
          }
          if localIs(inner, "v"), !inner.isClose {
            valueWasPlain = !hasAttributes(inner)
            if inner.isSelfClose {
              valueText = ""
              index = inner.end
            } else {
              index = inner.end
              valueText = consumeSimpleText("v")
            }
            continue
          }
          if localIs(inner, "is"), !inner.isClose {
            if inner.isSelfClose {
              index = inner.end
            } else {
              index = inner.end
              inlineText = consumeInlineText()
            }
            continue
          }
          index = max(inner.end, index + 1)
          if index <= before { index = before + 1 }
        }
      }

      guard let address else { return }
      let format = styleIndex.flatMap { formats.indices.contains($0) ? formats[$0] : nil }
      let isShared = formulaType == "shared" && formulaSI != nil
      var formulaRaw: String?
      var isFollower = false

      if sawFormula {
        if isShared, let si = formulaSI {
          let trimmed = formulaBody.trimmingCharacters(in: .whitespacesAndNewlines)
          let decoded = trimmed.contains("&") ? XLSXCodec.decodeXMLEntities(trimmed) : trimmed
          if decoded.isEmpty {
            isFollower = true
          } else {
            masters[si] = Master(row: address.row, col: address.col, formula: decoded)
            formulaRaw = decoded.hasPrefix("=") ? decoded : "=\(decoded)"
          }
        } else if !formulaBody.isEmpty {
          let decoded = decodeXMLContent(formulaBody)
          if !decoded.isEmpty {
            formulaRaw = decoded.hasPrefix("=") ? decoded : "=\(decoded)"
          }
        }
      }

      var cell = Cell()
      cell.format = format
      if let formulaRaw {
        cell.raw = formulaRaw
        if let formulaRef, let range = XLSXCodec.parseCellRange(formulaRef),
          range.start != range.end
        {
          arrayRefs[address] = range
        }
        if let cache = formulaCache(
          cellType: cellType,
          valueText: valueText,
          valueWasPlain: valueWasPlain,
          inlineText: inlineText
        ) {
          cell.importedFormulaResult = cache.text
          cell.importedFormulaValueType = cache.type
        }
      } else {
        cell.raw = literalRaw(cellType: cellType, valueText: valueText, inlineText: inlineText)
      }
      if !cell.isEmpty {
        cells[address] = cell
      }
      if isFollower, let si = formulaSI {
        let cache = formulaCache(
          cellType: cellType,
          valueText: valueText,
          valueWasPlain: valueWasPlain,
          inlineText: inlineText
        )
        followers.append(
          Follower(address: address, si: si, cacheText: cache?.text, cacheType: cache?.type)
        )
      }
    }

    public func literalRaw(cellType: String?, valueText: String?, inlineText: String?) -> String {
      let value = valueText.map(decodeXMLContent)
      // A stored boolean is 1 or 0. It reads back as the TRUE or FALSE that was typed.
      if cellType == "b", let value {
        return value == "1" || value.uppercased() == "TRUE" ? "TRUE" : "FALSE"
      }
      if cellType == "s" || cellType == "sharedString" {
        if !sharedTexts.isEmpty, let value, let index = Int(value),
          sharedTexts.indices.contains(index)
        {
          if let text = sharedTexts[index] { return text }
          if let inlineText, !inlineText.isEmpty { return inlineText }
          return value
        }
        if let value { return value }
      } else if let value {
        return value
      }
      if let inlineText, !inlineText.isEmpty { return inlineText }
      return ""
    }

    public func formulaCache(
      cellType: String?,
      valueText: String?,
      valueWasPlain: Bool,
      inlineText: String?
    ) -> (text: String, type: ImportedFormulaValueType)? {
      if let valueText {
        if valueWasPlain {
          let trimmed = valueText.trimmingCharacters(in: .whitespacesAndNewlines)
          let text = trimmed.contains("&") ? XLSXCodec.decodeXMLEntities(trimmed) : trimmed
          if !text.isEmpty {
            if cellType == "s" || cellType == "sharedString" {
              if let resolved = sharedText(at: text) {
                return (resolved, .string)
              }
            } else {
              return (text, importedType(cellType))
            }
          }
          if let blank = emptyStringCache(cellType) { return blank }
        } else {
          let text = decodeXMLContent(valueText)
          if !text.isEmpty {
            if cellType == "s" || cellType == "sharedString" {
              if let resolved = sharedText(at: text) {
                return (resolved, .string)
              }
            } else {
              return (text, importedType(cellType))
            }
          }
          if let blank = emptyStringCache(cellType) { return blank }
        }
      }
      if cellType == "s" || cellType == "sharedString", let valueText,
        let resolved = sharedText(at: decodeXMLContent(valueText))
      {
        return (resolved, .string)
      }
      if let inlineText {
        let text = decodeXMLContent(inlineText)
        if !text.isEmpty { return (text, .string) }
      }
      if let valueText {
        let text = decodeXMLContent(valueText)
        if !text.isEmpty { return (text, importedType(cellType)) }
        if let blank = emptyStringCache(cellType) { return blank }
      }
      return nil
    }

    public func emptyStringCache(_ cellType: String?) -> (
      text: String, type: ImportedFormulaValueType
    )? {
      guard cellType == "str" || cellType == "inlineStr" else { return nil }
      return ("", .string)
    }

    public func sharedText(at raw: String) -> String? {
      guard let index = Int(raw), sharedTexts.indices.contains(index) else { return nil }
      return sharedTexts[index]
    }

    public func importedType(_ cellType: String?) -> ImportedFormulaValueType {
      switch cellType {
      case "b": return .boolean
      case "e": return .error
      case "str", "inlineStr", "s", "sharedString", "d": return .string
      default: return .number
      }
    }

    public mutating func parseAutoFilter(_ tag: Tag) -> SheetFilterState? {
      let range = attribute(tag, "ref").flatMap { XLSXCodec.parseCellRange($0) }
      if tag.isSelfClose {
        index = tag.end
        guard let range else { return nil }
        return SheetFilterState(range: range, selectedValuesByColumn: [:])
      }
      var selected: [Int: Set<String>] = [:]
      var rules: [Int: ColumnFilterRules] = [:]
      var custom: [(op: String?, val: String)] = []
      var customAnd = false
      var top10: (top: Bool, count: Int)?
      var colId: Int?
      func finishColumn() {
        guard let colId, let range else { return }
        if let parsed = XLSXCodec.filterRules(
          customFilters: custom, matchAll: customAnd, top10: top10)
        {
          rules[range.normalized.minCol + colId] = parsed
        }
        custom = []
        customAnd = false
        top10 = nil
      }
      index = tag.end
      while index < count {
        let before = index
        seekTag()
        if index >= count { break }
        let inner = readTag(at: index)
        if localIs(inner, "autoFilter"), inner.isClose {
          index = max(inner.end, index + 1)
          break
        }
        if localIs(inner, "filterColumn"), !inner.isClose {
          colId = attributeRange(inner, "colId").flatMap { parseInt($0.0, $0.1) }
          if inner.isSelfClose { colId = nil }
        } else if localIs(inner, "filterColumn"), inner.isClose {
          finishColumn()
          colId = nil
        }
        if localIs(inner, "customFilters"), !inner.isClose {
          customAnd = isTrue(attribute(inner, "and"))
        }
        if localIs(inner, "customFilter"), !inner.isClose, colId != nil {
          let val = attribute(inner, "val").map {
            $0.contains("&") ? XLSXCodec.decodeXMLEntities($0) : $0
          }
          custom.append((attribute(inner, "operator"), val ?? ""))
        }
        if localIs(inner, "top10"), !inner.isClose, colId != nil,
          let count = attribute(inner, "val").flatMap({ Double($0) }), count >= 1,
          attribute(inner, "percent") != "1"
        {
          top10 = (attribute(inner, "top") != "0", Int(count))
        }
        if localIs(inner, "filter"), !inner.isClose, let colId, let range,
          let val = attribute(inner, "val")
        {
          let decoded = val.contains("&") ? XLSXCodec.decodeXMLEntities(val) : val
          selected[range.normalized.minCol + colId, default: []].insert(decoded)
        }
        index = max(inner.end, index + 1)
        if index <= before { index = before + 1 }
      }
      guard let range else { return nil }
      var state = SheetFilterState(range: range, selectedValuesByColumn: selected)
      state.rulesByColumn = rules
      return state
    }

    public func applyPane(_ tag: Tag, to sheet: inout Sheet) {
      let state = attribute(tag, "state")?.lowercased() ?? ""
      guard state == "frozen" || state == "frozensplit" else { return }
      if let y = attributeDouble(tag, "ySplit"), y > 0 {
        sheet.frozenRows = Int(y.rounded(.down))
      }
      if let x = attributeDouble(tag, "xSplit"), x > 0 {
        sheet.frozenColumns = Int(x.rounded(.down))
      }
    }

    public func applyColumn(_ tag: Tag, to sheet: inout Sheet) {
      guard let min = attributeRange(tag, "min").flatMap({ parseInt($0.0, $0.1) }),
        let max = attributeRange(tag, "max").flatMap({ parseInt($0.0, $0.1) }),
        max >= min, min >= 1
      else { return }
      // A `<col>` may cover every column to 16,384. Only hidden and grouped spans are kept per column.
      let span = min...Swift.min(max, StreamingWorksheet.maxKeptColumn)
      let hidden = isTrue(attribute(tag, "hidden"))
      let level = attribute(tag, "outlineLevel").flatMap { Int($0) } ?? 0
      let collapsed = isTrue(attribute(tag, "collapsed"))
      if hidden || level > 0 || collapsed {
        for col in span {
          if hidden { sheet.fileExtras.hiddenColumns.insert(col - 1) }
          if level > 0 { sheet.fileExtras.columnOutlineLevels[col - 1] = Swift.min(level, 7) }
          if collapsed { sheet.fileExtras.collapsedColumns.insert(col - 1) }
        }
      }
      guard let width = attributeDouble(tag, "width") else { return }
      let pixels = CGFloat(width) * 7
      // The default width is written for grouped or hidden columns; it is not a set width.
      guard pixels > 0, abs(pixels - Workbook.defaultColumnWidth) > 0.5 else { return }
      for col in span {
        sheet.columnWidths[col - 1] = pixels
      }
    }

    public func applyRow(_ tag: Tag, to sheet: inout Sheet) {
      // One pass over the attributes: a sheet can have a million rows.
      var row: Int?
      var height: Double?
      var hidden = false
      var level = 0
      var collapsed = false
      forEachAttribute(tag) { nameStart, nameLen, valueStart, valueEnd in
        switch (bytes[nameStart], nameLen) {
        case (114, 1):  // r
          row = parseInt(valueStart, valueEnd)
        case (104, 2):  // ht
          height = Double(stringFrom(valueStart, valueEnd))
        case (104, 6):  // hidden
          hidden = isTrueValue(valueStart, valueEnd)
        case (111, 12):  // outlineLevel
          level = parseInt(valueStart, valueEnd) ?? 0
        case (99, 9):  // collapsed
          collapsed = isTrueValue(valueStart, valueEnd)
        default:
          break
        }
      }
      guard let row, row >= 1 else { return }
      if hidden {
        sheet.fileExtras.hiddenRows.insert(row - 1)
      }
      if level > 0 {
        sheet.fileExtras.rowOutlineLevels[row - 1] = Swift.min(level, 7)
      }
      if collapsed {
        sheet.fileExtras.collapsedRows.insert(row - 1)
      }
      guard let height, height > 0 else { return }
      sheet.rowHeights[row - 1] = CGFloat(height)
    }

    /// "1" or "true".
    func isTrueValue(_ start: Int, _ end: Int) -> Bool {
      let length = end - start
      if length == 1 { return bytes[start] == 49 }
      return length == 4 && bytes[start] == 116
    }

    /// Calls `body` with the byte ranges of each attribute's name and value.
    func forEachAttribute(_ tag: Tag, _ body: (Int, Int, Int, Int) -> Void) {
      var cursor = tag.attrStart
      let end = tag.attrEnd
      while cursor < end {
        while cursor < end, isXMLSpace(bytes[cursor]) { cursor += 1 }
        if cursor >= end { break }
        let nameStart = cursor
        while cursor < end, bytes[cursor] != 61, !isXMLSpace(bytes[cursor]) { cursor += 1 }
        let nameLen = cursor - nameStart
        while cursor < end, isXMLSpace(bytes[cursor]) { cursor += 1 }
        guard cursor < end, bytes[cursor] == 61 else { continue }
        cursor += 1
        while cursor < end, isXMLSpace(bytes[cursor]) { cursor += 1 }
        guard cursor < end else { break }
        let quote = bytes[cursor]
        guard quote == 34 || quote == 39 else { break }
        cursor += 1
        let valueStart = cursor
        while cursor < end, bytes[cursor] != quote { cursor += 1 }
        let valueEnd = cursor
        if cursor < end { cursor += 1 }
        if nameLen > 0 { body(nameStart, nameLen, valueStart, valueEnd) }
      }
    }

    func isTrue(_ value: String?) -> Bool {
      value == "1" || value == "true"
    }

    public mutating func captureElement(_ tag: Tag, name: StaticString) -> String {
      let start = tag.start
      if tag.isSelfClose {
        index = tag.end
        return stringFrom(start, index)
      }
      var depth = 1
      index = tag.end
      while index < count, depth > 0 {
        let before = index
        seekTag()
        if index >= count { break }
        let inner = readTag(at: index)
        if inner.localLen > 0, localIs(inner, name) {
          if inner.isClose {
            depth -= 1
          } else if !inner.isSelfClose {
            depth += 1
          }
        }
        index = max(inner.end, index + 1)
        if index <= before { index = before + 1 }
      }
      return stringFrom(start, min(index, count))
    }

    public mutating func consumeInlineText() -> String? {
      var text: String?
      var nested = 0
      while index < count {
        let before = index
        seekTag()
        if index >= count { break }
        let tag = readTag(at: index)
        if tag.localLen == 0 {
          index = max(tag.end, index + 1)
          continue
        }
        if localIs(tag, "is"), tag.isClose {
          index = max(tag.end, index + 1)
          break
        }
        if localIs(tag, "t"), nested == 0, !tag.isClose {
          if text == nil {
            if tag.isSelfClose {
              text = ""
              index = tag.end
            } else {
              index = tag.end
              text = consumeSimpleText("t")
            }
          } else if tag.isSelfClose {
            index = tag.end
          } else {
            index = tag.end
            _ = consumeSimpleText("t")
          }
          continue
        }
        if !tag.isClose, !tag.isSelfClose { nested += 1 }
        if tag.isClose { nested = max(0, nested - 1) }
        index = max(tag.end, index + 1)
        if index <= before { index = before + 1 }
      }
      guard let text else { return nil }
      let decoded = decodeXMLContent(text)
      return decoded.isEmpty ? nil : decoded
    }

    public mutating func consumeSimpleText(_ name: StaticString) -> String {
      let start = index
      while index < count {
        if bytes[index] != 60 {
          index += 1
          continue
        }
        if let end = closingTagEnd(at: index, name: name) {
          let text = stringFrom(start, index)
          index = end
          return text
        }
        let tag = readTag(at: index)
        index = max(tag.end, index + 1)
      }
      return stringFrom(start, index)
    }

    public mutating func seekTag() {
      while index < count, bytes[index] != 60 {
        index += 1
      }
    }

    public func readTag(at start: Int) -> Tag {
      var tag = Tag(
        start: start,
        end: min(start + 1, count),
        localStart: start,
        localLen: 0,
        isClose: false,
        isSelfClose: false,
        attrStart: start,
        attrEnd: start
      )
      guard start < count, bytes[start] == 60 else { return tag }
      if start + 1 < count, bytes[start + 1] == 33 || bytes[start + 1] == 63 {
        tag.end = skipSpecial(at: start)
        return tag
      }

      var cursor = start + 1
      if cursor < count, bytes[cursor] == 47 {
        tag.isClose = true
        cursor += 1
      }
      let nameStart = cursor
      while cursor < count {
        let byte = bytes[cursor]
        if byte == 62 || byte == 47 || isXMLSpace(byte) { break }
        cursor += 1
      }
      var localStart = nameStart
      var nameCursor = nameStart
      while nameCursor < cursor {
        if bytes[nameCursor] == 58 { localStart = nameCursor + 1 }
        nameCursor += 1
      }
      tag.localStart = localStart
      tag.localLen = cursor - localStart
      tag.attrStart = cursor

      var quote: UInt8 = 0
      var slashAt: Int?
      while cursor < count {
        let byte = bytes[cursor]
        if quote != 0 {
          if byte == quote { quote = 0 }
          cursor += 1
          continue
        }
        if byte == 34 || byte == 39 {
          quote = byte
          slashAt = nil
          cursor += 1
          continue
        }
        if byte == 47 {
          slashAt = cursor
          cursor += 1
          continue
        }
        if byte == 62 {
          tag.isSelfClose = slashAt != nil
          tag.attrEnd = slashAt ?? cursor
          tag.end = cursor + 1
          return tag
        }
        if !isXMLSpace(byte) { slashAt = nil }
        cursor += 1
      }
      tag.attrEnd = cursor
      tag.end = cursor
      return tag
    }

    public func skipSpecial(at start: Int) -> Int {
      if start + 4 <= count, bytes[start + 1] == 33, bytes[start + 2] == 45, bytes[start + 3] == 45
      {
        var cursor = start + 4
        while cursor + 2 < count {
          if bytes[cursor] == 45, bytes[cursor + 1] == 45, bytes[cursor + 2] == 62 {
            return cursor + 3
          }
          cursor += 1
        }
        return count
      }
      if start + 9 <= count,
        bytes[start + 1] == 33, bytes[start + 2] == 91, bytes[start + 3] == 67,
        bytes[start + 4] == 68, bytes[start + 5] == 65, bytes[start + 6] == 84,
        bytes[start + 7] == 65, bytes[start + 8] == 91
      {
        var cursor = start + 9
        while cursor + 2 < count {
          if bytes[cursor] == 93, bytes[cursor + 1] == 93, bytes[cursor + 2] == 62 {
            return cursor + 3
          }
          cursor += 1
        }
        return count
      }
      var cursor = start + 2
      while cursor < count, bytes[cursor] != 62 { cursor += 1 }
      return min(cursor + 1, count)
    }

    public func closingTagEnd(at start: Int, name: StaticString) -> Int? {
      guard start + 2 < count, bytes[start] == 60, bytes[start + 1] == 47 else { return nil }
      var cursor = start + 2
      var localStart = cursor
      while cursor < count {
        let byte = bytes[cursor]
        if byte == 58 {
          cursor += 1
          localStart = cursor
          continue
        }
        if byte == 62 || isXMLSpace(byte) { break }
        cursor += 1
      }
      let matched = name.withUTF8Buffer { buffer -> Bool in
        guard buffer.count == cursor - localStart else { return false }
        for offset in 0..<buffer.count {
          if bytes[localStart + offset] != buffer[offset] { return false }
        }
        return true
      }
      guard matched else { return nil }
      while cursor < count, bytes[cursor] != 62 { cursor += 1 }
      guard cursor < count else { return nil }
      return cursor + 1
    }

    public func localIs(_ tag: Tag, _ name: StaticString) -> Bool {
      name.withUTF8Buffer { buffer in
        guard buffer.count == tag.localLen else { return false }
        for offset in 0..<buffer.count {
          if bytes[tag.localStart + offset] != buffer[offset] { return false }
        }
        return true
      }
    }

    public func hasAttributes(_ tag: Tag) -> Bool {
      var cursor = tag.attrStart
      while cursor < tag.attrEnd {
        if !isXMLSpace(bytes[cursor]) { return true }
        cursor += 1
      }
      return false
    }

    public func attributeRange(_ tag: Tag, _ name: StaticString) -> (Int, Int)? {
      name.withUTF8Buffer { nameBytes in
        var cursor = tag.attrStart
        let end = tag.attrEnd
        while cursor < end {
          while cursor < end, isXMLSpace(bytes[cursor]) { cursor += 1 }
          if cursor >= end { break }
          let nameStart = cursor
          while cursor < end {
            let byte = bytes[cursor]
            if byte == 61 || isXMLSpace(byte) { break }
            cursor += 1
          }
          let nameLen = cursor - nameStart
          while cursor < end, isXMLSpace(bytes[cursor]) { cursor += 1 }
          guard cursor < end, bytes[cursor] == 61 else { continue }
          cursor += 1
          while cursor < end, isXMLSpace(bytes[cursor]) { cursor += 1 }
          guard cursor < end else { break }
          let quote = bytes[cursor]
          guard quote == 34 || quote == 39 else { break }
          cursor += 1
          let valueStart = cursor
          while cursor < end, bytes[cursor] != quote { cursor += 1 }
          let valueEnd = cursor
          if cursor < end { cursor += 1 }
          if nameLen == nameBytes.count {
            var matches = true
            for offset in 0..<nameLen where bytes[nameStart + offset] != nameBytes[offset] {
              matches = false
              break
            }
            if matches { return (valueStart, valueEnd) }
          }
        }
        return nil
      }
    }

    public func attribute(_ tag: Tag, _ name: StaticString) -> String? {
      guard let range = attributeRange(tag, name) else { return nil }
      return stringFrom(range.0, range.1)
    }

    public func attributeDouble(_ tag: Tag, _ name: StaticString) -> Double? {
      guard let text = attribute(tag, name) else { return nil }
      return Double(text)
    }

    public func parseInt(_ start: Int, _ end: Int) -> Int? {
      guard start < end else { return nil }
      var value = 0
      var cursor = start
      while cursor < end {
        let byte = bytes[cursor]
        guard byte >= 48, byte <= 57 else { return nil }
        value = value * 10 + Int(byte - 48)
        cursor += 1
      }
      return value
    }

    public func parseCellRef(_ start: Int, _ end: Int) -> CellAddress? {
      var cursor = start
      if cursor < end, bytes[cursor] == 36 { cursor += 1 }
      var column = 0
      var sawLetter = false
      while cursor < end {
        var byte = bytes[cursor]
        if byte >= 97, byte <= 122 { byte -= 32 }
        if byte < 65 || byte > 90 { break }
        sawLetter = true
        column = column * 26 + Int(byte - 64)
        cursor += 1
      }
      guard sawLetter else { return nil }
      column -= 1
      if cursor < end, bytes[cursor] == 36 { cursor += 1 }
      guard cursor < end else { return nil }
      var row = 0
      var sawDigit = false
      while cursor < end {
        let byte = bytes[cursor]
        guard byte >= 48, byte <= 57 else { return nil }
        sawDigit = true
        row = row * 10 + Int(byte - 48)
        cursor += 1
      }
      guard sawDigit, row >= 1, column >= 0 else { return nil }
      return CellAddress(row: row - 1, col: column)
    }

    public func stringFrom(_ start: Int, _ end: Int) -> String {
      guard start < end else { return "" }
      let length = end - start
      return String(unsafeUninitializedCapacity: length) { buffer in
        guard let destination = buffer.baseAddress else { return 0 }
        destination.update(from: bytes + start, count: length)
        return length
      }
    }

    public func isXMLSpace(_ byte: UInt8) -> Bool {
      byte == 32 || byte == 9 || byte == 10 || byte == 13
    }

    public func decodeXMLContent(_ string: String) -> String {
      let normalized: String
      if string.contains("\r") {
        normalized = string.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(
          of: "\r", with: "\n")
      } else {
        normalized = string
      }
      guard normalized.contains("&") else { return normalized }
      var output = ""
      output.reserveCapacity(normalized.count)
      var cursor = normalized.startIndex
      while cursor < normalized.endIndex {
        if normalized[cursor] != "&" {
          let next = normalized[cursor...].firstIndex(of: "&") ?? normalized.endIndex
          output.append(contentsOf: normalized[cursor..<next])
          cursor = next
          continue
        }
        let entityStart = cursor
        cursor = normalized.index(after: cursor)
        guard let semi = normalized[cursor...].firstIndex(of: ";"),
          normalized.distance(from: cursor, to: semi) <= 12
        else {
          output.append("&")
          continue
        }
        let token = normalized[cursor..<semi]
        cursor = normalized.index(after: semi)
        if token == "amp" {
          output.append("&")
        } else if token == "lt" {
          output.append("<")
        } else if token == "gt" {
          output.append(">")
        } else if token == "quot" {
          output.append("\"")
        } else if token == "apos" {
          output.append("'")
        } else if let scalar = numericScalar(token) {
          output.append(Character(scalar))
        } else {
          output.append(contentsOf: normalized[entityStart..<cursor])
        }
      }
      return output
    }

    public func numericScalar(_ token: Substring) -> Unicode.Scalar? {
      guard token.first == "#" else { return nil }
      var digits = token.dropFirst()
      let hex: Bool
      if digits.first == "x" || digits.first == "X" {
        hex = true
        digits = digits.dropFirst()
      } else {
        hex = false
      }
      guard let value = UInt32(digits, radix: hex ? 16 : 10), let scalar = Unicode.Scalar(value)
      else {
        return nil
      }
      return scalar
    }
  }
}

/// Uncompressed zip entries opened once for a streaming import.
public nonisolated final class ZipPackage: @unchecked Sendable {
  /// Which archive a package was unpacked from: where its bytes are and how many there are.
  /// A package keeps its archive, so no other archive can hold those bytes while it is in use.
  private struct ArchiveKey: Hashable {
    var address: UInt
    var count: Int

    init?(_ data: Data) {
      // A very short Data keeps its bytes inside itself, at no fixed address. No archive with
      // a part in it is this short.
      guard data.count >= 64,
        let address = data.withUnsafeBytes({ $0.baseAddress })
      else { return nil }
      self.address = UInt(bitPattern: address)
      self.count = data.count
    }
  }

  private static let lock = NSLock()
  /// Packages in use, by archive. Two files can be loading at once, on any threads, so a read
  /// names its archive and gets that archive's parts or nothing.
  nonisolated(unsafe) private static var inUse: [ArchiveKey: (package: ZipPackage, uses: Int)] =
    [:]

  private let archiveData: Data
  private let key: ArchiveKey?
  private let files: [String: Data]

  /// The largest file Spark Grid opens, counted in unpacked bytes as they come out, not from
  /// the sizes the file declares: a small file can unpack to far more than memory holds.
  public struct Limits: Sendable {
    public var totalBytes: Int
    public var partBytes: Int

    public init(totalBytes: Int, partBytes: Int) {
      self.totalBytes = totalBytes
      self.partBytes = partBytes
    }

    /// 2 GB in all, and no part over 200 MB.
    public static let standard = Limits(totalBytes: 2_000_000_000, partBytes: 200_000_000)
  }

  struct LimitExceeded: Error {}

  /// One part's bytes. Stops as soon as the part passes `limits.partBytes` or `total`, the bytes
  /// unpacked so far, passes `limits.totalBytes`.
  static func extract(
    _ entry: Entry, from archive: Archive, total: inout Int, limits: Limits = .standard
  ) throws -> Data {
    var data = Data()
    _ = try archive.extract(entry) { chunk in
      total += chunk.count
      guard data.count + chunk.count <= limits.partBytes, total <= limits.totalBytes else {
        throw LimitExceeded()
      }
      data.append(chunk)
    }
    return data
  }

  public init(archiveData: Data, limits: Limits = .standard) throws {
    guard let archive = try? Archive(data: archiveData, accessMode: .read, pathEncoding: nil) else {
      throw XLSXCodec.CodecError.unreadable
    }
    var files: [String: Data] = [:]
    var total = 0
    for entry in archive {
      if entry.path.hasSuffix("/") { continue }
      let extracted: Data
      do {
        extracted = try Self.extract(entry, from: archive, total: &total, limits: limits)
      } catch is LimitExceeded {
        throw XLSXCodec.CodecError.tooLarge
      } catch {
        continue
      }
      if !extracted.isEmpty {
        files[entry.path] = extracted
      }
    }
    self.archiveData = archiveData
    self.key = ArchiveKey(archiveData)
    self.files = files
  }

  public func data(for entryPath: String) -> Data? {
    var key = entryPath
    if key.hasPrefix("/") { key.removeFirst() }
    if let data = files[key], !data.isEmpty { return data }
    if !key.hasPrefix("xl/"), let data = files["xl/\(key)"], !data.isEmpty { return data }
    return nil
  }

  /// Serves reads of this package's archive from memory while `body` runs, on every thread.
  /// Reads of any other archive are untouched.
  public static func use<T>(_ package: ZipPackage, _ body: () throws -> T) rethrows -> T {
    guard let key = package.key else { return try body() }
    lock.lock()
    // A second package unpacked from the same archive holds the same parts; the first serves.
    inUse[key, default: (package, 0)].uses += 1
    lock.unlock()
    defer {
      lock.lock()
      if let entry = inUse[key] {
        inUse[key] = entry.uses > 1 ? (entry.package, entry.uses - 1) : nil
      }
      lock.unlock()
    }
    return try body()
  }

  /// `(active, data)` for a part of `archiveData`. `active` is false when no import of that
  /// archive is running; the caller then opens the archive itself.
  public static func cachedEntry(in archiveData: Data, at entryPath: String) -> (Bool, Data?) {
    guard let key = ArchiveKey(archiveData) else { return (false, nil) }
    lock.lock()
    let package = inUse[key]?.package
    lock.unlock()
    guard let package else { return (false, nil) }
    return (true, package.data(for: entryPath))
  }
}

public enum XLSXImportParity {
  public static func summary(legacy: Workbook, streamed: Workbook) -> String {
    var lines: [String] = []
    var problems = 0
    func note(_ text: String) {
      problems += 1
      if lines.count < 40 { lines.append(text) }
    }

    if legacy.sheets.count != streamed.sheets.count {
      note("sheet count \(legacy.sheets.count) vs \(streamed.sheets.count)")
    }
    if legacy.namedRanges != streamed.namedRanges {
      note("defined names \(legacy.namedRanges.count) vs \(streamed.namedRanges.count)")
    }
    if legacy.xlsxThemeData != streamed.xlsxThemeData {
      note(
        "theme bytes \(legacy.xlsxThemeData?.count ?? -1) vs \(streamed.xlsxThemeData?.count ?? -1)"
      )
    }

    var cellCount = 0
    let sheetCount = min(legacy.sheets.count, streamed.sheets.count)
    for index in 0..<sheetCount {
      let left = legacy.sheets[index]
      let right = streamed.sheets[index]
      cellCount += left.cells.count
      if left.name != right.name {
        note("sheet \(index) name \(left.name) vs \(right.name)")
      }
      if left.cells.count != right.cells.count {
        note("\(left.name) cell count \(left.cells.count) vs \(right.cells.count)")
      }
      for (address, cell) in left.cells {
        guard let other = right.cells[address] else {
          note("\(left.name) \(address.a1) missing")
          continue
        }
        if cell.raw != other.raw {
          note("\(left.name) \(address.a1) raw \(cell.raw) vs \(other.raw)")
        }
        if cell.format != other.format {
          note("\(left.name) \(address.a1) format differs")
        }
        if cell.importedFormulaResult != other.importedFormulaResult {
          note(
            "\(left.name) \(address.a1) cache \(cell.importedFormulaResult ?? "nil") vs \(other.importedFormulaResult ?? "nil")"
          )
        }
        if cell.importedFormulaValueType != other.importedFormulaValueType {
          note(
            "\(left.name) \(address.a1) type \(String(describing: cell.importedFormulaValueType)) vs \(String(describing: other.importedFormulaValueType))"
          )
        }
      }
      for address in right.cells.keys where left.cells[address] == nil {
        note("\(left.name) \(address.a1) extra")
      }
      if left.columnWidths != right.columnWidths {
        note("\(left.name) column widths differ")
      }
      if left.rowHeights != right.rowHeights {
        note("\(left.name) row heights differ")
      }
      if left.frozenRows != right.frozenRows || left.frozenColumns != right.frozenColumns {
        note(
          "\(left.name) panes \(left.frozenRows)x\(left.frozenColumns) vs \(right.frozenRows)x\(right.frozenColumns)"
        )
      }
      if left.mergedRanges != right.mergedRanges {
        note("\(left.name) merges \(left.mergedRanges.count) vs \(right.mergedRanges.count)")
      }
      if left.autoFilter != right.autoFilter {
        note("\(left.name) autofilter differs")
      }
      if !sameRules(left.conditionalFormats, right.conditionalFormats) {
        note(
          "\(left.name) conditional formats \(left.conditionalFormats.count) vs \(right.conditionalFormats.count)"
        )
      }
      if !sameCharts(left.charts, right.charts) {
        note("\(left.name) charts \(left.charts.count) vs \(right.charts.count)")
      }
      if !sameImages(left.images, right.images) {
        note("\(left.name) images \(left.images.count) vs \(right.images.count)")
      }
      if !sameIngest(left.formulaIngestByColumn, right.formulaIngestByColumn) {
        note("\(left.name) formula index differs")
      }
    }

    if problems == 0 {
      return "match sheets=\(legacy.sheets.count) cells=\(cellCount)"
    }
    return (["\(problems) differences"] + lines).joined(separator: "\n")
  }

  private static func sameRules(_ left: [ConditionalFormatRule], _ right: [ConditionalFormatRule])
    -> Bool
  {
    guard left.count == right.count else { return false }
    for (lhs, rhs) in zip(left, right) {
      if lhs.range != rhs.range || lhs.stopIfTrue != rhs.stopIfTrue
        || lhs.predicate != rhs.predicate || lhs.style != rhs.style
      {
        return false
      }
    }
    return true
  }

  private static func sameCharts(_ left: [SheetChart], _ right: [SheetChart]) -> Bool {
    guard left.count == right.count else { return false }
    for (lhs, rhs) in zip(left, right) {
      var copy = rhs
      copy.id = lhs.id
      if copy != lhs { return false }
    }
    return true
  }

  private static func sameIngest(
    _ left: [Int: [(CellAddress, String)]],
    _ right: [Int: [(CellAddress, String)]]
  ) -> Bool {
    guard left.count == right.count else { return false }
    for (key, values) in left {
      guard let other = right[key], other.count == values.count else { return false }
      for (index, item) in values.enumerated()
      where item.0 != other[index].0 || item.1 != other[index].1 {
        return false
      }
    }
    return true
  }

  private static func sameImages(_ left: [SheetImage], _ right: [SheetImage]) -> Bool {
    guard left.count == right.count else { return false }
    for (lhs, rhs) in zip(left, right) {
      var copy = rhs
      copy.id = lhs.id
      if copy != lhs { return false }
    }
    return true
  }
}
