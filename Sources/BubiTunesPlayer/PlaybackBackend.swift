// Selects the audio device implementation per platform. The two
// implementations expose the same surface (init / refill / play / pause /
// played / visual / finished / volume), so swapping the backend is a
// file-level change:
//   - macOS: MacPlayback (AVFoundation)
//   - other platforms: DevicePlayback (miniaudio)
#if os(macOS)
typealias PlatformPlayback = MacPlayback
#else
typealias PlatformPlayback = DevicePlayback
#endif
