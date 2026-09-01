---
phase: KPL-01-one-trustworthy-task
plan: 24
subsystem: security-hardening
tags: [phoenix, csp, postgres, react, authentication, tdd]

requires:
  - phase: KPL-01-23
    provides: authoritative session recovery, security audit findings, and the complete Phase 1 gate
provides:
  - restrictive same-origin Content-Security-Policy at the Phoenix endpoint boundary
  - finite timeout enforcement for every PostgreSQL task-view operation
  - route-owned authentication continuation disposal with late-settlement fencing
  - executable closure evidence for all remaining KPL-01 security findings
affects: [phase-1-security, browser-runtime, task-views, authentication-recovery]

actuals:
  tokens: 9492
  tasks: 3
  commits: 9

tech-stack:
  added: []
  patterns:
    - endpoint security policy before static and router plugs
    - one positive application timeout consumed by all adapter SQL wrappers
    - owner-scoped continuation registries with generation-aware disposal

key-files:
  created:
    - apps/server/lib/keepling_web/security_headers.ex
    - apps/server/test/keepling_web/security_headers_test.exs
    - apps/web/src/test/security-content.test.tsx
  modified:
    - apps/server/config/config.exs
    - apps/server/lib/keepling/adapters/postgres/task_views.ex
    - apps/server/lib/keepling_web/endpoint.ex
    - apps/server/test/keepling/adapters/postgres/task_views_test.exs
    - apps/web/src/App.tsx
    - apps/web/src/app/AuthProvider.tsx
    - apps/web/src/app/routes.tsx
    - apps/web/src/features/auth/auth.test.tsx
    - .planning/phases/KPL-01-one-trustworthy-task/01-SECURITY.md

key-decisions:
  - "Apply one explicit same-origin CSP before Plug.Static so the application shell and API share the same restrictive execution boundary."
  - "Route every TaskViews transaction and SQL call through wrappers consuming the same positive 10-second production timeout."
  - "Dispose authentication continuations by route owner while fencing both authentication generation and owner liveness, including React Strict Mode effect rehearsal."

patterns-established:
  - "Browser defense in depth: canonical values render as React text and Phoenix independently constrains resource execution."
  - "Database bounds are proven with a real PostgreSQL cancellation rather than a mocked timeout option."
  - "Async UI recovery checks lifetime again after settlement before publishing state."

requirements-completed: [SRV-01, SRV-02, WEB-01, WEB-02, QUAL-01]

coverage:
  - id: D1
    description: "Production browser responses carry a restrictive CSP while hostile task, activity, and conflict values remain inert text."
    requirement: WEB-02
    verification:
      - kind: integration
        ref: "apps/server/test/keepling_web/security_headers_test.exs"
        status: pass
      - kind: automated_ui
        ref: "apps/web/src/test/security-content.test.tsx"
        status: pass
    human_judgment: false
  - id: D2
    description: "Every PostgreSQL task-view operation uses a finite timeout and maps real cancellation to the existing infrastructure-failure contract."
    requirement: SRV-02
    verification:
      - kind: integration
        ref: "apps/server/test/keepling/adapters/postgres/task_views_test.exs#cancels delayed PostgreSQL work"
        status: pass
    human_judgment: false
  - id: D3
    description: "Route-owned authentication continuations are disposed on route change or unmount without canceling live owners."
    requirement: WEB-01
    verification:
      - kind: unit
        ref: "apps/web/src/features/auth/auth.test.tsx#owner disposal and late settlement"
        status: pass
      - kind: integration
        ref: "./tooling/test-phase-1.sh --run"
        status: pass
    human_judgment: false
  - id: D4
    description: "The Phase KPL-01 STRIDE register has no remaining open threats."
    requirement: QUAL-01
    verification:
      - kind: other
        ref: ".planning/phases/KPL-01-one-trustworthy-task/01-SECURITY.md#threats_open: 0"
        status: pass
    human_judgment: false

duration: 20min
completed: 2026-08-31
status: complete
---

# Phase KPL-01 Plan 24: Security Hardening Summary

**Restrictive endpoint CSP, real PostgreSQL query cancellation, and route-lifetime authentication fencing close all 70 Phase 1 threats without weakening established task or recovery behavior.**

## Performance

- **Duration:** 20 min
- **Started:** 2026-09-01T00:49:38Z
- **Completed:** 2026-09-01T01:09:05Z
- **Tasks:** 3
- **Files modified:** 12

## Accomplishments

- Enforced a least-permissive same-origin CSP on static and API responses and proved hostile canonical values stay visible but inert in real UI surfaces.
- Bounded all TaskViews transactions and SQL calls with one positive application timeout, including a real `pg_sleep` cancellation mapped to `:infrastructure_failure`.
- Added route-owner continuation registration and disposal that excludes abandoned work before and after asynchronous settlement while preserving live ordering, replacement, and logout behavior.
- Re-ran the full Phase 1 gate and the security audit; all 70 registered threats are closed and `threats_open: 0`.

## Task Commits

Each TDD task was committed atomically through RED and GREEN:

1. **Task 1 RED: content-boundary proof** — `e7b068e` (test)
2. **Task 1 GREEN: endpoint CSP** — `8883ef7` (feat)
3. **Task 2 RED: task-view timeout proof** — `9b51cea` (test)
4. **Task 2 GREEN: bounded task-view reads** — `a8973ac` (feat)
5. **Task 3 RED: routed continuation disposal proof** — `b13a19c` (test)
6. **Task 3 GREEN: route-owned continuation disposal** — `8c33500` (feat)
7. **Task 3 correctness fix: Strict Mode scope lifetime** — `5e3d87e` (fix)

**Security audit:** `5b56f9c` (docs: verified 70/70 threats closed)

## Files Created/Modified

- `apps/server/lib/keepling_web/security_headers.ex` — central restrictive Content-Security-Policy plug.
- `apps/server/lib/keepling_web/endpoint.ex` — installs security headers before static serving and routing.
- `apps/server/test/keepling_web/security_headers_test.exs` — static, API, and production-policy assertions.
- `apps/web/src/test/security-content.test.tsx` — hostile task, activity, and conflict rendering proof.
- `apps/server/config/config.exs` — positive 10-second task-view query bound.
- `apps/server/lib/keepling/adapters/postgres/task_views.ex` — bounded transaction/query wrappers and test-only delayed-query seam.
- `apps/server/test/keepling/adapters/postgres/task_views_test.exs` — real PostgreSQL timeout and stable failure proof.
- `apps/web/src/app/AuthProvider.tsx` — owner-scoped registration, disposal, and generation/liveness fencing.
- `apps/web/src/app/routes.tsx` — pathname-owned scope lifecycle with Strict Mode-safe cleanup.
- `apps/web/src/App.tsx` — routes authenticated content through the scoped recovery callback.
- `apps/web/src/features/auth/auth.test.tsx` — unmount, route change, late settlement, idempotence, replacement, and Strict Mode coverage.
- `.planning/phases/KPL-01-one-trustworthy-task/01-SECURITY.md` — re-audited register with all 70 threats closed.

## Decisions Made

- Kept CSP policy independent of development-only Vite origins and excluded wildcard, inline-script, and eval permissions.
- Kept existing task-view result semantics intact by translating database cancellation through the established content-free `:infrastructure_failure` boundary.
- Used owner liveness in addition to auth generation so route disposal cannot cancel unrelated work or allow a late Promise to publish into an abandoned surface.

## TDD Gate Compliance

- Task 1 RED failed because no endpoint security-header plug existed; GREEN passed 2 server CSP tests and 3 hostile-render tests.
- Task 2 RED failed because TaskViews had no finite timeout seam; GREEN passed 7 adapter tests including real PostgreSQL cancellation.
- Task 3 RED failed because continuation ownership/disposal did not exist; GREEN passed the focused auth suite and typecheck.
- RED commits precede their corresponding GREEN commits in git history.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Preserved route scopes through React Strict Mode effect rehearsal**
- **Found during:** Task 3 full-gate verification
- **Issue:** Strict Mode's setup/cleanup rehearsal disposed the live route scope before the first real interaction, so a mounted surface could not resume its continuation.
- **Fix:** Added a failing Strict Mode regression test and generation-aware deferred cleanup that ignores rehearsal cleanup while still disposing an actual old pathname scope.
- **Files modified:** `apps/web/src/app/routes.tsx`, `apps/web/src/features/auth/auth.test.tsx`
- **Verification:** focused auth tests, TypeScript typecheck, and the full Phase 1 gate pass.
- **Committed in:** `5e3d87e`

---

**Total deviations:** 1 auto-fixed (1 Rule 1 bug)
**Impact on plan:** The fix was required for correct React production behavior and did not expand scope.

## Issues Encountered

- An abandoned disposable PostgreSQL process from an earlier RED command temporarily held the Playwright test port after a zsh trap used the shell's read-only `status` name. The exact disposable cluster was identified and stopped; no repository files or user database were touched.
- One intermediate Playwright run hit the existing session-revocation timing edge. An immediate fresh Playwright run passed 18/18, and the final canonical full gate also passed 18/18.

## Verification

- Focused CSP gate: 2 ExUnit tests and 3 Vitest tests passed.
- Focused TaskViews gate: 7 ExUnit tests passed, including actual database cancellation.
- Focused authentication gate: 19 Vitest tests passed and TypeScript typecheck passed.
- Canonical `./tooling/test-phase-1.sh --run`: repository integrity, 108 ExUnit tests, contract drift, TypeScript, 134 Vitest tests, and 18 Playwright tests all passed.
- Security re-audit: 70/70 threats closed; `threats_open: 0`.

## Known Stubs

None. The scan found only intentional nullable state and empty test collections; no placeholder behavior, skipped test, or incomplete production data path was introduced.

## Threat Surface

No unplanned security surface was introduced. CSP enforcement, database timeout handling, and authentication continuation lifetime are the three boundaries declared in the plan-time threat model, and the re-audit verified each mitigation.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Phase KPL-01 now has a green full-stack gate and a verified security register with no open threats. No blocker remains for the phase-level verification workflow.

## Self-Check: PASSED

All created artifacts exist, all eight pre-metadata commits resolve in git history, and the summary passes `git diff --check`.

---
*Phase: KPL-01-one-trustworthy-task*
*Completed: 2026-08-31*
