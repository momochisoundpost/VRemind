import Foundation
import VRemindCore

public enum BackupError: Error, LocalizedError, Equatable, Sendable {
    case invalidJSON
    case unsupportedSchemaVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidJSON:
            return "The selected file is not a valid VRemind backup."
        case .unsupportedSchemaVersion(let version):
            return "Backup schema version \(version) is not supported by this version of VRemind."
        }
    }
}

public struct BackupPayload: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let appVersion: String
    public let exportedAt: Date
    public let settings: AppSettings
    public let channels: [WatchedChannel]

    public init(
        schemaVersion: Int = BackupPayload.currentSchemaVersion,
        appVersion: String = AppConstants.appVersion,
        exportedAt: Date = Date(),
        settings: AppSettings,
        channels: [WatchedChannel]
    ) {
        self.schemaVersion = schemaVersion
        self.appVersion = appVersion
        self.exportedAt = exportedAt
        self.settings = settings
        self.channels = channels
    }

    public func encodedJSONData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func decodeAndValidate(from data: Data) throws -> BackupPayload {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let payload: BackupPayload
        do {
            payload = try decoder.decode(BackupPayload.self, from: data)
        } catch {
            throw BackupError.invalidJSON
        }

        guard (1...Self.currentSchemaVersion).contains(payload.schemaVersion) else {
            throw BackupError.unsupportedSchemaVersion(payload.schemaVersion)
        }

        return payload
    }

    public func sanitizedForRestore() -> (settings: AppSettings, channels: [WatchedChannel]) {
        var sanitizedSettings = settings
        sanitizedSettings.hasCompletedOnboarding = true

        let sanitizedChannels = channels.map { channel in
            var copy = channel
            copy.lastNotifiedVideoId = nil
            copy.lastNotifiedUpcomingId = nil
            return copy
        }

        return (settings: sanitizedSettings, channels: sanitizedChannels)
    }

    public static func defaultBackupFilename(for date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return "vremind-backup-\(formatter.string(from: date)).json"
    }
}
