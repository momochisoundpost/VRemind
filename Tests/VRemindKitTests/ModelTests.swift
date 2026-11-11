import Foundation
import Testing
@testable import VRemindKit

struct ModelTests {
    // MARK: - WatchedChannel Tests

    @Test func normalizeHandleVariants() {
        #expect(WatchedChannel.normalizeHandle("@bukancaitlyn") == "@bukancaitlyn")
        #expect(WatchedChannel.normalizeHandle("bukancaitlyn") == "@bukancaitlyn")
        #expect(WatchedChannel.normalizeHandle("  @bukancaitlyn  ") == "@bukancaitlyn")
        #expect(WatchedChannel.normalizeHandle("  bukancaitlyn  ") == "@bukancaitlyn")
        #expect(WatchedChannel.normalizeHandle("https://www.youtube.com/@bukancaitlyn") == "@bukancaitlyn")
        #expect(WatchedChannel.normalizeHandle("https://youtube.com/@bukancaitlyn/live") == "@bukancaitlyn")
        #expect(WatchedChannel.normalizeHandle("youtube.com/@bukancaitlyn") == "@bukancaitlyn")
        #expect(WatchedChannel.normalizeHandle("https://www.youtube.com/@bukancaitlyn?si=123") == "@bukancaitlyn")
        #expect(WatchedChannel.normalizeHandle("www.youtube.com/@bukancaitlyn") == "@bukancaitlyn")
        #expect(WatchedChannel.normalizeHandle("@user.name-1_2") == "@user.name-1_2")
        
        // Invalid handles
        #expect(WatchedChannel.normalizeHandle("") == nil)
        #expect(WatchedChannel.normalizeHandle("   \n\t  ") == nil)
        #expect(WatchedChannel.normalizeHandle("@") == nil)
        #expect(WatchedChannel.normalizeHandle("@@bukancaitlyn") == nil)
        #expect(WatchedChannel.normalizeHandle("@bukan caitlyn") == nil)
        #expect(WatchedChannel.normalizeHandle("@bukan!caitlyn") == nil)
        #expect(WatchedChannel.normalizeHandle("@bukan#caitlyn") == nil)
        #expect(WatchedChannel.normalizeHandle("https://www.youtube.com/") == nil)
        #expect(WatchedChannel.normalizeHandle("https://www.youtube.com/watch?v=123") == nil)
    }

    @Test func watchedChannelDefaultInitializer() {
        let channel = WatchedChannel(id: "@bukancaitlyn", name: "Caitlyn", handle: "@bukancaitlyn")
        #expect(channel.id == "@bukancaitlyn")
        #expect(channel.name == "Caitlyn")
        #expect(channel.handle == "@bukancaitlyn")
        #expect(channel.avatarURL == nil)
        #expect(channel.lastNotifiedVideoId == nil)
        #expect(channel.lastNotifiedUpcomingId == nil)
        #expect(channel.lastStreamedAt == nil)
    }

    @Test func watchedChannelCodableRoundTrip() throws {
        let channel = WatchedChannel(
            id: "@bukancaitlyn",
            name: "Caitlyn Momochi",
            handle: "@bukancaitlyn",
            avatarURL: URL(string: "https://example.com/avatar.jpg"),
            lastNotifiedVideoId: "vid123",
            lastNotifiedUpcomingId: "upc456",
            lastStreamedAt: Date(timeIntervalSince1970: 1700000000)
        )
        let data = try JSONEncoder().encode(channel)
        let decoded = try JSONDecoder().decode(WatchedChannel.self, from: data)
        #expect(channel == decoded)
    }

    // MARK: - StreamStatus Tests

    @Test func streamStatusCodableRoundTrip() throws {
        let statuses: [StreamStatus] = [
            .live(videoId: "vid1", title: "Live Now", startedAt: Date(timeIntervalSince1970: 1700000000)),
            .upcoming(videoId: "vid2", title: "Coming Soon", scheduledStartTime: Date(timeIntervalSince1970: 1700010000)),
            .offline(lastStreamedAt: Date(timeIntervalSince1970: 1699990000)),
            .unknown
        ]

        for status in statuses {
            let data = try JSONEncoder().encode(status)
            let decoded = try JSONDecoder().decode(StreamStatus.self, from: data)
            #expect(status == decoded)
        }
    }

    // MARK: - AppSettings Tests

    @Test func appSettingsDefaults() {
        let settings = AppSettings()
        #expect(settings.launchAtLogin == false)
        #expect(settings.notifyOnLive == true)
        #expect(settings.notifyOnUpcoming == false)
        #expect(settings.playNotificationSound == true)
        #expect(settings.hasCompletedOnboarding == false)
    }

    @Test func appSettingsCodableRoundTrip() throws {
        let settings = AppSettings(
            launchAtLogin: true,
            notifyOnLive: false,
            notifyOnUpcoming: true,
            playNotificationSound: false,
            hasCompletedOnboarding: true
        )
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(settings == decoded)
    }
}
