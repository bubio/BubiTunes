public protocol OPNASynthesizer: AnyObject {
  func write(secondary: Bool, register: UInt8, value: UInt8)
  func loadADPCM(_ bytes: [UInt8], at offset: Int) throws
  func render(frames: Int) -> [Float]
}

struct Playback {
  let track: VGM
  let synth: any OPNASynthesizer
  private var cursor = 0
  private var waiting = 0
  private var repeated = false

  init(track: VGM, synth: any OPNASynthesizer) {
    self.track = track
    self.synth = synth
  }

  mutating func render(upTo limit: Int) throws -> [Float] {
    var pcm: [Float] = []
    pcm.reserveCapacity(limit * 2)
    while pcm.count < limit * 2 {
      if waiting > 0 {
        let frames = min(waiting, limit - pcm.count / 2)
        pcm += synth.render(frames: frames)
        waiting -= frames
        continue
      }
      if cursor == track.events.count {
        guard !repeated, let loop = track.loop else { break }
        cursor = loop
        repeated = true
      }
      let event = track.events[cursor]
      cursor += 1
      switch event {
      case .wait(let frames): waiting = frames
      case .write(let secondary, let register, let value):
        synth.write(secondary: secondary, register: register, value: value)
      case .adpcm(let offset, let bytes): try synth.loadADPCM(bytes, at: offset)
      }
    }
    return pcm
  }
}
