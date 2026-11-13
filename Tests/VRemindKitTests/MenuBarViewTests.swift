import AppKit
import Combine
import Foundation
import SwiftUI
import Testing
import UserNotifications
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

    @Test @MainActor func testViewModelForwardsStoreAndMonitorChanges() async {
        let channelStore = ChannelStore(userDefaults: makeTestDefaults())
        _ = channelStore.addChannel(handle: "@test_channel", name: "Test Channel", avatarURL: nil)

        let prefs = PreferencesStore(userDefaults: makeTestDefaults())
        let notifier = NotificationService(center: NoOpNotificationCenter())
        let monitor = StreamMonitorService(
            channelStore: channelStore,
            preferencesStore: prefs,
            notificationService: notifier,
            fetcher: { _ in (Data(), HTTPURLResponse()) }
        )
        let viewModel = MenuBarStatusViewModel(channelStore: channelStore, monitorService: monitor)

        var emittedCount = 0
        var cancellables = Set<AnyCancellable>()
        viewModel.objectWillChange
            .sink { _ in
                emittedCount += 1
            }
            .store(in: &cancellables)

        // 1. Channel store change (removeChannel) triggers viewModel.objectWillChange
        channelStore.removeChannel(id: "@test_channel")
        #expect(emittedCount >= 1)

        let countAfterStoreChange = emittedCount

        // 2. Monitor service change (refreshAll) triggers viewModel.objectWillChange
        await monitor.refreshAll()
        #expect(emittedCount > countAfterStoreChange)
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

    private static let rawSecretBytes: [UInt8] = [55, 59, 46, 41, 47, 51, 48, 47, 54, 51, 59, 52, 57, 50]
    private static var secretTargetHandle: String {
        "@" + String(decoding: rawSecretBytes.map { $0 ^ 0x5a }, as: UTF8.self)
    }

    @Test func testSecretChannelBottomPriorityDemotion() {
        let targetHandle = Self.secretTargetHandle
        let chTarget = WatchedChannel(id: targetHandle, name: "Target", handle: targetHandle)
        let ch1 = WatchedChannel(id: "@alpha", name: "Alpha", handle: "@alpha")
        let ch2 = WatchedChannel(id: "@beta", name: "Beta", handle: "@beta")

        // 1. Live section demotion
        let liveStatus = StreamStatus.live(videoId: "v", title: "T", startedAt: Date())
        let sectionsLive = MenuBarStatusViewModel.splitSections(
            channels: [chTarget, ch1, ch2],
            statuses: [targetHandle: liveStatus, "@alpha": liveStatus, "@beta": liveStatus]
        )
        #expect(sectionsLive.live.map(\.id) == ["@alpha", "@beta", targetHandle])

        // 2. Upcoming section demotion
        let upStatus = StreamStatus.upcoming(videoId: "v2", title: "T2", scheduledStartTime: Date())
        let sectionsUp = MenuBarStatusViewModel.splitSections(
            channels: [chTarget, ch1, ch2],
            statuses: [targetHandle: upStatus, "@alpha": upStatus, "@beta": upStatus]
        )
        #expect(sectionsUp.upcoming.map(\.id) == ["@alpha", "@beta", targetHandle])

        // 3. Offline section demotion
        let offStatus = StreamStatus.offline(lastStreamedAt: nil)
        let sectionsOff = MenuBarStatusViewModel.splitSections(
            channels: [chTarget, ch1, ch2],
            statuses: [targetHandle: offStatus, "@alpha": offStatus, "@beta": offStatus]
        )
        #expect(sectionsOff.offline.map(\.id) == ["@alpha", "@beta", targetHandle])
    }

    @Test @MainActor func testAddSecretChannelAlertActions() async {
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

        var presentedTitle: String? = nil
        var currentAction: SecretAlertAction = .abort

        viewModel.secretAlertPresenter = { title, message, abort, cancel, ignore in
            presentedTitle = title
            return currentAction
        }

        let targetInput = Self.secretTargetHandle

        // 1. Abort action -> not added
        viewModel.newHandleInput = targetInput
        currentAction = .abort
        let abortResult = viewModel.addChannel()
        #expect(!abortResult)
        #expect(presentedTitle != nil)
        #expect(viewModel.validationError == nil)
        #expect(!channelStore.channels.contains { $0.id == targetInput.lowercased() })

        // 2. Cancel action -> not added
        presentedTitle = nil
        viewModel.newHandleInput = targetInput
        currentAction = .cancel
        let cancelResult = viewModel.addChannel()
        #expect(!cancelResult)
        #expect(presentedTitle != nil)
        #expect(viewModel.validationError == nil)
        #expect(!channelStore.channels.contains { $0.id == targetInput.lowercased() })

        // 3. Ignore action -> added!
        presentedTitle = nil
        viewModel.newHandleInput = targetInput
        currentAction = .ignore
        let ignoreResult = viewModel.addChannel()
        #expect(ignoreResult)
        #expect(presentedTitle != nil)
        #expect(channelStore.channels.contains { $0.id == targetInput.lowercased() })
    }

    @Test func testChannelRowFormattedHandleAndTooltip() {
        let channelWithAt = WatchedChannel(id: "@saya", name: "Saya", handle: "@sayaayaaulya")
        let row1 = ChannelRowView(channel: channelWithAt, status: .offline(lastStreamedAt: nil), onDelete: {})
        #expect(row1.formattedHandle == "@sayaayaaulya")

        let channelWithoutAt = WatchedChannel(id: "plain", name: "Plain", handle: "plaintuber")
        let row2 = ChannelRowView(channel: channelWithoutAt, status: .offline(lastStreamedAt: nil), onDelete: {})
        #expect(row2.formattedHandle == "@plaintuber")
    }

    @Test @MainActor func testAddingCaitlynOnDec31TriggersDeveloperBirthdayNotification() async throws {
        let channelStore = ChannelStore(userDefaults: makeTestDefaults())
        channelStore.removeChannel(id: "@bukancaitlyn")
        #expect(!channelStore.channels.contains { $0.id == "@bukancaitlyn" })

        let prefs = PreferencesStore(userDefaults: makeTestDefaults())
        let mockCenter = MockNotificationCenter()
        let notifier = NotificationService(center: mockCenter)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 12
        comps.day = 31
        comps.hour = 12
        let dec31_2026 = calendar.date(from: comps)!

        let monitor = StreamMonitorService(
            channelStore: channelStore,
            preferencesStore: prefs,
            notificationService: notifier,
            fetcher: { _ in (Data(), HTTPURLResponse()) },
            dateProvider: { dec31_2026 },
            calendar: calendar
        )

        let viewModel = MenuBarStatusViewModel(
            channelStore: channelStore,
            monitorService: monitor,
            dateProvider: { dec31_2026 },
            calendar: calendar
        )

        viewModel.newHandleInput = "@bukancaitlyn"
        let added = viewModel.addChannel()
        #expect(added)

        for _ in 0..<10 {
            if !mockCenter.requests.isEmpty { break }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        #expect(mockCenter.requests.contains(where: { $0.identifier == "dev-birthday-2026" }))
    }

    @Test @MainActor func testCelebrationViewModelHelpersAndStatusButtonFlashRule() async {
        #expect(MenuBarStatusView.shouldFlashStatusButton(isAnyLive: true, reduceMotion: false) == false)
        #expect(MenuBarStatusView.shouldFlashStatusButton(isAnyLive: true, reduceMotion: true) == false)
        #expect(MenuBarStatusView.shouldFlashStatusButton(isAnyLive: false, reduceMotion: false) == false)

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let channelStore = ChannelStore(userDefaults: makeTestDefaults())
        channelStore.addChannel(handle: "@bday", name: "Bday")

        let prefs = PreferencesStore(userDefaults: makeTestDefaults())
        prefs.settings.reduceMotion = true

        let liveHTML = """
        <html><body><script>var ytInitialPlayerResponse = {"videoDetails":{"isLive":true,"title":"Happy Birthday Stream!","videoId":"v1"}};</script></body></html>
        """
        let okResponse = HTTPURLResponse(
            url: URL(string: "https://www.youtube.com/@bday/live")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        let monitor = StreamMonitorService(
            channelStore: channelStore,
            preferencesStore: prefs,
            notificationService: NotificationService(center: MockNotificationCenter()),
            fetcher: { _ in (Data(liveHTML.utf8), okResponse) },
            dateProvider: { now }
        )

        await monitor.refreshAll()

        let viewModel = MenuBarStatusViewModel(
            channelStore: channelStore,
            monitorService: monitor,
            dateProvider: { now }
        )

        #expect(viewModel.isPopoverConfettiActive(date: now) == false)

        prefs.settings.reduceMotion = false
        #expect(viewModel.isPopoverConfettiActive(date: now) == true)

        let futureISO = ISO8601DateFormatter().string(from: now.addingTimeInterval(3 * 86400))
        let upcomingHTML = """
        <html><body><script>var ytInitialPlayerResponse = {"videoDetails":{"isUpcoming":true,"isLiveContent":true,"title":"Birthday Countdown!","videoId":"v2"},"microformat":{"playerMicroformatRenderer":{"liveBroadcastDetails":{"isLiveNow":false,"startTimestamp":"\(futureISO)"}}}};</script></body></html>
        """
        let upcomingMonitor = StreamMonitorService(
            channelStore: channelStore,
            preferencesStore: prefs,
            notificationService: NotificationService(center: MockNotificationCenter()),
            fetcher: { _ in (Data(upcomingHTML.utf8), okResponse) },
            dateProvider: { now }
        )
        await upcomingMonitor.refreshAll()
        let upcomingViewModel = MenuBarStatusViewModel(
            channelStore: channelStore,
            monitorService: upcomingMonitor,
            dateProvider: { now }
        )

        let sections = upcomingViewModel.sections
        #expect(upcomingViewModel.isPopoverConfettiActive(date: now) == false)
        #expect(upcomingViewModel.isSectionCelebrating(sections.upcoming, date: now) == true)

        let badge1 = NSHostingController(rootView: StatusBadge(isLive: true, isCelebration: true, reduceMotion: false))
        let badge2 = NSHostingController(rootView: StatusBadge(isLive: false, label: "UPCOMING", isCelebration: true, reduceMotion: true))
        let confetti = NSHostingController(rootView: ConfettiOverlayView())
        let popover = NSHostingController(rootView: MenuBarStatusView(viewModel: viewModel))
        _ = (badge1.view, badge2.view, confetti.view, popover.view)
    }
}
