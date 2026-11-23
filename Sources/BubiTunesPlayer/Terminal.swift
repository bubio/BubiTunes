#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Dispatch
import Foundation
import Synchronization

#if canImport(Darwin)
private typealias SignalHandler = sig_t
#elseif canImport(Glibc)
private typealias SignalHandler = __sighandler_t
#endif

final class Terminal {
  enum Key {
    case byte(UInt8)
    case up, down, left, right, escape, backTab
  }

  private var saved = termios()
  private let interrupted = Mutex(false)
  private var signals: [DispatchSourceSignal] = []
  private var previousHandlers: [(Int32, SignalHandler?)] = []
  private var pending: [UInt8] = []
  private var active = false
  private var lastRows: [String] = []
  let color = ProcessInfo.processInfo.environment["NO_COLOR"] == nil &&
    ProcessInfo.processInfo.environment["TERM"] != "dumb"

  init() throws {
    guard isatty(STDIN_FILENO) == 1, isatty(STDOUT_FILENO) == 1 else {
      throw VGMError.unsupported("an interactive terminal is required")
    }
    guard tcgetattr(STDIN_FILENO, &saved) == 0 else { throw POSIXError(.EIO) }
    var raw = saved
    raw.c_lflag &= ~tcflag_t(ICANON | ECHO | ISIG)
    raw.c_iflag &= ~tcflag_t(IXON)
    withUnsafeMutableBytes(of: &raw.c_cc) { controls in
      controls[Int(VMIN)] = 0
      controls[Int(VTIME)] = 0
    }
    for code in [SIGINT, SIGTERM, SIGHUP] {
      previousHandlers.append((code, signal(code, SIG_IGN)))
      let source = DispatchSource.makeSignalSource(signal: code, queue: .global())
      source.setEventHandler { [weak self] in self?.interrupted.withLock { $0 = true } }
      source.resume()
      signals.append(source)
    }
    guard tcsetattr(STDIN_FILENO, TCSANOW, &raw) == 0 else { throw POSIXError(.EIO) }
    active = true
    write("\u{1B}[?1049h\u{1B}[?25l\u{1B}[?7l")
  }

  deinit { restore() }

  func restore() {
    if active {
      active = false
      tcsetattr(STDIN_FILENO, TCSAFLUSH, &saved)
      write("\u{1B}[?7h\u{1B}[?25h\u{1B}[?1049l")
    }
    for source in signals { source.cancel() }
    for (code, handler) in previousHandlers { signal(code, handler) }
    signals.removeAll()
    previousHandlers.removeAll()
  }

  var shouldQuit: Bool { interrupted.withLock { $0 } }

  var viewport: (columns: Int, rows: Int) {
    var size = winsize()
    guard ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &size) == 0 else { return (80, 24) }
    return (size.ws_col == 0 ? 80 : Int(size.ws_col), size.ws_row == 0 ? 24 : Int(size.ws_row))
  }

  func keys() -> [Key] {
    var bytes = [UInt8](repeating: 0, count: 64)
    let count = bytes.withUnsafeMutableBytes { read(STDIN_FILENO, $0.baseAddress, $0.count) }
    if count > 0 { pending.append(contentsOf: bytes.prefix(count)) }
    var result: [Key] = []
    while let first = pending.first {
      guard first == 27 else {
        result.append(.byte(first))
        pending.removeFirst()
        continue
      }
      if pending.count == 1 || pending[1] != 91 {
        if pending.count == 1 && count > 0 { break }
        result.append(.escape)
        pending.removeFirst()
        continue
      }
      if pending.count < 3 {
        if count > 0 { break }
        pending.removeAll()
        continue
      }
      guard let end = pending.indices.dropFirst(2).first(where: { (0x40...0x7E).contains(pending[$0]) }) else {
        if pending.count > 32 || count == 0 { pending.removeAll() }
        break
      }
      switch pending[end] {
      case 65: result.append(.up)
      case 66: result.append(.down)
      case 67: result.append(.right)
      case 68: result.append(.left)
      case 90: result.append(.backTab)
      default: break
      }
      pending.removeFirst(end + 1)
    }
    return result
  }

  func draw(_ text: String) {
    let rows = text.components(separatedBy: "\n")
    guard rows != lastRows else { return }
    let clear = lastRows.isEmpty ? "\u{1B}[2J" : ""
    var patch = clear
    for index in 0..<min(viewport.rows, max(rows.count, lastRows.count)) {
      let row = index < rows.count ? rows[index] : ""
      if index < lastRows.count, lastRows[index] == row { continue }
      patch += "\u{1B}[\(index + 1);1H\u{1B}[2K" + row
    }
    lastRows = rows
    write(patch)
  }

  private func write(_ text: String) {
    FileHandle.standardOutput.write(Data(text.utf8))
  }
}
