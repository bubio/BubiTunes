import Foundation

public enum BubiTunes {
  public static func run(
    arguments: [String],
    makeSynth: (Int) throws -> any OPNASynthesizer
  ) -> Int32 {
    if arguments.isEmpty || arguments.first == "--help" || arguments.first == "-h" {
      print("Usage: bubitunes [--] FILE.vgm [FILE.vgz ...]")
      return arguments.isEmpty ? 2 : 0
    }
    let files = arguments.first == "--" ? Array(arguments.dropFirst()) : arguments
    guard !files.isEmpty else { return 2 }

    #if os(macOS)
    do {
      return try play(files: files, makeSynth: makeSynth)
    } catch {
      FileHandle.standardError.write(Data((clean(error.localizedDescription) + "\n").utf8))
      return 1
    }
    #else
    print("BubiTunes audio output currently requires macOS.")
    return 1
    #endif
  }

  private static func clean(_ text: String) -> String {
    String(String.UnicodeScalarView(text.unicodeScalars.filter {
      $0.properties.generalCategory != .control && $0.properties.generalCategory != .format
    }))
  }

  #if os(macOS)
  private static func play(
    files: [String],
    makeSynth: (Int) throws -> any OPNASynthesizer
  ) throws -> Int32 {
    let terminal = try Terminal()
    let urls = files.map { URL(fileURLWithPath: $0) }
    var index = 0
    var volume: Float = 0.8
    var failures: [String] = []
    defer {
      terminal.restore()
      if !failures.isEmpty {
        FileHandle.standardError.write(Data((failures.joined(separator: "\n") + "\n").utf8))
      }
    }
    var started = false

    while urls.indices.contains(index) && !terminal.shouldQuit {
      let current = index
      let url = urls[current]
      let track: VGM
      let audio: MacPlayback
      do {
        guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
          throw VGMError.invalid("expected a regular file")
        }
        let file = try FileHandle(forReadingFrom: url)
        let data = try file.read(upToCount: VGMInput.maximumBytes + 1) ?? Data()
        track = try VGM(data: data, filename: url.lastPathComponent)
        audio = try MacPlayback(track: track, synth: makeSynth(track.clock))
        try audio.refill()
      } catch {
        failures.append(clean(url.lastPathComponent + " — " + error.localizedDescription))
        index += 1
        continue
      }

      started = true
      audio.volume = volume
      audio.play()
      var paused = false
      var changedTrack = false
      while !terminal.shouldQuit {
        try audio.refill()
        if audio.finished { break }
        terminal.draw(screen(track: track, audio: audio, paused: paused, index: index,
                             urls: urls, error: failures.last, rows: terminal.rows))
        for key in terminal.keys() {
          switch key {
          case 3, 4, 113: return 0
          case 32:
            paused.toggle()
            if paused { audio.pause() } else { audio.play() }
          case 110: index += 1; changedTrack = true
          case 112: index = max(0, index - 1); changedTrack = true
          case 43, 61: volume = min(1, volume + 0.05)
          case 45: volume = max(0, volume - 0.05)
          default: continue
          }
          audio.volume = volume
          if key == 110 || key == 112 { break }
        }
        if changedTrack { break }
        Thread.sleep(forTimeInterval: 0.05)
      }
      if !changedTrack && audio.finished { index += 1 }
    }
    return started || terminal.shouldQuit ? 0 : 1
  }

  private static func screen(
    track: VGM, audio: MacPlayback, paused: Bool, index: Int, urls: [URL],
    error: String?, rows: Int
  ) -> String {
    func time(_ frames: Int) -> String {
      let seconds = frames / 44_100
      return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    let state = paused ? "Paused" : "Playing"
    var lines = ["BubiTunes  \(state)  \(time(audio.played)) / \(time(track.duration))  Vol \(Int(audio.volume * 100))%"]
    lines.append(clean(track.title + (track.artist.isEmpty ? "" : " — " + track.artist)))
    lines.append("Space play/pause   ←/p previous   →/n next   +/- volume   q quit")
    if let error { lines.append(error) }
    let available = max(0, rows - lines.count)
    let start = max(0, min(index - available / 2, urls.count - available))
    for position in start..<min(urls.count, start + available) {
      let marker = position == index ? ">" : " "
      lines.append("\(marker) \(position + 1)  \(clean(urls[position].lastPathComponent))")
    }
    return lines.prefix(rows).joined(separator: "\n")
  }
  #endif
}
