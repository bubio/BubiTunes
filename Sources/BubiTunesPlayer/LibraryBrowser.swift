import Dispatch
import Foundation
import Synchronization

final class LibraryBrowser {
  enum View: String {
    case library = "Library"
    case favorites = "Favorites"
    case history = "Recently Played"
  }

  enum Prompt: String {
    case search = "Search"
    case folder = "Add folder"
  }

  struct Row {
    let title: String
    let detail: String
    var path: String? = nil
    var group: LibraryGroup? = nil
  }

  private struct Location {
    let view: View
    let query: String
    let selection: Int
    let hierarchy: LibraryHierarchy
  }

  private struct Scan: Sendable {
    let id: Int
    let tracks: [LibraryTrack]
  }

  private final class ScanMailbox: Sendable {
    let result = Mutex<Scan?>(nil)
  }

  private let store: LibraryStore
  private let scanner = DispatchQueue(label: "BubiTunes.Library", qos: .utility)
  private let mailbox = ScanMailbox()
  private var scanID = 0
  private var indexed: [LibraryTrack] = []
  private var byPath: [String: LibraryTrack] = [:]
  private var state: Library
  var playbackPreferences: PlaybackPreferences { state.playbackPreferences ?? .init() }
  var savedQueue: SavedQueue? { state.playbackQueue }
  private(set) var scanning = false
  private(set) var rows: [Row] = []
  private(set) var view: View?
  private(set) var prompt: Prompt?
  private(set) var selection = 0
  var notice = ""
  private var input: [UInt8] = []
  private var query = ""
  private var queueReturn: Location?
  private var queryBeforePrompt = ""
  private var selectionBeforePrompt = 0
  private var hierarchy = LibraryHierarchy()
  private(set) var columns = LibraryColumns()
  var showsColumns: Bool { view == .library && hierarchy.grouping == .columns && query.isEmpty }
  private(set) var completionIndex = 0

  var title: String? {
    if view == .library { return query.isEmpty ? hierarchy.heading : "Library / Search" }
    return view?.rawValue
  }
  var completions: [SlashCommand] { prompt == .search ? SlashCommand.matches(promptText) : [] }
  var selectedCompletion: SlashCommand? {
    let candidates = completions
    return candidates.indices.contains(completionIndex) ? candidates[completionIndex] : nil
  }
  var selectedGroup: LibraryGroup? { rows.indices.contains(selection) ? rows[selection].group : nil }
  var argumentHint: String? {
    guard prompt == .search, promptText.contains(where: \.isWhitespace) else { return nil }
    return SlashCommand.parse(promptText)?.command.argumentHint
  }

  var promptText: String { String(decoding: input, as: UTF8.self) }
  var selectedPath: String? {
    if showsColumns {
      return columns.focus == .song ? columns.selectedSong?.path : nil
    }
    return rows.indices.contains(selection) ? rows[selection].path : nil
  }

  func isFavorite(_ path: String) -> Bool { state.favorites.contains(path) }

  init(folders: [String]) throws {
    store = try LibraryStore()
    state = Library()
    do {
      state = try store.read()
      if !folders.isEmpty {
        state = try store.update { library in folders.forEach { library.addFolder($0) } }
      }
    } catch {
      notice = error.localizedDescription
    }
    rescan()
  }

  func open(_ view: View) {
    self.view = view
    if view == .library { hierarchy.trail = [] }
    query = ""
    selection = 0
    rebuildRows()
  }

  func close() {
    view = nil
    prompt = nil
    rows = []
    selection = 0
  }

  func toggleQueue() {
    if let view {
      queueReturn = Location(view: view, query: query, selection: selection, hierarchy: hierarchy)
      close()
    } else if let location = queueReturn {
      queueReturn = nil
      view = location.view
      query = location.query
      selection = location.selection
      hierarchy = location.hierarchy
      rebuildRows()
    } else {
      open(.library)
    }
  }

  func move(_ offset: Int) {
    if showsColumns {
      columns.move(offset)
    } else {
      selection = max(0, min(rows.count - 1, selection + offset))
    }
  }

  func revealTrack(_ path: String) {
    guard view != nil, prompt == nil else { return }
    if showsColumns {
      columns.selectSong(atPath: path)
    } else if let index = rows.firstIndex(where: { $0.path == path }) {
      selection = index
    }
  }

  func moveColumn(_ offset: Int, wrap: Bool = false) {
    columns.focusBy(offset, wrap: wrap)
  }

  var allPaths: [String] { indexed.map(\.path) }
  var favoritePaths: [String] { state.favorites }

  func pathsForGame(_ name: String) -> [String] {
    if !name.isEmpty {
      return indexed.filter { track in
        track.gameNames.contains { $0.localizedCaseInsensitiveCompare(name) == .orderedSame }
      }.sortedInPackOrder().map(\.path)
    }
    let game = showsColumns ? columns.selectedAlbum : selectedGroup.flatMap { $0.field == .game ? $0 : nil }
      ?? hierarchy.trail.last(where: { $0.field == .game })
    guard view == .library, let game else { return [] }
    return indexed.filter { game.contains($0) }.sortedInPackOrder().map(\.path)
  }

  var collectionPaths: [String] {
    switch view {
    case .library where showsColumns: columns.songs.map(\.path)
    case .library where query.isEmpty: hierarchy.tracks(in: indexed).map(\.path)
    case .library, .favorites, .history: rows.compactMap(\.path)
    case nil: []
    }
  }

  func setGrouping(_ grouping: LibraryGrouping) {
    hierarchy = LibraryHierarchy(grouping: grouping)
    open(.library)
  }

  func cycleGrouping() { setGrouping(hierarchy.grouping.next) }

  func enterGroup() -> Bool {
    if showsColumns {
      guard columns.focus != .song else { return false }
      moveColumn(1)
      return true
    }
    guard let selectedGroup else { return false }
    hierarchy.trail.append(selectedGroup)
    filter("")
    return true
  }

  @discardableResult
  func back() -> Bool {
    guard view == .library else { return false }
    if !query.isEmpty {
      filter("")
      return true
    }
    if showsColumns {
      guard columns.focus != .artist else { return false }
      moveColumn(-1)
      return true
    }
    guard let previous = hierarchy.trail.popLast() else { return false }
    rebuildRows()
    selection = rows.firstIndex { $0.group == previous } ?? 0
    return true
  }

  func movePromptSelection(_ offset: Int) {
    let candidates = completions
    if candidates.isEmpty {
      move(offset)
    } else {
      completionIndex = max(0, min(candidates.count - 1, completionIndex + offset))
    }
  }

  func complete(_ command: SlashCommand) {
    let suffix = command.argumentHint == nil ? "" : " "
    input = Array((command.rawValue + suffix).utf8)
    completionIndex = 0
  }

  func start(_ kind: Prompt) {
    notice = ""
    if kind == .search, view == nil { open(.library) }
    queryBeforePrompt = query
    selectionBeforePrompt = selection
    input = []
    completionIndex = 0
    prompt = kind
  }

  func stopPrompt() {
    if prompt == .search {
      filter(queryBeforePrompt)
      selection = min(selectionBeforePrompt, max(0, rows.count - 1))
    }
    prompt = nil
  }

  func type(_ byte: UInt8) {
    switch byte {
    case 8, 127:
      if let text = String(bytes: input, encoding: .utf8) {
        input = Array(text.dropLast().utf8)
      } else {
        _ = input.popLast()
      }
    case 21: input.removeAll()
    case 32...255: if input.count < 4096 { input.append(byte) }
    default: return
    }
    if prompt == .search {
      completionIndex = 0
      if completions.isEmpty && argumentHint == nil { filter(promptText) }
    }
  }

  func filter(_ text: String) {
    query = text
    selection = 0
    rebuildRows()
  }

  func submit() {
    notice = ""
    let kind = prompt
    prompt = nil
    switch kind {
    case .folder:
      let text = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
      let url = URL(fileURLWithPath: (text as NSString).expandingTildeInPath).standardizedFileURL
      guard !text.isEmpty, (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
        notice = "Folder not found."
        return
      }
      if update({ $0.addFolder(url.path) }) {
        open(.library)
        rescan()
      }
    case .search: if promptText != query { filter(promptText) }
    case nil: break
    }
  }

  func setFavorite(_ path: String) {
    if update({ $0.toggleFavorite(path) }) {
      notice = state.favorites.contains(path) ? "Added to favorites." : "Removed from favorites."
    }
  }

  func recordPlay(_ path: String) {
    _ = update { $0.recordPlay(path) }
  }

  func savePlayback(queue: SavedQueue?, preferences: PlaybackPreferences,
                    originalPreferences: PlaybackPreferences) throws {
    guard queue != nil || preferences != originalPreferences else { return }
    _ = try store.update { library in
      var updated = library.playbackPreferences ?? .init()
      if preferences.volume != originalPreferences.volume { updated.volume = preferences.volume }
      if preferences.repeatMode != originalPreferences.repeatMode { updated.repeatMode = preferences.repeatMode }
      if preferences.spectrumVisible != originalPreferences.spectrumVisible {
        updated.spectrumVisible = preferences.spectrumVisible
      }
      library.playbackPreferences = updated
      if let queue { library.playbackQueue = queue }
    }
  }

  func rescan() {
    scanID += 1
    let id = scanID
    let folders = state.folders
    scanning = !folders.isEmpty
    scanner.async { [mailbox] in
      let tracks = LibraryTrack.scan(folders)
      mailbox.result.withLock { $0 = Scan(id: id, tracks: tracks) }
    }
  }

  func refresh(playingPath: String?) {
    let result = mailbox.result.withLock { value in
      let result = value
      value = nil
      return result
    }
    guard let result, result.id == scanID else { return }
    indexed = result.tracks
    columns.load(indexed)
    byPath = Dictionary(uniqueKeysWithValues: indexed.map { ($0.path, $0) })
    scanning = false
    rebuildRows()
    if let playingPath { revealTrack(playingPath) }
  }

  private func update(_ change: (inout Library) throws -> Void) -> Bool {
    do {
      state = try store.update(change)
      if view != nil { rebuildRows() }
      return true
    } catch {
      notice = error.localizedDescription
      return false
    }
  }

  private func rebuildRows() {
    func tracks(_ paths: [String]) -> [LibraryTrack] {
      paths.map { byPath[$0] ?? LibraryTrack(url: URL(fileURLWithPath: $0)) }
    }

    switch view {
    case .library where showsColumns:
      rows = []
    case .library where query.isEmpty:
      if let groups = hierarchy.groups(in: indexed) {
        rows = groups.map { row in
          let label = row.trackCount == 1 ? "1 track" : "\(row.trackCount) tracks"
          return Row(title: "▸ " + row.group.title, detail: label, group: row.group)
        }
      } else {
        rows = trackRows(hierarchy.tracks(in: indexed))
      }
    case nil:
      rows = []
    default:
      let items: [LibraryTrack] = switch view {
      case .library: indexed
      case .favorites: tracks(state.favorites)
      case .history: tracks(state.history)
      default: []
      }
      rows = trackRows(items.filter { query.isEmpty || $0.matches(query) })
    }
    if !showsColumns { move(0) }
  }

  private func trackRows(_ tracks: [LibraryTrack]) -> [Row] {
    let favorites = Set(state.favorites)
    return tracks.map { item in
      let favorite = favorites.contains(item.path) ? "♥ " : ""
      return Row(title: favorite + item.title, detail: item.detail, path: item.path)
    }
  }
}
