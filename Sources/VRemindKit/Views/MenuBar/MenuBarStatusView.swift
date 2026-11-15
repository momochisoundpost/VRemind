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
    @Published public var isPopoverVisible: Bool = false

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
    public let powerMonitor: PowerStateMonitor?

    public var preferencesStore: PreferencesStore {
        monitorService.preferencesStore
    }

    public var areAnimationsPaused: Bool {
        preferencesStore.settings.reduceMotion || (powerMonitor?.currentPolicy.animationsPaused ?? false)
    }

    public var shouldAnimatePopoverEffects: Bool {
        isPopoverVisible && !areAnimationsPaused
    }

    private let dateProvider: () -> Date
    private let calendar: Calendar
    private var dailyOrderDayStart: Date?
    private var dailyOrderedIds: [String]?
    private var cancellables = Set<AnyCancellable>()

    public init(
        channelStore: ChannelStore,
        monitorService: StreamMonitorService,
        powerMonitor: PowerStateMonitor? = nil,
        dateProvider: @escaping () -> Date = { Date() },
        calendar: Calendar = .current
    ) {
        self.channelStore = channelStore
        self.monitorService = monitorService
        let resolvedPowerMonitor = powerMonitor ?? monitorService.powerMonitor
        self.powerMonitor = resolvedPowerMonitor
        self.dateProvider = dateProvider
        self.calendar = calendar

        Publishers.Merge4(
            channelStore.objectWillChange,
            monitorService.objectWillChange,
            monitorService.preferencesStore.objectWillChange,
            resolvedPowerMonitor.objectWillChange
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
        let base = Self.splitSections(
            channels: channelStore.channels,
            statuses: monitorService.statuses
        )
        guard let orderedIds = dailyOrderedIds, !orderedIds.isEmpty else {
            return base
        }
        let todayStart = calendar.startOfDay(for: dateProvider())
        if dailyOrderDayStart == todayStart {
            return ChannelOrderPolicy.applyCustomOrder(base, orderedIds: orderedIds)
        }
        dailyOrderDayStart = nil
        dailyOrderedIds = nil
        return base
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
        let targetId = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        dailyOrderedIds?.removeAll { entry in
            let normalized = entry.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return normalized == targetId ||
                (!targetId.contains(":") && normalized == "youtube:\(targetId)")
        }
        channelStore.removeChannel(id: id)
    }

    public func clearCustomOrder() {
        dailyOrderDayStart = nil
        dailyOrderedIds = nil
        objectWillChange.send()
    }

    public func reorderSection(_ kind: SectionKind, fromIndex: Int, toIndex: Int) {
        let currentSections = sections
        let targetItems: [WatchedChannel]
        switch kind {
        case .live:
            targetItems = currentSections.live
        case .upcoming:
            targetItems = currentSections.upcoming
        case .offline:
            targetItems = currentSections.offline
        }

        guard fromIndex >= 0, fromIndex < targetItems.count,
              toIndex >= 0, toIndex < targetItems.count,
              fromIndex != toIndex else {
            return
        }

        let reordered = ChannelOrderPolicy.reorderSectionItems(
            targetItems,
            fromIndex: fromIndex,
            toIndex: toIndex
        )
        let nextSections = ChannelOrderPolicy.applySectionOrder(
            currentSections,
            kind: kind,
            reorderedSection: reordered
        )

        dailyOrderDayStart = calendar.startOfDay(for: dateProvider())
        dailyOrderedIds = (nextSections.live + nextSections.upcoming + nextSections.offline).map(\.id)

        objectWillChange.send()
        channelStore.reorderSection(orderedSectionIds: reordered.map(\.id))
    }

    public func refresh() {
        Task {
            await monitorService.refreshAll()
        }
    }

    public func isPopoverConfettiActive(date: Date = Date()) -> Bool {
        guard !areAnimationsPaused else {
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

private struct ActiveSectionDrag: Equatable {
    let kind: SectionKind
    let draggedId: String
    var step: DragLayoutStep
}

private struct SectionRowHeightPreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGFloat] = [:]

    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

// MARK: - MenuBarStatusView

public struct MenuBarStatusView: View {
    private static let sectionRowSpacing: CGFloat = 4
    private static let fallbackRowHeight: CGFloat = 46

    @ObservedObject public var viewModel: MenuBarStatusViewModel
    public let onOpenPreferences: () -> Void
    public let onQuit: () -> Void

    @State private var activeDrag: ActiveSectionDrag? = nil
    @State private var rowHeightsBySection: [SectionKind: [String: CGFloat]] = [:]
    @State private var suppressTapUntil: Date = .distantPast

    public static func shouldFlashStatusButton(isAnyLive: Bool, reduceMotion: Bool) -> Bool {
        false
    }

    public init(
        viewModel: MenuBarStatusViewModel,
        onOpenPreferences: @escaping () -> Void = {},
        onQuit: @escaping () -> Void = {}
    ) {
        self.viewModel = viewModel
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

            if viewModel.isPopoverVisible && viewModel.isPopoverConfettiActive() {
                ConfettiOverlayView()
            }
        }
        .frame(width: 360, height: 440)
        .onChange(of: viewModel.isPopoverVisible) { isVisible in
            if !isVisible {
                activeDrag = nil
            }
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
                            kind: .live,
                            title: "LIVE NOW",
                            count: sections.live.count,
                            color: Theme.live,
                            channels: sections.live
                        )
                    }

                    if !sections.upcoming.isEmpty {
                        sectionBlock(
                            kind: .upcoming,
                            title: "UPCOMING",
                            count: sections.upcoming.count,
                            color: .orange,
                            channels: sections.upcoming
                        )
                    }

                    if !sections.offline.isEmpty {
                        sectionBlock(
                            kind: .offline,
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
        kind: SectionKind,
        title: String,
        count: Int,
        color: Color,
        channels: [WatchedChannel]
    ) -> some View {
        let reduceMotion = viewModel.areAnimationsPaused
        let animate = viewModel.shouldAnimatePopoverEffects
        let isCelebrating = (kind == .live || kind == .upcoming) && viewModel.isSectionCelebrating(channels)

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(color)
                    .rainbowForeground(active: isCelebrating, animate: animate, reduceMotion: reduceMotion)

                Text("(\(count))")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)

            VStack(alignment: .leading, spacing: Self.sectionRowSpacing) {
                ForEach(Array(channels.enumerated()), id: \.element.id) { index, channel in
                    sectionRowView(
                        kind: kind,
                        index: index,
                        channel: channel,
                        channels: channels,
                        animate: animate,
                        reduceMotion: reduceMotion
                    )
                }
            }
            .coordinateSpace(name: sectionCoordinateSpaceName(for: kind))
            .onPreferenceChange(SectionRowHeightPreferenceKey.self) { heights in
                var current = rowHeightsBySection[kind] ?? [:]
                var changed = false
                for (id, height) in heights where height > 0 {
                    if abs((current[id] ?? 0) - height) > 0.5 {
                        current[id] = height
                        changed = true
                    }
                }
                if changed {
                    rowHeightsBySection[kind] = current
                }
            }
        }
    }

    private func sectionRowView(
        kind: SectionKind,
        index: Int,
        channel: WatchedChannel,
        channels: [WatchedChannel],
        animate: Bool,
        reduceMotion: Bool
    ) -> some View {
        let isDragged = isDraggedRow(kind: kind, channelId: channel.id)
        let rowAnimation: Animation? = (isDragged || reduceMotion || activeDrag == nil)
            ? nil
            : .interactiveSpring(response: 0.22, dampingFraction: 0.86)
        let targetIndexInSection = activeDrag?.kind == kind ? activeDrag?.step.targetIndex : nil

        let row = ChannelRowView(
            channel: channel,
            status: viewModel.monitorService.status(for: channel),
            animate: animate,
            reduceMotion: reduceMotion,
            isDraggingAnyRow: activeDrag != nil,
            shouldSuppressTap: { Date() < suppressTapUntil },
            onDelete: {
                viewModel.removeChannel(id: channel.id)
            }
        )
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: SectionRowHeightPreferenceKey.self,
                    value: [channel.id: proxy.size.height]
                )
            }
        )
        .offset(y: rowOffset(kind: kind, index: index, channelCount: channels.count))
        .zIndex(isDragged ? 10 : 0)
        .opacity(isDragged ? 0.92 : 1.0)
        .animation(rowAnimation, value: targetIndexInSection)

        return withSectionDragGesture(
            row,
            enabled: channels.count >= 2,
            kind: kind,
            channel: channel,
            channels: channels
        )
    }

    @ViewBuilder
    private func withSectionDragGesture<Row: View>(
        _ row: Row,
        enabled: Bool,
        kind: SectionKind,
        channel: WatchedChannel,
        channels: [WatchedChannel]
    ) -> some View {
        if enabled {
            row.simultaneousGesture(
                sectionDragGesture(kind: kind, channel: channel, channels: channels)
            )
        } else {
            row
        }
    }

    private func sectionDragGesture(
        kind: SectionKind,
        channel: WatchedChannel,
        channels: [WatchedChannel]
    ) -> some Gesture {
        DragGesture(
            minimumDistance: ChannelOrderPolicy.dragActivationThreshold,
            coordinateSpace: .named(sectionCoordinateSpaceName(for: kind))
        )
        .onChanged { value in
            if let current = activeDrag, (current.kind != kind || current.draggedId != channel.id) {
                return
            }

            let deltaY = value.translation.height
            if activeDrag == nil {
                guard ChannelOrderPolicy.exceedsDragThreshold(deltaY) else { return }
            }

            guard let currentIndex = channels.firstIndex(where: { $0.id == channel.id }) else {
                activeDrag = nil
                return
            }

            let step = ChannelOrderPolicy.calculateDragLayout(
                draggedIndex: currentIndex,
                deltaY: deltaY,
                itemHeights: measuredHeights(for: kind, channels: channels),
                itemSpacing: Self.sectionRowSpacing
            )
            activeDrag = ActiveSectionDrag(kind: kind, draggedId: channel.id, step: step)
        }
        .onEnded { value in
            guard let current = activeDrag, current.kind == kind, current.draggedId == channel.id else {
                return
            }

            // Block any synthetic button click fired right as the mouse releases a drag.
            suppressTapUntil = Date().addingTimeInterval(0.2)

            let fromIndex = channels.firstIndex(where: { $0.id == channel.id })
            let targetIndex: Int?
            if let fromIndex {
                targetIndex = ChannelOrderPolicy.calculateDragLayout(
                    draggedIndex: fromIndex,
                    deltaY: value.translation.height,
                    itemHeights: measuredHeights(for: kind, channels: channels),
                    itemSpacing: Self.sectionRowSpacing
                ).targetIndex
            } else {
                targetIndex = nil
            }

            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                activeDrag = nil
                if let fromIndex, let targetIndex, targetIndex != fromIndex {
                    viewModel.reorderSection(kind, fromIndex: fromIndex, toIndex: targetIndex)
                }
            }
        }
    }

    private func sectionCoordinateSpaceName(for kind: SectionKind) -> String {
        "section-\(kind.rawValue)"
    }

    private func isDraggedRow(kind: SectionKind, channelId: String) -> Bool {
        activeDrag?.kind == kind && activeDrag?.draggedId == channelId
    }

    private func rowOffset(kind: SectionKind, index: Int, channelCount: Int) -> CGFloat {
        guard let activeDrag, activeDrag.kind == kind else { return 0 }
        let translates = activeDrag.step.itemTranslateY
        guard index >= 0, index < channelCount, index < translates.count else { return 0 }
        return translates[index]
    }

    private func measuredHeights(for kind: SectionKind, channels: [WatchedChannel]) -> [CGFloat] {
        let cached = rowHeightsBySection[kind] ?? [:]
        return channels.map { cached[$0.id] ?? Self.fallbackRowHeight }
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

    @MainActor
    public static func makePopoverWithViewModel(
        channelStore: ChannelStore,
        monitorService: StreamMonitorService,
        powerMonitor: PowerStateMonitor? = nil,
        onOpenPreferences: @escaping () -> Void = {},
        onQuit: @escaping () -> Void = {}
    ) -> (popover: NSPopover, viewModel: MenuBarStatusViewModel) {
        let viewModel = MenuBarStatusViewModel(
            channelStore: channelStore,
            monitorService: monitorService,
            powerMonitor: powerMonitor
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
        return (popover, viewModel)
    }

    @MainActor
    public static func makePopover(
        channelStore: ChannelStore,
        monitorService: StreamMonitorService,
        powerMonitor: PowerStateMonitor? = nil,
        onOpenPreferences: @escaping () -> Void = {},
        onQuit: @escaping () -> Void = {}
    ) -> NSPopover {
        makePopoverWithViewModel(
            channelStore: channelStore,
            monitorService: monitorService,
            powerMonitor: powerMonitor,
            onOpenPreferences: onOpenPreferences,
            onQuit: onQuit
        ).popover
    }
}
