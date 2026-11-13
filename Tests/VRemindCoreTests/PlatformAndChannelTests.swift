import Foundation
import Testing
@testable import VRemindCore

@Suite struct PlatformAndChannelTests {
    @Test func testLegacyWatchedChannelDecodesAsYouTubeAndMigratesID() throws {
        let json = """
        {
            "id": "@bukancaitlyn",
            "name": "Caitlyn Momochi",
            "handle": "@bukancaitlyn",
            "lastNotifiedVideoId": "vid1"
        }
        """.data(using: .utf8)!

        let channel = try JSONDecoder().decode(WatchedChannel.self, from: json)
        #expect(channel.platform == .youtube)
        #expect(channel.id == "youtube:@bukancaitlyn")
        #expect(channel.handle == "@bukancaitlyn")
        #expect(channel.name == "Caitlyn Momochi")
        #expect(channel.lastNotifiedVideoId == "vid1")
    }

    @Test func testWatchedChannelCodableRoundTripWithPlatform() throws {
        let channel = WatchedChannel(
            id: "twitch:ironmouse",
            platform: .twitch,
            name: "ironmouse",
            handle: "ironmouse",
            avatarURL: URL(string: "https://example.com/ironmouse.jpg"),
            lastNotifiedVideoId: "stream123",
            lastNotifiedUpcomingId: nil,
            lastStreamedAt: Date(timeIntervalSince1970: 1700000000)
        )

        let data = try JSONEncoder().encode(channel)
        let decoded = try JSONDecoder().decode(WatchedChannel.self, from: data)

        #expect(decoded == channel)
        #expect(decoded.id == "twitch:ironmouse")
        #expect(decoded.platform == .twitch)
        #expect(decoded.handle == "ironmouse")
        #expect(decoded.name == "ironmouse")
        #expect(decoded.avatarURL == URL(string: "https://example.com/ironmouse.jpg"))
        #expect(decoded.lastNotifiedVideoId == "stream123")
        #expect(decoded.lastStreamedAt == Date(timeIntervalSince1970: 1700000000))
    }

    @Test func testMakeIDSeparatesSameHandleAcrossPlatforms() {
        let ytID = WatchedChannel.makeID(platform: .youtube, handle: "@ironmouse")
        let twitchID = WatchedChannel.makeID(platform: .twitch, handle: "ironmouse")
        #expect(ytID != twitchID)
        #expect(ytID == "youtube:@ironmouse")
        #expect(twitchID == "twitch:ironmouse")
        #expect(WatchedChannel.makeID(platform: .twitch, handle: "IronMouse") == "twitch:ironmouse")
    }

    @Test func testTwitchHandleNormalization() {
        #expect(WatchedChannel.normalizeHandle("ironmouse", for: .twitch) == "ironmouse")
        #expect(WatchedChannel.normalizeHandle("@IronMouse", for: .twitch) == "ironmouse")
        #expect(WatchedChannel.normalizeHandle("https://www.twitch.tv/IronMouse", for: .twitch) == "ironmouse")
        #expect(WatchedChannel.normalizeHandle("twitch.tv/ironmouse/schedule?foo=1", for: .twitch) == "ironmouse")

        // Rejections
        #expect(WatchedChannel.normalizeHandle("", for: .twitch) == nil)
        #expect(WatchedChannel.normalizeHandle("bad-dash", for: .twitch) == nil)
        #expect(WatchedChannel.normalizeHandle("user name", for: .twitch) == nil)
        #expect(WatchedChannel.normalizeHandle("https://twitch.tv/", for: .twitch) == nil)
        #expect(WatchedChannel.normalizeHandle("https://twitch.tv/directory/following", for: .twitch) == nil)
        let twentySixChars = String(repeating: "a", count: 26)
        #expect(WatchedChannel.normalizeHandle(twentySixChars, for: .twitch) == nil)
    }

    @Test func testDetectPlatformAndHandleFromURL() {
        let twitchResult = WatchedChannel.detectPlatformAndHandle(from: "https://twitch.tv/ironmouse")
        #expect(twitchResult?.platform == .twitch)
        #expect(twitchResult?.handle == "ironmouse")

        let ytResult = WatchedChannel.detectPlatformAndHandle(from: "https://youtube.com/@bukancaitlyn")
        #expect(ytResult?.platform == .youtube)
        #expect(ytResult?.handle == "@bukancaitlyn")

        let bareResult = WatchedChannel.detectPlatformAndHandle(from: "ironmouse")
        #expect(bareResult == nil)
    }

    @Test func testStreamPlatformProperties() {
        #expect(StreamPlatform.youtube.displayName == "YouTube")
        #expect(StreamPlatform.twitch.displayName == "Twitch")
        #expect(StreamPlatform.allCases == [.youtube, .twitch])
    }
}
