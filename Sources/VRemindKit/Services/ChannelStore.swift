import Foundation

@MainActor
public final class ChannelStore: ObservableObject {
    public nonisolated static let userDefaultsKey = "vremind.watchlist"

    @Published public private(set) var channels: [WatchedChannel]

    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let data = userDefaults.data(forKey: Self.userDefaultsKey),
           let decoded = try? JSONDecoder().decode([WatchedChannel].self, from: data) {
            self.channels = decoded
        } else {
            let seed = Self.defaultChannels
            self.channels = seed
            if let data = try? JSONEncoder().encode(seed) {
                userDefaults.set(data, forKey: Self.userDefaultsKey)
            }
        }
    }

    private static var defaultChannels: [WatchedChannel] {
        [
            WatchedChannel(
                id: "@bukancaitlyn",
                name: "Caitlyn Momochi",
                handle: "@bukancaitlyn"
            )
        ]
    }

    @discardableResult
    public func addChannel(handle: String, name: String? = nil, avatarURL: URL? = nil) -> WatchedChannel? {
        guard let normalized = WatchedChannel.normalizeHandle(handle) else {
            return nil
        }
        let id = normalized.lowercased()
        guard !channels.contains(where: { $0.id.lowercased() == id }) else {
            return nil
        }

        let resolvedName: String
        if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            resolvedName = name
        } else {
            resolvedName = normalized
        }

        let channel = WatchedChannel(
            id: id,
            name: resolvedName,
            handle: normalized,
            avatarURL: avatarURL
        )
        channels.append(channel)
        save()
        return channel
    }

    public func removeChannel(id: String) {
        let targetId = id.lowercased()
        channels.removeAll { $0.id.lowercased() == targetId }
        save()
    }

    public func updateMetadata(for id: String, name: String?, avatarURL: URL?) {
        let targetId = id.lowercased()
        guard let index = channels.firstIndex(where: { $0.id.lowercased() == targetId }) else {
            return
        }

        var changed = false
        if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            channels[index].name = name
            changed = true
        }
        if let avatarURL {
            channels[index].avatarURL = avatarURL
            changed = true
        }

        if changed {
            save()
        }
    }

    public func updateStatus(
        for id: String,
        status: StreamStatus,
        notifiedLiveId: String? = nil,
        notifiedUpcomingId: String? = nil
    ) {
        let targetId = id.lowercased()
        guard let index = channels.firstIndex(where: { $0.id.lowercased() == targetId }) else {
            return
        }

        var changed = false
        if let notifiedLiveId {
            channels[index].lastNotifiedVideoId = notifiedLiveId
            changed = true
        }
        if let notifiedUpcomingId {
            channels[index].lastNotifiedUpcomingId = notifiedUpcomingId
            changed = true
        }

        switch status {
        case .live(_, _, let startedAt):
            channels[index].lastStreamedAt = startedAt ?? Date()
            changed = true
        case .offline(let lastStreamed):
            if let lastStreamed {
                channels[index].lastStreamedAt = lastStreamed
                changed = true
            }
        case .upcoming, .unknown:
            break
        }

        if changed {
            save()
        }
    }

    public func resetToDefaults() {
        let seed = Self.defaultChannels
        channels = seed
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(channels) {
            userDefaults.set(data, forKey: Self.userDefaultsKey)
        }
    }
}
