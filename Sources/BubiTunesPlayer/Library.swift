import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

struct PlaybackPreferences: Codable, Equatable {
  var volume: Float = 0.8
  var repeatMode = QueueRepeatMode.off
  var spectrumVisible = true
}

struct SavedQueue: Codable, Equatable {
  let paths: [String]
  let index: Int
  let frame: Int?
  let shuffled: Bool
}

struct Library: Codable {
  var folders: [String] = []
  var favorites: [String] = []
  var history: [String] = []
  // Preserve data from older versions when writing the library back to disk.
  private var playlists: [String: [String]]?
  var playbackPreferences: PlaybackPreferences?
  var playbackQueue: SavedQueue?

  mutating func addFolder(_ path: String) {
    if !folders.contains(path) { folders.append(path) }
  }

  mutating func toggleFavorite(_ path: String) {
    if let index = favorites.firstIndex(of: path) {
      favorites.remove(at: index)
    } else {
      favorites.insert(path, at: 0)
    }
  }

  mutating func recordPlay(_ path: String) {
    history.removeAll { $0 == path }
    history.insert(path, at: 0)
    if history.count > 200 { history.removeLast(history.count - 200) }
  }
}

struct LibraryStore {
  let directory: URL

  init(directory: URL? = nil) throws {
    if let directory {
      self.directory = directory
    } else if let custom = ProcessInfo.processInfo.environment["BUBITUNES_LIBRARY_DIR"],
              !custom.isEmpty {
      self.directory = URL(fileURLWithPath: custom, isDirectory: true)
    } else {
      let manager = FileManager.default
      let support = try manager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: true)
      self.directory = support.appendingPathComponent("BubiTunes", isDirectory: true)
    }
  }

  private var file: URL { directory.appendingPathComponent("library.json") }

  func read() throws -> Library {
    do {
      return try JSONDecoder().decode(Library.self, from: Data(contentsOf: file))
    } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
      return Library()
    }
  }

  func update(_ change: (inout Library) throws -> Void) throws -> Library {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    #if canImport(Darwin) || canImport(Glibc)
    let descriptor = open(directory.appendingPathComponent("library.lock").path, O_CREAT | O_RDWR, 0o600)
    guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    defer { close(descriptor) }
    while flock(descriptor, LOCK_EX) != 0 {
      if errno != EINTR { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
    #endif
    var library = try read()
    try change(&library)
    try JSONEncoder().encode(library).write(to: file, options: .atomic)
    return library
  }
}

struct LibraryTrack: Sendable {
  let path: String
  let filename: String
  let title: String
  let detail: String
  let game: String
  let artist: String
  let gameNames: [String]
  let keywords: [String]

  init(url: URL, metadata: VGMMetadata? = nil) {
    path = url.path
    filename = url.lastPathComponent
    title = metadata?.title ?? filename
    let tags = metadata?.tags ?? []
    game = metadata?.game.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    gameNames = tags.dropFirst(2).prefix(2).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    artist = metadata?.artist.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    detail = [game, artist].filter { !$0.isEmpty }.joined(separator: " — ")
    keywords = Array(tags.prefix(8)) + [url.path, title]
  }

  func matches(_ query: String) -> Bool {
    query.split(whereSeparator: \.isWhitespace).allSatisfy { word in
      keywords.contains {
        $0.range(of: word, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]) != nil
      }
    }
  }

  static func scan(_ folders: [String]) -> [LibraryTrack] {
    let manager = FileManager.default
    var tracks: [LibraryTrack] = []
    var visited: Set<String> = []
    for folder in folders {
      guard let entries = manager.enumerator(
        at: URL(fileURLWithPath: folder), includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles, .skipsPackageDescendants]
      ) else { continue }
      for case let url as URL in entries {
        guard ["vgm", "vgz"].contains(url.pathExtension.lowercased()),
              visited.insert(url.standardizedFileURL.path).inserted,
              let metadata = try? VGMMetadata.read(url) else { continue }
        tracks.append(LibraryTrack(url: url, metadata: metadata))
      }
    }
    return tracks.sorted {
      let order = $0.title.localizedStandardCompare($1.title)
      return order == .orderedSame ? $0.path < $1.path : order == .orderedAscending
    }
  }
}

extension Array where Element == LibraryTrack {
  func sortedInPackOrder() -> [LibraryTrack] {
    sorted {
      let order = $0.filename.localizedStandardCompare($1.filename)
      return order == .orderedSame ? $0.path < $1.path : order == .orderedAscending
    }
  }
}
