import Foundation
import SwiftUI
import Testing
@testable import VRemindKit

@Suite("UpdateAvailableViewTests")
struct UpdateAvailableViewTests {
    @Test("UpdateAvailableView renders release notes and triggers actions")
    @MainActor
    func testViewActions() {
        var downloaded = false
        var skipped = false
        var later = false

        let release = GitHubRelease(
            tagName: "v1.0.2",
            name: "v1.0.2 — Bug Fixes",
            body: "### Changes\n- Fixed notifications",
            htmlURL: URL(string: "https://github.com/momochisoundpost/VRemind/releases/tag/v1.0.2")!,
            publishedAt: nil,
            assets: [
                GitHubReleaseAsset(
                    name: "VRemind-1.0.2.zip",
                    browserDownloadURL: URL(string: "https://github.com/momochisoundpost/VRemind/releases/download/v1.0.2/VRemind-1.0.2.zip")!,
                    size: 1024
                )
            ]
        )

        let view = UpdateAvailableView(
            release: release,
            currentVersion: "1.0.1",
            onDownload: { downloaded = true },
            onSkip: { skipped = true },
            onLater: { later = true }
        )

        #expect(view.release.tagName == "v1.0.2")
        view.onDownload()
        #expect(downloaded == true)
        view.onSkip()
        #expect(skipped == true)
        view.onLater()
        #expect(later == true)
    }

    @Test("UpdateAvailableView defaults currentVersion to AppConstants.appVersion")
    @MainActor
    func testDefaultVersion() {
        let release = GitHubRelease(
            tagName: "v1.2.0",
            name: "v1.2.0",
            body: nil,
            htmlURL: URL(string: "https://github.com")!,
            publishedAt: nil,
            assets: []
        )

        let view = UpdateAvailableView(
            release: release,
            onDownload: {},
            onSkip: {},
            onLater: {}
        )

        #expect(view.currentVersion == AppConstants.appVersion)
        #expect(view.release.tagName == "v1.2.0")
    }

    @Test("UpdateAvailableView renders body without crash")
    @MainActor
    func testBodyRendering() {
        let releaseWithBody = GitHubRelease(
            tagName: "v2.0.0",
            name: "Major Release",
            body: "## Headline\n- Feature 1\n- Feature 2",
            htmlURL: URL(string: "https://github.com")!,
            publishedAt: nil,
            assets: []
        )

        let viewWithBody = UpdateAvailableView(
            release: releaseWithBody,
            onDownload: {},
            onSkip: {},
            onLater: {}
        )
        _ = viewWithBody.body

        let releaseWithoutBody = GitHubRelease(
            tagName: "v2.0.1",
            name: nil,
            body: nil,
            htmlURL: URL(string: "https://github.com")!,
            publishedAt: nil,
            assets: []
        )

        let viewWithoutBody = UpdateAvailableView(
            release: releaseWithoutBody,
            onDownload: {},
            onSkip: {},
            onLater: {}
        )
        _ = viewWithoutBody.body
    }
}
