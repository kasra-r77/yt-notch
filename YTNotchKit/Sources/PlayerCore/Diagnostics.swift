import Foundation

/// The Copy Diagnostics report (design spec D7). It must hold nothing from the user's account
/// or listening: no titles, artists, playlists, IDs or names, only states and counts.
public enum Diagnostics {
    public struct Versions: Equatable, Sendable {
        public var app: String
        public var build: String
        public var macOS: String
        public var engine: String

        public init(app: String, build: String, macOS: String, engine: String) {
            self.app = app
            self.build = build
            self.macOS = macOS
            self.engine = engine
        }
    }

    public static let logLimit = 50

    @MainActor
    public static func report(versions: Versions, state: PlayerState, logLines: [String]) -> String {
        let missing = state.health.missing.map(\.rawValue).sorted()
        var lines = [
            "YT Notch \(versions.app) (\(versions.build))",
            "macOS \(versions.macOS)",
            "Engine: \(versions.engine)",
            "Bridge: \(state.bridgeVersion ?? "not attached")",
            "Health: \(name(of: state.health.status))",
            "Can't read: \(missing.isEmpty ? "nothing" : missing.joined(separator: ", "))",
            "Track loaded: \(state.track == nil ? "no" : "yes"), playing: \(state.isPlaying ? "yes" : "no")",
            "Lists: \(state.playlists.count) playlists\(state.playlistsMayBeOutOfDate ? " (saved)" : ""), \(state.queue.count) in Up next",
        ]
        let recent = logLines.suffix(logLimit)
        lines.append("")
        lines.append(recent.isEmpty ? "No log lines." : "Last \(recent.count) log lines:")
        lines.append(contentsOf: recent)
        return lines.joined(separator: "\n")
    }

    static func name(of status: Health.Status) -> String {
        switch status {
        case .starting: "starting"
        case .ok: "ok"
        case .signedOut: "signed out"
        case .offline: "offline"
        case .bridgeBroken: "bridge broken"
        }
    }
}
