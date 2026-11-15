import Foundation
import Testing
@testable import VRemindKit

@Suite("AppConstantsTests")
struct AppConstantsTests {
    @Test("AppConstants holds version 1.3.3 and required URLs")
    func testAppConstants() {
        #expect(AppConstants.appVersion == "1.3.3")
        #expect(AppConstants.releaseNotes == "The \"Genuine eBay Battery (Service Recommended)\" Update")
        #expect(AppConstants.policeSirenURL.absoluteString == "https://www.youtube.com/watch?v=HKieGUH9pzg")
        #expect(AppConstants.githubReleasesLatestURL.absoluteString == "https://api.github.com/repos/momochisoundpost/VRemind/releases/latest")
    }
}
