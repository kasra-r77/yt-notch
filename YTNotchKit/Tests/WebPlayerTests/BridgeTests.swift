import Foundation
import PlayerCore
import Testing
@testable import WebPlayer

/// bridge.js against the fixture page: every message and every command, with no Google.
@MainActor
@Suite(.serialized)
struct BridgeTests {
    let page = BridgeHarness()

    // MARK: Messages

    @Test func readyReportsVersionAndSignIn() async throws {
        try await page.load()
        #expect(page.events.first == .ready(bridgeVersion: "1", signedIn: true))
    }

    /// The bridge reads the player and nothing a person types: a password typed into the
    /// page never shows up in anything it posts.
    @Test func neverReportsWhatIsTypedIntoThePage() async throws {
        try await page.load()
        let secret = "correct horse battery staple"
        try await page.js("""
            const form = document.createElement('form');
            for (const type of ['email', 'password', 'text']) {
              const input = document.createElement('input');
              input.type = type;
              input.name = type;
              input.value = '\(secret)';
              form.appendChild(input);
            }
            document.body.appendChild(form);
            form.querySelectorAll('input').forEach((input) => input.dispatchEvent(new Event('input', { bubbles: true })));
            window.__ytNotch.refresh();
            window.fixture.advance(1);
            """)
        try await Task.sleep(for: .milliseconds(300))
        #expect(page.messages.count > 3)
        #expect(!page.messages.map { String(describing: $0) }.joined().contains(secret))
    }

    @Test func readyReportsSignedOut() async throws {
        try await page.load("signed-out")
        #expect(page.events.first == .ready(bridgeVersion: "1", signedIn: false))
    }

    @Test func stateDescribesTheLoadedTrack() async throws {
        try await page.load()
        let snapshot = try await page.any("state") { $0.snapshot }
        let track = try #require(snapshot.track)
        #expect(track.title == "First Song")
        #expect(track.artist == "The Fixtures")
        #expect(track.album == "Test Album")
        #expect(track.duration == 200)
        #expect(track.id.hasPrefix("m"))
        #expect(track.artworkURL?.absoluteString == "https://fixture.ytnotch.test/art/a-226.jpg")
        #expect(snapshot.position == 0)
        #expect(!snapshot.isPlaying)
        #expect(snapshot.canNext && snapshot.canPrevious)
        #expect(!snapshot.liked)
    }

    @Test func healthIsOKWhenEverythingIsThere() async throws {
        try await page.load()
        #expect(try await page.any("health") { $0.missing } == [])
        #expect(page.messages.contains { $0["type"] as? String == "health" && $0["ok"] as? Bool == true })
    }

    @Test func playerControlsAreNotMissingWhenNothingIsLoaded() async throws {
        try await page.load("empty")
        let missing = try await page.any("health") { $0.missing }
        #expect(missing.isDisjoint(with: [.playPause, .seek, .next, .previous, .like]))
        #expect(page.latestSnapshot?.track == nil)
    }

    @Test func missingLikeButtonIsReported() async throws {
        try await page.load("no-like")
        #expect(try await page.any("health") { $0.missing } == [.like])
    }

    @Test func missingVideoIsReported() async throws {
        try await page.load()
        try await page.js("window.fixture.removeVideo()")
        let missing = try await page.next("health without video") { $0.missing.flatMap { $0.isEmpty ? nil : $0 } }
        #expect(missing.isSuperset(of: [.playPause, .seek]))
    }

    @Test func signedOutWhenThePageShowsItsSignInPrompt() async throws {
        try await page.load()
        try await page.js("window.fixture.signOut()")
        try await page.next("signedOut", timeout: 6) { $0 == .signedOut ? true : nil }
    }

    @Test func trackChangeIsReported() async throws {
        try await page.load()
        try await page.js("window.fixture.setTrack(2)")
        let track = try await page.next("new track") { $0.snapshot?.track.flatMap { $0.title == "Third Song" ? $0 : nil } }
        #expect(track.album == nil)
        #expect(track.artist == "Someone Else")
    }

    @Test func positionIsReportedEverySecondWhilePlaying() async throws {
        try await page.load()
        try await page.send(.play)
        try await page.js("window.fixture.advance(10)")
        let first = try await page.next("heartbeat") { $0.snapshot.flatMap { $0.position >= 10 ? $0 : nil } }
        try await page.js("window.fixture.advance(5)")
        let second = try await page.next("next heartbeat", timeout: 3) { $0.snapshot.flatMap { $0.position >= 15 ? $0 : nil } }
        #expect(first.isPlaying && second.isPlaying)
    }

    // MARK: Commands

    @Test func play() async throws {
        try await page.load()
        #expect(try await page.send(.play)["ok"] as? Bool == true)
        try await page.next("playing") { $0.snapshot.flatMap { $0.isPlaying ? true : nil } }
    }

    @Test func pause() async throws {
        try await page.load()
        try await page.send(.play)
        try await page.next("playing") { $0.snapshot.flatMap { $0.isPlaying ? true : nil } }
        try await page.send(.pause)
        try await page.next("paused") { $0.snapshot.flatMap { $0.isPlaying ? nil : true } }
    }

    @Test func toggle() async throws {
        try await page.load()
        try await page.send(.toggle)
        try await page.next("playing") { $0.snapshot.flatMap { $0.isPlaying ? true : nil } }
        try await page.send(.toggle)
        try await page.next("paused") { $0.snapshot.flatMap { $0.isPlaying ? nil : true } }
    }

    @Test func nextUsesTheSitesHandler() async throws {
        try await page.load()
        try await page.send(.next)
        try await page.next("second track") { $0.snapshot?.track?.title == "Second Song" ? true : nil }
    }

    @Test func nextWithoutAHandlerRunsToTheEnd() async throws {
        try await page.load("no-handlers")
        try await page.send(.play)
        try await page.send(.next)
        let nearEnd = try await page.next("near the end") { $0.snapshot.flatMap { $0.position >= 199 ? $0 : nil } }
        #expect(nearEnd.track?.title == "First Song")
        try await page.js("window.fixture.advance(1)")
        try await page.next("second track") { $0.snapshot?.track?.title == "Second Song" ? true : nil }
    }

    @Test func previousUsesTheSitesHandler() async throws {
        try await page.load()
        try await page.send(.next)
        try await page.next("second track") { $0.snapshot?.track?.title == "Second Song" ? true : nil }
        try await page.send(.previous)
        try await page.next("first track again") { $0.snapshot?.track?.title == "First Song" ? true : nil }
    }

    @Test func previousWithoutAHandlerRestarts() async throws {
        try await page.load("no-handlers")
        try await page.send(.seek(to: 80))
        try await page.next("at 80") { $0.snapshot.flatMap { $0.position == 80 ? true : nil } }
        try await page.send(.previous)
        try await page.next("restarted") { $0.snapshot.flatMap { $0.position == 0 ? true : nil } }
    }

    @Test func handlerRemovedByThePageIsForgotten() async throws {
        try await page.load()
        try await page.js("window.fixture.unregister('nexttrack')")
        try await page.send(.play)
        try await page.send(.next)
        try await page.next("ran to the end instead") { $0.snapshot.flatMap { $0.position >= 199 ? true : nil } }
    }

    @Test(arguments: [(42.0, 42.0), (-3, 0), (500, 200)])
    func seek(to target: Double, lands: Double) async throws {
        try await page.load()
        try await page.send(.seek(to: 50))
        try await page.next("at 50") { $0.snapshot.flatMap { $0.position == 50 ? true : nil } }
        try await page.send(.seek(to: target))
        try await page.next("seeked") { $0.snapshot.flatMap { $0.position == lands ? true : nil } }
    }

    @Test func setLiked() async throws {
        try await page.load()
        try await page.send(.setLiked(true))
        try await page.next("liked") { $0.snapshot.flatMap { $0.liked ? true : nil } }
        try await page.send(.setLiked(true))
        #expect(try await page.js("return window.fixture.status().liked") as? Bool == true)
        try await page.send(.setLiked(false))
        try await page.next("unliked") { $0.snapshot.flatMap { $0.liked ? nil : true } }
    }

    // MARK: Never throws

    @Test func unknownCommandFailsQuietly() async throws {
        try await page.load()
        let result = try await page.js("return window.__ytNotch.command('dance', 1)") as? [String: Any]
        #expect(result?["ok"] as? Bool == false)
        #expect(try await page.pageErrors().isEmpty)
    }

    @Test func likeWithoutAButtonFailsAndShowsInHealth() async throws {
        try await page.load()
        try await page.js("window.fixture.removeLikeButton()")
        let result = try await page.send(.setLiked(true))
        #expect(result["ok"] as? Bool == false)
        try await page.next("like missing") { $0.missing.flatMap { $0.contains(.like) ? true : nil } }
        #expect(try await page.pageErrors().isEmpty)
    }

    @Test(arguments: [PlayerCommand.play, .pause, .toggle, .previous, .seek(to: 5)])
    func commandsWithNoVideoFailQuietly(command: PlayerCommand) async throws {
        try await page.load("empty")
        #expect(try await page.send(command)["ok"] as? Bool == false)
        #expect(try await page.pageErrors().isEmpty)
    }

    @Test func pageKeepsWorkingAfterEveryCommand() async throws {
        try await page.load()
        for command in [PlayerCommand.play, .seek(to: 30), .next, .previous, .setLiked(true), .toggle, .pause] {
            try await page.send(command)
        }
        try await page.js("window.fixture.advance(1)")
        #expect(try await page.pageErrors().isEmpty)
    }

    @Test func injectingTwiceKeepsOneBridge() async throws {
        try await page.load()
        try await page.js(Bridge.script)
        let readies = page.messages.filter { $0["type"] as? String == "ready" }.count
        #expect(readies == 1)
        #expect(try await page.js("return window.__ytNotch.version") as? String == "1")
    }
}
