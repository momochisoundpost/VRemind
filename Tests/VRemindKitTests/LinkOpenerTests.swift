import Foundation
import Testing
@testable import VRemindKit

struct LinkOpenerTests {
    @Test func videoURLFormat() {
        #expect(LinkOpener.videoURL(for: "42hstxcifYU").absoluteString
                == "https://www.youtube.com/watch?v=42hstxcifYU")
    }

    @Test func videoURLPercentEncodesUnsanitizedInput() {
        let url = LinkOpener.videoURL(for: "test video id?x=1")
        #expect(url.absoluteString == "https://www.youtube.com/watch?v=test%20video%20id?x=1")
    }
}
