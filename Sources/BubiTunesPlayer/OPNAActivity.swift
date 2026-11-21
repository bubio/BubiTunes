struct OPNAActivity: OptionSet, Sendable {
  let rawValue: UInt8

  static let fm = Self(rawValue: 1 << 0)
  static let ssg = Self(rawValue: 1 << 1)
  static let rhythm = Self(rawValue: 1 << 2)
  static let adpcm = Self(rawValue: 1 << 3)

  mutating func record(secondary: Bool, register: UInt8) {
    switch (secondary, register) {
    case (false, 0x00...0x0D): insert(.ssg)
    case (false, 0x10...0x1D): insert(.rhythm)
    case (true, 0x00...0x10): insert(.adpcm)
    case (false, 0x28), (_, 0x30...0xB6): insert(.fm)
    default: break
    }
  }
}
