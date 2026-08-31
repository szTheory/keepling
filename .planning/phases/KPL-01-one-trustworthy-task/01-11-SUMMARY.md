---
phase: KPL-01-one-trustworthy-task
plan: 11
subsystem: canonical-task-activity
tags: [elixir, phoenix, postgresql, hmac-cursor, openapi, react, typescript, accessibility]

requires:
  - phase: KPL-01-10
    provides: Stable account-scoped task, project, and tag identities with accepted semantic command receipts
provides:
  - Atomic versioned activity facts for every accepted task command with exact closed deltas
  - Account-scoped newest-first task activity API with bounded stale-aware HMAC keyset pagination
  - Generated contract boundary and safe routed browser history with exact account-timezone presentation
affects: [KPL-01-12, KPL-01-16, KPL-01-17, sync, mcp, task-export, recovery]

actuals:
  tokens: 21671
  tasks: 2
  commits: 4

tech-stack:
  added: []
  patterns: [atomic canonical activity facts, activity-view revision cursors, closed typed deltas, disclosure-gated technical identifiers]

key-files:
  created:
    - apps/server/lib/keepling/application/activity.ex
    - apps/server/lib/keepling_web/controllers/activity_controller.ex
    - apps/server/priv/repo/migrations/20260830000500_expand_task_activity.exs
    - apps/server/test/keepling/application/activity_test.exs
    - packages/contracts/vectors/activity.json
    - apps/web/src/features/activity/ActivityList.tsx
    - apps/web/src/features/activity/activity-list.test.tsx
  modified:
    - apps/server/lib/keepling/adapters/postgres/command_store.ex
    - apps/server/lib/keepling_web/router.ex
    - packages/contracts/openapi/keepling.yaml
    - packages/contracts/generated/keepling.ts
    - apps/web/src/api/keepling.ts
    - apps/web/src/app/routes.tsx

key-decisions:
  - "Accepted task activity is canonical account-lifetime user data committed in the same PostgreSQL transaction as task state, receipts, and undo metadata, while remaining a separate representation from each."
  - "Activity pagination uses a bounded newest-first keyset cursor whose HMAC binds account, task, acceptance time, activity ID, and activity-view revision; any projected-history change produces an explicit stale result."
  - "Organization deltas retain stable IDs but hydrate current labels and archive state at read time, so organization presentation changes advance the account activity-view revision without rewriting activity facts."
  - "The browser maps generated wire DTOs into a closed view model, renders all content as React text, and keeps revision and mutation identities inside native technical disclosures."

patterns-established:
  - "Canonical audit data: append one closed activity envelope per accepted semantic command inside the existing transaction, never derive user history from diagnostic logs or receipts."
  - "Snapshot-consistent history pagination: lock the account view revision for the page and bind every continuation cursor to the complete unique keyset and scope."
  - "Safe history UI: native list/time/details semantics, exact account-zone timestamps, explicit Load earlier focus transfer, and no opaque capability serialization."

requirements-completed: [SRV-02, SRV-03, WEB-02, QUAL-01]

coverage:
  - id: D1
    description: "Every accepted task command appends one exact closed canonical activity fact atomically with task state, receipt, and recovery metadata; authentication failures append none."
    requirement: SRV-02
    verification:
      - kind: integration
        ref: "apps/server/test/keepling/application/activity_test.exs#accepted facts are newest-first, exact, closed, bounded, and paginated"
        status: pass
      - kind: integration
        ref: "apps/server/test/keepling/application/activity_test.exs#authentication failures are not task history"
        status: pass
    human_judgment: false
  - id: D2
    description: "Task activity reads are account-scoped, newest-first, bounded, and continued only by an opaque HMAC cursor tied to the complete keyset and current activity view."
    requirement: SRV-03
    verification:
      - kind: integration
        ref: "apps/server/test/keepling/application/activity_test.exs#cursor changes are explicit and task/account scope never leaks"
        status: pass
      - kind: unit
        ref: "apps/server/test/keepling/application/activity_test.exs#activity cursors bind the full keyset, account, task, and view revision"
        status: pass
    human_judgment: false
  - id: D3
    description: "Phoenix, OpenAPI, checked-in TypeScript, and storage-neutral vectors expose the same closed activity vocabulary without undo handles or client-asserted actors."
    requirement: QUAL-01
    verification:
      - kind: integration
        ref: "pnpm contracts:check and packages/contracts/vectors/activity.json validation"
        status: pass
      - kind: unit
        ref: "apps/server/test/keepling/application/activity_test.exs#storage-neutral vectors and the application contract share one closed vocabulary"
        status: pass
    human_judgment: false
  - id: D4
    description: "The canonical task route renders hostile activity content as safe compact text with exact account-zone time, collapsed long changes, technical disclosures, explicit states, and accessible pagination focus."
    requirement: WEB-02
    verification:
      - kind: automated_ui
        ref: "apps/web/src/features/activity/activity-list.test.tsx"
        status: pass
      - kind: e2e
        ref: "pnpm --filter @keepling/web test:e2e"
        status: pass
      - kind: other
        ref: "web lint, typecheck, and production build"
        status: pass
    human_judgment: false

duration: 21min
completed: 2026-08-31
status: complete
---

# Phase KPL-01 Plan 11: Canonical Accepted Task Activity Summary

**Atomic versioned task activity with exact typed deltas, account-bound stale-aware pagination, generated contracts, and a safe accessible browser history**

## Performance

- **Duration:** 21 min
- **Started:** 2026-08-31T04:29:02Z
- **Completed:** 2026-08-31T04:50:16Z
- **Tasks:** 2
- **Files modified:** 13

## Accomplishments

- Expanded canonical task activity into a closed versioned envelope covering capture, detail updates, planning, Inbox transitions, completion, Trash, restore, and undo, with exact old/new values, server-derived actor/client fields, recovery state, and revision linkage appended in the accepted-command transaction.
- Added a reversible PostgreSQL schema and application query boundary for account-lifetime history, newest-first stable ordering, account/task isolation, a maximum page size of 50, stable organization-reference hydration, and opaque HMAC cursors invalidated by the relevant activity view revision.
- Added the authenticated Phoenix route, closed error mapping, OpenAPI schemas, checked-in generated TypeScript, and storage-neutral vectors without serializing opaque undo handles or permitting caller-provided actor labels.
- Added a canonical routed React history using native `ul`/`li`/`time`/`details`, exact account-timezone display, safe hostile-content rendering, archived organization labels, compact collapsed text changes, technical-only identifiers with Copy controls, explicit loading/empty/error/stale states, and focused explicit pagination.
- Proved the complete boundary with 54 server tests, reversible PostgreSQL 18.6 migration, contract drift and vector checks, 22 browser component tests, lint, typecheck, production build, repository integrity, and the existing 3-test real-stack Chromium suite.

## Task Commits

Each TDD task was committed with explicit RED and GREEN gates:

1. **Task 1 RED: Add failing canonical activity boundary proof** - `e05810a` (test)
2. **Task 1 GREEN: Finalize atomic activity facts and paginated API** - `7ae7c4f` (feat)
3. **Task 2 RED: Add failing routed activity UI proof** - `b11262e` (test)
4. **Task 2 GREEN: Route and render safe task activity** - `f0d1136` (feat)

## Files Created/Modified

- `apps/server/lib/keepling/application/activity.ex` - Closed activity vocabulary, cursor signing/verification, page contract, and problem results independent of Phoenix and storage.
- `apps/server/lib/keepling/adapters/postgres/command_store.ex` - Atomic accepted-fact insertion, view-revision advancement, bounded account-scoped keyset reads, and projected organization labels.
- `apps/server/lib/keepling_web/controllers/activity_controller.ex` and `apps/server/lib/keepling_web/router.ex` - Authenticated task activity endpoint with closed limit, cursor, stale, not-found, and authorization mapping.
- `apps/server/priv/repo/migrations/20260830000500_expand_task_activity.exs` - Reversible closed activity constraints, actor/recovery/undo linkage, and descending keyset index.
- `packages/contracts/openapi/keepling.yaml`, `packages/contracts/generated/keepling.ts`, and `packages/contracts/vectors/activity.json` - Shared wire vocabulary and storage-neutral accepted-history examples.
- `apps/web/src/api/keepling.ts` - Generated-wire-to-browser activity facade with opaque cursor forwarding and closed typed deltas.
- `apps/web/src/features/activity/ActivityList.tsx` and `apps/web/src/app/routes.tsx` - Safe activity rendering inside the canonical independently scrolling task detail surface.
- Focused ExUnit and Testing Library suites - Atomicity, closure, scope, ordering, bounds, cursor tampering/staleness, organization projection, authentication exclusion, hostile text, exact time, state, pagination focus, and route reachability evidence.

## Decisions Made

- Kept activity as canonical user data but not as the domain source of truth. Commands still decide against task snapshots; accepted activity records the exact resulting semantic fact for inspection, recovery, export, and later MCP compatibility.
- Derived the cursor key from the existing endpoint secret without introducing another runtime secret. The application boundary uses only standard-library crypto and constant-time signature comparison, preserving inward dependency direction.
- Bound cursors to the account activity-view revision rather than only the task revision because projected organization labels and archive state can change what an unchanged activity row renders.
- Mapped generated wire DTOs into a separate browser view representation before rendering. This keeps transport naming and nullable wire concerns out of presentation logic and preserves untrusted values as React text nodes.

## Deviations from Plan

None - plan executed exactly as written. Correctness work for organization-projection cursor invalidation and the shared detail-pane scroll boundary was required by D-59/D-60 and the plan's cursor/UI contracts, not added scope.

## Issues Encountered

- The browser RED proof initially used exact text-node queries for sentences split around an emphasized actor label. The GREEN proof now asserts the composed paragraph and opens native disclosures before checking interactive contents.
- Final server verification first established that the repository intentionally requires an explicit test database URL, test signing secret, and pinned runtime wrapper. The successful run used a disposable PostgreSQL 18.6 cluster, a generated throwaway test secret, explicit `MIX_ENV=test`, and removed the cluster afterward without touching project or user data.

## TDD Gate Compliance

- Task 1 RED commit `e05810a` failed because the canonical activity application contract, expanded persistence, paginated route, generated wire schema, and vector did not exist; GREEN commit `7ae7c4f` made the complete server/contract boundary pass.
- Task 2 RED commit `b11262e` failed because the activity component and route composition did not exist; GREEN commit `f0d1136` made hostile text, exact timezone, disclosure, state, pagination-focus, and route proof pass.
- No separate refactor commit was necessary. Both RED commits precede their matching GREEN commits in Git history.

## Known Stubs

None - no TODO, FIXME, placeholder implementation, skipped test, mock production data source, or hardcoded empty rendered activity source remains in the 13 changed files. Empty arrays/maps are typed accumulators, exact zero-result states, or test inputs rather than production stubs.

## Threat Surface

- T-KPL01-23 is mitigated by closed versioned delta DTOs, database constraints, wire vocabulary checks, React text-node rendering, collapsed untrusted text disclosures, and hostile script/image-content tests.
- T-KPL01-24 is mitigated by authenticated account/task predicates, account-bound cursor signatures, non-enumerating scope behavior, server-derived actor data, technical-only identifier disclosures, and the explicit absence of opaque undo handles.
- No security-relevant endpoint, authentication path, file access pattern, or trust-boundary schema outside the plan threat model was introduced.

## Verification Evidence

- Disposable PostgreSQL 18.6 migration `20260830000500` up, down one step, then up: passed.
- `mix format --check-formatted`, `MIX_ENV=test mix compile --warnings-as-errors`, and `MIX_ENV=test mix test`: 54/54 server tests passed through the pinned runtime preflight.
- `pnpm contracts:check` and `jq empty packages/contracts/vectors/activity.json`: OpenAPI/generated TypeScript drift and vector syntax checks passed.
- `pnpm --filter @keepling/web test`: 4 files and 22/22 browser component tests passed, including all 4 focused activity cases.
- `pnpm --filter @keepling/web lint`, `typecheck`, and `build`: passed; Vite transformed 60 modules.
- `tooling/check-repository-integrity.sh`: passed with no nested repository or planning root.
- `pnpm --filter @keepling/web test:e2e`: 3/3 real PostgreSQL/Phoenix/Chromium tests passed.

## User Setup Required

None. No dependency, credential, external service, or manual data migration was added.

## Next Phase Readiness

- Plan 01-12 can add planned/deadline transitions to the existing closed activity envelope and browser renderer without changing the cursor or ownership model.
- Later sync, MCP, export, and recovery work can reuse canonical accepted facts while keeping receipts, conflicts, security audit, and telemetry separate.
- No high-severity mitigation assigned to Plan 01-11 remains open.

## Self-Check: PASSED

- All seven created implementation, migration, vector, and test artifacts plus the canonical summary exist on disk.
- TDD commits `e05810a`, `7ae7c4f`, `b11262e`, and `f0d1136` exist in Git history in RED/GREEN order.
- Coverage metadata parsed without errors and classified all four deliverables as fully automated with passing evidence.
- Required actuals, requirements, stub scan, threat mitigations, migration reversal, privacy boundaries, and fresh cross-boundary verification are present.

---
*Phase: KPL-01-one-trustworthy-task*
*Completed: 2026-08-31*
