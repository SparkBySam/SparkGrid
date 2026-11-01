import Formula
import Foundation
import Functions
import GridCore
import Model
import NumberFormat

public nonisolated struct LookupTableKey: Hashable {
  public var sheet: String
  public var minRow: Int
  public var minCol: Int
  public var maxRow: Int
  public var maxCol: Int
  public var resultIndex: Int
  public var horizontal: Bool

  public func contains(address: CellAddress) -> Bool {
    address.row >= minRow && address.row <= maxRow && address.col >= minCol && address.col <= maxCol
  }
}

/// Exact-match VLOOKUP / HLOOKUP: one scan per table, then O(1) needle lookup.
public nonisolated final class FormulaLookupTableCache {
  public weak var profile: FormulaRecalcProfile?
  private var exactMaps: [LookupTableKey: [AggregateValueKey: CellValue]] = [:]

  public func invalidateAll() {
    exactMaps.removeAll(keepingCapacity: true)
  }

  public func invalidate(sheetName: String, address: CellAddress) {
    let sheet = sheetName.lowercased()
    exactMaps = exactMaps.filter { key, _ in
      key.sheet != sheet || !key.contains(address: address)
    }
  }

  public func exactLookup(
    key: LookupTableKey,
    needle: CellValue,
    build: () -> [AggregateValueKey: CellValue]
  ) -> CellValue? {
    guard let needleKey = AggregateValueKey.from(cellValue: needle) else { return nil }
    let map =
      exactMaps[key]
      ?? {
        let buildStart = CFAbsoluteTimeGetCurrent()
        let built = build()
        profile?.lookupIndexBuildSeconds += CFAbsoluteTimeGetCurrent() - buildStart
        exactMaps[key] = built
        return built
      }()
    return map[needleKey]
  }
}
