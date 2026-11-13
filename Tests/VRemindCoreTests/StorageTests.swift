import Foundation
import Testing
@testable import VRemindCore

@Suite struct StorageTests {
    private func makeTempFileURL(name: String = UUID().uuidString) -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VRemindStorageTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        return tempDir.appendingPathComponent("\(name).json")
    }

    @Test func testJSONFileChannelStorageReturnsEmptyWhenFileMissing() throws {
        let fileURL = makeTempFileURL()
        let storage = JSONFileChannelStorage(fileURL: fileURL)
        let channels = try storage.loadChannels()
        #expect(channels.isEmpty)
    }

    @Test func testJSONFileChannelStorageRoundTrip() throws {
        let fileURL = makeTempFileURL()
        let storage = JSONFileChannelStorage(fileURL: fileURL)

        let initial = [
            WatchedChannel(
                id: "youtube:@bukancaitlyn",
                platform: .youtube,
                name: "Caitlyn Momochi",
                handle: "@bukancaitlyn",
                avatarURL: URL(string: "https://example.com/caitlyn.jpg"),
                lastNotifiedVideoId: "v123",
                lastNotifiedUpcomingId: "u456",
                lastStreamedAt: Date(timeIntervalSince1970: 1700000000)
            ),
            WatchedChannel(
                id: "twitch:ironmouse",
                platform: .twitch,
                name: "ironmouse",
                handle: "ironmouse",
                avatarURL: URL(string: "https://example.com/mouse.jpg"),
                lastNotifiedVideoId: nil,
                lastNotifiedUpcomingId: nil,
                lastStreamedAt: nil
            )
        ]

        try storage.saveChannels(initial)
        #expect(FileManager.default.fileExists(atPath: fileURL.path))

        let loaded = try storage.loadChannels()
        #expect(loaded.count == 2)
        #expect(loaded == initial)
    }

    @Test func testJSONFileSettingsStorageReturnsDefaultsWhenFileMissing() throws {
        let fileURL = makeTempFileURL()
        let storage = JSONFileSettingsStorage(fileURL: fileURL)
        let settings = try storage.loadSettings()
        #expect(settings == AppSettings())
    }

    @Test func testJSONFileSettingsStorageRoundTrip() throws {
        let fileURL = makeTempFileURL()
        let storage = JSONFileSettingsStorage(fileURL: fileURL)

        var modified = AppSettings()
        modified.notifyOnLive = false
        modified.notifyOnUpcoming = true
        modified.reduceMotion = true
        modified.lastNotifiedDevBirthdayYear = 2026
        modified.ignoredUpdateTag = "v2.0.0"

        try storage.saveSettings(modified)
        #expect(FileManager.default.fileExists(atPath: fileURL.path))

        let loaded = try storage.loadSettings()
        #expect(loaded == modified)
    }

    @Test func testStorageCreatesIntermediateDirectories() throws {
        let nestedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Deeply", isDirectory: true)
            .appendingPathComponent("Nested", isDirectory: true)
            .appendingPathComponent("Path", isDirectory: true)
            .appendingPathComponent("\(UUID().uuidString).json")

        let channelStorage = JSONFileChannelStorage(fileURL: nestedURL)
        let testChannels = [WatchedChannel(id: "youtube:@test", platform: .youtube, name: "Test", handle: "@test")]
        try channelStorage.saveChannels(testChannels)
        #expect(FileManager.default.fileExists(atPath: nestedURL.path))
        let loaded = try channelStorage.loadChannels()
        #expect(loaded == testChannels)
    }
}
