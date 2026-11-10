import Foundation
import Testing
@testable import CaitlynKit

struct HubLogicTests {
    @Test func filterByQuery() {
        let seed = HubConfig.loadBundledSeed()
        let results = CaitPediaView.filter(entries: seed.lore, query: "WITCH", category: nil)
        #expect(results.count >= 3)
        for entry in results {
            let matchesTitle = entry.title.range(of: "witch", options: [.caseInsensitive, .diacriticInsensitive]) != nil
            let matchesSummary = entry.summary.range(of: "witch", options: [.caseInsensitive, .diacriticInsensitive]) != nil
            let matchesTag = entry.tags.contains {
                $0.range(of: "witch", options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
            #expect(matchesTitle || matchesSummary || matchesTag)
        }
    }

    @Test func whitespaceQueryReturnsAll() {
        let seed = HubConfig.loadBundledSeed()
        let results = CaitPediaView.filter(entries: seed.lore, query: "   ", category: nil)
        #expect(results.count == 8)
    }

    @Test func regexCharactersAreLiteral() {
        let seed = HubConfig.loadBundledSeed()
        let results = CaitPediaView.filter(entries: seed.lore, query: "[*\\", category: nil)
        #expect(results.isEmpty)
    }

    @Test func filterByCategory() {
        let seed = HubConfig.loadBundledSeed()
        let results = CaitPediaView.filter(entries: seed.lore, query: "", category: "Chat Memes")
        #expect(results.count == 2)
    }

    @Test func categoriesInOrder() {
        let seed = HubConfig.loadBundledSeed()
        let categories = CaitPediaView.categories(in: seed.lore)
        #expect(categories == ["Witch Era", "Audio Engineer Era", "VTuber Shenanigans", "Chat Memes"])
    }

    @Test func replaysSortedNewestFirst() {
        let seed = HubConfig.loadBundledSeed()
        let sorted = ReplaysView.sorted(seed.replays)
        #expect(sorted.first?.id == "S-rjK_FwjMU")
        #expect(sorted.last?.id == "PGzo5C_3rdQ")
    }

    @Test func emptyClipsReturnsNil() {
        var rng = SystemRandomNumberGenerator()
        let picked = ClipRouletteView.pickRandomClip(from: [], excluding: nil, using: &rng)
        #expect(picked == nil)
    }

    @Test func neverRepeatsLastWhenPossible() {
        var rng = SystemRandomNumberGenerator()
        let clips = [
            CuratedClip(id: "a", title: "Clip A", youtubeUrl: "https://youtu.be/a"),
            CuratedClip(id: "b", title: "Clip B", youtubeUrl: "https://youtu.be/b")
        ]
        for _ in 0..<50 {
            let picked = ClipRouletteView.pickRandomClip(from: clips, excluding: "a", using: &rng)
            #expect(picked?.id == "b")
        }
    }

    @Test func singleClipCanRepeat() {
        var rng = SystemRandomNumberGenerator()
        let clips = [
            CuratedClip(id: "only", title: "Only Clip", youtubeUrl: "https://youtu.be/only")
        ]
        let picked = ClipRouletteView.pickRandomClip(from: clips, excluding: "only", using: &rng)
        #expect(picked?.id == "only")
    }
}
