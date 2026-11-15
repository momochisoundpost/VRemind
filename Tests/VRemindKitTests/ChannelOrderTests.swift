import Combine
import CoreGraphics
import Foundation
import Testing
import VRemindCore
@testable import VRemindKit

struct ChannelOrderTests {
    @Test func testExceedsDragThresholdRequiresAtLeastFivePoints() {
        #expect(ChannelOrderPolicy.exceedsDragThreshold(0.0) == false)
        #expect(ChannelOrderPolicy.exceedsDragThreshold(4.9) == false)
        #expect(ChannelOrderPolicy.exceedsDragThreshold(-4.9) == false)
        #expect(ChannelOrderPolicy.exceedsDragThreshold(CGFloat.nan) == false)
        #expect(ChannelOrderPolicy.exceedsDragThreshold(5.0) == true)
        #expect(ChannelOrderPolicy.exceedsDragThreshold(-5.0) == true)
        #expect(ChannelOrderPolicy.exceedsDragThreshold(18.5) == true)
    }

    @Test func testCalculateDragLayoutComputesTargetClampingAndSiblingShifts() {
        let heights: [CGFloat] = [50.0, 50.0, 50.0]

        let stepDown = ChannelOrderPolicy.calculateDragLayout(draggedIndex: 0, deltaY: 60.0, itemHeights: heights, itemSpacing: 0.0)
        #expect(stepDown.targetIndex == 1)
        #expect(stepDown.clampedDragTranslateY == 60.0)
        #expect(stepDown.itemTranslateY == [60.0, -50.0, 0.0])

        let stepClamped = ChannelOrderPolicy.calculateDragLayout(draggedIndex: 0, deltaY: 500.0, itemHeights: heights, itemSpacing: 0.0)
        #expect(stepClamped.targetIndex == 2)
        #expect(stepClamped.clampedDragTranslateY == 100.0)
        #expect(stepClamped.itemTranslateY == [100.0, -50.0, -50.0])

        let stepUp = ChannelOrderPolicy.calculateDragLayout(draggedIndex: 2, deltaY: -60.0, itemHeights: heights, itemSpacing: 0.0)
        #expect(stepUp.targetIndex == 1)
        #expect(stepUp.clampedDragTranslateY == -60.0)
        #expect(stepUp.itemTranslateY == [0.0, 50.0, -60.0])

        let tallRowStep = ChannelOrderPolicy.calculateDragLayout(draggedIndex: 0, deltaY: 50.0, itemHeights: [70.0, 50.0], itemSpacing: 0.0)
        #expect(tallRowStep.targetIndex == 1)
        #expect(tallRowStep.clampedDragTranslateY == 50.0)
        #expect(tallRowStep.itemTranslateY == [50.0, -70.0])

        let spacedStep = ChannelOrderPolicy.calculateDragLayout(draggedIndex: 0, deltaY: 60.0, itemHeights: [50.0, 50.0], itemSpacing: 4.0)
        #expect(spacedStep.targetIndex == 1)
        #expect(spacedStep.clampedDragTranslateY == 54.0)
        #expect(spacedStep.itemTranslateY == [54.0, -54.0])
    }

    @Test func testReorderSectionItemsMovesSafelyAndHandlesOutOfBounds() {
        let a = WatchedChannel(id: "youtube:@a", platform: .youtube, name: "A", handle: "@a")
        let b = WatchedChannel(id: "youtube:@b", platform: .youtube, name: "B", handle: "@b")
        let c = WatchedChannel(id: "youtube:@c", platform: .youtube, name: "C", handle: "@c")
        let list = [a, b, c]

        let moved = ChannelOrderPolicy.reorderSectionItems(list, fromIndex: 2, toIndex: 0)
        #expect(moved.map(\.id) == ["youtube:@c", "youtube:@a", "youtube:@b"])
        #expect(ChannelOrderPolicy.reorderSectionItems(list, fromIndex: 1, toIndex: 1).map(\.id) == list.map(\.id))
        #expect(ChannelOrderPolicy.reorderSectionItems(list, fromIndex: -1, toIndex: 1).map(\.id) == list.map(\.id))
        #expect(ChannelOrderPolicy.reorderSectionItems(list, fromIndex: 0, toIndex: 99).map(\.id) == list.map(\.id))
    }

    @Test func testReorderWatchlistSlotsPreservesInterleavedPositionsAndLegacyIds() {
        let live1 = WatchedChannel(id: "youtube:@live1", platform: .youtube, name: "Live 1", handle: "@live1")
        let off1 = WatchedChannel(id: "@legacy1", platform: .youtube, name: "Off 1", handle: "@legacy1")
        let live2 = WatchedChannel(id: "twitch:live2", platform: .twitch, name: "Live 2", handle: "live2")
        let off2 = WatchedChannel(id: "youtube:@off2", platform: .youtube, name: "Off 2", handle: "@off2")
        let off3 = WatchedChannel(id: "twitch:off3", platform: .twitch, name: "Off 3", handle: "off3")

        let channels = [live1, off1, live2, off2, off3]
        let reordered = ChannelOrderPolicy.reorderWatchlistSlots(
            channels: channels,
            orderedSectionIds: ["twitch:off3", "youtube:@legacy1", "youtube:@off2"]
        )

        #expect(reordered.map(\.id) == [
            "youtube:@live1",
            "twitch:off3",
            "twitch:live2",
            "@legacy1",
            "youtube:@off2"
        ])
    }

    @Test @MainActor func testChannelStoreReorderSectionPersistsAndSkipsNoOpSaves() {
        let defaults = makeTestDefaults()
        let store = ChannelStore(userDefaults: defaults)
        store.addChannel(handle: "@one", name: "One")
        store.addChannel(handle: "@two", name: "Two")

        var publishCount = 0
        var cancellables = Set<AnyCancellable>()
        store.$channels
            .dropFirst()
            .sink { _ in publishCount += 1 }
            .store(in: &cancellables)

        // Unchanged order -> no publish
        let currentIds = store.channels.map(\.id)
        store.reorderSection(orderedSectionIds: currentIds)
        #expect(publishCount == 0)

        // Swap @two ahead of @one -> publishes once and persists to UserDefaults
        store.reorderSection(orderedSectionIds: ["youtube:@two", "youtube:@one", "youtube:@bukancaitlyn"])
        #expect(publishCount == 1)
        #expect(store.channels.map(\.id) == ["youtube:@two", "youtube:@one", "youtube:@bukancaitlyn"])

        let reloaded = ChannelStore(userDefaults: defaults)
        #expect(reloaded.channels.map(\.id) == ["youtube:@two", "youtube:@one", "youtube:@bukancaitlyn"])
    }
}
