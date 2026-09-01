---
phase: KPL-01-one-trustworthy-task
plan: 14
subsystem: task-lifecycle
tags: [elixir, phoenix, postgresql, openapi, react, accessibility, idempotency]

requires:
  - phase: KPL-01-13
    provides: Deterministic active and Completed projections with acknowledged list reconciliation patterns
provides:
  - Revision-aware complete and reopen semantic commands with narrow lifecycle rebasing
  - Exact account-scoped receipts, accepted activity facts, and stable lifecycle conflicts
  - Acknowledgement-gated browser controls with Completed-today placement and authoritative reopen destinations
affects: [KPL-01-15, KPL-01-16, KPL-01-17, sync, mcp, desktop-offline, iphone-offline]

actuals:
  tokens: 16944
  tasks: 2
  commits: 4

tech-stack:
  added: []
  patterns: [semantic lifecycle transition, lifecycle-only rebase, exact acknowledgement reconciliation, authoritative destination refresh]

key-files:
  created:
    - apps/server/test/keepling/application/task_lifecycle_test.exs
    - packages/contracts/vectors/lifecycle.json
    - apps/web/src/features/tasks/LifecycleActions.tsx
    - apps/web/src/features/tasks/lifecycle.test.tsx
  modified:
    - apps/server/lib/keepling/domain/task.ex
    - apps/server/lib/keepling/application/commands.ex
    - apps/server/lib/keepling/adapters/postgres/command_store.ex
    - apps/server/lib/keepling_web/controllers/command_controller.ex
    - apps/server/lib/keepling_web/router.ex
    - packages/contracts/openapi/keepling.yaml
    - packages/contracts/generated/keepling.ts
    - apps/web/src/api/keepling.ts
    - apps/web/src/app/routes.tsx
    - apps/web/src/features/lists/TaskList.tsx

key-decisions:
  - "Lifecycle staleness is scoped to the last accepted complete/reopen revision, so unrelated edits may rebase while opposing lifecycle intent returns a durable completed_at conflict."
  - "Completion preserves inbox_state, removes the task from active projections, and reopen derives current projection membership from preserved canonical task fields."
  - "Browser rows remain visible until task and mutation identities match the exact acknowledgement; reopen destinations are read back from authoritative views rather than predicted in the client."

patterns-established:
  - "Lifecycle truth: already-achieved intent is already_satisfied, unrelated revision drift may rebase, and newer opposing lifecycle intent conflicts on completed_at."
  - "Lifecycle UI truth: retain the row and stable submission through uncertainty, reconcile only an exact acknowledgement, then restore focus next, previous, or heading."

requirements-completed: [GTD-05, SRV-02, SRV-03, WEB-01, WEB-02]

coverage:
  - id: D1
    description: "Complete and reopen return stable replay, already_satisfied, unrelated-edit rebase, and opposing-intent conflict results."
    requirement: GTD-05
    verification:
      - kind: integration
        ref: "apps/server/test/keepling/application/task_lifecycle_test.exs"
        status: pass
      - kind: integration
        ref: "packages/contracts/vectors/lifecycle.json"
        status: pass
    human_judgment: false
  - id: D2
    description: "Accepted lifecycle transitions atomically persist one task revision, one activity fact, one receipt, and correct active/Completed membership."
    requirement: SRV-02
    verification:
      - kind: integration
        ref: "apps/server/test/keepling/application/task_lifecycle_test.exs#persists exact lifecycle receipts activity and projection destinations"
        status: pass
    human_judgment: false
  - id: D3
    description: "Lifecycle routes are account-scoped, closed-schema commands with expected revision, stable mutation identity, and generated contract parity."
    requirement: SRV-03
    verification:
      - kind: integration
        ref: "packages/contracts/openapi/keepling.yaml"
        status: pass
    human_judgment: false
  - id: D4
    description: "Browser controls wait for exact acknowledgement, group accepted completions, recompute reopen destinations, and restore focus deterministically."
    requirement: WEB-01
    verification:
      - kind: automated_ui
        ref: "apps/web/src/features/tasks/lifecycle.test.tsx"
        status: pass
    human_judgment: false
  - id: D5
    description: "Pending, authentication, conflict, unknown-delivery, and terminal error states remain distinct and keyboard-accessible with reduced-motion-safe presentation."
    requirement: WEB-02
    verification:
      - kind: automated_ui
        ref: "apps/web/src/features/tasks/lifecycle.test.tsx#shows an honest recovery state"
        status: pass
    human_judgment: false

duration: 18min
completed: 2026-08-31
status: complete
---

# Phase KPL-01 Plan 14: Trustworthy Complete and Reopen Summary

**Revision-aware complete/reopen commands with exact durable receipts, accepted activity facts, and acknowledgement-gated accessible list reconciliation**

## Performance

- **Duration:** 18 min
- **Started:** 2026-08-31T05:52:17Z
- **Completed:** 2026-08-31T06:10:21Z
- **Tasks:** 2
- **Files modified:** 14

## Accomplishments

- Added pure complete/reopen lifecycle decisions that distinguish replay, already-satisfied intent, unrelated-edit rebase, and newer opposing lifecycle intent without conflating general task revision drift.
- Carried both commands through the common account-scoped PostgreSQL transaction, durable receipts, accepted activity facts, projection revision advancement, Phoenix closed decoding, OpenAPI, generated TypeScript, and storage-neutral vectors.
- Preserved Inbox state on completion while excluding completed tasks from active Inbox and project counts; reopen recomputes Inbox, Today, and Upcoming visibility from canonical preserved fields.
- Added routed complete/reopen controls that retain rows and the exact mutation identity until acknowledgement, display honest distinct recovery states, group newly completed work under Completed today, refresh reopen destinations authoritatively, and restore focus deterministically.
- Proved the slice with dedicated GTD-05 server/vector/browser suites plus full server, browser, static, Phase 1, repository-integrity, production-build, and real-stack Chromium lanes.

## Task Commits

Each planned TDD task has an explicit RED commit followed by its GREEN commit:

1. **Task 1 RED: Add failing task lifecycle proof** - `4fac765` (test)
2. **Task 1 GREEN: Execute exact task lifecycle transitions** - `5f70ae4` (feat)
3. **Task 2 RED: Add failing browser lifecycle proof** - `38831ba` (test)
4. **Task 2 GREEN: Compose acknowledged lifecycle controls** - `5f34ef7` (feat)

## Files Created/Modified

- `apps/server/lib/keepling/domain/task.ex` - Pure complete/reopen state machine, lifecycle revision, accepted timestamp, and exact activity deltas.
- `apps/server/lib/keepling/application/commands.ex` and `apps/server/lib/keepling/adapters/postgres/command_store.ex` - Shared semantic dispatch, locked account-scoped execution, exact receipts, projection revisions, and preserved Inbox truth.
- `apps/server/lib/keepling_web/controllers/command_controller.ex`, `apps/server/lib/keepling_web/router.ex`, `packages/contracts/openapi/keepling.yaml`, and `packages/contracts/generated/keepling.ts` - Closed authenticated lifecycle transport and checked-in DTO parity.
- `apps/server/test/keepling/application/task_lifecycle_test.exs` and `packages/contracts/vectors/lifecycle.json` - Independent GTD-05 state-machine, persistence, route, replay, activity, and projection proof.
- `apps/web/src/api/keepling.ts` and `apps/web/src/app/routes.tsx` - Generated lifecycle DTO mapping and authenticated routed controls.
- `apps/web/src/features/tasks/LifecycleActions.tsx` and `apps/web/src/features/lists/TaskList.tsx` - Exact-acknowledgement control state, honest recovery, Completed-today reconciliation, authoritative reopen refresh, and focus restoration.
- `apps/web/src/features/tasks/lifecycle.test.tsx` - Dedicated pending, identity, recovery, grouping, destination, and focus evidence.

## Decisions Made

- Tracked the latest accepted lifecycle revision separately from the task's general revision. This preserves optimistic concurrency for opposing complete/reopen intent while permitting the specified narrow rebase over unrelated edits.
- Kept `inbox_state` unchanged through completion. Active list queries filter on `completed_at`, so reopen can recover visibility without manufacturing or erasing organizational intent.
- Required both mutation and task identity to match before browser reconciliation. A missing or mismatched response remains unknown and reuses the exact original submission.
- Refetched Inbox, Today, and Upcoming after reopen. The browser announces only server-observed destinations and never duplicates domain membership rules.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Included completion in the organization-assignment snapshot loader**
- **Found during:** Task 1 full server verification
- **Issue:** The specialized assignment loader omitted `completed_at`, so its acknowledgement snapshot regressed after TaskSnapshot made completion explicit.
- **Fix:** Selected and mapped the lifecycle field through the specialized loader, preserving stable acknowledgement shape across every semantic command.
- **Files modified:** `apps/server/lib/keepling/adapters/postgres/command_store.ex`
- **Commit:** `5f70ae4`

**2. [Rule 2 - Missing Critical Functionality] Composed lifecycle controls in the shared list row**
- **Found during:** Task 2
- **Issue:** The four planned browser files had no existing injection seam into visible task rows; route-only composition could not make complete/reopen reachable while preserving Today ordering and shared list state.
- **Fix:** Added the lifecycle control and acknowledgement reconciliation to the existing shared `TaskList` row, then routed every authenticated list with its CSRF token.
- **Files modified:** `apps/web/src/features/lists/TaskList.tsx`, `apps/web/src/app/routes.tsx`
- **Commit:** `5f34ef7`

## Issues Encountered

- The first plan-level server proof used the general secret variable name. This repository's test runtime correctly rejected it and required `KEEPLING_TEST_SECRET_KEY_BASE`; the command was rerun with the correct disposable test-only variable and passed 4/4.

## TDD Gate Compliance

- Task 1 RED commit `4fac765` failed 4/4 cases because lifecycle state, commands, routes, snapshots, and persistence did not exist. GREEN commit `5f70ae4` made all 4 focused cases and the 70-test server suite pass.
- Task 2 RED commit `38831ba` failed because `LifecycleActions` did not exist. GREEN commit `5f34ef7` made all 8 dedicated browser cases and the 40-test browser suite pass.
- Both RED commits precede their matching GREEN commits. No separate refactor commit was necessary.

## Known Stubs

None - no TODO, FIXME, skipped test, placeholder production behavior, mock production data source, hardcoded empty rendered data, or unrun verification remains in the 14 realized files.

## Threat Surface

- T-KPL01-29 is mitigated by account-scoped task locks, expected task revisions, a lifecycle-specific accepted revision, narrow unrelated-edit rebase, durable `completed_at` conflicts, and cross-account/structural failure tests.
- T-KPL01-30 is mitigated by fixed mutation identity, fingerprinted durable receipts, one accepted activity fact per transition, exact replay, task-plus-mutation acknowledgement matching, and byte-equivalent ambiguous-delivery retry.
- No high-severity mitigation remains open, and no security-relevant surface outside the plan threat model was introduced.

## Verification Evidence

- Focused lifecycle ExUnit suite: 4/4 passed through runtime preflight against disposable PostgreSQL 18.6.
- `pnpm contracts:check`: OpenAPI and checked-in generated TypeScript agree; lifecycle vectors are covered by the dedicated server suite.
- Focused lifecycle browser suite: 8/8 passed, including exact acknowledgement, stable unknown retry, distinct recovery, Completed-today movement, authoritative reopen destinations, and focus fallback.
- Full `mix test`: 70/70 server tests passed.
- Full web Vitest suite: 6 files and 40/40 tests passed.
- Web typecheck, ESLint, and production Vite build passed; Vite transformed 62 modules.
- `pnpm test:phase-1`: repository integrity, runtime preflight, warnings-as-errors compilation, contract drift, browser unit suite, and real-stack discovery passed.
- `pnpm --filter @keepling/web test:e2e`: 3/3 real PostgreSQL/Phoenix/Chromium tests passed.

## User Setup Required

None. No dependency, external credential, service, manual migration, or environment change was added.

## Next Phase Readiness

- Plan 01-15 can add Trash as its distinct lifecycle slice without overloading complete/reopen classifications or browser recovery copy.
- Offline clients can model complete/reopen as exact semantic commands with stable identity, expected revision, durable terminal receipts, and server-authoritative projection reconciliation.
- No high-severity mitigation assigned to Plan 01-14 remains open.

## Self-Check: PASSED

- All 14 realized domain, adapter, transport, contract, vector, facade, routing, list, control, and test files exist on disk.
- Commits `4fac765`, `5f70ae4`, `38831ba`, and `5f34ef7` exist in Git history in the documented RED/GREEN order.
- Required actuals, requirements, deviation records, TDD gates, stub scan, threat mitigations, and fresh cross-boundary verification are present.

---
*Phase: KPL-01-one-trustworthy-task*
*Completed: 2026-08-31*
