import Foundation

public struct WatchedChannel: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public var name: String
    public let handle: String
    public var avatarURL: URL?
    public var lastNotifiedVideoId: String?
    public var lastNotifiedUpcomingId: String?
    public var lastStreamedAt: Date?

    public init(
        id: String,
        name: String,
        handle: String,
        avatarURL: URL? = nil,
        lastNotifiedVideoId: String? = nil,
        lastNotifiedUpcomingId: String? = nil,
        lastStreamedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.handle = handle
        self.avatarURL = avatarURL
        self.lastNotifiedVideoId = lastNotifiedVideoId
        self.lastNotifiedUpcomingId = lastNotifiedUpcomingId
        self.lastStreamedAt = lastStreamedAt
    }

    public static func normalizeHandle(_ input: String) -> String? {
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
}
