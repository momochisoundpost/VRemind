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

    public var id: String {
        "\(platform.rawValue):\(handle.lowercased())"
    }
    public let platform: StreamPlatform
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
        platform: StreamPlatform = .youtube,
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
        self.platform = platform
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

    private enum CodingKeys: String, CodingKey {
        case platform
        case handle
        case displayName
        case avatarFilename
        case avatarURL
        case statusKind
        case streamTitle
        case videoId
        case liveStartedAt
        case upcomingStartTime
        case lastStreamedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.platform = try container.decodeIfPresent(StreamPlatform.self, forKey: .platform) ?? .youtube
        self.handle = try container.decode(String.self, forKey: .handle)
        self.displayName = try container.decode(String.self, forKey: .displayName)
        self.avatarFilename = try container.decodeIfPresent(String.self, forKey: .avatarFilename)
        self.avatarURL = try container.decodeIfPresent(URL.self, forKey: .avatarURL)
        self.statusKind = try container.decodeIfPresent(StatusKind.self, forKey: .statusKind) ?? .offline
        self.streamTitle = try container.decodeIfPresent(String.self, forKey: .streamTitle)
        self.videoId = try container.decodeIfPresent(String.self, forKey: .videoId)
        self.liveStartedAt = try container.decodeIfPresent(Date.self, forKey: .liveStartedAt)
        self.upcomingStartTime = try container.decodeIfPresent(Date.self, forKey: .upcomingStartTime)
        self.lastStreamedAt = try container.decodeIfPresent(Date.self, forKey: .lastStreamedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(platform, forKey: .platform)
        try container.encode(handle, forKey: .handle)
        try container.encode(displayName, forKey: .displayName)
        try container.encodeIfPresent(avatarFilename, forKey: .avatarFilename)
        try container.encodeIfPresent(avatarURL, forKey: .avatarURL)
        try container.encode(statusKind, forKey: .statusKind)
        try container.encodeIfPresent(streamTitle, forKey: .streamTitle)
        try container.encodeIfPresent(videoId, forKey: .videoId)
        try container.encodeIfPresent(liveStartedAt, forKey: .liveStartedAt)
        try container.encodeIfPresent(upcomingStartTime, forKey: .upcomingStartTime)
        try container.encodeIfPresent(lastStreamedAt, forKey: .lastStreamedAt)
    }

    /// Direct URL for the active/upcoming video if videoId is present.
    /// Preserved for YouTube; returns nil for Twitch (Twitch streams are watched at channelURL).
    public var videoURL: URL? {
        guard platform == .youtube else { return nil }
        guard let trimmed = videoId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        return URL(string: "https://www.youtube.com/watch?v=\(encoded)")
    }

    /// Direct channel URL based on handle and platform.
    public var channelURL: URL {
        if let providerURL = StreamProviderRegistry.default.channelURL(for: platform, handle: handle) {
            return providerURL
        }
        switch platform {
        case .youtube:
            return URL(string: "https://www.youtube.com")!
        case .twitch:
            return URL(string: "https://www.twitch.tv")!
        }
    }

    /// URL to watch the active or scheduled stream.
    /// Resolves to videoURL for YouTube when videoId is present, falling back to channelURL.
    /// Resolves to channelURL for Twitch.
    public var streamURL: URL {
        switch platform {
        case .youtube:
            return videoURL ?? channelURL
        case .twitch:
            return channelURL
        }
    }

    /// Custom deep link URL routed via vremind://open-stream?url=<target> to open directly in the user's browser.
    public var deepLinkURL: URL? {
        let target = streamURL.absoluteString
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
