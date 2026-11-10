import Combine
import Foundation

@MainActor
public final class LiveStatusService: ObservableObject {
    public typealias Fetcher = @Sendable (URL) async throws -> String

    @Published public private(set) var status: StreamStatus = .offline

    private let channelHandle: String
    private let fetcher: Fetcher

    public init(
        channelHandle: String = AppConstants.channelHandle,
        fetcher: Fetcher? = nil
    ) {
        self.channelHandle = channelHandle
        if let fetcher {
            self.fetcher = fetcher
        } else {
            self.fetcher = Self.defaultFetcher
        }
    }

    public func refresh() async {
        guard let url = URL(string: "https://www.youtube.com/\(channelHandle)/live") else {
            return
        }
        do {
            let html = try await fetcher(url)
            switch LivePageParser.parse(html: html) {
            case let .live(videoId, title, startedAt):
                self.status = StreamStatus(isLive: true, videoId: videoId, title: title, startedAt: startedAt)
            case .notLive:
                self.status = .offline
            case .unrecognized:
                break
            }
        } catch {
            // Keep previous status on network error.
        }
    }

    private static let defaultFetcher: Fetcher = { url in
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return String(decoding: data, as: UTF8.self)
    }
}
