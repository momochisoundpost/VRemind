# Caitlyn Momochi Mac Companion App (CaitlynSwift) Design Document

**Date**: 2026-11-09  
**Status**: Approved  
**Target Platform**: macOS 14.0+ (Sonoma / Sequoia)  
**Implementation Medium**: Swift 5.9+ / SwiftUI (Native App)

---

## 1. Intent & The Why

### Background
Caitlyn Momochi ([@bukancaitlyn](https://youtube.com/@bukancaitlyn) / [@Y2Karyl](https://x.com/@Y2Karyl)) is an Indonesian independent VTuber and content creator: a retired witch who pivoted to audio engineering, and then into VTubing. Caitlyn streams exclusively on YouTube, sharing gaming, chit-chat, and computing/tech experiments.

### Purpose
To build a high-performance, charming native Mac desktop companion for Caitlyn's community, inspired by the community-favorite fan portal [ohnyfans.com](https://ohnyfans.com). The companion gives fans an unobtrusive ambient indicator on their Mac for when Caitlyn goes live on YouTube, paired with a rich desktop hub for stream archives, an inside joke encyclopedia (*Cait-pedia*), and an iconic *Clip Roulette* spinner.

---

## 2. Goals, Non-Goals & Anti-Goals

### Goals
1. **Lightweight & Ambient**: Sits quietly in the macOS menu bar (`MenuBarExtra`), displaying real-time stream status with an animated live indicator and uptime counter.
2. **Cait-pedia Lore Hub**: Searchable, categorized dictionary of inside jokes, memes, lore milestones, and chat glossary.
3. **Stream Archives & Replay Shelf**: Curated replay shelf with YouTube video cards; clicking any video, stream, or clip instantly launches it in the user's default external browser (`NSWorkspace.shared.open`), preserving their YouTube login, chat, and subscriptions.
4. **Clip Roulette**: A fun button that spins and opens a random iconic stream clip or highlight in the default browser.
5. **Dynamic Updates without App Rebuilds**: Remote configuration via GitHub Raw JSON allows Caitlyn to add new lore entries, curated clips, and featured VODs anytime without requiring users to download a new app release.
6. **Robust Offline Fallback**: Ships with a bundled seed configuration (`caitlyn_hub.json`) so the app is immediately useful offline or if network access fails.

### Non-Goals
1. **Soundboard & Tech Shed**: Explicitly out of scope per user direction; keeping the app focused strictly on live status, lore wiki, VODs, and clip roulette.
2. **Multi-Platform Streaming**: Not supporting Twitch, Kick, or TikTok Live; Caitlyn streams exclusively on YouTube.
3. **In-App Live Chat Client or Embedded WebKit Player**: Not building an authenticated YouTube chat engine or heavy `WKWebView` player; all external links and videos open in the system default browser to preserve memory (<50 MB RAM), battery life, and user logins.
4. **Cross-Platform Support**: Strictly a native macOS application (no Windows, iOS, or web port in this scope).
5. **Third-Party Package Bloat**: Relying entirely on native Apple system frameworks (`SwiftUI`, `AppKit`, `Combine`/Modern Concurrency).

### Anti-Goals
1. **No Electron/Webview Wrappers**: Must be 100% native Swift/SwiftUI with minimal memory footprint (<50 MB RAM) and zero battery impact.
2. **No User API Key Requirement**: End-users must never be asked to configure Google Cloud Console developer tokens or YouTube Data API keys.
3. **No Invasive Notifications**: Avoid spammy desktop notification banners; notifications should be opt-in and restricted to stream go-live events.

---

## 3. Constraints

* **Operating System**: macOS 14.0 (Sonoma) or newer, enabling modern SwiftUI `MenuBarExtra`, `NavigationSplitView`, and `@Observable` macro state modeling.
* **Apple Silicon & Intel**: Must run natively on both Apple Silicon (arm64) and Intel (x86_64) Macs.
* **Network & Quotas**: Avoid direct reliance on metered YouTube Data API v3 client keys that easily exhaust daily quota limits across multiple app users.
* **Storage & Sandbox**: Must conform to macOS App Sandbox guidelines, storing user preferences in `UserDefaults` and cached remote configs in `Application Support`.

---

## 4. Approaches Considered

| Approach | Description | Pros | Cons | Decision |
| :--- | :--- | :--- | :--- | :--- |
| **1. Hybrid SwiftUI + Remote Config** *(Chosen)* | Pure SwiftUI app bundled with seed JSON. Checks YouTube channel live status directly and syncs remote JSON on GitHub Raw for updates. | Zero server cost, zero user API keys, instant updates via Git commit, offline fallback. | Depends on YouTube live endpoint redirect stability. | **Selected**: Best fit for an indie VTuber fan app. |
| **2. Fully Self-Contained Local App** | Everything (lore, VOD list) is hardcoded into the app bundle. | Simple to build, no external JSON endpoints. | Every new lore update or VOD requires building and distributing a new app release. | **Rejected**: Poor maintainability. |
| **3. Serverless Proxy Backend (Cloudflare Worker)** | Cloudflare Worker holds a YouTube API key and serves an API to the Mac app. | Official YouTube Data API v3 backing. | Requires managing cloud infrastructure, secrets, and API quota budgets. | **Rejected**: Unnecessary complexity for a community companion. |

---

## 5. Architecture & Component Design

### 5.1 Project Structure
```text
CaitlynSwift/
├── CaitlynSwiftApp.swift       # App entry point, MenuBarExtra & WindowGroup
├── Models/
│   ├── HubConfig.swift          # Root remote/local config model
│   ├── StreamStatus.swift       # Live/Offline status, streamId, title, uptime
│   ├── LoreEntry.swift          # Cait-pedia entries (category, definition, tags)
│   ├── ReplayVOD.swift          # Stream archives & full VODs (title, youtubeId, date)
│   └── CuratedClip.swift        # Iconic highlights for Clip Roulette (title, youtubeUrl)
├── Services/
│   ├── LiveStatusService.swift  # Scrapes/checks live embed metadata (verifies isLive vs scheduled)
│   └── ConfigSyncService.swift  # Syncs remote caitlyn_hub.json with local fallback
├── Views/
│   ├── MenuBar/
│   │   └── MenuBarStatusView.swift # Popover card view with live status & launch button
│   ├── Main/
│   │   ├── MainHubView.swift       # NavigationSplitView container
│   │   ├── ReplaysView.swift       # Stream archive grid & launcher
│   │   ├── CaitPediaView.swift     # Lore encyclopedia & search
│   │   └── ClipRouletteView.swift  # Random clip spinner tool
│   └── Components/
│       ├── StatusBadge.swift       # Animated "LIVE NOW" / "OFF-AIR" pill
│       ├── VODCard.swift           # Replay thumbnail card with browser launch
│       └── LoreCard.swift          # Expandable definition card
└── Resources/
    ├── caitlyn_hub.json         # Bundled initial seed config
    └── Assets.xcassets          # App icons, witch hat symbol, badges
```

### 5.2 Surface 1: Menu Bar Item (`MenuBarExtra`)
* **Status Icon**: Displays a custom icon (witch hat / broadcast dot). If Caitlyn is live, shows an accent color (purple/red) or pulse.
* **Popover View**:
  * **Header**: Caitlyn Momochi avatar, `@bukancaitlyn`, Live/Offline badge.
  * **Stream Card**: Current stream title, uptime counter (or time since last stream if offline, calculated from the latest VOD date), and "Watch Stream ↗" button opening the default browser via `NSWorkspace.shared.open`.
  * **Footer Action**: "Open Full App" button to toggle the main window, plus Quit.

### 5.3 Surface 2: Main App Window (`NavigationSplitView`)
* **Navigation Sidebar**:
  1. 🔴 **Live & Replays**: Featured recent VODs, stream categories, stats.
  2. 📖 **Cait-pedia**: Lore entries categorized by era (*Witch Era*, *Audio Engineer Era*, *VTuber Shenanigans*, *Chat Memes*) with instant search filtering.
  3. 🎰 **Clip Roulette**: A fun button that spins and opens a random iconic stream clip or highlight in the default browser.

### 5.4 Data Flow & Syncing
1. App launches $\rightarrow$ Loads bundled `caitlyn_hub.json` synchronously into memory so UI renders instantly.
2. Background task $\rightarrow$ Calls `ConfigSyncService.sync()` to fetch latest JSON from GitHub Raw URL. If updated, UI updates reactively via `@Observable`.
3. Background timer (every 3 minutes) $\rightarrow$ Calls `LiveStatusService.checkLive()`:
   * Inspects YouTube channel live status and verifies `isLive` is true (filtering out scheduled upcoming waiting rooms so false alerts never trigger).
   * Parses stream title and start timestamp; computes live uptime. When offline, computes "time since last stream" using the latest VOD date from `caitlyn_hub.json`.
