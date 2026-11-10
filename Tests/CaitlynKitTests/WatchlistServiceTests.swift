import Foundation
import Testing
@testable import CaitlynKit

@MainActor
struct WatchlistServiceTests {
    private func makeIsolatedDefaults() -> UserDefaults {
        let suiteName = "CaitlynWatchlistTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeService(
        defaults: UserDefaults? = nil,
        fetcher: LiveStatusService.Fetcher? = nil
    ) -> WatchlistService {
        let configService = ConfigSyncService(
            cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        return WatchlistService(
            configService: configService,
            userDefaults: defaults ?? makeIsolatedDefaults(),
            fetcher: fetcher ?? { _ in "<html><body>ytInitialData</body></html>" }
        )
    }

    @Test func pinnedChannelIsAlwaysSlotZero() {
        let service = makeService()
        #expect(service.channels.count == 1)
        let first = service.channels[0]
        #expect(first.name == "Caitlyn Momochi")
        #expect(first.handle == "@bukancaitlyn")
        #expect(first.id == "@bukancaitlyn")
        #expect(first.isPinned == true)
        #expect(first.avatarURL != nil)
    }

    @Test func cannotRemovePinnedChannel() {
        let service = makeService()
        #expect(service.removeChannel(id: "@bukancaitlyn") == false)
        #expect(service.channels.count == 1)
    }

    @Test func addsAndNormalizesCustomChannelsUpToCapOfThree() {
        let service = makeService()
        #expect(service.addChannel(name: "Kobo Kanaeru", handle: "kobokanaeru", avatarURL: nil) == true)
        #expect(service.channels.count == 2)
        #expect(service.channels[1].handle == "@kobokanaeru")
        #expect(service.channels[1].id == "@kobokanaeru")
        #expect(service.channels[1].isPinned == false)

        #expect(service.addChannel(name: "Ina", handle: "@ninomaeinanis", avatarURL: nil) == true)
        #expect(service.channels.count == 3)

        // 4th channel exceeds max 3 slots
        #expect(service.addChannel(name: "Fourth", handle: "@fourth", avatarURL: nil) == false)
        #expect(service.channels.count == 3)
    }

    @Test func rejectsDuplicateOrEmptyHandles() {
        let service = makeService()
        #expect(service.addChannel(name: "Caitlyn Clone", handle: "BukanCaitlyn", avatarURL: nil) == false)
        #expect(service.addChannel(name: "Empty", handle: "   ", avatarURL: nil) == false)
        #expect(service.addChannel(name: "OnlyAt", handle: "@", avatarURL: nil) == false)

        #expect(service.addChannel(name: "Kobo", handle: "@kobo", avatarURL: nil) == true)
        #expect(service.addChannel(name: "Kobo Again", handle: "KOBO", avatarURL: nil) == false)
        #expect(service.channels.count == 2)
    }

    @Test func persistsCustomChannelsInUserDefaults() {
        let defaults = makeIsolatedDefaults()
        let service1 = makeService(defaults: defaults)
        #expect(service1.addChannel(name: "Kobo Kanaeru", handle: "kobokanaeru", avatarURL: nil) == true)

        let service2 = makeService(defaults: defaults)
        #expect(service2.channels.count == 2)
        #expect(service2.channels[1].name == "Kobo Kanaeru")
        #expect(service2.channels[1].handle == "@kobokanaeru")

        #expect(service2.removeChannel(id: "@kobokanaeru") == true)
        let service3 = makeService(defaults: defaults)
        #expect(service3.channels.count == 1)
    }

    @Test func refreshesAllAndComputesIsAnyLive() async {
        let liveHTML = """
        <html><script>var ytInitialPlayerResponse = {"videoDetails":{"videoId":"live123","title":"Kobo Singing","isLive":true,"isUpcoming":false},"microformat":{"playerMicroformatRenderer":{"liveBroadcastDetails":{"isLiveNow":true,"startTimestamp":"2026-11-10T06:00:00Z"}}}};</script></html>
        """
        let offlineHTML = "<html><body>ytInitialData</body></html>"

        let service = makeService { url in
            if url.absoluteString.contains("@kobokanaeru") {
                return liveHTML
            }
            return offlineHTML
        }
        _ = service.addChannel(name: "Kobo Kanaeru", handle: "@kobokanaeru", avatarURL: nil)

        #expect(service.isAnyLive == false)
        await service.refreshAll()

        #expect(service.isAnyLive == true)
        #expect(service.statuses["@bukancaitlyn"]?.isLive == false)
        #expect(service.statuses["@kobokanaeru"]?.isLive == true)
        #expect(service.statuses["@kobokanaeru"]?.videoId == "live123")
        #expect(service.statuses["@kobokanaeru"]?.title == "Kobo Singing")
    }

    @Test func refreshesBackfillMissingCustomChannelAvatar() async {
        let htmlWithAvatar = """
        <html><head><meta property="og:image" content="https://yt3.googleusercontent.com/kobo_avatar=s160-c-k-c0x00ffffff-no-rj"></head><body>ytInitialData</body></html>
        """
        let service = makeService { _ in htmlWithAvatar }
        #expect(service.addChannel(name: "Kobo Kanaeru", handle: "@kobokanaeru", avatarURL: nil) == true)
        #expect(service.channels[1].avatarURL == nil)

        await service.refreshAll()
        #expect(service.channels[1].avatarURL?.absoluteString == "https://yt3.googleusercontent.com/kobo_avatar=s160-c-k-c0x00ffffff-no-rj")
    }
}
