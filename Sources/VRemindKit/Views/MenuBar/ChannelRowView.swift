import AppKit
import SwiftUI

// MARK: - Pointing Hand Cursor Modifier

public struct PointingHandCursorModifier: ViewModifier {
    @State private var isHovering = false

    public init() {}

    public func body(content: Content) -> some View {
        content
            .onHover { hovering in
                if hovering != isHovering {
                    isHovering = hovering
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
            }
            .onDisappear {
                if isHovering {
                    isHovering = false
                    NSCursor.pop()
                }
            }
    }
}

extension View {
    public func pointingHandCursor() -> some View {
        modifier(PointingHandCursorModifier())
    }
}

public struct ChannelRowView: View {
    public let channel: WatchedChannel
    public let status: StreamStatus
    public let animate: Bool
    public let reduceMotion: Bool
    public let isDraggingAnyRow: Bool
    public let dateProvider: () -> Date
    public let shouldSuppressTap: () -> Bool
    public let onDelete: () -> Void

    @State private var isRowHovered: Bool = false

    public nonisolated static func shouldShowDeleteButton(
        isHovered: Bool,
        isDraggingAnyRow: Bool
    ) -> Bool {
        isHovered && !isDraggingAnyRow
    }

    public init(
        channel: WatchedChannel,
        status: StreamStatus,
        animate: Bool = true,
        reduceMotion: Bool = false,
        isDraggingAnyRow: Bool = false,
        dateProvider: @escaping () -> Date = { Date() },
        shouldSuppressTap: @escaping () -> Bool = { false },
        onDelete: @escaping () -> Void
    ) {
        self.channel = channel
        self.status = status
        self.animate = animate
        self.reduceMotion = reduceMotion
        self.isDraggingAnyRow = isDraggingAnyRow
        self.dateProvider = dateProvider
        self.shouldSuppressTap = shouldSuppressTap
        self.onDelete = onDelete
    }

    public var isLive: Bool {
        if case .live = status {
            return true
        }
        return false
    }

    public var formattedHandle: String {
        switch channel.platform {
        case .youtube:
            return channel.handle.hasPrefix("@") ? channel.handle : "@\(channel.handle)"
        case .twitch:
            return channel.handle.hasPrefix("@") ? String(channel.handle.dropFirst()) : channel.handle
        }
    }

    public var streamURL: URL? {
        LinkOpener.streamURL(for: channel, status: status)
    }

    public var body: some View {
        let celebration = CelebrationDetector.detect(status: status, channel: channel, date: dateProvider())
        let showDelete = Self.shouldShowDeleteButton(
            isHovered: isRowHovered,
            isDraggingAnyRow: isDraggingAnyRow
        )

        HStack(spacing: 10) {
            Button(action: {
                guard !shouldSuppressTap() else { return }
                if let streamURL {
                    LinkOpener.open(streamURL)
                }
            }) {
                HStack(spacing: 10) {
                    ChannelAvatarView(url: channel.avatarURL, size: 36, platform: channel.platform)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(channel.name)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.primary)
                                .lineLimit(1)

                            Text(channel.handle)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .help("\(channel.platform.displayName): \(channel.handle)")
                        }
                        .help("\(channel.platform.displayName): \(channel.handle)")

                        statusSubtitleView(isCelebration: celebration.isCelebration)
                    }

                    Spacer(minLength: 4)

                    if isLive {
                        StatusBadge(
                            isLive: true,
                            isCelebration: celebration.isCelebration,
                            animate: animate,
                            reduceMotion: reduceMotion
                        )
                    } else if case .upcoming = status, celebration.isCelebration {
                        StatusBadge(
                            isLive: false,
                            label: "UPCOMING",
                            isCelebration: true,
                            animate: animate,
                            reduceMotion: reduceMotion
                        )
                    }
                }
            }
            .buttonStyle(.plain)
            .pointingHandCursor()

            if showDelete {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.live)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .help("Remove channel")
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(showDelete ? Color.primary.opacity(0.06) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isRowHovered = hovering
        }
        .onDisappear {
            isRowHovered = false
        }
    }

    @ViewBuilder
    private func statusSubtitleView(isCelebration: Bool) -> some View {
        switch status {
        case .live(_, let title, let startedAt):
            VStack(alignment: .leading, spacing: 1) {
                if !title.isEmpty {
                    Text(title)
                        .font(.system(size: 11))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
                Text("Live for \(ElapsedTime.liveDuration(since: startedAt))")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Theme.live)
                    .rainbowForeground(active: isCelebration, animate: animate, reduceMotion: reduceMotion)
            }

        case .upcoming(_, let title, let scheduledStartTime):
            VStack(alignment: .leading, spacing: 1) {
                if !title.isEmpty {
                    Text(title)
                        .font(.system(size: 11))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
                Text(formatScheduledTime(scheduledStartTime))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.orange)
                    .rainbowForeground(active: isCelebration, animate: animate, reduceMotion: reduceMotion)
            }

        case .offline(let lastStreamedAt):
            Text(lastStreamedAt != nil ? "Last live: \(ElapsedTime.relative(from: lastStreamedAt))" : "Offline")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)

        case .unknown:
            Text("Offline")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }

    private func formatScheduledTime(_ date: Date?) -> String {
        guard let date else { return "Upcoming" }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = Calendar.current.isDateInToday(date) ? .none : .short
        return "Starts: \(formatter.string(from: date))"
    }
}
