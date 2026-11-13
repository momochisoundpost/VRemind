import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol StreamProvider: Sendable {
    var platform: StreamPlatform { get }
    func normalizeHandle(_ input: String) -> String?
    func channelURL(for handle: String) -> URL?
    func watchURL(for channel: WatchedChannel, status: StreamStatus) -> URL?
    func fetchChannelState(for channel: WatchedChannel, fetcher: HTTPFetcher) async throws -> ChannelFetchResult
}

public struct StreamProviderRegistry: Sendable {
    private let providers: [any StreamProvider]

    public init(providers: [any StreamProvider] = [YouTubeStreamProvider(), TwitchStreamProvider()]) {
        self.providers = providers
    }

    public static let `default`: StreamProviderRegistry = StreamProviderRegistry()

    public func provider(for platform: StreamPlatform) -> (any StreamProvider)? {
        providers.first { $0.platform == platform }
    }

    public func watchURL(for channel: WatchedChannel, status: StreamStatus) -> URL? {
        provider(for: channel.platform)?.watchURL(for: channel, status: status)
    }

    public func channelURL(for platform: StreamPlatform, handle: String) -> URL? {
        provider(for: platform)?.channelURL(for: handle)
    }
}
