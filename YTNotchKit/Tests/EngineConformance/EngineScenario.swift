import Foundation
import PlayerCore

@MainActor
public struct EngineHarness {
    public let store: PlayerStore
    /// Moves playback time on, as real playback would.
    public let advance: @MainActor (TimeInterval) async throws -> Void

    public init(store: PlayerStore, advance: @escaping @MainActor (TimeInterval) async throws -> Void) {
        self.store = store
        self.advance = advance
    }
}

public struct ConformanceFailure: Error, CustomStringConvertible {
    public let description: String

    public init(description: String) {
        self.description = description
    }
}

/// A behaviour every PlayerEngine must have, whatever its tracks. FakeEngine and
/// WebPlayerController both run `EngineScenario.all`, each through its own harness.
public struct EngineScenario: Sendable, CustomStringConvertible {
    public let description: String
    private let body: @MainActor @Sendable (EngineHarness) async throws -> Void

    init(_ description: String, _ body: @escaping @MainActor @Sendable (EngineHarness) async throws -> Void) {
        self.description = description
        self.body = body
    }

    @MainActor
    public func run(_ harness: EngineHarness) async throws {
        try await eventually("the engine is ready with a track") {
            harness.store.state.health.status == .ok && harness.store.state.track != nil
        }
        try await body(harness)
    }
}

/// Waits for a condition, giving the main actor back while it waits.
@MainActor
public func eventually(_ what: String, timeout: TimeInterval = 5, _ condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() > deadline { throw ConformanceFailure(description: "Timed out waiting until \(what)") }
        try await Task.sleep(for: .milliseconds(10))
    }
}

extension EngineScenario {
    public static let all: [EngineScenario] = [
        EngineScenario("starts paused with a track") { harness in
            let state = harness.store.state
            guard !state.isPlaying else { throw ConformanceFailure(description: "started playing by itself") }
            guard state.track?.duration != nil else { throw ConformanceFailure(description: "no duration") }
        },
        EngineScenario("play and pause") { harness in
            let store = harness.store
            store.play()
            try await eventually("playing") { store.state.isPlaying }
            store.pause()
            try await eventually("paused") { !store.state.isPlaying }
        },
        EngineScenario("toggle") { harness in
            let store = harness.store
            store.togglePlayPause()
            try await eventually("playing") { store.state.isPlaying }
            store.togglePlayPause()
            try await eventually("paused") { !store.state.isPlaying }
        },
        EngineScenario("next changes the track") { harness in
            let store = harness.store
            let first = store.state.track
            store.next()
            try await eventually("a new track") { store.state.track != nil && store.state.track != first }
        },
        EngineScenario("previous early in a track goes back") { harness in
            let store = harness.store
            let first = store.state.track
            store.next()
            try await eventually("a new track") { store.state.track != nil && store.state.track != first }
            store.previous()
            try await eventually("the first track again") { store.state.track == first }
        },
        EngineScenario("seek") { harness in
            let store = harness.store
            store.seek(to: 30)
            try await eventually("at 30 seconds") { abs(store.state.position - 30) < 0.5 }
        },
        EngineScenario("like and unlike") { harness in
            let store = harness.store
            let wasLiked = store.state.liked
            store.toggleLike()
            try await eventually("like changed") { store.state.liked != wasLiked }
            store.toggleLike()
            try await eventually("like changed back") { store.state.liked == wasLiked }
        },
        EngineScenario("time moves while playing") { harness in
            let store = harness.store
            store.play()
            try await eventually("playing") { store.state.isPlaying }
            try await harness.advance(10)
            try await eventually("10 seconds in") { store.state.position >= 10 }
        },
        EngineScenario("the end of a track moves to the next") { harness in
            let store = harness.store
            let first = store.state.track
            let duration = first?.duration ?? 0
            store.play()
            try await eventually("playing") { store.state.isPlaying }
            try await harness.advance(duration + 1)
            try await eventually("the next track") { store.state.track != nil && store.state.track != first }
        },
    ]
}
