import Formula
import Foundation
import Functions
import GridCore
import Model
import NumberFormat

/// Phase timings for `recalculateEntireWorkbook` (Bug Bash / diagnostics).
public nonisolated final class FormulaRecalcProfile {
  public var ingestSeconds: Double = 0
  public var ingestParseSeconds: Double = 0
  public var ingestDependencySeconds: Double = 0
  /// Fill-follower `adjustedFormulaText` vs stored raw (includes serialize).
  public var ingestFillVerifySeconds: Double = 0
  /// `adjustExpression` on successful fill followers.
  public var ingestFillAdjustSeconds: Double = 0
  /// `shapeAnchorKey` during bulk ingest (parse misses / fallback).
  public var ingestShapeKeySeconds: Double = 0
  /// Sum: scan cells + bucket by column (across all sheet ingests).
  public var ingestEntryScanSeconds: Double = 0
  /// Sum: wall inside `concurrentPerform` column ingest (overlaps across cores per sheet).
  public var ingestColumnParallelWallSeconds: Double = 0
  /// Sum: merge `formulaAST` / `dependencies` / `dependents` after column ingest.
  public var ingestGraphBuildSeconds: Double = 0
  /// Max per-sheet `bulkIngestFormulas` wall.
  public var ingestBulkSheetWallPeakSeconds: Double = 0
  public var ingestTemplateCacheHits: Int = 0
  /// `buildShapeStripPlans` (AST anchor keys + fill validation); runs at eval start, not in `ingestSeconds`.
  public var shapeStripPlanSeconds: Double = 0
  public var aggregateIndexBuildSeconds: Double = 0
  public var lookupIndexBuildSeconds: Double = 0
  public var evalSeconds: Double = 0
  public var evalByFunctionSeconds: [String: Double] = [:]
  public var countifsHistogramLookups: Int = 0
  /// `COUNTIFS` reused a composite histogram built earlier in this recalc (skipped `supplyColumns`).
  public var countifsHistogramIndexHits: Int = 0
  /// First `COUNTIFS` for a composite range key in this recalc (built histogram via `supplyColumns`).
  public var countifsHistogramIndexBuilds: Int = 0
  public var countifsRowScanCells: Int = 0
  public var foreignFormulaEvaluations: Int = 0
  /// `IF(Cn="","",…)` guard: skipped heavy false branch on blank rows.
  public var ifBlankEqualityFastHits: Int = 0
  /// `IFERROR(VLOOKUP(…),…)` without nested `evalCall` dispatch.
  public var iferrorVlookupFastHits: Int = 0
  /// Column strip: exact VLOOKUP table cache hit.
  public var ifStripHits: Int = 0
  /// VLOOKUP kernel used IFERROR fallback expr (#N/A), not full branch tree.
  public var ifStripVlkNA: Int = 0
  /// Full `evaluate` on IF false branch (kernel plan miss).
  public var ifStripBranchTree: Int = 0
  /// Non-blank rows via IF-blank + COUNTIFS column kernel (one snapshot per strip).
  public var ifStripCountifsRows: Int = 0
  /// `TEXTJOIN` strip rows.
  public var ifStripTextJoinRows: Int = 0
  /// Duplicate-status strip rows.
  public var ifStripDupStatusRows: Int = 0
  public var ifStripPlanMiss: [String: Int] = [:]

  /// One row per `otherBranch` IF-blank strip plan miss.
  public struct IfStripOtherBranchEntry: Sendable {
    public var sheet: String
    public var masterA1: String
    public var formula: String
    public var rejectCode: String
  }

  public var ifStripOtherBranchEntries: [IfStripOtherBranchEntry] = []

  public func recordIfStripPlanMiss(_ reason: String) {
    ifStripPlanMiss[reason, default: 0] += 1
  }

  public func recordIfStripOtherBranch(
    sheet: String,
    masterA1: String,
    formula: String,
    rejectCode: String
  ) {
    ifStripOtherBranchEntries.append(
      IfStripOtherBranchEntry(
        sheet: sheet,
        masterA1: masterA1,
        formula: formula,
        rejectCode: rejectCode
      )
    )
  }

  /// `SUMPRODUCT` boolean-product fast path (masked histogram / column snapshots).
  public var sumproductBooleanHits: Int = 0
  /// Boolean-shaped `SUMPRODUCT` that did not use the fast path (parse miss or unsupported shape).
  public var sumproductBooleanFallbacks: Int = 0

  public struct SheetPhaseWalls: Sendable {
    public var name: String
    public var ingestWall: Double
    public var evalWall: Double
    /// CPU time in aggregate index builds during this sheet's eval (Σ attribution, may overlap).
    public var aggIdxCPU: Double
  }

  public var sheetPhaseWalls: [SheetPhaseWalls] = []

  public func recordSheetPhaseWalls(
    name: String, ingestWall: Double, evalWall: Double, aggIdxCPU: Double
  ) {
    sheetPhaseWalls.append(
      SheetPhaseWalls(name: name, ingestWall: ingestWall, evalWall: evalWall, aggIdxCPU: aggIdxCPU)
    )
  }

  public func recordEval(function: String, seconds: Double) {
    evalSeconds += seconds
    evalByFunctionSeconds[function, default: 0] += seconds
  }

  public func mergeFrom(_ other: FormulaRecalcProfile) {
    ingestSeconds += other.ingestSeconds
    ingestParseSeconds += other.ingestParseSeconds
    ingestDependencySeconds += other.ingestDependencySeconds
    ingestFillVerifySeconds += other.ingestFillVerifySeconds
    ingestFillAdjustSeconds += other.ingestFillAdjustSeconds
    ingestShapeKeySeconds += other.ingestShapeKeySeconds
    ingestEntryScanSeconds += other.ingestEntryScanSeconds
    ingestColumnParallelWallSeconds += other.ingestColumnParallelWallSeconds
    ingestGraphBuildSeconds += other.ingestGraphBuildSeconds
    ingestBulkSheetWallPeakSeconds = max(
      ingestBulkSheetWallPeakSeconds,
      other.ingestBulkSheetWallPeakSeconds
    )
    ingestTemplateCacheHits += other.ingestTemplateCacheHits
    shapeStripPlanSeconds += other.shapeStripPlanSeconds
    aggregateIndexBuildSeconds += other.aggregateIndexBuildSeconds
    lookupIndexBuildSeconds += other.lookupIndexBuildSeconds
    evalSeconds += other.evalSeconds
    countifsHistogramLookups += other.countifsHistogramLookups
    countifsHistogramIndexHits += other.countifsHistogramIndexHits
    countifsHistogramIndexBuilds += other.countifsHistogramIndexBuilds
    countifsRowScanCells += other.countifsRowScanCells
    foreignFormulaEvaluations += other.foreignFormulaEvaluations
    ifBlankEqualityFastHits += other.ifBlankEqualityFastHits
    iferrorVlookupFastHits += other.iferrorVlookupFastHits
    ifStripHits += other.ifStripHits
    ifStripVlkNA += other.ifStripVlkNA
    ifStripBranchTree += other.ifStripBranchTree
    ifStripCountifsRows += other.ifStripCountifsRows
    ifStripTextJoinRows += other.ifStripTextJoinRows
    ifStripDupStatusRows += other.ifStripDupStatusRows
    for (reason, count) in other.ifStripPlanMiss {
      ifStripPlanMiss[reason, default: 0] += count
    }
    ifStripOtherBranchEntries.append(contentsOf: other.ifStripOtherBranchEntries)
    sumproductBooleanHits += other.sumproductBooleanHits
    sumproductBooleanFallbacks += other.sumproductBooleanFallbacks
    sheetPhaseWalls.append(contentsOf: other.sheetPhaseWalls)
    for (name, seconds) in other.evalByFunctionSeconds {
      evalByFunctionSeconds[name, default: 0] += seconds
    }
  }

  private func ifStripOtherBranchSummary() -> String {
    guard !ifStripOtherBranchEntries.isEmpty else { return "" }
    let parts = ifStripOtherBranchEntries.map { entry in
      "\(entry.sheet)!\(entry.masterA1):\(entry.rejectCode):\(entry.formula)"
    }
    return " | ob " + parts.joined(separator: ";")
  }

  private func ifStripMissSummary() -> String {
    var parts: [String] = []
    if ifStripVlkNA > 0 { parts.append(String(format: "vlkNA %d", ifStripVlkNA)) }
    if ifStripBranchTree > 0 { parts.append(String(format: "branchTree %d", ifStripBranchTree)) }
    if !ifStripPlanMiss.isEmpty {
      let miss = ifStripPlanMiss.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(
        separator: " ")
      parts.append("planMiss \(miss)")
    }
    guard !parts.isEmpty else { return "" }
    return " | stripFB " + parts.joined(separator: " ") + ifStripOtherBranchSummary()
  }

  private func sheetPhaseWallSummary() -> String {
    guard !sheetPhaseWalls.isEmpty else { return "" }
    let parts = sheetPhaseWalls.map {
      String(
        format: "%@ in%.2f ev%.2f ag%.2f",
        $0.name,
        $0.ingestWall,
        $0.evalWall,
        $0.aggIdxCPU
      )
    }
    return " | sheets " + parts.joined(separator: " ")
  }

  public func detailSummary(totalSeconds: Double) -> String {
    let topEval = evalByFunctionSeconds.sorted { $0.value > $1.value }.prefix(4)
      .map { String(format: "%@ %.2fs", $0.key, $0.value) }
      .joined(separator: ", ")
    return String(
      format:
        "total %.2fs | ingest %.2fs wallPeak %.2fs (parseΣ %.2fs depsΣ %.2fs fillVerifyΣ %.2fs fillAdjustΣ %.2fs shapeKeyΣ %.2fs entryScanΣ %.2fs colWallΣ %.2fs graphΣ %.2fs tmplHit %d) shapePlan %.2fs | aggIdx %.2fs lookupIdx %.2fs eval %.2fs | COUNTIFS hit %d idxHit %d idxBuild %d scanCells %d foreignEval %d | sumProdBool hit %d fallback %d | ifBlank %d | iferrVlk %d | ifStripHit %d cntifsStrip %d textJoinStrip %d dupStrip %d | eval %@",
      totalSeconds,
      ingestSeconds,
      ingestBulkSheetWallPeakSeconds,
      ingestParseSeconds,
      ingestDependencySeconds,
      ingestFillVerifySeconds,
      ingestFillAdjustSeconds,
      ingestShapeKeySeconds,
      ingestEntryScanSeconds,
      ingestColumnParallelWallSeconds,
      ingestGraphBuildSeconds,
      ingestTemplateCacheHits,
      shapeStripPlanSeconds,
      aggregateIndexBuildSeconds,
      lookupIndexBuildSeconds,
      evalSeconds,
      countifsHistogramLookups,
      countifsHistogramIndexHits,
      countifsHistogramIndexBuilds,
      countifsRowScanCells,
      foreignFormulaEvaluations,
      sumproductBooleanHits,
      sumproductBooleanFallbacks,
      ifBlankEqualityFastHits,
      iferrorVlookupFastHits,
      ifStripHits,
      ifStripCountifsRows,
      ifStripTextJoinRows,
      ifStripDupStatusRows,
      topEval.isEmpty ? "—" : topEval
    ) + ifStripMissSummary() + sheetPhaseWallSummary()
  }
}
