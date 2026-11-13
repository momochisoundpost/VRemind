import Foundation

public struct WatchedChannel: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let platform: StreamPlatform
    public var name: String
    public let handle: String
    public var avatarURL: URL?
    public var lastNotifiedVideoId: String?
    public var lastNotifiedUpcomingId: String?
    public var lastStreamedAt: Date?

    public init(
        id: String,
        platform: StreamPlatform = .youtube,
        name: String,
        handle: String,
        avatarURL: URL? = nil,
        lastNotifiedVideoId: String? = nil,
        lastNotifiedUpcomingId: String? = nil,
        lastStreamedAt: Date? = nil
    ) {
        self.id = id
        self.platform = platform
        self.name = name
        self.handle = handle
        self.avatarURL = avatarURL
        self.lastNotifiedVideoId = lastNotifiedVideoId
        self.lastNotifiedUpcomingId = lastNotifiedUpcomingId
        self.lastStreamedAt = lastStreamedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case platform
        case name
        case handle
        case avatarURL
        case lastNotifiedVideoId
        case lastNotifiedUpcomingId
        case lastStreamedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedPlatform = try container.decodeIfPresent(StreamPlatform.self, forKey: .platform)
        let platform = decodedPlatform ?? .youtube
        let decodedId = try container.decode(String.self, forKey: .id)
        let name = try container.decode(String.self, forKey: .name)
        let handle = try container.decode(String.self, forKey: .handle)
        let avatarURL = try container.decodeIfPresent(URL.self, forKey: .avatarURL)
        let lastNotifiedVideoId = try container.decodeIfPresent(String.self, forKey: .lastNotifiedVideoId)
        let lastNotifiedUpcomingId = try container.decodeIfPresent(String.self, forKey: .lastNotifiedUpcomingId)
        let lastStreamedAt = try container.decodeIfPresent(Date.self, forKey: .lastStreamedAt)

        self.platform = platform
        self.name = name
        self.handle = handle
        self.avatarURL = avatarURL
        self.lastNotifiedVideoId = lastNotifiedVideoId
        self.lastNotifiedUpcomingId = lastNotifiedUpcomingId
        self.lastStreamedAt = lastStreamedAt

        if decodedPlatform == nil && !decodedId.hasPrefix("\(platform.rawValue):") {
            self.id = Self.makeID(platform: platform, handle: handle)
        } else {
            self.id = decodedId
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(platform, forKey: .platform)
        try container.encode(name, forKey: .name)
        try container.encode(handle, forKey: .handle)
        try container.encodeIfPresent(avatarURL, forKey: .avatarURL)
        try container.encodeIfPresent(lastNotifiedVideoId, forKey: .lastNotifiedVideoId)
        try container.encodeIfPresent(lastNotifiedUpcomingId, forKey: .lastNotifiedUpcomingId)
        try container.encodeIfPresent(lastStreamedAt, forKey: .lastStreamedAt)
    }

    public static func makeID(platform: StreamPlatform, handle: String) -> String {
        "\(platform.rawValue):\(handle.lowercased())"
    }

    public static func normalizeHandle(_ input: String) -> String? {
        normalizeHandle(input, for: .youtube)
    }

    public static func normalizeHandle(_ input: String, for platform: StreamPlatform) -> String? {
        switch platform {
        case .youtube:
            return normalizeYouTubeHandle(input)
        case .twitch:
            return normalizeTwitchHandle(input)
        }
    }

    public static func detectPlatformAndHandle(from input: String) -> (platform: StreamPlatform, handle: String)? {
        let lower = input.lowercased()
        if lower.contains("twitch.tv") {
            if let handle = normalizeHandle(input, for: .twitch) {
                return (.twitch, handle)
            }
        } else if lower.contains("youtube.com") || lower.contains("youtu.be") {
            if let handle = normalizeHandle(input, for: .youtube) {
                return (.youtube, handle)
            }
        }
        return nil
    }

    // MARK: - Private Helpers

    private static func normalizeYouTubeHandle(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Handles and URLs cannot contain internal whitespace
        if trimmed.contains(where: \.isWhitespace) {
            return nil
        }

        let handleBody: String
        if let atRange = trimmed.range(of: "@") {
            let prefix = trimmed[..<atRange.lowerBound]
            if !prefix.isEmpty {
                let lowerPrefix = prefix.lowercased()
                guard lowerPrefix.hasSuffix("/"),
                      lowerPrefix.contains("youtube.com") || lowerPrefix.contains("youtu.be") || lowerPrefix == "/" else {
                    return nil
                }
                let afterAt = trimmed[atRange.upperBound...]
                let segment = afterAt.prefix { char in
                    char != "/" && char != "?" && char != "#"
                }
                handleBody = String(segment)
            } else {
                handleBody = String(trimmed[atRange.upperBound...])
            }
        } else {
            if trimmed.contains("://") || trimmed.contains("/") || trimmed.lowercased().contains("youtube.com") {
                return nil
            }
            handleBody = trimmed
        }

        guard !handleBody.isEmpty else { return nil }

        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-")
        guard handleBody.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return nil
        }

        return "@\(handleBody)"
    }

    private static let twitchReservedPaths: Set<String> = [
        "directory", "videos", "settings", "subscriptions", "wallet",
        "inventory", "drops", "downloads", "jobs", "p", "u"
    ]

    private static func normalizeTwitchHandle(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Handles and URLs cannot contain internal whitespace
        if trimmed.contains(where: \.isWhitespace) {
            return nil
        }

        var candidate: String

        let isExplicitURL = trimmed.contains("://")
        let lowerTrimmed = trimmed.lowercased()
        let startsWithTwitchHost = lowerTrimmed.hasPrefix("twitch.tv/") ||
            lowerTrimmed.hasPrefix("www.twitch.tv/") ||
            lowerTrimmed.hasPrefix("m.twitch.tv/")

        if isExplicitURL || startsWithTwitchHost {
            let urlString = isExplicitURL ? trimmed : "https://" + trimmed
            guard let url = URL(string: urlString),
                  let host = url.host?.lowercased() else {
                return nil
            }

            let validHosts: Set<String> = ["twitch.tv", "www.twitch.tv", "m.twitch.tv"]
            guard validHosts.contains(host) else {
                return nil
            }

            let segments = url.pathComponents.filter { $0 != "/" }
            guard let firstSegment = segments.first else {
                return nil
            }
            candidate = firstSegment
        } else {
            if trimmed.contains("/") || trimmed.contains("?") || trimmed.contains("#") {
                return nil
            }
            candidate = trimmed
        }

        if candidate.hasPrefix("@") {
            candidate.removeFirst()
        }

        guard !candidate.isEmpty else { return nil }

        let lowerCandidate = candidate.lowercased()
        if twitchReservedPaths.contains(lowerCandidate) {
            return nil
        }

        guard (1...25).contains(candidate.count) else {
            return nil
        }

        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_")
        guard candidate.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return nil
        }

        return lowerCandidate
    }
}
