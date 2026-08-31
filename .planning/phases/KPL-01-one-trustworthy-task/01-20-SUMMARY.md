---
phase: KPL-01-one-trustworthy-task
plan: 20
subsystem: browser-auth-recovery
tags: [react, typescript, authentication, continuations, playwright, accessibility]

requires:
  - phase: KPL-01-19
    provides: Complete Phase 1 browser lifecycle and fail-fast real-stack verification gate
provides:
  - Exact authenticated-read recovery for task detail, activity pagination, organization assignment, Projects, and Tags
  - Keyed, ordered, exact-once draining of concurrent authentication continuations
  - Retained route state beneath an accessible recovery overlay with visible continuation retry
  - Real expired-session and concurrent-continuation browser evidence
affects: [browser-authentication, task-detail, activity, organizations, phase-1-verification]

actuals:
  tokens: 10973
  tasks: 3
  commits: 10

tech-stack:
  added: []
  patterns: [keyed authentication continuations, exact read resumption, all-settled continuation drain, retained-route recovery overlay]

key-files:
  created:
    - apps/web/e2e/authenticated-read-recovery.spec.ts
  modified:
    - apps/web/src/app/AuthProvider.tsx
    - apps/web/src/app/routes.tsx
    - apps/web/src/features/tasks/TaskEditor.tsx
    - apps/web/src/features/activity/ActivityList.tsx
    - apps/web/src/features/organizations/OrganizationFields.tsx
    - apps/web/src/features/auth/auth.test.tsx
    - apps/server/config/test.exs

key-decisions:
  - "Authentication continuations are keyed by semantic intent and mutation identity, preserve insertion order, deduplicate repeated registration, and delete only after successful settlement."
  - "The authenticated route remains mounted during recovery; accessibility hiding is applied to retained root elements without inserting a layout-affecting DOM wrapper."
  - "The test environment permits the full suite's successful sign-in volume while production authentication abuse limits remain unchanged."

patterns-established:
  - "Exact read continuation: capture the route, task, or cursor-bound read and retry that operation only after server-issued session rotation."
  - "Concurrent recovery: await every continuation with all-settled semantics, retain failures for explicit retry, and fence stale drains on authentication clear."
  - "Recovery presentation: keep work mounted beneath one modal overlay and expose resume failure as a named recoverable state."

requirements-completed: [SRV-01, WEB-02, QUAL-01]

coverage:
  - id: D1
    description: "Expired task-detail and activity reads return to the same task and exact pagination cursor without discarding mounted work."
    requirement: WEB-02
    verification:
      - kind: unit
        ref: "apps/web/src/features/tasks/task-editor.test.tsx and apps/web/src/features/activity/activity-list.test.tsx#authenticated read recovery"
        status: pass
      - kind: e2e
        ref: "apps/web/e2e/authenticated-read-recovery.spec.ts#@authenticated-read-task"
        status: pass
    human_judgment: false
  - id: D2
    description: "Expired assignment, Projects, and Tags reads recover their original task or organization-kind context through real sign-in."
    requirement: SRV-01
    verification:
      - kind: unit
        ref: "apps/web/src/features/organizations/organization-fields.test.tsx#authenticated read recovery"
        status: pass
      - kind: e2e
        ref: "apps/web/e2e/authenticated-read-recovery.spec.ts#@authenticated-read-organizations"
        status: pass
    human_judgment: false
  - id: D3
    description: "One session rotation drains concurrent compatible continuations exactly once, preserves successful results, and leaves failures visibly retryable."
    requirement: QUAL-01
    verification:
      - kind: unit
        ref: "apps/web/src/features/auth/auth.test.tsx#concurrent authentication continuations"
        status: pass
      - kind: e2e
        ref: "apps/web/e2e/authenticated-read-recovery.spec.ts#@authenticated-read-concurrent"
        status: pass
    human_judgment: false

duration: 30min
completed: 2026-08-31
status: complete
---

# Phase KPL-01 Plan 20: Authenticated Read Recovery Summary

**Exact protected-read resumption and ordered concurrent continuation draining preserve route, draft, and pagination context across real session expiry**

## Performance

- **Duration:** 30 min
- **Started:** 2026-08-31T22:08:41Z
- **Completed:** 2026-08-31T22:38:39Z
- **Tasks:** 3
- **Files modified:** 12

## Accomplishments

- Task detail, initial activity, cursor pagination, assignment, Projects, and Tags distinguish authentication expiry from generic read failure and resume the exact interrupted read.
- The authentication coordinator retains concurrent keyed continuations, awaits every resume, removes only successful entries, and presents failed resumes for another explicit attempt.
- Recovery keeps authenticated content mounted and inaccessible beneath one overlay, preserving dirty state and route identity without changing responsive layout.
- Real Phoenix/PostgreSQL tests revoke sessions and prove task, organization, and concurrent read recovery through visible sign-in.

## Task Commits

Each task followed a committed RED/GREEN sequence, with verification hardening committed separately:

1. **Task 1: Resume an expired task-detail read through the real stack** — `c140284` (RED), `24d9e65` (GREEN)
2. **Task 2: Extend exact read recovery to organizations, projects, and tags** — `7f26be4` (RED), `ac9d931` (GREEN)
3. **Task 3: Drain concurrent reauthentication continuations safely** — `1d74eb1` (RED), `2c062f8` (GREEN)
4. **Recovery presentation and verification hardening** — `a2a3b7b`, `ab84f53`, `281eed2`, `a15a907`

## Files Created/Modified

- `apps/web/e2e/authenticated-read-recovery.spec.ts` — Real expired-session task, organization, and concurrent continuation proof.
- `apps/web/src/App.tsx` — Supplies visible continuation failure and retry state to routing.
- `apps/web/src/app/AuthProvider.tsx` — Owns the keyed ordered continuation collection and all-settled drain.
- `apps/web/src/app/routes.tsx` — Wires read continuations and retains inaccessible route content beneath recovery UI.
- `apps/web/src/features/tasks/TaskEditor.tsx` — Resumes the exact task read and names resumed failure.
- `apps/web/src/features/activity/ActivityList.tsx` — Resumes initial or cursor-bound activity reads without clearing accepted pages.
- `apps/web/src/features/organizations/OrganizationFields.tsx` — Resumes assignment and kind-specific organization reads.
- `apps/web/src/features/tasks/task-editor.test.tsx` — Task-read recovery coverage.
- `apps/web/src/features/activity/activity-list.test.tsx` — Initial and pagination recovery coverage.
- `apps/web/src/features/organizations/organization-fields.test.tsx` — Assignment, Projects, and Tags recovery coverage.
- `apps/web/src/features/auth/auth.test.tsx` — Concurrent drain, deduplication, failure, retry, and fencing coverage.
- `apps/server/config/test.exs` — Test-only login allowance for deterministic full-suite recovery scenarios.

## Decisions Made

- Continuation identity uses the closed semantic intent kind plus mutation identity; this deduplicates repeated registration without logging or exposing identifiers.
- A drain uses `Promise.allSettled`, preserves registration order, and removes an entry only after success so one failure cannot suppress other recovery work.
- Route content stays mounted through a component boundary that adds no layout node; root content is temporarily `aria-hidden` while the recovery overlay is active.
- Test-only authentication policy accommodates deliberate successful-login volume; production defaults are untouched.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Hid retained route content from assistive technology**
- **Found during:** Task 3 recovery presentation verification
- **Issue:** Keeping the route mounted allowed both the retained content and sign-in overlay to remain exposed in the accessibility tree.
- **Fix:** Added a recovery boundary that marks retained root elements `aria-hidden` while the overlay is active and restores prior values afterward.
- **Files modified:** `apps/web/src/app/routes.tsx`
- **Verification:** Focused authentication/lifecycle tests and the full Playwright suite pass.
- **Committed in:** `a2a3b7b`, `281eed2`

**2. [Rule 1 - Bug] Prevented recovery presentation from remounting or widening routes**
- **Found during:** Full Phase 1 verification
- **Issue:** A conditional wrapper remounted interrupted work; a persistent DOM wrapper then broke the 1024px direct-child layout contract.
- **Fix:** Kept one stable React boundary with no layout DOM node and applied accessibility state to existing root elements.
- **Files modified:** `apps/web/src/app/routes.tsx`
- **Verification:** Lifecycle recovery and `UI-BACKSTOP-OVERFLOW` pass at all tested widths and themes.
- **Committed in:** `ab84f53`, `281eed2`

**3. [Rule 3 - Blocking] Prevented full-suite browser login exhaustion**
- **Found during:** Plan-level verification
- **Issue:** The new real-expiry scenarios legitimately raised successful sign-ins above the production account bucket during one shared seeded E2E run, causing later tests to receive a rate-limit rejection.
- **Fix:** Raised only the test-environment login allowance and consolidated the concurrent tracer into the task-route scenario that already registers task and activity reads together.
- **Files modified:** `apps/server/config/test.exs`, `apps/web/e2e/authenticated-read-recovery.spec.ts`
- **Verification:** The full gate passes 105 ExUnit, 101 Vitest, and 15 Playwright tests; production policy remains unchanged.
- **Committed in:** `281eed2`, `a15a907`

---

**Total deviations:** 3 auto-fixed (2 Rule 1 bugs, 1 Rule 3 blocking issue)
**Impact on plan:** The fixes preserve the intended recovery contract, accessibility, responsive layout, and production abuse policy without adding product scope.

## Issues Encountered

- Repository-wide ESLint still reports two pre-existing `react-hooks/set-state-in-effect` findings in unchanged list components. They are recorded in `deferred-items.md` and `.planning/WINDOWS.md`; changed-file lint passes.

## TDD Gate Compliance

- Task 1 RED `c140284` precedes GREEN `24d9e65`.
- Task 2 RED `7f26be4` precedes GREEN `ac9d931`.
- Task 3 RED `1d74eb1` precedes GREEN `2c062f8`.

## Verification

- Focused recovery suites: 44 tests passed.
- Focused real-stack recovery/lifecycle/overflow run: 4 Playwright tests passed.
- Changed-file ESLint: passed.
- TypeScript project build: passed.
- `./tooling/test-phase-1.sh --run`: repository integrity, runtime preflight, 105 ExUnit tests, contract drift, TypeScript, 101 Vitest tests, and 15 Playwright tests passed.
- Threat mitigations: resumed reads remain server-session scoped; keyed continuations deduplicate and drain exactly once; no private values enter diagnostics; collection state is fenced on authentication clear.

## Known Stubs

None. Empty collections, nullable refs, and empty form values found by the stub scan are operational state or test fixtures, not shipped placeholders.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- The protected browser read matrix and shared continuation coordinator are ready for final phase verification.
- No high-severity threat remains open; the two pre-existing lint findings remain explicitly deferred.

## Self-Check: PASSED

- All 12 implementation/test files and this summary exist.
- All 10 task, TDD, and verification-hardening commits are present in Git history.

---
*Phase: KPL-01-one-trustworthy-task*
*Completed: 2026-08-31*
