import AppKit
import SwiftUI

/// Medium (systemMedium) watchlist widget view displaying up to 3 monitored channels
/// with live status badges, stream titles, and individual deep links to watch.
public struct MediumWatchlistWidgetView: View {
    public let channels: [WidgetChannelItem]
    public let avatarsDirectoryURL: URL?

    public init(
        channels: [WidgetChannelItem] = [],
        avatarsDirectoryURL: URL? = nil
    ) {
        self.channels = channels
        self.avatarsDirectoryURL = avatarsDirectoryURL ?? WidgetSnapshotStore.shared.avatarsDirectoryURL
    }

    public init(entry: VRemindWidgetEntry, avatarsDirectoryURL: URL? = nil) {
        self.init(
            channels: entry.snapshot.channels,
            avatarsDirectoryURL: avatarsDirectoryURL ?? WidgetSnapshotStore.shared.avatarsDirectoryURL
        )
    }

    public var displayedChannels: [WidgetChannelItem] {
        Array(channels.prefix(3))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            headerView

            // Channel Rows or Empty View
            if displayedChannels.isEmpty {
                emptyView
            } else {
                VStack(spacing: 6) {
                    ForEach(displayedChannels) { channel in
                        channelRow(for: channel)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
    }

    // MARK: - Subviews

    private var headerView: some View {
        HStack(alignment: .center) {
            HStack(spacing: 5) {
                Image(systemName: "play.tv.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Theme.accent)
                Text("VRemind")
                    .font(.system(size: 12, weight: .bold))
            }

            Spacer()

            Text("\(channels.count) \(channels.count == 1 ? "channel" : "channels")")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
        }
    }

    private var emptyView: some View {
        VStack(alignment: .center, spacing: 4) {
            Spacer()
            Text("No channels monitored")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            Text("Add channels in VRemind menu bar")
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.8))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func channelRow(for channel: WidgetChannelItem) -> some View {
        Link(destination: channel.deepLinkURL ?? channel.channelURL) {
            HStack(spacing: 8) {
                // Avatar Thumbnail or Monogram
                avatarThumbnail(for: channel)

                // Creator name & stream title
                VStack(alignment: .leading, spacing: 2) {
                    Text(channel.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    if let title = channel.streamTitle, !title.isEmpty {
                        Text(title)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    } else {
                        Text(channel.handle)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.8))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)

                // Status Badge & Timing
                statusBadge(for: channel)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.04))
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func avatarThumbnail(for channel: WidgetChannelItem) -> some View {
        Group {
            if let image = WidgetAvatarLoader.loadNSImage(filename: channel.avatarFilename, in: avatarsDirectoryURL) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 28, height: 28)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .strokeBorder(channel.statusKind == .live ? Color.red.opacity(0.5) : Color.primary.opacity(0.1), lineWidth: 1)
                    )
            } else {
                WidgetMonogramView(
                    displayName: channel.displayName,
                    size: 28,
                    isDimmed: channel.statusKind != .live
                )
            }
        }
        .frame(width: 28, height: 28)
        .overlay(
            PlatformBadgeView(platform: channel.platform, size: 9),
            alignment: .bottomTrailing
        )
    }

    @ViewBuilder
    private func statusBadge(for channel: WidgetChannelItem) -> some View {
        switch channel.statusKind {
        case .live:
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 5, height: 5)
                Text(ElapsedTime.liveDuration(since: channel.liveStartedAt))
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(Color.red)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.red.opacity(0.12))
            .clipShape(Capsule())

        case .upcoming:
            Text("UPCOMING")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(Color.blue)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.blue.opacity(0.12))
                .clipShape(Capsule())

        case .offline, .unknown:
            if let lastStreamed = channel.lastStreamedAt {
                Text(ElapsedTime.relative(from: lastStreamed))
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(.secondary)
            } else {
                Text("OFFLINE")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
    }
}
