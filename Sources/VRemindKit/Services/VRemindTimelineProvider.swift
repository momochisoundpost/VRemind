import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Generates timeline entries for VRemind widgets by reading the cached snapshot
/// from `WidgetSnapshotStore` and refreshing on schedule or when reloaded by the host app.
public struct VRemindTimelineProvider {
    public typealias Entry = VRemindWidgetEntry

    public let store: WidgetSnapshotStoreProtocol

    public init(store: WidgetSnapshotStoreProtocol = WidgetSnapshotStore.shared) {
        self.store = store
    }

    /// Generates placeholder entry for widget galleries.
    public func placeholderEntry() -> VRemindWidgetEntry {
        .previewSample
    }

    /// Generates current snapshot entry for widget preview or immediate display.
    public func snapshotEntry(isPreview: Bool = false) -> VRemindWidgetEntry {
        if isPreview {
            return .previewSample
        }
        if let snapshot = store.readSnapshot() {
            return VRemindWidgetEntry(date: Date(), snapshot: snapshot, isPlaceholder: false)
        }
        return .fallback
    }

    #if canImport(WidgetKit)
    /// Builds timeline with next refresh interval policy (15 minutes).
    public func timelineEntries() -> Timeline<VRemindWidgetEntry> {
        let now = Date()
        let entry = snapshotEntry(isPreview: false)
        let refreshDate = Calendar.current.date(byAdding: .minute, value: 15, to: now) ?? now.addingTimeInterval(900)
        return Timeline(entries: [entry], policy: .after(refreshDate))
    }
    #endif
}

#if canImport(WidgetKit)
extension VRemindTimelineProvider: TimelineProvider {
    public func placeholder(in context: Context) -> VRemindWidgetEntry {
        placeholderEntry()
    }

    public func getSnapshot(in context: Context, completion: @escaping (VRemindWidgetEntry) -> Void) {
        completion(snapshotEntry(isPreview: context.isPreview))
    }

    public func getTimeline(in context: Context, completion: @escaping (Timeline<VRemindWidgetEntry>) -> Void) {
        completion(timelineEntries())
    }
}
#endif
