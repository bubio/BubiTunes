#if os(macOS)
import AVFoundation
import Foundation
import Synchronization

private final class PlayCounters: Sendable {
  let state = Mutex((pending: 0, played: 0))
}

final class MacPlayback {
  private let engine = AVAudioEngine()
  private let node = AVAudioPlayerNode()
  private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
  private let counters = PlayCounters()
  private var playback: Playback
  private var exhausted = false

  var played: Int { counters.state.withLock { $0.played } }
  var finished: Bool { exhausted && counters.state.withLock { $0.pending == 0 } }

  var volume: Float {
    get { node.volume }
    set { node.volume = newValue }
  }

  init(track: VGM, synth: any OPNASynthesizer) throws {
    playback = Playback(track: track, synth: synth)
    engine.attach(node)
    engine.connect(node, to: engine.mainMixerNode, format: format)
    try engine.start()
  }

  deinit {
    node.stop()
    engine.stop()
  }

  func play() { node.play() }
  func pause() { node.pause() }

  func refill() throws {
    while !exhausted && counters.state.withLock({ $0.pending < 4 }) {
      let samples = try playback.render(upTo: 2048)
      guard !samples.isEmpty else {
        exhausted = true
        return
      }
      let frames = samples.count / 2
      guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
            let channels = buffer.floatChannelData else {
        throw CocoaError(.fileWriteOutOfSpace)
      }
      buffer.frameLength = AVAudioFrameCount(frames)
      for frame in 0..<frames {
        channels[0][frame] = samples[frame * 2]
        channels[1][frame] = samples[frame * 2 + 1]
      }
      counters.state.withLock { $0.pending += 1 }
      node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [counters] _ in
        counters.state.withLock {
          $0.pending -= 1
          $0.played += frames
        }
      }
    }
  }
}
#endif
