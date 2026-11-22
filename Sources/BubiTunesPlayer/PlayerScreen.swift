import Foundation

struct PlayerScreen {
  struct NowPlaying {
    var title: String
    var detail: String
    var state: String
    var position: String
    var duration: String
    var progress: Double
    var volume: Int
    var looping: Bool
    var spectrum: Spectrum?
    var activity: OPNAActivity
    var repeatMode: QueueRepeatMode = .off
  }

  struct Entry {
    let name: String
    let detail: String
  }

  struct Column {
    let title: String
    let count: Int
    let selected: Int?
    let focused: Bool
    let label: (Int) -> String
  }

  var now: NowPlaying
  var listTitle: String
  var entryCount: Int
  var entry: (Int) -> Entry
  var selection: Int?
  var chooser: Bool
  var emptyMessage: String
  var prompt: String?
  var notice: String?
  var help: [String]?
  var completingCommand = false
  var browsingLibrary = false
  var columns: [Column] = []
  var columnContext = ""

  func render(columns viewportWidth: Int, rows: Int, color: Bool) -> String {
    let width = max(1, min(viewportWidth, 116))
    let canvas = Canvas(width: width, color: color)
    let wide = width >= 80 && rows >= 20
    let full = width >= 36 && rows >= 10
    var output: [String] = []

    var title = canvas.text(" ◈ ", .violet, bold: true) + canvas.text("BubiTunes", .light, bold: true)
    if width >= 39 { title += canvas.text("   OPNA", .mint, bold: true) }
    output.append(canvas.line(canvas.balance(title, canvas.text("YM2608  /  44.1 kHz ", .muted), width: width), on: .header))

    let footer = rows >= 8 ? keybar(canvas) : []
    let notificationRows = (prompt != nil && rows >= 5) || (notice != nil && rows >= 8) ? 1 : 0
    let deck = full && (prompt == nil || rows >= 15)
      ? (wide ? wideDeck(canvas) : compactDeck(canvas, showDetail: rows >= 15))
      : []
    // Leave room for the list heading and at least one item.
    let availableDeckRows = rows - output.count - footer.count - notificationRows - 2
    if !deck.isEmpty && deck.count < availableDeckRows {
      output.append("")
      output.append(contentsOf: deck)
    } else {
      output.append(canvas.line(canvas.text(now.title, .light, bold: true), on: .panel))
      output.append(canvas.line(canvas.text("\(now.state)  \(now.position)  Vol \(now.volume)%  \(now.repeatMode.label)", .mint), on: .panel))
    }

    if let prompt, rows >= 5 {
      output.append(canvas.line(canvas.text(" / ", .ink, on: .mint, bold: true) + canvas.text(" " + prompt, .light), on: .selected))
    } else if let notice, rows >= 8 {
      output.append(canvas.line(canvas.text("  " + notice, .amber), on: .background))
    }

    let remaining = max(0, rows - output.count - footer.count)
    let content = columns.isEmpty || help != nil ? list(canvas, height: remaining) : columnDeck(canvas, height: remaining)
    output.append(contentsOf: content)
    output.append(contentsOf: footer)
    return output.prefix(rows).joined(separator: "\n")
  }

  private func wideDeck(_ canvas: Canvas) -> [String] {
    let left = min(48, canvas.width * 46 / 100)
    let right = canvas.width - left - 2
    let player = canvas.panel("Now playing", width: left, rows: playback(canvas, width: left - 4))
    let meters = canvas.panel("Spectrum / OPNA", width: right, rows: visualizer(canvas, width: right - 4))
    return zip(player, meters).map { $0 + "  " + $1 }
  }

  private func compactDeck(_ canvas: Canvas, showDetail: Bool) -> [String] {
    let width = canvas.width - 4
    let time = canvas.text("\(now.position) / \(now.duration)", .muted)
    let status = canvas.text("\(now.state)   Vol \(now.volume)%", .mint, bold: true)
    let progress = bar(canvas, progress: now.progress, width: max(1, width - time.width - 2)) + canvas.text("  ") + time
    let details = !showDetail || now.detail.isEmpty ? [] : [canvas.text(now.detail, .muted)]
    let display = now.spectrum.map { spectrum in
      let glyphs = Array("·▁▂▃▄▅▆▇█")
      let values = String(spectrum.bands.map { glyphs[Spectrum.level($0)] })
      return canvas.text(values, .aqua, bold: true) + canvas.text("    ") + activity(canvas)
    } ?? activity(canvas)
    return canvas.panel("Now playing", width: canvas.width, rows: [
      canvas.balance(status, modeStatus(canvas), width: width),
      canvas.text(now.title, .light, bold: true),
    ] + details + [progress, display])
  }

  private func playback(_ canvas: Canvas, width: Int) -> [Line] {
    let stateColor: Tone = now.state == "Playing" ? .mint : .amber
    let symbol = now.state == "Playing" ? "▶" : now.state == "Paused" ? "Ⅱ" : "■"
    return [
      canvas.balance(canvas.text(" \(symbol) \(now.state) ", .ink, on: stateColor, bold: true),
                     canvas.text(now.looping ? "LOOP ×1" : "", .amber), width: width),
      canvas.balance([], repeatStatus(canvas), width: width),
      canvas.text("▌ ", .violet, bold: true) + canvas.text(now.title, .light, bold: true),
      canvas.text(now.detail, .muted),
      [],
      bar(canvas, progress: now.progress, width: width),
      canvas.balance(canvas.text("\(now.position) / \(now.duration)", .light),
                     canvas.text("Vol \(now.volume)%", .mint), width: width),
      key(canvas, "Space", "Pause / Play") + canvas.text("  ") + key(canvas, "←  →", "Track"),
    ]
  }

  private func modeStatus(_ canvas: Canvas) -> Line {
    let loop = now.looping ? canvas.text("LOOP ×1  ", .amber) : []
    return loop + repeatStatus(canvas)
  }

  private func repeatStatus(_ canvas: Canvas) -> Line {
    canvas.text(now.repeatMode.label, now.repeatMode == .off ? .muted : .violet, bold: now.repeatMode != .off)
  }

  private func visualizer(_ canvas: Canvas, width: Int) -> [Line] {
    let meterRows = 5
    let peak = now.spectrum ?? .silent
    var output = (0..<meterRows).map { row -> Line in
      let level = meterRows - row
      if now.spectrum == nil {
        return row == 2 ? canvas.text("Spectrum off   /spectrum on", .muted) : []
      }
      let barWidth = min(5, max(1, width / peak.bands.count - 1))
      let tones: [Tone] = [.amber, .violet, .blue, .aqua, .mint]
      let columns = peak.bands.map { amplitude -> Line in
        let steps = Int((Double(Spectrum.level(amplitude)) * 1.25).rounded())
        let remaining = steps - (level - 1) * 2
        let glyph = remaining >= 2 ? "█" : remaining == 1 ? "▄" : "·"
        return canvas.text(String(repeating: glyph, count: barWidth), remaining > 0 ? tones[row] : .grid)
      }
      return columns.dropFirst().reduce(columns.first ?? []) { $0 + canvas.text(" ") + $1 }
    }
    output.append(canvas.balance(canvas.text("LOW", .muted), canvas.text("HIGH", .muted), width: width))
    let meterWidth = min(12, max(4, (width - 9) / 2))
    func meter(_ channel: String, _ value: Float) -> Line {
      canvas.text(channel + " ", .light, bold: true) +
        bar(canvas, progress: Double(Spectrum.level(value)) / 8, width: meterWidth)
    }
    output.append(meter("L", peak.left) + canvas.text("   ") + meter("R", peak.right))
    output.append(activity(canvas))
    return output
  }

  private func activity(_ canvas: Canvas) -> Line {
    let parts: [(String, OPNAActivity, Tone)] = [
      ("FM", .fm, .violet), ("SSG", .ssg, .mint), ("RHY", .rhythm, .amber), ("ADPCM", .adpcm, .blue),
    ]
    return parts.enumerated().flatMap { index, part -> Line in
      let active = now.activity.contains(part.1)
      let gap = index == 0 ? "" : "  "
      return canvas.text(gap + (active ? "● " : "○ ") + part.0, active ? part.2 : .muted, bold: active)
    }
  }

  private func columnDeck(_ canvas: Canvas, height: Int) -> [String] {
    guard height >= 2, let focused = columns.first(where: \.focused) else { return [] }
    if canvas.width >= 56 && height >= 6 && columns.count == 3 {
      let gap = height >= 9 ? 1 : 0
      let filterHeight = min(8, max(3, (height - gap) / 3 + 1))
      let artistWidth = (canvas.width - 2) / 2
      let gameWidth = canvas.width - artistWidth - 2
      let artists = columnPanel(columns[0], canvas: canvas, width: artistWidth, height: filterHeight)
      let games = columnPanel(columns[1], canvas: canvas, width: gameWidth, height: filterHeight)
      let songs = columnPanel(columns[2], canvas: canvas, width: canvas.width,
                              height: height - filterHeight - gap)
      return zip(artists, games).map { $0 + "  " + $1 } + (gap == 1 ? [""] : []) + songs
    }
    let context = height >= 4 && !columnContext.isEmpty
      ? [canvas.line(canvas.text("  " + columnContext, .muted), on: .panel)] : []
    return context + columnPanel(focused, canvas: canvas, width: canvas.width, height: height - context.count)
  }

  private func columnPanel(_ column: Column, canvas: Canvas, width: Int, height: Int) -> [String] {
    let framed = width >= 16 && height >= 3
    let count = height - (framed ? 2 : 1)
    let limit = width - (framed ? 4 : 0)
    let selected = column.selected ?? 0
    let start = max(0, min(selected - count / 2, column.count - count))
    var lines = (start..<min(column.count, start + count)).map { index -> Line in
      let active = index == column.selected
      let background: Tone = active ? .selected : .panel
      let marker = canvas.text(active ? "› " : "  ", column.focused ? .mint : .violet, on: background, bold: active)
      let item = canvas.text(column.label(index), active ? .light : .muted, on: background, bold: active)
      return canvas.fit(marker + item, limit: limit, on: background)
    }
    if lines.isEmpty && count > 0 {
      lines.append(canvas.text(emptyMessage, .muted))
    }
    lines += Array(repeating: [], count: max(0, count - lines.count))
    let title = (column.focused ? "▸ " : "") + column.title
    if framed {
      return canvas.panel(title, width: width, rows: lines, border: column.focused ? .aqua : .grid)
    }
    let pane = Canvas(width: width, color: canvas.color)
    return [pane.line(canvas.text(title, .aqua, bold: true), on: .panel)] +
      lines.map { pane.line($0, on: .panel) }
  }

  private func list(_ canvas: Canvas, height: Int) -> [String] {
    guard height >= 2 else { return [] }
    let width = canvas.width
    let count = help == nil && entryCount > 0 ? "  \(entryCount)" : ""
    let title = help == nil ? listTitle + count : "Slash commands"
    let content = width >= 25 ? width - 4 : width
    let framed = width >= 25 && height >= 3
    let available = max(0, height - (framed ? 2 : 1))
    let lines: [Line]
    if let help {
      lines = help.prefix(available).map { canvas.text($0, .aqua) }
    } else if entryCount == 0 {
      lines = [canvas.text(emptyMessage, .muted)]
    } else {
      let position = selection ?? 0
      let start = max(0, min(position - available / 2, entryCount - available))
      lines = (start..<min(entryCount, start + available)).map { index in
        let row = entry(index)
        let active = selection == index
        let background: Tone = active ? .selected : .panel
        let detailsWidth = content >= 60 && !row.detail.isEmpty ? content / 3 : 0
        let nameWidth = content - (detailsWidth == 0 ? 0 : detailsWidth + 2)
        let marker = canvas.text(active ? "› " : "  ", active ? .mint : .muted, on: background, bold: active)
        let name = canvas.text(row.name, active ? .light : .muted, on: background, bold: active)
        var line = canvas.fit(marker + name, limit: nameWidth, on: background)
        if detailsWidth > 0 {
          line += canvas.text("  ", .muted, on: background)
          line += canvas.fit(canvas.text(row.detail, .muted, on: background), limit: detailsWidth, on: background)
        }
        return line
      }
    }
    let padded = lines.prefix(available) + Array(repeating: [], count: max(0, available - lines.count))
    if framed {
      return canvas.panel(title, width: width, rows: Array(padded))
    }
    return [canvas.line(canvas.text(" " + title, .violet, bold: true), on: .panel)] +
      padded.map { canvas.line($0, on: .panel) }
  }

  private func keybar(_ canvas: Canvas) -> [String] {
    let visible: Line
    if completingCommand {
      visible = key(canvas, "↑↓", "Select") + canvas.text("  ") + key(canvas, "Tab", "Complete") +
        canvas.text("  ") + key(canvas, "Enter", "Run")
    } else if prompt != nil {
      visible = key(canvas, "Enter", "Apply") + canvas.text("  ") + key(canvas, "Tab", "Queue") +
        canvas.text("  ") + key(canvas, "Esc", "Cancel")
    } else if help != nil {
      visible = key(canvas, "Esc", "Back")
    } else if !columns.isEmpty {
      let action = columns.last?.focused == true ? "Play from song" : "Next pane"
      visible = key(canvas, "← →", "Pane") + canvas.text("  ") + key(canvas, "↑↓", "Select") +
        canvas.text("  ") + key(canvas, "Enter", action) + canvas.text("  ") +
        key(canvas, "P", "Queue") + canvas.text("  ") + key(canvas, "S", "Shuffle")
    } else if browsingLibrary {
      visible = key(canvas, "↑↓", "Select") + canvas.text("  ") + key(canvas, "Enter", "Open / play from here") +
        canvas.text("  ") + key(canvas, "P", "Queue") + canvas.text("  ") + key(canvas, "S", "Shuffle")
    } else if chooser {
      visible = key(canvas, "↑↓", "Select") + canvas.text("  ") + key(canvas, "Enter", "Play from here") +
        canvas.text("  ") + key(canvas, "P", "Queue") + canvas.text("  ") + key(canvas, "S", "Shuffle")
    } else {
      visible = key(canvas, "Space", "Pause") + canvas.text("  ") + key(canvas, "← →", "Track") +
        canvas.text("  ") + key(canvas, "+ −", "Volume") + canvas.text("  ") + key(canvas, "R", "Repeat") +
        canvas.text("  ") + key(canvas, "P", "Browse")
    }
    let other = key(canvas, "/", "Search / command") + canvas.text("  ") + key(canvas, "?", "Help") +
      canvas.text("  ") + key(canvas, "q", "Quit")
    let primary = canvas.text(" ") + visible
    let secondary = canvas.text(" ") + other + canvas.text(" ")
    if primary.width + secondary.width + 2 <= canvas.width {
      return [canvas.line(canvas.balance(primary, secondary, width: canvas.width), on: .header)]
    }
    return [canvas.line(secondary, on: .header), canvas.line(primary, on: .header)]
  }

  private func key(_ canvas: Canvas, _ name: String, _ label: String) -> Line {
    canvas.text(" \(name) ", .light, on: .selected, bold: true) + canvas.text(" " + label, .muted)
  }

  private func bar(_ canvas: Canvas, progress: Double, width: Int) -> Line {
    let filled = Int((max(0, min(1, progress)) * Double(width)).rounded(.down))
    return canvas.text(String(repeating: "━", count: filled), .aqua, bold: true) +
      canvas.text(String(repeating: "─", count: width - filled), .grid)
  }
}

private enum Tone: Int {
  case background = 233, panel = 234, header = 235, selected = 237, ink = 16
  case grid = 60, muted = 250, light = 255
  case violet = 141, blue = 111, aqua = 80, mint = 121, amber = 221
}

private struct Span {
  let text: String
  let ink: Tone
  let paper: Tone?
  let bold: Bool
}

private typealias Line = [Span]

private extension Array where Element == Span {
  var width: Int { reduce(0) { $0 + terminalCellWidth($1.text) } }
}

private struct Canvas {
  let width: Int
  let color: Bool

  func text(_ label: String, _ tone: Tone = .light, on paper: Tone? = nil, bold: Bool = false) -> Line {
    label.isEmpty ? [] : [Span(text: label, ink: tone, paper: paper, bold: bold)]
  }

  func balance(_ left: Line, _ right: Line, width: Int) -> Line {
    guard right.width > 0, right.width + 2 < width else { return left }
    let trimmed = truncate(left, limit: width - right.width - 2)
    return trimmed + text(String(repeating: " ", count: width - trimmed.width - right.width)) + right
  }

  func fit(_ line: Line, limit: Int, on paper: Tone) -> Line {
    let cropped = truncate(line, limit: limit)
    return cropped + text(String(repeating: " ", count: max(0, limit - cropped.width)), .light, on: paper)
  }

  func line(_ line: Line, on paper: Tone) -> String {
    encode(fit(line, limit: width, on: paper), on: paper)
  }

  func panel(_ title: String, width: Int, rows: [Line], border: Tone = .grid) -> [String] {
    let caption = text("╭─ ", border) + text(title, border == .aqua ? .mint : .violet, bold: true) + text(" ", border)
    let clippedCaption = truncate(caption, limit: width - 2)
    let top = clippedCaption + text(String(repeating: "─", count: width - 1 - clippedCaption.width) + "╮", border)
    let bottom = text("╰" + String(repeating: "─", count: width - 2) + "╯", border)
    return [encode(top, on: .panel)] + rows.map {
      let interior = fit($0, limit: width - 4, on: .panel)
      return encode(text("│ ", border) + interior + text(" │", border), on: .panel)
    } + [encode(bottom, on: .panel)]
  }

  private func truncate(_ line: Line, limit: Int) -> Line {
    guard limit > 0 else { return [] }
    if line.width <= limit { return line }
    var left = limit - 1
    var result: Line = []
    for span in line {
      var prefix = ""
      for character in span.text {
        let advance = terminalCellWidth(String(character))
        guard advance <= left else {
          return result + text(prefix, span.ink, on: span.paper, bold: span.bold) +
            text("…", span.ink, on: span.paper, bold: span.bold)
        }
        prefix.append(character)
        left -= advance
      }
      result += text(prefix, span.ink, on: span.paper, bold: span.bold)
    }
    return result
  }

  private func encode(_ line: Line, on paper: Tone) -> String {
    guard color else { return line.map(\.text).joined() }
    return line.map { span in
      let intensity = span.bold ? "1" : "22"
      return "\u{1B}[\(intensity);38;5;\(span.ink.rawValue);48;5;\((span.paper ?? paper).rawValue)m" + span.text
    }.joined() + "\u{1B}[0m"
  }
}

func terminalCellWidth(_ text: String) -> Int {
  text.reduce(0) { width, character in
    let scalars = character.unicodeScalars
    guard let first = scalars.first else { return width }
    let code = first.value
    let wide = first.properties.isEmojiPresentation || scalars.contains { $0.value == 0xFE0F } ||
      (0x1100...0x115F).contains(code) || code == 0x2329 || code == 0x232A ||
      (0x2E80...0xA4CF).contains(code) || (0xAC00...0xD7A3).contains(code) ||
      (0xF900...0xFAFF).contains(code) || (0xFE10...0xFE6F).contains(code) ||
      (0xFF01...0xFF60).contains(code) || (0xFFE0...0xFFE6).contains(code) ||
      (0x20000...0x3FFFD).contains(code)
    return width + (wide ? 2 : 1)
  }
}
