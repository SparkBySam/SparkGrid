import Foundation

public enum A1Notation {
  public static func columnLabel(for index: Int) -> String {
    guard index >= 0 else { return "" }
    var n = index + 1
    var label = ""
    while n > 0 {
      n -= 1
      let remainder = n % 26
      let scalar = UnicodeScalar(65 + remainder).map { String($0) } ?? ""
      label = scalar + label
      n /= 26
    }
    return label
  }

  public static func columnIndex(from label: String) -> Int? {
    let upper = label.uppercased()
    guard !upper.isEmpty, upper.allSatisfy({ $0.isLetter }) else { return nil }
    var index = 0
    for char in upper {
      guard let scalar = char.asciiValue, scalar >= 65, scalar <= 90 else { return nil }
      index = index * 26 + Int(scalar - 64)
    }
    return index - 1
  }
}
