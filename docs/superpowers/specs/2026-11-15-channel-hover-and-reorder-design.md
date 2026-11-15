# Hover-Only Trash Icon & Intra-Section Channel Drag-to-Reorder Design

- **Date:** 2026-11-15
- **Branch:** `feat/laptop-low-power`
- **Scope:** Small Change (Hover-only delete action and intra-section vertical drag-to-reorder in `VRemindKit`, persisted to `UserDefaults` with zero modifications to `VRemindCore`)

---

## 1. Intent and Why
Bring macOS `VRemind` up to parity with `VRemind-win` so watchlist channel rows remain visually clean until hovered, and users can drag channels vertically within `LIVE NOW`, `UPCOMING`, and `OFFLINE` sections to prioritize favorite streamers without modifying `VRemindCore`.

---

## 2. Goals, Non-Goals, and Anti-Goals

### Goals
- **Hover-Only Delete & Row Highlight:** Show a subtle rounded highlight (`cornerRadius: 6`, `Color.primary.opacity(0.06)`) and reveal a red trash button (`Theme.live`) only when the pointer hovers over a row and no drag is active.
- **Intra-Section Drag-to-Reorder (`>= 5pt` threshold):** Pressing and dragging vertically (`>= 5pt`) within a section of 2+ channels elevates the dragged row (`zIndex: 10`, `opacity: 0.92`, clamped vertical offset) and shifts sibling rows up/down (`offset`) as their midpoints are crossed, while `< 5pt` clicks still open the stream URL.
- **Slot-Preserving Persistence & Same-Day Projection:** Dropping a row updates that section's index slots in `ChannelStore.channels` (`UserDefaults`) and records a same-calendar-day order projection in `MenuBarStatusViewModel` so custom ordering (including `@matsuijulianch` moved up) holds for the rest of today before `demoteSecret` resets on the next calendar day.

### Non-Goals
- Cross-section dragging (`OFFLINE` into `LIVE NOW`).
- Modifying `VRemindCore`.
- Changing `WidgetSnapshotStore` timestamp-based sorting (Option A: widget sorting stays as-is).

### Anti-Goals
- Breaking normal row clicks or trash button clicks.
- Causing the `.transient` `NSPopover` to dismiss mid-drag.

---

## 3. Constraints
- Zero changes to `VRemindCore`.
- Command Line Tools only (`bash scripts/test.sh`, `bash scripts/build-app.sh`).
- Zero third-party dependencies.
- `macOS 12.0+` (`arm64` + `x86_64`) compatibility.
- Respect `areAnimationsPaused` (Reduce Motion / Low Power Mode) and cancel any active drag if `!viewModel.isPopoverVisible`.

---

## 4. Approaches Considered
1. **Direct `DragGesture` + Pure `ChannelOrderPolicy` Offset Math *(Chosen)*:** 1:1 with `VRemind-win`, unit-testable pure layout/slot logic, preserves custom layout, and keeps `NSPopover` focus intact.
2. **SwiftUI `.onDrag` / `.onDrop`:** Rejected due to OS pasteboard previews and `.transient` `NSPopover` focus/click conflicts on macOS 12.
3. **Native SwiftUI `List` + `.onMove`:** Rejected due to unwanted `NSTableView` row chrome on macOS 12.

---

## 5. Decided Design
- `Sources/VRemindKit/Services/ChannelOrderPolicy.swift`: `SectionKind`, `DragLayoutStep`, and `ChannelOrderPolicy` (`dragActivationThreshold = 5.0`, `exceedsDragThreshold`, `calculateDragLayout`, `reorderSectionItems`, `applySectionOrder`, `applyCustomOrder`, `reorderWatchlistSlots`).
- `Sources/VRemindKit/Services/ChannelStore.swift`: `reorderSection(orderedSectionIds:)`.
- `Sources/VRemindKit/Views/MenuBar/MenuBarStatusView.swift`: `MenuBarStatusViewModel` same-day order projection and `reorderSection(_:fromIndex:toIndex:)`; `MenuBarStatusView` row height measurement and section-scoped `DragGesture`.
- `Sources/VRemindKit/Views/MenuBar/ChannelRowView.swift`: hover-only trash icon (`Theme.live`), hover background highlight, `isDraggingAnyRow` suppression, and `shouldSuppressTap` guard.
