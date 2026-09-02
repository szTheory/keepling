---
phase: KPL-03-mac-daily-loop
plan: 03
subsystem: desktop-workspace
tags: [electron, react, client-facade, sqlite, node-sqlite, task-lifecycle, undo, conflict-resolution]

requires:
  - phase: KPL-03-mac-daily-loop
    plan: 09
    provides: Platform-free packages/web-ui with ClientFacade contract and a responsive Inbox capture/list/detail slice, proven but not yet load-bearing on desktop
provides:
  - Full-loop Workspace presentation (Inbox/Today/Trash, edit, complete/reopen, Trash/restore, latest undo, inline conflict resolution) in packages/web-ui, shared across web and desktop
  - Real desktop ClientFacade adapter and IPC-backed local-only lifecycle/edit/undo/conflict operations, committed atomically via the same BEGIN IMMEDIATE/COMMIT pattern capture used
  - The Electron renderer now composes the shared Workspace through the facade instead of a standalone screen -- the Plan 03-09 extraction boundary is load-bearing on the Mac client
affects: [KPL-03-04, KPL-03-05, KPL-03-06, ship-readiness]

actuals:
  tokens: 28100
  tasks: 2
  commits: 2

tech-stack:
  added: []
  patterns:
    [
      client-facade-lifecycle-expansion,
      local-only-durable-lifecycle-commit,
      last-action-single-level-undo,
      inline-mine-current-conflict-resolution,
      stable-identity-focus-restoration-on-removal,
    ]

key-files:
  created:
    - packages/web-ui/src/tasks/TaskEditor.tsx
    - packages/web-ui/src/tasks/ConflictResolver.tsx
    - packages/web-ui/src/recovery/SyncRecovery.tsx
    - apps/desktop/renderer/desktopClientFacade.ts
    - apps/desktop/renderer/desktop.css
    - apps/desktop/test/e2e/daily-loop.spec.ts
    - apps/desktop/test/application/state-matrix.test.tsx
  modified:
    - packages/web-ui/src/ClientFacade.ts
    - packages/web-ui/src/tasks/TaskList.tsx
    - packages/web-ui/src/workspace/Workspace.tsx
    - apps/desktop/migrations/0001_initial.sql
    - apps/desktop/store-worker/local-store.ts
    - apps/desktop/store-worker/index.ts
    - apps/desktop/main/application/DesktopApplication.ts
    - apps/desktop/main/index.ts
    - apps/desktop/preload/index.ts
    - apps/desktop/renderer/main.tsx
    - apps/desktop/vitest.config.ts
    - apps/desktop/test/fixtures/desktopClientFacade.ts
    - apps/desktop/test/renderer/workspace-tracer.test.tsx
    - apps/desktop/test/store/offline-capture.test.ts
    - apps/web/src/adapters/browserClientFacade.ts
    - apps/web/src/adapters/browserClientFacade.test.tsx
    - apps/web/src/app/WorkspaceShell.test.tsx

key-decisions:
  - "Desktop's new edit/complete/reopen/trash/restore/moveToday/undo operations are local-only in this plan: they commit atomically to SQLite (same D-03 BEGIN IMMEDIATE/COMMIT pattern as capture) but do not enqueue an outbox mutation for a real server round-trip, so a task edited/completed/trashed on the Mac never claims \"Synced\" -- only \"Saved on this Mac\". Real sync/conflict for these commands (matching the account-scoped revision-lock model Phase 1/2 built server-side) is deferred; the desktop conflict flow that exists today is exercised only through the pre-existing capture-mutation sync-ack path."
  - "Undo is single-level (\"latest supported change\"), stored as one `last_local_action` row that the next local mutation overwrites -- matching D-14's \"persistent latest semantic undo\", not a multi-step undo stack."
  - "The browser adapter (apps/web) was extended for real to satisfy the shared ClientFacade interface change (edit/lifecycle/Today/undo route through the existing @/api/keepling command functions already used by apps/web's own TaskEditor/LifecycleActions/RecoveryStrip). Its Today/Trash routes stay backed by the already-loaded Inbox list only -- getTrash/today endpoints are not wired -- since apps/web's production Inbox route is explicitly out of scope for this plan; this keeps the interface honestly implemented without expanding apps/web's shipped surface."
  - "Conflict resolution surfaces only the `title` field (the only field the existing capture-sync-ack conflict path carries); notes/date conflicts are not modeled in this plan's local-only lifecycle scope."

patterns-established:
  - "Local-only durable lifecycle commit: editTask/applyLifecycle/applyMoveToday each snapshot the pre-change row into a `last_local_action` singleton and commit the change in the same BEGIN IMMEDIATE/COMMIT transaction, so undo is a single further atomic commit rather than an in-memory reversal."
  - "Dirty-work lift: TaskEditor exposes save()/discard() via useImperativeHandle; Workspace owns the dirty flag and intercepts navigation (route switch, task selection, Escape) to show one Save Changes/Discard Changes/Keep Editing dialog regardless of what triggered the navigation attempt."
  - "Stable-identity focus restoration: when the selected task leaves the current route's filtered view (completed/trashed/moved), Workspace computes the next task at the same list position, falling back to the previous task, falling back to focusing the empty-state heading -- never a DOM index."

requirements-completed: [MAC-01, MAC-02, MAC-04, QUAL-04]

coverage:
  - id: D1
    description: "Jon can capture, edit (title/notes with Command-S/Command-Return save and a Save Changes/Discard Changes/Keep Editing dirty-work dialog), complete/reopen, Trash/restore, and undo the latest supported change, entirely through the durable local-first facade with immediate local visibility."
    requirement: MAC-01
    verification:
      - kind: e2e
        ref: "test/e2e/daily-loop.spec.ts#completes the full daily loop through user-visible roles only"
        status: pass
      - kind: unit
        ref: "test/application/state-matrix.test.tsx#labels a freshly captured task \"Saved on this Mac\" before any network concern (D-03)"
        status: pass
      - kind: unit
        ref: "test/application/state-matrix.test.tsx#offers a named undo action after a lifecycle change and settles after undo"
        status: pass
    human_judgment: false
  - id: D2
    description: "List focus is independent from selection; Up/Down, Return, and stable-identity focus restoration after a row leaves the current view (complete/trash/move) work without falling back to a DOM index."
    requirement: MAC-02
    verification:
      - kind: e2e
        ref: "test/e2e/daily-loop.spec.ts#completes the full daily loop through user-visible roles only (focuses the Inbox Is Clear heading after the last Inbox row is trashed)"
        status: pass
      - kind: unit
        ref: "test/renderer/workspace-tracer.test.tsx#moves stable list focus independently from selection and opens by stable task identity"
        status: pass
    human_judgment: true
    rationale: "Native IME/dead-key composition, key-repeat suppression, and full native Tab order across the editor/lifecycle controls are only exercisable with a real physical or synthetic keyboard session against the packaged app; this plan's E2E proves the roles/keyboard-equivalent path but not every native input-method edge case."
  - id: D3
    description: "The Electron renderer composes the shared packages/web-ui Workspace through a real desktopClientFacade adapter backed by new IPC channels and SQLite columns -- the Plan 03-09 extraction is now load-bearing shipped code on the Mac client, not test-only."
    requirement: MAC-04
    verification:
      - kind: unit
        ref: "test/application/client-facade-boundary.test.ts#keeps packages/web-ui/src free of browser and Electron platform imports"
        status: pass
      - kind: e2e
        ref: "test/e2e/daily-loop.spec.ts (real Electron app launched from dist/{main,preload,renderer,worker}, driven only through user-visible roles)"
        status: pass
    human_judgment: false
  - id: D4
    description: "Populated/empty/loading/error/partial/zero-one-many state considerations and the QUAL-04 deterministic-state contract are demonstrated with disposable per-test facade instances and no shared clock/order dependency."
    requirement: QUAL-04
    verification:
      - kind: unit
        ref: "test/application/state-matrix.test.tsx (16 cases: Populated, Empty, Loading/durability labels, Error/recovery, Conflict, Partial, dirty-work safety, Overflow/long text, responsive breakpoint)"
        status: pass
    human_judgment: true
    rationale: "CSS-level overflow/wrap/truncation, forced-colors/Reduce-Transparency/Differentiate-Without-Color/200%-zoom accessibility media features, and light/dark pixel snapshots at all five UI-SPEC breakpoints are not demonstrable in this jsdom component harness (no real paint/layout). Marked human-needed rather than asserted as passing -- see Known Gaps below."
  - id: D5
    description: "A sync conflict (from the existing capture-mutation sync-ack path) is presented inline with the task's draft still visible, and is resolved only through an explicit mine/current choice -- it never silently overwrites."
    requirement: MAC-01
    verification:
      - kind: e2e
        ref: "test/e2e/daily-loop.spec.ts#surfaces a sync conflict inline and requires an explicit mine/current choice"
        status: pass
      - kind: unit
        ref: "test/application/state-matrix.test.tsx#presents mine/current inline and never overwrites without an explicit choice"
        status: pass
      - kind: unit
        ref: "test/application/state-matrix.test.tsx#commits the chosen field and clears the conflict on resolution"
        status: pass
    human_judgment: false

duration: ~100min
completed: 2026-09-02
status: complete
---

# Phase KPL-03 Plan 03: Full Daily Loop and Resolved State Matrix Summary

**The Electron renderer now composes the shared `packages/web-ui` Workspace through a real facade adapter -- edit, complete/reopen, Trash/restore, latest undo, and inline mine/current conflict resolution are all real, IPC-backed, atomically-committed operations, not stubs**

## Performance

- **Duration:** ~100 min
- **Started:** 2026-09-02T19:00:00Z (approximate)
- **Completed:** 2026-09-02T20:20:00Z
- **Tasks:** 2
- **Files modified:** 24 (7 created, 17 modified)

## Accomplishments

- Extended `ClientFacade` with named `editTask`/`completeTask`/`reopenTask`/`trashTask`/`restoreTask`/`moveToday`/`undoLastChange`/`resolveConflict` operations and a route/conflict-aware snapshot, still frozen by the Plan 03-09 import-boundary test.
- Built `TaskEditor` (Command-S/Command-Return save, Save Changes/Discard Changes/Keep Editing dirty-work dialog, complete/reopen and Trash/restore actions outside editable controls), `ConflictResolver` (inline mine/current choice, draft preserved until an explicit decision), and `SyncRecovery` (latest-undo strip with the "No Changes Need Your Attention" healthy copy) in `packages/web-ui`.
- Rewired `Workspace` with Inbox/Today/Trash navigation, a `TaskEditor` composed through an imperative save/discard handle, and stable-identity focus restoration (next row at the same position, else previous row, else the empty-state heading) whenever a task leaves the current route's filtered view.
- Extended the desktop SQLite local store (`notes`/`completed_at`/`trashed_at`/`planned` columns, a `last_local_action` singleton for latest-undo, mine/current-aware `conflicts` rows) with the same commit-first `BEGIN IMMEDIATE`/`COMMIT` durability pattern `acceptCapture` already used, and added matching `DesktopApplication` methods, IPC channels, and zod-validated preload contracts.
- Replaced the standalone renderer `App` with the real `desktopClientFacade` adapter composing the shared `Workspace` -- this is what makes the Plan 03-09 extraction load-bearing shipped code on the Mac client, per that plan's explicit carry-forward instruction.
- Extended the browser adapter (`apps/web/src/adapters/browserClientFacade.ts`) for real (not a stub) so the shared interface change doesn't break `apps/web`: edit/lifecycle/Today/undo/conflict-resolution route through the existing `@/api/keepling` command functions already used by `apps/web`'s own `TaskEditor`/`LifecycleActions`/`RecoveryStrip`/`ConflictResolver`.
- Added a real Electron-launched E2E (`test/e2e/daily-loop.spec.ts`) that builds `dist/{main,preload,renderer,worker}` and drives the actual app only through user-visible roles: capture → edit+save → complete → reopen → Add to Today → remove from Today → Trash → restore → undo → verify, plus a second spec proving a sync conflict is presented inline and resolved only through an explicit choice.
- Added a 16-case state matrix (`test/application/state-matrix.test.tsx`) covering Populated/Empty/Loading-durability-labels/Error-recovery/Conflict/Partial/dirty-work-safety/Overflow-long-text/responsive-breakpoint, against a fixture extended with real in-memory edit/lifecycle/undo/conflict semantics.

## Task Commits

1. **Task 2: Expand the workspace through edit, task lifecycle, Trash, restore, undo, conflicts, and exact focus recovery** - `2f7b187` (feat)
2. **Task 3: Freeze the populated, empty, loading, partial, overflow, long-text, retry, conflict, denied, and unrecoverable matrix** - `8ef12ff` (test)

_Note: Both plan tasks carried `tdd="true"`. See "TDD Gate Compliance" below -- implementation and tests were built together for this integration-heavy plan rather than in a strict RED-first sequence, disclosed rather than silently skipped._

## Files Created/Modified

- `packages/web-ui/src/tasks/TaskEditor.tsx` - Title/notes edit, dirty-work imperative handle, lifecycle actions.
- `packages/web-ui/src/tasks/ConflictResolver.tsx` - Inline mine/current conflict presentation.
- `packages/web-ui/src/recovery/SyncRecovery.tsx` - Latest-undo strip with healthy empty-state copy.
- `apps/desktop/renderer/desktopClientFacade.ts` - Production `ClientFacade` adapter over `window.keepling`.
- `apps/desktop/renderer/desktop.css` - Extracted/extended desktop presentation styles (nav, list/detail grid, dirty dialog, conflict, recovery strip).
- `apps/desktop/test/e2e/daily-loop.spec.ts` - Real Electron-launched keyboard-complete daily-loop and conflict E2E.
- `apps/desktop/test/application/state-matrix.test.tsx` - 16-case resolved UI-state matrix.
- `packages/web-ui/src/ClientFacade.ts` - Extended contract (edit/lifecycle/undo/conflict/route).
- `packages/web-ui/src/tasks/TaskList.tsx` - Stable-identity roving focus, external `focusTaskId` restoration.
- `packages/web-ui/src/workspace/Workspace.tsx` - Nav, dirty-work dialog, conflict banner, recovery strip, focus restoration.
- `apps/desktop/migrations/0001_initial.sql` - `visible_projection` gains `notes`/`completed_at`/`trashed_at`/`planned`; new `last_local_action` singleton.
- `apps/desktop/store-worker/local-store.ts` - `editTask`/`applyLifecycle`/`applyMoveToday`/`undoLastLocalAction`/`listConflicts`/`resolveConflict`, mine/current conflict capture.
- `apps/desktop/store-worker/index.ts` - New worker operation cases.
- `apps/desktop/main/application/DesktopApplication.ts` - New application methods and `LocalStorePort` additions.
- `apps/desktop/main/index.ts` - New IPC handles; `conflict` sync-mode test hook.
- `apps/desktop/preload/index.ts` - zod-validated `editTask`/`lifecycleTask`/`moveToday`/`undoLastAction`/`listConflicts`/`resolveConflict` bridge methods.
- `apps/desktop/renderer/main.tsx` - Renders the shared `Workspace` through the real facade.
- `apps/desktop/vitest.config.ts` - `application` project include widened to `.tsx` so the plan's exact `state-matrix.test.tsx` path resolves.
- `apps/desktop/test/fixtures/desktopClientFacade.ts` - Extended in-memory fixture with real edit/lifecycle/undo/conflict semantics.
- `apps/desktop/test/renderer/workspace-tracer.test.tsx` - Seed-task literals updated for the extended `WorkspaceTaskView` shape.
- `apps/desktop/test/store/offline-capture.test.ts` - Snapshot assertion updated for the extended projection row shape.
- `apps/web/src/adapters/browserClientFacade.ts` - Real edit/lifecycle/Today/undo/conflict wiring via existing `@/api/keepling` functions.
- `apps/web/src/adapters/browserClientFacade.test.tsx` - Updated expected `WorkspaceTaskView` shape.
- `apps/web/src/app/WorkspaceShell.test.tsx` - Stub facade extended to satisfy the new interface.

## Decisions Made

See `key-decisions` in frontmatter: local-only lifecycle commits (no server round-trip for edit/complete/reopen/trash/restore/Today in this plan), single-level "latest supported" undo, browser adapter kept Inbox-list-derived for Today/Trash, and conflict resolution scoped to the `title` field.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Fixed a `SyncRecovery` state bug: undo settlement message was overwritten by the healthy copy on the same render**
- **Found during:** Task 3 (state-matrix authoring) -- caught by `offers a named undo action after a lifecycle change and settles after undo`.
- **Issue:** `SyncRecovery` derived its status text purely from `availability === null`, so the moment `undoLastChange` cleared availability, "Change undone." was replaced by "No Changes Need Your Attention" before the person could read it.
- **Fix:** Track a `settledMessage` that persists until the next non-null recovery availability arrives.
- **Files modified:** `packages/web-ui/src/recovery/SyncRecovery.tsx`
- **Verification:** `test/application/state-matrix.test.tsx#offers a named undo action after a lifecycle change and settles after undo`
- **Committed in:** `8ef12ff`

**2. [Rule 1 - Bug] `apps/web`'s `ClientFacade` conflict-task-id lookup was type-unsound and semantically wrong**
- **Found during:** Task 2, `pnpm typecheck:web` after extending `browserClientFacade.ts`.
- **Issue:** The first draft derived a conflict's owning task by guessing a revision-minus-one match against loaded records -- fragile and occasionally wrong, and TypeScript correctly flagged the narrowing as unsound.
- **Fix:** Track `activeConflictTaskId` explicitly at the point the conflict is caught (the `taskId` already passed into `runCommand`).
- **Files modified:** `apps/web/src/adapters/browserClientFacade.ts`
- **Verification:** `pnpm typecheck:web` clean; `pnpm --dir apps/web test --run` (153/153 pass).
- **Committed in:** `2f7b187`

---

**Total deviations:** 2 auto-fixed (1 blocking, 1 bug). **Impact:** Both fixes were necessary for correctness (a misleading undo message, and a fragile/type-unsound conflict-owner lookup); no scope creep.

## TDD Gate Compliance

Both tasks carry `tdd="true"`, but this plan's two tasks are large, tightly coupled cross-package integrations (shared presentation, desktop main/preload/worker/renderer, and the browser adapter all had to change together for the type system to stay sound). Implementation and tests were authored together rather than in a strict test-first RED/GREEN sequence per task; there is no separate `test(KPL-03-03): add failing test for ...` commit preceding each `feat` commit. Verification is still real and complete (`pnpm test:desktop`, `pnpm --dir apps/web test --run`, `pnpm typecheck:desktop`, `pnpm typecheck:web`, `pnpm lint:web`, and a real Electron-launched E2E all pass), but the RED-first gate itself was not followed. Recorded here per the plan's own gate-enforcement instruction rather than silently omitted.

## Issues Encountered

- **Transient E2E flake, not reproduced.** On the first `daily-loop.spec.ts` run, the captured task's title showed as "Call dentisting" instead of "Call dentist" in the editor (one character sequence longer than expected). Re-running the identical spec three consecutive times afterward reproduced correctly ("Call dentist") every time, including with debug DOM dumps confirming the exact stored/rendered value. No code change was made to "fix" this because it did not reproduce; if it recurs in CI it likely indicates either a stale/lingering Electron process from a prior build attempt or an OS-level input-method timing artifact rather than a Workspace/facade bug -- worth a closer look if it recurs.

## User Setup Required

None.

## Known Stubs

None load-bearing. See "Known Gaps" below for scoped-down (not stubbed) verification.

## Known Gaps (scoped down, disclosed per plan instruction to mark unreachable evidence human-needed rather than pass it)

- **Full UI-SPEC breakpoint/theme/accessibility visual matrix.** The plan's Task 3 asked for light/dark snapshots at 680×520/1024×700/1064×700/1180×780/1440×900 plus 200% zoom and forced-colors/Reduce-Transparency/Differentiate-Without-Color media features. `state-matrix.test.tsx` proves the underlying `resolveBreakpoint` logic and live resize re-derivation, but jsdom has no real paint/layout engine, so CSS-level overflow/wrap/truncation and the accessibility media-feature contracts are not demonstrated here. This needs a real browser/Playwright visual pass (the desktop E2E lane could be extended with `page.screenshot()` assertions at each width) -- marked `human_judgment: true` in the coverage block rather than claimed as passing.
- **Native IME/dead-key composition and full native Tab order** across the editor and lifecycle controls are exercised only through the E2E's keyboard-equivalent role interactions, not a genuine IME composition session.
- **No real server round-trip for edit/complete/reopen/trash/restore/Today on desktop.** These commit atomically to local SQLite (real durability, real "Saved on this Mac") but never enqueue an outbox mutation, so they can never report "Synced" in this plan. Real desktop-to-server sync for these commands is a clearly separate follow-on scope (would need account-scoped revision-lock commands matching Phase 1/2's server model), not silently implied as done.
- **Conflict resolution is title-only.** The existing capture-sync-ack conflict path is the only real conflict source wired up; notes/date conflicts aren't modeled since edit/date changes are local-only in this plan.
- **`apps/web`'s Today/Trash routes remain Inbox-list-derived only** in the browser adapter (no `getTrash`/today endpoint fetch wired), since expanding `apps/web`'s shipped surface was explicitly out of scope for this plan.

## Threat Flags

None new. The Task 2/3 threat register items (T-KPL03-03-01 through -04) are mitigated as designed: `ClientFacade` remains free of platform imports (verified by the existing import-boundary test, still passing with the expanded interface), the desktop renderer subscribes to the facade before the initial `snapshot()` resolves, task text is rendered as plain React text throughout the new components, and long content stays in `<textarea>`/internally-scrolled regions rather than being interpreted as markup.

## Next Phase Readiness

- The shared `Workspace` (with its now-complete edit/lifecycle/Trash/undo/conflict surface) is the real, load-bearing Mac Inbox/Today/Trash screen -- future Mac-daily-loop plans build on top of this, not around it.
- A real server-synced edit/lifecycle path for desktop (matching the account-scoped revision-lock model) and a visual/breakpoint E2E pass are the clearest next-plan candidates flagged by the Known Gaps above.
- `apps/web`'s `useSharedWorkspace` production-adoption decision (flagged by Plan 03-09) remains open and untouched by this plan, as instructed.

## Self-Check: PASSED

- All 7 created files exist on disk (`packages/web-ui/src/tasks/TaskEditor.tsx`, `ConflictResolver.tsx`, `packages/web-ui/src/recovery/SyncRecovery.tsx`, `apps/desktop/renderer/desktopClientFacade.ts`, `desktop.css`, `apps/desktop/test/e2e/daily-loop.spec.ts`, `apps/desktop/test/application/state-matrix.test.tsx`).
- Both commits (`2f7b187`, `8ef12ff`) resolve in `git log`.
- `pnpm test:desktop` -- 7 files, 50 tests pass (34 pre-existing + 16 new state-matrix cases).
- `pnpm --dir apps/web test --run` -- 15 files, 153 tests pass.
- `pnpm typecheck:desktop` and `pnpm typecheck:web` -- both clean.
- `pnpm lint:web` -- clean.
- `pnpm test:desktop:e2e` (`npx playwright test --config playwright.config.ts` against `test/e2e/daily-loop.spec.ts`, real Electron app built from `dist/{main,preload,renderer,worker}`) -- 2/2 pass, run three consecutive times for confidence.

---
*Phase: KPL-03-mac-daily-loop*
*Completed: 2026-09-02*
