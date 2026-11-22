import Foundation
import Testing
@testable import BubiTunesPlayer

@Test func spectrumShowsTheToneWithoutCancellingOppositeStereoPhase() {
  let pcm = (0..<2048).flatMap { frame -> [Float] in
    let value = Float(sin(Double(frame) * 2 * .pi * 46 / 2048)) * 0.5
    return [value, -value]
  }
  let spectrum = Spectrum.analyze(pcm)
  #expect(spectrum.bands.indices.max { spectrum.bands[$0] < spectrum.bands[$1] } == 6)
  #expect(spectrum.bands[6] > 0.45)
  #expect(spectrum.left == 0.5)
  #expect(spectrum.right == 0.5)
  #expect(Spectrum.analyze([0, 0]).bands.allSatisfy { $0 == 0 })
  #expect(Spectrum.level(0) == 0)
  #expect(Spectrum.level(1) == 8)
}

@Test func opnaActivitySeparatesRegisterBanks() {
  var activity: OPNAActivity = []
  activity.record(secondary: false, register: 0x07)
  #expect(activity == .ssg)
  activity.record(secondary: true, register: 0x07)
  #expect(activity == [.ssg, .adpcm])
  activity.record(secondary: false, register: 0x18)
  activity.record(secondary: true, register: 0xA0)
  #expect(activity == [.ssg, .adpcm, .rhythm, .fm])
}

@Test func slashCommandPreservesOrdinaryLibrarySearch() {
  #expect(SlashCommand.parse("VOLUME 35  ")?.command == .volume)
  #expect(SlashCommand.parse("VOLUME 35  ")?.argument == "35")
  #expect(SlashCommand.parse("pause")?.argument.isEmpty == true)
  #expect(SlashCommand.parse("曲名") == nil)
  #expect(SlashCommand.parse("composer name") == nil)
}

@Test func slashSuggestionsNarrowIncrementallyAndPromoteTheExactCommand() {
  #expect(SlashCommand.matches("").count == SlashCommand.allCases.count)
  #expect(SlashCommand.matches("p") == [.pause, .play, .prev])
  #expect(SlashCommand.matches("PLAY") == [.play])
  #expect(SlashCommand.matches("vol") == [.volume])
  #expect(SlashCommand.matches("volume ").isEmpty)
  #expect(SlashCommand.matches("曲").isEmpty)
  #expect(SlashCommand.volume.needsArgument)
}

@Test func spectrumDisplayScaleHighlightsOrdinaryPeaksAndPreservesStereoMeters() {
  var scale = SpectrumDisplayScale()
  let strong = Spectrum(bands: [0.12, 0.03], left: 0.24, right: 0.18)
  let loud = scale.apply(to: strong, frames: 2048)
  #expect(Spectrum.level(loud.bands[0]) == 8)
  #expect(loud.bands[1] == 0.25)
  #expect(loud.left == strong.left)
  #expect(loud.right == strong.right)

  let quiet = Spectrum(bands: [0.03, 0.005], left: 0.06, right: 0.05)
  let afterPeak = scale.apply(to: quiet, frames: 44_100)
  #expect(Spectrum.level(afterPeak.bands[0]) < 8)
  #expect(scale.apply(to: .silent, frames: 44_100).bands.allSatisfy { $0 == 0 })

  let afterSilence = scale.apply(to: quiet, frames: 6 * 44_100)
  #expect(afterSilence.bands[0] > afterPeak.bands[0])
  #expect(Spectrum.level(afterSilence.bands[0]) < 8)
}
