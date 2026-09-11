---
phase: KPL-06-portability-and-trust-release
plan: 09
subsystem: ui
tags: [conflict-resolver, recovery-strip, keyboard-navigation, dirty-guard, O-44, O-43, O-22, D-37]

# Dependency graph
requires:
  - phase: KPL-06-06
    provides: durable refusal_records (mutation id, entity id, outcome, per-field diverging values, unresolved flag) that this plan's rendering contract targets
  - phase: KPL-06-05
    provides: the corrected ConflictField.field OpenAPI enum (completed_at/trashed_at) that lifecycle conflicts need to decode at all
provides:
  - A per-field, lifecycle-aware ConflictResolver (packages/web-ui) rendering one labelled fieldset/radio group per affected field, with no row for an absent field
  - A widened ClientFacade contract (WorkspaceConflictView.fields, resolveConflict per-field choices, WorkspaceSnapshotView.unresolvedRefusals) that both browser and desktop adapters implement
  - An unresolved-refusal entry in the existing SyncRecovery strip, alongside the eligible-undo entry, with a navigating "Review conflict" action
  - A guardedSetRoute imperative seam on Workspace, and DesktopShell's new-task/go-inbox/go-today keyboard commands routed through it instead of calling facade.setRoute directly
affects: [KPL-06-13-final-verification, any future plan wiring 06-06's refusal_records into the desktop preload bridge]

# Actuals (#2632)
actuals:
  tokens: 12900
  tasks: 3
  commits: 3

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Native fieldset/legend + input[type=radio] per conflicting field, reusing the Phase 1 organization-picker pattern instead of adding a radio-group registry primitive -- one accessible mutually-exclusive decision per labelled group"
    - "Workspace exposes an imperative handle (forwardRef/useImperativeHandle) so a host component (DesktopShell) can request a guarded navigation without duplicating or bypassing the dirty-state check that already gates mouse navigation"

key-files:
  created:
    - packages/web-ui/src/tasks/ConflictResolver.test.tsx
    - packages/web-ui/src/workspace/Workspace.test.tsx
    - packages/web-ui/vitest.config.ts
    - packages/web-ui/src/test/setup.ts
    - apps/desktop/test/e2e/guarded-navigation.spec.ts
  modified:
    - packages/web-ui/src/ClientFacade.ts
    - packages/web-ui/src/tasks/ConflictResolver.tsx
    - packages/web-ui/src/recovery/SyncRecovery.tsx
    - packages/web-ui/src/workspace/Workspace.tsx
    - apps/desktop/renderer/DesktopShell.tsx
    - apps/desktop/renderer/desktopClientFacade.ts
    - apps/web/src/adapters/browserClientFacade.ts
    - apps/web/src/app/WorkspaceShell.test.tsx
    - apps/desktop/test/fixtures/desktopClientFacade.ts
    - apps/desktop/test/application/state-matrix.test.tsx
    - apps/desktop/test/e2e/daily-loop.spec.ts

key-decisions:
  - "WorkspaceConflictView widened to a `fields` array (ConflictFieldName covers title/notes/plannedDate/deadline/project/tags/completion/trashStatus) instead of a single bare mine/current/field:'title' shape, so a lifecycle or Trash divergence has somewhere to render at all -- ClientFacade.ts was not in this plan's declared files_modified but is the shared type both the resolver and both adapters compile against, so widening it was unavoidable."
  - "resolveConflict now takes a per-field choice map (Partial<Record<ConflictFieldName,'current'|'mine'>>) submitted once, rather than one whole-conflict choice -- browserClientFacade.ts passes the map straight through to the existing multi-field resolve-task-conflict command; desktopClientFacade.ts's preload bridge still only carries a single title choice (06-06 did not wire refusal_records into listConflicts), so it extracts choices.title with a first-available fallback, disclosed as a known limit rather than silently dropped."
  - "SyncRecovery.tsx (not in this task's declared files_modified) was widened directly, rather than duplicating recovery-strip rendering inside Workspace.tsx, because it IS the existing recovery strip the acceptance criteria require reusing -- 'no new UI surface' would be violated by building a second one beside it."
  - "The desktop adapter's unresolvedRefusals always resolves to an empty array: wiring 06-06's durable refusal_records table through main/preload/local-store into this renderer contract needs new preload IPC and store-worker reads, which is out of this plan's authorized file scope (only Workspace.tsx was declared). The contract, its rendering, and its navigation are real and tested against fixtures; the desktop production data source is a disclosed gap, not a stub papered over as done."
  - "Workspace.tsx exposes `guardedSetRoute` via forwardRef/useImperativeHandle rather than moving keyboard-command handling down into Workspace's own scope (the plan's other offered option) -- this keeps DesktopShell owning command dispatch/menu-equivalence exactly as before, with only the three route-changing cases rerouted through the guard."

patterns-established:
  - "A shared presentation component exposes a narrow imperative handle only when a specific external host (not any consumer) must reach an internal guard it cannot duplicate correctly itself."

requirements-completed: [QUAL-04]

coverage:
  - id: D1
    description: "ConflictResolver renders one labelled fieldset/radio group per field named in the conflict payload (no row for an absent field), including a lifecycle/Trash-divergence row in plain lifecycle words, with per-field staging and one submission point"
    requirement: "QUAL-04"
    verification:
      - kind: unit
        ref: "packages/web-ui/src/tasks/ConflictResolver.test.tsx (9 cases: one-field, six-field, absent-field, lifecycle, staging/no-premature-mutation, nonconflicting-field-preservation, rejected, uncertain-result, long-text collapse across notes/project/tags)"
        status: pass
      - kind: other
        ref: "pnpm typecheck:web && pnpm typecheck:desktop"
        status: pass
      - kind: other
        ref: "git diff --exit-code -- apps/web/components.json (no registry drift)"
        status: pass
    human_judgment: false
  - id: D2
    description: "An unresolved refusal for a task not currently viewed surfaces in the existing recovery strip, naming the task, with a navigating Review conflict action, disappearing on resolution, without displacing the eligible-undo entry"
    requirement: "QUAL-04"
    verification:
      - kind: unit
        ref: "packages/web-ui/src/workspace/Workspace.test.tsx (4 cases: naming, navigation, no-entry-when-resolved, multiple-refusals-preserve-undo-entry)"
        status: pass
      - kind: other
        ref: "pnpm --dir packages/web-ui exec vitest run (13/13, no reduced count) and pnpm --dir apps/web exec vitest run (172/172, no regression)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Every keyboard command in DesktopShell.tsx that changes route or selected task (new-task, go-inbox, go-today) routes through Workspace's dirty-state guard; a dirty editor produces the existing discard dialog for each shortcut and a clean editor navigates immediately with no dialog"
    requirement: "QUAL-04"
    verification:
      - kind: e2e
        ref: "apps/desktop/test/e2e/guarded-navigation.spec.ts (7 real Electron cases: clean navigation for all three shortcuts, dirty dialog for each shortcut, keyboard-initiated Save/Discard/Keep-Editing each matching the mouse-initiated outcome)"
        status: pass
      - kind: other
        ref: "sed 's|//.*$||' apps/desktop/renderer/DesktopShell.tsx | grep -cE 'facade\\.(setRoute|selectTask)\\(' == 0"
        status: pass
      - kind: other
        ref: "pnpm test:desktop:e2e (83/83, up from 76 pre-plan, 0 failed) and node tooling/verify-desktop-phase.mjs (10/11 lanes PASS)"
        status: pass
    human_judgment: false
  - id: D4
    description: "The desktop phase gate reports zero failed lanes with positive case counts across typecheck, unit, ipc, electron-e2e, package-once, package-reproducible, packaged, real-stack-sync, and privacy"
    verification:
      - kind: other
        ref: "node tooling/verify-desktop-phase.mjs -- 10/11 lanes PASS"
        status: pass
      - kind: other
        ref: "node tooling/verify-desktop-phase.mjs -- macos-integration lane"
        status: fail
    human_judgment: true
    rationale: "The macos-integration lane fails with the same pre-existing 'no macOS integration evidence exists for application digest <new digest>' condition already disclosed in 06-06-SUMMARY.md: this lane runs once per packaged-artifact digest and every desktop-touching plan since 06-03 has changed that digest. 06-13's own declared scope inventories tooling/verify-macos-integration.mjs results as part of final phase verification, so regenerating it here would be redone again by the next desktop-touching plan regardless. A human should confirm this stays deferred to 06-13."

duration: ~95min
completed: 2026-09-11
status: complete
---

# Phase KPL-06 Plan 09: Per-Field Conflict Resolver, Recovery-Strip Refusals, and Guarded Keyboard Navigation Summary

**Widened the conflict resolver from one title-only whole-conflict choice to one labelled fieldset/radio row per affected field (including a lifecycle/Trash row in plain words), surfaced unresolved refusals in the existing recovery strip, and routed every keyboard route-changing command in DesktopShell through the same dirty-state guard mouse navigation already uses.**

## Performance

- **Duration:** ~95 min
- **Tasks:** 3 (all `type="auto" tdd="true"`)
- **Files modified:** 16 (5 created, 11 modified)

## Accomplishments

- **Task 1:** `ConflictResolver.tsx` renders one native `fieldset`/`legend` + `input[type=radio]` group per field the conflict payload names (title/notes/plannedDate/deadline/project/tags/completion/trashStatus), never a row for an absent field. A lifecycle/Trash divergence gets its own row (`Completion`/`Trash status`) in plain lifecycle words rather than a title diff. Choices stage locally in component state and submit once via a widened `resolveConflict(choices)` call; the heading/body copy stays byte-identical to the pre-plan strings; the existing six-line collapse-with-disclosure pattern applies per row (proven for notes, project, and tags). `ClientFacade.ts`'s `WorkspaceConflictView` was widened to a `fields` array to make this possible, cascading a minimal, compile-only fix into `browserClientFacade.ts` (now surfaces every field the server's `TaskConflict` already carries, not just title) and `desktopClientFacade.ts` (still title-only, since the preload bridge itself is unchanged). No vitest config existed anywhere in `packages/web-ui`; added one (mirroring `apps/web`'s jsdom setup) so this plan's own tests could run at all.
- **Task 2:** `WorkspaceSnapshotView` gained `unresolvedRefusals` (route/taskId/taskTitle); `SyncRecovery.tsx` (the existing recovery strip) renders one entry per unresolved refusal alongside its pre-existing eligible-undo entry, with a `Review conflict` action that navigates to the task. Both adapters report an empty list for now — wiring 06-06's durable `refusal_records` table into this contract needs new preload IPC and store-worker reads, outside this plan's declared file scope, disclosed below rather than stubbed silently.
- **Task 3:** `Workspace.tsx` now exposes a `guardedSetRoute` imperative handle (forwardRef/`useImperativeHandle`) that runs the exact same `attemptNavigation` dirty check and discard dialog the mouse nav links already use. `DesktopShell.tsx`'s `new-task`/`go-inbox`/`go-today` keyboard commands call `workspaceRef.current?.guardedSetRoute(...)` instead of `facade.setRoute(...)` directly — a keystroke can no longer discard unsaved work. Proven against the real shipped Electron app in `apps/desktop/test/e2e/guarded-navigation.spec.ts` (7 cases).

## Task Commits

1. **Task 1: Widen the conflict resolver to one labelled row per affected field** - `dfb6b55` (feat)
2. **Task 2: Surface an unattended refusal in the recovery strip** - `88d55aa` (feat)
3. **Task 3: Route every keyboard navigation command through the dirty-state guard** - `1e76ab4` (feat)

**Plan metadata:** (this commit, following)

## Files Created/Modified

- `packages/web-ui/src/tasks/ConflictResolver.tsx` — widened per-field, lifecycle-aware chooser
- `packages/web-ui/src/tasks/ConflictResolver.test.tsx` — 9 new tests
- `packages/web-ui/src/ClientFacade.ts` — `ConflictFieldName`/`WorkspaceConflictFieldView`, widened `WorkspaceConflictView`/`resolveConflict`, `UnresolvedRefusalView`/`WorkspaceSnapshotView.unresolvedRefusals`
- `packages/web-ui/src/recovery/SyncRecovery.tsx` — renders unresolved-refusal entries alongside the undo entry
- `packages/web-ui/src/workspace/Workspace.tsx` — `guardedSetRoute` imperative handle; wires `unresolvedRefusals` into `SyncRecovery`
- `packages/web-ui/src/workspace/Workspace.test.tsx` — 4 new tests
- `packages/web-ui/vitest.config.ts`, `packages/web-ui/src/test/setup.ts` — new test infrastructure (none existed)
- `apps/desktop/renderer/DesktopShell.tsx` — keyboard commands route through `guardedSetRoute`
- `apps/desktop/renderer/desktopClientFacade.ts` — adapts to widened facade shape (title-only, disclosed limit)
- `apps/web/src/adapters/browserClientFacade.ts` — surfaces every field the server already returns
- `apps/web/src/app/WorkspaceShell.test.tsx`, `apps/desktop/test/fixtures/desktopClientFacade.ts`, `apps/desktop/test/application/state-matrix.test.tsx`, `apps/desktop/test/e2e/daily-loop.spec.ts` — updated fixtures/tests broken by the widened `WorkspaceConflictView`/`WorkspaceSnapshotView` shapes
- `apps/desktop/test/e2e/guarded-navigation.spec.ts` — 7 new Electron E2E cases

## Decisions Made

See `key-decisions` in frontmatter. In prose: `ClientFacade.ts` and `SyncRecovery.tsx` were touched even though neither was in this plan's declared `files_modified`, because they are the shared type contract and the literal recovery strip the tasks' own acceptance criteria require widening — narrower scope would have meant either duplicating the strip or leaving the resolver unable to compile. The desktop adapter's `unresolvedRefusals` and lifecycle-conflict rendering both stay real-but-empty/title-only in production until a follow-on plan wires 06-06's `refusal_records` and the OpenAPI lifecycle-field decode path through the preload bridge and `apps/web/src/api/keepling.ts`'s `mapTaskConflict` (which today drops any conflict naming a field outside `notes`/`title` entirely) — both are disclosed gaps, not silent regressions, and neither was in this plan's authorized file scope.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Widened `ClientFacade.ts` (not in declared files_modified) to make the per-field resolver possible**
- **Found during:** Task 1
- **Issue:** `WorkspaceConflictView` was a single bare `{current, field: 'title', id, mine, taskId}` shape; a resolver rendering one row per field cannot be built against it.
- **Fix:** Widened to `{fields: WorkspaceConflictFieldView[], id, taskId}` with a closed `ConflictFieldName` union covering every field class the plan names, plus a per-field `resolveConflict(choices)` signature.
- **Files modified:** `packages/web-ui/src/ClientFacade.ts`, `apps/web/src/adapters/browserClientFacade.ts`, `apps/desktop/renderer/desktopClientFacade.ts` (minimal compile-fix only), plus fixtures broken by the shape change (`apps/desktop/test/fixtures/desktopClientFacade.ts`, `apps/desktop/test/application/state-matrix.test.tsx`, `apps/desktop/test/e2e/daily-loop.spec.ts`, `apps/web/src/app/WorkspaceShell.test.tsx`).
- **Verification:** `pnpm typecheck:web`, `pnpm typecheck:desktop`, `pnpm --dir apps/web exec vitest run` (172/172), `pnpm --dir apps/desktop test` (306/306), `pnpm test:desktop:e2e` (83/83).
- **Committed in:** `dfb6b55` (Task 1 commit)

**2. [Rule 3 - Blocking] No vitest test infrastructure existed for `packages/web-ui`**
- **Found during:** Task 1, first attempt to run this plan's own `<verify>` command
- **Issue:** `pnpm --dir packages/web-ui exec vitest run` had no config to run against — no `vitest.config.ts`, no jsdom setup, no prior test file anywhere in the package.
- **Fix:** Added `packages/web-ui/vitest.config.ts` and `packages/web-ui/src/test/setup.ts`, mirroring `apps/web`'s existing jsdom configuration exactly.
- **Files modified:** `packages/web-ui/vitest.config.ts`, `packages/web-ui/src/test/setup.ts`
- **Verification:** `pnpm --dir packages/web-ui exec vitest run` runs and passes (13/13 across both new test files).
- **Committed in:** `dfb6b55` (Task 1 commit)

**3. [Rule 3 - Blocking] Widened `SyncRecovery.tsx` (not in declared files_modified) rather than duplicating the recovery strip**
- **Found during:** Task 2
- **Issue:** The recovery strip Task 2 must widen actually lives in `SyncRecovery.tsx`, a sibling file Workspace renders — not in Workspace.tsx itself.
- **Fix:** Added `onReviewRefusal`/`unresolvedRefusals` props to `SyncRecovery.tsx` and rendered one entry per refusal alongside the existing undo entry; wired from `Workspace.tsx`.
- **Files modified:** `packages/web-ui/src/recovery/SyncRecovery.tsx`, `packages/web-ui/src/workspace/Workspace.tsx`
- **Verification:** `packages/web-ui/src/workspace/Workspace.test.tsx` (4/4 pass, including the undo-entry-preserved-with-multiple-refusals case).
- **Committed in:** `88d55aa` (Task 2 commit)

**4. [Rule 1 - Bug, pre-existing test broken by Task 1's shape change] Fixed the real Electron conflict-resolution E2E flow**
- **Found during:** Task 1 verification (full e2e suite), before Task 3 began
- **Issue:** `apps/desktop/test/e2e/daily-loop.spec.ts`'s conflict test clicked a single `getByRole('button', {name: 'Use mine'})` that resolved the conflict on click — the widened resolver requires selecting a radio and then a separate `Save resolution` button.
- **Fix:** Updated the test to click the radio then the submit button.
- **Files modified:** `apps/desktop/test/e2e/daily-loop.spec.ts`
- **Verification:** `pnpm test:desktop:e2e` (full suite, 0 failed).
- **Committed in:** `88d55aa` (Task 2 commit, alongside the other conflict-shape fixture fixes)

---

**Total deviations:** 4 auto-fixed (3 blocking scope necessities, 1 pre-existing-test bug from Task 1's own shape change). **Impact:** All four were necessary direct consequences of correctly implementing this plan's stated tasks; no scope creep beyond what building and testing the per-field resolver, the widened recovery strip, and the guarded keyboard navigation required.

## Issues Encountered

None beyond the deviations above.

## Known Stubs

- **Desktop `unresolvedRefusals` always empty.** `desktopClientFacade.ts`'s `currentSnapshot()` reports `unresolvedRefusals: []` unconditionally. The rendering contract, staging, navigation, and undo-entry-preservation behavior are real and tested (`Workspace.test.tsx`), but the desktop production data source (06-06's `refusal_records` table) is not yet wired through the preload bridge/`local-store.ts` `listConflicts`-equivalent — that requires new preload IPC and store-worker reads outside this plan's declared `files_modified` (only `Workspace.tsx` was authorized). A future plan must add a `listUnresolvedRefusals`-equivalent preload operation and wire it here.
- **Desktop lifecycle/Trash conflicts still not decodable end-to-end.** `desktopClientFacade.ts`'s `mapConflict` still only maps the single title field the pre-existing `listConflicts()`/`conflicts` table carries (06-06 deliberately left that table's narrower write unchanged, adding `refusal_records` as an additive, broader record instead). `apps/web/src/api/keepling.ts`'s `mapTaskConflict` also still drops any conflict naming a field outside `notes`/`title` entirely (returns `null` for the WHOLE conflict, not just the unrecognized field) — a real server-issued lifecycle conflict would currently vanish from both the browser and desktop adapters rather than reach the resolver's new lifecycle row. The resolver itself renders a lifecycle row correctly given a payload that names one (proven via direct fixture in `ConflictResolver.test.tsx`); wiring a real lifecycle conflict through either adapter's decode path is out of this plan's declared scope and is the next gap to close before O-44/D-37 is fully closed end-to-end.

## Threat Flags

None — the three threat-register mitigations this plan owns (T-06-09-01 through T-06-09-04) are all addressed by the changes above and proven by the cited tests; T-06-09-05 (long-value overflow) is explicitly `accept`ed in the plan's own threat model.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- The per-field, lifecycle-aware `ConflictResolver` contract is real and fully proven against fixtures; the recovery-strip widening and the guarded-keyboard-navigation fix are both real and proven end-to-end (the latter against the real shipped Electron app).
- Two disclosed gaps remain before O-44/D-37 is closed end-to-end in production (see Known Stubs above): wiring `refusal_records` into the desktop preload bridge, and widening `apps/web/src/api/keepling.ts`'s `mapTaskConflict`/OpenAPI lifecycle-field decode path so a real lifecycle conflict reaches either adapter instead of vanishing. Neither was in this plan's authorized `files_modified`.
- The desktop phase gate is green at 10/11 lanes; the `macos-integration` lane's failure is the same pre-existing, already-disclosed condition from 06-06-SUMMARY.md (evidence must be regenerated once per packaged-artifact digest, deferred to 06-13's own declared scope).
- Ready for the next KPL-06 plan.

---
*Phase: KPL-06-portability-and-trust-release*
*Completed: 2026-09-11*

## Self-Check: PASSED

- All key-files.created exist on disk (verified with `[ -f ]`): `packages/web-ui/src/tasks/ConflictResolver.test.tsx`, `packages/web-ui/src/workspace/Workspace.test.tsx`, `packages/web-ui/vitest.config.ts`, `packages/web-ui/src/test/setup.ts`, `apps/desktop/test/e2e/guarded-navigation.spec.ts`.
- All three task commits (`dfb6b55`, `88d55aa`, `1e76ab4`) exist in `git log --oneline --all`.
- Re-ran every task's `<verify>`: `pnpm --dir packages/web-ui exec vitest run src/tasks/ConflictResolver.test.tsx` (9/9), `pnpm typecheck:web && pnpm lint:web` (pass), `git diff --exit-code -- apps/web/components.json` (clean), `pnpm --dir packages/web-ui exec vitest run src/workspace` (4/4) and full-package run (13/13), `pnpm --dir apps/web exec vitest run` (172/172, no regression), `pnpm test:desktop:e2e` (83/83, was 76 before this plan), `sed 's|//.*$||' apps/desktop/renderer/DesktopShell.tsx | grep -cE 'facade\.(setRoute|selectTask)\('` (0), `pnpm typecheck:desktop` (pass), `node tooling/verify-desktop-phase.mjs` (10/11 lanes PASS; `macos-integration` fails for the disclosed, pre-existing, out-of-scope reason above).
