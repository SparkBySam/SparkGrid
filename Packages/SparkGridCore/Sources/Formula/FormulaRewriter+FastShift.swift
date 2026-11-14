import Foundation
import GridCore

extension FormulaRewriter {
  /// `shiftForStructure` without parsing: plain cell references and ranges, with or without a
  /// sheet name, have their rows or columns moved in the formula's own bytes. Parsing every
  /// formula took about 10 µs each, 0.7 s for one row deleted on a sheet of 105,000 formulas.
  ///
  /// Nil when the formula holds anything this does not handle the same way as the parser does:
  /// a reference that becomes #REF!, whole rows or columns, tables, arrays, spill references,
  /// error values, names outside ASCII. The caller then parses it. A formula with nothing to
  /// move comes back as it was written; the parser path writes every formula in standard form.
  static func fastShiftForStructure(
    _ raw: String,
    formulaSheetName: String,
    mutatedSheetName: String,
    axis: Axis,
    change: StructureChange
  ) -> String? {
    var shifter = FastShifter(
      raw: raw, formulaSheet: formulaSheetName, mutatedSheet: mutatedSheetName, axis: axis,
      change: change)
    return shifter.run()
  }
}

private struct FastShifter {
  let bytes: [UInt8]
  let mutated: [UInt8]
  let formulaOnMutated: Bool
  let axis: FormulaRewriter.Axis
  let change: FormulaRewriter.StructureChange
  var out: [UInt8] = []

  init(
    raw: String, formulaSheet: String, mutatedSheet: String, axis: FormulaRewriter.Axis,
    change: FormulaRewriter.StructureChange
  ) {
    bytes = Array(raw.utf8)
    mutated = Array(mutatedSheet.utf8)
    formulaOnMutated = formulaSheet.caseInsensitiveCompare(mutatedSheet) == .orderedSame
    self.axis = axis
    self.change = change
    out.reserveCapacity(bytes.count + 8)
  }

  private static let dollar = UInt8(ascii: "$")
  private static let colon = UInt8(ascii: ":")
  private static let bang = UInt8(ascii: "!")
  private static let quote = UInt8(ascii: "'")
  private static let doubleQuote = UInt8(ascii: "\"")

  private func isLetter(_ b: UInt8) -> Bool { (b | 0x20) >= 0x61 && (b | 0x20) <= 0x7A }
  private func isDigit(_ b: UInt8) -> Bool { b >= 0x30 && b <= 0x39 }
  private func isNameByte(_ b: UInt8) -> Bool {
    isLetter(b) || isDigit(b) || b == Self.dollar || b == UInt8(ascii: "_")
      || b == UInt8(ascii: ".")
  }
  private func isRefByte(_ b: UInt8) -> Bool { isLetter(b) || isDigit(b) || b == Self.dollar }

  /// A sheet name, ASCII, compared with the changed sheet's without regard to case.
  private func isMutated(_ name: ArraySlice<UInt8>) -> Bool {
    guard name.count == mutated.count else { return false }
    for (a, b) in zip(name, mutated) where a != b {
      // Only letters match without regard to case.
      guard isLetter(a), isLetter(b), a | 0x20 == b | 0x20 else { return false }
    }
    return true
  }

  /// An address in `bytes[from..<to]`, as `A1Reference.parseAddress` reads one: optional `$`,
  /// letters, optional `$`, digits, nothing else.
  private struct Address {
    var col: Int
    var row: Int
    var absCol: Bool
    var digitsStart: Int
  }

  private func address(_ from: Int, _ to: Int) -> Address? {
    var i = from
    var absCol = false
    if i < to, bytes[i] == Self.dollar {
      absCol = true
      i += 1
    }
    var col = 0
    let lettersStart = i
    while i < to, isLetter(bytes[i]) {
      col = col * 26 + Int((bytes[i] | 0x20) - 0x60)
      i += 1
    }
    // Longer runs are left to the parser.
    guard i > lettersStart, i - lettersStart <= 7 else { return nil }
    if i < to, bytes[i] == Self.dollar { i += 1 }
    let digitsStart = i
    var row = 0
    while i < to, isDigit(bytes[i]) {
      row = row * 10 + Int(bytes[i] - 0x30)
      i += 1
    }
    guard i == to, i > digitsStart, i - digitsStart <= 9, row >= 1 else { return nil }
    return Address(col: col - 1, row: row - 1, absCol: absCol, digitsStart: digitsStart)
  }

  private func nextNonSpaceIsParen(_ from: Int) -> Bool {
    var j = from
    while j < bytes.count, bytes[j] == 0x20 || bytes[j] == 0x09 || bytes[j] == 0x0A { j += 1 }
    return j < bytes.count && bytes[j] == UInt8(ascii: "(")
  }

  /// The position along the axis, moved; nil when a lone cell is deleted.
  private func movedCell(_ position: Int) -> Int? {
    switch change {
    case .insert(let index, let count):
      return position >= index ? position + count : position
    case .delete(let index, let count):
      if position >= index && position < index + count { return nil }
      return position >= index + count ? position - count : position
    }
  }

  /// One address written with its new row or column; the rest as written.
  private mutating func write(_ a: Address, from: Int, to: Int, position: Int) {
    switch axis {
    case .row:
      out.append(contentsOf: bytes[from..<a.digitsStart])
      out.append(contentsOf: String(position + 1).utf8)
    case .column:
      if a.absCol { out.append(Self.dollar) }
      out.append(contentsOf: A1Notation.columnLabel(for: position).utf8)
      // Any `$` before the row, and the row, as written.
      var rowStart = a.digitsStart
      if rowStart > from, bytes[rowStart - 1] == Self.dollar { rowStart -= 1 }
      out.append(contentsOf: bytes[rowStart..<to])
    }
  }

  /// A cell or range at `start`, shifted into `out` when `onSheet`. Returns where it ends, or
  /// nil when it is not one this handles.
  private mutating func reference(at start: Int, onSheet: Bool) -> Int? {
    var j = start
    while j < bytes.count, isRefByte(bytes[j]) { j += 1 }
    guard let first = address(start, j) else { return nil }
    var second: (Address, Int, Int)?
    var end = j
    if j < bytes.count, bytes[j] == Self.colon {
      var k = j + 1
      while k < bytes.count, isRefByte(bytes[k]) { k += 1 }
      // A sheet named on the right too, or a whole row or column: the parser handles it.
      if k < bytes.count, bytes[k] == Self.bang { return nil }
      guard let parsed = address(j + 1, k) else { return nil }
      second = (parsed, j + 1, k)
      end = k
    }
    guard onSheet else {
      out.append(contentsOf: bytes[start..<end])
      return end
    }
    let firstPosition = axis == .row ? first.row : first.col
    guard let (secondAddress, secondStart, secondEnd) = second else {
      guard let moved = movedCell(firstPosition) else { return nil }
      if moved == firstPosition {
        out.append(contentsOf: bytes[start..<end])
      } else {
        write(first, from: start, to: j, position: moved)
      }
      return end
    }
    let secondPosition = axis == .row ? secondAddress.row : secondAddress.col
    var newFirst = firstPosition
    var newSecond = secondPosition
    switch change {
    case .insert:
      newFirst = movedCell(firstPosition) ?? firstPosition
      newSecond = movedCell(secondPosition) ?? secondPosition
    case .delete(let index, let count):
      // As `shiftRange`: #REF! only when every row of the range goes (the parser writes it);
      // otherwise the range shrinks by the deleted rows inside it.
      let low = min(firstPosition, secondPosition)
      let high = max(firstPosition, secondPosition)
      let after = index + count
      if index <= low && after > high { return nil }
      func moved(_ position: Int, isLow: Bool) -> Int {
        if position < index { return position }
        if position >= after { return position - count }
        return isLow ? index : index - 1
      }
      let newLow = moved(low, isLow: true)
      let newHigh = moved(high, isLow: false)
      if firstPosition <= secondPosition {
        newFirst = newLow
        newSecond = newHigh
      } else {
        newFirst = newHigh
        newSecond = newLow
      }
    }
    if newFirst == firstPosition {
      out.append(contentsOf: bytes[start..<j])
    } else {
      write(first, from: start, to: j, position: newFirst)
    }
    out.append(Self.colon)
    if newSecond == secondPosition {
      out.append(contentsOf: bytes[secondStart..<secondEnd])
    } else {
      write(secondAddress, from: secondStart, to: secondEnd, position: newSecond)
    }
    return end
  }

  mutating func run() -> String? {
    var i = 0
    while i < bytes.count, bytes[i] == 0x20 {
      out.append(bytes[i])
      i += 1
    }
    guard i < bytes.count, bytes[i] == UInt8(ascii: "=") else { return nil }
    out.append(bytes[i])
    i += 1

    while i < bytes.count {
      let b = bytes[i]
      if b >= 0x80 { return nil }
      switch b {
      case Self.doubleQuote:
        // Text: copied as written, "" inside it included.
        out.append(b)
        i += 1
        while i < bytes.count {
          out.append(bytes[i])
          if bytes[i] == Self.doubleQuote {
            if i + 1 < bytes.count, bytes[i + 1] == Self.doubleQuote {
              out.append(bytes[i + 1])
              i += 2
              continue
            }
            i += 1
            break
          }
          i += 1
        }
      case UInt8(ascii: "#"), UInt8(ascii: "["), UInt8(ascii: "]"), UInt8(ascii: "{"),
        UInt8(ascii: "}"), UInt8(ascii: "@"):
        return nil
      case Self.quote:
        // A quoted sheet name, then "!" and a reference.
        var j = i + 1
        var name: [UInt8] = []
        var closed = false
        while j < bytes.count {
          if bytes[j] == Self.quote {
            if j + 1 < bytes.count, bytes[j + 1] == Self.quote {
              name.append(Self.quote)
              j += 2
              continue
            }
            closed = true
            j += 1
            break
          }
          if bytes[j] >= 0x80 { return nil }
          name.append(bytes[j])
          j += 1
        }
        guard closed, j < bytes.count, bytes[j] == Self.bang else { return nil }
        out.append(contentsOf: bytes[i...j])
        guard let end = reference(at: j + 1, onSheet: isMutated(name[...])) else { return nil }
        i = end
      case _ where isDigit(b) || b == UInt8(ascii: "."):
        // A number. A row range such as 2:5 goes to the parser.
        var j = i
        while j < bytes.count, isDigit(bytes[j]) || bytes[j] == UInt8(ascii: ".") { j += 1 }
        if j < bytes.count, bytes[j] | 0x20 == UInt8(ascii: "e") {
          var k = j + 1
          if k < bytes.count, bytes[k] == UInt8(ascii: "+") || bytes[k] == UInt8(ascii: "-") {
            k += 1
          }
          if k < bytes.count, isDigit(bytes[k]) {
            j = k
            while j < bytes.count, isDigit(bytes[j]) { j += 1 }
          }
        }
        if j < bytes.count, bytes[j] == Self.colon || isNameByte(bytes[j]) { return nil }
        out.append(contentsOf: bytes[i..<j])
        i = j
      case _ where isLetter(b) || b == Self.dollar || b == UInt8(ascii: "_"):
        var j = i
        var hasDollar = false
        while j < bytes.count, isNameByte(bytes[j]) {
          if bytes[j] == Self.dollar { hasDollar = true }
          j += 1
        }
        if j < bytes.count, bytes[j] == Self.bang {
          // An unquoted sheet name.
          out.append(contentsOf: bytes[i...j])
          guard let end = reference(at: j + 1, onSheet: isMutated(bytes[i..<j])) else { return nil }
          i = end
        } else if address(i, j) != nil, hasDollar || !nextNonSpaceIsParen(j) {
          guard let end = reference(at: i, onSheet: formulaOnMutated) else { return nil }
          i = end
        } else {
          // A function, name or TRUE/FALSE. A column range such as A:C goes to the parser.
          if j < bytes.count, bytes[j] == Self.colon { return nil }
          out.append(contentsOf: bytes[i..<j])
          i = j
        }
      default:
        out.append(b)
        i += 1
      }
    }
    return String(decoding: out, as: UTF8.self)
  }
}
