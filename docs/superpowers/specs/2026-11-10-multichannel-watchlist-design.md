# Multi-VTuber Watchlist & Channel Avatars Design Document

**Date**: 2026-11-10  
**Status**: Draft for User Approval  
**Target Platform**: macOS 12.0+ (Monterey and newer)  
**Implementation Medium**: Swift / SwiftUI hosted in AppKit (`NSStatusItem` + `NSPopover`)

---

## 1. Intent & The Why

### Background
The companion currently monitors Caitlyn Momochi (@bukancaitlyn) with an ambient live indicator in the macOS menu bar and a main desktop hub for stream archives and lore. Fans, however, often follow a small handful of favorite VTubers alongside Caitlyn and want quick reminders without cluttering their system with multiple separate apps. Additionally, replacing the placeholder sparkle circle with actual profile pictures gives each VTuber immediate visual recognition.

### Purpose
1. **Profile Pictures**: Display authentic channel avatars (starting with Caitlyn's official YouTube avatar) in the menu bar popover and across cards.
2. **Multi-VTuber Watchlist (Max 3 Slots)**: Allow users to follow up to 3 VTubers (Caitlyn pinned at slot #1, plus up to 2 customizable VTuber slots). The menu bar icon alerts the user if *any* watched VTuber is live, and the popover stacks their status cards for an instant overview.

---

## 2. Goals & Non-Goals

### Goals
1. **Stacked Multi-Card Popover**: The menu bar popover displays up to 3 channel cards stacked cleanly, each showing avatar, name, handle, live status badge, stream title (when live), uptime/offline timestamp, and a direct "Watch Stream ↗" button.
2. **Pinned Anchor + Custom Slots**: Slot 1 is always Caitlyn Momochi (pinned). Slots 2 and 3 can be added or removed by the user at will (capped at 3 total slots).
3. **No-API-Key Live Tracking**: Custom VTubers added by their `@handle` (e.g., `@kobo_kanaeru`) are tracked using the existing `LivePageParser` against `https://www.youtube.com/@handle/live` with zero API keys.
4. **Any-Live Menu Bar Alert**: The menu bar item turns into the animated/red broadcasting icon if *any* watched VTuber is live.
5. **Persistent User Watchlist**: Custom slots are saved in `UserDefaults` so they survive app restarts.
6. **Avatar Component with Fallbacks**: `ChannelAvatarView` renders avatars via `AsyncImage` with a circular clip, subtle border, and a graceful fallback (sparkle badge or colored initial) when offline or loading.

### Non-Goals
1. **Unbounded Channels (>3)**: Strictly capped at 3 slots to preserve low memory (<50 MB RAM), zero CPU overhead, and compact popover sizing.
2. **Multi-Platform Support**: YouTube only; not expanding to Twitch/Kick.
3. **Changing Main Hub Scope**: Cait-pedia, Stream Archives, and Clip Roulette remain Caitlyn's dedicated hub. The watchlist specifically extends the live reminder popover.

---

## 3. Architecture & Data Flow

### Data Models
```swift
public struct WatchedChannel: Codable, Identifiable, Equatable, Sendable {
    public let id: String          // Normalized handle (e.g., "@bukancaitlyn")
    public var name: String        // Display name (e.g., "Caitlyn Momochi")
    public var handle: String      // Channel handle
    public var avatarURL: URL?     // YouTube avatar URL
    public var isPinned: Bool      // True for Caitlyn (cannot be removed)
}
```

### Services
* **`WatchlistService` (`@MainActor ObservableObject`)**:
  * Pinned slot: Caitlyn Momochi (sourced from `ConfigSyncService.config`).
  * Custom slots: Loaded from / stored to `UserDefaults` key `"caitlynswift.watched_channels"`.
  * `channels: [WatchedChannel]`: Returns `[caitlyn] + customChannels` (max 3).
  * `statuses: [String: StreamStatus]`: Map of normalized handle -> `StreamStatus`.
  * `isAnyLive: Bool`: Computes whether any channel in the watchlist is currently live.
  * `refreshAll()`: Fetches live status for all active channels in parallel via `LiveStatusService.Fetcher`.
  * `addChannel(name: String, handle: String, avatarURL: URL?) -> Bool`: Validates handle, creates `WatchedChannel`, saves to `UserDefaults`.
  * `removeChannel(id: String)`: Removes custom channel if `!isPinned`.

### UI Components
1. **`ChannelAvatarView`**:
   * Uses SwiftUI `AsyncImage` with a fallback placeholder.
   * Circular clip, 36x36 frame, smooth border.
2. **`WatchlistChannelCard`**:
   * Compact card for one streamer in the stack.
   * If live: highlights with live accent border, displays live stream title and uptime.
   * "Watch Stream ↗" opens the stream in the user's default browser via `LinkOpener`.
   * For non-pinned channels: includes a subtle remove button (`xmark.circle`).
3. **`AddChannelCard`**:
   * Visible when `channels.count < 3`.
   * Clean dashed button: `"+ Add VTuber (X/3)"`.
   * Clicking presents an inline mini-form:
     * Handle input (`@handle`)
     * Name input (e.g. `Kobo Kanaeru`)
     * `Save` and `Cancel` buttons.
4. **`MenuBarStatusView` (Redesigned Stack)**:
   * Header: Caitlyn Momochi Companion & Watchlist.
   * Vertical stack of `WatchlistChannelCard` items + optional `AddChannelCard`.
   * Bottom bar: "Open Full App" and "Quit".
   * Auto-calculates `fittingSize` dynamically so the popover remains snug and compact.

---

## 4. Verification & Testing Strategy
* **Unit Tests**:
  * `WatchlistServiceTests`:
    * Pinned channel cannot be removed.
    * Adding beyond 3 slots is rejected.
    * Duplicate handles are prevented.
    * `isAnyLive` evaluates correctly when 0, 1, or multiple channels are live.
    * Persistence round-trip to `UserDefaults`.
  * `AvatarTests`:
    * Avatar URL parsing and fallback rendering.
  * `PopoverHeightTests`:
    * Fitting size calculates correctly with 1, 2, and 3 slots populated.
* **Compatibility**:
  * Strict macOS 12 Monterey compliance (SwiftUI `AsyncImage`, `NavigationView`, `ObservableObject`).
