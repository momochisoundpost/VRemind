# Celebration Mode & Holiday Easter Egg Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add multilingual celebration keyword detection, rainbow UI styling, non-Metal popover confetti rain, a Reduce Motion accessibility toggle, and a December 31st developer birthday easter egg with mailto notification to VRemind.

**Architecture:** A pure `CelebrationDetector` service evaluates stream titles (English, Indonesian, Japanese) and calendar dates (Dec 31, year > 1999) independently from scraping and UI. Visual effects layer onto SwiftUI views using macOS 12 Monterey-compatible `LinearGradient`, `TimelineView`, and CPU-rasterized `Canvas` particles gated by `AppSettings.reduceMotion`. Birthday notifications hook into `ChannelStore` addition and `StreamMonitorService` refresh/launch cycles with yearly throttling via `AppSettings.lastNotifiedDevBirthdayYear`.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit, UserNotifications, Swift Testing (`Testing` framework), SwiftPM (`./scripts/test.sh`, `./scripts/build-app.sh`).

**Spec:** [docs/superpowers/specs/2026-11-12-celebration-mode-design.md](file:///Users/karyl/CaitDev/CaitlynSwift/docs/superpowers/specs/2026-11-12-celebration-mode-design.md)

## Global Constraints

- **Target Platform:** macOS 12.0 Monterey (`.macOS(.v12)`) and newer; no macOS 13+ exclusive APIs (avoid `NavigationStack`, `View.scrollIndicators`, `ImageRenderer`).
- **Non-Metal GPU Compatibility:** No SpriteKit (`SKView`), Metal shaders, or WebKit overlays; use CPU-safe SwiftUI `Canvas`, `TimelineView`, and `LinearGradient`.
- **Zero Idle Overhead:** Popover particle animations must halt completely when the popover closes or when `reduceMotion == true`.
- **Standard URL Scheme Security:** Developer birthday `mailto:` URLs must be opened via `NSWorkspace` / `urlOpener` (`mailto:y2karyl@disroot.org?subject=Happy%20Birthday%20Caitlyn!`).
- **Backward-Compatible Persistence:** `AppSettings` must decode older JSON payloads cleanly without losing existing user preferences.

## Review Focus

1. **Year `<= 1999` or non-Dec-31 boundary on Caitlyn Momochi:** Dec 31, 1999 or Dec 30 / Jan 1 of any year must not trigger `.developerBirthday` or birthday notifications; only Dec 31 with `year > 1999` triggers it. (Pinned in Task 1 & Task 4)
2. **Word-boundary & mixed-script title matching:** Substrings inside unrelated English words (`"unbirthday"`, `"annihilation"`) must not false-trigger, while mixed-script titles (`"【初配信/DEBUT】"`, `"Ultah ke-3!"`, `"生誕祭2026"`) must match accurately. (Pinned in Task 1)
3. **Far-future upcoming streams vs. today-scheduled streams for confetti:** An upcoming celebration stream scheduled more than a day away must show rainbow row/header accents without triggering popover confetti (`shouldShowConfetti == false`), whereas live or today-scheduled celebration streams trigger confetti. (Pinned in Task 1 & Task 5)
4. **Yearly notification throttling on Dec 31:** Once the developer birthday notification fires in year $Y$, `lastNotifiedDevBirthdayYear` is set to $Y$ so repeat polling cycles, app launches, or re-adding Caitlyn in year $Y$ do not re-notify, while year $Y + 1$ fires cleanly. (Pinned in Task 4)
5. **Legacy `AppSettings` JSON decoding:** Existing v1.1 `UserDefaults` JSON lacking `reduceMotion` and `lastNotifiedDevBirthdayYear` must decode with `reduceMotion == false` and `lastNotifiedDevBirthdayYear == nil` while keeping all prior settings. (Pinned in Task 2)

---

## File Structure

- **Create:** `Sources/VRemindKit/Services/CelebrationDetector.swift` — Pure keyword matching (EN/ID/JA), Dec 31 > 1999 holiday detection, and confetti-window scoping.
- **Create:** `Sources/VRemindKit/Views/Components/RainbowStyle.swift` — macOS 12-compatible rainbow gradient text/badge view modifier with normal and reduced-motion animation speeds.
- **Create:** `Sources/VRemindKit/Views/Components/ConfettiOverlayView.swift` — macOS 12 SwiftUI `TimelineView` + `Canvas` software-drawn confetti rain with deterministic/bounded particles.
- **Create:** `Tests/VRemindKitTests/CelebrationDetectorTests.swift` — Unit tests for `CelebrationDetector`.
- **Modify:** `Sources/VRemindKit/Models/AppSettings.swift` — Add `reduceMotion: Bool` and `lastNotifiedDevBirthdayYear: Int?` with backward-compatible `Codable`.
- **Modify:** `Sources/VRemindKit/Views/Preferences/PreferencesView.swift` — Add Reduce Motion toggle in General tab.
- **Modify:** `Sources/VRemindKit/Services/NotificationService.swift` — Add `notifyDeveloperBirthday(year:playSound:)` and handle `"mailto"` URL action on notification click.
- **Modify:** `Sources/VRemindKit/Services/StreamMonitorService.swift` — Inject `Date` provider (default `Date.init`) and trigger Dec 31 developer birthday check on `refreshAll()`.
- **Modify:** `Sources/VRemindKit/Views/Components/StatusBadge.swift` — Support optional `label`, `isCelebration`, and `reduceMotion` rainbow styling.
- **Modify:** `Sources/VRemindKit/Views/MenuBar/ChannelRowView.swift` — Apply celebration detection to live/upcoming status badges and time subtitles.
- **Modify:** `Sources/VRemindKit/Views/MenuBar/MenuBarStatusView.swift` — Add Dec 31 notification trigger on `addChannel()`, expose confetti/header celebration state, layer `ConfettiOverlayView`, and provide `shouldFlashStatusButton(isAnyLive:reduceMotion:)`.
- **Modify:** `Sources/VRemind/AppDelegate.swift` — Observe `reduceMotion` to stop/suppress `flashTimer`, and run Dec 31 birthday check at launch.
- **Modify Tests:** `PreferencesStoreTests.swift`, `PreferencesViewTests.swift`, `NotificationServiceTests.swift`, `StreamMonitorServiceTests.swift`, `MenuBarViewTests.swift`.

---

### Task 1: CelebrationDetector Service (Keywords, Dec 31 Rules, Confetti Window)

**Files:**
- Create: `Sources/VRemindKit/Services/CelebrationDetector.swift`
- Test: `Tests/VRemindKitTests/CelebrationDetectorTests.swift`

**Interfaces:**
- Produces:
  - `public enum CelebrationType: Equatable, Sendable { case birthday, debut, anniversary, developerBirthday }`
  - `public struct CelebrationResult: Equatable, Sendable { public let isCelebration: Bool; public let type: CelebrationType?; public let matchedKeyword: String?; public static let none: CelebrationResult }`
  - `public enum CelebrationDetector: Sendable` with:
    - `public static func detect(title: String) -> CelebrationResult`
    - `public static func isTargetDeveloperChannel(_ channel: WatchedChannel) -> Bool`
    - `public static func isDeveloperBirthday(date: Date = Date(), calendar: Calendar = .current) -> Bool`
    - `public static func detect(status: StreamStatus, channel: WatchedChannel, date: Date = Date(), calendar: Calendar = .current) -> CelebrationResult`
    - `public static func shouldShowConfetti(channels: [WatchedChannel], statuses: [String: StreamStatus], date: Date = Date(), calendar: Calendar = .current) -> Bool`

- [ ] **Step 1: Write the failing tests in `Tests/VRemindKitTests/CelebrationDetectorTests.swift`**

Include tests covering:
- `testEnglishKeywords()`: matches `"My Birthday Stream!"`, `"3D Bday Party"`, `"VTuber Debut Stream"`, `"Re-Debut Announcement"`, `"3rd Anniversary"`, `"2nd Anni"` -> expected `CelebrationType`, and rejects `"unbirthday"` and `"annihilation"`.
- `testIndonesianKeywords()`: matches `"Stream Ultah ke-20"`, `"Ulang Tahun Bareng"`, `"Hari Jadi Channel"`, `"Anniv 1 Tahun"`.
- `testJapaneseKeywords()`: matches `"【生誕祭】お祝い"`, `"誕生日配信"`, `"バースデーライブ"`, `"【初配信/DEBUT】"`, `"新衣装お披露目"`, `"3周年記念配信"`, `"記念枠"`, `"1周年ありがとう"`.
- `testDeveloperBirthdayDateBoundary()`: `isDeveloperBirthday(date:calendar:)` returns `true` for Dec 31, 2000 and Dec 31, 2026; returns `false` for Dec 31, 1999, Dec 30, 2026, and Jan 1, 2027.
- `testTargetChannelDetection()`: `isTargetDeveloperChannel` matches `@bukancaitlyn`, `BUKANCAITLYN`, and display name `"Caitlyn Momochi"`; rejects `"@othervtuber"`.
- `testShouldShowConfettiScope()`:
  - Live celebration stream -> `true`
  - Upcoming celebration stream scheduled later today (`date + 3600s`) -> `true`
  - Upcoming celebration stream scheduled 3 days in future (`date + 3*86400s`) -> `false` (even though `detect(...)` for that row returns `isCelebration == true`)
  - Offline `@bukancaitlyn` on Dec 31, 2026 -> `true`
  - Offline `@bukancaitlyn` on Nov 12, 2026 -> `false`

- [ ] **Step 2: Run tests to verify failure**

Run: `./scripts/test.sh --filter CelebrationDetectorTests`
Expected: FAIL with compilation error (`cannot find 'CelebrationDetector' in scope`).

- [ ] **Step 3: Implement `CelebrationDetector` in `Sources/VRemindKit/Services/CelebrationDetector.swift`**

Implementation details:
- Use `NSRegularExpression` with `\b...\b` word boundaries for ASCII/Latin keywords (`birthday stream`, `birthday`, `bday`, `re-debut`, `redebut`, `debut`, `anniversary`, `anni`, `ultah`, `ulang tahun`, `hari jadi`, `anniv`) so `"unbirthday"` or `"annihilation"` do not match, and case-insensitive matching.
- Use localized substring matching for CJK keywords (`生誕祭`, `誕生日`, `バースデー`, `初配信`, `お披露目`, `周年`, `記念配信`, `記念枠`) since Japanese does not use spaces for word boundaries.
- Priority order for title checks: birthday -> debut -> anniversary.
- `detect(status:channel:date:calendar:)`: checks `.live(_, let title, _)` and `.upcoming(_, let title, _)` with `detect(title:)`; if not matched and `isTargetDeveloperChannel(channel) && isDeveloperBirthday(date: date, calendar: calendar)`, returns `.developerBirthday`.
- `shouldShowConfetti(channels:statuses:date:calendar:)`: returns `true` if any channel has `isTargetDeveloperChannel && isDeveloperBirthday`, OR any `.live` stream matches `detect(title:)`, OR any `.upcoming(_, let title, let scheduledStartTime)` matches `detect(title:)` AND (`scheduledStartTime.map { calendar.isDate($0, inSameDayAs: date) } ?? false`).

- [ ] **Step 4: Run tests to verify pass**

Run: `./scripts/test.sh --filter CelebrationDetectorTests`
Expected: PASS (all 6 tests in `CelebrationDetectorTests`).

- [ ] **Step 5: Commit**

```bash
git add Sources/VRemindKit/Services/CelebrationDetector.swift Tests/VRemindKitTests/CelebrationDetectorTests.swift
git commit -m "feat: add CelebrationDetector for EN/ID/JA milestones and Dec 31 rules"
```

---

### Task 2: AppSettings (`reduceMotion`, `lastNotifiedDevBirthdayYear`) & Preferences UI

**Files:**
- Modify: `Sources/VRemindKit/Models/AppSettings.swift:10-78`
- Modify: `Sources/VRemindKit/Views/Preferences/PreferencesView.swift:174-208`
- Test: `Tests/VRemindKitTests/PreferencesStoreTests.swift`
- Test: `Tests/VRemindKitTests/PreferencesViewTests.swift`

**Interfaces:**
- Consumes: Existing `AppSettings`, `PreferencesStore`, `PreferencesViewModel`
- Produces:
  - `AppSettings.reduceMotion: Bool` (default `false`)
  - `AppSettings.lastNotifiedDevBirthdayYear: Int?` (default `nil`)
  - Checkbox toggle `"Reduce Motion (Turn off flashing & popover confetti)"` bound to `$preferencesStore.settings.reduceMotion` in `PreferencesView.generalTab`.

- [ ] **Step 1: Write the failing tests in `PreferencesStoreTests.swift` and `PreferencesViewTests.swift`**

In `Tests/VRemindKitTests/PreferencesStoreTests.swift`:
- Add `testReduceMotionAndDevBirthdayYearPersistence()`: verifies `reduceMotion` defaults to `false`, `lastNotifiedDevBirthdayYear` defaults to `nil`, mutating both to `true` and `2026` persists across new `PreferencesStore` instances, and `resetToDefaults()` resets both.
- Update `testLegacyPreferencesDecodeGracefully()`: assert `#expect(store.settings.reduceMotion == false)` and `#expect(store.settings.lastNotifiedDevBirthdayYear == nil)` when decoding legacy 5-key JSON.

In `Tests/VRemindKitTests/PreferencesViewTests.swift`:
- Add `testReduceMotionBindingAndReset()`: verifies setting `prefs.settings.reduceMotion = true` persists and `viewModel.performFactoryReset()` resets it to `false`, and rendering `PreferencesView(viewModel: vm)` produces a valid `NSHostingController` without crashing.

- [ ] **Step 2: Run tests to verify failure**

Run: `./scripts/test.sh --filter "PreferencesStoreTests|PreferencesViewTests"`
Expected: FAIL with `value of type 'AppSettings' has no member 'reduceMotion'`.

- [ ] **Step 3: Update `AppSettings.swift` and `PreferencesView.swift`**

- In `Sources/VRemindKit/Models/AppSettings.swift`:
  - Add `public var reduceMotion: Bool` and `public var lastNotifiedDevBirthdayYear: Int?` to properties, `init` (defaulting `reduceMotion = false`, `lastNotifiedDevBirthdayYear = nil`), `CodingKeys`, `init(from:)` (`decodeIfPresent` with `?? false` and `try?`), and `encode(to:)`.
- In `Sources/VRemindKit/Views/Preferences/PreferencesView.swift`:
  - Under `generalTab` -> `"Startup"` (or a new `"Appearance & Motion"` / `"Startup & Motion"` block right below `"Launch VRemind at login"`), add:
    `Toggle("Reduce Motion (Turn off flashing & popover confetti)", isOn: $preferencesStore.settings.reduceMotion).toggleStyle(.checkbox)`

- [ ] **Step 4: Run tests to verify pass**

Run: `./scripts/test.sh --filter "PreferencesStoreTests|PreferencesViewTests"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/VRemindKit/Models/AppSettings.swift Sources/VRemindKit/Views/Preferences/PreferencesView.swift Tests/VRemindKitTests/PreferencesStoreTests.swift Tests/VRemindKitTests/PreferencesViewTests.swift
git commit -m "feat: add reduceMotion and lastNotifiedDevBirthdayYear to AppSettings and PreferencesView"
```

---

### Task 3: Developer Birthday Notification & Mailto Action

**Files:**
- Modify: `Sources/VRemindKit/Services/NotificationService.swift:75-205`
- Test: `Tests/VRemindKitTests/NotificationServiceTests.swift`

**Interfaces:**
- Consumes: Existing `NotificationService`, `NotificationCenterProtocol`, `urlOpener`
- Produces:
  - `public static let devBirthdayEmailURL: URL` (`mailto:y2karyl@disroot.org?subject=Happy%20Birthday%20Caitlyn!`)
  - `public func notifyDeveloperBirthday(year: Int, playSound: Bool) async` on `NotificationService`
  - Click handling in `NotificationService.handleNotificationClick(userInfo:)` opening `userInfo["mailtoURL"]` via `urlOpener`.

- [ ] **Step 1: Write the failing tests in `Tests/VRemindKitTests/NotificationServiceTests.swift`**

- Add `testNotifyDeveloperBirthdayPayloadAndClick()`:
  - Calls `await service.notifyDeveloperBirthday(year: 2026, playSound: true)`.
  - Asserts `mockCenter.requests.count == 1`.
  - Asserts `request.identifier == "dev-birthday-2026"`.
  - Asserts `request.content.title == "🎉 Happy Birthday to the Developer!"`.
  - Asserts `request.content.body.contains("Caitlyn Momochi")` and `request.content.sound == .default`.
  - Asserts `request.content.userInfo["mailtoURL"] as? String == "mailto:y2karyl@disroot.org?subject=Happy%20Birthday%20Caitlyn!"`.
  - Calls `service.handleNotificationClick(userInfo: request.content.userInfo)` and asserts `openedURL?.absoluteString == "mailto:y2karyl@disroot.org?subject=Happy%20Birthday%20Caitlyn!"`.
- Add `testNotifyDeveloperBirthdaySilent()`:
  - Calls with `playSound: false` and asserts `request.content.sound == nil`.

- [ ] **Step 2: Run tests to verify failure**

Run: `./scripts/test.sh --filter NotificationServiceTests`
Expected: FAIL with `value of type 'NotificationService' has no member 'notifyDeveloperBirthday'`.

- [ ] **Step 3: Implement `notifyDeveloperBirthday` and mailto click handling in `NotificationService.swift`**

- Add `public static let devBirthdayEmailURL = URL(string: "mailto:y2karyl@disroot.org?subject=Happy%20Birthday%20Caitlyn!")!`.
- Implement `notifyDeveloperBirthday(year: Int, playSound: Bool) async`:
  - Builds `UNMutableNotificationContent` with `title = "🎉 Happy Birthday to the Developer!"`, `body = "Today is Caitlyn Momochi's birthday! Click to send a birthday wish."`, `userInfo = ["mailtoURL": Self.devBirthdayEmailURL.absoluteString]`, `sound = playSound ? .default : nil`, `identifier = "dev-birthday-\(year)"`.
  - Adds request via `try await center.add(request)`.
- In `handleNotificationClick(userInfo:)`:
  - Before the `videoId` check, check `if let mailtoString = userInfo["mailtoURL"] as? String, let mailtoURL = URL(string: mailtoString), mailtoURL.scheme == "mailto" { urlOpener(mailtoURL); return }`.

- [ ] **Step 4: Run tests to verify pass**

Run: `./scripts/test.sh --filter NotificationServiceTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/VRemindKit/Services/NotificationService.swift Tests/VRemindKitTests/NotificationServiceTests.swift
git commit -m "feat: add developer birthday notification and mailto click handler"
```

---

### Task 4: Dec 31 Trigger Integration in StreamMonitorService & MenuBarStatusViewModel

**Files:**
- Modify: `Sources/VRemindKit/Services/StreamMonitorService.swift:30-105`
- Modify: `Sources/VRemindKit/Views/MenuBar/MenuBarStatusView.swift:65-170`
- Test: `Tests/VRemindKitTests/StreamMonitorServiceTests.swift`
- Test: `Tests/VRemindKitTests/MenuBarViewTests.swift`

**Interfaces:**
- Consumes: `CelebrationDetector.isTargetDeveloperChannel`, `CelebrationDetector.isDeveloperBirthday`, `NotificationService.notifyDeveloperBirthday`, `AppSettings.lastNotifiedDevBirthdayYear`
- Produces:
  - `StreamMonitorService.init(..., dateProvider: @escaping @Sendable () -> Date = { Date() }, calendar: Calendar = .current)` (backward-compatible defaulted parameters)
  - `public func checkDeveloperBirthdayNotificationIfNeeded(date: Date? = nil) async` on `StreamMonitorService`
  - `MenuBarStatusViewModel.init(..., dateProvider: @escaping () -> Date = { Date() }, calendar: Calendar = .current)` calling `checkDeveloperBirthdayNotificationIfNeeded` when `@bukancaitlyn` is added.

- [ ] **Step 1: Write the failing tests in `StreamMonitorServiceTests.swift` and `MenuBarViewTests.swift`**

In `Tests/VRemindKitTests/StreamMonitorServiceTests.swift`:
- Add `testDeveloperBirthdayNotificationTriggersOncePerYearOnDec31()`:
  - Create `ChannelStore` (which starts with `@bukancaitlyn`), `PreferencesStore`, `MockNotificationCenter`, `NotificationService`.
  - Inject mutable `currentDate = Dec 31, 2026`.
  - Call `await monitor.refreshAll()` -> asserts 1 `dev-birthday-2026` notification added and `preferencesStore.settings.lastNotifiedDevBirthdayYear == 2026`.
  - Call `await monitor.refreshAll()` a second time in 2026 -> asserts notification count remains 1 (throttled).
  - Advance `currentDate = Dec 31, 2027` and call `await monitor.refreshAll()` -> asserts a second notification (`dev-birthday-2027`) is sent and `lastNotifiedDevBirthdayYear == 2027`.
- Add `testDeveloperBirthdayDoesNotTriggerIn1999OrNonDec31()`:
  - Test with `Dec 31, 1999` and `Nov 12, 2026` -> asserts 0 birthday notifications sent.

In `Tests/VRemindKitTests/MenuBarViewTests.swift`:
- Add `testAddingCaitlynOnDec31TriggersDeveloperBirthdayNotification()`:
  - Remove `@bukancaitlyn` from store, configure `dateProvider` to Dec 31, 2026, set `viewModel.newHandleInput = "@bukancaitlyn"`, call `viewModel.addChannel()`, yield/await microtask, and assert `mockCenter.requests.contains(where: { $0.identifier == "dev-birthday-2026" })`.

- [ ] **Step 2: Run tests to verify failure**

Run: `./scripts/test.sh --filter "StreamMonitorServiceTests|MenuBarViewTests"`
Expected: FAIL with missing `dateProvider` parameter / missing `checkDeveloperBirthdayNotificationIfNeeded`.

- [ ] **Step 3: Implement Dec 31 notification checks in `StreamMonitorService.swift` and `MenuBarStatusView.swift`**

- In `StreamMonitorService`:
  - Add `private let dateProvider: @Sendable () -> Date` and `private let calendar: Calendar` with defaults `{ Date() }` and `.current`.
  - Add `public func checkDeveloperBirthdayNotificationIfNeeded(date: Date? = nil) async`:
    - `let now = date ?? dateProvider()`
    - Guard `CelebrationDetector.isDeveloperBirthday(date: now, calendar: calendar)`
    - Guard `channelStore.channels.contains { CelebrationDetector.isTargetDeveloperChannel($0) }`
    - `let year = calendar.component(.year, from: now)`
    - Guard `preferencesStore.settings.lastNotifiedDevBirthdayYear != year`
    - Set `preferencesStore.settings.lastNotifiedDevBirthdayYear = year` (before awaiting so concurrent tasks don't double-fire)
    - Call `await notificationService.notifyDeveloperBirthday(year: year, playSound: preferencesStore.settings.playNotificationSound)`.
  - Call `await checkDeveloperBirthdayNotificationIfNeeded()` at the start of `performRefreshPass()`.
- In `MenuBarStatusViewModel`:
  - Subscribe to `monitorService.preferencesStore.objectWillChange` in `Publishers.Merge3(...)`.
  - In `addChannel()`: after `channelStore.addChannel(...)` succeeds, inside the existing `Task { ... }` block (or alongside `refreshAll()`), `await monitorService.checkDeveloperBirthdayNotificationIfNeeded()` executes when `refreshAll()` runs — or call it directly before `refreshAll()` so even if network is slow, the notification triggers immediately on add.

- [ ] **Step 4: Run tests to verify pass**

Run: `./scripts/test.sh --filter "StreamMonitorServiceTests|MenuBarViewTests"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/VRemindKit/Services/StreamMonitorService.swift Sources/VRemindKit/Views/MenuBar/MenuBarStatusView.swift Tests/VRemindKitTests/StreamMonitorServiceTests.swift Tests/VRemindKitTests/MenuBarViewTests.swift
git commit -m "feat: trigger developer birthday notification on Dec 31 add and refresh with yearly throttle"
```

---

### Task 5: Rainbow Styling & Non-Metal Confetti Canvas Components (macOS 12 Compatible)

**Files:**
- Create: `Sources/VRemindKit/Views/Components/RainbowStyle.swift`
- Create: `Sources/VRemindKit/Views/Components/ConfettiOverlayView.swift`
- Modify: `Sources/VRemindKit/Views/Components/StatusBadge.swift:1-34`
- Modify: `Sources/VRemindKit/Views/MenuBar/ChannelRowView.swift:70-150`
- Modify: `Sources/VRemindKit/Views/MenuBar/MenuBarStatusView.swift:180-375`
- Test: `Tests/VRemindKitTests/MenuBarViewTests.swift`

**Interfaces:**
- Consumes: `CelebrationDetector.detect(...)`, `CelebrationDetector.shouldShowConfetti(...)`, `AppSettings.reduceMotion`
- Produces:
  - `public struct RainbowGradientView: View` / `extension View { public func rainbowForeground(active: Bool, reduceMotion: Bool) -> some View }` (uses `TimelineView(.animation)` when `!reduceMotion`, slower 8s cycle or gentle static `LinearGradient` when `reduceMotion`, strictly macOS 12 APIs)
  - `public struct ConfettiOverlayView: View` (`TimelineView(.animation(minimumInterval: 1.0 / 30.0))` + `Canvas` drawing 45 2D shapes without Metal)
  - `StatusBadge(isLive: Bool, label: String? = nil, isCelebration: Bool = false, reduceMotion: Bool = false)`
  - `ChannelRowView(channel: WatchedChannel, status: StreamStatus, reduceMotion: Bool = false, dateProvider: @escaping () -> Date = { Date() }, onDelete: @escaping () -> Void)`
  - `MenuBarStatusViewModel.isPopoverConfettiActive(date: Date = Date()) -> Bool`
  - `MenuBarStatusViewModel.isSectionCelebrating(_ channels: [WatchedChannel], date: Date = Date()) -> Bool`
  - `MenuBarStatusView.shouldFlashStatusButton(isAnyLive: Bool, reduceMotion: Bool) -> Bool`

- [ ] **Step 1: Write the failing tests in `Tests/VRemindKitTests/MenuBarViewTests.swift`**

- Add `testCelebrationViewModelHelpersAndStatusButtonFlashRule()`:
  - Verify `MenuBarStatusView.shouldFlashStatusButton(isAnyLive: true, reduceMotion: false) == true`
  - Verify `MenuBarStatusView.shouldFlashStatusButton(isAnyLive: true, reduceMotion: true) == false`
  - Verify `MenuBarStatusView.shouldFlashStatusButton(isAnyLive: false, reduceMotion: false) == false`
  - Verify `viewModel.isPopoverConfettiActive(date:)` returns `false` when `reduceMotion == true` even if a live birthday stream is active.
  - Verify `viewModel.isPopoverConfettiActive(date:)` returns `true` when `reduceMotion == false` and a live birthday stream is active.
  - Verify `viewModel.isPopoverConfettiActive(date:)` returns `false` for a far-future upcoming birthday stream (`date + 3*86400s`), while `viewModel.isSectionCelebrating(sections.upcoming, date:)` returns `true`.
  - Instantiate `StatusBadge(isLive: true, isCelebration: true, reduceMotion: false)`, `StatusBadge(isLive: false, label: "UPCOMING", isCelebration: true, reduceMotion: true)`, `ConfettiOverlayView()`, and `MenuBarStatusView(viewModel: viewModel)` inside `NSHostingController` to verify macOS 12 SwiftUI view construction succeeds without errors.

- [ ] **Step 2: Run tests to verify failure**

Run: `./scripts/test.sh --filter MenuBarViewTests`
Expected: FAIL with missing `shouldFlashStatusButton`, `isPopoverConfettiActive`, `isSectionCelebrating`, `ConfettiOverlayView`.

- [ ] **Step 3: Create `RainbowStyle.swift`, `ConfettiOverlayView.swift`, and update `StatusBadge.swift`, `ChannelRowView.swift`, and `MenuBarStatusView.swift`**

- `Sources/VRemindKit/Views/Components/RainbowStyle.swift`:
  - `RainbowPalette`: static array of 7 vibrant SwiftUI `Color`s (red `#FF0055`, orange `#FF9900`, yellow `#FFE600`, green `#33CC33`, cyan `#00BFFF`, purple `#9933FF`, red `#FF0055`).
  - `RainbowTextModifier`: when `active == true`, uses `TimelineView(.animation)` (3.0s cycle normally, 10.0s gentle cycle when `reduceMotion == true`) to compute shifting gradient start/end points and overlays `.mask(content)` onto the `LinearGradient`. When `active == false`, renders `content` unchanged. All APIs strictly macOS 12+.
- `Sources/VRemindKit/Views/Components/ConfettiOverlayView.swift`:
  - Lightweight particle state initialized deterministically/randomly with 45 particles (rectangles, circles, streamers) in celebration colors.
  - Uses `TimelineView(.animation(minimumInterval: 1.0 / 30.0))` + SwiftUI `Canvas` (`context.fill(...)` and `context.rotate(...)`) for 100% CPU-safe rendering on non-Metal GPUs. Set `.allowsHitTesting(false)`.
- `Sources/VRemindKit/Views/Components/StatusBadge.swift`:
  - Add optional `label: String? = nil`, `isCelebration: Bool = false`, `reduceMotion: Bool = false`.
  - When `isCelebration` is `true`, apply `.rainbowForeground(active: true, reduceMotion: reduceMotion)` to the dot, text (`label ?? (isLive ? "LIVE NOW" : "OFFLINE")`), and capsule border stroke.
- `Sources/VRemindKit/Views/MenuBar/ChannelRowView.swift`:
  - Accept `reduceMotion: Bool = false` and `dateProvider: () -> Date = { Date() }`.
  - Evaluate `let celebration = CelebrationDetector.detect(status: status, channel: channel, date: dateProvider())`.
  - Show rainbow `StatusBadge` for live celebrating streams (`isLive: true, isCelebration: celebration.isCelebration, reduceMotion: reduceMotion`) AND for upcoming celebrating streams (`isLive: false, label: "UPCOMING", isCelebration: true, reduceMotion: reduceMotion`).
  - Apply `.rainbowForeground(active: celebration.isCelebration, reduceMotion: reduceMotion)` to the `"Live for ..."` / `"Starts: ..."` subtitle text when `celebration.isCelebration` is `true`.
- `Sources/VRemindKit/Views/MenuBar/MenuBarStatusView.swift`:
  - Add `isPopoverConfettiActive(date:)` (respects `!monitorService.preferencesStore.settings.reduceMotion` and `CelebrationDetector.shouldShowConfetti(...)`) and `isSectionCelebrating(_:date:)` to `MenuBarStatusViewModel`.
  - Add `public static func shouldFlashStatusButton(isAnyLive: Bool, reduceMotion: Bool) -> Bool { isAnyLive && !reduceMotion }`.
  - In `MenuBarStatusView`: observe `preferencesStore = viewModel.monitorService.preferencesStore` and track `@State private var isPopoverVisible = false` via `.onAppear { isPopoverVisible = true }` / `.onDisappear { isPopoverVisible = false }`; wrap `VStack` in `ZStack`, overlaying `ConfettiOverlayView()` only when `isPopoverVisible && viewModel.isPopoverConfettiActive()` is `true` (guaranteeing zero idle CPU when the popover is closed); pass `reduceMotion` to `ChannelRowView`; apply `.rainbowForeground(active: isCelebrating, reduceMotion: reduceMotion)` to `"LIVE NOW"` and `"UPCOMING"` section headers when `isSectionCelebrating` is `true`.

- [ ] **Step 4: Run tests to verify pass**

Run: `./scripts/test.sh --filter MenuBarViewTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/VRemindKit/Views/Components/RainbowStyle.swift Sources/VRemindKit/Views/Components/ConfettiOverlayView.swift Sources/VRemindKit/Views/Components/StatusBadge.swift Sources/VRemindKit/Views/MenuBar/ChannelRowView.swift Sources/VRemindKit/Views/MenuBar/MenuBarStatusView.swift Tests/VRemindKitTests/MenuBarViewTests.swift
git commit -m "feat: add macOS 12 rainbow badges and non-Metal Canvas confetti overlay"
```

---

### Task 6: AppDelegate Integration & End-to-End macOS 12 Verification

**Files:**
- Modify: `Sources/VRemind/AppDelegate.swift:50-55,230-283`

**Interfaces:**
- Consumes: `MenuBarStatusView.shouldFlashStatusButton(isAnyLive:reduceMotion:)`, `StreamMonitorService.checkDeveloperBirthdayNotificationIfNeeded()`, `PreferencesStore.settings.reduceMotion`

- [ ] **Step 1: Update `Sources/VRemind/AppDelegate.swift`**

- In `applicationDidFinishLaunching`:
  - Trigger `Task { [weak self] in await self?.monitorService.checkDeveloperBirthdayNotificationIfNeeded() }` right alongside `monitorService.startPolling()`.
- In `setupObservations()`:
  - Add a Combine subscription on `preferencesStore.$settings.map(\.reduceMotion).removeDuplicates().receive(on: RunLoop.main)` calling `self?.updateStatusButton()`.
- In `updateStatusButton()`:
  - Check `let shouldFlash = MenuBarStatusView.shouldFlashStatusButton(isAnyLive: isAnyLive, reduceMotion: preferencesStore.settings.reduceMotion)`.
  - If `isAnyLive`:
    - If `shouldFlash`: start/keep `flashTimer` as before.
    - If `!shouldFlash` (`reduceMotion == true`): invalidate `flashTimer`, set `flashTimer = nil`, set `flashPhase = true`, and call `MenuBarStatusView.configureStatusButton(button, isLive: true, flashPhase: true)` (steady red icon without flashing).
  - If `!isAnyLive`: invalidate `flashTimer` and configure offline icon as before.

- [ ] **Step 2: Run full test suite**

Run: `./scripts/test.sh`
Expected: All test suites PASS (0 failures).

- [ ] **Step 3: Build universal macOS 12.0 Monterey app bundle**

Run: `./scripts/build-app.sh`
Expected: Clean build for `arm64-apple-macosx12.0` / `x86_64-apple-macosx12.0` producing `build/VRemind.app` with exit code 0 (confirms zero macOS 13+ API usage).

- [ ] **Step 4: Remove temporary brainstorm mockup file & commit**

```bash
rm -f mockup-celebration.html
git add Sources/VRemind/AppDelegate.swift
git commit -m "feat: integrate reduceMotion status bar flashing and launch birthday check"
```
