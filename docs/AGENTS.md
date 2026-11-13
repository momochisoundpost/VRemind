# Working with AI Agents

`VRemind` was built and architected from day one through human-agent collaboration. This guide documents the workflow, model stack, prompt practices, and macOS guardrails used to develop and maintain this repository with AI agents.

*(For changes to the portable engine itself, see [`VRemindCore/docs/AGENTS.md`](https://github.com/momochisoundpost/VRemindCore/blob/main/docs/AGENTS.md).)*

---

## 1. The Agent Stack & Philosophy

We use **Google Antigravity** paired with the **[Superpowers](https://github.com/obra/superpowers)** agentic workflow system (skills, subagents, and test-driven development gates):

```text
┌──────────────────────────────────────────────────────────────────────┐
│                        Human Architect / Lead                        │
│        (Vents raw ideas/screenshots, picks UX, approves specs)       │
└──────────────────┬───────────────────────────────┬───────────────────┘
                   │                               │
                   ▼                               ▼
┌─────────────────────────────────┐  ┌─────────────────────────────────┐
│     Stage 0: Vent & Ideate      │  │   Stages 1–2: Spec & Planning   │
│      (Gemini 3.8 Flash)         │  │        (Claude 5.5 Opus)        │
├─────────────────────────────────┤  ├─────────────────────────────────┤
│ • Brain-dump raw feature ideas  │  │ • Formalize design specs        │
│ • React to UI screenshots       │  │ • Architectural boundaries      │
│ • Explore "what I like/want"    │  │ • Edge case discovery           │
│ • Fast prototyping & sparring   │  │ • Atomic Superpowers plans      │
└──────────────────┬──────────────┘  └────────────────┬────────────────┘
                   │                                  │
                   └──────────────┬───────────────────┘
                                  ▼
               ┌──────────────────────────────────────┐
               │ Stages 3–4: SDD Execution & Review   │
               │   Gemini 4 Argon / Hydrogen (Deep)   │
               │   Gemini 3.8 Flash High (Focused)    │
               ├──────────────────────────────────────┤
               │ • Subagent Implementers & Reviewers  │
               │ • Strict TDD (Red -> Green -> Refac) │
               │ • CLT-only test + universal build    │
               └──────────────────────────────────────┘
```

### Model Role Assignment
- **Stage 0 — Venting & Brainstorming Starting Point (`Gemini 3.8 Flash`):**
  - **Strengths:** Fast, conversational iteration with zero friction when ideas aren't fully formed yet.
  - **Responsibilities:** Starting point for "venting it out" — dumping raw UX frustrations, attaching menu bar/widget screenshots, riffing on copy or visual direction ("whatever I like/want"), and converging on what the feature should feel like before writing a formal spec.
- **Stages 1–2 — Planning & Architecture (`Claude 5.5 Opus`):**
  - **Strengths:** High contextual rigor, structural reasoning, boundary discipline (`VRemindCore` vs. `VRemindKit`), and edge-case discovery.
  - **Responsibilities:** Distilling brainstormed intent into a design doc (`docs/superpowers/specs/*.md`) and breaking work into bite-sized, single-responsibility tasks in an implementation plan (`docs/superpowers/plans/*.md`).
- **Stages 3–4 — Implementation & Verification (`Gemini 4 Argon / Hydrogen` or `Gemini 3.8 Flash High`):**
  - **Strengths:** Fast tool execution, multi-subagent coordination (Implementer + Reviewer pairs under Superpowers Subagent-Driven Development), and thorough verification runs.
  - **Model Selection by Complexity:**
    - **Gemini 4 Argon / Hydrogen (Deep / High-Complexity):** Multi-target architectural shifts (`VRemindCore` <-> `VRemindKit` wiring), WidgetKit timeline/snapshot isolation, AppKit window/popover coordination, sleep/wake observers, and universal build fixes.
    - **Gemini 3.8 Flash (High Thinking / Focused):** Targeted SwiftUI view tweaks (e.g., dropdown styling, avatar badges), localization/copy updates, unit/view test coverage in `Tests/VRemindKitTests/`, and release docs/changelogs.

---

## 2. Superpowers Workflow Lifecycle

Features, UI overhauls, and bugfixes in `VRemind` follow this workflow:

```text
Vent / Spar (Gemini 3.8 Flash)
   ──► Spec (Claude 5.5 / Opus)
   ──► Plan (Claude 5.5 / Opus)
   ──► Subagent-Driven Dev (Gemini 4 / 3.8 Flash High)
   ──► Universal Build & Test Gate (`scripts/test.sh` + `scripts/build-app.sh`)
```

1. **Vent & Shape (`Gemini 3.8 Flash` + Superpowers Brainstorming):** Talk through rough ideas, attach screenshots, drop half-baked features if they bloat the app (e.g., deferring extra platforms until clean), and lock down UX direction.
2. **Design Spec (`docs/superpowers/specs/`):** Document goals, non-goals, data/UI flow, migration guarantees, and trade-offs, then review/approve before coding.
3. **Implementation Plan (`docs/superpowers/plans/`):** Break the spec into numbered tasks declaring files, Red failing tests, Green implementation, and verification commands.
4. **Subagent-Driven Development (SDD):** Dispatch implementer + reviewer subagents per task, ending with a whole-branch review and fresh full-suite verification.

---

## 3. Strict Rules for Coding Agents Working on `VRemind`

When prompting an agent to modify this repository, enforce these non-negotiable constraints:

### Rule 1: Zero Xcode IDE Dependency (Command Line Tools Only)
> **Constraint:** Everything must build, test, and package `VRemind.app` + `VRemindWidget.appex` using **only Xcode Command Line Tools** (`swift test` / `swift build`, zero `.xcodeproj` requirement).
> - Never introduce build steps that assume full `Xcode.app` (`xcodebuild`, asset-catalog compiler-only features unavailable in CLT, etc.).
> - Preserve the `_NSExtensionMain` linker entry point and manual app-bundle packaging in [`scripts/build-app.sh`](../scripts/build-app.sh).

### Rule 2: Zero Third-Party Dependencies
> **Constraint:** `VRemind` consumes only Apple SDK frameworks (`SwiftUI`, `AppKit`, `Combine`, `UserNotifications`, `ServiceManagement`, `WidgetKit`) and our first-party [`VRemindCore`](https://github.com/momochisoundpost/VRemindCore) Swift package. Do not add third-party SwiftPM packages.

### Rule 3: Keep Core Logic in `VRemindCore`, Mac Glue in `VRemindKit`
> - Stream providers, HTML/JSON parsers, `WatchedChannel` normalization, `StreamMonitorEngine`, and `CelebrationDetector` live upstream in [`VRemindCore`](https://github.com/momochisoundpost/VRemindCore).
> - Never duplicate core scraping/parsing rules inside `VRemindKit`. `VRemindKit` owns macOS persistence (`UserDefaults`), `NSWorkspace` sleep/wake hooks, `UNUserNotificationCenter`, WidgetKit snapshot caching, updater networking UI, and SwiftUI/AppKit views.

### Rule 4: macOS 12 Monterey & Non-Metal GPU Compatibility
> - Target platform remains `macOS 12.0+` (`arm64` + `x86_64` universal binary).
> - Gate newer APIs with `@available(macOS 13, *)` / `if #available(...)` and provide macOS 12 fallbacks (e.g., `SMAppService` vs. Monterey AppleScript login items; CPU-rasterized SwiftUI `Canvas` effects over Metal-only shaders).
> - Respect Accessibility `Reduce Motion` (`AppSettings.reduceMotion`) across animations and confetti.

### Rule 5: Strict Test-Driven Development
> - Write failing tests under `Tests/VRemindKitTests/` before modifying production code.
> - Mock network/system boundaries (`HTTPFetcher`, `NotificationCenterProtocol`, temp directories / isolated `UserDefaults` suites).
> - Always verify with both [`scripts/test.sh`](../scripts/test.sh) and [`scripts/build-app.sh`](../scripts/build-app.sh).

---

## 4. Prompt Templates for Working with Agents

### Prompt 1: Venting a Raw Idea or UI Fix (Gemini 3.8 Flash Starting Point)
```text
I want to change how <UI element / workflow> feels right now.
Here is what's bugging me / what I want instead: <raw vent + optional screenshot>.

Before touching code, let's brainstorm 2–3 concrete options for VRemind (macOS 12+, SwiftUI/AppKit, CLT-only build) with visual/layout trade-offs and pick the cleanest direction.
```

### Prompt 2: Mac Bridge / UI Feature Execution
```text
Implement Task <N> from docs/superpowers/plans/<plan-file>.md.
Read the referenced files in Sources/VRemindKit/ and Tests/VRemindKitTests/ first.

Requirements:
1. Follow strict TDD: add failing tests in Tests/VRemindKitTests/ first and confirm they fail.
2. Keep macOS 12 compatibility and respect Reduce Motion where applicable.
3. Run `bash scripts/test.sh` and `bash scripts/build-app.sh` and confirm zero warnings/failures.
```

### Prompt 3: Systematic Debugging (UI / WidgetKit / Bridge)
```text
<Describe unexpected UI, popover, notification, or widget behavior.>
Do not guess or apply speculative fixes.
1. Inspect the relevant VRemindKit / VRemind / VRemindWidget source files and trace the state flow end-to-end.
2. Write a failing test in Tests/VRemindKitTests/ reproducing the bug.
3. Apply the minimal root-cause fix.
4. Run `bash scripts/test.sh` and `bash scripts/build-app.sh` to verify.
```

---

## 5. Verification Checklist for Agent Handoffs

Before accepting changes generated by an AI agent:

- [ ] `bash scripts/test.sh` passes 100% of `VRemindKitTests` with zero warnings.
- [ ] `bash scripts/build-app.sh` succeeds cleanly (`build/VRemind.app` + embedded `VRemindWidget.appex`).
- [ ] Core platform logic wasn't duplicated out of `VRemindCore`.
- [ ] macOS 12+ deployment compatibility (`platforms: [.macOS(.v12)]`) is intact.
- [ ] `CHANGELOG.md` and `Resources/Info.plist` / `Resources/Widget-Info.plist` / `AppConstants` versions match on releases.
