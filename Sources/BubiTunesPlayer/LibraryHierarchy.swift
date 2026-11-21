import Foundation

enum LibraryGrouping: String, CaseIterable {
  case columns, games, artists, tracks

  var title: String { rawValue.capitalized }

  var next: Self {
    switch self {
    case .columns: .games
    case .games: .artists
    case .artists: .tracks
    case .tracks: .columns
    }
  }
}

struct LibraryGroup: Hashable {
  enum Field {
    case game, artist

    func value(in track: LibraryTrack) -> String? {
      let value = self == .game ? track.game : track.artist
      return value.isEmpty ? nil : value
    }
  }

  let field: Field
  let name: String?

  var title: String { name ?? (field == .game ? "Unknown game" : "Unknown artist") }

  func contains(_ track: LibraryTrack) -> Bool { field.value(in: track) == name }
}

struct LibraryHierarchy {
  struct GroupRow {
    let group: LibraryGroup
    let trackCount: Int
  }

  var grouping: LibraryGrouping = .columns
  var trail: [LibraryGroup] = []

  var heading: String { (["Library", grouping.title] + trail.map(\.title)).joined(separator: " / ") }

  private var nextField: LibraryGroup.Field? {
    switch (grouping, trail.count) {
    case (.games, 0): .game
    case (.artists, 0): .artist
    case (.artists, 1): .game
    default: nil
    }
  }

  func tracks(in tracks: [LibraryTrack]) -> [LibraryTrack] {
    guard !trail.isEmpty else { return tracks }
    let matches = tracks.filter { track in trail.allSatisfy { $0.contains(track) } }
    return trail.contains { $0.field == .game } ? matches.sortedInPackOrder() : matches
  }

  func groups(in tracks: [LibraryTrack]) -> [GroupRow]? {
    guard let field = nextField else { return nil }
    return Self.groupRows(by: field, in: self.tracks(in: tracks))
  }

  static func groupRows(by field: LibraryGroup.Field, in tracks: [LibraryTrack]) -> [GroupRow] {
    let counts = tracks.reduce(into: [LibraryGroup: Int]()) { counts, track in
      counts[LibraryGroup(field: field, name: field.value(in: track)), default: 0] += 1
    }
    return counts.map { GroupRow(group: $0.key, trackCount: $0.value) }.sorted { left, right in
      if (left.group.name == nil) != (right.group.name == nil) { return left.group.name != nil }
      let order = left.group.title.localizedStandardCompare(right.group.title)
      return order == .orderedSame ? left.group.title < right.group.title : order == .orderedAscending
    }
  }
}
