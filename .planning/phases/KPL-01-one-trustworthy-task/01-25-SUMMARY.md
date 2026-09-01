---
phase: KPL-01-one-trustworthy-task
plan: 25
subsystem: responsive-ui
tags: [react, base-ui, playwright, accessibility, responsive-layout, tdd]

requires:
  - phase: KPL-01-24
    provides: route-owned authentication recovery and the hardened Phase 1 browser runtime
provides:
  - semantic modal navigation for every authenticated destination below 1064px
  - canonical 1024px compact-wide and 1064px persistent-navigation workspace boundaries
  - one task editor composition across narrow full-page and wide detail-region layouts
  - executable five-viewport authenticated route matrix with axe, focus, scroll, and overflow proof
affects: [browser-ui, authenticated-routing, accessibility, phase-1-uat]

actuals:
  tokens: 11555
  tasks: 3
  commits: 12

tech-stack:
  added: []
  patterns:
    - Base UI modal drawer behind a local semantic wrapper
    - shell-owned list/detail slots with one main landmark
    - DTCG breakpoint tokens consumed by named CSS grid regions

key-files:
  created:
    - apps/web/src/app/WorkspaceShell.tsx
    - apps/web/src/components/ui/drawer.tsx
    - apps/web/e2e/responsive-route-matrix.spec.ts
  modified:
    - apps/web/src/App.tsx
    - apps/web/src/app/AppShell.tsx
    - apps/web/src/app/routes.tsx
    - apps/web/src/features/lists/TaskList.tsx
    - apps/web/src/features/tasks/TaskEditor.tsx
    - apps/web/src/index.css
    - apps/web/src/test/ui-contract.test.tsx
    - packages/design-tokens/css.css
    - packages/design-tokens/tokens.json
    - apps/web/src/features/sessions/SessionList.tsx
    - apps/web/src/features/sessions/session-list.test.tsx

key-decisions:
  - "Keep 1024–1063px on modal drawer navigation so the full 360px list and 480px detail minimums remain intact."
  - "Begin persistent navigation at exactly 1064px with a 224px navigation region and cap the list at 440px."
  - "Let WorkspaceShell own the main landmark while TaskList and TaskEditor render as embedded sections in routed list/detail composition."

patterns-established:
  - "Responsive routing: canonical URLs select content; viewport CSS changes only its spatial presentation."
  - "Narrow return: list scroll, origin view, and row focus are stored on the originating history entry and consumed once on return."
  - "Route proof: structural viewport assertions remain separate from perceptual and assistive-technology UAT."

requirements-completed: [GTD-01, GTD-02, GTD-03, GTD-04, GTD-05, GTD-06, GTD-07, WEB-01, WEB-02, QUAL-01]

coverage:
  - id: D1
    description: "Every authenticated destination is reachable below 1064px through a semantic modal navigation drawer with deterministic focus entry, containment, escape, and return."
    requirement: WEB-01
    verification:
      - kind: e2e
        ref: "apps/web/e2e/responsive-route-matrix.spec.ts#drawer reaches primary routes by keyboard"
        status: pass
      - kind: unit
        ref: "apps/web/src/test/ui-contract.test.tsx#opens semantic primary navigation"
        status: pass
    human_judgment: false
  - id: D2
    description: "The workspace preserves 360/480 panes at 1024px and introduces the 224px persistent navigation region at exactly 1064px."
    requirement: WEB-02
    verification:
      - kind: e2e
        ref: "apps/web/e2e/responsive-route-matrix.spec.ts#preserves the amended 1024 and 1064 workspace boundaries"
        status: pass
      - kind: unit
        ref: "apps/web/src/test/ui-contract.test.tsx#keeps DTCG source and generated CSS in exact semantic sync"
        status: pass
    human_judgment: false
  - id: D3
    description: "Inbox, Today, Upcoming, Completed, Trash, Sessions, and the canonical task editor expose one main landmark without horizontal overflow at 320, 768, 1024, 1064, and 1440 CSS pixels."
    requirement: QUAL-01
    verification:
      - kind: e2e
        ref: "apps/web/e2e/responsive-route-matrix.spec.ts#full route and viewport matrix"
        status: pass
      - kind: automated_ui
        ref: "axe serious/critical scan for all 35 route/viewport cases"
        status: pass
    human_judgment: false
  - id: D4
    description: "Accessibility-tree semantics, keyboard focus, forced-colors behavior, and responsive presentation meet the deterministic browser UI contract."
    requirement: QUAL-01
    verification:
      - kind: e2e
        ref: "apps/web/e2e/responsive-route-matrix.spec.ts#@uat-accessibility and @uat-reflow"
        status: pass
      - kind: e2e
        ref: "apps/web/e2e/visual.spec.ts#@uat-reflow"
        status: pass
    human_judgment: false

duration: 29min
completed: 2026-08-31
status: complete
---

# Phase KPL-01 Plan 25: Responsive Authenticated Workspace Summary

**A semantic Base UI navigation drawer and token-driven list/detail shell make every authenticated route reachable from 320px through 1440px while preserving one canonical task editor and exact 1024/1064 boundaries.**

## Performance

- **Duration:** 29 min
- **Started:** 2026-09-01T01:13:09Z
- **Completed:** 2026-09-01T01:42:13Z
- **Tasks:** 3
- **Files modified:** 14

## Accomplishments

- Replaced route-specific navigation with one semantic modal drawer below 1064px and a 224px persistent navigation region at and above 1064px.
- Encoded the amended UI-SPEC exactly: 360px minimum/440px maximum list, 480px minimum detail, independent pane scrolling, and no 320px fallback or fixed-width arithmetic.
- Preserved the canonical task URL across narrow full-page and wide detail presentations, including Back restoration of origin view, scroll, and row focus.
- Added deterministic DOM/layout/accessibility proof across 35 authenticated route/viewport cases without treating screenshots or automated axe output as human visual/VoiceOver sign-off.

## Task Commits

1. **Task 1 RED: responsive drawer proof** — `3396b99` (test)
2. **Task 1 GREEN: semantic navigation drawer** — `bc8df79` (feat)
3. **Task 2 RED: workspace boundary proof** — `5577ac6` (test)
4. **Task 2 RED: narrow return proof** — `5b03b7a` (test)
5. **Task 2 GREEN: canonical workspace boundaries** — `2591bba` (feat)
6. **Task 3 RED: full route matrix proof** — `5b61c29` (test)
7. **Task 3 GREEN: responsive authenticated matrix** — `9ae150d` (feat)
8. **Task 3 lint correction** — `ae8c2aa` (fix)
9. **Task 3 standalone-route compatibility** — `e14a39a` (fix)
10. **Task 3 seeded-heading determinism** — `eaa9f8b` (test)
11. **Full-gate RED: pre-acceptance revocation recovery** — `24d938c` (test)
12. **Full-gate GREEN: reconcile-before-retry revocation** — `39518a9` (fix)

## Files Created/Modified

- `apps/web/src/components/ui/drawer.tsx` — local wrapper around the installed Base UI modal drawer.
- `apps/web/src/app/WorkspaceShell.tsx` — compact header, primary navigation, and shell-owned list/detail composition.
- `apps/web/src/app/AppShell.tsx` — routes Inbox, primary lists, tasks, and Sessions through the shared workspace.
- `apps/web/src/app/routes.tsx` — supplies canonical route content slots and preserves standalone route consumers.
- `apps/web/src/features/lists/TaskList.tsx` — embedded list surface and one-shot narrow scroll/focus restoration.
- `apps/web/src/features/tasks/TaskEditor.tsx` — embedded/full-page editor modes and semantic narrow Back action.
- `apps/web/src/index.css` — exact 1024px and 1064px grid transitions with independent pane scrolling.
- `packages/design-tokens/tokens.json`, `packages/design-tokens/css.css` — checked-in compact-wide and persistent-navigation breakpoints.
- `apps/web/src/test/ui-contract.test.tsx` — static and component-level responsive-shell contract checks.
- `apps/web/e2e/responsive-route-matrix.spec.ts` — keyboard, geometry, scroll, focus, overflow, landmark, and axe matrix.
- `apps/web/src/features/sessions/SessionList.tsx` — reconciles a resumed revoke, then retries once with fresh CSRF only when the target remains active.
- `apps/web/src/features/sessions/session-list.test.tsx` — distinguishes accepted/absent revocations from rejected/still-active revocations.

## Decisions Made

- Used the already-installed Base UI drawer rather than creating custom modal/focus mechanics or adding a dependency.
- Kept native anchors and browser history as the routing source of truth; the shell does not introduce a second router.
- Made the shell the sole main-landmark owner for split views, with embedded list/editor sections preserving reusable component identity.
- Preserved legacy standalone `AppRoutes` consumers through an explicit `authenticatedContentOwnsRoutes` composition contract.

## TDD Gate Compliance

- Task 1 RED failed because no accessible “Open navigation” trigger existed; GREEN passed 5 component assertions and 2 real-browser drawer paths, then passed the tracer feedback rerun.
- Task 2 RED failed on missing breakpoint tokens, canonical grid arithmetic, and narrow Back behavior; GREEN passed 6 UI-contract tests, 4 responsive Playwright tests, and typecheck.
- Task 3 RED failed because the wide canonical task route exposed two main landmarks; GREEN passed 5 responsive Playwright tests, 7 UI-contract tests, and all 55 affected regression tests.
- Every RED commit precedes its corresponding GREEN implementation in git history.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Preserved standalone authenticated route composition**
- **Found during:** Task 3 full verification
- **Issue:** `AppRoutes` consumers without `AppShell` received empty list/detail route slots after the shared-shell refactor.
- **Fix:** Added a semantic shell-less fallback and an explicit production ownership flag so tests and non-shell consumers retain route output without duplicating the production shell.
- **Files modified:** `apps/web/src/App.tsx`, `apps/web/src/app/routes.tsx`
- **Verification:** 55 affected Vitest tests and TypeScript typecheck pass.
- **Committed in:** `e14a39a`

**2. [Rule 1 - Bug] Made route-heading assertions deterministic with accumulated seeded data**
- **Found during:** Task 3 full verification
- **Issue:** A prior lifecycle test could add a second section heading named “Today,” making an underspecified route assertion ambiguous.
- **Fix:** Scoped matrix assertions to the route-level heading.
- **Files modified:** `apps/web/e2e/responsive-route-matrix.spec.ts`
- **Verification:** focused responsive Playwright suite passes 5/5, including all 35 matrix cases.
- **Committed in:** `eaa9f8b`

**3. [Rule 1 - Bug] Resumed a session revocation rejected before acceptance**
- **Found during:** Canonical full-gate verification
- **Issue:** After recent-authentication recovery, session administration reconciled inventory but stopped when the target was still active, so an operation rejected by the recent-auth plug was never completed.
- **Fix:** Reconcile inventory first; if the target is absent, accept the authoritative result without replay, and if it remains active, retry the revoke once with the fresh recent-auth CSRF token.
- **Files modified:** `apps/web/src/features/sessions/SessionList.tsx`, `apps/web/src/features/sessions/session-list.test.tsx`
- **Verification:** 33/33 focused session/auth tests, isolated real-stack lifecycle recovery, typecheck, and the canonical full Phase 1 gate pass.
- **Committed in:** `24d938c`, `39518a9`

---

**Total deviations:** 3 auto-fixed (3 Rule 1 bugs)
**Impact on plan:** Both fixes preserve existing composition and deterministic verification; no feature scope was added.

## Issues Encountered

- Repository-wide ESLint remains red on three pre-existing errors: `AuthProvider.tsx:259` fast-refresh export composition and the previously recorded `react-hooks/set-state-in-effect` patterns in `TaskList.tsx:224` and `TrashList.tsx:91`. Plan-local lint findings were fixed in `ae8c2aa`; the baseline items are recorded in `deferred-items.md`.
- The first full Phase 1 runs exposed a deterministic recent-auth session-revocation recovery bug. A reconcile-before-retry fix closed it while preserving no-replay behavior when authoritative inventory proves the original revoke already committed.

## Verification

- Focused component contract: 7/7 Vitest assertions passed.
- Focused responsive browser contract: 5/5 Playwright tests passed, including 35 route/viewport axe cases.
- Affected regression suites: 55/55 Vitest tests passed.
- TypeScript: passed.
- Full Phase 1 gate: repository integrity and runtime preflight passed; 108/108 ExUnit passed; contract drift and typecheck passed; 138/138 Vitest passed; 23/23 Playwright passed.
- Repository-wide ESLint: executed; three pre-existing errors and two warnings remain as recorded above.

## Known Stubs

None. The scan found only CSS class naming and native date-input placeholder attributes; no placeholder behavior, skipped test, or incomplete data path was introduced.

## Threat Surface

No unplanned security surface was introduced. Navigation intent, modal/background isolation, untrusted content reflow, and canonical task-route composition are the boundaries declared in the plan threat model and are covered by the focused tests.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

The responsive workspace contract and route matrix are ready for the three explicitly human UAT items in `01-VERIFICATION.md`. The canonical Phase 1 executable gate is green; repository-wide ESLint still has the separately recorded baseline violations.

## Self-Check: PASSED

All three created artifacts exist, all twelve implementation/test commits resolve in git history, and the summary passes `git diff --check`.

---
*Phase: KPL-01-one-trustworthy-task*
*Completed: 2026-08-31*
