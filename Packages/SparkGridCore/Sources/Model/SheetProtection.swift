import CryptoKit
import Foundation

/// A sheet's `<sheetProtection>` element: whether it is on, and its password if it has one.
/// Like other spreadsheet apps' sheet protection, this stops mistakes, not a determined reader.
public nonisolated enum SheetProtection {
  /// True when the element turns protection on (`sheet="1"`).
  public static func isOn(_ xml: String?) -> Bool {
    guard let xml else { return false }
    return attribute("sheet", in: xml).map { $0 == "1" || $0 == "true" } ?? false
  }

  public static func hasPassword(_ xml: String?) -> Bool {
    guard let xml else { return false }
    return attribute("password", in: xml) != nil || attribute("hashValue", in: xml) != nil
  }

  /// Whether `password` unlocks the element. With no password set, anything does.
  public static func verify(_ password: String, against xml: String?) -> Bool {
    guard let xml, hasPassword(xml) else { return true }
    if let legacy = attribute("password", in: xml) {
      return legacy.uppercased() == legacyHash(password)
    }
    guard let algorithm = attribute("algorithmName", in: xml),
      let hashValue = attribute("hashValue", in: xml),
      let saltText = attribute("saltValue", in: xml), let salt = Data(base64Encoded: saltText),
      let spin = attribute("spinCount", in: xml).flatMap({ Int($0) }), spin >= 0, spin <= 10_000_000
    else { return false }
    guard let computed = iteratedHash(password, salt: salt, spinCount: spin, algorithm: algorithm)
    else { return false }
    return computed.base64EncodedString() == hashValue
  }

  /// Things a protected sheet can still allow. In the file each is an attribute that is "0"
  /// when allowed: `sort="0"` lets anyone sort the protected sheet.
  public enum Permission: String, CaseIterable, Sendable {
    case formatCells, formatColumns, formatRows
    case insertColumns, insertRows, insertHyperlinks
    case deleteColumns, deleteRows
    case sort, autoFilter

    /// The wording other apps use in their Protect Sheet window.
    public var title: String {
      switch self {
      case .formatCells: "Format cells"
      case .formatColumns: "Format columns"
      case .formatRows: "Format rows"
      case .insertColumns: "Insert columns"
      case .insertRows: "Insert rows"
      case .insertHyperlinks: "Insert links"
      case .deleteColumns: "Delete columns"
      case .deleteRows: "Delete rows"
      case .sort: "Sort"
      case .autoFilter: "Use filters"
      }
    }
  }

  /// True when the protection element allows `permission`. With protection off, everything is.
  public static func allows(_ permission: Permission, in xml: String?) -> Bool {
    guard isOn(xml), let xml else { return true }
    return attribute(permission.rawValue, in: xml).map { $0 == "0" || $0 == "false" } ?? false
  }

  /// What the element allows.
  public static func permissions(in xml: String?) -> Set<Permission> {
    Set(Permission.allCases.filter { allows($0, in: xml) })
  }

  /// The element for protecting a sheet, with the password hashed the way older files store it,
  /// which every app that reads these files understands.
  public static func element(password: String?, allowing: Set<Permission> = []) -> String {
    var xml = "<sheetProtection"
    if let password, !password.isEmpty {
      xml += #" password="\#(legacyHash(password))""#
    }
    xml += #" sheet="1" objects="1" scenarios="1""#
    // Written in the schema's attribute order.
    for permission in Permission.allCases where allowing.contains(permission) {
      xml += #" \#(permission.rawValue)="0""#
    }
    return xml + "/>"
  }

  /// The 16-bit hash in the `password` attribute, as four hex digits.
  public static func legacyHash(_ password: String) -> String {
    // Each character's low byte, as the original algorithm reads them.
    let bytes = password.utf16.map { Int($0 & 0xFF) }
    var hash = 0
    for byte in bytes.reversed() {
      hash = ((hash >> 14) & 0x01) | ((hash << 1) & 0x7FFF)
      hash ^= byte
    }
    hash = ((hash >> 14) & 0x01) | ((hash << 1) & 0x7FFF)
    hash ^= bytes.count
    hash ^= 0xCE4B
    return String(format: "%04X", hash)
  }

  /// SHA-2 over the salt and the UTF-16 password, then over each result and a 4-byte counter.
  static func iteratedHash(_ password: String, salt: Data, spinCount: Int, algorithm: String)
    -> Data?
  {
    let digest: (Data) -> Data
    switch algorithm.uppercased() {
    case "SHA-512": digest = { Data(SHA512.hash(data: $0)) }
    case "SHA-384": digest = { Data(SHA384.hash(data: $0)) }
    case "SHA-256": digest = { Data(SHA256.hash(data: $0)) }
    default: return nil
    }
    var utf16 = Data()
    for unit in password.utf16 {
      utf16.append(UInt8(unit & 0xFF))
      utf16.append(UInt8(unit >> 8))
    }
    var hash = digest(salt + utf16)
    for counter in 0..<spinCount {
      var block = hash
      let value = UInt32(counter)
      block.append(UInt8(value & 0xFF))
      block.append(UInt8((value >> 8) & 0xFF))
      block.append(UInt8((value >> 16) & 0xFF))
      block.append(UInt8(value >> 24))
      hash = digest(block)
    }
    return hash
  }

  static func attribute(_ name: String, in xml: String) -> String? {
    guard let range = xml.range(of: #"\b\#(name)="([^"]*)""#, options: .regularExpression) else {
      return nil
    }
    let match = xml[range]
    guard let open = match.firstIndex(of: "\"") else { return nil }
    return String(match[match.index(after: open)..<match.index(before: match.endIndex)])
  }
}
