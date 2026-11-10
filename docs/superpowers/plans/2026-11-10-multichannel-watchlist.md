# Multi-VTuber Watchlist & Channel Avatars Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (or superpowers:subagent-driven-development) to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the Caitlyn Momochi Mac companion app with channel profile pictures and a multi-VTuber watchlist (max 3 slots) in the menu bar popover, alerting the user whenever any tracked VTuber goes live.

**Architecture:**
- Slot 1 is permanently pinned to Caitlyn Momochi (sourced from `ConfigSyncService`).
- Slots 2 & 3 are user-configurable channels stored in `UserDefaults`.
- `WatchlistService` coordinates live checking for all tracked channels using `LivePageParser` without API keys.
- Menu bar icon alerts (`dot.radiowaves.left.and.right`) if `isAnyLive == true`.
- Popover dynamically stacks channel cards and auto-fits height using `.fittingSize`.
- All external stream links open in the user's default browser via `LinkOpener`.

**Tech Stack:** macOS 12.0 (Monterey+), Swift 6.3 toolchain (Swift 5 mode), SwiftUI + AppKit, Foundation (`URLSession`, `JSONDecoder`), Swift Testing via `scripts/test.sh`.

**Spec:** `docs/superpowers/specs/2026-11-10-multichannel-watchlist-design.md`

---

## Global Constraints
- Target platform: **macOS 12.0** (`platforms: [.macOS(.v12)]`). Do not use macOS 13+/14+ APIs (`MenuBarExtra`, `NavigationSplitView`, `@Observable`, Swift `Regex` literals).
- 100% native Swift/SwiftUI; zero WebKit, zero Electron, zero third-party dependencies.
- Build and test strictly through `scripts/test.sh` and `scripts/build-app.sh`.
- Maximum 3 VTuber slots total. Slot 1 is always Caitlyn Momochi.
- Preserve all existing tests and features (Cait-pedia, Stream Archives pagination, Clip Roulette).

---

## Tasks

### Task 1: Channel Avatar Model & Component
**Files:**
- Modify: `Sources/CaitlynKit/Models/HubConfig.swift`
- Modify: `Sources/CaitlynKit/Resources/caitlyn_hub.json`
- Create: `Sources/CaitlynKit/Views/Components/ChannelAvatarView.swift`
- Modify: `Tests/CaitlynKitTests/ModelTests.swift`

- [ ] **Step 1: Write failing test for `avatarURL` in `HubConfig`**
  - In `Tests/CaitlynKitTests/ModelTests.swift`, add test `avatarURLDecodesFromSeed()` expecting `seed.avatarURL` to match Caitlyn's official YouTube avatar URL.
  - Run `bash scripts/test.sh --filter avatarURLDecodesFromSeed` -> Verify failure (RED).

- [ ] **Step 2: Add `avatarURL` to `HubConfig` and `caitlyn_hub.json`**
  - In `Sources/CaitlynKit/Models/HubConfig.swift`, add `public let avatarURL: URL?`.
  - In `Sources/CaitlynKit/Resources/caitlyn_hub.json`, add `"avatarUrl": "https://yt3.googleusercontent.com/4rJNGjXsRJD2IM3KUkspGsjCjdfO170tW7U36kdg_PqzytqnfB3LwdOsYfjRAP4idOr_kh8WEA=s160-c-k-c0x00ffffff-no-rj"`.
  - Run `bash scripts/test.sh --filter avatarURLDecodesFromSeed` -> Verify pass (GREEN).

- [ ] **Step 3: Implement `ChannelAvatarView`**
  - In `Sources/CaitlynKit/Views/Components/ChannelAvatarView.swift`:
    - Takes `url: URL?`, `size: CGFloat = 36`, `fallbackSymbol: String = "sparkles"`.
    - Uses `AsyncImage(url: url)`:
      - `.success`: circular clipped image with subtle stroke border.
      - `.empty` / `.failure`: `Circle()` filled with `Theme.accent.opacity(0.18)` containing `Image(systemName: fallbackSymbol)`.
    - Fits Monterey (macOS 12.0) `AsyncImage`.

- [ ] **Step 4: Commit Task 1**
  - Run `bash scripts/test.sh` to ensure all tests pass.
  - Git commit: `feat: add channel avatar support and Caitlyn avatar asset`

---

### Task 2: WatchedChannel Model & WatchlistService
**Files:**
- Create: `Sources/CaitlynKit/Models/WatchedChannel.swift`
- Create: `Sources/CaitlynKit/Services/WatchlistService.swift`
- Create: `Tests/CaitlynKitTests/WatchlistServiceTests.swift`

- [ ] **Step 1: Write failing tests in `WatchlistServiceTests.swift`**
  - Test pinned channel: Slot 0 is always Caitlyn Momochi and `isPinned == true`.
  - Test cannot remove pinned channel: `removeChannel(id:)` returns `false` for Caitlyn.
  - Test add custom channel: Can add up to 2 custom channels with normalized `@` handle.
  - Test capacity cap: Adding a 4th channel returns `false` and does not add.
  - Test duplicate prevention: Adding an existing handle returns `false`.
  - Test `isAnyLive`: Returns `true` if any channel's status has `isLive == true`.
  - Test persistence: Custom channels survive across `WatchlistService` instances using the same `UserDefaults`.
  - Run `bash scripts/test.sh --filter WatchlistServiceTests` -> Verify build failure (RED).

- [ ] **Step 2: Implement `WatchedChannel` model**
  - In `Sources/CaitlynKit/Models/WatchedChannel.swift`:
    ```swift
    public struct WatchedChannel: Codable, Identifiable, Equatable, Sendable {
        public let id: String
        public var name: String
        public var handle: String
        public var avatarURL: URL?
        public var isPinned: Bool
        public init(name: String, handle: String, avatarURL: URL? = nil, isPinned: Bool = false) { ... }
    }
    ```
  - Normalize handle: automatically prepends `@` if missing; `id` is lowercase normalized handle.

- [ ] **Step 3: Implement `WatchlistService`**
  - In `Sources/CaitlynKit/Services/WatchlistService.swift`:
    - `@MainActor public final class WatchlistService: ObservableObject`
    - `@Published public private(set) var customChannels: [WatchedChannel] = []`
    - `@Published public private(set) var statuses: [String: StreamStatus] = [:]`
    - Injected dependencies: `configService: ConfigSyncService`, `userDefaults: UserDefaults = .standard`, `fetcher: LiveStatusService.Fetcher? = nil`.
    - Computed property `channels: [WatchedChannel]`: returns `[caitlynChannel] + customChannels` (max 3).
    - Computed property `isAnyLive: Bool`: checks `statuses.values.contains { $0.isLive }`.
    - Methods:
      - `addChannel(name: String, handle: String, avatarURL: URL?) -> Bool`
      - `removeChannel(id: String) -> Bool`
      - `refreshAll() async`: runs concurrent `fetcher` tasks for all channels in `channels`, parsing each with `LivePageParser.parse(html:)`.
  - Run `bash scripts/test.sh --filter WatchlistServiceTests` -> Verify pass (GREEN).

- [ ] **Step 4: Commit Task 2**
  - Git commit: `feat: implement WatchedChannel model and WatchlistService`

---

### Task 3: Watchlist Cards UI Components
**Files:**
- Create: `Sources/CaitlynKit/Views/Components/WatchlistChannelCard.swift`
- Create: `Sources/CaitlynKit/Views/Components/AddChannelCard.swift`
- Create: `Tests/CaitlynKitTests/WatchlistCardTests.swift`

- [ ] **Step 1: Write test for card status text and actions**
  - Verify status line calculation for custom channels (offline vs live).
  - Verify normalized handle display.
  - Run `bash scripts/test.sh --filter WatchlistCardTests` -> Verify failure (RED).

- [ ] **Step 2: Implement `WatchlistChannelCard`**
  - In `Sources/CaitlynKit/Views/Components/WatchlistChannelCard.swift`:
    - Displays `ChannelAvatarView(url: channel.avatarURL, size: 36)`.
    - Channel name, handle, and `StatusBadge(isLive: status.isLive)`.
    - If live: stream title (1 line) + uptime elapsed.
    - If offline: time since last stream (for Caitlyn) or "Offline".
    - "Watch Stream ↗" button opening `status.watchURL(channelHandle: channel.handle)` via `LinkOpener`.
    - If `!channel.isPinned`: small delete button (`xmark.circle`) calling `onRemove()`.
    - Border highlights with `Theme.live.opacity(0.3)` when live.

- [ ] **Step 3: Implement `AddChannelCard`**
  - In `Sources/CaitlynKit/Views/Components/AddChannelCard.swift`:
    - Collapsed state: clean dashed rounded rectangle button: `"+ Add VTuber (\(currentCount)/3)"`.
    - Expanded state: inline form with:
      - Handle `TextField("@handle", text: $handle)`
      - Name `TextField("Display Name", text: $name)`
      - Cancel and Add buttons.
      - Error message if handle is empty or already in list.
    - Calls `onAdd(name, handle)` on submit and collapses.

- [ ] **Step 4: Commit Task 3**
  - Run `bash scripts/test.sh` -> Verify pass (GREEN).
  - Git commit: `feat: create WatchlistChannelCard and AddChannelCard views`

---

### Task 4: Redesign `MenuBarStatusView` & Wire into `AppDelegate`
**Files:**
- Modify: `Sources/CaitlynKit/Views/MenuBar/MenuBarStatusView.swift`
- Modify: `Sources/CaitlynSwift/AppDelegate.swift`
- Modify: `Tests/CaitlynKitTests/MenuBarStatusTests.swift`

- [ ] **Step 1: Update `MenuBarStatusView` to use `WatchlistService`**
  - Update `MenuBarStatusView` initializer to take `watchlistService: WatchlistService` (and keep `configService`).
  - Layout:
    - Header: Companion title + active watchlist counter `(\(watchlistService.channels.count)/3)`.
    - `VStack(spacing: 10)`:
      - For each channel in `watchlistService.channels`:
        - `WatchlistChannelCard(channel: channel, status: watchlistService.statuses[channel.id] ?? .offline, onRemove: { watchlistService.removeChannel(id: channel.id) })`
      - If `watchlistService.channels.count < 3`:
        - `AddChannelCard(currentCount: watchlistService.channels.count, onAdd: { name, handle in watchlistService.addChannel(name: name, handle: handle) })`
    - Bottom action bar: "Open Full App" and "Quit".
    - Frame: width 320, `.fixedSize(horizontal: false, vertical: true)`.
  - Update `makePopover` factory method to bind to `watchlistService`.

- [ ] **Step 2: Update `AppDelegate`**
  - Replace standalone `liveService` with `watchlistService = WatchlistService(configService: configService)`.
  - In `setupPopover()`: pass `watchlistService` into `MenuBarStatusView.makePopover`.
  - In `observeStatus()`: observe `watchlistService.$statuses` and `watchlistService.$customChannels`:
    - Update status item button icon (`watchlistService.isAnyLive ? "dot.radiowaves.left.and.right" : "sparkles"`).
    - Update popover content size dynamically (`popover.contentSize = view.fittingSize`).
  - In `startPollTimer()` and sleep/wake notifications: call `await watchlistService.refreshAll()`.

- [ ] **Step 3: Update `MenuBarStatusTests`**
  - Verify `popoverContentHeightFitsCompactly()` with 1, 2, and 3 channels.
  - Run `bash scripts/test.sh --filter MenuBarStatusTests` -> Verify pass (GREEN).

- [ ] **Step 4: Commit Task 4**
  - Git commit: `feat: integrate multi-VTuber watchlist stack into menu bar popover`

---

### Task 5: Verification, Packaging & Documentation
**Files:**
- Modify: `README.md`
- Output: `build/CaitlynSwift.app`

- [ ] **Step 1: Run the full test suite**
  - Run `bash scripts/test.sh` -> Expect 40+ tests in 7 suites all passing with zero errors.

- [ ] **Step 2: Rebuild release `.app` bundle**
  - Run `bash scripts/build-app.sh` -> Build universal signed `build/CaitlynSwift.app`.
  - Verify plist lint and bundle structure.

- [ ] **Step 3: Update `README.md`**
  - Document the new 3-slot Multi-VTuber Watchlist feature and profile picture support.

- [ ] **Step 4: Commit Task 5**
  - Git commit: `docs: update README for multi-VTuber watchlist feature`
