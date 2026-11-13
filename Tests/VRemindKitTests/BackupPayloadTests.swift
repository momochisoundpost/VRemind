import Foundation
import Testing
import VRemindCore
@testable import VRemindKit

struct BackupPayloadTests {
    @Test func testRoundTripEncodingAndDecoding() throws {
        let settings = AppSettings(
            launchAtLogin: true,
            notifyOnLive: false,
            notifyOnUpcoming: true,
            playNotificationSound: false,
            hasCompletedOnboarding: true,
            updateConsent: .allowed,
            reduceMotion: true
        )
        let channels = [
            WatchedChannel(
                id: "UC1234567890",
                platform: .youtube,
                name: "Test YouTube",
                handle: "@testyt",
                avatarURL: URL(string: "https://example.com/yt.png"),
                lastStreamedAt: Date(timeIntervalSince1970: 1700000000)
            ),
            WatchedChannel(
                id: "twitch_987",
                platform: .twitch,
                name: "Test Twitch",
                handle: "testtwitch",
                avatarURL: URL(string: "https://example.com/tw.png")
            )
        ]

        let exportedAt = Date(timeIntervalSince1970: 1700001234)
        let payload = BackupPayload(
            schemaVersion: 1,
            appVersion: "1.3.1",
            exportedAt: exportedAt,
            settings: settings,
            channels: channels
        )

        let data = try payload.encodedJSONData()
        let decoded = try BackupPayload.decodeAndValidate(from: data)

        #expect(decoded.schemaVersion == 1)
        #expect(decoded.appVersion == "1.3.1")
        #expect(decoded.exportedAt == exportedAt)
        #expect(decoded.settings == settings)
        #expect(decoded.channels == channels)
    }

    @Test func testDecodeRejectsCorruptedAndNonBackupJSON() {
        let corruptedData = Data("{".utf8)
        #expect(throws: BackupError.invalidJSON) {
            try BackupPayload.decodeAndValidate(from: corruptedData)
        }

        let emptyArrayData = Data("[]".utf8)
        #expect(throws: BackupError.invalidJSON) {
            try BackupPayload.decodeAndValidate(from: emptyArrayData)
        }

        let unrelatedObjectData = Data(#"{"hello":"world"}"#.utf8)
        #expect(throws: BackupError.invalidJSON) {
            try BackupPayload.decodeAndValidate(from: unrelatedObjectData)
        }
    }

    @Test func testDecodeRejectsUnsupportedSchemaVersion() throws {
        let basePayload = BackupPayload(
            schemaVersion: 1,
            appVersion: "1.3.1",
            exportedAt: Date(timeIntervalSince1970: 1700000000),
            settings: AppSettings(),
            channels: []
        )
        let baseData = try basePayload.encodedJSONData()
        let baseString = String(decoding: baseData, as: UTF8.self)

        let futureData = Data(baseString.replacingOccurrences(of: "\"schemaVersion\" : 1", with: "\"schemaVersion\" : 99").utf8)
        #expect(throws: BackupError.unsupportedSchemaVersion(99)) {
            try BackupPayload.decodeAndValidate(from: futureData)
        }

        let zeroData = Data(baseString.replacingOccurrences(of: "\"schemaVersion\" : 1", with: "\"schemaVersion\" : 0").utf8)
        #expect(throws: BackupError.unsupportedSchemaVersion(0)) {
            try BackupPayload.decodeAndValidate(from: zeroData)
        }
    }

    @Test func testSanitizedForRestoreForcesOnboardingAndClearsNotificationIds() {
        var settings = AppSettings()
        settings.hasCompletedOnboarding = false
        settings.reduceMotion = true

        let lastStreamed = Date(timeIntervalSince1970: 1700000000)
        var channel = WatchedChannel(
            id: "UC_sanitize",
            platform: .youtube,
            name: "Sanitize Channel",
            handle: "@sanitize",
            avatarURL: URL(string: "https://example.com/avatar.png"),
            lastStreamedAt: lastStreamed
        )
        channel.lastNotifiedVideoId = "vid1"
        channel.lastNotifiedUpcomingId = "up1"

        let payload = BackupPayload(settings: settings, channels: [channel])
        let sanitized = payload.sanitizedForRestore()

        #expect(sanitized.settings.hasCompletedOnboarding == true)
        #expect(sanitized.settings.reduceMotion == true)
        #expect(sanitized.channels.count == 1)

        let restoredChannel = sanitized.channels[0]
        #expect(restoredChannel.lastNotifiedVideoId == nil)
        #expect(restoredChannel.lastNotifiedUpcomingId == nil)
        #expect(restoredChannel.lastStreamedAt == lastStreamed)
        #expect(restoredChannel.name == "Sanitize Channel")
        #expect(restoredChannel.handle == "@sanitize")
        #expect(restoredChannel.platform == .youtube)
        #expect(restoredChannel.avatarURL == URL(string: "https://example.com/avatar.png"))
    }

    @Test func testDefaultBackupFilenameFormat() {
        let filename = BackupPayload.defaultBackupFilename(for: Date(timeIntervalSince1970: 1700000000))
        #expect(
            filename.range(of: #"^vremind-backup-\d{4}-\d{2}-\d{2}\.json$"#, options: .regularExpression) != nil,
            "Expected filename '\(filename)' to match vremind-backup-YYYY-MM-DD.json"
        )
    }
}
