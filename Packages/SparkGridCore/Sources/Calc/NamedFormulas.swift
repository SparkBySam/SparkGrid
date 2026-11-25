import Formula
import Foundation
import Model

/// A defined name whose refers-to is a formula, not a fixed range: a constant (`=0.07`), a
/// moving range (`=OFFSET(Data!$A$1,0,0,COUNTA(Data!$A:$A),1)`) or a LAMBDA a sheet calls by
/// name. They were not read at all before 1.7 (#NAME?).
public nonisolated enum NamedFormulas {
  private static let cache = NSCache<NSString, Box>()
  private final class Box {
    let expr: FormulaExpr?
    init(_ expr: FormulaExpr?) { self.expr = expr }
  }

  /// The parsed refers-to of a formula name; nil for a range name or text that does not parse.
  public static func expression(for named: NamedRange) -> FormulaExpr? {
    guard !named.resolvesToRange, let text = named.refersTo else { return nil }
    var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if !trimmed.hasPrefix("=") { trimmed = "=" + trimmed }
    let key = trimmed as NSString
    if let hit = cache.object(forKey: key) { return hit.expr }
    let expr = try? FormulaParser.parse(trimmed)
    cache.setObject(Box(expr), forKey: key)
    return expr
  }
}
