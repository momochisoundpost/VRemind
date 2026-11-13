import Foundation
import Testing
@testable import VRemindKit

@Suite("SemanticVersionTests")
struct SemanticVersionTests {
    @Test("Parses standard semver strings with and without v prefix")
    func testParsing() {
        let v1 = SemanticVersion("1.0.1")
        #expect(v1.major == 1 && v1.minor == 0 && v1.patch == 1)

        let vBeta = SemanticVersion("1.1-beta")
        #expect(vBeta.major == 1 && vBeta.minor == 1 && vBeta.patch == 0)

        let v11 = SemanticVersion("1.1")
        #expect(v11.major == 1 && v11.minor == 1 && v11.patch == 0)

        let v2 = SemanticVersion("v1.2.3")
        #expect(v2.major == 1 && v2.minor == 2 && v2.patch == 3)

        let fallback = SemanticVersion("invalid-tag")
        #expect(fallback.major == 0 && fallback.minor == 0 && fallback.patch == 0)
    }

    @Test("Comparison correctly orders newer, older, and equal versions")
    func testComparison() {
        let current = SemanticVersion("1.0.1")
        let newer = SemanticVersion("v1.0.2")
        let older = SemanticVersion("v1.0.0")
        let equal = SemanticVersion("1.0.1")

        #expect(newer > current)
        #expect(older < current)
        #expect(current == equal)
        #expect(newer.isNewerThan(current))
        #expect(!older.isNewerThan(current))
    }

    @Test("AppConstants holds version 1.2.1 and required URLs")
    func testAppConstants() {
        #expect(AppConstants.appVersion == "1.2.1")
        #expect(AppConstants.releaseNotes == "WIDGETS YES WIDGETS")
        #expect(AppConstants.policeSirenURL.absoluteString == "https://www.youtube.com/watch?v=HKieGUH9pzg")
        #expect(AppConstants.githubReleasesLatestURL.absoluteString == "https://api.github.com/repos/momochisoundpost/VRemind/releases/latest")
    }
}
