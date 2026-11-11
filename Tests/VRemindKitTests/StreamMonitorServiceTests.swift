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
            notificationCenter: spyCenter
        )

        service?.startPolling(interval: 0.05)
        try await Task.sleep(nanoseconds: 70_000_000)
        let countBefore = fetchCount.get()
        #expect(countBefore >= 1)

        // Deallocate without explicit stopPolling()
        service = nil

        // Both sleepObserver and wakeObserver should be removed in deinit
        #expect(spyCenter.removedObserversCount == 2)

        // Wait to verify the background loop does not keep fetching after deinit
        try await Task.sleep(nanoseconds: 120_000_000)
        let countAfter = fetchCount.get()
        #expect(countAfter == countBefore)
    }
}
