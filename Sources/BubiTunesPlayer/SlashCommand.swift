import Foundation

enum SlashCommand: String, CaseIterable {
  case help, play, pause, next, prev, restart, volume, shuffle
  case repeatMode = "repeat"
  case library, browse, favorites, history, rescan, search, spectrum, quit

  static func parse(_ input: String) -> (command: Self, argument: Substring)? {
    let parts = input.trimmingCharacters(in: .whitespacesAndNewlines)
      .split(maxSplits: 1, whereSeparator: \.isWhitespace)
    guard let name = parts.first, let command = Self(rawValue: name.lowercased()) else { return nil }
    return (command, parts.count == 2 ? parts[1] : "")
  }

  static func matches(_ input: String) -> [Self] {
    guard !input.contains(where: \.isWhitespace) else { return [] }
    let prefix = input.lowercased()
    guard !prefix.isEmpty else { return allCases }
    return allCases.filter { $0.rawValue.hasPrefix(prefix) }.sorted { left, right in
      if left.rawValue == prefix { return right.rawValue != prefix }
      if right.rawValue == prefix { return false }
      return left.rawValue < right.rawValue
    }
  }

  var argumentHint: String? {
    switch self {
    case .play, .shuffle: "[list|favorites|library|game [name]]"
    case .repeatMode: "off|one|all"
    case .browse: "columns|games|artists|tracks"
    case .search: "<text>"
    case .volume: "0–100"
    case .spectrum: "on|off"
    default: nil
    }
  }

  var needsArgument: Bool { [.browse, .search, .volume].contains(self) }
  var usage: String { "/" + rawValue + (argumentHint.map { " " + $0 } ?? "") }

  var detail: String {
    switch self {
    case .help: "Show shortcuts"
    case .play: "Resume or play a collection"
    case .shuffle: "Shuffle a collection or the queue"
    case .repeatMode: "Repeat one track or the queue"
    case .pause: "Pause playback"
    case .next: "Play the next track"
    case .prev: "Play the previous track"
    case .restart: "Restart the current track"
    case .volume: "Set volume"
    case .library: "Open the music library"
    case .browse: "Switch library grouping"
    case .favorites: "Open favorites"
    case .history: "Open recently played tracks"
    case .rescan: "Rescan registered folders"
    case .search: "Find tracks by GD3 or filename"
    case .spectrum: "Show or hide the spectrum"
    case .quit: "Quit BubiTunes"
    }
  }

  static let helpLines = [
    "Type after / to narrow commands. ↑↓ select, Tab completes.",
    "/play   /pause   /next   /prev   /restart",
    "/play list / favorites / library / game [name]",
    "/shuffle favorites / library / game [name]",
    "/repeat off|one|all   S Shuffle   R Repeat",
    "/volume 0–100   /spectrum on|off   /quit",
    "/browse columns|games|artists|tracks   /search <text>",
    "/library   /favorites   /history   /rescan",
  ]
}
