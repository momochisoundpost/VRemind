import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct YouTubeStreamProvider: StreamProvider {
    public var platform: StreamPlatform { .youtube }

    public init() {}

    public func normalizeHandle(_ input: String) -> String? {
        WatchedChannel.normalizeHandle(input, for: .youtube)
    }

    public func channelURL(for handle: String) -> URL? {
        let trimmed = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let formatted = trimmed.hasPrefix("@") ? trimmed : "@\(trimmed)"
        guard let encoded = formatted.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: "https://www.youtube.com/\(encoded)")
    }

    public func watchURL(for channel: WatchedChannel, status: StreamStatus) -> URL? {
        switch status {
        case .live(let videoId, _, _), .upcoming(let videoId, _, _):
            let trimmedId = videoId.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedId.isEmpty {
                let encoded = trimmedId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmedId
                return URL(string: "https://www.youtube.com/watch?v=\(encoded)")
            }
        case .offline, .unknown:
            break
        }

        let handle = channel.handle.trimmingCharacters(in: .whitespacesAndNewlines)
        let formatted = handle.hasPrefix("@") ? handle : "@\(handle)"
        let encoded = formatted.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? formatted
        return URL(string: "https://www.youtube.com/\(encoded)/live")
    }

    public func fetchChannelState(for channel: WatchedChannel, fetcher: HTTPFetcher) async throws -> ChannelFetchResult {
        let handle = channel.handle.trimmingCharacters(in: .whitespacesAndNewlines)
        let formatted = handle.hasPrefix("@") ? handle : "@\(handle)"
        guard let encoded = formatted.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://www.youtube.com/\(encoded)/live") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        let (data, _) = try await fetcher(request)

        #if canImport(ObjectiveC)
        return autoreleasepool {
            parseHTML(data)
        }
        #else
        return parseHTML(data)
        #endif
    }

    private func parseHTML(_ data: Data) -> ChannelFetchResult {
        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            return ChannelFetchResult(pageResult: .unrecognized)
        }
        let parsed = LivePageParser.parse(html: html)
        let title = LivePageParser.extractChannelTitle(from: html)
        let avatar = LivePageParser.extractAvatarURL(from: html)
        return ChannelFetchResult(pageResult: parsed, channelTitle: title, avatarURL: avatar)
    }
}
