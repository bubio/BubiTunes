import Bubilator88Core
import BubiTunesPlayer
import Foundation

private final class CoreOPNA: OPNASynthesizer {
  let renderer: YM2608Renderer

  init(clock: Int) throws {
    renderer = try YM2608Renderer(clockHz: clock)
    #if os(macOS)
    try loadRhythm()
    #endif
  }

  func write(secondary: Bool, register: UInt8, value: UInt8) {
    renderer.write(port: secondary ? .secondary : .primary, register: register, value: value)
  }

  func loadADPCM(_ bytes: [UInt8], at offset: Int) throws {
    try renderer.loadADPCM(bytes, at: offset)
  }

  func render(frames: Int) -> [Float] {
    renderer.render(frames: frames)
  }
}

#if os(macOS)
import AVFoundation

extension CoreOPNA {
  private func loadRhythm() throws {
    let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    let directory = executable.deletingLastPathComponent()
    let candidates = [
      directory.appendingPathComponent("BubiTunesRhythm"),
      directory.deletingLastPathComponent().appendingPathComponent("Resources"),
      URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("BubiTunesRhythm"),
    ]
    for (index, name) in ["BD", "SD", "TOP", "HH", "TOM", "RIM"].enumerated() {
      let filename = "Rhythm_\(name).wav"
      guard let url = candidates.map({ $0.appendingPathComponent(filename) }).first(where: {
        FileManager.default.fileExists(atPath: $0.path)
      }) else {
        throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: filename])
      }
      let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatInt16, interleaved: false)
      guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                          frameCapacity: AVAudioFrameCount(file.length)) else {
        throw CocoaError(.fileReadCorruptFile)
      }
      try file.read(into: buffer)
      guard let samples = buffer.int16ChannelData?[0] else { throw CocoaError(.fileReadCorruptFile) }
      try renderer.loadRhythmSample(index: index,
                                    samples: Array(UnsafeBufferPointer(start: samples, count: Int(buffer.frameLength))),
                                    sampleRate: Int(buffer.format.sampleRate))
    }
  }
}
#endif

exit(BubiTunes.run(arguments: Array(CommandLine.arguments.dropFirst())) { try CoreOPNA(clock: $0) })
