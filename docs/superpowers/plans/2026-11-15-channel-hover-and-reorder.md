# Plan: Hover-Only Trash Icon & Intra-Section Channel Drag-to-Reorder (`feat/laptop-low-power`)

## Workspace & Isolation Rules
- Execute ALL file reads, writes, edits, builds, tests, and git commits inside the isolated worktree:
  `/Users/karyl/CaitDev/CaitlynSwift/.worktrees/feat-laptop-low-power` (branch `feat/laptop-low-power`).
- NEVER modify `/Users/karyl/CaitDev/CaitlynSwift` (main checkout) or `/Users/karyl/CaitDev/VRemindCore`.
- Follow `docs/AGENTS.md`: Command Line Tools only (`bash scripts/test.sh` and `bash scripts/build-app.sh`), zero 3rd-party dependencies, `macOS 12.0+` (`arm64` + `x86_64`), strict TDD, zero compiler warnings.

---

## Task 1: Pure `ChannelOrderPolicy` & `ChannelStore.reorderSection` (TDD)

**Files:**
- Create: `Sources/VRemindKit/Services/ChannelOrderPolicy.swift`
- Modify: `Sources/VRemindKit/Services/ChannelStore.swift`
- Create: `Tests/VRemindKitTests/ChannelOrderTests.swift`

**Steps:**
1. **Red Phase:** Create `Tests/VRemindKitTests/ChannelOrderTests.swift` covering `exceedsDragThreshold`, `calculateDragLayout`, `reorderSectionItems`, `reorderWatchlistSlots`, and `ChannelStore.reorderSection(orderedSectionIds:)`. Run `bash scripts/test.sh --filter ChannelOrderTests` to verify failure.
2. **Green Phase:**
   - Implement `Sources/VRemindKit/Services/ChannelOrderPolicy.swift` (`SectionKind`, `DragLayoutStep`, `ChannelOrderPolicy`).
   - Add `ChannelStore.reorderSection(orderedSectionIds:)` in `Sources/VRemindKit/Services/ChannelStore.swift`.
3. **Verify & Commit:** Run `bash scripts/test.sh --filter ChannelOrderTests` and commit (`feat: add ChannelOrderPolicy and slot-preserving ChannelStore reorder`).

---

## Task 2: `MenuBarStatusViewModel` Section Reordering & Same-Day Order Projection (TDD)

**Files:**
- Modify: `Sources/VRemindKit/Views/MenuBar/MenuBarStatusView.swift`
- Modify: `Tests/VRemindKitTests/ChannelOrderTests.swift`

**Steps:**
1. **Red Phase:** Add `testViewModelReorderSectionUpdatesStoreAndPersists` and `testSameDayCustomOrderProjectionOverridesSecretDemotionUntilNextDay` to `Tests/VRemindKitTests/ChannelOrderTests.swift`. Run `bash scripts/test.sh --filter ChannelOrderTests` and confirm failure.
2. **Green Phase:** Add `dailyOrderDayStart`, `dailyOrderedIds`, `clearCustomOrder()`, `reorderSection(_:fromIndex:toIndex:)`, day-rollover clearing in `sections`, and `removeChannel(id:)` cleanup to `MenuBarStatusViewModel`.
3. **Verify & Commit:** Run `bash scripts/test.sh --filter ChannelOrderTests` and commit (`feat: wire MenuBarStatusViewModel section reorder and same-day order projection`).

---

## Task 3: Hover-Only Trash Icon & Intra-Section Drag UI in `ChannelRowView` & `MenuBarStatusView` (TDD)

**Files:**
- Modify: `Sources/VRemindKit/Views/MenuBar/ChannelRowView.swift`
- Modify: `Sources/VRemindKit/Views/MenuBar/MenuBarStatusView.swift`
- Modify: `Tests/VRemindKitTests/MenuBarViewTests.swift`

**Steps:**
1. **Red Phase:** Add `testChannelRowHoverDeleteVisibilityAndDragSuppression()` to `Tests/VRemindKitTests/MenuBarViewTests.swift`. Run `bash scripts/test.sh --filter MenuBarViewTests` and confirm failure.
2. **Green Phase:** Update `ChannelRowView` (`isDraggingAnyRow`, `shouldSuppressTap`, `shouldShowDeleteButton`, hover highlight & red trash icon) and `MenuBarStatusView` (row height measurement, section-scoped `DragGesture`, `ActiveSectionDrag` offsets/zIndex/opacity, tap suppression, popover hide drag cancellation).
3. **Verify & Commit:** Run `bash scripts/test.sh` and `bash scripts/build-app.sh` and commit (`feat: add hover-only delete button and intra-section drag-to-reorder in popover`).

---

## Task 4: Final Verification & Branch Integration Menu
1. Run `bash scripts/test.sh && bash scripts/build-app.sh && git status --short`.
2. Present the `finishing-a-development-branch` 3-option menu and wait for user choice.
