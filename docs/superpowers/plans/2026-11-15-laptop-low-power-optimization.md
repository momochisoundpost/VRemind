# Laptop & Low Power Mode Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate random 60 fps offscreen celebration energy spikes, stop 3-minute no-op disk/WidgetKit wakeups, scale background polling across AC / Battery / Low Power Mode tiers on Efficiency cores, and run VRemind at macOS's lowest background scheduling priority whenever UI is closed.

**Architecture:** `PowerStateMonitor` resolves `PowerPolicy` tiers (`.normal` 180s/batch 3, `.battery` 360s/batch 2, `.lowPowerMode` 900s/batch 1 + paused animations + deferred update checks) from `ProcessInfo.isLowPowerModeEnabled` and `IOKit.ps` power sources. `ProcessPriorityManager` applies `PRIO_MAX` (`+20` nice) at launch and toggles `PRIO_DARWIN_BG` on whenever the active UI surface set (`.popover`, `.preferences`, `.onboarding`, `.updateAvailable`) is empty. `StreamMonitorService`, `ChannelStore`, `WidgetSnapshotStore`, and `RainbowStyle` gate offscreen/paused `TimelineView` animations and skip unchanged disk/WidgetKit writes while running network/parse passes inside `.background` QoS tasks.

**Tech Stack:** Swift 5.9+, macOS 12.0+ Monterey (`arm64` + `x86_64`), SwiftUI, AppKit, Combine, WidgetKit, `IOKit.ps`, `Darwin`, Swift Testing (`./scripts/test.sh`, `./scripts/build-app.sh`).

**Spec:** [docs/superpowers/specs/2026-11-15-laptop-low-power-optimization-design.md](file:///Users/karyl/CaitDev/CaitlynSwift/docs/superpowers/specs/2026-11-15-laptop-low-power-optimization-design.md)

## Global Constraints

- **Command Line Tools Only:** Everything must compile, pass tests (`bash scripts/test.sh`), and bundle `VRemind.app` + `VRemindWidget.appex` (`bash scripts/build-app.sh`) using only Xcode CLT on macOS 12.0+ (`arm64` + `x86_64`).
- **Apple SDK Frameworks Only:** Uses only `Foundation`, `AppKit`, `SwiftUI`, `Combine`, `UserNotifications`, `WidgetKit`, `AVKit`, `IOKit.ps`, and `Darwin` (no third-party packages).
- **Boundary Discipline:** All stream scraping/parsing remains inside `VRemindCore` (`1.0.0`); `VRemindKit` and `VRemind` handle scheduling, power/priority policy, UI lifecycle, and persistence/widget diffing.
- **Test Isolation:** Unit tests must never leak `PRIO_DARWIN_BG` onto the `swift test` runner process or perform real network requests.

## Review Focus

1. **Desktop Mac / Hackintosh or UPS power source (`IOPSGetProvidingPowerSourceType` returning `"AC Power"`, `"UPS Power"`, or `nil`):** Must map to `.ac` (`PowerTier.normal`, `180s` poll, batch `3`), while `"Battery Power"` maps to `.battery` (`360s`, batch `2`), and `isLowPowerModeEnabled == true` overrides any power source to `.lowPowerMode` (`900s`, batch `1`). *(Pinned in Task 1)*
2. **Overlapping UI surfaces (e.g., opening Preferences from the popover closes the popover while Preferences stays open):** `ProcessPriorityManager` must keep `PRIO_DARWIN_BG` disabled (`false`) until *every* active `UISurface` token has called `endUIActivity`, re-enabling `PRIO_DARWIN_BG` only when `activeSurfaces` transitions back to empty. *(Pinned in Task 1 & Task 5)*
3. **Steady-state live stream with `startedAt == nil`:** Repeated 3-minute polls of an already-live stream with `startedAt == nil` must not overwrite `lastStreamedAt = Date()` on every pass (which would force `ChannelStore` saves and `WidgetCenter` reloads every poll), while a newly live stream (`didTransitionToLive == true` or `lastStreamedAt == nil`) still stamps `lastStreamedAt`. *(Pinned in Task 2 & Task 3)*
4. **System sleep (`willSleepNotification` / `didWakeNotification`) and power changes during sleep:** `StreamMonitorService` must pause on both `screensDidSleepNotification` and `willSleepNotification`, and upon `screensDidWakeNotification` or `didWakeNotification` must refresh `powerMonitor` before scheduling the resumed poll pass so post-wake power tiers take effect immediately. *(Pinned in Task 3)*
5. **Celebration stream active while popover is closed (`isPopoverVisible == false`) or in Low Power Mode (`animationsPaused == true`):** `RainbowGradientView.showsAnimatedTimeline` must be `false` whenever `animate == false` or `reduceMotion == true`, and `MenuBarStatusViewModel.isPopoverConfettiActive` must return `false` when `powerMonitor.currentPolicy.animationsPaused == true`. *(Pinned in Task 4)*

---

## File Structure

- **Create:** `Sources/VRemindKit/Services/PowerStateMonitor.swift` — `PowerSource`, `PowerTier`, `PowerPolicy`, and `@MainActor public final class PowerStateMonitor: ObservableObject`.
- **Create:** `Sources/VRemindKit/Services/ProcessPriorityManager.swift` — `UISurface`, `PriorityBackend`, and `@MainActor public final class ProcessPriorityManager`.
- **Create:** `Tests/VRemindKitTests/PowerAndPriorityTests.swift` — Unit tests for power tier resolution, live power notifications, and UI-surface priority reference tracking.
- **Modify:** `Sources/VRemindKit/Services/ChannelStore.swift` — Equality guards on `updateMetadata` and `updateStatus` (`didTransitionToLive: Bool = false`) so unchanged polls neither mutate `@Published var channels` nor write `UserDefaults`.
- **Modify:** `Sources/VRemindKit/Services/WidgetSnapshotStore.swift` — Default `.background` ephemeral `URLSession`, `didWriteAvatar` tracking, and `WidgetChannelItem` equality diffing before writing `widget-cache.json` or calling `timelineReloader`.
- **Modify:** `Sources/VRemindKit/Services/StreamMonitorService.swift` — `.background` ephemeral `URLSession`, `PowerStateMonitor` integration, dynamic `batchSize` (3 / 2 / 1), `.background` QoS `Task.detached` execution, leeway-tolerant timer rescheduling on power changes, `willSleep` / `didWake` observers, and unchanged status diffing.
- **Modify:** `Sources/VRemindKit/Views/Components/RainbowStyle.swift` — Add `animate: Bool = true` to `RainbowGradientView`, `RainbowTextModifier`, and `.rainbowForeground`; render static `LinearGradient` (zero `TimelineView`) when `!animate || reduceMotion`, and 30 fps `TimelineView(.animation(minimumInterval: 1.0 / 30.0))` when `animate && !reduceMotion`.
- **Modify:** `Sources/VRemindKit/Views/Components/StatusBadge.swift`, `Sources/VRemindKit/Views/MenuBar/ChannelRowView.swift`, `Sources/VRemindKit/Views/MenuBar/MenuBarStatusView.swift` — Add `animate: Bool = true` parameter and `isPopoverVisible` / `powerMonitor` wiring so closed popovers and Low Power Mode never run `TimelineView` or confetti.
- **Modify:** `Sources/VRemindKit/Services/UpdateService.swift`, `Sources/VRemind/AppDelegate.swift`, `Sources/VRemind/PreferencesWindowController.swift`, `Sources/VRemind/OnboardingWindowController.swift`, `Sources/VRemind/UpdateAvailableWindowController.swift` — Ephemeral `.background` update session, `NSPopoverDelegate` visibility & priority hooks, window controller priority hooks, `UpdateAvailableWindowController` `contentViewController = nil` teardown on close, 1-hour `updateTimer.tolerance`, and Low Power Mode automatic update check deferral.
- **Modify Tests:** `Tests/VRemindKitTests/ChannelStoreTests.swift`, `Tests/VRemindKitTests/WidgetSnapshotStoreTests.swift`, `Tests/VRemindKitTests/StreamMonitorServiceTests.swift`, `Tests/VRemindKitTests/MenuBarViewTests.swift`, `Tests/VRemindKitTests/UpdateServiceTests.swift`.

---

### Task 1: Power State Monitor & Process Priority Manager

**Files:**
- Create: `Sources/VRemindKit/Services/PowerStateMonitor.swift`
- Create: `Sources/VRemindKit/Services/ProcessPriorityManager.swift`
- Create: `Tests/VRemindKitTests/PowerAndPriorityTests.swift`

**Interfaces:**
- Produces:
  - `public enum PowerSource: Equatable, Sendable { case ac, battery }`
  - `public enum PowerTier: Equatable, Sendable { case normal, battery, lowPowerMode }`
  - `public struct PowerPolicy: Equatable, Sendable`:
    - `public let tier: PowerTier`
    - `public let pollInterval: TimeInterval`
    - `public let timerLeeway: TimeInterval`
    - `public let batchSize: Int`
    - `public let animationsPaused: Bool`
    - `public let deferBackgroundUpdateChecks: Bool`
    - `public static func resolve(source: PowerSource, isLowPowerModeEnabled: Bool) -> PowerPolicy`
  - `@MainActor public final class PowerStateMonitor: ObservableObject`:
    - `@Published public private(set) var currentPolicy: PowerPolicy`
    - `public static func mapPowerSourceType(_ rawType: String?) -> PowerSource`
    - `public static func systemPowerSource() -> PowerSource`
    - `public init(powerSourceProvider: @escaping @Sendable () -> PowerSource = PowerStateMonitor.systemPowerSource, lowPowerModeProvider: @escaping @Sendable () -> Bool = { ProcessInfo.processInfo.isLowPowerModeEnabled }, notificationCenter: NotificationCenter = .default, observeSystemPowerSource: Bool = false)`
    - `public func refresh()`
  - `public enum UISurface: Hashable, Sendable { case popover, preferences, onboarding, updateAvailable }`
  - `public struct PriorityBackend: Sendable`:
    - `public let applyNice: @Sendable (Int32) -> Void`
    - `public let setBackgroundState: @Sendable (Bool) -> Void`
    - `public static let noop: PriorityBackend`
    - `public static let darwin: PriorityBackend`
  - `@MainActor public final class ProcessPriorityManager`:
    - `public private(set) var activeSurfaces: Set<UISurface>`
    - `public private(set) var isBackgroundThrottled: Bool`
    - `public init(backend: PriorityBackend = .noop)`
    - `public func applyLaunchBaseline()`
    - `public func beginUIActivity(_ surface: UISurface)`
    - `public func endUIActivity(_ surface: UISurface)`

- [ ] **Step 1: Write the failing tests in `Tests/VRemindKitTests/PowerAndPriorityTests.swift`**

```swift
import Combine
import Darwin
import Foundation
import Testing
@testable import VRemindKit

struct PowerAndPriorityTests {
    @Test func testPowerPolicyTierResolutionAndSourceMapping() {
        #expect(PowerStateMonitor.mapPowerSourceType("Battery Power") == .battery)
        #expect(PowerStateMonitor.mapPowerSourceType("AC Power") == .ac)
        #expect(PowerStateMonitor.mapPowerSourceType("UPS Power") == .ac)
        #expect(PowerStateMonitor.mapPowerSourceType(nil) == .ac)

        let normal = PowerPolicy.resolve(source: .ac, isLowPowerModeEnabled: false)
        #expect(normal.tier == .normal)
        #expect(normal.pollInterval == 180)
        #expect(normal.timerLeeway == 30)
        #expect(normal.batchSize == 3)
        #expect(normal.animationsPaused == false)
        #expect(normal.deferBackgroundUpdateChecks == false)

        let battery = PowerPolicy.resolve(source: .battery, isLowPowerModeEnabled: false)
        #expect(battery.tier == .battery)
        #expect(battery.pollInterval == 360)
        #expect(battery.timerLeeway == 60)
        #expect(battery.batchSize == 2)
        #expect(battery.animationsPaused == false)
        #expect(battery.deferBackgroundUpdateChecks == false)

        let lpmOnAC = PowerPolicy.resolve(source: .ac, isLowPowerModeEnabled: true)
        let lpmOnBattery = PowerPolicy.resolve(source: .battery, isLowPowerModeEnabled: true)
        #expect(lpmOnAC == lpmOnBattery)
        #expect(lpmOnAC.tier == .lowPowerMode)
        #expect(lpmOnAC.pollInterval == 900)
        #expect(lpmOnAC.timerLeeway == 180)
        #expect(lpmOnAC.batchSize == 1)
        #expect(lpmOnAC.animationsPaused == true)
        #expect(lpmOnAC.deferBackgroundUpdateChecks == true)
    }

    @Test @MainActor func testPowerStateMonitorObservesTransitionsWithoutDuplicatePublishes() async {
        let sourceBox = ValueBox<PowerSource>(.ac)
        let lpmBox = ValueBox<Bool>(false)
        let center = NotificationCenter()

        let monitor = PowerStateMonitor(
            powerSourceProvider: { sourceBox.get() },
            lowPowerModeProvider: { lpmBox.get() },
            notificationCenter: center,
            observeSystemPowerSource: false
        )

        #expect(monitor.currentPolicy.tier == .normal)

        var publishedPolicies: [PowerPolicy] = []
        var cancellables = Set<AnyCancellable>()
        monitor.$currentPolicy
            .dropFirst()
            .sink { publishedPolicies.append($0) }
            .store(in: &cancellables)

        // Unchanged refresh should not re-publish
        monitor.refresh()
        #expect(publishedPolicies.isEmpty)

        // Switch to battery
        sourceBox.set(.battery)
        monitor.refresh()
        #expect(publishedPolicies.map(\.tier) == [.battery])

        // Post NSProcessInfoPowerStateDidChange with Low Power Mode enabled
        lpmBox.set(true)
        center.post(name: .NSProcessInfoPowerStateDidChange, object: nil)
        for _ in 0..<20 {
            if monitor.currentPolicy.tier == .lowPowerMode { break }
            await Task.yield()
        }
        #expect(monitor.currentPolicy.tier == .lowPowerMode)
        #expect(publishedPolicies.map(\.tier) == [.battery, .lowPowerMode])
    }

    @Test @MainActor func testProcessPriorityManagerTracksOverlappingUISurfaces() {
        let niceCalls = ValueBox<[Int32]>([])
        let bgCalls = ValueBox<[Bool]>([])

        let spyBackend = PriorityBackend(
            applyNice: { nice in niceCalls.set(niceCalls.get() + [nice]) },
            setBackgroundState: { enabled in bgCalls.set(bgCalls.get() + [enabled]) }
        )

        let manager = ProcessPriorityManager(backend: spyBackend)
        manager.applyLaunchBaseline()

        #expect(niceCalls.get() == [Int32(PRIO_MAX)])
        #expect(bgCalls.get() == [true])
        #expect(manager.isBackgroundThrottled == true)

        // Popover opens -> lifts background throttle
        manager.beginUIActivity(.popover)
        #expect(bgCalls.get() == [true, false])
        #expect(manager.isBackgroundThrottled == false)

        // Preferences opens while popover is still open -> no duplicate syscall
        manager.beginUIActivity(.preferences)
        #expect(bgCalls.get() == [true, false])
        #expect(manager.activeSurfaces == [.popover, .preferences])

        // Popover closes while Preferences remains open -> stays unthrottled
        manager.endUIActivity(.popover)
        #expect(bgCalls.get() == [true, false])
        #expect(manager.isBackgroundThrottled == false)

        // Preferences closes -> all surfaces closed -> re-engages background throttle
        manager.endUIActivity(.preferences)
        #expect(bgCalls.get() == [true, false, true])
        #expect(manager.isBackgroundThrottled == true)
        #expect(manager.activeSurfaces.isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/test.sh --filter PowerAndPriorityTests`
Expected: FAIL with compilation error (`cannot find 'PowerStateMonitor' in scope`).

- [ ] **Step 3: Implement `PowerStateMonitor.swift` and `ProcessPriorityManager.swift`**

In `Sources/VRemindKit/Services/PowerStateMonitor.swift`:
- Import `Combine`, `Foundation`, `IOKit.ps`.
- Implement `PowerPolicy.resolve(source:isLowPowerModeEnabled:)` with exact values (`180/30/3` normal, `360/60/2` battery, `900/180/1` lowPowerMode).
- `mapPowerSourceType(_ rawType: String?) -> PowerSource`: returns `.battery` only when `rawType == kIOPMBatteryPowerValue` (`"Battery Power"`), otherwise `.ac`.
- `systemPowerSource() -> PowerSource`: calls `IOPSCopyPowerSourcesInfo()?.takeRetainedValue()` and `IOPSGetProvidingPowerSourceType(blob)?.takeRetainedValue() as String?`, passing to `mapPowerSourceType`.
- Observe `Notification.Name.NSProcessInfoPowerStateDidChange` on `notificationCenter`; hop to `@MainActor` (`if Thread.isMainThread { MainActor.assumeIsolated { ... } } else { Task { @MainActor ... } }`) and call `refresh()`.
- When `observeSystemPowerSource == true`, register a `CFRunLoopSource` via `IOPSNotificationCreateRunLoopSource` on `CFRunLoopGetMain()` using an unretained/weak box and remove it in `deinit`.
- `refresh()` computes `let resolved = PowerPolicy.resolve(...)` and assigns `currentPolicy = resolved` only when `resolved != currentPolicy`.

In `Sources/VRemindKit/Services/ProcessPriorityManager.swift`:
- Import `Darwin`, `Foundation`.
- `PriorityBackend.darwin` calls ` _ = Darwin.setpriority(PRIO_PROCESS, 0, nice)` and `_ = Darwin.setpriority(PRIO_DARWIN_PROCESS, 0, enabled ? PRIO_DARWIN_BG : 0)`.
- `ProcessPriorityManager` tracks `activeSurfaces: Set<UISurface>` and only calls `backend.setBackgroundState` when `isBackgroundThrottled` changes.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash scripts/test.sh --filter PowerAndPriorityTests`
Expected: PASS (all 3 tests in `PowerAndPriorityTests`).

- [ ] **Step 5: Commit**

```bash
git add Sources/VRemindKit/Services/PowerStateMonitor.swift Sources/VRemindKit/Services/ProcessPriorityManager.swift Tests/VRemindKitTests/PowerAndPriorityTests.swift
git commit -m "feat: add PowerStateMonitor and ProcessPriorityManager for laptop power scaling"
```

---

### Task 2: Eliminate No-Op Persistence & WidgetKit Churn (`ChannelStore` & `WidgetSnapshotStore`)

**Files:**
- Modify: `Sources/VRemindKit/Services/ChannelStore.swift:102-166`
- Modify: `Sources/VRemindKit/Services/WidgetSnapshotStore.swift:20-178`
- Test: `Tests/VRemindKitTests/ChannelStoreTests.swift`
- Test: `Tests/VRemindKitTests/WidgetSnapshotStoreTests.swift`

**Interfaces:**
- Consumes: `WatchedChannel`, `StreamStatus`, `WidgetChannelItem`
- Produces:
  - `ChannelStore.updateMetadata(for id: String, name: String?, avatarURL: URL?)` (no-op when trimmed `name` and `avatarURL` match existing channel)
  - `ChannelStore.updateStatus(for id: String, status: StreamStatus, notifiedLiveId: String? = nil, notifiedUpcomingId: String? = nil, didTransitionToLive: Bool = false)` (no-op when fields are unchanged; when `.live` has `startedAt == nil`, stamps `Date()` only when `existing.lastStreamedAt == nil || didTransitionToLive || notifiedLiveId != nil`)
  - `WidgetSnapshotStore`: default `urlSession` uses `URLSessionConfiguration.ephemeral` with `urlCache = nil` and `networkServiceType = .background`; `writeSnapshot(channels:statuses:)` skips disk write and `timelineReloader?()` when `cacheFileURL` exists, `sorted == existingChannels`, and no new avatar file was written.

- [ ] **Step 1: Add failing no-op diffing tests in `ChannelStoreTests.swift` and `WidgetSnapshotStoreTests.swift`**

In `Tests/VRemindKitTests/ChannelStoreTests.swift`:
```swift
    @Test @MainActor func updateMetadataAndStatusSkipNoOpSavesAndPublishes() async {
        let store = ChannelStore(userDefaults: makeTestDefaults())
        let avatar = URL(string: "https://example.com/a.png")!
        store.addChannel(handle: "@steady", name: "Steady", avatarURL: avatar)

        let started = Date(timeIntervalSince1970: 1_700_000_000)
        store.updateStatus(
            for: "youtube:@steady",
            status: .live(videoId: "v1", title: "Live", startedAt: started),
            notifiedLiveId: "v1",
            didTransitionToLive: true
        )

        var publishCount = 0
        var cancellables = Set<AnyCancellable>()
        store.$channels
            .dropFirst()
            .sink { _ in publishCount += 1 }
            .store(in: &cancellables)

        // Identical metadata -> zero publishes
        store.updateMetadata(for: "youtube:@steady", name: "Steady", avatarURL: avatar)
        #expect(publishCount == 0)

        // Identical live status with same startedAt -> zero publishes
        store.updateStatus(
            for: "youtube:@steady",
            status: .live(videoId: "v1", title: "Live", startedAt: started)
        )
        #expect(publishCount == 0)

        // Steady-state live poll with startedAt == nil (already has lastStreamedAt, didTransitionToLive == false) -> zero publishes, preserves lastStreamedAt
        store.updateStatus(
            for: "youtube:@steady",
            status: .live(videoId: "v1", title: "Live", startedAt: nil),
            didTransitionToLive: false
        )
        #expect(publishCount == 0)
        #expect(store.channels.first(where: { $0.id == "youtube:@steady" })?.lastStreamedAt == started)
    }
```
(Add `import Combine` at top of `ChannelStoreTests.swift`.)

In `Tests/VRemindKitTests/WidgetSnapshotStoreTests.swift`:
```swift
    @Test func writeSnapshotSkipsDiskWriteAndTimelineReloadWhenUnchanged() async throws {
        let tempDir = try createTemporaryDirectory()
        defer { removeTemporaryDirectory(tempDir) }

        let reloadCounter = Counter()
        let store = WidgetSnapshotStore(
            directoryURL: tempDir,
            timelineReloader: { reloadCounter.increment() }
        )

        let channel = WatchedChannel(id: "youtube:@bukancaitlyn", name: "Caitlyn", handle: "@bukancaitlyn")
        let liveDate = Date(timeIntervalSince1970: 1_731_401_000)
        let statuses: [String: StreamStatus] = [
            channel.id: .live(videoId: "v1", title: "Stream", startedAt: liveDate)
        ]

        try await store.writeSnapshot(channels: [channel], statuses: statuses)
        #expect(reloadCounter.value == 1)

        // Second identical write -> skipped, reloadCounter stays 1
        try await store.writeSnapshot(channels: [channel], statuses: statuses)
        #expect(reloadCounter.value == 1)

        // Changed stream title -> writes and reloads
        let updatedStatuses: [String: StreamStatus] = [
            channel.id: .live(videoId: "v1", title: "New Title", startedAt: liveDate)
        ]
        try await store.writeSnapshot(channels: [channel], statuses: updatedStatuses)
        #expect(reloadCounter.value == 2)
    }
```

- [ ] **Step 2: Run tests to verify failure**

Run: `bash scripts/test.sh --filter "ChannelStoreTests|WidgetSnapshotStoreTests"`
Expected: FAIL (`updateStatus` does not accept `didTransitionToLive` / `reloadCounter.value` is `2` instead of `1`).

- [ ] **Step 3: Implement diffing guards in `ChannelStore.swift` and `WidgetSnapshotStore.swift`**

In `Sources/VRemindKit/Services/ChannelStore.swift`:
- In `updateMetadata(for:name:avatarURL:)`, copy `var candidate = channels[index]`. Update `candidate.name` only if `trimmed != candidate.name`; update `candidate.avatarURL` only if `avatarURL != candidate.avatarURL`. If `candidate != channels[index]`, assign `channels[index] = candidate` and call `save()`.
- In `updateStatus(for:status:notifiedLiveId:notifiedUpcomingId:didTransitionToLive: Bool = false)`, copy `var candidate = channels[index]`. Update `lastNotifiedVideoId` / `lastNotifiedUpcomingId` only if different. For `.live(_, _, let startedAt)`: if `let startedAt`, set `candidate.lastStreamedAt = startedAt`; else if `candidate.lastStreamedAt == nil || didTransitionToLive || notifiedLiveId != nil`, set `candidate.lastStreamedAt = Date()`. For `.offline(let lastStreamed)`, set `candidate.lastStreamedAt = lastStreamed` if non-nil. Assign `channels[index] = candidate` and `save()` only when `candidate != channels[index]`.

In `Sources/VRemindKit/Services/WidgetSnapshotStore.swift`:
- Add `public static let defaultURLSession: URLSession` configured with `.ephemeral`, `urlCache = nil`, `requestCachePolicy = .reloadIgnoringLocalCacheData`, `networkServiceType = .background`, `timeoutIntervalForRequest = 15`, and use it as default parameter in `init`.
- Change `cacheAvatarIfNeeded(from:to:) -> Bool` to return `true` when a new file was written.
- In `writeSnapshot(channels:statuses:)`, track `var didWriteAnyAvatar = false`. After computing `let sorted = Self.sortChannels(items)`, check if `fileManager.fileExists(atPath: cacheFileURL.path)`, `!didWriteAnyAvatar`, and `readSnapshot()?.channels == sorted`; if so, return early without writing or calling `timelineReloader?()`.

- [ ] **Step 4: Run tests to verify pass**

Run: `bash scripts/test.sh --filter "ChannelStoreTests|WidgetSnapshotStoreTests"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/VRemindKit/Services/ChannelStore.swift Sources/VRemindKit/Services/WidgetSnapshotStore.swift Tests/VRemindKitTests/ChannelStoreTests.swift Tests/VRemindKitTests/WidgetSnapshotStoreTests.swift
git commit -m "perf: skip no-op ChannelStore saves and unchanged WidgetKit timeline reloads"
```

---

### Task 3: Power-Aware Background Polling, E-Core QoS & System Sleep/Wake (`StreamMonitorService`)

**Files:**
- Modify: `Sources/VRemindKit/Services/StreamMonitorService.swift`
- Test: `Tests/VRemindKitTests/StreamMonitorServiceTests.swift`

**Interfaces:**
- Consumes: `PowerStateMonitor`, `PowerPolicy`, `ChannelStore.updateStatus(..., didTransitionToLive:)`
- Produces:
  - `StreamMonitorService.powerMonitor: PowerStateMonitor`
  - `StreamMonitorService.init(..., powerMonitor: PowerStateMonitor? = nil, ...)`
  - `StreamMonitorService.startPolling(interval: TimeInterval? = nil)` (when `interval == nil`, dynamically uses `powerMonitor.currentPolicy.pollInterval` and reschedules when `powerMonitor.$currentPolicy` changes; when `interval != nil`, uses that fixed override)
  - `StreamMonitorService.effectiveBatchSize: Int` (uses `powerMonitor.currentPolicy.batchSize` = `3` normal, `2` battery, `1` lowPowerMode)
  - System + display sleep/wake handling (`screensDidSleepNotification`, `screensDidWakeNotification`, `willSleepNotification`, `didWakeNotification`)

- [ ] **Step 1: Add failing tests in `Tests/VRemindKitTests/StreamMonitorServiceTests.swift`**

Add tests at the end of `StreamMonitorServiceTests` (and update `testDeallocationCleansUpObserversAndStopsPolling` line 543/548 from `2` to `4` for the 4 sleep/wake observers):
```swift
    @Test @MainActor func testPowerTierAdaptsConcurrencyBatchSize() async {
        let channelStore = ChannelStore(userDefaults: makeTestDefaults())
        for i in 1...4 {
            _ = channelStore.addChannel(handle: "@ch\(i)", name: "Ch \(i)")
        }
        let prefs = PreferencesStore(userDefaults: makeTestDefaults())
        let sourceBox = ValueBox<PowerSource>(.ac)
        let lpmBox = ValueBox<Bool>(true)
        let powerMonitor = PowerStateMonitor(
            powerSourceProvider: { sourceBox.get() },
            lowPowerModeProvider: { lpmBox.get() },
            notificationCenter: NotificationCenter(),
            observeSystemPowerSource: false
        )

        let tracker = ConcurrencyTracker()
        let service = StreamMonitorService(
            channelStore: channelStore,
            preferencesStore: prefs,
            notificationService: MockNotificationService(),
            fetcher: { _ in
                tracker.enter()
                try? await Task.sleep(nanoseconds: 25_000_000)
                tracker.exit()
                return (makeOfflineHTML(), make200Response())
            },
            snapshotStore: SpyWidgetSnapshotStore(),
            powerMonitor: powerMonitor
        )

        // In Low Power Mode, batchSize must be 1 (serialized)
        #expect(service.effectiveBatchSize == 1)
        await service.refreshAll()
        #expect(tracker.peakConcurrency == 1)

        // On Battery (Low Power Mode off), batchSize must be 2
        lpmBox.set(false)
        sourceBox.set(.battery)
        powerMonitor.refresh()
        #expect(service.effectiveBatchSize == 2)
    }

    @Test @MainActor func testSystemWillSleepPausesAndDidWakeRefreshesPowerTierAndResumes() async {
        let channelStore = ChannelStore(userDefaults: makeTestDefaults())
        let prefs = PreferencesStore(userDefaults: makeTestDefaults())
        let testCenter = NotificationCenter()
        let lpmBox = ValueBox<Bool>(false)
        let powerMonitor = PowerStateMonitor(
            powerSourceProvider: { .ac },
            lowPowerModeProvider: { lpmBox.get() },
            notificationCenter: NotificationCenter(),
            observeSystemPowerSource: false
        )

        let service = StreamMonitorService(
            channelStore: channelStore,
            preferencesStore: prefs,
            notificationService: MockNotificationService(),
            fetcher: { _ in (makeOfflineHTML(), make200Response()) },
            notificationCenter: testCenter,
            snapshotStore: SpyWidgetSnapshotStore(),
            powerMonitor: powerMonitor
        )

        service.startPolling()
        #expect(service.isPolling)
        #expect(!service.isPausedForSleep)
        #expect(service.currentPollingInterval == 180)

        // System sleep pauses polling
        testCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        #expect(service.isPausedForSleep)

        // Enable Low Power Mode while asleep, then wake
        lpmBox.set(true)
        testCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        #expect(!service.isPausedForSleep)
        #expect(service.isPolling)
        #expect(service.currentPollingInterval == 900)

        service.stopPolling()
    }
```

- [ ] **Step 2: Run tests to verify failure**

Run: `bash scripts/test.sh --filter StreamMonitorServiceTests`
Expected: FAIL (`extra argument 'powerMonitor' in call`).

- [ ] **Step 3: Update `StreamMonitorService.swift` with `.background` QoS, power-tier scheduling, and system sleep/wake**

In `Sources/VRemindKit/Services/StreamMonitorService.swift`:
- Set `config.networkServiceType = .background` in `StreamMonitorService.session` and use `StreamMonitorService.defaultHTTPFetcher` (backed by `StreamMonitorService.session`) as the default `httpFetcher` when none is injected.
- Add `public let powerMonitor: PowerStateMonitor`, `private var customIntervalOverride: TimeInterval?`, `public var currentPollingInterval: TimeInterval { customIntervalOverride ?? powerMonitor.currentPolicy.pollInterval }`, and `public var effectiveBatchSize: Int { powerMonitor.currentPolicy.batchSize }`.
- In `performRefreshPass()`:
  - Capture `let batchSize = effectiveBatchSize`, `let registry = providerRegistry`, `let fetcher = httpFetcher`, `let now = dateProvider()`, `let cal = calendar`.
  - Run `StreamMonitorEngine(registry: registry, batchSize: batchSize).refreshPass(...)` inside `await Task.detached(priority: .background) { ... }.value`, hopping back to `@MainActor` in `onEvent`.
  - In `handleMonitorEvent`:
    - For `.statusUpdated(let channelId, let status)`: compute `let previous = statuses[channelId]`; detect `didTransitionToLive` when `status` is `.live(let newVid, _, _)` and `previous` was not `.live` with `newVid`. Update `statuses[channelId] = status` only when `previous != status`, and call `channelStore.updateStatus(for: channelId, status: status, didTransitionToLive: didTransitionToLive)`.
    - For `.refreshFinished(let finalStatuses)`: assign `self.statuses = finalStatuses` only if `self.statuses != finalStatuses`.
  - At end of `performRefreshPass()`, assign `self.statuses = filteredStatuses` only if `self.statuses != filteredStatuses`, then run `snapshotStore.writeSnapshot(channels: channelsSnapshot, statuses: filteredStatuses)` inside `Task.detached(priority: .background)`.
- In `startPolling(interval: TimeInterval? = nil)`:
  - Store `customIntervalOverride = interval`.
  - Register 4 observers on `notificationCenter`: `screensDidSleepNotification`, `screensDidWakeNotification`, `willSleepNotification`, and `didWakeNotification` (storing all 4 tokens and removing all 4 in `stopPolling()` and `deinit`).
  - When `handleScreensDidWake()` runs, call `powerMonitor.refresh()` before `startPollingLoop()`.
  - Observe `powerMonitor.$currentPolicy.dropFirst()` while polling when `customIntervalOverride == nil`: on policy change when `!isPausedForSleep`, update the sleep timer to the new `pollInterval` without firing an extra immediate `refreshAll()`.
  - In `startPollingLoop()`, after `await self?.refreshAll()`, sleep using a `.background` QoS `DispatchSourceTimer` (or `Task.sleep` paired with timer leeway) for `currentPollingInterval` with `leeway: .seconds(Int(powerMonitor.currentPolicy.timerLeeway))`.

- [ ] **Step 4: Run tests to verify pass**

Run: `bash scripts/test.sh --filter StreamMonitorServiceTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/VRemindKit/Services/StreamMonitorService.swift Tests/VRemindKitTests/StreamMonitorServiceTests.swift
git commit -m "perf: add power-tier polling, background E-core QoS, and system sleep/wake hooks"
```

---

### Task 4: Popover Visibility & Zero-`TimelineView` Static Mode (`RainbowStyle`, `StatusBadge`, `ChannelRowView`, `MenuBarStatusView`)

**Files:**
- Modify: `Sources/VRemindKit/Views/Components/RainbowStyle.swift`
- Modify: `Sources/VRemindKit/Views/Components/StatusBadge.swift`
- Modify: `Sources/VRemindKit/Views/MenuBar/ChannelRowView.swift`
- Modify: `Sources/VRemindKit/Views/MenuBar/MenuBarStatusView.swift`
- Test: `Tests/VRemindKitTests/MenuBarViewTests.swift`

**Interfaces:**
- Consumes: `PowerStateMonitor`
- Produces:
  - `RainbowGradientView(animate: Bool = true, reduceMotion: Bool = false)` with `public var showsAnimatedTimeline: Bool { animate && !reduceMotion }`
  - `RainbowTextModifier(active: Bool, animate: Bool = true, reduceMotion: Bool = false)`
  - `View.rainbowForeground(active: Bool, animate: Bool = true, reduceMotion: Bool = false)`
  - `StatusBadge(isLive: Bool, label: String? = nil, isCelebration: Bool = false, animate: Bool = true, reduceMotion: Bool = false)`
  - `ChannelRowView(channel: WatchedChannel, status: StreamStatus, animate: Bool = true, reduceMotion: Bool = false, dateProvider: @escaping () -> Date = { Date() }, onDelete: @escaping () -> Void)`
  - `MenuBarStatusViewModel`:
    - `@Published public var isPopoverVisible: Bool = false`
    - `public let powerMonitor: PowerStateMonitor?`
    - `public var areAnimationsPaused: Bool` (`preferencesStore.settings.reduceMotion || (powerMonitor?.currentPolicy.animationsPaused ?? false)`)
    - `public var shouldAnimatePopoverEffects: Bool` (`isPopoverVisible && !areAnimationsPaused`)
  - `MenuBarStatusView.makePopover(channelStore:monitorService:powerMonitor:onOpenPreferences:onQuit:) -> NSPopover` (and `makePopoverWithViewModel(...) -> (NSPopover, MenuBarStatusViewModel)` or exposing `viewModel` for `AppDelegate`)

- [ ] **Step 1: Add failing animation-gating tests in `Tests/VRemindKitTests/MenuBarViewTests.swift`**

```swift
    @Test @MainActor func testPopoverVisibilityAndLowPowerModeGateRainbowAndConfettiAnimations() async {
        // 1. RainbowGradientView only runs TimelineView when animate == true && reduceMotion == false
        #expect(RainbowGradientView(animate: true, reduceMotion: false).showsAnimatedTimeline == true)
        #expect(RainbowGradientView(animate: false, reduceMotion: false).showsAnimatedTimeline == false)
        #expect(RainbowGradientView(animate: true, reduceMotion: true).showsAnimatedTimeline == false)
        #expect(RainbowGradientView(animate: false, reduceMotion: true).showsAnimatedTimeline == false)

        // 2. Low Power Mode pauses confetti and popover animations even when reduceMotion == false and popover is visible
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let channelStore = ChannelStore(userDefaults: makeTestDefaults())
        _ = channelStore.addChannel(handle: "@bday", name: "Bday")
        let prefs = PreferencesStore(userDefaults: makeTestDefaults())
        prefs.settings.reduceMotion = false

        let liveHTML = """
        <html><body><script>var ytInitialPlayerResponse = {"videoDetails":{"isLive":true,"title":"Happy Birthday Stream!","videoId":"v1"}};</script></body></html>
        """
        let okResponse = HTTPURLResponse(url: URL(string: "https://www.youtube.com/@bday/live")!, statusCode: 200, httpVersion: nil, headerFields: nil)!

        let lpmBox = ValueBox<Bool>(false)
        let powerMonitor = PowerStateMonitor(
            powerSourceProvider: { .ac },
            lowPowerModeProvider: { lpmBox.get() },
            notificationCenter: NotificationCenter(),
            observeSystemPowerSource: false
        )

        let monitor = StreamMonitorService(
            channelStore: channelStore,
            preferencesStore: prefs,
            notificationService: NotificationService(center: MockNotificationCenter()),
            fetcher: { _ in (Data(liveHTML.utf8), okResponse) },
            snapshotStore: SpyWidgetSnapshotStore(),
            dateProvider: { now },
            powerMonitor: powerMonitor
        )
        await monitor.refreshAll()

        let viewModel = MenuBarStatusViewModel(
            channelStore: channelStore,
            monitorService: monitor,
            powerMonitor: powerMonitor,
            dateProvider: { now }
        )

        // Popover starts hidden -> shouldAnimatePopoverEffects is false
        #expect(viewModel.isPopoverVisible == false)
        #expect(viewModel.shouldAnimatePopoverEffects == false)
        #expect(viewModel.isPopoverConfettiActive(date: now) == true)

        // Popover shown in normal power mode -> animations active
        viewModel.isPopoverVisible = true
        #expect(viewModel.shouldAnimatePopoverEffects == true)

        // Enable Low Power Mode -> confetti & animations pause immediately
        lpmBox.set(true)
        powerMonitor.refresh()
        #expect(viewModel.areAnimationsPaused == true)
        #expect(viewModel.shouldAnimatePopoverEffects == false)
        #expect(viewModel.isPopoverConfettiActive(date: now) == false)
    }
```

- [ ] **Step 2: Run test to verify failure**

Run: `bash scripts/test.sh --filter MenuBarViewTests`
Expected: FAIL (`extra argument 'animate' in call`).

- [ ] **Step 3: Implement animation gating in `RainbowStyle.swift`, `StatusBadge.swift`, `ChannelRowView.swift`, and `MenuBarStatusView.swift`**

- In `Sources/VRemindKit/Views/Components/RainbowStyle.swift`:
  - Add `public let animate: Bool` (default `true`) and `public var showsAnimatedTimeline: Bool { animate && !reduceMotion }` to `RainbowGradientView`.
  - In `RainbowGradientView.body`: when `showsAnimatedTimeline` is `true`, render `TimelineView(.animation(minimumInterval: 1.0 / 30.0))` with `cycleDuration = 3.0`; when `false`, render a static `LinearGradient(gradient: Gradient(colors: RainbowPalette.colors), startPoint: .topLeading, endPoint: .bottomTrailing)` with zero `TimelineView`.
  - Thread `animate: Bool = true` through `RainbowTextModifier` and `.rainbowForeground(active:animate:reduceMotion:)`.
- In `Sources/VRemindKit/Views/Components/StatusBadge.swift` and `Sources/VRemindKit/Views/MenuBar/ChannelRowView.swift`:
  - Add `public let animate: Bool` (default `true`) and pass `animate: animate` to `.rainbowForeground(...)` and `StatusBadge(...)`.
- In `Sources/VRemindKit/Views/MenuBar/MenuBarStatusView.swift`:
  - Add `@Published public var isPopoverVisible: Bool = false` and `public let powerMonitor: PowerStateMonitor?` to `MenuBarStatusViewModel` (defaulting `powerMonitor: PowerStateMonitor? = nil`, falling back to `monitorService.powerMonitor`).
  - Subscribe to `resolvedPowerMonitor.objectWillChange` alongside `channelStore`, `monitorService`, and `preferencesStore`.
  - In `isPopoverConfettiActive(date:)`, guard `!areAnimationsPaused`.
  - In `MenuBarStatusView`, bind visibility to `viewModel.isPopoverVisible`, gate `ConfettiOverlayView()` on `viewModel.isPopoverVisible && viewModel.isPopoverConfettiActive()`, and pass `animate: viewModel.shouldAnimatePopoverEffects` into `sectionBlock` and `ChannelRowView`.

- [ ] **Step 4: Run test to verify pass**

Run: `bash scripts/test.sh --filter MenuBarViewTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/VRemindKit/Views/Components/RainbowStyle.swift Sources/VRemindKit/Views/Components/StatusBadge.swift Sources/VRemindKit/Views/MenuBar/ChannelRowView.swift Sources/VRemindKit/Views/MenuBar/MenuBarStatusView.swift Tests/VRemindKitTests/MenuBarViewTests.swift
git commit -m "perf: gate rainbow TimelineView and confetti on popover visibility and Low Power Mode"
```

---

### Task 5: AppDelegate Integration (`NSPopoverDelegate`, Window Priority Hooks, Low Power Update Deferral, Video Teardown) & Universal Build Verification

**Files:**
- Modify: `Sources/VRemindKit/Services/UpdateService.swift:18-33`
- Modify: `Sources/VRemind/AppDelegate.swift`
- Modify: `Sources/VRemind/PreferencesWindowController.swift`
- Modify: `Sources/VRemind/OnboardingWindowController.swift`
- Modify: `Sources/VRemind/UpdateAvailableWindowController.swift`
- Test: `Tests/VRemindKitTests/UpdateServiceTests.swift`

**Interfaces:**
- Consumes: `PowerStateMonitor`, `ProcessPriorityManager`, `MenuBarStatusViewModel`
- Produces:
  - `UpdateService.defaultSession: URLSession` (ephemeral, `urlCache = nil`, `networkServiceType = .background`)
  - `UpdateService.checkForUpdates(manual: Bool = false, isLowPowerModeEnabled: Bool = false) async -> UpdateCheckResult` (returns `.skippedNotConsented` when `!manual && isLowPowerModeEnabled`, while keeping `checkForUpdates(manual:)` backward-compatible)
  - `AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate` wiring `powerMonitor`, `priorityManager`, `popoverWillShow` / `popoverDidClose`, window controller UI activity callbacks, and `updateTimer?.tolerance = 3_600`
  - `UpdateAvailableWindowController`: clears `window?.contentViewController = nil` in `close()` and `windowWillClose(_:)`

- [ ] **Step 1: Add failing Low Power Mode update deferral test in `Tests/VRemindKitTests/UpdateServiceTests.swift`**

Read `Tests/VRemindKitTests/UpdateServiceTests.swift` and add:
```swift
    @Test @MainActor func automaticUpdateCheckSkipsInLowPowerModeWhileManualProceeds() async {
        let prefs = PreferencesStore(userDefaults: makeTestDefaults())
        prefs.settings.updateConsent = .allowed

        var fetchCount = 0
        let service = UpdateService(
            preferencesStore: prefs,
            currentVersion: "1.0.0",
            fetchRelease: {
                fetchCount += 1
                return GitHubRelease(
                    tagName: "v1.1.0",
                    name: "1.1.0",
                    body: "Notes",
                    htmlURL: URL(string: "https://github.com/momochisoundpost/VRemind/releases/tag/v1.1.0")!
                )
            }
        )

        // Automatic check in Low Power Mode is deferred without hitting network
        let autoResult = await service.checkForUpdates(manual: false, isLowPowerModeEnabled: true)
        #expect(fetchCount == 0)
        #expect(autoResult == .skippedNotConsented)

        // Manual check in Low Power Mode still proceeds
        let manualResult = await service.checkForUpdates(manual: true, isLowPowerModeEnabled: true)
        #expect(fetchCount == 1)
        if case .updateAvailable(let release) = manualResult {
            #expect(release.tagName == "v1.1.0")
        } else {
            Issue.record("Expected .updateAvailable on manual check")
        }
    }
```

- [ ] **Step 2: Run test to verify failure**

Run: `bash scripts/test.sh --filter UpdateServiceTests`
Expected: FAIL (`extra argument 'isLowPowerModeEnabled' in call`).

- [ ] **Step 3: Implement `UpdateService`, `AppDelegate`, and Window Controller lifecycle updates**

- In `Sources/VRemindKit/Services/UpdateService.swift`:
  - Add `public static let defaultSession: URLSession` with `URLSessionConfiguration.ephemeral`, `urlCache = nil`, `networkServiceType = .background`, and use it as the default `session` argument in `init`.
  - Add `isLowPowerModeEnabled: Bool = false` to `checkForUpdates(manual: Bool = false, isLowPowerModeEnabled: Bool = false)`: if `!manual && (preferencesStore.settings.updateConsent != .allowed || isLowPowerModeEnabled)`, set `self.lastResult = .skippedNotConsented` and return `.skippedNotConsented`.
- In `Sources/VRemind/UpdateAvailableWindowController.swift`:
  - Add optional `onVisibilityChange: ((Bool) -> Void)? = nil` callback; call `onVisibilityChange?(true)` on show and in `windowWillClose` / `close()` call `window?.contentViewController = nil` and `onVisibilityChange?(false)`.
- In `Sources/VRemind/PreferencesWindowController.swift` and `Sources/VRemind/OnboardingWindowController.swift`:
  - Add optional `onVisibilityChange: ((Bool) -> Void)? = nil` (or notify on show and `windowWillClose` / `close()`).
- In `Sources/VRemind/AppDelegate.swift`:
  - Add `var powerMonitor: PowerStateMonitor!`, `var priorityManager: ProcessPriorityManager!`, and `var statusViewModel: MenuBarStatusViewModel!`.
  - Initialize `powerMonitor = PowerStateMonitor(observeSystemPowerSource: true)` and `priorityManager = ProcessPriorityManager(backend: .darwin)` in `applicationDidFinishLaunching`, calling `priorityManager.applyLaunchBaseline()`.
  - Conform `AppDelegate` to `NSPopoverDelegate`; set `popover?.delegate = self`; in `popoverWillShow` set `statusViewModel.isPopoverVisible = true` and `priorityManager.beginUIActivity(.popover)`; in `popoverDidClose` set `statusViewModel.isPopoverVisible = false` and `priorityManager.endUIActivity(.popover)`.
  - Wire `.preferences`, `.onboarding`, and `.updateAvailable` `onVisibilityChange` callbacks into `priorityManager.beginUIActivity` / `endUIActivity`.
  - Set `updateTimer?.tolerance = 3_600` in `startPeriodicUpdateChecksIfNeeded()`, and pass `isLowPowerModeEnabled: powerMonitor.currentPolicy.deferBackgroundUpdateChecks` into automatic `updateService.checkForUpdates(...)` calls.

- [ ] **Step 4: Run full test suite and build universal app bundle**

Run: `bash scripts/test.sh && bash scripts/build-app.sh`
Expected: 100% of test suites PASS with zero warnings, and `Built /Users/karyl/CaitDev/CaitlynSwift/build/VRemind.app` succeeds.

- [ ] **Step 5: Commit**

```bash
git add Sources/VRemindKit/Services/UpdateService.swift Sources/VRemind/AppDelegate.swift Sources/VRemind/PreferencesWindowController.swift Sources/VRemind/OnboardingWindowController.swift Sources/VRemind/UpdateAvailableWindowController.swift Tests/VRemindKitTests/UpdateServiceTests.swift
git commit -m "feat: wire NSPopoverDelegate, Darwin background priority, and Low Power Mode update deferral"
```
