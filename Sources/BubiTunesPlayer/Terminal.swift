#if os(macOS)
import Darwin
import Dispatch
import Foundation
import Synchronization

final class Terminal {
  private var saved = termios()
  private let interrupted = Mutex(false)
  private var signals: [DispatchSourceSignal] = []
  private var previousHandlers: [(Int32, sig_t?)] = []
  private var pending: [UInt8] = []
  private var active = false

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

  var rows: Int {
    var size = winsize()
    guard ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) == 0, size.ws_row > 0 else { return 24 }
    return Int(size.ws_row)
  }

  func keys() -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: 64)
    let count = bytes.withUnsafeMutableBytes { read(STDIN_FILENO, $0.baseAddress, $0.count) }
    if count > 0 { pending.append(contentsOf: bytes.prefix(count)) }
    var result: [UInt8] = []
    while let first = pending.first {
      if first != 27 {
        result.append(first)
        pending.removeFirst()
      } else if pending.count >= 2, pending[1] != 91 {
        pending.removeFirst(2)
      } else if pending.count >= 3 {
        if pending[2] == 67 { result.append(110) } // Right
        if pending[2] == 68 { result.append(112) } // Left
        pending.removeFirst(3)
      } else {
        break
      }
    }
    return result
  }

  func draw(_ text: String) {
    write("\u{1B}[H\u{1B}[2J" + text.replacingOccurrences(of: "\n", with: "\r\n"))
  }

  private func write(_ text: String) {
    FileHandle.standardOutput.write(Data(text.utf8))
  }
}
#endif
