# GitHub Release Updater & Consent Flow Design

**Date:** 2026-11-11  
**Status:** In Review  
**Topic:** Automatic and manual update checking via GitHub Releases for VRemind, with consent-gated launch checks, preferences controls, and a release notes dialog.  
**Target Version:** 1.0.1  

---

## 1. Intent & Context

VRemind is published as an open-source macOS app on GitHub (`https://github.com/momochisoundpost/VRemind`). Releases are distributed as zipped application bundles (`VRemind-x.y.z.zip`) attached to GitHub Releases. Because VRemind is ad-hoc signed without an Apple Developer ID paid certificate or Sparkle appcast infrastructure, users currently have no built-in way of knowing when bug fixes or new features are released.

The goal is to implement a native, lightweight update-checking mechanism that respects user privacy and consent:
1. Always ask the user for permission to check for updates (during onboarding and on launch) until they explicitly say "Yes" or check "Never ask again" with "No".
2. Only check GitHub and display update notifications/dialogs if the user has consented (or explicitly clicks "Check for Updates" manually).
3. Present an update dialog displaying the release version, title, and formatted release notes fetched directly from the GitHub Releases API.
4. Provide a seamless hand-off to download the release asset or view the release page in the browser, avoiding macOS Gatekeeper corruption.
5. Bump the app version to `1.0.1`.

---

## 2. Goals, Non-Goals & Anti-Goals

### Goals
- **Privacy & Consent First**: Never make network requests to GitHub for updates without user consent, unless initiated manually in Preferences.
- **Persistent Consent States**:
  - `.undecided`: Ask on onboarding and on launch until decided.
  - `.allowed`: Automatically check GitHub on launch (and in background).
  - `.neverAsk`: Do not check automatically and never prompt on launch again.
- **GitHub API Integration**: Fetch latest release metadata from `https://api.github.com/repos/momochisoundpost/VRemind/releases/latest` using native `URLSession` and zero external dependencies.
- **Semantic Version Comparison**: Safely compare semantic versions (e.g., `1.0.1` vs `v1.0.2` or `1.1.0`) taking `v` prefix into account.
- **Release Notes Dialog**: Dedicated native macOS window / sheet presenting the release notes markdown, version tag, published date, and action buttons ("Download Update" and "Later").
- **Preferences Integration**: Add an Updates section in Preferences showing current version (`1.0.1`), automatic check toggle, last checked time, and an instant "Check for Updates Now" button.
- **Version Bump**: Update app version to `1.0.1` across `Info.plist`, UI copy, and internal constants.

### Non-Goals
- Third-party binary updater frameworks like Sparkle (avoids external C/Obj-C dependencies and complex custom EdDSA appcast hosting).
- Silent automatic in-place binary rewriting/replacing in `/Applications` (breaks ad-hoc signing, risks quarantine bricking, and fails in standard non-admin accounts).
- Full GitHub GraphQL or authenticated API (public releases API requires no auth token).

### Anti-Goals
- Never spam the user with repeating update prompts if they selected "Never ask again".
- Never show the update dialog unexpectedly if the user has not consented to automatic checks.
- Never crash or block app launch if the network is unavailable or GitHub API is rate-limited.

---

## 3. Approaches Considered

### Approach 1: Native Pure Swift `UpdateService` + Browser Handoff *(Chosen)*
- **Architecture**: A dedicated `UpdateService` querying `api.github.com/repos/momochisoundpost/VRemind/releases/latest`. State machine handles `.undecided`, `.allowed`, and `.neverAsk`. Dialog renders markdown release notes with a primary button opening the release `.zip` or GitHub page in the user's default browser.
- **Pros**: Zero third-party dependencies, completely native SwiftUI/AppKit, works reliably with ad-hoc signed open-source builds, respects Gatekeeper quarantine rules.
- **Cons**: User manually moves the updated `.app` into `/Applications` after downloading.
- **Why Chosen**: Best strategy for independent open-source apps without a paid Apple Developer ID account.

### Approach 2: In-App Self-Replacement / Auto-Installer
- **Architecture**: App downloads `.zip`, runs unpack scripts, attempts `xattr -cr`, and replaces `/Applications/VRemind.app`.
- **Pros**: One-click install.
- **Cons**: High failure rate without Apple Developer ID notarization. macOS AMFI frequently flags self-extracted apps as damaged, requiring terminal intervention.

### Approach 3: Sparkle Framework Integration
- **Architecture**: Sparkle 2 SPM dependency with appcast XML.
- **Pros**: Standard macOS update UI.
- **Cons**: Requires hosting an EdDSA signed XML feed for every GitHub release; GitHub Releases API does not generate appcasts automatically; adds external binary dependencies.

---

## 4. Detailed Specification

### 4.1 Data Models & Settings

#### `UpdateConsentState`
```swift
public enum UpdateConsentState: String, Codable, Sendable {
    case undecided
    case allowed
    case neverAsk
}
```

#### `AppSettings` Update
Add fields to `AppSettings`:
- `updateConsent: UpdateConsentState` (default: `.undecided`)
- `lastUpdateCheckDate: Date?` (default: `nil`)
- `ignoredUpdateTag: String?` (default: `nil`, optional to skip reminding about a dismissed version if needed)

#### `GitHubRelease`
```swift
public struct GitHubRelease: Codable, Equatable, Sendable {
    public let tagName: String
    public let name: String?
    public let body: String?
    public let htmlURL: URL
    public let publishedAt: Date?
    public let assets: [GitHubReleaseAsset]
}

public struct GitHubReleaseAsset: Codable, Equatable, Sendable {
    public let name: String
    public let browserDownloadURL: URL
    public let size: Int
}
```

#### Semantic Version Parsing
`SemanticVersion`:
- Parses strings like `"v1.0.0"`, `"1.0.1"`, `"v1.2.0-beta"` into `(major, minor, patch)`.
- Implements `Comparable`.
- `SemanticVersion.isNewer(remote: String, current: String) -> Bool`.

---

### 4.2 Consent Prompts & Lifecycle

#### User Consent State Machine
The user consent is modeled with three states:
1. `.undecided`: Has not made a permanent decision. The app will prompt for update consent on launch until resolved.
2. `.allowed`: User granted consent. Automatic checks occur on launch and periodically every 24 hours in the background.
3. `.neverAsk`: User explicitly declined and checked "Never ask again". Automatic checks are disabled and no consent prompts appear on launch.

#### Onboarding View (`OnboardingView`)
- Includes an "Automatic Updates" section:
  - Toggle: `"Check for updates automatically"` (default: `true`).
  - When enabled: Completing onboarding sets `updateConsent = .allowed`.
  - When disabled: A helper checkbox appears: `"Never ask again"` (default: `false`).
    - If "Never ask again" is checked: Completing onboarding sets `updateConsent = .neverAsk`.
    - If left unchecked: Completing onboarding leaves `updateConsent = .undecided` (app will prompt on subsequent launches).

#### Launch Consent Prompt (`AppDelegate`)
When the app launches:
1. If onboarding has not been completed, present `OnboardingWindowController`.
2. Once onboarding is complete:
   - If `updateConsent == .undecided`:
     Present a focused consent dialog:
     - **Title**: `"Enable Automatic Update Checks?"`
     - **Message**: `"VRemind can check GitHub Releases to notify you when new versions and improvements are available. No personal data is transmitted."`
     - **Checkbox**: `"Never ask again"` (default: unchecked).
     - **Buttons**:
       - `"Enable"` (default action) -> sets `updateConsent = .allowed`, performs immediate check.
       - `"Not Now"` -> If "Never ask again" is checked, sets `updateConsent = .neverAsk`. If unchecked, remains `.undecided` (will ask again on next launch).
   - If `updateConsent == .allowed`:
     Proceed to check for updates (silent mode).
   - If `updateConsent == .neverAsk`:
     Do nothing.

#### Periodic Background Checking & Notification Flow
Since macOS users often leave their machines running 24/7:
1. When `updateConsent == .allowed`, `UpdateService` schedules a periodic check every **24 hours** (86,400 seconds), aligned with system wake events.
2. If a new update is found during a **periodic background check**:
   - Rather than disrupting the user by popping up a floating window over fullscreen games or active apps, VRemind posts a **native macOS notification**:
     - **Title**: `"VRemind Update Available"`
     - **Body**: `"Version \(release.tagName) is available on GitHub. Click to view release notes and download."`
   - Clicking this notification opens the `UpdateAvailableWindowController` dialog with full release notes.
3. If an update is detected via a **launch check** or a **manual check in Preferences**:
   - Presents `UpdateAvailableWindowController` directly to the user.
4. If a release tag matches `ignoredUpdateTag`, automatic background checks and launch checks will skip notifying for that specific version (manual check in Preferences will still show it).

---

### 4.3 Update Dialog (`UpdateAvailableWindowController`)
When an update dialog is presented:
- Window size: `480 x 400`, titled `"Software Update Available"`.
- Displays:
  - App Icon (`AppIconView(size: 48)`)
  - Title: `"VRemind \(release.tagName) is available!"`
  - Subtitle: `"Current version: 1.0.1 • New version: \(release.tagName)"`
  - Release notes: Scrollable view rendering GitHub release markdown (`body`).
  - Actions:
    - **"Download Update"** (`.borderedProminent`): Opens the `.zip` direct download asset URL if present, or `release.htmlURL` in default browser via `LinkOpener.open(...)`.
    - **"Skip This Version"**: Saves `ignoredUpdateTag = release.tagName` so this specific version will not trigger automatic notifications again.
    - **"Remind Me Later"**: Closes dialog without setting `ignoredUpdateTag` (snoozes until the next 24h check or next app launch).


---

### 4.4 Preferences UI Integration
In `PreferencesView`:
- **Updates Section** (under General tab or dedicated section):
  - Toggle: `"Automatically check for updates"` (mapped to `updateConsent == .allowed` vs `neverAsk`).
  - Button: `"Check for Updates Now"` (manual check, always allowed regardless of auto-check consent).
  - Status display:
    - Idle: `"Current Version: 1.0.1 (Build 1)"`
    - Checking: `"Checking GitHub for updates..."` with spinner.
    - Up to date: `"VRemind 1.0.1 is currently up to date."` (with checkmark).
    - Update available: `"Version X.Y.Z is available."` with button to open update dialog.
    - Error: `"Unable to check for updates. Check your internet connection."`

---

### 4.5 Version Bump to 1.0.1
Files to update:
- `Resources/Info.plist`: `CFBundleShortVersionString` set to `"1.0.1"`.
- `AppConstants.swift`: Add `public static let appVersion = "1.0.1"`.
- `PreferencesView.swift`: Display dynamic version string from bundle or constant.
- Documentation / README version references where applicable.

---

## 5. What's Left to the Builder
- Exact markdown rendering styling for the release notes scrollview (e.g. AttributedString with markdown or SwiftUI Text formatting).
- Layout padding and button alignment in `UpdateAvailableView` and `PreferencesView`.
- Unit test fixtures containing mock GitHub API JSON responses.

---

## 6. Automated Test Plan
1. **`SemanticVersionTests`**:
   - Comparison of `1.0.1` vs `1.0.0` (false), `1.0.1` vs `1.0.2` (true), `1.0.1` vs `v1.0.1` (false), malformed strings fallback.
2. **`UpdateServiceTests`**:
   - Decoding GitHub Releases API JSON payload.
   - Successful update detection returns `GitHubRelease`.
   - Equal or older version returns `.upToDate`.
   - Network failure or rate limit returns error without throwing fatal exceptions.
3. **`PreferencesStoreTests`**:
   - Persistence of `UpdateConsentState` (`.undecided`, `.allowed`, `.neverAsk`).
4. **`OnboardingViewModelTests`**:
   - Update consent toggle correctly updates preferences store.
5. **`PreferencesViewModelTests`**:
   - Toggling automatic updates updates `updateConsent`.
   - Manual check triggers update service and updates status.
