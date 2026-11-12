import AppKit
import SwiftUI
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Small (systemSmall) hero widget view featuring a single creator.
/// Displays a full-bleed avatar background with dark gradient scrim, crisp white typography,
/// live status badges, uptime, and deep link browser launch.
public struct SmallHeroWidgetView: View {
    public let channel: WidgetChannelItem?
    public let avatarsDirectoryURL: URL?
    public let allOffline: Bool

    public init(
        channel: WidgetChannelItem?,
        avatarsDirectoryURL: URL? = nil,
        allOffline: Bool = false
    ) {
        self.channel = channel
        self.avatarsDirectoryURL = avatarsDirectoryURL ?? WidgetSnapshotStore.shared.avatarsDirectoryURL
        self.allOffline = allOffline
    }

    public init(entry: VRemindWidgetEntry, avatarsDirectoryURL: URL? = nil) {
        self.init(
            channel: entry.heroChannel,
            avatarsDirectoryURL: avatarsDirectoryURL ?? WidgetSnapshotStore.shared.avatarsDirectoryURL,
            allOffline: entry.isAllOffline
        )
    }

    // MARK: - Computed Properties for Logic & Testing

    public var isLive: Bool {
        channel?.statusKind == .live
    }

    public var isDimmed: Bool {
        if allOffline { return true }
        guard let channel = channel else { return true }
        return channel.statusKind == .offline || channel.statusKind == .unknown
    }

    public var hasLocalAvatarImage: Bool {
        WidgetAvatarLoader.loadNSImage(
            filename: channel?.avatarFilename,
            in: avatarsDirectoryURL
        ) != nil
    }

    public var monogramLetter: String {
        let name = channel?.displayName ?? "VRemind"
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = trimmed.first {
            return String(first).uppercased()
        }
        return "V"
    }

    public var uptimeText: String {
        ElapsedTime.liveDuration(since: channel?.liveStartedAt)
    }

    public var offlineHeadline: String {
        if allOffline {
            return "All channels offline"
        }
        return channel?.displayName ?? "All channels offline"
    }

    public var deepLinkURL: URL? {
        channel?.deepLinkURL
    }

    // MARK: - View Body

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Layer 1: Background Avatar or Monogram
                backgroundLayer(size: geometry.size)

                // Layer 2: Gradient Scrim
                LinearGradient(
                    gradient: Gradient(colors: [
                        .black.opacity(0.15),
                        .black.opacity(0.55),
                        .black.opacity(0.95)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Layer 3: Foreground Content
                VStack(alignment: .leading, spacing: 0) {
                    topStatusHeader
                    Spacer(minLength: 4)
                    bottomContent
                }
                .padding(12)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        #if canImport(WidgetKit)
        .widgetURL(deepLinkURL)
        #endif
    }

    // MARK: - Subviews

    @ViewBuilder
    private func backgroundLayer(size: CGSize) -> some View {
        if let nsImage = WidgetAvatarLoader.loadNSImage(filename: channel?.avatarFilename, in: avatarsDirectoryURL) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size.width, height: size.height)
                .saturation(isDimmed ? 0.2 : 1.0)
                .opacity(isDimmed ? 0.6 : 1.0)
                .clipped()
        } else {
            // High-contrast monogram fallback (Review Focus #2)
            ZStack {
                LinearGradient(
                    colors: isDimmed
                        ? [Color(white: 0.25), Color(white: 0.12)]
                        : [Theme.accent, Color.purple.opacity(0.7), Color.black.opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .saturation(isDimmed ? 0.2 : 1.0)
                .opacity(isDimmed ? 0.6 : 1.0)

                Text(monogramLetter)
                    .font(.system(size: min(size.width, size.height) * 0.44, weight: .black, design: .rounded))
                    .foregroundColor(.white.opacity(isDimmed ? 0.4 : 0.6))
                    .shadow(color: .black.opacity(0.5), radius: 6, x: 0, y: 3)
            }
            .frame(width: size.width, height: size.height)
        }
    }

    @ViewBuilder
    private var topStatusHeader: some View {
        HStack(alignment: .center, spacing: 6) {
            if isLive {
                // Live status badge
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 6, height: 6)
                    Text("LIVE")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.red.opacity(0.85))
                .clipShape(Capsule())

                Spacer()

                // Uptime pill
                Text(uptimeText)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.45))
                    .clipShape(Capsule())
            } else if let channel = channel, channel.statusKind == .upcoming {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 6, height: 6)
                    Text("UPCOMING")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.blue.opacity(0.75))
                .clipShape(Capsule())

                Spacer()
            } else {
                // Offline status badge (Review Focus #4)
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 6, height: 6)
                    Text("OFFLINE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.85))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.45))
                .clipShape(Capsule())

                Spacer()

                if let lastStreamed = channel?.lastStreamedAt {
                    Text(ElapsedTime.relative(from: lastStreamed))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(0.75))
                }
            }
        }
    }

    @ViewBuilder
    private var bottomContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let channel = channel {
                if allOffline {
                    Text(offlineHeadline)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(channel.displayName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(1)
                } else {
                    Text(channel.displayName)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    if let title = channel.streamTitle, !title.isEmpty {
                        Text(title)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(2)
                    } else {
                        Text(channel.handle)
                            .font(.system(size: 10, weight: .regular))
                            .foregroundColor(.white.opacity(0.75))
                            .lineLimit(1)
                    }

                    if isLive {
                        Text("Click to watch ↗")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(Theme.accent)
                            .padding(.top, 2)
                    }
                }
            } else {
                Text("VRemind")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                Text("No channels added")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.white.opacity(0.8))
            }
        }
    }
}
