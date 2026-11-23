#if os(Windows)
import Foundation
import Synchronization
import WinSDK

// Windows console implementation of the terminal surface, selected via
// PlatformTerminal on Windows (see TerminalBackend.swift). It exposes
// exactly the same surface as the POSIX Terminal so PlayerSession does
// not change beyond the type name.
//
// The console is driven with virtual terminal sequences, mirroring the
// POSIX raw mode: on input, ENABLE_VIRTUAL_TERMINAL_INPUT is enabled and
// the line/echo/processed modes are removed, so keys arrive as a byte
// stream (escape sequences included) through ReadFile and Ctrl+C arrives
// as byte 0x03 instead of raising a signal. On output,
// ENABLE_VIRTUAL_TERMINAL_PROCESSING is enabled so the same escape
// sequences Terminal.draw produces are interpreted by the console. This
// targets modern hosts (Windows Terminal, PowerShell); conhost support
// is best-effort only.
//
// As a safety net for console control events that do not arrive as
// bytes (close, logoff, Ctrl+Break), a SetConsoleCtrlHandler callback
// sets the same interrupted flag shouldQuit reads. The handler is a C
// function without a context pointer, so the active instance's flag is
// published through a file-scope slot while the terminal is alive.
// The flag lives in a class box so the active instance can publish it
// through the slot by reference; Mutex is a value type, so it can
// neither be shared by assignment nor compared by identity.
// @unchecked Sendable: the only stored property is a Mutex, which
// guards every access to the flag, so sharing a box across isolation
// domains is thread-safe in practice. The conformance is needed to
// publish the box through ctrlHandlerSlot (a Mutex) without tripping
// Swift 6 region-isolation diagnostics on the `inout sending` closure.
private final class InterruptBox: @unchecked Sendable {
  let flag = Mutex(false)
}

private let ctrlHandlerSlot = Mutex<InterruptBox?>(nil)

private func bubiTunesConsoleCtrlHandler(_ type: DWORD) -> WindowsBool {
  ctrlHandlerSlot.withLock { $0 }?.flag.withLock { $0 = true }
  return WindowsBool(true)
}

final class WindowsTerminal {
  enum Key {
    case byte(UInt8)
    case up, down, left, right, escape, backTab
  }

  private let inputHandle: HANDLE
  private let outputHandle: HANDLE
  private var savedInputMode: DWORD = 0
  private var savedOutputMode: DWORD = 0
  private let interruptBox = InterruptBox()
  private var pending: [UInt8] = []
  private var active = false
  private var lastRows: [String] = []
  let color = ProcessInfo.processInfo.environment["NO_COLOR"] == nil &&
    ProcessInfo.processInfo.environment["TERM"] != "dumb"

  init() throws {
    inputHandle = GetStdHandle(STD_INPUT_HANDLE)
    outputHandle = GetStdHandle(STD_OUTPUT_HANDLE)
    guard inputHandle != INVALID_HANDLE_VALUE, outputHandle != INVALID_HANDLE_VALUE,
      GetFileType(inputHandle) == FILE_TYPE_CHAR, GetFileType(outputHandle) == FILE_TYPE_CHAR
    else {
      throw VGMError.unsupported("an interactive terminal is required")
    }
    guard GetConsoleMode(inputHandle, &savedInputMode) != false,
      GetConsoleMode(outputHandle, &savedOutputMode) != false
    else { throw POSIXError(.EIO) }

    SetConsoleCP(65001)  // CP_UTF8
    SetConsoleOutputCP(65001)

    // The ENABLE_* constants are imported as Int32 while console modes
    // are DWORD (UInt32), so convert each flag before the arithmetic.
    let inputMode = (savedInputMode & ~DWORD(bitPattern: ENABLE_LINE_INPUT | ENABLE_ECHO_INPUT | ENABLE_PROCESSED_INPUT))
      | DWORD(bitPattern: ENABLE_VIRTUAL_TERMINAL_INPUT)
    let outputMode = savedOutputMode | DWORD(bitPattern: ENABLE_VIRTUAL_TERMINAL_PROCESSING)
    guard SetConsoleMode(inputHandle, inputMode) != false,
      SetConsoleMode(outputHandle, outputMode) != false
    else { throw POSIXError(.EIO) }

    ctrlHandlerSlot.withLock { $0 = interruptBox }
    SetConsoleCtrlHandler(bubiTunesConsoleCtrlHandler, true)
    active = true
    write("\u{1B}[?1049h\u{1B}[?25l\u{1B}[?7l")
  }

  deinit { restore() }

  func restore() {
    if active {
      active = false
      // Leave the alternate screen while virtual terminal processing is
      // still enabled, then put the saved console modes back.
      write("\u{1B}[?7h\u{1B}[?25h\u{1B}[?1049l")
      SetConsoleMode(inputHandle, savedInputMode)
      SetConsoleMode(outputHandle, savedOutputMode)
    }
    SetConsoleCtrlHandler(bubiTunesConsoleCtrlHandler, false)
    ctrlHandlerSlot.withLock { slot in
      if slot === interruptBox { slot = nil }
    }
  }

  var shouldQuit: Bool { interruptBox.flag.withLock { $0 } }

  var viewport: (columns: Int, rows: Int) {
    var info = CONSOLE_SCREEN_BUFFER_INFO()
    guard GetConsoleScreenBufferInfo(outputHandle, &info) != false else { return (80, 24) }
    let columns = Int(info.srWindow.Right - info.srWindow.Left) + 1
    let rows = Int(info.srWindow.Bottom - info.srWindow.Top) + 1
    return (columns <= 0 ? 80 : columns, rows <= 0 ? 24 : rows)
  }

  func keys() -> [Key] {
    var count = 0
    if WaitForSingleObject(inputHandle, 0) == WAIT_OBJECT_0 {
      var bytes = [UInt8](repeating: 0, count: 64)
      var read: DWORD = 0
      let ok = bytes.withUnsafeMutableBytes {
        ReadFile(inputHandle, $0.baseAddress, DWORD($0.count), &read, nil)
      }
      if ok, read > 0 {
        count = Int(read)
        pending.append(contentsOf: bytes.prefix(count))
      }
    }
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
#endif
