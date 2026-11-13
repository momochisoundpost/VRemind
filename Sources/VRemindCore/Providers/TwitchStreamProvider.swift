import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct TwitchStreamProvider: StreamProvider {
    public static let publicWebClientID = "kimne78kx3ncx6brgo4mv6wki5h1ko"
    public static let graphQLEndpoint = URL(string: "https://gql.twitch.tv/gql")!

    public var platform: StreamPlatform { .twitch }

    public init() {}

    public func normalizeHandle(_ input: String) -> String? {
        WatchedChannel.normalizeHandle(input, for: .twitch)
    }

    public func channelURL(for handle: String) -> URL? {
        let clean = handle.trimmingCharacters(in: CharacterSet(charactersIn: "@").union(.whitespacesAndNewlines))
        guard !clean.isEmpty else { return nil }
        let lower = clean.lowercased()
        guard let encoded = lower.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: "https://www.twitch.tv/\(encoded)")
    }

    public func watchURL(for channel: WatchedChannel, status: StreamStatus) -> URL? {
        channelURL(for: channel.handle)
    }

    public func fetchChannelState(for channel: WatchedChannel, fetcher: HTTPFetcher) async throws -> ChannelFetchResult {
        var request = URLRequest(url: Self.graphQLEndpoint)
        request.httpMethod = "POST"
        request.setValue(Self.publicWebClientID, forHTTPHeaderField: "Client-ID")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let cleanHandle = channel.handle.trimmingCharacters(in: CharacterSet(charactersIn: "@").union(.whitespacesAndNewlines)).lowercased()
        let query = """
        query($login: String!) {
            user(login: $login) {
                id
                login
                displayName
                profileImageURL(width: 300)
                stream {
                    id
                    title
                    createdAt
                    type
                }
            }
        }
        """
        let body: [String: Any] = [
            "query": query,
            "variables": ["login": cleanHandle]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await fetcher(request)

        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            return ChannelFetchResult(pageResult: .unrecognized)
        }

        let pageResult = TwitchResponseParser.parse(data: data)
        let channelTitle = TwitchResponseParser.extractChannelTitle(from: data)
        let avatarURL = TwitchResponseParser.extractAvatarURL(from: data)

        return ChannelFetchResult(pageResult: pageResult, channelTitle: channelTitle, avatarURL: avatarURL)
    }
}
