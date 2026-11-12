# GitHub Release Updater & Consent Flow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement automatic and manual GitHub release checking with user consent gating, preferences controls, update dialog with release notes, 24-hour background checking with macOS notifications, Easter egg, and version bump to 1.0.1.

**Architecture:** A zero-dependency pure Swift `UpdateService` querying GitHub's Releases API, comparing versions via `SemanticVersion`, persisting user consent states (`.undecided`, `.allowed`, `.neverAsk`) in `AppSettings`, presenting a native SwiftUI/AppKit update dialog with markdown notes for launch/preferences checks, delivering native notifications on periodic 24-hour checks, and linking directly to browser downloads to avoid Gatekeeper quarantine corruption.

**Tech Stack:** Swift 5.9+, macOS 12.0+ SDK, AppKit, SwiftUI, UserNotifications, Foundation (`URLSession`), Swift Testing framework.

**Spec:** `docs/superpowers/specs/2026-11-11-github-updater-design.md`

## Global Constraints

- macOS target version floor: 12.0 (Monterey).
- Zero third-party library dependencies (pure Swift / AppKit / SwiftUI / Foundation / UserNotifications).
- App version string is `"1.0.1"` (bumped from `"1.0.0"`).
- GitHub releases API endpoint: `https://api.github.com/repos/momochisoundpost/VRemind/releases/latest`.
- Police siren video URL for Easter egg: `https://www.youtube.com/watch?v=HKieGUH9pzg`.
- Test commands run via `bash scripts/test.sh` (or `bash scripts/test.sh --filter <SuiteName>`).
- App builds via `bash scripts/build-app.sh`.

## Review Focus

1. **GitHub API HTTP 403 / Rate Limiting**: Silent and background checks must return a clean failure result without throwing exceptions or showing error alerts to the user. (Tested in Task 3)
2. **Malformed or Non-Standard Release Tags**: Tags like `"draft-build"`, `"v"`, or empty strings must parse safely and default to `(0, 0, 0)` rather than crashing. (Tested in Task 1)
3. **Network Disconnected on Silent / Launch Check**: If offline, silent check completes with a failure result without interrupting the user. (Tested in Task 3)
4. **"Remind Me Later" vs. "Skip This Version"**: "Remind Me Later" does not set `ignoredUpdateTag`, so the user will be alerted again on next launch; "Skip This Version" sets `ignoredUpdateTag` to suppress alerts for that version. (Tested in Task 4)
5. **Easter Egg Activation**: When local version is newer than the remote release (e.g. running local `1.0.1` when remote tag is `v1.0.0`), manual check returns `.localVersionNewer(remoteVersion:)` and triggers the "Did you steal Caitlyn's computer?" alert. (Tested in Task 6)

---

### Task 1: SemanticVersion & AppConstants Version Bump

**Files:**
- Create: `Sources/VRemindKit/Utilities/SemanticVersion.swift`
- Modify: `Sources/VRemindKit/AppConstants.swift`
- Modify: `Resources/Info.plist`
- Test: `Tests/VRemindKitTests/SemanticVersionTests.swift`

**Interfaces:**
- Produces:
  - `SemanticVersion: Comparable, Equatable, Sendable` with `init(_ string: String)`, `major: Int`, `minor: Int`, `patch: Int`, `isNewerThan(_ other: SemanticVersion) -> Bool`.
  - `AppConstants.appVersion: String = "1.0.1"`.
  - `AppConstants.githubReleasesLatestURL: URL`.
  - `AppConstants.policeSirenURL: URL`.

- [ ] **Step 1: Write the failing test**

Create `Tests/VRemindKitTests/SemanticVersionTests.swift`:
```swift
import Foundation
import Testing
@testable import VRemindKit

@Suite("SemanticVersionTests")
struct SemanticVersionTests {
    @Test("Parses standard semver strings with and without v prefix")
    func testParsing() {
        let v1 = SemanticVersion("1.0.1")
        #expect(v1.major == 1 && v1.minor == 0 && v1.patch == 1)

        let v2 = SemanticVersion("v1.2.3")
        #expect(v2.major == 1 && v2.minor == 2 && v2.patch == 3)

        let fallback = SemanticVersion("invalid-tag")
        #expect(fallback.major == 0 && fallback.minor == 0 && fallback.patch == 0)
    }

    @Test("Comparison correctly orders newer, older, and equal versions")
    func testComparison() {
        let current = SemanticVersion("1.0.1")
        let newer = SemanticVersion("v1.0.2")
        let older = SemanticVersion("v1.0.0")
        let equal = SemanticVersion("1.0.1")

        #expect(newer > current)
        #expect(older < current)
        #expect(current == equal)
    }

    @Test("AppConstants holds version 1.0.1 and required URLs")
    func testAppConstants() {
        #expect(AppConstants.appVersion == "1.0.1")
        #expect(AppConstants.policeSirenURL.absoluteString == "https://www.youtube.com/watch?v=HKieGUH9pzg")
        #expect(AppConstants.githubReleasesLatestURL.absoluteString == "https://api.github.com/repos/momochisoundpost/VRemind/releases/latest")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/test.sh --filter SemanticVersionTests`
Expected: FAIL with "cannot find 'SemanticVersion' in scope" and missing `AppConstants` properties.

- [ ] **Step 3: Implement `SemanticVersion` and update `AppConstants` and `Info.plist`**

1. Create `Sources/VRemindKit/Utilities/SemanticVersion.swift`:
   - Strips leading `"v"`, splits by `"."`, parses first 3 components as integers, defaults missing to `0`.
   - Conforms to `Comparable` comparing `major`, then `minor`, then `patch`.
2. Update `Sources/VRemindKit/AppConstants.swift`:
   - Add `appVersion = "1.0.1"`.
   - Add `githubReleasesLatestURL = URL(string: "https://api.github.com/repos/momochisoundpost/VRemind/releases/latest")!`.
   - Add `policeSirenURL = URL(string: "https://www.youtube.com/watch?v=HKieGUH9pzg")!`.
3. Update `Resources/Info.plist`:
   - Set `CFBundleShortVersionString` to `"1.0.1"`.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash scripts/test.sh --filter SemanticVersionTests`
Expected: PASS (3 tests in SemanticVersionTests passed).

- [ ] **Step 5: Commit**

```bash
git add Sources/VRemindKit/Utilities/SemanticVersion.swift Sources/VRemindKit/AppConstants.swift Resources/Info.plist Tests/VRemindKitTests/SemanticVersionTests.swift
git commit -m "feat: add SemanticVersion utility and bump version to 1.0.1"
```

---

### Task 2: UpdateConsentState & AppSettings Persistence

**Files:**
- Modify: `Sources/VRemindKit/Models/AppSettings.swift`
- Modify: `Sources/VRemindKit/Services/PreferencesStore.swift`
- Modify: `Tests/VRemindKitTests/PreferencesStoreTests.swift`

**Interfaces:**
- Consumes: Task 1.
- Produces:
  - `UpdateConsentState: String, Codable, Sendable` with cases `.undecided`, `.allowed`, `.neverAsk`.
  - `AppSettings.updateConsent: UpdateConsentState` (default `.undecided`).
  - `AppSettings.lastUpdateCheckDate: Date?` (default `nil`).
  - `AppSettings.ignoredUpdateTag: String?` (default `nil`).

- [ ] **Step 1: Write the failing test**

Add to `Tests/VRemindKitTests/PreferencesStoreTests.swift`:
```swift
@Test("Update consent defaults to undecided and round-trips via PreferencesStore")
func testUpdateConsentSettingsPersistence() {
    let defaults = UserDefaults(suiteName: "test.preferences.updates.\(UUID().uuidString)")!
    let store = PreferencesStore(userDefaults: defaults)

    #expect(store.settings.updateConsent == .undecided)
    #expect(store.settings.lastUpdateCheckDate == nil)
    #expect(store.settings.ignoredUpdateTag == nil)

    store.settings.updateConsent = .allowed
    store.settings.ignoredUpdateTag = "v1.0.0"
    let now = Date()
    store.settings.lastUpdateCheckDate = now

    let reloadedStore = PreferencesStore(userDefaults: defaults)
    #expect(reloadedStore.settings.updateConsent == .allowed)
    #expect(reloadedStore.settings.ignoredUpdateTag == "v1.0.0")
    #expect(reloadedStore.settings.lastUpdateCheckDate != nil)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/test.sh --filter testUpdateConsentSettingsPersistence`
Expected: FAIL with "value of type 'AppSettings' has no member 'updateConsent'".

- [ ] **Step 3: Update `AppSettings.swift` and `PreferencesStore.swift`**

1. In `Sources/VRemindKit/Models/AppSettings.swift`:
   - Define `public enum UpdateConsentState: String, Codable, Sendable, CaseIterable { case undecided, allowed, neverAsk }`.
   - Add fields to `AppSettings`:
     - `public var updateConsent: UpdateConsentState = .undecided`
     - `public var lastUpdateCheckDate: Date? = nil`
     - `public var ignoredUpdateTag: String? = nil`
   - Update `init(...)` signature and default parameter values.
2. In `Sources/VRemindKit/Services/PreferencesStore.swift`:
   - Ensure backward compatibility when decoding older stored settings JSON where `updateConsent` is missing (provide default `.undecided` if nil).

- [ ] **Step 4: Run test to verify it passes**

Run: `bash scripts/test.sh --filter PreferencesStoreTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/VRemindKit/Models/AppSettings.swift Sources/VRemindKit/Services/PreferencesStore.swift Tests/VRemindKitTests/PreferencesStoreTests.swift
git commit -m "feat: add UpdateConsentState and update check settings to AppSettings"
```

---

### Task 3: GitHubRelease Model & UpdateService

**Files:**
- Create: `Sources/VRemindKit/Models/GitHubRelease.swift`
- Create: `Sources/VRemindKit/Services/UpdateService.swift`
- Test: `Tests/VRemindKitTests/UpdateServiceTests.swift`

**Interfaces:**
- Consumes: Task 1 (`SemanticVersion`, `AppConstants`), Task 2 (`AppSettings`, `UpdateConsentState`).
- Produces:
  - `GitHubRelease: Codable, Equatable, Sendable`:
    - `tagName: String`, `name: String?`, `body: String?`, `htmlURL: URL`, `publishedAt: Date?`, `assets: [GitHubReleaseAsset]`.
  - `GitHubReleaseAsset: Codable, Equatable, Sendable`:
    - `name: String`, `browserDownloadURL: URL`, `size: Int?`.
  - `UpdateCheckResult: Equatable, Sendable`:
    - `.updateAvailable(GitHubRelease)`
    - `.upToDate(latestVersion: String)`
    - `.localVersionNewer(remoteVersion: String)` (Easter egg condition)
    - `.skippedIgnored(version: String)`
    - `.skippedNotConsented`
    - `.failed(String)`
  - `@MainActor UpdateService: ObservableObject`:
    - `init(preferencesStore: PreferencesStore, session: URLSession = .shared, currentVersion: String = AppConstants.appVersion)`
    - `checkForUpdates(manual: Bool) async -> UpdateCheckResult`
    - `@Published var isChecking: Bool`
    - `@Published var lastResult: UpdateCheckResult?`

- [ ] **Step 1: Write the failing test**

Create `Tests/VRemindKitTests/UpdateServiceTests.swift`:
```swift
import Foundation
import Testing
@testable import VRemindKit

@Suite("UpdateServiceTests")
struct UpdateServiceTests {
    @Test("Decodes GitHubRelease JSON correctly")
    func testDecodeRelease() throws {
        let json = """
        {
          "tag_name": "v1.0.2",
          "name": "v1.0.2 — Performance Fixes",
          "body": "Fixed memory usage",
          "html_url": "https://github.com/momochisoundpost/VRemind/releases/tag/v1.0.2",
          "assets": [
            {
              "name": "VRemind-1.0.2.zip",
              "browser_download_url": "https://github.com/momochisoundpost/VRemind/releases/download/v1.0.2/VRemind-1.0.2.zip",
              "size": 10485760
            }
          ]
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let release = try decoder.decode(GitHubRelease.self, from: json)
        #expect(release.tagName == "v1.0.2")
        #expect(release.name == "v1.0.2 — Performance Fixes")
        #expect(release.assets.first?.name == "VRemind-1.0.2.zip")
    }

    @Test("checkForUpdates detects newer version when remote is greater")
    func testNewerVersionDetected() async {
        let prefs = PreferencesStore(userDefaults: UserDefaults(suiteName: "test.update.newer.\(UUID().uuidString)")!)
        prefs.settings.updateConsent = .allowed

        let service = UpdateService(
            preferencesStore: prefs,
            currentVersion: "1.0.1",
            fetchRelease: {
                GitHubRelease(
                    tagName: "v1.0.2",
                    name: "v1.0.2",
                    body: "Release notes",
                    htmlURL: URL(string: "https://github.com")!,
                    publishedAt: nil,
                    assets: []
                )
            }
        )

        let result = await service.checkForUpdates(manual: false)
        if case .updateAvailable(let rel) = result {
            #expect(rel.tagName == "v1.0.2")
        } else {
            Issue.record("Expected updateAvailable, got \(result)")
        }
    }

    @Test("checkForUpdates detects local version newer than remote (Easter egg)")
    func testLocalVersionNewerEasterEgg() async {
        let prefs = PreferencesStore(userDefaults: UserDefaults(suiteName: "test.update.easter.\(UUID().uuidString)")!)
        let service = UpdateService(
            preferencesStore: prefs,
            currentVersion: "1.0.1",
            fetchRelease: {
                GitHubRelease(
                    tagName: "v1.0.0",
                    name: "v1.0.0",
                    body: "Old release",
                    htmlURL: URL(string: "https://github.com")!,
                    publishedAt: nil,
                    assets: []
                )
            }
        )

        let result = await service.checkForUpdates(manual: true)
        #expect(result == .localVersionNewer(remoteVersion: "v1.0.0"))
    }

    @Test("checkForUpdates skips check when not consented and not manual")
    func testSilentCheckSkippedWhenNotConsented() async {
        let prefs = PreferencesStore(userDefaults: UserDefaults(suiteName: "test.update.skip.\(UUID().uuidString)")!)
        prefs.settings.updateConsent = .neverAsk

        let service = UpdateService(
            preferencesStore: prefs,
            currentVersion: "1.0.1",
            fetchRelease: { fatalError("Should not be called") }
        )

        let result = await service.checkForUpdates(manual: false)
        #expect(result == .skippedNotConsented)
    }

    @Test("checkForUpdates respects ignoredUpdateTag on automatic checks")
    func testIgnoredTagSkippedOnAutomaticCheck() async {
        let prefs = PreferencesStore(userDefaults: UserDefaults(suiteName: "test.update.ignored.\(UUID().uuidString)")!)
        prefs.settings.updateConsent = .allowed
        prefs.settings.ignoredUpdateTag = "v1.0.2"

        let service = UpdateService(
            preferencesStore: prefs,
            currentVersion: "1.0.1",
            fetchRelease: {
                GitHubRelease(
                    tagName: "v1.0.2",
                    name: "v1.0.2",
                    body: nil,
                    htmlURL: URL(string: "https://github.com")!,
                    publishedAt: nil,
                    assets: []
                )
            }
        )

        let result = await service.checkForUpdates(manual: false)
        #expect(result == .skippedIgnored(version: "v1.0.2"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/test.sh --filter UpdateServiceTests`
Expected: FAIL with "cannot find 'UpdateService' in scope".

- [ ] **Step 3: Implement `GitHubRelease.swift` and `UpdateService.swift`**

1. Create `Sources/VRemindKit/Models/GitHubRelease.swift`:
   - Define `GitHubRelease` and `GitHubReleaseAsset`.
   - Add custom `CodingKeys` or use `convertFromSnakeCase`.
2. Create `Sources/VRemindKit/Services/UpdateService.swift`:
   - Injectable fetch closure `fetchRelease: (() async throws -> GitHubRelease?)?` for testing.
   - When `fetchRelease == nil`, performs `URLSession.shared.data(from: AppConstants.githubReleasesLatestURL)` with a custom `User-Agent: VRemind-macOS/1.0.1`.
   - Evaluates version using `SemanticVersion`:
     - If `remote > local`:
       - If `!manual && release.tagName == preferencesStore.settings.ignoredUpdateTag`: return `.skippedIgnored(version: release.tagName)`.
       - Else: return `.updateAvailable(release)`.
     - If `local > remote`: return `.localVersionNewer(remoteVersion: release.tagName)`.
     - Else: return `.upToDate(latestVersion: release.tagName)`.
   - Handles network errors gracefully, returning `.failed(error.localizedDescription)`.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash scripts/test.sh --filter UpdateServiceTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/VRemindKit/Models/GitHubRelease.swift Sources/VRemindKit/Services/UpdateService.swift Tests/VRemindKitTests/UpdateServiceTests.swift
git commit -m "feat: implement GitHubRelease model and UpdateService with version comparison"
```

---

### Task 4: Update Available View & Dialog Controller

**Files:**
- Create: `Sources/VRemindKit/Views/Updates/UpdateAvailableView.swift`
- Create: `Sources/VRemind/UpdateAvailableWindowController.swift`
- Test: `Tests/VRemindKitTests/UpdateAvailableViewTests.swift`

**Interfaces:**
- Consumes: Task 1 (`AppConstants`), Task 2 (`PreferencesStore`), Task 3 (`GitHubRelease`).
- Produces:
  - `UpdateAvailableView: View` accepting `release: GitHubRelease`, `onDownload: () -> Void`, `onSkip: () -> Void`, `onLater: () -> Void`.
  - `@MainActor UpdateAvailableWindowController: NSWindowController`:
    - `static func show(release: GitHubRelease, preferencesStore: PreferencesStore)`

- [ ] **Step 1: Write the failing test**

Create `Tests/VRemindKitTests/UpdateAvailableViewTests.swift`:
```swift
import Foundation
import SwiftUI
import Testing
@testable import VRemindKit

@Suite("UpdateAvailableViewTests")
struct UpdateAvailableViewTests {
    @Test("UpdateAvailableView renders release notes and triggers actions")
    @MainActor
    func testViewActions() {
        var downloaded = false
        var skipped = false
        var later = false

        let release = GitHubRelease(
            tagName: "v1.0.2",
            name: "v1.0.2 — Bug Fixes",
            body: "### Changes\n- Fixed notifications",
            htmlURL: URL(string: "https://github.com/momochisoundpost/VRemind/releases/tag/v1.0.2")!,
            publishedAt: nil,
            assets: [
                GitHubReleaseAsset(
                    name: "VRemind-1.0.2.zip",
                    browserDownloadURL: URL(string: "https://github.com/momochisoundpost/VRemind/releases/download/v1.0.2/VRemind-1.0.2.zip")!,
                    size: 1024
                )
            ]
        )

        let view = UpdateAvailableView(
            release: release,
            currentVersion: "1.0.1",
            onDownload: { downloaded = true },
            onSkip: { skipped = true },
            onLater: { later = true }
        )

        #expect(view.release.tagName == "v1.0.2")
        view.onDownload()
        #expect(downloaded == true)
        view.onSkip()
        #expect(skipped == true)
        view.onLater()
        #expect(later == true)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/test.sh --filter UpdateAvailableViewTests`
Expected: FAIL with "cannot find 'UpdateAvailableView' in scope".

- [ ] **Step 3: Implement `UpdateAvailableView.swift` and `UpdateAvailableWindowController.swift`**

1. Create `Sources/VRemindKit/Views/Updates/UpdateAvailableView.swift`:
   - Header with `AppIconView(size: 48)`, title `"VRemind \(release.tagName) is available!"`, and version comparison subtitle `"Current version: \(currentVersion) • New version: \(release.tagName)"`.
   - Scrollable `ScrollView` displaying the markdown release notes with monospaced/styled body text.
   - Action buttons:
     - `"Download Update"` (prominent style, tinted with `Theme.accent`): calls `onDownload()`.
     - `"Skip This Version"` (`.bordered`): calls `onSkip()`.
     - `"Remind Me Later"` (`.borderless`): calls `onLater()`.
2. Create `Sources/VRemind/UpdateAvailableWindowController.swift`:
   - Singleton or window tracking to center and show window.
   - When download clicked: opens direct `.zip` asset URL if available or `release.htmlURL` via `LinkOpener.open(...)` and closes window.
   - When skip clicked: sets `preferencesStore.settings.ignoredUpdateTag = release.tagName` and closes window.
   - When later clicked: closes window without setting ignored tag.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash scripts/test.sh --filter UpdateAvailableViewTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/VRemindKit/Views/Updates/UpdateAvailableView.swift Sources/VRemind/UpdateAvailableWindowController.swift Tests/VRemindKitTests/UpdateAvailableViewTests.swift
git commit -m "feat: implement UpdateAvailableView and UpdateAvailableWindowController"
```

---

### Task 5: Onboarding View Updates & Launch Consent Prompt

**Files:**
- Modify: `Sources/VRemindKit/Views/Onboarding/OnboardingView.swift`
- Modify: `Sources/VRemind/OnboardingWindowController.swift`
- Modify: `Sources/VRemind/AppDelegate.swift`
- Modify: `Tests/VRemindKitTests/OnboardingViewTests.swift`

**Interfaces:**
- Consumes: Task 2 (`AppSettings`, `UpdateConsentState`), Task 3 (`UpdateService`), Task 4 (`UpdateAvailableWindowController`).
- Produces:
  - `OnboardingViewModel.enableUpdateChecks: Bool` (default: `true`).
  - `OnboardingViewModel.neverAskUpdatesAgain: Bool` (default: `false`).
  - Launch consent prompt logic in `AppDelegate`.

- [ ] **Step 1: Write the failing test**

Add to `Tests/VRemindKitTests/OnboardingViewTests.swift`:
```swift
@Test("Onboarding completion sets updateConsent to allowed when enabled")
@MainActor
func testOnboardingUpdateConsentEnabled() {
    let prefs = PreferencesStore(userDefaults: UserDefaults(suiteName: "test.onboarding.consent.on.\(UUID().uuidString)")!)
    let channels = ChannelStore(userDefaults: UserDefaults(suiteName: "test.onboarding.channels.on.\(UUID().uuidString)")!)
    let vm = OnboardingViewModel(channelStore: channels, preferencesStore: prefs)

    #expect(vm.enableUpdateChecks == true)
    #expect(vm.neverAskUpdatesAgain == false)
    _ = vm.completeOnboarding()

    #expect(prefs.settings.updateConsent == .allowed)
}

@Test("Onboarding completion sets updateConsent to neverAsk when disabled and neverAsk checked")
@MainActor
func testOnboardingUpdateConsentNeverAsk() {
    let prefs = PreferencesStore(userDefaults: UserDefaults(suiteName: "test.onboarding.consent.never.\(UUID().uuidString)")!)
    let channels = ChannelStore(userDefaults: UserDefaults(suiteName: "test.onboarding.channels.never.\(UUID().uuidString)")!)
    let vm = OnboardingViewModel(channelStore: channels, preferencesStore: prefs)

    vm.enableUpdateChecks = false
    vm.neverAskUpdatesAgain = true
    _ = vm.completeOnboarding()

    #expect(prefs.settings.updateConsent == .neverAsk)
}

@Test("Onboarding completion leaves updateConsent undecided when disabled but neverAsk unchecked")
@MainActor
func testOnboardingUpdateConsentUndecidedWhenUnchecked() {
    let prefs = PreferencesStore(userDefaults: UserDefaults(suiteName: "test.onboarding.consent.undecided.\(UUID().uuidString)")!)
    let channels = ChannelStore(userDefaults: UserDefaults(suiteName: "test.onboarding.channels.undecided.\(UUID().uuidString)")!)
    let vm = OnboardingViewModel(channelStore: channels, preferencesStore: prefs)

    vm.enableUpdateChecks = false
    vm.neverAskUpdatesAgain = false
    _ = vm.completeOnboarding()

    #expect(prefs.settings.updateConsent == .undecided)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/test.sh --filter OnboardingViewTests`
Expected: FAIL with "value of type 'OnboardingViewModel' has no member 'enableUpdateChecks'".

- [ ] **Step 3: Update `OnboardingView.swift`, `OnboardingWindowController.swift`, and `AppDelegate.swift`**

1. In `Sources/VRemindKit/Views/Onboarding/OnboardingView.swift`:
   - Add `@Published public var enableUpdateChecks: Bool = true`.
   - Add `@Published public var neverAskUpdatesAgain: Bool = false`.
   - In `completeOnboarding()`:
     - If `enableUpdateChecks`: `preferencesStore.settings.updateConsent = .allowed`.
     - Else if `neverAskUpdatesAgain`: `preferencesStore.settings.updateConsent = .neverAsk`.
     - Else: `preferencesStore.settings.updateConsent = .undecided`.
   - In `OnboardingView.body`:
     - Add an "Updates" section before the "Get Started" button:
       ```swift
       VStack(alignment: .leading, spacing: 6) {
           Text("Updates").font(.headline)
           Toggle("Check for updates automatically", isOn: $viewModel.enableUpdateChecks)
               .toggleStyle(.checkbox)
           if !viewModel.enableUpdateChecks {
               Toggle("Never ask again", isOn: $viewModel.neverAskUpdatesAgain)
                   .toggleStyle(.checkbox)
                   .font(.caption)
                   .foregroundColor(.secondary)
           }
       }
       ```
     - Adjust frame height from `380` to `440` so all content fits cleanly without clipping.
2. In `Sources/VRemind/AppDelegate.swift`:
   - Initialize `updateService = UpdateService(preferencesStore: preferencesStore)`.
   - In `showOnboardingIfNeeded()` / after onboarding completion:
     - Call `checkUpdateConsentAndLaunchCheck()`.
     - If `updateConsent == .undecided`: present `NSAlert` modal:
       - Message: `"Enable Automatic Update Checks?"`
       - Informative text: `"VRemind can check GitHub Releases to notify you when new features and improvements are available. No personal data is transmitted."`
       - Buttons: `"Enable"`, `"Not Now"`.
       - Accessory view: `NSButton(checkboxWithTitle: "Never ask again", target: nil, action: nil)`.
       - If "Enable": sets `.allowed`, runs `checkForUpdates(manual: false)`.
       - If "Not Now": if checkbox is checked, sets `.neverAsk`; else remains `.undecided`.
     - If `updateConsent == .allowed`: run `updateService.checkForUpdates(manual: false)`. If `.updateAvailable(let release)`, call `UpdateAvailableWindowController.show(release: release, preferencesStore: preferencesStore)`.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash scripts/test.sh --filter OnboardingViewTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/VRemindKit/Views/Onboarding/OnboardingView.swift Sources/VRemind/AppDelegate.swift Tests/VRemindKitTests/OnboardingViewTests.swift
git commit -m "feat: add update check consent to Onboarding and launch flow in AppDelegate"
```

---

### Task 6: Preferences UI Integration & Easter Egg Flow

**Files:**
- Modify: `Sources/VRemindKit/Views/Preferences/PreferencesView.swift`
- Modify: `Sources/VRemind/PreferencesWindowController.swift`
- Modify: `Tests/VRemindKitTests/PreferencesViewTests.swift`

**Interfaces:**
- Consumes: Task 1 (`AppConstants`), Task 2 (`PreferencesStore`), Task 3 (`UpdateService`), Task 4 (`UpdateAvailableWindowController`).
- Produces:
  - Updates card in Preferences General tab.
  - Manual "Check for Updates Now" action with live progress and status.
  - Easter egg alert ("Did you steal Caitlyn's computer?" -> Yes opens police siren video).

- [ ] **Step 1: Write the failing test**

Add to `Tests/VRemindKitTests/PreferencesViewTests.swift`:
```swift
@Test("PreferencesViewModel exposes update checking and toggles consent")
@MainActor
func testPreferencesViewModelUpdates() async {
    let defaults = UserDefaults(suiteName: "test.pref.updates.\(UUID().uuidString)")!
    let prefs = PreferencesStore(userDefaults: defaults)
    let channels = ChannelStore(userDefaults: defaults)
    let updateService = UpdateService(
        preferencesStore: prefs,
        currentVersion: "1.0.1",
        fetchRelease: {
            GitHubRelease(
                tagName: "v1.0.0",
                name: "v1.0.0",
                body: nil,
                htmlURL: URL(string: "https://github.com")!,
                publishedAt: nil,
                assets: []
            )
        }
    )

    let vm = PreferencesViewModel(
        preferencesStore: prefs,
        channelStore: channels,
        notificationService: nil,
        updateService: updateService
    )

    #expect(vm.isAutoUpdateEnabled == false)
    vm.setAutoUpdateEnabled(true)
    #expect(prefs.settings.updateConsent == .allowed)
    #expect(vm.isAutoUpdateEnabled == true)

    let result = await vm.checkForUpdatesManually()
    #expect(result == .localVersionNewer(remoteVersion: "v1.0.0"))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/test.sh --filter testPreferencesViewModelUpdates`
Expected: FAIL with "extra argument 'updateService' in call" or missing members.

- [ ] **Step 3: Update `PreferencesView.swift` and `PreferencesWindowController.swift`**

1. In `Sources/VRemindKit/Views/Preferences/PreferencesView.swift`:
   - Add `public let updateService: UpdateService?` to `PreferencesViewModel`.
   - Add `@Published public var updateStatusText: String? = nil`.
   - Add `@Published public var isShowingEasterEggAlert: Bool = false`.
   - Add `isAutoUpdateEnabled: Bool` (getter: `preferencesStore.settings.updateConsent == .allowed`, setter: sets `.allowed` when true, `.neverAsk` when false).
   - Add `checkForUpdatesManually() async -> UpdateCheckResult?`:
     - Calls `updateService.checkForUpdates(manual: true)`.
     - If `.localVersionNewer`: triggers `isShowingEasterEggAlert = true`.
     - Updates `updateStatusText`.
   - In `generalTab` view:
     - Add an "Updates" section with:
       - Version string: `"Current Version: \(AppConstants.appVersion)"`.
       - Toggle: `"Automatically check for updates"`.
       - Button: `"Check for Updates Now"`.
       - Progress spinner / status text.
     - Add `.alert(isPresented: $viewModel.isShowingEasterEggAlert)`:
       - Title: `Text("Did you steal Caitlyn's computer?")`
       - Message: `Text("Your version (\(AppConstants.appVersion)) is newer than what's available on GitHub.")`
       - Primary button: `.default(Text("Yes")) { LinkOpener.open(AppConstants.policeSirenURL) }`
       - Secondary button: `.cancel(Text("No"))`
   - In `aboutTab`:
     - Update version display from hardcoded `"Version 1.0"` to `"Version \(AppConstants.appVersion)"`.
2. In `Sources/VRemind/PreferencesWindowController.swift`:
   - Pass `updateService` into `PreferencesViewModel`.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash scripts/test.sh --filter PreferencesViewTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/VRemindKit/Views/Preferences/PreferencesView.swift Sources/VRemind/PreferencesWindowController.swift Tests/VRemindKitTests/PreferencesViewTests.swift
git commit -m "feat: add Updates section to Preferences with Easter egg alert handling"
```

---

### Task 7: Background Periodic Polling, Notification Routing, and End-to-End Build Verification

**Files:**
- Modify: `Sources/VRemindKit/Services/NotificationService.swift`
- Modify: `Sources/VRemind/AppDelegate.swift`
- Modify: `Tests/VRemindKitTests/NotificationServiceTests.swift`

**Interfaces:**
- Consumes: Tasks 1-6.
- Produces:
  - 24-hour periodic update check timer in `AppDelegate`.
  - Native macOS notification posted when background update found:
    - Identifier: `"VREMIND_UPDATE_AVAILABLE"`.
    - Clicking routes to `UpdateAvailableWindowController.show(...)`.
  - Universal binary build passing via `scripts/build-app.sh`.

- [ ] **Step 1: Write the failing test**

Add to `Tests/VRemindKitTests/NotificationServiceTests.swift`:
```swift
@Test("NotificationService posts update available notification payload")
func testUpdateNotificationPayload() {
    let service = NotificationService()
    let release = GitHubRelease(
        tagName: "v1.0.2",
        name: "v1.0.2 — Improvements",
        body: "Notes",
        htmlURL: URL(string: "https://github.com")!,
        publishedAt: nil,
        assets: []
    )

    let request = service.makeUpdateNotificationRequest(release: release)
    #expect(request.content.title == "VRemind Update Available")
    #expect(request.content.body.contains("1.0.2"))
    #expect(request.content.userInfo["tagName"] as? String == "v1.0.2")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/test.sh --filter testUpdateNotificationPayload`
Expected: FAIL with "value of type 'NotificationService' has no member 'makeUpdateNotificationRequest'".

- [ ] **Step 3: Implement background periodic check and notification handling**

1. In `Sources/VRemindKit/Services/NotificationService.swift`:
   - Add `makeUpdateNotificationRequest(release: GitHubRelease) -> UNNotificationRequest`.
   - Add notification category identifier `"VREMIND_UPDATE_AVAILABLE"`.
   - In `handleNotificationClick`: if userInfo contains `"isUpdateNotification"`, invoke update callback.
2. In `Sources/VRemind/AppDelegate.swift`:
   - Add `updateTimer: Timer?`.
   - Schedule periodic timer with 86,400 seconds (24 hours) interval when `updateConsent == .allowed`.
   - In periodic tick: call `updateService.checkForUpdates(manual: false)`.
   - If `.updateAvailable(let release)`:
     - Post notification via `notificationService`.
   - Wire notification delegate so clicking the notification presents `UpdateAvailableWindowController`.
3. In `AppDelegate.applicationWillTerminate`:
   - Invalidate `updateTimer`.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash scripts/test.sh`
Expected: ALL 14 test suites pass.

- [ ] **Step 5: Verify App Assembly and Binary Build**

Run: `bash scripts/build-app.sh`
Expected: Universal binary built successfully to `build/VRemind.app`.

- [ ] **Step 6: Commit**

```bash
git add Sources/VRemindKit/Services/NotificationService.swift Sources/VRemind/AppDelegate.swift Tests/VRemindKitTests/NotificationServiceTests.swift
git commit -m "feat: add 24-hour periodic update checking and notification routing"
```
