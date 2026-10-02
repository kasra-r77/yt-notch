import Foundation
import PlayerCore

/// The Swift side of the bridge contract. Everything the app knows about the site itself
/// stays in `bridge.js`.
public enum Bridge {
    /// The `window.webkit.messageHandlers` name the script posts to.
    public static let messageHandlerName = "ytNotch"

    /// `bridge.js`, shipped inside the app. Never downloaded.
    public static let script: String = {
        guard let url = Bundle.module.url(forResource: "bridge", withExtension: "js"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            preconditionFailure("bridge.js is missing from the WebPlayer bundle")
        }
        return text
    }()

    /// Run with `arguments(for:)`; resolves to `{ ok, error? }`.
    public static let commandFunctionBody = """
    return window.__ytNotch ? window.__ytNotch.command(name, value) : { ok: false, error: 'bridge not attached' };
    """

    public static let refreshFunctionBody = """
    return Boolean(window.__ytNotch && window.__ytNotch.refresh && window.__ytNotch.refresh());
    """

    public static func arguments(for command: PlayerCommand) -> [String: Any] {
        let (name, value): (String, Any) = switch command {
        case .play: ("play", NSNull())
        case .pause: ("pause", NSNull())
        case .toggle: ("toggle", NSNull())
        case .next: ("next", NSNull())
        case .previous: ("previous", NSNull())
        case let .seek(seconds): ("seek", seconds)
        case let .setLiked(liked): ("setLiked", liked)
        case let .playPlaylist(id): ("playPlaylist", id)
        case let .playQueueItem(index): ("playQueueItem", index)
        case let .setShuffle(isOn): ("setShuffle", isOn)
        case let .setRepeat(mode): ("setRepeat", mode.rawValue)
        }
        return ["name": name, "value": value]
    }

    /// Not a player command: only the full window opens the site's sign-in.
    public static var signInArguments: [String: Any] { ["name": "signIn", "value": NSNull()] }

    public static func event(from body: Any) -> PlayerEvent? {
        guard let message = body as? [String: Any], let type = message["type"] as? String else { return nil }
        switch type {
        case "ready":
            guard let version = message["bridgeVersion"] as? String,
                  let signedIn = message["signedIn"] as? Bool else { return nil }
            return .ready(bridgeVersion: version, signedIn: signedIn)
        case "state":
            return .state(snapshot(from: message))
        case "health":
            let names = message["missing"] as? [String] ?? []
            return .health(missing: Set(names.compactMap(Feature.init(rawValue:))))
        case "signedOut":
            return .signedOut
        case "playlists":
            let items = (message["items"] as? [[String: Any]] ?? []).compactMap { item -> PlaylistItem? in
                guard let id = item["id"] as? String, let title = item["title"] as? String else { return nil }
                return PlaylistItem(id: id, title: title, thumbnailURL: url(item["thumbnailURL"]),
                                    isLikedMusic: item["isLikedMusic"] as? Bool ?? false)
            }
            return .playlists(items)
        case "queue":
            let items = (message["items"] as? [[String: Any]] ?? []).compactMap { item -> QueueItem? in
                guard let index = item["index"] as? Int, let title = item["title"] as? String else { return nil }
                return QueueItem(
                    index: index,
                    title: title,
                    artist: item["artist"] as? String ?? "",
                    isCurrent: item["isCurrent"] as? Bool ?? false,
                    artworkURL: url(item["artworkURL"]),
                    duration: item["duration"] as? Double
                )
            }
            return .queue(items)
        case "artwork":
            guard let url = url(message["url"]), let text = message["data"] as? String,
                  let data = Data(base64Encoded: text), !data.isEmpty else { return nil }
            return .artwork(url: url, data: data)
        case "modes":
            let shuffle = message["shuffle"] as? Bool
            let mode = (message["repeat"] as? String).flatMap(RepeatMode.init(rawValue:))
            guard shuffle != nil || mode != nil else { return nil }
            return .modes(shuffle: shuffle, repeatMode: mode)
        default:
            return nil
        }
    }

    private static func snapshot(from message: [String: Any]) -> PlaybackSnapshot {
        var track: Track?
        if let id = message["trackId"] as? String, let title = message["title"] as? String {
            track = Track(
                id: id,
                title: title,
                artist: message["artist"] as? String ?? "",
                album: message["album"] as? String,
                artworkURL: url(message["artworkURL"]),
                duration: message["duration"] as? Double
            )
        }
        return PlaybackSnapshot(
            track: track,
            position: message["position"] as? Double ?? 0,
            isPlaying: message["isPlaying"] as? Bool ?? false,
            canNext: message["canNext"] as? Bool ?? false,
            canPrevious: message["canPrevious"] as? Bool ?? false,
            liked: message["liked"] as? Bool ?? false,
            playlistID: message["playlistId"] as? String
        )
    }

    private static func url(_ value: Any?) -> URL? {
        (value as? String).flatMap(URL.init(string:))
    }
}
