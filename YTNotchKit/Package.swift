// swift-tools-version:6.0
import PackageDescription

// Module rules (AGENTS.md): PlayerCore imports only Foundation and Observation. The other
// three import PlayerCore and never each other. Only WebPlayer imports WebKit.
// Tests/ArchitectureTests checks these on every `swift test`.
let package = Package(
    name: "YTNotchKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PlayerCore", targets: ["PlayerCore"]),
        .library(name: "WebPlayer", targets: ["WebPlayer"]),
        .library(name: "NotchUI", targets: ["NotchUI"]),
        .library(name: "SystemMedia", targets: ["SystemMedia"]),
    ],
    targets: [
        .target(name: "PlayerCore"),
        .target(name: "WebPlayer", dependencies: ["PlayerCore"]),
        .target(name: "NotchUI", dependencies: ["PlayerCore"]),
        .target(name: "SystemMedia", dependencies: ["PlayerCore"]),
        .testTarget(name: "PlayerCoreTests", dependencies: ["PlayerCore"]),
        .testTarget(name: "ArchitectureTests"),
    ]
)
