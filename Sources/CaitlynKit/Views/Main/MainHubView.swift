import SwiftUI

public enum HubSection: String, CaseIterable, Identifiable, Sendable {
    case replays
    case caitpedia
    case roulette

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .replays: return "Live & Replays"
        case .caitpedia: return "Cait-pedia"
        case .roulette: return "Clip Roulette"
        }
    }

    public var symbolName: String {
        switch self {
        case .replays: return "play.rectangle"
        case .caitpedia: return "book"
        case .roulette: return "dice"
        }
    }
}

public struct MainHubView: View {
    @ObservedObject private var configService: ConfigSyncService
    @ObservedObject private var liveService: LiveStatusService
    @State private var selection: HubSection? = .replays

    public init(configService: ConfigSyncService, liveService: LiveStatusService) {
        self.configService = configService
        self.liveService = liveService
    }

    public var body: some View {
        NavigationView {
            List(HubSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.symbolName)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .frame(minWidth: 190)

            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 820, minHeight: 560)
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection ?? .replays {
        case .replays:
            ReplaysView(
                status: liveService.status,
                channelHandle: configService.config.channelHandle,
                replays: configService.config.replays
            )
        case .caitpedia:
            CaitPediaView(entries: configService.config.lore)
        case .roulette:
            ClipRouletteView(clips: configService.config.clips)
        }
    }
}
