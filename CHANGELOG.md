# Changelog

## [1.3] - 2026-11-13

### Release Notes
**The Better Together Update** — *yes, we're a version number late to the Minecraft Bedrock 1.2 joke.*

Missed opportunity on the version number aside, **1.3** is genuinely VRemind's **Better Together** release. In practice, that means two things: first, you don't just get live alerts for YouTube anymore — **Twitch** joins the watchlist right alongside it. Second, the entire backend got pulled apart so it isn't chained to macOS anymore. The Mac app stays 100% native SwiftUI and AppKit, while **`VRemindCore`** gives the business engine a life of its own anywhere Swift can run — your Windows PC, your Linux dev box, Googlebooks, or as a clean blueprint for KDE Plasma and GNOME ports.

### Highlights & What's New

#### 💜 Twitch Support (Still Zero API Keys)
- **YouTube + Twitch in One Watchlist:** Track creators on both YouTube and Twitch as independent watchlist entries — even if the same VTuber streams on both.
- **Platform Picker & Smart URL Detection:** Use the new platform dropdown on the left of the input bar to choose **YouTube** or **Twitch**, or just paste a `twitch.tv/...` or `youtube.com/@...` link and VRemind picks the right platform automatically.
- **Avatar Platform Badges:** Channel avatars in the menu bar popover and macOS desktop widgets now wear a subtle bottom-right platform badge (red for YouTube, purple for Twitch) so you can tell where someone is live at a glance.
- **Zero API Keys Required:** Checks Twitch live status, stream titles, start times, and avatars out of the box with no Twitch developer account or OAuth keys.

#### 🧱 VRemindCore & The Backend Overhaul
- **Decoupled Core (`VRemindCore`) + Mac Bridge (`VRemindKit`):** Extracted all domain models, stream providers, polling/deduplication logic, celebration detection, and persistence contracts into `VRemindCore` using only `Foundation` (and `FoundationNetworking` on non-Apple platforms) — zero `AppKit`, `SwiftUI`, `Combine`, `UserNotifications`, or `WidgetKit` imports.
- **Built for More Platforms & Feeds:** Introduces `StreamProvider` and `StreamProviderRegistry` (`YouTubeStreamProvider`, `TwitchStreamProvider`), making it straightforward to plug in more platforms and feeds (like RSS) down the road, and to build native frontends beyond macOS. `VRemindCore` now lives in its own standalone repository at [momochisoundpost/VRemindCore](https://github.com/momochisoundpost/VRemindCore) with full architecture, provider, and porting docs.

#### 🔄 Seamless v1.2 Migration & Widget Isolation
- **Automatic Watchlist & Widget Upgrade:** Existing v1.2 `UserDefaults` watchlists and `widget-cache.json` entries automatically migrate as YouTube channels without losing notification history, timestamps, or cached avatars.
- **Per-Platform Avatar Caching:** Widget avatars are now scoped by platform (`youtube_...`, `twitch_...`) so creators with matching handles across platforms never overwrite each other.

---

## [1.2] - 2026-11-12

### Release Notes
**生日SANG NYIT** — *wish your mom a happy birthday and buy something nice to her.*

I forgot my old boss' birthday, so for that moron I implemented the party update. Also, we heard you like updates, so we updated the updater so you can read about updates while updating to the latest update.

### Highlights & What's New

#### 🎉 Celebration Mode (Multilingual Milestone Detection)
- **EN / ID / JA Keyword Detection:** VRemind now scans scraped YouTube stream titles for birthday, debut, re-debut, and anniversary milestones across:
  - **English:** `birthday`, `bday`, `birthday stream`, `debut`, `re-debut`, `anniversary`
  - **Indonesian:** `ultah`, `ulang tahun`, `hari jadi`, `anniv`
  - **Japanese:** `生誕祭`, `誕生日`, `バースデー`, `初配信`, `お披露目`, `周年`, `記念配信`, `記念枠`
- **Rainbow Status Accents:** Celebrating **LIVE NOW** and **UPCOMING** badges, section headers, and elapsed/start-time labels shift from standard red and orange into an animated rainbow gradient.
- **Non-Metal Popover Confetti:** When a milestone stream is live or airing today, opening the menu bar popover rains party confetti across the window. Built with pure CPU-drawn SwiftUI `Canvas` and `TimelineView` so it runs smoothly on non-Metal GPUs and legacy Hackintoshes from **macOS 12 Monterey** upward, with zero idle CPU usage when the popover is closed.

#### ♿ Reduce Motion Preference
- Added a **Reduce Motion** toggle under **Preferences → General** that stops the flashing menu bar live icon, disables popover confetti rain, and tones down rainbow gradients to a gentle, slower shift.

#### ✨ Upgraded Software Updater (`MarkdownView`)
- **Yo Dawg, We Updated the Updater:** Replaced the raw `#` and `<img>` wall of text in the **Software Update Available** dialog with a native, zero-dependency macOS 12 Markdown renderer supporting headings, bullet lists, code blocks, inline formatting, and embedded GitHub Release screenshots.

---

## [1.1] - 2026-11-12

### Release Notes
**The Native Desktop & WidgetKit Release**

What started as a vibecoded menu bar app meant for B-roll footage in a Hackintosh desktop video has evolved into a full-fledged native macOS experience. With 1.1, VRemind breaks out of the menu bar and lands directly onto your desktop with reverse-engineered, zero-Xcode native WidgetKit desktop widgets.

### Highlights & What's New

#### 🎨 Native macOS Desktop Widgets (WidgetKit)
- **Small Hero Widget (`systemSmall`):**
  - **Edge-to-Edge Avatar Backdrop:** The creator's profile picture fills the entire widget edge-to-edge with a clean fill-crop and dark gradient scrim.
  - **Adaptive Desktop Contrast:** On macOS Sonoma (or newer), desktop widgets shift to an ambient monochrome or tinted state when application windows are focused. VRemind dynamically adapts via `@Environment(\.widgetRenderingMode)`—switching typography and status badges to solid high-contrast black so stream titles and live status remain glanceable at all times.
- **Medium Watchlist Widget (`systemMedium`):** Quick-grid status view with side-by-side stream titles and countdown timers.
- **Large Dashboard Widget (`systemLarge`):** Prominent featured live hero card alongside a full multi-channel watchlist overview.
- **One-Click Deep Linking (`vremind://open-stream`):** Tapping any widget instantly launches the live broadcast in your default browser.

#### 🖱️ Menu Bar App Refinements
- **Tactile Cursor Feedback:** Hovering over any VTuber channel row now presents the pointing hand cursor (`NSCursor.pointingHand`) for clear interactive feedback.
- **Long Handle Tooltips:** Handles that exceed compact row bounds now reveal their complete `@handle` string in a native macOS tooltip on hover.
- **macOS Golden Gate (macOS 27) Ready:** On macOS 27 (Golden Gate), the menu bar app seamlessly respects the user's system liquid glass preferences and vibrancy styling.

#### 🛠️ Stubborn Zero-Xcode Engineering
- Built 100% with pure Swift, SwiftUI, AppKit, and WidgetKit using **only Xcode Command Line Tools** (`/Library/Developer/CommandLineTools`).
- Reverse-engineered the Apple App Extension Mach-O entry point (`_NSExtensionMain`) and PlugInKit registration to bypass the 40+ GB Xcode IDE requirement.
- Universal Mach-O binary supporting both Apple Silicon (`arm64`) and Intel (`x86_64`), running seamlessly from macOS 12 Monterey up to macOS 27 Golden Gate.

---

## [1.1-beta] - 2026-11-12

### Release Notes
**WIDGETS YES WIDGETS**

### Highlights
- **Native macOS WidgetKit Extension:** Built 100% in pure Swift without Xcode IDE requirements (command-line tools only).
- **Three Widget Sizes:** Small, Medium, Large.
- **Deep Linking Protocol (`vremind://`)**
- **Reverse-Engineered App Extension Runtime**
