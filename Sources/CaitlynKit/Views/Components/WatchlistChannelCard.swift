import SwiftUI

public struct WatchlistChannelCard: View {
    public let channel: WatchedChannel
    public let status: StreamStatus
    public let lastStreamAt: Date?
    public let onRemove: (() -> Void)?

    public init(
        channel: WatchedChannel,
        status: StreamStatus,
        lastStreamAt: Date? = nil,
        onRemove: (() -> Void)? = nil
    ) {
        self.channel = channel
        self.status = status
        self.lastStreamAt = lastStreamAt
        self.onRemove = onRemove
    }

    public static func statusLine(status: StreamStatus, lastStreamAt: Date?, now: Date) -> String {
        if status.isLive {
            if let startedAt = status.startedAt {
                return "Live for " + ElapsedTime.short(from: startedAt, to: now)
            }
            return "Live now"
        }
        if let lastStreamAt {
            return "Last stream " + ElapsedTime.short(from: lastStreamAt, to: now) + " ago"
        }
        return "Offline"
    }

    public static func actionButtonTitle(isLive: Bool) -> String {
        isLive ? "Watch Stream ↗" : "Visit ↗"
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ChannelAvatarView(url: channel.avatarURL, size: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(channel.name)
                        .font(.system(size: 13, weight: .bold))
                        .lineLimit(1)
                    Text(channel.handle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                StatusBadge(isLive: status.isLive)

                if !channel.isPinned, let onRemove {
                    Button {
                        onRemove()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove from watchlist")
                }
            }

            if status.isLive, let title = status.title, !title.isEmpty {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    Text(
                        Self.statusLine(
                            status: status,
                            lastStreamAt: lastStreamAt,
                            now: context.date
                        )
                    )
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                }

                Spacer()

                Button {
                    LinkOpener.open(status.watchURL(channelHandle: channel.handle))
                } label: {
                    Text(Self.actionButtonTitle(isLive: status.isLive))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(status.isLive ? Theme.live : Theme.accent)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(status.isLive ? Theme.live.opacity(0.08) : Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    status.isLive ? Theme.live.opacity(0.3) : Color.secondary.opacity(0.2),
                    lineWidth: 1
                )
        )
    }
}
