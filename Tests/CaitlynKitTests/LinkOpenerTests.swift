import Foundation
import Testing
@testable import CaitlynKit

struct LinkOpenerTests {
    @Test func videoURLFormat() {
        #expect(LinkOpener.videoURL(for: "42hstxcifYU").absoluteString
                == "https://www.youtube.com/watch?v=42hstxcifYU")
    }
}
