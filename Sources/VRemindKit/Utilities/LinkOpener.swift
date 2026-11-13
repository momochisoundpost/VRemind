import AppKit
import Foundation
import VRemindCore

public enum LinkOpener {
    public struct SharedOpener: Sendable {
        public init() {}

        public func parseStreamDeepLink(_ url: URL) -> URL? {
            LinkOpener.parseStreamDeepLink(url)
        }

        public func open(_ url: URL) {
            LinkOpener.open(url)
        }

        public func videoURL(for youtubeId: String) -> URL {
            LinkOpener.videoURL(for: youtubeId)
        }

        public func channelURL(for platform: StreamPlatform, handle: String) -> URL {
            LinkOpener.channelURL(for: platform, handle: handle)
        }

        public func streamURL(for channel: WatchedChannel, status: StreamStatus) -> URL {
            LinkOpener.streamURL(for: channel, status: status)
        }
    }

    public static let shared = SharedOpener()

    private static let fallbackURL = URL(string: "https://www.youtube.com")!

    public static func videoURL(for youtubeId: String) -> URL {
        let encoded = youtubeId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? youtubeId
        return URL(string: "https://www.youtube.com/watch?v=\(encoded)") ?? fallbackURL
    }

    public static func channelURL(for platform: StreamPlatform, handle: String) -> URL {
        if let url = StreamProviderRegistry.default.channelURL(for: platform, handle: handle) {
            return url
        }
        switch platform {
        case .youtube:
            return URL(string: "https://www.youtube.com")!
        case .twitch:
            return URL(string: "https://www.twitch.tv")!
        }
    }

    public static func streamURL(for channel: WatchedChannel, status: StreamStatus) -> URL {
        if let url = StreamProviderRegistry.default.watchURL(for: channel, status: status) {
            return url
        }
        switch channel.platform {
        case .youtube:
            return URL(string: "https://www.youtube.com")!
        case .twitch:
            return URL(string: "https://www.twitch.tv")!
        }
    }

    /// Parses and validates a deep link with scheme `vremind://open-stream?url=<target>`.
    ///
    /// Validates that the target is a valid HTTP or HTTPS URL to prevent opening arbitrary or unsafe schemes
    /// (e.g. `file://`, `javascript:`, non-http/https, or malformed queries).
    public static func parseStreamDeepLink(_ url: URL) -> URL? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        guard components.scheme?.lowercased() == "vremind",
              components.host?.lowercased() == "open-stream" else {
            return nil
        }

        guard let targetString = components.queryItems?.first(where: { $0.name == "url" })?.value else {
            return nil
        }

        let trimmedTarget = targetString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTarget.isEmpty,
              let targetURL = URL(string: trimmedTarget) else {
            return nil
        }

        guard let scheme = targetURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = targetURL.host,
              !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return targetURL
    }

    public static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
