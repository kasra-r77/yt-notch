import AppKit

/// NotchUI downloads nothing: a picture the store doesn't have shows as the placeholder.
@MainActor
final class ArtworkImages {
    static let shared = ArtworkImages()

    struct Artwork: Equatable {
        let image: NSImage
        let accent: AccentColor
    }

    private struct Entry {
        let data: Data
        let image: NSImage
        var accent: AccentColor?
    }

    private var entries: [URL: Entry] = [:]
    private var order: [URL] = []
    /// Enough for a long Up next list's thumbnails as well as the track's artwork.
    private let limit = 64

    func image(for url: URL, data: Data) -> NSImage? {
        entry(for: url, data: data)?.image
    }

    func artwork(for url: URL, data: Data) -> Artwork? {
        guard var entry = entry(for: url, data: data) else { return nil }
        if entry.accent == nil {
            entry.accent = AccentColor.from(entry.image.cgImage(forProposedRect: nil, context: nil, hints: nil))
            entries[url] = entry
        }
        return Artwork(image: entry.image, accent: entry.accent ?? .white)
    }

    private func entry(for url: URL, data: Data) -> Entry? {
        if let entry = entries[url], entry.data == data { return entry }
        guard let image = NSImage(data: data) else { return nil }
        let entry = Entry(data: data, image: image)
        entries[url] = entry
        order.removeAll { $0 == url }
        order.append(url)
        while order.count > limit {
            entries[order.removeFirst()] = nil
        }
        return entry
    }
}
