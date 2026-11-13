import SwiftUI
#if canImport(WidgetKit)
import WidgetKit
#endif
import VRemindKit

#if canImport(WidgetKit)
public struct VRemindWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    public let entry: VRemindWidgetEntry

    public init(entry: VRemindWidgetEntry) {
        self.entry = entry
    }

    public var body: some View {
        switch family {
        case .systemSmall:
            SmallHeroWidgetView(entry: entry)
        case .systemMedium:
            MediumWatchlistWidgetView(entry: entry)
        case .systemLarge, .systemExtraLarge:
            LargeDashboardWidgetView(entry: entry)
        @unknown default:
            SmallHeroWidgetView(entry: entry)
        }
    }
}

public struct VRemindWidget: Widget {
    public let kind: String = "VRemindWidget"

    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: VRemindTimelineProvider()) { entry in
            VRemindWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("VRemind")
        .description("Track your favorite VTubers and streamers live on YouTube and Twitch.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
public struct VRemindWidgetBundle: WidgetBundle {
    public init() {}

    public var body: some Widget {
        VRemindWidget()
    }
}
#endif
