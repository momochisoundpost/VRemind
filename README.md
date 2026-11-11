# VRemind

A native macOS 12.0+ (Monterey and newer) menu bar VTuber stream reminder coded 100% in Swift with SwiftUI and AppKit, featuring zero external dependencies.

VRemind sits quietly in your macOS menu bar, monitors your favorite VTubers and content creators on YouTube, alerts you with desktop notifications the moment they go live or schedule an upcoming waiting room, and lets you jump straight into the stream with a single click.

---

## Key Features

- **Unlimited VTuber Watchlist**:
  - Add any VTuber or creator by their YouTube `@handle` (e.g. `@bukancaitlyn`, `@filian`, `@ironmouse`).
  - Pre-seeded with **Caitlyn Momochi** ([@bukancaitlyn](https://www.youtube.com/@bukancaitlyn)) as the default/example starter channel (fully editable and removable).
  - Inline handle validation: automatically formats handles, verifies valid channel syntax, and prevents duplicate entries.
  - Watchlist channels and metadata are persisted locally via `UserDefaults`.

- **Live & Upcoming Stream Detection**:
  - **Zero API Keys Required**: Lightweight regex-based HTML scraping of YouTube `/live` pages extracts stream titles, video IDs, upcoming start times, and channel avatars without requiring YouTube Data API quotas or Google Cloud credentials.
  - **Rich Status Tracking**:
    - `🔴 LIVE`: Highlights active broadcasts with title, elapsed uptime, and direct watch link.
    - `🗓️ UPCOMING`: Shows scheduled waiting rooms and stream start times (e.g., `in 45m`).
    - `Offline`: Displays time elapsed since the channel last streamed.
  - **Smart Concurrency & Power Management**: Concurrency is bounded to a maximum of 3 concurrent network requests to prevent rate limiting. Background polling automatically pauses when displays go to sleep and resumes immediately upon display wake.
  - **Dynamic Menu Bar Icon**: The menu bar icon changes dynamically (`dot.radiowaves.left.and.right` in vibrant red when any watched channel is live, or a subtle `bell` when all channels are offline).

- **Native macOS Desktop Notifications**:
  - Powered by Apple's `UserNotifications` framework (`UNUserNotificationCenter`).
  - Independent toggles for live broadcasts (`🔴 LIVE`) and scheduled waiting rooms (`🗓️ UPCOMING`).
  - Notification sound toggle (`Play sound`).
  - Smart deduplication by video ID prevents duplicate alerts for the same stream.
  - Click-to-open: Clicking an alert launches the stream directly in your default web browser.

- **First-Run & Post-Reset Welcome / Onboarding Window**:
  - Automatically welcomes first-time users or opens after a factory reset.
  - Introduces the app, provides a quick handle entry to add your favorite VTuber (or keep the default Caitlyn Momochi starter channel), and requests notification authorization with one click.

- **Preferences Window (`⌘,`)**:
  - **General Tab**:
    - **Launch at Login**: Integrates with modern `SMAppService` on macOS 13+ (Ventura and newer) with an automatic fallback to Monterey-compatible AppleScript login item management on macOS 12.
    - **Factory Reset**: Restores channels and settings to their initial default state with double-confirmation protection.
  - **Notifications Tab**:
    - Granular controls for Live alerts, Upcoming stream reminders, and notification sounds.
    - Live system authorization status badge with one-click access to macOS System Settings.
  - **About Tab**:
    - Backstory: *"VRemind by Caitlyn Momochi, initially vibecoded for their Hackintosh video"*
    - Open-source philosophy: *"You don't like what I did? Go fork yourself, it's free and open source."*
    - Quick links to Caitlyn Momochi's [YouTube](https://www.youtube.com/@bukancaitlyn), [X / Twitter](https://x.com/Y2Karyl), and GitHub.

---

## Architecture Overview

VRemind is structured into a reusable core library target and a lightweight executable target:

```text
CaitlynSwift/
├── Sources/
│   ├── VRemindKit/               # Core framework library
│   │   ├── Models/               # WatchedChannel, StreamStatus, AppSettings, ElapsedTime
│   │   ├── Services/             # StreamMonitorService, NotificationService, ChannelStore, PreferencesStore, LivePageParser
│   │   ├── Utilities/            # LinkOpener, LaunchAtLoginHelper
│   │   ├── Views/                # SwiftUI views (MenuBar, Preferences, Onboarding, Components, Theme)
│   │   └── AppConstants.swift    # Global constants
│   └── VRemind/                  # Application executable
│       ├── AppDelegate.swift     # NSApplicationDelegate, NSStatusItem, NSPopover, Sleep/Wake
│       ├── PreferencesWindowController.swift
│       ├── OnboardingWindowController.swift
│       └── main.swift
├── Tests/
│   └── VRemindKitTests/          # Swift Testing suite (90+ comprehensive unit and view tests)
├── Resources/
│   └── Info.plist                # App bundle metadata (LSUIElement = true for menu bar only)
└── scripts/
    ├── test.sh                   # Test runner script (supports Xcode CLT)
    └── build-app.sh              # Universal binary build and release packager
```

- **`VRemindKit`**: Contains all business logic, HTML scraping, notification management, persistence, and SwiftUI UI components. Decoupled from application lifecycle to allow thorough automated testing.
- **`VRemind`**: Minimal AppKit executable that coordinates the `NSStatusItem`, popover presentation, display sleep/wake notifications, and window controllers for Preferences and Onboarding. Sets `LSUIElement = true` so the app runs unobtrusively in the menu bar without cluttering the macOS Dock.

---

## Requirements

- **Operating System**: macOS 12.0 (Monterey) or newer (Universal: Apple Silicon & Intel x86_64).
- **Build Tools**: Xcode Command Line Tools (no full Xcode IDE installation required).

---

## Running Tests

Run the full automated test suite using Swift Testing:

```bash
bash scripts/test.sh
```

You can also pass arguments through to `swift test`, such as running specific suites or tests:

```bash
bash scripts/test.sh --filter LivePageParserTests
```

---

## Building the Release Application

To compile the universal release binary and assemble `build/VRemind.app`:

```bash
bash scripts/build-app.sh
```

This script:
1. Compiles optimized release binaries for both `arm64` (Apple Silicon) and `x86_64` (Intel).
2. Merges them into a universal Mach-O binary using `lipo`.
3. Packages the `VRemind.app` bundle with `Contents/Info.plist`.
4. Applies ad-hoc code signing (`codesign --force --deep --sign -`).

To launch the built application:

```bash
open build/VRemind.app
```
