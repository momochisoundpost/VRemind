# Native Markdown Video Renderer & Backup/Restore Design Document

- **Status:** Complete (Ready for Approval)
- **Date:** 2026-11-13
- **Author:** Antigravity / Caitlyn Momochi
- **Target Release:** VRemind v1.3.1

---

## 1. Intent & The Why

VRemind's native macOS 12+ `MarkdownView` (introduced for GitHub update release notes in `UpdateAvailableView`) was recently recognized and indexed by the XERJ open-source Corpus Hub as an exemplary native Swift reference.

However, real-world GitHub release notes frequently include markdown elements not yet supported by VRemind's lightweight parser—most notably blockquotes (`> quote text`, which currently leak raw `>` characters into paragraphs, as seen in the v1.3 release notes) and embedded video demos (`<video src="...">`, `.mp4` / `.mov` clips uploaded to GitHub releases/issues). 

Furthermore, users managing multiple VTuber/streamer watchlists have requested a clean, safe way to export and restore their configuration (watchlist channels and app preferences) without manually digging into macOS `UserDefaults` plists.

This project delivers:
1. A rich, lightweight, 100% native markdown renderer supporting blockquotes, ordered lists, inline styling, and inline looping video demos.
2. A streamlined JSON Backup & Restore interface in the Preferences window with automated service cache invalidation.

---

## 2. Goals, Non-Goals, & Anti-Goals

### Goals
- **Fix Markdown Parsing:** Properly parse markdown blockquotes (`> text`), numbered lists (`1. item`), horizontal dividers, inline text styling, code blocks, and media without leaking raw markdown control characters.
- **Native Video Support in Release Notes:** Detect and render video assets embedded in GitHub release markdown (`<video src="...">`, markdown links/images pointing to `.mp4`/`.mov`, or GitHub user attachments wrapped in `<video>`).
- **Muted Looping Autoplay (Option A):** Play changelog video clips automatically on a silent loop once visible, matching the modern GIF/video changelog teaser experience, with an overlay control to unmute/pause.
- **Resource Discipline:** Completely pause and tear down AVPlayer instances when the update window is hidden or dismissed to consume 0% background CPU/GPU.
- **JSON Backup & Export:** Allow users to export their complete watchlist and application settings into a portable, versioned JSON file via `NSSavePanel`.
- **JSON Restore & Validation:** Allow users to import a backup file via `NSOpenPanel`, validate schema compatibility, prompt with a clear confirmation alert, and cleanly overwrite current settings and channels.
- **Immediate State Synchronization:** When a backup is restored, trigger immediate refresh of `StreamMonitorService` and update the Widget snapshot.
- **macOS 12+ & Non-Metal Compatibility:** Retain 100% compatibility with macOS 12 Monterey, software rasterization (non-Metal GPUs / Hackintosh), and 0 external third-party dependencies.

### Non-Goals
- Building a general-purpose web browser or full CommonMark HTML engine.
- Merging / diffing watchlist items during restore (full state overwrite with user confirmation is intended).
- Cloud sync (iCloud / Google Drive) for backups.

### Anti-Goals
- Spawning WebKit / `WKWebView` processes for release notes (violates memory and native aesthetic requirements).
- Heavy third-party Swift Package Manager dependencies.
- Audio autoplay: videos MUST never autoplay with sound enabled.

---

## 3. Constraints

- **Platform:** macOS 12.0 Monterey (`.macOS(.v12)`) and newer.
- **Dependencies:** Strictly zero external Swift packages. Use only standard Apple frameworks: `SwiftUI`, `AppKit`, `AVKit`, `AVFoundation`, `Combine`.
- **Performance:** Release notes modal must display instantaneously without blocking the main actor. AVPlayer buffering must occur asynchronously.
- **Sandboxing & File Safety:** Backup export and restore must operate via system `NSSavePanel` and `NSOpenPanel` granting explicit user file access.

---

## 4. Approaches Considered & Trade-Offs

### Approach 1: Pure Native SwiftUI/AVKit Extensions (Chosen)
- **Description:** 
  - Extend `MarkdownBlock` with `.blockquote(text:)`, `.numberedList(index: Int, text: String)`, and `.video(url: URL, alt: String?)`.
  - Extend `MarkdownParser` with regular expressions and line scanning for quotes, lists, `<video>` tags, and video URLs.
  - Implement `MarkdownVideoPlayerView` using standard `AVKit` / `AVPlayer` with loop observation, mute state management, and fallback error handling.
  - Add `BackupPayload: Codable` and export/restore handlers in `PreferencesViewModel` using `NSSavePanel` and `NSOpenPanel`, with service notification to refresh the stream monitor and widget cache.
- **Pros:** 
  - 100% native AppKit/SwiftUI.
  - Featherweight binary footprint and memory usage.
  - Preserves the clean, self-contained architecture that earned XERJ Corpus Hub inclusion.
- **Cons:** Custom parser rules must be maintained for new syntax edge cases.
- **Decision:** Chosen because it meets all lean performance, privacy, and compatibility requirements.

### Approach 2: Embedded WebKit (`WKWebView`)
- **Description:** Render GitHub release markdown via an embedded web view with HTML5 `<video autoplay loop muted>` tags.
- **Pros:** Instant full CommonMark & HTML5 video support.
- **Cons:** High memory overhead (60–100MB helper processes), potential WebKit sandbox hurdles, non-native appearance.
- **Decision:** Rejected.

### Approach 3: Third-Party Markdown Swift Package
- **Description:** Pull in external packages like `MarkdownUI` or `Down`.
- **Pros:** Full CommonMark compliance.
- **Cons:** Adds third-party dependencies to a previously dependency-free library, still requires writing custom video player components.
- **Decision:** Rejected.

---

## 5. Detailed Architecture & Design

### 5.1 Markdown Parser Extensions (`MarkdownParser.swift`)

#### New `MarkdownBlock` Cases
```swift
public enum MarkdownBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(text: String)
    case bullet(text: String)
    case numberedList(index: Int, text: String)
    case blockquote(text: String)
    case codeBlock(code: String)
    case divider
    case image(url: URL, alt: String?)
    case video(url: URL, alt: String?)
}
```

#### Parsing Rules & Asset Detection
1. **Blockquotes:**
   - Detect lines starting with `>` (e.g. `> quoted text`).
   - Consecutive `>` lines are accumulated, stripped of leading `>`, and trimmed into a single `.blockquote(text:)` block.
2. **Numbered Lists:**
   - Regex: `^([0-9]+)\.\s+(.*)$`
   - Emits `.numberedList(index: Int, text: String)`.
3. **Media & Video Assets:**
   - **HTML `<video>` tags:** `<video\b[^>]*\bsrc\s*=\s*["'](https?://[^"']+)["'][^>]*>` (matches both extensioned URLs and GitHub `user-attachments/assets/<uuid>` URLs).
   - **Markdown video syntax:** `!\[([^\]]*)\]\((https?://[^\s\)]+\.(mp4|mov|m4v))\)`
   - **Markdown links to videos:** `\[([^\]]*)\]\((https?://[^\s\)]+\.(mp4|mov|m4v))\)`
   - **HTML `<img>` tags / Markdown images:** `!\[alt\](url)` or `<img src="url">` always map to `.image(url:alt:)`.
   - **Extensionless URLs:** Standalone URLs without `<video>` wrapper remain plain clickable markdown links, preventing false-positive AVPlayer loading of non-video assets.
   - **Format Support:** Strictly native macOS formats (`.mp4`, `.mov`, `.m4v`). WebM is intentionally excluded since AVFoundation lacks native VP8/VP9/AV1 decoding on macOS 12; WebM links render as standard clickable web links.

---

### 5.2 Native Video Component (`MarkdownVideoPlayerView.swift`)

A SwiftUI view backed by `AVKit` / `AVPlayer`:
- **Looping & Mute:**
  - Initialized with `player.isMuted = true`.
  - Observes `AVPlayerItemDidPlayToEndTimeNotification` to seek back to `.zero` and replay immediately.
- **Controls & Overlay:**
  - Compact rounded-corner presentation (`cornerRadius: 8`).
  - Small pill badge at top-right:
    - Default: `Muted 􀊢`
    - Tapping toggles between muted and unmuted.
  - Hover / Tap controls: Clicking anywhere on the video toggles pause / play with a subtle center icon indicator.
- **Failure & Loading State:**
  - If the video item fails to load or media decoding encounters an error, displays an unobtrusive placeholder with an "Open Video in Browser" button (`LinkOpener.open(url)`).
- **Lifecycle Management:**
  - In `onDisappear`: calls `player.pause()`, removes notification observers, and releases player resources to ensure no background battery or memory draw.

---

### 5.3 Blockquote Visual Styling (`MarkdownView.swift`)

When `.blockquote(text:)` is rendered:
- Left vertical stroke: `Rectangle().fill(Theme.accent).frame(width: 3)`
- Text style: `.font(.body).italic().foregroundColor(.secondary)`
- Background: subtle `Color.secondary.opacity(0.08)` rounded background.
- Padding: `padding(.leading, 8).padding(.vertical, 4)`

---

### 5.4 Backup & Restore System (`PreferencesStore` & `ChannelStore`)

#### Data Model (`BackupPayload.swift`)
```swift
public struct BackupPayload: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let appVersion: String
    public let exportedAt: Date
    public let settings: AppSettings
    public let channels: [WatchedChannel]

    public init(
        settings: AppSettings,
        channels: [WatchedChannel],
        appVersion: String = AppConstants.appVersion,
        exportedAt: Date = Date()
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.appVersion = appVersion
        self.exportedAt = exportedAt
        self.settings = settings
        self.channels = channels
    }
}
```

#### Sanitization on Restore
To protect app state:
- `hasCompletedOnboarding` is guaranteed to be set to `true` (preventing an unwanted onboarding wizard popup on restart).
- Ephemeral live alert tracking IDs (`lastNotifiedVideoId`, `lastNotifiedUpcomingId`) are reset to `nil` so newly monitored channels receive timely alerts on their next stream.

#### UI in `PreferencesView.swift`
Placed in the **General** tab directly above the Danger Zone:

```
┌────────────────────────────────────────────────────────┐
│ Data & Backup                                          │
│ Export your watchlist and preferences to a JSON file,  │
│ or restore from a previous backup.                     │
│                                                        │
│ [ Export Backup... ]       [ Restore Backup... ]       │
└────────────────────────────────────────────────────────┘
```

#### Export Flow
1. User clicks **Export Backup...**.
2. App constructs `BackupPayload(settings: preferencesStore.settings, channels: channelStore.channels)`.
3. Encodes with pretty-printed `JSONEncoder` (`.prettyPrinted`, `.sortedKeys`, `.iso8601`).
4. Opens `NSSavePanel`:
   - `allowedContentTypes = [.json]`
   - `nameFieldStringValue = "vremind-backup-\(dateString).json"`
5. On `.OK`, writes JSON data to the selected file URL.

#### Restore Flow & Synchronization
1. User clicks **Restore Backup...**.
2. Opens `NSOpenPanel`:
   - `allowedContentTypes = [.json]`
   - `allowsMultipleSelection = false`
3. On `.OK`, reads data from URL and decodes `BackupPayload`.
4. If invalid JSON or unsupported schema version, displays error alert: *"Invalid Backup File: The selected file could not be read as a VRemind backup."*
5. If valid, displays confirmation alert:
   - Title: *"Restore Backup?"*
   - Message: *"This will replace your current watchlist (\(currentCount) channels) and app preferences with the backup from \(dateString). This cannot be undone."*
   - Buttons: **Restore (Destructive)** and **Cancel**.
6. On confirmation:
   - Updates `preferencesStore.settings = sanitizedSettings`
   - Calls `channelStore.saveChannels(sanitizedChannels)`
   - Synchronizes launch-at-login state with `LaunchAtLoginHelper.setEnabled(sanitizedSettings.launchAtLogin)`
   - Triggers `onRestore` callback wired to `AppDelegate`:
     - Calls `await monitorService.refreshAll()`
     - Exports updated `WidgetSnapshot` to disk for Notification Center widgets.

---

## 6. What's Left to the Builder

- Exact layout spacing and typography tokens matching `Theme.swift`.
- Edge-case attributes in `<video>` tags (`width`, `height`, `controls`).
- Unit test suite coverage for:
  - Markdown parser: blockquotes, numbered lists, video tags, combined markdown blocks.
  - Backup/Restore encoding, decoding, corrupted file handling, sanitization, and schema validation.
