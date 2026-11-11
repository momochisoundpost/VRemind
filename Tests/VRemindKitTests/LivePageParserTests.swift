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

    @Test func scheduledStreamIsNotLive() {
        let html = """
        <script>var ytInitialPlayerResponse = {"videoDetails":{"isUpcoming":true,"isLiveContent":true,"title":"Upcoming Stream","videoId":"sched456"},"microformat":{"playerMicroformatRenderer":{"liveBroadcastDetails":{"isLiveNow":false}}}};</script>
        """
        #expect(LivePageParser.parse(html: html) == .notLive)
    }

    @Test func endedStreamIsNotLive() {
        let html = """
        <script>var ytInitialPlayerResponse = {"videoDetails":{"isLiveContent":true,"title":"Past Stream","videoId":"past789"}};</script>
        """
        #expect(LivePageParser.parse(html: html) == .notLive)
    }

    @Test func channelPageIsNotLive() {
        let html = "<script>var ytInitialData = {};</script>"
        #expect(LivePageParser.parse(html: html) == .notLive)
    }

    @Test func consentPageIsUnrecognized() {
        let html = "<html>Before you continue to YouTube</html>"
        #expect(LivePageParser.parse(html: html) == .unrecognized)
    }
}
