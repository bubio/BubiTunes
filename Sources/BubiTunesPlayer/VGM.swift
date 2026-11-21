import Foundation

enum VGMError: LocalizedError {
  case invalid(String)
  case unsupported(String)

  var errorDescription: String? {
    switch self {
    case .invalid(let message): "Invalid VGM: \(message)"
    case .unsupported(let message): "Unsupported VGM: \(message)"
    }
  }
}

struct VGM {
  enum Event {
    case write(secondary: Bool, register: UInt8, value: UInt8)
    case wait(Int)
    case adpcm(offset: Int, bytes: [UInt8])
  }

  let clock: Int
  let title: String
  let artist: String
  let events: [Event]
  let loop: Int?
  let duration: Int

  init(data: Data, filename: String) throws {
    let source = try VGMInput.expand(data)
    var reader = Reader(bytes: source, end: source.count)
    guard try reader.u32(at: 0) == 0x206D6756 else { throw VGMError.invalid("missing header") }
    let version = try reader.u32(at: 8)
    guard (0x151...0x171).contains(version) else { throw VGMError.unsupported("version") }
    let end = try reader.offset(at: 4, defaultValue: source.count)
    let start = try reader.offset(at: 0x34, defaultValue: 0x40)
    let gd3 = try reader.offset(at: 0x14, defaultValue: 0)
    let loopOffset = try reader.offset(at: 0x1C, defaultValue: 0)
    guard end <= source.count, start >= 0x4C, start < end,
          gd3 == 0 || (gd3 >= start && gd3 < end) else {
      throw VGMError.invalid("header offsets")
    }
    let masterClock = try reader.u32(at: 0x48)
    guard (44_100...16_000_000).contains(masterClock) else {
      throw VGMError.unsupported("requires one YM2608")
    }
    clock = masterClock

    let chipOffsets = [0x0C, 0x10, 0x2C, 0x30, 0x38, 0x40, 0x44, 0x4C, 0x50, 0x54,
      0x58, 0x5C, 0x60, 0x64, 0x68, 0x6C, 0x70, 0x74, 0x80, 0x84, 0x88, 0x8C,
      0x90, 0x98, 0x9C, 0xA0, 0xA4, 0xA8, 0xAC, 0xB0, 0xB4, 0xB8,
      0xC0, 0xC4, 0xC8, 0xCC, 0xD0, 0xD8, 0xDC, 0xE0]
    let headerEnd = version >= 0x170 && start >= 0xC0
      ? try reader.offset(at: 0xBC, defaultValue: start)
      : start
    guard headerEnd >= min(start, 0xC0), headerEnd <= start else {
      throw VGMError.invalid("extra header offset")
    }
    for offset in chipOffsets where offset + 4 <= headerEnd {
      if try reader.u32(at: offset) != 0 {
        throw VGMError.unsupported("additional sound chip")
      }
    }
    let tags = try Self.tags(reader: reader, start: gd3, end: end)
    title = Self.tag(tags, english: 0, japanese: 1) ?? filename
    artist = Self.tag(tags, english: 6, japanese: 7) ?? ""

    reader.position = start
    reader.end = gd3 == 0 ? end : gd3
    var parsed: [Event] = []
    var samples = 0
    var loopIndex: Int?
    var loopSample = 0
    var ended = false
    while reader.position < reader.end {
      if reader.position == loopOffset {
        loopIndex = parsed.count
        loopSample = samples
      }
      let command = try reader.byte()
      var wait: Int?
      switch command {
      case 0x56, 0x57:
        parsed.append(.write(secondary: command == 0x57, register: try reader.byte(), value: try reader.byte()))
      case 0x61:
        wait = try Int(reader.byte()) | Int(reader.byte()) << 8
      case 0x62: wait = 735
      case 0x63: wait = 882
      case 0x70...0x7F: wait = Int(command & 0xF) + 1
      case 0x66: ended = true
      case 0x67:
        guard try reader.byte() == 0x66 else { throw VGMError.invalid("bad data block marker") }
        let kind = try reader.byte()
        guard kind == 0x81 else { throw VGMError.unsupported("data block type \(kind)") }
        let size = try reader.word()
        guard size >= 8, size <= reader.end - reader.position else {
          throw VGMError.invalid("truncated data block")
        }
        let memorySize = try reader.word()
        let offset = try reader.word()
        let count = size - 8
        guard memorySize <= 0x40000, offset <= memorySize, count <= memorySize - offset else {
          throw VGMError.invalid("Delta-T memory range")
        }
        parsed.append(.adpcm(offset: offset, bytes: try reader.take(count)))
      default:
        throw VGMError.unsupported(String(format: "command 0x%02X", command))
      }
      if ended { break }
      if let wait, wait > 0 {
        samples += wait
        parsed.append(.wait(wait))
      }
    }
    guard ended else { throw VGMError.invalid("missing end command") }
    if loopOffset != 0, loopIndex == nil || loopSample == samples {
      throw VGMError.invalid("loop does not address a playable command")
    }
    events = parsed
    loop = loopIndex
    duration = samples + (loopIndex == nil ? 0 : samples - loopSample)
  }

  private static func tags(reader: Reader, start: Int, end: Int) throws -> [String] {
    guard start > 0 else { return [] }
    guard end - start >= 12, try reader.u32(at: start) == 0x20336447 else {
      throw VGMError.invalid("GD3 header")
    }
    let size = try reader.u32(at: start + 8)
    guard size <= end - start - 12, size.isMultiple(of: 2) else {
      throw VGMError.invalid("GD3 length")
    }
    let payload = reader.bytes[(start + 12)..<(start + 12 + size)]
    let text = String(data: Data(payload), encoding: .utf16LittleEndian) ?? ""
    return text.components(separatedBy: "\u{0}")
  }

  private static func tag(_ tags: [String], english: Int, japanese: Int) -> String? {
    [english, japanese].compactMap { index in
      tags.indices.contains(index) && !tags[index].isEmpty ? tags[index] : nil
    }.first
  }
}

private struct Reader {
  let bytes: [UInt8]
  var end: Int
  var position = 0

  func u32(at offset: Int) throws -> Int {
    guard offset >= 0, end - offset >= 4 else { throw VGMError.invalid("truncated integer") }
    return Int(bytes[offset]) | Int(bytes[offset + 1]) << 8
      | Int(bytes[offset + 2]) << 16 | Int(bytes[offset + 3]) << 24
  }

  func offset(at field: Int, defaultValue: Int) throws -> Int {
    let relative = try u32(at: field)
    return relative == 0 ? defaultValue : field + relative
  }

  mutating func byte() throws -> UInt8 {
    guard position < end else { throw VGMError.invalid("truncated command") }
    defer { position += 1 }
    return bytes[position]
  }

  mutating func word() throws -> Int {
    let value = try u32(at: position)
    position += 4
    return value
  }

  mutating func take(_ count: Int) throws -> [UInt8] {
    guard count <= end - position else { throw VGMError.invalid("truncated data block") }
    defer { position += count }
    return Array(bytes[position..<(position + count)])
  }
}
