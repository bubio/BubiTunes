import Foundation
import Testing
@testable import BubiTunesPlayer

private func vgm(_ commands: [UInt8], loop: Int? = nil) -> Data {
  var bytes = Data(repeating: 0, count: 0x80)
  func write(_ value: UInt32, at offset: Int) {
    bytes.replaceSubrange(offset..<offset + 4, with: withUnsafeBytes(of: value.littleEndian, Array.init))
  }
  write(0x206D6756, at: 0)
  write(UInt32(0x80 + commands.count - 4), at: 4)
  write(0x171, at: 8)
  write(0x80 - 0x34, at: 0x34)
  write(8_000_000, at: 0x48)
  if let loop { write(UInt32(0x80 + loop - 0x1C), at: 0x1C) }
  bytes.append(contentsOf: commands)
  return bytes
}

@Test func playbackUsesSampleWaitsAndPreservesLoopState() throws {
  let data = vgm([0x56, 7, 0x3E, 0x71, 0x57, 0, 4, 0x72, 0x66], loop: 4)
  let track = try VGM(data: data, filename: "demo.vgm")
  #expect(track.title == "demo.vgm")
  #expect(track.duration == 8)
  let synth = TestSynth()
  var playback = Playback(track: track, synth: synth)
  #expect(try playback.render(upTo: 4) == [1, 1, 1, 1, 2, 2, 2, 2])
  #expect(try playback.render(upTo: 10) == [2, 2, 3, 3, 3, 3, 3, 3])
  #expect(try playback.render(upTo: 10).isEmpty)
}

@Test func validatesEventAndLoopBounds() throws {
  #expect(throws: VGMError.self) { try VGM(data: vgm([0x56, 7]), filename: "broken") }
  #expect(throws: VGMError.self) { try VGM(data: vgm([0x56, 7, 0, 0x66], loop: 1), filename: "broken") }
  #expect(throws: VGMError.self) { try VGM(data: vgm([0x52, 0, 0, 0x66]), filename: "wrong chip") }
  #expect(throws: VGMError.self) {
    try VGM(data: vgm([0x67, 0x66, 0x81, 8, 0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0, 0x66]), filename: "bad ROM")
  }
}

private final class TestSynth: OPNASynthesizer {
  var writes: Float = 0
  func write(secondary: Bool, register: UInt8, value: UInt8) { writes += 1 }
  func loadADPCM(_ bytes: [UInt8], at offset: Int) throws {}
  func render(frames: Int) -> [Float] { Array(repeating: writes, count: frames * 2) }
}

@Test func gzipAndVGMGenerateIdenticalOutput() throws {
  let compressed = try #require(Data(base64Encoded: "H4sIAAAAAAAA/wtLz1VoZGBgKGRkIBr4YBMUqiLeACQQxm5XmAYAiqApcIUAAAA="))
  let raw = vgm([0x56, 7, 0x3E, 0x71, 0x66])
  var a = Playback(track: try VGM(data: raw, filename: "song"), synth: TestSynth())
  var b = Playback(track: try VGM(data: compressed, filename: "song"), synth: TestSynth())
  #expect(try a.render(upTo: 100) == b.render(upTo: 100))
  #expect(throws: VGMError.self) {
    try VGM(data: compressed.dropLast(), filename: "truncated")
  }
}

@Test func gd3UsesEnglishThenJapanese() throws {
  var data = vgm([0x70, 0x66])
  func bytes(_ word: UInt32) -> [UInt8] { withUnsafeBytes(of: word.littleEndian, Array.init) }
  let text = ["", "曲名", "", "", "", "", "Artist", "作者", "", "", ""].joined(separator: "\u{0}")
  let tags = try #require(text.data(using: .utf16LittleEndian))
  data.replaceSubrange(0x14..<0x18, with: bytes(UInt32(data.count - 0x14)))
  data.append(contentsOf: [0x47, 0x64, 0x33, 0x20])
  data.append(contentsOf: bytes(0x100))
  data.append(contentsOf: bytes(UInt32(tags.count)))
  data.append(tags)
  data.replaceSubrange(4..<8, with: bytes(UInt32(data.count - 4)))

  let track = try VGM(data: data, filename: "fallback.vgm")
  #expect(track.title == "曲名")
  #expect(track.artist == "Artist")
}
