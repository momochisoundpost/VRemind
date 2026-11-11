# Memory and CPU Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate background idle CPU burn (reducing from ~27% to 0.0%) and minimize private memory retention in VRemind.

**Architecture:** Remove the continuous CoreAnimation `.repeatForever` loop from `StatusBadge.swift`. Configure an ephemeral `URLSession` without memory caching in `StreamMonitorService.swift` and wrap HTML parsing in `autoreleasepool { ... }` so large HTML response buffers and temporary regex/JSON objects are released immediately.

**Tech Stack:** Swift 5.9+, macOS 12.0+ Monterey, SwiftUI, Foundation, AppKit.

**Spec:** `docs/superpowers/specs/2026-11-11-memory-cpu-optimization-design.md`

## Global Constraints

- macOS 12.0 Monterey deployment target (`x86_64` + `arm64` universal binary).
- Zero third-party dependencies (native Swift, SwiftUI, AppKit).
- Deterministic CLI test execution via `bash scripts/test.sh`.

## Review Focus

1. **`StatusBadge` rendering**: Ensure `StatusBadge(isLive: true)` and `StatusBadge(isLive: false)` render correctly without runtime crashes or visual regressions.
2. **Ephemeral session timeout and error handling**: Verify `StreamMonitorService.defaultFetcher` uses `URLSessionConfiguration.ephemeral` with `urlCache = nil` and handles timeouts/network errors cleanly.
3. **Autorelease safety**: Ensure `autoreleasepool` cleanly encapsulates parsing without escaping un-retained references.
4. **Test suite integrity**: Verify all 100 existing tests across 12 suites continue to pass with 0 regressions.
5. **Real-world verification**: Sample the compiled `VRemind.app` process to confirm CPU usage drops to < 0.5% when idle.

---

### Task 1: Eliminate StatusBadge Animation Loop and Enable Ephemeral Fetching

**Files:**
- Modify: `Sources/VRemindKit/Views/Components/StatusBadge.swift`
- Modify: `Sources/VRemindKit/Services/StreamMonitorService.swift`

**Interfaces:**
- Consumes: `StatusBadge(isLive: Bool)`, `StreamMonitorService.defaultFetcher`
- Produces: 0.0% idle CPU badge rendering and zero-cache ephemeral network fetching.

- [ ] **Step 1: Update `StatusBadge.swift` to remove `.repeatForever` animation**

Remove `@State private var isPulsing`, `.animation(...)`, `.onAppear`, and `.onChange`. Render a clean, static dot:
```swift
public struct StatusBadge: View {
    public let isLive: Bool

    public init(isLive: Bool) {
        self.isLive = isLive
    }

    public var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isLive ? Theme.live : Color.secondary.opacity(0.6))
                .frame(width: 8, height: 8)

            Text(isLive ? "LIVE NOW" : "OFFLINE")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(isLive ? Theme.live : .secondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(isLive ? Theme.live.opacity(0.14) : Color.secondary.opacity(0.12))
        )
        .overlay(
            Capsule()
                .strokeBorder(isLive ? Theme.live.opacity(0.35) : Color.secondary.opacity(0.25), lineWidth: 1)
        )
    }
}
```

- [ ] **Step 2: Update `StreamMonitorService.swift` with ephemeral session and autoreleasepool**

1. Define a shared ephemeral `URLSession`:
```swift
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()

    public nonisolated static let defaultFetcher: Fetcher = { url in
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        return try await session.data(for: request)
    }
```
2. In `performRefreshPass()`, wrap HTML string decoding and parsing in `autoreleasepool`:
```swift
    autoreleasepool {
        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            return (channel, .success((.unrecognized, nil, nil)))
        }
        let parsed = LivePageParser.parse(html: html)
        let extractedTitle = LivePageParser.extractChannelTitle(from: html)
        let extractedAvatar = LivePageParser.extractAvatarURL(from: html)
        return (channel, .success((parsed, extractedTitle, extractedAvatar)))
    }
```

- [ ] **Step 3: Run automated test suite**

Run: `bash scripts/test.sh`
Expected: 100 tests in 12 suites PASS with 0 failures.

- [ ] **Step 4: Commit**

```bash
git add Sources/VRemindKit/Views/Components/StatusBadge.swift Sources/VRemindKit/Services/StreamMonitorService.swift
git commit -m "perf: eliminate background 60fps animation and use ephemeral network session"
```

---

### Task 2: Release Build, Process Verification and Deployment

**Files:**
- Output: `build/VRemind.app`

**Interfaces:**
- Consumes: All updated targets.
- Produces: Running `VRemind.app` verified with 0.0% idle CPU.

- [ ] **Step 1: Build release application bundle**

Run: `bash scripts/build-app.sh`
Expected: Successfully builds universal `build/VRemind.app`.

- [ ] **Step 2: Relaunch application**

Run: `killall VRemind || true; sleep 1; open build/VRemind.app`
Expected: Launches updated process.

- [ ] **Step 3: Verify idle CPU usage via process sample**

Measure: Check `%CPU` of `VRemind` process after 5 seconds of idle time.
Expected: `%CPU` is < 0.5% (typically 0.0%).
