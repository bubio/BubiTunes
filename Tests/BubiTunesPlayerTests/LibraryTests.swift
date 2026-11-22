import Foundation
import Testing
@testable import BubiTunesPlayer

@Test func libraryPersistsFoldersFavoritesAndHistory() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = try LibraryStore(directory: directory)
  #expect(try store.read().folders.isEmpty)
  _ = try store.update {
    $0.addFolder("/Music")
    $0.addFolder("/Music")
    $0.toggleFavorite("/Music/song.vgm")
    $0.recordPlay("/Music/song.vgm")
    $0.recordPlay("/Music/other.vgz")
    $0.recordPlay("/Music/song.vgm")
  }

  let loaded = try store.read()
  #expect(loaded.folders == ["/Music"])
  #expect(loaded.favorites == ["/Music/song.vgm"])
  #expect(loaded.history == ["/Music/song.vgm", "/Music/other.vgz"])
  #expect(try store.update { $0.toggleFavorite("/Music/song.vgm") }.favorites.isEmpty)
}

@Test func librarySearchMatchesJapaneseAndEnglishGD3Fields() {
  let metadata = VGMMetadata(filename: "song.vgm",
                             tags: ["Theme", "主題曲", "Game", "ゲーム", "", "", "Composer", "作曲者"])
  let track = LibraryTrack(url: URL(fileURLWithPath: "/Music/song.vgm"), metadata: metadata)
  #expect(track.gameNames == ["Game", "ゲーム"])
  #expect(track.matches("主題曲 ゲーム 作曲者"))
  #expect(track.matches("theme COMPOSER"))
  #expect(track.matches("song.vgm"))
  #expect(!track.matches("other"))
}

@Test func libraryStoreDoesNotReplaceUnreadableData() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let file = directory.appendingPathComponent("library.json")
  let corrupt = Data("invalid".utf8)
  try corrupt.write(to: file)
  #expect(throws: DecodingError.self) { try storeUpdate(directory: directory) }
  #expect(try Data(contentsOf: file) == corrupt)
}

private func storeUpdate(directory: URL) throws {
  _ = try LibraryStore(directory: directory).update { $0.folders.append("/Music") }
}

@Test func libraryHierarchyGroupsByGameOrArtistAndPreservesUntaggedTracks() {
  func track(_ filename: String, _ game: String, _ artist: String) -> LibraryTrack {
    LibraryTrack(url: URL(fileURLWithPath: "/Music/" + filename),
                 metadata: VGMMetadata(filename: filename, tags: ["", "", game, "", "", "", artist]))
  }
  let tracks = [
    track("opening.vgm", "Game A", "作曲者"),
    track("ending.vgm", "Game A", "作曲者"),
    track("battle.vgz", "Game B", "作曲者"),
    track("untagged.vgm", "", ""),
  ]
  var hierarchy = LibraryHierarchy(grouping: .games)
  let games = hierarchy.groups(in: tracks) ?? []
  #expect(games.map(\.group.title) == ["Game A", "Game B", "Unknown game"])
  #expect(games.map(\.trackCount) == [2, 1, 1])
  hierarchy.trail = [.init(field: .game, name: nil)]
  #expect(hierarchy.tracks(in: tracks).map(\.title) == ["untagged.vgm"])

  hierarchy = LibraryHierarchy(grouping: .artists)
  #expect(hierarchy.groups(in: tracks)?.map(\.group.title) == ["作曲者", "Unknown artist"])
  hierarchy.trail = [.init(field: .artist, name: "作曲者")]
  #expect(hierarchy.groups(in: tracks)?.map(\.group.title) == ["Game A", "Game B"])
  hierarchy.trail.append(.init(field: .game, name: "Game B"))
  #expect(hierarchy.groups(in: tracks) == nil)
  #expect(hierarchy.tracks(in: tracks).map(\.title) == ["battle.vgz"])
}

@Test func libraryColumnsFilterTheDependentPanesAndPreserveSelectionsOnReload() {
  func track(_ title: String, _ game: String, _ author: String) -> LibraryTrack {
    LibraryTrack(url: URL(fileURLWithPath: "/Music/" + title + ".vgm"),
                 metadata: VGMMetadata(filename: title, tags: [title, "", game, "", "", "", author]))
  }
  let tracks = [
    track("Opening", "Game A", "Amy"),
    track("Battle", "Game B", "Amy"),
    track("Ending", "Game A", "Ben"),
    track("Untagged", "", ""),
  ]
  var columns = LibraryColumns()
  columns.load(tracks)
  #expect(columns.songs.count == 4)
  #expect(columns.count(.artist) == 4)
  columns.move(1)
  #expect(columns.selectedArtist?.title == "Amy")
  #expect(columns.albums.map(\.group.title) == ["Game A", "Game B"])
  columns.focusBy(1)
  columns.move(2)
  #expect(columns.songs.map(\.title) == ["Battle"])
  columns.focusBy(1)
  #expect(columns.selectedSong?.title == "Battle")

  columns.load(Array(tracks.reversed()))
  #expect(columns.selectedArtist?.title == "Amy")
  #expect(columns.selectedAlbum?.title == "Game B")
  #expect(columns.selectedSong?.title == "Battle")

  columns.focusBy(1, wrap: true)
  columns.move(-1)
  #expect(columns.focus == .artist)
  #expect(columns.selectedAlbum == nil)
  #expect(columns.songs.count == 4)
  columns.move(3)
  #expect(columns.selectedArtist?.title == "Unknown artist")
  #expect(columns.songs.map(\.title) == ["Untagged"])
}

@Test func selectedGameUsesNaturalFilenamesWhileKeepingGD3Titles() {
  func track(_ filename: String, title: String) -> LibraryTrack {
    LibraryTrack(url: URL(fileURLWithPath: "/Music/" + filename),
                 metadata: VGMMetadata(filename: filename, tags: [title, "", "Pack Game"]))
  }
  // The index is in GD3 title order, deliberately different from pack order.
  let indexed = [
    track("02 Battle.vgz", title: "Alpha"),
    track("10 Ending.vgm", title: "Beta"),
    track("01 Opening.vgm", title: "Zulu"),
  ]
  var columns = LibraryColumns()
  columns.load(indexed)
  #expect(columns.songs.map(\.title) == ["Alpha", "Beta", "Zulu"])
  columns.focusBy(1)
  columns.move(1)
  #expect(columns.songs.map(\.title) == ["Zulu", "Alpha", "Beta"])

  let hierarchy = LibraryHierarchy(grouping: .games, trail: [.init(field: .game, name: "Pack Game")])
  #expect(hierarchy.tracks(in: indexed).map(\.filename) == ["01 Opening.vgm", "02 Battle.vgz", "10 Ending.vgm"])

  let numeric = [track("Song 10.vgm", title: "First"), track("Song 2.vgm", title: "Second")]
  #expect(numeric.sortedInPackOrder().map(\.filename) == ["Song 2.vgm", "Song 10.vgm"])
}

@Test func playbackStatePersistsAlongsideAnExistingLibrary() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let oldLibrary = #"{"folders":["/Music"],"favorites":[],"history":[],"playlists":{"Mix":["/Music/first.vgm"]}}"#
  try Data(oldLibrary.utf8).write(to: directory.appendingPathComponent("library.json"))
  let store = try LibraryStore(directory: directory)
  let before = try store.read()
  #expect(before.playbackPreferences == nil)
  #expect(before.playbackQueue == nil)
  let preferences = PlaybackPreferences(volume: 0.35, repeatMode: .all, spectrumVisible: false)
  let queue = SavedQueue(paths: ["/Music/second.vgz", "/Music/first.vgm"],
                         index: 1, frame: 66_150, shuffled: true)
  _ = try store.update {
    $0.playbackPreferences = preferences
    $0.playbackQueue = queue
  }
  let after = try store.update { $0.toggleFavorite("/Music/first.vgm") }
  #expect(after.folders == ["/Music"])
  #expect(after.playbackPreferences == preferences)
  #expect(after.playbackQueue?.paths == queue.paths)
  #expect(after.playbackQueue?.index == 1)
  #expect(after.playbackQueue?.frame == 66_150)
  #expect(after.playbackQueue?.shuffled == true)
  let json = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("library.json")))
  let legacyPlaylists = (json as? [String: Any])?["playlists"] as? [String: [String]]
  #expect(legacyPlaylists == ["Mix": ["/Music/first.vgm"]])
}
