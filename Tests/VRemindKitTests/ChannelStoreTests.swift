import Foundation
import Testing
@testable import VRemindKit

struct ChannelStoreTests {
    @Test @MainActor func unlimitedWatchlistAdditionAndRemoval() async {
        let store = ChannelStore(userDefaults: makeTestDefaults())
        #expect(store.channels.count == 1) // Caitlyn default
        #expect(store.channels[0].handle == "@bukancaitlyn")

        let ch1 = store.addChannel(handle: "@vtuber1", name: nil, avatarURL: nil)
        let ch2 = store.addChannel(handle: "@vtuber2", name: nil, avatarURL: nil)
        let ch3 = store.addChannel(handle: "@vtuber3", name: nil, avatarURL: nil)
        let ch4 = store.addChannel(handle: "@vtuber4", name: nil, avatarURL: nil)

        #expect(ch1 != nil)
        #expect(ch2 != nil)
        #expect(ch3 != nil)
        #expect(ch4 != nil)
        #expect(store.channels.count == 5)

        store.removeChannel(id: "@vtuber2")
        #expect(store.channels.count == 4)
        #expect(!store.channels.contains { $0.id == "@vtuber2" })
    }

    @Test @MainActor func factoryResetRestoresDefaultState() async {
        let store = ChannelStore(userDefaults: makeTestDefaults())
        store.addChannel(handle: "@custom_oshi", name: "Custom", avatarURL: nil)
        store.removeChannel(id: "@bukancaitlyn")
        #expect(store.channels.count == 1)

        store.resetToDefaults()
        #expect(store.channels.count == 1)
        #expect(store.channels.first?.handle == "@bukancaitlyn")
        #expect(store.channels.first?.name == "Caitlyn Momochi")
    }

    @Test @MainActor func addChannelValidationAndDuplicates() async {
        let store = ChannelStore(userDefaults: makeTestDefaults())

        // Duplicate of default channel (case-insensitive)
        let dup1 = store.addChannel(handle: "@bukancaitlyn")
        #expect(dup1 == nil)
        let dup2 = store.addChannel(handle: "@BUKANCAITLYN")
        #expect(dup2 == nil)

        // Invalid handles
        let inv1 = store.addChannel(handle: "")
        #expect(inv1 == nil)
        let inv2 = store.addChannel(handle: "invalid handle with spaces")
        #expect(inv2 == nil)

        // URL normalization
        let added = store.addChannel(
            handle: "https://www.youtube.com/@new_streamer",
            name: "New Streamer",
            avatarURL: URL(string: "https://example.com/avatar.png")
        )
        #expect(added?.id == "@new_streamer")
        #expect(added?.handle == "@new_streamer")
        #expect(added?.name == "New Streamer")
        #expect(added?.avatarURL == URL(string: "https://example.com/avatar.png"))

        // Default name to handle when nil or empty
        let defaultName1 = store.addChannel(handle: "@no_name", name: nil)
        #expect(defaultName1?.name == "@no_name")

        let defaultName2 = store.addChannel(handle: "@empty_name", name: "   ")
        #expect(defaultName2?.name == "@empty_name")
    }

    @Test @MainActor func removeChannelCaseInsensitive() async {
        let store = ChannelStore(userDefaults: makeTestDefaults())
        store.addChannel(handle: "@test_channel")
        #expect(store.channels.contains { $0.id == "@test_channel" })

        store.removeChannel(id: "@TEST_CHANNEL")
        #expect(!store.channels.contains { $0.id == "@test_channel" })
    }

    @Test @MainActor func updateMetadata() async {
        let store = ChannelStore(userDefaults: makeTestDefaults())
        let originalAvatar = URL(string: "https://example.com/old.png")
        store.addChannel(handle: "@vtuber", name: "Old Name", avatarURL: originalAvatar)

        // Update name and avatar
        let newAvatar = URL(string: "https://example.com/new.png")
        store.updateMetadata(for: "@VTUBER", name: "New Name", avatarURL: newAvatar)

        let updated = store.channels.first { $0.id == "@vtuber" }
        #expect(updated?.name == "New Name")
        #expect(updated?.avatarURL == newAvatar)

        // Empty name after trimming does not overwrite existing name
        store.updateMetadata(for: "@vtuber", name: "  ", avatarURL: nil)
        let unchangedName = store.channels.first { $0.id == "@vtuber" }
        #expect(unchangedName?.name == "New Name")
        #expect(unchangedName?.avatarURL == newAvatar)

        // Non-existent channel id does not crash
        store.updateMetadata(for: "@unknown", name: "Something", avatarURL: nil)
    }

    @Test @MainActor func updateStatus() async {
        let store = ChannelStore(userDefaults: makeTestDefaults())
        store.addChannel(handle: "@vtuber")

        let started = Date(timeIntervalSince1970: 1700000000)
        store.updateStatus(
            for: "@VTUBER",
            status: .live(videoId: "vid_123", title: "Live Stream", startedAt: started),
            notifiedLiveId: "vid_123"
        )

        var channel = store.channels.first { $0.id == "@vtuber" }
        #expect(channel?.lastNotifiedVideoId == "vid_123")
        #expect(channel?.lastStreamedAt == started)

        // Offline status with lastStreamedAt updates timestamp
        let offlineStreamed = Date(timeIntervalSince1970: 1700010000)
        store.updateStatus(
            for: "@vtuber",
            status: .offline(lastStreamedAt: offlineStreamed)
        )
        channel = store.channels.first { $0.id == "@vtuber" }
        #expect(channel?.lastStreamedAt == offlineStreamed)

        // Upcoming status with notifiedUpcomingId
        store.updateStatus(
            for: "@vtuber",
            status: .upcoming(videoId: "vid_upc", title: "Upcoming", scheduledStartTime: nil),
            notifiedUpcomingId: "vid_upc"
        )
        channel = store.channels.first { $0.id == "@vtuber" }
        #expect(channel?.lastNotifiedUpcomingId == "vid_upc")
    }

    @Test @MainActor func persistenceAcrossStoreInstances() async {
        let defaults = makeTestDefaults()
        let store1 = ChannelStore(userDefaults: defaults)
        store1.addChannel(handle: "@persistent_vtuber", name: "Persistent")

        let store2 = ChannelStore(userDefaults: defaults)
        #expect(store2.channels.count == 2)
        #expect(store2.channels.contains { $0.id == "@persistent_vtuber" && $0.name == "Persistent" })
    }
}
