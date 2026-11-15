# Laptop & Low Power Mode Optimization Design

- **Date:** 2026-11-15
- **Status:** Ready for Approval
- **Target:** `CaitlynSwift` (`VRemind` + `VRemindKit`, `macOS 12.0+` `arm64` + `x86_64`)

---

## 1. Intent & The Why

VRemind was originally developed and profiled on a desktop computer running on continuous wall power. When running on a laptop—specifically an M1 MacBook Air on battery with macOS Low Power Mode enabled—Activity Monitor revealed two distinct power problems:

1. **Random browser-scale energy spikes (`3,004.4` Energy Impact, `App Nap: No`, Battery menu flagging "Using Significant Energy"):**
   - `AppDelegate` keeps a single `NSPopover` and `NSHostingController<MenuBarStatusView>` alive for the entire process lifetime for instant popover responsiveness.
   - `MenuBarStatusView` gates `ConfettiOverlayView` on `isPopoverVisible`, **but `.rainbowForeground` (`RainbowStyle.swift` / `RainbowGradientView`) is never gated on popover visibility**.
   - Whenever any watched channel enters `.live` or `.upcoming` with a celebration keyword (birthday, debut, anniversary, etc.) or on December 31st, multiple `TimelineView(.animation)` render loops (three inside `StatusBadge` alone, plus `ChannelRowView` subtitles and `MenuBarStatusView` section headers) run continuously at 60 fps inside the closed, hidden popover. Even with `Reduce Motion` enabled, `RainbowGradientView` still mounts `TimelineView(.animation)` (only stretching `cycleDuration` from `3.0s` to `10.0s`). This blocks macOS App Nap and explains why extreme energy spikes appear "randomly."

2. **High baseline 12-hour energy draw (`136.68`, nearly matching an active multi-tab browser) and zero Low Power Mode / laptop adaptation:**
   - **No power-tier awareness:** `StreamMonitorService` polls every `180s` in batches of `3` regardless of AC power, unplugged battery, or `ProcessInfo.processInfo.isLowPowerModeEnabled`.
   - **No-op 3-minute disk, SwiftUI, and WidgetKit churn:**
     - `ChannelStore.updateMetadata` and `ChannelStore.updateStatus` unconditionally set `changed = true`, re-encode JSON to `UserDefaults`, and publish `@Published var channels` every poll even when channel metadata and status are identical (`updateStatus` also stamps `lastStreamedAt = Date()` on every live poll if `startedAt == nil`).
     - `StreamMonitorService.performRefreshPass` mutates `@Published var statuses` repeatedly even when unchanged and unconditionally calls `exportWidgetSnapshot()`, rewriting `widget-cache.json` and calling `WidgetCenter.shared.reloadAllTimelines()` every 180s (waking `VRemindWidget.appex` continuously).
   - **Missing sleep/priority/leeway hygiene:**
     - Sleep pausing only observes `NSWorkspace.screensDidSleepNotification` / `screensDidWakeNotification`, missing `willSleepNotification` / `didWakeNotification`.
     - Polling runs via `@MainActor` `Task.sleep(nanoseconds:)` with zero timer leeway/coalescing, default thread QoS (rather than `.background` E-core scheduling), and standard process priority (`nice 0`).

This update makes VRemind gentle on Mac laptops—stopping all offscreen animation and no-op churn, adapting polling and visuals across AC / Battery / Low Power Mode tiers, and running VRemind at macOS's lowest background priority whenever the UI is closed.

---

## 2. Goals, Non-Goals, & Anti-Goals

### Goals
- **Eliminate offscreen rendering and restore App Nap:** Zero `TimelineView` or animation timers active when the menu bar popover is closed, achieving ~0.0% idle CPU and App Nap eligibility even when celebration streams are live or upcoming.
- **Stop unnecessary 3-minute churn:** Only mutate `ChannelStore`, publish `statuses`, write `widget-cache.json`, or call `WidgetCenter.shared.reloadAllTimelines()` when data has actually changed.
- **Three-tier power scaling (AC / Battery / Low Power Mode):**
  - **Normal (AC power, Low Power Mode off):** `180s` (3 min) poll interval, `30s` timer leeway, batch size `3`, animations enabled (unless `reduceMotion`).
  - **Battery (unplugged, Low Power Mode off):** `360s` (6 min) poll interval, `60s` timer leeway, batch size `2`, animations enabled (unless `reduceMotion`).
  - **Low Power Mode (`ProcessInfo.processInfo.isLowPowerModeEnabled == true`, any power source):** `900s` (15 min) poll interval, `180s` timer leeway, batch size `1` (serialized), all popover animations & confetti paused/static even when the popover is open, and periodic background GitHub update checks skipped/deferred while Low Power Mode is active.
- **Lowest scheduling priority on macOS / Apple Silicon:**
  - Set POSIX process niceness to `PRIO_MAX` (`+20`) at launch.
  - Engage Darwin background priority (`PRIO_DARWIN_PROCESS` / `PRIO_DARWIN_BG`) whenever all VRemind UI surfaces (popover, Preferences, Onboarding, Update Available windows) are closed, and temporarily lift `PRIO_DARWIN_BG` while any UI surface is open so clicks stay immediate.
  - Run background polling, engine fetches/parsing, and widget snapshot exports at `.background` QoS off `@MainActor` (pinned to M1 Efficiency cores), using an ephemeral `.background` `networkServiceType` `URLSession`.
- **Complete sleep/wake resilience:** Pause polling on both display sleep (`screensDidSleep`) and system sleep (`willSleep`), and resume cleanly on wake (while re-evaluating the current power tier).

### Non-Goals
- Modifying `VRemindCore` (under parallel feature work elsewhere; `Package.swift` remains pinned to `VRemindCore` `1.0.0`).
- Adding manual battery/polling-interval controls to `PreferencesView` (scaling responds automatically to macOS AC/Battery and Low Power Mode state).
- Completely disabling background stream notifications during Low Power Mode (alerts stay active at the throttled 15-minute cadence).
- Removing static rainbow celebration styling when `reduceMotion` or Low Power Mode is active and the popover is open.

### Anti-Goals
- Leaving `PRIO_DARWIN_BG` active while the user is interacting with the popover or Preferences window (causes sluggish UI responsiveness).
- Using `NSBackgroundActivityScheduler` for normal AC polling (OS-enforced indefinite deferrals break predictable 3-minute live alerts).
- Introducing third-party SwiftPM dependencies or macOS 13+-only APIs without Monterey compatibility.

---

## 3. Constraints

- **Command Line Tools Only:** Everything must compile, pass tests (`bash scripts/test.sh`), and bundle `VRemind.app` + `VRemindWidget.appex` (`bash scripts/build-app.sh`) using only Xcode CLT on macOS 12.0+ (`arm64` + `x86_64`).
- **Apple SDK Frameworks Only:** Uses only `Foundation`, `AppKit`, `SwiftUI`, `Combine`, `UserNotifications`, `WidgetKit`, `AVKit`, `IOKit.ps`, and `Darwin` (no third-party packages).
- **macOS 12 Monterey Compatibility:** `ProcessInfo.processInfo.isLowPowerModeEnabled` and `Notification.Name.NSProcessInfoPowerStateDidChange` are macOS 12.0+ APIs; `IOKit.ps` (`IOPSCopyPowerSourcesInfo`, `IOPSGetProvidingPowerSourceType`, `IOPSNotificationCreateRunLoopSource`) and `Darwin.setpriority` are supported across macOS 12+.
- **Boundary Discipline:** All stream scraping/parsing remains inside `VRemindCore` (`1.0.0`); `VRemindKit` and `VRemind` handle scheduling, power/priority policy, UI lifecycle, and persistence/widget diffing.
- **Test Isolation:** Unit tests must never leak `PRIO_DARWIN_BG` onto the `swift test` runner process or perform real network requests.

---

## 4. Approaches Considered

### Approach 1: `CaitlynSwift`-Only Optimization with Coalesced Leeway Timer & Dynamic Priority *(Chosen)*
Keep `VRemindCore` untouched at `1.0.0` and build all fixes inside `VRemindKit` and `VRemind`:
- Fix `NSPopoverDelegate`-backed visibility and eliminate offscreen/paused `TimelineView` loops.
- Add equality guards to `ChannelStore`, `StreamMonitorService`, and `WidgetSnapshotStore` to stop no-op disk writes, SwiftUI redraws, and `WidgetCenter` reloads.
- Introduce `PowerStateMonitor` (observing `ProcessInfo` Low Power Mode + `IOKit.ps` power source) and `ProcessPriorityManager` (`PRIO_MAX` + UI-aware `PRIO_DARWIN_BG`).
- Drive `StreamMonitorService` via a leeway-tolerant `.background` QoS timer that dynamically creates/selects `StreamMonitorEngine(batchSize:)` (3 / 2 / 1) and uses a `.background` `URLSessionConfiguration.ephemeral` fetcher.
- **Trade-off:** Self-contained in one repository with zero upstream release coordination while eliminating the 60 fps leak, App Nap block, WidgetKit wakeups, and Low Power Mode polling overhead. `YouTubeStreamProvider` inside `VRemindCore` still parses HTML/JSON twice per channel during each poll pass.

### Approach 2: Full-Stack (`CaitlynSwift` + `VRemindCore` `1.0.1`)
Everything in Approach 1, plus refactoring `YouTubeStreamProvider.parseHTML` and `LivePageParser` in `VRemindCore` so HTML/JSON extraction happens in a single pass per channel.
- **Trade-off:** Roughly halves YouTube parsing CPU/allocations per poll, but requires coordinating a `VRemindCore` update/tag while `VRemindCore` is actively being modified for other features.

### Approach 3: System-Managed `NSBackgroundActivityScheduler`
Same UI, diffing, and priority fixes as Approach 1, but delegate poll scheduling to macOS `NSBackgroundActivityScheduler`.
- **Trade-off:** Maximum OS energy heuristic integration, but macOS frequently defers `NSBackgroundActivityScheduler` well past the target interval even on AC power, degrading live stream alert timeliness and test determinism.

**Why Approach 1 won:** `CaitlynSwift` already consumes `VRemindCore` remotely at `1.0.0`, and `StreamMonitorEngine.init(registry:batchSize:)` + injectable `HTTPFetcher` already expose everything `StreamMonitorService` needs to adapt concurrency, QoS, and networking per power tier without touching `VRemindCore`.

---

## 5. Architecture & Detailed Component Design

### 5.1 Power Policy & Monitoring (`PowerStateMonitor.swift`)

Introduce value types and a main-actor observable monitor in `Sources/VRemindKit/Services/PowerStateMonitor.swift`:

- `public enum PowerSource: Equatable, Sendable { case ac, battery }`
- `public enum PowerTier: Equatable, Sendable { case normal, battery, lowPowerMode }`
- `public struct PowerPolicy: Equatable, Sendable`:
  - `tier: PowerTier`
  - `pollInterval: TimeInterval`
  - `timerLeeway: TimeInterval`
  - `batchSize: Int`
  - `animationsPaused: Bool`
  - `deferBackgroundUpdateChecks: Bool`
- **Tier Mapping:**
  - `isLowPowerModeEnabled == true` (overrides AC/Battery) -> `.lowPowerMode`:
    - `pollInterval = 900`, `timerLeeway = 180`, `batchSize = 1`, `animationsPaused = true`, `deferBackgroundUpdateChecks = true`
  - `source == .battery` && `!isLowPowerModeEnabled` -> `.battery`:
    - `pollInterval = 360`, `timerLeeway = 60`, `batchSize = 2`, `animationsPaused = false`, `deferBackgroundUpdateChecks = false`
  - `source == .ac` && `!isLowPowerModeEnabled` -> `.normal`:
    - `pollInterval = AppConstants.livePollInterval` (`180`), `timerLeeway = 30`, `batchSize = 3`, `animationsPaused = false`, `deferBackgroundUpdateChecks = false`
- **Detection & Live Observation:**
  - Protocol / injectable closures (`powerSourceProvider: @Sendable () -> PowerSource`, `lowPowerModeProvider: @Sendable () -> Bool`, `notificationCenter: NotificationCenter`) so tests can simulate AC, battery, and Low Power Mode transitions deterministically.
  - Default `lowPowerModeProvider` reads `ProcessInfo.processInfo.isLowPowerModeEnabled` and observes `Notification.Name.NSProcessInfoPowerStateDidChange` (hopping onto `@MainActor` before mutating `@Published public private(set) var currentPolicy`).
  - Default `powerSourceProvider` calls `IOPSCopyPowerSourcesInfo()` + `IOPSGetProvidingPowerSourceType()`: maps `kIOPMBatteryPowerValue` (`"Battery Power"`) to `.battery`, and `"AC Power"`, `"UPS Power"`, or `nil` (desktop Macs / Hackintoshes without a battery) to `.ac`.
  - Live AC/battery changes register an `IOPSNotificationCreateRunLoopSource` on `CFRunLoopGetMain()` (only when live system power monitoring is enabled in default init) and remove the `CFRunLoopSource` in `deinit`.
  - `currentPolicy` only updates (and publishes `objectWillChange`) when the resolved `PowerPolicy` actually differs from the previous value.

### 5.2 Dynamic Process Priority (`ProcessPriorityManager.swift`)

Introduce `ProcessPriorityManager` in `Sources/VRemindKit/Services/ProcessPriorityManager.swift`:

- **Testable Seam:** Inject a `PriorityBackend` closure/protocol (`applyNice: (Int32) -> Void`, `setBackgroundState: (Bool) -> Void`), with a `DarwinPriorityBackend` using `Darwin.setpriority` for the real app and a no-op or spy backend for unit tests.
- **UISurface Token Tracking:**
  - `public enum UISurface: Hashable, Sendable { case popover, preferences, onboarding, updateAvailable }`
  - `private var activeSurfaces: Set<UISurface> = []`
- **Behavior:**
  - `applyLaunchBaseline()`: calls `setpriority(PRIO_PROCESS, 0, PRIO_MAX)` (`+20` nice) and immediately applies `PRIO_DARWIN_BG` if `activeSurfaces.isEmpty`.
  - `beginUIActivity(_ surface: UISurface)`: inserts `surface`; if transitioning from empty -> non-empty, clears Darwin background throttling (`setpriority(PRIO_DARWIN_PROCESS, 0, 0)`).
  - `endUIActivity(_ surface: UISurface)`: removes `surface`; if transitioning from non-empty -> empty, engages `setpriority(PRIO_DARWIN_PROCESS, 0, PRIO_DARWIN_BG)`.
  - App integration: `AppDelegate` calls `applyLaunchBaseline()` at launch and wires `beginUIActivity` / `endUIActivity` into `NSPopoverDelegate` (`popoverWillShow` / `popoverDidClose`) and the window controllers (`PreferencesWindowController`, `OnboardingWindowController`, `UpdateAvailableWindowController` on show/close).
  - *Constraint check:* Updating `@AppStorage`/tests never invokes `DarwinPriorityBackend` unless explicitly constructed, ensuring `swift test` never throttles the test runner process.

### 5.3 Popover Visibility, Animation Gating & Window Lifecycle

1. **Reliable Popover Visibility (`AppDelegate.swift` + `MenuBarStatusView.swift`):**
   - Add `@Published public var isPopoverVisible: Bool = false` to `MenuBarStatusViewModel`.
   - Set `AppDelegate` (or a dedicated `PopoverVisibilityCoordinator`) as `popover.delegate` (`NSPopoverDelegate`):
     - `popoverWillShow(_:)`: sets `viewModel.isPopoverVisible = true` and `priorityManager.beginUIActivity(.popover)`.
     - `popoverDidClose(_:)`: sets `viewModel.isPopoverVisible = false` and `priorityManager.endUIActivity(.popover)`.
   - Keep SwiftUI `.onAppear` / `.onDisappear` on `MenuBarStatusView` syncing `viewModel.isPopoverVisible` idempotently so standalone SwiftUI rendering remains consistent, while relying on `NSPopoverDelegate` as the authoritative AppKit lifecycle signal.
   - Because `isPopoverVisible` initializes to `false`, creating the `NSPopover` at app launch never mounts `TimelineView`.

2. **Eliminate Unbounded `TimelineView` Loops (`RainbowStyle.swift`, `StatusBadge.swift`, `ChannelRowView.swift`, `MenuBarStatusView.swift`, `ConfettiOverlayView.swift`):**
   - Update `RainbowGradientView` and `RainbowTextModifier` (`.rainbowForeground(active:animate:reduceMotion:)` with sensible defaults `animate: Bool = true, reduceMotion: Bool = false`):
     - When `active == false`: render `content` unchanged.
     - When `active == true && !isVisible` (or when `animate == false` and popover is closed): render `content` with **no** `TimelineView`, gradient, or mask.
     - When `active == true && isVisible && (reduceMotion || animationsPaused)`: render a **static** `LinearGradient` masked to `content`—zero `TimelineView(.animation)` in the view hierarchy.
     - When `active == true && isVisible && !reduceMotion && !animationsPaused`: animate with `TimelineView(.animation(minimumInterval: 1.0 / 30.0))` (matching `ConfettiOverlayView`'s 30 fps cap rather than unthrottled 60/120 fps).
   - Also check `MenuBarStatusViewModel.isPopoverConfettiActive(date:)`:
     - Return `false` if `preferencesStore.settings.reduceMotion` **or** `powerMonitor?.currentPolicy.animationsPaused == true` (Low Power Mode).
   - Also check `MenuBarStatusView` gating:
     - `MenuBarStatusView` passes `isPopoverVisible` and `animationsPaused` (from `powerMonitor`) down to `sectionBlock`, `ChannelRowView`, and `StatusBadge`, so **zero** `TimelineView` instances exist when the popover is closed or in Low Power Mode.
   - Also check `UpdateAvailableWindowController.windowWillClose`:
     - Clear `window?.contentViewController = nil` in `windowWillClose` (after checking `currentController === self`) to guarantee immediate teardown of `MarkdownVideoPlayerView` / `AVPlayer` even when closed via the window close button.

### 5.4 Store & Widget Diffing (`ChannelStore.swift`, `WidgetSnapshotStore.swift`, `StreamMonitorService.swift`)

1. **`ChannelStore` Equality Guards:**
   - `updateMetadata(for:name:avatarURL:)`: build a candidate `WatchedChannel`, update `name` only if non-empty and different from current `name`, update `avatarURL` only if non-nil and different from current `avatarURL`. Mutate `channels[index]` and call `save()` **only if `updated != existing`**.
   - `updateStatus(for:status:notifiedLiveId:notifiedUpcomingId:)`:
     - Only set `lastNotifiedVideoId` / `lastNotifiedUpcomingId` if different.
     - For `.live(_, _, let startedAt)`: if `startedAt` is non-nil, only assign `lastStreamedAt = startedAt` if different from existing `lastStreamedAt`. If `startedAt == nil`, only assign `Date()` if `existing.lastStreamedAt == nil` **or** `StreamMonitorService` passes an explicit live-transition flag (i.e., channel just transitioned from non-live or changed `videoId`—do **not** stamp `Date()` on every steady-state 3-minute poll of the same live stream!).
     - For `.offline(let lastStreamed)`: only assign `lastStreamedAt = lastStreamed` if non-nil and different.
     - Mutate `channels[index]` and call `save()` **only if `updated != existing`**.

2. **`StreamMonitorService` Event & State Guards:**
   - Guard `.statusUpdated(channelId, status)` in `handleMonitorEvent`: only write `statuses[channelId] = status` if `statuses[channelId] != status`, and only call `channelStore.updateStatus(...)` when the status changed (or `startedAt` / `lastStreamedAt` needs updating).
   - At the end of `performRefreshPass`: only assign `self.statuses = filteredStatuses` if `self.statuses != filteredStatuses` (and ignore redundant `.refreshFinished` re-assignment when final status dictionary already matches).

3. **`WidgetSnapshotStore` Content Diffing & Ephemeral Session:**
   - In `WidgetSnapshotStore.init`, default `urlSession` to a dedicated ephemeral `URLSession` (`URLSessionConfiguration.ephemeral`, `urlCache = nil`, `networkServiceType = .background`) instead of `URLSession.shared`.
   - In `writeSnapshot(channels:statuses:)`:
     - Download/cache missing avatars first and track whether any new avatar file was written (`didWriteAvatar: Bool`).
     - Compute `let sorted = Self.sortChannels(items)`.
     - Compare `sorted` against the last snapshot (`lastWrittenChannels` in memory, or `readSnapshot()?.channels` if `cacheFileURL` exists on disk).
     - If `fileManager.fileExists(atPath: cacheFileURL.path)` **and** `existingChannels == sorted` **and** `!didWriteAvatar`: return immediately without re-encoding `widget-cache.json` or calling `timelineReloader?()` (`WidgetCenter.shared.reloadAllTimelines()`).

### 5.5 Power-Aware Background Polling & Sleep Handling (`StreamMonitorService.swift`)

- **Dedicated `.background` `URLSession` for default HTTP fetching:**
  - When `StreamMonitorService` creates its default `httpFetcher` (no custom `fetcher`/`httpFetcher` injected), use a dedicated `URLSessionConfiguration.ephemeral` with:
    - `urlCache = nil`
    - `requestCachePolicy = .reloadIgnoringLocalCacheData`
    - `timeoutIntervalForRequest = 15`
    - `networkServiceType = .background`
- **Background QoS Execution:**
  - Execute `engine.refreshPass(...)` and `snapshotStore.writeSnapshot(...)` inside `Task.detached(priority: .background)` so Apple Silicon schedules network callbacks, HTML/JSON parsing, and JSON disk serialization strictly on **Efficiency cores**, hopping back to `@MainActor` only to process `MonitorEvent` diffs and update `@Published` properties.
- **Coalesced Leeway Scheduling + Power-Tier Adaptation:**
  - Inject optional `powerMonitor: PowerStateMonitor` (defaulting to a shared or newly created instance) and an injectable scheduling mechanism (or `DispatchSourceTimer` on a `.background` QoS `DispatchQueue` with explicit `leeway` = `policy.timerLeeway`!).
  - When `startPolling(interval: TimeInterval? = nil)` is called:
    - If an explicit `interval` is passed (e.g., unit tests passing `interval: 0.05` or `3600`), honor that fixed interval with proportional leeway (`min(interval * 0.1, 30)`).
    - When `interval == nil` (production app launch), dynamically follow `powerMonitor.currentPolicy`:
      - Run an initial refresh immediately, then schedule the next poll after `policy.pollInterval` with `policy.timerLeeway` on a `.background` QoS queue.
      - Observe `powerMonitor.$currentPolicy`: when the tier changes while polling is active (e.g., user unplugs charger or enables Low Power Mode), reschedule the next timer cleanly without triggering an unnecessary extra fetch immediately (Wait: if transitioning *up* to AC / normal from a long Low Power Mode wait and elapsed time since last refresh exceeds the new shorter interval, reschedule/trigger appropriately; if transitioning *down* to Battery/Low Power Mode, simply stretch the upcoming deadline).
  - Select `batchSize` per pass using `StreamMonitorEngine(registry: providerRegistry, batchSize: powerMonitor.currentPolicy.batchSize)` (or cache engines by batch size 1, 2, 3), unless overridden in tests.
- **System + Display Sleep/Wake:**
  - Observe **both** display sleep/wake (`NSWorkspace.screensDidSleepNotification` / `screensDidWakeNotification`) and system sleep/wake (`NSWorkspace.willSleepNotification` / `didWakeNotification`).
  - Note for existing test `testDisplaySleepPausesAndWakeResumesPolling` and `testDeallocationCleansUpObserversAndStopsPolling`:
    - Update `testDeallocationCleansUpObserversAndStopsPolling` cleanly to reflect the expanded sleep/wake observers (or verify all registered observer tokens are removed on `deinit`).
    - When waking from sleep (`isPausedForSleep` transitions `true -> false`), re-evaluate `powerMonitor.refresh()` before restarting the polling timer so any power-source / Low Power Mode change that happened during sleep takes effect immediately.

### 5.6 Low Power Mode Update Deferral (`AppDelegate.swift` + `UpdateService.swift`)

- In `UpdateService.swift`, default `session` to a lightweight ephemeral `URLSession` (`urlCache = nil`, `.background` service type) instead of `URLSession.shared`.
- In `AppDelegate`:
  - `performPeriodicUpdateCheck()` (the 24-hour background timer) and automatic launch update check (`performLaunchUpdateCheck()`) check `!powerMonitor.currentPolicy.deferBackgroundUpdateChecks` (`!isLowPowerModeEnabled`) before hitting GitHub API.
  - Set `updateTimer?.tolerance = 3_600` (1 hour coalescing tolerance on the 24-hour timer!).
  - Manual "Check for Updates Now" in `PreferencesView` remains unrestricted.

---

## 6. Verification Strategy

1. **Automated Tests (`Tests/VRemindKitTests/`):**
   - `PowerStateMonitorTests`: policy tier resolution (`AC -> normal`, `Battery -> battery`, `Low Power Mode on AC or Battery -> lowPowerMode`), duplicate policy suppression, live notification & power-source change transitions.
   - `ProcessPriorityManagerTests`: baseline nice `+20` call, balanced `beginUIActivity` / `endUIActivity` reference behavior across multiple surfaces (e.g., opening Preferences while popover closes keeps `PRIO_DARWIN_BG` off until all surfaces close).
   - `ChannelStoreTests` & `WidgetSnapshotStoreTests`: verify identical `updateMetadata` / `updateStatus` calls do not rewrite `UserDefaults` or emit duplicate `channels` updates, and identical `writeSnapshot` calls do not rewrite `widget-cache.json` or increment `timelineReloader`.
   - `StreamMonitorServiceTests`: power-tier interval/batchSize adaptation (`batchSize == 1` in Low Power Mode, `2` on battery, `3` on AC), `willSleep` / `didWake` pausing and resuming alongside `screensDidSleep` / `screensDidWake`, observer cleanup on `deinit`, unchanged refresh passes not emitting `statuses` churn.
   - `MenuBarViewTests`: `RainbowTextModifier` renders static content (zero `TimelineView`) when popover is hidden, when `reduceMotion == true`, or when `animationsPaused == true`; `isPopoverConfettiActive` returns `false` under Low Power Mode.
2. **Build & Bundle Verification:**
   - `bash scripts/test.sh` passes 100% with zero warnings.
   - `bash scripts/build-app.sh` produces universal `build/VRemind.app` + `VRemindWidget.appex`.
3. **Runtime Power Validation (manual check on Mac):**
   - Launch built `VRemind.app` with a celebrating stream active while popover stays closed: verify `App Nap: Yes` and `0.0%` CPU / negligible Energy Impact in Activity Monitor.
   - Toggle Low Power Mode and verify polling throttles to 15-minute serialized passes and confetti/rainbow animations freeze.

---

## 7. What Is Left to the Builder

- Exact placement/wiring of `PowerStateMonitor` and `ProcessPriorityManager` ownership inside `AppDelegate` vs `StreamMonitorService` default arguments (preserving existing convenience initializers for tests).
- Whether `Package.swift` needs an explicit `.linkedFramework("IOKit")` linker setting for `VRemindKit` under Xcode CLT SwiftPM.
- Exact `DispatchSourceTimer` / cancellable timer wrapper implementation details in `StreamMonitorService` so sleep/wake, tier changes, and `deinit` cancel cleanly without retain cycles.
- Checking `Swift` strict concurrency (`Sendable`) annotations across the new `PowerStateMonitor` / `ProcessPriorityManager` helpers so `swift build -c release` emits zero warnings.
