import Combine
import Foundation

@MainActor
public final class WatchlistService: ObservableObject {
    public nonisolated static let maxSlots = 3
    public nonisolated static let userDefaultsKey = "caitlynswift.watched_channels"

    @Published public private(set) var customChannels: [WatchedChannel] = []
    @Published public private(set) var statuses: [String: StreamStatus] = [:]

    private let configService: ConfigSyncService
    private let userDefaults: UserDefaults
    private let fetcher: LiveStatusService.Fetcher
    private var cancellables: Set<AnyCancellable> = []

    public init(
        configService: ConfigSyncService,
        userDefaults: UserDefaults = .standard,
        fetcher: LiveStatusService.Fetcher? = nil
    ) {
        self.configService = configService
        self.userDefaults = userDefaults
        self.fetcher = fetcher ?? Self.defaultFetcher

        self.customChannels = Self.loadCustomChannels(from: userDefaults)

        configService.$config
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    public var caitlynChannel: WatchedChannel {
        WatchedChannel(
            name: "Caitlyn Momochi",
            handle: configService.config.channelHandle,
            avatarURL: configService.config.avatarURL,
            isPinned: true
        )
    }

    public var channels: [WatchedChannel] {
        let pinned = caitlynChannel
        let extras = customChannels
            .filter { $0.id != pinned.id }
            .prefix(Self.maxSlots - 1)
        return [pinned] + extras
    }

    public var isAnyLive: Bool {
        channels.contains { statuses[$0.id]?.isLive == true }
    }

    public func status(for channel: WatchedChannel) -> StreamStatus {
        statuses[channel.id] ?? .offline
    }

    @discardableResult
    public func addChannel(name: String, handle: String, avatarURL: URL? = nil) -> Bool {
        guard channels.count < Self.maxSlots else { return false }
        guard let normalized = WatchedChannel.normalizeHandle(handle) else { return false }
        let candidateID = normalized.lowercased()
        guard !channels.contains(where: { $0.id == candidateID }) else { return false }

        let channel = WatchedChannel(
            name: name,
            handle: normalized,
            avatarURL: avatarURL,
            isPinned: false
        )
        customChannels.append(channel)
        saveCustomChannels()
        return true
    }

    @discardableResult
    public func removeChannel(id: String) -> Bool {
        let targetID = id.lowercased()
        guard targetID != caitlynChannel.id else { return false }
        guard let index = customChannels.firstIndex(where: { $0.id == targetID }) else {
            return false
        }
        customChannels.remove(at: index)
        statuses.removeValue(forKey: targetID)
        saveCustomChannels()
        return true
    }

    public func refreshAll() async {
        let activeChannels = channels
        let fetcher = self.fetcher

        let updates: [(String, LivePageResult?, URL?)] = await withTaskGroup(
            of: (String, LivePageResult?, URL?).self
        ) { group in
            for channel in activeChannels {
                group.addTask {
                    guard let url = URL(string: "https://www.youtube.com/\(channel.handle)/live") else {
                        return (channel.id, nil, nil)
                    }
                    do {
                        let html = try await fetcher(url)
                        return (
                            channel.id,
                            LivePageParser.parse(html: html),
                            LivePageParser.extractAvatarURL(from: html)
                        )
                    } catch {
                        return (channel.id, nil, nil)
                    }
                }
            }
            var collected: [(String, LivePageResult?, URL?)] = []
            for await item in group {
                collected.append(item)
            }
            return collected
        }

        var nextStatuses = statuses
        var didUpdateAvatars = false
        for (channelID, result, extractedAvatar) in updates {
            if let extractedAvatar,
               let idx = customChannels.firstIndex(where: { $0.id == channelID }),
               customChannels[idx].avatarURL == nil {
                customChannels[idx].avatarURL = extractedAvatar
                didUpdateAvatars = true
            }
            guard let result else { continue }
            switch result {
            case let .live(videoId, title, startedAt):
                nextStatuses[channelID] = StreamStatus(
                    isLive: true,
                    videoId: videoId,
                    title: title,
                    startedAt: startedAt
                )
            case .notLive:
                nextStatuses[channelID] = .offline
            case .unrecognized:
                break
            }
        }
        if didUpdateAvatars {
            saveCustomChannels()
        }
        self.statuses = nextStatuses
    }

    private func saveCustomChannels() {
        if let data = try? JSONEncoder().encode(customChannels) {
            userDefaults.set(data, forKey: Self.userDefaultsKey)
        }
    }

    private static func loadCustomChannels(from userDefaults: UserDefaults) -> [WatchedChannel] {
        guard let data = userDefaults.data(forKey: userDefaultsKey),
              let decoded = try? JSONDecoder().decode([WatchedChannel].self, from: data) else {
            return []
        }
        return Array(decoded.filter { !$0.isPinned }.prefix(maxSlots - 1))
    }

    private static let defaultFetcher: LiveStatusService.Fetcher = { url in
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return String(decoding: data, as: UTF8.self)
    }
}
