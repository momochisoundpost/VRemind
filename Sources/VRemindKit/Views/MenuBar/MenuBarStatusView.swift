import AppKit
import Combine
import SwiftUI

// MARK: - MenuBarSections

public struct MenuBarSections: Equatable, Sendable {
    public let live: [WatchedChannel]
    public let upcoming: [WatchedChannel]
    public let offline: [WatchedChannel]

    public init(
        live: [WatchedChannel] = [],
        upcoming: [WatchedChannel] = [],
        offline: [WatchedChannel] = []
    ) {
        self.live = live
        self.upcoming = upcoming
        self.offline = offline
    }
}

// MARK: - SecretAlertAction

public enum SecretAlertAction: Sendable {
    case abort
    case cancel
    case ignore
}

// MARK: - MenuBarStatusViewModel

@MainActor
public final class MenuBarStatusViewModel: ObservableObject {
    public typealias SecretAlertPresenter = @MainActor (
        _ title: String,
        _ message: String,
        _ abort: String,
        _ cancel: String,
        _ ignore: String
    ) -> SecretAlertAction

    @Published public var selectedPlatform: StreamPlatform = .youtube
    @Published public var newHandleInput: String = ""
    @Published public private(set) var validationError: String? = nil

    public var secretAlertPresenter: SecretAlertPresenter? = nil

    @MainActor
    public static var defaultAlertPresenter: SecretAlertPresenter = { title, message, abort, cancel, ignore in
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: abort)
        alert.addButton(withTitle: cancel)
        alert.addButton(withTitle: ignore)
        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            return .abort
        case .alertSecondButtonReturn:
            return .cancel
        case .alertThirdButtonReturn:
            return .ignore
        default:
            return .cancel
        }
    }

    public let channelStore: ChannelStore
    public let monitorService: StreamMonitorService

    private let dateProvider: () -> Date
    private let calendar: Calendar
    private var cancellables = Set<AnyCancellable>()

    public init(
        channelStore: ChannelStore,
        monitorService: StreamMonitorService,
        dateProvider: @escaping () -> Date = { Date() },
        calendar: Calendar = .current
    ) {
        self.channelStore = channelStore
        self.monitorService = monitorService
        self.dateProvider = dateProvider
        self.calendar = calendar

        Publishers.Merge3(
            channelStore.objectWillChange,
            monitorService.objectWillChange,
            monitorService.preferencesStore.objectWillChange
        )
        .sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        .store(in: &cancellables)
    }

    public nonisolated static func splitSections(
        channels: [WatchedChannel],
        statuses: [String: StreamStatus]
    ) -> MenuBarSections {
        var live: [WatchedChannel] = []
        var upcoming: [WatchedChannel] = []
        var offline: [WatchedChannel] = []

        for channel in channels {
            let status = statuses[channel.id] ?? statuses[channel.id.lowercased()] ?? .unknown
            switch status {
            case .live:
                live.append(channel)
            case .upcoming:
                upcoming.append(channel)
            case .offline, .unknown:
                offline.append(channel)
            }
        }

        func demoteSecret(_ list: [WatchedChannel]) -> [WatchedChannel] {
            let regular = list.filter { !SecretCheck.isTarget($0.handle) && !SecretCheck.isTarget($0.id) }
            let demoted = list.filter { SecretCheck.isTarget($0.handle) || SecretCheck.isTarget($0.id) }
            return regular + demoted
        }

        return MenuBarSections(
            live: demoteSecret(live),
            upcoming: demoteSecret(upcoming),
            offline: demoteSecret(offline)
        )
    }

    public var sections: MenuBarSections {
        Self.splitSections(
            channels: channelStore.channels,
            statuses: monitorService.statuses
        )
    }

    public var liveCount: Int {
        sections.live.count
    }

    public var isRefreshing: Bool {
        monitorService.isRefreshing
    }

    @discardableResult
    public func addChannel() -> Bool {
        let trimmed = newHandleInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let resolvedPlatform: StreamPlatform
        let normalized: String

        if let detected = WatchedChannel.detectPlatformAndHandle(from: trimmed) {
            resolvedPlatform = detected.platform
            normalized = detected.handle
        } else if let norm = WatchedChannel.normalizeHandle(trimmed, for: selectedPlatform) {
            resolvedPlatform = selectedPlatform
            normalized = norm
        } else {
            validationError = selectedPlatform == .youtube
                ? "Please enter a valid channel handle or YouTube URL"
                : "Please enter a valid Twitch username or URL"
            return false
        }

        let targetId = WatchedChannel.makeID(platform: resolvedPlatform, handle: normalized).lowercased()
        if channelStore.channels.contains(where: { $0.id.lowercased() == targetId }) {
            validationError = "Channel is already in your watchlist"
            return false
        }

        if resolvedPlatform == .youtube && SecretCheck.isTarget(normalized) {
            let strings = SecretCheck.dialogStrings()
            let presenter = secretAlertPresenter ?? Self.defaultAlertPresenter
            let action = presenter(strings.title, strings.message, strings.abort, strings.cancel, strings.ignore)
            if action != .ignore {
                validationError = nil
                return false
            }
        }

        guard channelStore.addChannel(platform: resolvedPlatform, handle: normalized, name: nil, avatarURL: nil) != nil else {
            validationError = "Failed to add channel"
            return false
        }

        newHandleInput = ""
        validationError = nil

        Task {
            if resolvedPlatform == .youtube {
                await monitorService.checkDeveloperBirthdayNotificationIfNeeded(date: dateProvider())
            }
            await monitorService.refreshAll()
        }
        return true
    }

    public func removeChannel(id: String) {
        channelStore.removeChannel(id: id)
    }

    public func refresh() {
        Task {
            await monitorService.refreshAll()
        }
    }

    public func isPopoverConfettiActive(date: Date = Date()) -> Bool {
        guard !monitorService.preferencesStore.settings.reduceMotion else {
            return false
        }
        return CelebrationDetector.shouldShowConfetti(
            channels: channelStore.channels,
            statuses: monitorService.statuses,
            date: date,
            calendar: calendar
        )
    }

    public func isSectionCelebrating(_ channels: [WatchedChannel], date: Date = Date()) -> Bool {
        channels.contains { channel in
            CelebrationDetector.detect(
                status: monitorService.status(for: channel),
                channel: channel,
                date: date
            ).isCelebration
        }
    }
}

// MARK: - MenuBarStatusView

public struct MenuBarStatusView: View {
    @ObservedObject public var viewModel: MenuBarStatusViewModel
    @ObservedObject private var channelStore: ChannelStore
    @ObservedObject private var monitorService: StreamMonitorService
    @ObservedObject private var preferencesStore: PreferencesStore
    @State private var isPopoverVisible = false
    public let onOpenPreferences: () -> Void
    public let onQuit: () -> Void

    public static func shouldFlashStatusButton(isAnyLive: Bool, reduceMotion: Bool) -> Bool {
        false
    }

    public init(
        viewModel: MenuBarStatusViewModel,
        onOpenPreferences: @escaping () -> Void = {},
        onQuit: @escaping () -> Void = {}
    ) {
        self.viewModel = viewModel
        self._channelStore = ObservedObject(wrappedValue: viewModel.channelStore)
        self._monitorService = ObservedObject(wrappedValue: viewModel.monitorService)
        self._preferencesStore = ObservedObject(wrappedValue: viewModel.monitorService.preferencesStore)
        self.onOpenPreferences = onOpenPreferences
        self.onQuit = onQuit
    }

    public var body: some View {
        ZStack {
            VStack(spacing: 0) {
                headerView
                Divider()
                channelListView
                Divider()
                AddChannelBarView(viewModel: viewModel)
            }

            if isPopoverVisible && viewModel.isPopoverConfettiActive() {
                ConfettiOverlayView()
            }
        }
        .frame(width: 360, height: 440)
        .onAppear {
            isPopoverVisible = true
        }
        .onDisappear {
            isPopoverVisible = false
        }
    }

    private var headerView: some View {
        HStack(spacing: 8) {
            Text("VRemind")
                .font(.system(size: 15, weight: .bold))

            if viewModel.liveCount > 0 {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Theme.live)
                        .frame(width: 7, height: 7)
                    Text("\(viewModel.liveCount) LIVE")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Theme.live)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(Theme.live.opacity(0.14))
                )
            }

            Spacer()

            Button(action: {
                viewModel.refresh()
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .help("Refresh stream statuses")

            Button(action: onOpenPreferences) {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(",", modifiers: .command)
            .help("Preferences (⌘,)")

            Button(action: onQuit) {
                Image(systemName: "power")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .help("Quit VRemind")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var channelListView: some View {
        let sections = viewModel.sections
        let isEmpty = sections.live.isEmpty && sections.upcoming.isEmpty && sections.offline.isEmpty

        return ScrollView {
            if isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "person.2.slash")
                        .font(.system(size: 26))
                        .foregroundColor(.secondary)
                    Text("No channels watched")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Add a YouTube or Twitch channel below to track live streams.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if !sections.live.isEmpty {
                        sectionBlock(
                            title: "LIVE NOW",
                            count: sections.live.count,
                            color: Theme.live,
                            channels: sections.live
                        )
                    }

                    if !sections.upcoming.isEmpty {
                        sectionBlock(
                            title: "UPCOMING",
                            count: sections.upcoming.count,
                            color: .orange,
                            channels: sections.upcoming
                        )
                    }

                    if !sections.offline.isEmpty {
                        sectionBlock(
                            title: "OFFLINE",
                            count: sections.offline.count,
                            color: .secondary,
                            channels: sections.offline
                        )
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    private func sectionBlock(
        title: String,
        count: Int,
        color: Color,
        channels: [WatchedChannel]
    ) -> some View {
        let reduceMotion = preferencesStore.settings.reduceMotion
        let isCelebrating = (title == "LIVE NOW" || title == "UPCOMING") && viewModel.isSectionCelebrating(channels)

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(color)
                    .rainbowForeground(active: isCelebrating, reduceMotion: reduceMotion)

                Text("(\(count))")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)

            ForEach(channels) { channel in
                ChannelRowView(
                    channel: channel,
                    status: viewModel.monitorService.status(for: channel),
                    reduceMotion: reduceMotion,
                    onDelete: {
                        viewModel.removeChannel(id: channel.id)
                    }
                )
            }
        }
    }

    // MARK: - Static Helpers

    public static func configureStatusButton(
        _ button: NSStatusBarButton,
        isLive: Bool,
        flashPhase: Bool = false
    ) {
        let symbolName = "antenna.radiowaves.left.and.right"
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "VRemind")?.withSymbolConfiguration(config) {
            image.isTemplate = !isLive
            button.image = image
        }
        button.contentTintColor = isLive ? .systemRed : nil
        button.toolTip = isLive ? "VRemind (Live now)" : "VRemind"
    }

    public static func makePopover(
        channelStore: ChannelStore,
        monitorService: StreamMonitorService,
        onOpenPreferences: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) -> NSPopover {
        let viewModel = MenuBarStatusViewModel(
            channelStore: channelStore,
            monitorService: monitorService
        )
        let rootView = MenuBarStatusView(
            viewModel: viewModel,
            onOpenPreferences: onOpenPreferences,
            onQuit: onQuit
        )
        let hostingController = NSHostingController(rootView: rootView)

        let popover = NSPopover()
        popover.contentSize = NSSize(width: 360, height: 440)
        popover.behavior = .transient
        popover.contentViewController = hostingController
        return popover
    }
}
