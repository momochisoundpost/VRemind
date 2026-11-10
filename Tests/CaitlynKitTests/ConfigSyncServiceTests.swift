import Foundation
import Testing
@testable import CaitlynKit

@MainActor
struct ConfigSyncServiceTests {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConfigSyncServiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cacheFile(in dir: URL) -> URL {
        dir.appendingPathComponent("caitlyn_hub.json")
    }

    private func seed(version: Int) -> HubConfig {
        var config = HubConfig.loadBundledSeed()
        config.version = version
        return config
    }

    @Test func loadsSeedWhenNoCache() throws {
        let dir = try makeTempDir()
        let service = ConfigSyncService(cacheDirectory: dir)
        #expect(service.config == HubConfig.loadBundledSeed())
    }

    @Test func prefersValidCache() throws {
        let dir = try makeTempDir()
        try seed(version: 99).encoded().write(to: cacheFile(in: dir))
        let service = ConfigSyncService(cacheDirectory: dir)
        #expect(service.config.version == 99)
    }

    @Test func corruptCacheFallsBackToSeed() throws {
        let dir = try makeTempDir()
        try Data("not json".utf8).write(to: cacheFile(in: dir))
        let service = ConfigSyncService(cacheDirectory: dir)
        #expect(service.config.version == 1)
    }

    @Test func syncFromFileURLUpdatesAndCaches() async throws {
        let dir = try makeTempDir()
        let remote = try makeTempDir().appendingPathComponent("remote.json")
        try seed(version: 7).encoded().write(to: remote)
        let service = ConfigSyncService(cacheDirectory: dir, remoteURL: remote)
        await service.sync()
        #expect(service.config.version == 7)
        let cached = try HubConfig.decode(from: Data(contentsOf: cacheFile(in: dir)))
        #expect(cached.version == 7)
    }

    @Test func syncFailureKeepsConfigAndCache() async throws {
        let dir = try makeTempDir()
        let service = ConfigSyncService(cacheDirectory: dir, remoteURL: URL(string: "http://127.0.0.1:9/none.json")!)
        let before = service.config
        await service.sync()
        #expect(service.config == before)
        #expect(!FileManager.default.fileExists(atPath: cacheFile(in: dir).path))
    }

    @Test func syncInvalidJSONKeepsConfig() async throws {
        let dir = try makeTempDir()
        let remote = try makeTempDir().appendingPathComponent("remote.json")
        try Data(#"{"oops":1}"#.utf8).write(to: remote)
        let service = ConfigSyncService(cacheDirectory: dir, remoteURL: remote)
        let before = service.config
        await service.sync()
        #expect(service.config == before)
    }
}
