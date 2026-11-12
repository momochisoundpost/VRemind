import Foundation
import Testing
@testable import VRemindKit

@Suite("UpdateServiceTests")
@MainActor
struct UpdateServiceTests {
    @Test("Decodes GitHubRelease JSON correctly")
    func testDecodeRelease() throws {
        let json = """
        {
          "tag_name": "v1.0.2",
          "name": "v1.0.2 — Performance Fixes",
          "body": "Fixed memory usage",
          "html_url": "https://github.com/momochisoundpost/VRemind/releases/tag/v1.0.2",
          "assets": [
            {
              "name": "VRemind-1.0.2.zip",
              "browser_download_url": "https://github.com/momochisoundpost/VRemind/releases/download/v1.0.2/VRemind-1.0.2.zip",
              "size": 10485760
            }
          ]
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let release = try decoder.decode(GitHubRelease.self, from: json)
        #expect(release.tagName == "v1.0.2")
        #expect(release.name == "v1.0.2 — Performance Fixes")
        #expect(release.assets.first?.name == "VRemind-1.0.2.zip")
    }

    @Test("checkForUpdates detects newer version when remote is greater")
    func testNewerVersionDetected() async {
        let prefs = PreferencesStore(userDefaults: UserDefaults(suiteName: "test.update.newer.\(UUID().uuidString)")!)
        prefs.settings.updateConsent = .allowed

        let service = UpdateService(
            preferencesStore: prefs,
            currentVersion: "1.0.1",
            fetchRelease: {
                GitHubRelease(
                    tagName: "v1.0.2",
                    name: "v1.0.2",
                    body: "Release notes",
                    htmlURL: URL(string: "https://github.com")!,
                    publishedAt: nil,
                    assets: []
                )
            }
        )

        let result = await service.checkForUpdates(manual: false)
        if case .updateAvailable(let rel) = result {
            #expect(rel.tagName == "v1.0.2")
        } else {
            Issue.record("Expected updateAvailable, got \(result)")
        }
    }

    @Test("checkForUpdates detects local version newer than remote (Easter egg)")
    func testLocalVersionNewerEasterEgg() async {
        let prefs = PreferencesStore(userDefaults: UserDefaults(suiteName: "test.update.easter.\(UUID().uuidString)")!)
        let service = UpdateService(
            preferencesStore: prefs,
            currentVersion: "1.0.1",
            fetchRelease: {
                GitHubRelease(
                    tagName: "v1.0.0",
                    name: "v1.0.0",
                    body: "Old release",
                    htmlURL: URL(string: "https://github.com")!,
                    publishedAt: nil,
                    assets: []
                )
            }
        )

        let result = await service.checkForUpdates(manual: true)
        #expect(result == .localVersionNewer(remoteVersion: "v1.0.0"))
    }

    @Test("checkForUpdates skips check when not consented and not manual")
    func testSilentCheckSkippedWhenNotConsented() async {
        let prefs = PreferencesStore(userDefaults: UserDefaults(suiteName: "test.update.skip.\(UUID().uuidString)")!)
        prefs.settings.updateConsent = .neverAsk

        let service = UpdateService(
            preferencesStore: prefs,
            currentVersion: "1.0.1",
            fetchRelease: { fatalError("Should not be called") }
        )

        let result = await service.checkForUpdates(manual: false)
        #expect(result == .skippedNotConsented)
    }

    @Test("checkForUpdates respects ignoredUpdateTag on automatic checks")
    func testIgnoredTagSkippedOnAutomaticCheck() async {
        let prefs = PreferencesStore(userDefaults: UserDefaults(suiteName: "test.update.ignored.\(UUID().uuidString)")!)
        prefs.settings.updateConsent = .allowed
        prefs.settings.ignoredUpdateTag = "v1.0.2"

        let service = UpdateService(
            preferencesStore: prefs,
            currentVersion: "1.0.1",
            fetchRelease: {
                GitHubRelease(
                    tagName: "v1.0.2",
                    name: "v1.0.2",
                    body: nil,
                    htmlURL: URL(string: "https://github.com")!,
                    publishedAt: nil,
                    assets: []
                )
            }
        )

        let result = await service.checkForUpdates(manual: false)
        #expect(result == .skippedIgnored(version: "v1.0.2"))
    }

    @Test("checkForUpdates detects up to date when versions match")
    func testUpToDateWhenVersionsMatch() async {
        let prefs = PreferencesStore(userDefaults: UserDefaults(suiteName: "test.update.uptodate.\(UUID().uuidString)")!)
        prefs.settings.updateConsent = .allowed

        let service = UpdateService(
            preferencesStore: prefs,
            currentVersion: "1.0.1",
            fetchRelease: {
                GitHubRelease(
                    tagName: "v1.0.1",
                    name: "v1.0.1",
                    body: nil,
                    htmlURL: URL(string: "https://github.com")!,
                    publishedAt: nil,
                    assets: []
                )
            }
        )

        let result = await service.checkForUpdates(manual: false)
        #expect(result == .upToDate(latestVersion: "v1.0.1"))
    }

    @Test("checkForUpdates manual check bypasses ignored tag")
    func testManualCheckBypassesIgnoredTag() async {
        let prefs = PreferencesStore(userDefaults: UserDefaults(suiteName: "test.update.manual.ignored.\(UUID().uuidString)")!)
        prefs.settings.updateConsent = .allowed
        prefs.settings.ignoredUpdateTag = "v1.0.2"

        let service = UpdateService(
            preferencesStore: prefs,
            currentVersion: "1.0.1",
            fetchRelease: {
                GitHubRelease(
                    tagName: "v1.0.2",
                    name: "v1.0.2",
                    body: nil,
                    htmlURL: URL(string: "https://github.com")!,
                    publishedAt: nil,
                    assets: []
                )
            }
        )

        let result = await service.checkForUpdates(manual: true)
        if case .updateAvailable(let rel) = result {
            #expect(rel.tagName == "v1.0.2")
        } else {
            Issue.record("Expected updateAvailable, got \(result)")
        }
    }

    @Test("checkForUpdates manual check bypasses consent requirement")
    func testManualCheckBypassesConsent() async {
        let prefs = PreferencesStore(userDefaults: UserDefaults(suiteName: "test.update.manual.consent.\(UUID().uuidString)")!)
        prefs.settings.updateConsent = .neverAsk

        let service = UpdateService(
            preferencesStore: prefs,
            currentVersion: "1.0.1",
            fetchRelease: {
                GitHubRelease(
                    tagName: "v1.0.2",
                    name: "v1.0.2",
                    body: nil,
                    htmlURL: URL(string: "https://github.com")!,
                    publishedAt: nil,
                    assets: []
                )
            }
        )

        let result = await service.checkForUpdates(manual: true)
        if case .updateAvailable(let rel) = result {
            #expect(rel.tagName == "v1.0.2")
        } else {
            Issue.record("Expected updateAvailable, got \(result)")
        }
    }

    @Test("checkForUpdates returns failed when fetch throws error")
    func testNetworkErrorReturnsFailed() async {
        struct MockError: LocalizedError {
            var errorDescription: String? { "Connection timed out" }
        }

        let prefs = PreferencesStore(userDefaults: UserDefaults(suiteName: "test.update.error.\(UUID().uuidString)")!)
        prefs.settings.updateConsent = .allowed

        let service = UpdateService(
            preferencesStore: prefs,
            currentVersion: "1.0.1",
            fetchRelease: {
                throw MockError()
            }
        )

        let result = await service.checkForUpdates(manual: false)
        #expect(result == .failed("Connection timed out"))
    }

    @Test("checkForUpdates updates lastUpdateCheckDate on check")
    func testLastUpdateCheckDateUpdatedOnCheck() async {
        let prefs = PreferencesStore(userDefaults: UserDefaults(suiteName: "test.update.date.\(UUID().uuidString)")!)
        prefs.settings.updateConsent = .allowed
        #expect(prefs.settings.lastUpdateCheckDate == nil)

        let service = UpdateService(
            preferencesStore: prefs,
            currentVersion: "1.0.1",
            fetchRelease: {
                GitHubRelease(
                    tagName: "v1.0.1",
                    name: "v1.0.1",
                    body: nil,
                    htmlURL: URL(string: "https://github.com")!,
                    publishedAt: nil,
                    assets: []
                )
            }
        )

        _ = await service.checkForUpdates(manual: false)
        #expect(prefs.settings.lastUpdateCheckDate != nil)
    }

    @Test("GitHubRelease round-trips through JSONEncoder and JSONDecoder")
    func testGitHubReleaseRoundtrip() throws {
        let asset = GitHubReleaseAsset(
            name: "VRemind-1.0.2.zip",
            browserDownloadURL: URL(string: "https://github.com/momochisoundpost/VRemind/releases/download/v1.0.2/VRemind-1.0.2.zip")!,
            size: 10485760
        )
        let release = GitHubRelease(
            tagName: "v1.0.2",
            name: "Release 1.0.2",
            body: "Notes",
            htmlURL: URL(string: "https://github.com/momochisoundpost/VRemind/releases/tag/v1.0.2")!,
            publishedAt: Date(timeIntervalSince1970: 1700000000),
            assets: [asset]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(release)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(GitHubRelease.self, from: data)

        #expect(decoded.tagName == release.tagName)
        #expect(decoded.name == release.name)
        #expect(decoded.body == release.body)
        #expect(decoded.htmlURL == release.htmlURL)
        #expect(decoded.assets == release.assets)
    }
}
