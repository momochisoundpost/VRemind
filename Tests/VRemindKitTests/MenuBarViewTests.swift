import AppKit
import Foundation
import SwiftUI
import Testing
@testable import VRemindKit

struct MenuBarViewTests {
    @Test func testMenuBarPopoverSectionSorting() {
        let liveStatus = StreamStatus.live(videoId: "1", title: "Live", startedAt: Date())
        let offlineStatus = StreamStatus.offline(lastStreamedAt: nil)
        let upcomingStatus = StreamStatus.upcoming(videoId: "2", title: "Later", scheduledStartTime: Date())

        let ch1 = WatchedChannel(id: "@a", name: "A", handle: "@a")
        let ch2 = WatchedChannel(id: "@b", name: "B", handle: "@b")
        let ch3 = WatchedChannel(id: "@c", name: "C", handle: "@c")

        let sections = MenuBarStatusViewModel.splitSections(
            channels: [ch1, ch2, ch3],
            statuses: ["@a": liveStatus, "@b": offlineStatus, "@c": upcomingStatus]
        )

        XCTAssertEqual(sections.live.count, 1)
        XCTAssertEqual(sections.upcoming.count, 1)
        XCTAssertEqual(sections.offline.count, 1)
    }

    @Test @MainActor func testAddChannelValidationAndDuplicate() async {
        let channelStore = ChannelStore(userDefaults: makeTestDefaults())
        let prefs = PreferencesStore(userDefaults: makeTestDefaults())
        let notifier = NotificationService(center: NoOpNotificationCenter())
        let monitor = StreamMonitorService(
            channelStore: channelStore,
            preferencesStore: prefs,
            notificationService: notifier,
            fetcher: { _ in (Data(), HTTPURLResponse()) }
        )
        let viewModel = MenuBarStatusViewModel(channelStore: channelStore, monitorService: monitor)

        // Invalid input
        viewModel.newHandleInput = "invalid handle with space"
        let failed = viewModel.addChannel()
        #expect(!failed)
        #expect(viewModel.validationError != nil)

        // Valid input
        viewModel.newHandleInput = "  @hololive_new  "
        let succeeded = viewModel.addChannel()
        #expect(succeeded)
        #expect(viewModel.validationError == nil)
        #expect(viewModel.newHandleInput.isEmpty)
        #expect(channelStore.channels.contains { $0.id == "@hololive_new" })

        // Duplicate input
        viewModel.newHandleInput = "@hololive_new"
        let duplicateFailed = viewModel.addChannel()
        #expect(!duplicateFailed)
        #expect(viewModel.validationError != nil)
    }

    @Test @MainActor func testRemoveChannel() async {
        let channelStore = ChannelStore(userDefaults: makeTestDefaults())
        let prefs = PreferencesStore(userDefaults: makeTestDefaults())
        let notifier = NotificationService(center: NoOpNotificationCenter())
        let monitor = StreamMonitorService(
            channelStore: channelStore,
            preferencesStore: prefs,
            notificationService: notifier,
            fetcher: { _ in (Data(), HTTPURLResponse()) }
        )
        let viewModel = MenuBarStatusViewModel(channelStore: channelStore, monitorService: monitor)

        viewModel.newHandleInput = "@to_remove"
        _ = viewModel.addChannel()
        #expect(channelStore.channels.contains { $0.id == "@to_remove" })

        viewModel.removeChannel(id: "@to_remove")
        #expect(!channelStore.channels.contains { $0.id == "@to_remove" })
    }

    @Test @MainActor func testConfigureStatusButton() {
        let button = NSStatusBarButton()
        MenuBarStatusView.configureStatusButton(button, isLive: false)
        #expect(button.image != nil)
        #expect(button.contentTintColor == nil)

        MenuBarStatusView.configureStatusButton(button, isLive: true, flashPhase: false)
        #expect(button.image != nil)
        #expect(button.contentTintColor != nil)

        MenuBarStatusView.configureStatusButton(button, isLive: true, flashPhase: true)
        #expect(button.image != nil)
        #expect(button.contentTintColor == .systemRed)
    }

    @Test @MainActor func testMakePopover() {
        let channelStore = ChannelStore(userDefaults: makeTestDefaults())
        let prefs = PreferencesStore(userDefaults: makeTestDefaults())
        let notifier = NotificationService(center: NoOpNotificationCenter())
        let monitor = StreamMonitorService(
            channelStore: channelStore,
            preferencesStore: prefs,
            notificationService: notifier,
            fetcher: { _ in (Data(), HTTPURLResponse()) }
        )

        var didOpenPrefs = false
        var didQuit = false
        let popover = MenuBarStatusView.makePopover(
            channelStore: channelStore,
            monitorService: monitor,
            onOpenPreferences: { didOpenPrefs = true },
            onQuit: { didQuit = true }
        )

        #expect(popover.contentViewController != nil)
        #expect(popover.behavior == .transient)
        #expect(!didOpenPrefs)
        #expect(!didQuit)
    }

    @Test @MainActor func testViewsRenderWithoutCrash() {
        let channelStore = ChannelStore(userDefaults: makeTestDefaults())
        let prefs = PreferencesStore(userDefaults: makeTestDefaults())
        let notifier = NotificationService(center: NoOpNotificationCenter())
        let monitor = StreamMonitorService(
            channelStore: channelStore,
            preferencesStore: prefs,
            notificationService: notifier,
            fetcher: { _ in (Data(), HTTPURLResponse()) }
        )
        let viewModel = MenuBarStatusViewModel(channelStore: channelStore, monitorService: monitor)

        let statusView = MenuBarStatusView(viewModel: viewModel)
        _ = statusView.body

        let addBarView = AddChannelBarView(viewModel: viewModel)
        _ = addBarView.body

        let liveChannel = WatchedChannel(id: "@live", name: "Live One", handle: "@live")
        let liveRow = ChannelRowView(
            channel: liveChannel,
            status: .live(videoId: "vid123", title: "Stream Live", startedAt: Date()),
            onDelete: {}
        )
        #expect(liveRow.isLive == true)
        #expect(liveRow.streamURL == URL(string: "https://www.youtube.com/watch?v=vid123")!)
        _ = liveRow.body

        let upcomingRow = ChannelRowView(
            channel: liveChannel,
            status: .upcoming(videoId: "up456", title: "Stream Soon", scheduledStartTime: Date()),
            onDelete: {}
        )
        #expect(upcomingRow.isLive == false)
        #expect(upcomingRow.streamURL == URL(string: "https://www.youtube.com/watch?v=up456")!)
        _ = upcomingRow.body

        let offlineRow = ChannelRowView(
            channel: liveChannel,
            status: .offline(lastStreamedAt: Date().addingTimeInterval(-3600)),
            onDelete: {}
        )
        #expect(offlineRow.isLive == false)
        #expect(offlineRow.streamURL == URL(string: "https://www.youtube.com/@live/live")!)
        _ = offlineRow.body
    }

    @Test func testElapsedTimeLiveDurationAndRelative() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let past = now.addingTimeInterval(-125 * 60) // 2h 05m ago

        #expect(ElapsedTime.liveDuration(since: past, now: now) == "2h 05m")
        #expect(ElapsedTime.liveDuration(since: nil, now: now) == "Live")

        #expect(ElapsedTime.relative(from: past, now: now) == "2h 05m ago")
        #expect(ElapsedTime.relative(from: nil, now: now) == "Offline")
    }
}
