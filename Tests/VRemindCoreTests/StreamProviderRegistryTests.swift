import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import VRemindCore

@Suite struct StreamProviderRegistryTests {
    @Test func testDefaultRegistryResolvesProviders() {
        let registry = StreamProviderRegistry.default

        let ytProvider = registry.provider(for: .youtube)
        #expect(ytProvider != nil)
        #expect(ytProvider?.platform == .youtube)

        let twitchProvider = registry.provider(for: .twitch)
        #expect(twitchProvider != nil)
        #expect(twitchProvider?.platform == .twitch)
    }

    @Test func testWatchURLYouTubeLiveAndOffline() {
        let registry = StreamProviderRegistry.default

        let ytChannel = WatchedChannel(
            id: "youtube:@bukancaitlyn",
            platform: .youtube,
            name: "Caitlyn Momochi",
            handle: "@bukancaitlyn"
        )

        let liveStatus = StreamStatus.live(videoId: "abc", title: "Live Stream", startedAt: nil)
        #expect(registry.watchURL(for: ytChannel, status: liveStatus) == URL(string: "https://www.youtube.com/watch?v=abc"))

        let emptyIdLiveStatus = StreamStatus.live(videoId: "", title: "Live Stream", startedAt: nil)
        #expect(registry.watchURL(for: ytChannel, status: emptyIdLiveStatus) == URL(string: "https://www.youtube.com/@bukancaitlyn/live"))

        let upcomingStatus = StreamStatus.upcoming(videoId: "def", title: "Upcoming", scheduledStartTime: nil)
        #expect(registry.watchURL(for: ytChannel, status: upcomingStatus) == URL(string: "https://www.youtube.com/watch?v=def"))

        let offlineStatus = StreamStatus.offline(lastStreamedAt: nil)
        #expect(registry.watchURL(for: ytChannel, status: offlineStatus) == URL(string: "https://www.youtube.com/@bukancaitlyn/live"))

        let unknownStatus = StreamStatus.unknown
        #expect(registry.watchURL(for: ytChannel, status: unknownStatus) == URL(string: "https://www.youtube.com/@bukancaitlyn/live"))
    }

    @Test func testWatchURLTwitchLiveAndOffline() {
        let registry = StreamProviderRegistry.default

        let twitchChannel = WatchedChannel(
            id: "twitch:ironmouse",
            platform: .twitch,
            name: "ironmouse",
            handle: "ironmouse"
        )

        let liveStatus = StreamStatus.live(videoId: "999", title: "Twitch Live", startedAt: nil)
        #expect(registry.watchURL(for: twitchChannel, status: liveStatus) == URL(string: "https://www.twitch.tv/ironmouse"))

        let offlineStatus = StreamStatus.offline(lastStreamedAt: nil)
        #expect(registry.watchURL(for: twitchChannel, status: offlineStatus) == URL(string: "https://www.twitch.tv/ironmouse"))
    }

    @Test func testChannelURLForPlatforms() {
        let registry = StreamProviderRegistry.default

        #expect(registry.channelURL(for: .youtube, handle: "@bukancaitlyn") == URL(string: "https://www.youtube.com/@bukancaitlyn"))
        #expect(registry.channelURL(for: .youtube, handle: "bukancaitlyn") == URL(string: "https://www.youtube.com/@bukancaitlyn"))
        #expect(registry.channelURL(for: .twitch, handle: "ironmouse") == URL(string: "https://www.twitch.tv/ironmouse"))
        #expect(registry.channelURL(for: .twitch, handle: "@ironmouse") == URL(string: "https://www.twitch.tv/ironmouse"))
    }

    @Test func testCustomRegistryWithMockProvider() {
        struct MockProvider: StreamProvider {
            let platform: StreamPlatform = .youtube
            func normalizeHandle(_ input: String) -> String? { "mock:\(input)" }
            func channelURL(for handle: String) -> URL? { URL(string: "https://mock.example/\(handle)") }
            func watchURL(for channel: WatchedChannel, status: StreamStatus) -> URL? { URL(string: "https://mock.example/watch") }
            func fetchChannelState(for channel: WatchedChannel, fetcher: HTTPFetcher) async throws -> ChannelFetchResult {
                ChannelFetchResult(pageResult: .unrecognized)
            }
        }

        let customRegistry = StreamProviderRegistry(providers: [MockProvider()])
        #expect(customRegistry.provider(for: .youtube) != nil)
        #expect(customRegistry.provider(for: .twitch) == nil)

        let channel = WatchedChannel(id: "youtube:test", platform: .youtube, name: "Test", handle: "test")
        #expect(customRegistry.watchURL(for: channel, status: .offline(lastStreamedAt: nil)) == URL(string: "https://mock.example/watch"))
    }

    @Test func testYouTubeStreamProviderFetchChannelState() async throws {
        let channel = WatchedChannel(
            id: "youtube:@bukancaitlyn",
            platform: .youtube,
            name: "Caitlyn Momochi",
            handle: "@bukancaitlyn"
        )

        final class RequestBox: @unchecked Sendable {
            var request: URLRequest?
        }
        let box = RequestBox()
        let sampleHTML = """
        <!DOCTYPE html>
        <html>
        <head>
          <title>Caitlyn Momochi - YouTube</title>
          <meta property="og:title" content="Caitlyn Momochi">
        </head>
        <body>
          <script>
            var ytInitialPlayerResponse = {
              "videoDetails": {
                "videoId": "yt123",
                "title": "Stream Title",
                "author": "Caitlyn Momochi",
                "isLive": true
              }
            };
          </script>
        </body>
        </html>
        """

        let fetcher: HTTPFetcher = { request in
            box.request = request
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (sampleHTML.data(using: .utf8)!, response)
        }

        let provider = YouTubeStreamProvider()
        let result = try await provider.fetchChannelState(for: channel, fetcher: fetcher)

        let capturedRequest = box.request
        #expect(capturedRequest?.url == URL(string: "https://www.youtube.com/@bukancaitlyn/live"))
        #expect(capturedRequest?.value(forHTTPHeaderField: "User-Agent")?.contains("Mozilla") == true)
        #expect(capturedRequest?.value(forHTTPHeaderField: "Accept-Language")?.contains("en") == true)

        #expect(result.pageResult == .live(videoId: "yt123", title: "Stream Title", startedAt: nil))
        #expect(result.channelTitle == "Caitlyn Momochi")
    }
}
