// swift-tools-version:5.10
// Throwaway spike for phase 0 (YT-9 onwards). Not part of the app; deleted after gate G0.
import PackageDescription

let package = Package(
    name: "YTNotchSpike",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "YTNotchSpike")
    ]
)
