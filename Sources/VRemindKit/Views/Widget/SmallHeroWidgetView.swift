import AppKit
import SwiftUI
#if canImport(WidgetKit)
import WidgetKit
#endif

// MARK: - Backward-compatible Widget Container Background Extension

extension View {
    @ViewBuilder
    public func widgetContainerBackground<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        #if canImport(WidgetKit)
        if #available(macOS 14.0, iOS 17.0, *) {
            self.containerBackground(for: .widget) {
                content()
            }
        } else {
            self.padding(12)
                .background(content())
        }
        #else
        self.padding(12)
            .background(content())
        #endif
    }
}

// MARK: - Widget Rendering Mode Reader for macOS 13+

#if canImport(WidgetKit)
@available(macOS 13.0, iOS 16.0, *)
private struct WidgetRenderingModeReader<Content: View>: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let content: (Bool) -> Content

    var body: some View {
        let isMonochrome = renderingMode == .accented || renderingMode == .vibrant
        content(isMonochrome)
    }
}
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

    public func primaryTextColor(isMonochrome: Bool) -> Color {
        isMonochrome ? .black : .white
    }

    public func secondaryTextColor(isMonochrome: Bool) -> Color {
        isMonochrome ? .black.opacity(0.85) : .white.opacity(0.9)
    }

    // MARK: - View Body

    public var body: some View {
        #if canImport(WidgetKit)
        if #available(macOS 13.0, iOS 16.0, *) {
            WidgetRenderingModeReader { isMonochrome in
                contentBody(isMonochrome: isMonochrome)
            }
            .widgetURL(deepLinkURL)
        } else {
            contentBody(isMonochrome: false)
                .widgetURL(deepLinkURL)
        }
        #else
        contentBody(isMonochrome: false)
        #endif
    }

    @ViewBuilder
    private func contentBody(isMonochrome: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            topStatusHeader(isMonochrome: isMonochrome)
            Spacer(minLength: 4)
            bottomContent(isMonochrome: isMonochrome)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetContainerBackground {
            ZStack {
                backgroundLayer(isMonochrome: isMonochrome)

                LinearGradient(
                    gradient: Gradient(colors: isMonochrome
                        ? [.white.opacity(0.0), .white.opacity(0.2), .white.opacity(0.55)]
                        : [.black.opacity(0.15), .black.opacity(0.55), .black.opacity(0.95)]
                    ),
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private func backgroundLayer(isMonochrome: Bool = false) -> some View {
        if let nsImage = WidgetAvatarLoader.loadNSImage(filename: channel?.avatarFilename, in: avatarsDirectoryURL) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .saturation(isDimmed ? 0.2 : 1.0)
                .opacity(isDimmed ? 0.6 : 1.0)
                .clipped()
        } else {
            // High-contrast monogram fallback
            GeometryReader { geo in
                ZStack {
                    LinearGradient(
                        colors: isMonochrome
                            ? [Color(white: 0.88), Color(white: 0.72)]
                            : (isDimmed
                                ? [Color(white: 0.25), Color(white: 0.12)]
                                : [Theme.accent, Color.purple.opacity(0.7), Color.black.opacity(0.8)]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .saturation(isDimmed ? 0.2 : 1.0)
                    .opacity(isDimmed ? 0.6 : 1.0)

                    Text(monogramLetter)
                        .font(.system(size: min(geo.size.width, geo.size.height) * 0.44, weight: .black, design: .rounded))
                        .foregroundColor(isMonochrome ? .black.opacity(0.35) : .white.opacity(isDimmed ? 0.4 : 0.6))
                        .shadow(color: isMonochrome ? .clear : .black.opacity(0.5), radius: 6, x: 0, y: 3)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private func topStatusHeader(isMonochrome: Bool) -> some View {
        HStack(alignment: .center, spacing: 6) {
            if isLive {
                // Live status badge
                HStack(spacing: 4) {
                    Circle()
                        .fill(isMonochrome ? Color.black : Color.red)
                        .frame(width: 6, height: 6)
                    Text("LIVE")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(isMonochrome ? .black : .white)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(isMonochrome ? Color.white.opacity(0.85) : Color.red.opacity(0.85))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(isMonochrome ? Color.black.opacity(0.4) : Color.clear, lineWidth: 1)
                )

                Spacer()

                // Uptime pill
                Text(uptimeText)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(isMonochrome ? .black : .white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(isMonochrome ? Color.white.opacity(0.75) : Color.black.opacity(0.45))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(isMonochrome ? Color.black.opacity(0.3) : Color.clear, lineWidth: 1)
                    )
            } else if let channel = channel, channel.statusKind == .upcoming {
                HStack(spacing: 4) {
                    Circle()
                        .fill(isMonochrome ? Color.black : Color.blue)
                        .frame(width: 6, height: 6)
                    Text("UPCOMING")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(isMonochrome ? .black : .white)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(isMonochrome ? Color.white.opacity(0.85) : Color.blue.opacity(0.75))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(isMonochrome ? Color.black.opacity(0.4) : Color.clear, lineWidth: 1)
                )

                Spacer()
            } else {
                // Offline status badge
                HStack(spacing: 4) {
                    Circle()
                        .fill(isMonochrome ? Color.black.opacity(0.6) : Color.secondary)
                        .frame(width: 6, height: 6)
                    Text("OFFLINE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(isMonochrome ? .black : .white.opacity(0.85))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(isMonochrome ? Color.white.opacity(0.75) : Color.black.opacity(0.45))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(isMonochrome ? Color.black.opacity(0.3) : Color.clear, lineWidth: 1)
                )

                Spacer()

                if let lastStreamed = channel?.lastStreamedAt {
                    Text(ElapsedTime.relative(from: lastStreamed))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(isMonochrome ? .black.opacity(0.75) : .white.opacity(0.75))
                }
            }
        }
    }

    @ViewBuilder
    private func bottomContent(isMonochrome: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let channel = channel {
                if allOffline {
                    Text(offlineHeadline)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(primaryTextColor(isMonochrome: isMonochrome))
                        .lineLimit(1)
                    Text(channel.displayName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(secondaryTextColor(isMonochrome: isMonochrome))
                        .lineLimit(1)
                } else {
                    Text(channel.displayName)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(primaryTextColor(isMonochrome: isMonochrome))
                        .lineLimit(1)

                    if let title = channel.streamTitle, !title.isEmpty {
                        Text(title)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(secondaryTextColor(isMonochrome: isMonochrome))
                            .lineLimit(2)
                    } else {
                        Text(channel.handle)
                            .font(.system(size: 10, weight: .regular))
                            .foregroundColor(isMonochrome ? .black.opacity(0.75) : .white.opacity(0.75))
                            .lineLimit(1)
                    }

                    if isLive {
                        Text("Click to watch ↗")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(isMonochrome ? .black : Theme.accent)
                            .padding(.top, 2)
                    }
                }
            } else {
                Text("VRemind")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(primaryTextColor(isMonochrome: isMonochrome))
                Text("No channels added")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(secondaryTextColor(isMonochrome: isMonochrome))
            }
        }
    }
}
