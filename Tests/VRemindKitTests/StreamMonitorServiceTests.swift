import AppKit
import Foundation
import Testing
@testable import VRemindKit

func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "") {
    #expect(a == b, Comment(rawValue: message))
}

@MainActor
func MockNotificationService(center: NotificationCenterProtocol? = nil) -> NotificationService {
    NotificationService(center: center ?? MockNotificationCenter())
}

func make200Response(url: URL = URL(string: "https://www.youtube.com/@test/live")!) -> URLResponse {
    HTTPURLResponse(
        url: url,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
    )!
}

func makeLiveHTML(
    videoId: String,
    channelTitle: String = "Test Channel",
    streamTitle: String = "Test Stream",
    avatarURL: String? = nil
) -> Data {
    let avatarTag = avatarURL.map { "<link rel=\"image_src\" href=\"\($0)\">" } ?? ""
    let html = """
    <!DOCTYPE html>
    <html>
    <head>
    <title>\(streamTitle) - YouTube</title>
    \(avatarTag)
    </head>
    <body>
    <script>
    var ytInitialPlayerResponse = {
        "videoDetails": {
            "videoId": "\(videoId)",
            "title": "\(streamTitle)",
            "author": "\(channelTitle)",
            "isLive": true
        },
        "microformat": {
            "playerMicroformatRenderer": {
                "liveBroadcastDetails": {
                    "isLiveNow": true,
                    "startTimestamp": "2026-11-11T12:00:00Z"
                }
            }
        }
    };
    </script>
    </body>
    </html>
    """
    return html.data(using: .utf8)!
}

func makeUpcomingHTML(
    videoId: String,
    channelTitle: String = "Test Channel",
    streamTitle: String = "Upcoming Stream"
) -> Data {
    let html = """
    <!DOCTYPE html>
    <html>
    <head><title>\(streamTitle) - YouTube</title></head>
    <body>
    <script>
    var ytInitialPlayerResponse = {
        "videoDetails": {
            "videoId": "\(videoId)",
            "title": "\(streamTitle)",
            "author": "\(channelTitle)",
            "isUpcoming": true
        },
        "microformat": {
            "playerMicroformatRenderer": {
                "liveBroadcastDetails": {
                    "isLiveNow": false,
                    "startTimestamp": "2026-11-12T12:00:00Z"
                }
            }
        }
    };
    </script>
    </body>
    </html>
    """
    return html.data(using: .utf8)!
}

func makeOfflineHTML(
    channelTitle: String = "Test Channel",
    avatarURL: String = "https://yt3.googleusercontent.com/test-avatar=s800"
) -> Data {
    let html = """
    <!DOCTYPE html>
    <html>
    <head>
    <meta property="og:title" content="\(channelTitle)">
    <link rel=\"image_src\" href=\"\(avatarURL)\">
    </head>
    <body>
    <script>var ytInitialData = {};</script>
    </body>
    </html>
    """
    return html.data(using: .utf8)!
}

final class ValueBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T
    init(_ value: T) { self.value = value }
    func get() -> T {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
    func set(_ newValue: T) {
        lock.lock()
        defer { lock.unlock() }
        value = newValue
    }
}

final class SpyWidgetSnapshotStore: WidgetSnapshotStoreProtocol, @unchecked Sendable {
    struct WriteRecord: Sendable {
        let channels: [WatchedChannel]
        let statuses: [String: StreamStatus]
    }

    private let lock = NSLock()
    private var _writes: [WriteRecord] = []
    private var _shouldThrow: Error?

    var shouldThrow: Error? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _shouldThrow
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _shouldThrow = newValue
        }
    }

    var writeCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _writes.count
    }

    var writes: [WriteRecord] {
        lock.lock()
        defer { lock.unlock() }
        return _writes
    }

    var lastWrite: WriteRecord? {
        lock.lock()
        defer { lock.unlock() }
        return _writes.last
    }

    init(shouldThrow: Error? = nil) {
        self._shouldThrow = shouldThrow
    }

    private func recordWrite(channels: [WatchedChannel], statuses: [String: StreamStatus]) throws {
        lock.lock()
        defer { lock.unlock() }
        if let err = _shouldThrow {
            throw err
        }
        _writes.append(WriteRecord(channels: channels, statuses: statuses))
    }

    func writeSnapshot(channels: [WatchedChannel], statuses: [String: StreamStatus]) async throws {
        try recordWrite(channels: channels, statuses: statuses)
    }

    func readSnapshot() -> WidgetSnapshot? {
        nil
    }
}

struct StreamMonitorServiceTests {
    @Test @MainActor func testLiveDeduplicationDoesNotNotifyTwice() async {
        let channelStore = ChannelStore(userDefaults: makeTestDefaults())
        let prefs = PreferencesStore(userDefaults: makeTestDefaults())
        prefs.settings.notifyOnLive = true
        let mockNotifier = MockNotificationService()

        let service = StreamMonitorService(
            channelStore: channelStore,
            preferencesStore: prefs,
            notificationService: mockNotifier,
            fetcher: { _ in (makeLiveHTML(videoId: "stream1"), make200Response()) }
        )

        await service.refreshAll()
        XCTAssertEqual(mockNotifier.liveNotificationCount, 1)

        // Poll 2 with same video ID
        await service.refreshAll()
        XCTAssertEqual(mockNotifier.liveNotificationCount, 1) // Deduplicated!
    }

    @Test @MainActor func testUpcomingDeduplicationDoesNotNotifyTwice() async {
        let channelStore = ChannelStore(userDefaults: makeTestDefaults())
        let prefs = PreferencesStore(userDefaults: makeTestDefaults())
        prefs.settings.notifyOnUpcoming = true
        let mockNotifier = MockNotificationService()

        let service = StreamMonitorService(
            channelStore: channelStore,
            preferencesStore: prefs,
            notificationService: mockNotifier,
            fetcher: { _ in (makeUpcomingHTML(videoId: "up1"), make200Response()) }
        )

        await service.refreshAll()
        #expect(mockNotifier.upcomingNotificationCount == 1)

        // Poll 2 with same upcoming video ID
        await service.refreshAll()
        #expect(mockNotifier.upcomingNotificationCount == 1)
    }

    @Test @MainActor func testNotificationSuppressedWhenDisabledInPreferences() async {
        let channelStore = ChannelStore(userDefaults: makeTestDefaults())
        let prefs = PreferencesStore(userDefaults: makeTestDefaults())
        prefs.settings.notifyOnLive = false
        prefs.settings.notifyOnUpcoming = false
        let mockNotifier = MockNotificationService()

        let service = StreamMonitorService(
            channelStore: channelStore,
            preferencesStore: prefs,
            notificationService: mockNotifier,
            fetcher: { _ in (makeLiveHTML(videoId: "stream1"), make200Response()) }
        )

        await service.refreshAll()
        #expect(mockNotifier.liveNotificationCount == 0)
        #expect(mockNotifier.upcomingNotificationCount == 0)
    }

    @Test @MainActor func testNewStreamIdTriggersNewNotification() async {
        let channelStore = ChannelStore(userDefaults: makeTestDefaults())
        let prefs = PreferencesStore(userDefaults: makeTestDefaults())
        prefs.settings.notifyOnLive = true
        let mockNotifier = MockNotificationService()

        let currentVideoId = ValueBox("stream1")
        let service = StreamMonitorService(
            channelStore: channelStore,
            preferencesStore: prefs,
            notificationService: mockNotifier,
            fetcher: { _ in (makeLiveHTML(videoId: currentVideoId.get()), make200Response()) }
        )

        await service.refreshAll()
        #expect(mockNotifier.liveNotificationCount == 1)

        currentVideoId.set("stream2")
        await service.refreshAll()
        #expect(mockNotifier.liveNotificationCount == 2)
    }

    @Test @MainActor func testMetadataUpdatedFromLivePageHTML() async {
        let channelStore = ChannelStore(userDefaults: makeTestDefaults())
        let prefs = PreferencesStore(userDefaults: makeTestDefaults())
        let mockNotifier = MockNotificationService()

        let service = StreamMonitorService(
            channelStore: channelStore,
            preferencesStore: prefs,
            notificationService: mockNotifier,
            fetcher: { _ in
                (
                    makeLiveHTML(
                        videoId: "live99",
                        channelTitle: "Caitlyn Official",
                        streamTitle: "Karaoke Stream",
                        avatarURL: "https://yt3.googleusercontent.com/caitlyn-avatar=s800"
                    ),
                    make200Response()
                )
            }
        )

        await service.refreshAll()

        let updatedChannel = channelStore.channels.first(where: { $0.id == "@bukancaitlyn" })
        #expect(updatedChannel?.name == "Caitlyn Official")
        #expect(updatedChannel?.avatarURL?.absoluteString == "https://yt3.googleusercontent.com/caitlyn-avatar=s800")
    }

    @Test @MainActor func testOfflineTransitionPreservesLastStreamedAt() async {
        let channelStore = ChannelStore(userDefaults: makeTestDefaults())
        let prefs = PreferencesStore(userDefaults: makeTestDefaults())
        let mockNotifier = MockNotificationService()

        let isLive = ValueBox(true)
        let service = StreamMonitorService(
            channelStore: channelStore,
            preferencesStore: prefs,
            notificationService: mockNotifier,
            fetcher: { _ in
                if isLive.get() {
                    return (makeLiveHTML(videoId: "stream1"), make200Response())
                } else {
                    return (makeOfflineHTML(), make200Response())
                }
            }
        )

        await service.refreshAll()
        let liveChannel = channelStore.channels.first(where: { $0.id == "@bukancaitlyn" })
        #expect(liveChannel?.lastStreamedAt != nil)
        let lastStreamed = liveChannel?.lastStreamedAt

        isLive.set(false)
        await service.refreshAll()
        let offlineChannel = channelStore.channels.first(where: { $0.id == "@bukancaitlyn" })
        #expect(offlineChannel?.lastStreamedAt == lastStreamed)

        if case .offline(let timestamp) = service.status(for: offlineChannel!) {
            #expect(timestamp == lastStreamed)
        } else {
            Issue.record("Expected status to be .offline with timestamp")
        }
    }

    @Test @MainActor func testIsAnyLiveReflectsWatchlistState() async {
        let channelStore = ChannelStore(userDefaults: makeTestDefaults())
        let prefs = PreferencesStore(userDefaults: makeTestDefaults())
        let mockNotifier = MockNotificationService()

        let isLive = ValueBox(false)
        let service = StreamMonitorService(
            channelStore: channelStore,
            preferencesStore: prefs,
            notificationService: mockNotifier,
            fetcher: { _ in
                if isLive.get() {
                    return (makeLiveHTML(videoId: "s1"), make200Response())
                } else {
                    return (makeOfflineHTML(), make200Response())
                }
            }
        )

        await service.refreshAll()
        #expect(service.isAnyLive == false)

        isLive.set(true)
        await service.refreshAll()
        #expect(service.isAnyLive == true)
    }

    @Test @MainActor func testStatusForChannelReturnsKnownAndUnknown() async {
        let channelStore = ChannelStore(userDefaults: makeTestDefaults())
        let prefs = PreferencesStore(userDefaults: makeTestDefaults())
        let mockNotifier = MockNotificationService()

        let service = StreamMonitorService(
            channelStore: channelStore,
            preferencesStore: prefs,
            notificationService: mockNotifier,
            fetcher: { _ in (makeLiveHTML(videoId: "s1"), make200Response()) }
        )

        let unwatchedChannel = WatchedChannel(id: "@unknown", name: "Unknown", handle: "@unknown")
        #expect(service.status(for: unwatchedChannel) == .unknown)

        await service.refreshAll()
        let caitlyn = channelStore.channels[0]
        if case .live(let vid, _, _) = service.status(for: caitlyn) {
            #expect(vid == "s1")
        } else {
            Issue.record("Expected .live status")
        }
    }

    @Test @MainActor func testBatchConcurrencyLimitsToThreeChannels() async {
        let channelStore = ChannelStore(userDefaults: makeTestDefaults())
        channelStore.addChannel(handle: "@ch2")
        channelStore.addChannel(handle: "@ch3")
        channelStore.addChannel(handle: "@ch4")
        channelStore.addChannel(handle: "@ch5")
        channelStore.addChannel(handle: "@ch6")
        channelStore.addChannel(handle: "@ch7")
        #expect(channelStore.channels.count == 7)

        let prefs = PreferencesStore(userDefaults: makeTestDefaults())
        let mockNotifier = MockNotificationService()

        final class ConcurrencyTracker: @unchecked Sendable {
            private let lock = NSLock()
            private var currentActive: Int = 0
            private(set) var peakConcurrency: Int = 0

            func enter() {
                lock.lock()
                defer { lock.unlock() }
                currentActive += 1
                if currentActive > peakConcurrency {
                    peakConcurrency = currentActive
                }
            }

            func exit() {
                lock.lock()
                defer { lock.unlock() }
                currentActive -= 1
            }
        }

        let tracker = ConcurrencyTracker()

        let service = StreamMonitorService(
            channelStore: channelStore,
            preferencesStore: prefs,
            notificationService: mockNotifier,
            fetcher: { _ in
                tracker.enter()
                try await Task.sleep(nanoseconds: 20_000_000) // 20ms
                tracker.exit()
                return (makeOfflineHTML(), make200Response())
            }
        )

        await service.refreshAll()
        #expect(tracker.peakConcurrency <= 3)
        #expect(tracker.peakConcurrency > 0)
    }

    @Test @MainActor func testDisplaySleepPausesAndWakeResumesPolling() async {
        let channelStore = ChannelStore(userDefaults: makeTestDefaults())
        let prefs = PreferencesStore(userDefaults: makeTestDefaults())
        let mockNotifier = MockNotificationService()
        let testCenter = NotificationCenter()

        let service = StreamMonitorService(
            channelStore: channelStore,
            preferencesStore: prefs,
            notificationService: mockNotifier,
            fetcher: { _ in (makeOfflineHTML(), make200Response()) },
            notificationCenter: testCenter
        )

        #expect(!service.isPolling)
        service.startPolling(interval: 3600)
        #expect(service.isPolling)
        #expect(!service.isPausedForSleep)

        // Post sleep notification
        testCenter.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        #expect(service.isPausedForSleep)

        // Post wake notification
        testCenter.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        #expect(!service.isPausedForSleep)
        #expect(service.isPolling)

        service.stopPolling()
        #expect(!service.isPolling)
        #expect(!service.isPausedForSleep)
    }

    @Test @MainActor func testFetchErrorSetsUnknownStatusWithoutCrashing() async {
        let channelStore = ChannelStore(userDefaults: makeTestDefaults())
        let prefs = PreferencesStore(userDefaults: makeTestDefaults())
        let mockNotifier = MockNotificationService()

        let service = StreamMonitorService(
            channelStore: channelStore,
            preferencesStore: prefs,
            notificationService: mockNotifier,
            fetcher: { _ in throw URLError(.timedOut) }
        )

        await service.refreshAll()
        let caitlyn = channelStore.channels[0]
        #expect(service.status(for: caitlyn) == .unknown)
    }

    @Test @MainActor func testDeallocationCleansUpObserversAndStopsPolling() async throws {
        final class SpyNotificationCenter: NotificationCenter, @unchecked Sendable {
            private let lock = NSLock()
            private(set) var removedObserversCount: Int = 0

            override func removeObserver(_ observer: Any) {
                lock.lock()
                defer { lock.unlock() }
                removedObserversCount += 1
                super.removeObserver(observer)
            }
        }

        let channelStore = ChannelStore(userDefaults: makeTestDefaults())
        let prefs = PreferencesStore(userDefaults: makeTestDefaults())
        let mockNotifier = MockNotificationService()
        let spyCenter = SpyNotificationCenter()
        let fetchCount = ValueBox(0)

        var service: StreamMonitorService? = StreamMonitorService(
            channelStore: channelStore,
            preferencesStore: prefs,
            notificationService: mockNotifier,
            fetcher: { _ in
                fetchCount.set(fetchCount.get() + 1)
                return (makeOfflineHTML(), make200Response())
            },
            notificationCenter: spyCenter,
            snapshotStore: SpyWidgetSnapshotStore()
        )

        service?.startPolling(interval: 0.05)
        for _ in 0..<50 {
            if fetchCount.get() >= 1 { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let countBefore = fetchCount.get()
        #expect(countBefore >= 1)

        // Deallocate without explicit stopPolling()
        service = nil

        for _ in 0..<50 {
            if spyCenter.removedObserversCount == 2 { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        // Both sleepObserver and wakeObserver should be removed in deinit
        #expect(spyCenter.removedObserversCount == 2)

        // Wait to verify the background loop does not keep fetching after deinit
        try await Task.sleep(nanoseconds: 120_000_000)
        let countAfter = fetchCount.get()
        #expect(countAfter == countBefore)
    }

    @Test @MainActor func testConcurrentRefreshQueuesFollowUpPass() async {
        let channelStore = ChannelStore(userDefaults: makeTestDefaults())
        _ = channelStore.addChannel(handle: "@first", name: "First Channel", avatarURL: nil)

        let prefs = PreferencesStore(userDefaults: makeTestDefaults())
        let mockNotifier = MockNotificationService()

        final class ServiceHolder: @unchecked Sendable {
            weak var service: StreamMonitorService?
        }
        let holder = ServiceHolder()

        actor FetchTracker {
            var fetchedURLs: [URL] = []
            var didTriggerConcurrent = false

            func record(_ url: URL) {
                fetchedURLs.append(url)
            }

            func shouldTriggerConcurrent() -> Bool {
                if !didTriggerConcurrent {
                    didTriggerConcurrent = true
                    return true
                }
                return false
            }

            func urls() -> [URL] {
                fetchedURLs
            }
        }
        let tracker = FetchTracker()

        let service = StreamMonitorService(
            channelStore: channelStore,
            preferencesStore: prefs,
            notificationService: mockNotifier,
            fetcher: { url in
                await tracker.record(url)
                let urlString = url.absoluteString

                if urlString.contains("@first") {
                    // Only trigger the concurrent refresh once during the initial pass
                    let shouldTrigger = await tracker.shouldTriggerConcurrent()
                    if shouldTrigger {
                        _ = await MainActor.run {
                            channelStore.addChannel(handle: "@second", name: "Second Channel", avatarURL: nil)
                        }
                        await holder.service?.refreshAll()
                    }
                    return (makeLiveHTML(videoId: "vid_first"), make200Response(url: url))
                } else if urlString.contains("@second") {
                    return (makeLiveHTML(videoId: "vid_second"), make200Response(url: url))
                }

                return (Data(), make200Response(url: url))
            }
        )
        holder.service = service

        // Run the initial refresh
        await service.refreshAll()

        let fetched = await tracker.urls().map { $0.absoluteString }
        #expect(fetched.contains { $0.contains("@first") })
        #expect(fetched.contains { $0.contains("@second") })

        let firstStatus = service.status(for: WatchedChannel(id: "@first", name: "First Channel", handle: "@first"))
        let secondStatus = service.status(for: WatchedChannel(id: "@second", name: "Second Channel", handle: "@second"))

        if case .live(let vid1, _, _) = firstStatus {
            #expect(vid1 == "vid_first")
        } else {
            Issue.record("Expected @first to be live")
        }

        if case .live(let vid2, _, _) = secondStatus {
            #expect(vid2 == "vid_second")
        } else {
            Issue.record("Expected @second to be live via queued refresh pass")
        }
    }

    @Test @MainActor func testLiveStreamPollingPopulatesAndPersistsAvatarURL() async {
        let channelStore = ChannelStore(userDefaults: makeTestDefaults())
        _ = channelStore.addChannel(handle: "@live_vtuber", name: "Live VTuber", avatarURL: nil)

        let prefs = PreferencesStore(userDefaults: makeTestDefaults())
        let mockNotifier = MockNotificationService()

        let liveHTMLWithAvatar = """
        <html><body>
        <script>var ytInitialPlayerResponse = {"videoDetails":{"isLive":true,"title":"Live Concert","videoId":"live_concert_123","author":"Live VTuber"},"microformat":{"playerMicroformatRenderer":{"liveBroadcastDetails":{"isLiveNow":true}}}};</script>
        <script>var ytInitialData = {"videoSecondaryInfoRenderer":{"owner":{"videoOwnerRenderer":{"thumbnail":{"thumbnails":[{"url":"https://yt3.ggpht.com/live_vtuber_avatar=s88-c-k-c0x00ffffff-no-rj","width":88,"height":88}]}}}}};</script>
        </body></html>
        """

        let service = StreamMonitorService(
            channelStore: channelStore,
            preferencesStore: prefs,
            notificationService: mockNotifier,
            fetcher: { url in
                (Data(liveHTMLWithAvatar.utf8), make200Response(url: url))
            }
        )

        await service.refreshAll()

        let channel = channelStore.channels.first { $0.id == "@live_vtuber" }
        #expect(channel?.avatarURL?.absoluteString == "https://yt3.ggpht.com/live_vtuber_avatar=s88-c-k-c0x00ffffff-no-rj")
    }

    @Test @MainActor func testUpcomingStreamPollingPopulatesAndPersistsAvatarURL() async {
        let channelStore = ChannelStore(userDefaults: makeTestDefaults())
        _ = channelStore.addChannel(handle: "@upcoming_vtuber", name: "Upcoming VTuber", avatarURL: nil)

        let prefs = PreferencesStore(userDefaults: makeTestDefaults())
        let mockNotifier = MockNotificationService()

        let upcomingHTMLWithEscapedAvatar = """
        <script>var ytInitialPlayerResponse = {"videoDetails":{"isUpcoming":true,"title":"Upcoming Debut","videoId":"upcoming_debut_456","author":"Upcoming VTuber"},"microformat":{"playerMicroformatRenderer":{"liveBroadcastDetails":{"isLiveNow":false}}}};</script>
        <script>var ytInitialData = {"videoSecondaryInfoRenderer":{"owner":{"videoOwnerRenderer":{"thumbnail":{"thumbnails":[{"url":"https:\\/\\/yt3.ggpht.com\\/upcoming_vtuber_avatar=s88-c-k-c0x00ffffff-no-rj"}]}}}}};</script>
        """

        let service = StreamMonitorService(
            channelStore: channelStore,
            preferencesStore: prefs,
            notificationService: mockNotifier,
            fetcher: { url in
                (Data(upcomingHTMLWithEscapedAvatar.utf8), make200Response(url: url))
            }
        )

        await service.refreshAll()

        let channel = channelStore.channels.first { $0.id == "@upcoming_vtuber" }
        #expect(channel?.avatarURL?.absoluteString == "https://yt3.ggpht.com/upcoming_vtuber_avatar=s88-c-k-c0x00ffffff-no-rj")
    }

    @Test @MainActor func testPollingPassUpdatesWidgetSnapshot() async {
        let channelStore = ChannelStore(userDefaults: makeTestDefaults())
        let prefs = PreferencesStore(userDefaults: makeTestDefaults())
        let mockNotifier = MockNotificationService()
        let spySnapshotStore = SpyWidgetSnapshotStore()

        let currentStatus = ValueBox("live")
        let service = StreamMonitorService(
            channelStore: channelStore,
            preferencesStore: prefs,
            notificationService: mockNotifier,
            fetcher: { _ in
                if currentStatus.get() == "live" {
                    return (makeLiveHTML(videoId: "vid_123", channelTitle: "Caitlyn", streamTitle: "Singing"), make200Response())
                } else {
                    return (makeOfflineHTML(channelTitle: "Caitlyn"), make200Response())
                }
            },
            snapshotStore: spySnapshotStore
        )

        // Initial refresh pass (live)
        await service.refreshAll()

        #expect(spySnapshotStore.writeCount == 1)
        if let lastWrite = spySnapshotStore.lastWrite {
            #expect(lastWrite.channels.contains { $0.id == "@bukancaitlyn" })
            if case .live(let vid, let title, _) = lastWrite.statuses["@bukancaitlyn"] {
                #expect(vid == "vid_123")
                #expect(title == "Singing")
            } else {
                Issue.record("Expected .live stream status in snapshot")
            }
        }

        // Status transition to offline
        currentStatus.set("offline")
        await service.refreshAll()

        #expect(spySnapshotStore.writeCount == 2)
        if let secondWrite = spySnapshotStore.lastWrite {
            if case .offline = secondWrite.statuses["@bukancaitlyn"] {
                // Expected offline status
            } else {
                Issue.record("Expected .offline stream status in snapshot after transition")
            }
        }
    }

    @Test @MainActor func testPollingPassUpdatesWidgetSnapshotWithExtractedMetadata() async {
        let channelStore = ChannelStore(userDefaults: makeTestDefaults())
        let prefs = PreferencesStore(userDefaults: makeTestDefaults())
        let mockNotifier = MockNotificationService()
        let spySnapshotStore = SpyWidgetSnapshotStore()

        let service = StreamMonitorService(
            channelStore: channelStore,
            preferencesStore: prefs,
            notificationService: mockNotifier,
            fetcher: { _ in
                (
                    makeLiveHTML(
                        videoId: "live_avatar_id",
                        channelTitle: "Updated Caitlyn Name",
                        streamTitle: "Stream Title",
                        avatarURL: "https://yt3.googleusercontent.com/avatar123=s800"
                    ),
                    make200Response()
                )
            },
            snapshotStore: spySnapshotStore
        )

        await service.refreshAll()

        #expect(spySnapshotStore.writeCount == 1)
        if let lastWrite = spySnapshotStore.lastWrite {
            let channel = lastWrite.channels.first { $0.id == "@bukancaitlyn" }
            #expect(channel?.name == "Updated Caitlyn Name")
            #expect(channel?.avatarURL?.absoluteString == "https://yt3.googleusercontent.com/avatar123=s800")
        }
    }

    @Test @MainActor func testSnapshotStoreErrorDoesNotCrashOrInterruptPolling() async {
        enum TestError: Error {
            case simulatedDiskError
        }

        let channelStore = ChannelStore(userDefaults: makeTestDefaults())
        let prefs = PreferencesStore(userDefaults: makeTestDefaults())
        let mockNotifier = MockNotificationService()
        let failingSnapshotStore = SpyWidgetSnapshotStore(shouldThrow: TestError.simulatedDiskError)

        let service = StreamMonitorService(
            channelStore: channelStore,
            preferencesStore: prefs,
            notificationService: mockNotifier,
            fetcher: { _ in (makeLiveHTML(videoId: "vid_survive"), make200Response()) },
            snapshotStore: failingSnapshotStore
        )

        // Refresh must not throw or crash despite snapshot store throwing
        await service.refreshAll()

        let channel = channelStore.channels[0]
        if case .live(let videoId, _, _) = service.status(for: channel) {
            #expect(videoId == "vid_survive")
        } else {
            Issue.record("Expected stream status to be updated to live despite snapshot store failure")
        }
    }

    @Test @MainActor func testEmptyWatchlistExportsEmptySnapshot() async {
        let channelStore = ChannelStore(userDefaults: makeTestDefaults())
        channelStore.removeChannel(id: "@bukancaitlyn")
        #expect(channelStore.channels.isEmpty)

        let prefs = PreferencesStore(userDefaults: makeTestDefaults())
        let mockNotifier = MockNotificationService()
        let spySnapshotStore = SpyWidgetSnapshotStore()

        let service = StreamMonitorService(
            channelStore: channelStore,
            preferencesStore: prefs,
            notificationService: mockNotifier,
            snapshotStore: spySnapshotStore
        )

        await service.refreshAll()

        #expect(spySnapshotStore.writeCount == 1)
        if let lastWrite = spySnapshotStore.lastWrite {
            #expect(lastWrite.channels.isEmpty)
        }
    }
}
