// Selects the terminal implementation per platform, mirroring
// PlaybackBackend.swift. Both implementations expose the same surface
// (init / restore / shouldQuit / viewport / keys / draw / color), so
// swapping the backend is a file-level change:
//   - Windows: WindowsTerminal (Win32 console, virtual terminal input)
//   - other platforms: Terminal (POSIX termios)
#if os(Windows)
typealias PlatformTerminal = WindowsTerminal
#else
typealias PlatformTerminal = Terminal
#endif
