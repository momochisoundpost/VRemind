# Celebration Mode & Holiday Easter Egg Design Document

- **Status:** Complete (Ready for Approval)
- **Date:** 2026-11-12
- **Author:** Antigravity / Caitlyn Momochi

---

## 1. Intent & The Why

VRemind is a macOS menu bar app for tracking VTuber and creator YouTube live streams. To add celebratory flair during milestones (such as VTuber birthdays, debuts, re-debuts, and channel anniversaries) and honor the developer's birthday on New Year's Eve, VRemind will introduce **Celebration Mode**. 

When celebratory streams are detected or a specific holiday condition is met, VRemind shifts its standard red/orange visual cues into an energetic rainbow theme with falling confetti in the menu bar popover. A user-configurable **Reduce Motion** option ensures the visual flair can be toned down for accessibility and performance on non-Metal GPUs.

---

## 2. Goals, Non-Goals, & Anti-Goals

### Goals
- **Multi-language Milestone Detection:** Automatically detect celebration streams by scanning scraped YouTube stream titles for milestone keywords across English, Indonesian, and Japanese.
- **Celebration Aesthetics:** Replace standard red ("LIVE NOW") and orange ("UPCOMING") styling with vibrant rainbow gradients and badge accents on channels that have active or today-scheduled celebratory streams.
- **Popover Confetti Rain:** Render a celebratory confetti particle shower inside the menu bar popover when a celebratory stream is actively live, scheduled for today, or during the Dec 31 developer holiday.
- **Accessibility & Motion Control:** Add a "Reduce Motion" preference that disables menu bar flashing, turns off confetti particles, and slows down rainbow animations to a gentle, static-friendly shift.
- **December 31st Developer Birthday Easter Egg:** When Caitlyn Momochi (`@bukancaitlyn`) is present on the watchlist when the calendar hits Dec 31st (years > 1999), or is added on Dec 31st, activate Celebration Mode and trigger a macOS system notification that opens the user's default Mail app addressed to `y2karyl@disroot.org` (throttled to at most once per calendar year).
- **macOS 12 Monterey & Non-Metal Compatibility:** Ensure all views, animations, and particle effects strictly target **macOS 12.0 Monterey (`.macOS(.v12)`)** and execute cleanly on CPU software rasterization without requiring Metal hardware acceleration (supporting legacy/Hackintosh environments).

### Non-Goals
- Modifying YouTube scraping network logic or parsing APIs beyond inspecting stream titles.
- Playing continuous celebratory audio inside the popover.
- Interfering with other channel notifications outside of celebration badges.

### Anti-Goals
- High CPU/GPU load while the popover is closed (particle timers or animation loops must completely halt when popover is dismissed).
- Overwhelming, unreadable UI where rainbow text obscures channel names or stream titles. Only status badges, section headers, and duration/status accents receive rainbow styling; channel names and titles remain standard readable colors.

---

## 3. Constraints

- **Platform:** macOS 12.0 Monterey (`.macOS(.v12)`) and newer. No macOS 13+ exclusive APIs (e.g. avoid `NavigationStack`, `View.scrollIndicators`, `ImageRenderer`).
- **GPU Architecture:** Must operate smoothly on systems without Metal hardware acceleration (e.g. software rasterization / legacy Hackintosh hardware). Avoid SpriteKit/Metal render passes (`SKView`, Metal shaders).
- **Process Isolation:** The menu bar popover is transient; background monitoring services must remain lightweight and headless.
- **Security & Privacy:** The `mailto:` link generation must only use standard URL schemes (`URL(string: "mailto:y2karyl@disroot.org?subject=...")`) via system `NSWorkspace` / `LinkOpener`.

---

## 4. Approaches Considered & Trade-Offs

### Approach 1: Modular Celebration Engine with SwiftUI Native Canvas (Chosen)
- **Description:** A dedicated `CelebrationDetector` inspects stream titles and calendar dates. Visual styling is applied via SwiftUI view modifiers compatible with macOS 12 (`Canvas`, `TimelineView`, `LinearGradient`). Confetti is rendered via a software-drawn SwiftUI `Canvas` active only when the popover is displayed. A new `reduceMotion` preference controls motion intensity across the app.
- **Pros:** Zero third-party dependencies; fully compatible with macOS 12 and non-Metal GPUs; zero CPU overhead when popover is closed; clear separation of concerns; easy to unit test.
- **Cons:** Custom confetti physics must be calculated in Swift rather than using SpriteKit's physics engine.
- **Decision:** Chosen because it meets all performance, compatibility, and architecture requirements.

### Approach 2: SpriteKit Overlay & Direct Status Enum Modification
- **Description:** Augment `StreamStatus` with celebration flags and embed an `SKView` particle emitter into `MenuBarStatusView`.
- **Pros:** Built-in particle physics in Xcode (`.sks`).
- **Cons:** Requires Metal GPU acceleration; exhibits rendering glitches and transparency artifacts inside macOS `NSPopover`; introduces memory leaks on legacy hardware.
- **Decision:** Rejected due to non-Metal GPU requirement.

### Approach 3: Embedded WebKit Overlay
- **Description:** Render the confetti layer using a transparent `WKWebView` with HTML/JS.
- **Pros:** Readily available web libraries (`canvas-confetti`).
- **Cons:** Massive process overhead, heavy memory footprint, slow popover display response.
- **Decision:** Rejected.

---

## 5. Detailed Component Design

### 5.1 Celebration Keyword & Date Detection (`CelebrationDetector`)
A pure, testable service:
```swift
public enum CelebrationType: Equatable, Sendable {
    case birthday
    case debut
    case anniversary
    case developerBirthday
}

public struct CelebrationResult: Equatable, Sendable {
    public let isCelebration: Bool
    public let type: CelebrationType?
    public let matchedKeyword: String?
}
```

#### Keyword Patterns (Case-Insensitive):
- **Birthday:**
  - English: `birthday`, `bday`, `birthday stream`
  - Indonesian: `ultah`, `ulang tahun`
  - Japanese: `生誕祭`, `誕生日`, `バースデー`
- **Debut / Re-debut:**
  - English: `debut`, `re-debut`, `redebut`
  - Japanese: `初配信`, `お披露目`
- **Anniversary:**
  - English: `anniversary`, `anni`
  - Indonesian: `hari jadi`, `anniv`
  - Japanese: `周年`, `記念配信`, `記念枠`

#### December 31st Developer Birthday Easter Egg Logic:
- Target channel: handle equals `@bukancaitlyn` or ID equals `bukancaitlyn`, or channel name equals `Caitlyn Momochi`.
- Date condition: `Calendar.current` components: `month == 12`, `day == 31`, `year > 1999`.
- Trigger rules:
  1. **On Addition:** If added on Dec 31st, dispatch the birthday notification immediately.
  2. **On Launch / Background Refresh:** If `@bukancaitlyn` is already on the watchlist when the calendar hits Dec 31st, dispatch the notification once per calendar year (persisted via `lastNotifiedDevBirthdayYear: Int?` in `AppSettings`).
- Notification Payload:
  - Title: `"🎉 Happy Birthday to the Developer!"`
  - Body: `"Today is Caitlyn Momochi's birthday! Click here to send a birthday wish."`
  - Action / URL: `mailto:y2karyl@disroot.org?subject=Happy%20Birthday%20Caitlyn!`

### 5.2 Confetti Activation Scope
- **Popover Confetti Shower:** Activates when:
  - Any stream in the watchlist is `.live` with a celebration title, OR
  - Any stream in the watchlist is `.upcoming` with a celebration title scheduled for **today**, OR
  - Today is December 31st (year > 1999) and `@bukancaitlyn` is present in the watchlist.
- If a celebration stream is scheduled for a future date (beyond today), the individual row displays celebratory styling, but the intrusive popover confetti shower is suppressed until the day of the stream.

### 5.3 Row & Header Visual Granularity
- **Row-level styling:** Celebratory channels receive a rainbow `StatusBadge` and rainbow-accented time subtitle. Non-celebrating channels retain standard red/orange/secondary styling.
- **Section headers:** If *any* channel in "LIVE NOW" or "UPCOMING" is celebrating, that section's header text ("LIVE NOW" / "UPCOMING") receives the rainbow gradient.

### 5.4 Settings & Reduce Motion (`AppSettings`)
Add to `AppSettings`:
```swift
public var reduceMotion: Bool = false
public var lastNotifiedDevBirthdayYear: Int? = nil
```
- Saved in `PreferencesStore` (`UserDefaults`).
- Added to `PreferencesView` under the "General" section as:
  `Toggle("Reduce Motion (Turn off flashing & popover confetti)", isOn: $viewModel.reduceMotion)`
- **Effects when enabled:**
  1. `AppDelegate.flashTimer` is invalidated / suppressed (menu bar status button does not flash even when a channel is live).
  2. Popover confetti particle rendering is skipped.
  3. Rainbow styling uses a slower, subdued shift or static gradient.

### 5.5 Rainbow Visual Styling (`RainbowStyle`)
- Compatible with macOS 12 Monterey:
  - Linear gradient with stops: Red (`#FF0055`), Orange (`#FF9900`), Yellow (`#FFE600`), Green (`#33CC33`), Blue (`#00BFFF`), Purple (`#9933FF`), Red (`#FF0055`).
  - Active on:
    - Section titles ("LIVE NOW", "UPCOMING") when celebration streams exist.
    - `StatusBadge` capsule outline, background tint, and label text for celebratory channels.
    - Elapsed duration / scheduled start time subtitle in `ChannelRowView`.
  - Animates phase across time when motion is enabled; holds static gradient or slow 8-second shift when `reduceMotion` is enabled.

### 5.6 Confetti Particle Layer (`ConfettiOverlayView`)
- Implemented using SwiftUI `TimelineView` and `Canvas` (available in macOS 12+):
  - 40–50 lightweight particles (rectangles, streamers, circles) in celebration colors.
  - Generates simple downward velocities with slight sinusoidal horizontal sway.
  - Runs strictly when popover is open and `!reduceMotion`.
  - Zero timer activity when popover closes.

### 5.7 Notification & Mail Link Handling
- `NotificationService.sendDeveloperBirthdayNotification()`:
  - Dispatches standard user notification.
  - When user clicks/activates the notification, `AppDelegate` opens the `mailto:y2karyl@disroot.org?subject=Happy%20Birthday%20Caitlyn!` URL using `NSWorkspace.shared.open(...)`.

---

## 6. What Is Left to the Builder

- Exact particle color palettes and distribution curves for confetti shapes.
- Precise padding and overlay positioning inside `MenuBarStatusView`.
- Unit test suite for `CelebrationDetector`, `AppSettings` persistence, and Dec 31 calendar boundaries.
