import Foundation
import Testing
@testable import CaitlynKit

struct WatchlistCardTests {
    private let now = Date(timeIntervalSince1970: 2_000_000)

    @Test func statusLineFormatsLiveAndOfflineStates() {
        let start = now.addingTimeInterval(-(2 * 3600 + 15 * 60))
        let liveStatus = StreamStatus(isLive: true, videoId: "v1", title: "Live", startedAt: start)
        #expect(WatchlistChannelCard.statusLine(status: liveStatus, lastStreamAt: nil, now: now) == "Live for 2h 15m")

        let lastStream = now.addingTimeInterval(-(3 * 86400 + 5 * 3600))
        #expect(WatchlistChannelCard.statusLine(status: .offline, lastStreamAt: lastStream, now: now) == "Last stream 3d 5h ago")
        #expect(WatchlistChannelCard.statusLine(status: .offline, lastStreamAt: nil, now: now) == "Offline")
    }

    @Test func addCardLabelShowsSlotFraction() {
        #expect(AddChannelCard.buttonLabel(currentCount: 1) == "+ Add VTuber (1/3)")
        #expect(AddChannelCard.buttonLabel(currentCount: 2) == "+ Add VTuber (2/3)")
    }
}
