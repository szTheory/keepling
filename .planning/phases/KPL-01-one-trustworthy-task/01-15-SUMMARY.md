---
phase: KPL-01-one-trustworthy-task
plan: 15
subsystem: task-recovery
tags: [elixir, phoenix, postgresql, openapi, react, accessibility, idempotency, trash]

requires:
  - phase: KPL-01-14
    provides: Revision-aware lifecycle commands, durable receipts/activity, active/Completed projections, and acknowledged browser reconciliation
provides:
  - Exact-revision durable Trash and restore transitions with stable identity and canonical field/history preservation
  - Account-scoped newest-first Trash query, retained ordering, exact receipts, accepted activity, and authoritative restore destinations
  - Authenticated accessible Trash route with acknowledgement-gated restore, honest recovery states, live announcements, and deterministic focus
affects: [KPL-01-16, KPL-01-17, sync, mcp, desktop-offline, iphone-offline, undo]

actuals:
  tokens: 20005
  tasks: 2
  commits: 4

tech-stack:
  added: []
  patterns: [durable recoverable state, exact-revision semantic transition, authoritative destination acknowledgement, acknowledgement-gated row removal]

key-files:
  created:
    - apps/server/priv/repo/migrations/20260830000700_add_trash_state.exs
    - apps/server/test/keepling/application/trash_restore_test.exs
    - packages/contracts/vectors/trash-restore.json
    - apps/web/src/features/lists/TrashList.tsx
    - apps/web/src/features/lists/trash-list.test.tsx
  modified:
    - apps/server/lib/keepling/domain/task.ex
    - apps/server/lib/keepling/application/commands.ex
    - apps/server/lib/keepling/adapters/postgres/command_store.ex
    - apps/server/lib/keepling/adapters/postgres/task_views.ex
    - apps/server/lib/keepling_web/controllers/command_controller.ex
    - apps/server/lib/keepling_web/router.ex
    - packages/contracts/openapi/keepling.yaml
    - packages/contracts/generated/keepling.ts
    - apps/web/src/api/keepling.ts
    - apps/web/src/app/routes.tsx

key-decisions:
  - "Trash is a nullable accepted UTC instant on the retained canonical task row; accepted Trash time is immutable across already-satisfied retries, and no purge or retention mechanism exists."
  - "Trash and restore compare the expected revision to the exact current task revision before evaluating already-satisfied intent; every other task write conflicts while the task is trashed."
  - "Restore acknowledgements carry server-derived projection destinations, so the browser never predicts visibility from preserved but possibly inactive Inbox, date, or completion fields."

patterns-established:
  - "Recoverable lifecycle truth: hide a retained row from active projections, preserve organization/date/completion/order data, and restore visibility from canonical state without manufacturing intent."
  - "Trash UI truth: retain the row and exact submission through pending, auth, conflict, generic, and unknown states; remove and focus only after task-plus-mutation acknowledgement matches."

requirements-completed: [GTD-06, SRV-02, SRV-03, WEB-02]

coverage:
  - id: D1
    description: "Trash and restore are exact-revision, idempotent semantic transitions that retain the canonical task row and never hard-delete or expire it."
    requirement: GTD-06
    verification:
      - kind: integration
        ref: "apps/server/test/keepling/application/trash_restore_test.exs"
        status: pass
      - kind: other
        ref: "packages/contracts/vectors/trash-restore.json"
        status: pass
    human_judgment: false
  - id: D2
    description: "Canonical fields, assignments, completion, accepted activity, Today order, stable identity, receipts, and active-list exclusion survive Trash and restore."
    requirement: SRV-02
    verification:
      - kind: integration
        ref: "apps/server/test/keepling/application/trash_restore_test.exs#trash and restore preserve canonical state, activity, assignments, completion, and order"
        status: pass
    human_judgment: false
  - id: D3
    description: "Authenticated account-scoped closed routes and generated contracts expose Trash without cross-account task or receipt disclosure."
    requirement: SRV-03
    verification:
      - kind: integration
        ref: "apps/server/test/keepling/application/trash_restore_test.exs#authenticated Trash routes retain the row until restore acknowledgement"
        status: pass
      - kind: other
        ref: "pnpm contracts:check"
        status: pass
    human_judgment: false
  - id: D4
    description: "The browser Trash route has honest loading/empty/error/recovery states and removes a row, announces destinations, and restores focus only after exact acknowledgement."
    requirement: WEB-02
    verification:
      - kind: automated_ui
        ref: "apps/web/src/features/lists/trash-list.test.tsx"
        status: pass
    human_judgment: false

duration: 18min
completed: 2026-08-31
status: complete
---

# Phase KPL-01 Plan 15: Durable Trash and Restore Summary

**Exact-revision recoverable Trash state with retained PostgreSQL truth, durable receipts/activity, authoritative restore destinations, and acknowledgement-gated accessible browser recovery**

## Performance

- **Duration:** 18 min
- **Started:** 2026-08-31T06:16:33Z
- **Completed:** 2026-08-31T06:34:52Z
- **Tasks:** 2
- **Files modified:** 15

## Accomplishments

- Added pure Trash/restore decisions that demand the exact current revision, preserve stable identity and every non-Trash task field, return stable replay/already-satisfied/conflict results, and never create a hard-delete or retention path.
- Carried both transitions through the common account-scoped PostgreSQL transaction with one retained task row, accepted activity facts, exact terminal receipts, projection revisions, closed Phoenix decoding, OpenAPI, generated TypeScript, and independent storage-neutral vectors.
- Excluded trashed tasks from Inbox, Today, Upcoming, Completed, and active-project counts without erasing Inbox, date, completion, organization, history, or Today-order truth; restore derives and returns actual current destinations.
- Added an authenticated `/trash` browser route that renders explicit loading/empty/error states, retains rows and fixed mutation identities through uncertainty, removes only after matching acknowledgement, announces destinations, and restores focus next/previous/heading.
- Proved the slice with dedicated GTD-06 server/vector/browser suites plus full server, browser, contract, static, production-build, Phase 1, repository-integrity, and real-stack Chromium lanes.

## Task Commits

Each planned TDD task has an explicit RED commit followed by its GREEN commit:

1. **Task 1 RED: Add failing Trash/restore preservation proof** - `934e9c0` (test)
2. **Task 1 GREEN: Persist exact Trash/restore transitions** - `9585d9f` (feat)
3. **Task 2 RED: Add failing browser Trash proof** - `432e94f` (test)
4. **Task 2 GREEN: Route acknowledged Trash restore** - `bd9e881` (feat)

## Files Created/Modified

- `apps/server/lib/keepling/domain/task.ex` - Pure exact-revision Trash/restore state machine and closed accepted activity deltas.
- `apps/server/lib/keepling/application/commands.ex` and `apps/server/lib/keepling/adapters/postgres/command_store.ex` - Shared dispatch, retained canonical persistence, account scope, terminal receipts, activity, projection bumps, and authoritative destinations.
- `apps/server/lib/keepling/adapters/postgres/task_views.ex` - Active projection predicates that exclude Trash while leaving preserved state and ordering intact.
- `apps/server/lib/keepling_web/controllers/command_controller.ex`, `apps/server/lib/keepling_web/router.ex`, `packages/contracts/openapi/keepling.yaml`, and `packages/contracts/generated/keepling.ts` - Authenticated closed Trash transport and checked-in DTO parity.
- `apps/server/priv/repo/migrations/20260830000700_add_trash_state.exs`, `apps/server/test/keepling/application/trash_restore_test.exs`, and `packages/contracts/vectors/trash-restore.json` - Expand-only canonical state plus dedicated preservation, route, account-scope, ordering, migration, replay, and no-hard-delete proof.
- `apps/web/src/api/keepling.ts`, `apps/web/src/app/routes.tsx`, and `apps/web/src/features/lists/TrashList.tsx` - Generated-contract facade, authenticated route, honest restore orchestration, accessible copy, live region, and deterministic focus.
- `apps/web/src/features/lists/trash-list.test.tsx` - Dedicated loading, empty, routing, pending, identity, recovery, destination, row-removal, and focus evidence.

## Decisions Made

- Stored `trashed_at` on the existing task row rather than introducing a separate Trash store or deleting data. This makes recoverability canonical and preserves all foreign-key-linked history and organization/order records.
- Checked exact revision before already-satisfied intent. A stale new command cannot silently succeed merely because another Trash/restore already reached the requested state; only the exact current revision may return no change.
- Treated preserved completion as authoritative during restore. A completed task with preserved Inbox/date fields returns to Completed only; the server returns projection destinations and the client announces exactly those values.
- Reused the command receipt and activity kernel. Trash/restore do not receive a specialized persistence bypass, so later API/MCP/native clients inherit the same invariant and replay behavior.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical Functionality] Excluded Trash in the shared task-view projection adapter**
- **Found during:** Task 1 (Persist exact Trash/restore semantics)
- **Issue:** The plan's explicit file list omitted `task_views.ex`, but Inbox/Today/Upcoming/Completed are owned there. Without updating those predicates, a trashed row could remain visible in active projections, violating D-15 and the recoverability claim.
- **Fix:** Added `trashed_at IS NULL` to every active/completed projection and Today ordering eligibility path while retaining the order rows themselves.
- **Files modified:** `apps/server/lib/keepling/adapters/postgres/task_views.ex`
- **Verification:** Dedicated preservation tests, 75/75 full server tests, and real-stack lanes passed.
- **Committed in:** `9585d9f`

**2. [Rule 1 - Bug] Preserved the original accepted Trash timestamp on already-satisfied commands**
- **Found during:** Task 1 focused GREEN run
- **Issue:** The first implementation compared `trashed_at` to the new command's acceptance time, which would rewrite the accepted Trash instant instead of returning `already_satisfied` at the exact current revision.
- **Fix:** Split operation intent from the timestamp value: exact-revision Trash on an already-trashed task now returns the unchanged task and original instant.
- **Files modified:** `apps/server/lib/keepling/domain/task.ex`
- **Verification:** Focused storage-neutral vector suite passed 5/5.
- **Committed in:** `9585d9f`

**3. [Rule 1 - Bug] Passed the explicit POST method through the restore facade**
- **Found during:** Task 2 focused GREEN run
- **Issue:** The first facade call shifted the command and CSRF arguments because the `POST` method parameter was omitted, classifying every response as unknown.
- **Fix:** Supplied the closed method argument and reran exact-body retry, acknowledgement, removal, announcement, and focus tests.
- **Files modified:** `apps/web/src/api/keepling.ts`
- **Verification:** Dedicated browser suite passed 8/8; typecheck and lint passed.
- **Committed in:** `bd9e881`

---

**Total deviations:** 3 auto-fixed (2 Rule 1 bugs, 1 Rule 2 missing critical functionality)
**Impact on plan:** Every change was required for truthful recoverability or correct boundary wiring; no unrelated feature scope or dependency was added.

## Issues Encountered

- The first server RED command reached the repository's intentional runtime guard without `KEEPLING_TEST_DATABASE_URL`. A disposable PostgreSQL 18.6 database and test-only secret were supplied, after which the suite reached the intended 0/5 missing-implementation RED state.
- The RED persistence fixture initially attempted a second singleton account and duplicate organization names. Those fixture errors were corrected before implementation so failures represented missing Trash behavior rather than invalid seed data.
- The initial preservation expectation predicted Inbox/Today/Completed simultaneously for a previously completed task. It was corrected before GREEN work: preserved completion truth means its actual restored destination is Completed only.

## TDD Gate Compliance

- Task 1 RED commit `934e9c0` reached 0/5 with missing canonical column, domain transitions, application query/dispatch, and Phoenix routes. GREEN commit `9585d9f` made 5/5 dedicated cases and the 75-test server suite pass.
- Task 2 RED commit `432e94f` failed because `TrashList` did not exist. GREEN commit `bd9e881` made 8/8 dedicated browser cases and the 48-test full browser suite pass.
- Both RED commits precede their matching GREEN commits. No separate refactor commit was necessary.

## Known Stubs

None - no TODO, FIXME, skipped test, placeholder production behavior, mock production data source, hardcoded empty rendered data, or unrun verification remains in the 15 realized files.

## Threat Surface

- T-KPL01-31 is mitigated by exact current revision, account-scoped row locks and receipts, retained canonical rows, stable replay, immutable accepted Trash time, and explicit stale/cross-account tests.
- T-KPL01-32 is mitigated by authenticated routing and an account predicate on Trash task, activity, and receipt reads; opaque task and mutation identities never authorize access.
- The new HTTP routes and schema columns are the planned threat surface. No additional network, authentication, file-access, or trust-boundary surface outside the plan threat model was introduced, and no high-severity mitigation remains open.

## Verification Evidence

- Focused Trash/restore ExUnit suite: 5/5 passed against disposable PostgreSQL 18.6.
- `pnpm contracts:check`: OpenAPI and checked-in generated TypeScript agree; storage-neutral Trash vectors are covered by the dedicated server suite.
- Focused Trash browser suite: 8/8 passed, including exact acknowledgement, pending retention, same-body unknown retry, auth/conflict/generic states, server destinations, route retention, and focus fallback.
- Full `mix test`: 75/75 server tests passed after warnings-as-errors compilation.
- Full web Vitest suite: 7 files and 48/48 tests passed.
- Web typecheck, ESLint, and production Vite build passed; Vite transformed 63 modules.
- `pnpm test:phase-1`: repository integrity, runtime preflight, warnings-as-errors compilation, contract drift, browser unit suite, and real-stack discovery passed.
- `pnpm --filter @keepling/web test:e2e`: 3/3 real PostgreSQL/Phoenix/Chromium tests passed.

## User Setup Required

None. No dependency, external credential, service, operator migration step, or environment change was added.

## Next Phase Readiness

- Plan 01-16 can add bounded undo over Trash/restore using the same exact revision, retained task row, activity fact, receipt, and destination semantics.
- Later offline and MCP adapters can send the checked-in version 1 semantic commands without copying deletion, projection, or recovery rules.
- No high-severity mitigation assigned to Plan 01-15 remains open.

## Self-Check: PASSED

- All 15 realized domain, application, PostgreSQL, transport, migration, contract, vector, facade, routing, component, and test files exist on disk.
- Commits `934e9c0`, `9585d9f`, `432e94f`, and `bd9e881` exist in Git history in the documented RED/GREEN order.
- Required actuals, requirements, coverage metadata, deviation records, TDD gates, stub scan, threat mitigations, and fresh cross-boundary verification are present.

---
*Phase: KPL-01-one-trustworthy-task*
*Completed: 2026-08-31*
