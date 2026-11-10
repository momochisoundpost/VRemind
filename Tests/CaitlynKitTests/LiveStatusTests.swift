import Foundation
import Testing
@testable import CaitlynKit

@MainActor
struct LiveStatusTests {
    nonisolated private static let liveHTML = """
    <html><body><script>var ytInitialPlayerResponse = {"videoDetails":{"isLive":true,"title":"Hackintosh & Chat","videoId":"live123"},"microformat":{"playerMicroformatRenderer":{"liveBroadcastDetails":{"isLiveNow":true,"startTimestamp":"2026-11-09T20:00:00+00:00"}}}};</script></body></html>
    """

    @MainActor
    private final class StubState {
        var nextResponse: String = LiveStatusTests.liveHTML
        var shouldThrow: Bool = false
    }

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

    @Test func unrecognizedPageKeepsPreviousStatus() async {
        let state = StubState()
        let service = LiveStatusService(channelHandle: "@bukancaitlyn") { @MainActor _ in
            state.nextResponse
        }
        await service.refresh()
        #expect(service.status.isLive == true)
        #expect(service.status.videoId == "live123")

        state.nextResponse = "<html>Before you continue to YouTube</html>"
        await service.refresh()
        #expect(service.status.isLive == true)
        #expect(service.status.videoId == "live123")

        state.nextResponse = "<script>var ytInitialData = {};</script>"
        await service.refresh()
        #expect(service.status == .offline)
    }

    @Test func fetchErrorKeepsPreviousStatus() async {
        struct StubError: Error {}
        let state = StubState()
        let service = LiveStatusService(channelHandle: "@bukancaitlyn") { @MainActor _ in
            if state.shouldThrow {
                throw StubError()
            }
            return Self.liveHTML
        }
        await service.refresh()
        #expect(service.status.isLive == true)
        #expect(service.status.videoId == "live123")

        state.shouldThrow = true
        await service.refresh()
        #expect(service.status.isLive == true)
        #expect(service.status.videoId == "live123")
    }
}
