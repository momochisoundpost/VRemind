import Foundation

public protocol ChannelStorage: Sendable {
    func loadChannels() throws -> [WatchedChannel]
    func saveChannels(_ channels: [WatchedChannel]) throws
}

public protocol SettingsStorage: Sendable {
    func loadSettings() throws -> AppSettings
    func saveSettings(_ settings: AppSettings) throws
}

public final class JSONFileChannelStorage: ChannelStorage {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func loadChannels() throws -> [WatchedChannel] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([WatchedChannel].self, from: data)
    }

    public func saveChannels(_ channels: [WatchedChannel]) throws {
        let directory = fileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(channels)
        try data.write(to: fileURL, options: .atomic)
    }
}

public final class JSONFileSettingsStorage: SettingsStorage {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func loadSettings() throws -> AppSettings {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return AppSettings()
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(AppSettings.self, from: data)
    }

    public func saveSettings(_ settings: AppSettings) throws {
        let directory = fileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)
        try data.write(to: fileURL, options: .atomic)
    }
}
