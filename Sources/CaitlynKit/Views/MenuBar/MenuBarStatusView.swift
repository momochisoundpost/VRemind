import SwiftUI

public struct MenuBarStatusView: View {
    @ObservedObject private var configService: ConfigSyncService
    @ObservedObject private var liveService: LiveStatusService
    private let onOpenHub: () -> Void
    private let onQuit: () -> Void

    public init(
        configService: ConfigSyncService,
        liveService: LiveStatusService,
        onOpenHub: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.configService = configService
        self.liveService = liveService
        self.onOpenHub = onOpenHub
        self.onQuit = onQuit
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

    public var body: some View {
        let status = liveService.status
        let config = configService.config

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Theme.accent.opacity(0.18))
                        .frame(width: 36, height: 36)
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Theme.accent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Caitlyn Momochi")
                        .font(.system(size: 13, weight: .bold))
                    Text(config.channelHandle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                StatusBadge(isLive: status.isLive)
            }

            TimelineView(.periodic(from: .now, by: 60)) { context in
                VStack(alignment: .leading, spacing: 4) {
                    if status.isLive, let title = status.title, !title.isEmpty {
                        Text(title)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(2)
                    }
                    Text(
                        Self.statusLine(
                            status: status,
                            lastStreamAt: config.latestReplayDate,
                            now: context.date
                        )
                    )
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
                )
            }

            Button {
                LinkOpener.open(status.watchURL(channelHandle: config.channelHandle))
            } label: {
                Text("Watch Stream ↗")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(status.isLive ? Theme.live : Theme.accent)
                    )
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                Button {
                    onOpenHub()
                } label: {
                    Text("Open Full App")
                        .font(.system(size: 12, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(Color(NSColor.controlBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    onQuit()
                } label: {
                    Text("Quit")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(Color(NSColor.controlBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(width: 320)
    }
}
