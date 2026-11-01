import Formula
import Foundation
import Functions
import GridCore
import Model
import NumberFormat

/// Stable identity for a rectangular range used by conditional aggregates (COUNTIFS, SUMIFS, …).
public nonisolated struct AggregateRangeKey: Hashable {
  public var sheet: String
  public var minRow: Int
  public var minCol: Int
  public var maxRow: Int
  public var maxCol: Int

  public init(sheet: String?, row: Int, col: Int, rows: Int, cols: Int) {
    self.sheet = (sheet ?? "").lowercased()
    self.minRow = row
    self.minCol = col
    self.maxRow = row + rows - 1
    self.maxCol = col + cols - 1
  }

  public func contains(address: CellAddress) -> Bool {
    address.row >= minRow && address.row <= maxRow && address.col >= minCol && address.col <= maxCol
  }
}

/// Normalized cell value for equality-based aggregate histograms (COUNTIFS / SUMIFS lookups).
public nonisolated struct AggregateValueKey: Hashable {
  public enum Kind: UInt8 {
    case blank = 0
    case number = 1
    case text = 2
    case bool = 3
  }

  public var kind: Kind
  public var numberBits: UInt64
  public var text: String

  public static func from(cellValue: CellValue) -> AggregateValueKey? {
    switch cellValue {
    case .error:
      return nil
    case .blank:
      return AggregateValueKey(kind: .blank, numberBits: 0, text: "")
    case .number(let number):
      return AggregateValueKey(kind: .number, numberBits: number.bitPattern, text: "")
    case .bool(let flag):
      return AggregateValueKey(kind: .bool, numberBits: flag ? 1 : 0, text: "")
    case .string(let raw):
      return AggregateValueKey(kind: .text, numberBits: 0, text: raw.lowercased())
    }
  }
}

public nonisolated struct AggregateCriteriaTupleKey: Hashable {
  public var parts: [AggregateValueKey]
}

private struct CompositeCountIndexKey: Hashable {
  var rangeKeys: [AggregateRangeKey]
}

private struct CompositeSumIndexKey: Hashable {
  var criteriaRangeKeys: [AggregateRangeKey]
  var sumRangeKey: AggregateRangeKey
}

private struct MaskedCountIndexKey: Hashable {
  var rangeKey: AggregateRangeKey
  var staticMaskKey: UInt64
}

public nonisolated struct AggregateSumBucket {
  public var count: Int = 0
  public var sum: Double = 0
}

/// One scan per criteria range, then O(1) COUNTIFS / SUMIFS lookups via composite histograms.
public nonisolated final class FormulaAggregateRangeCache {
  public weak var profile: FormulaRecalcProfile?
  /// Reads cell values directly from the workbook model (no per-cell formula eval).
  public var workbookBulkLoader: ((AggregateRangeKey) -> [CellValue])?
  private var snapshots: [AggregateRangeKey: [CellValue]] = [:]
  private var countIndexes: [CompositeCountIndexKey: [AggregateCriteriaTupleKey: Int]] = [:]
  private var sumIndexes: [CompositeSumIndexKey: [AggregateCriteriaTupleKey: AggregateSumBucket]] =
    [:]
  private var booleanStaticMasks: [UInt64: [Bool]] = [:]
  private var maskedCountIndexes: [MaskedCountIndexKey: [AggregateValueKey: Int]] = [:]

  public func invalidateAll() {
    snapshots.removeAll(keepingCapacity: true)
    countIndexes.removeAll(keepingCapacity: true)
    sumIndexes.removeAll(keepingCapacity: true)
    booleanStaticMasks.removeAll(keepingCapacity: true)
    maskedCountIndexes.removeAll(keepingCapacity: true)
  }

  public func invalidate(sheetName: String, address: CellAddress) {
    guard !snapshots.isEmpty else { return }
    let sheet = sheetName.lowercased()
    var removedKeys: Set<AggregateRangeKey> = []
    snapshots = snapshots.filter { key, _ in
      // A display-path range is stored with an empty sheet until the formula's
      // sheet is known. That snapshot still covers this cell.
      let sameSheet = key.sheet == sheet || key.sheet.isEmpty
      if sameSheet && key.contains(address: address) {
        removedKeys.insert(key)
        return false
      }
      return true
    }
    guard !removedKeys.isEmpty else { return }
    countIndexes = countIndexes.filter { !usesAnyRange($0.key.rangeKeys, in: removedKeys) }
    sumIndexes = sumIndexes.filter {
      !usesAnyRange($0.key.criteriaRangeKeys, in: removedKeys)
        && !removedKeys.contains($0.key.sumRangeKey)
    }
    maskedCountIndexes = maskedCountIndexes.filter { !removedKeys.contains($0.key.rangeKey) }
    booleanStaticMasks.removeAll(keepingCapacity: true)
  }

  public func countForMaskedCriteria(
    rangeKey: AggregateRangeKey,
    column: [CellValue],
    staticMaskKey: UInt64,
    mask: [Bool],
    criteriaKey: AggregateValueKey
  ) -> Int {
    let indexKey = MaskedCountIndexKey(rangeKey: rangeKey, staticMaskKey: staticMaskKey)
    let map =
      maskedCountIndexes[indexKey]
      ?? buildMaskedCountIndex(
        indexKey: indexKey,
        column: column,
        mask: mask
      )
    return map[criteriaKey, default: 0]
  }

  public func booleanStaticMask(key: UInt64, rowCount: Int, build: (Int) -> Bool) -> [Bool] {
    if let cached = booleanStaticMasks[key], cached.count == rowCount {
      return cached
    }
    var mask = [Bool]()
    mask.reserveCapacity(rowCount)
    for row in 0..<rowCount {
      mask.append(build(row))
    }
    booleanStaticMasks[key] = mask
    return mask
  }

  public func rowMajorValues(
    key: AggregateRangeKey,
    count: Int,
    fill: (Int) -> CellValue
  ) -> [CellValue] {
    if let cached = snapshots[key] {
      return cached
    }
    let buildStart = CFAbsoluteTimeGetCurrent()
    let values: [CellValue]
    if let bulk = workbookBulkLoader?(key), bulk.count == count {
      values = bulk
    } else {
      var built = [CellValue]()
      built.reserveCapacity(count)
      for index in 0..<count {
        built.append(fill(index))
      }
      values = built
    }
    snapshots[key] = values
    profile?.aggregateIndexBuildSeconds += CFAbsoluteTimeGetCurrent() - buildStart
    return values
  }

  public func countForCriteria(
    rangeKeys: [AggregateRangeKey],
    criteriaKeys: [AggregateValueKey],
    supplyColumns: () -> [[CellValue]]
  ) -> Int {
    let indexKey = CompositeCountIndexKey(rangeKeys: rangeKeys)
    let tuple = AggregateCriteriaTupleKey(parts: criteriaKeys)
    if let map = countIndexes[indexKey] {
      profile?.countifsHistogramIndexHits += 1
      return map[tuple, default: 0]
    }
    profile?.countifsHistogramIndexBuilds += 1
    let map = buildCountIndex(indexKey: indexKey, columns: supplyColumns())
    return map[tuple, default: 0]
  }

  public func sumByRowFilter(
    sumColumn: [CellValue],
    includeRow: (Int) -> Bool
  ) -> AggregateSumBucket {
    var bucket = AggregateSumBucket()
    for row in 0..<sumColumn.count {
      guard includeRow(row) else { continue }
      let value = sumColumn[row]
      guard case .number(let number) = value else { continue }
      bucket.count += 1
      bucket.sum += number
    }
    return bucket
  }

  public func sumForCriteria(
    criteriaRangeKeys: [AggregateRangeKey],
    sumRangeKey: AggregateRangeKey,
    criteriaKeys: [AggregateValueKey],
    supplyColumns: () -> (criteriaColumns: [[CellValue]], sumColumn: [CellValue])
  ) -> AggregateSumBucket {
    let indexKey = CompositeSumIndexKey(
      criteriaRangeKeys: criteriaRangeKeys, sumRangeKey: sumRangeKey)
    let tuple = AggregateCriteriaTupleKey(parts: criteriaKeys)
    if let map = sumIndexes[indexKey] {
      return map[tuple, default: AggregateSumBucket()]
    }
    let supplied = supplyColumns()
    let map = buildSumIndex(
      indexKey: indexKey,
      criteriaColumns: supplied.criteriaColumns,
      sumColumn: supplied.sumColumn
    )
    return map[tuple, default: AggregateSumBucket()]
  }

  private func usesAnyRange(_ keys: [AggregateRangeKey], in removed: Set<AggregateRangeKey>) -> Bool
  {
    keys.contains(where: { removed.contains($0) })
  }

  private func buildCountIndex(
    indexKey: CompositeCountIndexKey,
    columns: [[CellValue]]
  ) -> [AggregateCriteriaTupleKey: Int] {
    let buildStart = CFAbsoluteTimeGetCurrent()
    defer {
      profile?.aggregateIndexBuildSeconds += CFAbsoluteTimeGetCurrent() - buildStart
    }
    guard let rowCount = columns.first?.count, rowCount > 0 else {
      let empty: [AggregateCriteriaTupleKey: Int] = [:]
      countIndexes[indexKey] = empty
      return empty
    }
    var map: [AggregateCriteriaTupleKey: Int] = [:]
    for row in 0..<rowCount {
      var parts: [AggregateValueKey] = []
      parts.reserveCapacity(columns.count)
      var skip = false
      for column in columns {
        guard let key = AggregateValueKey.from(cellValue: column[row]) else {
          skip = true
          break
        }
        parts.append(key)
      }
      if skip { continue }
      let tuple = AggregateCriteriaTupleKey(parts: parts)
      map[tuple, default: 0] += 1
    }
    countIndexes[indexKey] = map
    return map
  }

  private func buildSumIndex(
    indexKey: CompositeSumIndexKey,
    criteriaColumns: [[CellValue]],
    sumColumn: [CellValue]
  ) -> [AggregateCriteriaTupleKey: AggregateSumBucket] {
    let buildStart = CFAbsoluteTimeGetCurrent()
    defer {
      profile?.aggregateIndexBuildSeconds += CFAbsoluteTimeGetCurrent() - buildStart
    }
    let rowCount = sumColumn.count
    guard rowCount > 0 else {
      let empty: [AggregateCriteriaTupleKey: AggregateSumBucket] = [:]
      sumIndexes[indexKey] = empty
      return empty
    }
    var map: [AggregateCriteriaTupleKey: AggregateSumBucket] = [:]
    for row in 0..<rowCount {
      var parts: [AggregateValueKey] = []
      parts.reserveCapacity(criteriaColumns.count)
      var skip = false
      for column in criteriaColumns {
        guard let key = AggregateValueKey.from(cellValue: column[row]) else {
          skip = true
          break
        }
        parts.append(key)
      }
      if skip { continue }
      let sumValue = sumColumn[row]
      guard case .number(let number) = sumValue else { continue }
      let tuple = AggregateCriteriaTupleKey(parts: parts)
      var bucket = map[tuple, default: AggregateSumBucket()]
      bucket.count += 1
      bucket.sum += number
      map[tuple] = bucket
    }
    sumIndexes[indexKey] = map
    return map
  }

  private func buildMaskedCountIndex(
    indexKey: MaskedCountIndexKey,
    column: [CellValue],
    mask: [Bool]
  ) -> [AggregateValueKey: Int] {
    let buildStart = CFAbsoluteTimeGetCurrent()
    defer {
      profile?.aggregateIndexBuildSeconds += CFAbsoluteTimeGetCurrent() - buildStart
    }
    var map: [AggregateValueKey: Int] = [:]
    let rowCount = min(column.count, mask.count)
    for row in 0..<rowCount {
      guard mask[row] else { continue }
      guard let key = AggregateValueKey.from(cellValue: column[row]) else { continue }
      map[key, default: 0] += 1
    }
    maskedCountIndexes[indexKey] = map
    return map
  }
}
