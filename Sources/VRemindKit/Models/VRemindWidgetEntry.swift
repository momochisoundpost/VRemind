import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Timeline entry representing the state of watched channels for widget rendering.
public struct VRemindWidgetEntry: Sendable, Equatable {
    public let date: Date
    public let snapshot: WidgetSnapshot
    public let isPlaceholder: Bool

    public init(
        date: Date = Date(),
        snapshot: WidgetSnapshot = WidgetSnapshot(),
        isPlaceholder: Bool = false
    ) {
        self.date = date
        self.snapshot = snapshot
        self.isPlaceholder = isPlaceholder
    }

    /// Primary featured channel (first in sorted list, if any).
    public var heroChannel: WidgetChannelItem? {
        snapshot.channels.first
    }

    /// True if there are no live or upcoming channels.
    public var isAllOffline: Bool {
        snapshot.channels.isEmpty || snapshot.channels.allSatisfy {
            $0.statusKind == .offline || $0.statusKind == .unknown
        }
    }

    /// Default fallback entry when no snapshot is available on disk.
    public static var fallback: VRemindWidgetEntry {
        let starter = WidgetChannelItem(
            platform: .youtube,
            handle: AppConstants.channelHandle,
            displayName: "Caitlyn Momochi",
            avatarFilename: "youtube_bukancaitlyn.jpg",
            avatarURL: nil,
            statusKind: .offline,
            streamTitle: nil,
            videoId: nil,
            liveStartedAt: nil,
            upcomingStartTime: nil,
            lastStreamedAt: nil
        )
        return VRemindWidgetEntry(
            date: Date(),
            snapshot: WidgetSnapshot(generatedAt: Date(), channels: [starter]),
            isPlaceholder: false
        )
    }

    /// Sample entry used for widget previews and placeholders.
    public static var previewSample: VRemindWidgetEntry {
        let starter = WidgetChannelItem(
            platform: .youtube,
            handle: AppConstants.channelHandle,
            displayName: "Caitlyn Momochi",
            avatarFilename: "youtube_bukancaitlyn.jpg",
            avatarURL: nil,
            statusKind: .live,
            streamTitle: "Chill Piano Practice 🎹",
            videoId: "sample_live",
            liveStartedAt: Date().addingTimeInterval(-1800),
            upcomingStartTime: nil,
            lastStreamedAt: nil
        )
        return VRemindWidgetEntry(
            date: Date(),
            snapshot: WidgetSnapshot(generatedAt: Date(), channels: [starter]),
            isPlaceholder: true
        )
    }
}

#if canImport(WidgetKit)
extension VRemindWidgetEntry: TimelineEntry {}
#endif
