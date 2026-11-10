import Foundation
import Testing
@testable import CaitlynKit

struct ModelTests {
    @Test func seedDecodes() {
        let seed = HubConfig.loadBundledSeed()
        #expect(seed.channelHandle == "@bukancaitlyn")
        #expect(seed.lore.count == 8)
        #expect(seed.replays.count == 30)
        #expect(seed.clips.count == 5)
    }

    @Test func avatarURLDecodesFromSeed() {
        let seed = HubConfig.loadBundledSeed()
        #expect(seed.avatarURL?.absoluteString == "https://yt3.googleusercontent.com/4rJNGjXsRJD2IM3KUkspGsjCjdfO170tW7U36kdg_PqzytqnfB3LwdOsYfjRAP4idOr_kh8WEA=s160-c-k-c0x00ffffff-no-rj")
    }

    @Test func latestReplayDate() {
        let seed = HubConfig.loadBundledSeed()
        #expect(seed.latestReplayDate == ISO8601DateFormatter().date(from: "2026-11-05T12:00:00Z"))
    }

    @Test func roundTrip() throws {
        let seed = HubConfig.loadBundledSeed()
        #expect(try HubConfig.decode(from: seed.encoded()) == seed)
    }

    @Test func decodesFractionalSecondDates() throws {
        var json = String(decoding: try HubConfig.loadBundledSeed().encoded(), as: UTF8.self)
        json = json.replacingOccurrences(of: "2026-11-05T12:00:00Z", with: "2026-11-05T12:00:00.250Z")
        let config = try HubConfig.decode(from: Data(json.utf8))
        let expected = try #require(ISO8601DateFormatter().date(from: "2026-11-05T12:00:00Z"))
        #expect(config.latestReplayDate == expected.addingTimeInterval(0.25))
    }

    @Test func replayURLs() throws {
        let seed = HubConfig.loadBundledSeed()
        let replay = try #require(seed.replays.first { $0.id == "kjiDlqyM-IE" })
        #expect(replay.watchURL.absoluteString == "https://www.youtube.com/watch?v=kjiDlqyM-IE")
        #expect(replay.thumbnailURL.absoluteString == "https://i.ytimg.com/vi/kjiDlqyM-IE/mqdefault.jpg")
    }

    @Test func elapsedFormatting() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        #expect(ElapsedTime.short(from: start, to: start.addingTimeInterval(42 * 60)) == "42m")
        #expect(ElapsedTime.short(from: start, to: start.addingTimeInterval(2 * 3600 + 5 * 60)) == "2h 05m")
        #expect(ElapsedTime.short(from: start, to: start.addingTimeInterval(2 * 3600 + 5 * 60 + 59)) == "2h 05m")
        #expect(ElapsedTime.short(from: start, to: start.addingTimeInterval(3 * 86400 + 4 * 3600)) == "3d 4h")
        #expect(ElapsedTime.short(from: start, to: start.addingTimeInterval(3 * 86400 + 4 * 3600 + 50 * 60)) == "3d 4h")
        #expect(ElapsedTime.short(from: start, to: start.addingTimeInterval(-60)) == "0m")
    }

    @Test func watchURLFallsBackToLivePage() {
        #expect(StreamStatus.offline.watchURL(channelHandle: "@bukancaitlyn").absoluteString
                == "https://www.youtube.com/@bukancaitlyn/live")
        let live = StreamStatus(isLive: true, videoId: "abc", title: "Live", startedAt: nil)
        #expect(live.watchURL(channelHandle: "@bukancaitlyn").absoluteString
                == "https://www.youtube.com/watch?v=abc")
    }
}
