import Foundation
import Testing
@testable import VRemindKit

struct WidgetSnapshotStoreTests {
    private func createTemporaryDirectory() throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WidgetSnapshotStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true, attributes: nil)
        return tempURL
    }

    private func removeTemporaryDirectory(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var _value = 0
        var value: Int {
            lock.lock()
            defer { lock.unlock() }
            return _value
        }
        func increment() {
            lock.lock()
            defer { lock.unlock() }
            _value += 1
        }
    }

    // MARK: - Test 1: Custom Directory Injection Round-trip

    @Test func customDirectoryInjectionWritesAndReadsWidgetCache() async throws {
        let tempDir = try createTemporaryDirectory()
        defer { removeTemporaryDirectory(tempDir) }

        let reloadCounter = Counter()
        let store = WidgetSnapshotStore(
            directoryURL: tempDir,
            timelineReloader: {
                reloadCounter.increment()
            }
        )

        let channel1 = WatchedChannel(
            id: "channel-1",
            name: "Caitlyn Momochi",
            handle: "@bukancaitlyn",
            avatarURL: URL(string: "https://example.com/avatar1.jpg")
        )
        let channel2 = WatchedChannel(
            id: "channel-2",
            name: "Other Creator",
            handle: "othercreator",
            avatarURL: nil
        )

        let liveDate = Date(timeIntervalSince1970: 1731401000)
        let statuses: [String: StreamStatus] = [
            channel1.id: .live(videoId: "vid1", title: "Live Concert", startedAt: liveDate),
            channel2.id: .offline(lastStreamedAt: nil)
        ]

        try await store.writeSnapshot(channels: [channel1, channel2], statuses: statuses)

        let cacheFile = tempDir.appendingPathComponent("widget-cache.json")
        #expect(FileManager.default.fileExists(atPath: cacheFile.path))
        #expect(reloadCounter.value == 1)

        let snapshot = store.readSnapshot()
        #expect(snapshot != nil)
        #expect(snapshot?.channels.count == 2)

        let first = snapshot?.channels.first
        #expect(first?.handle == "@bukancaitlyn")
        #expect(first?.displayName == "Caitlyn Momochi")
        #expect(first?.statusKind == .live)
        #expect(first?.streamTitle == "Live Concert")
        #expect(first?.videoId == "vid1")
        #expect(first?.liveStartedAt == liveDate)

        let second = snapshot?.channels.last
        #expect(second?.handle == "othercreator")
        #expect(second?.displayName == "Other Creator")
        #expect(second?.statusKind == .offline)
    }

    // MARK: - Test 2: Missing File Returns Nil Gracefully

    @Test func readSnapshotReturnsNilWhenFileMissing() throws {
        let tempDir = try createTemporaryDirectory()
        defer { removeTemporaryDirectory(tempDir) }

        let store = WidgetSnapshotStore(directoryURL: tempDir)
        let snapshot = store.readSnapshot()
        #expect(snapshot == nil)
    }

    // MARK: - Test 3: Corrupt JSON Returns Nil Gracefully (Review Focus #1)

    @Test func readSnapshotReturnsNilOnCorruptJSON() throws {
        let tempDir = try createTemporaryDirectory()
        defer { removeTemporaryDirectory(tempDir) }

        let cacheFile = tempDir.appendingPathComponent("widget-cache.json")
        let corruptData = Data("{{invalid-corrupt-json-payload-not-a-snapshot}}".utf8)
        try corruptData.write(to: cacheFile)

        let store = WidgetSnapshotStore(directoryURL: tempDir)
        let snapshot = store.readSnapshot()
        #expect(snapshot == nil)
    }

    // MARK: - Test 4: Sorting Logic Picks Most Recently Live Channel as Primary (Review Focus #3)

    @Test func sortingLogicPicksMostRecentlyLiveChannelAsPrimary() async throws {
        let tempDir = try createTemporaryDirectory()
        defer { removeTemporaryDirectory(tempDir) }

        let store = WidgetSnapshotStore(directoryURL: tempDir)

        let earlierLiveDate = Date(timeIntervalSince1970: 1731401000)
        let moreRecentLiveDate = Date(timeIntervalSince1970: 1731405000)
        let upcomingDate = Date(timeIntervalSince1970: 1731409000)
        let lastStreamedDate = Date(timeIntervalSince1970: 1731300000)

        let channelEarlier = WatchedChannel(
            id: "ch-earlier",
            name: "Earlier Live",
            handle: "@earlier"
        )
        let channelRecent = WatchedChannel(
            id: "ch-recent",
            name: "Recent Live",
            handle: "@recent"
        )
        let channelUpcoming = WatchedChannel(
            id: "ch-upcoming",
            name: "Upcoming Channel",
            handle: "@upcoming"
        )
        let channelOffline = WatchedChannel(
            id: "ch-offline",
            name: "Offline Channel",
            handle: "@offline"
        )

        let statuses: [String: StreamStatus] = [
            channelEarlier.id: .live(videoId: "v1", title: "Earlier Stream", startedAt: earlierLiveDate),
            channelRecent.id: .live(videoId: "v2", title: "Recent Stream", startedAt: moreRecentLiveDate),
            channelUpcoming.id: .upcoming(videoId: "v3", title: "Later Stream", scheduledStartTime: upcomingDate),
            channelOffline.id: .offline(lastStreamedAt: lastStreamedDate)
        ]

        // Pass channels with channelEarlier first
        try await store.writeSnapshot(
            channels: [channelEarlier, channelRecent, channelUpcoming, channelOffline],
            statuses: statuses
        )

        let snapshot = store.readSnapshot()
        #expect(snapshot != nil)
        guard let channels = snapshot?.channels else {
            Issue.record("Expected snapshot channels to be present")
            return
        }

        #expect(channels.count == 4)
        // Primary channel should be the one who went live most recently (channelRecent)
        #expect(channels[0].handle == "@recent")
        #expect(channels[0].statusKind == .live)
        #expect(channels[0].liveStartedAt == moreRecentLiveDate)

        // Second should be earlier live channel
        #expect(channels[1].handle == "@earlier")
        #expect(channels[1].statusKind == .live)
        #expect(channels[1].liveStartedAt == earlierLiveDate)

        // Third should be upcoming channel
        #expect(channels[2].handle == "@upcoming")
        #expect(channels[2].statusKind == .upcoming)

        // Fourth should be offline channel
        #expect(channels[3].handle == "@offline")
        #expect(channels[3].statusKind == .offline)
    }

    // MARK: - Test 5: Local Avatar File Caching

    @Test func avatarLocalFileCachingWritesToAvatarsDirectory() async throws {
        let tempDir = try createTemporaryDirectory()
        defer { removeTemporaryDirectory(tempDir) }

        // Create a local source image file to simulate avatar URL
        let sourceImageURL = tempDir.appendingPathComponent("source-avatar.jpg")
        let dummyImageData = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46]) // JPEG magic bytes
        try dummyImageData.write(to: sourceImageURL)

        let channel = WatchedChannel(
            id: "caitlyn-id",
            name: "Caitlyn Momochi",
            handle: "@bukancaitlyn",
            avatarURL: sourceImageURL
        )

        let store = WidgetSnapshotStore(directoryURL: tempDir)
        try await store.writeSnapshot(
            channels: [channel],
            statuses: [channel.id: StreamStatus.offline(lastStreamedAt: nil)]
        )

        let cachedAvatarFile = tempDir.appendingPathComponent("Avatars/youtube_bukancaitlyn.jpg")
        #expect(FileManager.default.fileExists(atPath: cachedAvatarFile.path))

        let readData = try Data(contentsOf: cachedAvatarFile)
        #expect(readData == dummyImageData)

        let snapshot = store.readSnapshot()
        #expect(snapshot?.channels.first?.avatarFilename == "youtube_bukancaitlyn.jpg")
    }

    // MARK: - Test 6: Cross-Platform Avatar Filename Isolation

    @Test func avatarFilenamePlatformIsolation() {
        let ytFilename = WidgetSnapshotStore.avatarFilename(for: "@ironmouse", platform: .youtube)
        let twitchFilename = WidgetSnapshotStore.avatarFilename(for: "ironmouse", platform: .twitch)
        #expect(ytFilename == "youtube_ironmouse.jpg")
        #expect(twitchFilename == "twitch_ironmouse.jpg")
        #expect(ytFilename != twitchFilename)
    }

    @Test func writeSnapshotWithCrossPlatformChannelsStoresDistinctItemsAndAvatars() async throws {
        let tempDir = try createTemporaryDirectory()
        defer { removeTemporaryDirectory(tempDir) }

        let store = WidgetSnapshotStore(directoryURL: tempDir)

        let ytChannel = WatchedChannel(
            id: "youtube:@ironmouse",
            platform: .youtube,
            name: "Ironmouse YT",
            handle: "@ironmouse"
        )
        let twitchChannel = WatchedChannel(
            id: "twitch:ironmouse",
            platform: .twitch,
            name: "Ironmouse Twitch",
            handle: "ironmouse"
        )

        let liveDate = Date(timeIntervalSince1970: 1731401000)
        let statuses: [String: StreamStatus] = [
            ytChannel.id: .live(videoId: "yt123", title: "YT Stream", startedAt: liveDate),
            twitchChannel.id: .live(videoId: "999", title: "Twitch Stream", startedAt: liveDate)
        ]

        try await store.writeSnapshot(channels: [ytChannel, twitchChannel], statuses: statuses)

        let snapshot = try #require(store.readSnapshot())
        #expect(snapshot.channels.count == 2)
        let ids = snapshot.channels.map(\.id)
        #expect(ids.contains("youtube:@ironmouse"))
        #expect(ids.contains("twitch:ironmouse"))

        let ytItem = try #require(snapshot.channels.first(where: { $0.platform == .youtube }))
        let twitchItem = try #require(snapshot.channels.first(where: { $0.platform == .twitch }))

        #expect(ytItem.id != twitchItem.id)
        #expect(WidgetSnapshotStore.avatarFilename(for: ytItem.handle, platform: ytItem.platform) !=
                WidgetSnapshotStore.avatarFilename(for: twitchItem.handle, platform: twitchItem.platform))
    }

    // MARK: - Test 7: Container Path Resolution

    @Test func resolveDefaultDirectoryURLForHostAndWidgetExtension() {
        // Unsandboxed host app resolution
        let hostURL = WidgetSnapshotStore.resolveDefaultDirectoryURL(
            bundleIdentifier: "com.caitlyn.vremind",
            bundleURL: URL(fileURLWithPath: "/Applications/VRemind.app"),
            widgetBundleIdentifier: "com.caitlyn.vremind.widget"
        )
        #expect(hostURL.path.contains("Library/Containers/com.caitlyn.vremind.widget/Data/Library/Application Support/VRemind"))

        // Sandboxed widget extension resolution
        let widgetURL = WidgetSnapshotStore.resolveDefaultDirectoryURL(
            bundleIdentifier: "com.caitlyn.vremind.widget",
            bundleURL: URL(fileURLWithPath: "/Applications/VRemind.app/Contents/PlugIns/VRemindWidget.appex"),
            widgetBundleIdentifier: "com.caitlyn.vremind.widget"
        )
        #expect(widgetURL.path.hasSuffix("Library/Application Support/VRemind"))
    }
}
