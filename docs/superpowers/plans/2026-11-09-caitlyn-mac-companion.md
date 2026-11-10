# Caitlyn Momochi Mac Companion (CaitlynSwift) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A native macOS 12+ companion app for VTuber Caitlyn Momochi (@bukancaitlyn): a menu bar live indicator plus a main window with Replays, Cait-pedia and Clip Roulette. Every link opens in the default browser.

**Architecture:** Swift package with a `CaitlynKit` library (models, services, SwiftUI views) and a thin `CaitlynSwift` executable (AppKit shell: `NSStatusItem` + `NSPopover`, and an `NSWindow` hosting SwiftUI). The app starts from the bundled `caitlyn_hub.json`, then syncs a remote copy from GitHub Raw. Live status comes from parsing `youtube.com/@bukancaitlyn/live`.

**Tech Stack:** Swift 6.3 toolchain (Swift 5 language mode, tools-version 5.9), SwiftUI + AppKit, Foundation `URLSession`/`JSONDecoder`/`JSONSerialization`, Swift Testing. Only Xcode Command Line Tools are installed; there is no Xcode and no XCTest.

**Spec:** `docs/superpowers/specs/2026-11-09-caitlyn-mac-companion-design.md`

## Global Constraints
- Deployment target **macOS 12.0** (`platforms: [.macOS(.v12)]`). Do NOT use: `MenuBarExtra`, `NavigationSplitView`, `NavigationStack`, `openWindow`/`Window` scenes, `@Observable`, `Grid`, Swift `Regex` literals / `/.../` regex, `.scrollContentBackground`, or anything else marked macOS 13+. Use `ObservableObject`/`@Published`, `NavigationView`, `LazyVGrid`, `NSRegularExpression` or manual scanning.
- 100% native; no WebKit, no Electron, no third-party packages.
- All external links open via `NSWorkspace.shared.open(_:)` (through `LinkOpener`).
- No user API keys. Soundboard and Tech Shed are out of scope.
- **Build/test only through `scripts/test.sh`** (already committed). It handles the CLT `Testing.framework` paths and sandbox-safe caches; extra args pass through (`scripts/test.sh --filter ModelTests`). Plain `swift test` fails in this environment. For a build without tests, use the same env and flags that script sets, with `swift build`.
- Tests use Swift Testing (`import Testing`, `@Test`, `#expect`), `@testable import CaitlynKit`.
- Seed data `Sources/CaitlynKit/Resources/caitlyn_hub.json` is already committed with real content. Do not change its content; models must decode it as-is (ISO-8601 dates).
- Remote config URL constant: `https://raw.githubusercontent.com/Y2Karyl/CaitlynSwift/main/caitlyn_hub.json`, and only in `AppConstants`.
- Live poll interval: 180 seconds.

## Review Focus
1. **Scheduled waiting room**: `/live` resolves to an upcoming stream (`isUpcoming: true`, no `isLive: true`). It must count as not live. Owned by Task 3 test `scheduledStreamIsNotLive`.
2. **Consent/garbage page or network error**: the fetch returns an unrecognized page or throws. The last known status must stay; no flicker to offline. Owned by Task 3 tests `unrecognizedPageKeepsPreviousStatus` and `fetchErrorKeepsPreviousStatus`.
3. **Offline launch / bad remote JSON**: no network, HTTP 404, or remote JSON that doesn't decode. Keep the current config and leave the cache untouched. Owned by Task 2 tests.
4. **Empty clips**: if the synced config has `clips: []`, Roulette shows a message and the button is disabled. No crash. Owned by Task 5 test `emptyClipsReturnsNil`.
5. **Search input**: whitespace-only queries and regex metacharacters (`[`, `*`, `\`). Use plain case-insensitive substring matching. Owned by Task 5 tests.

---

### Task 1: Package, Models, Seed Loading

**Files:**
- Create: `Package.swift`
- Create: `Sources/CaitlynKit/Models/StreamStatus.swift`, `LoreEntry.swift`, `ReplayVOD.swift`, `CuratedClip.swift`, `HubConfig.swift`, `ElapsedTime.swift`
- Create: `Sources/CaitlynKit/AppConstants.swift`
- Create: `Sources/CaitlynSwift/main.swift` (stub: `import AppKit; import CaitlynKit; NSApplication.shared.run()` is acceptable; Task 6 replaces it)
- Test: `Tests/CaitlynKitTests/ModelTests.swift`

**Interfaces (Produces):**
- `Package.swift`: tools-version 5.9; `platforms: [.macOS(.v12)]`; library target `CaitlynKit` with `resources: [.process("Resources")]`; executable target `CaitlynSwift` depending on `CaitlynKit`; test target `CaitlynKitTests`.
- `public struct LoreEntry: Codable, Equatable, Identifiable` (`id, title, category, summary: String`, `tags: [String]`)
- `public struct ReplayVOD: Codable, Equatable, Identifiable` (`id, title, youtubeId: String`, `date: Date`, `duration: String`); `public var watchURL: URL` (`https://www.youtube.com/watch?v=<youtubeId>`); `public var thumbnailURL: URL` (`https://i.ytimg.com/vi/<youtubeId>/mqdefault.jpg`)
- `public struct CuratedClip: Codable, Equatable, Identifiable` (`id, title, youtubeUrl: String`); `public var url: URL?`
- `public struct HubConfig: Codable, Equatable` (`version: Int`, `channelHandle: String`, `lore: [LoreEntry]`, `replays: [ReplayVOD]`, `clips: [CuratedClip]`)
  - `public static func decode(from data: Data) throws -> HubConfig` (ISO-8601 dates)
  - `public func encoded() throws -> Data` (round-trips with `decode`)
  - `public var latestReplayDate: Date?` (max replay date)
  - `public static func bundledSeedURL() -> URL?`: first `Bundle.main.resourceURL/CaitlynSwift_CaitlynKit.bundle/caitlyn_hub.json` if it exists (the `.app` layout from Task 7), otherwise `Bundle.module.url(forResource: "caitlyn_hub", withExtension: "json")`
  - `public static func loadBundledSeed() -> HubConfig` (decodes the seed; `fatalError` with a clear message if missing, since that's a packaging bug)
- `public struct StreamStatus: Equatable` (`isLive: Bool`, `videoId: String?`, `title: String?`, `startedAt: Date?`); `public static let offline`; `public func watchURL(channelHandle: String) -> URL` (the video URL when live with an id, otherwise `https://www.youtube.com/<handle>/live`)
- `public enum ElapsedTime { public static func short(from: Date, to: Date) -> String }`. Format: under 1h → `"42m"`; under 24h → `"2h 05m"`; otherwise `"3d 4h"`. Negative intervals clamp to `"0m"`.
- `public enum AppConstants`: `channelHandle = "@bukancaitlyn"`, `remoteConfigURL: URL` (value in Global Constraints), `livePollInterval: TimeInterval = 180`

- [ ] **Step 1: Write failing tests** in `ModelTests.swift`:
  - `seedDecodes`: `HubConfig.loadBundledSeed()` has `channelHandle == "@bukancaitlyn"`, `lore.count == 8`, `replays.count == 8`, `clips.count == 5`.
  - `latestReplayDate`: equals `ISO8601DateFormatter().date(from: "2026-11-05T12:00:00Z")`.
  - `roundTrip`: `HubConfig.decode(from: seed.encoded()) == seed`.
  - `replayURLs`: replay with id `kjiDlqyM-IE` gives `watchURL.absoluteString == "https://www.youtube.com/watch?v=kjiDlqyM-IE"` and a thumbnail of `"https://i.ytimg.com/vi/kjiDlqyM-IE/mqdefault.jpg"`.
  - `elapsedFormatting`: 42 min → `"42m"`; 2h5m → `"2h 05m"`; 3d4h → `"3d 4h"`; negative → `"0m"`.
  - `watchURLFallsBackToLivePage`: `StreamStatus.offline.watchURL(channelHandle: "@bukancaitlyn").absoluteString == "https://www.youtube.com/@bukancaitlyn/live"`; a live status with `videoId "abc"` gives `"https://www.youtube.com/watch?v=abc"`.
- [ ] **Step 2:** `scripts/test.sh --filter ModelTests` → FAIL (types missing)
- [ ] **Step 3:** Implement the files above.
- [ ] **Step 4:** `scripts/test.sh` → all pass; `swift build` of the executable succeeds (via test.sh's build).
- [ ] **Step 5:** Commit `feat: package, models, and seed loading`

---

### Task 2: ConfigSyncService

**Files:**
- Create: `Sources/CaitlynKit/Services/ConfigSyncService.swift`
- Test: `Tests/CaitlynKitTests/ConfigSyncServiceTests.swift`

**Interfaces:**
- Consumes: `HubConfig.decode`, `encoded()`, `loadBundledSeed()`, `AppConstants.remoteConfigURL`
- Produces: `@MainActor public final class ConfigSyncService: ObservableObject`
  - `@Published public private(set) var config: HubConfig`
  - `public init(cacheDirectory: URL, remoteURL: URL = AppConstants.remoteConfigURL, session: URLSession = .shared)`. Synchronously loads `cacheDirectory/caitlyn_hub.json` if it decodes, otherwise the bundled seed. Never throws.
  - `public func sync() async`. Fetches `remoteURL`. If the response is an `HTTPURLResponse`, require status 200–299 (non-HTTP responses such as `file://` are accepted). Decode it; on success, write the cache atomically (create the directory if needed) and publish. On any failure, do nothing.
  - `public static func defaultCacheDirectory() -> URL` (Application Support/`CaitlynSwift`)

- [ ] **Step 1: Write failing tests** (each uses a fresh temp dir):
  - `loadsSeedWhenNoCache`: `config == HubConfig.loadBundledSeed()`
  - `prefersValidCache`: write a seed copy with `version = 99` to the cache file → `config.version == 99`
  - `corruptCacheFallsBackToSeed`: cache file containing `"not json"` → `config.version == 1`
  - `syncFromFileURLUpdatesAndCaches`: remote = `file://` temp JSON with `version = 7` → after `await sync()`, `config.version == 7` and the cache file decodes to version 7
  - `syncFailureKeepsConfigAndCache`: remote = `http://127.0.0.1:9/none.json` → config unchanged, cache file not created
  - `syncInvalidJSONKeepsConfig`: remote = `file://` with `{"oops":1}` → config unchanged
- [ ] **Step 2:** `scripts/test.sh --filter ConfigSyncServiceTests` → FAIL
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** `scripts/test.sh` → all pass
- [ ] **Step 5:** Commit `feat: config sync with cache and offline fallback`

---

### Task 3: Live Status Parsing and Service

**Files:**
- Create: `Sources/CaitlynKit/Services/LivePageParser.swift`
- Create: `Sources/CaitlynKit/Services/LiveStatusService.swift`
- Test: `Tests/CaitlynKitTests/LiveStatusTests.swift`

**Interfaces:**
- Consumes: `StreamStatus`, `AppConstants`
- Produces:
  - `public enum LivePageResult: Equatable { case live(videoId: String, title: String, startedAt: Date?); case notLive; case unrecognized }`
  - `public enum LivePageParser { public static func parse(html: String) -> LivePageResult }`. Rules:
    1. Find `ytInitialPlayerResponse = {`, extract the balanced JSON object by brace counting that respects JSON strings and escapes, then parse it with `JSONSerialization`.
    2. `.live` only if `videoDetails.isLive == true`, or `microformat.playerMicroformatRenderer.liveBroadcastDetails.isLiveNow == true`, **and** `videoDetails.isUpcoming != true`. `videoId`/`title` come from `videoDetails`. `startedAt` comes from `liveBroadcastDetails.startTimestamp` (ISO-8601, which may include fractional seconds or `+00:00`), otherwise nil.
    3. If a player response exists but isn't live → `.notLive`.
    4. No player response, but the HTML contains `ytInitialData` (a normal channel page) → `.notLive`.
    5. Anything else (consent page, empty, malformed JSON) → `.unrecognized`.
  - `@MainActor public final class LiveStatusService: ObservableObject`
    - `@Published public private(set) var status: StreamStatus` (starts `.offline`)
    - `public typealias Fetcher = @Sendable (URL) async throws -> String`
    - `public init(channelHandle: String = AppConstants.channelHandle, fetcher: Fetcher? = nil)`. The default fetcher uses `URLSession` with a desktop Safari `User-Agent` and `Accept-Language: en-US,en` on `https://www.youtube.com/<handle>/live`.
    - `public func refresh() async`: `.live` → set live status; `.notLive` → `.offline`; `.unrecognized` or a thrown error → keep the current status.

- [ ] **Step 1: Write failing tests** with HTML fixture strings built inline:
  - `activeLiveStream`: `isLive: true`, title `"Hackintosh & Chat"`, videoId `"live123"`, startTimestamp `"2026-11-09T20:00:00+00:00"` → `.live("live123", "Hackintosh & Chat", <that date>)`
  - `braceInsideStringDoesNotBreakExtraction`: title `"a } tricky { title"` → parses as live with that title
  - `scheduledStreamIsNotLive`: `isUpcoming: true`, `isLiveContent: true`, no `isLive` → `.notLive`
  - `endedStreamIsNotLive`: `isLive` absent, `isLiveContent: true` → `.notLive`
  - `channelPageIsNotLive`: `"<script>var ytInitialData = {};</script>"` → `.notLive`
  - `consentPageIsUnrecognized`: `"<html>Before you continue to YouTube</html>"` → `.unrecognized`
  - Service tests with a stub fetcher: live HTML → `status.isLive == true`, with videoId set; then `unrecognizedPageKeepsPreviousStatus` (still live); `fetchErrorKeepsPreviousStatus` (stub throws → still live); then channel-page HTML → `status == .offline`
- [ ] **Step 2:** `scripts/test.sh --filter LiveStatusTests` → FAIL
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** `scripts/test.sh` → all pass
- [ ] **Step 5:** Commit `feat: YouTube live status parser and service`

---

### Task 4: Theme, LinkOpener, Reusable Components

**Files:**
- Create: `Sources/CaitlynKit/Utilities/LinkOpener.swift`
- Create: `Sources/CaitlynKit/Views/Theme.swift`
- Create: `Sources/CaitlynKit/Views/Components/StatusBadge.swift`, `VODCard.swift`, `LoreCard.swift`
- Test: `Tests/CaitlynKitTests/LinkOpenerTests.swift`

**Interfaces (Produces):**
- `public enum LinkOpener { public static func videoURL(for youtubeId: String) -> URL; public static func open(_ url: URL) }`. `open` calls `NSWorkspace.shared.open`. `ReplayVOD.watchURL` should use `videoURL(for:)` so the format is defined once (refactor Task 1's implementation to call it).
- `public enum Theme`: `accent` (Caitlyn purple, e.g. `Color(red: 0.62, green: 0.36, blue: 0.95)`), `live` (red). Use system colors elsewhere so light and dark mode both work.
- `public struct StatusBadge: View` (`init(isLive: Bool)`). Pill reading `"LIVE NOW"` with a pulsing red dot, or `"OFFLINE"` in secondary color.
- `public struct VODCard: View` (`init(replay: ReplayVOD)`). `AsyncImage` 16:9 thumbnail with a placeholder, a 2-line title, and `date` (abbreviated) • `duration`. The whole card is a plain-style button that opens `replay.watchURL` via `LinkOpener`.
- `public struct LoreCard: View` (`init(entry: LoreEntry)`). Title, category capsule, and summary (collapsed to 2 lines; click toggles expansion), plus tag chips.

- [ ] **Step 1: Write failing test** `videoURLFormat`: `LinkOpener.videoURL(for: "42hstxcifYU").absoluteString == "https://www.youtube.com/watch?v=42hstxcifYU"`
- [ ] **Step 2:** `scripts/test.sh --filter LinkOpenerTests` → FAIL
- [ ] **Step 3:** Implement. Views must compile against macOS 12 (watch for 13+ modifiers).
- [ ] **Step 4:** `scripts/test.sh` → all pass, no availability errors
- [ ] **Step 5:** Commit `feat: link opener, theme, and reusable components`

---

### Task 5: Main Hub Views

**Files:**
- Create: `Sources/CaitlynKit/Views/Main/ReplaysView.swift`, `CaitPediaView.swift`, `ClipRouletteView.swift`, `MainHubView.swift`
- Test: `Tests/CaitlynKitTests/HubLogicTests.swift`

**Interfaces:**
- Consumes: `HubConfig`, `LoreEntry`, `ReplayVOD`, `CuratedClip`, `StreamStatus`, `ElapsedTime`, `LinkOpener`, `StatusBadge`, `VODCard`, `LoreCard`, `ConfigSyncService`, `LiveStatusService`
- Produces:
  - `CaitPediaView` (`init(entries: [LoreEntry])`). Search field (`.searchable` or a `TextField`) and a category picker (an "All" option plus categories).
    - `static func filter(entries: [LoreEntry], query: String, category: String?) -> [LoreEntry]`: trim the query; an empty query matches everything. Otherwise do case- and diacritic-insensitive substring matching (`range(of:options:)`, not regex) over title, summary and tags. Preserve the input order.
    - `static func categories(in entries: [LoreEntry]) -> [String]`: unique categories in first-appearance order
  - `ReplaysView` (`init(status: StreamStatus, channelHandle: String, replays: [ReplayVOD])`). A live banner at the top: when live, show `StatusBadge`, the title and a "Watch Live ↗" button; when offline, show "Offline". Below it, a `LazyVGrid` (adaptive, min 220) of `VODCard`s sorted newest first.
    - `static func sorted(_ replays: [ReplayVOD]) -> [ReplayVOD]` (date descending)
  - `ClipRouletteView` (`init(clips: [CuratedClip])`). A big "Spin" button that briefly cycles titles (~1s animation), lands on a pick, and shows it with an "Open ↗" button. With empty clips, show "No clips yet" and disable the button.
    - `static func pickRandomClip<G: RandomNumberGenerator>(from clips: [CuratedClip], excluding lastId: String?, using generator: inout G) -> CuratedClip?`: nil if empty; never returns `lastId` when more than one clip exists
  - `public enum HubSection: String, CaseIterable, Identifiable { case replays, caitpedia, roulette }`. Labels/symbols: "Live & Replays" `play.rectangle`, "Cait-pedia" `book`, "Clip Roulette" `dice`.
  - `public struct MainHubView: View` (`init(configService: ConfigSyncService, liveService: LiveStatusService)`). Both are `@ObservedObject`. Uses a `NavigationView` with a sidebar `List` (`.listStyle(.sidebar)`) of `HubSection`, with `replays` selected initially, and a detail area showing the chosen view. Minimum frame 820×560.

- [ ] **Step 1: Write failing tests**:
  - `filterByQuery`: query `"WITCH"` over the seed lore → every result's title, summary or tags contain "witch" case-insensitively, and the count is ≥ 3
  - `whitespaceQueryReturnsAll`: `"   "` → all 8
  - `regexCharactersAreLiteral`: `"[*\\"` → empty, no crash
  - `filterByCategory`: category `"Chat Memes"`, empty query → 2 entries
  - `categoriesInOrder`: seed → `["Witch Era", "Audio Engineer Era", "VTuber Shenanigans", "Chat Memes"]`
  - `replaysSortedNewestFirst`: the first item is `S-rjK_FwjMU` and the last is `PGzo5C_3rdQ`
  - `emptyClipsReturnsNil`: `pickRandomClip(from: [], excluding: nil, using: &rng) == nil`
  - `neverRepeatsLastWhenPossible`: 2 clips, exclude `"a"`, 50 iterations with `SystemRandomNumberGenerator` → always `"b"`
  - `singleClipCanRepeat`: 1 clip, exclude its own id → returns it
- [ ] **Step 2:** `scripts/test.sh --filter HubLogicTests` → FAIL
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** `scripts/test.sh` → all pass
- [ ] **Step 5:** Commit `feat: replays, cait-pedia, clip roulette, and main hub`

---

### Task 6: Menu Bar Popover and AppKit Shell

**Files:**
- Create: `Sources/CaitlynKit/Views/MenuBar/MenuBarStatusView.swift`
- Create: `Sources/CaitlynSwift/AppDelegate.swift`
- Modify: `Sources/CaitlynSwift/main.swift`
- Test: `Tests/CaitlynKitTests/MenuBarStatusTests.swift`

**Interfaces:**
- Consumes: everything above
- Produces:
  - `public struct MenuBarStatusView: View` (`init(configService:liveService:onOpenHub: @escaping () -> Void, onQuit: @escaping () -> Void)`). About 320pt wide. It contains:
    - a header ("Caitlyn Momochi" plus `@bukancaitlyn`, with `StatusBadge`)
    - a stream card (title when live, and the status line)
    - "Watch Stream ↗" (`LinkOpener.open(status.watchURL(channelHandle:))`)
    - "Open Full App" and "Quit"
    - The status line refreshes every 60s (`TimelineView(.periodic(from:by:))` is macOS 12+).
    - `static func statusLine(status: StreamStatus, lastStreamAt: Date?, now: Date) -> String`:
      - live with `startedAt` → `"Live for " + ElapsedTime.short(from: startedAt, to: now)`
      - live without `startedAt` → `"Live now"`
      - offline with `lastStreamAt` → `"Last stream " + ElapsedTime.short(...) + " ago"`
      - otherwise → `"Offline"`
  - `AppDelegate: NSObject, NSApplicationDelegate` (executable target):
    - Owns `ConfigSyncService(cacheDirectory: .defaultCacheDirectory())` and `LiveStatusService()`.
    - Creates an `NSStatusItem` (variable length). Its button image is the SF Symbol `sparkles`, as a template image, when offline. When live it is `dot.radiowaves.left.and.right` with `contentTintColor = .systemRed`. Update it by observing `liveService.$status` (Combine `sink`).
    - Clicking the button toggles an `NSPopover` (`.transient`) that hosts `MenuBarStatusView` in an `NSHostingController`.
    - "Open Full App" closes the popover and shows one reused `NSWindow` (titled "Caitlyn Momochi", `NSHostingView(rootView: MainHubView(...))`, centered, `isReleasedWhenClosed = false`), then calls `NSApp.activate(ignoringOtherApps: true)`.
    - On launch, call `Task { await configService.sync() }` and `await liveService.refresh()`, then start a 180s repeating `Timer` that refreshes live status.
    - Invalidate the timer on `NSWorkspace.screensDidSleepNotification`. On `screensDidWakeNotification`, refresh immediately and restart the timer.
  - `main.swift`: `let app = NSApplication.shared; let delegate = AppDelegate(); app.delegate = delegate; app.setActivationPolicy(.accessory); app.run()`

- [ ] **Step 1: Write failing tests** for `statusLine` (fixed `now`):
  - live, started 1h42m earlier → `"Live for 1h 42m"`
  - live, `startedAt` nil → `"Live now"`
  - offline, last stream 4d2h earlier → `"Last stream 4d 2h ago"`
  - offline, nil → `"Offline"`
- [ ] **Step 2:** `scripts/test.sh --filter MenuBarStatusTests` → FAIL
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** `scripts/test.sh` → all pass, and the `CaitlynSwift` executable builds
- [ ] **Step 5:** Commit `feat: menu bar popover and AppKit app shell`

---

### Task 7: `.app` Bundle Script

**Files:**
- Create: `scripts/build-app.sh`
- Create: `Resources/Info.plist` (template)
- Modify: `README.md` (create it: what the app is, `scripts/test.sh`, `scripts/build-app.sh`, how to edit `caitlyn_hub.json`, and the remote URL to publish)

**Interfaces (Produces):** `scripts/build-app.sh` → `build/CaitlynSwift.app`
- Use the same sandbox-safe env/flags as `scripts/test.sh`. Run `swift build -c release`.
- Try a universal binary: build with `--triple arm64-apple-macosx12.0` and `--triple x86_64-apple-macosx12.0`, then `lipo -create`. If either cross build fails, fall back to the host-arch binary and print a clear warning. Don't fail the script for that.
- Layout:
  - `Contents/MacOS/CaitlynSwift`
  - `Contents/Info.plist`
  - `Contents/Resources/CaitlynSwift_CaitlynKit.bundle` (copied from the build dir). This matches `HubConfig.bundledSeedURL()`'s first lookup.
- Info.plist values: `CFBundleIdentifier` `com.y2karyl.caitlynswift`, `CFBundleName`/`CFBundleDisplayName` `Caitlyn Companion`, `CFBundleExecutable` `CaitlynSwift`, `CFBundlePackageType` `APPL`, `CFBundleShortVersionString` `1.0.0`, `CFBundleVersion` `1`, `LSMinimumSystemVersion` `12.0`, `LSUIElement` `true`, `NSHighResolutionCapable` `true`.
- Ad-hoc sign: `codesign --force --deep --sign - build/CaitlynSwift.app`.

- [ ] **Step 1:** Write the script and plist.
- [ ] **Step 2:** Run `scripts/build-app.sh`. Expected: it exits 0; `plutil -lint build/CaitlynSwift.app/Contents/Info.plist` reports OK; `file build/CaitlynSwift.app/Contents/MacOS/CaitlynSwift` lists the arch(es); `build/CaitlynSwift.app/Contents/Resources/CaitlynSwift_CaitlynKit.bundle/caitlyn_hub.json` exists (the `.process` rule may flatten it; adjust `bundledSeedURL()` to the actual layout if it differs and add a test); `codesign --verify build/CaitlynSwift.app` passes.
- [ ] **Step 3:** `scripts/test.sh` still passes.
- [ ] **Step 4:** Commit `build: app bundle script and README`
