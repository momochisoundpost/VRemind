# VRemind Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transform the single-creator `CaitlynSwift` desktop companion into `VRemind`, a production-grade, highly reliable native macOS Monterey (12.0+) menu bar utility that pings desktop notifications when watched VTubers go live or schedule broadcasts.

**Architecture:** A native AppKit menu bar status item (`NSStatusItem` + `NSPopover`) backed by single-responsibility services (`ChannelStore`, `StreamMonitorService`, `NotificationService`, `PreferencesStore`) communicating via Swift Combine and `@MainActor` async/await. Purges all legacy Caitlyn-specific views/syncing, removes the 3-slot cap to support an unlimited watchlist with progressive metadata resolution, and introduces native `UNUserNotificationCenter` desktop alerts, an onboarding welcome window, and a multi-tab preferences panel.

**Tech Stack:** Swift 5.9, AppKit, SwiftUI, UserNotifications, ServiceManagement, Combine, XCTest. Zero external third-party dependencies.

**Spec:** [docs/superpowers/specs/2026-11-11-vremind-design.md](file:///Users/karyl/CaitDev/CaitlynSwift/docs/superpowers/specs/2026-11-11-vremind-design.md)

## Global Constraints

- Platform: macOS 12.0 (Monterey) and newer, universal binary (Apple Silicon and Intel).
- Language: 100% Swift 5.9 using Apple native frameworks (Foundation, AppKit, SwiftUI, UserNotifications, ServiceManagement).
- Zero third-party SPM or CocoaPods package dependencies.
- Build toolchain: Must build and test using standard Xcode Command Line Tools (`swift build`, `swift test`, `bash scripts/test.sh`, `bash scripts/build-app.sh`).
- Default example channel: Caitlyn Momochi (`@bukancaitlyn`) pre-seeded as an editable, removable starting example.
- Attribution copy in About: *"VRemind by Caitlyn Momochi, initially vibecoded for their Hackintosh video"*.

## Review Focus

1. **Handle normalization with URL or whitespace input**: Entering `"  @bukancaitlyn  "` or `"https://www.youtube.com/@bukancaitlyn"` normalizes cleanly to `"@bukancaitlyn"` without error. (Pinned to Task 2).
2. **Channel offline on first poll**: Adding an offline channel resolves display name and falls back gracefully to `.notLive` without throwing unrecognized HTML errors. (Pinned to Task 4).
3. **Live stream notification deduplication**: When videoId `"abc"` remains live across multiple 3-minute poll cycles, only one notification is fired. (Pinned to Task 6).
4. **Upcoming waiting room cancellation/transition**: When an upcoming stream starts or is removed, status transitions cleanly without zombie alerts. (Pinned to Task 4).
5. **Factory reset state cleanup**: Triggering factory reset wipes all persisted custom channels and notification IDs, restores default settings, and re-presents the onboarding window without crash. (Pinned to Task 3).

---

### Task 1: Repository Rebranding & Legacy Purge

**Files:**
- Create: `Sources/VRemind/main.swift`, `Sources/VRemind/AppDelegate.swift`
- Modify: `Package.swift`, `scripts/build-app.sh`, `scripts/test.sh`, `Resources/Info.plist`
- Delete: Legacy Caitlyn-specific files in `Sources/CaitlynKit/Models/` (`CuratedClip.swift`, `LoreEntry.swift`, `ReplayVOD.swift`, `HubConfig.swift`), `Resources/caitlyn_hub.json`, `Services/ConfigSyncService.swift`, and `Views/` (`Main/`, `Components/LoreCard.swift`, `Components/VODCard.swift`, `Components/EasterEggOverlayView.swift`).

**Interfaces:**
- Consumes: Existing SPM package structure.
- Produces: Renamed targets `VRemindKit`, `VRemind`, `VRemindKitTests`.

- [ ] **Step 1: Write the failing build check**

Verify package rename by checking target compilation:
`swift build --target VRemind`
Expected: FAIL (target `VRemind` not defined).

- [ ] **Step 2: Update `Package.swift` and directory structure**

Rename targets:
- `CaitlynKit` -> `VRemindKit` (folder: `Sources/VRemindKit`)
- `CaitlynSwift` -> `VRemind` (folder: `Sources/VRemind`)
- `CaitlynKitTests` -> `VRemindKitTests` (folder: `Tests/VRemindKitTests`)
Delete legacy Caitlyn lore, clip, VOD models, views, and `caitlyn_hub.json`.
Update `scripts/build-app.sh` and `scripts/test.sh` to reference `VRemind` and `VRemindKit`.
Update `Resources/Info.plist` bundle identifier to `com.caitlyn.vremind` and executable name to `VRemind`.

- [ ] **Step 3: Run build to verify clean compilation**

Run: `swift build`
Expected: PASS with 0 warnings.

- [ ] **Step 4: Commit**

```bash
git add Package.swift Sources/ Tests/ scripts/ Resources/
git commit -m "refactor: rebrand package to VRemind and purge legacy lore/VOD modules"
```

---

### Task 2: Data Models (`WatchedChannel`, `StreamStatus`, `AppSettings`)

**Files:**
- Create: `Sources/VRemindKit/Models/WatchedChannel.swift`, `Sources/VRemindKit/Models/StreamStatus.swift`, `Sources/VRemindKit/Models/AppSettings.swift`
- Test: `Tests/VRemindKitTests/ModelTests.swift`

**Interfaces:**
- Consumes: Foundation.
- Produces:
  ```swift
  public struct WatchedChannel: Codable, Identifiable, Equatable, Sendable {
      public let id: String
      public var name: String
      public let handle: String
      public var avatarURL: URL?
      public var lastNotifiedVideoId: String?
      public var lastNotifiedUpcomingId: String?
      public var lastStreamedAt: Date?
      public static func normalizeHandle(_ input: String) -> String?
  }
  public enum StreamStatus: Codable, Equatable, Sendable {
      case live(videoId: String, title: String, startedAt: Date?)
      case upcoming(videoId: String, title: String, scheduledStartTime: Date?)
      case offline(lastStreamedAt: Date?)
      case unknown
  }
  public struct AppSettings: Codable, Equatable, Sendable {
      public var launchAtLogin: Bool
      public var notifyOnLive: Bool
      public var notifyOnUpcoming: Bool
      public var playNotificationSound: Bool
      public var hasCompletedOnboarding: Bool
  }
  ```

- [ ] **Step 1: Write the failing tests**

```swift
func testNormalizeHandleVariants() {
    XCTAssertEqual(WatchedChannel.normalizeHandle("@bukancaitlyn"), "@bukancaitlyn")
    XCTAssertEqual(WatchedChannel.normalizeHandle("bukancaitlyn"), "@bukancaitlyn")
    XCTAssertEqual(WatchedChannel.normalizeHandle("  @bukancaitlyn  "), "@bukancaitlyn")
    XCTAssertEqual(WatchedChannel.normalizeHandle("https://www.youtube.com/@bukancaitlyn"), "@bukancaitlyn")
    XCTAssertNil(WatchedChannel.normalizeHandle(""))
}

func testWatchedChannelCodableRoundTrip() throws {
    let channel = WatchedChannel(
        id: "@bukancaitlyn",
        name: "Caitlyn Momochi",
        handle: "@bukancaitlyn",
        avatarURL: URL(string: "https://example.com/avatar.jpg"),
        lastNotifiedVideoId: "vid123",
        lastNotifiedUpcomingId: nil,
        lastStreamedAt: Date(timeIntervalSince1970: 1700000000)
    )
    let data = try JSONEncoder().encode(channel)
    let decoded = try JSONDecoder().decode(WatchedChannel.self, from: data)
    XCTAssertEqual(channel, decoded)
}
```

- [ ] **Step 2: Run test to verify failure**

Run: `swift test --filter ModelTests`
Expected: FAIL.

- [ ] **Step 3: Implement `WatchedChannel`, `StreamStatus`, and `AppSettings`**

Implement URL and `@` prefix stripping in `normalizeHandle`. Implement Codable compliance.

- [ ] **Step 4: Run test to verify pass**

Run: `swift test --filter ModelTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/VRemindKit/Models/ Tests/VRemindKitTests/ModelTests.swift
git commit -m "feat: implement VRemind data models and handle normalizer"
```

---

### Task 3: `ChannelStore` & `PreferencesStore`

**Files:**
- Create: `Sources/VRemindKit/Services/ChannelStore.swift`, `Sources/VRemindKit/Services/PreferencesStore.swift`
- Test: `Tests/VRemindKitTests/ChannelStoreTests.swift`, `Tests/VRemindKitTests/PreferencesStoreTests.swift`

**Interfaces:**
- Consumes: `WatchedChannel`, `StreamStatus`, `AppSettings`.
- Produces:
  ```swift
  @MainActor
  public final class ChannelStore: ObservableObject {
      @Published public private(set) var channels: [WatchedChannel]
      public func addChannel(handle: String, name: String?, avatarURL: URL?) -> WatchedChannel?
      public func removeChannel(id: String)
      public func updateMetadata(for id: String, name: String?, avatarURL: URL?)
      public func updateStatus(for id: String, status: StreamStatus, notifiedLiveId: String?, notifiedUpcomingId: String?)
      public func resetToDefaults()
  }
  @MainActor
  public final class PreferencesStore: ObservableObject {
      @Published public var settings: AppSettings
      public func resetToDefaults()
  }
  ```

- [ ] **Step 1: Write the failing tests**

```swift
func testUnlimitedWatchlistAdditionAndRemoval() async {
    let store = ChannelStore(userDefaults: makeTestDefaults())
    XCTAssertEqual(store.channels.count, 1) // Caitlyn default
    XCTAssertEqual(store.channels[0].handle, "@bukancaitlyn")
    
    let ch1 = store.addChannel(handle: "@vtuber1", name: nil, avatarURL: nil)
    let ch2 = store.addChannel(handle: "@vtuber2", name: nil, avatarURL: nil)
    let ch3 = store.addChannel(handle: "@vtuber3", name: nil, avatarURL: nil)
    let ch4 = store.addChannel(handle: "@vtuber4", name: nil, avatarURL: nil)
    XCTAssertEqual(store.channels.count, 5)
    
    store.removeChannel(id: "@vtuber2")
    XCTAssertEqual(store.channels.count, 4)
}

func testFactoryResetRestoresDefaultState() async {
    let store = ChannelStore(userDefaults: makeTestDefaults())
    store.addChannel(handle: "@custom_oshi", name: "Custom", avatarURL: nil)
    store.removeChannel(id: "@bukancaitlyn")
    XCTAssertEqual(store.channels.count, 1)
    
    store.resetToDefaults()
    XCTAssertEqual(store.channels.count, 1)
    XCTAssertEqual(store.channels.first?.handle, "@bukancaitlyn")
}
```

- [ ] **Step 2: Run test to verify failure**

Run: `swift test --filter ChannelStoreTests`
Expected: FAIL.

- [ ] **Step 3: Implement `ChannelStore` and `PreferencesStore`**

Back persistence by `UserDefaults` JSON encoding. Default seed includes `@bukancaitlyn` with name `"Caitlyn Momochi"`. Implement thread-safe publishing on `@MainActor`.

- [ ] **Step 4: Run test to verify pass**

Run: `swift test --filter ChannelStoreTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/VRemindKit/Services/ Tests/VRemindKitTests/
git commit -m "feat: implement ChannelStore and PreferencesStore with unlimited channels"
```

---

### Task 4: `LivePageParser` Enhancement (Upcoming Streams & Metadata)

**Files:**
- Modify: `Sources/VRemindKit/Services/LivePageParser.swift`
- Test: `Tests/VRemindKitTests/LivePageParserTests.swift`

**Interfaces:**
- Consumes: Raw HTML string.
- Produces:
  ```swift
  public enum LivePageResult: Equatable, Sendable {
      case live(videoId: String, title: String, startedAt: Date?)
      case upcoming(videoId: String, title: String, scheduledStartTime: Date?)
      case notLive(channelTitle: String?, avatarURL: URL?)
      case unrecognized
  }
  public enum LivePageParser {
      public static func parse(html: String) -> LivePageResult
      public static func extractAvatarURL(from html: String) -> URL?
      public static func extractChannelTitle(from html: String) -> String?
  }
  ```

- [ ] **Step 1: Write the failing tests**

```swift
func testParseUpcomingWaitingRoom() {
    let html = #"""
    ytInitialPlayerResponse = {"videoDetails":{"videoId":"upcoming123","title":"Karaoke Stream!","isUpcoming":true},"microformat":{"playerMicroformatRenderer":{"liveBroadcastDetails":{"startTimestamp":"2026-11-12T12:00:00Z"}}}}
    """#
    let result = LivePageParser.parse(html: html)
    if case .upcoming(let videoId, let title, let startTime) = result {
        XCTAssertEqual(videoId, "upcoming123")
        XCTAssertEqual(title, "Karaoke Stream!")
        XCTAssertNotNil(startTime)
    } else {
        XCTFail("Expected .upcoming, got \(result)")
    }
}

func testOfflineChannelReturnsMetadata() {
    let html = #"ytInitialPlayerResponse = {"videoDetails":{"videoId":"vod123","isLive":false,"isUpcoming":false,"author":"Test VTuber"}}"#
    let result = LivePageParser.parse(html: html)
    if case .notLive(let channelTitle, _) = result {
        XCTAssertEqual(channelTitle, "Test VTuber")
    } else {
        XCTFail("Expected .notLive with title, got \(result)")
    }
}
```

- [ ] **Step 2: Run test to verify failure**

Run: `swift test --filter LivePageParserTests`
Expected: FAIL.

- [ ] **Step 3: Implement upcoming stream and author/metadata parsing in `LivePageParser`**

Parse `isUpcoming` flag and `startTimestamp` from microformat renderer. Extract `author` or channel name from `videoDetails`.

- [ ] **Step 4: Run test to verify pass**

Run: `swift test --filter LivePageParserTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/VRemindKit/Services/LivePageParser.swift Tests/VRemindKitTests/LivePageParserTests.swift
git commit -m "feat: enhance LivePageParser to detect upcoming waiting rooms and channel metadata"
```

---

### Task 5: `NotificationService` (`UNUserNotificationCenter`)

**Files:**
- Create: `Sources/VRemindKit/Services/NotificationService.swift`
- Test: `Tests/VRemindKitTests/NotificationServiceTests.swift`

**Interfaces:**
- Consumes: `UserNotifications`, `AppKit`.
- Produces:
  ```swift
  @MainActor
  public protocol NotificationCenterProtocol: AnyObject {
      func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
      func add(_ request: UNNotificationRequest) async throws
      func getNotificationSettings() async -> UNNotificationSettings
  }
  @MainActor
  public final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
      public func requestAuthorization() async -> Bool
      public func notifyLive(channelName: String, title: String, videoId: String, playSound: Bool) async
      public func notifyUpcoming(channelName: String, title: String, videoId: String, playSound: Bool) async
  }
  ```

- [ ] **Step 1: Write the failing tests**

```swift
func testNotificationRequestPayloadConstruction() async throws {
    let mockCenter = MockNotificationCenter()
    let service = NotificationService(center: mockCenter)
    await service.notifyLive(channelName: "Caitlyn Momochi", title: "Late Night Chat", videoId: "xyz789", playSound: true)
    
    XCTAssertEqual(mockCenter.requests.count, 1)
    let request = mockCenter.requests[0]
    XCTAssertEqual(request.content.title, "Caitlyn Momochi")
    XCTAssertTrue(request.content.body.contains("🔴 LIVE:"))
    XCTAssertEqual(request.content.userInfo["videoId"] as? String, "xyz789")
}
```

- [ ] **Step 2: Run test to verify failure**

Run: `swift test --filter NotificationServiceTests`
Expected: FAIL.

- [ ] **Step 3: Implement `NotificationService`**

Implement `UNUserNotificationCenterDelegate` with `userNotificationCenter(_:didReceive:withCompletionHandler:)` to open `https://www.youtube.com/watch?v={videoId}` when notification banner is clicked. Implement live and upcoming request builders.

- [ ] **Step 4: Run test to verify pass**

Run: `swift test --filter NotificationServiceTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/VRemindKit/Services/NotificationService.swift Tests/VRemindKitTests/NotificationServiceTests.swift
git commit -m "feat: implement NotificationService with click-to-open stream handling"
```

---

### Task 6: `StreamMonitorService` (Throttled Background Polling)

**Files:**
- Create: `Sources/VRemindKit/Services/StreamMonitorService.swift`
- Test: `Tests/VRemindKitTests/StreamMonitorServiceTests.swift`

**Interfaces:**
- Consumes: `ChannelStore`, `PreferencesStore`, `NotificationService`, `LivePageParser`.
- Produces:
  ```swift
  @MainActor
  public final class StreamMonitorService: ObservableObject {
      @Published public private(set) var isRefreshing: Bool
      @Published public private(set) var statuses: [String: StreamStatus]
      public init(channelStore: ChannelStore, preferencesStore: PreferencesStore, notificationService: NotificationService, fetcher: @escaping (URL) async throws -> (Data, URLResponse))
      public func refreshAll() async
      public func startPolling()
      public func stopPolling()
  }
  ```

- [ ] **Step 1: Write the failing tests**

```swift
func testLiveDeduplicationDoesNotNotifyTwice() async {
    let channelStore = ChannelStore(userDefaults: makeTestDefaults())
    let prefs = PreferencesStore(userDefaults: makeTestDefaults())
    prefs.settings.notifyOnLive = true
    let mockNotifier = MockNotificationService()
    
    let service = StreamMonitorService(
        channelStore: channelStore,
        preferencesStore: prefs,
        notificationService: mockNotifier,
        fetcher: { _ in (makeLiveHTML(videoId: "stream1"), make200Response()) }
    )
    
    await service.refreshAll()
    XCTAssertEqual(mockNotifier.liveNotificationCount, 1)
    
    // Poll 2 with same video ID
    await service.refreshAll()
    XCTAssertEqual(mockNotifier.liveNotificationCount, 1) // Deduplicated!
}
```

- [ ] **Step 2: Run test to verify failure**

Run: `swift test --filter StreamMonitorServiceTests`
Expected: FAIL.

- [ ] **Step 3: Implement `StreamMonitorService`**

Implement batches of 3 channels with task groups. Check display sleep (`screensDidSleepNotification`) to pause polling and resume on wake. Update channel `lastStreamedAt` and metadata on offline results.

- [ ] **Step 4: Run test to verify pass**

Run: `swift test --filter StreamMonitorServiceTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/VRemindKit/Services/StreamMonitorService.swift Tests/VRemindKitTests/StreamMonitorServiceTests.swift
git commit -m "feat: implement StreamMonitorService with batch polling and deduplication"
```

---

### Task 7: `LaunchAtLoginHelper`

**Files:**
- Create: `Sources/VRemindKit/Utilities/LaunchAtLoginHelper.swift`
- Test: `Tests/VRemindKitTests/LaunchAtLoginHelperTests.swift`

**Interfaces:**
- Consumes: `ServiceManagement`, `Foundation`.
- Produces:
  ```swift
  public enum LaunchAtLoginHelper {
      public static var isEnabled: Bool { get }
      public static func setEnabled(_ enabled: Bool) -> Bool
  }
  ```

- [ ] **Step 1: Write the failing test**

```swift
func testLaunchAtLoginToggleState() {
    // Tests interface contract
    let initial = LaunchAtLoginHelper.isEnabled
    _ = LaunchAtLoginHelper.setEnabled(initial)
    XCTAssertEqual(LaunchAtLoginHelper.isEnabled, initial)
}
```

- [ ] **Step 2: Run test to verify failure**

Run: `swift test --filter LaunchAtLoginHelperTests`
Expected: FAIL.

- [ ] **Step 3: Implement `LaunchAtLoginHelper`**

Use `#available(macOS 13.0, *)` with `SMAppService.mainApp`. On macOS 12 fallback, execute AppleScript login item management via `NSAppleScript`.

- [ ] **Step 4: Run test to verify pass**

Run: `swift test --filter LaunchAtLoginHelperTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/VRemindKit/Utilities/LaunchAtLoginHelper.swift Tests/VRemindKitTests/LaunchAtLoginHelperTests.swift
git commit -m "feat: implement LaunchAtLoginHelper with Monterey AppleScript fallback"
```

---

### Task 8: Onboarding Welcome Window

**Files:**
- Create: `Sources/VRemindKit/Views/Onboarding/OnboardingView.swift`, `Sources/VRemind/OnboardingWindowController.swift`
- Test: `Tests/VRemindKitTests/OnboardingViewTests.swift`

**Interfaces:**
- Consumes: `ChannelStore`, `PreferencesStore`, `NotificationService`.
- Produces: `OnboardingWindowController.showIfNeeded(channelStore:preferencesStore:notificationService:)`.

- [ ] **Step 1: Write the failing test**

```swift
func testOnboardingCompletionMarksSettings() async {
    let prefs = PreferencesStore(userDefaults: makeTestDefaults())
    let store = ChannelStore(userDefaults: makeTestDefaults())
    let viewModel = OnboardingViewModel(channelStore: store, preferencesStore: prefs)
    
    XCTAssertFalse(prefs.settings.hasCompletedOnboarding)
    viewModel.customHandle = "@pekorach"
    viewModel.completeOnboarding()
    
    XCTAssertTrue(prefs.settings.hasCompletedOnboarding)
    XCTAssertTrue(store.channels.contains(where: { $0.handle == "@pekorach" }))
}
```

- [ ] **Step 2: Run test to verify failure**

Run: `swift test --filter OnboardingViewTests`
Expected: FAIL.

- [ ] **Step 3: Implement `OnboardingView` and `OnboardingWindowController`**

SwiftUI welcome view containing:
- App greeting and subtitle: *"Never miss a stream from your favorite VTuber"*.
- Channel handle text field with `@bukancaitlyn` pre-populated.
- "Enable Notifications" button with live authorization status.
- "Get Started" button that saves channel, updates `hasCompletedOnboarding = true`, and dismisses window.

- [ ] **Step 4: Run test to verify pass**

Run: `swift test --filter OnboardingViewTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/VRemindKit/Views/Onboarding/ Sources/VRemind/OnboardingWindowController.swift Tests/VRemindKitTests/OnboardingViewTests.swift
git commit -m "feat: implement first-run OnboardingView and window controller"
```

---

### Task 9: Preferences Window

**Files:**
- Create: `Sources/VRemindKit/Views/Preferences/PreferencesView.swift`, `Sources/VRemind/PreferencesWindowController.swift`
- Test: `Tests/VRemindKitTests/PreferencesViewTests.swift`

**Interfaces:**
- Consumes: `PreferencesStore`, `ChannelStore`, `LaunchAtLoginHelper`.
- Produces: `PreferencesWindowController.show(preferencesStore:channelStore:onFactoryReset:)`.

- [ ] **Step 1: Write the failing test**

```swift
func testFactoryResetActionClearsAll() {
    let prefs = PreferencesStore(userDefaults: makeTestDefaults())
    let store = ChannelStore(userDefaults: makeTestDefaults())
    store.addChannel(handle: "@extra", name: nil, avatarURL: nil)
    prefs.settings.notifyOnUpcoming = true
    
    let viewModel = PreferencesViewModel(preferencesStore: prefs, channelStore: store)
    viewModel.performFactoryReset()
    
    XCTAssertFalse(prefs.settings.hasCompletedOnboarding)
    XCTAssertFalse(prefs.settings.notifyOnUpcoming)
    XCTAssertEqual(store.channels.count, 1)
    XCTAssertEqual(store.channels[0].handle, "@bukancaitlyn")
}
```

- [ ] **Step 2: Run test to verify failure**

Run: `swift test --filter PreferencesViewTests`
Expected: FAIL.

- [ ] **Step 3: Implement `PreferencesView` with 3 Tabs**

- Tab 1: **General**: Launch at login toggle, Factory Reset with confirmation modal alert.
- Tab 2: **Notifications**: Checkboxes for Live alerts, Upcoming alerts, Sound alerts.
- Tab 3: **About**: Title, version, copy: *"VRemind by Caitlyn Momochi, initially vibecoded for their Hackintosh video"*, clickable links to YouTube and Twitter/X.

- [ ] **Step 4: Run test to verify pass**

Run: `swift test --filter PreferencesViewTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/VRemindKit/Views/Preferences/ Sources/VRemind/PreferencesWindowController.swift Tests/VRemindKitTests/PreferencesViewTests.swift
git commit -m "feat: implement Preferences window with General, Notifications, and About tabs"
```

---

### Task 10: Redesigned Menu Bar Popover & App Wiring

**Files:**
- Modify: `Sources/VRemindKit/Views/MenuBar/MenuBarStatusView.swift`, `Sources/VRemind/AppDelegate.swift`
- Create: `Sources/VRemindKit/Views/MenuBar/ChannelRowView.swift`, `Sources/VRemindKit/Views/MenuBar/AddChannelBarView.swift`
- Test: `Tests/VRemindKitTests/MenuBarViewTests.swift`

**Interfaces:**
- Consumes: `ChannelStore`, `StreamMonitorService`, `PreferencesWindowController`, `OnboardingWindowController`.
- Produces: Complete running `VRemind` menu bar application.

- [ ] **Step 1: Write the failing test**

```swift
func testMenuBarPopoverSectionSorting() {
    let liveStatus = StreamStatus.live(videoId: "1", title: "Live", startedAt: Date())
    let offlineStatus = StreamStatus.offline(lastStreamedAt: nil)
    let upcomingStatus = StreamStatus.upcoming(videoId: "2", title: "Later", scheduledStartTime: Date())
    
    let ch1 = WatchedChannel(id: "@a", name: "A", handle: "@a")
    let ch2 = WatchedChannel(id: "@b", name: "B", handle: "@b")
    let ch3 = WatchedChannel(id: "@c", name: "C", handle: "@c")
    
    let sections = MenuBarStatusViewModel.splitSections(
        channels: [ch1, ch2, ch3],
        statuses: ["@a": liveStatus, "@b": offlineStatus, "@c": upcomingStatus]
    )
    
    XCTAssertEqual(sections.live.count, 1)
    XCTAssertEqual(sections.upcoming.count, 1)
    XCTAssertEqual(sections.offline.count, 1)
}
```

- [ ] **Step 2: Run test to verify failure**

Run: `swift test --filter MenuBarViewTests`
Expected: FAIL.

- [ ] **Step 3: Implement redesigned `MenuBarStatusView` and wire `AppDelegate`**

- Header: App title "VRemind", active live badge, gear button (`⌘,`) to open Preferences, Quit button.
- Scrollable list partitioned into **LIVE NOW**, **UPCOMING**, and **OFFLINE** sections.
- Channel rows with avatar, stream status/title, elapsed time or scheduled time, and delete button.
- Bottom Bar: Quick-add field for `@handle` with inline validation.
- In `AppDelegate`: Initialize `ChannelStore`, `PreferencesStore`, `NotificationService`, and `StreamMonitorService`. Check `hasCompletedOnboarding` on launch and show `OnboardingWindowController` if false.

- [ ] **Step 4: Run test to verify pass**

Run: `swift test --filter MenuBarViewTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/VRemindKit/Views/MenuBar/ Sources/VRemind/AppDelegate.swift Tests/VRemindKitTests/MenuBarViewTests.swift
git commit -m "feat: implement redesigned menu bar popover and wire AppDelegate"
```

---

### Task 11: End-to-End Build, Test Suite & Release Packaging

**Files:**
- Modify: `README.md`, `scripts/build-app.sh`, `scripts/test.sh`

**Interfaces:**
- Consumes: All modules and targets.
- Produces: Verified `build/VRemind.app` bundle and passing tests.

- [ ] **Step 1: Run comprehensive automated test suite**

Run: `bash scripts/test.sh`
Expected: All tests PASS with 0 failures.

- [ ] **Step 2: Build release application bundle**

Run: `bash scripts/build-app.sh`
Expected: Creates `build/VRemind.app` signed and bundled with `Resources/Info.plist`.

- [ ] **Step 3: Verify app bundle structure**

Run: `ls -la build/VRemind.app/Contents/MacOS/VRemind`
Expected: Executable exists and is executable.

- [ ] **Step 4: Update `README.md` for VRemind**

Document VRemind features, build instructions, preferences, and Twitter/GitHub showcase overview.

- [ ] **Step 5: Commit**

```bash
git add README.md scripts/
git commit -m "chore: complete VRemind release packaging and documentation"
```
