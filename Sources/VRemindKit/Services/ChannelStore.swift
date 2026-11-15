import Foundation
import VRemindCore

private struct SendableUserDefaults: @unchecked Sendable {
    let defaults: UserDefaults
}

@MainActor
public final class ChannelStore: ObservableObject {
    public nonisolated static let userDefaultsKey = "vremind.watchlist"

    @Published public private(set) var channels: [WatchedChannel]

    private let storage: SendableUserDefaults
    private var userDefaults: UserDefaults { storage.defaults }

    public init(userDefaults: UserDefaults = .standard) {
        self.storage = SendableUserDefaults(defaults: userDefaults)
        if let data = userDefaults.data(forKey: Self.userDefaultsKey),
           let decoded = try? JSONDecoder().decode([WatchedChannel].self, from: data) {
            self.channels = decoded

            var needsResave = false
            if let rawArray = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] {
                for dict in rawArray {
                    if dict["platform"] == nil {
                        needsResave = true
                        break
                    }
                    if let id = dict["id"] as? String, !id.contains(":") {
                        needsResave = true
                        break
                    }
                }
            }
            if needsResave {
                save()
            }
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
                id: "youtube:@bukancaitlyn",
                platform: .youtube,
                name: "Caitlyn Momochi",
                handle: "@bukancaitlyn"
            )
        ]
    }

    @discardableResult
    public func addChannel(
        platform: StreamPlatform = .youtube,
        handle: String,
        name: String? = nil,
        avatarURL: URL? = nil
    ) -> WatchedChannel? {
        guard let normalized = WatchedChannel.normalizeHandle(handle, for: platform) else {
            return nil
        }
        let id = WatchedChannel.makeID(platform: platform, handle: normalized)
        guard !channels.contains(where: { $0.id.lowercased() == id.lowercased() }) else {
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
            platform: platform,
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
        channels.removeAll {
            $0.id.lowercased() == targetId ||
            (!targetId.contains(":") && $0.id.lowercased() == "youtube:\(targetId)")
        }
        save()
    }

    public func updateMetadata(for id: String, name: String?, avatarURL: URL?) {
        let targetId = id.lowercased()
        guard let index = channels.firstIndex(where: {
            $0.id.lowercased() == targetId ||
            (!targetId.contains(":") && $0.id.lowercased() == "youtube:\(targetId)")
        }) else {
            return
        }

        var candidate = channels[index]
        if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            candidate.name = name
        }
        if let avatarURL {
            candidate.avatarURL = avatarURL
        }

        if candidate != channels[index] {
            channels[index] = candidate
            save()
        }
    }

    public func updateStatus(
        for id: String,
        status: StreamStatus,
        notifiedLiveId: String? = nil,
        notifiedUpcomingId: String? = nil,
        didTransitionToLive: Bool = false
    ) {
        let targetId = id.lowercased()
        guard let index = channels.firstIndex(where: {
            $0.id.lowercased() == targetId ||
            (!targetId.contains(":") && $0.id.lowercased() == "youtube:\(targetId)")
        }) else {
            return
        }

        var candidate = channels[index]
        let isNewLiveNotification = notifiedLiveId != nil && notifiedLiveId != channels[index].lastNotifiedVideoId
        if let notifiedLiveId {
            candidate.lastNotifiedVideoId = notifiedLiveId
        }
        if let notifiedUpcomingId {
            candidate.lastNotifiedUpcomingId = notifiedUpcomingId
        }

        switch status {
        case .live(_, _, let startedAt):
            if let startedAt {
                candidate.lastStreamedAt = startedAt
            } else if candidate.lastStreamedAt == nil || didTransitionToLive || isNewLiveNotification {
                candidate.lastStreamedAt = Date()
            }
        case .offline(let lastStreamed):
            if let lastStreamed {
                candidate.lastStreamedAt = lastStreamed
            }
        case .upcoming, .unknown:
            break
        }

        if candidate != channels[index] {
            channels[index] = candidate
            save()
        }
    }

    public func reorderSection(orderedSectionIds: [String]) {
        let reordered = ChannelOrderPolicy.reorderWatchlistSlots(
            channels: channels,
            orderedSectionIds: orderedSectionIds
        )
        if reordered != channels {
            channels = reordered
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

extension ChannelStore: ChannelStorage, @unchecked Sendable {
    public nonisolated func loadChannels() throws -> [WatchedChannel] {
        guard let data = storage.defaults.data(forKey: Self.userDefaultsKey) else {
            return []
        }
        return try JSONDecoder().decode([WatchedChannel].self, from: data)
    }

    public nonisolated func saveChannels(_ channels: [WatchedChannel]) throws {
        let data = try JSONEncoder().encode(channels)
        storage.defaults.set(data, forKey: Self.userDefaultsKey)
        Task { @MainActor in
            self.channels = channels
        }
    }
}
