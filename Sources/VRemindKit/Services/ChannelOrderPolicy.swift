import CoreGraphics
import Foundation
import VRemindCore

public enum SectionKind: String, Equatable, Hashable, Sendable {
    case live
    case upcoming
    case offline
}

public struct DragLayoutStep: Equatable, Sendable {
    public let targetIndex: Int
    public let clampedDragTranslateY: CGFloat
    public let itemTranslateY: [CGFloat]

    public init(
        targetIndex: Int,
        clampedDragTranslateY: CGFloat,
        itemTranslateY: [CGFloat]
    ) {
        self.targetIndex = targetIndex
        self.clampedDragTranslateY = clampedDragTranslateY
        self.itemTranslateY = itemTranslateY
    }
}

public enum ChannelOrderPolicy: Sendable {
    public static let dragActivationThreshold: CGFloat = 5.0

    public static func exceedsDragThreshold(_ deltaY: CGFloat) -> Bool {
        !deltaY.isNaN && abs(deltaY) >= dragActivationThreshold
    }

    public static func calculateDragLayout(
        draggedIndex: Int,
        deltaY: CGFloat,
        itemHeights: [CGFloat],
        itemSpacing: CGFloat = 0.0
    ) -> DragLayoutStep {
        guard !itemHeights.isEmpty else {
            return DragLayoutStep(targetIndex: 0, clampedDragTranslateY: 0, itemTranslateY: [])
        }

        let count = itemHeights.count
        guard draggedIndex >= 0, draggedIndex < count else {
            return DragLayoutStep(
                targetIndex: 0,
                clampedDragTranslateY: 0,
                itemTranslateY: Array(repeating: 0, count: count)
            )
        }

        guard count > 1 else {
            return DragLayoutStep(targetIndex: 0, clampedDragTranslateY: 0, itemTranslateY: [0])
        }

        let spacing = max(0, itemSpacing)
        var tops = [CGFloat](repeating: 0, count: count)
        var centers = [CGFloat](repeating: 0, count: count)
        var cursorY: CGFloat = 0
        for index in 0..<count {
            let height = max(1, itemHeights[index])
            tops[index] = cursorY
            centers[index] = cursorY + (height / 2)
            cursorY += height + spacing
        }

        let totalHeight = cursorY - spacing
        let draggedHeight = max(1, itemHeights[draggedIndex])
        let minDelta = -tops[draggedIndex]
        let maxDelta = totalHeight - (tops[draggedIndex] + draggedHeight)
        let safeDelta: CGFloat = (deltaY.isNaN || deltaY.isInfinite) ? 0 : deltaY
        let clampedDelta = min(max(safeDelta, minDelta), maxDelta)

        let draggedTop = tops[draggedIndex] + clampedDelta
        let draggedBottom = draggedTop + draggedHeight

        var targetIndex = draggedIndex
        if clampedDelta > 0 {
            for index in (draggedIndex + 1)..<count {
                if draggedBottom >= centers[index] {
                    targetIndex = index
                } else {
                    break
                }
            }
        } else if clampedDelta < 0 {
            for index in stride(from: draggedIndex - 1, through: 0, by: -1) {
                if draggedTop <= centers[index] {
                    targetIndex = index
                } else {
                    break
                }
            }
        }

        var translates = [CGFloat](repeating: 0, count: count)
        translates[draggedIndex] = clampedDelta
        let shiftAmount = draggedHeight + spacing
        if targetIndex > draggedIndex {
            for index in (draggedIndex + 1)...targetIndex {
                translates[index] = -shiftAmount
            }
        } else if targetIndex < draggedIndex {
            for index in targetIndex..<draggedIndex {
                translates[index] = shiftAmount
            }
        }

        return DragLayoutStep(
            targetIndex: targetIndex,
            clampedDragTranslateY: clampedDelta,
            itemTranslateY: translates
        )
    }

    public static func reorderSectionItems<T>(
        _ items: [T],
        fromIndex: Int,
        toIndex: Int
    ) -> [T] {
        guard items.count > 1,
              fromIndex >= 0, fromIndex < items.count,
              toIndex >= 0, toIndex < items.count,
              fromIndex != toIndex else {
            return items
        }

        var reordered = items
        let moved = reordered.remove(at: fromIndex)
        reordered.insert(moved, at: toIndex)
        return reordered
    }

    public static func applySectionOrder(
        _ sections: MenuBarSections,
        kind: SectionKind,
        reorderedSection: [WatchedChannel]
    ) -> MenuBarSections {
        switch kind {
        case .live:
            return MenuBarSections(live: reorderedSection, upcoming: sections.upcoming, offline: sections.offline)
        case .upcoming:
            return MenuBarSections(live: sections.live, upcoming: reorderedSection, offline: sections.offline)
        case .offline:
            return MenuBarSections(live: sections.live, upcoming: sections.upcoming, offline: reorderedSection)
        }
    }

    public static func applyCustomOrder(
        _ sections: MenuBarSections,
        orderedIds: [String]
    ) -> MenuBarSections {
        let rankByKey = buildRankLookup(from: orderedIds)
        guard !rankByKey.isEmpty else {
            return sections
        }

        return MenuBarSections(
            live: sortSectionByRank(sections.live, rankByKey: rankByKey),
            upcoming: sortSectionByRank(sections.upcoming, rankByKey: rankByKey),
            offline: sortSectionByRank(sections.offline, rankByKey: rankByKey)
        )
    }

    public static func reorderWatchlistSlots(
        channels: [WatchedChannel],
        orderedSectionIds: [String]
    ) -> [WatchedChannel] {
        let rankByKey = buildRankLookup(from: orderedSectionIds)
        guard !rankByKey.isEmpty else {
            return channels
        }

        var slotIndices: [Int] = []
        var matched: [(rank: Int, originalIndex: Int, channel: WatchedChannel)] = []

        for (index, channel) in channels.enumerated() {
            if let rank = resolveRank(for: channel, rankByKey: rankByKey) {
                slotIndices.append(index)
                matched.append((rank: rank, originalIndex: index, channel: channel))
            }
        }

        guard slotIndices.count > 1 else {
            return channels
        }

        let sorted = matched.sorted { lhs, rhs in
            if lhs.rank != rhs.rank {
                return lhs.rank < rhs.rank
            }
            return lhs.originalIndex < rhs.originalIndex
        }

        var updated = channels
        for (slotPosition, targetChannelIndex) in slotIndices.enumerated() {
            updated[targetChannelIndex] = sorted[slotPosition].channel
        }
        return updated
    }

    private static func buildRankLookup(from orderedIds: [String]) -> [String: Int] {
        var rankByKey: [String: Int] = [:]
        for (rank, rawId) in orderedIds.enumerated() {
            let normalized = rawId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalized.isEmpty else { continue }
            if rankByKey[normalized] == nil {
                rankByKey[normalized] = rank
            }
            if !normalized.contains(":") {
                let prefixed = "youtube:\(normalized)"
                if rankByKey[prefixed] == nil {
                    rankByKey[prefixed] = rank
                }
            }
        }
        return rankByKey
    }

    private static func resolveRank(for channel: WatchedChannel, rankByKey: [String: Int]) -> Int? {
        let rawId = channel.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !rawId.isEmpty {
            if let rank = rankByKey[rawId] {
                return rank
            }
            if !rawId.contains(":") {
                let prefixed = "\(channel.platform.rawValue):\(rawId)"
                if let rank = rankByKey[prefixed] {
                    return rank
                }
            }
        }

        let handleKey = "\(channel.platform.rawValue):\(channel.handle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
        return rankByKey[handleKey]
    }

    private static func sortSectionByRank(
        _ items: [WatchedChannel],
        rankByKey: [String: Int]
    ) -> [WatchedChannel] {
        guard items.count > 1 else {
            return items
        }

        let indexed = items.enumerated().map { (offset: $0.offset, item: $0.element) }
        return indexed.sorted { lhs, rhs in
            let rankA = resolveRank(for: lhs.item, rankByKey: rankByKey) ?? Int.max
            let rankB = resolveRank(for: rhs.item, rankByKey: rankByKey) ?? Int.max
            if rankA != rankB {
                return rankA < rankB
            }
            return lhs.offset < rhs.offset
        }
        .map(\.item)
    }
}
