import Foundation
import Testing
@testable import VRemindKit

@Suite("AppConstantsTests")
struct AppConstantsTests {
    @Test("AppConstants holds version 1.3.1 and required URLs")
    func testAppConstants() {
        #expect(AppConstants.appVersion == "1.3.1")
        #expect(AppConstants.releaseNotes == "The \"Yo Dawg, We Updated the Updater Again\" Update")
        #expect(AppConstants.policeSirenURL.absoluteString == "https://www.youtube.com/watch?v=HKieGUH9pzg")
        #expect(AppConstants.githubReleasesLatestURL.absoluteString == "https://api.github.com/repos/momochisoundpost/VRemind/releases/latest")
    }
}
