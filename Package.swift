// swift-tools-version: 6.1
import Foundation
import PackageDescription

let localCore = ProcessInfo.processInfo.environment["BUBITUNES_CORE_DIR"]
let core: Package.Dependency = localCore.map { .package(path: $0) }
  ?? .package(url: "https://github.com/bubio/Bubilator88Core.git", from: "1.13.0")

// Windows has no system zlib for SwiftPM to resolve, so there the CZlib
// target is built from the vendored sources in Sources/CZlibVendored.
// Everywhere else CZlib stays a systemLibrary target backed by the
// system zlib. The target name is "CZlib" in both cases and the module
// exposes the same shim.h, so the Swift sources do not change.
#if os(Windows)
let zlibTarget: Target = .target(
  name: "CZlib",
  path: "Sources/CZlibVendored",
  exclude: ["NOTICE.txt"],
  publicHeadersPath: "include"
)
#else
let zlibTarget: Target = .systemLibrary(
  name: "CZlib", pkgConfig: "zlib", providers: [.apt(["zlib1g-dev"])])
#endif

let package = Package(
  name: "BubiTunes",
  platforms: [.macOS(.v15)],
  products: [
    .executable(name: "bubitunes", targets: ["BubiTunesCLI"]),
  ],
  dependencies: [core],
  targets: [
    zlibTarget,
    .target(
      name: "CMinAudio",
      exclude: ["NOTICE.txt"],
      linkerSettings: [
        .linkedLibrary("m", .when(platforms: [.linux])),
        .linkedLibrary("dl", .when(platforms: [.linux])),
      ]
    ),
    .target(name: "BubiTunesPlayer", dependencies: ["CZlib", "CMinAudio"]),
    .executableTarget(name: "BubiTunesCLI", dependencies: [
      "BubiTunesPlayer", "CMinAudio", .product(name: "Bubilator88Core", package: "Bubilator88Core"),
      .target(name: "BubiTunesRhythmData", condition: .when(platforms: [.windows])),
    ]),
    .target(
      name: "BubiTunesRhythmData",
      path: "BubiTunesRhythm",
      resources: ["BD", "SD", "TOP", "HH", "TOM", "RIM"].map { .embedInCode("Rhythm_\($0).wav") }
    ),
    .testTarget(name: "BubiTunesPlayerTests", dependencies: ["BubiTunesPlayer"]),
  ]
)
