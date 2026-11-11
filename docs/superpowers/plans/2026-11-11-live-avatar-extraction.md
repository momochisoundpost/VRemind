# Live & Upcoming Channel Avatar Extraction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable automatic channel avatar extraction and persistence for live and upcoming VTuber streams by supporting YouTube's `yt3.ggpht.com` watch page CDN and `videoOwnerRenderer` metadata.

**Architecture:** Update `LivePageParser.extractAvatarURL` to parse `videoOwnerRenderer` thumbnails when available and recognize all YouTube avatar CDN domains (`yt3.ggpht.com`, `yt4.ggpht.com`, `yt3.googleusercontent.com`, `yt4.googleusercontent.com`, unescaped and escaped `\/`). Verify that `ChannelStore` and `StreamMonitorService` persist the extracted avatar for live and upcoming channels.

**Tech Stack:** Swift 5.9+, macOS 12.0+ (Monterey), Swift Testing framework (`Testing`), Foundation, AppKit.

**Spec:** `docs/superpowers/specs/2026-11-11-live-avatar-extraction-design.md`

## Global Constraints

- macOS 12.0 Monterey deployment floor (`arm64` and `x86_64` universal binary).
- Zero third-party dependencies (100% native Swift, Foundation, SwiftUI, AppKit).
- Deterministic CLI test execution via `bash scripts/test.sh` without requiring an `.app` bundle context or external network access.
- Git commits in standard sandbox require `BypassSandbox: true` due to `.git/index.lock`.

## Review Focus

1. **`yt3.ggpht.com` in watch page `videoOwnerRenderer`**: Watch pages format avatar URLs inside `videoSecondaryInfoRenderer.owner.videoOwnerRenderer.thumbnail.thumbnails`. Ensure `extractAvatarURL` resolves this URL accurately.
2. **Escaped URLs in inline JavaScript (`https:\/\/yt3.ggpht.com\/...`)**: YouTube initial data embeds URLs with backslash-escaped forward slashes. Ensure these are unescaped cleanly into valid `URL` instances.
3. **Existing `yt3.googleusercontent.com` URLs on offline channel pages**: Ensure offline channel page avatar extraction continues to work with zero regressions.
4. **URL Query Parameters and sizing tokens**: Avatar URLs from YouTube often include sizing tokens such as `=s48-c-k-c0x00ffffff-no-rj` or `=s88-c-k-c0x00ffffff-no-rj`. Ensure characters like `=`, `-`, and `_` are preserved without truncation.
5. **ChannelStore metadata persistence**: When a channel is polled while live or upcoming, verify `ChannelStore.channels` is updated with `avatarURL != nil` and saved to `UserDefaults`.

---

### Task 1: Multi-Domain and Owner Thumbnail Parsing in `LivePageParser`

**Files:**
- Modify: `Sources/VRemindKit/Services/LivePageParser.swift`
- Test: `Tests/VRemindKitTests/LivePageParserTests.swift`

**Interfaces:**
- Consumes: `LivePageParser.extractAvatarURL(from: String) -> URL?`
- Produces: Enhanced `LivePageParser.extractAvatarURL(from: String) -> URL?` supporting `yt3.ggpht.com`, `yt4.ggpht.com`, `yt3.googleusercontent.com`, and `yt4.googleusercontent.com` (both plain and JSON-escaped).

- [ ] **Step 1: Write failing unit tests in `LivePageParserTests.swift`**

Add tests:
- `testExtractAvatarURLFromLiveWatchPageWithGgpht`: HTML containing `"videoOwnerRenderer":{"thumbnail":{"thumbnails":[{"url":"https://yt3.ggpht.com/avatar_live_token=s48-c-k-c0x00ffffff-no-rj"}]}}`.
- `testExtractAvatarURLFromEscapedGgpht`: HTML containing `"https:\/\/yt3.ggpht.com\/avatar_live_escaped=s88-c-k-c0x00ffffff-no-rj"`.
- `testExtractAvatarURLFromYt4Domain`: HTML containing `"https://yt4.ggpht.com/avatar_yt4"`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash scripts/test.sh --filter LivePageParserTests`
Expected: FAIL on the new `ggpht` tests (`extractAvatarURL` currently returns `nil`).

- [ ] **Step 3: Implement multi-domain and owner thumbnail extraction in `LivePageParser.swift`**

Update `LivePageParser.extractAvatarURL(from html: String) -> URL?`:
1. Search specifically for the owner avatar in `videoOwnerRenderer` or `owner` if present in `html`.
2. Support prefixes:
   - `https://yt3.ggpht.com/`
   - `https://yt4.ggpht.com/`
   - `https://yt3.googleusercontent.com/`
   - `https://yt4.googleusercontent.com/`
   - Escaped variants: `https:\/\/yt3.ggpht.com\/`, `https:\/\/yt4.ggpht.com\/`, `https:\/\/yt3.googleusercontent.com\/`, `https:\/\/yt4.googleusercontent.com\/`
3. Unescape `\/` to `/`, extract up to terminating characters (`"`, `'`, ` `, `<`, `>`, `\`), and validate with `URL(string:)`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash scripts/test.sh --filter LivePageParserTests`
Expected: PASS with 0 failures.

- [ ] **Step 5: Commit**

```bash
git add Sources/VRemindKit/Services/LivePageParser.swift Tests/VRemindKitTests/LivePageParserTests.swift
git commit -m "feat(parser): support yt3/yt4.ggpht.com avatar extraction on live watch pages"
```

---

### Task 2: Live/Upcoming Avatar End-to-End Persistence and Verification

**Files:**
- Modify: `Tests/VRemindKitTests/StreamMonitorServiceTests.swift`

**Interfaces:**
- Consumes: `StreamMonitorService`, `ChannelStore`, `LivePageParser`
- Produces: Verified end-to-end integration where live/upcoming polling populates and persists `channel.avatarURL`.

- [ ] **Step 1: Write integration unit test in `StreamMonitorServiceTests.swift`**

Add test:
- `testLiveStreamPollingPopulatesAndPersistsAvatarURL`: Add channel with `avatarURL: nil`. Poll with live stream HTML containing `https://yt3.ggpht.com/...`. Verify `channelStore.channels.first?.avatarURL` is updated to the `yt3.ggpht.com` URL.
- `testUpcomingStreamPollingPopulatesAndPersistsAvatarURL`: Add channel with `avatarURL: nil`. Poll with upcoming stream HTML containing `https://yt3.ggpht.com/...`. Verify `channelStore.channels.first?.avatarURL` is updated.

- [ ] **Step 2: Run test suite**

Run: `bash scripts/test.sh`
Expected: 97+ tests across 12 suites PASS with 0 failures.

- [ ] **Step 3: Build release app bundle**

Run: `bash scripts/build-app.sh`
Expected: Universal binary `build/VRemind.app` builds cleanly.

- [ ] **Step 4: Commit**

```bash
git add Tests/VRemindKitTests/StreamMonitorServiceTests.swift
git commit -m "test(monitor): verify avatar persistence for live and upcoming channels"
```
