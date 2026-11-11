import AppKit
import SwiftUI

public struct ChannelRowView: View {
    public let channel: WatchedChannel
    public let status: StreamStatus
    public let onDelete: () -> Void

    public init(
        channel: WatchedChannel,
        status: StreamStatus,
        onDelete: @escaping () -> Void
    ) {
        self.channel = channel
        self.status = status
        self.onDelete = onDelete
    }

    public var isLive: Bool {
        if case .live = status {
            return true
        }
        return false
    }

    public var streamURL: URL? {
        switch status {
        case .live(let videoId, _, _), .upcoming(let videoId, _, _):
            if !videoId.isEmpty {
                return LinkOpener.videoURL(for: videoId)
            }
        case .offline, .unknown:
            break
        }
        let handle = channel.handle.hasPrefix("@") ? channel.handle : "@\(channel.handle)"
        let encodedHandle = handle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? handle
        return URL(string: "https://www.youtube.com/\(encodedHandle)/live")
    }

    public var body: some View {
        HStack(spacing: 10) {
            Button(action: {
                if let streamURL {
                    LinkOpener.open(streamURL)
                }
            }) {
                HStack(spacing: 10) {
                    ChannelAvatarView(url: channel.avatarURL, size: 36)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(channel.name)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.primary)
                                .lineLimit(1)

                            Text(channel.handle)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        statusSubtitleView
                    }

                    Spacer(minLength: 4)

                    if isLive {
                        StatusBadge(isLive: true)
                    }
                }
            }
            .buttonStyle(.plain)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove channel")
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var statusSubtitleView: some View {
        switch status {
        case .live(_, let title, let startedAt):
            VStack(alignment: .leading, spacing: 1) {
                if !title.isEmpty {
                    Text(title)
                        .font(.system(size: 11))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
                Text("Live for \(ElapsedTime.liveDuration(since: startedAt))")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Theme.live)
            }

        case .upcoming(_, let title, let scheduledStartTime):
            VStack(alignment: .leading, spacing: 1) {
                if !title.isEmpty {
                    Text(title)
                        .font(.system(size: 11))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
                Text(formatScheduledTime(scheduledStartTime))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.orange)
            }

        case .offline(let lastStreamedAt):
            Text(lastStreamedAt != nil ? "Last live: \(ElapsedTime.relative(from: lastStreamedAt))" : "Offline")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)

        case .unknown:
            Text("Offline")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }

    private func formatScheduledTime(_ date: Date?) -> String {
        guard let date else { return "Upcoming" }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = Calendar.current.isDateInToday(date) ? .none : .short
        return "Starts: \(formatter.string(from: date))"
    }
}
