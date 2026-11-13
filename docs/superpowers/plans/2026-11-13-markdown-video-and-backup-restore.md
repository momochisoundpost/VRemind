# Native Markdown Video Renderer & Backup/Restore Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade VRemind's native macOS 12 markdown renderer with full block/inline formatting fixes and lightweight muted-looping `AVKit` video playback, and add versioned JSON backup/restore to Preferences with immediate monitor and widget synchronization.

**Architecture:** `MarkdownParser` and `MarkdownBlock` (in `MarkdownView.swift`) remain pure synchronous Swift without network calls, adding blockquotes, nested/ordered/task lists, GFM tables, and `<video>` / Apple-native video URL detection while delegating playback to a new `MarkdownVideoPlayerView` backed by `AVPlayer` + `AVPlayerView(controlsStyle: .none)`. On the preferences side, a pure `BackupPayload` model handles versioned JSON serialization, schema validation, and ephemeral notification-state sanitization, wired through `PreferencesViewModel` (`NSSavePanel` / `NSOpenPanel`) to `PreferencesWindowController` and `AppDelegate`, which purges stale `StreamMonitorService` statuses and refreshes widgets on restore.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit, AVKit, AVFoundation, UniformTypeIdentifiers, Combine, Swift Testing (`Testing`), Xcode Command Line Tools (`bash scripts/test.sh`, `bash scripts/build-app.sh`).

**Spec:** [docs/superpowers/specs/2026-11-13-markdown-video-and-backup-restore-design.md](file:///Users/karyl/CaitDev/CaitlynSwift/docs/superpowers/specs/2026-11-13-markdown-video-and-backup-restore-design.md)

## Global Constraints

- **Platform & Build:** Target macOS 12.0 Monterey (`.macOS(.v12)`) Universal (`arm64` + `x86_64`), built strictly with Xcode Command Line Tools (`bash scripts/test.sh` and `bash scripts/build-app.sh`). No macOS 13+ exclusive APIs (`Grid`, `NavigationStack`, `scrollIndicators`, `ImageRenderer`).
- **Zero Third-Party Dependencies:** Use only standard Apple SDK frameworks (`SwiftUI`, `AppKit`, `AVKit`, `AVFoundation`, `UniformTypeIdentifiers`, `Combine`) and `VRemindCore`. Never embed `WKWebView`.
- **Non-Metal GPU Compatibility:** Views must render cleanly under CPU software rasterization without Metal shaders or SpriteKit.
- **Audio & Power Discipline:** Release-note videos must always start muted (`player.isMuted = true`) and immediately pause/release `AVPlayer` resources in `.onDisappear`.
- **No Unrequested `VRemindCore` Changes:** All changes live within `CaitlynSwift` (`VRemindKit`, `VRemind`, and `VRemindKitTests`).

## Review Focus

1. **Extensionless GitHub `user-attachments/assets/<uuid>` URL differentiation:** `<video src="https://github.com/user-attachments/assets/...">` and `<video><source src="..."></video>` must parse as `.video`, `<img>` / `![alt](...)` as `.image`, and bare extensionless asset URLs on standalone lines as `.paragraph` clickable links so non-video attachments never trigger `AVPlayer` errors. *(Pinned in Task 1)*
2. **Unsupported `.webm` links and playback failure handling:** Links ending in `.webm` must remain clickable markdown links (never `.video`), and failed `.mp4`/`.mov`/`.m4v` streams must transition `MarkdownVideoPlayerController` into `hasFailed == true` showing an "Open Video in Browser" fallback while cleaning up observers on `.onDisappear`. *(Pinned in Task 1 & Task 2)*
3. **Blockquotes, multi-line quotes, nested/ordered lists, and GFM tables:** Consecutive `>` lines (with or without leading space, including blank `>` separators) must collapse into `.blockquote` without leaking literal `>`, indented sub-bullets must preserve indent depth, numbered lists must stay separate from paragraphs, and GFM tables must render on macOS 12 without `Grid`. *(Pinned in Task 1)*
4. **Malformed, non-backup, or future-schema backup JSON resilience:** Feeding truncated text, raw `[WatchedChannel]` JSON, or `schemaVersion: 99` / `0` into `BackupPayload.decodeAndValidate(from:)` and `PreferencesViewModel.prepareRestore(from:)` must surface `backupErrorMessage` without mutating existing `PreferencesStore` or `ChannelStore` data. *(Pinned in Task 3 & Task 4)*
5. **Post-restore state sanitization and monitor/widget synchronization:** Restoring a valid backup containing `hasCompletedOnboarding: false` and stale `lastNotifiedVideoId`/`lastNotifiedUpcomingId` values must force `hasCompletedOnboarding == true`, clear alert tracking IDs, overwrite stores, sync `LaunchAtLoginHelper`, purge stale `StreamMonitorService.statuses` (even across in-flight passes), and refresh the widget snapshot. *(Pinned in Task 3, Task 4 & Task 5)*

---

## File Structure

- **Create:** `Sources/VRemindKit/Views/Components/MarkdownVideoPlayerView.swift` — `MarkdownVideoPlayerController`, `AVPlayerContainerView` (`NSViewRepresentable` wrapping `AVPlayerView` with `.none` controls), and `MarkdownVideoPlayerView` (muted looping, mute toggle pill, tap-to-pause, loading/failure fallback, `.onDisappear` teardown).
- **Create:** `Sources/VRemindKit/Models/BackupPayload.swift` — `BackupError` and versioned `BackupPayload` with JSON encoding/decoding, schema validation, filename helper, and `sanitizedForRestore()`.
- **Create:** `Tests/VRemindKitTests/BackupPayloadTests.swift` — Unit tests for `BackupPayload` encoding, validation, error handling, and sanitization.
- **Modify:** `Sources/VRemindKit/Views/Components/MarkdownView.swift` — Expand `MarkdownBlock`, upgrade `MarkdownParser` (blockquotes, nested bullets, numbered lists, task lists, GFM tables, `<video>`/`<source>`/`<img>`/linked-image/video-extension detection, bare URL autolinking, `<br>` normalization), and add SwiftUI rendering for all new block types.
- **Modify:** `Sources/VRemindKit/Services/StreamMonitorService.swift` — Add `clearStatuses()` and epoch/channel-set guarding in `performRefreshPass()` so stale channels cannot return after restore/reset.
- **Modify:** `Sources/VRemindKit/Views/Preferences/PreferencesView.swift` — Add backup/restore state & methods to `PreferencesViewModel`, add `Data & Backup` section, scrollable `generalTab`, confirmation alert, and error alert in `PreferencesView`.
- **Modify:** `Sources/VRemind/PreferencesWindowController.swift` — Add `onRestore` callback parameter and adjust window height to `460`.
- **Modify:** `Sources/VRemind/AppDelegate.swift` — Wire `onRestore` to `handleRestore()`, purge `monitorService.clearStatuses()` in both `handleRestore()` and `handleFactoryReset()`, and trigger widget snapshot + stream refresh.
- **Modify Tests:** `Tests/VRemindKitTests/MarkdownViewTests.swift`, `Tests/VRemindKitTests/StreamMonitorServiceTests.swift`, `Tests/VRemindKitTests/PreferencesViewTests.swift`.

---

### Task 1: Upgrade `MarkdownBlock` & `MarkdownParser` + Native Block Rendering

**Files:**
- Modify: `Sources/VRemindKit/Views/Components/MarkdownView.swift:1-245`
- Test: `Tests/VRemindKitTests/MarkdownViewTests.swift:1-71`

**Interfaces:**
- Consumes: `Theme.accent` from `Sources/VRemindKit/Views/Theme.swift`
- Produces:
  - Updated `public enum MarkdownBlock: Equatable, Sendable` preserving existing cases (`.heading`, `.paragraph`, `.bullet(text:)`, `.codeBlock`, `.divider`, `.image`) and adding:
    - `.nestedBullet(indent: Int, text: String)`
    - `.numberedList(index: Int, text: String)`
    - `.taskItem(checked: Bool, text: String)`
    - `.blockquote(text: String)`
    - `.table(headers: [String], rows: [[String]])`
    - `.video(url: URL, alt: String?)`
  - `MarkdownParser.parse(_ markdown: String) -> [MarkdownBlock]`
  - `MarkdownView.inlineText(_ raw: String) -> Text` (normalizing `<br>`/`<br/>` to `\n` and autolinking bare `https://` / `http://` URLs)

- [ ] **Step 1: Write failing tests in `Tests/VRemindKitTests/MarkdownViewTests.swift`**

Append tests to `MarkdownViewTests` asserting exact `MarkdownParser.parse(_:)` output for:
- `testParsesSingleAndMultilineBlockquotes()`:
  - `"> yes, we're a version number late"` -> `[.blockquote(text: "yes, we're a version number late")]`
  - `">Line 1\n> Line 2\n>\n> Second para"` -> `[.blockquote(text: "Line 1 Line 2\n\nSecond para")]`
- `testParsesNestedBulletsNumberedListsAndTaskItems()`:
  - `"- Top\n  - Child\n    * Grandchild\n1. First\n2. Second\n- [ ] Todo\n- [x] Done"` -> `[.bullet(text: "Top"), .nestedBullet(indent: 1, text: "Child"), .nestedBullet(indent: 2, text: "Grandchild"), .numberedList(index: 1, text: "First"), .numberedList(index: 2, text: "Second"), .taskItem(checked: false, text: "Todo"), .taskItem(checked: true, text: "Done")]`
- `testParsesGFMTables()`:
  - `"| Platform | Keyless |\n| :--- | :---: |\n| YouTube | Yes |\n| Twitch | Yes |"` -> `[.table(headers: ["Platform", "Keyless"], rows: [["YouTube", "Yes"], ["Twitch", "Yes"]])]`
- `testParsesVideoTagsAndDistinguishesGitHubAssetURLs()`:
  - `"<video src=\"https://github.com/user-attachments/assets/abc-123\" controls></video>"` -> `.video(url: URL(string: "https://github.com/user-attachments/assets/abc-123")!, alt: nil)`
  - Multi-line `"<video controls muted>\n  <source src=\"https://example.com/demo.mp4\" type=\"video/mp4\">\n</video>"` -> `.video(url: URL(string: "https://example.com/demo.mp4")!, alt: nil)`
  - `"![clip](https://example.com/clip.mov?raw=true)"` and `"[watch](https://example.com/clip.m4v)"` -> `.video(...)`
  - `"[webm](https://example.com/clip.webm)"` -> `.paragraph(text: "[webm](https://example.com/clip.webm)")` (NOT `.video`)
  - `"https://github.com/user-attachments/assets/def-456"` (bare standalone extensionless URL) -> `.paragraph(text: "https://github.com/user-attachments/assets/def-456")` (NOT `.video` or `.image`)
  - `"[![badge](https://example.com/badge.png)](https://example.com)"` -> `.image(url: URL(string: "https://example.com/badge.png")!, alt: "badge")`
- `testRendersExtendedMarkdownBlocksInHostingController()`:
  - Pass markdown combining heading, blockquote, nested bullet, numbered list, task list, table, code block, divider, and bare URL into `MarkdownView(markdown:)` hosted in `NSHostingController` and verify `fittingSize.width >= 0`. (Wire `.video` to a placeholder `Text(alt ?? url.lastPathComponent)` temporarily until Task 2 creates `MarkdownVideoPlayerView`).

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/test.sh --filter MarkdownViewTests`
Expected: FAIL with compile errors (`Type 'MarkdownBlock' has no member 'blockquote'`, `'numberedList'`, `'video'`, etc.).

- [ ] **Step 3: Implement extended `MarkdownBlock`, `MarkdownParser`, and SwiftUI block renderers in `Sources/VRemindKit/Views/Components/MarkdownView.swift`**

Implementation guidance:
- Add the new `MarkdownBlock` cases listed in Interfaces (`nestedBullet(indent:text:)`, `numberedList(index:text:)`, `taskItem(checked:text:)`, `blockquote(text:)`, `table(headers:rows:)`, `video(url:alt:)`).
- In `MarkdownParser.parse(_:)`:
  - Handle multi-line `<video ...>...</video>` and `<img ...>` blocks before line-by-line paragraph accumulation: if a line starts with `<video` (case-insensitive) and doesn't close `</video>` on the same line, buffer until `</video>` (or EOF), join with spaces, and extract `src="..."` from either `<video>` or `<source>` attributes.
  - Detect video syntax via:
    1. `<video ... src="(https?://...)">` or `<source ... src="(https?://...)">` inside a `<video>` block.
    2. Standalone `![alt](url)` or `[alt](url)` where `URL(string: url)?.pathExtension.lowercased()` is in `["mp4", "mov", "m4v"]`.
  - Detect image syntax via `[![alt](imgURL)](linkURL)`, `![alt](imgURL)`, or `<img ... src="imgURL">` (accepting optional markdown image title `"..."`).
  - Accumulate consecutive `>` blockquote lines (stripping leading `>` and at most one following space) into blockquote paragraphs separated by `"\n\n"` whenever an empty `>` line occurs; flush blockquote before non-`>` lines.
  - Detect GFM tables when a `| ... |` header line is immediately followed by a separator line matching `^\|?[\s:\-]+\|[\s\|:\-]*$`; parse subsequent `| ... |` lines as rows, padding/truncating rows to `headers.count`.
  - Detect task items (`- [ ] `, `- [x] `, `* [ ] `, `* [x] ` case-insensitive on `x`) before regular bullets.
  - Count leading indentation spaces (`leadingSpaces / 2`, ignoring tabs as 2 spaces) on `- ` / `* ` / `+ ` bullets: emit `.bullet(text:)` when `indent == 0` and `.nestedBullet(indent: indent, text:)` when `indent > 0`.
  - Detect ordered lists via regex `^([0-9]+)\.\s+(.+)$` -> `.numberedList(index:text:)`.
- In `MarkdownView.blockView(_:)`:
  - Render `.blockquote` with a `3pt` `Theme.accent` leading `RoundedRectangle`, italicized `.secondary` text, subtle `Color.secondary.opacity(0.08)` background, and `6pt` corner radius.
  - Render `.nestedBullet` with `◦` marker and `CGFloat(min(indent, 4)) * 16 + 4` leading padding.
  - Render `.numberedList` with `Text("\(index).").monospacedDigit().foregroundColor(.secondary)` + `inlineText(text)`.
  - Render `.taskItem` with SF Symbol `checked ? "checkmark.square.fill" : "square"` (`Theme.accent` when checked) + `inlineText(text)`.
  - Render `.table` using macOS 12-compatible `VStack(spacing: 0)` + `HStack` columns (never macOS 13 `Grid`), bold header row, `Divider()`, alternating subtle row shading, and `1pt` secondary border.
  - Render `.video` temporarily with `Text(alt ?? url.lastPathComponent)` (Task 2 swaps in `MarkdownVideoPlayerView`).
- In `MarkdownView.inlineText(_:)`:
  - Normalize `<br>`, `<br/>`, `<br />` (case-insensitive) to `\n`, wrap bare `https?://...` URLs not already enclosed in `(...)`, `[...]`, or `<...>` as `[url](url)` using `NSDataDetector` or regex, then construct `AttributedString(markdown:options:)` with `.inlineOnlyPreservingWhitespace`.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash scripts/test.sh --filter MarkdownViewTests`
Expected: PASS (all existing and new `MarkdownViewTests` pass).

- [ ] **Step 5: Commit**

```bash
git add Sources/VRemindKit/Views/Components/MarkdownView.swift Tests/VRemindKitTests/MarkdownViewTests.swift
git commit -m "feat(markdown): fix blockquotes, lists, tables, and video tag parsing"
```

---

### Task 2: Native `MarkdownVideoPlayerView` with AVKit Looping & Failure Fallback

**Files:**
- Create: `Sources/VRemindKit/Views/Components/MarkdownVideoPlayerView.swift`
- Modify: `Sources/VRemindKit/Views/Components/MarkdownView.swift` (replace temporary `.video` placeholder with `MarkdownVideoPlayerView(url: url, alt: alt)`)
- Test: `Tests/VRemindKitTests/MarkdownViewTests.swift`

**Interfaces:**
- Consumes: `MarkdownBlock.video(url: URL, alt: String?)` from Task 1, `LinkOpener.open(_:)`
- Produces:
  - `@MainActor public final class MarkdownVideoPlayerController: ObservableObject` with:
    - `public let url: URL`
    - `public let player: AVPlayer`
    - `@Published public private(set) var isMuted: Bool` (starts `true`)
    - `@Published public private(set) var isPaused: Bool` (starts `false`)
    - `@Published public private(set) var isLoading: Bool`
    - `@Published public private(set) var hasFailed: Bool`
    - `public init(url: URL, player: AVPlayer = AVPlayer())`
    - `public func start()`
    - `public func stop()`
    - `public func toggleMute()`
    - `public func togglePlayPause()`
    - `public func markFailed()` (or internal failure transition testable via `playerItem` failure or helper)
  - `public struct MarkdownVideoPlayerView: View` with `public init(url: URL, alt: String? = nil, onOpenInBrowser: @escaping (URL) -> Void = LinkOpener.open)`

- [ ] **Step 1: Write failing tests in `Tests/VRemindKitTests/MarkdownViewTests.swift`**

Add tests for `MarkdownVideoPlayerController` and `MarkdownVideoPlayerView`:
- `testVideoPlayerControllerDefaultsMutedAndTogglesMuteAndPause()`:
  - Instantiate `MarkdownVideoPlayerController(url: URL(string: "https://example.com/demo.mp4")!)`.
  - Assert `isMuted == true`, `player.isMuted == true`, `isPaused == false`.
  - Call `toggleMute()` -> `isMuted == false`, `player.isMuted == false`; call again -> `true`.
  - Call `togglePlayPause()` -> `isPaused == true`, `player.rate == 0`; call again -> `isPaused == false`.
- `testVideoPlayerControllerStartStopAndFailureFallback()`:
  - Call `start()` -> `player.currentItem != nil`, `player.isMuted == true`, `hasFailed == false`.
  - Call `markFailed()` -> `hasFailed == true`, `isLoading == false`.
  - Call `stop()` -> `player.currentItem == nil`, `player.rate == 0`.
- `testMarkdownVideoPlayerViewAndMarkdownViewWithVideoRenderWithoutCrash()`:
  - Render `MarkdownVideoPlayerView(url: URL(string: "https://example.com/demo.mp4")!, alt: "Demo clip")` and `MarkdownView(markdown: "<video src=\"https://example.com/demo.mp4\"></video>")` inside `NSHostingController`, verifying `fittingSize.width >= 0` and clean deallocation.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/test.sh --filter MarkdownViewTests`
Expected: FAIL (`Cannot find 'MarkdownVideoPlayerController' in scope`).

- [ ] **Step 3: Create `Sources/VRemindKit/Views/Components/MarkdownVideoPlayerView.swift` and wire into `MarkdownView.swift`**

Implementation guidance:
- In `MarkdownVideoPlayerView.swift`, import `AVFoundation`, `AVKit`, `AppKit`, `SwiftUI`.
- Implement `MarkdownVideoPlayerController`:
  - `start()`: guards against duplicate initialization; configures `AVPlayerItem(url: url)`, sets `player.isMuted = isMuted`, `player.actionAtItemEnd = .none`, replaces item, observes `item.observe(\.status, options: [.initial, .new])` dispatching to `@MainActor` (`readyToPlay` -> `isLoading = false`, `failed` -> `markFailed()`), and registers `NotificationCenter.default` observers for `.AVPlayerItemDidPlayToEndTime` (seek to `.zero` and `player.play()` when `!isPaused`) and `.AVPlayerItemFailedToPlayToEndTime` (`markFailed()`).
  - `stop()`: pauses `player`, invalidates status KVO token, removes notification observers, calls `player.replaceCurrentItem(with: nil)`.
  - Ensure `deinit` removes notification observers and invalidates KVO token safely.
- Implement `private struct AVPlayerContainerView: NSViewRepresentable` wrapping `AVPlayerView`:
  - `controlsStyle = .none`, `showsFullScreenToggleButton = false`, `videoGravity = .resizeAspect`, `view.player = player`.
- Implement `MarkdownVideoPlayerView`:
  - Holds `@StateObject private var controller: MarkdownVideoPlayerController`.
  - When `controller.hasFailed`: renders rounded fallback box (`Color.secondary.opacity(0.08)`) with `video.slash` SF Symbol, `alt ?? url.lastPathComponent`, and `"Open Video in Browser"` button calling `onOpenInBrowser(url)`.
  - Otherwise: renders `ZStack` (`frame(maxWidth: .infinity).frame(height: 220)`, `background(Color.black.opacity(0.85))`, `cornerRadius(8)`) containing `AVPlayerContainerView(player: controller.player)`, tap gesture for `controller.togglePlayPause()`, optional small `ProgressView` while `isLoading`, subtle `play.fill` overlay when `isPaused && !isLoading`, and top-right mute capsule button (`Muted` / `Sound` with `speaker.slash.fill` / `speaker.wave.2.fill`) calling `controller.toggleMute()`.
  - Attach `.onAppear { controller.start() }` and `.onDisappear { controller.stop() }`.
- In `MarkdownView.swift`, update `.video(let url, let alt)` case to render `MarkdownVideoPlayerView(url: url, alt: alt)`.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash scripts/test.sh --filter MarkdownViewTests`
Expected: PASS (all `MarkdownViewTests` pass).

- [ ] **Step 5: Commit**

```bash
git add Sources/VRemindKit/Views/Components/MarkdownVideoPlayerView.swift Sources/VRemindKit/Views/Components/MarkdownView.swift Tests/VRemindKitTests/MarkdownViewTests.swift
git commit -m "feat(markdown): add native AVKit muted-looping video player with fallback UI"
```

---

### Task 3: `BackupPayload` Model, Validation, and Sanitization

**Files:**
- Create: `Sources/VRemindKit/Models/BackupPayload.swift`
- Test: `Tests/VRemindKitTests/BackupPayloadTests.swift`

**Interfaces:**
- Consumes: `AppSettings`, `WatchedChannel`, `StreamPlatform`, `AppConstants.appVersion` (from `VRemindCore` via `VRemindKit`)
- Produces:
  - `public enum BackupError: Error, LocalizedError, Equatable, Sendable { case invalidJSON, unsupportedSchemaVersion(Int) }`
  - `public struct BackupPayload: Codable, Equatable, Sendable` with:
    - `public static let currentSchemaVersion = 1`
    - `public let schemaVersion: Int`
    - `public let appVersion: String`
    - `public let exportedAt: Date`
    - `public let settings: AppSettings`
    - `public let channels: [WatchedChannel]`
    - `public init(schemaVersion: Int = BackupPayload.currentSchemaVersion, appVersion: String = AppConstants.appVersion, exportedAt: Date = Date(), settings: AppSettings, channels: [WatchedChannel])`
    - `public func encodedJSONData() throws -> Data`
    - `public static func decodeAndValidate(from data: Data) throws -> BackupPayload`
    - `public func sanitizedForRestore() -> (settings: AppSettings, channels: [WatchedChannel])`
    - `public static func defaultBackupFilename(for date: Date = Date()) -> String`

- [ ] **Step 1: Write failing tests in `Tests/VRemindKitTests/BackupPayloadTests.swift`**

Write tests covering:
- `testRoundTripEncodingAndDecoding()`: create `AppSettings(launchAtLogin: true, notifyOnLive: false, notifyOnUpcoming: true, playNotificationSound: false, hasCompletedOnboarding: true, updateConsent: .allowed, reduceMotion: true)` and mixed YouTube + Twitch `[WatchedChannel]`, call `encodedJSONData()`, decode with `BackupPayload.decodeAndValidate(from:)`, and expect exact equality on `schemaVersion == 1`, `appVersion`, `settings`, and `channels`.
- `testDecodeRejectsCorruptedAndNonBackupJSON()`:
  - Invalid UTF-8 / truncated `{` throws `BackupError.invalidJSON`
  - Valid JSON array `[]` or unrelated object `{"hello":"world"}` throws `BackupError.invalidJSON`
- `testDecodeRejectsUnsupportedSchemaVersion()`:
  - Payload with `"schemaVersion": 99` throws `BackupError.unsupportedSchemaVersion(99)`
  - Payload with `"schemaVersion": 0` throws `BackupError.unsupportedSchemaVersion(0)`
- `testSanitizedForRestoreForcesOnboardingAndClearsNotificationIds()`:
  - Payload with `settings.hasCompletedOnboarding = false`, `settings.reduceMotion = true`, and channel with `lastNotifiedVideoId = "vid1"`, `lastNotifiedUpcomingId = "up1"`, `lastStreamedAt = Date(timeIntervalSince1970: 1700000000)` -> `sanitizedForRestore()` returns `settings.hasCompletedOnboarding == true`, `settings.reduceMotion == true`, channel `lastNotifiedVideoId == nil`, `lastNotifiedUpcomingId == nil`, and preserves `lastStreamedAt`, `name`, `handle`, `platform`, `avatarURL`.
- `testDefaultBackupFilenameFormat()`:
  - `defaultBackupFilename(for:)` returns `"vremind-backup-YYYY-MM-DD.json"` matching `^vremind-backup-\d{4}-\d{2}-\d{2}\.json$`.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/test.sh --filter BackupPayloadTests`
Expected: FAIL (`Cannot find 'BackupPayload' in scope`).

- [ ] **Step 3: Implement `Sources/VRemindKit/Models/BackupPayload.swift`**

Implementation guidance:
- Implement `BackupError` with helpful `errorDescription` messages for `.invalidJSON` and `.unsupportedSchemaVersion(let version)`.
- Implement `BackupPayload` using `JSONEncoder` (`.prettyPrinted`, `.sortedKeys`, `.iso8601` date strategy) and `JSONDecoder` (`.iso8601` date strategy).
- In `decodeAndValidate(from:)`: catch `DecodingError` / other decode errors as `BackupError.invalidJSON`, then verify `(1...Self.currentSchemaVersion).contains(payload.schemaVersion)` or throw `BackupError.unsupportedSchemaVersion(payload.schemaVersion)`.
- In `sanitizedForRestore()`: clone `settings` with `hasCompletedOnboarding = true`, map `channels` clearing `lastNotifiedVideoId = nil` and `lastNotifiedUpcomingId = nil`.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash scripts/test.sh --filter BackupPayloadTests`
Expected: PASS (all 5 `BackupPayloadTests` pass).

- [ ] **Step 5: Commit**

```bash
git add Sources/VRemindKit/Models/BackupPayload.swift Tests/VRemindKitTests/BackupPayloadTests.swift
git commit -m "feat(backup): add versioned BackupPayload model, validation, and restore sanitization"
```

---

### Task 4: `StreamMonitorService.clearStatuses()` & `PreferencesViewModel` Backup/Restore Logic

**Files:**
- Modify: `Sources/VRemindKit/Services/StreamMonitorService.swift:150-170`
- Modify: `Sources/VRemindKit/Views/Preferences/PreferencesView.swift:5-138`
- Test: `Tests/VRemindKitTests/StreamMonitorServiceTests.swift`, `Tests/VRemindKitTests/PreferencesViewTests.swift`

**Interfaces:**
- Consumes: `BackupPayload`, `BackupError`, `PreferencesStore`, `ChannelStore`, `LaunchAtLoginHelper`
- Produces:
  - `StreamMonitorService.clearStatuses()` (public `@MainActor` method)
  - `PreferencesViewModel`:
    - Init adds trailing optional parameter `onRestore: (() -> Void)? = nil` (defaulting `nil`, preserving existing signatures)
    - `@Published public var isShowingRestoreConfirmation: Bool`
    - `@Published public var pendingRestorePayload: BackupPayload?`
    - `@Published public var backupErrorMessage: String?`
    - `@Published public var backupStatusText: String?`
    - `public func buildBackupData() throws -> Data`
    - `public func prepareRestore(from data: Data)`
    - `public func confirmRestore()`
    - `public func cancelRestore()`
    - `public func exportBackup(chooseSaveURL: (() -> URL?)? = nil)`
    - `public func restoreBackup(chooseOpenURL: (() -> URL?)? = nil)`

- [ ] **Step 1: Write failing tests in `Tests/VRemindKitTests/StreamMonitorServiceTests.swift` and `Tests/VRemindKitTests/PreferencesViewTests.swift`**

In `StreamMonitorServiceTests.swift`:
- `testClearStatusesPurgesCachedChannelStatuses()`:
  - Run a refresh pass populating `service.statuses` for `@old`, remove `@old` from `channelStore`, call `service.clearStatuses()`, verify `service.statuses.isEmpty` and `service.isAnyLive == false`.
  - Also verify `performRefreshPass()` does not retain statuses for channels removed mid-refresh.

In `PreferencesViewTests.swift`:
- `testExportBackupWritesValidJSONFile()`:
  - Populate `prefs.settings.notifyOnUpcoming = true` and `store.addChannel(handle: "@test_vtuber")`, write via `viewModel.exportBackup(chooseSaveURL: { tempFileURL })`, decode resulting file with `BackupPayload.decodeAndValidate(from:)` and verify channel & preference fidelity.
- `testRestoreBackupOverwritesStoresSanitizesAndTriggersCallback()`:
  - Prepare backup JSON with `hasCompletedOnboarding: false`, `notifyOnUpcoming: true`, `reduceMotion: true`, and one Twitch channel (`twitch:ironmouse`, `lastNotifiedVideoId: "old123"`).
  - Current `store` has `@bukancaitlyn` + `@other`.
  - Call `viewModel.restoreBackup(chooseOpenURL: { tempBackupURL })` -> verify `isShowingRestoreConfirmation == true`, `pendingRestorePayload != nil`, stores NOT modified yet.
  - Call `viewModel.confirmRestore()` -> verify `isShowingRestoreConfirmation == false`, `pendingRestorePayload == nil`, `onRestore` callback fired, `store.channels` now equals `[twitch:ironmouse]` ONLY with `lastNotifiedVideoId == nil`, `prefs.settings.hasCompletedOnboarding == true`, `prefs.settings.reduceMotion == true`, and `backupStatusText != nil`.
- `testRestoreInvalidFileSurfacesErrorWithoutMutatingStores()`:
  - Call `viewModel.prepareRestore(from: Data("not json".utf8))` -> verify `backupErrorMessage != nil`, `isShowingRestoreConfirmation == false`, existing `store.channels` and `prefs.settings` untouched.
- `testCancelRestoreClearsPendingPayloadWithoutMutatingStores()`:
  - Call `prepareRestore(from: validData)` then `cancelRestore()` -> `isShowingRestoreConfirmation == false`, `pendingRestorePayload == nil`, stores untouched.

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash scripts/test.sh --filter "StreamMonitorServiceTests|PreferencesViewTests"`
Expected: FAIL (`value of type 'StreamMonitorService' has no member 'clearStatuses'`, `PreferencesViewModel` missing backup methods).

- [ ] **Step 3: Implement `StreamMonitorService.clearStatuses()` and `PreferencesViewModel` backup/restore methods**

Implementation guidance:
- In `Sources/VRemindKit/Services/StreamMonitorService.swift`:
  - Add `private var statusEpoch: UInt64 = 0`.
  - Add `public func clearStatuses()`: increments `statusEpoch &+= 1` and sets `statuses = [:]`.
  - In `performRefreshPass()`: capture `let epoch = statusEpoch`; after `engine.refreshPass(...)` returns, check `guard epoch == statusEpoch else { return }`, filter `updatedStatuses` to active `Set(channelStore.channels.map { $0.id.lowercased() })` keys (matching `channel.id` or `channel.id.lowercased()`), assign `self.statuses = filteredStatuses`, and call `await exportWidgetSnapshot()`.
- In `Sources/VRemindKit/Views/Preferences/PreferencesView.swift`:
  - Import `UniformTypeIdentifiers`.
  - Update `PreferencesViewModel` `init` to accept `onRestore: (() -> Void)? = nil` (both primary and convenience inits keep backward source compatibility).
  - Implement `buildBackupData()`, `prepareRestore(from:)`, `confirmRestore()`, `cancelRestore()`.
  - Note on `confirmRestore()`: read `pendingRestorePayload`, run `sanitizedForRestore()`, apply `preferencesStore.settings = sanitized.settings`, write channels via `try? channelStore.saveChannels(sanitized.channels)`, call `_ = LaunchAtLoginHelper.setEnabled(sanitized.settings.launchAtLogin)`, clear pending state, set `backupStatusText = "Restored \(sanitized.channels.count) channel(s) from backup."`, and invoke `onRestore?()`.
  - Implement `exportBackup(chooseSaveURL:)`: resolves URL using `chooseSaveURL?() ?? presentSavePanel()`, writes `try buildBackupData().write(to: url, options: .atomic)`, sets `backupStatusText = "Backup exported."`, catches errors into `backupErrorMessage`.
  - Implement `restoreBackup(chooseOpenURL:)`: resolves URL using `chooseOpenURL?() ?? presentOpenPanel()`, reads `Data(contentsOf: url)`, calls `prepareRestore(from: data)`, catches read errors into `backupErrorMessage`.
  - Private `presentSavePanel()` sets `NSSavePanel()` with `allowedContentTypes = [.json]`, `nameFieldStringValue = BackupPayload.defaultBackupFilename()`, `canCreateDirectories = true`; `presentOpenPanel()` sets `NSOpenPanel()` with `allowedContentTypes = [.json]`, `allowsMultipleSelection = false`, `canChooseDirectories = false`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash scripts/test.sh --filter "StreamMonitorServiceTests|PreferencesViewTests"`
Expected: PASS (all existing and new tests in both suites pass).

- [ ] **Step 5: Commit**

```bash
git add Sources/VRemindKit/Services/StreamMonitorService.swift Sources/VRemindKit/Views/Preferences/PreferencesView.swift Tests/VRemindKitTests/StreamMonitorServiceTests.swift Tests/VRemindKitTests/PreferencesViewTests.swift
git commit -m "feat(backup): add StreamMonitorService status reset and PreferencesViewModel backup/restore"
```

---

### Task 5: Preferences Data & Backup UI, `AppDelegate` Wiring & Full Build Verification

**Files:**
- Modify: `Sources/VRemindKit/Views/Preferences/PreferencesView.swift:140-277`
- Modify: `Sources/VRemind/PreferencesWindowController.swift:9-80`
- Modify: `Sources/VRemind/AppDelegate.swift:104-125`
- Test: `Tests/VRemindKitTests/PreferencesViewTests.swift`

**Interfaces:**
- Consumes: `PreferencesViewModel` backup/restore APIs from Task 4, `StreamMonitorService.clearStatuses()` from Task 4
- Produces:
  - `PreferencesView` `Data & Backup` section with Export/Restore buttons, confirmation alert, and error alert
  - `PreferencesWindowController.show(..., onRestore: (() -> Void)? = nil)` & `init(..., onRestore: (() -> Void)? = nil)`
  - `AppDelegate.handleRestore()` + updated `handleFactoryReset()`

- [ ] **Step 1: Write failing test in `Tests/VRemindKitTests/PreferencesViewTests.swift`**

Add view rendering test:
- `testPreferencesViewRendersWithPendingRestoreAndErrorState()`:
  - Instantiate `PreferencesViewModel`, set `backupStatusText = "Backup exported."`, `backupErrorMessage = "Invalid file"`, render `PreferencesView(viewModel:)` in `NSHostingController` (`fittingSize.width >= 0`), then set `isShowingRestoreConfirmation = true` with a valid `pendingRestorePayload` and verify rendering does not crash.

- [ ] **Step 2: Run test to verify baseline/failure**

Run: `bash scripts/test.sh --filter PreferencesViewTests`
Expected: PASS or FAIL depending on compilation — proceed immediately to UI & wiring implementation so the UI renders Data & Backup and alerts cleanly.

- [ ] **Step 3: Implement `PreferencesView` Data & Backup UI, `PreferencesWindowController` forwarding, and `AppDelegate` restore handling**

Implementation guidance:
- In `Sources/VRemindKit/Views/Preferences/PreferencesView.swift`:
  - Wrap `generalTab` contents in `ScrollView { VStack(alignment: .leading, spacing: 18) { ... }.padding(20) }` and update `TabView` `.frame(width: 480, height: 460)` so all four sections (Startup, Updates, Data & Backup, Danger Zone) fit comfortably without clipping.
  - Add **Data & Backup** `VStack(alignment: .leading, spacing: 8)` between `Updates` and `Danger Zone`:
    - Header: `Text("Data & Backup").font(.headline)`
    - Subtitle: `Text("Export your watchlist and preferences to a JSON file, or restore from a previous backup.").font(.caption).foregroundColor(.secondary)`
    - Buttons `HStack(spacing: 12)`:
      - `Button("Export Backup...") { viewModel.exportBackup() }.buttonStyle(.bordered)` — attach `.alert(isPresented: backupErrorBinding)` on this button (or a wrapper view) showing title `"Backup Failed"` and `viewModel.backupErrorMessage ?? ""` so alert bindings live on distinct views on macOS 12!
      - `Button("Restore Backup...") { viewModel.restoreBackup() }.buttonStyle(.bordered)` — attach `.alert(isPresented: $viewModel.isShowingRestoreConfirmation)` on the Data & Backup `VStack` showing title `"Restore Backup?"`, message `"This will replace your current watchlist (\(viewModel.channelStore.channels.count) channel(s)) and app preferences with the selected backup. This cannot be undone."`, `.destructive(Text("Restore")) { viewModel.confirmRestore() }`, and `.cancel { viewModel.cancelRestore() }`.
    - Optional status text: `if let backupStatus = viewModel.backupStatusText { Text(backupStatus).font(.caption).foregroundColor(.secondary) }`.
- In `Sources/VRemind/PreferencesWindowController.swift`:
  - Add `onRestore: (() -> Void)? = nil` to `show(...)` and `init(...)`, forwarding into `PreferencesViewModel`.
  - Update window `contentRect` height from `400` to `460`.
- In `Sources/VRemind/AppDelegate.swift`:
  - Pass `onRestore: { [weak self] in self?.handleRestore() }` to `PreferencesWindowController.show(...)`.
  - Add `private func handleRestore()`:
    ```swift
    private func handleRestore() {
        Task { [weak self] in
            guard let self else { return }
            self.monitorService.clearStatuses()
            await self.monitorService.exportWidgetSnapshot()
            await self.monitorService.refreshAll()
        }
    }
    ```
  - Update `handleFactoryReset()` to also call `self.monitorService.clearStatuses()` and `await self.monitorService.exportWidgetSnapshot()` right before `await self.monitorService.refreshAll()`.

- [ ] **Step 4: Run full test suite & universal release build**

Run: `bash scripts/test.sh`
Expected: PASS across all suites (including all new `MarkdownViewTests`, `BackupPayloadTests`, `StreamMonitorServiceTests`, `PreferencesViewTests`), 0 failures.

Run: `bash scripts/build-app.sh`
Expected: PASS producing codesigned `build/VRemind.app` and embedded `VRemindWidget.appex`.

- [ ] **Step 5: Commit**

```bash
git add Sources/VRemindKit/Views/Preferences/PreferencesView.swift Sources/VRemind/PreferencesWindowController.swift Sources/VRemind/AppDelegate.swift Tests/VRemindKitTests/PreferencesViewTests.swift
git commit -m "feat(preferences): add JSON backup/restore UI and AppDelegate monitor synchronization"
```
