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
    var motion = SpectrumMotion()
    var shimmer: Double?
  }

  struct Entry {
    let name: String
    let detail: String
    var isTrack = false
    var current = false
  }

  struct Column {
    let title: String
    let count: Int
    let selected: Int?
    let focused: Bool
    var tracks = false
    var isCurrent: (Int) -> Bool = { _ in false }
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
      output.append(canvas.line(trackTitle(canvas, width: width), on: .panel))
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
    let display = now.spectrum == nil ? activity(canvas) :
      spectrumRow(canvas, row: 0, rows: 1, barWidth: 1) + canvas.text("  ") + activity(canvas)
    return canvas.panel("Now playing", width: canvas.width, rows: [
      canvas.balance(status, modeStatus(canvas), width: width),
      trackTitle(canvas, width: width),
    ] + details + [progress, display])
  }

  private func playback(_ canvas: Canvas, width: Int) -> [Line] {
    let stateColor: Tone = now.state == "Playing" ? .mint : .amber
    let symbol = now.state == "Playing" ? "▶" : now.state == "Paused" ? "Ⅱ" : "■"
    return [
      canvas.balance(canvas.text(" \(symbol) \(now.state) ", .ink, on: stateColor, bold: true),
                     canvas.text(now.looping ? "LOOP ×1" : "", .amber), width: width),
      canvas.balance([], repeatStatus(canvas), width: width),
      canvas.text("▌ ", .violet, bold: true) + trackTitle(canvas, width: width - 2),
      canvas.text(now.detail, .muted),
      [],
      bar(canvas, progress: now.progress, width: width),
      canvas.balance(canvas.text("\(now.position) / \(now.duration)", .light),
                     canvas.text("Vol \(now.volume)%", .mint), width: width),
      key(canvas, "Space", "Pause / Play") + canvas.text("  ") + key(canvas, "←  →", "Track"),
    ]
  }

  private func trackTitle(_ canvas: Canvas, width: Int) -> Line {
    canvas.shimmer(now.title, phase: now.shimmer, width: width, base: .light)
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
    let bands = now.motion.bands.count
    let barWidth = max(1, (width + 1) / bands - 1)
    let graphWidth = bands * (barWidth + 1) - 1
    var output = (0..<meterRows).map { row -> Line in
      if now.spectrum == nil {
        return row == 2 ? canvas.text("Spectrum off   /spectrum on", .muted) : []
      }
      return spectrumRow(canvas, row: row, rows: meterRows, barWidth: barWidth)
    }
    output.append(now.spectrum == nil ? [] :
      canvas.balance(canvas.text("LOW", .muted), canvas.text("HIGH", .muted), width: graphWidth))
    let meterWidth = min(12, max(4, (width - 9) / 2))
    if let spectrum = now.spectrum {
      output.append(stereoMeter(canvas, channel: "L", amplitude: spectrum.left, width: meterWidth) +
        canvas.text("   ") + stereoMeter(canvas, channel: "R", amplitude: spectrum.right, width: meterWidth))
    } else {
      output.append([])
    }
    output.append(activity(canvas))
    return output
  }

  private func spectrumRow(_ canvas: Canvas, row: Int, rows: Int, barWidth: Int) -> Line {
    let glyphs = Array(" ▁▂▃▄▅▆▇█")
    let tones: [Tone] = [.pink, .violet, .blue, .aqua, .mint]
    let offset = (rows - 1 - row) * 8
    return now.motion.bands.enumerated().flatMap { index, band -> Line in
      let height = Int((band.height * Float(rows * 8)).rounded())
      let peak = Int((band.peak * Float(rows * 8)).rounded())
      let hasPeak = peak > offset && peak <= offset + 8
      let fill = max(0, min(8, height - offset))
      let glyph: Character = fill > 0 ? glyphs[fill] : hasPeak ? "━" : row == rows - 1 ? "┈" : "·"
      let tone = hasPeak ? .peak : fill > 0 ? (rows == 1 ? .aqua : tones[row]) : .grid
      return canvas.text(index == 0 ? "" : " ") +
        canvas.text(String(repeating: glyph, count: barWidth), tone)
    }
  }

  private func stereoMeter(_ canvas: Canvas, channel: String, amplitude: Float, width: Int) -> Line {
    let filled = Int((Spectrum.height(amplitude) * Float(width)).rounded())
    return canvas.text(channel + " ", .light, bold: true) + (0..<width).flatMap { index -> Line in
      let tone: Tone = index >= width - 2 ? .amber : index >= width - 5 ? .aqua : .mint
      return canvas.text(index < filled ? "▪" : "╌", index < filled ? tone : .grid)
    }
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
      let current = column.isCurrent(index)
      let style = rowStyle(canvas, current: current, selected: index == column.selected,
                           track: column.tracks, focused: column.focused)
      let (marker, background) = (style.marker, style.background)
      let item = rowName(column.label(index), canvas: canvas, width: limit - marker.width,
                         current: current, background: background)
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
    let framed = width >= 25 && height >= 3
    let content = framed ? width - 4 : width
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
        let style = rowStyle(canvas, current: row.current, selected: selection == index, track: row.isTrack)
        let (marker, background) = (style.marker, style.background)
        let detailsWidth = content >= 60 && !row.detail.isEmpty ? content / 3 : 0
        let nameWidth = content - (detailsWidth == 0 ? 0 : detailsWidth + 2)
        let name = rowName(row.name, canvas: canvas, width: nameWidth - marker.width,
                           current: row.current, background: background)
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

  private func rowStyle(_ canvas: Canvas, current: Bool, selected: Bool, track: Bool,
                        focused: Bool = true) -> (marker: Line, background: Tone) {
    if current {
      return (canvas.text("› ", .mint, on: .playingRow, bold: true), .playingRow)
    }
    let background: Tone = selected ? .selected : .panel
    let cursor = track && now.state != "Stopped" ? "▹ " : "› "
    let marker = canvas.text(selected ? cursor : "  ", focused ? .mint : .violet,
                             on: background, bold: selected)
    return (marker, background)
  }

  private func rowName(_ name: String, canvas: Canvas, width: Int, current: Bool, background: Tone) -> Line {
    if current {
      return canvas.shimmer(name, phase: now.shimmer, width: width, base: .sky, on: background)
    }
    let selected = background == .selected
    return canvas.text(name, selected ? .light : .muted, on: background, bold: selected)
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
  case background = 233, panel = 234, header = 235, selected = 237, playingRow = 24, ink = 16
  case grid = 60, muted = 250, light = 255
  case violet = 141, blue = 111, aqua = 80, mint = 121, amber = 221
  case pink = 213, sky = 153, peak = 159, shine = 231
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

  func shimmer(_ label: String, phase: Double?, width: Int, base: Tone, on paper: Tone? = nil) -> Line {
    let clipped = truncate(text(label, base, on: paper, bold: true), limit: width)
    guard color, let phase, !clipped.isEmpty else { return clipped }
    let sweepWidth = Double(max(3, min(8, clipped.width / 3)))
    let center = phase * (Double(clipped.width) + 2 * sweepWidth) - sweepWidth
    var result: Line = []
    var position = 0
    for character in clipped.map(\.text).joined() {
      let text = String(character)
      let cells = terminalCellWidth(text)
      let distance = abs(Double(position) + Double(cells) / 2 - center) / sweepWidth
      let tone: Tone = distance < 0.35 ? .shine : distance < 0.72 ? .peak : distance < 1 ? .sky : base
      if result.last?.ink == tone, let last = result.popLast() {
        result.append(Span(text: last.text + text, ink: tone, paper: paper, bold: true))
      } else {
        result.append(Span(text: text, ink: tone, paper: paper, bold: true))
      }
      position += cells
    }
    return result
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
