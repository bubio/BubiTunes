import Foundation

struct Spectrum: Sendable {
  private static let size = 2048
  private static let window = (0..<size).map {
    Float(0.5 - 0.5 * cos(2 * Double.pi * Double($0) / Double(size - 1)))
  }
  private static let edges = [1, 3, 5, 8, 13, 21, 34, 55, 89, 144, 233, 377, size / 2]
  private static let rotation = (0..<(size / 2)).map { offset in
    let angle = -2 * Double.pi * Double(offset) / Double(size)
    return (Float(cos(angle)), Float(sin(angle)))
  }
  private static let reversed = (0..<size).map { index in
    var result = 0
    var bits = index
    for _ in 0..<size.trailingZeroBitCount {
      result = (result << 1) | (bits & 1)
      bits >>= 1
    }
    return result
  }

  static let silent = Spectrum(bands: Array(repeating: 0, count: edges.count - 1), left: 0, right: 0)
  let bands: [Float]
  let left: Float
  let right: Float

  static func analyze(_ pcm: [Float]) -> Self {
    let frames = min(size, pcm.count / 2)
    guard frames > 0 else { return silent }

    var left: Float = 0
    var right: Float = 0
    for frame in 0..<frames {
      left = max(left, abs(pcm[2 * frame]))
      right = max(right, abs(pcm[2 * frame + 1]))
    }
    guard max(left, right) > 0 else { return silent }

    // Analyze each side to preserve energy for stereo signals with opposite phase.
    let leftPower = power(pcm, channel: 0, frames: frames)
    let rightPower = power(pcm, channel: 1, frames: frames)
    let bands = zip(edges, edges.dropFirst()).map { begin, end in
      let peak = (begin..<end).reduce(Float.zero) { max($0, leftPower[$1], rightPower[$1]) }
      return sqrt(peak) * 4 / Float(size)
    }
    return Spectrum(bands: bands, left: left, right: right)
  }

  static func level(_ amplitude: Float) -> Int {
    guard amplitude > 0 else { return 0 }
    let dB = 20 * log10(amplitude)
    return Int(min(8, max(0, (dB + 60) / 7.5)))
  }

  private static func power(_ pcm: [Float], channel: Int, frames: Int) -> [Float] {
    var real = [Float](repeating: 0, count: size)
    var imaginary = real
    for frame in 0..<frames {
      real[reversed[frame]] = pcm[frame * 2 + channel] * window[frame]
    }

    var width = 2
    while width <= size {
      let half = width / 2
      let step = size / width
      for begin in stride(from: 0, to: size, by: width) {
        for offset in 0..<half {
          let low = begin + offset
          let high = low + half
          let (cosine, sine) = rotation[offset * step]
          let re = real[high] * cosine - imaginary[high] * sine
          let im = real[high] * sine + imaginary[high] * cosine
          real[high] = real[low] - re
          imaginary[high] = imaginary[low] - im
          real[low] += re
          imaginary[low] += im
        }
      }
      width *= 2
    }
    return (0..<(size / 2)).map { real[$0] * real[$0] + imaginary[$0] * imaginary[$0] }
  }
}

/// Scales the displayed frequency bands against a slowly decaying track peak.
struct SpectrumDisplayScale {
  private static let minimumReference: Float = 0.063 // About -24 dBFS.
  private static let halfLifeFrames = 6 * 44_100
  private var reference = minimumReference

  mutating func apply(to spectrum: Spectrum, frames: Int) -> Spectrum {
    let decay = Float(pow(0.5, Double(frames) / Double(Self.halfLifeFrames)))
    let peak = spectrum.bands.max() ?? 0
    reference = max(Self.minimumReference, peak, reference * decay)
    return Spectrum(bands: spectrum.bands.map { $0 / reference },
                    left: spectrum.left, right: spectrum.right)
  }
}
