import Foundation

public protocol PlaylistCache {
    func load() -> [PlaylistItem]
    func save(_ items: [PlaylistItem])
}

public struct UserDefaultsPlaylistCache: PlaylistCache {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "cachedPlaylists") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> [PlaylistItem] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([PlaylistItem].self, from: data)) ?? []
    }

    public func save(_ items: [PlaylistItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: key)
    }
}
