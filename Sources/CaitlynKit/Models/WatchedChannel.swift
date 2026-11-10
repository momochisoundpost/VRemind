import Foundation

public struct WatchedChannel: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public var name: String
    public var handle: String
    public var avatarURL: URL?
    public var isPinned: Bool

    public static func normalizeHandle(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutAt = trimmed.hasPrefix("@") ? String(trimmed.dropFirst()) : trimmed
        let cleaned = withoutAt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        return "@" + cleaned
    }

    public init(name: String, handle: String, avatarURL: URL? = nil, isPinned: Bool = false) {
        let normalized = Self.normalizeHandle(handle) ?? "@unknown"
        self.id = normalized.lowercased()
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = trimmedName.isEmpty ? normalized : trimmedName
        self.handle = normalized
        self.avatarURL = avatarURL
        self.isPinned = isPinned
    }
}
