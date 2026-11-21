import CZlib
import Foundation

enum VGMInput {
  static let maximumBytes = 16 * 1024 * 1024

  static func read(_ url: URL) throws -> Data {
    guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
      throw VGMError.invalid("expected a regular file")
    }
    let file = try FileHandle(forReadingFrom: url)
    defer { try? file.close() }
    return try file.read(upToCount: maximumBytes + 1) ?? Data()
  }

  static func expand(_ input: Data) throws -> [UInt8] {
    guard input.count <= maximumBytes else { throw VGMError.invalid("file exceeds 16 MiB") }
    guard input.prefix(2).elementsEqual([0x1F, 0x8B]) else { return Array(input) }

    var stream = z_stream()
    guard inflateInit2_(&stream, 31, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
      throw VGMError.invalid("cannot initialize gzip decoder")
    }
    defer { inflateEnd(&stream) }

    return try input.withUnsafeBytes { raw in
      stream.next_in = UnsafeMutablePointer(mutating: raw.bindMemory(to: UInt8.self).baseAddress)
      stream.avail_in = UInt32(raw.count)
      var chunk = [UInt8](repeating: 0, count: 32 * 1024)
      var output: [UInt8] = []
      let chunkSize = chunk.count
      while true {
        let status = chunk.withUnsafeMutableBufferPointer { buffer in
          stream.next_out = buffer.baseAddress
          stream.avail_out = UInt32(buffer.count)
          return inflate(&stream, Z_NO_FLUSH)
        }
        let count = chunkSize - Int(stream.avail_out)
        guard output.count + count <= maximumBytes else {
          throw VGMError.invalid("expanded file exceeds 16 MiB")
        }
        output.append(contentsOf: chunk.prefix(count))
        if status == Z_STREAM_END { return output }
        guard status == Z_OK else { throw VGMError.invalid("corrupt gzip stream") }
      }
    }
  }
}
