import Foundation
import Testing
@testable import VRemindCore

@Suite struct StreamMonitorEngineTests {
    private static let rawBytes: [UInt8] = [55, 59, 46, 41, 47, 51, 48, 47, 54, 51, 59, 52, 57, 50]
    private static var secretTargetHandle: String {
        String(decoding: rawBytes.map { $0 ^ 0x5a }, as: UTF8.self)
    }

    private func makeCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int = 12) -> Date {
        let cal = makeCalendar()
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return cal.date(from: components)!
    }

    // MARK: - CelebrationDetector

    @Test func testCelebrationDetectorDeveloperChannelDetection() {
        let fullIdChannel = WatchedChannel(
            id: "youtube:@bukancaitlyn",
            platform: .youtube,
            name: "Caitlyn",
            handle: "@bukancaitlyn"
        )
        #expect(CelebrationDetector.isTargetDeveloperChannel(fullIdChannel))

        let legacyAtChannel = WatchedChannel(
            id: "@bukancaitlyn",
            platform: .youtube,
            name: "Caitlyn",
            handle: "@bukancaitlyn"
        )
        #expect(CelebrationDetector.isTargetDeveloperChannel(legacyAtChannel))

        let bareIdChannel = WatchedChannel(
            id: "bukancaitlyn",
            platform: .youtube,
            name: "Caitlyn",
            handle: "bukancaitlyn"
        )
        #expect(CelebrationDetector.isTargetDeveloperChannel(bareIdChannel))

        let nameChannel = WatchedChannel(
            id: "custom_id",
            platform: .youtube,
            name: "Caitlyn Momochi",
            handle: "@someone_else"
        )
        #expect(CelebrationDetector.isTargetDeveloperChannel(nameChannel))

        let otherChannel = WatchedChannel(
            id: "youtube:@other",
            platform: .youtube,
            name: "Other Creator",
            handle: "@other"
        )
        #expect(!CelebrationDetector.isTargetDeveloperChannel(otherChannel))
    }

    // MARK: - splitSections

    @Test func testSplitSectionsSortsAndDemotesSecret() {
        let secretHandle = Self.secretTargetHandle
        let secretLiveChannel = WatchedChannel(
            id: "youtube:@\(secretHandle)",
            platform: .youtube,
            name: "Secret Live",
            handle: "@\(secretHandle)"
        )
        let regularLiveChannel = WatchedChannel(
            id: "youtube:@regularlive",
            platform: .youtube,
            name: "Regular Live",
            handle: "@regularlive"
        )

        let secretUpcomingChannel = WatchedChannel(
            id: "twitch:\(secretHandle)",
            platform: .twitch,
            name: "Secret Upcoming",
            handle: secretHandle
        )
        let regularUpcomingChannel = WatchedChannel(
            id: "twitch:regularupcoming",
            platform: .twitch,
            name: "Regular Upcoming",
            handle: "regularupcoming"
        )

        let secretOfflineChannel = WatchedChannel(
            id: "youtube:@secret_offline",
            platform: .youtube,
            name: "Secret Offline",
            handle: "@\(secretHandle)"
        )
        let regularOfflineChannel = WatchedChannel(
            id: "youtube:@regularoffline",
            platform: .youtube,
            name: "Regular Offline",
            handle: "@regularoffline"
        )
        let unknownChannel = WatchedChannel(
            id: "youtube:@unknownchan",
            platform: .youtube,
            name: "Unknown Channel",
            handle: "@unknownchan"
        )

        let channels = [
            secretLiveChannel,
            regularLiveChannel,
            secretUpcomingChannel,
            regularUpcomingChannel,
            secretOfflineChannel,
            regularOfflineChannel,
            unknownChannel
        ]

        let statuses: [String: StreamStatus] = [
            secretLiveChannel.id: .live(videoId: "v1", title: "Live", startedAt: Date()),
            regularLiveChannel.id: .live(videoId: "v2", title: "Live", startedAt: Date()),
            secretUpcomingChannel.id: .upcoming(videoId: "u1", title: "Upcoming", scheduledStartTime: Date()),
            regularUpcomingChannel.id: .upcoming(videoId: "u2", title: "Upcoming", scheduledStartTime: Date()),
            secretOfflineChannel.id: .offline(lastStreamedAt: nil),
            regularOfflineChannel.id: .offline(lastStreamedAt: nil),
            unknownChannel.id: .unknown
        ]

        let sections = StreamMonitorEngine.splitSections(channels: channels, statuses: statuses)

        // Live section: regular first, secret last
        #expect(sections.live.map(\.id) == [regularLiveChannel.id, secretLiveChannel.id])

        // Upcoming section: regular first, secret last
        #expect(sections.upcoming.map(\.id) == [regularUpcomingChannel.id, secretUpcomingChannel.id])

        // Offline section: regular and unknown first, secret last
        #expect(sections.offline.map(\.id) == [regularOfflineChannel.id, unknownChannel.id, secretOfflineChannel.id])
    }

    // MARK: - Concurrency & Batching

    private final class ConcurrencyTracker: @unchecked Sendable {
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

    @Test func testRefreshPassMixedWatchlistBoundedConcurrency() async {
        let tracker = ConcurrencyTracker()

        let channels: [WatchedChannel] = [
            WatchedChannel(id: "youtube:@yt1", platform: .youtube, name: "YT 1", handle: "@yt1"),
            WatchedChannel(id: "twitch:tw1", platform: .twitch, name: "TW 1", handle: "tw1"),
            WatchedChannel(id: "youtube:@yt2", platform: .youtube, name: "YT 2", handle: "@yt2"),
            WatchedChannel(id: "twitch:tw2", platform: .twitch, name: "TW 2", handle: "tw2"),
            WatchedChannel(id: "youtube:@yt3", platform: .youtube, name: "YT 3", handle: "@yt3"),
            WatchedChannel(id: "twitch:tw3", platform: .twitch, name: "TW 3", handle: "tw3")
        ]

        let mockFetcher: HTTPFetcher = { request in
            tracker.enter()
            try await Task.sleep(nanoseconds: 20_000_000) // 20ms
            tracker.exit()

            // Return a valid offline HTML for YouTube or GraphQL response for Twitch
            if request.url?.host?.contains("twitch") == true {
                let json = """
                {"data":{"user":{"id":"1","login":"test","displayName":"Test","profileImageURL":"https://example.com/tw.jpg","stream":null}}}
                """
                let data = Data(json.utf8)
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (data, response)
            } else {
                let html = "<html><head><title>Channel - YouTube</title></head><body>Offline</body></html>"
                let data = Data(html.utf8)
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (data, response)
            }
        }

        let engine = StreamMonitorEngine(batchSize: 3)
        let finalStatuses = await engine.refreshPass(
            channels: channels,
            settings: AppSettings(),
            currentStatuses: [:],
            fetcher: mockFetcher,
            onEvent: { _ in }
        )

        #expect(tracker.peakConcurrency <= 3)
        #expect(finalStatuses.count == 6)
        for channel in channels {
            #expect(finalStatuses[channel.id] != nil)
        }
    }

    // MARK: - Notifications & Deduplication

    private final class EventCollector: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var events: [MonitorEvent] = []

        func add(_ event: MonitorEvent) {
            lock.lock()
            defer { lock.unlock() }
            events.append(event)
        }
    }

    private func makeLiveHTML(videoId: String, channelTitle: String = "Test Channel", streamTitle: String = "Test Stream") -> Data {
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
        return Data(html.utf8)
    }

    private func makeUpcomingHTML(videoId: String, channelTitle: String = "Test Channel", streamTitle: String = "Upcoming Stream") -> Data {
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
        return Data(html.utf8)
    }

    @Test func testRefreshPassDeduplicatesNotificationsAndRespectsSettings() async {
        let chLiveNew = WatchedChannel(
            id: "youtube:@livenew",
            platform: .youtube,
            name: "Live New",
            handle: "@livenew",
            lastNotifiedVideoId: nil
        )
        let chLiveDup = WatchedChannel(
            id: "youtube:@livedup",
            platform: .youtube,
            name: "Live Dup",
            handle: "@livedup",
            lastNotifiedVideoId: "v_already"
        )
        let chUpcomingNew = WatchedChannel(
            id: "youtube:@upnew",
            platform: .youtube,
            name: "Up New",
            handle: "@upnew",
            lastNotifiedUpcomingId: nil
        )
        let chUpcomingDup = WatchedChannel(
            id: "youtube:@updup",
            platform: .youtube,
            name: "Up Dup",
            handle: "@updup",
            lastNotifiedUpcomingId: "u_already"
        )

        let channels = [chLiveNew, chLiveDup, chUpcomingNew, chUpcomingDup]

        let mockFetcher: HTTPFetcher = { request in
            let path = request.url?.absoluteString ?? ""
            let data: Data
            if path.contains("livenew") {
                data = self.makeLiveHTML(videoId: "v_new", streamTitle: "Live Stream 1")
            } else if path.contains("livedup") {
                data = self.makeLiveHTML(videoId: "v_already", streamTitle: "Live Stream 2")
            } else if path.contains("upnew") {
                data = self.makeUpcomingHTML(videoId: "u_new", streamTitle: "Upcoming Stream 1")
            } else {
                data = self.makeUpcomingHTML(videoId: "u_already", streamTitle: "Upcoming Stream 2")
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }

        // 1. Both live & upcoming notifications enabled in settings
        var settings = AppSettings()
        settings.notifyOnLive = true
        settings.notifyOnUpcoming = true

        let collector1 = EventCollector()
        let engine = StreamMonitorEngine()
        _ = await engine.refreshPass(
            channels: channels,
            settings: settings,
            currentStatuses: [:],
            fetcher: mockFetcher,
            onEvent: { collector1.add($0) }
        )

        let liveEvents = collector1.events.compactMap { event -> String? in
            if case .notifyLive(let ch, let vid, _) = event {
                return "\(ch.id):\(vid)"
            }
            return nil
        }
        #expect(liveEvents == ["youtube:@livenew:v_new"])

        let upcomingEvents = collector1.events.compactMap { event -> String? in
            if case .notifyUpcoming(let ch, let vid, _) = event {
                return "\(ch.id):\(vid)"
            }
            return nil
        }
        #expect(upcomingEvents == ["youtube:@upnew:u_new"])

        // 2. Both disabled in settings
        settings.notifyOnLive = false
        settings.notifyOnUpcoming = false

        let collector2 = EventCollector()
        _ = await engine.refreshPass(
            channels: channels,
            settings: settings,
            currentStatuses: [:],
            fetcher: mockFetcher,
            onEvent: { collector2.add($0) }
        )

        let liveEventsDisabled = collector2.events.filter {
            if case .notifyLive = $0 { return true }
            return false
        }
        #expect(liveEventsDisabled.isEmpty)

        let upcomingEventsDisabled = collector2.events.filter {
            if case .notifyUpcoming = $0 { return true }
            return false
        }
        #expect(upcomingEventsDisabled.isEmpty)
    }

    // MARK: - Developer Birthday

    @Test func testRefreshPassEmitsDeveloperBirthdayOncePerYearOnDec31() async {
        let caitlyn = WatchedChannel(
            id: "youtube:@bukancaitlyn",
            platform: .youtube,
            name: "Caitlyn Momochi",
            handle: "@bukancaitlyn"
        )
        let other = WatchedChannel(
            id: "youtube:@other",
            platform: .youtube,
            name: "Other Creator",
            handle: "@other"
        )

        let dec31_2026 = makeDate(year: 2026, month: 12, day: 31)
        let dec30_2026 = makeDate(year: 2026, month: 12, day: 30)
        let dec31_1999 = makeDate(year: 1999, month: 12, day: 31)
        let cal = makeCalendar()

        let dummyFetcher: HTTPFetcher = { req in
            let html = "<html><head><title>YT</title></head></html>"
            return (Data(html.utf8), HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let engine = StreamMonitorEngine()

        // 1. Dec 31 2026 with Caitlyn, not yet notified -> emits .notifyDeveloperBirthday(year: 2026)
        let c1 = EventCollector()
        var s1 = AppSettings()
        s1.lastNotifiedDevBirthdayYear = nil
        _ = await engine.refreshPass(
            channels: [caitlyn],
            settings: s1,
            currentStatuses: [:],
            fetcher: dummyFetcher,
            date: dec31_2026,
            calendar: cal,
            onEvent: { c1.add($0) }
        )
        let bday1 = c1.events.contains { if case .notifyDeveloperBirthday(2026) = $0 { return true }; return false }
        #expect(bday1)

        // 2. Already notified this year -> does NOT emit
        let c2 = EventCollector()
        var s2 = AppSettings()
        s2.lastNotifiedDevBirthdayYear = 2026
        _ = await engine.refreshPass(
            channels: [caitlyn],
            settings: s2,
            currentStatuses: [:],
            fetcher: dummyFetcher,
            date: dec31_2026,
            calendar: cal,
            onEvent: { c2.add($0) }
        )
        let bday2 = c2.events.contains { if case .notifyDeveloperBirthday = $0 { return true }; return false }
        #expect(!bday2)

        // 3. Dec 30 2026 -> does NOT emit
        let c3 = EventCollector()
        _ = await engine.refreshPass(
            channels: [caitlyn],
            settings: s1,
            currentStatuses: [:],
            fetcher: dummyFetcher,
            date: dec30_2026,
            calendar: cal,
            onEvent: { c3.add($0) }
        )
        let bday3 = c3.events.contains { if case .notifyDeveloperBirthday = $0 { return true }; return false }
        #expect(!bday3)

        // 4. Dec 31 1999 (not > 1999) -> does NOT emit
        let c4 = EventCollector()
        _ = await engine.refreshPass(
            channels: [caitlyn],
            settings: s1,
            currentStatuses: [:],
            fetcher: dummyFetcher,
            date: dec31_1999,
            calendar: cal,
            onEvent: { c4.add($0) }
        )
        let bday4 = c4.events.contains { if case .notifyDeveloperBirthday = $0 { return true }; return false }
        #expect(!bday4)

        // 5. Watchlist has no Caitlyn channel on Dec 31 2026 -> does NOT emit
        let c5 = EventCollector()
        _ = await engine.refreshPass(
            channels: [other],
            settings: s1,
            currentStatuses: [:],
            fetcher: dummyFetcher,
            date: dec31_2026,
            calendar: cal,
            onEvent: { c5.add($0) }
        )
        let bday5 = c5.events.contains { if case .notifyDeveloperBirthday = $0 { return true }; return false }
        #expect(!bday5)
    }

    // MARK: - Preserving Metadata on Error or Unrecognized

    @Test func testRefreshPassPreservesMetadataOnHttpErrorOrUnrecognized() async {
        let errorChannel = WatchedChannel(
            id: "youtube:@errchan",
            platform: .youtube,
            name: "Initial Error Channel",
            handle: "@errchan",
            avatarURL: URL(string: "https://example.com/err.jpg")
        )
        let unrecChannel = WatchedChannel(
            id: "youtube:@unrecchan",
            platform: .youtube,
            name: "Initial Unrec Channel",
            handle: "@unrecchan",
            avatarURL: URL(string: "https://example.com/unrec.jpg")
        )

        let mockFetcher: HTTPFetcher = { req in
            let path = req.url?.absoluteString ?? ""
            if path.contains("errchan") {
                throw URLError(.timedOut)
            } else {
                // Return unrecognizable HTML without structured data or channel title
                let html = "<html><body>Something unrecognized</body></html>"
                return (Data(html.utf8), HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
        }

        let collector = EventCollector()
        let engine = StreamMonitorEngine()
        let statuses = await engine.refreshPass(
            channels: [errorChannel, unrecChannel],
            settings: AppSettings(),
            currentStatuses: [:],
            fetcher: mockFetcher,
            onEvent: { collector.add($0) }
        )

        #expect(statuses[errorChannel.id] == .unknown)
        #expect(statuses[unrecChannel.id] == .unknown)

        // MetadataUpdated must NOT have been emitted for either channel
        let metadataEvents = collector.events.filter {
            if case .metadataUpdated = $0 { return true }
            return false
        }
        #expect(metadataEvents.isEmpty)
    }

    // MARK: - Portability Check

    @Test func testVRemindCorePortabilityZeroForbiddenImports() throws {
        // Find Sources/VRemindCore
        var dirURL = URL(fileURLWithPath: #file)
        while dirURL.pathComponents.count > 1 {
            let candidate = dirURL.appendingPathComponent("Sources/VRemindCore", isDirectory: true)
            if FileManager.default.fileExists(atPath: candidate.path) {
                dirURL = candidate
                break
            }
            dirURL = dirURL.deletingLastPathComponent()
        }

        let enumerator = FileManager.default.enumerator(at: dirURL, includingPropertiesForKeys: nil)
        var checkedFileCount = 0
        let forbidden = ["AppKit", "SwiftUI", "Combine", "UserNotifications", "WidgetKit"]

        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "swift" else { continue }
            checkedFileCount += 1
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            for module in forbidden {
                let pattern = "import\\s+\(module)\\b"
                let regex = try NSRegularExpression(pattern: pattern)
                let range = NSRange(content.startIndex..., in: content)
                let matches = regex.matches(in: content, range: range)
                #expect(matches.isEmpty, "File \(fileURL.lastPathComponent) contains forbidden import \(module)")
            }
        }

        #expect(checkedFileCount > 5, "Checked \(checkedFileCount) Swift source files in VRemindCore")
    }
}
