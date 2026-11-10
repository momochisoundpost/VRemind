import SwiftUI

public struct ReplaysView: View {
    public let status: StreamStatus
    public let channelHandle: String
    public let replays: [ReplayVOD]

    private let columns = [
        GridItem(.adaptive(minimum: 220), spacing: 14)
    ]

    public init(status: StreamStatus, channelHandle: String, replays: [ReplayVOD]) {
        self.status = status
        self.channelHandle = channelHandle
        self.replays = replays
    }

    public static func sorted(_ replays: [ReplayVOD]) -> [ReplayVOD] {
        replays.sorted { $0.date > $1.date }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                liveBanner

                Text("Stream Archive")
                    .font(.system(size: 18, weight: .bold))

                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(Self.sorted(replays)) { replay in
                        VODCard(replay: replay)
                    }
                }
            }
            .padding(20)
        }
    }

    private var liveBanner: some View {
        HStack(spacing: 12) {
            StatusBadge(isLive: status.isLive)

            if status.isLive {
                Text(status.title ?? "Streaming live on YouTube")
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)

                Spacer()

                Button {
                    LinkOpener.open(status.watchURL(channelHandle: channelHandle))
                } label: {
                    Text("Watch Live ↗")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Theme.live)
                        )
                }
                .buttonStyle(.plain)
            } else {
                Text("Offline")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)

                Spacer()

                Button {
                    LinkOpener.open(status.watchURL(channelHandle: channelHandle))
                } label: {
                    Text("Channel ↗")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(status.isLive ? Theme.live.opacity(0.08) : Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(status.isLive ? Theme.live.opacity(0.3) : Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
}
