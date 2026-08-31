---
phase: KPL-01-one-trustworthy-task
plan: 21
subsystem: conflict-resolution-recovery
tags: [react, playwright, postgresql, phoenix, idempotency, conflict-resolution]

requires:
  - phase: KPL-01-16
    provides: Persisted conflicts, exact-revision resolution, and acknowledgement-gated browser reconciliation
  - phase: KPL-01-17
    provides: Immutable prepared submissions, durable receipt lookup, and credentialed after-commit fault injection
provides:
  - One exact-submission lock for every conflict-resolution action while delivery remains nonterminal
  - Real PostgreSQL/Phoenix/Chromium proof that a committed resolution survives response loss without replacement identity or effect
affects: [KPL-01-22, verification, desktop-offline, iphone-offline]

actuals:
  tokens: 3111
  tasks: 2
  commits: 3

tech-stack:
  added: []
  patterns: [exact-submission UI lock, immutable conflict choice, receipt-first after-commit reconciliation]

key-files:
  created:
    - apps/web/e2e/conflict-resolution-recovery.spec.ts
  modified:
    - apps/web/src/features/tasks/ConflictResolver.tsx
    - apps/web/src/features/tasks/conflict-resolver.test.tsx

key-decisions:
  - "The exact submission snapshot is the authority for locking conflict choices, Save resolution, and Keep editing through in-flight, unknown, and authentication-required states."

patterns-established:
  - "Nonterminal conflict resolution: once dispatched, mine/current selections and mutation identity remain immutable until matching acknowledgement or verified terminal rejection."
  - "Response-loss proof: query the original durable receipt after a real after-commit disconnect and assert both one request body and one canonical revision effect."

requirements-completed: [SRV-03, WEB-02, QUAL-01]

coverage:
  - id: D1
    description: "Deferred conflict-resolution responses disable every choice, escape, and duplicate-save control while retaining the first prepared request."
    requirement: WEB-02
    verification:
      - kind: automated_ui
        ref: "apps/web/src/features/tasks/conflict-resolver.test.tsx#freezes-the-dispatched-selection"
        status: pass
    human_judgment: false
  - id: D2
    description: "A real after-commit response loss reconciles the first accepted mine/current selection by its original receipt without a replacement request or canonical effect."
    requirement: SRV-03
    verification:
      - kind: e2e
        ref: "apps/web/e2e/conflict-resolution-recovery.spec.ts"
        status: pass
    human_judgment: false
  - id: D3
    description: "The credentialed fault remains test-only and all conflict identity checks execute through authenticated semantic routes."
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

# Phase KPL-01 Plan 21: Conflict Resolution Recovery Summary

**Immutable conflict choices across deferred, lost, and authentication-interrupted responses, with real after-commit PostgreSQL reconciliation by the original receipt**

## Performance

- **Duration:** 5 min
- **Started:** 2026-08-31T22:42:00Z
- **Completed:** 2026-08-31T22:46:45Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments

- Derived one `resolutionLocked` predicate from the exact submission snapshot and applied it to mine/current selections, Save resolution, and Keep editing for every in-flight, unknown, and authentication-required state.
- Removed the reachable nonterminal fencing path: attempted interaction can no longer clear recovery, replace the selected values, or mint a second mutation identity after dispatch.
- Added a real-stack Chromium scenario that creates a persisted edit conflict, commits the first resolution in PostgreSQL, loses the HTTP response at the real Phoenix boundary, attempts replacement interaction, and reconciles the original durable receipt exactly once.
- Passed the complete Phase 1 server, contract, browser-unit, typecheck, privacy, production-isolation, and 16-case real-stack browser gate.

## Task Commits

1. **Task 1 RED: Add failing dispatched-resolution lock proof** - `1582739` (test)
2. **Task 1 GREEN: Freeze dispatched conflict resolution** - `0a1fdc5` (fix)
3. **Task 2: Prove real conflict response-loss recovery** - `2acf2e4` (test)

## Files Created/Modified

- `apps/web/src/features/tasks/ConflictResolver.tsx` - Exact-snapshot nonterminal lock shared by all resolution-changing controls and guarded choice handling.
- `apps/web/src/features/tasks/conflict-resolver.test.tsx` - Deferred-promise regression plus explicit unknown-delivery and authentication-required lock assertions.
- `apps/web/e2e/conflict-resolution-recovery.spec.ts` - Authenticated real-stack conflict creation, credentialed after-commit loss, immutable choice/identity checks, durable receipt lookup, and canonical task reconciliation.

## Decisions Made

- The exact submission state, rather than a collection of independently maintained UI flags, is the authority for whether a dispatched resolution may still be changed.
- Terminal acknowledgement closes the resolver; verified terminal rejection unlocks selection so a subsequent user choice can intentionally create a new attempt. Unknown delivery and authentication interruption never do.
- The real-stack proof asserts both transport identity and canonical effect: one resolution request body, one stored receipt for that mutation, and exactly one revision increment containing the first selected value.

## Deviations from Plan

None - plan scope and behavior were implemented exactly as specified.

## TDD Gate Compliance

- Task 1 RED commit `1582739` failed 1/8 because mine/current controls remained enabled during a deferred request. GREEN commit `0a1fdc5` made all 8/8 focused cases pass and the tracer feedback gate reran them successfully.
- Task 2 is a test-only real-stack expansion over the production behavior completed by Task 1. Its full Playwright scenario passed on its first run, so no artificial failing implementation was introduced; the Task 1 RED case proves the same replacement-interaction defect before the fix.

## Known Stubs

None - no TODO, FIXME, skipped test, placeholder production behavior, mock production data source, hardcoded empty rendered data, or unrun verification remains in the three realized files. Empty arrays and nullable refs found by the mechanical scan are local test accumulators and exact-submission state, not UI stubs.

## Threat Surface

- T-KPL01-G21-01 is mitigated by the exact-state lock and guarded choice handler across all three nonterminal states.
- T-KPL01-G21-02 is mitigated by immutable request bytes and mutation identity, durable original-receipt lookup, matching acknowledgement checks, and the after-commit-loss real-stack proof.
- T-KPL01-G21-03 continues to rely on the existing session-derived account scope; the E2E uses only authenticated semantic routes.
- T-KPL01-G21-04 continues to render conflict values as React plain text within the existing bounded disclosure UI.
- No network endpoint, authentication path, file-access pattern, schema change, telemetry field, or other security surface outside the plan threat model was introduced. No high-severity mitigation remains open.

## Verification Evidence

- Focused conflict resolver: 1 file and 8/8 Vitest cases passed.
- Dedicated real-stack recovery: 1/1 Chromium case passed against owned PostgreSQL 18.6 and Phoenix.
- Full server suite: 105/105 ExUnit tests passed.
- Contract drift and browser TypeScript checks passed.
- Full browser unit suite: 11 files and 102/102 Vitest cases passed.
- Full real-stack browser suite: 16/16 Chromium cases passed, including the new conflict recovery case.
- `./tooling/test-phase-1.sh --run` ended with `Phase 1 server, contract, browser, privacy, and production-isolation lanes passed`.

## User Setup Required

None - no dependency, external service, secret, migration, or operator action was added.

## Next Phase Readiness

- Plan 01-22 can consume a conflict resolver whose dispatched choice and identity remain inspectable and recoverable across every nonterminal delivery state.
- The verifier's P16.2 response-loss gap now has both controllably deferred component proof and real after-commit PostgreSQL/Phoenix/Chromium evidence.

## Self-Check: PASSED

- All three implementation/proof files and this summary exist at their recorded paths.
- Task commits `1582739`, `0a1fdc5`, and `2acf2e4` resolve in repository history.
- Fresh focused, dedicated E2E, and complete Phase 1 verification passed after the final code change; the realized diff and summary pass `git diff --check`.

---
*Phase: KPL-01-one-trustworthy-task*
*Completed: 2026-08-31*
