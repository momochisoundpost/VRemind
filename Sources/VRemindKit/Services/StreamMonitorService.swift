import AppKit
import Combine
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
        config.networkServiceType = .background
        return URLSession(configuration: config)
    }()

    public nonisolated static let defaultHTTPFetcher: HTTPFetcher = { request in
        var req = request
        req.cachePolicy = .reloadIgnoringLocalCacheData
        if req.value(forHTTPHeaderField: "User-Agent") == nil {
            req.setValue(
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
                forHTTPHeaderField: "User-Agent"
            )
        }
        if req.value(forHTTPHeaderField: "Accept-Language") == nil {
            req.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        }
        return try await session.data(for: req)
    }

    public nonisolated static let defaultFetcher: Fetcher = { url in
        try await defaultHTTPFetcher(URLRequest(url: url))
    }

    @Published public private(set) var isRefreshing: Bool = false
    @Published public private(set) var statuses: [String: StreamStatus] = [:]

    public let channelStore: ChannelStore
    public let preferencesStore: PreferencesStore
    public let notificationService: NotificationService
    public let snapshotStore: WidgetSnapshotStoreProtocol
    public let providerRegistry: StreamProviderRegistry
    public let powerMonitor: PowerStateMonitor
    public var engine: StreamMonitorEngine {
        StreamMonitorEngine(registry: providerRegistry, batchSize: effectiveBatchSize)
    }
    public let httpFetcher: HTTPFetcher
    public let fetcher: Fetcher

    public private(set) var isPolling: Bool = false
    public private(set) var isPausedForSleep: Bool = false

    private var customIntervalOverride: TimeInterval?
    public var currentPollingInterval: TimeInterval {
        customIntervalOverride ?? powerMonitor.currentPolicy.pollInterval
    }
    public var effectiveBatchSize: Int {
        powerMonitor.currentPolicy.batchSize
    }

    private let notificationCenter: NotificationCenter
    private let dateProvider: @Sendable () -> Date
    private let calendar: Calendar
    private var pollingTask: Task<Void, Never>?
    private var sleepObservers: [any NSObjectProtocol] = []
    private var policyCancellable: AnyCancellable?
    private var sleepTimerCoordinator: SleepTimerCoordinator?
    private var needsAnotherRefresh: Bool = false
    private var statusEpoch: UInt64 = 0

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
        calendar: Calendar = .current,
        powerMonitor: PowerStateMonitor? = nil
    ) {
        self.channelStore = channelStore
        self.preferencesStore = preferencesStore
        self.notificationService = notificationService
        self.providerRegistry = providerRegistry
        self.notificationCenter = notificationCenter
        self.snapshotStore = snapshotStore
        self.dateProvider = dateProvider
        self.calendar = calendar
        self.powerMonitor = powerMonitor ?? PowerStateMonitor()

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
            self.httpFetcher = StreamMonitorService.defaultHTTPFetcher
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
        let channelsSnapshot = channelStore.channels
        let statusesSnapshot = statuses
        let snapshotStore = self.snapshotStore
        await Task.detached(priority: .background) {
            do {
                try await snapshotStore.writeSnapshot(
                    channels: channelsSnapshot,
                    statuses: statusesSnapshot
                )
            } catch {
                NSLog("Failed to export widget snapshot: %@", error.localizedDescription)
            }
        }.value
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

    public func clearStatuses() {
        statusEpoch &+= 1
        statuses = [:]
    }

    private func performRefreshPass() async {
        let epoch = statusEpoch
        let channels = channelStore.channels
        let settings = preferencesStore.settings
        let currentStatuses = self.statuses

        let batchSize = effectiveBatchSize
        let registry = providerRegistry
        let fetcher = httpFetcher
        let now = dateProvider()
        let cal = calendar

        let updatedStatuses = await Task.detached(priority: .background) { [weak self] () -> [String: StreamStatus] in
            let engine = StreamMonitorEngine(registry: registry, batchSize: batchSize)
            return await engine.refreshPass(
                channels: channels,
                settings: settings,
                currentStatuses: currentStatuses,
                fetcher: fetcher,
                date: now,
                calendar: cal
            ) { [weak self] event in
                guard let self = self else { return }
                await self.receiveMonitorEvent(event, epoch: epoch)
            }
        }.value

        guard epoch == statusEpoch else { return }
        let activeKeys = Set(channelStore.channels.map { $0.id.lowercased() })
        let filteredStatuses = updatedStatuses.filter { key, _ in
            activeKeys.contains(key.lowercased())
        }
        if self.statuses != filteredStatuses {
            self.statuses = filteredStatuses
        }
        await exportWidgetSnapshot()
    }

    private func receiveMonitorEvent(_ event: MonitorEvent, epoch: UInt64) async {
        guard self.statusEpoch == epoch else { return }
        await self.handleMonitorEvent(event)
    }

    private func handleMonitorEvent(_ event: MonitorEvent) async {
        switch event {
        case .statusUpdated(let channelId, let status):
            let previous = statuses[channelId]
            let didTransitionToLive: Bool
            if case .live(let newVid, _, _) = status {
                if case .live(let oldVid, _, _) = previous, oldVid == newVid {
                    didTransitionToLive = false
                } else {
                    didTransitionToLive = true
                }
            } else {
                didTransitionToLive = false
            }
            if previous != status {
                statuses[channelId] = status
            }
            channelStore.updateStatus(for: channelId, status: status, didTransitionToLive: didTransitionToLive)

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
            if self.statuses != finalStatuses {
                self.statuses = finalStatuses
            }
        }
    }

    public func startPolling(interval: TimeInterval? = nil) {
        stopPolling()

        isPolling = true
        isPausedForSleep = false
        customIntervalOverride = interval

        let handleEvent: @Sendable (Notification) -> Void = { [weak self] note in
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    guard let self = self else { return }
                    switch note.name {
                    case NSWorkspace.screensDidSleepNotification, NSWorkspace.willSleepNotification:
                        self.handleSleep()
                    case NSWorkspace.screensDidWakeNotification, NSWorkspace.didWakeNotification:
                        self.handleWake()
                    default:
                        break
                    }
                }
            } else {
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    switch note.name {
                    case NSWorkspace.screensDidSleepNotification, NSWorkspace.willSleepNotification:
                        self.handleSleep()
                    case NSWorkspace.screensDidWakeNotification, NSWorkspace.didWakeNotification:
                        self.handleWake()
                    default:
                        break
                    }
                }
            }
        }

        let notificationNames: [Notification.Name] = [
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.willSleepNotification,
            NSWorkspace.didWakeNotification
        ]

        for name in notificationNames {
            let observer = notificationCenter.addObserver(
                forName: name,
                object: nil,
                queue: nil,
                using: handleEvent
            )
            sleepObservers.append(observer)
        }

        if customIntervalOverride == nil {
            policyCancellable = powerMonitor.$currentPolicy
                .dropFirst()
                .sink { [weak self] newPolicy in
                    self?.handlePolicyChange(newPolicy)
                }
        }

        startPollingLoop()
    }

    public func stopPolling() {
        isPolling = false
        isPausedForSleep = false
        customIntervalOverride = nil

        policyCancellable?.cancel()
        policyCancellable = nil

        pollingTask?.cancel()
        pollingTask = nil

        sleepTimerCoordinator?.cancel()
        sleepTimerCoordinator = nil

        for observer in sleepObservers {
            notificationCenter.removeObserver(observer)
        }
        sleepObservers.removeAll()
    }

    deinit {
        policyCancellable?.cancel()
        pollingTask?.cancel()
        sleepTimerCoordinator?.cancel()
        for observer in sleepObservers {
            notificationCenter.removeObserver(observer)
        }
    }

    private func handleSleep() {
        guard isPolling, !isPausedForSleep else { return }
        isPausedForSleep = true
        sleepTimerCoordinator?.cancel()
        sleepTimerCoordinator = nil
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func handleWake() {
        guard isPolling, isPausedForSleep else { return }
        powerMonitor.refresh()
        isPausedForSleep = false
        startPollingLoop()
    }

    private func handlePolicyChange(_ newPolicy: PowerPolicy) {
        guard customIntervalOverride == nil, isPolling, !isPausedForSleep else { return }
        let leewaySeconds = newPolicy.timerLeeway
        sleepTimerCoordinator?.reschedule(interval: newPolicy.pollInterval, leeway: leewaySeconds)
    }

    private func startPollingLoop() {
        pollingTask?.cancel()
        sleepTimerCoordinator?.cancel()
        sleepTimerCoordinator = nil

        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let service = self, service.isPolling, !service.isPausedForSleep else { break }
                await service.refreshAll()
                guard !Task.isCancelled, self != nil else { break }
                await self?.sleepForCurrentInterval()
            }
        }
    }

    private func sleepForCurrentInterval() async {
        let interval = currentPollingInterval
        let leewaySeconds: Double
        if customIntervalOverride != nil {
            leewaySeconds = min(interval * 0.1, powerMonitor.currentPolicy.timerLeeway)
        } else {
            leewaySeconds = powerMonitor.currentPolicy.timerLeeway
        }

        let coordinator = SleepTimerCoordinator()
        self.sleepTimerCoordinator = coordinator

        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                coordinator.start(
                    interval: interval,
                    leeway: leewaySeconds,
                    continuation: continuation
                )
            }
        } onCancel: {
            coordinator.cancel()
        }
    }
}

final class SleepTimerCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    private var timer: DispatchSourceTimer?
    private var continuation: CheckedContinuation<Void, Never>?
    private var isResumed = false

    func start(
        interval: TimeInterval,
        leeway: TimeInterval,
        continuation: CheckedContinuation<Void, Never>
    ) {
        lock.lock()
        if isResumed {
            lock.unlock()
            continuation.resume()
            return
        }

        self.continuation = continuation

        let timer = DispatchSource.makeTimerSource(
            flags: [],
            queue: DispatchQueue.global(qos: .background)
        )
        self.timer = timer

        let leewayMs = max(1, Int(leeway * 1000))
        timer.schedule(deadline: .now() + interval, leeway: .milliseconds(leewayMs))

        timer.setEventHandler { [weak self] in
            self?.resumeOnce()
        }
        timer.resume()
        lock.unlock()
    }

    func reschedule(interval: TimeInterval, leeway: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        guard !isResumed, let timer = timer else { return }
        let leewayMs = max(1, Int(leeway * 1000))
        timer.schedule(deadline: .now() + interval, leeway: .milliseconds(leewayMs))
    }

    func resumeOnce() {
        lock.lock()
        if isResumed {
            lock.unlock()
            return
        }
        isResumed = true
        let cont = continuation
        continuation = nil
        let t = timer
        timer = nil
        lock.unlock()

        if let t {
            t.setEventHandler(handler: nil)
            t.cancel()
        }
        cont?.resume()
    }

    func cancel() {
        resumeOnce()
    }
}
