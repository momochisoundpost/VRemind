import Foundation
import Testing
@testable import VRemindKit

struct LivePageParserTests {
    private static let liveHTML = """
    <html><body><script>var ytInitialPlayerResponse = {"videoDetails":{"isLive":true,"title":"Hackintosh & Chat","videoId":"live123"},"microformat":{"playerMicroformatRenderer":{"liveBroadcastDetails":{"isLiveNow":true,"startTimestamp":"2026-11-09T20:00:00+00:00"}}}};</script></body></html>
    """

    @Test func activeLiveStream() throws {
        let expectedDate = try #require(ISO8601DateFormatter().date(from: "2026-11-09T20:00:00Z"))
        let result = LivePageParser.parse(html: Self.liveHTML)
        #expect(result == .live(videoId: "live123", title: "Hackintosh & Chat", startedAt: expectedDate))
    }

    @Test func braceInsideStringDoesNotBreakExtraction() {
        let html = """
        <script>var ytInitialPlayerResponse = {"videoDetails":{"isLive":true,"title":"a } tricky { title","videoId":"v999"}};</script>
        """
        let result = LivePageParser.parse(html: html)
        #expect(result == .live(videoId: "v999", title: "a } tricky { title", startedAt: nil))
    }

    @Test func parseUpcomingWaitingRoomWithStartTime() throws {
        let html = #"""
        ytInitialPlayerResponse = {"videoDetails":{"videoId":"upcoming123","title":"Karaoke Stream!","isUpcoming":true},"microformat":{"playerMicroformatRenderer":{"liveBroadcastDetails":{"startTimestamp":"2026-11-12T12:00:00Z"}}}}
        """#
        let expectedDate = try #require(ISO8601DateFormatter().date(from: "2026-11-12T12:00:00Z"))
        let result = LivePageParser.parse(html: html)
        #expect(result == .upcoming(videoId: "upcoming123", title: "Karaoke Stream!", scheduledStartTime: expectedDate))
    }

    @Test func scheduledStreamWithoutStartTimeIsUpcoming() {
        let html = """
        <script>var ytInitialPlayerResponse = {"videoDetails":{"isUpcoming":true,"isLiveContent":true,"title":"Upcoming Stream","videoId":"sched456"},"microformat":{"playerMicroformatRenderer":{"liveBroadcastDetails":{"isLiveNow":false}}}};</script>
        """
        #expect(LivePageParser.parse(html: html) == .upcoming(videoId: "sched456", title: "Upcoming Stream", scheduledStartTime: nil))
    }

    @Test func offlineChannelReturnsMetadata() {
        let html = #"ytInitialPlayerResponse = {"videoDetails":{"videoId":"vod123","isLive":false,"isUpcoming":false,"author":"Test VTuber"}}"#
        let result = LivePageParser.parse(html: html)
        #expect(result == .notLive(channelTitle: "Test VTuber", avatarURL: nil))
    }

    @Test func endedStreamWithoutAuthorReturnsNotLiveWithoutMetadata() {
        let html = """
        <script>var ytInitialPlayerResponse = {"videoDetails":{"isLiveContent":true,"title":"Past Stream","videoId":"past789"}};</script>
        """
        #expect(LivePageParser.parse(html: html) == .notLive(channelTitle: nil, avatarURL: nil))
    }

    @Test func channelPageWithAvatarAndTitle() {
        let html = """
        <html>
        <head>
          <title>Caitlyn Momochi - YouTube</title>
          <link rel="image_src" href="https://yt3.googleusercontent.com/ytc/AIdro_test123=s800-c-k-c0x00ffffff-no-rj">
        </head>
        <body><script>var ytInitialData = {};</script></body>
        </html>
        """
        let expectedAvatar = URL(string: "https://yt3.googleusercontent.com/ytc/AIdro_test123=s800-c-k-c0x00ffffff-no-rj")
        #expect(LivePageParser.parse(html: html) == .notLive(channelTitle: "Caitlyn Momochi", avatarURL: expectedAvatar))
    }

    @Test func channelPageWithoutMetadataReturnsNotLiveWithNils() {
        let html = "<script>var ytInitialData = {};</script>"
        #expect(LivePageParser.parse(html: html) == .notLive(channelTitle: nil, avatarURL: nil))
    }

    @Test func consentPageIsUnrecognized() {
        let html = "<html>Before you continue to YouTube</html>"
        #expect(LivePageParser.parse(html: html) == .unrecognized)
    }

    @Test func extractChannelTitleFromVideoDetailsAuthor() {
        let html = #"ytInitialPlayerResponse = {"videoDetails":{"author":"Author Name"}}"#
        #expect(LivePageParser.extractChannelTitle(from: html) == "Author Name")
    }

    @Test func extractChannelTitleFromOgTitleMetaTag() {
        let html = #"<html><head><meta property="og:title" content="Oshi Channel &amp; Gaming - YouTube"></head></html>"#
        #expect(LivePageParser.extractChannelTitle(from: html) == "Oshi Channel & Gaming")
    }

    @Test func extractChannelTitleFromTitleTag() {
        let html = #"<html><head><title>Kobo Kanaeru Ch. hololive-ID - YouTube</title></head></html>"#
        #expect(LivePageParser.extractChannelTitle(from: html) == "Kobo Kanaeru Ch. hololive-ID")
    }

    @Test func extractAvatarURLMatchesGoogleusercontent() {
        let html = #"<link rel="image_src" href="https://yt3.googleusercontent.com/avatar_id=s800">"#
        #expect(LivePageParser.extractAvatarURL(from: html) == URL(string: "https://yt3.googleusercontent.com/avatar_id=s800"))
    }

    @Test func extractAvatarURLReturnsNilWhenAbsent() {
        let html = "<html><body>No avatar here</body></html>"
        #expect(LivePageParser.extractAvatarURL(from: html) == nil)
    }

    @Test func transitionLifecycleFromUpcomingToLive() {
        let upcomingHTML = #"""
        ytInitialPlayerResponse = {"videoDetails":{"videoId":"stream999","title":"Guerilla Live","isUpcoming":true},"microformat":{"playerMicroformatRenderer":{"liveBroadcastDetails":{"startTimestamp":"2026-11-12T12:00:00Z"}}}}
        """#
        let liveHTML = #"""
        ytInitialPlayerResponse = {"videoDetails":{"videoId":"stream999","title":"Guerilla Live","isLive":true,"isUpcoming":false},"microformat":{"playerMicroformatRenderer":{"liveBroadcastDetails":{"isLiveNow":true,"startTimestamp":"2026-11-12T12:00:00Z"}}}}
        """#
        let endedHTML = #"""
        ytInitialPlayerResponse = {"videoDetails":{"videoId":"stream999","title":"Guerilla Live","isLive":false,"isUpcoming":false,"author":"Guerilla VTuber"}}
        """#
        guard case let .upcoming(upId, _, _) = LivePageParser.parse(html: upcomingHTML) else {
            Issue.record("Expected .upcoming")
            return
        }
        #expect(upId == "stream999")

        guard case let .live(liveId, _, _) = LivePageParser.parse(html: liveHTML) else {
            Issue.record("Expected .live")
            return
        }
        #expect(liveId == "stream999")

        guard case let .notLive(author, _) = LivePageParser.parse(html: endedHTML) else {
            Issue.record("Expected .notLive")
            return
        }
        #expect(author == "Guerilla VTuber")
    }
}
