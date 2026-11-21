struct LibraryColumns {
  enum Pane: Int, CaseIterable {
    case artist, album, song

    var title: String {
      switch self {
      case .artist: "Artist"
      case .album: "Game"
      case .song: "Song"
      }
    }
  }

  private var all: [LibraryTrack] = []
  private var artistTracks: [LibraryTrack] = []
  private(set) var artists: [LibraryHierarchy.GroupRow] = []
  private(set) var albums: [LibraryHierarchy.GroupRow] = []
  private(set) var songs: [LibraryTrack] = []
  private(set) var focus = Pane.artist
  private var artist = 0
  private var album = 0
  private var song = 0

  var selectedArtist: LibraryGroup? { artist > 0 ? artists[artist - 1].group : nil }
  var selectedAlbum: LibraryGroup? { album > 0 ? albums[album - 1].group : nil }

  var selectedSong: LibraryTrack? { songs.indices.contains(song) ? songs[song] : nil }

  func count(_ pane: Pane) -> Int {
    switch pane {
    case .artist: artists.count + 1
    case .album: albums.count + 1
    case .song: songs.count
    }
  }

  func selection(_ pane: Pane) -> Int? {
    switch pane {
    case .artist: artist
    case .album: album
    case .song: selectedSong == nil ? nil : song
    }
  }

  mutating func load(_ tracks: [LibraryTrack]) {
    let previousArtist = selectedArtist
    let previousAlbum = selectedAlbum
    let previousSong = selectedSong?.path
    all = tracks
    artists = LibraryHierarchy.groupRows(by: .artist, in: tracks)
    if let previousArtist, let index = artists.firstIndex(where: { $0.group == previousArtist }) {
      artist = index + 1
    } else {
      artist = 0
    }
    updateAlbums(keeping: previousAlbum)
    if let previousSong, let index = songs.firstIndex(where: { $0.path == previousSong }) {
      song = index
    }
  }

  mutating func focusBy(_ offset: Int, wrap: Bool = false) {
    let count = Pane.allCases.count
    let position = focus.rawValue + offset
    let result = wrap ? (position + count) % count : min(count - 1, max(0, position))
    focus = Pane(rawValue: result) ?? .artist
  }

  mutating func move(_ offset: Int) {
    let current = selection(focus) ?? 0
    let next = max(0, min(count(focus) - 1, current + offset))
    guard next != current else { return }
    switch focus {
    case .artist:
      artist = next
      updateAlbums(keeping: nil)
    case .album:
      album = next
      updateSongs()
    case .song:
      song = next
    }
  }

  private mutating func updateAlbums(keeping previous: LibraryGroup?) {
    if let selectedArtist {
      artistTracks = all.filter { selectedArtist.contains($0) }
    } else {
      artistTracks = all
    }
    albums = LibraryHierarchy.groupRows(by: .game, in: artistTracks)
    if let previous, let index = albums.firstIndex(where: { $0.group == previous }) {
      album = index + 1
    } else {
      album = 0
    }
    updateSongs()
  }

  private mutating func updateSongs() {
    if let selectedAlbum {
      songs = artistTracks.filter { selectedAlbum.contains($0) }.sortedInPackOrder()
    } else {
      songs = artistTracks
    }
    song = 0
  }
}
