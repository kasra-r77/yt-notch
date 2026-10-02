import Foundation
import Testing
@testable import PlayerCore

/// Copy Diagnostics: what a bug report needs, and nothing from the user's account (D7).
@MainActor
struct DiagnosticsTests {
    let versions = Diagnostics.Versions(app: "0.1.0", build: "7", macOS: "Version 26.3 (Build 25D60)", engine: "web player")

    @Test func versionsHealthAndTheLog() {
        let engine = FakeEngine()
        let store = PlayerStore(engine: engine)
        engine.simulateMissing([.shuffle, .like])
        let report = Diagnostics.report(versions: versions, state: store.state, logLines: ["one", "two"])
        let lines = report.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        #expect(lines[0] == "YT Notch 0.1.0 (7)")
        #expect(lines.contains("macOS Version 26.3 (Build 25D60)"))
        #expect(lines.contains("Engine: web player"))
        #expect(lines.contains("Bridge: \(FakeEngine.bridgeVersion)"))
        #expect(lines.contains("Health: ok"))
        #expect(lines.contains("Can't read: like, shuffle"))
        #expect(lines.contains("Last 2 log lines:"))
        #expect(lines.suffix(2) == ["one", "two"])
    }

    @Test func onlyTheNewestFiftyLogLines() {
        let store = PlayerStore(engine: FakeEngine())
        let log = (1...80).map { "line \($0)" }
        let report = Diagnostics.report(versions: versions, state: store.state, logLines: log)
        #expect(report.contains("Last 50 log lines:"))
        #expect(!report.contains("line 30\n"))
        #expect(report.hasSuffix("line 80"))
    }

    @Test func nothingFromTheAccountOrTheListening() throws {
        let engine = FakeEngine()
        let store = PlayerStore(engine: engine)
        store.play()
        let report = Diagnostics.report(versions: versions, state: store.state, logLines: [])
        let track = try #require(store.state.track)
        let private_ = [track.title, track.artist, track.id] + store.state.playlists.flatMap { [$0.title, $0.id] }
            + store.state.queue.map(\.title)
        for value in private_ {
            #expect(!report.contains(value), "the report holds \(value)")
        }
        #expect(report.contains("Track loaded: yes, playing: yes"))
        #expect(report.contains("Lists: \(store.state.playlists.count) playlists, \(store.state.queue.count) in Up next"))
    }

    @Test func whichStatusesNeedTheUser() {
        #expect(Health.Status.signedOut.needsAttention)
        #expect(Health.Status.offline.needsAttention)
        #expect(Health.Status.bridgeBroken.needsAttention)
        #expect(!Health.Status.ok.needsAttention)
        #expect(!Health.Status.starting.needsAttention)
    }
}
