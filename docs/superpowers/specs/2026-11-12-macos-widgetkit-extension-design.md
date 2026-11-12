# macOS WidgetKit Extension (`VRemindWidget`) Design

**Date:** 2026-11-12  
**Status:** Approved / Ready for Planning  
**Topic:** Native macOS WidgetKit extension for VRemind supporting Small, Medium, and Large widgets across macOS 12 Monterey (Notification Center) and macOS 14+ Sonoma/Sequoia (Desktop & Notification Center), built with pure Swift Package Manager and zero external dependencies.  
**Target Version:** 1.1.0  

---

## 1. Intent & Context

On MacBooks equipped with a display notch, crowded menu bars cause status icons on the left of the system tray to be obscured behind the physical notch cutout and vanish from view. While VRemind provides local desktop notifications and a dynamic menu bar icon, relying exclusively on the menu bar creates a reliability gap for users with many menu bar utilities or smaller laptop displays.

To solve this, VRemind will introduce an official Apple **WidgetKit extension** (`VRemindWidget.appex`) embedded directly within the application bundle. 
- On **macOS 14 Sonoma and newer**, users can place VRemind widgets directly on their desktop for ambient, persistent live stream monitoring.
- On **macOS 12 Monterey and 13 Ventura**, the widget integrates natively into the macOS Notification Center sidebar, giving Monterey users reliable at-a-glance status beyond the menu bar.

In keeping with VRemind's core architecture, this will be built **100% in Swift with SwiftUI and AppKit**, without third-party frameworks, without requiring a full 15GB+ Xcode installation (pure Xcode Command Line Tools / SPM), and without requiring a paid Apple Developer ID provisioning profile.

---

## 2. Goals, Non-Goals & Anti-Goals

### Goals
- **Official WidgetKit Integration**: Native Apple WidgetKit extension conforming to `Widget` and `WidgetBundle` using `StaticConfiguration` for universal macOS 12.0+ compatibility.
- **Three Supported Widget Sizes**:
  1. **Small (`systemSmall`)**: Hero single-creator view. Features a full-bleed creator profile picture background, a shadowy dark gradient scrim for contrast, bold white typography (creator name, stream title, live status / uptime), and launches the stream directly in the user's default browser on click.
  2. **Medium (`systemMedium`)**: Multi-channel watchlist overview displaying 2–3 active creators with status badges, stream titles, and individual click-to-watch links (`Link(destination:)`).
  3. **Large (`systemLarge`)**: Full dashboard featuring the top live stream card and a scroll-free list of upcoming scheduled streams and offline channels.
- **Direct Container Storage Architecture (Ad-Hoc Signing Friendly)**:
  - The main app (`VRemind`) is an unsandboxed `LSUIElement` app. It writes `widget-cache.json` and cached avatars directly into the widget extension's sandbox container (`~/Library/Containers/com.caitlyn.vremind.widget/Data/Library/Application Support/VRemind/`).
  - The widget extension is sandboxed (`com.apple.security.app-sandbox = true` as required by `chronod`) and reads directly from its own container using standard `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)`.
  - This avoids requiring Apple Developer ID provisioned App Groups, which fail validation on ad-hoc signed binaries.
- **Zero Duplicate Polling & Battery Efficiency**: The widget extension makes zero direct network requests and parses no raw HTML, eliminating redundant scraping, avoiding YouTube IP rate limits, and conserving MacBook battery.
- **CLI & Pure SPM Build Pipeline**: Build and package the `.appex` extension bundle directly within `scripts/build-app.sh` using `swift build`, assembling `Contents/PlugIns/VRemindWidget.appex` and ad-hoc code-signing it with entitlements.
- **Custom Deep-Link Scheme for Browser Launch**:
  - Register `vremind://` URL scheme in `Resources/Info.plist`.
  - Widget items link to `vremind://open-stream?url=<encoded_youtube_url>`.
  - `AppDelegate.swift` handles `application(_:open:)` by dispatching the decoded URL to `NSWorkspace.shared.open(...)` (opening in default browser without stealing focus or forcing the popover to show).
- **Sensible Edge-Case Fallbacks**:
  - If multiple channels are live: Small widget spotlights the creator who went live most recently.
  - If all channels are offline: Small widget displays the primary/starter creator's avatar with a dimmed, grayscale aesthetic and "All channels offline".
  - If avatar image fails to load or is not yet cached: Renders a high-contrast branded monogram / fallback graphic.

### Non-Goals
- Full Xcode IDE project files (`.xcodeproj` or `xcodegen`) that would require gigabytes of disk storage.
- Interactive iOS 17 / macOS 14 `AppIntent` configurations that break compatibility with macOS 12 Monterey.
- Background scraping or independent network polling inside the WidgetKit extension.
- Third-party helper binaries or Electron wrappers.

### Anti-Goals
- Never require paid Apple Developer Program certificates or provisioned App Groups (must run and reload via standard ad-hoc signing).
- Never block or crash the main app if the widget extension fails to load.
- Never drain system resources by running rapid timeline reload loops.

---

## 3. Approaches Considered

### Approach 1: SPM Extension Target + Direct Container Snapshot *(Chosen)*
- **Architecture**: A new `VRemindWidget` executable target in `Package.swift` importing `WidgetKit`, `SwiftUI`, and `VRemindKit`. Main unsandboxed app serializes state directly into the widget extension's container directory (`~/Library/Containers/com.caitlyn.vremind.widget/Data/Library/Application Support/VRemind/widget-cache.json`) and notifies `WidgetCenter`. The sandboxed widget extension reads from its own container via standard `FileManager`. `scripts/build-app.sh` compiles universal binaries, constructs the `.appex` structure in `Contents/PlugIns/`, and signs both the extension and app.
- **Pros**: 100% compliant with zero external dependencies, works with Xcode Command Line Tools, lightweight on disk, battery-efficient, fully compatible with macOS 12 Monterey through macOS 15+, and functions flawlessly with ad-hoc code signing without requiring Apple Developer ID provisioning profiles.
- **Cons**: Requires shell assembly for the `.appex` bundle in `build-app.sh`.
- **Why Chosen**: Meets all user requirements and preserves disk space and command-line ergonomics.

### Approach 2: Full Xcode Project Migration (`.xcodeproj` / XcodeGen)
- **Architecture**: Migrate project to an Xcode project managing app and widget targets.
- **Pros**: Standard Apple graphical workflow.
- **Cons**: Requires full Xcode installation (15GB+ SSD footprint), breaks `bash scripts/build-app.sh` for users with only Command Line Tools.
- **Why Rejected**: User explicitly rejected this due to scarce SSD storage.

### Approach 3: Independent Network Scraping inside Widget Extension
- **Architecture**: Widget extension makes its own network requests to YouTube `/live`.
- **Pros**: Runs independently of main app polling.
- **Cons**: Apple severely throttles widget network execution and execution budgets; duplicate HTML parsing drains battery and risks YouTube IP bans.
- **Why Rejected**: Unreliable and inefficient.

---

## 4. Detailed Specification

### 4.1 Data Models (`VRemindKit/Models/WidgetSnapshot.swift`)

A lightweight, Codable data transfer object shared between `VRemind` and `VRemindWidget`:

```swift
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public let generatedAt: Date
    public let channels: [WidgetChannelItem]

    public init(generatedAt: Date, channels: [WidgetChannelItem]) {
        self.generatedAt = generatedAt
        self.channels = channels
    }
}

public struct WidgetChannelItem: Codable, Equatable, Sendable, Identifiable {
    public var id: String { handle }
    public let handle: String
    public let displayName: String
    public let avatarFilename: String? // Local filename in Avatars/ cache directory
    public let avatarURL: URL?
    public let statusKind: StatusKind // .live, .upcoming, .offline, .unknown
    public let streamTitle: String?
    public let videoId: String?
    public let liveStartedAt: Date?
    public let upcomingStartTime: Date?
    public let lastStreamedAt: Date?

    public enum StatusKind: String, Codable, Sendable {
        case live
        case upcoming
        case offline
        case unknown
    }

    public var deepLinkURL: URL? {
        let target = videoURL?.absoluteString ?? channelURL.absoluteString
        var components = URLComponents()
        components.scheme = "vremind"
        components.host = "open-stream"
        components.queryItems = [URLQueryItem(name: "url", value: target)]
        return components.url
    }
}
```

### 4.2 Data Storage & Container Resolution (`VRemindKit/Services/WidgetSnapshotStore.swift`)

The `WidgetSnapshotStore` handles reading and writing `widget-cache.json` across the process boundary:
- **Widget Container Identification**:
  - `Bundle ID`: `com.caitlyn.vremind.widget`
  - In the host app: Resolves `~/Library/Containers/com.caitlyn.vremind.widget/Data/Library/Application Support/VRemind/` (creates directories if missing).
  - In the widget extension: Resolves `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!/VRemind/` (its own container, no sandbox violation).
- **File Structure**:
  - `.../VRemind/widget-cache.json`
  - `.../VRemind/Avatars/<channel_handle>.jpg`
- **Export Method**: `WidgetSnapshotStore.writeSnapshot(from channels: [WatchedChannel], statuses: [String: StreamStatus]) async throws`
  - Maps domain models into `WidgetSnapshot`.
  - Automatically writes cached avatar images to `.../VRemind/Avatars/`.
  - Calls `WidgetCenter.shared.reloadAllTimelines()` on macOS 12+.
- **Import Method**: `WidgetSnapshotStore.readSnapshot() -> WidgetSnapshot?`
  - Safely decodes `widget-cache.json`. Returns fallback starter data if file does not exist.

### 4.3 Deep Link Routing (`VRemind/AppDelegate.swift` & `Resources/Info.plist`)

1. **Info.plist Registration**:
   ```xml
   <key>CFBundleURLTypes</key>
   <array>
       <dict>
           <key>CFBundleURLName</key>
           <string>com.caitlyn.vremind.deeplink</string>
           <key>CFBundleURLSchemes</key>
           <array>
               <string>vremind</string>
           </array>
       </dict>
   </array>
   ```
2. **AppDelegate Open URL Handler**:
   ```swift
   func application(_ application: NSApplication, open urls: [URL]) {
       for url in urls {
           guard url.scheme == "vremind", url.host == "open-stream",
                 let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                 let targetString = components.queryItems?.first(where: { $0.name == "url" })?.value,
                 let targetURL = URL(string: targetString) else {
               continue
           }
           NSWorkspace.shared.open(targetURL)
       }
   }
   ```

### 4.4 Widget Views (`VRemindWidget/Views/`)

#### 1. Small Hero Widget (`SmallHeroWidgetView`)
- Full-bleed avatar background:
  - Loads local cached avatar from container `Avatars/` directory or falls back to monogram.
  - Clipped to widget bounds with `.aspectRatio(contentMode: .fill)`.
- Scrim:
  - `LinearGradient(gradient: Gradient(colors: [.black.opacity(0.15), .black.opacity(0.55), .black.opacity(0.95)]), startPoint: .top, endPoint: .bottom)`
- High-contrast white typography:
  - Top: `🔴 LIVE` pill + elapsed uptime (e.g., `1h 24m`).
  - Bottom: Creator name in `.headline.bold()`, stream title in `.caption` (2 lines max), and watch hint.
- Deep Link:
  - Wrapped in `.widgetURL(channel.deepLinkURL)` which routes through `vremind://open-stream` straight into the default browser.
- Offline state:
  - Avatar dimmed with `.saturation(0.2).opacity(0.6)`.
  - Label: "All channels offline" + last live timestamp.

#### 2. Medium Watchlist Widget (`MediumWatchlistWidgetView`)
- Header: App title + count of monitored channels.
- List: Up to 3 active creators (prioritizing `.live`, then `.upcoming`, then `.offline`).
- Interactive links: Each row uses `Link(destination: channel.deepLinkURL!)` to open that specific creator's stream.

#### 3. Large Dashboard Widget (`LargeDashboardWidgetView`)
- Featured live broadcast banner on top (similar to Small widget card).
- Watchlist grid / list below showing upcoming schedules and offline channels with individual deep links.

### 4.5 Packaging & Build System Updates (`scripts/build-app.sh`)

1. **`Package.swift`**:
   - Add target `VRemindWidget` (`path: "Sources/VRemindWidget"`, dependencies: `["VRemindKit"]`).
2. **Entitlements**:
   - `Resources/Widget.entitlements`:
     ```xml
     <?xml version="1.0" encoding="UTF-8"?>
     <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
     <plist version="1.0">
     <dict>
         <key>com.apple.security.app-sandbox</key>
         <true/>
         <key>com.apple.security.files.user-selected.read-only</key>
         <true/>
     </dict>
     </plist>
     ```
3. **`Resources/Widget-Info.plist`**:
   - `CFBundleIdentifier`: `com.caitlyn.vremind.widget`
   - `CFBundlePackageType`: `XPC!`
   - `NSExtension`:
     - `NSExtensionPointIdentifier`: `com.apple.widgetkit-extension`
     - `NSExtensionPrincipalClass`: empty (SwiftUI `@main`)
4. **`scripts/build-app.sh`**:
   - Build universal binaries for `VRemindWidget` (`arm64` + `x86_64`) targeting `macos12.0`.
   - Create directory `$APP_DIR/Contents/PlugIns/VRemindWidget.appex/Contents/MacOS/`.
   - Copy universal binary to `$APP_DIR/Contents/PlugIns/VRemindWidget.appex/Contents/MacOS/VRemindWidget`.
   - Copy `Resources/Widget-Info.plist` to `$APP_DIR/Contents/PlugIns/VRemindWidget.appex/Contents/Info.plist`.
   - Codesign `.appex` with sandbox entitlement:
     `codesign --force --sign - --entitlements Resources/Widget.entitlements "$APP_DIR/Contents/PlugIns/VRemindWidget.appex"`
   - Codesign outer `.app` bundle:
     `codesign --force --deep --sign - "$APP_DIR"`

---

## 5. What's Left to the Builder

- Fine-tuning exact typography font scales for Small vs Medium widgets across light/dark desktop modes.
- Local avatar image disk writing format (JPEG compression vs raw data).
- Automated test coverage in `Tests/VRemindKitTests/` for:
  - `WidgetSnapshot` encoding and decoding.
  - `WidgetSnapshotStore` file I/O, container path resolution, and fallback handling.
  - Sorting logic for determining hero creator in Small widget.
  - Deep link URL format parsing in `AppDelegate`.
