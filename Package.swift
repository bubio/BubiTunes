// swift-tools-version: 6.1
import Foundation
import PackageDescription

let localCore = ProcessInfo.processInfo.environment["BUBITUNES_CORE_DIR"]
let core: Package.Dependency = localCore.map { .package(path: $0) }
  ?? .package(url: "https://github.com/bubio/Bubilator88Core.git", from: "1.13.0")

let package = Package(
  name: "BubiTunes",
  platforms: [.macOS(.v15)],
  products: [
    .executable(name: "bubitunes", targets: ["BubiTunesCLI"]),
  ],
  dependencies: [core],
  targets: [
    .systemLibrary(name: "CZlib", pkgConfig: "zlib", providers: [.apt(["zlib1g-dev"])]),
    .target(name: "BubiTunesPlayer", dependencies: ["CZlib"]),
    .executableTarget(name: "BubiTunesCLI", dependencies: [
      "BubiTunesPlayer", .product(name: "Bubilator88Core", package: "Bubilator88Core"),
    ]),
    .testTarget(name: "BubiTunesPlayerTests", dependencies: ["BubiTunesPlayer"]),
  ]
)
