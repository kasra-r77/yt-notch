import Foundation
import PlayerCore
import Testing
@testable import WebPlayer

/// The pictures the bridge hands over (YT-40): the track's artwork and the queue's
/// thumbnails, read through the page, each once while in use. The fixture answers the
/// page's requests for them itself, so nothing here touches the network.
@MainActor
@Suite(.serialized)
struct BridgeArtworkTests {
    let page = BridgeHarness()

    static func art(_ name: String) -> URL { URL(string: "https://fixture.ytnotch.test/art/\(name).jpg")! }

    var pictures: [URL: Data] {
        var pictures: [URL: Data] = [:]
        for case let .artwork(url, data) in page.events where pictures[url] == nil { pictures[url] = data }
        return pictures
    }

    var pictureMessages: Int {
        page.events.filter { if case .artwork = $0 { true } else { false } }.count
    }

    func picture(_ track: String) async throws -> Data {
        let text = try await page.js("return window.fixture.pictures.\(track)") as? String
        return try #require(text.flatMap { Data(base64Encoded: $0) })
    }

    func requests() async throws -> [[String: Any]] {
        try await page.js("return window.fixture.artRequests") as? [[String: Any]] ?? []
    }

    /// Asks the bridge to report everything again a few times, then waits for any reads.
    func reportAgain() async throws {
        for _ in 0..<3 {
            try await page.js("window.__ytNotch.refresh(); window.fixture.advance(1)")
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    @Test func handsOverTheTrackArtworkAndTheQueueThumbnails() async throws {
        try await page.load()
        try await page.wait("four pictures") { _ in pictures.count == 4 }
        let red = try await picture("a")
        let blue = try await picture("b")
        let green = try await picture("c")
        #expect(pictures == [Self.art("a-226"): red, Self.art("a-120"): red, Self.art("b-120"): blue, Self.art("c-120"): green],
                "every queue item's, including those the page hasn't scrolled to")
    }

    @Test func readsThroughThePageFromItsCacheWithoutCookies() async throws {
        try await page.load()
        try await page.wait("four pictures") { _ in pictures.count == 4 }
        let requests = try await requests()
        #expect(requests.count == 4)
        for request in requests {
            #expect(request["cache"] as? String == "force-cache")
            #expect(request["credentials"] as? String == "omit")
            #expect(request["mode"] as? String == "cors")
        }
    }

    @Test func eachPictureOnceWhileItIsInUse() async throws {
        try await page.load()
        try await page.wait("four pictures") { _ in pictures.count == 4 }
        try await reportAgain()
        #expect(try await requests().count == 4)
        #expect(pictureMessages == 4)
    }

    @Test func aNewTrackBringsItsArtwork() async throws {
        try await page.load()
        try await page.wait("four pictures") { _ in pictures.count == 4 }
        try await page.send(.next)
        let blue = try await picture("b")
        try await page.wait("the second track's artwork") { _ in pictures[Self.art("b-226")] == blue }
    }

    @Test(arguments: ["art-fails", "art-big", "art-not-image"])
    func picturesThePageCantHandOverAreLeftOut(option: String) async throws {
        try await page.load(option)
        let deadline = Date().addingTimeInterval(5)
        while try await requests().count < 4 {
            if Date() > deadline { throw BridgeHarness.HarnessError.timedOut("four requests") }
            try await Task.sleep(for: .milliseconds(20))
        }
        try await reportAgain()
        #expect(pictureMessages == 0)
        #expect(try await requests().count == 4, "no retrying while the pictures stay in use")
        #expect(try await page.pageErrors().isEmpty)
    }
}
