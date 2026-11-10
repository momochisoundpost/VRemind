import AppKit
import Foundation
import SwiftUI
import Testing
@testable import CaitlynKit

struct MenuBarStatusTests {
    private let now = Date(timeIntervalSince1970: 2_000_000)

    @Test @MainActor func popoverContentHeightFitsCompactlyForWatchlistSlots() {
        let suiteName = "MenuBarPopoverTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let configService = ConfigSyncService(
            cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        let watchlistService = WatchlistService(
            configService: configService,
            userDefaults: defaults,
            fetcher: { _ in "<html><body>ytInitialData</body></html>" }
        )
        let popover1 = MenuBarStatusView.makePopover(
            configService: configService,
            watchlistService: watchlistService,
            onOpenHub: {},
            onQuit: {}
        )
        let size1 = popover1.contentSize
        #expect(size1.width == 320)
        #expect(size1.height > 150 && size1.height <= 300)

        #expect(watchlistService.addChannel(name: "Kobo", handle: "@kobo") == true)
        let popover2 = MenuBarStatusView.makePopover(
            configService: configService,
            watchlistService: watchlistService,
            onOpenHub: {},
            onQuit: {}
        )
        let size2 = popover2.contentSize
        #expect(size2.height > size1.height)

        #expect(watchlistService.addChannel(name: "Ina", handle: "@ina") == true)
        let popover3 = MenuBarStatusView.makePopover(
            configService: configService,
            watchlistService: watchlistService,
            onOpenHub: {},
            onQuit: {}
        )
        let size3 = popover3.contentSize
        #expect(size3.height > size2.height)
    }

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
