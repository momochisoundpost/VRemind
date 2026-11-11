# Live & Upcoming Channel Avatar Extraction Design

**Date:** 2026-11-11  
**Status:** In Review  
**Topic:** Fix missing channel avatar thumbnails for currently live and upcoming VTuber streams in VRemind.

---

## 1. Intent & Context

In VRemind 1.0, watched channels that are offline successfully resolve and display their profile avatars (e.g. `@bukancaitlyn`, `@lortlimbah`, `@jinggaawoo`). However, channels that are actively **LIVE NOW** (e.g. `@sayaayaaulia`) or **UPCOMING** (e.g. `@Renjiro_Junichi`) display the default fallback purple sparkle icon instead of the creator's avatar.

### Root Cause
1. When a channel is offline, YouTube returns their channel home page, where avatars are typically hosted on `https://yt3.googleusercontent.com/`.
2. When a channel is live or has an upcoming stream scheduled, `https://www.youtube.com/@handle/live` renders YouTube's live watch page player. On watch pages, YouTube hosts channel creator avatars on **`https://yt3.ggpht.com/`** (inside `videoSecondaryInfoRenderer` -> `videoOwnerRenderer.thumbnail`).
3. `LivePageParser.extractAvatarURL(from:)` only checked for `https://yt3.googleusercontent.com/` (and its backslash-escaped variant). Because `yt3.ggpht.com` was ignored, `extractAvatarURL` returned `nil` for any channel polled while live or upcoming, leaving `avatarURL` unpopulated in `ChannelStore`.

---

## 2. Goals & Non-Goals

### Goals
- Extract channel profile pictures on live and upcoming watch pages by recognizing YouTube's avatar image hostnames (`yt3.ggpht.com`, `yt4.ggpht.com`, `yt3.googleusercontent.com`, `yt4.googleusercontent.com`) and target the channel owner's avatar.
- Prioritize high-resolution thumbnails from `videoOwnerRenderer` (or channel header metadata) when available in the page payload.
- Ensure that once an avatar URL is resolved on any poll (live, upcoming, or offline), `ChannelStore` caches and preserves it across subsequent polls.
- Provide comprehensive automated tests for avatar extraction from both live watch pages (`yt3.ggpht.com`) and offline channel pages (`yt3.googleusercontent.com`).

### Non-Goals
- Third-party image hosting or downloading images to local disk files (SwiftUI's `AsyncImage` handles memory/URL caching natively).
- Adding YouTube Data API v3 or requiring user API keys.

---

## 3. Approaches Considered

### Approach 1: Plain Multi-Domain String Matching
Update `LivePageParser.extractAvatarURL` to search for `yt3.ggpht.com` in addition to `yt3.googleusercontent.com`.
- *Trade-off:* Fast to write, but string-scanning the entire HTML could theoretically grab a commenter or related video thumbnail if page order varies.

### Approach 2: Targeted Owner JSON Extraction + Multi-Domain Regex Fallback *(Chosen)*
1. Look specifically for `videoOwnerRenderer` / `videoSecondaryInfoRenderer` in the watch page's data to extract the channel owner's thumbnail array with 100% precision (preferring larger thumbnails like `s88` or `s176`).
2. Fall back to multi-domain scanning supporting both `yt3.ggpht.com` / `yt4.ggpht.com` and `yt3.googleusercontent.com` / `yt4.googleusercontent.com` (both unescaped and JSON `\/` escaped).
3. Ensure `ChannelStore` preserves the existing `avatarURL` if a subsequent poll temporarily fails to extract an avatar.
- *Trade-off:* Cleanest and most resilient; guarantees accurate channel avatar extraction without false positives.

### Approach 3: Two-Step Secondary Fetch to Channel Landing Page
If `/live` returns a watch page without an avatar, make a separate fetch to `https://www.youtube.com/@handle`.
- *Trade-off:* Introduces redundant network requests and slower polling when the live watch page already contains the creator's avatar.

---

## 4. Technical Design

### 4.1 `LivePageParser` Enhancements
In `Sources/VRemindKit/Services/LivePageParser.swift`:
1. **Targeted Owner Thumbnail Extraction**:
   - In `extractAvatarURL(from html: String) -> URL?`:
     - Search for `videoOwnerRenderer` or `owner` thumbnail blocks in `html`. If found, extract the URL from the thumbnail list (e.g. matching `https://yt[0-9]\.(ggpht|googleusercontent)\.com/[^"'\s<>\\]+`).
2. **Multi-Domain Support**:
   - Check prefixes:
     - `https://yt3.ggpht.com/`
     - `https://yt4.ggpht.com/`
     - `https://yt3.googleusercontent.com/`
     - `https://yt4.googleusercontent.com/`
     - Backslash-escaped variants: `https:\/\/yt3.ggpht.com\/`, `https:\/\/yt4.ggpht.com\/`, `https:\/\/yt3.googleusercontent.com\/`, `https:\/\/yt4.googleusercontent.com\/`
   - Normalize escaped `\/` to `/` and validate as a valid `URL`.

### 4.2 Automated Testing
In `Tests/VRemindKitTests/LivePageParserTests.swift`:
- `testExtractAvatarURLFromLiveWatchPageWithGgpht`: Verify avatar extraction from live stream HTML containing `yt3.ggpht.com` in `videoOwnerRenderer`.
- `testExtractAvatarURLFromEscapedGgpht`: Verify JSON-escaped `https:\/\/yt3.ggpht.com\/` extraction.
- `testExtractAvatarURLFromGoogleusercontent`: Verify backward compatibility with existing `yt3.googleusercontent.com` offline fixtures.
- `testStreamMonitorServiceExtractsAvatarOnLiveStream`: End-to-end integration test verifying that a channel added while live receives and stores its `avatarURL` on the initial poll.
