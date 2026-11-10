import Foundation
import Testing
@testable import CaitlynKit

struct MenuBarStatusTests {
    private let now = Date(timeIntervalSince1970: 2_000_000)

    @Test func liveWithStartTimeShowsElapsed() {
        let start = now.addingTimeInterval(-(1 * 3600 + 42 * 60))
        let status = StreamStatus(isLive: true, videoId: "abc", title: "Live", startedAt: start)
        #expect(MenuBarStatusView.statusLine(status: status, lastStreamAt: nil, now: now)
                == "Live for 1h 42m")
    }

    @Test func liveWithoutStartTimeShowsLiveNow() {
        let status = StreamStatus(isLive: true, videoId: "abc", title: "Live", startedAt: nil)
        #expect(MenuBarStatusView.statusLine(status: status, lastStreamAt: nil, now: now)
                == "Live now")
    }

    @Test func offlineWithLastStreamShowsAgo() {
        let last = now.addingTimeInterval(-(4 * 86400 + 2 * 3600))
        #expect(MenuBarStatusView.statusLine(status: .offline, lastStreamAt: last, now: now)
                == "Last stream 4d 2h ago")
    }

    @Test func offlineWithoutLastStreamShowsOffline() {
        #expect(MenuBarStatusView.statusLine(status: .offline, lastStreamAt: nil, now: now)
                == "Offline")
    }
}
