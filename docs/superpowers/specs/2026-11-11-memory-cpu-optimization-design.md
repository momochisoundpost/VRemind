# Memory and CPU Optimization Design

**Date:** 2026-11-11  
**Status:** In Review  
**Topic:** Optimize VRemind background idle CPU usage (from ~27% down to 0.0%) and private RAM footprint (from ~52MB down to ~25-30MB) for low-memory Macs (e.g. 4GB MacBook Air).

---

## 1. Intent & Context

Activity Monitor profiling of VRemind 1.0 revealed:
- **Idle CPU usage:** 22.8% – 27.6% continuously, even when the menu bar popover is closed and no streams are actively changing state.
- **Physical Memory:** ~197MB resident (104MB shared system frameworks + 52MB private dirty memory).

### Root Causes
1. **Continuous 60 FPS CoreAnimation loop in `StatusBadge`:**
   [`StatusBadge.swift:18-23`](file:///Users/karyl/CaitDev/CaitlynSwift/Sources/VRemindKit/Views/Components/StatusBadge.swift#L18-L23) uses `.animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: isPulsing)`. Because `NSPopover` keeps its `NSHostingController` resident in memory, CoreAnimation continuously renders at 60 FPS in the background, consuming 20-30% CPU.
2. **`URLSession.shared` memory caching on 1.35MB HTML payloads:**
   [`StreamMonitorService.defaultFetcher`](file:///Users/karyl/CaitDev/CaitlynSwift/Sources/VRemindKit/Services/StreamMonitorService.swift#L8-L16) uses `URLSession.shared` with default caching. Polling 6 channels downloads ~8MB of HTML, which lingers in `URLCache.shared` memory buffers.
3. **Autoreleased Foundation objects:**
   Parsing 1.35MB HTML files with JSON deserialization and regexes creates temporary Objective-C/Foundation objects that remain in thread autorelease pools between runloop iterations.

---

## 2. Goals & Non-Goals

### Goals
- Drop idle background CPU usage to **< 0.1%** (effectively 0.0%).
- Reduce private dirty memory footprint from ~52MB to **~25–30MB**.
- Ensure network buffers and large HTML response strings are immediately freed after parsing.
- Retain instant popover opening responsiveness with zero UX degradation.

### Non-Goals
- Altering the 3-minute poll interval (`AppConstants.livePollInterval = 180s`).
- Dropping SwiftUI in favor of pure AppKit views (unnecessary since AppKit/SwiftUI is native and already fast once continuous animations are removed).

---

## 3. Approaches Considered

### Approach 1: The Essential Diet *(Chosen)*
- Remove the `.repeatForever` CoreAnimation loop from `StatusBadge`, rendering a clean, high-contrast static live dot (with static glow/capsule border).
- Replace `URLSession.shared` in `StreamMonitorService.defaultFetcher` with a dedicated ephemeral `URLSession` (`urlCache = nil`, `.reloadIgnoringLocalCacheData`).
- Wrap channel HTML parsing in `autoreleasepool { ... }` so temporary strings, dictionaries, and regex match objects are reclaimed immediately.
- *Trade-off:* Clean, safe, zero UX latency; instantly fixes both the 27% CPU burn and memory cache retention.

### Approach 2: Aggressive On-Demand Popover Lifecycle
- Everything in Approach 1, plus destroy and recreate the `NSPopover.contentViewController` every time the menu bar icon is clicked.
- *Trade-off:* Saves an extra ~5MB of RAM, but adds a noticeable 50ms stutter when the user clicks the menu bar icon.

### Approach 3: Streaming Partial-Body HTML Parsing
- Everything in Approach 1, plus stream-read the HTTP socket and terminate the connection once `ytInitialPlayerResponse` is found in the first ~150KB.
- *Trade-off:* More fragile against YouTube DOM changes if scripts are relocated.

---

## 4. Technical Specification

### 4.1 `StatusBadge.swift`
- Remove `@State private var isPulsing` and `.repeatForever` animation modifier.
- Render the live dot statically with crisp styling:
  ```swift
  Circle()
      .fill(isLive ? Theme.live : Color.secondary.opacity(0.6))
      .frame(width: 8, height: 8)
  ```
- Retain the clean capsule outline and badge styling.

### 4.2 `StreamMonitorService.swift`
- In `defaultFetcher`:
  Configure an ephemeral session:
  ```swift
  private static let session: URLSession = {
      let config = URLSessionConfiguration.ephemeral
      config.urlCache = nil
      config.requestCachePolicy = .reloadIgnoringLocalCacheData
      config.timeoutIntervalForRequest = 15
      return URLSession(configuration: config)
  }()
  ```
  Use `session.data(for: request)`.
- In `performRefreshPass`:
  Wrap the parsing of each channel's HTML payload inside `autoreleasepool { ... }` so temporary Foundation allocations drain immediately.

### 4.3 Verification
- All 100 existing automated unit and view tests continue to pass.
- Measure CPU usage of the compiled app via `sample` / `ps` to verify idle CPU is < 0.5%.
- Measure private dirty memory footprint in Activity Monitor.
