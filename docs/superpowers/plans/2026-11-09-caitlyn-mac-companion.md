# Caitlyn Momochi Mac Companion (CaitlynSwift) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS desktop companion app for VTuber Caitlyn Momochi (@bukancaitlyn) featuring an ambient menu bar live checker, a stream archive shelf, a searchable Cait-pedia lore wiki, and a Clip Roulette spinner, with all links opening in the user's default browser.

**Architecture:** A native Swift 6 / SwiftUI application with a dual surface: a lightweight `MenuBarExtra` status popover and a `WindowGroup` main hub. Content is driven by a hybrid model with bundled seed data (`caitlyn_hub.json`) that asynchronously syncs against a remote GitHub Raw JSON, with live YouTube broadcast detection.

**Tech Stack:** macOS 14.0+, Swift 6.3+, SwiftUI, AppKit (`NSWorkspace`), Foundation (`URLSession`, `JSONDecoder`), Swift Testing / XCTest.

**Spec:** `docs/superpowers/specs/2026-11-09-caitlyn-mac-companion-design.md`

## Global Constraints
- Target platform is macOS 14.0+ (Sonoma / Sequoia) on both Apple Silicon and Intel.
- 100% native Swift/SwiftUI; zero WebKit (`WKWebView`) or Electron dependencies to guarantee <50 MB RAM footprint and zero battery drain.
- All external links (streams, VODs, clips) MUST open via `NSWorkspace.shared.open(_:)` in the system default browser.
- No user-configured API keys or Google Cloud tokens required.
- Soundboard and Tech Shed are explicitly excluded from this build.

## Review Focus
1. **Scheduled Stream False Positive**: YouTube channel `/live` redirecting to an upcoming waiting room video -> must verify `isLive == true` in parsed player response so scheduled streams do not trigger false "LIVE NOW" alerts.
2. **Offline / Network Outage Fallback**: Launching without network or when GitHub Raw is unreachable -> must seamlessly load the bundled `caitlyn_hub.json` without UI lockup or crashes.
3. **HTTP 429 / 500 Network Glitches**: `LiveStatusService` encountering rate limits or transport errors -> must retain the last verified `StreamStatus` and not flicker or crash.
4. **Empty Clip Roulette**: Syncing a config where `clips` is empty -> Clip Roulette must disable the button and show a graceful fallback message instead of throwing an index out of bounds error.
5. **Cait-pedia Search Special Characters**: Searching with regex characters (`[`, `*`, `\`) or empty strings in Cait-pedia -> must perform clean case-insensitive substring matching without crashing.

---

### Task 1: Swift Package Setup, Core Models & Seed Config

**Files:**
- Create: `Package.swift`
- Create: `Sources/CaitlynSwift/Models/StreamStatus.swift`
- Create: `Sources/CaitlynSwift/Models/LoreEntry.swift`
- Create: `Sources/CaitlynSwift/Models/ReplayVOD.swift`
- Create: `Sources/CaitlynSwift/Models/CuratedClip.swift`
- Create: `Sources/CaitlynSwift/Models/HubConfig.swift`
- Create: `Sources/CaitlynSwift/Resources/caitlyn_hub.json`
- Create: `Tests/CaitlynSwiftTests/ModelTests.swift`

**Interfaces:**
- Produces:
  - `struct StreamStatus: Sendable, Codable, Equatable`: `isLive: Bool`, `streamId: String?`, `title: String?`, `startedAt: Date?`, `lastStreamAt: Date?`
  - `struct LoreEntry: Identifiable, Sendable, Codable, Equatable`: `id: String`, `title: String`, `category: String`, `summary: String`, `tags: [String]`
  - `struct ReplayVOD: Identifiable, Sendable, Codable, Equatable`: `id: String`, `title: String`, `youtubeId: String`, `date: Date`, `duration: String`
  - `struct CuratedClip: Identifiable, Sendable, Codable, Equatable`: `id: String`, `title: String`, `youtubeUrl: String`
  - `struct HubConfig: Sendable, Codable, Equatable`: `version: Int`, `channelHandle: String`, `lore: [LoreEntry]`, `replays: [ReplayVOD]`, `clips: [CuratedClip]`

- [ ] **Step 1: Write failing model decode & validation tests**

```swift
// Tests/CaitlynSwiftTests/ModelTests.swift
import Testing
import Foundation
@testable import CaitlynSwift

@Suite struct ModelTests {
    @Test func testDecodeHubConfigFromSeedJSON() throws {
        guard let url = Bundle.module.url(forResource: "caitlyn_hub.json", withExtension: nil) else {
            Issue.record("caitlyn_hub.json missing from module resources")
            return
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let config = try decoder.decode(HubConfig.self, from: data)
        #expect(config.channelHandle == "@bukancaitlyn")
        #expect(!config.lore.isEmpty)
        #expect(!config.replays.isEmpty)
        #expect(!config.clips.isEmpty)
    }

    @Test func testStreamStatusUptimeCalculation() {
        let now = Date()
        let twoHoursAgo = now.addingTimeInterval(-7200)
        let status = StreamStatus(isLive: true, streamId: "test123", title: "Live", startedAt: twoHoursAgo, lastStreamAt: nil)
        #expect(status.uptimeString(relativeTo: now).contains("2h"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ModelTests`  
Expected: FAIL (missing package/models/resource)

- [ ] **Step 3: Implement `Package.swift`, Models, and `caitlyn_hub.json`**

Create `Package.swift` targeting macOS 14.0+, define models conforming to `Codable`, `Sendable`, `Identifiable`, and populate `caitlyn_hub.json` with initial Caitlyn lore (Witch era, Audio engineering, VTuber shift) and sample replays/clips.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ModelTests`  
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/ Tests/
git commit -m "feat: setup package structure, core models, and seed JSON"
```

---

### Task 2: Config Sync Service with Offline Fallback

**Files:**
- Create: `Sources/CaitlynSwift/Services/ConfigSyncService.swift`
- Create: `Tests/CaitlynSwiftTests/ConfigSyncServiceTests.swift`

**Interfaces:**
- Consumes: `HubConfig`
- Produces:
  - `@Observable final class ConfigSyncService: Sendable`
  - `func loadInitial() -> HubConfig`
  - `func sync(from url: URL) async throws -> HubConfig`

- [ ] **Step 1: Write failing tests for ConfigSyncService**

```swift
// Tests/CaitlynSwiftTests/ConfigSyncServiceTests.swift
import Testing
import Foundation
@testable import CaitlynSwift

@Suite struct ConfigSyncServiceTests {
    @Test func testLoadInitialReturnsBundledSeedWhenNoCache() {
        let service = ConfigSyncService()
        let config = service.loadInitial()
        #expect(config.channelHandle == "@bukancaitlyn")
        #expect(config.lore.count > 0)
    }

    @Test func testSyncFallsBackToBundledOnNetworkError() async {
        let service = ConfigSyncService()
        let invalidURL = URL(string: "https://127.0.0.1:9999/nonexistent.json")!
        let config = await service.syncWithFallback(from: invalidURL)
        #expect(config.channelHandle == "@bukancaitlyn")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ConfigSyncServiceTests`  
Expected: FAIL (`ConfigSyncService` not defined)

- [ ] **Step 3: Implement `ConfigSyncService`**

Implement `ConfigSyncService` using `URLSession.shared.data(from:)`, caching valid remote responses in `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)` with instant fallback to `Bundle.module` seed.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ConfigSyncServiceTests`  
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/CaitlynSwift/Services/ConfigSyncService.swift Tests/CaitlynSwiftTests/ConfigSyncServiceTests.swift
git commit -m "feat: implement ConfigSyncService with offline fallback"
```

---

### Task 3: YouTube Live Status Service

**Files:**
- Create: `Sources/CaitlynSwift/Services/LiveStatusService.swift`
- Create: `Tests/CaitlynSwiftTests/LiveStatusServiceTests.swift`

**Interfaces:**
- Consumes: `StreamStatus`
- Produces:
  - `@Observable final class LiveStatusService: Sendable`
  - `func parseLivePayload(html: String) -> (isLive: Bool, title: String?, videoId: String?, startedAt: Date?)`
  - `func checkLiveStatus(channelHandle: String) async -> StreamStatus`

- [ ] **Step 1: Write failing parser tests for live vs scheduled detection**

```swift
// Tests/CaitlynSwiftTests/LiveStatusServiceTests.swift
import Testing
import Foundation
@testable import CaitlynSwift

@Suite struct LiveStatusServiceTests {
    @Test func testParseActiveLiveStream() {
        let liveHTML = """
        <script>var ytInitialPlayerResponse = {"videoDetails":{"isLive":true,"title":"Hackintosh & Chat","videoId":"live123"},"microformat":{"playerMicroformatRenderer":{"liveBroadcastDetails":{"startTimestamp":"2026-11-09T20:00:00Z"}}}};<\/script>
        """
        let service = LiveStatusService()
        let parsed = service.parseLivePayload(html: liveHTML)
        #expect(parsed.isLive == true)
        #expect(parsed.videoId == "live123")
        #expect(parsed.title == "Hackintosh & Chat")
        #expect(parsed.startedAt != nil)
    }

    @Test func testParseScheduledWaitingRoomIsNotLive() {
        let scheduledHTML = """
        <script>var ytInitialPlayerResponse = {"videoDetails":{"isLive":false,"title":"Upcoming Stream","videoId":"sched456"},"microformat":{"playerMicroformatRenderer":{"liveBroadcastDetails":{"isLiveNow":false}}}};<\/script>
        """
        let service = LiveStatusService()
        let parsed = service.parseLivePayload(html: scheduledHTML)
        #expect(parsed.isLive == false)
    }

    @Test func testParseOfflineChannelPage() {
        let offlineHTML = "<html><body>Channel home</body></html>"
        let service = LiveStatusService()
        let parsed = service.parseLivePayload(html: offlineHTML)
        #expect(parsed.isLive == false)
        #expect(parsed.videoId == nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter LiveStatusServiceTests`  
Expected: FAIL (`LiveStatusService` not defined)

- [ ] **Step 3: Implement `LiveStatusService`**

Implement `parseLivePayload(html:)` using regex extraction of `ytInitialPlayerResponse` to detect `isLive` / `isLiveNow`, title, videoId, and startTimestamp; implement `checkLiveStatus(channelHandle:)` with `URLSession` fetching `https://www.youtube.com/@\(handle)/live`.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter LiveStatusServiceTests`  
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/CaitlynSwift/Services/LiveStatusService.swift Tests/CaitlynSwiftTests/LiveStatusServiceTests.swift
git commit -m "feat: implement LiveStatusService with active broadcast detection"
```

---

### Task 4: Reusable UI Components & External URL Opener

**Files:**
- Create: `Sources/CaitlynSwift/Views/Components/StatusBadge.swift`
- Create: `Sources/CaitlynSwift/Views/Components/VODCard.swift`
- Create: `Sources/CaitlynSwift/Views/Components/LoreCard.swift`
- Create: `Sources/CaitlynSwift/Utilities/LinkOpener.swift`
- Create: `Tests/CaitlynSwiftTests/LinkOpenerTests.swift`

**Interfaces:**
- Produces:
  - `struct LinkOpener`: `static func openYouTubeVideo(id: String) -> Bool`, `static func openURL(_ url: URL) -> Bool`
  - `struct StatusBadge: View`: Renders animated green/red pulsing dot with "LIVE NOW" or "OFFLINE"
  - `struct VODCard: View`: Thumbnail image, title, date, duration, and click-to-open action
  - `struct LoreCard: View`: Title, category badge, expandable summary, tag pills

- [ ] **Step 1: Write test for LinkOpener URL construction**

```swift
// Tests/CaitlynSwiftTests/LinkOpenerTests.swift
import Testing
import Foundation
@testable import CaitlynSwift

@Suite struct LinkOpenerTests {
    @Test func testYouTubeVideoURLGeneration() {
        let url = LinkOpener.videoURL(for: "dQw4w9WgXcQ")
        #expect(url.absoluteString == "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter LinkOpenerTests`  
Expected: FAIL

- [ ] **Step 3: Implement `LinkOpener` and SwiftUI component views**

Implement `LinkOpener` with `NSWorkspace.shared.open(url)`, and construct SwiftUI components `StatusBadge`, `VODCard`, and `LoreCard` with macOS native typography and Caitlyn's purple-themed accents.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter LinkOpenerTests`  
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/CaitlynSwift/Views/Components/ Sources/CaitlynSwift/Utilities/ Tests/CaitlynSwiftTests/LinkOpenerTests.swift
git commit -m "feat: add StatusBadge, VODCard, LoreCard, and LinkOpener"
```

---

### Task 5: Main Hub Views (Replays, Cait-pedia, Clip Roulette, Split Container)

**Files:**
- Create: `Sources/CaitlynSwift/Views/Main/ReplaysView.swift`
- Create: `Sources/CaitlynSwift/Views/Main/CaitPediaView.swift`
- Create: `Sources/CaitlynSwift/Views/Main/ClipRouletteView.swift`
- Create: `Sources/CaitlynSwift/Views/Main/MainHubView.swift`
- Create: `Tests/CaitlynSwiftTests/LoreSearchTests.swift`

**Interfaces:**
- Consumes: `HubConfig`, `LoreEntry`, `ReplayVOD`, `CuratedClip`, `LinkOpener`
- Produces:
  - `struct CaitPediaView: View`: Searchable list of lore with category filter picker
  - `struct ReplaysView: View`: Grid of `VODCard` items
  - `struct ClipRouletteView: View`: Interactive random clip picker button with rolling animation
  - `struct MainHubView: View`: `NavigationSplitView` with sidebar selecting between Live/Replays, Cait-pedia, and Clip Roulette

- [ ] **Step 1: Write failing tests for lore search and clip roulette selection logic**

```swift
// Tests/CaitlynSwiftTests/LoreSearchTests.swift
import Testing
import Foundation
@testable import CaitlynSwift

@Suite struct LoreSearchTests {
    @Test func testLoreSearchFiltering() {
        let entries = [
            LoreEntry(id: "1", title: "Retired Witch", category: "Lore", summary: "Used to cast spells", tags: ["witch"]),
            LoreEntry(id: "2", title: "OpenCore", category: "Tech", summary: "Bootloader for Hackintosh", tags: ["tech"])
        ]
        let filtered = CaitPediaView.filter(entries: entries, query: "witch", category: nil)
        #expect(filtered.count == 1)
        #expect(filtered.first?.id == "1")
    }

    @Test func testClipRoulettePicksElement() {
        let clips = [
            CuratedClip(id: "1", title: "Funny Moment", youtubeUrl: "https://youtu.be/1"),
            CuratedClip(id: "2", title: "Epic Win", youtubeUrl: "https://youtu.be/2")
        ]
        let picked = ClipRouletteView.pickRandomClip(from: clips)
        #expect(picked != nil)
        #expect(clips.contains(where: { $0.id == picked?.id }))
    }

    @Test func testClipRouletteEmptyListReturnsNil() {
        let empty: [CuratedClip] = []
        let picked = ClipRouletteView.pickRandomClip(from: empty)
        #expect(picked == nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter LoreSearchTests`  
Expected: FAIL

- [ ] **Step 3: Implement `ReplaysView`, `CaitPediaView`, `ClipRouletteView`, and `MainHubView`**

Implement views using SwiftUI `NavigationSplitView`, `@State` search query, and animated clip picker.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter LoreSearchTests`  
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/CaitlynSwift/Views/Main/ Tests/CaitlynSwiftTests/LoreSearchTests.swift
git commit -m "feat: implement ReplaysView, CaitPediaView, ClipRouletteView, and MainHubView"
```

---

### Task 6: Menu Bar Popover, App Lifecycle & AppKit Integration

**Files:**
- Create: `Sources/CaitlynSwift/Views/MenuBar/MenuBarStatusView.swift`
- Create: `Sources/CaitlynSwift/CaitlynSwiftApp.swift`
- Create: `Sources/CaitlynSwift/AppState.swift`

**Interfaces:**
- Consumes: `LiveStatusService`, `ConfigSyncService`, `StreamStatus`, `HubConfig`, `MainHubView`
- Produces:
  - `@Observable final class AppState: Sendable`: Coordinates live polling timer, config updates, and window presentation
  - `struct MenuBarStatusView: View`: Popover showing live status card, uptime, "Watch Stream ↗", and "Open Full App" button
  - `@main struct CaitlynSwiftApp: App`: SwiftUI `MenuBarExtra` and `WindowGroup` entry point

- [ ] **Step 1: Write integration test for AppState synchronization**

```swift
// Tests/CaitlynSwiftTests/AppStateTests.swift
import Testing
import Foundation
@testable import CaitlynSwift

@Suite struct AppStateTests {
    @Test func testInitialStateLoadsSeedConfig() {
        let appState = AppState()
        #expect(appState.config.channelHandle == "@bukancaitlyn")
        #expect(!appState.config.lore.isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AppStateTests`  
Expected: FAIL

- [ ] **Step 3: Implement `AppState`, `MenuBarStatusView`, and `CaitlynSwiftApp`**

Implement `AppState` with periodic timer (every 180s) checking live status, `MenuBarStatusView` popover with direct action to open stream in default browser, and `@main` app with `MenuBarExtra("Caitlyn", systemImage: ...)` and `WindowGroup(id: "main-hub")`.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test`  
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/CaitlynSwift/ AppState.swift CaitlynSwiftApp.swift Tests/
git commit -m "feat: implement AppState, MenuBarStatusView, and app entry point"
```
