import SwiftUI

public struct ReplaysView: View {
    public static let defaultPageSize = 8

    public let status: StreamStatus
    public let channelHandle: String
    public let replays: [ReplayVOD]

    @State private var currentPage: Int = 0

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

    public static func totalPages(for totalCount: Int, pageSize: Int = defaultPageSize) -> Int {
        guard pageSize > 0, totalCount > 0 else { return 1 }
        return (totalCount + pageSize - 1) / pageSize
    }

    public static func page(
        of replays: [ReplayVOD],
        pageIndex: Int,
        pageSize: Int = defaultPageSize
    ) -> [ReplayVOD] {
        guard !replays.isEmpty, pageSize > 0 else { return [] }
        let pages = totalPages(for: replays.count, pageSize: pageSize)
        let clampedPage = min(max(0, pageIndex), pages - 1)
        let start = clampedPage * pageSize
        let end = min(start + pageSize, replays.count)
        return Array(replays[start..<end])
    }

    public var body: some View {
        let sortedReplays = Self.sorted(replays)
        let pageCount = Self.totalPages(for: sortedReplays.count)
        let clampedPage = min(max(0, currentPage), pageCount - 1)
        let currentItems = Self.page(of: sortedReplays, pageIndex: clampedPage)

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                liveBanner

                HStack(alignment: .firstTextBaseline) {
                    Text("Stream Archive")
                        .font(.system(size: 18, weight: .bold))

                    Text("(\(sortedReplays.count))")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)

                    Spacer()

                    if pageCount > 1 {
                        paginationBar(clampedPage: clampedPage, pageCount: pageCount)
                    }
                }

                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(currentItems) { replay in
                        VODCard(replay: replay)
                    }
                }

                if pageCount > 1 {
                    HStack {
                        Spacer()
                        paginationBar(clampedPage: clampedPage, pageCount: pageCount)
                        Spacer()
                    }
                    .padding(.top, 4)
                }
            }
            .padding(20)
        }
    }

    private func paginationBar(clampedPage: Int, pageCount: Int) -> some View {
        HStack(spacing: 6) {
            Button {
                currentPage = max(0, clampedPage - 1)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Prev")
                        .font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
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
            .disabled(clampedPage == 0)
            .opacity(clampedPage == 0 ? 0.45 : 1.0)

            ForEach(0..<pageCount, id: \.self) { index in
                let isSelected = index == clampedPage
                Button {
                    currentPage = index
                } label: {
                    Text("\(index + 1)")
                        .font(.system(size: 12, weight: isSelected ? .bold : .medium, design: .monospaced))
                        .foregroundColor(isSelected ? .white : .primary)
                        .frame(minWidth: 26, minHeight: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(isSelected ? Theme.accent : Color(NSColor.controlBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .strokeBorder(
                                    isSelected ? Theme.accent : Color.secondary.opacity(0.25),
                                    lineWidth: 1
                                )
                        )
                }
                .buttonStyle(.plain)
            }

            Button {
                currentPage = min(pageCount - 1, clampedPage + 1)
            } label: {
                HStack(spacing: 4) {
                    Text("Next")
                        .font(.system(size: 12, weight: .medium))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
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
            .disabled(clampedPage >= pageCount - 1)
            .opacity(clampedPage >= pageCount - 1 ? 0.45 : 1.0)
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
