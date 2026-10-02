import AppKit
import Foundation
import PlayerCore
import SwiftUI
import Testing
@testable import NotchUI

/// The notch shows only the pictures the page handed over; it downloads nothing.
@MainActor
@Suite(.serialized)
struct ArtworkTests {
    typealias SilentEngine = PlayingViewTests.SilentEngine

    /// 4 × 4 solid red and blue PNGs.
    static let red = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAIAAAAmkwkpAAAAEElEQVR4nGO4o6EBRwzEcQDzAxLBI9OCRQAAAABJRU5ErkJggg==")!
    static let blue = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAIAAAAmkwkpAAAAEElEQVR4nGPQCLgDRwzEcQAdkhVBx4FAOAAAAABJRU5ErkJggg==")!
    let url = URL(string: "https://x.test/art.jpg")!

    init() {
        _ = NSApplication.shared
    }

    @Test func theNotchShowsArtworkOnceThePageHandsItOver() async throws {
        let engine = SilentEngine()
        let store = PlayerStore(engine: engine)
        engine.report(.ready(bridgeVersion: "1", signedIn: true))
        engine.report(.state(PlaybackSnapshot(track: Track(id: "t", title: "T", artist: "A", artworkURL: url), isPlaying: true)))
        let panel = NotchPanel(screen: Displays.external, store: store, pointer: PointerTracker())
        panel.schedulesTicks = false
        defer { panel.close() }
        #expect(panel.model.artwork == nil, "the placeholder until the page hands it over")
        #expect(panel.model.accent == .white)

        engine.report(.artwork(url: url, data: Self.red))
        try await eventually("the artwork") { panel.model.artwork != nil }
        #expect(panel.model.accent.red > panel.model.accent.blue, "the accent comes from the picture")

        engine.report(.state(PlaybackSnapshot(track: Track(id: "u", title: "U", artist: "A", artworkURL: nil), isPlaying: true)))
        try await eventually("no artwork for a track without one") { panel.model.artwork == nil }
        #expect(panel.model.accent == .white)
    }

    @Test func picturesAreMadeOnceForTheirBytes() {
        let images = ArtworkImages()
        let first = images.image(for: url, data: Self.red)
        #expect(first != nil)
        #expect(images.image(for: url, data: Self.red) === first)
        #expect(images.image(for: url, data: Self.blue) !== first, "new bytes for the address, a new picture")
        #expect(images.image(for: url, data: Data("not a picture".utf8)) == nil)
        #expect(images.artwork(for: url, data: Self.blue)?.accent != .white)
    }

    @Test func aRowShowsItsThumbnailFromThePage() throws {
        let row = ListRow(queueItem: QueueItem(index: 0, title: "Title", artist: "Artist", isCurrent: false, artworkURL: url))
        #expect(row.artworkURL == url)
        func tilePixel(_ image: NSImage?) throws -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
            let view = ZStack {
                Tokens.Color.surface
                ListRowView(row: row, image: image, isPlaying: false, accent: .white, reduceMotion: false) {}
            }
            .frame(width: 384, height: 48)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            return try Pixels(try #require(renderer.cgImage)).at(x: 24, y: 24)
        }
        let placeholder = try tilePixel(nil)
        #expect(placeholder.r < 40 && placeholder.r == placeholder.b, "white 8% on black")
        let shown = try tilePixel(NSImage(data: Self.red))
        #expect(shown.r > 150 && shown.b < 80)
    }
}
