---
phase: KPL-01-one-trustworthy-task
plan: 23
subsystem: session-recovery
tags: [react, phoenix, playwright, postgresql, authentication, uncertain-delivery]

requires:
  - phase: KPL-01-08
    provides: Tracked browser sessions, recent authentication, CSRF rotation, and routed session administration
  - phase: KPL-01-17
    provides: Credentialed compile-gated after-commit fault injection on authenticated mutation routes
provides:
  - Authoritative read reconciliation for uncertain session rename, revoke, and current-session logout
  - Persistent read-only recovery controls that never resend an uncertain session mutation
  - Test-only recent-auth DELETE fault injection ordered after authentication, origin, CSRF, and recent-auth checks
  - Real PostgreSQL/Phoenix/Chromium proof for all three after-commit-loss session outcomes
affects: [phase-1-verification, browser-auth, desktop-session-management, iphone-session-management]

actuals:
  tokens: 6706
  tasks: 2
  commits: 5

tech-stack:
  added: []
  patterns: [authoritative session reconciliation, read-only uncertain-outcome retry, compile-gated recent-auth fault seam]

key-files:
  created:
    - apps/web/src/features/sessions/session-list.test.tsx
    - apps/web/e2e/session-reconciliation.spec.ts
  modified:
    - apps/web/src/features/sessions/SessionList.tsx
    - apps/server/lib/keepling_web/router.ex
    - apps/server/test/keepling_web/test_fault_test.exs

key-decisions:
  - "Session administration reserves definitive changed, unchanged, revoked, active, and logged-out outcomes for authoritative inventory or authentication-probe evidence."
  - "The recent-auth session DELETE route gains the credentialed fault plug only in test and only after authentication, trusted-origin/CSRF, and recent-auth authorization have completed."

patterns-established:
  - "Uncertain session write: retain the intended action, fence conflicting controls, reconcile by read, and let Check again repeat only that read."
  - "Current-session logout: only authentication_required from the existing cookie-authenticated session probe clears browser authentication."

requirements-completed: [SRV-01, SRV-03, WEB-02, QUAL-01]

coverage:
  - id: D1
    description: "Rename and other-session revoke response loss reconcile account-scoped authoritative inventory before reporting changed, unchanged, revoked, or active state."
    requirement: SRV-03
    verification:
      - kind: automated_ui
        ref: "apps/web/src/features/sessions/session-list.test.tsx#uncertain session administration"
        status: pass
      - kind: e2e
        ref: "apps/web/e2e/session-reconciliation.spec.ts#@session-reconciliation"
        status: pass
    human_judgment: false
  - id: D2
    description: "Current-session logout response loss probes authentication and clears account-scoped browser state only when the server proves the session is gone."
    requirement: SRV-01
    verification:
      - kind: automated_ui
        ref: "apps/web/src/features/sessions/session-list.test.tsx#logout probe cases"
        status: pass
      - kind: e2e
        ref: "apps/web/e2e/session-reconciliation.spec.ts#@session-reconciliation"
        status: pass
    human_judgment: false
  - id: D3
    description: "The session DELETE after-commit seam exists only in test and follows every authentication, CSRF/origin, and recent-auth plug while production keeps the original four-pipeline route."
    requirement: QUAL-01
    verification:
      - kind: integration
        ref: "apps/server/test/keepling_web/test_fault_test.exs"
        status: pass
      - kind: other
        ref: "./tooling/test-phase-1.sh --run production-routes lane"
        status: pass
    human_judgment: false

duration: 8min
completed: 2026-08-31
status: complete
---

# Phase KPL-01 Plan 23: Session Administration Recovery Summary

**Authoritative inventory and authentication probes make session rename, revoke, and logout honest after real committed-response loss without replaying writes**

## Performance

- **Duration:** 8 min
- **Started:** 2026-08-31T22:57:41Z
- **Completed:** 2026-08-31T23:05:43Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments

- Added an explicit session-action recovery state that retains the intended rename, revoke, or logout while fencing every conflicting session control.
- Reconciled uncertain rename/revoke delivery with the authenticated Sessions inventory and current-session logout with the existing cookie-authenticated session probe.
- Reserved definitive outcome copy for proved server truth; unreadable reconciliation remains visibly unknown with a named read-only Check again action.
- Extended the compile-gated test fault router so recent-auth session DELETE requests traverse the fault plug only after authentication, trusted-origin/CSRF, and recent-auth authorization.
- Proved one real after-commit PATCH, DELETE, and logout POST against PostgreSQL/Phoenix/Chromium, with no automatic duplicate write.

## Task Commits

1. **Task 1 RED: Add failing session reconciliation proof** - `d897b28` (test)
2. **Task 1 GREEN: Reconcile uncertain session actions** - `473b83b` (fix)
3. **Task 2 RED: Add failing recent-auth fault route proof** - `386c3b5` (test)
4. **Task 2 GREEN: Gate recent-auth faults to tests** - `4ccff4b` (fix)
5. **Task 2 proof: Prove session response-loss recovery** - `65de1e6` (test)

## Files Created/Modified

- `apps/web/src/features/sessions/SessionList.tsx` - Retained action state, authoritative reconciliation, unknown-state copy, read-only recovery, and control fencing.
- `apps/web/src/features/sessions/session-list.test.tsx` - Eight rename, revoke, logout, unchanged/active, unknown, and read-only retry component cases.
- `apps/server/lib/keepling_web/router.ex` - Test-only recent-auth mutation pipeline with the fault plug last.
- `apps/server/test/keepling_web/test_fault_test.exs` - Exact test/production pipeline split and compiled route proof.
- `apps/web/e2e/session-reconciliation.spec.ts` - Real-stack after-commit-loss proof for session rename, revoke, and current-session logout.

## Decisions Made

- Treat inventory presence, absence, and exact label equality as the only authority for rename/revoke result copy; a second read failure or an unexpected third state stays explicitly unknown.
- Treat only `authentication_required` from `GET /api/v1/session` as proof that current-session logout committed. A successful probe means still signed in; any unreadable probe remains unknown.
- Reuse the existing compile-gated `:test_fault` plug after `:recent_auth`; no production route, schema, contract, or canonical persistence change is necessary.

## Deviations from Plan

None - plan executed exactly as written.

## TDD Gate Compliance

- Task 1 RED commit `d897b28` failed 8/8 because the existing component inferred unchanged/active state from missing responses and never probed logout authentication. GREEN commit `473b83b` made all 8/8 focused cases pass; the tracer feedback gate reran them successfully before expansion.
- Task 2 RED commit `386c3b5` produced the sole full-suite failure at 104/105 because the recent-auth test pipeline did not exist. GREEN commit `4ccff4b` restored 105/105 and passed production route isolation.
- The real-stack expansion commit `65de1e6` exercises the production behavior already established by the two RED/GREEN cycles and passed 1/1 after correcting test-locator assertions; no artificial production regression was introduced.

## Issues Encountered

- The focused Mix test requires repository-owned disposable PostgreSQL configuration even though the route assertion itself does not query storage. The full Phase 1 harness supplied the correct environment and produced the intended single RED failure.
- The first Playwright run used a non-unique live-region locator, and the second queried the intentionally revoked secondary session after revocation. Both were test-only assertion issues; exact copy lookup and an authenticated pre-logout inventory check corrected them without changing production behavior.

## Known Stubs

None - the mechanical scan found only empty request-collection arrays in the Playwright proof and nullable operational state checks. No TODO, FIXME, skipped test, placeholder production behavior, mock production data source, hardcoded empty rendered value, or unrun verification remains.

## Threat Surface

- T-KPL01-G23-01 is mitigated by the existing cookie-authenticated session probe; only its `authentication_required` problem triggers `onLoggedOut`.
- T-KPL01-G23-02 is mitigated by account-scoped inventory reconciliation and exact label/presence checks before outcome copy.
- T-KPL01-G23-03 is mitigated by retained checking/unknown state and a named Check again action that issues only a read.
- T-KPL01-G23-04 continues to rely on authenticated account scope and coarse session fields; no task content, token, fingerprint, or arbitrary identifier logging was added.
- T-KPL01-G23-05 is mitigated by user-triggered bounded read retries and control fencing during each check.
- The planned test-only recent-auth route seam is compile-gated and ordered after every authorization plug. The production route inspection passed, and no unmodeled endpoint, schema, file-access pattern, telemetry field, or high-severity open mitigation remains.

## Verification Evidence

- Focused session reconciliation: 1 file and 8/8 Vitest cases passed.
- Existing authentication/session regression suite plus new focused suite: 2 files and 22/22 Vitest cases passed.
- Dedicated real-stack session recovery: 1/1 Chromium case passed against disposable PostgreSQL 18.6 and Phoenix, with exactly one PATCH, one DELETE, and one logout POST.
- Changed-file ESLint and the TypeScript project build passed.
- `./tooling/test-phase-1.sh --run`: repository integrity and runtime preflight passed; 105/105 ExUnit, contract drift, TypeScript, 110/110 Vitest, and 18/18 Chromium tests passed; privacy and production-isolation lanes passed.

## User Setup Required

None - no dependency, external service, secret, migration, or operator action was added.

## Next Phase Readiness

- Phase KPL-01 now has real after-commit-loss coverage for the remaining session administration gap in addition to authenticated reads, conflict resolution, and Today ordering.
- Session mutations have an inspectable recovery pattern suitable for later offline clients without adding browser-local canonical state.
- No high-severity mitigation assigned to Plan 01-23 remains open.

## Self-Check: PASSED

- All five implementation/proof files and this summary exist at their recorded paths.
- Task commits `d897b28`, `473b83b`, `386c3b5`, `4ccff4b`, and `65de1e6` resolve in repository history in the documented order.
- Required actuals, requirement coverage, TDD evidence, stub scan, threat mitigations, and fresh complete Phase 1 verification are present.

---
*Phase: KPL-01-one-trustworthy-task*
*Completed: 2026-08-31*
