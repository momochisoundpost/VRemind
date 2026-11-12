# Changelog

## [1.1-beta] - 2026-11-12

### Release Notes
**WIDGETS YES WIDGETS**

### Highlights
- **Native macOS WidgetKit Extension:** Built 100% in pure Swift without Xcode IDE requirements (command-line tools only).
- **Three Widget Sizes:**
  - **Small (Hero Single Creator):** Focused status of your most active or upcoming streamer, with dynamic avatar backdrop and shadow-contrasted typography. Single click opens the live stream in your default browser.
  - **Medium (Watchlist Quick Grid):** Side-by-side stream and upcoming countdown display.
  - **Large (Dashboard & Carousel):** Comprehensive watchlist status at a glance.
- **Deep Linking Protocol (`vremind://`):** Allows instant, interactive browser and app triggers right from the desktop or Notification Center.
- **Reverse-Engineered App Extension Runtime:** Configured native Mach-O `_NSExtensionMain` entry point and LaunchServices/PlugInKit registration without requiring full Xcode.
