---
phase: KPL-01-one-trustworthy-task
plan: 22
subsystem: today-order-recovery
tags: [react, playwright, postgresql, phoenix, idempotency, uncertain-delivery]

requires:
  - phase: KPL-01-13
    provides: Server-owned Today ordering, exact move receipts, and browser receipt lookup
  - phase: KPL-01-17
    provides: Immutable exact-submission state machine and credentialed after-commit faults
provides:
  - Global Today ordering lock across in-flight, unknown, and authentication-required delivery states
  - Guarded move entry point that retains the original exact mutation until a terminal result
  - Real PostgreSQL/Phoenix/Chromium proof of one accepted move after response loss
affects: [phase-1-verification, desktop-offline, iphone-offline, synchronization]

actuals:
  tokens: 3106
  tasks: 2
  commits: 3

tech-stack:
  added: []
  patterns: [exact-submission global lock, terminal-only release, receipt-first order reconciliation]

key-files:
  created:
    - apps/web/e2e/today-order-recovery.spec.ts
  modified:
    - apps/web/src/features/lists/TaskList.tsx
    - apps/web/src/features/lists/task-lists.test.tsx

key-decisions:
  - "Today ordering uses the exact submission snapshot as its global lock authority; transient progress presentation never decides whether another move may begin."

patterns-established:
  - "Unresolved Today order: disable every ordering control and guard the command entry point until matching acknowledgement or verified terminal rejection clears the retained submission."
  - "After-commit order proof: compare the durable original receipt, returned order revision, and full canonical order while asserting one transport command and no duplicate task identity."

requirements-completed: [GTD-03, SRV-03, WEB-02, QUAL-01]

coverage:
  - id: D1
    description: "Every Today Earlier/Later control and the move entry point remain globally locked while one exact move is in flight, unknown, or authentication-required."
    requirement: WEB-02
    verification:
      - kind: automated_ui
        ref: "apps/web/src/features/lists/task-lists.test.tsx#globally locks Today moves and looks up the original identity after response loss"
        status: pass
    human_judgment: false
  - id: D2
    description: "A committed Today move whose response is lost remains recoverable by its original mutation identity and produces exactly one canonical order change."
    requirement: SRV-03
    verification:
      - kind: e2e
        ref: "apps/web/e2e/today-order-recovery.spec.ts#@today-order-recovery"
        status: pass
    human_judgment: false
  - id: D3
    description: "The global move lock preserves semantic ordering, authentication recovery, contract compatibility, privacy, and production fault isolation across the full Phase 1 boundary."
    requirement: QUAL-01
    verification:
      - kind: other
        ref: "./tooling/test-phase-1.sh --run"
        status: pass
    human_judgment: false

duration: 5min
completed: 2026-08-31
status: complete
---

# Phase KPL-01 Plan 22: Today Order Recovery Summary

**One globally locked exact Today move survives real after-commit response loss and reconciles its original durable receipt into one canonical order change**

## Performance

- **Duration:** 5 min
- **Started:** 2026-08-31T22:49:58Z
- **Completed:** 2026-08-31T22:55:02Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments

- Replaced transient `movingTaskId` authorization with one exact-submission lock shared by all Today Earlier/Later controls.
- Guarded `move()` before identity allocation so programmatic interaction cannot replace an unresolved request.
- Retained the original request through unknown and authentication-required recovery, releasing only after matching acknowledgement or terminal rejection.
- Added a fresh-stack Playwright scenario that commits through PostgreSQL, loses the Phoenix response, refuses a forced second-row action, checks the original receipt, and proves one duplicate-free canonical swap.

## Task Commits

1. **Task 1 RED: Add failing Today move lock proof** - `2c6f2ee` (test)
2. **Task 1 GREEN: Retain the unresolved Today move** - `9d87afd` (fix)
3. **Task 2: Prove Today move response-loss recovery** - `7da9596` (test)

## Files Created/Modified

- `apps/web/src/features/lists/TaskList.tsx` - Exact-snapshot global order lock, guarded entry point, and terminal-only release.
- `apps/web/src/features/lists/task-lists.test.tsx` - Deferred, unknown, authentication-required, replacement-attempt, and terminal-release component assertions.
- `apps/web/e2e/today-order-recovery.spec.ts` - Credentialed real after-commit response-loss, receipt, revision, canonical order, and duplicate-effect proof.

## Decisions Made

- The exact submission state is the authority for both visible control locking and imperative replacement refusal. `movingTaskId` remains presentation-only for the initiating row's progress message.
- The real-stack proof validates both sides of recovery: one observed command/identity at the browser boundary and one revisioned, duplicate-free canonical swap from PostgreSQL.

## Deviations from Plan

None - plan scope and behavior were implemented exactly as specified.

## TDD Gate Compliance

- Task 1 RED commit `2c6f2ee` failed 1/9 because every Today move control re-enabled after response loss. GREEN commit `9d87afd` made 9/9 focused cases pass, and the tracer feedback gate reran successfully.
- Task 2 is a test-only real-stack expansion over Task 1's now-complete production behavior. Its 1/1 Playwright case passed on first execution; no artificial production regression was introduced to manufacture another RED state.

## Issues Encountered

- Changed-file ESLint continues to report the pre-existing `react-hooks/set-state-in-effect` finding in `TaskList.tsx` line 195, already recorded by Plan 01-20. Lint with only that known rule excluded passes for both files changed by Task 1; this plan did not modify the effect.

## Known Stubs

None - empty arrays and nullable exact-submission/test values found by the mechanical scan are operational state or test accumulators, not rendered placeholders. No TODO, FIXME, skipped test, mock production data, or unrun verification remains.

## Threat Surface

- T-KPL01-G22-01 is mitigated by the exact-state global lock, disabled controls, and first-line `move()` guard.
- T-KPL01-G22-02 is mitigated by immutable mutation identity, durable receipt lookup, and real after-commit PostgreSQL/Phoenix/Chromium proof.
- T-KPL01-G22-03 is mitigated by retained Check again/sign-in recovery actions and terminal-only lock release.
- No endpoint, authentication path, schema, file-access pattern, telemetry field, or other security surface outside the plan threat model was introduced. No high-severity mitigation remains open.

## Verification Evidence

- Focused TaskList suite: 1 file and 9/9 Vitest cases passed.
- Dedicated Today recovery: 1/1 Chromium case passed against fresh PostgreSQL 18.6 and Phoenix.
- Changed-code ESLint passed with only the pre-existing `react-hooks/set-state-in-effect` rule excluded; TypeScript project checking passed.
- `./tooling/test-phase-1.sh --run`: repository integrity and runtime preflight passed; 105/105 ExUnit, contract drift, TypeScript, 102/102 Vitest, and 17/17 Chromium tests passed; privacy and production-isolation lanes passed.

## User Setup Required

None - no dependency, external service, secret, migration, or operator action was added.

## Next Phase Readiness

- Plan 01-23 can close the remaining uncertain session-administration gap on top of a Today order path that no longer permits replacement identities.
- The verifier's unresolved Today replacement and after-commit evidence gaps are closed with component and real-stack proof.

## Self-Check: PASSED

- All three implementation/proof files and this summary exist at their recorded paths.
- Task commits `2c6f2ee`, `9d87afd`, and `7da9596` resolve in Git history in the documented order.
- Required actuals, requirement coverage, stub scan, threat mitigations, and fresh complete Phase 1 verification are present.

---
*Phase: KPL-01-one-trustworthy-task*
*Completed: 2026-08-31*
