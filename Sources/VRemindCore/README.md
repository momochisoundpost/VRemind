# VRemindCore

The platform-agnostic Swift business engine behind **VRemind**.

`VRemindCore` contains all domain models, zero-API-key stream providers and parsers, polling and notification-deduplication rules, celebration detection, and persistence abstractions — with **zero** dependencies on `AppKit`, `SwiftUI`, `Combine`, `UserNotifications`, `ServiceManagement`, or `WidgetKit`.

On macOS, `VRemindKit` acts as the native Mac bridge between `VRemindCore` and the `VRemind` menu bar app + `VRemindWidget` extension. Outside macOS, `VRemindCore` can be compiled on any platform with a Swift toolchain (Linux, Windows, Chromebooks/Linux containers, etc.) or used as a clean reference architecture for native ports (e.g., KDE Plasma / Qt or GNOME Shell extensions).

---

## Portability Rules

Every file inside `Sources/VRemindCore/` must satisfy two hard constraints:

1. **Foundation-Only Imports:** Only import `Foundation`, plus `#if canImport(FoundationNetworking) import FoundationNetworking #endif` when referencing HTTP networking types (`URLRequest`, `URLResponse`, `HTTPURLResponse`, `URLSession`).
2. **No Apple Runtime Coupling:** Never import `AppKit`, `SwiftUI`, `Combine`, `UserNotifications`, `ServiceManagement`, or `WidgetKit`. Guard Objective-C runtime conveniences such as `autoreleasepool` behind `#if canImport(ObjectiveC)`.

---

## Architecture & Directory Layout

```text
Sources/VRemindCore/
├── AppConstants.swift                 # Version, release endpoint, default handle, poll interval (180s)
├── Models/
│   ├── StreamPlatform.swift           # Supported platforms (.youtube, .twitch)
│   ├── WatchedChannel.swift           # Canonical (platform, handle) model, normalization, URL detection, v1.2 migration
│   ├── StreamStatus.swift             # .live, .upcoming, .offline, .unknown
│   ├── ChannelFetchResult.swift       # HTTPFetcher, LivePageResult, ChannelFetchResult
│   ├── AppSettings.swift              # Codable preferences & update consent state
│   ├── ElapsedTime.swift              # Compact duration and relative time formatters
│   └── GitHubRelease.swift            # Codable GitHub Releases model for update checks
├── Providers/
│   ├── StreamProvider.swift           # StreamProvider protocol & StreamProviderRegistry
│   ├── YouTubeStreamProvider.swift    # YouTube /live page fetcher & watch URL builder
│   ├── TwitchStreamProvider.swift     # Key-free Twitch GraphQL fetcher (gql.twitch.tv/gql)
│   └── TwitchResponseParser.swift     # Pure JSON parser for Twitch GraphQL payloads
├── Services/
│   ├── StreamMonitorEngine.swift      # Bounded-concurrency (3) polling pass, dedup events, section sorting
│   ├── LivePageParser.swift           # Pure HTML/JSON scraper for YouTube /live pages
│   └── CelebrationDetector.swift      # EN/ID/JA milestone title rules & Dec 31 developer birthday logic
├── Persistence/
│   └── StorageProtocols.swift         # ChannelStorage, SettingsStorage, JSONFileChannelStorage, JSONFileSettingsStorage
└── Utilities/
    ├── SecretCheck.swift
    └── SemanticVersion.swift
```

---

## Core Abstractions

### `StreamProvider` & `StreamProviderRegistry`
Every streaming platform (or future feed type such as Kick or RSS) implements `StreamProvider`:

- `platform: StreamPlatform`
- `normalizeHandle(_ input: String) -> String?`
- `channelURL(for handle: String) -> URL?`
- `watchURL(for channel: WatchedChannel, status: StreamStatus) -> URL?`
- `fetchChannelState(for channel: WatchedChannel, fetcher: HTTPFetcher) async throws -> ChannelFetchResult`

`StreamProviderRegistry.default` wires `YouTubeStreamProvider` and `TwitchStreamProvider` together. Custom registries can be injected into `StreamMonitorEngine` for testing or extending platforms.

### `StreamMonitorEngine`
`StreamMonitorEngine` executes stateless, bounded-concurrency refresh passes (`defaultBatchSize = 3`, ephemeral cache-free `URLSession`) and emits structured `MonitorEvent` values via an async handler:

- `.statusUpdated(channelId:status:)`
- `.metadataUpdated(channelId:name:avatarURL:)`
- `.notifyLive(channel:videoId:title:)`
- `.notifyUpcoming(channel:videoId:title:)`
- `.notifyDeveloperBirthday(year:)`
- `.refreshFinished(statuses:)`

Platform bridges (`VRemindKit` on macOS, or custom hosts elsewhere) translate those events into native UI state, desktop notifications, widgets, and power-management hooks (such as display sleep/wake).

### Persistence (`StorageProtocols`)
`VRemindCore` defines `ChannelStorage` and `SettingsStorage`, along with pure-`Foundation` file-backed implementations (`JSONFileChannelStorage` and `JSONFileSettingsStorage`) using atomic JSON writes for non-Apple environments. On macOS, `VRemindKit`'s `ChannelStore` and `PreferencesStore` conform to the same protocols backed by `UserDefaults`.

---

## Development Workflow (Test-Driven Development)

All changes to `VRemindCore` follow strict **TDD** (Red → Green → Refactor):

1. **Write a failing test first** under `Tests/VRemindCoreTests/` (e.g., fixture HTML/JSON tests for a new parser or provider, handle normalization edge cases, or `StreamMonitorEngine` event assertions). Never hit live external networks in unit tests — inject a mock `HTTPFetcher`.
2. **Run the focused test** and confirm it fails for the expected reason.
3. **Implement the minimal `Foundation`-only code** in `Sources/VRemindCore/` to make it pass.
4. **Run the `VRemindCoreTests` suite and portability check** before committing.

### Running Tests

On macOS (with Xcode Command Line Tools):

```bash
# Run VRemindCore tests only
bash scripts/test.sh --filter VRemindCoreTests

# Run a specific test suite
bash scripts/test.sh --filter TwitchStreamProviderTests

# Run the entire package test suite (VRemindCoreTests + VRemindKitTests)
bash scripts/test.sh
```

On Linux / non-Apple Swift toolchains (testing `VRemindCore` directly):

```bash
swift test --filter VRemindCoreTests
```

### Portability Check

Verify before committing that no Apple-only frameworks slipped into `Sources/VRemindCore/`:

```bash
grep -rnE "import (AppKit|SwiftUI|Combine|UserNotifications|WidgetKit|ServiceManagement)" Sources/VRemindCore
```

This command should return zero matches.

---

## Adding a New Provider (e.g., Kick or RSS)

1. Add the new case to `StreamPlatform` in `Models/StreamPlatform.swift` and handle its input normalization/URL detection in `WatchedChannel.swift`.
2. Write parser & provider tests first in `Tests/VRemindCoreTests/` covering live, offline, error/HTTP non-2xx, and malformed payload fixtures.
3. Implement a pure parser + `StreamProvider` struct under `Sources/VRemindCore/Providers/` using `HTTPFetcher`.
4. Register the provider in `StreamProviderRegistry.default` (`Providers/StreamProvider.swift`).
5. Update platform bridges (`VRemindKit` on macOS) to expose UI badges, pickers, and link handling for the new `StreamPlatform` case.
