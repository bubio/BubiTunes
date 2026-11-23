import Bubilator88Core
import BubiTunesPlayer
import CMinAudio
import Foundation

private final class CoreOPNA: OPNASynthesizer {
  let renderer: YM2608Renderer

  init(clock: Int) throws {
    renderer = try YM2608Renderer(clockHz: clock)
    try loadRhythm()
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

extension CoreOPNA {
  /// Loads the substitute OPNA rhythm samples (BubiTunesRhythm/*.wav) with
  /// miniaudio's decoder, which works on every platform.
  private func loadRhythm() throws {
    let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    let directory = executable.deletingLastPathComponent()
    let candidates = [
      directory.appendingPathComponent("BubiTunesRhythm"),
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
      var decoder = ma_decoder()
      var config = ma_decoder_config_init(ma_format_s16, 1, 0)
      guard ma_decoder_init_file(url.path, &config, &decoder) == MA_SUCCESS else {
        throw CocoaError(.fileReadCorruptFile)
      }
      defer { ma_decoder_uninit(&decoder) }
      var frameCount: ma_uint64 = 0
      guard ma_decoder_get_length_in_pcm_frames(&decoder, &frameCount) == MA_SUCCESS else {
        throw CocoaError(.fileReadCorruptFile)
      }
      var samples = [Int16](repeating: 0, count: Int(frameCount))
      var framesRead: ma_uint64 = 0
      let status = samples.withUnsafeMutableBufferPointer { buffer in
        ma_decoder_read_pcm_frames(&decoder, buffer.baseAddress, frameCount, &framesRead)
      }
      guard status == MA_SUCCESS || status == MA_AT_END else {
        throw CocoaError(.fileReadCorruptFile)
      }
      samples.removeLast(samples.count - Int(framesRead))
      try renderer.loadRhythmSample(index: index, samples: samples,
                                    sampleRate: Int(decoder.outputSampleRate))
    }
  }
}

exit(BubiTunes.run(arguments: Array(CommandLine.arguments.dropFirst())) { try CoreOPNA(clock: $0) })
