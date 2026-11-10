import Foundation

public struct HubConfig: Codable, Equatable, Sendable {
    public var version: Int
    public var channelHandle: String
    public var avatarURL: URL?
    public var lore: [LoreEntry]
    public var replays: [ReplayVOD]
    public var clips: [CuratedClip]

    enum CodingKeys: String, CodingKey {
        case version
        case channelHandle
        case avatarURL = "avatarUrl"
        case lore
        case replays
        case clips
    }

    public init(
        version: Int,
        channelHandle: String,
        avatarURL: URL? = nil,
        lore: [LoreEntry],
        replays: [ReplayVOD],
        clips: [CuratedClip]
    ) {
        self.version = version
        self.channelHandle = channelHandle
        self.avatarURL = avatarURL
        self.lore = lore
        self.replays = replays
        self.clips = clips
    }

    public static func decode(from data: Data) throws -> HubConfig {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: string) {
                return date
            }
            let standard = ISO8601DateFormatter()
            standard.formatOptions = [.withInternetDateTime]
            if let date = standard.date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date: \(string)")
        }
        return try decoder.decode(HubConfig.self, from: data)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public var latestReplayDate: Date? {
        replays.map(\.date).max()
    }

    /// Prefers the resource bundle inside a packaged `.app` (Contents/Resources),
    /// falling back to SwiftPM's `Bundle.module` for `swift run` / tests.
    public static func bundledSeedURL() -> URL? {
        if let appResources = Bundle.main.resourceURL {
            let url = appResources
                .appendingPathComponent("CaitlynSwift_CaitlynKit.bundle")
                .appendingPathComponent("caitlyn_hub.json")
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return Bundle.module.url(forResource: "caitlyn_hub", withExtension: "json")
    }

    public static func loadBundledSeed() -> HubConfig {
        guard let url = bundledSeedURL() else {
            fatalError("caitlyn_hub.json is missing from the CaitlynKit resource bundle (packaging bug)")
        }
        do {
            return try decode(from: Data(contentsOf: url))
        } catch {
            fatalError("Bundled caitlyn_hub.json at \(url.path) failed to decode: \(error)")
        }
    }
}
