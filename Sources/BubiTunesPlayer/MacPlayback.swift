#if os(macOS)
import AVFoundation
import Foundation
import Synchronization

private final class PlayCounters: Sendable {
  struct State {
    var pending = 0
    var played = 0
    var spectrum = Spectrum.silent
    var activity: OPNAActivity = []
  }

  let state = Mutex(State())
}

final class MacPlayback {
  private let engine = AVAudioEngine()
  private let node = AVAudioPlayerNode()
  private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
  private let counters = PlayCounters()
  private let startFrame: Int
  private var playback: Playback
  private var spectrumScale = SpectrumDisplayScale()
  private var exhausted = false

  var played: Int { startFrame + counters.state.withLock { $0.played } }
  var visual: (spectrum: Spectrum, activity: OPNAActivity) {
    counters.state.withLock {
      let visual = ($0.spectrum, $0.activity)
      $0.activity = []
      return visual
    }
  }

  var finished: Bool { exhausted && counters.state.withLock { $0.pending == 0 } }

  var volume: Float {
    get { node.volume }
    set { node.volume = newValue }
  }

  init(track: VGM, synth: any OPNASynthesizer, startFrame: Int,
       shouldCancel: () -> Bool) throws {
    self.startFrame = startFrame
    playback = Playback(track: track, synth: synth)
    try playback.skip(frames: startFrame, shouldCancel: shouldCancel)
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
      let samples = try playback.render(upTo: Playback.bufferFrames)
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
      let spectrum = spectrumScale.apply(to: Spectrum.analyze(samples), frames: frames)
      let activity = playback.activity
      counters.state.withLock { $0.pending += 1 }
      node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [counters] _ in
        counters.state.withLock {
          $0.pending -= 1
          $0.played += frames
          $0.spectrum = spectrum
          $0.activity.formUnion(activity)
        }
      }
    }
  }
}
#endif
