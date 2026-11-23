#if !os(macOS)
import CMinAudio
import Foundation
import Synchronization

/// Chunk queue shared between the session thread (`DevicePlayback.refill`)
/// and the miniaudio data callback running on the audio thread.
///
/// Mirrors the bookkeeping of MacPlayback's AVAudioPlayerNode scheduling:
/// a chunk counts as pending until it has been consumed in full, at which
/// point `played`, `spectrum` and `activity` are updated with its values.
private final class ChunkQueue: Sendable {
  struct Chunk {
    var samples: [Float]
    var spectrum: Spectrum
    var activity: OPNAActivity
  }

  struct State {
    var queue: [Chunk] = []
    var offset = 0 // Frames already consumed from the first queued chunk.
    var played = 0
    var spectrum = Spectrum.silent
    var activity: OPNAActivity = []
    var exhausted = false
  }

  let state = Mutex(State())
}

private func deviceDataCallback(
  _ device: UnsafeMutablePointer<ma_device>?,
  _ output: UnsafeMutableRawPointer?,
  _ input: UnsafeRawPointer?,
  _ frameCount: ma_uint32
) {
  guard let device, let output, let userData = device.pointee.pUserData else { return }
  let chunks = Unmanaged<ChunkQueue>.fromOpaque(userData).takeUnretainedValue()
  let totalFrames = Int(frameCount)
  let out = output.bindMemory(to: Float.self, capacity: totalFrames * 2)
  chunks.state.withLock { state in
    var written = 0
    while written < totalFrames, let chunk = state.queue.first {
      let chunkFrames = chunk.samples.count / 2
      let take = min(chunkFrames - state.offset, totalFrames - written)
      for index in 0..<(take * 2) {
        out[written * 2 + index] = chunk.samples[state.offset * 2 + index]
      }
      state.offset += take
      written += take
      if state.offset == chunkFrames {
        state.queue.removeFirst()
        state.offset = 0
        state.played += chunkFrames
        state.spectrum = chunk.spectrum
        state.activity.formUnion(chunk.activity)
      }
    }
    for index in (written * 2)..<(totalFrames * 2) {
      out[index] = 0
    }
  }
}

/// Audio output backed by miniaudio, used on platforms other than macOS.
/// Exposes the same surface as MacPlayback so PlayerSession can use either
/// through the PlatformPlayback typealias (see PlaybackBackend.swift).
final class DevicePlayback {
  private let chunks = ChunkQueue()
  private let startFrame: Int
  private var playback: Playback
  private var spectrumScale = SpectrumDisplayScale()
  private var device = ma_device()
  private var chunksPointer: UnsafeMutableRawPointer?
  private var storedVolume: Float = 1

  var played: Int { startFrame + chunks.state.withLock { $0.played } }
  var visual: (spectrum: Spectrum, activity: OPNAActivity) {
    chunks.state.withLock {
      let visual = ($0.spectrum, $0.activity)
      $0.activity = []
      return visual
    }
  }

  var finished: Bool {
    chunks.state.withLock { $0.exhausted && $0.queue.isEmpty }
  }

  var volume: Float {
    get { storedVolume }
    set {
      storedVolume = newValue
      ma_device_set_master_volume(&device, newValue)
    }
  }

  init(track: VGM, synth: any OPNASynthesizer, startFrame: Int,
       shouldCancel: () -> Bool) throws {
    self.startFrame = startFrame
    playback = Playback(track: track, synth: synth)
    try playback.skip(frames: startFrame, shouldCancel: shouldCancel)

    var config = ma_device_config_init(ma_device_type_playback)
    config.playback.format = ma_format_f32
    config.playback.channels = 2
    config.sampleRate = 44_100
    config.periodSizeInFrames = ma_uint32(Playback.bufferFrames)
    config.dataCallback = deviceDataCallback
    let pointer = Unmanaged.passRetained(chunks).toOpaque()
    config.pUserData = pointer
    guard ma_device_init(nil, &config, &device) == MA_SUCCESS else {
      Unmanaged<ChunkQueue>.fromOpaque(pointer).release()
      throw VGMError.unsupported("audio output device could not be opened")
    }
    chunksPointer = pointer
  }

  deinit {
    ma_device_stop(&device)
    ma_device_uninit(&device)
    if let chunksPointer {
      Unmanaged<ChunkQueue>.fromOpaque(chunksPointer).release()
    }
  }

  func play() { ma_device_start(&device) }
  func pause() { ma_device_stop(&device) }

  func refill() throws {
    while chunks.state.withLock({ !$0.exhausted && $0.queue.count < 4 }) {
      let samples = try playback.render(upTo: Playback.bufferFrames)
      guard !samples.isEmpty else {
        chunks.state.withLock { $0.exhausted = true }
        return
      }
      let spectrum = spectrumScale.apply(to: Spectrum.analyze(samples), frames: samples.count / 2)
      let activity = playback.activity
      chunks.state.withLock {
        $0.queue.append(ChunkQueue.Chunk(samples: samples, spectrum: spectrum, activity: activity))
      }
    }
  }
}
#endif
