import AppKit
import Foundation
import VRemindCore

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
    public let snapshotStore: WidgetSnapshotStoreProtocol
    public let providerRegistry: StreamProviderRegistry
    public let engine: StreamMonitorEngine
    public let httpFetcher: HTTPFetcher
    public let fetcher: Fetcher

    public private(set) var isPolling: Bool = false
    public private(set) var isPausedForSleep: Bool = false

    private let notificationCenter: NotificationCenter
    private let dateProvider: @Sendable () -> Date
    private let calendar: Calendar
    private var pollingTask: Task<Void, Never>?
    private var pollingInterval: TimeInterval = AppConstants.livePollInterval
    private var sleepObserver: (any NSObjectProtocol)?
    private var wakeObserver: (any NSObjectProtocol)?
    private var needsAnotherRefresh: Bool = false

    public init(
        channelStore: ChannelStore,
        preferencesStore: PreferencesStore,
        notificationService: NotificationService,
        fetcher: Fetcher? = nil,
        httpFetcher: HTTPFetcher? = nil,
        providerRegistry: StreamProviderRegistry = .default,
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        snapshotStore: WidgetSnapshotStoreProtocol = WidgetSnapshotStore.shared,
        dateProvider: @escaping @Sendable () -> Date = { Date() },
        calendar: Calendar = .current
    ) {
        self.channelStore = channelStore
        self.preferencesStore = preferencesStore
        self.notificationService = notificationService
        self.providerRegistry = providerRegistry
        self.notificationCenter = notificationCenter
        self.snapshotStore = snapshotStore
        self.dateProvider = dateProvider
        self.calendar = calendar
        self.engine = StreamMonitorEngine(registry: providerRegistry)

        if let httpFetcher = httpFetcher {
            self.httpFetcher = httpFetcher
            self.fetcher = fetcher ?? { url in
                try await httpFetcher(URLRequest(url: url))
            }
        } else if let fetcher = fetcher {
            self.fetcher = fetcher
            self.httpFetcher = { request in
                guard let url = request.url else {
                    throw URLError(.badURL)
                }
                return try await fetcher(url)
            }
        } else {
            self.httpFetcher = StreamMonitorEngine.defaultFetcher
            self.fetcher = StreamMonitorService.defaultFetcher
        }
    }

    public var isAnyLive: Bool {
        channelStore.channels.contains { channel in
            if case .live = status(for: channel) {
                return true
            }
            return false
        }
    }

    public func status(for channel: WatchedChannel) -> StreamStatus {
        statuses[channel.id] ?? statuses[channel.id.lowercased()] ?? .unknown
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

    public func checkDeveloperBirthdayNotificationIfNeeded(date: Date? = nil) async {
        let now = date ?? dateProvider()
        guard CelebrationDetector.isDeveloperBirthday(date: now, calendar: calendar) else {
            return
        }
        guard channelStore.channels.contains(where: { CelebrationDetector.isTargetDeveloperChannel($0) }) else {
            return
        }
        let year = calendar.component(.year, from: now)
        guard preferencesStore.settings.lastNotifiedDevBirthdayYear != year else {
            return
        }
        preferencesStore.settings.lastNotifiedDevBirthdayYear = year
        await notificationService.notifyDeveloperBirthday(
            year: year,
            playSound: preferencesStore.settings.playNotificationSound
        )
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

    private var statusEpoch: UInt64 = 0

    public func clearStatuses() {
        statusEpoch &+= 1
        statuses = [:]
    }

    private func performRefreshPass() async {
        let epoch = statusEpoch
        let channels = channelStore.channels
        let settings = preferencesStore.settings
        let currentStatuses = self.statuses

        let updatedStatuses = await engine.refreshPass(
            channels: channels,
            settings: settings,
            currentStatuses: currentStatuses,
            fetcher: self.httpFetcher,
            date: dateProvider(),
            calendar: calendar
        ) { [weak self] event in
            guard let self = self, await self.statusEpoch == epoch else { return }
            await self.handleMonitorEvent(event)
        }

        guard epoch == statusEpoch else { return }
        let activeKeys = Set(channelStore.channels.map { $0.id.lowercased() })
        let filteredStatuses = updatedStatuses.filter { key, _ in
            activeKeys.contains(key.lowercased())
        }
        self.statuses = filteredStatuses
        await exportWidgetSnapshot()
    }

    private func handleMonitorEvent(_ event: MonitorEvent) async {
        switch event {
        case .statusUpdated(let channelId, let status):
            statuses[channelId] = status
            channelStore.updateStatus(for: channelId, status: status)

        case .metadataUpdated(let channelId, let name, let avatarURL):
            channelStore.updateMetadata(for: channelId, name: name, avatarURL: avatarURL)

        case .notifyLive(let channel, let videoId, let title):
            let liveStatus = StreamStatus.live(videoId: videoId, title: title, startedAt: nil)
            let watchURL = LinkOpener.streamURL(for: channel, status: liveStatus)
            let current = channelStore.channels.first(where: { $0.id.lowercased() == channel.id.lowercased() }) ?? channel
            await notificationService.notifyLive(
                channelName: current.name,
                title: title,
                videoId: videoId,
                channelHandle: current.handle,
                platform: current.platform,
                watchURL: watchURL,
                playSound: preferencesStore.settings.playNotificationSound
            )
            channelStore.updateStatus(
                for: channel.id,
                status: statuses[channel.id] ?? liveStatus,
                notifiedLiveId: videoId
            )

        case .notifyUpcoming(let channel, let videoId, let title):
            let upcomingStatus = StreamStatus.upcoming(videoId: videoId, title: title, scheduledStartTime: nil)
            let watchURL = LinkOpener.streamURL(for: channel, status: upcomingStatus)
            let current = channelStore.channels.first(where: { $0.id.lowercased() == channel.id.lowercased() }) ?? channel
            await notificationService.notifyUpcoming(
                channelName: current.name,
                title: title,
                videoId: videoId,
                channelHandle: current.handle,
                platform: current.platform,
                watchURL: watchURL,
                playSound: preferencesStore.settings.playNotificationSound
            )
            channelStore.updateStatus(
                for: channel.id,
                status: statuses[channel.id] ?? upcomingStatus,
                notifiedUpcomingId: videoId
            )

        case .notifyDeveloperBirthday(let year):
            preferencesStore.settings.lastNotifiedDevBirthdayYear = year
            await notificationService.notifyDeveloperBirthday(
                year: year,
                playSound: preferencesStore.settings.playNotificationSound
            )

        case .refreshFinished(let finalStatuses):
            self.statuses = finalStatuses
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
