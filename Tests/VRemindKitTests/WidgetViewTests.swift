import AppKit
import Foundation
import SwiftUI
import Testing
@testable import VRemindKit

struct WidgetViewTests {
    private func createTempDirectory() throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WidgetViewTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true, attributes: nil)
        return tempURL
    }

    private func removeTempDirectory(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func createDummyImageFile(at url: URL) throws {
        // Create a 32x32 blank bitmap representation and write as PNG/JPEG
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 32,
            pixelsHigh: 32,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 32 * 4,
            bitsPerPixel: 32
        )!
        let data = rep.representation(using: .jpeg, properties: [:])!
        try data.write(to: url)
    }

    // MARK: - Test 1: SmallHeroWidgetView renders with live creator and uptime

    @Test func smallHeroWidgetViewRendersLiveCreatorAndUptime() {
        let now = Date()
        let liveStarted = now.addingTimeInterval(-3600) // 1h ago
        let channel = WidgetChannelItem(
            handle: "@caitlyn",
            displayName: "Caitlyn Momochi",
            avatarFilename: "caitlyn.jpg",
            statusKind: .live,
            streamTitle: "Chill Piano Stream 🎹",
            videoId: "xyz123",
            liveStartedAt: liveStarted
        )

        let view = SmallHeroWidgetView(channel: channel, allOffline: false)
        #expect(view.channel?.displayName == "Caitlyn Momochi")
        #expect(view.channel?.statusKind == .live)
        #expect(view.isLive == true)
        #expect(view.isDimmed == false)
        #expect(view.uptimeText == ElapsedTime.liveDuration(since: liveStarted, now: now))
        #expect(view.deepLinkURL == URL(string: "vremind://open-stream?url=https://www.youtube.com/watch?v%3Dxyz123"))

        // Verify body evaluation
        _ = view.body
    }

    // MARK: - Test 2: SmallHeroWidgetView renders offline state with dimmed avatar (Review Focus #4)

    @Test func smallHeroWidgetViewRendersOfflineStateWithDimmedAvatar() {
        let lastStreamed = Date().addingTimeInterval(-7200)
        let channel = WidgetChannelItem(
            handle: "@caitlyn",
            displayName: "Caitlyn Momochi",
            avatarFilename: "caitlyn.jpg",
            statusKind: .offline,
            lastStreamedAt: lastStreamed
        )

        let view = SmallHeroWidgetView(channel: channel, allOffline: true)
        #expect(view.isLive == false)
        #expect(view.isDimmed == true)
        #expect(view.channel?.displayName == "Caitlyn Momochi")
        #expect(view.offlineHeadline == "All channels offline")

        // Verify body evaluation
        _ = view.body
    }

    // MARK: - Test 3: SmallHeroWidgetView renders monogram when avatar image is missing (Review Focus #2)

    @Test func smallHeroWidgetViewRendersMonogramWhenAvatarImageMissing() throws {
        let tempDir = try createTempDirectory()
        defer { removeTempDirectory(tempDir) }

        let channel = WidgetChannelItem(
            handle: "@caitlyn",
            displayName: "Caitlyn Momochi",
            avatarFilename: "non_existent.jpg",
            statusKind: .live,
            streamTitle: "Singing Stream",
            videoId: "v123"
        )

        let view = SmallHeroWidgetView(channel: channel, avatarsDirectoryURL: tempDir)
        #expect(view.hasLocalAvatarImage == false)
        #expect(view.monogramLetter == "C")

        // Now create a valid image on disk and confirm hasLocalAvatarImage becomes true
        let imageURL = tempDir.appendingPathComponent("non_existent.jpg")
        try createDummyImageFile(at: imageURL)

        let viewWithImage = SmallHeroWidgetView(channel: channel, avatarsDirectoryURL: tempDir)
        #expect(viewWithImage.hasLocalAvatarImage == true)

        // Verify body evaluation
        _ = view.body
        _ = viewWithImage.body
    }

    // MARK: - Test 4: MediumWatchlistWidgetView renders multi-channel rows with deep links

    @Test func mediumWatchlistWidgetViewRendersMultiChannelRowsWithDeepLinks() {
        let ch1 = WidgetChannelItem(
            handle: "@ch1",
            displayName: "Channel One",
            statusKind: .live,
            streamTitle: "Playing Hollow Knight",
            videoId: "vid1",
            liveStartedAt: Date()
        )
        let ch2 = WidgetChannelItem(
            handle: "@ch2",
            displayName: "Channel Two",
            statusKind: .upcoming,
            streamTitle: "Tomorrow stream",
            videoId: "vid2",
            upcomingStartTime: Date().addingTimeInterval(3600)
        )
        let ch3 = WidgetChannelItem(
            handle: "@ch3",
            displayName: "Channel Three",
            statusKind: .offline
        )

        let view = MediumWatchlistWidgetView(channels: [ch1, ch2, ch3])
        #expect(view.channels.count == 3)
        #expect(view.displayedChannels.count == 3)
        #expect(view.displayedChannels[0].deepLinkURL == URL(string: "vremind://open-stream?url=https://www.youtube.com/watch?v%3Dvid1"))
        #expect(view.displayedChannels[1].deepLinkURL == URL(string: "vremind://open-stream?url=https://www.youtube.com/watch?v%3Dvid2"))
        #expect(view.displayedChannels[2].deepLinkURL == URL(string: "vremind://open-stream?url=https://www.youtube.com/@ch3"))

        // Verify body evaluation
        _ = view.body
    }

    // MARK: - Test 5: LargeDashboardWidgetView renders hero and channel rows

    @Test func largeDashboardWidgetViewRendersHeroAndRows() {
        let ch1 = WidgetChannelItem(
            handle: "@hero",
            displayName: "Hero Creator",
            statusKind: .live,
            streamTitle: "Big Collab Live Now!",
            videoId: "hero1"
        )
        let ch2 = WidgetChannelItem(
            handle: "@two",
            displayName: "Second Channel",
            statusKind: .offline
        )

        let view = LargeDashboardWidgetView(channels: [ch1, ch2])
        #expect(view.heroChannel?.displayName == "Hero Creator")
        #expect(view.remainingChannels.count == 1)
        #expect(view.remainingChannels[0].displayName == "Second Channel")

        // Verify body evaluation
        _ = view.body
    }

    // MARK: - Test 6: VRemindTimelineProvider generates entries from store or fallback

    @Test func timelineProviderGeneratesEntries() {
        let mockStore = MockSnapshotStore()
        let provider = VRemindTimelineProvider(store: mockStore)

        // Placeholder entry
        let placeholder = provider.placeholderEntry()
        #expect(placeholder.snapshot.channels.isEmpty == false)

        // Snapshot entry
        let snapshot = provider.snapshotEntry(isPreview: false)
        #expect(snapshot.snapshot.channels.first?.displayName == "Test")

        // Timeline entry
        let timeline = provider.timelineEntries()
        #expect(timeline.entries.count == 1)
        #expect(timeline.entries.first?.snapshot.channels.first?.displayName == "Test")
    }

    // MARK: - Test 7: VRemindWidgetEntry helper properties

    @Test func widgetEntryHelpers() {
        let liveChannel = WidgetChannelItem(handle: "@live", displayName: "Live", statusKind: .live)
        let offlineChannel = WidgetChannelItem(handle: "@off", displayName: "Off", statusKind: .offline)

        let liveEntry = VRemindWidgetEntry(
            snapshot: WidgetSnapshot(channels: [liveChannel, offlineChannel])
        )
        #expect(liveEntry.heroChannel?.handle == "@live")
        #expect(liveEntry.isAllOffline == false)

        let offlineEntry = VRemindWidgetEntry(
            snapshot: WidgetSnapshot(channels: [offlineChannel])
        )
        #expect(offlineEntry.isAllOffline == true)

        let fallback = VRemindWidgetEntry.fallback
        #expect(fallback.snapshot.channels.count == 1)
        #expect(fallback.snapshot.channels.first?.handle == AppConstants.channelHandle)
    }

    // MARK: - Test 8: SmallHeroWidgetView Monochrome Contrast Adaptation (1.1 Polish)

    @Test func smallHeroWidgetViewMonochromeContrastAdaptsToBlack() {
        let channel = WidgetChannelItem(
            handle: "@caitlyn",
            displayName: "Caitlyn Momochi",
            avatarFilename: nil,
            statusKind: .live,
            streamTitle: "Chill Stream"
        )
        let view = SmallHeroWidgetView(channel: channel)
        #expect(view.primaryTextColor(isMonochrome: false) == Color.white)
        #expect(view.primaryTextColor(isMonochrome: true) == Color.black)
        #expect(view.secondaryTextColor(isMonochrome: false) == Color.white.opacity(0.9))
        #expect(view.secondaryTextColor(isMonochrome: true) == Color.black.opacity(0.85))
    }

    @Test func smallHeroWidgetViewMonogramFallbackMonochromeContrast() {
        let view = SmallHeroWidgetView(channel: nil, allOffline: true)
        #expect(view.primaryTextColor(isMonochrome: true) == Color.black)
        _ = view.body
    }

    private final class MockSnapshotStore: WidgetSnapshotStoreProtocol, @unchecked Sendable {
        var snapshotToReturn: WidgetSnapshot? = WidgetSnapshot(
            generatedAt: Date(),
            channels: [
                WidgetChannelItem(handle: "@test", displayName: "Test", statusKind: .live)
            ]
        )

        func writeSnapshot(channels: [WatchedChannel], statuses: [String: StreamStatus]) async throws {}

        func readSnapshot() -> WidgetSnapshot? {
            snapshotToReturn
        }
    }
}
