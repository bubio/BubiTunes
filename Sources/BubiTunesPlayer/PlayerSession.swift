import Foundation

final class PlayerSession {
  private struct Playing {
    let track: VGM
    let audio: PlatformPlayback
    var paused = false
  }

  private let terminal: Terminal
  private let browser: LibraryBrowser
  private let makeSynth: (Int) throws -> any OPNASynthesizer
  private var queue: [String] = []
  private var index = 0
  private var resumeFrame: Int?
  private var shuffledQueue = false
  private var playing: Playing?
  private let originalPreferences: PlaybackPreferences
  private var preferences: PlaybackPreferences
  private var failures: [String] = []
  private var started = false
  private var keepOpen: Bool
  private var activityUntil = [0, 0, 0, 0]
  private var slashFromQueue = false
  private var commandHelp = false
  private let queueAtLaunch: SavedQueue?

  private static let parts: [OPNAActivity] = [.fm, .ssg, .rhythm, .adpcm]

  init(paths: [String], makeSynth: @escaping (Int) throws -> any OPNASynthesizer) throws {
    self.makeSynth = makeSynth
    var folders: [String] = []
    for path in paths {
      let url = URL(fileURLWithPath: path).standardizedFileURL
      if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
        folders.append(url.path)
      } else {
        queue.append(url.path)
      }
    }
    keepOpen = queue.isEmpty || !folders.isEmpty
    terminal = try Terminal()
    browser = try LibraryBrowser(folders: folders)
    originalPreferences = browser.playbackPreferences
    preferences = originalPreferences
    preferences.volume = min(1, max(0, preferences.volume))
    if queue.isEmpty {
      if let saved = browser.savedQueue {
        queue = saved.paths
        index = min(max(0, saved.index), queue.count)
        shuffledQueue = saved.shuffled
        if queue.indices.contains(index) { resumeFrame = max(0, saved.frame ?? 0) }
      }
      queueAtLaunch = SavedQueue(paths: queue, index: index, frame: resumeFrame, shuffled: shuffledQueue)
    } else {
      queueAtLaunch = nil
    }
    if keepOpen { browser.open(.library) }
  }

  func run() throws -> Int32 {
    defer {
      playing?.audio.pause()
      let saved = SavedQueue(paths: queue, index: index,
                             frame: playing?.audio.played ?? resumeFrame, shuffled: shuffledQueue)
      do {
        try browser.savePlayback(queue: saved == queueAtLaunch ? nil : saved, preferences: preferences,
                                 originalPreferences: originalPreferences)
      } catch {
        failures.append(terminalText("Could not save playback state — " + error.localizedDescription))
      }
      terminal.restore()
      if !failures.isEmpty {
        FileHandle.standardError.write(Data((failures.joined(separator: "\n") + "\n").utf8))
      }
    }

    while !terminal.shouldQuit {
      browser.refresh()
      if playing == nil { startNextTrack() }
      if terminal.shouldQuit { break }
      if let playing {
        try playing.audio.refill()
        if playing.audio.finished {
          advance(trackFinished: true)
          continue
        }
      } else if !keepOpen {
        return started ? 0 : 1
      }
      terminal.draw(screen())
      for key in terminal.keys() {
        if handle(key) { return 0 }
      }
      Thread.sleep(forTimeInterval: 0.05)
    }
    return 0
  }

  private func advance(trackFinished: Bool = false) {
    resumeFrame = nil
    playing = nil
    index = preferences.repeatMode.nextIndex(after: index, count: queue.count, trackFinished: trackFinished)
  }

  private func startNextTrack() {
    for _ in queue.indices {
      guard queue.indices.contains(index) else { return }
      let url = URL(fileURLWithPath: queue[index])
      do {
        let track = try VGM(data: VGMInput.read(url), filename: url.lastPathComponent)
        guard track.duration > 0 else { throw VGMError.invalid("track has no audio frames") }
        let frame = resumeFrame ?? 0
        let startFrame = frame < track.duration ? frame : 0
        let paused = resumeFrame != nil
        let audio = try PlatformPlayback(track: track, synth: makeSynth(track.clock), startFrame: startFrame) {
          terminal.shouldQuit
        }
        try audio.refill()
        audio.volume = preferences.volume
        if !paused { audio.play() }
        activityUntil = [0, 0, 0, 0]
        playing = Playing(track: track, audio: audio, paused: paused)
        resumeFrame = nil
        started = true
        browser.recordPlay(url.path)
        return
      } catch is CancellationError {
        return
      } catch {
        if resumeFrame != nil { resumeFrame = 0 }
        let message = terminalText(url.lastPathComponent + " — " + error.localizedDescription)
        if !failures.contains(message) { failures.append(message) }
        browser.notice = message
        index = preferences.repeatMode.nextIndex(after: index, count: queue.count)
      }
    }
    // Every file failed. Leave the queue exhausted even when queue repeat is on.
    index = queue.count
    resumeFrame = nil
  }

  private func handle(_ key: Terminal.Key) -> Bool {
    switch key {
    case .byte(3), .byte(4): return true
    default: break
    }
    if browser.prompt != nil {
      switch key {
      case .escape:
        let returnToQueue = browser.prompt == .search && slashFromQueue
        browser.stopPrompt()
        if returnToQueue { browser.close() }
      case .byte(9):
        if let command = browser.selectedCompletion {
          browser.complete(command)
        } else if browser.prompt == .search, let path = browser.selectedPath {
          queue.append(path)
        }
      case .byte(10), .byte(13):
        if browser.prompt == .search {
          return submitSlash()
        }
        browser.submit()
      case .up: browser.movePromptSelection(-1)
      case .down: browser.movePromptSelection(1)
      case .byte(let value): browser.type(value)
      default: break
      }
      return false
    }

    if commandHelp {
      commandHelp = false
      switch key {
      case .byte(113): return true
      case .byte(47): openSlash()
      default: break
      }
      return false
    }

    switch key {
    case .byte(113): return true // q
    case .byte(63): commandHelp = true
    case .escape: if !browser.back() { browser.close() }
    case .byte(47): openSlash()
    case .byte(108): show(.library)
    case .byte(103):
      keepOpen = true
      browser.cycleGrouping()
    case .byte(104): show(.history)
    case .byte(70): show(.favorites)
    case .byte(100): keepOpen = true; browser.start(.folder)
    case .byte(114): if browser.view != nil { browser.rescan() }
    case .byte(80):
      browser.toggleQueue()
      if browser.view != nil { keepOpen = true }
    case .byte(83):
      playCollection(browser.view == nil ? queue : browser.collectionPaths, shuffled: true)
    case .byte(82):
      preferences.repeatMode = preferences.repeatMode.next
    case .byte(102):
      if browser.view == nil, playing != nil {
        browser.setFavorite(queue[index])
      } else if let path = browser.selectedPath {
        browser.setFavorite(path)
      }
    case .up, .byte(107): browser.move(-1)
    case .down, .byte(106): browser.move(1)
    case .byte(97):
      if let path = browser.selectedPath { queue.append(path) }
    case .byte(9):
      if browser.showsColumns { browser.moveColumn(1, wrap: true) }
    case .backTab:
      if browser.showsColumns { browser.moveColumn(-1, wrap: true) }
    case .byte(10), .byte(13): if !browser.enterGroup() { playSelection() }
    case .byte(32): setPaused(!(playing?.paused ?? true))
    case .right:
      if browser.view == nil { advance() } else { _ = browser.enterGroup() }
    case .left:
      if browser.view == nil {
        goBack()
      } else if browser.showsColumns {
        browser.moveColumn(-1)
      } else {
        browser.back()
      }
    case .byte(110): advance()
    case .byte(112): goBack()
    case .byte(43), .byte(61): setVolume(preferences.volume + 0.05)
    case .byte(45): setVolume(preferences.volume - 0.05)
    default: break
    }
    return false
  }

  private func openSlash() {
    slashFromQueue = browser.view == nil
    show(.library, preservingView: true)
    browser.start(.search)
  }

  private func submitSlash() -> Bool {
    if let candidate = browser.selectedCompletion {
      if candidate.needsArgument {
        browser.complete(candidate)
        return false
      }
      return runSlash(candidate, argument: "")
    }
    if let parsed = SlashCommand.parse(browser.promptText) {
      if parsed.command.needsArgument, parsed.argument.isEmpty {
        browser.complete(parsed.command)
        return false
      }
      return runSlash(parsed.command, argument: parsed.argument)
    }
    browser.submit()
    playSelection()
    return false
  }

  private func runSlash(_ command: SlashCommand, argument: Substring) -> Bool {
    browser.stopPrompt()
    if slashFromQueue { browser.close() }
    return execute(command, argument: argument)
  }

  private func execute(_ command: SlashCommand, argument: Substring) -> Bool {
    browser.notice = ""
    guard argument.isEmpty || command.argumentHint != nil else {
      browser.notice = "Usage: /\(command.rawValue)"
      return false
    }
    switch command {
    case .help: commandHelp = true
    case .play: play(argument)
    case .shuffle: play(argument, shuffled: true)
    case .repeatMode:
      if argument.isEmpty {
        preferences.repeatMode = preferences.repeatMode.next
      } else if let mode = QueueRepeatMode(rawValue: argument.lowercased()) {
        preferences.repeatMode = mode
      } else {
        browser.notice = "Usage: " + command.usage
      }
    case .pause: setPaused(true)
    case .next: advance()
    case .prev: goBack()
    case .restart:
      if !queue.isEmpty {
        index = min(index, queue.count - 1)
        resumeFrame = nil
        playing = nil
      }
    case .volume:
      if let percent = Int(argument), (0...100).contains(percent) {
        setVolume(Float(percent) / 100)
      } else {
        browser.notice = "Usage: /volume 0–100"
      }
    case .library: show(.library)
    case .browse:
      if let grouping = LibraryGrouping(rawValue: argument.lowercased()) {
        keepOpen = true
        browser.setGrouping(grouping)
      } else {
        browser.notice = "Usage: " + command.usage
      }
    case .favorites: show(.favorites)
    case .history: show(.history)
    case .rescan:
      show(.library)
      browser.rescan()
    case .search:
      show(.library, preservingView: true)
      browser.filter(String(argument))
    case .spectrum:
      switch argument.lowercased() {
      case "on": preferences.spectrumVisible = true
      case "off": preferences.spectrumVisible = false
      case "": preferences.spectrumVisible.toggle()
      default:
        browser.notice = "Usage: /spectrum on|off"
        return false
      }
      browser.notice = preferences.spectrumVisible ? "Spectrum on." : "Spectrum off."
    case .quit: return true
    }
    return false
  }

  private func play(_ argument: Substring, shuffled: Bool = false) {
    let terms = argument.split(maxSplits: 1, whereSeparator: \.isWhitespace)
    switch terms.first?.lowercased() {
    case nil:
      if shuffled {
        playCollection(browser.view == nil ? queue : browser.collectionPaths, shuffled: true)
      } else {
        setPaused(false)
      }
    case "favorites" where terms.count == 1:
      playCollection(browser.favoritePaths, shuffled: shuffled)
    case "library" where terms.count == 1:
      playCollection(browser.allPaths, shuffled: shuffled)
    case "list" where terms.count == 1:
      playCollection(browser.view == nil ? queue : browser.collectionPaths, shuffled: shuffled)
    case "game":
      let name = terms.count == 2 ? String(terms[1]) : ""
      playCollection(browser.pathsForGame(name), shuffled: shuffled,
                     emptyNotice: "No matching game. Open a game or supply its GD3 name.")
    default:
      let command = shuffled ? SlashCommand.shuffle : .play
      browser.notice = "Usage: " + command.usage
    }
  }

  private func playCollection(_ tracks: [String], shuffled: Bool = false,
                              emptyNotice: String = "No tracks in this collection.") {
    guard !tracks.isEmpty else {
      browser.notice = emptyNotice
      return
    }
    startQueue(shuffled ? tracks.shuffled() : tracks, at: 0, shuffled: shuffled)
    browser.close()
  }

  private func startQueue(_ tracks: [String], at position: Int, shuffled: Bool) {
    browser.notice = ""
    queue = tracks
    index = position
    shuffledQueue = shuffled
    resumeFrame = nil
    playing = nil
  }

  private func goBack() {
    if !queue.isEmpty {
      index = preferences.repeatMode.previousIndex(before: index, count: queue.count)
      resumeFrame = nil
      playing = nil
    }
  }

  private func setPaused(_ paused: Bool) {
    guard let active = playing, active.paused != paused else { return }
    playing?.paused = paused
    if paused { active.audio.pause() } else { active.audio.play() }
  }

  private func playSelection() {
    guard let selected = browser.selectedPath else { return }
    let tracks = browser.collectionPaths
    guard let position = tracks.firstIndex(of: selected) else { return }
    startQueue(tracks, at: position, shuffled: false)
  }

  private func show(_ view: LibraryBrowser.View, preservingView: Bool = false) {
    keepOpen = true
    if !preservingView || browser.view == nil { browser.open(view) }
  }

  private func setVolume(_ value: Float) {
    preferences.volume = max(0, min(1, value))
    playing?.audio.volume = preferences.volume
  }

  private func screen() -> String {
    let size = terminal.viewport
    let now = nowPlaying()
    let browsing = browser.view != nil
    let commands = browser.completions
    let listTitle: String
    let entryCount: Int
    let selection: Int?
    let entry: (Int) -> PlayerScreen.Entry
    if !commands.isEmpty {
      listTitle = "Matching commands"
      entryCount = commands.count
      selection = browser.completionIndex
      entry = { .init(name: commands[$0].usage, detail: commands[$0].detail) }
    } else if browsing {
      listTitle = browser.title ?? "Library"
      entryCount = browser.rows.count
      selection = browser.selection
      entry = { position in
        let row = self.browser.rows[position]
        return .init(name: terminalText(row.title), detail: terminalText(row.detail))
      }
    } else {
      listTitle = shuffledQueue ? "Playback queue · Shuffled" : "Playback queue"
      entryCount = queue.count
      selection = queue.indices.contains(index) ? index : nil
      entry = { position in
        let filename = URL(fileURLWithPath: self.queue[position]).lastPathComponent
        return .init(name: "\(position + 1)  " + terminalText(filename), detail: "")
      }
    }

    let notice = browser.notice
    let prompt = browser.prompt.map {
      let value = terminalText(browser.promptText)
      if $0 == .search {
        let hint = browser.argumentHint.map { "   " + $0 } ?? ""
        return value + "▏" + hint
      }
      return $0.rawValue + "  " + value + "▏"
    }
    let help = SlashCommand.helpLines + [
      "l Library   d Register folder   r Rescan   F Favorites",
      "h History   a Add selected song to queue",
      "g Group library   P Queue / browse   S Shuffle   R Repeat",
      "← → or Tab Switch pane   Enter Open or play   Esc Back",
    ]
    return PlayerScreen(
      now: now, listTitle: listTitle,
      entryCount: entryCount, entry: entry, selection: selection, chooser: browsing,
      emptyMessage: browser.scanning ? "Scanning folders…" : "No tracks   /library or d to add a folder",
      prompt: prompt, notice: notice.isEmpty ? nil : terminalText(notice),
      help: commandHelp ? help : nil, completingCommand: !commands.isEmpty,
      browsingLibrary: browser.view == .library,
      columns: browser.showsColumns && commands.isEmpty ? libraryColumns() : [],
      columnContext: libraryContext()
    ).render(columns: size.columns, rows: size.rows, color: terminal.color)
  }

  private func libraryColumns() -> [PlayerScreen.Column] {
    let columns = browser.columns
    return LibraryColumns.Pane.allCases.map { pane in
      .init(title: pane.title, count: columns.count(pane), selected: columns.selection(pane),
            focused: columns.focus == pane) { index in
        switch pane {
        case .artist:
          return index == 0 ? "All artists" : terminalText(columns.artists[index - 1].group.title)
        case .album:
          return index == 0 ? "All games" : terminalText(columns.albums[index - 1].group.title)
        case .song:
          let track = columns.songs[index]
          return (self.browser.isFavorite(track.path) ? "♥ " : "") + terminalText(track.title)
        }
      }
    }
  }

  private func libraryContext() -> String {
    guard browser.showsColumns else { return "" }
    let columns = browser.columns
    let artist = terminalText(columns.selectedArtist?.title ?? "All artists")
    let game = terminalText(columns.selectedAlbum?.title ?? "All games")
    return [artist, game].joined(separator: "  /  ")
  }

  private func nowPlaying() -> PlayerScreen.NowPlaying {
    let volumePercent = Int((preferences.volume * 100).rounded())
    guard let playing else {
      return .init(title: "No track loaded", detail: "", state: "Stopped",
                   position: "0:00", duration: "0:00", progress: 0,
                   volume: volumePercent, looping: false,
                   spectrum: preferences.spectrumVisible ? .silent : nil, activity: [], repeatMode: preferences.repeatMode)
    }
    let visual = playing.audio.visual
    let elapsed = playing.audio.played
    var activity: OPNAActivity = []
    for (index, part) in Self.parts.enumerated() {
      if visual.activity.contains(part) { activityUntil[index] = elapsed + 13_230 }
      if !playing.paused && elapsed < activityUntil[index] { activity.insert(part) }
    }
    let pcm = playing.paused ? Spectrum.silent : visual.spectrum
    let display = Spectrum(bands: pcm.bands, left: pcm.left * preferences.volume, right: pcm.right * preferences.volume)
    let track = playing.track
    let detail = [track.game, track.artist].filter { !$0.isEmpty }.map(terminalText).joined(separator: "  /  ")
    return .init(title: terminalText(track.title), detail: detail, state: playing.paused ? "Paused" : "Playing",
                 position: time(elapsed), duration: time(track.duration),
                 progress: Double(elapsed) / Double(max(1, track.duration)), volume: volumePercent,
                 looping: track.loop != nil, spectrum: preferences.spectrumVisible ? display : nil, activity: activity,
                 repeatMode: preferences.repeatMode)
  }

  private func time(_ frames: Int) -> String {
    let seconds = frames / 44_100
    return String(format: "%d:%02d", seconds / 60, seconds % 60)
  }
}
