# macOS WidgetKit Extension (`VRemindWidget`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an official native macOS WidgetKit extension for VRemind supporting Small, Medium, and Large widgets with local avatar caching and browser deep-linking, compatible with macOS 12+ Monterey up to modern macOS, compiled via pure Swift Package Manager.

**Architecture:** The main unsandboxed VRemind app performs background YouTube `/live` scraping and serializes a lightweight `WidgetSnapshot` and cached avatar images directly into the widget extension's sandbox container (`~/Library/Containers/com.caitlyn.vremind.widget/Data/Library/Application Support/VRemind/`). The sandboxed widget extension reads this snapshot from its own container via standard `FileManager` and renders Small, Medium, and Large widgets with `StaticConfiguration`. Deep links route through `vremind://open-stream?url=...` handled by `AppDelegate` to open streams directly in the user's default browser.

**Tech Stack:** Swift 5.9+, SwiftUI, AppKit, WidgetKit, Swift Package Manager (`swift build`), `UNUserNotificationCenter`, macOS 12.0+ Deployment Target.

**Spec:** `docs/superpowers/specs/2026-11-12-macos-widgetkit-extension-design.md`

## Global Constraints

- Deployment target is macOS 12.0 (Monterey) or newer across all targets.
- 100% native Swift, SwiftUI, and AppKit with zero external third-party dependencies.
- Build must succeed via Xcode Command Line Tools (`bash scripts/build-app.sh`) without requiring full Xcode IDE or `.xcodeproj`.
- Universal binary support (`arm64` Apple Silicon + `x86_64` Intel).
- Ad-hoc code signing (`codesign --sign -`) with sandbox entitlement on the `.appex` bundle; no paid Apple Developer ID certificate or provisioned App Groups required.

## Review Focus

1. **Missing or Corrupt Widget Cache**: If `widget-cache.json` does not exist or contains invalid JSON on first widget launch before the main app runs, the widget must display a calm starter/placeholder state without crashing.
2. **Missing Local Avatar File**: If an avatar image is not yet cached locally on disk (or fails to write), the Small hero widget must gracefully fall back to a high-contrast monogram placeholder instead of rendering a broken blank frame.
3. **Multiple Channels Live Simultaneously**: In the Small widget (which only displays a single hero creator), the widget must deterministically select the creator who went live most recently.
4. **All Channels Offline**: When zero watched channels are live or upcoming, the Small widget must dim the background avatar with grayscale saturation and clearly state "All channels offline" rather than appearing blank or frozen.
5. **Deep Link Decoding Safety**: If an invalid, malformed, or non-HTTP URL is passed to `vremind://open-stream?url=...`, `AppDelegate` must safely ignore the request without crashing or opening an unsafe URI.

---

### Task 1: Widget Data Models & Deep Link Generation

**Files:**
- Create: `Sources/VRemindKit/Models/WidgetSnapshot.swift`
- Test: `Tests/VRemindKitTests/WidgetSnapshotTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public struct WidgetSnapshot: Codable, Equatable, Sendable
  public struct WidgetChannelItem: Codable, Equatable, Sendable, Identifiable {
      public var id: String { handle }
      public let handle: String
      public let displayName: String
      public let avatarFilename: String?
      public let avatarURL: URL?
      public let statusKind: StatusKind
      public let streamTitle: String?
      public let videoId: String?
      public let liveStartedAt: Date?
      public let upcomingStartTime: Date?
      public let lastStreamedAt: Date?
      public var deepLinkURL: URL?
  }
  public enum StatusKind: String, Codable, Sendable
  ```

- [ ] **Step 1: Write the failing tests for `WidgetSnapshot` and `deepLinkURL`**

Create `Tests/VRemindKitTests/WidgetSnapshotTests.swift` testing:
1. Codable round-trip for `WidgetSnapshot` with all fields populated.
2. `deepLinkURL` generation constructing `vremind://open-stream?url=<encoded_youtube_url>`.
3. Fallback to channel URL when `videoId` is nil.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/test.sh --filter WidgetSnapshotTests`
Expected: FAIL with "cannot find type 'WidgetSnapshot' in scope"

- [ ] **Step 3: Implement `WidgetSnapshot` and `WidgetChannelItem` in `Sources/VRemindKit/Models/WidgetSnapshot.swift`**

Implement `WidgetSnapshot`, `WidgetChannelItem`, `StatusKind`, and `deepLinkURL` with `URLComponents(scheme: "vremind", host: "open-stream", queryItems: ...)`.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash scripts/test.sh --filter WidgetSnapshotTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/VRemindKit/Models/WidgetSnapshot.swift Tests/VRemindKitTests/WidgetSnapshotTests.swift
git commit -m "feat(widget): add WidgetSnapshot and WidgetChannelItem data models"
```

---

### Task 2: Container Resolution & `WidgetSnapshotStore`

**Files:**
- Create: `Sources/VRemindKit/Services/WidgetSnapshotStore.swift`
- Test: `Tests/VRemindKitTests/WidgetSnapshotStoreTests.swift`

**Interfaces:**
- Consumes: `WidgetSnapshot`, `WidgetChannelItem`, `WatchedChannel`, `StreamStatus` from Task 1.
- Produces:
  ```swift
  public protocol WidgetSnapshotStoreProtocol: Sendable {
      func writeSnapshot(channels: [WatchedChannel], statuses: [String: StreamStatus]) async throws
      func readSnapshot() -> WidgetSnapshot?
  }
  public final class WidgetSnapshotStore: WidgetSnapshotStoreProtocol, Sendable
  ```

- [ ] **Step 1: Write failing tests for `WidgetSnapshotStore`**

Create `Tests/VRemindKitTests/WidgetSnapshotStoreTests.swift` verifying:
1. Custom directory injection writes and reads `widget-cache.json` matching serialized channels.
2. `readSnapshot()` returns `nil` when file is missing without throwing.
3. Corrupt JSON in cache file returns `nil` gracefully (Review Focus #1).
4. Sorting logic picks the most recently live channel as primary (Review Focus #3).

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/test.sh --filter WidgetSnapshotStoreTests`
Expected: FAIL with "cannot find 'WidgetSnapshotStore' in scope"

- [ ] **Step 3: Implement `WidgetSnapshotStore`**

In `Sources/VRemindKit/Services/WidgetSnapshotStore.swift`:
- Resolves container path: checks if running inside container or host app (`~/Library/Containers/com.caitlyn.vremind.widget/Data/Library/Application Support/VRemind/`).
- `writeSnapshot` writes JSON atomized, caches avatars to `Avatars/`, and calls `#if canImport(WidgetKit) WidgetCenter.shared.reloadAllTimelines() #endif`.
- `readSnapshot` reads and decodes JSON.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash scripts/test.sh --filter WidgetSnapshotStoreTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/VRemindKit/Services/WidgetSnapshotStore.swift Tests/VRemindKitTests/WidgetSnapshotStoreTests.swift
git commit -m "feat(widget): implement WidgetSnapshotStore and container path resolution"
```

---

### Task 3: Automatic Widget Sync from `StreamMonitorService`

**Files:**
- Modify: `Sources/VRemindKit/Services/StreamMonitorService.swift`
- Test: `Tests/VRemindKitTests/StreamMonitorServiceTests.swift`

**Interfaces:**
- Consumes: `WidgetSnapshotStoreProtocol` from Task 2.
- Modifies: `StreamMonitorService.init(..., snapshotStore: WidgetSnapshotStoreProtocol = WidgetSnapshotStore.shared)`

- [ ] **Step 1: Write failing test in `StreamMonitorServiceTests.swift`**

Add test `testPollingPassUpdatesWidgetSnapshot()` verifying that when a polling pass completes or stream status changes, `snapshotStore.writeSnapshot(...)` is invoked.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/test.sh --filter StreamMonitorServiceTests`
Expected: FAIL verifying snapshot write was not triggered.

- [ ] **Step 3: Update `StreamMonitorService.swift`**

Inject `snapshotStore` into `StreamMonitorService` and trigger snapshot export at the end of each refresh pass and when channel metadata updates.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash scripts/test.sh --filter StreamMonitorServiceTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/VRemindKit/Services/StreamMonitorService.swift Tests/VRemindKitTests/StreamMonitorServiceTests.swift
git commit -m "feat(widget): trigger widget snapshot updates from StreamMonitorService"
```

---

### Task 4: Custom URL Scheme Registration & `AppDelegate` URL Routing

**Files:**
- Modify: `Resources/Info.plist`
- Modify: `Sources/VRemind/AppDelegate.swift`
- Modify: `Sources/VRemindKit/Utilities/LinkOpener.swift`
- Test: `Tests/VRemindKitTests/LinkOpenerTests.swift`

**Interfaces:**
- Consumes: `vremind://open-stream?url=...` scheme.
- Modifies: `AppDelegate.application(_:open urls: [URL])`.

- [ ] **Step 1: Write failing tests for deep link parsing & validation**

Add test in `LinkOpenerTests.swift` verifying:
1. `LinkOpener.parseStreamDeepLink(url)` extracts target `https://` YouTube URL.
2. Rejects invalid schemes, missing `url` query parameter, or non-http/https targets (Review Focus #5).

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/test.sh --filter LinkOpenerTests`
Expected: FAIL with "type 'LinkOpener' has no member 'parseStreamDeepLink'"

- [ ] **Step 3: Implement deep link parser and `AppDelegate` handler**

1. Add `parseStreamDeepLink` to `LinkOpener`.
2. Register `vremind` scheme under `CFBundleURLTypes` in `Resources/Info.plist`.
3. In `AppDelegate.swift`, implement `application(_:open urls:)`:
   ```swift
   func application(_ application: NSApplication, open urls: [URL]) {
       for url in urls {
           if let streamURL = LinkOpener.shared.parseStreamDeepLink(url) {
               LinkOpener.shared.open(streamURL)
           }
       }
   }
   ```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash scripts/test.sh --filter LinkOpenerTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Resources/Info.plist Sources/VRemind/AppDelegate.swift Sources/VRemindKit/Utilities/LinkOpener.swift Tests/VRemindKitTests/LinkOpenerTests.swift
git commit -m "feat(widget): register vremind:// URL scheme and route deep links in AppDelegate"
```

---

### Task 5: Widget UI Components & `VRemindWidgetBundle`

**Files:**
- Create: `Sources/VRemindWidget/VRemindTimelineProvider.swift`
- Create: `Sources/VRemindWidget/Views/SmallHeroWidgetView.swift`
- Create: `Sources/VRemindWidget/Views/MediumWatchlistWidgetView.swift`
- Create: `Sources/VRemindWidget/Views/LargeDashboardWidgetView.swift`
- Create: `Sources/VRemindWidget/VRemindWidget.swift`
- Test: `Tests/VRemindKitTests/WidgetViewTests.swift`

**Interfaces:**
- Consumes: `WidgetSnapshot`, `WidgetChannelItem`, `WidgetSnapshotStore` from Tasks 1-2.
- Produces:
  ```swift
  @main struct VRemindWidgetBundle: WidgetBundle
  struct VRemindWidget: Widget
  ```

- [ ] **Step 1: Write failing view rendering tests**

Create `Tests/VRemindKitTests/WidgetViewTests.swift` verifying:
1. `SmallHeroWidgetView` renders with live creator and uptime.
2. `SmallHeroWidgetView` renders with offline state and dimmed avatar (Review Focus #4).
3. `SmallHeroWidgetView` renders monogram when avatar image is missing (Review Focus #2).
4. `MediumWatchlistWidgetView` renders multi-channel rows with deep links.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/test.sh --filter WidgetViewTests`
Expected: FAIL with "cannot find 'SmallHeroWidgetView' in scope"

- [ ] **Step 3: Implement Widget Views & Timeline Provider**

1. In `Sources/VRemindWidget/Views/SmallHeroWidgetView.swift`:
   - Full-bleed avatar image (`Image(nsImage:)`), dark gradient scrim, crisp white typography, `.widgetURL(channel.deepLinkURL)`.
2. In `Sources/VRemindWidget/Views/MediumWatchlistWidgetView.swift`:
   - Watchlist rows with status badges and `Link(destination: channel.deepLinkURL!)`.
3. In `Sources/VRemindWidget/Views/LargeDashboardWidgetView.swift`:
   - Featured top card and remaining channels listed below.
4. In `Sources/VRemindWidget/VRemindTimelineProvider.swift`:
   - Conforms to `TimelineProvider`, reads snapshot via `WidgetSnapshotStore`, provides fallback entry.
5. In `Sources/VRemindWidget/VRemindWidget.swift`:
   - `@main struct VRemindWidgetBundle: WidgetBundle` and `struct VRemindWidget: Widget` with `StaticConfiguration(kind: "VRemindWidget", provider: VRemindTimelineProvider())`.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash scripts/test.sh --filter WidgetViewTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/VRemindWidget/ Tests/VRemindKitTests/WidgetViewTests.swift
git commit -m "feat(widget): implement Small, Medium, and Large WidgetKit views and bundle"
```

---

### Task 6: Packaging, Sandbox Entitlements, and Build Script Assembly

**Files:**
- Modify: `Package.swift`
- Create: `Resources/Widget.entitlements`
- Create: `Resources/Widget-Info.plist`
- Modify: `scripts/build-app.sh`

**Interfaces:**
- Produces: `build/VRemind.app/Contents/PlugIns/VRemindWidget.appex` signed and packaged.

- [ ] **Step 1: Create `Resources/Widget.entitlements` and `Resources/Widget-Info.plist`**

1. Create `Resources/Widget.entitlements` with `com.apple.security.app-sandbox = true`.
2. Create `Resources/Widget-Info.plist` with `CFBundleIdentifier = com.caitlyn.vremind.widget`, `CFBundlePackageType = XPC!`, and `NSExtensionPointIdentifier = com.apple.widgetkit-extension`.

- [ ] **Step 2: Update `Package.swift`**

Add executable target `VRemindWidget`:
```swift
.executableTarget(
    name: "VRemindWidget",
    dependencies: ["VRemindKit"],
    path: "Sources/VRemindWidget"
)
```

- [ ] **Step 3: Update `scripts/build-app.sh` to package `.appex`**

In `scripts/build-app.sh`:
1. Compile `VRemindWidget` for `arm64` and `x86_64` (or host architecture fallback).
2. Create `$APP_DIR/Contents/PlugIns/VRemindWidget.appex/Contents/MacOS`.
3. Copy/lipo binary to `$APP_DIR/Contents/PlugIns/VRemindWidget.appex/Contents/MacOS/VRemindWidget`.
4. Copy `Resources/Widget-Info.plist` to `$APP_DIR/Contents/PlugIns/VRemindWidget.appex/Contents/Info.plist`.
5. Ad-hoc codesign `.appex` with entitlements:
   `codesign --force --sign - --entitlements Resources/Widget.entitlements "$APP_DIR/Contents/PlugIns/VRemindWidget.appex"`
6. Ad-hoc codesign parent app:
   `codesign --force --deep --sign - "$APP_DIR"`

- [ ] **Step 4: Run build script and automated tests to verify**

Run: `bash scripts/test.sh && bash scripts/build-app.sh`
Expected: All tests pass, universal `VRemind.app` is assembled with `Contents/PlugIns/VRemindWidget.appex` embedded and validly codesigned.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Resources/Widget.entitlements Resources/Widget-Info.plist scripts/build-app.sh
git commit -m "feat(widget): integrate VRemindWidget.appex packaging and codesigning into build-app.sh"
```
