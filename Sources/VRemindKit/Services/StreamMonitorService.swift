import AppKit
import Foundation

@MainActor
public final class StreamMonitorService: ObservableObject {
    public typealias Fetcher = @Sendable (URL) async throws -> (Data, URLResponse)

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()

    public nonisolated static let defaultFetcher: Fetcher = { url in
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        return try await session.data(for: request)
    }

    @Published public private(set) var isRefreshing: Bool = false
    @Published public private(set) var statuses: [String: StreamStatus] = [:]

    public let channelStore: ChannelStore
    public let preferencesStore: PreferencesStore
    public let notificationService: NotificationService
    public let fetcher: Fetcher
    public let snapshotStore: WidgetSnapshotStoreProtocol

    public private(set) var isPolling: Bool = false
    public private(set) var isPausedForSleep: Bool = false

    private let notificationCenter: NotificationCenter
    private var pollingTask: Task<Void, Never>?
    private var pollingInterval: TimeInterval = AppConstants.livePollInterval
    private var sleepObserver: (any NSObjectProtocol)?
    private var wakeObserver: (any NSObjectProtocol)?
    private var needsAnotherRefresh: Bool = false

    public init(
        channelStore: ChannelStore,
        preferencesStore: PreferencesStore,
        notificationService: NotificationService,
        fetcher: @escaping Fetcher = StreamMonitorService.defaultFetcher,
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        snapshotStore: WidgetSnapshotStoreProtocol = WidgetSnapshotStore.shared
    ) {
        self.channelStore = channelStore
        self.preferencesStore = preferencesStore
        self.notificationService = notificationService
        self.fetcher = fetcher
        self.notificationCenter = notificationCenter
        self.snapshotStore = snapshotStore
    }

    public var isAnyLive: Bool {
        channelStore.channels.contains { channel in
            if case .live = statuses[channel.id] {
                return true
            }
            return false
        }
    }

    public func status(for channel: WatchedChannel) -> StreamStatus {
        statuses[channel.id] ?? .unknown
    }

    public func exportWidgetSnapshot() async {
        do {
            try await snapshotStore.writeSnapshot(
                channels: channelStore.channels,
                statuses: statuses
            )
        } catch {
            NSLog("Failed to export widget snapshot: %@", error.localizedDescription)
        }
    }

    public func refreshAll() async {
        if isRefreshing {
            needsAnotherRefresh = true
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }

        repeat {
            needsAnotherRefresh = false
            await performRefreshPass()
        } while needsAnotherRefresh && !Task.isCancelled
    }

    private func performRefreshPass() async {
        let channels = channelStore.channels
        guard !channels.isEmpty else {
            await exportWidgetSnapshot()
            return
        }

        let batchSize = 3
        let fetch = self.fetcher

        for startIndex in stride(from: 0, to: channels.count, by: batchSize) {
            guard !Task.isCancelled else { break }
            let endIndex = min(startIndex + batchSize, channels.count)
            let batch = Array(channels[startIndex..<endIndex])

            typealias FetchOutcome = (
                channel: WatchedChannel,
                result: Result<(LivePageResult, String?, URL?), Error>
            )

            let outcomes: [FetchOutcome] = await withTaskGroup(of: FetchOutcome.self) { group in
                for channel in batch {
                    group.addTask {
                        let urlString: String
                        if channel.handle.hasPrefix("@") {
                            urlString = "https://www.youtube.com/\(channel.handle)/live"
                        } else {
                            urlString = "https://www.youtube.com/@\(channel.handle)/live"
                        }

                        guard let url = URL(string: urlString) else {
                            return (channel, .failure(URLError(.badURL)))
                        }

                        do {
                            let (data, _) = try await fetch(url)
                            let outcome = autoreleasepool { () -> (LivePageResult, String?, URL?) in
                                guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                                    return (.unrecognized, nil, nil)
                                }
                                let parsed = LivePageParser.parse(html: html)
                                let extractedTitle = LivePageParser.extractChannelTitle(from: html)
                                let extractedAvatar = LivePageParser.extractAvatarURL(from: html)
                                return (parsed, extractedTitle, extractedAvatar)
                            }
                            return (channel, .success(outcome))
                        } catch {
                            return (channel, .failure(error))
                        }
                    }
                }

                var collected: [FetchOutcome] = []
                for await item in group {
                    collected.append(item)
                }
                return collected
            }

            for outcome in outcomes {
                await apply(outcome: outcome)
            }
        }

        await exportWidgetSnapshot()
    }

    private func apply(outcome: (channel: WatchedChannel, result: Result<(LivePageResult, String?, URL?), Error>)) async {
        let channel = outcome.channel
        switch outcome.result {
        case .failure:
            statuses[channel.id] = .unknown
            channelStore.updateStatus(for: channel.id, status: .unknown)

        case .success((let pageResult, let extractedTitle, let extractedAvatar)):
            var titleToUpdate = extractedTitle
            var avatarToUpdate = extractedAvatar

            if case .notLive(let channelTitle, let avatarURL) = pageResult {
                if titleToUpdate == nil { titleToUpdate = channelTitle }
                if avatarToUpdate == nil { avatarToUpdate = avatarURL }
            }

            if titleToUpdate != nil || avatarToUpdate != nil {
                channelStore.updateMetadata(for: channel.id, name: titleToUpdate, avatarURL: avatarToUpdate)
            }

            let currentChannel = channelStore.channels.first(where: { $0.id == channel.id }) ?? channel

            switch pageResult {
            case .live(let videoId, let title, let startedAt):
                let streamStatus = StreamStatus.live(videoId: videoId, title: title, startedAt: startedAt)
                statuses[channel.id] = streamStatus

                let shouldNotify = (currentChannel.lastNotifiedVideoId != videoId) && preferencesStore.settings.notifyOnLive
                if shouldNotify {
                    await notificationService.notifyLive(
                        channelName: currentChannel.name,
                        title: title,
                        videoId: videoId,
                        channelHandle: currentChannel.handle,
                        playSound: preferencesStore.settings.playNotificationSound
                    )
                    channelStore.updateStatus(
                        for: channel.id,
                        status: streamStatus,
                        notifiedLiveId: videoId
                    )
                } else {
                    channelStore.updateStatus(
                        for: channel.id,
                        status: streamStatus
                    )
                }

            case .upcoming(let videoId, let title, let scheduledStartTime):
                let streamStatus = StreamStatus.upcoming(videoId: videoId, title: title, scheduledStartTime: scheduledStartTime)
                statuses[channel.id] = streamStatus

                let shouldNotify = (currentChannel.lastNotifiedUpcomingId != videoId) && preferencesStore.settings.notifyOnUpcoming
                if shouldNotify {
                    await notificationService.notifyUpcoming(
                        channelName: currentChannel.name,
                        title: title,
                        videoId: videoId,
                        channelHandle: currentChannel.handle,
                        playSound: preferencesStore.settings.playNotificationSound
                    )
                    channelStore.updateStatus(
                        for: channel.id,
                        status: streamStatus,
                        notifiedUpcomingId: videoId
                    )
                } else {
                    channelStore.updateStatus(
                        for: channel.id,
                        status: streamStatus
                    )
                }

            case .notLive:
                let offlineStatus = StreamStatus.offline(lastStreamedAt: currentChannel.lastStreamedAt)
                statuses[channel.id] = offlineStatus
                channelStore.updateStatus(
                    for: channel.id,
                    status: offlineStatus
                )

            case .unrecognized:
                statuses[channel.id] = .unknown
                channelStore.updateStatus(
                    for: channel.id,
                    status: .unknown
                )
            }
        }
    }

    public func startPolling(interval: TimeInterval = AppConstants.livePollInterval) {
        stopPolling()

        isPolling = true
        isPausedForSleep = false
        pollingInterval = interval

        sleepObserver = notificationCenter.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    self?.handleScreensDidSleep()
                }
            } else {
                Task { @MainActor [weak self] in
                    self?.handleScreensDidSleep()
                }
            }
        }

        wakeObserver = notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    self?.handleScreensDidWake()
                }
            } else {
                Task { @MainActor [weak self] in
                    self?.handleScreensDidWake()
                }
            }
        }

        startPollingLoop()
    }

    public func stopPolling() {
        isPolling = false
        isPausedForSleep = false

        pollingTask?.cancel()
        pollingTask = nil

        if let sleepObserver {
            notificationCenter.removeObserver(sleepObserver)
            self.sleepObserver = nil
        }
        if let wakeObserver {
            notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
    }

    deinit {
        pollingTask?.cancel()
        if let sleepObserver {
            notificationCenter.removeObserver(sleepObserver)
        }
        if let wakeObserver {
            notificationCenter.removeObserver(wakeObserver)
        }
    }

    private func handleScreensDidSleep() {
        guard isPolling, !isPausedForSleep else { return }
        isPausedForSleep = true
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func handleScreensDidWake() {
        guard isPolling, isPausedForSleep else { return }
        isPausedForSleep = false
        startPollingLoop()
    }

    private func startPollingLoop() {
        pollingTask?.cancel()
        let interval = self.pollingInterval
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard self != nil else { break }
                await self?.refreshAll()

                do {
                    try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                } catch {
                    break
                }

                guard self != nil else { break }
            }
        }
    }
}
