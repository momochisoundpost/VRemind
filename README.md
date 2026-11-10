# Caitlyn Companion (`CaitlynSwift`)

A lightweight native macOS 12+ (Monterey and newer) desktop companion app for independent VTuber **Caitlyn Momochi** ([@bukancaitlyn](https://www.youtube.com/@bukancaitlyn) / [@Y2Karyl](https://x.com/Y2Karyl)).

## Features

- **Menu Bar Live Indicator & 3-Slot VTuber Watchlist (`NSStatusItem` + `NSPopover`)**: Sits quietly in the macOS menu bar (`sparkles` when offline, red `dot.radiowaves.left.and.right` when any watched VTuber is live on YouTube). Slot 1 is permanently pinned to Caitlyn Momochi with their channel profile picture, and you can add up to 2 additional VTubers by `@handle` (persisted in `UserDefaults`). Polls `/live` every 3 minutes (pausing while displays sleep) and shows live stream titles, uptime, or time since last stream.
- **Main Hub Window**:
  - **Live & Replays**: Paginated stream archive grid (8 VODs per page, 30 bundled VODs) sorted newest-first with 1-click launch in your default browser.
  - **Cait-pedia**: Searchable, category-filtered glossary of Caitlyn's lore, eras, and chat memes.
  - **Clip Roulette**: Spin to land on a random highlight clip without immediate repeats.
- **Hybrid Offline + Remote Sync**: Boots immediately from the bundled `caitlyn_hub.json` seed, then syncs the latest copy from GitHub Raw and caches it in `~/Library/Application Support/CaitlynSwift/caitlyn_hub.json`.

## Running Tests

Only Xcode Command Line Tools are required (no full Xcode installation needed):

```bash
bash scripts/test.sh
```

Pass extra arguments through to `swift test` if needed (for example, `bash scripts/test.sh --filter HubLogicTests`).

## Building `CaitlynSwift.app`

```bash
bash scripts/build-app.sh
```

This builds a release universal binary (falling back to the host architecture if cross-compilation isn't available), packages `build/CaitlynSwift.app` with `Resources/Info.plist` and the `CaitlynSwift_CaitlynKit.bundle` resource bundle, and ad-hoc signs the bundle.

To launch the built app:

```bash
open build/CaitlynSwift.app
```

## Updating Lore, Replays, and Clips (`caitlyn_hub.json`)

The bundled seed lives at:

```text
Sources/CaitlynKit/Resources/caitlyn_hub.json
```

On launch, the app also checks the remote config URL defined in `Sources/CaitlynKit/AppConstants.swift`:

```text
https://raw.githubusercontent.com/Y2Karyl/CaitlynSwift/main/caitlyn_hub.json
```

Publish an updated `caitlyn_hub.json` at the root of the `main` branch of `Y2Karyl/CaitlynSwift` (using ISO-8601 UTC dates like `"2026-11-05T12:00:00Z"`) to roll out new lore entries, VOD replays, or roulette clips without shipping a new app binary.
