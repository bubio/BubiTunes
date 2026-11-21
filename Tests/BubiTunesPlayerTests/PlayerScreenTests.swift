import Testing
@testable import BubiTunesPlayer

@Test func deckFitsDisplayCellsAndKeepsQueueVisibleOnResize() {
  let title = "長いゲーム音楽タイトル" + String(repeating: "🎵", count: 80)
  var screen = PlayerScreen(
    now: .init(title: title, detail: "主題曲 / Composer", state: "Playing", position: "1:23",
               duration: "3:45", progress: 0.37, volume: 80, looping: true, spectrum: .silent,
               activity: .ssg),
    listTitle: "Playback queue", entryCount: 30,
    entry: { .init(name: "\($0 + 1)  " + title, detail: "") }, selection: 18, chooser: false,
    emptyMessage: "No tracks", prompt: nil, notice: nil, help: nil
  )
  for (columns, rows) in [(104, 28), (80, 12), (44, 18), (28, 11), (13, 5)] {
    let frame = screen.render(columns: columns, rows: rows, color: false)
    let lines = frame.split(separator: "\n", omittingEmptySubsequences: false)
    #expect(lines.count <= rows)
    #expect(lines.allSatisfy { terminalCellWidth(String($0)) <= columns })
    if rows >= 11 { #expect(frame.contains("› 19")) }
    if rows >= 20 { #expect(frame.contains("Spectrum / OPNA")) }
  }
  screen.now.repeatMode = .one
  let modes = screen.render(columns: 80, rows: 24, color: false)
  #expect(modes.contains("Playing"))
  #expect(modes.contains("LOOP ×1"))
  #expect(modes.contains("Repeat one"))
  #expect(screen.render(columns: 100, rows: 24, color: true).contains("\u{1B}["))
  #expect(!screen.render(columns: 100, rows: 24, color: false).contains("\u{1B}"))
}

@Test func threePaneLibraryStacksSongsBelowFiltersAndFitsCompactTerminals() throws {
  let screen = PlayerScreen(
    now: .init(title: "OPNA", detail: "", state: "Stopped", position: "0:00", duration: "0:00",
               progress: 0, volume: 80, looping: false, spectrum: nil, activity: []),
    listTitle: "Library", entryCount: 0, entry: { _ in .init(name: "", detail: "") },
    selection: nil, chooser: true, emptyMessage: "No tracks", prompt: nil, notice: nil, help: nil,
    columns: [
      .init(title: "Artist", count: 1, selected: 0, focused: false) { _ in "作曲者" },
      .init(title: "Game", count: 1, selected: 0, focused: false) { _ in "ゲーム" },
      .init(title: "Song", count: 1, selected: 0, focused: true) { _ in "曲" },
    ], columnContext: "作曲者 / ゲーム"
  )
  let wide = screen.render(columns: 100, rows: 26, color: false)
  let lines = wide.split(separator: "\n")
  let filters = try #require(lines.firstIndex { $0.contains("Artist") && $0.contains("Game") })
  let songs = try #require(lines.firstIndex { $0.hasPrefix("╭─ ▸ Song") })
  #expect(filters < songs)
  #expect(terminalCellWidth(String(lines[songs])) == 100)
  let compact = screen.render(columns: 52, rows: 18, color: false)
  #expect(compact.contains("作曲者 / ゲーム"))
  #expect(compact.contains("▸ Song"))
  #expect(compact.contains("› 曲"))
  #expect(!compact.contains("╭─ Artist"))
  for (width, height) in [(100, 26), (80, 12), (58, 18), (52, 18), (22, 12)] {
    let rendered = screen.render(columns: width, rows: height, color: false)
    #expect(rendered.split(separator: "\n").allSatisfy { terminalCellWidth(String($0)) <= width })
  }
}
