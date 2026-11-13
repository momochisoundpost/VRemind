import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public typealias HTTPFetcher = @Sendable (URLRequest) async throws -> (Data, URLResponse)

public enum LivePageResult: Equatable, Sendable {
    case live(videoId: String, title: String, startedAt: Date?)
    case upcoming(videoId: String, title: String, scheduledStartTime: Date?)
    case notLive(channelTitle: String?, avatarURL: URL?)
    case unrecognized
}

public struct ChannelFetchResult: Equatable, Sendable {
    public let pageResult: LivePageResult
    public let channelTitle: String?
    public let avatarURL: URL?

    public init(
        pageResult: LivePageResult,
        channelTitle: String? = nil,
        avatarURL: URL? = nil
    ) {
        self.pageResult = pageResult
        self.channelTitle = channelTitle
        self.avatarURL = avatarURL
    }
}
