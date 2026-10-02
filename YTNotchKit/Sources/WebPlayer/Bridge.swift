import Foundation
import PlayerCore

/// The Swift side of the bridge contract: the script to inject, how its messages become
/// PlayerEvents, and how PlayerCommands become calls into it. Everything the app knows about
/// the site itself stays in `bridge.js`.
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

    // MARK: Commands

    /// The body for `callAsyncJavaScript` that runs a command, with `arguments(for:)`.
    /// It resolves to `{ ok, error? }`.
    public static let commandFunctionBody = """
    return window.__ytNotch ? window.__ytNotch.command(name, value) : { ok: false, error: 'bridge not attached' };
    """

    /// Asks the bridge to report everything again. Resolves to false when it isn't attached.
    public static let refreshFunctionBody = """
    return Boolean(window.__ytNotch && window.__ytNotch.refresh && window.__ytNotch.refresh());
    """

    /// The `name` and `value` arguments for `commandFunctionBody`.
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

    // MARK: Messages

    /// Turns a message body posted by the script into an event, or nil when it isn't one.
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
                return PlaylistItem(id: id, title: title, thumbnailURL: url(item["thumbnailURL"]))
            }
            return .playlists(items)
        case "queue":
            let items = (message["items"] as? [[String: Any]] ?? []).compactMap { item -> QueueItem? in
                guard let index = item["index"] as? Int, let title = item["title"] as? String else { return nil }
                return QueueItem(
                    index: index,
                    title: title,
                    artist: item["artist"] as? String ?? "",
                    isCurrent: item["isCurrent"] as? Bool ?? false
                )
            }
            return .queue(items)
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
            liked: message["liked"] as? Bool ?? false
        )
    }

    private static func url(_ value: Any?) -> URL? {
        (value as? String).flatMap(URL.init(string:))
    }
}
