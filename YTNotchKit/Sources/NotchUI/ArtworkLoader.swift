import AppKit
import OSLog

/// Loads track artwork for the notch and works out its accent colour, keeping the last few.
///
/// Artwork comes straight from the image address the player reports, through an ephemeral
/// session: no cookies, no cache on disk, nothing sent but the request for the picture.
@MainActor
final class ArtworkLoader {
    static let shared = ArtworkLoader()

    struct Artwork: Equatable {
        let image: NSImage
        let accent: AccentColor
    }

    private var cache: [URL: Artwork] = [:]
    private var order: [URL] = []
    private var inFlight: [URL: Task<Data?, Never>] = [:]
    /// Enough for a long Up next list's thumbnails as well as the track's artwork.
    private let limit = 64
    private let session: URLSession
    private let log = Logger(subsystem: "io.github.kasra-r77.ytnotch", category: "NotchUI")

    init(session: URLSession = URLSession(configuration: .ephemeral)) {
        self.session = session
    }

    func cached(_ url: URL) -> Artwork? { cache[url] }

    func artwork(for url: URL) async -> Artwork? {
        if let cached = cache[url] { return cached }
        // Only the bytes cross from the download; the image and its accent are made here.
        let task: Task<Data?, Never>
        if let running = inFlight[url] {
            task = running
        } else {
            task = Task.detached { [session, log] () -> Data? in
                do {
                    return try await session.data(from: url).0
                } catch {
                    log.notice("artwork failed to load: \(error.localizedDescription, privacy: .public)")
                    return nil
                }
            }
            inFlight[url] = task
        }
        let data = await task.value
        inFlight[url] = nil
        if let cached = cache[url] { return cached }
        guard let data, let image = NSImage(data: data) else { return nil }
        let artwork = Artwork(image: image, accent: AccentColor.from(image.cgImage(forProposedRect: nil, context: nil, hints: nil)))
        remember(artwork, for: url)
        return artwork
    }

    func remember(_ artwork: Artwork, for url: URL) {
        cache[url] = artwork
        order.removeAll { $0 == url }
        order.append(url)
        while order.count > limit {
            cache[order.removeFirst()] = nil
        }
    }
}
