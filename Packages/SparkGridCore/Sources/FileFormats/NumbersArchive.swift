import Foundation

/// The objects in a Numbers document: each `.iwa` part is Snappy-compressed chunks holding
/// protobuf archives, and every archive is an object with an identifier, a message type and a
/// payload. Objects point at each other by identifier.
nonisolated struct NumbersArchive {
  struct Object {
    let type: UInt32
    let payload: Data
  }

  enum ReadError: Error {
    case notNumbers
    case damaged(String)
  }

  private(set) var objects: [UInt64: Object] = [:]

  init(parts: [String: Data]) throws {
    let iwa = parts.filter { $0.key.hasSuffix(".iwa") }
    guard !iwa.isEmpty else { throw ReadError.notNumbers }
    for (path, data) in iwa {
      let stream: Data
      do {
        stream = try Self.decompress(data)
      } catch {
        throw ReadError.damaged(path)
      }
      try readArchives(stream, path: path)
    }
  }

  func object(_ id: UInt64) -> Object? { objects[id] }

  func message(_ id: UInt64) -> ProtoMessage? {
    objects[id].map { ProtoMessage($0.payload) }
  }

  /// The identifiers of every object of a message type.
  func ids(ofType type: UInt32) -> [UInt64] {
    objects.filter { $0.value.type == type }.map(\.key).sorted()
  }

  private mutating func readArchives(_ stream: Data, path: String) throws {
    var reader = ProtoReader(stream)
    while !reader.isAtEnd {
      guard let infoLength = reader.varint(), let infoBytes = reader.bytes(Int(infoLength)) else {
        throw ReadError.damaged(path)
      }
      let info = ProtoMessage(infoBytes)
      let identifier = info.varint(1) ?? 0
      for messageInfo in info.messages(2) {
        let length = Int(messageInfo.varint(3) ?? 0)
        guard let payload = reader.bytes(length) else { throw ReadError.damaged(path) }
        // The first message is the object; later ones extend it and are not read here.
        if objects[identifier] == nil {
          objects[identifier] = Object(type: UInt32(messageInfo.varint(1) ?? 0), payload: payload)
        }
      }
    }
  }

  // MARK: IWA chunks and Snappy

  /// An `.iwa` part: chunks of a zero byte, a 3-byte little-endian length and raw Snappy data.
  static func decompress(_ data: Data) throws -> Data {
    let bytes = [UInt8](data)
    var out = [UInt8]()
    out.reserveCapacity(bytes.count * 3)
    var i = 0
    while i < bytes.count {
      guard i + 4 <= bytes.count, bytes[i] == 0 else { throw ReadError.damaged("chunk header") }
      let length = Int(bytes[i + 1]) | Int(bytes[i + 2]) << 8 | Int(bytes[i + 3]) << 16
      i += 4
      guard i + length <= bytes.count else { throw ReadError.damaged("chunk length") }
      try snappyDecompress(bytes[i..<(i + length)], into: &out)
      i += length
    }
    return Data(out)
  }

  /// Raw Snappy (no framing): the uncompressed length, then literals and back-references.
  static func snappyDecompress(_ input: ArraySlice<UInt8>, into out: inout [UInt8]) throws {
    var i = input.startIndex
    var expected = 0
    var shift = 0
    while true {
      guard i < input.endIndex, shift < 35 else { throw ReadError.damaged("snappy length") }
      let byte = input[i]
      i += 1
      expected |= Int(byte & 0x7F) << shift
      if byte & 0x80 == 0 { break }
      shift += 7
    }
    let start = out.count
    // A Numbers part is at most a few hundred megabytes; refuse anything claiming more.
    guard expected <= 400_000_000 else { throw ReadError.damaged("snappy size") }
    out.reserveCapacity(start + expected)
    while i < input.endIndex {
      let tag = input[i]
      i += 1
      switch tag & 0x03 {
      case 0:
        var length = Int(tag >> 2)
        if length >= 60 {
          let count = length - 59
          guard i + count <= input.endIndex else { throw ReadError.damaged("literal") }
          length = 0
          for k in 0..<count { length |= Int(input[i + k]) << (8 * k) }
          i += count
        }
        length += 1
        guard i + length <= input.endIndex else { throw ReadError.damaged("literal") }
        out.append(contentsOf: input[i..<(i + length)])
        i += length
      case 1:
        guard i < input.endIndex else { throw ReadError.damaged("copy") }
        let length = Int((tag >> 2) & 0x07) + 4
        let offset = Int(tag >> 5) << 8 | Int(input[i])
        i += 1
        try copy(offset: offset, length: length, start: start, out: &out)
      case 2:
        guard i + 2 <= input.endIndex else { throw ReadError.damaged("copy") }
        let length = Int(tag >> 2) + 1
        let offset = Int(input[i]) | Int(input[i + 1]) << 8
        i += 2
        try copy(offset: offset, length: length, start: start, out: &out)
      default:
        guard i + 4 <= input.endIndex else { throw ReadError.damaged("copy") }
        let length = Int(tag >> 2) + 1
        let offset =
          Int(input[i]) | Int(input[i + 1]) << 8 | Int(input[i + 2]) << 16 | Int(input[i + 3]) << 24
        i += 4
        try copy(offset: offset, length: length, start: start, out: &out)
      }
    }
    guard out.count - start == expected else { throw ReadError.damaged("snappy total") }
  }

  private static func copy(offset: Int, length: Int, start: Int, out: inout [UInt8]) throws {
    guard offset > 0, out.count - offset >= start else { throw ReadError.damaged("offset") }
    var from = out.count - offset
    // Byte by byte: a copy may overlap what it is writing.
    for _ in 0..<length {
      out.append(out[from])
      from += 1
    }
  }
}

/// A protobuf message read without its schema: each field number's values as they were written.
nonisolated struct ProtoMessage {
  enum Value {
    case varint(UInt64)
    case fixed64(UInt64)
    case bytes(Data)
    case fixed32(UInt32)
  }

  private(set) var fields: [Int: [Value]] = [:]

  init(_ data: Data) {
    var reader = ProtoReader(data)
    while !reader.isAtEnd {
      guard let key = reader.varint() else { break }
      let field = Int(key >> 3)
      let value: Value
      switch key & 0x07 {
      case 0:
        guard let v = reader.varint() else { return }
        value = .varint(v)
      case 1:
        guard let v = reader.fixed64() else { return }
        value = .fixed64(v)
      case 2:
        guard let length = reader.varint(), let bytes = reader.bytes(Int(length)) else { return }
        value = .bytes(bytes)
      case 5:
        guard let v = reader.fixed32() else { return }
        value = .fixed32(v)
      default:
        return
      }
      fields[field, default: []].append(value)
    }
  }

  func has(_ field: Int) -> Bool { fields[field] != nil }

  func varint(_ field: Int) -> UInt64? {
    for value in fields[field] ?? [] {
      if case .varint(let v) = value { return v }
    }
    return nil
  }

  /// Repeated varints, written one by one or packed.
  func varints(_ field: Int) -> [UInt64] {
    var out: [UInt64] = []
    for value in fields[field] ?? [] {
      switch value {
      case .varint(let v): out.append(v)
      case .bytes(let data):
        var reader = ProtoReader(data)
        while !reader.isAtEnd, let v = reader.varint() { out.append(v) }
      default: break
      }
    }
    return out
  }

  func double(_ field: Int) -> Double? {
    for value in fields[field] ?? [] {
      if case .fixed64(let v) = value { return Double(bitPattern: v) }
    }
    return nil
  }

  func float(_ field: Int) -> Float? {
    for value in fields[field] ?? [] {
      if case .fixed32(let v) = value { return Float(bitPattern: v) }
    }
    return nil
  }

  /// Repeated floats, written one by one.
  func floats(_ field: Int) -> [Float] {
    (fields[field] ?? []).compactMap {
      if case .fixed32(let v) = $0 { return Float(bitPattern: v) }
      return nil
    }
  }

  func data(_ field: Int) -> Data? {
    for value in fields[field] ?? [] {
      if case .bytes(let d) = value { return d }
    }
    return nil
  }

  func string(_ field: Int) -> String? {
    data(field).map { String(decoding: $0, as: UTF8.self) }
  }

  func message(_ field: Int) -> ProtoMessage? {
    data(field).map(ProtoMessage.init)
  }

  func messages(_ field: Int) -> [ProtoMessage] {
    (fields[field] ?? []).compactMap {
      if case .bytes(let d) = $0 { return ProtoMessage(d) }
      return nil
    }
  }

  /// A `TSP.Reference`: a message whose field 1 is an object identifier.
  func reference(_ field: Int) -> UInt64? {
    message(field)?.varint(1)
  }

  func references(_ field: Int) -> [UInt64] {
    messages(field).compactMap { $0.varint(1) }
  }
}

nonisolated struct ProtoReader {
  private let bytes: [UInt8]
  private var index = 0

  init(_ data: Data) { bytes = [UInt8](data) }

  var isAtEnd: Bool { index >= bytes.count }

  mutating func varint() -> UInt64? {
    var result: UInt64 = 0
    var shift: UInt64 = 0
    while index < bytes.count, shift < 64 {
      let byte = bytes[index]
      index += 1
      result |= UInt64(byte & 0x7F) << shift
      if byte & 0x80 == 0 { return result }
      shift += 7
    }
    return nil
  }

  mutating func fixed64() -> UInt64? {
    guard index + 8 <= bytes.count else { return nil }
    var v: UInt64 = 0
    for k in 0..<8 { v |= UInt64(bytes[index + k]) << (8 * UInt64(k)) }
    index += 8
    return v
  }

  mutating func fixed32() -> UInt32? {
    guard index + 4 <= bytes.count else { return nil }
    var v: UInt32 = 0
    for k in 0..<4 { v |= UInt32(bytes[index + k]) << (8 * UInt32(k)) }
    index += 4
    return v
  }

  mutating func bytes(_ count: Int) -> Data? {
    guard count >= 0, index + count <= bytes.count else { return nil }
    defer { index += count }
    return Data(bytes[index..<(index + count)])
  }
}
