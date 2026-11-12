import Foundation

/// Status kind representing the current state of a channel for widget rendering.
public enum StatusKind: String, Codable, Sendable, CaseIterable, Equatable {
    case live
    case upcoming
    case offline
    case unknown
}

/// A lightweight, Codable representation of a single channel item tailored for WidgetKit timeline rendering.
public struct WidgetChannelItem: Codable, Equatable, Sendable, Identifiable {
    public typealias StatusKind = VRemindKit.StatusKind

    public var id: String { handle }
    public let handle: String
    public let displayName: String
    public let avatarFilename: String?
    public let avatarURL: URL?
    public let statusKind: StatusKind
    public let streamTitle: String?
    public let videoId: String?
    public let liveStartedAt: Date?
    public let upcomingStartTime: Date?
    public let lastStreamedAt: Date?

    public init(
        handle: String,
        displayName: String,
        avatarFilename: String? = nil,
        avatarURL: URL? = nil,
        statusKind: StatusKind = .offline,
        streamTitle: String? = nil,
        videoId: String? = nil,
        liveStartedAt: Date? = nil,
        upcomingStartTime: Date? = nil,
        lastStreamedAt: Date? = nil
    ) {
        self.handle = handle
        self.displayName = displayName
        self.avatarFilename = avatarFilename
        self.avatarURL = avatarURL
        self.statusKind = statusKind
        self.streamTitle = streamTitle
        self.videoId = videoId
        self.liveStartedAt = liveStartedAt
        self.upcomingStartTime = upcomingStartTime
        self.lastStreamedAt = lastStreamedAt
    }

    /// Direct YouTube URL for the active/upcoming video if videoId is present.
    public var videoURL: URL? {
        guard let trimmed = videoId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        return URL(string: "https://www.youtube.com/watch?v=\(encoded)")
    }

    /// Direct YouTube channel URL based on handle.
    public var channelURL: URL {
        let trimmed = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return URL(string: "https://www.youtube.com")!
        }
        let formatted = trimmed.hasPrefix("@") ? trimmed : "@\(trimmed)"
        let encoded = formatted.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? formatted
        return URL(string: "https://www.youtube.com/\(encoded)") ?? URL(string: "https://www.youtube.com")!
    }

    /// Custom deep link URL routed via vremind://open-stream?url=<target> to open directly in the user's browser.
    public var deepLinkURL: URL? {
        let target = videoURL?.absoluteString ?? channelURL.absoluteString
        var components = URLComponents()
        components.scheme = "vremind"
        components.host = "open-stream"
        components.queryItems = [URLQueryItem(name: "url", value: target)]
        return components.url
    }
}

/// Lightweight snapshot serialized by the main app and read by the WidgetKit extension.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public let generatedAt: Date
    public let channels: [WidgetChannelItem]

    public init(
        generatedAt: Date = Date(),
        channels: [WidgetChannelItem] = []
    ) {
        self.generatedAt = generatedAt
        self.channels = channels
    }
}
