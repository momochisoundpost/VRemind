import AppKit
import SwiftUI

/// Large (systemLarge) dashboard widget view combining a prominent hero card
/// for the top live broadcast and a multi-channel watchlist list below.
public struct LargeDashboardWidgetView: View {
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

    public var heroChannel: WidgetChannelItem? {
        channels.first
    }

    public var remainingChannels: [WidgetChannelItem] {
        Array(channels.dropFirst().prefix(4))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            headerView

            if channels.isEmpty {
                emptyView
            } else {
                // Featured Hero Banner
                if let hero = heroChannel {
                    heroBanner(for: hero)
                }

                // Remaining Watchlist Section
                if !remainingChannels.isEmpty {
                    Text("Watchlist")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(.top, 2)

                    VStack(spacing: 5) {
                        ForEach(remainingChannels) { channel in
                            watchlistRow(for: channel)
                        }
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
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Theme.accent)
                Text("VRemind Dashboard")
                    .font(.system(size: 13, weight: .bold))
            }

            Spacer()

            Text("\(channels.count) \(channels.count == 1 ? "channel" : "channels")")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
        }
    }

    private var emptyView: some View {
        VStack(alignment: .center, spacing: 6) {
            Spacer()
            Image(systemName: "sparkles.tv")
                .font(.system(size: 28))
                .foregroundColor(Theme.accent.opacity(0.8))
            Text("No channels monitored")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)
            Text("Add YouTube or Twitch channels in the menu bar popover.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func heroBanner(for channel: WidgetChannelItem) -> some View {
        Link(destination: channel.deepLinkURL ?? channel.channelURL) {
            HStack(spacing: 10) {
                // Avatar
                heroAvatar(for: channel)

                // Details
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        if channel.statusKind == .live {
                            HStack(spacing: 4) {
                                Circle().fill(Color.red).frame(width: 5, height: 5)
                                Text("LIVE")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.85))
                            .clipShape(Capsule())

                            Text(ElapsedTime.liveDuration(since: channel.liveStartedAt))
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.85))
                        } else if channel.statusKind == .upcoming {
                            Text("UPCOMING")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.8))
                                .clipShape(Capsule())
                        } else {
                            Text("OFFLINE")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white.opacity(0.85))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }

                    Text(channel.displayName)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    if let title = channel.streamTitle, !title.isEmpty {
                        Text(title)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(2)
                    } else {
                        Text(channel.handle)
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.75))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)

                Image(systemName: "arrow.up.right.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(Theme.accent)
            }
            .padding(10)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black.opacity(0.6))
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(channel.statusKind == .live ? Color.red.opacity(0.35) : Color.white.opacity(0.1), lineWidth: 1)
                }
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func heroAvatar(for channel: WidgetChannelItem) -> some View {
        Group {
            if let image = WidgetAvatarLoader.loadNSImage(filename: channel.avatarFilename, in: avatarsDirectoryURL) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 48, height: 48)
                    .clipShape(Circle())
            } else {
                WidgetMonogramView(
                    displayName: channel.displayName,
                    size: 48,
                    isDimmed: channel.statusKind != .live
                )
            }
        }
        .frame(width: 48, height: 48)
        .overlay(
            PlatformBadgeView(platform: channel.platform, size: 12),
            alignment: .bottomTrailing
        )
    }

    @ViewBuilder
    private func watchlistAvatar(for channel: WidgetChannelItem) -> some View {
        Group {
            if let image = WidgetAvatarLoader.loadNSImage(filename: channel.avatarFilename, in: avatarsDirectoryURL) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 24, height: 24)
                    .clipShape(Circle())
            } else {
                WidgetMonogramView(displayName: channel.displayName, size: 24, isDimmed: channel.statusKind != .live)
            }
        }
        .frame(width: 24, height: 24)
        .overlay(
            PlatformBadgeView(platform: channel.platform, size: 8),
            alignment: .bottomTrailing
        )
    }

    @ViewBuilder
    private func watchlistRow(for channel: WidgetChannelItem) -> some View {
        Link(destination: channel.deepLinkURL ?? channel.channelURL) {
            HStack(spacing: 8) {
                watchlistAvatar(for: channel)

                VStack(alignment: .leading, spacing: 1) {
                    Text(channel.displayName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    if let title = channel.streamTitle, !title.isEmpty {
                        Text(title)
                            .font(.system(size: 9))
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

                if channel.statusKind == .live {
                    HStack(spacing: 3) {
                        Circle().fill(Color.red).frame(width: 4, height: 4)
                        Text("LIVE")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(Color.red)
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.red.opacity(0.12))
                    .clipShape(Capsule())
                } else if channel.statusKind == .upcoming {
                    Text("UPCOMING")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(Color.blue)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.12))
                        .clipShape(Capsule())
                } else if let lastStreamed = channel.lastStreamedAt {
                    Text(ElapsedTime.relative(from: lastStreamed))
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(.secondary)
                } else {
                    Text("OFFLINE")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.03))
            )
        }
        .buttonStyle(.plain)
    }
}
