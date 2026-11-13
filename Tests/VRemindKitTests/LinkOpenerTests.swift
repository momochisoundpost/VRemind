import Foundation
import Testing
import VRemindCore
@testable import VRemindKit

struct LinkOpenerTests {
    @Test func videoURLFormat() {
        #expect(LinkOpener.videoURL(for: "42hstxcifYU").absoluteString
                == "https://www.youtube.com/watch?v=42hstxcifYU")
    }

    @Test func videoURLPercentEncodesUnsanitizedInput() {
        let url = LinkOpener.videoURL(for: "test video id?x=1")
        #expect(url.absoluteString == "https://www.youtube.com/watch?v=test%20video%20id?x=1")
    }

    @Test func parseStreamDeepLinkExtractsValidTargetURL() {
        let rawDeepLink = URL(string: "vremind://open-stream?url=https://www.youtube.com/watch?v=42hstxcifYU")!
        let target = LinkOpener.parseStreamDeepLink(rawDeepLink)
        #expect(target?.absoluteString == "https://www.youtube.com/watch?v=42hstxcifYU")

        // Also verify .shared instance accessor
        let sharedTarget = LinkOpener.shared.parseStreamDeepLink(rawDeepLink)
        #expect(sharedTarget?.absoluteString == "https://www.youtube.com/watch?v=42hstxcifYU")

        let channelDeepLink = URL(string: "vremind://open-stream?url=https://www.youtube.com/@caitlyn")!
        let channelTarget = LinkOpener.parseStreamDeepLink(channelDeepLink)
        #expect(channelTarget?.absoluteString == "https://www.youtube.com/@caitlyn")

        let encodedDeepLink = URL(string: "vremind://open-stream?url=https%3A%2F%2Fwww.youtube.com%2Fwatch%3Fv%3D42hstxcifYU")!
        let encodedTarget = LinkOpener.parseStreamDeepLink(encodedDeepLink)
        #expect(encodedTarget?.absoluteString == "https://www.youtube.com/watch?v=42hstxcifYU")

        let httpDeepLink = URL(string: "vremind://open-stream?url=http://example.com/stream")!
        let httpTarget = LinkOpener.parseStreamDeepLink(httpDeepLink)
        #expect(httpTarget?.absoluteString == "http://example.com/stream")
    }

    @Test func parseStreamDeepLinkRejectsInvalidSchemesAndHosts() {
        let invalidScheme = URL(string: "https://open-stream?url=https://www.youtube.com")!
        #expect(LinkOpener.parseStreamDeepLink(invalidScheme) == nil)

        let invalidHost = URL(string: "vremind://preferences?url=https://www.youtube.com")!
        #expect(LinkOpener.parseStreamDeepLink(invalidHost) == nil)
    }

    @Test func parseStreamDeepLinkRejectsMissingOrEmptyURLParameter() {
        let noQuery = URL(string: "vremind://open-stream")!
        #expect(LinkOpener.parseStreamDeepLink(noQuery) == nil)

        let wrongQuery = URL(string: "vremind://open-stream?channel=caitlyn")!
        #expect(LinkOpener.parseStreamDeepLink(wrongQuery) == nil)

        let emptyURL = URL(string: "vremind://open-stream?url=")!
        #expect(LinkOpener.parseStreamDeepLink(emptyURL) == nil)

        let spacesOnly = URL(string: "vremind://open-stream?url=%20%20")!
        #expect(LinkOpener.parseStreamDeepLink(spacesOnly) == nil)
    }

    @Test func parseStreamDeepLinkRejectsNonHttpSchemesAndMalformedTargets() {
        // Review Focus #5: reject file://, javascript:, data:, and nested custom schemes
        let fileURL = URL(string: "vremind://open-stream?url=file:///etc/passwd")!
        #expect(LinkOpener.parseStreamDeepLink(fileURL) == nil)

        let jsURL = URL(string: "vremind://open-stream?url=javascript:alert(1)")!
        #expect(LinkOpener.parseStreamDeepLink(jsURL) == nil)

        let dataURL = URL(string: "vremind://open-stream?url=data:text/html;base64,PHNjcmlwdD4=")!
        #expect(LinkOpener.parseStreamDeepLink(dataURL) == nil)

        let nestedVremind = URL(string: "vremind://open-stream?url=vremind://open-stream")!
        #expect(LinkOpener.parseStreamDeepLink(nestedVremind) == nil)

        let malformedTarget = URL(string: "vremind://open-stream?url=not_a_valid_url")!
        #expect(LinkOpener.parseStreamDeepLink(malformedTarget) == nil)

        let noHostTarget = URL(string: "vremind://open-stream?url=https://")!
        #expect(LinkOpener.parseStreamDeepLink(noHostTarget) == nil)
    }

    @Test func testStreamURLForTwitch() {
        let twitchChannel = WatchedChannel(
            id: "twitch:ironmouse",
            platform: .twitch,
            name: "Ironmouse",
            handle: "ironmouse"
        )
        let liveStatus = StreamStatus.live(videoId: "stream123", title: "Live", startedAt: Date())
        let url = LinkOpener.streamURL(for: twitchChannel, status: liveStatus)
        #expect(url.absoluteString == "https://www.twitch.tv/ironmouse")
    }

    @Test func testStreamURLForYouTube() {
        let youtubeChannel = WatchedChannel(
            id: "youtube:@bukancaitlyn",
            platform: .youtube,
            name: "Caitlyn Momochi",
            handle: "@bukancaitlyn"
        )
        let liveStatus = StreamStatus.live(videoId: "abc", title: "Live", startedAt: Date())
        let url = LinkOpener.streamURL(for: youtubeChannel, status: liveStatus)
        #expect(url.absoluteString == "https://www.youtube.com/watch?v=abc")
    }

    @Test func testChannelURLForPlatforms() {
        #expect(LinkOpener.channelURL(for: .twitch, handle: "ironmouse") == URL(string: "https://www.twitch.tv/ironmouse")!)
        #expect(LinkOpener.channelURL(for: .youtube, handle: "@bukancaitlyn") == URL(string: "https://www.youtube.com/@bukancaitlyn")!)
    }
}
