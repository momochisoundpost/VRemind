# Changelog

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
