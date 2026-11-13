# VRemind

<p align="center">
  <img src="Resources/Icons/app-icon.png" alt="VRemind App Icon" width="96">
</p>

A native macOS 12.0+ (Monterey and newer) menu bar VTuber stream reminder coded 100% in Swift with SwiftUI and AppKit, featuring zero external dependencies.

---

### 🎧 Vibecoded with Love

> *"Why did I vibecode this? Because I graduated from film school doing sound. What do you expect from someone who did film sound to write world-changing code from scratch? That's dumb."*

This project was built and vibecoded using **Google Antigravity**, pairing **Claude Opus** for architecture and planning with **Gemini Argon** for implementation and deep optimization. The result is a clean, modular, zero-dependency, and fully test-driven native macOS utility.

---

<p align="center">
  <img src="Screenshot-popover.png" alt="VRemind Menu Bar Popover" width="380">
</p>

VRemind sits quietly in your macOS menu bar, monitors your favorite VTubers and content creators on YouTube, alerts you with desktop notifications the moment they go live or schedule an upcoming waiting room, and lets you jump straight into the stream with a single click.

---

## Key Features

- **Unlimited VTuber Watchlist**:
  - Add any VTuber or creator by their YouTube `@handle` (e.g. `@bukancaitlyn`, `@filian`, `@ironmouse`).
  - Pre-seeded with **Caitlyn Momochi** ([@bukancaitlyn](https://www.youtube.com/@bukancaitlyn)) as the default starter channel (fully editable and removable).
  - Inline handle validation: automatically formats handles, verifies valid channel syntax, and prevents duplicate entries.
  - Watchlist channels and metadata are persisted locally via `UserDefaults`.

- **Live & Upcoming Stream Detection**:
  - **Zero API Keys Required**: Lightweight regex-based HTML scraping of YouTube `/live` pages extracts stream titles, video IDs, upcoming start times, and channel avatars without requiring YouTube Data API quotas or Google Cloud credentials.
  - **Rich Status Tracking**:
    - `🔴 LIVE`: Highlights active broadcasts with title, elapsed uptime, and direct watch link.
    - `🗓️ UPCOMING`: Shows scheduled waiting rooms and stream start times (e.g., `in 45m`).
    - `Offline`: Displays time elapsed since the channel last streamed.
  - **Smart Concurrency & Power Management**: Concurrency is bounded to a maximum of 3 concurrent network requests to prevent rate limiting. Background polling automatically pauses when displays go to sleep and resumes immediately upon display wake.
  - **Solid Menu Bar Icon**: Displays a subtle `antenna.radiowaves.left.and.right` icon when all channels are offline and switches to a steady, non-distracting red (`systemRed`) when any watched channel is live.

- **Native macOS Desktop Widgets (`WidgetKit`)**:
  - **Small Hero (`systemSmall`)**: Edge-to-edge creator avatar backdrop with adaptive desktop contrast (`@Environment(\.widgetRenderingMode)`) on macOS Sonoma and newer.
  - **Medium Watchlist (`systemMedium`)**: Quick-grid status view with side-by-side stream titles and countdown timers.
  - **Large Dashboard (`systemLarge`)**: Featured live hero card alongside a full multi-channel watchlist overview.
  - **One-Click Deep Linking (`vremind://open-stream`)**: Tapping any widget launches the stream directly in your default browser.
  - **Zero-Xcode App Extension**: Reverse-engineered `_NSExtensionMain` WidgetKit bundle built exclusively with Xcode Command Line Tools.

- **Celebration Mode (Multilingual Milestone Detection)**:
  - Automatically scans scraped YouTube stream titles for birthday, debut, re-debut, and anniversary milestones in **English**, **Indonesian**, and **Japanese**.
  - Shifts celebrating **LIVE NOW** and **UPCOMING** badges, section headers, and stream timers into an animated rainbow gradient.
  - **Non-Metal Popover Confetti**: Rains party confetti inside the menu bar popover when a milestone stream is live or airing today, drawn via pure CPU-rasterized SwiftUI `Canvas` and `TimelineView` with zero idle CPU usage when closed.

- **Built-in Software Updater (`MarkdownView`)**:
  - Periodic and manual update checks against GitHub Releases with opt-in consent and "Skip This Version".
  - Native macOS 12-compatible Markdown renderer in the **Software Update Available** dialog supporting headings, bullet lists, code blocks, inline formatting, and embedded GitHub Release screenshots.

- **Menu Bar Polish**:
  - Tactile pointing hand cursor (`NSCursor.pointingHand`) and full `@handle` tooltips on channel rows.
  - Ready for macOS 27 Golden Gate liquid glass and vibrancy styling.

- **Native macOS Desktop Notifications**:
  - Powered by Apple's `UserNotifications` framework (`UNUserNotificationCenter`).
  - Independent toggles for live broadcasts (`🔴 LIVE`) and scheduled waiting rooms (`🗓️ UPCOMING`).
  - Notification sound toggle (`Play sound`).
  - Smart deduplication by video ID prevents duplicate alerts for the same stream.
  - Click-to-open: Clicking an alert launches the stream directly in your default web browser.

- **First-Run & Post-Reset Welcome / Onboarding Window**:
  - Automatically welcomes first-time users or opens after a factory reset.
  - Introduces the app, provides a quick handle entry to add your favorite VTuber, and requests notification authorization with one click.

- **Preferences Window (`⌘,`)**:
  - **General Tab**:
    - **Launch at Login**: Integrates with modern `SMAppService` on macOS 13+ (Ventura and newer) with an automatic fallback to Monterey-compatible AppleScript login item management on macOS 12.
    - **Reduce Motion**: Disables popover confetti rain and slows rainbow gradients to a calm, gentle shift.
    - **Updates**: Opt-in automatic update checks, current version display, and manual **Check for Updates Now** button.
    - **Factory Reset**: Restores channels and settings to their initial default state with double-confirmation protection.
  - **Notifications Tab**:
    - Granular controls for Live alerts, Upcoming stream reminders, and notification sounds.
    - Live system authorization status badge with one-click access to macOS System Settings.
  - **About Tab**:
    - Backstory and open-source philosophy: *"You don't like what I did? Go fork yourself, it's free and open source."*
    - Quick links to Caitlyn Momochi's [YouTube](https://www.youtube.com/@bukancaitlyn), [X / Twitter](https://x.com/Y2Karyl), [GitHub](https://github.com/momochisoundpost), and [Instagram](https://www.instagram.com/bukancaitlyn).

---

## Installation

### Option 1: Download Pre-built Release (Recommended)

1. Download `VRemind.zip` from the [Releases](https://github.com/momochisoundpost/VRemind/releases) page.
2. Unzip and drag `VRemind.app` into your `/Applications` folder.
3. Open `VRemind.app`.

> [!NOTE]
> **macOS Gatekeeper Warning**: Because VRemind is an independent open-source project and ad-hoc code-signed without an Apple Developer ID certificate, macOS may say:
> *"VRemind.app is damaged and can’t be opened."* or *"cannot be opened because the developer cannot be verified."*
>
> - **macOS 15 Sequoia and newer**:
>   1. Try opening `VRemind.app` once and click **Done** (or **OK**) on the Gatekeeper dialog.
>   2. Open **System Settings → Privacy & Security**.
>   3. Scroll down to the **Security** section where `"VRemind.app" was blocked` appears, click **Open Anyway**, and authenticate with Touch ID / your password.
> - **macOS 12 Monterey – macOS 14 Sonoma**: **Right-Click (Control-Click) `VRemind.app` → Open → Open**.
> - **Any macOS version (Terminal)**: Clear the quarantine flag directly:
>   ```bash
>   xattr -cr /Applications/VRemind.app
>   ```

### Option 2: Build from Source

Requirements: macOS 12.0+ and Xcode Command Line Tools (`xcode-select --install`). Full Xcode IDE is not required.

```bash
# Clone the repository
git clone https://github.com/momochisoundpost/VRemind.git
cd VRemind

# Build universal release binary (arm64 + x86_64)
bash scripts/build-app.sh

# Launch the built application
open build/VRemind.app
```

---

## Quick Start & Usage

1. **Menu Bar Status**: Look for the antenna icon (`antenna.radiowaves.left.and.right`) in your macOS menu bar. If any watched channel goes live, it turns solid red.
2. **Add a Creator**: Click the menu bar icon to open the popover. Type any YouTube creator's handle in the bottom input bar (e.g. `@filian`, `@ironmouse`, `@bukancaitlyn`) and press Return or click `+`.
3. **Watch a Stream**: Click on any channel row or notification alert to open the stream directly in your default browser.
4. **Remove a Channel**: Hover over a channel row and click the trash can icon.
5. **Preferences**: Click the gear icon in the popover header or press `⌘,` to customize notifications and launch-at-login behavior.
6. **Quit**: Click the menu bar icon and select **Quit VRemind** (or press `⌘Q`).

---

## Frequently Asked Questions (FAQ)

### Is there any Windows build for that?
**No.** VRemind was built on Mac, for macOS, exclusively for Mac users. By writing it 100% in native Swift, SwiftUI, and AppKit with zero external dependencies, I can guarantee a true native look and feel, fluid animations, and genuine system integration. No bloated Electron wrappers, no web containers. If someone wants a Windows or Linux version, go fork yourself and build one—it's open source!

### Why are you still supporting macOS 12 Monterey?
Because I love the glowing Apple logo MacBook users! My very first long-form video was installing macOS Monterey on an early 2008 MacBook using OpenCore Legacy Patcher (OCLP)—so you already know what it leads to. Classic Intel Macs and OCLP-patched machines deserve great lightweight native software too, so VRemind was built from day one to run natively and smoothly on Monterey 12.0+ without sacrificing modern Swift concurrency or features.

### Do I need a YouTube API key or Google Cloud account?
**No.** VRemind requires zero API keys, no Google Cloud developer projects, and no auth credentials. It extracts stream statuses, video IDs, start times, and avatar URLs directly from publicly accessible YouTube `/live` pages.

### Why does macOS say the app is "damaged" or from an "unverified developer"?
Apple requires developers to pay $99/year for an Apple Developer ID certificate to notarize software. Because this is a free, indie hobby project, the binary is ad-hoc code-signed. You can bypass this in seconds:
- **macOS 15 Sequoia and newer**: Attempt to open `VRemind.app` once, click **Done**, then open **System Settings → Privacy & Security**, scroll to **Security**, and click **Open Anyway**.
- **macOS 12 – 14**: Right-Click `VRemind.app` → **Open** → **Open**.
- **Terminal**:
  ```bash
  xattr -cr /Applications/VRemind.app
  ```
You can also inspect the full source code and build it locally in seconds with `bash scripts/build-app.sh`.

### Does this drain my MacBook battery or hog CPU in the background?
**Not at all.** VRemind is engineered specifically for power efficiency on macOS:
- Network sessions are ephemeral and cache-free to prevent memory bloat.
- Network polling runs gently once every 3 minutes, throttled to a maximum of 3 concurrent requests.
- When your Mac display turns off or enters sleep, polling completely stops. It resumes instantly the moment your display wakes up.

### Can I track creators who aren't VTubers?
**Yes.** While VRemind was designed with VTubers in mind, you can monitor any YouTube channel that livestreams by simply entering their `@handle` (e.g. tech creators, podcasters, esports channels, gamers).

### Can I remove Caitlyn Momochi from my watchlist?
**Yes.** Caitlyn Momochi is just the default starter channel so the list isn't blank on first launch. Hover over the channel row, click the trash can icon, and add whoever you like.

### What if YouTube changes its page layout and streams stop updating?
Because VRemind parses YouTube's public web HTML, major layout updates on YouTube's side can occasionally affect regex patterns. If a creator goes live and VRemind doesn't pick it up, please open an Issue or submit a Pull Request. The parser is completely modular and backed by 184 automated unit tests.

---

## Architecture Overview

VRemind is structured into a reusable core library target, a lightweight menu bar executable target, and a native WidgetKit extension target:

```text
VRemind/
├── Sources/
│   ├── VRemindKit/               # Core framework library
│   │   ├── Models/               # WatchedChannel, StreamStatus, AppSettings, GitHubRelease, WidgetSnapshot, VRemindWidgetEntry, ElapsedTime
│   │   ├── Services/             # StreamMonitorService, NotificationService, ChannelStore, PreferencesStore, LivePageParser, CelebrationDetector, UpdateService, WidgetSnapshotStore, VRemindTimelineProvider
│   │   ├── Utilities/            # LinkOpener, LaunchAtLoginHelper, SecretCheck, SemanticVersion, BrandIcon
│   │   ├── Views/                # SwiftUI views (MenuBar, Preferences, Onboarding, Updates, Widget, Components, Theme)
│   │   └── AppConstants.swift    # Global constants
│   ├── VRemind/                  # Application executable
│   │   ├── AppDelegate.swift     # NSApplicationDelegate, NSStatusItem, NSPopover, Sleep/Wake, Deep Links
│   │   ├── PreferencesWindowController.swift
│   │   ├── OnboardingWindowController.swift
│   │   ├── UpdateAvailableWindowController.swift
│   │   └── main.swift
│   └── VRemindWidget/            # Native macOS WidgetKit extension (_NSExtensionMain)
│       ├── VRemindWidget.swift
│       ├── VRemindTimelineProvider.swift
│       └── Views/                # SmallHeroWidgetView, MediumWatchlistWidgetView, LargeDashboardWidgetView
├── Tests/
│   └── VRemindKitTests/          # Swift Testing suite (184 unit and view tests across 21 suites)
├── Resources/
│   ├── Info.plist                # App bundle metadata (LSUIElement = true for menu bar only)
│   ├── Widget-Info.plist         # WidgetKit extension metadata
│   └── Widget.entitlements
└── scripts/
    ├── test.sh                   # Test runner script (supports Xcode CLT)
    └── build-app.sh              # Universal binary & WidgetKit extension packager
```

- **`VRemindKit`**: Contains all business logic, HTML scraping, celebration detection, update checking, Markdown rendering, notification management, persistence, and SwiftUI UI components. Decoupled from application lifecycle to allow thorough automated testing.
- **`VRemind`**: Minimal AppKit executable that coordinates the `NSStatusItem`, popover presentation, display sleep/wake notifications, deep links, and window controllers for Preferences, Onboarding, and Software Updates. Sets `LSUIElement = true` so the app runs unobtrusively in the menu bar without cluttering the macOS Dock.
- **`VRemindWidget`**: Native WidgetKit extension embedded inside `Contents/PlugIns/VRemindWidget.appex`, built without Xcode using `-Xlinker -e -Xlinker _NSExtensionMain`.

---

## Requirements

- **Operating System**: macOS 12.0 (Monterey) or newer (Universal: Apple Silicon & Intel x86_64).
- **Build Tools**: Xcode Command Line Tools (no full Xcode IDE installation required).

---

## Running Tests

Run the automated test suite (184 tests across 21 suites) using Apple's modern Swift Testing framework:

```bash
bash scripts/test.sh
```

You can also pass arguments through to `swift test`, such as running specific test suites:

```bash
bash scripts/test.sh --filter LivePageParserTests
```

---

## Disclaimer

- **YouTube Notice**: VRemind is an independent open-source project and is not affiliated with, endorsed by, or associated with YouTube or Google LLC. YouTube is a trademark of Google LLC.
- **HTML Scraping Notice**: VRemind checks streams by scraping publicly accessible YouTube `/live` pages without an API key. YouTube may alter their frontend DOM or JSON structures from time to time. If stream statuses or avatars fail to parse after a YouTube platform update, please open an issue or pull request.

---

## Contributing

Contributions, bug reports, and suggestions are welcome!
1. Fork the repository.
2. Create your feature branch (`git checkout -b feat/my-new-feature`).
3. Make sure all unit tests pass (`bash scripts/test.sh`).
4. Commit your changes and open a Pull Request.

---

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

*"You don't like what I did? Go fork yourself, it's free and open source."*

---

<p align="center">
  <a href="https://apple.com"><img src="https://img.shields.io/badge/Platform-macOS%2012%2B-blue?logo=apple" alt="Platform: macOS 12+"></a>
  <a href="https://swift.org"><img src="https://img.shields.io/badge/Swift-5.9%2B-F05138?logo=swift" alt="Swift: 5.9+"></a>
  <img src="https://img.shields.io/badge/Dependencies-Zero-brightgreen" alt="Dependencies: Zero">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-green" alt="License: MIT"></a>
  <a href="#running-tests"><img src="https://img.shields.io/badge/Tests-184%20Passing-success" alt="Tests: 184 Passing"></a>
</p>
