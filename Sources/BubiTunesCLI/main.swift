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
  /// Loads the substitute OPNA rhythm samples linked into the executable.
  private func loadRhythm() throws {
    for index in 0..<6 {
      var byteCount = 0
      guard let bytes = bubitunes_rhythm_sample(index, &byteCount) else {
        throw CocoaError(.fileNoSuchFile)
      }
      var decoder = ma_decoder()
      var config = ma_decoder_config_init(ma_format_s16, 1, 0)
      let decoderStatus = ma_decoder_init_memory(bytes, byteCount, &config, &decoder)
      guard decoderStatus == MA_SUCCESS else {
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
